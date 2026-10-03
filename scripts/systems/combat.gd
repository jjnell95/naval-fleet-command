class_name Combat
## Engagement geometry and probability. Pure static functions, no state, no randomness.

const LEAD_MAX_ITER := 4
const AIR_TARGET_BONUS := 1.25
## An aircraft that sees a missile coming turns away and runs, and a missile fired at the edge of
## its range then runs out of fuel short of it. Against an air target the usable range is cut by
## the target's escape speed over the missile's, never below this fraction. GAMEPLAY_ESTIMATE.
const AIR_ESCAPE_FLOOR := 0.6
const TORPEDO_EVASION_BENEFIT := 0.45
const BMD_INTERCEPTOR_ADVANTAGE := 0.45  # GAMEPLAY_ESTIMATE


## Lead intercept point against a track's estimated motion. Falls back to the raw track position
## when kinematics are not yet estimated.
static func intercept_point(launch_pos: Vector2, weapon_speed_kn: float, track_pos: Vector2, course_deg: float, target_speed_kn: float, has_kinematics: bool) -> Vector2:
	if not has_kinematics or target_speed_kn <= 0.1 or weapon_speed_kn <= 0.0:
		return track_pos
	var velocity := Geo.heading_to_vector(course_deg) * Geo.knots_to_nm_per_s(target_speed_kn)
	var offset := track_pos - launch_pos
	var speed := Geo.knots_to_nm_per_s(weapon_speed_kn)
	var a := velocity.length_squared() - speed * speed
	var b := 2.0 * offset.dot(velocity)
	var c := offset.length_squared()
	var time := INF
	if absf(a) < 0.00000001:
		if b < -0.00000001:
			time = -c / b
	else:
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			for candidate: float in [(-b - sqrt(disc)) / (2.0 * a), (-b + sqrt(disc)) / (2.0 * a)]:
				if candidate >= 0.0:
					time = minf(time, candidate)
	return track_pos + velocity * time if is_finite(time) else Vector2.INF



## Flight profiles that have to get there over the water. A sea-skimmer, a gun round on a flat
## trajectory and a torpedo all stop at a coastline; a cruise missile at 8000 m, a ballistic round
## and an exoatmospheric interceptor do not. GAMEPLAY_ESTIMATE: the split is by profile alone,
## because a round carries no altitude of its own — the simplification is that every "high"
## weapon clears every hill.
const SURFACE_BOUND_PROFILES := ["sea_skimming", "direct", "subsurface"]


static func profile_is_surface_bound(spec: WeaponSpec) -> bool:
	# A "direct" air-to-air or anti-air round is fired at something in the air and flies at its
	# height, not along the ground: a short-range dogfight missile shot across a headland, or a
	# point-defence round at a helicopter over the coast, is not a sea-skimmer.
	if spec.type in ["aam", "sam", "ciws"] and spec.profile == "direct":
		return false
	return SURFACE_BOUND_PROFILES.has(spec.profile)


## Whether the path a round would actually fly crosses land. Tested against the lead point rather
## than the track, so the check and the firing solution drawn on the map agree.
static func crosses_land(shooter: Unit, spec: WeaponSpec, track: Track) -> bool:
	if Terrain.is_empty() or not profile_is_surface_bound(spec):
		return false
	# A target ashore is reached by crossing the coast, and a battery ashore fires out over its
	# own; neither is a line-of-fire problem. Whether the round then gets there is decided in
	# flight, against the ground it actually meets.
	if track.domain == "land" or shooter.spec.domain == "land":
		return false
	var aim := intercept_point(shooter.position, spec.speed_kn, track.position, track.course_deg, track.speed_kn, track.has_kinematics)
	return Terrain.blocks_path(shooter.position, aim)


## Whether `shooter` may fire `spec` at `track` right now. Returns {ok, reason, range_nm}.
static func check_engagement(shooter: Unit, spec: WeaponSpec, track: Track, reserved_round := false) -> Dictionary:
	var out := {"ok": false, "reason": "", "range_nm": 0.0}
	if shooter == null or spec == null or track == null:
		out["reason"] = "NO TARGET"
		return out
	out["range_nm"] = shooter.position.distance_to(track.position)
	if not shooter.alive:
		out["reason"] = "UNIT LOST"
		return out
	if not reserved_round and shooter.magazine_count(spec.id) <= 0:
		out["reason"] = "MAGAZINE EMPTY"
		return out
	if not shooter.can_fire():
		out["reason"] = "LAUNCHERS DAMAGED"
		return out
	if shooter.roe == Unit.Roe.HOLD:
		out["reason"] = "WEAPONS HOLD"
		return out
	if track.status == Track.Status.LOST:
		out["reason"] = "TRACK LOST"
		return out
	if not track.visible_to(shooter):
		out["reason"] = "TRACK NOT HELD / OFF LINK"
		return out
	if track.identity in ["NEUTRAL", "FRIENDLY"]:
		out["reason"] = "PROTECTED IDENTITY"
		return out
	if shooter.roe == Unit.Roe.TIGHT and track.identity != "HOSTILE":
		out["reason"] = "IDENTIFY CONTACT / WEAPONS TIGHT"
		return out
	if not suits_track(spec, track):
		out["reason"] = "WRONG WEAPON FOR CONTACT"
		return out
	var d := shooter.position.distance_to(track.position)
	out["range_nm"] = d
	var max_range := effective_range_nm(shooter, spec)
	if d > max_range:
		out["reason"] = "OUT OF RANGE"
		return out
	if d < spec.min_range_nm:
		out["reason"] = "TOO CLOSE"
		return out
	if track.is_bearing_only() and not spec.is_torpedo():
		out["reason"] = "BEARING ONLY / NO RANGE SOLUTION"
		return out
	# A position worked up from bearings is a fair guess at a ship; at an aircraft covering eight
	# miles a minute it is no fire-control solution at all.
	if track.domain == "air" and track.bearing_only:
		out["reason"] = "NO RADAR FIX ON AIRCRAFT"
		return out
	var aim := intercept_point(shooter.position, spec.speed_kn, track.position, track.course_deg, track.speed_kn, track.has_kinematics)
	if not aim.is_finite():
		out["reason"] = "NO INTERCEPT SOLUTION"
		return out
	out["aim_point"] = aim
	out["flight_range_nm"] = shooter.position.distance_to(aim)
	out["flight_time_s"] = time_of_flight_s(spec, out["flight_range_nm"])
	if float(out["flight_range_nm"]) > max_range:
		out["reason"] = "INTERCEPT BEYOND WEAPON RANGE"
		return out
	# The range the target is at now, against the reach left once it turns and runs: the lead point
	# already allows for the course it holds, so this is the margin for the turn it has yet to make.
	# An aircraft coming straight in has not yet chosen to turn away, so it gets a lighter margin, not
	# none: it will turn once it sees the shot.
	var escape := air_escape_factor(spec, track)
	if closing_on(track, shooter.position):
		escape = maxf(escape, CLOSING_ESCAPE_FLOOR)
	if track.domain == "air" and d > max_range * escape:
		out["reason"] = "TARGET CAN OUTRUN THE SHOT"
		return out
	if crosses_land(shooter, spec, track):
		out["reason"] = "NO LINE OF FIRE"
		return out
	var arc := firing_arc_check(shooter, spec, aim)
	if not arc.ok:
		out["reason"] = "MOUNT MASKED / ATTACK TO UNMASK"
		out["unmask_heading_deg"] = arc.heading_deg
		return out
	out["ok"] = true
	out["reason"] = "IN ENVELOPE"
	return out


## Each authored mount contributes a relative center bearing and a half-width. Multiple mounts
## form a union of arcs; unlisted weapons are unrestricted. A real VLS fit never needs hull
## unmasking. Mechanical launcher arcs are platform data, not a restriction on every SAM.
static func firing_arc_check(shooter: Unit, spec: WeaponSpec, aim: Vector2) -> Dictionary:
	var result := {"ok": true, "heading_deg": shooter.heading_deg}
	if spec.vls_pack > 0 and shooter.spec.vls_cells > 0:
		return result
	var arcs: Array = shooter.spec.weapon_mount_arcs.get(spec.id, [])
	if arcs.is_empty():
		return result
	var bearing := Geo.bearing_deg(shooter.position, aim)
	var relative := Geo.heading_delta(shooter.heading_deg, bearing)
	var best_turn := INF
	for arc: Vector2 in arcs:
		var offset := Geo.heading_delta(arc.x, relative)
		if absf(offset) <= arc.y:
			return result
		# Aim a few degrees inside the nearest edge so motion between rounds does not chatter.
		var safe_half := maxf(arc.y - 5.0, 0.0)
		var turn := offset - clampf(offset, -safe_half, safe_half)
		if absf(turn) < absf(best_turn):
			best_turn = turn
	result.ok = false
	result.heading_deg = fposmod(shooter.heading_deg + best_turn, 360.0)
	return result


## A point on the shooter's side of the target at the standoff distance, swung round the target in
## steps when the direct one is on land. Shared by the AI's approach and the player's Attack task.
const STANDOFF_ARC_DEG: Array[float] = [0.0, 25.0, 50.0, 75.0, 100.0, 130.0, 160.0]


static func standoff_point(from: Vector2, target_pos: Vector2, standoff_nm: float) -> Vector2:
	var offset := (from - target_pos).normalized() * standoff_nm
	if offset.length() < 0.001:
		offset = Vector2(0.0, -standoff_nm)
	if Terrain.is_empty():
		return target_pos + offset
	for step: float in STANDOFF_ARC_DEG:
		for side: float in [1.0, -1.0]:
			var candidate := target_pos + offset.rotated(deg_to_rad(step * side))
			if not Terrain.is_land(candidate):
				return candidate
	return target_pos + offset


## A sea point within `standoff_nm` of the target from which a surface-bound round has an open
## line to it: the standoff ring swung round the target, then drawn in. Vector2.INF when the
## coast leaves none, which ends an attack rather than parking it behind a headland.
static func clear_standoff_point(from: Vector2, target_pos: Vector2, standoff_nm: float) -> Vector2:
	if Terrain.is_empty():
		return standoff_point(from, target_pos, standoff_nm)
	var bearing := (from - target_pos).normalized()
	if bearing.length() < 0.001:
		bearing = Vector2(0.0, -1.0)
	for fraction: float in [1.0, 0.75, 0.5, 0.3]:
		for step: float in STANDOFF_ARC_DEG:
			for side: float in [1.0, -1.0]:
				var candidate := target_pos + bearing.rotated(deg_to_rad(step * side)) * standoff_nm * fraction
				if not Terrain.is_land(candidate) and not Terrain.blocks_path(candidate, target_pos):
					return candidate
	return Vector2.INF


## The share of a missile's range that is usable against an aircraft that turns and runs once it
## sees the shot coming: (missile speed - escape speed) / missile speed, floored at AIR_ESCAPE_FLOOR.
## Escape speed is the reported class's top speed when the plot knows the class, else the plot's
## own speed. Reads only the plot.
static func air_escape_factor(spec: WeaponSpec, track: Track) -> float:
	if track == null or track.domain != "air" or spec.speed_kn <= 0.0 or spec.is_gun():
		return 1.0
	var escape := track.speed_kn if track.has_kinematics else 0.0
	if track.classification >= Track.Classification.CLASS_KNOWN:
		var pid := MapSymbols.platform_for_class(track.known_class, track.known_category)
		var known := DataDB.platform(pid) if pid != "" else null
		if known != null:
			escape = maxf(escape, known.max_speed_kn)
	return clampf((spec.speed_kn - escape) / spec.speed_kn, AIR_ESCAPE_FLOOR, 1.0)


## Whether the plot's course points within CLOSING_CONE_DEG of `at`: an aircraft coming straight
## in is shot at the full envelope, because turning away is a choice it has not yet made.
const CLOSING_CONE_DEG := 45.0
const CLOSING_ESCAPE_FLOOR := 0.8


static func closing_on(track: Track, at: Vector2) -> bool:
	if track == null or not track.has_kinematics or track.speed_kn <= 0.0:
		return false
	return absf(Geo.heading_delta(track.course_deg, Geo.bearing_deg(track.position, at))) <= CLOSING_CONE_DEG


## Unpowered bombs depend on the launch aircraft height. All numbers are gameplay tuning.
static func effective_range_nm(shooter: Unit, spec: WeaponSpec) -> float:
	if spec.type == "bomb":
		return minf(spec.max_range_nm, maxf(shooter.altitude_m, 0.0) / 1000.0)
	return spec.max_range_nm


## Probability that one interceptor destroys one incoming round. Fast, low-flying or stealthy
## rounds carry a higher `defensive_difficulty` and are correspondingly harder to stop.
static func intercept_probability(interceptor: WeaponSpec, threat: WeaponSpec) -> float:
	if interceptor.base_pk <= 0.0:
		return 0.0  # a weapon with no listed effectiveness cannot intercept
	var difficulty := threat.defensive_difficulty
	# A ballistic round is a very hard problem for a missile built for the atmosphere, and a
	# tractable one for an interceptor built to meet it outside it.
	if threat.profile == "ballistic" and interceptor.profile == "exoatmospheric":
		difficulty *= BMD_INTERCEPTOR_ADVANTAGE
	# The floor keeps very difficult rounds from becoming outright immune.
	return clampf(interceptor.base_pk / maxf(difficulty, 0.1), 0.05, 0.95)


## Hit probability once the seeker has acquired a real unit. Milestone 4 will subtract the
## effect of hard-kill and soft-kill defences here.
static func hit_probability(spec: WeaponSpec, target: Unit) -> float:
	if spec.is_torpedo():
		# A ship that has heard the torpedo and is running gives the weapon a much harder problem.
		# Turning away and opening the range is the only hard answer a surface ship has.
		var evasion := clampf(target.speed_kn / maxf(target.spec.max_speed_kn, 1.0), 0.0, 1.0)
		return clampf(spec.base_pk * (1.0 - TORPEDO_EVASION_BENEFIT * evasion), 0.05, 0.99)
	if target.in_flight():
		# An aircraft is a far easier thing to hit than a sea-skimming missile, and these weapons
		# are rated against the harder job.
		return clampf(spec.base_pk * AIR_TARGET_BONUS * DefensiveResponse.evasion_factor(target, spec), 0.0, 0.90)
	var size_mod := clampf(0.75 + target.spec.signature_factor * 0.25, 0.6, 1.1)
	return clampf(spec.base_pk * size_mod * DefensiveResponse.evasion_factor(target, spec), 0.0, 0.99)


## How long this weapon would take to cover a given range.
static func time_of_flight_s(spec: WeaponSpec, range_nm: float) -> float:
	if spec.speed_kn <= 0.0:
		return INF
	return range_nm / spec.speed_kn * 3600.0


## Whether this weapon is the right kind for what the track is believed to be. A contact whose
## domain is not yet known cannot be matched to a weapon, which is another reason to classify
## before shooting.
static func suits_track(spec: WeaponSpec, track: Track) -> bool:
	if track.domain == "subsurface":
		return spec.target_types.has("subsurface")
	if track.domain == "surface":
		return spec.target_types.has("surface")
	if track.domain == "air":
		return spec.target_types.has("air")
	if track.domain == "land":
		return spec.target_types.has("land")  # land-attack cruise missiles and gunfire
	return false
