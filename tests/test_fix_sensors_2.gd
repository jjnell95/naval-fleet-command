extends TestCase
## The sensor cycle does only the work that can change what is reported: a sonar pair out of every
## reach and a lookout pair beyond any look are let go before their models run, a unit that never
## leaves the link files each report once, in the shared plot, and the whole cycle shows in the
## profiler. What it reports is unchanged (tests/test_sensor_cycle.gd compares every track against
## the pair-by-pair reference); these tests pin the work and the cases the shortcuts must respect.

const HORMUZ := "res://data/scenarios/gulf_01_hormuz.json"


func _world(units: Array) -> Array:
	Terrain.load_from({})
	Detection.set_environment({"sea_state": 2})
	var um := UnitManager.new()
	ScenarioLoader.populate(um, {"units": units})
	var tm := TrackManager.new()
	tm.neutral_factions = PackedStringArray(["NEUTRAL"])
	var sm := SensorManager.new()
	sm.unit_manager = um
	sm.track_manager = tm
	sm.rng.seed = 77
	return [um, tm, sm]


func _free(world: Array) -> void:
	(world[0] as UnitManager).clear()
	for i in range(world.size() - 1, -1, -1):
		(world[i] as Node).free()
	Detection.set_environment({})


func _named(um: UnitManager, callsign: String) -> Unit:
	for u: Unit in um.units:
		if u.callsign == callsign:
			return u
	return null


## A destroyer listening, one ship eight miles off, and a squadron far over the horizon.
func _far_squadron() -> Array:
	var units: Array = [
		{"platform": "usn_ddg_burke_iii", "callsign": "Burke", "faction": "BLUE", "position_nm": [0, 0], "heading_deg": 90, "speed_kn": 10},
		{"platform": "pla_ddg_type055", "callsign": "Near", "faction": "RED", "position_nm": [8, 2], "heading_deg": 270, "speed_kn": 18},
	]
	for i in 8:
		units.append({"platform": "pla_ddg_type055", "callsign": "Far%d" % i, "faction": "RED", "position_nm": [220 + 10 * i, 40], "heading_deg": 270, "speed_kn": 20})
	return _world(units)


func test_a_sonar_pair_out_of_every_reach_never_runs_the_acoustic_model() -> void:
	var world := _far_squadron()
	var sm: SensorManager = world[2]
	var tm: TrackManager = world[1]
	for second in 3:
		sm.run_cycle(float(second))
	# The two near ships weigh each other each cycle, and nobody weighs any of the eight far ones,
	# being far beyond anything that could be heard.
	assert_true(sm.sonar_pairs_weighed <= 3 * 2, "only the close pairs reach the acoustic model (%d over three cycles)" % sm.sonar_pairs_weighed)
	assert_true(tm.find_track("BLUE", _named(world[0], "Near")) != null, "the ship eight miles off is still heard")
	_free(world)


## A pair let go before the model must still sample the sea floor under both ends, as the model
## would have, or the sample a unit carries (and so every later acoustic figure) would depend on
## which pairs were weighed.
func test_a_far_pair_still_samples_the_floor_as_the_model_would() -> void:
	var samples: Array = []
	for reference in [true, false]:
		var world := _far_squadron()
		var sm: SensorManager = world[2]
		sm.reference_path = reference
		var um: UnitManager = world[0]
		for second in 4:
			for u: Unit in um.units:
				if u.callsign.begins_with("Far"):
					u.position += Vector2(-0.7, 0.0)
			sm.run_cycle(float(second))
		var seen: Array = []
		for u: Unit in um.units:
			seen.append([u.callsign, u.bottom_sampled_at, u.bottom_generation])
		samples.append(seen)
		_free(world)
	assert_eq(samples[1], samples[0], "every unit's floor sample is taken on the same cycles, pair by pair or not")


func test_the_lookout_weighs_only_what_is_inside_the_longest_look() -> void:
	var world := _far_squadron()
	var sm: SensorManager = world[2]
	var was_profiling := Debug.profiling
	Debug.profiling = true
	Debug.timings.clear()
	for second in 3:
		sm.run_cycle(float(second))
	assert_eq(sm.lookout_pairs_weighed, 0, "nothing on the surface is within six miles of anyone")
	for path in ["sensors/setup", "sensors/visual", "sensors/radar", "sensors/sonar", "sensors/esm"]:
		assert_true(Debug.timings.has(path), "the profiler shows %s" % path)
	Debug.profiling = was_profiling
	Debug.timings.clear()
	_free(world)


func test_a_lookout_still_recognises_a_ship_alongside() -> void:
	var world := _world([
		{"platform": "usn_ddg_burke_iii", "callsign": "Burke", "faction": "BLUE", "position_nm": [0, 0], "heading_deg": 90, "speed_kn": 10},
		{"platform": "pla_ddg_type055", "callsign": "Close", "faction": "RED", "position_nm": [2, 0], "heading_deg": 270, "speed_kn": 10},
		{"platform": "pla_ddg_type055", "callsign": "Off", "faction": "RED", "position_nm": [40, 0], "heading_deg": 270, "speed_kn": 10},
	])
	var sm: SensorManager = world[2]
	var tm: TrackManager = world[1]
	sm.run_cycle(0.0)
	var close := tm.find_track("BLUE", _named(world[0], "Close"))
	assert_true(close != null and close.class_evidence == "Visual recognition", "the ship two miles off is recognised by eye")
	assert_eq(sm.lookout_pairs_weighed, 2, "one look each way between the two ships in sight, none at the one forty miles off")
	_free(world)


func test_a_unit_always_on_the_link_files_each_report_once() -> void:
	var world := _world([
		{"platform": "usn_ddg_burke_iii", "callsign": "Burke", "faction": "BLUE", "position_nm": [0, 0], "heading_deg": 90, "speed_kn": 10},
		{"platform": "usn_ssn_virginia", "callsign": "Virginia", "faction": "BLUE", "position_nm": [10, -6], "heading_deg": 0, "speed_kn": 5, "depth_m": 15},
		{"platform": "pla_ddg_type055", "callsign": "Nanchang", "faction": "RED", "position_nm": [20, 0], "heading_deg": 270, "speed_kn": 16},
	])
	var um: UnitManager = world[0]
	var tm: TrackManager = world[1]
	var sm: SensorManager = world[2]
	var burke := _named(um, "Burke")
	var boat := _named(um, "Virginia")
	sm.run_cycle(0.0)
	assert_true(not TrackManager.keeps_own_picture(burke), "a destroyer on the link never needs a picture of her own")
	assert_true(TrackManager.keeps_own_picture(boat), "a boat may dive off the link, and keeps hers")
	assert_true(not tm._local_keys.has(burke), "no private copy of the destroyer's reports")
	assert_true(tm._local_keys.has(boat), "the boat's own picture is still kept")
	var held := tm.find_for(burke, _named(um, "Nanchang"))
	assert_true(held != null and held.networked and held.contributors.has(burke), "the destroyer reads her contact on the shared plot")
	assert_eq(tm.tracks_for(burke), tm.get_tracks("BLUE"), "her picture is the shared plot")
	_free(world)


## Launch attribution needs the watching unit itself to hold the launcher firmly and freshly. A unit
## with no picture of its own is judged on its own last measured plot in the shared one.
func test_a_linked_ship_still_attributes_a_launch_it_watched() -> void:
	var world := _world([
		{"platform": "usn_ddg_burke_iii", "callsign": "Burke", "faction": "BLUE", "position_nm": [0, 0], "heading_deg": 90, "speed_kn": 10},
		{"platform": "pla_ddg_type055", "callsign": "Nanchang", "faction": "RED", "position_nm": [20, 0], "heading_deg": 270, "speed_kn": 16},
	])
	var um: UnitManager = world[0]
	var tm: TrackManager = world[1]
	var sm: SensorManager = world[2]
	var burke := _named(um, "Burke")
	var shooter := _named(um, "Nanchang")
	sm.run_cycle(10.0)
	var t := tm.find_track("BLUE", shooter)
	assert_true(t != null and not t.is_bearing_only() and t.firm_looks.has(burke), "the destroyer's radar holds the launcher")
	var w := Weapon.new()
	w.shooter = shooter
	w.position = shooter.position + Vector2(-0.2, 0.0)
	w.heading_deg = 270.0
	w.time_alive_s = 1.0
	tm.observe_hostile_launch(burke, w, 13.0)
	assert_eq(t.identity, "UNKNOWN", "a look three seconds old is not watching the launch")
	tm.observe_hostile_launch(burke, w, 11.0)
	assert_eq(t.identity, "HOSTILE", "a launch watched on her own fresh radar plot is hostile evidence")
	assert_eq(t.identity_evidence, "Observed hostile launch")
	_free(world)


## The cost of the cycle in a fixed seeded battle, counted as work done rather than timed: a gross
## regression (every pair weighed again, every report filed twice) fails here on any machine.
func test_the_sensor_cycle_work_in_a_seeded_battle_stays_bounded() -> void:
	SimClock.set_paused(true)
	var sim := Simulation.new()
	sim.seed_override = 45
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	assert_true(sim.load_scenario(HORMUZ), HORMUZ)
	sim.ai_plays_player = true
	sim._build_ai()
	SimClock.advance(120.0)
	var sm := sim.sensor_manager
	var tm := sim.track_manager
	var sonar0 := sm.sonar_pairs_weighed
	var lookout0 := sm.lookout_pairs_weighed
	var filed0 := tm.picture_filings
	var opposing := 0
	SimClock.advance(180.0)
	var units := sim.unit_manager.units
	for a: Unit in units:
		for b: Unit in units:
			if a.is_engageable() and b.is_engageable() and a.faction != b.faction:
				opposing += 1
	var cycles := 180.0
	var sonar := (sm.sonar_pairs_weighed - sonar0) / cycles
	var lookout := (sm.lookout_pairs_weighed - lookout0) / cycles
	var filed := (tm.picture_filings - filed0) / cycles
	print("    hormuz: %d opposing pairs; per cycle %.1f sonar pairs weighed, %.1f lookout pairs, %.1f reports filed" % [opposing, sonar, lookout, filed])
	assert_true(opposing > 200, "the battle has plenty of pairs to weigh (%d)" % opposing)
	assert_true(sonar <= 0.05 * opposing, "sonar pairs weighed per cycle (%.1f) stay a small share of the %d pairs" % [sonar, opposing])
	assert_true(lookout <= 0.05 * opposing, "lookout pairs weighed per cycle (%.1f) stay a small share of the %d pairs" % [lookout, opposing])
	assert_true(filed <= 45.0, "reports filed per cycle (%.1f) stay near one per report" % filed)
	sim.unit_manager.clear()
	sim.get_parent().remove_child(sim)
	sim.free()
