extends TestCase

const DT := 0.25


func _make(speed: float, heading := 0.0) -> Unit:
	var spec := PlatformSpec.new()
	spec.max_speed_kn = 30.0
	spec.cruise_speed_kn = 15.0
	spec.turn_rate_deg_s = 3.0
	spec.accel_kn_s = 0.25
	var u := Unit.new()
	u.spec = spec
	u.speed_kn = speed
	u.ordered_speed_kn = speed
	u.heading_deg = heading
	u.ordered_heading_deg = heading
	return u


func _run(u: Unit, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		Movement.step(u, DT)
		t += DT


func test_straight_north() -> void:
	var u := _make(10.0, 0.0)
	_run(u, 3600.0)
	assert_near(u.position.y, 10.0, 0.01, "10 kn for 1 h = 10 nm north (float32 drift ok)")
	assert_near(u.position.x, 0.0, 0.01)


func test_straight_east() -> void:
	var u := _make(20.0, 90.0)
	_run(u, 1800.0)
	assert_near(u.position.x, 10.0, 1e-3, "20 kn for 30 min = 10 nm east")


func test_turn_rate() -> void:
	var u := _make(10.0, 0.0)
	u.apply_order(Order.set_course(90.0))
	_run(u, 10.0)
	assert_near(u.heading_deg, 30.0, 1e-3, "3 deg/s for 10 s")
	_run(u, 60.0)
	assert_near(u.heading_deg, 90.0, 1e-3, "settles on ordered course")


func test_shortest_turn() -> void:
	var u := _make(10.0, 350.0)
	u.apply_order(Order.set_course(10.0))
	_run(u, 5.0)
	assert_near(u.heading_deg, 5.0, 1e-3, "turns through north, not the long way")


func test_speed_clamp_and_accel() -> void:
	var u := _make(0.0)
	u.apply_order(Order.set_speed(999.0))
	assert_near(u.ordered_speed_kn, 30.0, 1e-6, "clamped to max")
	_run(u, 20.0)
	assert_near(u.speed_kn, 5.0, 1e-3, "0.25 kn/s for 20 s")


func test_waypoint_arrival_stops() -> void:
	var u := _make(0.0, 0.0)
	u.apply_order(Order.move(Vector2(0.0, 5.0)))
	assert_near(u.ordered_speed_kn, 15.0, 1e-6, "MOVE from stop uses cruise speed")
	_run(u, 3600.0)
	assert_true(u.waypoints.is_empty(), "waypoint consumed")
	assert_near(u.position.y, 5.0, 0.3, "stops near waypoint")
	assert_near(u.speed_kn, 0.0, 1e-3, "all stop after final waypoint")


func test_waypoint_append() -> void:
	var u := _make(10.0, 0.0)
	u.apply_order(Order.move(Vector2(0.0, 5.0)))
	u.apply_order(Order.move(Vector2(5.0, 5.0), true))
	assert_eq(u.waypoints.size(), 2)
	u.apply_order(Order.move(Vector2(9.0, 9.0)))
	assert_eq(u.waypoints.size(), 1, "non-append replaces route")
