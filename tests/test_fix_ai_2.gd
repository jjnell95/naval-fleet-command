extends TestCase
## Mission effectiveness grades how the mission was played: whether anyone commanded it, the
## hits the force's own weapons landed on neutrals and on itself, and rounds spent far beyond
## what their targets were worth.


func _unit(faction: String, callsign: String, pos: Vector2, category: String, hp := 100.0) -> Unit:
	var spec := PlatformSpec.new()
	spec.short_name = callsign
	spec.category = category
	spec.max_speed_kn = 28.0
	spec.cruise_speed_kn = 14.0
	spec.health = hp
	var u := Unit.new()
	u.spec = spec
	u.faction = faction
	u.callsign = callsign
	u.position = pos
	u.health = hp
	return u


func _weapon(type: String) -> WeaponSpec:
	var spec := WeaponSpec.new()
	spec.id = "test_%s" % type
	spec.display_name = "Test %s" % type
	spec.type = type
	return spec


## [unit manager, mission manager, weapon manager]: a convoy escort against one raider, with a
## neutral trawler about, won by holding on for an hour.
func _passage() -> Array:
	var um := UnitManager.new()
	for u: Unit in [_unit("BLUE", "Escort", Vector2.ZERO, "frigate"), _unit("BLUE", "Maud", Vector2(1.0, 0.0), "merchant"),
			_unit("RED", "Raider", Vector2(0.0, 10.0), "corvette"), _unit("NEUTRAL", "Trawler", Vector2(5.0, 5.0), "merchant")]:
		um.add_unit(u)
	var mm := MissionManager.new()
	mm.unit_manager = um
	mm.player_faction = "BLUE"
	mm.configure({"id": "test", "neutral_factions": ["NEUTRAL"], "objectives": {
		"victory": [{"type": "time_elapsed", "seconds": 3600.0, "text": "Hold the passage"}],
		"loss": [{"type": "unit_lost", "callsigns": ["Maud"], "text": "Maud lost"}]}})
	var wm := WeaponManager.new()
	mm.listen(wm)
	return [um, mm, wm]


func _free(h: Array) -> void:
	h[2].free()
	h[1].free()
	h[0].free()


func _called(um: UnitManager, callsign: String) -> Unit:
	for u: Unit in um.units:
		if u.callsign == callsign:
			return u
	return null


func _track_on(u: Unit) -> Track:
	var t := Track.new()
	t.truth = u
	t.position = u.position
	return t


func _give_order(um: UnitManager, u: Unit, o: Order) -> void:
	um.order_issued.emit(u, o)


# --- Command --------------------------------------------------------------------------------

func test_a_victory_won_without_a_single_order_grades_well_below_a_commanded_one() -> void:
	var h := _passage()
	var mm: MissionManager = h[1]
	mm.tick(3700.0)
	assert_eq(mm.result, MissionManager.Result.VICTORY, "the passage was held")
	var idle := mm.assessment()
	assert_true(not bool(idle["commanded"]), "nobody gave an order")
	assert_true(int(idle["percent"]) < 40, "a victory nobody commanded grades under 40, not %d" % int(idle["percent"]))
	assert_true(MissionManager.assessment_text(idle).contains("no orders given"), "the debrief says why: %s" % MissionManager.assessment_text(idle))
	_free(h)
	h = _passage()
	mm = h[1]
	_give_order(h[0], _called(h[0], "Escort"), Order.move(Vector2(3.0, 3.0)))
	mm.tick(3700.0)
	var commanded := mm.assessment()
	assert_true(bool(commanded["commanded"]))
	assert_true(int(commanded["percent"]) >= 60, "the same victory under command grades as one: %d" % int(commanded["percent"]))
	_free(h)


func test_doctrine_crew_and_refused_orders_are_not_command() -> void:
	var h := _passage()
	var um: UnitManager = h[0]
	var mm: MissionManager = h[1]
	var escort := _called(um, "Escort")
	_give_order(um, escort, Order.set_air_defence_mode(false))
	var crew := Order.move(Vector2(2.0, 2.0))
	crew.origin = "crew"
	_give_order(um, escort, crew)
	var refused := Order.move(Vector2(2.0, 2.0))
	refused.execution_accepted = false
	_give_order(um, escort, refused)
	_give_order(um, _called(um, "Raider"), Order.move(Vector2(0.0, 0.0)))
	assert_eq(mm.orders_given, 0, "the arrival doctrine, the crew's own manoeuvres, a refusal and the enemy's orders are not the commander's")
	_give_order(um, escort, Order.set_speed(20.0))
	assert_eq(mm.orders_given, 1)
	_free(h)


func test_a_mission_with_no_enemy_at_sea_is_not_marked_down_for_standing_by() -> void:
	var um := UnitManager.new()
	um.add_unit(_unit("BLUE", "Escort", Vector2.ZERO, "frigate"))
	var mm := MissionManager.new()
	mm.unit_manager = um
	mm.player_faction = "BLUE"
	mm.configure({"id": "test", "objectives": {"victory": [{"type": "time_elapsed", "seconds": 60.0, "text": "Hold"}]}})
	mm.tick(100.0)
	assert_eq(mm.assessment()["percent"], 100, "nothing to deal with, nothing to command")
	mm.free()
	um.free()


# --- Neutrals and the force's own ------------------------------------------------------------

func test_each_hit_on_a_neutral_is_a_civilian_incident_charged_whatever_the_damage() -> void:
	var h := _passage()
	var um: UnitManager = h[0]
	var mm: MissionManager = h[1]
	var wm: WeaponManager = h[2]
	_give_order(um, _called(um, "Escort"), Order.set_speed(20.0))
	var trawler := _called(um, "Trawler")
	var nsm := _weapon("asm")
	nsm.short_name = "NSM"
	um.now_s = 381.0
	wm.weapon_impact.emit("BLUE", nsm, trawler, true)
	um.now_s = 1183.0
	wm.weapon_impact.emit("BLUE", _weapon("gun"), trawler, true)
	wm.weapon_impact.emit("BLUE", _weapon("gun"), trawler, true)
	wm.weapon_impact.emit("BLUE", _weapon("gun"), trawler, false)
	wm.weapon_impact.emit("RED", nsm, trawler, true)
	mm.tick(3700.0)
	var a := mm.assessment()
	assert_eq(a["neutral_hits"], 3, "three of the force's rounds struck her; a miss and the enemy's hit are not the force's incidents")
	assert_eq((a["civilian_incidents"] as Array).size(), 3)
	assert_eq(str((a["civilian_incidents"] as Array)[0]["callsign"]), "Trawler")
	assert_eq(str((a["civilian_incidents"] as Array)[0]["weapon"]), "NSM")
	assert_near(float((a["civilian_incidents"] as Array)[0]["time_s"]), 381.0, 0.01)
	assert_true(trawler.alive and trawler.health == trawler.spec.health, "she is afloat and, in this test, unmarked")
	assert_eq(int(a["percent"]), 80 - 30, "a clean commanded victory less three incidents, however light the damage")
	var text := MissionManager.assessment_text(a)
	assert_true(text.contains("Civilian −30 (3 hits on a neutral)"), "the debrief's figures name the incidents: %s" % text)
	_free(h)


func test_a_hit_by_the_force_on_its_own_ship_is_charged_as_fratricide() -> void:
	var h := _passage()
	var um: UnitManager = h[0]
	var mm: MissionManager = h[1]
	_give_order(um, _called(um, "Escort"), Order.set_speed(20.0))
	var before := int(mm.assessment()["percent"])
	(h[2] as WeaponManager).weapon_impact.emit("BLUE", _weapon("gun"), _called(um, "Maud"), true)
	(h[2] as WeaponManager).weapon_impact.emit("RED", _weapon("asm"), _called(um, "Maud"), true)
	var a := mm.assessment()
	assert_eq(a["own_fire_hits"], 1, "the enemy's hit is the enemy's")
	assert_eq(int(a["percent"]), before - int(MissionManager.OWN_FIRE_HIT_PENALTY))
	assert_true(MissionManager.assessment_text(a).contains("Own fire −10 (1 hit on your force)"), MissionManager.assessment_text(a))
	_free(h)


# --- Ammunition ---------------------------------------------------------------------------------

func test_rounds_far_beyond_what_the_target_was_worth_cost_but_a_proportionate_salvo_does_not() -> void:
	var h := _passage()
	var um: UnitManager = h[0]
	var mm: MissionManager = h[1]
	var wm: WeaponManager = h[2]
	var escort := _called(um, "Escort")
	_give_order(um, escort, Order.set_speed(20.0))
	var raider := _track_on(_called(um, "Raider"))
	var before := int(mm.assessment()["percent"])
	for i in 4:
		wm.round_fired.emit(escort, _weapon("asm"), raider)
	for i in 40:
		wm.round_fired.emit(escort, _weapon("gun"), raider)
	assert_eq(int(mm.assessment()["percent"]), before, "four missiles and a few dozen shells at a corvette are in proportion")
	for i in 20:
		wm.round_fired.emit(escort, _weapon("asm"), raider)
	var a := mm.assessment()
	assert_true(float(a["economy"]) > 5.0, "two dozen missiles at one corvette are out of proportion: %.1f" % float(a["economy"]))
	assert_true(MissionManager.assessment_text(a).contains("Ammunition −"), MissionManager.assessment_text(a))
	var spent := float(a["economy"])
	wm.round_fired.emit(_called(um, "Raider"), _weapon("asm"), _track_on(escort))
	assert_near(float(mm.assessment()["economy"]), spent, 0.001, "the enemy's expenditure is the enemy's")
	_free(h)


func test_a_round_at_a_neutral_is_all_excess() -> void:
	var h := _passage()
	var um: UnitManager = h[0]
	var mm: MissionManager = h[1]
	(h[2] as WeaponManager).round_fired.emit(_called(um, "Escort"), _weapon("asm"), _track_on(_called(um, "Trawler")))
	assert_near(float(mm.assessment()["ammunition_excess"]), MissionManager.ROUND_POINTS["asm"], 0.001)
	_free(h)


# --- The record survives a save -------------------------------------------------------------

func test_a_saved_engagement_keeps_its_conduct_record() -> void:
	var sim := Simulation.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	assert_true(sim.load_scenario("res://data/scenarios/northern_passage.json"))
	SimClock.set_paused(true)
	var frigate: Unit = null
	var neutral: Unit = null
	for u: Unit in sim.unit_manager.units:
		if u.spec.id == "rnon_ffg_fridtjof_nansen":
			frigate = u
		if u.faction == "NEUTRAL" and neutral == null:
			neutral = u
	assert_true(sim.unit_manager.issue_order(frigate, Order.move(frigate.position + Vector2(0.0, 1.0))), "a real order through the command path")
	assert_eq(sim.mission_manager.orders_given, 1, "the simulation hears the commander's orders")
	sim.weapon_manager.weapon_impact.emit("BLUE", _weapon("gun"), neutral, true)
	sim.weapon_manager.round_fired.emit(frigate, _weapon("asm"), _track_on(neutral))
	var before := sim.mission_manager.assessment()
	assert_eq(before["neutral_hits"], 1, "the simulation hears where the force's rounds land")
	var snap := sim.capture_snapshot()
	sim.mission_manager.configure(sim.scenario)
	assert_eq(sim.mission_manager.orders_given, 0, "a fresh start forgets the record")
	assert_eq(sim.restore_snapshot(snap), "")
	var after := sim.mission_manager.assessment()
	assert_eq(after["orders_given"], 1)
	assert_eq(after["neutral_hits"], 1)
	assert_near(float(after["ammunition_excess"]), float(before["ammunition_excess"]), 0.001)
	assert_eq(after["percent"], before["percent"])
	sim.free()


# --- The introductory passage played ----------------------------------------------------------

func test_northern_passage_left_to_itself_grades_under_forty() -> void:
	var sim := Simulation.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	assert_true(sim.load_scenario("res://data/scenarios/northern_passage.json"))
	SimClock.set_paused(true)
	while sim.mission_manager.result == MissionManager.Result.RUNNING and SimClock.sim_time < 2800.0:
		SimClock.advance(2.0)
	var a := sim.mission_manager.assessment()
	assert_eq(sim.mission_manager.result, MissionManager.Result.VICTORY, "the standing defences bring the freighter through")
	assert_true(int(a["percent"]) < 40, "but nobody commanded the passage: %s" % MissionManager.assessment_text(a))
	sim.free()
