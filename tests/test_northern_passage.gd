extends TestCase

const PATH := "res://data/scenarios/northern_passage.json"

func _sim() -> Simulation:
	var sim := Simulation.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	assert_true(sim.load_scenario(PATH))
	SimClock.set_paused(true)
	return sim

func _unit(sim: Simulation, name: String) -> Unit:
	for u: Unit in sim.unit_manager.units:
		if u.callsign == name:
			return u
	return null

func test_intro_has_valid_geography_roster_and_one_embarked_helicopter() -> void:
	var sc := ScenarioLoader.load_file(PATH)
	assert_eq(ScenarioWorkshop.validate(sc), "")
	var sim := _sim()
	assert_eq(sim.unit_manager.units.size(), 8)
	var aircraft := sim.unit_manager.units.filter(func(u: Unit) -> bool: return u.is_aircraft())
	assert_eq(aircraft.size(), 1)
	assert_eq(aircraft[0].spec.id, "usn_helo_mh60r")
	assert_true(aircraft[0].home == _unit(sim, "USS Truxtun (DDG 103)"))
	assert_true(aircraft[0].ready_to_launch())
	assert_eq(sim.unit_manager.get_faction_units("NEUTRAL").size(), 2)
	assert_true(sim.track_manager.get_tracks("BLUE").is_empty(), "no pre-revealed targets")
	assert_true(sim.track_manager.get_tracks("RED").is_empty(), "AI starts with its own empty picture")
	for u: Unit in sim.unit_manager.units:
		if u.needs_sea_room():
			assert_true(not Terrain.is_land(u.position), u.callsign)
	sim.free()

func test_opening_route_is_eight_miles_and_respects_the_existing_speed_cap() -> void:
	var sim := _sim()
	var cargo := _unit(sim, "MV Northern Light")
	assert_eq(cargo.waypoints.size(), 2)
	assert_near(cargo.ordered_speed_kn, 15)
	var length := 0.0
	var previous := cargo.position
	for p: Vector2 in cargo.waypoints:
		length += previous.distance_to(p)
		assert_true(not Terrain.blocks_path(previous, p), "route leg crosses no land")
		previous = p
	assert_near(length, 8)
	assert_true(length > cargo.position.distance_to(previous), "measure the dogleg, not the straight line")
	assert_true(length / cargo.ordered_speed_kn * 3600 < 2700)
	for name: String in ["USS Truxtun (DDG 103)", "HNoMS Roald Amundsen (F 311)"]:
		assert_true(_unit(sim, name).formation_leader == cargo)
	sim.free()

func test_opening_route_opt_in_preserves_legacy_patrol_behavior() -> void:
	var um := UnitManager.new()
	ScenarioLoader.populate(um, {"units": [{"platform": "civ_merchant_bulk", "position_nm": [0, 0], "speed_kn": 13, "patrol_nm": [[2, 0]]}]})
	assert_true(um.units[0].waypoints.is_empty(), "legacy patrols still belong to the existing controller")
	assert_eq(um.units[0].patrol_route.size(), 1)
	um.free()

func test_paused_route_and_launch_orders_do_not_advance_the_battle() -> void:
	var sim := _sim()
	var cargo := _unit(sim, "MV Northern Light")
	var host := _unit(sim, "USS Truxtun (DDG 103)")
	var aircraft: Unit = host.embarked[0]
	assert_true(sim.unit_manager.issue_order(host, Order.launch_aircraft()))
	var timer := aircraft.state_timer_s
	var fuel := aircraft.fuel_s
	var position := cargo.position
	assert_true(sim.unit_manager.issue_order(cargo, Order.move(Vector2(3, 0))))
	assert_true(sim.unit_manager.issue_order(cargo, Order.move(Vector2(3, 5), true)))
	SimClock._advance_frame(30)
	assert_near(SimClock.sim_time, 0)
	assert_eq(cargo.position, position)
	assert_near(cargo.ordered_speed_kn, 15)
	assert_near(aircraft.fuel_s, fuel)
	assert_near(aircraft.state_timer_s, timer)
	assert_true(sim.track_manager.get_tracks("BLUE").is_empty())
	sim.free()

func test_other_faction_neutral_loss_is_not_a_player_incident() -> void:
	var sim := _sim()
	Damage.apply(_unit(sim, "MV Skerry Trader"), 500, "asm", "RED")
	sim.mission_manager.tick(10)
	assert_eq(sim.mission_manager.result, MissionManager.Result.RUNNING)
	assert_eq(sim.mission_manager.loss_objectives[2].progress(sim.unit_manager, 10), "no attributed losses")
	Damage.apply(_unit(sim, "MV Coastal Star"), 500, "asm", "BLUE")
	sim.mission_manager.tick(20)
	assert_eq(sim.mission_manager.result, MissionManager.Result.DEFEAT)
	assert_true(sim.mission_manager.loss_objectives[2].complete)
	sim.free()

func test_player_damage_responsibility_survives_a_later_flooding_loss() -> void:
	var sim := _sim()
	var civilian := _unit(sim, "MV Skerry Trader")
	Damage.apply(civilian, 20, "asm", "BLUE")
	civilian.flooding = 1.0
	civilian.health = 0.001
	Damage.tick([civilian], 1)
	assert_true(not civilian.alive)
	assert_eq(civilian.last_attacker, "BLUE")
	sim.mission_manager.tick(30)
	assert_eq(sim.mission_manager.result, MissionManager.Result.DEFEAT)
	sim.free()

func test_deadline_tie_and_freighter_loss_override_arrival() -> void:
	var sim := _sim()
	var cargo := _unit(sim, "MV Northern Light")
	cargo.position = Vector2(3, 5)
	sim.mission_manager.tick(2700)
	assert_eq(sim.mission_manager.result, MissionManager.Result.DEFEAT)
	assert_true(sim.mission_manager.loss_objectives[1].complete)
	assert_true(sim.reload())
	cargo = _unit(sim, "MV Northern Light")
	cargo.position = Vector2(3, 5)
	Damage.apply(cargo, 500, "asm", "RED")
	sim.mission_manager.tick(1800)
	assert_eq(sim.mission_manager.result, MissionManager.Result.DEFEAT)
	sim.free()

func test_delivery_does_not_require_destroying_the_opposition() -> void:
	var sim := _sim()
	_unit(sim, "MV Northern Light").position = Vector2(3, 5)
	sim.mission_manager.tick(1900)
	assert_eq(sim.mission_manager.result, MissionManager.Result.VICTORY)
	assert_eq(sim.unit_manager.get_engageable_units("RED").size(), 2)
	sim.free()

func test_authoring_rejects_malformed_responsibility_and_route_flags() -> void:
	var sc := ScenarioLoader.load_file(PATH)
	sc.units[2].follow_route = "yes"
	assert_true(ScenarioWorkshop.validate(sc) != "")
	sc.units[2].follow_route = true
	var loss: Dictionary = sc.objectives.loss[2]
	loss.caused_by = 8
	assert_true(ScenarioWorkshop.validate(sc) != "")
	loss.caused_by = "MISSING"
	assert_true(ScenarioWorkshop.validate(sc) != "")
	loss.caused_by = "BLUE"
	loss.type = "time_elapsed"
	assert_true(ScenarioWorkshop.validate(sc) != "")
	loss.type = "unit_lost"
	assert_eq(ScenarioWorkshop.validate(sc), "")

func test_radio_journal_is_chronological_bounded_and_reset_per_mission() -> void:
	var radio := RadioNet.new()
	for i in RadioNet.MAX_JOURNAL + 2:
		radio.flash("Observed %d" % i)
	assert_eq(radio.history.size(), RadioNet.MAX_HISTORY)
	assert_eq(radio.journal.size(), RadioNet.MAX_JOURNAL)
	assert_eq(radio.journal_omitted, 2)
	assert_true(radio.journal[0].ends_with("Observed 2"))
	assert_eq(radio.journal.back(), radio.history.front())
	radio.clear()
	assert_true(radio.journal.is_empty())
	assert_eq(radio.journal_omitted, 0)
