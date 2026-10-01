extends TestCase


func _air_harness(loadout: Dictionary = {"aim120_family": 2}) -> Array:
	Terrain.clear()
	var um := UnitManager.new()
	ScenarioLoader.populate(um, {"units": [{"platform": "usn_cvn_nimitz", "callsign": "Carrier", "faction": "BLUE",
		"aviation_stores": {"aim120_family": 3}, "aviation_buoys": 0,
		"air_wing": [{"platform": "usn_fighter_fa18e", "count": 2, "callsign": "CAP", "loadout": loadout}]}]})
	var av := AviationManager.new()
	av.unit_manager = um
	return [um, av, um.units[0], um.units[1], um.units[2]]


func test_rearming_conserves_shared_stocks_and_keeps_authored_fit() -> void:
	var h := _air_harness()
	var a: Unit = h[3]
	var b: Unit = h[4]
	a.magazines["aim120_family"] = 0
	b.magazines["aim120_family"] = 0
	h[1]._step_turnaround(a, 1)
	h[1]._step_turnaround(b, 1)
	assert_eq(a.magazine_count("aim120_family"), 2)
	assert_eq(b.magazine_count("aim120_family"), 1, "second section shares remaining stock")
	assert_eq(h[2].aviation_stores["aim120_family"], 0)
	assert_eq(a.magazine_count("agm_158c_lrasm"), 0, "CAP does not turn into a strike fit")
	assert_eq(a.weapons.size(), 1)
	a.magazines["aim120_family"] = 0
	h[1]._step_turnaround(a, 1)
	assert_eq(a.magazine_count("aim120_family"), 0, "an empty base cannot rearm again")
	h[1].free()
	h[0].free()


func test_empty_authored_fit_stays_unarmed_and_diversion_cannot_conjure_stock() -> void:
	var h := _air_harness({})
	h[1]._step_turnaround(h[3], 1)
	assert_true(h[3].magazines.is_empty())
	assert_true(h[3].weapons.is_empty())
	var other := Unit.new()
	other.spec = h[2].spec
	h[4].home = other
	h[4].sortie_loadout = {"aim120_family": 2}
	h[1]._step_turnaround(h[4], 1)
	assert_eq(h[4].magazine_count("aim120_family"), 0)
	h[1].free()
	h[0].free()


func test_reserve_aircraft_prepare_once_without_reloading_or_taking_deck_slots() -> void:
	var h := _air_harness()
	var a: Unit = h[3]
	a.flight_state = Unit.FlightState.RESERVE
	a.state_timer_s = 2
	a.magazines["aim120_family"] = 1
	assert_eq(h[2].launch_spots_busy(), 0)
	assert_true(h[1].launch(h[2], a.callsign) == null)
	h[1]._run_cycle(1, 1)
	assert_true(not a.ready_to_launch())
	h[1]._run_cycle(1, 2)
	assert_true(a.ready_to_launch())
	assert_eq(a.magazine_count("aim120_family"), 1)
	assert_eq(h[2].aviation_stores["aim120_family"], 3)
	h[1].free()
	h[0].free()


func test_reserves_share_host_loss_and_damaged_deck_cannot_launch() -> void:
	var h := _air_harness()
	h[2].fire = 0.5
	assert_true(h[1].launch(h[2], h[3].callsign) == null)
	h[3].flight_state = Unit.FlightState.RESERVE
	h[3].state_timer_s = 10
	h[2].alive = false
	h[1]._run_cycle(1, 1)
	assert_true(not h[3].alive)
	assert_true(not h[4].alive)
	h[1].free()
	h[0].free()


func test_hold_station_requires_continuous_presence_and_excludes_stowed_aircraft() -> void:
	var h := _air_harness()
	var um: UnitManager = h[0]
	var o := MissionObjective.from_dict({"type": "hold_area", "callsigns": ["Carrier"], "radius_nm": 5, "seconds": 300})
	assert_true(not o.evaluate(um, 0))
	assert_true(not o.evaluate(um, 299))
	h[2].position = Vector2(6, 0)
	assert_true(not o.evaluate(um, 300))
	h[2].position = Vector2.ZERO
	assert_true(not o.evaluate(um, 301))
	assert_true(not o.evaluate(um, 600))
	assert_true(o.evaluate(um, 601))
	var aircraft := MissionObjective.from_dict({"type": "hold_area", "callsigns": [h[3].callsign], "seconds": 1})
	assert_true(not aircraft.evaluate(um, 0))
	assert_true(not aircraft.evaluate(um, 10), "embarked airframe cannot fly a patrol")
	h[1].free()
	h[0].free()


func test_phase_prerequisite_cannot_end_any_mode_mission_and_loss_still_wins() -> void:
	var h := _air_harness()
	var mm := MissionManager.new()
	mm.unit_manager = h[0]
	mm.configure({"victory_mode": "any", "objectives": {"victory": [
		{"id": "prepare", "type": "time_elapsed", "seconds": 10, "phase_only": true},
		{"id": "finish", "type": "time_elapsed", "seconds": 20, "after": ["prepare"]}],
		"loss": [{"id": "lost", "type": "unit_lost", "callsigns": ["Carrier"]}]}})
	mm.tick(10)
	assert_eq(mm.result, MissionManager.Result.RUNNING)
	assert_true(mm.victory_objectives[0].complete)
	h[2].alive = false
	mm.tick(20)
	assert_eq(mm.result, MissionManager.Result.DEFEAT)
	mm.free()
	h[1].free()
	h[0].free()


func test_mission_restart_resets_hold_and_dependencies() -> void:
	var h := _air_harness()
	var mm := MissionManager.new()
	mm.unit_manager = h[0]
	var sc := {"objectives": {"victory": [{"id": "station", "type": "hold_area", "faction": "BLUE", "seconds": 5}]}}
	mm.configure(sc)
	mm.tick(0)
	mm.tick(5)
	assert_eq(mm.result, MissionManager.Result.VICTORY)
	mm.configure(sc)
	mm.tick(0)
	assert_eq(mm.result, MissionManager.Result.RUNNING)
	assert_eq(mm.victory_objectives[0].held_seconds, 0.0)
	mm.free()
	h[1].free()
	h[0].free()


func test_follow_on_force_does_not_reset_existing_airframes_or_duplicate_homes() -> void:
	var h := _air_harness()
	var a: Unit = h[3]
	a.flight_state = Unit.FlightState.AIRBORNE
	a.position = Vector2(50, 50)
	a.fuel_s = 99
	a.magazines["aim120_family"] = 0
	ScenarioLoader.populate(h[0], {"units": [{"platform": "cw90_tu22m3", "callsign": "Raid", "faction": "RED", "position_nm": [100, 100]}]})
	assert_eq(h[2].embarked.size(), 2)
	assert_eq(a.position, Vector2(50, 50))
	assert_eq(a.fuel_s, 99.0)
	assert_eq(a.magazine_count("aim120_family"), 0)
	assert_eq(h[2].aviation_stores["aim120_family"], 3)
	assert_true(h[0].units.back().airborne())
	h[1].free()
	h[0].free()


func test_all_operations_have_valid_dependencies_wings_and_finite_stores() -> void:
	var operations := 0
	var exercises := 0
	for entry: Dictionary in ScenarioIndex.list_all():
		if entry.custom:
			continue
		var sc := ScenarioLoader.load_file(entry.path)
		if entry.collection == "exercises":
			exercises += 1
			assert_eq(ScenarioMenu._shelf_of(entry), "exercises")
			continue
		operations += 1
		assert_eq(sc.operation_plan.size(), 3)
		var ids := {}
		for o: Dictionary in sc.objectives.victory:
			for previous: String in o.get("after", []):
				assert_true(ids.has(previous), "%s prerequisite defined before use: %s" % [entry.id, previous])
			assert_true(not ids.has(o.id), "unique objective id")
			ids[o.id] = true
		var um := UnitManager.new()
		Terrain.clear()
		ScenarioLoader.populate(um, sc)
		var names := {}
		for u in um.units:
			assert_true(not names.has(u.callsign), "%s unique callsign: %s" % [entry.id, u.callsign])
			names[u.callsign] = true
			if u.spec.id in ["usn_cvn_nimitz", "usn_cvn_ford"]:
				assert_eq(u.embarked.size(), 59, "%s has the larger air wing" % entry.id)
				assert_true(u.stowed_aircraft().size() < u.embarked.size(), "reserve remains aboard")
			assert_true(u.embarked.size() <= u.spec.aircraft_capacity)
			for wid: String in u.aviation_stores:
				assert_true(DataDB.weapon(wid) != null and int(u.aviation_stores[wid]) >= 0)
			for wid: String in u.sortie_loadout:
				assert_true(u.spec.weapon_loadout.has(wid), "authored aircraft weapon is supported")
		for event: Dictionary in sc.get("events", []):
			for previous: String in event.get("after", []):
				assert_true(ids.has(previous))
			for ud: Dictionary in event.get("reinforcements", []):
				assert_true(not names.has(ud.callsign), "reinforcement identity does not alias opening force")
				names[ud.callsign] = true
				assert_true(DataDB.platform(ud.platform) != null)
				if int(sc.year) == 1990:
					assert_true(str(ud.platform).begins_with("cw90_"))
		um.free()
	assert_eq(operations, 7, "one 2027 operation per chart region and three from 1990")
	assert_eq(exercises, 2, "Northern Passage and Carrier Qualification")


func test_scheduled_raid_fires_once_preserves_fog_and_resets_on_reload() -> void:
	var sim := Simulation.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	assert_true(sim.load_scenario("res://data/scenarios/cold_war_03_carrier.json"))
	var initial := sim.unit_manager.units.size()
	sim._tick_operation_events(2399)
	assert_eq(sim.unit_manager.units.size(), initial)
	sim._tick_operation_events(2400)
	assert_eq(sim.unit_manager.units.size(), initial + 1)
	assert_eq(sim.unit_manager.units.back().callsign, "Backfire raid 2")
	assert_true(sim.unit_manager.units.back().airborne())
	assert_true(sim.track_manager.get_tracks("BLUE").is_empty(), "a new raid is not an automatic contact report")
	sim._tick_operation_events(2401)
	assert_eq(sim.unit_manager.units.size(), initial + 1)
	assert_true(sim.reload())
	assert_true(sim.completed_events.is_empty())
	assert_eq(sim.unit_manager.units.size(), initial)
	sim.free()
