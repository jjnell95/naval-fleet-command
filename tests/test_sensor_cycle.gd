extends TestCase
## The sensor cycle that works out each unit's figures once per cycle must leave every track picture
## exactly as the original pair-by-pair cycle does: the same reports, in the same order, from the
## same random draws. Each test runs one world twice, once down each path, and compares every
## field of every track in every picture (positions, error ellipses, classification, contributors,
## ages, history), the random stream, and in the battles the whole saved engagement, with the
## optimised run saved and restored half way: nothing it works out outlives a cycle, so a restored
## engagement must carry on exactly as an uninterrupted one.

const HORMUZ := "res://data/scenarios/gulf_01_hormuz.json"
const TARTUS := "res://data/scenarios/med_01_tartus.json"
const ISLAND := {"id": "isle", "name": "Isle", "elevation_m": 300.0, "points_nm": [[8, -6], [16, -6], [16, 6], [8, 6]]}


## Everything the radar, ESM and sonar passes treat differently, on one chart: aircraft at height
## with a jammer among them, a hovering dipping helicopter, ships and a shore battery either side
## of a hill, a boat that drops off the network as it goes deep, a merchant that was never on it,
## damaged sets, radars switched off and on, a ping, and a loss part way through.
func _world() -> Array:
	Terrain.load_from({"terrain": {"land": [ISLAND]}})
	Detection.set_environment({"sea_state": 3, "layer_depth_m": 60.0, "layer_strength": 0.5})
	var um := UnitManager.new()
	ScenarioLoader.populate(um, {"units": [
		{"platform": "usn_ddg_burke_iii", "callsign": "Burke", "faction": "BLUE", "position_nm": [0, 0], "heading_deg": 90, "speed_kn": 18},
		{"platform": "usn_ea_ea18g", "callsign": "Growler", "faction": "BLUE", "position_nm": [-10, 20], "heading_deg": 100, "speed_kn": 300},
		{"platform": "usn_aew_e2d", "callsign": "Hawkeye", "faction": "BLUE", "position_nm": [-40, -10], "heading_deg": 0, "speed_kn": 250},
		{"platform": "usn_fighter_fa18e", "callsign": "Hornet", "faction": "BLUE", "position_nm": [5, 30], "heading_deg": 180, "speed_kn": 350},
		{"platform": "usn_ssn_virginia", "callsign": "Virginia", "faction": "BLUE", "position_nm": [20, -20], "heading_deg": 45, "speed_kn": 8, "depth_m": 15},
		{"platform": "usn_helo_mh60r", "callsign": "Seahawk", "faction": "BLUE", "position_nm": [22, 2], "speed_kn": 0},
		{"platform": "pla_ddg_type055", "callsign": "Nanchang", "faction": "RED", "position_nm": [30, 0], "heading_deg": 270, "speed_kn": 16},
		{"platform": "pla_ssn_type093b", "callsign": "Boat", "faction": "RED", "position_nm": [26, -8], "heading_deg": 300, "speed_kn": 6, "depth_m": 15},
		{"platform": "pla_fighter_j16", "callsign": "Flanker", "faction": "RED", "position_nm": [60, 25], "heading_deg": 250, "speed_kn": 400},
		{"platform": "pla_aew_kj500", "callsign": "Eye", "faction": "RED", "position_nm": [90, 0], "heading_deg": 0, "speed_kn": 280},
		{"platform": "pla_battery_yj12b", "callsign": "Battery", "faction": "RED", "position_nm": [12, 0]},
		{"platform": "civ_merchant_bulk", "callsign": "Merchant", "faction": "NEUTRAL", "position_nm": [15, 12], "heading_deg": 200, "speed_kn": 12},
	]})
	var seahawk := _named(um, "Seahawk")
	seahawk.flight_state = Unit.FlightState.AIRBORNE
	seahawk.altitude_m = 60.0
	_named(um, "Hawkeye").components["sensors"] = 0.6
	_named(um, "Nanchang").components["sensors"] = 0.8
	var tm := TrackManager.new()
	tm.neutral_factions = PackedStringArray(["NEUTRAL"])
	var sm := SensorManager.new()
	sm.unit_manager = um
	sm.track_manager = tm
	sm.rng.seed = 2026
	return [um, tm, sm]


func _named(um: UnitManager, callsign: String) -> Unit:
	for u: Unit in um.units:
		if u.callsign == callsign:
			return u
	return null


## The same scripted evolution for both runs: everything moves, aircraft turn, the boats change
## depth, radars and a sonar switch, and a ship is lost.
func _evolve(um: UnitManager, cycle: int) -> void:
	for u: Unit in um.units:
		if not u.alive:
			continue
		if u.is_aircraft() and u.speed_kn > 100.0:
			u.heading_deg = fposmod(u.heading_deg + 4.0, 360.0)
		u.position += Geo.heading_to_vector(u.heading_deg) * Geo.knots_to_nm_per_s(u.speed_kn) * SensorManager.SENSOR_DT
	var virginia := _named(um, "Virginia")
	virginia.depth_m = 120.0 if floori(cycle / 25.0) % 2 == 1 else 15.0
	_named(um, "Boat").depth_m = 150.0 if floori(cycle / 35.0) % 2 == 1 else 15.0
	_named(um, "Nanchang").radar_on = floori(cycle / 15.0) % 3 != 1
	_named(um, "Growler").radar_on = floori(cycle / 20.0) % 4 != 3
	_named(um, "Burke").active_sonar_on = floori(cycle / 30.0) % 2 == 1
	if cycle == 140:
		_named(um, "Merchant").alive = false


func _run(reference: bool, cycles: int) -> Dictionary:
	var world := _world()
	var um: UnitManager = world[0]
	var tm: TrackManager = world[1]
	var sm: SensorManager = world[2]
	sm.reference_path = reference
	var added := [0]
	tm.track_added.connect(func(_f: String, _t: Track) -> void: added[0] += 1)
	for i in cycles:
		sm.run_cycle(float(i + 1))
		_evolve(um, i)
	var out := {"pictures": _pictures(tm), "rng": sm.rng.state, "next": tm._next_number.duplicate(), "added": added[0]}
	sm.free()
	tm.free()
	um.free()
	Terrain.clear()
	Detection.set_environment({})
	return out


## Every track in every picture, every field, with units written as their ids.
static func _pictures(tm: TrackManager) -> Dictionary:
	var out := {}
	var keys := tm._tracks.keys()
	keys.sort()
	for key: String in keys:
		var list := []
		for t: Track in tm._tracks[key]:
			var row := {}
			for field: String in SimSnapshot.script_variables(t):
				row[field] = _plain(t.get(field))
			list.append(row)
		out[key] = list
	return out


static func _plain(v: Variant) -> Variant:
	if v is Unit:
		return "unit %d" % (v as Unit).id
	if v is Dictionary:
		var d := {}
		for k in v:
			d[_plain(k)] = _plain(v[k])
		return d
	return v


## The path to the first difference, so a failure says which track and field moved.
func _first_difference(a: Variant, b: Variant, path: String) -> String:
	if typeof(a) != typeof(b):
		return "%s: %s vs %s" % [path, a, b]
	if a is Dictionary:
		for k in a:
			if not b.has(k):
				return "%s/%s missing" % [path, k]
			var d := _first_difference(a[k], b[k], "%s/%s" % [path, k])
			if d != "":
				return d
		for k in b:
			if not a.has(k):
				return "%s/%s extra" % [path, k]
		return ""
	if a is Array:
		if a.size() != b.size():
			return "%s: %d vs %d entries" % [path, a.size(), b.size()]
		for i in a.size():
			var d := _first_difference(a[i], b[i], "%s[%d]" % [path, i])
			if d != "":
				return d
		return ""
	return "" if a == b else "%s: %s vs %s" % [path, a, b]


func test_indexed_cycle_matches_the_reference_on_a_mixed_chart() -> void:
	var reference := _run(true, 200)
	var indexed := _run(false, 200)
	assert_eq(_first_difference(reference, indexed, ""), "", "every picture identical")
	# The world must actually exercise what it claims to: firm plots and bearings, a jammed and a
	# masked line, a disconnected unit's own picture, classification well under way.
	var sources := {}
	var classified := 0
	var local_pictures := 0
	for key: String in reference["pictures"]:
		if key.begins_with("local:"):
			local_pictures += 1
		for row: Dictionary in reference["pictures"][key]:
			sources[row["source"]] = true
			if int(row["classification"]) >= Track.Classification.CLASS_KNOWN:
				classified += 1
	for source in ["radar", "esm", "sonar_passive"]:
		assert_true(sources.has(source), "the run made %s reports" % source)
	assert_true(classified > 0, "tracks reached class")
	assert_true(local_pictures >= 6, "units kept their own pictures")
	assert_true(int(reference["added"]) > 4)


## A terrain walk shared between a radar plot and an ESM bearing must give the same answer as
## walking it twice: the island screens the battery from the destroyer at sea level.
func test_a_shared_sight_line_still_masks() -> void:
	var world := _world()
	var um: UnitManager = world[0]
	var tm: TrackManager = world[1]
	var sm: SensorManager = world[2]
	var burke := _named(um, "Burke")
	var battery := _named(um, "Battery")
	battery.position = Vector2(20, 0)  # in the lee of the island, seen from the west
	for u: Unit in um.units:
		if u != burke and u != battery:
			u.alive = false
	assert_true(Detection.terrain_masks(burke, battery), "the hill is in the way")
	sm.run_cycle(1.0)
	assert_true(tm.find_track("BLUE", battery) == null, "neither radar nor ESM sees through it")
	battery.position = Vector2(20, 20)
	sm.run_cycle(2.0)
	assert_true(tm.find_track("BLUE", battery) != null, "in the open it is seen")
	sm.free()
	tm.free()
	um.free()
	Terrain.clear()
	Detection.set_environment({})


func _battle(path: String, seed_value: int, warm_s: float, compare_s: float) -> void:
	SimClock.set_paused(true)
	var sim := Simulation.new()
	sim.seed_override = seed_value
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	assert_true(sim.load_scenario(path), path)
	sim.ai_plays_player = true
	sim._build_ai()
	SimClock.advance(warm_s)
	# Restored from bytes each time: a restore takes over the snapshot's arrays, so a snapshot
	# restored once is no longer the moment it was taken.
	var start := var_to_bytes(sim.capture_snapshot())
	assert_eq(sim.restore_snapshot(bytes_to_var(start)), "")
	# The reference walks every sight line too, as the sensor cycle did before either shortcut.
	sim.sensor_manager.reference_path = true
	Terrain.height_shortcut = false
	SimClock.advance(compare_s)
	var reference := SimSnapshot.capture(sim)
	assert_eq(sim.restore_snapshot(bytes_to_var(start)), "")
	sim.sensor_manager.reference_path = false
	Terrain.height_shortcut = true
	SimClock.advance(compare_s * 0.5)
	var middle := var_to_bytes(sim.capture_snapshot())
	assert_eq(sim.restore_snapshot(bytes_to_var(middle)), "")
	SimClock.advance(compare_s * 0.5)
	var indexed := SimSnapshot.capture(sim)
	assert_eq(_first_difference(reference, indexed, ""), "", "%s: the whole engagement identical" % path.get_file())
	print("    %s: %d tracks, %d units" % [path.get_file(), (reference["tracks"] as Array).size(), (reference["units"] as Array).size()])
	assert_true((reference["tracks"] as Array).size() > 0, "the battle holds tracks")
	sim.unit_manager.clear()
	sim.get_parent().remove_child(sim)
	sim.free()


## Twenty-six units in a narrow strait: small craft, shore sites, a shallow layer and a coast.
func test_indexed_cycle_matches_the_reference_in_a_seeded_hormuz_battle() -> void:
	_battle(HORMUZ, 45, 600.0, 300.0)


## Fifteen units with aircraft, a convergence zone and a coast.
func test_indexed_cycle_matches_the_reference_in_a_seeded_tartus_battle() -> void:
	_battle(TARTUS, 7, 600.0, 300.0)
