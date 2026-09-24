extends TestCase


func _target() -> Unit:
	var u := Unit.new()
	u.spec = PlatformSpec.new()
	u.spec.short_name = "TEST"
	u.faction = "RED"
	return u


func _bearing(u: Unit, pos: Vector2) -> SensorContact:
	var c := SensorContact.make(u, pos, 8.0, 0.5, 1.0, 20.0, "sonar_passive")
	c.bearing_only = true
	c.error_minor_nm = 0.4
	return c


func test_unobserved_death_does_not_reveal_itself_by_dropping_the_track() -> void:
	var tm := TrackManager.new()
	var live := _target()
	var dead := _target()
	tm.observe("BLUE", live, Vector2(10, 0), 0.5, 1.0, 0.0, 1.0, 10.0)
	tm.observe("BLUE", dead, Vector2(10, 0), 0.5, 1.0, 0.0, 1.0, 10.0)
	dead.alive = false
	tm.tick(120.0, 120.0)
	assert_eq(tm.get_tracks("BLUE").size(), 2, "both contacts must coast on the same evidence")
	var a := tm.find_track("BLUE", live)
	var b := tm.find_track("BLUE", dead)
	if a != null and b != null:
		assert_eq(a.status, b.status)
		assert_near(a.position_error_nm, b.position_error_nm)
	tm.tick(1801.0, 1681.0)
	assert_eq(tm.get_tracks("BLUE").size(), 0, "both expire after the same observation timeout")
	tm.free()


func test_firm_fix_after_a_bearing_is_independent_of_sensor_order() -> void:
	var u := _target()
	var firm := SensorContact.make(u, Vector2(0, 20), 0.3, 0.5, 1.0, 20.0)
	var bearing := _bearing(u, Vector2(6, 40))
	var a := TrackManager.new()
	var b := TrackManager.new()
	a.observe_contact("BLUE", firm, 10.0, 1.0)
	a.observe_contact("BLUE", bearing, 10.0, 1.0)
	b.observe_contact("BLUE", bearing, 10.0, 1.0)
	b.observe_contact("BLUE", firm, 10.0, 1.0)
	var first := a.find_track("BLUE", u)
	var second := b.find_track("BLUE", u)
	assert_near(first.position.distance_to(second.position), 0.0, 0.001, "a range guess must not contaminate a measured fix")
	assert_near(second.position.distance_to(firm.position), 0.0, 0.001)
	assert_eq(second._obs_pos.size(), 1)
	assert_near(second._obs_pos[0].distance_to(firm.position), 0.0, 0.001, "velocity fit must use the best observation")
	a.free()
	b.free()


func test_less_precise_sensor_cannot_overwrite_a_better_fix() -> void:
	var tm := TrackManager.new()
	var u := _target()
	tm.observe_contact("BLUE", SensorContact.make(u, Vector2(0, 20), 0.2, 0.5, 1.0, 20.0), 1.0, 1.0)
	tm.observe_contact("BLUE", SensorContact.make(u, Vector2(3, 24), 2.0, 0.5, 1.0, 24.0), 1.0, 1.0)
	var t := tm.find_track("BLUE", u)
	assert_near(t.position.distance_to(Vector2(0, 20)), 0.0, 0.001)
	assert_near(t.position_error_nm, 0.2)
	assert_near(t.observation_time_s, 1.0, 0.001, "multiple sensors do not create extra elapsed observation time")
	tm.free()


func test_reacquisition_resets_stale_course_and_speed() -> void:
	var tm := TrackManager.new()
	var u := _target()
	for i in range(1, 70):
		tm.observe("BLUE", u, Vector2(float(i) / 360.0, 0), 0.5, 1.0, float(i), 1.0, 10.0)
	var t := tm.find_track("BLUE", u)
	assert_true(t.has_kinematics)
	tm.tick(200.0, 131.0)
	tm.observe("BLUE", u, Vector2(0, 10), 0.5, 1.0, 201.0, 1.0, 10.0)
	assert_true(not t.has_kinematics, "do not derive a teleport velocity across an unobserved manoeuvre")
	assert_near(t.position.distance_to(Vector2(0, 10)), 0.0, 0.001, "reacquired fix replaces the coasted estimate")
	tm.free()
