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


func _geometry_report(u: Unit, origin: Vector2, at: Vector2, key: String, accuracy := 0.3) -> SensorContact:
	var c := _bearing(u, origin + (at - origin).normalized() * 20.0)
	c.bearing_origin = origin
	c.bearing_key = key
	c.error_axis_deg = Geo.bearing_deg(origin, at)
	c.bearing_accuracy_deg = accuracy
	c.bearing_range_limit_nm = 100.0
	return c


func test_stationary_and_constant_speed_observers_have_no_passive_range_solution() -> void:
	var target := _target()
	for moving in [false, true]:
		var tm := TrackManager.new()
		for second in range(0, 901, 10):
			var origin := Vector2(float(second) / 180.0, 0.0) if moving else Vector2.ZERO
			var at := Vector2(1.0 + float(second) / 360.0, 15.0)
			tm.observe_contact("BLUE", _geometry_report(target, origin, at, "listener"), second, 1.0)
		var track := tm.find_track("BLUE", target)
		assert_true(track.is_bearing_only(), "unknown target velocity prevents range from a straight observer track")
		assert_near(track.tma_quality, 0.0)
		tm.free()


func test_real_observer_manoeuvre_resolves_moving_target_from_bearings() -> void:
	var target := _target()
	var tm := TrackManager.new()
	var at := Vector2.ZERO
	for second in range(0, 601, 10):
		var origin := Vector2(float(second) / 120.0, 0.0) if second <= 300 else Vector2(2.5, float(second - 300) / 120.0)
		at = Vector2(1.0 + float(second) / 360.0, 15.0)
		tm.observe_contact("BLUE", _geometry_report(target, origin, at, "listener", 0.1), second, 1.0)
	var track := tm.find_track("BLUE", target)
	assert_true(not track.is_bearing_only(), "a useful two-leg own track makes constant target motion observable")
	assert_true(track.tma_quality >= 0.6)
	assert_true(track.position.distance_to(at) < 0.5, "solution derived from recorded geometry follows the moving target")
	assert_true(track.class_is_probable == false, "short observation gain alone does not give a class")
	tm.free()


func test_crossed_bearings_resolve_but_coincident_or_collinear_buoys_do_not() -> void:
	var target := _target()
	for second_origin in [Vector2(0.0, 0.0), Vector2(0.0, 2.0), Vector2(8.0, 0.0)]:
		var tm := TrackManager.new()
		var at := Vector2(0.0, 8.0)
		tm.observe_contact("BLUE", _geometry_report(target, Vector2.ZERO, at, "buoy:1"), 10.0, 1.0)
		tm.observe_contact("BLUE", _geometry_report(target, second_origin, at, "buoy:2"), 10.0, 1.0)
		var t := tm.find_track("BLUE", target)
		if second_origin.x > 1.0:
			assert_true(not t.is_bearing_only(), "independent crossing lines produce an estimated fix")
			assert_true(t.position.distance_to(at) < 0.01)
			assert_true(t.position_error_nm < 1.0)
		else:
			assert_true(t.is_bearing_only(), "extra buoy count without geometry does not measure range")
		tm.free()


func test_signature_class_affiliation_and_name_are_separate_evidence() -> void:
	var target := _target()
	target.spec.id = "known_frigate"
	target.callsign = "Secret Hull Name"
	var tm := TrackManager.new()
	for second in 1200:
		var c := _geometry_report(target, Vector2.ZERO, Vector2(0, 12), "listener")
		tm.observe_contact("BLUE", c, float(second), 1.0)
	var t := tm.find_track("BLUE", target)
	assert_eq(t.classification, Track.Classification.CLASS_KNOWN)
	assert_true(t.class_is_probable)
	assert_eq(t.identity, "UNKNOWN", "probable acoustic type is not affiliation")
	assert_eq(t.known_callsign, "", "no amount of listening discloses a callsign")
	tm.configure_recognition({"BLUE": {"known_frigate": "HOSTILE"}, "RED": {"known_frigate": "FRIENDLY"}})
	tm.observe_contact("BLUE", _geometry_report(target, Vector2.ZERO, Vector2(0, 12), "listener"), 1201.0, 1.0)
	assert_eq(t.identity, "HOSTILE", "authored intelligence correlates the observed signature")
	assert_eq(t.identity_evidence, "Scenario recognition brief")
	assert_eq(t.known_callsign, "")
	var visual := SensorContact.make(target, Vector2(0, 12), 0.1, 1.0, 1.0, 2.0, "visual")
	visual.visual_identification = true
	tm.observe_contact("BLUE", visual, 1202.0, 1.0)
	assert_eq(t.classification, Track.Classification.IDENTIFIED)
	assert_eq(t.known_callsign, "Secret Hull Name")
	assert_true(not t.class_is_probable)
	tm.free()


func test_serialized_bearing_history_continues_identically() -> void:
	var target := _target()
	var history := []
	for second in range(0, 301, 10):
		var origin := Vector2(float(second) / 120.0, 0.0)
		BearingSolution.add(history, _geometry_report(target, origin, Vector2(1.0 + float(second) / 360.0, 15.0), "listener", 0.1), second)
	var saved_track := Track.new()
	saved_track.bearing_history = history
	var refs := SimSnapshot.Refs.new()
	var fields := SimSnapshot.fields_of(saved_track, SimSnapshot.TRACK_SKIP, refs)
	var loaded_track := Track.new()
	SimSnapshot._fill(loaded_track, bytes_to_var(var_to_bytes(fields)), refs)
	var resumed := loaded_track.bearing_history
	for second in range(310, 601, 10):
		var origin := Vector2(2.5, float(second - 300) / 120.0)
		var c := _geometry_report(target, origin, Vector2(1.0 + float(second) / 360.0, 15.0), "listener", 0.1)
		BearingSolution.add(history, c, second)
		BearingSolution.add(resumed, c, second)
	assert_true(not BearingSolution.estimate(history, 600.0).is_empty(), "the continued manoeuvre resolves range")
	assert_eq(var_to_bytes(BearingSolution.estimate(history, 600.0)), var_to_bytes(BearingSolution.estimate(resumed, 600.0)), "save-compatible measurement data reproduces the same solution")


func test_realistic_bearing_precision_resolves_a_close_contact_after_useful_baseline() -> void:
	var history := []
	var target := _target()
	var rng := RandomNumberGenerator.new()
	rng.seed = 73
	for second in range(0, 901, 10):
		var origin := Vector2(float(second) / 120.0, 0.0) if second <= 450 else Vector2(3.75, float(second - 450) / 120.0)
		var at := Vector2(1.0 + float(second) / 360.0, 6.0)
		var c := _geometry_report(target, origin, at, "listener", 0.8)
		c.error_axis_deg += rng.randfn(0.0, 0.8)
		BearingSolution.add(history, c, second)
	var solution := BearingSolution.estimate(history, 900.0)
	assert_true(not solution.is_empty(), "a useful baseline resolves a close contact at shipped sonar precision")
	if not solution.is_empty():
		assert_true((solution["position"] as Vector2).distance_to(Vector2(3.5, 6.0)) <= float(solution["major"]), "true location lies within the reported uncertainty for this seeded measurement history")


func test_distant_incoming_weapon_does_not_disclose_its_launcher() -> void:
	var observer := _target()
	observer.faction = "BLUE"
	observer.position = Vector2.ZERO
	var target := _target()
	target.position = Vector2(0, 20)
	var tm := TrackManager.new()
	var c := SensorContact.make(target, target.position, 0.3, 1.0, 1.0, 20.0, "radar", observer)
	tm.observe_contact("BLUE", c, 10.0, 1.0)
	var w := Weapon.new()
	w.shooter = target
	w.position = Vector2(0, 5)
	w.heading_deg = 180.0
	w.time_alive_s = 120.0
	tm.observe_hostile_launch(observer, w, 10.0)
	assert_eq(tm.find_track("BLUE", target).identity, "UNKNOWN", "seeing an old incoming missile cannot reveal hidden launch origin")
	w.time_alive_s = 1.0
	w.position = Vector2(0, 19.9)
	tm.observe_hostile_launch(observer, w, 10.0)
	assert_eq(tm.find_track("BLUE", target).identity, "HOSTILE", "a freshly observed launch from a held position toward us is hostile evidence")
	assert_eq(tm.find_track("BLUE", target).identity_evidence, "Observed hostile launch")
	tm.free()


func test_snapshot_preserves_the_partial_ten_second_solution_update_cycle() -> void:
	var target := _target()
	target.id = 91
	var tm := TrackManager.new()
	for second in range(10, 14):
		for pair in [[Vector2.ZERO, "a"], [Vector2(8, 0), "b"]]:
			tm.observe_contact("BLUE", _geometry_report(target, pair[0], Vector2(0, 8), pair[1]), second, 1.0)
	var t := tm.find_track("BLUE", target)
	assert_eq(t.bearing_solution_at, 10.0, "snapshot is three seconds into the solution update cycle")
	assert_true(not t.bearing_solution_cache.is_empty())
	var refs := SimSnapshot.Refs.new()
	refs.units_by_id[target.id] = target
	var saved := SimSnapshot.fields_of(t, SimSnapshot.TRACK_SKIP, refs)
	var loaded := Track.new()
	SimSnapshot._fill(loaded, bytes_to_var(var_to_bytes(saved)), refs)
	var resumed := TrackManager.new()
	resumed._tracks = {"BLUE": [loaded]}
	resumed._by_target = {"BLUE": {target: loaded}}
	for second in range(14, 24):
		for pair in [[Vector2.ZERO, "a"], [Vector2(8, 0), "b"]]:
			var c := _geometry_report(target, pair[0], Vector2(0, 8), pair[1])
			tm.observe_contact("BLUE", c, second, 1.0)
			resumed.observe_contact("BLUE", c, second, 1.0)
	var uninterrupted := var_to_bytes(SimSnapshot.fields_of(t, SimSnapshot.TRACK_SKIP, refs))
	var continued := var_to_bytes(SimSnapshot.fields_of(loaded, SimSnapshot.TRACK_SKIP, refs))
	assert_eq(uninterrupted, continued, "cached estimate, phase and next recomputation survive an actual reflective snapshot")
	tm.free()
	resumed.free()
