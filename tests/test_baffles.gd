extends TestCase
## A hull sonar is deaf astern. These pin the arc, who has it, and the habit that answers it.


func _sonar(array_depth := 0.0, hover := false) -> SensorSpec:
	var s := SensorSpec.new()
	s.kind = "sonar"
	s.passive_sensitivity_nm = 30.0
	s.active_range_nm = 12.0
	s.self_noise_tolerance = 0.8
	s.array_depth_m = array_depth
	s.requires_hover = hover
	return s


func _boat(faction: String, at: Vector2, heading := 0.0) -> Unit:
	var u := Unit.new()
	u.spec = PlatformSpec.new()
	u.spec.domain = "subsurface"
	u.spec.max_speed_kn = 20.0
	u.spec.cruise_speed_kn = 6.0
	u.spec.turn_rate_deg_s = 3.0
	u.spec.accel_kn_s = 0.5
	u.spec.max_depth_m = 300.0
	u.spec.depth_rate_m_s = 2.0
	u.spec.acoustic_signature = 1.0
	u.faction = faction
	u.position = at
	u.heading_deg = heading
	u.ordered_heading_deg = heading
	u.speed_kn = 6.0
	u.ordered_speed_kn = 6.0
	u.depth_m = 100.0
	u.ordered_depth_m = 100.0
	u.health = 50.0
	return u


func _before() -> void:
	Terrain.clear()
	Detection.set_environment({})


func test_a_hull_sonar_hears_nothing_in_the_arc_astern() -> void:
	_before()
	var listener := _boat("BLUE", Vector2.ZERO, 0.0)
	var hull := _sonar()
	listener.sensors.append(hull)
	var ahead := _boat("RED", Vector2(0, 5))
	var abeam := _boat("RED", Vector2(5, 0))
	var astern := _boat("RED", Vector2(0, -5))
	var quarter := _boat("RED", Vector2(5.0 * sin(deg_to_rad(145.0)), 5.0 * cos(deg_to_rad(145.0))))
	assert_true(Detection.passive_sonar_range_nm(listener, hull, ahead) > 5.0, "heard ahead")
	assert_true(Detection.passive_sonar_range_nm(listener, hull, abeam) > 5.0, "heard abeam")
	assert_near(Detection.passive_sonar_range_nm(listener, hull, astern), 0.0, 1e-6, "not heard dead astern")
	assert_true(Detection.passive_sonar_range_nm(listener, hull, quarter) > 5.0, "heard on the quarter, 35 degrees off the stern")
	listener.active_sonar_on = true
	assert_true(Detection.active_sonar_reach_nm(listener, ahead) > 5.0, "a ping comes back from ahead")
	assert_near(Detection.active_sonar_reach_nm(listener, astern), 0.0, 1e-6, "and not from astern")
	assert_true(Detection.active_sonar_sensor_for(listener, astern) == null, "no set is credited with it")
	# Turning the boat moves the arc with it.
	listener.heading_deg = 90.0
	assert_true(Detection.passive_sonar_range_nm(listener, hull, astern) > 5.0, "after a turn, what was astern is on the beam and heard")
	assert_near(Detection.passive_sonar_range_nm(listener, hull, _boat("RED", Vector2(-5, 0))), 0.0, 1e-6, "and the arc now lies to the west")


func test_a_streamed_array_and_a_dipping_set_have_no_baffles() -> void:
	_before()
	var ship := _boat("BLUE", Vector2.ZERO)
	ship.spec.domain = "surface"
	ship.depth_m = 0.0
	assert_true(Detection.has_baffles(ship, _sonar()), "a hull set has")
	assert_true(not Detection.has_baffles(ship, _sonar(150.0)), "a towed or variable-depth array has not")
	assert_true(not Detection.has_baffles(ship, _sonar(100.0, true)), "nor a dipping set")
	var boat := _boat("BLUE", Vector2.ZERO)
	boat.sensors.append(_sonar())
	assert_true(Detection.deaf_astern(boat), "a boat with only a hull suite has no ears astern, which the chart shows")


func test_a_pinger_in_the_baffles_is_not_heard_either() -> void:
	_before()
	var listener := _boat("BLUE", Vector2(0, 20), 0.0)
	listener.sensors.append(_sonar())
	var pinger := _boat("RED", Vector2.ZERO)
	pinger.sensors.append(_sonar())
	pinger.active_sonar_on = true
	assert_near(Detection.active_sonar_detection_nm(listener, pinger), 0.0, 1e-6, "dead astern")
	listener.heading_deg = 180.0
	assert_true(Detection.active_sonar_detection_nm(listener, pinger) > 20.0, "bows on, it carries")


func test_a_boat_clearing_its_baffles_hears_what_was_astern_and_keeps_its_route() -> void:
	_before()
	var boat := _boat("BLUE", Vector2.ZERO, 0.0)
	var hull := _sonar()
	boat.sensors.append(hull)
	boat.waypoints.assign([Vector2(0, 60)])
	boat.baffle_clear_interval_s = 900.0
	var trailer := _boat("RED", Vector2(0, -4))
	var heard_s := 0.0
	var worst_off := 0.0
	var t := 0.0
	while t < 1800.0:
		Movement.step(boat, 0.25)
		trailer.position = boat.position + Vector2(0, -4)  # holds station dead astern of the route
		if Detection.passive_sonar_range_nm(boat, hull, trailer) > 4.0:
			heard_s += 0.25
		worst_off = maxf(worst_off, absf(boat.position.x))
		t += 0.25
	assert_true(heard_s > 150.0, "two clearing turns in half an hour give the trailer away for %.0f s" % heard_s)
	assert_true(heard_s < 600.0, "and for most of it he is still unheard")
	assert_true(worst_off < 0.5, "the doglegs stay within half a mile of the track (%.2f nm)" % worst_off)
	assert_eq(boat.waypoints.size(), 1, "and the route is as ordered")
	# No habit, no turn: he is never heard.
	var steady := _boat("BLUE", Vector2.ZERO, 0.0)
	steady.sensors.append(hull)
	steady.waypoints.assign([Vector2(0, 60)])
	heard_s = 0.0
	t = 0.0
	while t < 1800.0:
		Movement.step(steady, 0.25)
		trailer.position = steady.position + Vector2(0, -4)
		if Detection.passive_sonar_range_nm(steady, hull, trailer) > 4.0:
			heard_s += 0.25
		t += 0.25
	assert_near(heard_s, 0.0, 0.01, "a boat on a steady course never hears the one in its baffles")
