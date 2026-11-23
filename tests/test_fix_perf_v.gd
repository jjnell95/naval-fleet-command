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


## ESM time per intercept over twenty cycles of a ring of listeners round one aircraft.
func _esm_per_intercept_us(world: Array, listeners: int, start: int) -> float:
	var sm: SensorManager = world[2]
	Debug.profiling = true
	Debug.timings.clear()
	for cycle in 20:
		sm.run_cycle(float(start + cycle))
	Debug.profiling = false
	var spent := float(Debug.timings.get("sensors/esm", 0)) / (20.0 * listeners)
	Debug.timings.clear()
	return spent


## Two dozen listeners hearing one aircraft's radar each file an intercept every cycle. Each one
## used to rework the crossed fix from every line, so an intercept cost more the more listeners
## heard the contact: 1.7 times as much with two dozen as with six on the plot as it was, 1.4
## once the fix read the history in place. Filed cheaply, an intercept costs the same however many
## hear it. The two rings are timed in turn, best of five each, so a busy machine slows both alike.
func test_an_aircraft_heard_by_many_listeners_is_filed_cheaply() -> void:
	var many := _ring_round_an_emitter(24, 45.0)
	var few := _ring_round_an_emitter(6, 45.0)
	var emitter: Unit = (many[0] as UnitManager).units[0]
	assert_true(emitter.in_flight() and emitter.radar_emitting(), "the aircraft is up and transmitting")
	for second in 20:
		(many[2] as SensorManager).run_cycle(float(second))
		(few[2] as SensorManager).run_cycle(float(second))
	var best_many := INF
	var best_few := INF
	var second := 20
	for run in 5:
		best_many = minf(best_many, _esm_per_intercept_us(many, 24, second))
		best_few = minf(best_few, _esm_per_intercept_us(few, 6, second))
		second += 20
	var track := (many[1] as TrackManager).find_track("BLUE", emitter)
	print("    an intercept on an aircraft two dozen listeners hear: %.1f us; six hear: %.1f us" % [best_many, best_few])
	assert_true(track != null and not track.is_bearing_only() and track.contributors.size() == 24, "every listener hears it and the crossed lines fix it")
	assert_true(best_many <= 1.2 * best_few, "an intercept two dozen listeners share costs %.1f us against %.1f us for six, within a fifth" % [best_many, best_few])
	_free(few)
	_free(many)


const TAIWAN := "res://data/scenarios/pacific_02_taiwan_strait.json"


func _battle(path: String, seed: int) -> Simulation:
	SimClock.set_paused(true)
	var sim := Simulation.new()
	sim.seed_override = seed
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	assert_true(sim.load_scenario(path), path)
	sim.ai_plays_player = true
	sim._build_ai()
	return sim


func _end(sim: Simulation) -> void:
	sim.unit_manager.clear()
	sim.get_parent().remove_child(sim)
	sim.free()


## The reports each quarter of the second files, from 100 s of play: where the cycle once landed
## whole in one tick and the other three filed nothing, every quarter files part of it and none
## more than three fifths.
func _quarters(sim: Simulation, ticks: int) -> PackedInt32Array:
	var by := PackedInt32Array([0, 0, 0, 0])
	for i in ticks:
		var before := sim.track_manager.picture_filings
		var quarter := int(round(fposmod(SimClock.sim_time, 1.0) / 0.25)) % 4
		SimClock.advance(0.25)
		by[quarter] += sim.track_manager.picture_filings - before
	return by


func _spread(by: PackedInt32Array) -> String:
	var total := 0
	for n in by:
		total += n
	for n in by:
		if n < total / 20 or n > total * 3 / 5:
			return "reports by quarter %s" % by
	return ""


## At one times a second the sensor cycle is spread over the four ticks of its second, so no one
## tick carries it all. A contact several observers hold in different ticks is still one look a
## cycle: its classification grows by a cycle's worth each second, not four.
func test_the_sensor_cycle_is_spread_over_the_ticks_of_its_second() -> void:
	var sim := _battle(TAIWAN, 2)
	SimClock.advance(300.0)
	var by := _quarters(sim, 400)
	print("    Taiwan Strait: reports filed by quarter of the second %s" % by)
	assert_eq(_spread(by), "", "every quarter of the second files part of the cycle")
	_end(sim)


## A contact held by observers that look in different ticks of the second is merged once a cycle:
## its classification time grows by one cycle's worth a second, as when they all looked at once.
func test_a_contact_held_across_the_ticks_of_a_second_is_one_look_a_cycle() -> void:
	var world := _ring_round_an_emitter(24, 30.0)
	var um: UnitManager = world[0]
	var tm: TrackManager = world[1]
	var sm: SensorManager = world[2]
	var emitter: Unit = um.units[0]
	for second in 30:
		for quarter in SensorManager.SLICES:
			sm.run_slice(float(second) + 0.25 * quarter)
	var t := tm.find_track("BLUE", emitter)
	var spread := t.observation_time_s
	var looked := t.contributors.size()
	var dealt_over := not (sm._plan[1] as PackedInt32Array).is_empty()
	_free(world)
	world = _ring_round_an_emitter(24, 30.0)
	tm = world[1]
	sm = world[2]
	emitter = (world[0] as UnitManager).units[0]
	for second in 30:
		sm.run_cycle(float(second))
	var whole := tm.find_track("BLUE", emitter).observation_time_s
	_free(world)
	assert_eq(looked, 24, "all two dozen listeners hear it")
	assert_true(dealt_over, "and they look in more than one tick of the second")
	assert_true(whole > 0.0 and absf(spread - whole) <= whole * 0.05, "classification time %.1f s spread over the ticks against %.1f s in whole cycles" % [spread, whole])


## The workshop's 48-a-side recipe on a coast: two carriers, 48 ships and four boats a side, the
## carriers' air wings, AI on both sides. Written where load_scenario can read it.
const FLEET_RECIPE := {"aircraft_per_carrier": 16, "blue_carriers": 2, "blue_ships": 48, "blue_subs": 4, "coastlines": true,
	"extent_nm": 300, "red_carriers": 2, "red_ships": 48, "red_subs": 4, "region": 0, "seed": 29, "year": 2027}


func _fleet() -> Simulation:
	var path := "user://perf-fleet48-%d.json" % OS.get_process_id()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(ScenarioWorkshop.generate(FLEET_RECIPE)))
	file.close()
	var sim := _battle(path, 2)
	DirAccess.remove_absolute(path)
	return sim


## An entity's saved fields are what encoding every one of them gives, plain values and all, and
## the variable list read once for its script is the one its property list gives.
func test_a_capture_stores_every_field_as_its_encoding_would() -> void:
	var sim := _battle(TAIWAN, 2)
	SimClock.advance(240.0)
	var refs := SimSnapshot.Refs.new()
	var checked := 0
	var objects: Array = []
	objects.append_array(sim.unit_manager.units)
	for key in sim.track_manager._tracks:
		objects.append_array(sim.track_manager._tracks[key])
	for obj: Object in objects:
		var listed := PackedStringArray()
		for p: Dictionary in obj.get_property_list():
			if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				listed.append(str(p["name"]))
		assert_eq(SimSnapshot.script_variables(obj), listed, "the variables of %s" % obj)
		var skip := SimSnapshot.UNIT_SKIP if obj is Unit else SimSnapshot.TRACK_SKIP
		var expected := {}
		var reference := SimSnapshot.Refs.new()
		for name in listed:
			if not skip.has(name):
				expected[name] = reference.enc(obj.get(name))
		if var_to_bytes(SimSnapshot.fields_of(obj, skip, refs)) != var_to_bytes(expected):
			assert_eq(SimSnapshot.fields_of(obj, skip, SimSnapshot.Refs.new()), expected, "the fields of %s" % obj)
			break
		checked += 1
	assert_true(checked > 50, "units and tracks compared (%d)" % checked)
	_end(sim)


## What the capture did before it read each script's variable list once and stored plain values
## as they are: the property list of every unit and track walked, and every field encoded. Timed in
## the same process at the same moment as the capture, it is the yardstick a busy machine cannot
## move: both slow alike.
func _generic_encoding_ms(sim: Simulation) -> float:
	var at := Time.get_ticks_usec()
	var refs := SimSnapshot.Refs.new()
	var objects: Array = []
	objects.append_array(sim.unit_manager.units)
	for key in sim.track_manager._tracks:
		objects.append_array(sim.track_manager._tracks[key])
	var out: Array = []
	for obj: Object in objects:
		var fields := {}
		for p: Dictionary in obj.get_property_list():
			if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				fields[p["name"]] = refs.enc(obj.get(p["name"]))
		out.append(fields)
	return float(Time.get_ticks_usec() - at) / 1000.0


## The frame an autosave is taken in holds only the capture, and the capture of a 48-a-side fleet a
## hundred seconds in costs well under what walking and encoding its units and tracks the generic
## way does (the whole capture took more than that walk before; about a third of it now). Encoding,
## compression and the file all follow off the main thread where there are threads.
func test_an_autosave_holds_one_frame_only_for_a_quick_capture() -> void:
	var sim := _fleet()
	SimClock.advance(100.0)
	var best := INF
	var yardstick := INF
	var snapshot := {}
	for attempt in 3:
		var at := Time.get_ticks_usec()
		snapshot = sim.capture_snapshot()
		best = minf(best, float(Time.get_ticks_usec() - at) / 1000.0)
		yardstick = minf(yardstick, _generic_encoding_ms(sim))
	assert_true((snapshot.get("errors", ["?"]) as Array).is_empty(), "the capture is whole")
	var scratch := "user://test-perf-saves-%d" % OS.get_process_id()
	SaveGame.root_override = scratch
	var threads := SaveGame.use_worker
	SaveGame.use_worker = true
	var job := SaveGame.begin_autosave({"label": "test"}, {"simulation": snapshot, "presentation": {"journal": [{"text": "a"}]}})
	var at := Time.get_ticks_usec()
	job.step()
	var first_step := float(Time.get_ticks_usec() - at) / 1000.0
	var reference_at := Time.get_ticks_usec()
	var _bytes := var_to_bytes(snapshot)
	var encoding := float(Time.get_ticks_usec() - reference_at) / 1000.0
	assert_eq(SaveGame.finish_writing(), "", "the autosave is written")
	var back := SaveGame.read(job.path)
	assert_eq(back.get("error", "?"), "", "and reads back")
	assert_true(var_to_bytes(back.get("payload", {}).get("simulation", {})) == var_to_bytes(snapshot), "as the engagement captured")
	SaveGame.remove(job.path)
	SaveGame.use_worker = threads
	SaveGame.root_override = ""
	DirAccess.remove_absolute(scratch)
	print("    48-a-side fleet at 100 s: capture %.1f ms against %.1f ms for the generic walk; the autosave's next frame %.1f ms, encoding the snapshot %.1f ms" % [best, yardstick, first_step, encoding])
	assert_true(best <= 0.6 * yardstick, "the capture takes %.1f ms, under three fifths of the generic walk's %.1f ms" % [best, yardstick])
	assert_true(first_step <= 0.5 * encoding, "the frame after it hands the encoding on (%.1f ms against %.1f ms to encode it)" % [first_step, encoding])
	_end(sim)


## Two minutes of the 48-a-side fleet with AI on both sides, tick by tick. Before the cycle was
## spread, every fourth tick carried it whole and filed every report, and took more than ten times
## as long on average as the other three. Now every quarter of the second files part of the cycle,
## and the dearest quarter of the second costs on average within three times the cheapest (about
## twice on a quiet machine). A mean over two minutes of one quarter against another's, both timed
## in the same run, holds on a machine shared with other work, where one tick's time does not; the
## figures are printed.
func test_a_48_a_side_fleet_keeps_every_tick_short() -> void:
	var sim := _fleet()
	var tm := sim.track_manager
	var ticks := PackedFloat64Array()
	var by := PackedInt32Array([0, 0, 0, 0])
	for i in 480:
		var before := tm.picture_filings
		var quarter := i % 4
		var at := Time.get_ticks_usec()
		SimClock.advance(0.25)
		ticks.append(float(Time.get_ticks_usec() - at) / 1000.0)
		by[quarter] += tm.picture_filings - before
	var sorted := ticks.duplicate()
	sorted.sort()
	var total := 0.0
	for ms in ticks:
		total += ms
	var mean := total / ticks.size()
	var median := sorted[sorted.size() / 2]
	var p95 := sorted[int(sorted.size() * 0.95)]
	var p99 := sorted[int(sorted.size() * 0.99)]
	var by_quarter := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	for i in ticks.size():
		by_quarter[i % 4] += ticks[i] / (ticks.size() / 4.0)
	var dearest := 0.0
	var cheapest := INF
	for ms in by_quarter:
		dearest = maxf(dearest, ms)
		cheapest = minf(cheapest, ms)
	print("    48-a-side fleet, 120 s: tick mean %.1f ms, median %.1f, p95 %.1f, p99 %.1f, max %.1f; mean by quarter of the second %.1f %.1f %.1f %.1f ms; reports by quarter %s" % [
		mean, median, p95, p99, sorted[-1], by_quarter[0], by_quarter[1], by_quarter[2], by_quarter[3], by])
	assert_eq(_spread(by), "", "every quarter of the second files part of the cycle")
	assert_true(dearest <= 3.0 * cheapest, "the dearest quarter of the second (%.1f ms a tick) is within three times the cheapest (%.1f ms)" % [dearest, cheapest])
	_end(sim)


## A cycle with little to do is not spread: each slice works out every unit's figures afresh, which
## costs more than it saves. A handful of ships runs its whole cycle in the first tick of the second.
func test_a_small_cycle_runs_whole_in_its_first_slice() -> void:
	var world := _ring_round_an_emitter(4, 30.0)
	var tm: TrackManager = world[1]
	var sm: SensorManager = world[2]
	var by := PackedInt32Array([0, 0, 0, 0])
	for second in 10:
		for quarter in SensorManager.SLICES:
			var before := tm.picture_filings
			sm.run_slice(float(second) + 0.25 * quarter)
			by[quarter] += tm.picture_filings - before
	_free(world)
	assert_true(by[0] > 0 and by[1] == 0 and by[2] == 0 and by[3] == 0, "every report in the first slice (%s)" % by)
