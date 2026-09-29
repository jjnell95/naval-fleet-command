class_name WeaponManager
extends Node
## Owns weapons in flight, resolves salvos, seeker acquisition, hits and damage.
## Reads Tracks for aim points and Units only for terminal acquisition and impact.

signal round_fired(shooter: Unit, spec: WeaponSpec, track: Track)
signal weapon_launched(shooter: Unit, spec: WeaponSpec, track: Track, rounds: int)
signal weapon_impact(faction: String, spec: WeaponSpec, target: Unit, hit: bool)
signal unit_destroyed(unit: Unit, killer_faction: String)
signal engagement_rejected(shooter: Unit, spec: WeaponSpec, reason: String)
signal interceptor_launched(shooter: Unit, spec: WeaponSpec, threat: Weapon, rounds: int)
signal weapon_defeated(threat: Weapon, reason: String, by_unit: Unit)
## A round pulled off its target by decoys that found another ship in its seeker basket.
signal weapon_seduced(threat: Weapon, from_unit: Unit, to_unit: Unit)
## Expendable decoys used, chaff or acoustic, whether or not they worked. A towed decoy is not one.
signal decoys_spent(unit: Unit, count: int)

const IMPACT_MIN_NM := 0.05
## Decoys do not delete a missile; they move it. A seduced seeker flies on through the cloud and
## locks whatever else it finds ahead, which is why an escort's chaff is a hazard to the ship
## behind it. GAMEPLAY_ESTIMATE.
const SEDUCED_REACQUIRE_P := 0.5
const SEEKER_CONE_DEG := 35.0
const MAX_SEDUCTIONS := 2

var unit_manager: UnitManager
var track_manager: TrackManager
var rng := RandomNumberGenerator.new()
var in_flight: Array[Weapon] = []

var _next_id := 1
var _launcher_ready_at: Dictionary = {}  # shooter -> launcher group -> next launch time
var now_s := 0.0
var _pending: Array = []  # queued salvo rounds: {shooter, spec, track, time}


func launch(shooter: Unit, spec: WeaponSpec, track: Track, salvo: int, now: float) -> bool:
	now_s = now
	var check := engagement_check(shooter, spec, track, now)
	if not check["ok"]:
		engagement_rejected.emit(shooter, spec, check["reason"])
		return false
	var rounds := clampi(salvo, 1, shooter.magazine_count(spec.id))
	shooter.consume_magazine(spec.id, rounds)
	var launch_at := now + ready_in_s(shooter, spec, now)
	for i in rounds:
		if i == 0 and launch_at <= now:
			_fire_round(shooter, spec, track)
			_mark_launched(shooter, spec, now)
		else:
			_pending.append({"shooter": shooter, "spec": spec, "track": track, "time": launch_at})
		launch_at += maxf(spec.launch_interval_s, 0.25)
	weapon_launched.emit(shooter, spec, track, rounds)
	return true


## VLS fits share an abstract launch service. Other mounts/racks are independent by weapon
## family. Timing is gameplay tuning, not a real launcher throughput specification.
static func launcher_key(shooter: Unit, spec: WeaponSpec) -> String:
	return "VLS" if spec.vls_pack > 0 and shooter.spec.vls_cells > 0 else spec.id


func _ready_time(shooter: Unit, spec: WeaponSpec) -> float:
	return float(_launcher_ready_at.get(shooter, {}).get(launcher_key(shooter, spec), 0.0))


func _mark_launched(shooter: Unit, spec: WeaponSpec, now: float) -> void:
	var ready: Dictionary = _launcher_ready_at.get(shooter, {})
	ready[launcher_key(shooter, spec)] = now + maxf(spec.launch_interval_s, 0.25)
	_launcher_ready_at[shooter] = ready


func ready_in_s(shooter: Unit, spec: WeaponSpec, now: float) -> float:
	var at := maxf(now, _ready_time(shooter, spec))
	var queue: Array = _pending.filter(func(p: Dictionary) -> bool: return p.shooter == shooter and launcher_key(shooter, p.spec) == launcher_key(shooter, spec))
	queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.time) < float(b.time))
	for p: Dictionary in queue:
		at = maxf(at, float(p.time)) + maxf(p.spec.launch_interval_s, 0.25)
	return maxf(at - now, 0.0)



func committed_rounds(shooter: Unit, spec: WeaponSpec, track: Track = null, queued_only := false) -> int:
	var count := 0
	for p: Dictionary in _pending:
		if p.shooter == shooter and p.spec == spec and (track == null or p.track == track):
			count += 1
	if not queued_only:
		for w in in_flight:
			if w.shooter == shooter and (w.spec == spec or w.delivery_spec == spec) and w.phase != Weapon.Phase.DEAD and (track == null or w.target_track == track):
				count += 1
	return count


func engagement_check(shooter: Unit, spec: WeaponSpec, track: Track, now: float, reserved_round := false) -> Dictionary:
	var check := Combat.check_engagement(shooter, spec, track, reserved_round)
	if not check.ok:
		return check
	if not radar_support_available(shooter, spec):
		check.ok = false
		check.reason = "RADAR GUIDANCE UNAVAILABLE"
	elif not reserved_round and spec.requires_fire_control_channel() and track.domain == "air" and not channel_available(shooter, track):
		check.ok = false
		check.reason = "FIRE CONTROL SATURATED"
	if not reserved_round:
		check["ready_in_s"] = ready_in_s(shooter, spec, now)
	return check


## Unfired rounds stay aboard. A cancel, hold order or invalid solution refunds only reservations.
func cancel_salvo(shooter: Unit, track: Track = null) -> int:
	var count := 0
	for i in range(_pending.size() - 1, -1, -1):
		var p: Dictionary = _pending[i]
		if p.shooter == shooter and (track == null or p.track == track):
			_pending.remove_at(i)
			if shooter.alive:
				shooter.magazines[p.spec.id] = shooter.magazine_count(p.spec.id) + 1
			count += 1
	return count



## Fires interceptors at a weapon already in flight. Used by the automatic air-defence system,
## never by a direct player order. Returns the number of rounds launched.
func launch_interceptor(shooter: Unit, spec: WeaponSpec, threat: Weapon, rounds: int, now: float) -> int:
	if not shooter.alive or not shooter.can_fire() or shooter.roe == Unit.Roe.HOLD or threat.phase == Weapon.Phase.DEAD:
		return 0
	if not AirDefence._can_intercept(spec, threat):
		return 0
	if not interceptor_support_available(shooter, spec, threat):
		return 0
	now_s = now
	if now < _ready_time(shooter, spec):
		return 0
	var distance := shooter.position.distance_to(threat.position)
	if distance < spec.min_range_nm or distance > spec.max_range_nm:
		return 0
	if spec.requires_fire_control_channel() and not channel_available(shooter, threat):
		return 0
	# SAMs leave one at a time at the authored launch interval. A CIWS round count is a
	# short burst abstraction, so the whole burst is expended in one firing cycle.
	var available := mini(rounds, shooter.magazine_count(spec.id))
	if spec.type != "ciws":
		available = mini(available, 1)
	if available <= 0:
		return 0
	shooter.consume_magazine(spec.id, available)
	_mark_launched(shooter, spec, now)
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
		threat.close_in_commitments[shooter.id] = int(threat.close_in_commitments.get(shooter.id, 0)) + 1
	else:
		threat.guided_interceptors_committed += available
		var layer := spec.defensive_layer()
		threat.defence_commitments[layer] = int(threat.defence_commitments.get(layer, 0)) + available
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
	now_s = now
	_pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.time) < float(b.time))
	for p: Dictionary in _pending.duplicate():
		var check := engagement_check(p.shooter, p.spec, p.track, now, true)
		if not check.ok:
			_pending.erase(p)
			if p.shooter.alive:
				p.shooter.magazines[p.spec.id] = p.shooter.magazine_count(p.spec.id) + 1
			engagement_rejected.emit(p.shooter, p.spec, "QUEUED ROUND CANCELLED: " + str(check.reason))
		elif now >= float(p.time) and now >= _ready_time(p.shooter, p.spec):
			_pending.erase(p)
			_fire_round(p.shooter, p.spec, p.track)
			_mark_launched(p.shooter, p.spec, now)
	for i in range(in_flight.size() - 1, -1, -1):
		_step(in_flight[i], dt)
		if in_flight[i].phase == Weapon.Phase.DEAD:
			in_flight.remove_at(i)


func clear() -> void:
	in_flight.clear()
	_pending.clear()
	_launcher_ready_at.clear()
	now_s = 0.0
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
	w.launch_altitude_m = shooter.altitude_m if shooter.in_flight() else spec.altitude_m
	w.launched_ashore = shooter.spec.domain == "land"
	w.aim_point = _aim_for(w)
	w.launch_range_nm = w.position.distance_to(w.aim_point)
	w.heading_deg = Geo.bearing_deg(w.position, w.aim_point)
	in_flight.append(w)
	round_fired.emit(shooter, spec, track)


func _aim_for(w: Weapon) -> Vector2:
	var t := w.target_track
	if t == null:
		return w.aim_point
	var aim := Combat.intercept_point(w.position, w.spec.speed_kn, t.position, t.course_deg, t.speed_kn, t.has_kinematics)
	return aim if aim.is_finite() else t.position


func _step(w: Weapon, dt: float) -> void:
	# Interceptors are stepped before the rounds they chase, and a decoy can kill a round at the
	# end of a tick. A round already dead must not fly on and roll an impact of its own.
	if w.phase == Weapon.Phase.DEAD:
		return
	w.time_alive_s += dt
	if not radar_support_available(w.shooter, w.spec):
		w.phase = Weapon.Phase.DEAD
		w.dead_reason = "GUIDANCE LOST"
		return
	if w.intercept_target != null:
		_step_interceptor(w, dt)
		return
	if w.spec.delivery_payload_id != "":
		_step_delivery(w, dt)
		return
	# Mid-course updates only while the track is still being observed.
	if w.delivery_spec == null and w.phase == Weapon.Phase.CRUISE and w.target_track != null and w.target_track.status == Track.Status.ACTIVE and w.target_track.visible_to(w.shooter):
		w.aim_point = _aim_for(w)

	var goal := w.aim_point
	# The seeker loses a target that leaves its medium: a helicopter that lands on its deck, a
	# boat that dives under an anti-ship missile.
	if w.phase == Weapon.Phase.TERMINAL and w.acquired != null and w.acquired.alive and can_target(w.spec, w.acquired):
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

	if _hits_terrain(w, travel):
		w.phase = Weapon.Phase.DEAD
		w.dead_reason = "TERRAIN"
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


## Rocket-delivered ASW: fly to the held launch solution, then put a fresh torpedo into the
## water. The payload has its own speed, seeker and run distance, with no hidden target cue.
func _step_delivery(w: Weapon, dt: float) -> void:
	var travel := w.speed_nm_per_s() * dt
	var remaining := w.position.distance_to(w.aim_point)
	w.heading_deg = Geo.bearing_deg(w.position, w.aim_point)
	if remaining <= travel:
		w.position = w.aim_point
		if Terrain.is_land(w.position):
			w.phase = Weapon.Phase.DEAD
			w.dead_reason = "PAYLOAD LANDED ASHORE"
			return
		var payload := DataDB.weapon(w.spec.delivery_payload_id)
		if payload == null:
			w.phase = Weapon.Phase.DEAD
			w.dead_reason = "NO PAYLOAD"
			return
		w.delivery_spec = w.spec
		w.spec = payload
		w.distance_flown_nm = 0.0
		w.time_alive_s = 0.0
		w.aim_point = w.position + Geo.heading_to_vector(w.heading_deg) * payload.max_range_nm
	else:
		w.position = w.position.move_toward(w.aim_point, travel)
		w.distance_flown_nm += travel
		if w.distance_flown_nm >= w.spec.max_range_nm:
			w.phase = Weapon.Phase.DEAD
			w.dead_reason = "DELIVERY RANGE EXHAUSTED"


## A round that has to stay low ends against the first ground it meets: the sea-skimmer into the
## headland, the torpedo into the shoal. It is not a defensive success and is never credited as
## one, so it dies here rather than through defeat_weapon(). Interceptors are exempt — they are
## fired upward at something closing head-on and the engagement resolves within a mile or two.
func _hits_terrain(w: Weapon, travel: float) -> bool:
	if Terrain.is_empty() or not Combat.profile_is_surface_bound(w.spec):
		return false
	# A round going for something ashore has to cross the coast to get there: a cruise missile
	# follows the ground in, a gun round arcs over the beach. The land it is aimed at is the
	# target, not an obstacle.
	if _bound_for_land(w):
		return false
	# A battery's round starts on dry ground. It is exempt until it has cleared its own coast,
	# and an ordinary low flyer from then on.
	if w.launched_ashore:
		if Terrain.is_land(w.position):
			return false
		w.launched_ashore = false
	if Terrain.is_land(w.position):
		return true
	# A fast round covers enough ground in one tick to step over a narrow spit, so above a
	# fraction of the chart resolution the whole step is tested rather than its end point.
	if travel <= Terrain.CELL_NM * 0.25:
		return false
	return Terrain.first_land_contact(w.position - Geo.heading_to_vector(w.heading_deg) * travel, w.position) >= 0.0


func _step_interceptor(w: Weapon, dt: float) -> void:
	var threat := w.intercept_target
	if threat.phase == Weapon.Phase.DEAD:
		w.phase = Weapon.Phase.DEAD
		w.dead_reason = "THREAT ALREADY DEFEATED"
		return
	if not AirDefence._can_intercept(w.spec, threat) or not interceptor_support_available(w.shooter, w.spec, threat):
		w.phase = Weapon.Phase.DEAD
		w.dead_reason = "GUIDANCE LOST"
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


## Decoys have beaten the lock on `from`. The seeker searches on along its heading; if another
## ship lies in its cone and basket it may take that instead, otherwise the round is spent.
func seduce(w: Weapon, from: Unit) -> Unit:
	if w.phase == Weapon.Phase.DEAD:
		return null
	w.seductions += 1
	var best: Unit = null
	if w.seductions <= MAX_SEDUCTIONS and rng.randf() < SEDUCED_REACQUIRE_P:
		var best_d := w.spec.acquisition_radius_nm()
		for u in unit_manager.units:
			if u == from or u.faction == w.faction or not can_target(w.spec, u):
				continue
			var d := w.position.distance_to(u.position)
			if d > best_d:
				continue
			if absf(Geo.heading_delta(w.heading_deg, Geo.bearing_deg(w.position, u.position))) > SEEKER_CONE_DEG:
				continue
			best = u
			best_d = d
	if best == null:
		defeat_weapon(w, "DECOYED", from)
		return null
	w.acquired = best
	w.phase = Weapon.Phase.TERMINAL
	w.decoy_attempted = false  # the new target gets its own chance to decoy it; acoustic tries are per ship already
	weapon_seduced.emit(w, from, best)
	return best


## Whether this round is on its way to a target ashore, by seeker lock or by the track it was
## fired at.
static func _bound_for_land(w: Weapon) -> bool:
	if w.acquired != null:
		return w.acquired.spec.domain == "land"
	return w.target_track != null and w.target_track.domain == "land"


## A seeker only works in its own medium. An anti-ship missile cannot find a submerged boat, and
## a torpedo is no use against something that is not in the water.
static func can_target(spec: WeaponSpec, u: Unit) -> bool:
	if not u.is_engageable():
		return false
	if u.spec.domain == "land":
		return spec.target_types.has("land")
	if u.in_flight():
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
		var destroyed := Damage.apply(target, w.spec.damage, w.spec.type, w.faction)
		weapon_impact.emit(w.faction, w.spec, target, true)
		if destroyed:
			unit_destroyed.emit(target, w.faction)
	else:
		weapon_impact.emit(w.faction, w.spec, target, false)


## One abstract guidance channel per distinct air target, across manual and automatic shots.
## Self-contained CIWS and air-to-air missiles do not reserve ship SAM channels.
func channel_targets(shooter: Unit) -> Dictionary:
	var targets := {}
	for w in in_flight:
		if w.shooter != shooter or w.phase == Weapon.Phase.DEAD or not w.spec.requires_fire_control_channel():
			continue
		if w.intercept_target != null and w.intercept_target.phase != Weapon.Phase.DEAD:
			targets[w.intercept_target] = true
		elif w.target_track != null and w.target_track.domain == "air":
			targets[w.target_track] = true
	for p: Dictionary in _pending:
		if p["shooter"] == shooter and p["spec"].requires_fire_control_channel() and p["track"].domain == "air":
			targets[p["track"]] = true
	return targets


func channel_available(shooter: Unit, target: RefCounted) -> bool:
	var targets := channel_targets(shooter)
	return targets.has(target) or targets.size() < shooter.spec.fire_control_channels


func channel_loads() -> Dictionary:
	var loads := {}
	for w in in_flight:
		if w.shooter != null and not loads.has(w.shooter):
			loads[w.shooter] = channel_targets(w.shooter).size()
	for p: Dictionary in _pending:
		if not loads.has(p["shooter"]):
			loads[p["shooter"]] = channel_targets(p["shooter"]).size()
	return loads


## Command/semi-active SAMs need a working emitting fire-control system. Autonomous
## seekers and self-contained CIWS remain independent of the ship's search-radar switch.
static func radar_support_available(shooter: Unit, spec: WeaponSpec) -> bool:
	if not spec.requires_radar_support():
		return true
	return shooter != null and shooter.alive and shooter.radar_on and shooter.emcon != Unit.Emcon.SILENT and float(shooter.components.get("sensors", 1.0)) > 0.15


static func interceptor_support_available(shooter: Unit, spec: WeaponSpec, threat: Weapon) -> bool:
	if not radar_support_available(shooter, spec):
		return false
	if not spec.requires_radar_support():
		return true
	# A consort's detection is a cue, not illumination through the earth or an island.
	var horizon := Detection.radar_horizon_nm(Detection.mast_or_altitude_m(shooter), threat.flight_altitude_m())
	return shooter.position.distance_to(threat.position) <= horizon and not Detection.terrain_hides_weapon(shooter, threat)
