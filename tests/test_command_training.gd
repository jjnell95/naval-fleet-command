extends TestCase

func _sim(id: String) -> Simulation:
	var sim := Simulation.new()
	sim.seed_override = 31
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	assert_true(sim.load_scenario("res://data/scenarios/%s.json" % id))
	SimClock.set_paused(true)
	return sim

func _unit(sim: Simulation, name: String) -> Unit:
	for u: Unit in sim.unit_manager.units:
		if u.callsign == name: return u
	return null

func _until(sim: Simulation, objective: String, max_seconds: int) -> bool:
	for second in max_seconds:
		if sim.mission_manager.objective(objective).complete: return true
		SimClock.advance(1.0)
	return sim.mission_manager.objective(objective).complete

func test_training_scenarios_validate_and_require_real_practice() -> void:
	for id: String in CommandTraining.IDS:
		var scenario := ScenarioLoader.load_file("res://data/scenarios/%s.json" % id)
		assert_eq(ScenarioWorkshop.validate(scenario), "", id)
		assert_eq(scenario["collection"], "exercises")
		var sim := _sim(id)
		for second in 90: SimClock.advance(1.0)
		assert_eq(sim.mission_manager.result, MissionManager.Result.RUNNING, "time alone cannot win a lesson")
		assert_true(sim.mission_manager.victory_objectives.all(func(o: MissionObjective) -> bool: return not o.complete))
		sim.free()

func test_rejected_and_crew_orders_never_award_manual_command_credit() -> void:
	var sim := _sim("training_missile_defence")
	var ship := _unit(sim, "USS Practice")
	var crew := Order.set_air_defence_mode(false)
	crew.origin = "crew"
	sim.unit_manager.issue_order(ship, crew)
	assert_true(not sim.mission_manager.objective("manual_defence").complete)
	var rejected := Order.set_air_defence_mode(false)
	rejected.execution_accepted = false
	CommandTraining.record_order(sim, ship, rejected)
	assert_true(not sim.mission_manager.objective("manual_defence").complete)
	sim.unit_manager.issue_order(ship, Order.set_air_defence_mode(false))
	assert_true(sim.mission_manager.objective("manual_defence").complete)
	sim.unit_manager.issue_order(ship, Order.intercept())
	assert_true(not sim.mission_manager.objective("manual_intercept").complete, "X against an empty sky is not practice")
	sim.free()

func test_missile_exercise_finishes_after_a_real_detected_interception() -> void:
	var sim := _sim("training_missile_defence")
	var ship := _unit(sim, "USS Practice")
	sim.unit_manager.issue_order(ship, Order.set_air_defence_mode(false))
	var observed := false
	var accepted := false
	for second in 900:
		SimClock.advance(1.0)
		if not sim.threat_manager.get_threats("BLUE").is_empty():
			observed = true
			var intercept := Order.intercept()
			sim.unit_manager.issue_order(ship, intercept)
			accepted = accepted or intercept.execution_accepted
		if sim.mission_manager.result != MissionManager.Result.RUNNING: break
	assert_true(observed, "ordinary radar detects the opposing AI's missile")
	assert_true(accepted, "a manual defensive order commits actual interceptors")
	assert_true(ship.alive)
	assert_eq(sim.mission_manager.result, MissionManager.Result.VICTORY, "survival without the accepted command cannot satisfy this lesson")
	sim.free()

func test_asw_exercise_requires_passive_inspection_localization_torpedo_and_recovery() -> void:
	var sim := _sim("training_asw")
	var helo := _unit(sim, "Seahawk Practice")
	sim.unit_manager.issue_order(helo, Order.deploy_dipping_sonar())
	assert_true(_until(sim, "dip_listen", 180), "hover/lower/listen uses the actual array cycle")
	var datum: Track
	for second in 120:
		SimClock.advance(1.0)
		for track: Track in sim.track_manager.tracks_for(helo):
			if track.is_bearing_only() and track.source == "sonar_passive": datum = track
		if datum != null: break
	assert_true(datum != null, "the stock dipping array hears a passive bearing")
	if datum == null:
		sim.free()
		return
	assert_true(not sim.mission_manager.objective("passive_datum").complete, "the player must actually inspect uncertainty")
	CommandTraining.record_inspection(sim, datum)
	assert_true(sim.mission_manager.objective("passive_datum").complete)
	sim.unit_manager.issue_order(helo, Order.active_sonar())
	assert_true(_until(sim, "active_fix", 120), "active sonar must actually produce the range report")
	assert_true(not sim.mission_manager.objective("authorize_attack").complete, "localization never implies permission to fire")
	for track: Track in sim.track_manager.tracks_for(helo):
		if track.id == str(sim.mission_manager.objective("active_fix").practice_state.get("track_id", "")): datum = track
	var torpedo := ""
	for weapon: WeaponSpec in helo.weapons:
		if weapon.is_torpedo(): torpedo = weapon.id
	var fire := Order.engage(datum, torpedo, 1)
	var accepted := sim.unit_manager.issue_order(helo, fire)
	assert_true(accepted, "torpedo order rejected: %s; identity %s, domain %s, range %.2f; check %s" % [fire.receipt, datum.identity, datum.domain, helo.position.distance_to(datum.position), Combat.check_engagement(helo, helo.get_weapon(torpedo), datum)])
	assert_true(_until(sim, "authorize_attack", 60), "explicit authorization must result in a torpedo away; %s" % sim.mission_manager.objective("authorize_attack").practice_state)
	sim.unit_manager.issue_order(helo, Order.recover_dipping_sonar())
	assert_true(not sim.mission_manager.objective("recover_array").complete, "the raise order is not immediate recovery")
	assert_true(_until(sim, "recover_array", 45))
	assert_eq(helo.dip_phase, DippingSonar.Phase.STOWED)
	assert_eq(sim.mission_manager.result, MissionManager.Result.VICTORY)
	sim.free()

func test_training_progress_and_pending_cycle_survive_save_restore() -> void:
	var sim := _sim("training_asw")
	var helo := _unit(sim, "Seahawk Practice")
	sim.unit_manager.issue_order(helo, Order.deploy_dipping_sonar())
	for second in 8: SimClock.advance(1.0)
	var saved := SimSnapshot.capture(sim)
	var before := sim.mission_manager.objective("dip_listen").practice_state.duplicate(true)
	assert_true(not before.is_empty())
	assert_true(_until(sim, "dip_listen", 180))
	var completed_at := SimClock.sim_time
	assert_eq(sim.restore_snapshot(saved), "")
	assert_eq(sim.mission_manager.objective("dip_listen").practice_state, before)
	assert_true(not sim.mission_manager.objective("dip_listen").complete)
	assert_true(_until(sim, "dip_listen", 180))
	assert_near(SimClock.sim_time, completed_at, 0.01, "the restored deployment earns credit at the same tick")
	sim.free()
