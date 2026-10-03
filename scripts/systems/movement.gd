class_name Movement
## Kinematics on simulation ticks. Pure functions over Unit state; no rendering, no nodes.

const ARRIVAL_MIN_NM := 0.1
const FULL_TURN_SPEED_KN := 5.0  # GAMEPLAY_ESTIMATE: below this, rudder authority scales down
## A fixed-wing aircraft with nowhere to go flies a racetrack through the point it was sent to
## rather than stopping in the air. GAMEPLAY_ESTIMATE dimensions.
const HOLD_LEG_NM := 6.0
const HOLD_WIDTH_NM := 3.0


## Whether this unit is a fixed-wing aircraft in normal flight: it cannot stop, hover or park.
static func must_keep_flying(u: Unit) -> bool:
	return u.is_aircraft() and not u.spec.can_hover and u.flight_state == Unit.FlightState.AIRBORNE


## A holding racetrack that starts and ends at `center`, its long legs along `heading_deg`. It ends
## where it began, so arriving at the last point simply lays the same pattern again: no state.
static func hold_pattern(center: Vector2, heading_deg: float) -> Array[Vector2]:
	var along := Geo.heading_to_vector(heading_deg)
	var right := Geo.heading_to_vector(heading_deg + 90.0)
	return [center + along * HOLD_LEG_NM, center + along * HOLD_LEG_NM + right * HOLD_WIDTH_NM, center + right * HOLD_WIDTH_NM, center]


## Puts a fixed-wing aircraft into a hold at `center` at its economical patrol speed.
static func enter_hold(u: Unit, center: Vector2) -> void:
	u.waypoints.assign(hold_pattern(center, u.heading_deg))
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
	var evading := u.evasion_remaining_s > 0.0
	var desired := u.evasion_course_deg if evading else u.ordered_heading_deg
	if u.needs_sea_room():
		_drop_stranded_waypoints(u)
	if not evading and not u.waypoints.is_empty():
		var wp: Vector2 = u.waypoints[0]
		var arrive := maxf(ARRIVAL_MIN_NM, Geo.knots_to_nm_per_s(u.speed_kn) * dt * 2.0)
		if u.position.distance_to(wp) <= arrive:
			u.waypoints.pop_front()
			if u.patrol_active:
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
	var turn_scale := clampf(u.speed_kn / FULL_TURN_SPEED_KN, 0.0, 1.0)
	var rate := u.spec.turn_rate_deg_s * turn_scale
	if u.needs_sea_room() and u.spec.length_m > 0:
		# GAMEPLAY_ESTIMATE: a displacement hull needs a turning circle proportional to
		# its length. The catalogue rate is a ceiling, not a pivot rate at every speed.
		var radius_m := u.spec.length_m * (1.5 if u.is_submarine() else 2.5)
		rate = minf(rate, rad_to_deg(u.speed_kn * 1852.0 / 3600.0 / radius_m))
	var max_turn := rate * dt
	var delta := clampf(Geo.heading_delta(u.heading_deg, desired), -max_turn, max_turn)
	u.heading_deg = fposmod(u.heading_deg + delta, 360.0)

	var target_speed := clampf(u.ordered_speed_kn, 0.0, u.effective_max_speed())
	if evading:
		target_speed = u.effective_max_speed()
	else:
		target_speed = minf(target_speed, u.formation_speed_cap_kn)
	target_speed = minf(target_speed, TowedArray.speed_limit(u))
	var max_dv := u.spec.accel_kn_s * dt
	u.speed_kn += clampf(target_speed - u.speed_kn, -max_dv, max_dv)

	var advance := Geo.heading_to_vector(u.heading_deg) * Geo.knots_to_nm_per_s(u.speed_kn) * dt
	if u.needs_sea_room():
		# The one guarantee that holds however the heading was chosen: by an order, by station
		# keeping, by a turn-away under fire. The step is projected along the shore rather than
		# refused outright, so a ship pressed onto a coast follows it instead of grinding at it.
		u.position = Terrain.constrain_step(u.position, u.position + advance)
	else:
		u.position += advance
	_step_depth(u, dt)
	_step_altitude(u, dt)


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


## Aircraft climb and descend at a fixed rate. Anything that cannot fly stays on the surface.
static func _step_altitude(u: Unit, dt: float) -> void:
	if u.spec.altitude_rate_m_s <= 0.0:
		u.altitude_m = 0.0
		return
	if not u.airborne():
		u.altitude_m = 0.0
		return
	var target := clampf(u.ordered_altitude_m, 0.0, u.spec.max_altitude_m)
	var step := u.spec.altitude_rate_m_s * dt
	u.altitude_m += clampf(target - u.altitude_m, -step, step)


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
