extends TestCase


func _unit(id: String, faction := "BLUE") -> Unit:
	var u := Unit.new()
	u.spec = DataDB.platform(id)
	u.faction = faction
	u.callsign = id
	return u


func test_ready_aircraft_are_not_completed_training_sorties() -> void:
	var um := UnitManager.new()
	var a := _unit("usn_fighter_fa18e")
	um.add_unit(a)
	var objective := MissionObjective.from_dict({"type": "aircraft_recovered", "faction": "BLUE", "count": 1})
	assert_true(not objective.evaluate(um, 100), "a parked aircraft has never flown or recovered")
	a.completed_sorties = 1
	a.completed_sorties_by_facility["catobar"] = 1
	assert_true(objective.evaluate(um, 200), "a completed landing satisfies the objective")
	um.free()


func test_training_uses_actual_landing_history_and_own_faction() -> void:
	var um := UnitManager.new()
	var a := _unit("usn_fighter_fa18e")
	a.completed_sorties = 1
	a.completed_sorties_by_facility["catobar"] = 1
	var hostile := _unit("rfn_strike_su30sm", "RED")
	hostile.completed_sorties = 1
	hostile.completed_sorties_by_facility["airfield"] = 1
	um.add_unit(a)
	um.add_unit(hostile)
	var field := MissionObjective.from_dict({"type": "aircraft_recovered", "faction": "BLUE", "facility": "airfield"})
	assert_true(not field.evaluate(um, 200), "neither an opposing recovery nor a carrier landing is a friendly airfield recovery")
	a.completed_sorties += 1
	a.completed_sorties_by_facility["airfield"] = 1
	assert_true(field.evaluate(um, 500))
	var deck := MissionObjective.from_dict({"type": "aircraft_recovered", "faction": "BLUE", "facility": "deck"})
	assert_true(deck.evaluate(um, 500), "earlier carrier landing remains recorded after a diversion to shore")
	um.free()


func test_aircraft_inventory_groups_types_and_excludes_lost_airframes() -> void:
	var base := _unit("usn_cvn_nimitz")
	var ready := _unit("usn_fighter_fa18e")
	var cycling := _unit("usn_fighter_fa18e")
	cycling.flight_state = Unit.FlightState.TURNAROUND
	var helo := _unit("usn_helo_mh60r")
	var lost := _unit("usn_aew_e2d")
	lost.alive = false
	base.embarked.assign([ready, cycling, helo, lost])
	var inventory := AirOperations.inventory(base)
	assert_eq(inventory.size(), 2)
	for group in inventory:
		if group["id"] == ready.spec.id:
			assert_eq(group["total"], 2)
			assert_eq(group["ready"], 1, "turnaround does not count as launchable")
	base.embarked.clear()


func test_later_losses_do_not_erase_historical_recovery_progress() -> void:
	var um := UnitManager.new()
	for i in 2:
		var a := _unit("usn_fighter_fa18e")
		a.completed_sorties = 1
		a.completed_sorties_by_facility["airfield"] = 1
		a.alive = i == 1
		um.add_unit(a)
	var objective := MissionObjective.from_dict({"type": "aircraft_recovered", "faction": "BLUE", "facility": "airfield", "count": 2})
	assert_true(objective.evaluate(um, 300), "successful landings are counted independently of later survival")
	um.free()


func test_landing_aircraft_remain_visible_on_friendly_plot() -> void:
	var um := UnitManager.new()
	var a := _unit("usn_fighter_fa18e")
	a.flight_state = Unit.FlightState.RECOVERING
	um.add_unit(a)
	var map := TacticalMap.new()
	map.unit_manager = um
	map.player_faction = "BLUE"
	assert_true(map._own_units().has(a), "aircraft cannot disappear from the plot during approach")
	map.select_units([a])
	map.set_move_mode(true)
	assert_eq(map.interaction_mode, TacticalMap.InteractionMode.SELECT, "controlled landing does not offer a movement order that execution will reject")
	a.flight_state = Unit.FlightState.TURNAROUND
	assert_true(not map._own_units().has(a), "aircraft aboard the deck leave the plot")
	map.free()
	um.free()


func test_air_operations_exercise_has_mixed_compatible_basing() -> void:
	var scenario := ScenarioLoader.load_file("res://data/scenarios/carrier_qualification.json")
	var um := UnitManager.new()
	ScenarioLoader.populate(um, scenario)
	var facilities: Dictionary = {}
	var kinds: Dictionary = {}
	for u in um.units:
		if u.spec.aircraft_capacity > 0:
			facilities[u.spec.flight_facility()] = true
		if u.is_aircraft():
			assert_true(u.home != null and u.home.spec.can_operate(u.spec), u.callsign + " has a compatible home")
			kinds[u.spec.flight_requirement()] = true
	assert_true(facilities.has("catobar") and facilities.has("stovl") and facilities.has("airfield"))
	assert_true(kinds.has("catobar") and kinds.has("stovl") and kinds.has("runway") and kinds.has("helicopter"))
	um.free()
