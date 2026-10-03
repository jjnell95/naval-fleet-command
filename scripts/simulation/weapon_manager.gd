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
## Every completed flight, including ordinary impacts, losses of guidance and exhausted range.
signal weapon_resolved(weapon: Weapon)
## A round pulled off its target by decoys that found another ship in its seeker basket.
signal weapon_seduced(threat: Weapon, from_unit: Unit, to_unit: Unit)
## Expendable decoys used, chaff or acoustic, whether or not they worked. A towed decoy is not one.
signal decoys_spent(unit: Unit, count: int)
## An offensive round left its launcher, with its group tag. A group attack counts what it has
## spent from this; rounds that later resolve are gone from in_flight but stay spent.
signal weapon_fired(weapon: Weapon)
## A reserved round left the launcher queue without firing: cancelled by the commander, a hold
## order, or a solution that failed while it waited. `refunded` is false when the shooter was lost
## with it aboard. A group attack returns the round to its pool.
signal queued_round_dropped(shooter: Unit, spec: WeaponSpec, track: Track, group_id: int, refunded: bool, reason: String)

const IMPACT_MIN_NM := 0.05
## Decoys do not delete a missile; they move it. A seduced seeker flies on through the cloud and
## locks whatever else it finds ahead, which is why an escort's chaff is a hazard to the ship
## behind it. GAMEPLAY_ESTIMATE.
const SEDUCED_REACQUIRE_P := 0.5
const MAX_SEDUCTIONS := 2

var unit_manager: UnitManager
var track_manager: TrackManager
var rng := RandomNumberGenerator.new()
var in_flight: Array[Weapon] = []
var revision := 0  # presentation invalidation for launches/cancellations while paused

var _channel_batch := false
var _channel_cache: Dictionary = {}

var _next_id := 1
var _launcher_ready_at: Dictionary = {}  # shooter -> launcher group -> next launch time
var now_s := 0.0
var _pending: Array = []  # queued salvo rounds: {shooter, spec, track, time, group}
var _pending_dirty := false


## `group_id` tags every round of the salvo, queued or fired, for a coordinated group attack.
func launch(shooter: Unit, spec: WeaponSpec, track: Track, salvo: int, now: float, group_id := -1) -> bool:
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
			_fire_round(shooter, spec, track, group_id)
			_mark_launched(shooter, spec, now)
		else:
			_pending.append({"shooter": shooter, "spec": spec, "track": track, "time": launch_at, "group": group_id})
			_pending_dirty = true
		launch_at += launch_spacing(shooter, spec)
	if _channel_batch and spec.requires_fire_control_channel() and track.domain == "air":
		var held: Dictionary = _channel_cache.get(shooter, {})
		held[track] = true
		_channel_cache[shooter] = held
	revision += 1
	weapon_launched.emit(shooter, spec, track, rounds)
	return true


## Authored mechanical groups share one service; VLS fits share an abstract launch service.
## Other mounts/racks are independent by weapon family. Timing is gameplay tuning, not a real launcher throughput specification.
static func launcher_key(shooter: Unit, spec: WeaponSpec) -> String:
	return str(shooter.spec.launcher_groups.get(spec.id, "VLS" if spec.vls_pack > 0 and shooter.spec.vls_cells > 0 else spec.id))


static func launch_spacing(shooter: Unit, spec: WeaponSpec) -> float:
	return maxf(maxf(spec.launch_interval_s, 0.25), float(shooter.spec.launcher_service_s.get(launcher_key(shooter, spec), 0.0)))


func _ready_time(shooter: Unit, spec: WeaponSpec) -> float:
	return float(_launcher_ready_at.get(shooter, {}).get(launcher_key(shooter, spec), 0.0))


func _mark_launched(shooter: Unit, spec: WeaponSpec, now: float) -> void:
	var ready: Dictionary = _launcher_ready_at.get(shooter, {})
	ready[launcher_key(shooter, spec)] = now + launch_spacing(shooter, spec)
	_launcher_ready_at[shooter] = ready


func ready_in_s(shooter: Unit, spec: WeaponSpec, now: float) -> float:
	var at := maxf(now, _ready_time(shooter, spec))
	var key := launcher_key(shooter, spec)
	_sort_pending()
	for p: Dictionary in _pending:
		if p.shooter == shooter and launcher_key(shooter, p.spec) == key:
			at = maxf(at, float(p.time)) + launch_spacing(shooter, p.spec)
	return maxf(at - now, 0.0)


func _sort_pending() -> void:
	if not _pending_dirty:
		return
	_pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.time) < float(b.time))
	_pending_dirty = false



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


## Rounds one side has on the way to each of its contacts, keyed by track id: those flying and those
## still queued on a launcher behind the first round of a salvo. A queued round is as committed as a
## flying one; leaving it out let a group spend four times its intended weight on one target. Keyed
## by id because a boat off the link holds its own Track object for the same contact.
func rounds_committed_by_track_id(faction: String) -> Dictionary:
	var out := {}
	for w in in_flight:
		if w.faction == faction and w.target_track != null and w.phase != Weapon.Phase.DEAD:
			out[w.target_track.id] = int(out.get(w.target_track.id, 0)) + 1
	for p: Dictionary in _pending:
		var shooter: Unit = p.shooter
		var track: Track = p.track
		if shooter.faction == faction and track != null:
			out[track.id] = int(out.get(track.id, 0)) + 1
	return out


func engagement_check(shooter: Unit, spec: WeaponSpec, track: Track, now: float, reserved_round := false) -> Dictionary:
	var check := Combat.check_engagement(shooter, spec, track, reserved_round)
	if not check.ok:
		return check
	if not track_support_available(shooter, spec, track):
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
	var retained: Array = []
	var dropped: Array = []
	for p: Dictionary in _pending:
		if p.shooter == shooter and (track == null or p.track == track):
			if shooter.alive:
				shooter.magazines[p.spec.id] = shooter.magazine_count(p.spec.id) + 1
			count += 1
			dropped.append(p)
		else:
			retained.append(p)
	_pending = retained
	if count > 0:
		revision += 1
	for p: Dictionary in dropped:
		queued_round_dropped.emit(p.shooter, p.spec, p.track, int(p.get("group", -1)), shooter.alive, "CANCELLED")
	return count


## One contact as a faction holds it. A platform off the link keeps its own copy of a track under
## the same number, so commitments are counted by owner and number, never by the Track object.
static func contact_key(t: Track) -> String:
	return "" if t == null else "%s|%s" % [t.owner_faction, t.id]


## A group attack's rounds: queued, plus (unless `queued_only`) in flight and not yet resolved.
## Narrowed to one contact (`key`, from contact_key) and to one shooter when given.
func group_rounds(group_id: int, key := "", queued_only := false, shooter: Unit = null) -> int:
	var count := 0
	for p: Dictionary in _pending:
		if int(p.get("group", -1)) == group_id and (shooter == null or p.shooter == shooter) and (key == "" or contact_key(p.track) == key):
			count += 1
	if not queued_only:
		for w in in_flight:
			if w.group_id == group_id and w.phase != Weapon.Phase.DEAD and (shooter == null or w.shooter == shooter) and (key == "" or contact_key(w.target_track) == key):
				count += 1
	return count


## Withdraws a group attack's queued rounds: all of them, one shooter's, or those at one contact.
## Refunds follow cancel_salvo: a round goes back aboard only if its shooter is still afloat.
func cancel_group(group_id: int, shooter: Unit = null, key := "", reason := "CANCELLED") -> int:
	var retained: Array = []
	var dropped: Array = []
	for p: Dictionary in _pending:
		if int(p.get("group", -1)) == group_id and (shooter == null or p.shooter == shooter) and (key == "" or contact_key(p.track) == key):
			if p.shooter.alive:
				p.shooter.magazines[p.spec.id] = p.shooter.magazine_count(p.spec.id) + 1
			dropped.append(p)
		else:
			retained.append(p)
	_pending = retained
	if not dropped.is_empty():
		revision += 1
	for p: Dictionary in dropped:
		queued_round_dropped.emit(p.shooter, p.spec, p.track, group_id, p.shooter.alive, reason)
	return dropped.size()


## Every offensive round a faction has queued or flying at one contact, whoever fired it and on
## whatever picture: what the side as a whole already has committed there.
func faction_commitment(faction: String, track: Track, queued_only := false) -> int:
	var key := contact_key(track)
	var count := 0
	for p: Dictionary in _pending:
		if p.shooter.faction == faction and contact_key(p.track) == key:
			count += 1
	if not queued_only:
		for w in in_flight:
			if w.faction == faction and w.phase != Weapon.Phase.DEAD and w.intercept_target == null and contact_key(w.target_track) == key:
				count += 1
	return count



## Fires interceptors at a weapon already in flight. Used by the air-defence system: by itself on
## automatic defence, or for the rounds a commander's intercept order cleared (AirDefence
## order_intercept), through the same layers and checks either way. Returns the rounds launched.
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
	if not Combat.firing_arc_check(shooter, spec, threat.position).ok:
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
	if _channel_batch and spec.requires_fire_control_channel():
		var held: Dictionary = _channel_cache.get(shooter, {})
		held[threat] = true
		_channel_cache[shooter] = held
	revision += 1
	interceptor_launched.emit(shooter, spec, threat, available)
	return available


## Marks an in-flight weapon as destroyed or decoyed before it reaches its target.
func defeat_weapon(threat: Weapon, reason: String, by_unit: Unit = null) -> void:
	if threat.phase == Weapon.Phase.DEAD:
		return
	threat.phase = Weapon.Phase.DEAD
	threat.dead_reason = reason
	revision += 1
	weapon_defeated.emit(threat, reason, by_unit)


func tick(dt: float, now: float) -> void:
	now_s = now
	_sort_pending()
	for p: Dictionary in _pending.duplicate():
		var check := engagement_check(p.shooter, p.spec, p.track, now, true)
		if not check.ok:
			_pending.erase(p)
			revision += 1
			if p.shooter.alive:
				p.shooter.magazines[p.spec.id] = p.shooter.magazine_count(p.spec.id) + 1
			engagement_rejected.emit(p.shooter, p.spec, "QUEUED ROUND CANCELLED: " + str(check.reason))
			queued_round_dropped.emit(p.shooter, p.spec, p.track, int(p.get("group", -1)), p.shooter.alive, str(check.reason))
		elif now >= float(p.time) and now >= _ready_time(p.shooter, p.spec):
			_pending.erase(p)
			_fire_round(p.shooter, p.spec, p.track, int(p.get("group", -1)))
			_mark_launched(p.shooter, p.spec, now)
	for i in range(in_flight.size() - 1, -1, -1):
		_step(in_flight[i], dt)
		if in_flight[i].phase == Weapon.Phase.DEAD:
			var resolved := in_flight[i]
			in_flight.remove_at(i)
			revision += 1
			weapon_resolved.emit(resolved)


func clear() -> void:
	end_channel_batch()
	in_flight.clear()
	_pending.clear()
	_pending_dirty = false
	_launcher_ready_at.clear()
	now_s = 0.0
	_next_id = 1
	revision += 1


func _fire_round(shooter: Unit, spec: WeaponSpec, track: Track, group_id := -1) -> void:
	var w := Weapon.new()
	w.id = _next_id
	_next_id += 1
	w.spec = spec
	w.faction = shooter.faction
	w.shooter = shooter
	w.target_track = track
	w.group_id = group_id
	w.position = shooter.position
	w.launch_altitude_m = shooter.altitude_m if shooter.in_flight() else spec.altitude_m
	w.launched_ashore = shooter.spec.domain == "land"
	w.aim_point = _aim_for(w)
	w.launch_range_nm = w.position.distance_to(w.aim_point)
	w.heading_deg = Geo.bearing_deg(w.position, w.aim_point)
	in_flight.append(w)
	revision += 1
	round_fired.emit(shooter, spec, track)
	weapon_fired.emit(w)


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
	if w.intercept_target == null and w.target_track != null and not track_support_available(w.shooter, w.spec, w.target_track):
		w.phase = Weapon.Phase.DEAD
		w.dead_reason = "GUIDANCE LOST"
		return
	if w.intercept_target != null:
		_step_interceptor(w, dt)
		return
	if w.spec.delivery_payload_id != "":
		_step_delivery(w, dt)
		return
	# Authored update-capable weapons follow only an active report held by a living shooter.
	# An autonomous launch-and-leave weapon keeps its launch solution until terminal search.
	if w.spec.supports_midcourse_updates() and w.delivery_spec == null and w.phase == Weapon.Phase.CRUISE and w.shooter != null and w.shooter.alive and w.target_track != null and w.target_track.status == Track.Status.ACTIVE and w.target_track.visible_to(w.shooter):
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

	var previous := w.position
	var distance_before := w.distance_flown_nm
	var travel := minf(w.speed_nm_per_s() * dt, maxf(w.spec.max_range_nm - distance_before, 0.0))
	w.position += Geo.heading_to_vector(w.heading_deg) * travel
	w.distance_flown_nm += travel

	if _hits_terrain(w, travel):
		w.phase = Weapon.Phase.DEAD
		w.dead_reason = "TERRAIN"
		return

	if w.phase == Weapon.Phase.CRUISE:
		if w.spec.is_torpedo():
			# A torpedo runs out before its seeker comes on, then searches the whole way in.
			# That is why a shot down a rough bearing is still worth taking.
			if w.distance_flown_nm >= w.spec.run_to_enable_nm:
				# Only the part of the step after run-out is inside the seeker basket.
				var enabled_fraction := clampf((w.spec.run_to_enable_nm - distance_before) / maxf(travel, 1e-9), 0.0, 1.0)
				previous = previous.lerp(w.position, enabled_fraction)
				previous = _try_acquire(w, previous)
		else:
			var radius := w.spec.acquisition_radius_nm()
			var enabled_fraction := _first_radius_contact_fraction(previous, w.position, w.aim_point, radius)
			if is_finite(enabled_fraction):
				previous = previous.lerp(w.position, enabled_fraction)
				previous = _try_acquire(w, previous)

	# Sweep the travelled segment instead of inflating the impact radius by speed. Fast rounds
	# must not skip a target, or hit one they passed a long way abeam while unable to turn.
	if w.phase == Weapon.Phase.TERMINAL and w.acquired != null and _segment_distance_squared(previous, w.position, w.acquired.position) <= IMPACT_MIN_NM * IMPACT_MIN_NM:
		_resolve_impact(w)
	elif w.phase != Weapon.Phase.DEAD and w.distance_flown_nm >= w.spec.max_range_nm:
		w.phase = Weapon.Phase.DEAD
		w.dead_reason = "RANGE EXHAUSTED"


## Rocket-delivered ASW: fly to the held launch solution, then put a fresh torpedo into the
## water. The payload has its own speed, seeker and run distance, with no hidden target cue.
func _step_delivery(w: Weapon, dt: float) -> void:
	var travel := minf(w.speed_nm_per_s() * dt, maxf(w.spec.max_range_nm - w.distance_flown_nm, 0.0))
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
	# Lead a moving inbound. Pointing only at its current position makes crossing shots chase
	# its wake, and an accurate swept collision check exposes the miss hidden by a wide radius.
	var aim := Combat.intercept_point(w.position, w.spec.speed_kn, threat.position, threat.heading_deg, threat.spec.speed_kn, true)
	var desired := Geo.bearing_deg(w.position, aim if aim.is_finite() else threat.position)
	var max_turn := w.spec.turn_rate_deg_s * dt
	w.heading_deg = fposmod(w.heading_deg + clampf(Geo.heading_delta(w.heading_deg, desired), -max_turn, max_turn), 360.0)
	var previous := w.position
	var travel := minf(w.speed_nm_per_s() * dt, maxf(w.spec.max_range_nm - w.distance_flown_nm, 0.0))
	w.position += Geo.heading_to_vector(w.heading_deg) * travel
	w.distance_flown_nm += travel
	# Interceptors are advanced before the inbound. Test relative motion through this tick,
	# including the inbound's remaining run, instead of a speed-dependent proximity radius.
	var flight_dt := travel / w.speed_nm_per_s() if w.speed_nm_per_s() > 0.0 else 0.0
	var threat_remaining := maxf(threat.spec.max_range_nm - threat.distance_flown_nm, 0.0)
	if threat.speed_nm_per_s() > 0.0:
		flight_dt = minf(flight_dt, threat_remaining / threat.speed_nm_per_s())
	elif threat_remaining <= 0.0:
		flight_dt = 0.0
	var intercept_end := previous + Geo.heading_to_vector(w.heading_deg) * w.speed_nm_per_s() * flight_dt
	var threat_travel := threat.speed_nm_per_s() * flight_dt
	var threat_end := threat.position + Geo.heading_to_vector(threat.heading_deg) * threat_travel
	if _segment_distance_squared(previous - threat.position, intercept_end - threat_end, Vector2.ZERO) > IMPACT_MIN_NM * IMPACT_MIN_NM:
		if w.distance_flown_nm >= w.spec.max_range_nm:
			w.phase = Weapon.Phase.DEAD
			w.dead_reason = "RANGE EXHAUSTED"
		return
	w.phase = Weapon.Phase.DEAD
	if rng.randf() < Combat.intercept_probability(w.spec, threat.spec):
		w.dead_reason = "INTERCEPT"
		defeat_weapon(threat, "INTERCEPTED", w.shooter)
	else:
		w.dead_reason = "INTERCEPT MISS"


static func _segment_distance_squared(from: Vector2, to: Vector2, point: Vector2) -> float:
	var delta := to - from
	var fraction := clampf((point - from).dot(delta) / maxf(delta.length_squared(), 1e-12), 0.0, 1.0)
	return point.distance_squared_to(from + delta * fraction)


## The first point of a step inside a circle. INF means the entire step misses the basket.
static func _first_radius_contact_fraction(from: Vector2, to: Vector2, point: Vector2, radius: float) -> float:
	var offset := from - point
	var c := offset.length_squared() - radius * radius
	if c <= 0.0:
		return 0.0
	var delta := to - from
	var a := delta.length_squared()
	if a <= 1e-12:
		return INF
	var b := offset.dot(delta)
	var discriminant := b * b - a * c
	if discriminant < 0.0:
		return INF
	var fraction := (-b - sqrt(discriminant)) / a
	return fraction if fraction >= 0.0 and fraction <= 1.0 else INF


## First intersection of a swept forward search cone and its range circle. Clip the segment
## against the two cone boundary half-planes, then the circle. This catches fast passes without
## acquiring something behind the seeker or inventing an impact before the lock point.
static func first_seeker_contact_fraction(from: Vector2, to: Vector2, point: Vector2, radius: float, heading_deg: float, half_angle_deg: float) -> float:
	var delta := to - from
	var relative := point - from
	var forward := Geo.heading_to_vector(heading_deg)
	var side := Vector2(forward.y, -forward.x)
	var angle := deg_to_rad(clampf(half_angle_deg, 0.1, 89.9))
	var low := 0.0
	var high := 1.0
	for sign_value: float in [-1.0, 1.0]:
		var normal := forward * sin(angle) + side * (sign_value * cos(angle))
		var start := relative.dot(normal)
		var rate := -delta.dot(normal)
		if absf(rate) < 1e-9:
			if start < -1e-7:
				return INF
		elif rate > 0.0:
			low = maxf(low, -start / rate)
		else:
			high = minf(high, -start / rate)
	if low > high + 1e-7 or high < 0.0 or low > 1.0:
		return INF
	low = clampf(low, 0.0, 1.0)
	high = clampf(high, low, 1.0)
	var clipped_from := from.lerp(to, low)
	var fraction := _first_radius_contact_fraction(clipped_from, from.lerp(to, high), point, radius)
	return lerpf(low, high, fraction) if is_finite(fraction) else INF


## Return the actual lock point, so an impact cannot use travel completed before acquisition.
## Terminal search cannot read the commander's identities: friendly and neutral traffic can be
## acquired just like hostile traffic. The firing platform is excluded from its own seeker.
func _try_acquire(w: Weapon, previous: Vector2) -> Vector2:
	var radius := w.spec.acquisition_radius_nm()
	var best: Unit = null
	var first_fraction := INF
	var best_d_squared := INF
	for u in unit_manager.units:
		if u == w.shooter or not can_target(w.spec, u):
			continue
		var fraction := first_seeker_contact_fraction(previous, w.position, u.position, radius, w.heading_deg, w.spec.seeker_half_angle_deg)
		if not is_finite(fraction):
			continue
		var lock_point := previous.lerp(w.position, fraction)
		var d_squared := lock_point.distance_squared_to(u.position)
		if fraction < first_fraction or (is_equal_approx(fraction, first_fraction) and d_squared <= best_d_squared):
			best = u
			first_fraction = fraction
			best_d_squared = d_squared
	if best == null:
		if _segment_distance_squared(previous, w.position, w.aim_point) <= IMPACT_MIN_NM * IMPACT_MIN_NM * 4.0:
			w.phase = Weapon.Phase.DEAD
			w.dead_reason = "NO ACQUISITION"
		return previous
	w.acquired = best
	w.phase = Weapon.Phase.TERMINAL
	return previous.lerp(w.position, first_fraction)


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
			if u == from or u == w.shooter or not can_target(w.spec, u):
				continue
			var d := w.position.distance_to(u.position)
			if d > best_d:
				continue
			if not is_finite(first_seeker_contact_fraction(w.position, w.position, u.position, best_d, w.heading_deg, w.spec.seeker_half_angle_deg)):
				continue
			best = u
			best_d = d
	if best == null:
		defeat_weapon(w, "DECOYED", from)
		return null
	w.acquired = best
	w.phase = Weapon.Phase.TERMINAL
	w.decoy_attempted = false  # the new target gets its own chance to decoy it; acoustic tries are per ship already
	revision += 1
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
	if _channel_batch:
		var held: Dictionary = _channel_cache.get(shooter, {})
		for target in held.keys():
			if target is Weapon and target.phase == Weapon.Phase.DEAD:
				held.erase(target)
		return held
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


func begin_channel_batch() -> void:
	_channel_cache = _all_channel_targets()
	_channel_batch = true


func end_channel_batch() -> void:
	_channel_batch = false
	_channel_cache.clear()


func _all_channel_targets() -> Dictionary:
	var all := {}
	for w in in_flight:
		if w.shooter == null or w.phase == Weapon.Phase.DEAD or not w.spec.requires_fire_control_channel():
			continue
		var target: RefCounted = w.intercept_target if w.intercept_target != null else w.target_track
		if target == null or (target is Weapon and target.phase == Weapon.Phase.DEAD) or (target is Track and target.domain != "air"):
			continue
		var held: Dictionary = all.get(w.shooter, {})
		held[target] = true
		all[w.shooter] = held
	for p: Dictionary in _pending:
		if p.spec.requires_fire_control_channel() and p.track.domain == "air":
			var held: Dictionary = all.get(p.shooter, {})
			held[p.track] = true
			all[p.shooter] = held
	return all


func channel_loads() -> Dictionary:
	var loads := {}
	var all := _channel_cache if _channel_batch else _all_channel_targets()
	for shooter in all:
		loads[shooter] = all[shooter].size()
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


## Unknown altitude cannot certify a low-target illuminator path: use a conservative sea-level
## estimate until a radar observation supplies height. The decision never follows Track.truth.
static func track_support_available(shooter: Unit, spec: WeaponSpec, track: Track) -> bool:
	if not radar_support_available(shooter, spec):
		return false
	if not spec.requires_radar_support() or track == null or track.domain != "air":
		return true
	var altitude := maxf(track.altitude_m, 0.0)
	var horizon := Detection.radar_horizon_nm(Detection.mast_or_altitude_m(shooter), altitude)
	return shooter.position.distance_to(track.position) <= horizon and not Terrain.masks_line_of_sight(shooter.position, Detection.mast_or_altitude_m(shooter), track.position, altitude)
