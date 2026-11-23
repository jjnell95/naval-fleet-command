extends TestCase
## The simulation tick's cost in a large engagement: crossing the bearings of a contact many
## listeners hear, the defence step, and the measuring harness's forced autosave. The costs are
## pinned by the work done (solutions worked, rounds weighed, reports filed) rather than by the
## clock, so a busy machine cannot fail them; the times themselves are printed.


func _world(units: Array) -> Array:
	Terrain.load_from({})
	Detection.set_environment({"sea_state": 2})
	var um := UnitManager.new()
	ScenarioLoader.populate(um, {"units": units})
	var tm := TrackManager.new()
	var sm := SensorManager.new()
	sm.unit_manager = um
	sm.track_manager = tm
	sm.rng.seed = 31
	return [um, tm, sm]


func _free(world: Array) -> void:
	(world[0] as UnitManager).clear()
	for i in range(world.size() - 1, -1, -1):
		(world[i] as Node).free()
	Detection.set_environment({})


## A ring of destroyers, radars off, listening to one patrol aircraft's radar in the middle.
func _ring_round_an_emitter(listeners: int, radius_nm: float) -> Array:
	var units: Array = [{"platform": "rfn_mpa_il38n", "callsign": "Emitter", "faction": "RED", "position_nm": [0, 0], "heading_deg": 90, "speed_kn": 300}]
	for i in listeners:
		var at := Vector2.from_angle(TAU * i / listeners) * radius_nm
		units.append({"platform": "usn_ddg_burke_iii", "callsign": "Ear%d" % i, "faction": "BLUE", "position_nm": [at.x, at.y], "heading_deg": 0, "speed_kn": 12, "radar_on": false})
	return _world(units)


## Two dozen listeners each file a line on one aircraft every cycle. The plot crosses the lines it
## holds at the first line of each moment and again once half the listeners have filed since, not
## once for every listener that reports: the work a cycle no longer grows with the square of the
## listeners, and the fix is as good.
func test_lines_filed_together_are_crossed_once_a_look() -> void:
	var world := _ring_round_an_emitter(24, 45.0)
	var um: UnitManager = world[0]
	var tm: TrackManager = world[1]
	var sm: SensorManager = world[2]
	var emitter: Unit = um.units[0]
	for second in 20:
		sm.run_cycle(float(second))
	var before := tm.bearing_solutions_worked
	for second in range(20, 40):
		sm.run_cycle(float(second))
	var whole := tm.bearing_solutions_worked - before
	var track := tm.find_track("BLUE", emitter)
	assert_true(track != null and not track.is_bearing_only() and track.contributors.size() == 24, "every listener hears it and the crossed lines fix it")
	var miss := track.position.distance_to(emitter.position)
	assert_true(miss <= maxf(track.position_error_nm, 0.5), "the fix is %.2f nm from the aircraft, inside its %.2f nm ellipse" % [miss, track.position_error_nm])
	assert_true(whole <= 20 * 2, "twenty cycles of two dozen lines crossed %d times, at most twice a cycle" % whole)
	# Spread over the ticks of the second, the lines filed in each tick are crossed once, and once
	# more when half the listeners have filed since.
	before = tm.bearing_solutions_worked
	for second in range(40, 50):
		for quarter in SensorManager.SLICES:
			sm.run_slice(float(second) + 0.25 * quarter)
	var sliced := tm.bearing_solutions_worked - before
	miss = track.position.distance_to(emitter.position)
	assert_true(not track.is_bearing_only() and miss <= maxf(track.position_error_nm, 0.5), "still fixed, %.2f nm off inside %.2f nm" % [miss, track.position_error_nm])
	assert_true(sliced <= 10 * (SensorManager.SLICES + 2), "ten seconds in slices crossed %d times, about once a tick" % sliced)
	_free(world)


## A measuring run started at a scenario, as the dev harness starts one, never passes the briefing.
## The autosave its --perf-autosave flag forces is written all the same, into the harness's own
## folder, so the sample measures the frames an autosave costs; one that cannot be written says why.
func test_a_forced_autosave_in_a_harness_run_is_written() -> void:
	var saved_root := SaveGame.root_override
	var scratch := "user://test-perf-autosave-%d" % Time.get_ticks_usec()
	var root := (Engine.get_main_loop() as SceneTree).root
	var main: Main = preload("res://scenes/main/Main.tscn").instantiate()
	root.add_child(main)
	main.simulation.seed_override = 2
	main.start_scenario("res://data/scenarios/pacific_02_taiwan_strait.json")
	SimClock.set_paused(true)
	SimClock.advance(30.0)
	assert_true(main.save_refusal() != "", "a scenario nobody has taken command of is not saved")
	var harness := DevHarness.new(main)
	harness.prepare_forced_autosave(scratch)
	SaveGame.force_next_autosave = true
	main._autosave_if_due()
	assert_eq(harness.forced_autosave_result(), "", "the forced autosave is written")
	var saves := SaveGame.list_saves()
	assert_true(saves.size() == 1 and str(saves[0].get("path", "")).begins_with(scratch), "into the harness's folder (%s)" % [saves])
	# One that cannot be taken is reported with the reason.
	main.simulation.mission_manager.result = MissionManager.Result.VICTORY
	SaveGame.force_next_autosave = true
	main._autosave_if_due()
	assert_eq(harness.forced_autosave_result(), "The engagement has ended", "the reason it was not written")
	for save in saves:
		SaveGame.remove(str(save["path"]))
	DirAccess.remove_absolute(scratch)
	SaveGame.root_override = saved_root
	main.free()
