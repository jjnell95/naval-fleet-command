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


func test_quantity_selects_the_airframes_the_deck_will_send() -> void:
	var base := _unit("fra_cvn_charles_de_gaulle")
	var first := _unit("fra_fighter_rafale_m")
	var cycling := _unit("fra_fighter_rafale_m")
	cycling.flight_state = Unit.FlightState.TURNAROUND
	var second := _unit("fra_fighter_rafale_m")
	var helo := _unit("fra_helo_panther")
	var third := _unit("fra_fighter_rafale_m")
	var lost := _unit("fra_fighter_rafale_m")
	lost.alive = false
	base.embarked.assign([first, cycling, helo, second, third, lost])
	var rows := AirOperations.deck_rows(base, "fra_fighter_rafale_m")
	assert_eq(rows, [first, cycling, second, third] as Array[Unit], "the type's live airframes in deck order")
	assert_eq(AirOperations.selected_rows(rows, 0), [false, false, false, false] as Array[bool], "nothing lit, nothing goes")
	assert_eq(AirOperations.selected_rows(rows, 2), [true, false, true, false] as Array[bool], "the first two ready airframes, skipping one in turnaround")
	# The deck launches the first ready airframes of the type, the same ones the indicators show.
	var ready_in_order: Array[Unit] = []
	for a in base.stowed_aircraft():
		if a.spec.id == "fra_fighter_rafale_m":
			ready_in_order.append(a)
	assert_eq(ready_in_order.slice(0, 2), [first, second] as Array[Unit], "the indicators match the deck's own choice")
	assert_eq(AirOperations.deck_rows(null, "fra_fighter_rafale_m"), [] as Array[Unit])
	base.embarked.clear()


func test_chart_station_drag_previews_then_requests_one_edit_and_escape_cancels() -> void:
	var sim := Simulation.new()
	var map := TacticalMap.new()
	var missions := AirMissionManager.new()
	sim.air_mission_manager = missions
	map.simulation = sim
	map.size = Vector2(800, 600)
	map.center_nm = Vector2.ZERO
	map.ppn = 5.0
	var m := AirMission.new()
	m.id = 7
	m.faction = map.player_faction
	m.station = Vector2.ZERO
	m.radius_nm = 10
	missions.missions.append(m)
	var at := map.world_to_screen(m.station)
	assert_eq(map.station_handle_at(at).get("mode"), TacticalMap.DragMode.STATION)
	assert_eq(map.station_handle_at(at + Vector2(50, 0)).get("mode"), TacticalMap.DragMode.RADIUS)
	var edits: Array[Vector2] = []
	map.mission_station_move_requested.connect(func(_m: AirMission, point: Vector2) -> void: edits.append(point))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	map._drag_mission = m
	map._begin_drag(TacticalMap.DragMode.STATION, press)
	var motion := InputEventMouseMotion.new()
	motion.position = at + Vector2(30, 20)
	map._handle_mouse_motion(motion)
	assert_eq(m.station, Vector2.ZERO, "dragging previews without mutating the accepted mission")
	assert_true(map.cancel_interaction_mode(), "Escape consumes an active station drag")
	assert_true(edits.is_empty())
	map._drag_mission = m
	map._begin_drag(TacticalMap.DragMode.STATION, press)
	map._handle_mouse_motion(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = motion.position
	map._handle_mouse_button(release)
	assert_eq(edits.size(), 1, "release submits exactly one authoritative revision")
	assert_eq(edits[0], map.screen_to_world(motion.position))
	assert_eq(m.station, Vector2.ZERO, "the map leaves order acceptance to the simulation")
	assert_eq(map._drag_mode, TacticalMap.DragMode.NONE)
	map.free()
	missions.free()
	sim.free()


func test_silent_submarine_hover_and_escort_handle_use_reported_state() -> void:
	var sub := _unit("cw90_los_angeles")
	sub.comms_enabled = true
	sub.depth_m = 200
	sub.position = Vector2(90, 90)
	sub.heading_deg = 90
	sub.speed_kn = 25
	sub.health = 1
	sub.fire = 0.8
	sub.comms_report = {"position": Vector2.ZERO, "heading_deg": 0.0, "speed_kn": 10.0, "depth_m": 40.0, "health": sub.spec.health}
	var lines := TacticalMap.own_hover_lines(sub, 100.0)
	assert_true(lines[2].contains("CSE 000") and lines[2].contains("10 kn") and lines[2].contains("40 m") and lines[2].contains("0% damage"), lines[2])
	var escort := _unit("cw90_los_angeles")
	escort.station_leader = sub
	escort.station_offset = Vector2(2, 5)
	assert_true(TacticalMap.escort_station_point(escort).distance_to(Vector2(2, 5)) < 0.001, "relative station follows reported guide position/course")
	escort.station_axis_deg = 90
	assert_true(TacticalMap.escort_station_point(escort).distance_to(Vector2(5, -2)) < 0.001, "fixed threat axis stays fixed even when the guide turns")
