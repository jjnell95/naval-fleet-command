extends TestCase
## The sensor cycle's cost: filing a bearing on something many listeners hear, the passes that
## let pairs beyond any horizon go, the cycle spread over the ticks of a second, a large fleet's
## tick and the autosave's frame. What the cycle reports is pinned by tests/test_sensor_cycle.gd
## and the seeded comparisons; these tests pin the cost and the cases the shortcuts must respect.


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


## A ring of destroyers listening to one patrol aircraft's radar in the middle.
func _ring_round_an_emitter(listeners: int, radius_nm: float) -> Array:
	var units: Array = [{"platform": "rfn_mpa_il38n", "callsign": "Emitter", "faction": "RED", "position_nm": [0, 0], "heading_deg": 90, "speed_kn": 300}]
	for i in listeners:
		var at := Vector2.from_angle(TAU * i / listeners) * radius_nm
		units.append({"platform": "usn_ddg_burke_iii", "callsign": "Ear%d" % i, "faction": "BLUE", "position_nm": [at.x, at.y], "heading_deg": 0, "speed_kn": 12, "radar_on": false})
	return _world(units)


## The lines the plot crossed before, copied one by one: every report of the last two seconds in a
## sample begun in the last twenty, each line as smoothed.
func _copied_current(history: Array, now: float) -> Array:
	var current := []
	for i in range(history.size() - 1, -1, -1):
		var report: Dictionary = history[i]
		if now - float(report.get("sample_start", report["time"])) > BearingSolution.SAMPLE_INTERVAL_S * 2.0:
			break
		if now - float(report["time"]) <= 2.0:
			current.push_front({"key": report["key"], "origin": report["origin"], "bearing": report.get("smooth", report["bearing"]),
				"time": report["time"], "sigma": report["sigma"], "limit": report["limit"], "speed_limit": report.get("speed_limit", BearingSolution.SHIP_SPEED_LIMIT_KN)})
	return current


## Something that may be an aircraft is fixed by the lines taken together, reworked at every look.
## The fix, worked on the history where it stands, is the general fit of copies of those lines to
## the last bit, through listeners joining, falling silent, samples rolling over and poor geometry.
func test_a_crossed_fix_is_the_fit_of_the_lines_taken_together() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var history: Array = []
	var latest := {}
	var target := Vector2(5.0, 8.0)
	var compared := 0
	var fixed := 0
	for second in 400:
		var now := float(second)
		target += Vector2(0.12, -0.05)
		for listener in 12:
			if rng.randf() < 0.3:
				continue
			var origin := Vector2.from_angle(TAU * listener / 12.0) * (30.0 + 4.0 * listener) + Vector2(rng.randf_range(-0.2, 0.2), 0.0)
			var c := SensorContact.new()
			c.bearing_key = "unit:%d:esm" % listener
			c.bearing_origin = origin
			c.error_axis_deg = Geo.bearing_deg(origin, target) + rng.randfn(0.0, 2.0)
			c.bearing_accuracy_deg = 2.0
			c.bearing_range_limit_nm = 400.0
			c.bearing_speed_limit_kn = 1200.0
			BearingSolution.add(history, c, now, latest)
			var fast := BearingSolution.estimate(history, now, 1200.0)
			var current := _copied_current(history, now)
			var expected := {}
			if current.size() >= 2:
				var good := false
				for i in current.size():
					for j in range(i + 1, current.size()):
						var a: Dictionary = current[i]
						var b: Dictionary = current[j]
						if a["key"] != b["key"] and (a["origin"] as Vector2).distance_to(b["origin"]) >= BearingSolution.MIN_BASELINE_NM and absf(sin(deg_to_rad(float(a["bearing"]) - float(b["bearing"])))) >= BearingSolution.MIN_CROSSING_SINE:
							good = true
				if good:
					expected = BearingSolution._fit(current, float(current[-1]["time"]), false)
			compared += 1
			if not expected.is_empty():
				fixed += 1
			if var_to_bytes(fast) != var_to_bytes(expected):
				assert_eq(fast, expected, "the same fix at %.0f s after listener %d" % [now, listener])
				return
	assert_true(compared > 3000 and fixed > compared / 2, "most looks were crossed into a fix (%d of %d)" % [fixed, compared])


## A look inside a listener's open sample updates that sample where it stands, with its fields in
## the same order as a new sample's, so a save of the history is the same as before.
func test_a_look_in_an_open_sample_updates_it_in_place() -> void:
	var history: Array = []
	var latest := {}
	var c := SensorContact.new()
	c.bearing_key = "unit:1:esm"
	c.bearing_origin = Vector2(1.0, 2.0)
	c.error_axis_deg = 40.0
	c.bearing_accuracy_deg = 1.0
	var first := BearingSolution.add(history, c, 100.0, latest)
	c.error_axis_deg = 42.0
	c.bearing_origin = Vector2(1.1, 2.0)
	var second := BearingSolution.add(history, c, 101.0, latest)
	assert_true(is_same(first, second) and history.size() == 1, "the look joins the sample it falls in")
	assert_eq(second.keys(), ["key", "origin", "bearing", "sigma", "limit", "speed_limit", "time", "smooth", "n", "mean_bearing", "mean_origin", "mean_time", "sample_start"], "in the sample's own field order")
	assert_near(float(second["mean_bearing"]), 41.0, 1e-9, "the sample's mean takes the new look")
	assert_near(float(second["time"]), 101.0, 1e-9, "and its time")
	assert_near(float(second["smooth"]), 40.5, 1e-9, "and the drawn line moves a quarter of the way")
	assert_eq(int(second["n"]), 2, "two looks")


## Two dozen listeners hearing one aircraft's radar each file an intercept every cycle, and each one
## reworks the crossed fix from all two dozen lines. An intercept cost 180 us on the plot as it was;
## the best of three runs of twenty cycles must come in under 150.
func test_an_aircraft_heard_by_many_listeners_is_filed_cheaply() -> void:
	var world := _ring_round_an_emitter(24, 45.0)
	var um: UnitManager = world[0]
	var tm: TrackManager = world[1]
	var sm: SensorManager = world[2]
	var emitter: Unit = um.units[0]
	assert_true(emitter.in_flight() and emitter.radar_emitting(), "the aircraft is up and transmitting")
	for second in 20:
		sm.run_cycle(float(second))
	var best := INF
	var second := 20
	for run in 3:
		Debug.profiling = true
		Debug.timings.clear()
		for cycle in 20:
			sm.run_cycle(float(second))
			second += 1
		Debug.profiling = false
		best = minf(best, float(Debug.timings.get("sensors/esm", 0)) / (20.0 * 24.0))
	Debug.timings.clear()
	var track := tm.find_track("BLUE", emitter)
	print("    an intercept on an aircraft two dozen listeners hear: %.1f us" % best)
	assert_true(track != null and not track.is_bearing_only() and track.contributors.size() == 24, "every listener hears it and the crossed lines fix it")
	assert_true(best < 150.0, "an intercept costs %.1f us, under 150" % best)
	_free(world)
