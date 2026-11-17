extends TestCase
## Darkness for the lookouts, holds an airframe can fly, and signals that fit the chart.


func _ship(faction: String, at: Vector2) -> Unit:
	var u := Unit.new()
	u.spec = PlatformSpec.new()
	u.spec.mast_height_m = 25.0
	u.spec.max_speed_kn = 30.0
	u.faction = faction
	u.callsign = faction
	u.position = at
	u.health = 100.0
	u.radar_on = false
	return u


func _sighted(separation_nm: float) -> bool:
	Terrain.clear()
	var um := UnitManager.new()
	var tm := TrackManager.new()
	var sm := SensorManager.new()
	sm.unit_manager = um
	sm.track_manager = tm
	var own := _ship("BLUE", Vector2.ZERO)
	var other := _ship("RED", Vector2(0, separation_nm))
	um.add_unit(own)
	um.add_unit(other)
	sm._visual_pass(own, 1.0)
	var seen := tm.find_track("BLUE", other) != null
	sm.free()
	tm.free()
	um.free()
	return seen


func test_light_runs_from_day_through_twilight_to_night() -> void:
	Detection.set_environment({})
	assert_near(Detection.light, 1.0, 0.0001, "a scenario that sets no sun is fought in daylight")
	Detection.set_sun_elevation(20.0)
	assert_near(Detection.visual_light_factor(), 1.0, 0.0001, "sun up")
	assert_eq(Detection.light_name(), "day")
	Detection.set_sun_elevation(-6.0)
	assert_near(Detection.light, 0.5, 0.0001, "half way through nautical twilight")
	assert_eq(Detection.light_name(), "twilight")
	Detection.set_sun_elevation(-30.0)
	assert_near(Detection.visual_light_factor(), Detection.NIGHT_VISUAL_FACTOR, 0.0001, "night")
	assert_eq(Detection.light_name(), "night")
	Detection.set_environment({})
	assert_near(Detection.light, 1.0, 0.0001, "a new environment starts in daylight again")


func test_a_lookout_recognises_a_ship_at_four_miles_by_day_and_not_by_night() -> void:
	Detection.set_environment({"visibility_nm": 12.0})
	assert_true(_sighted(4.0), "by day, inside six miles")
	Detection.set_sun_elevation(-30.0)
	assert_true(not _sighted(4.0), "at night four miles is past what the eye can recognise")
	assert_true(_sighted(1.5), "close aboard it still can")
	Detection.set_environment({"visibility_nm": 1.0})
	assert_true(not _sighted(1.5), "and by day, fog still caps it")
	Detection.set_environment({})


func test_the_simulation_sets_the_light_from_its_clock_and_chart() -> void:
	SimClock.set_paused(true)
	var sim := Simulation.new()
	sim.seed_override = 31
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	assert_true(sim.load_scenario("res://data/scenarios/cold_war_03_carrier.json"), "loads")
	var chart: Dictionary = sim.scenario.get("map", {})
	var sun := WorldPresentation.sun_angles(float(SimClock.start_unix_time), float(chart.get("anchor_lat", 60.0)), float(chart.get("anchor_lon", 0.0)))
	var expected := clampf(1.0 - sun.x / Detection.NIGHT_SUN_ELEVATION_DEG, 0.0, 1.0)
	assert_near(Detection.light, expected, 0.0001, "known at the first second, sun at %.1f degrees" % sun.x)
	SimClock.advance(3600.0)
	var later := WorldPresentation.sun_angles(float(SimClock.start_unix_time) + 3600.0, float(chart.get("anchor_lat", 60.0)), float(chart.get("anchor_lon", 0.0)))
	assert_near(Detection.light, clampf(1.0 - later.x / Detection.NIGHT_SUN_ELEVATION_DEG, 0.0, 1.0), 0.02, "and follows the hour")
	sim.unit_manager.clear()
	sim.queue_free()
	sim.free()
	Detection.set_environment({})
	Terrain.clear()


func test_a_hold_is_wide_enough_for_the_airframe_that_flies_it() -> void:
	var fighter := Movement.hold_size_nm(DataDB.platform("usn_fighter_fa18e"))
	assert_near(fighter.x, Movement.HOLD_WIDTH_NM, 0.0001, "a fighter keeps the standard racetrack")
	assert_near(fighter.y, Movement.HOLD_LEG_NM, 0.0001)
	for id: String in ["usn_mpa_p8a", "rfn_bomber_tu22m3", "rfn_mpa_tu142"]:
		var spec := DataDB.platform(id)
		var size := Movement.hold_size_nm(spec)
		var diameter := 2.0 * Geo.knots_to_nm_per_s(spec.flight_speed("patrol")) / deg_to_rad(spec.turn_rate_deg_s)
		assert_true(size.x >= diameter, "%s: %.1f nm wide for a %.1f nm turn" % [id, size.x, diameter])
		# It flies the pattern it was given: every corner is reached, none written off.
		var u := Unit.new()
		u.spec = spec
		u.flight_state = Unit.FlightState.AIRBORNE
		u.altitude_m = 6000.0
		u.ordered_altitude_m = 6000.0
		u.fuel_s = 99999.0
		u.speed_kn = spec.flight_speed("patrol")
		Movement.enter_hold(u, Vector2.ZERO)
		var corners := u.waypoints.duplicate()
		var nearest := [INF, INF, INF, INF]
		for i in 4 * 3600:
			Movement.step(u, 0.25)
			for c in 4:
				nearest[c] = minf(nearest[c], u.position.distance_to(corners[c]))
		for c in 4:
			assert_true(nearest[c] < 0.6, "%s passes corner %d of its hold (closest %.2f nm)" % [id, c, nearest[c]])


func test_a_long_signal_wraps_between_words() -> void:
	var font := ThemeDB.fallback_font
	var text := "TASKING UPDATE: a patrol aircraft reports a cruiser near the northern box, accuracy about fifteen miles, and the reserve strike is being readied on deck"
	var rows := TacticalMap.wrap_radio_text(font, text, 14, 400.0)
	assert_true(rows.size() > 1, "more than one row")
	for row: String in rows:
		assert_true(font.get_string_size(row, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x <= 400.0, "each row fits: %s" % row)
	assert_eq(" ".join(rows), text, "nothing lost or reordered")
	assert_eq(TacticalMap.wrap_radio_text(font, "Aye", 14, 400.0), PackedStringArray(["Aye"]), "a short signal is one row")
