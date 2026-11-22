class_name Movement
## Kinematics on simulation ticks. Pure functions over Unit state; no rendering, no nodes.

const ARRIVAL_MIN_NM := 0.1
const FULL_TURN_SPEED_KN := 5.0  # GAMEPLAY_ESTIMATE: below this, rudder authority scales down
## A fixed-wing aircraft with nowhere to go flies a racetrack through the point it was sent to
## rather than stopping in the air. GAMEPLAY_ESTIMATE dimensions.
const HOLD_LEG_NM := 6.0
const HOLD_WIDTH_NM := 3.0
const HOLD_TURN_MARGIN := 1.15


## A hull held by a coast for this long, making less than COAST_HEADWAY_FRACTION of the way its
## ordered speed asks for, has run out of water: it stops, gives up the leg and says so, rather
## than grinding at the beach with its engines turning. GAMEPLAY_ESTIMATE.
const COAST_BLOCKED_S := 20.0
const COAST_HEADWAY_FRACTION := 0.25
## Meeting a coast at less than this off its line, a hull is turned along it; steeper, it is stopped.
const COAST_TURN_MAX_DEG := 60.0
## A hull held by a coast can still be worked round with her engines, as fast as she would turn
## at this speed: without it a ship stopped bows-on to a beach could never be turned off it.
const COAST_TWIST_KN := 8.0
## While she is still coming round by more than this she is not counted as blocked.
const COAST_TURNING_DEG := 5.0


## Fraction of economical patrol speed below which a fixed-wing aircraft cannot be flown.
const MIN_FLYING_FRACTION := 0.6  # GAMEPLAY_ESTIMATE


## Turn rate actually available now, in degrees a second: the catalogue rate, scaled down at low
## speed, and for a hull held to a turning circle proportional to its length.
static func turn_rate_now(u: Unit) -> float:
	var way := u.speed_kn
	if u.coast_blocked_s > 0.0 and u.needs_sea_room():
		way = maxf(way, COAST_TWIST_KN)
	var rate := u.spec.turn_rate_deg_s * clampf(way / FULL_TURN_SPEED_KN, 0.0, 1.0)
	if u.needs_sea_room() and u.spec.length_m > 0:
		# GAMEPLAY_ESTIMATE: a displacement hull needs a turning circle proportional to
		# its length. The catalogue rate is a ceiling, not a pivot rate at every speed.
		var radius_m := u.spec.length_m * (1.5 if u.is_submarine() else 2.5)
		rate = minf(rate, rad_to_deg(way * 1852.0 / 3600.0 / radius_m))
	return rate


## A waypoint inside either of the two circles the unit would trace at full rudder can never be
## reached by turning toward it: the unit would orbit it for good. It counts as passed. A point
## merely close astern is outside both circles and is reached by coming round.
static func _passing_inside_turn(u: Unit, wp: Vector2) -> bool:
	var rate := turn_rate_now(u)
	if rate <= 0.0:
		return false
	var radius_nm := Geo.knots_to_nm_per_s(u.speed_kn) / deg_to_rad(rate)
	var abeam := Geo.heading_to_vector(u.heading_deg + 90.0) * radius_nm
	var inside := radius_nm * 0.95
	return wp.distance_to(u.position + abeam) < inside or wp.distance_to(u.position - abeam) < inside


## A last point inside the turning circle is not an arrival: steering for it she would only circle
## it. She stands on for a tactical diameter, from where the point lies outside both circles, and
## comes round to it. A point on the way is simply passed for the next. A fixed-wing aircraft
## holds through the point instead, and a hull with no sea room ahead counts it as reached.
static func _open_out(u: Unit, wp: Vector2) -> bool:
	if must_keep_flying(u):
		return false
	var rate := turn_rate_now(u)
	if rate <= 0.0:
		return false
	var diameter := 2.0 * Geo.knots_to_nm_per_s(u.speed_kn) / deg_to_rad(rate)
	var out := u.position + Geo.heading_to_vector(u.heading_deg) * diameter
	if u.needs_sea_room() and not Terrain.is_empty() and (Terrain.is_land(out) or not Terrain.sea_leg_clear(u.position, out)):
		return false
	u.waypoints.push_front(out)
	return true


## Clearing baffles. A boat with the habit swings BAFFLE_CLEAR_TURN_DEG off its course for the last
## BAFFLE_CLEAR_S of every interval, to alternate sides, so the arc its hull sonar cannot hear
## (Detection.baffled) sweeps over what was dead astern. The route itself is not changed.
const BAFFLE_CLEAR_S := 150.0
const BAFFLE_CLEAR_TURN_DEG := 70.0


static func _baffle_clearing_offset(u: Unit, dt: float) -> float:
	if u.baffle_clear_interval_s <= BAFFLE_CLEAR_S or not u.is_submarine() or u.speed_kn < 1.0:
		return 0.0
	u.baffle_clock_s += dt
	var leg := floorf(u.baffle_clock_s / u.baffle_clear_interval_s)
	if u.baffle_clock_s - leg * u.baffle_clear_interval_s < u.baffle_clear_interval_s - BAFFLE_CLEAR_S:
		return 0.0
	return BAFFLE_CLEAR_TURN_DEG if int(leg) % 2 == 0 else -BAFFLE_CLEAR_TURN_DEG


## Whether this unit is a fixed-wing aircraft in normal flight: it cannot stop, hover or park.
static func must_keep_flying(u: Unit) -> bool:
	return u.is_aircraft() and not u.spec.can_hover and u.flight_state == Unit.FlightState.AIRBORNE


## A holding racetrack that starts and ends at `center`, its long legs along `heading_deg`. It ends
## where it began, so arriving at the last point simply lays the same pattern again: no state.
static func hold_pattern(center: Vector2, heading_deg: float, width_nm := HOLD_WIDTH_NM, leg_nm := HOLD_LEG_NM) -> Array[Vector2]:
	var along := Geo.heading_to_vector(heading_deg)
	var right := Geo.heading_to_vector(heading_deg + 90.0)
	return [center + along * leg_nm, center + along * leg_nm + right * width_nm, center + right * width_nm, center]


## The racetrack an airframe can actually fly at its patrol speed: at least as wide as its turn
## diameter with a margin, and twice as long as it is wide. A fighter keeps the standard pattern;
## a patrol aircraft or a bomber gets a bigger one.
static func hold_size_nm(spec: PlatformSpec) -> Vector2:
	var rate := maxf(spec.turn_rate_deg_s, 0.1)
	var diameter := 2.0 * Geo.knots_to_nm_per_s(spec.flight_speed("patrol")) / deg_to_rad(rate)
	var width := maxf(HOLD_WIDTH_NM, diameter * HOLD_TURN_MARGIN)
	return Vector2(width, maxf(HOLD_LEG_NM, width * 2.0))


## Puts a fixed-wing aircraft into a hold at `center` at its economical patrol speed. The long legs
## lie along its present heading unless `along_deg` names another; the racetrack is to the right of
## them, so a caller that must keep the aircraft off something lays the legs with it to port.
static func enter_hold(u: Unit, center: Vector2, along_deg := NAN) -> void:
	var hold := hold_size_nm(u.spec)
	u.waypoints.assign(hold_pattern(center, u.heading_deg if is_nan(along_deg) else along_deg, hold.x, hold.y))
	u.ordered_speed_kn = u.spec.flight_speed("patrol")
	u.hold_active = true
	u.hold_point = center


static func step(u: Unit, dt: float) -> void:
	if u.is_aircraft() and u.flight_state == Unit.FlightState.RECOVERING:
		return  # AviationManager owns the final approach, descent and moving-deck intercept.
	if u.is_aircraft() and not u.airborne():
		# Sitting in a hangar: it goes where its parent goes and does nothing of its own.
		if u.home != null:
			u.position = u.home.position
			u.heading_deg = u.home.heading_deg
		u.speed_kn = 0.0
		u.altitude_m = 0.0
		return
	if DippingSonar.step_motion(u, dt):
		return
	TowedArray.step(u, dt)
	SubmarinePower.step(u, dt)
	var evading := u.evasion_remaining_s > 0.0
	var desired := u.evasion_course_deg if evading else u.ordered_heading_deg
	if u.needs_sea_room():
		_drop_stranded_waypoints(u)
	if not evading and not u.waypoints.is_empty():
		var wp: Vector2 = u.waypoints[0]
		var arrive := maxf(ARRIVAL_MIN_NM, Geo.knots_to_nm_per_s(u.speed_kn) * dt * 2.0)
		var inside_turn := u.position.distance_to(wp) > arrive and _passing_inside_turn(u, wp)
		if inside_turn and u.waypoints.size() == 1 and not u.patrol_active and _open_out(u, wp):
			pass  # the point is kept, and the leg out from it now leads
		elif u.position.distance_to(wp) <= arrive or inside_turn:
			u.waypoints.pop_front()
			# Only the corners of the circuit come round again: the way a hull was given round a
			# coast to reach its first corner is sailed once.
			if u.patrol_active and (u.station_route.is_empty() or u.station_route.has(wp)):
				u.waypoints.append(wp)
				u.patrol_legs_completed += 1
			if u.waypoints.is_empty():
				u.ordered_heading_deg = u.heading_deg
				if must_keep_flying(u):
					enter_hold(u, wp)  # a jet arriving with nowhere to go holds there
				else:
					u.ordered_speed_kn = 0.0
		if not u.waypoints.is_empty():
			desired = Geo.bearing_deg(u.position, u.waypoints[0])
			u.ordered_heading_deg = desired

	if not evading and must_keep_flying(u) and u.waypoints.is_empty() and u.ordered_speed_kn < u.spec.flight_speed("patrol") * 0.5:
		# Ordered to stop, or left with no speed by anything else: a fixed-wing aircraft holds.
		enter_hold(u, u.position)
		desired = Geo.bearing_deg(u.position, u.waypoints[0])
	if not evading:
		desired += _baffle_clearing_offset(u, dt)
	var max_turn := turn_rate_now(u) * dt
	var off_course := Geo.heading_delta(u.heading_deg, desired)
	var delta := clampf(off_course, -max_turn, max_turn)
	u.heading_deg = fposmod(u.heading_deg + delta, 360.0)

	var target_speed := clampf(u.ordered_speed_kn, 0.0, u.effective_max_speed())
	if must_keep_flying(u):
		# A wing stops flying long before it stops moving: no order holds a jet below this.
		target_speed = maxf(target_speed, minf(u.spec.flight_speed("patrol") * MIN_FLYING_FRACTION, u.effective_max_speed()))
	if evading:
		target_speed = u.effective_max_speed()
	else:
		target_speed = minf(target_speed, u.formation_speed_cap_kn)
	target_speed = minf(target_speed, TowedArray.speed_limit(u))
	target_speed = minf(target_speed, SubmarinePower.speed_limit(u))
	var max_dv := u.spec.accel_kn_s * dt
	u.speed_kn += clampf(target_speed - u.speed_kn, -max_dv, max_dv)

	var advance := Geo.heading_to_vector(u.heading_deg) * Geo.knots_to_nm_per_s(u.speed_kn) * dt
	if u.needs_sea_room():
		# The one guarantee that holds however the heading was chosen: by an order, by station
		# keeping, by a turn-away under fire. The step is projected along the shore rather than
		# refused outright, so a ship pressed onto a coast follows it instead of grinding at it.
		_step_in_sea_room(u, advance, target_speed, absf(off_course) > COAST_TURNING_DEG, dt)
	else:
		u.position += advance
	_step_depth(u, dt)
	_step_altitude(u, dt)


## One step of a hull that has to stay in the water. In open water it goes where it was heading.
## Against a coast the step is taken along the shore, and the hull's read-out follows what it
## actually did: its speed is the way it made, and meeting the shore at a slant it is turned along
## it, so a ship following a beach shows the course and speed she is making and one stopped by it
## shows none. Held without headway for COAST_BLOCKED_S on the heading she was told to steer, she
## stops and gives up the leg; the mark is left for UnitManager to report once. While she is still
## `coming_round` to that heading she is being worked off the shore, not blocked by it.
static func _step_in_sea_room(u: Unit, advance: Vector2, target_speed: float, coming_round: bool, dt: float) -> void:
	var wanted := u.position + advance
	var reached := Terrain.constrain_step(u.position, wanted)
	if reached == wanted:
		u.position = reached
		u.coast_blocked_s = 0.0
		if u.speed_kn >= 1.0:
			u.coast_blocked = false
		return
	var made := u.position.distance_to(reached)
	if made > 1e-9:
		var along := Geo.bearing_deg(u.position, reached)
		if absf(Geo.heading_delta(u.heading_deg, along)) <= COAST_TURN_MAX_DEG:
			u.heading_deg = along
	u.speed_kn = minf(u.speed_kn, made / maxf(dt, 1e-6) * 3600.0)
	u.position = reached
	if made >= Geo.knots_to_nm_per_s(target_speed) * dt * COAST_HEADWAY_FRACTION:
		u.coast_blocked_s = 0.0
		return
	# Held. The count starts at once, so that she can be twisted round; it runs on only while she
	# is pointing where she was told to go and the shore will not let her.
	u.coast_blocked_s = maxf(u.coast_blocked_s, dt) if coming_round else u.coast_blocked_s + dt
	if u.coast_blocked_s < COAST_BLOCKED_S or u.coast_blocked:
		return
	u.coast_blocked = true
	u.coast_blocked_s = 0.0
	u.waypoints.clear()
	u.nav_goal = Vector2.INF
	u.patrol_active = false
	u.ordered_heading_deg = u.heading_deg
	u.ordered_speed_kn = 0.0
	u.speed_kn = 0.0


## A hull cannot arrive at a waypoint that is on dry land, and without this it would steer at the
## beach for the rest of the scenario. Aircraft keep theirs: they overfly, and a land-based one is
## recovering to a field that is ashore on purpose.
static func _drop_stranded_waypoints(u: Unit) -> void:
	if Terrain.is_empty() or u.waypoints.is_empty():
		return
	var dropped := false
	while not u.waypoints.is_empty() and Terrain.is_land(u.waypoints[0]):
		u.waypoints.pop_front()
		dropped = true
	if dropped and u.waypoints.is_empty():
		u.patrol_active = false
		u.ordered_heading_deg = u.heading_deg
		u.ordered_speed_kn = 0.0


## Over land an aircraft keeps at least this much height above the highest ground under it and on
## the next minute or two of its track, whatever altitude it was ordered: a low run is flown over
## the sea, not through a hillside. GAMEPLAY_ESTIMATE.
const TERRAIN_CLEARANCE_FIXED_WING_M := 150.0
const TERRAIN_CLEARANCE_ROTARY_M := 60.0
const TERRAIN_LOOKAHEAD_S: Array[float] = [60.0, 120.0]


## Aircraft climb and descend at a fixed rate. Anything that cannot fly stays on the surface.
static func _step_altitude(u: Unit, dt: float) -> void:
	if u.spec.altitude_rate_m_s <= 0.0:
		u.altitude_m = 0.0
		return
	if not u.airborne():
		u.altitude_m = 0.0
		return
	var target := clampf(u.ordered_altitude_m, 0.0, u.spec.max_altitude_m)
	var ground := terrain_under(u)
	if ground > 0.0:
		var clearance := TERRAIN_CLEARANCE_ROTARY_M if u.spec.can_hover else TERRAIN_CLEARANCE_FIXED_WING_M
		target = maxf(target, minf(ground + clearance, u.spec.max_altitude_m))
	var step := u.spec.altitude_rate_m_s * dt
	u.altitude_m += clampf(target - u.altitude_m, -step, step)
	# Never below the ground itself, should the rate not have carried her over a crest in time.
	u.altitude_m = maxf(u.altitude_m, minf(Terrain.elevation_at(u.position), u.spec.max_altitude_m))


## The highest ground under an aircraft and along the next stretch of its track. Zero at sea.
static func terrain_under(u: Unit) -> float:
	if Terrain.is_empty():
		return 0.0
	var ground := Terrain.elevation_at(u.position)
	var along := Geo.heading_to_vector(u.heading_deg) * Geo.knots_to_nm_per_s(u.speed_kn)
	for seconds: float in TERRAIN_LOOKAHEAD_S:
		ground = maxf(ground, Terrain.elevation_at(u.position + along * seconds))
	return ground


## Boats change depth at a fixed rate. Anything that cannot submerge simply stays at zero. The
## floor is a hard limit whatever the order says: a boat that runs onto the shelf comes up with it.
static func _step_depth(u: Unit, dt: float) -> void:
	if u.spec.depth_rate_m_s <= 0.0:
		u.depth_m = 0.0
		return
	var target := clampf(u.ordered_depth_m, 0.0, Acoustics.max_operating_depth_m(u))
	var step := u.spec.depth_rate_m_s * dt
	u.depth_m += clampf(target - u.depth_m, -step, step)
	var floor_m := Acoustics.bottom_m(u)
	if floor_m >= 0.0:
		u.depth_m = minf(u.depth_m, maxf(floor_m - 5.0, 0.0))  # never through the floor
