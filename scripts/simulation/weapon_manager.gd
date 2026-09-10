class_name WeaponManager
extends Node
## Owns weapons in flight, resolves salvos, seeker acquisition, hits and damage.
## Reads Tracks for aim points and Units only for terminal acquisition and impact.

signal weapon_launched(shooter: Unit, spec: WeaponSpec, track: Track, rounds: int)
signal weapon_impact(faction: String, spec: WeaponSpec, target: Unit, hit: bool)
signal unit_destroyed(unit: Unit, killer_faction: String)
signal engagement_rejected(shooter: Unit, spec: WeaponSpec, reason: String)
signal interceptor_launched(shooter: Unit, spec: WeaponSpec, threat: Weapon, rounds: int)
signal weapon_defeated(threat: Weapon, reason: String, by_unit: Unit)

const IMPACT_MIN_NM := 0.05

var unit_manager: UnitManager
var track_manager: TrackManager
var rng := RandomNumberGenerator.new()
var in_flight: Array[Weapon] = []

var _next_id := 1
var _pending: Array = []  # queued salvo rounds: {shooter, spec, track, time}


func launch(shooter: Unit, spec: WeaponSpec, track: Track, salvo: int, now: float) -> bool:
	var check := Combat.check_engagement(shooter, spec, track)
	if not check["ok"]:
		engagement_rejected.emit(shooter, spec, check["reason"])
		return false
	var rounds := clampi(salvo, 1, shooter.magazine_count(spec.id))
	shooter.consume_magazine(spec.id, rounds)
	for i in rounds:
		if i == 0:
			_fire_round(shooter, spec, track)
		else:
			_pending.append({"shooter": shooter, "spec": spec, "track": track, "time": now + spec.launch_interval_s * i})
	weapon_launched.emit(shooter, spec, track, rounds)
	return true


## Fires interceptors at a weapon already in flight. Used by the automatic air-defence system,
## never by a direct player order. Returns the number of rounds launched.
func launch_interceptor(shooter: Unit, spec: WeaponSpec, threat: Weapon, rounds: int, now: float) -> int:
	if not shooter.alive or threat.phase == Weapon.Phase.DEAD:
		return 0
	var available := mini(rounds, shooter.magazine_count(spec.id))
	if available <= 0:
		return 0
	shooter.consume_magazine(spec.id, available)
	for i in available:
		var w := Weapon.new()
		w.id = _next_id
		_next_id += 1
		w.spec = spec
		w.faction = shooter.faction
		w.shooter = shooter
		w.intercept_target = threat
		w.position = shooter.position
		w.heading_deg = Geo.bearing_deg(w.position, threat.position)
		w.aim_point = threat.position
		w.phase = Weapon.Phase.TERMINAL
		in_flight.append(w)
	if spec.type == "ciws":
		threat.close_in_bursts_committed += 1
	else:
		threat.guided_interceptors_committed += available
	interceptor_launched.emit(shooter, spec, threat, available)
	return available


## Marks an in-flight weapon as destroyed or decoyed before it reaches its target.
func defeat_weapon(threat: Weapon, reason: String, by_unit: Unit = null) -> void:
	if threat.phase == Weapon.Phase.DEAD:
		return
	threat.phase = Weapon.Phase.DEAD
	threat.dead_reason = reason
	weapon_defeated.emit(threat, reason, by_unit)


func tick(dt: float, now: float) -> void:
	for i in range(_pending.size() - 1, -1, -1):
		if now >= _pending[i]["time"]:
			var p: Dictionary = _pending[i]
			_pending.remove_at(i)
			if p["shooter"].alive:
				_fire_round(p["shooter"], p["spec"], p["track"])
	for i in range(in_flight.size() - 1, -1, -1):
		_step(in_flight[i], dt)
		if in_flight[i].phase == Weapon.Phase.DEAD:
			in_flight.remove_at(i)


func clear() -> void:
	in_flight.clear()
	_pending.clear()
	_next_id = 1


func _fire_round(shooter: Unit, spec: WeaponSpec, track: Track) -> void:
	var w := Weapon.new()
	w.id = _next_id
	_next_id += 1
	w.spec = spec
	w.faction = shooter.faction
	w.shooter = shooter
	w.target_track = track
	w.position = shooter.position
	w.aim_point = _aim_for(w)
	w.heading_deg = Geo.bearing_deg(w.position, w.aim_point)
	in_flight.append(w)


func _aim_for(w: Weapon) -> Vector2:
	var t := w.target_track
	if t == null:
		return w.aim_point
	return Combat.intercept_point(w.position, w.spec.speed_kn, t.position, t.course_deg, t.speed_kn, t.has_kinematics)


func _step(w: Weapon, dt: float) -> void:
	w.time_alive_s += dt
	if w.intercept_target != null:
		_step_interceptor(w, dt)
		return
	# Mid-course updates only while the track is still being observed.
	if w.phase == Weapon.Phase.CRUISE and w.target_track != null and w.target_track.status == Track.Status.ACTIVE:
		w.aim_point = _aim_for(w)

	var goal := w.aim_point
	if w.phase == Weapon.Phase.TERMINAL and w.acquired != null and w.acquired.alive:
		goal = w.acquired.position
	elif w.phase == Weapon.Phase.TERMINAL:
		w.phase = Weapon.Phase.DEAD
		w.dead_reason = "TARGET LOST"
		return

	var desired := Geo.bearing_deg(w.position, goal)
	var max_turn := w.spec.turn_rate_deg_s * dt
	w.heading_deg = fposmod(w.heading_deg + clampf(Geo.heading_delta(w.heading_deg, desired), -max_turn, max_turn), 360.0)

	var travel := w.speed_nm_per_s() * dt
	w.position += Geo.heading_to_vector(w.heading_deg) * travel
	w.distance_flown_nm += travel

	if w.distance_flown_nm >= w.spec.max_range_nm:
		w.phase = Weapon.Phase.DEAD
		w.dead_reason = "RANGE EXHAUSTED"
		return

	if w.phase == Weapon.Phase.CRUISE:
		if w.spec.is_torpedo():
			# A torpedo runs out before its seeker comes on, then searches the whole way in.
			# That is why a shot down a rough bearing is still worth taking.
			if w.distance_flown_nm >= w.spec.run_to_enable_nm:
				_try_acquire(w, travel)
			return
		if w.position.distance_to(w.aim_point) <= w.spec.acquisition_radius_nm():
			_try_acquire(w, travel)
		return

	var impact := maxf(IMPACT_MIN_NM, travel)
	if w.acquired != null and w.position.distance_to(w.acquired.position) <= impact:
		_resolve_impact(w)


func _step_interceptor(w: Weapon, dt: float) -> void:
	var threat := w.intercept_target
	if threat.phase == Weapon.Phase.DEAD:
		w.phase = Weapon.Phase.DEAD
		w.dead_reason = "THREAT ALREADY DEFEATED"
		return
	var desired := Geo.bearing_deg(w.position, threat.position)
	var max_turn := w.spec.turn_rate_deg_s * dt
	w.heading_deg = fposmod(w.heading_deg + clampf(Geo.heading_delta(w.heading_deg, desired), -max_turn, max_turn), 360.0)
	var travel := w.speed_nm_per_s() * dt
	w.position += Geo.heading_to_vector(w.heading_deg) * travel
	w.distance_flown_nm += travel
	if w.distance_flown_nm >= w.spec.max_range_nm:
		w.phase = Weapon.Phase.DEAD
		w.dead_reason = "RANGE EXHAUSTED"
		return
	var impact := maxf(IMPACT_MIN_NM, travel + threat.speed_nm_per_s() * dt)
	if w.position.distance_to(threat.position) > impact:
		return
	w.phase = Weapon.Phase.DEAD
	if rng.randf() < Combat.intercept_probability(w.spec, threat.spec):
		w.dead_reason = "INTERCEPT"
		defeat_weapon(threat, "INTERCEPTED", w.shooter)
	else:
		w.dead_reason = "INTERCEPT MISS"


func _try_acquire(w: Weapon, travel: float) -> void:
	var radius := w.spec.acquisition_radius_nm()
	var best: Unit = null
	var best_d := radius
	for u in unit_manager.units:
		if u.faction == w.faction or not can_target(w.spec, u):
			continue
		var d := w.position.distance_to(u.position)
		if d <= best_d:
			best = u
			best_d = d
	if best == null:
		if w.position.distance_to(w.aim_point) <= maxf(IMPACT_MIN_NM * 2.0, travel * 1.5):
			w.phase = Weapon.Phase.DEAD
			w.dead_reason = "NO ACQUISITION"
		return
	w.acquired = best
	w.phase = Weapon.Phase.TERMINAL


## A seeker only works in its own medium. An anti-ship missile cannot find a submerged boat, and
## a torpedo is no use against something that is not in the water.
static func can_target(spec: WeaponSpec, u: Unit) -> bool:
	if not u.is_engageable():
		return false
	if u.spec.domain == "land":
		return spec.target_types.has("land")
	if u.airborne():
		return spec.target_types.has("air")
	if u.submerged():
		return spec.target_types.has("subsurface")
	return spec.target_types.has("surface")


func _resolve_impact(w: Weapon) -> void:
	var target := w.acquired
	w.phase = Weapon.Phase.DEAD
	var pk := Combat.hit_probability(w.spec, target)
	var hit := rng.randf() < pk
	w.dead_reason = "HIT" if hit else "MISS"
	if hit:
		var destroyed := Damage.apply(target, w.spec.damage)
		weapon_impact.emit(w.faction, w.spec, target, true)
		if destroyed:
			unit_destroyed.emit(target, w.faction)
	else:
		weapon_impact.emit(w.faction, w.spec, target, false)
