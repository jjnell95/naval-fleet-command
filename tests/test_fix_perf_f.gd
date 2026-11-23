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
## holds once for each moment it files them at, not once for every listener that reports: the
## work a cycle no longer grows with the square of the listeners, and the fix is as good.
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
	assert_true(whole <= 20, "twenty cycles of two dozen lines crossed %d times, at most once a cycle" % whole)
	# Spread over the ticks of the second, the lines filed in each tick are crossed once.
	before = tm.bearing_solutions_worked
	for second in range(40, 50):
		for quarter in SensorManager.SLICES:
			sm.run_slice(float(second) + 0.25 * quarter)
	var sliced := tm.bearing_solutions_worked - before
	miss = track.position.distance_to(emitter.position)
	assert_true(not track.is_bearing_only() and miss <= maxf(track.position_error_nm, 0.5), "still fixed, %.2f nm off inside %.2f nm" % [miss, track.position_error_nm])
	assert_true(sliced <= 10 * SensorManager.SLICES, "ten seconds in slices crossed %d times, at most once a tick" % sliced)
	_free(world)
