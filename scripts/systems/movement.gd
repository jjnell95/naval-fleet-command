class_name Movement
## Kinematics on simulation ticks. Pure functions over Unit state; no rendering, no nodes.

const ARRIVAL_MIN_NM := 0.1
const FULL_TURN_SPEED_KN := 5.0  # GAMEPLAY_ESTIMATE: below this, rudder authority scales down


static func step(u: Unit, dt: float) -> void:
	if u.is_aircraft() and not u.airborne():
		# Sitting in a hangar: it goes where its parent goes and does nothing of its own.
		if u.home != null:
			u.position = u.home.position
			u.heading_deg = u.home.heading_deg
		u.speed_kn = 0.0
		u.altitude_m = 0.0
		return
	var desired := u.ordered_heading_deg
	if u.needs_sea_room():
		_drop_stranded_waypoints(u)
	if not u.waypoints.is_empty():
		var wp: Vector2 = u.waypoints[0]
		var arrive := maxf(ARRIVAL_MIN_NM, Geo.knots_to_nm_per_s(u.speed_kn) * dt * 2.0)
		if u.position.distance_to(wp) <= arrive:
			u.waypoints.pop_front()
			if u.waypoints.is_empty():
				u.ordered_heading_deg = u.heading_deg
				u.ordered_speed_kn = 0.0
		if not u.waypoints.is_empty():
			desired = Geo.bearing_deg(u.position, u.waypoints[0])
			u.ordered_heading_deg = desired

	var turn_scale := clampf(u.speed_kn / FULL_TURN_SPEED_KN, 0.0, 1.0)
	var max_turn := u.spec.turn_rate_deg_s * turn_scale * dt
	var delta := clampf(Geo.heading_delta(u.heading_deg, desired), -max_turn, max_turn)
	u.heading_deg = fposmod(u.heading_deg + delta, 360.0)

	var target_speed := clampf(u.ordered_speed_kn, 0.0, u.effective_max_speed())
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


## Boats change depth at a fixed rate. Anything that cannot submerge simply stays at zero.
static func _step_depth(u: Unit, dt: float) -> void:
	if u.spec.depth_rate_m_s <= 0.0:
		u.depth_m = 0.0
		return
	var target := clampf(u.ordered_depth_m, 0.0, u.spec.max_depth_m)
	var step := u.spec.depth_rate_m_s * dt
	u.depth_m += clampf(target - u.depth_m, -step, step)
