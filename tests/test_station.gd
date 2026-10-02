extends TestCase
## The standing assignment: a patrol circuit or a formation station survives the temporary tasks
## that interrupt it (investigate, attack, refuelling) and is ended only by an explicit replacement
## order. Return to Station resumes it; auto-return does so when a task ends, never over a newer
## order; fuel and recovery outrank the station.

const DT := 0.25


func _ship(pos := Vector2.ZERO, callsign := "") -> Unit:
	var u := Unit.new()
	u.spec = DataDB.platform("usn_ddg_arleigh_burke_iia")
	for sid in u.spec.sensor_ids:
		u.sensors.append(DataDB.sensor(sid))
	for wid: String in u.spec.weapon_loadout:
		var w := DataDB.weapon(wid)
		if w != null:
			u.weapons.append(w)
			u.magazines[wid] = int(u.spec.weapon_loadout[wid])
	u.faction = "BLUE"
	u.callsign = callsign
	u.position = pos
	u.health = u.spec.health
	return u


func _track(pos: Vector2, id := "0101") -> Track:
	var t := Track.new()
	t.id = id
	t.owner_faction = "BLUE"
	t.position = pos
	return t


func _run(um: UnitManager, seconds: float, av: AviationManager = null, now_start := 0.0) -> float:
	var now := now_start
	for i in int(seconds / DT):
		now += DT
		um.tick(DT, now)
		if av != null:
			av.tick(DT, now)
	return now


func _screen(um: UnitManager) -> Array[Unit]:
	var guide := _ship(Vector2.ZERO, "Guide")
	var escort := _ship(Vector2(4.0, 6.0), "Escort")
	guide.heading_deg = 0.0
	guide.ordered_speed_kn = 12.0
	guide.speed_kn = 12.0
	um.add_unit(guide)
	um.add_unit(escort)
	var form := Order.form_up(guide, Vector2(4.0, 6.0))
	form.station_label = "SCREEN STATION"
	assert_true(um.issue_order(escort, form))
	return [guide, escort]


func test_formation_and_patrol_orders_record_the_standing_assignment() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var pair := _screen(um)
	var escort: Unit = pair[1]
	assert_eq(escort.station_kind, "formation")
	assert_eq(escort.station_leader, pair[0])
	assert_eq(escort.station_offset, Vector2(4.0, 6.0))
	assert_eq(escort.station_label, "SCREEN STATION")
	assert_true(escort.on_station())
	var picket := _ship(Vector2(0, 40), "Picket")
	um.add_unit(picket)
	assert_true(um.issue_order(picket, Order.patrol_box(Vector2(-5, 35), Vector2(5, 45))))
	assert_eq(picket.station_kind, "patrol")
	assert_eq(picket.station_route.size(), 4)
	assert_true(picket.on_station())
	um.free()


func test_escort_investigates_and_returns_to_its_screen_station() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var pair := _screen(um)
	var guide: Unit = pair[0]
	var escort: Unit = pair[1]
	escort.auto_return = true
	var t := _track(Vector2(12.0, 14.0))
	var resumed: Array = []
	um.station_resumed.connect(func(u: Unit, why: String) -> void: resumed.append([u, why]))
	assert_true(um.issue_order(escort, Order.investigate(t)))
	assert_eq(escort.formation_leader, null, "the escort leaves the screen to look")
	assert_eq(escort.station_kind, "formation", "but the screen station is kept")
	assert_true(not escort.on_station())
	var now := _run(um, 60.0)
	t.classification = Track.Classification.CLASS_KNOWN
	t.known_class = "Trawler"
	_run(um, DT, null, now)
	assert_eq(escort.formation_leader, guide, "auto-return re-forms on the same guide")
	assert_eq(escort.formation_offset, Vector2(4.0, 6.0), "at the same station")
	assert_eq(resumed.size(), 1)
	assert_eq(resumed[0], [escort, "Contact classified"])
	um.free()


func test_without_auto_return_the_escort_holds_until_told_to_return() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var pair := _screen(um)
	var guide: Unit = pair[0]
	var escort: Unit = pair[1]
	var t := _track(Vector2(12.0, 14.0))
	um.issue_order(escort, Order.investigate(t))
	var now := _run(um, 30.0)
	t.classification = Track.Classification.CLASS_KNOWN
	_run(um, DT, null, now)
	assert_eq(escort.formation_leader, null, "the classic behaviour: hold at the contact")
	assert_eq(escort.station_kind, "formation", "the station is still there to go back to")
	assert_true(um.issue_order(escort, Order.return_to_station()))
	assert_eq(escort.formation_leader, guide)
	assert_true(escort.on_station())
	um.free()


func test_patrol_resumes_at_the_nearest_corner_after_an_attack_ends() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var picket := _ship(Vector2(0, 0), "Picket")
	um.add_unit(picket)
	picket.auto_return = true
	var box := Order.patrol_box(Vector2(-10, -10), Vector2(10, 10))
	assert_true(um.issue_order(picket, box))
	var t := _track(Vector2(30, 30))
	t.identity = "HOSTILE"
	t.domain = "surface"
	t.classification = Track.Classification.SURFACE
	assert_true(um.issue_order(picket, Order.attack(t)))
	assert_true(not picket.patrol_active, "the attack suspends the circuit")
	picket.position = Vector2(12, 11)  # wherever the attack left her
	um._end_attack(picket, t, "Target destroyed")
	assert_true(picket.patrol_active, "and the circuit is resumed when it ends")
	assert_eq(picket.waypoints[0], Vector2(10, 10), "starting from the corner nearest her")
	assert_eq(picket.waypoints.size(), 4)
	um.free()


func test_an_explicit_transit_replaces_the_station_and_prevents_a_later_return() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var pair := _screen(um)
	var escort: Unit = pair[1]
	escort.auto_return = true
	var t := _track(Vector2(12.0, 14.0))
	um.issue_order(escort, Order.investigate(t))
	var now := _run(um, 20.0)
	assert_true(um.issue_order(escort, Order.move(Vector2(-20, 0))))
	assert_eq(escort.station_kind, "", "a new transit is a replacement order")
	t.classification = Track.Classification.CLASS_KNOWN
	_run(um, 5.0, null, now)
	assert_eq(escort.formation_leader, null, "no unexpected return to the old screen")
	assert_eq(escort.waypoints, [Vector2(-20, 0)], "the newer order stands")
	assert_true(not um.issue_order(escort, Order.return_to_station()))
	assert_eq(UnitManager.station_rejection(escort), "No station assigned")
	um.free()


func test_a_late_task_end_never_overwrites_a_newer_order() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var picket := _ship(Vector2(0, 0), "Picket")
	um.add_unit(picket)
	picket.auto_return = true
	um.issue_order(picket, Order.patrol_box(Vector2(-10, -10), Vector2(10, 10)))
	var t := _track(Vector2(30, 30))
	um.issue_order(picket, Order.investigate(t))
	var started := picket.task_generation
	# A crew order (an air mission's interception, say) changes course without ending the station.
	var crew := Order.move(Vector2(0, 50))
	crew.origin = "crew"
	um.issue_order(picket, crew)
	assert_eq(picket.station_kind, "patrol", "a crew order keeps the station")
	um._return_after_task(picket, started, "Contact classified")
	assert_true(not picket.patrol_active, "the task's generation is stale: the newer order stands")
	assert_eq(picket.waypoints, [Vector2(0, 50)])
	um.free()


func test_the_guide_lost_while_an_escort_is_away_passes_the_station_on() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var guide := _ship(Vector2.ZERO, "Guide")
	var second := _ship(Vector2(-4, 6), "Second")
	var away := _ship(Vector2(4, 6), "Away")
	for u in [guide, second, away]:
		um.add_unit(u)
	um.issue_order(second, Order.form_up(guide, Vector2(-4, 6)))
	um.issue_order(away, Order.form_up(guide, Vector2(4, 6)))
	um.issue_order(away, Order.investigate(_track(Vector2(20, 20))))
	guide.alive = false
	_run(um, DT)
	assert_eq(second.formation_leader, null, "the consort on station takes over as guide")
	assert_eq(second.station_kind, "", "and has no station of its own now")
	assert_eq(away.station_leader, second, "the absent consort's station moves to the new guide")
	assert_eq(away.station_offset, Vector2(4, 6), "at the offset it was given")
	assert_true(um.issue_order(away, Order.return_to_station()))
	assert_eq(away.formation_leader, second)
	um.free()


func test_the_guide_lost_with_nobody_on_station_leaves_a_clear_reason() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var guide := _ship(Vector2.ZERO, "Guide")
	var away := _ship(Vector2(4, 6), "Away")
	um.add_unit(guide)
	um.add_unit(away)
	um.issue_order(away, Order.form_up(guide, Vector2(4, 6)))
	um.issue_order(away, Order.investigate(_track(Vector2(20, 20))))
	guide.alive = false
	_run(um, DT)
	assert_eq(away.station_kind, "", "the only consort now guides the group")
	assert_eq(away.station_note, "Formation guide lost: now guiding the group")
	assert_true(not um.issue_order(away, Order.return_to_station()))
	um.free()


# --- Aircraft: refuelling preserves the station, fuel and recovery outrank it ----------------

func _air_spec(tanker := false) -> PlatformSpec:
	var p := PlatformSpec.new()
	p.short_name = "Tanker Test" if tanker else "Fighter Test"
	p.domain = "air"
	p.can_hover = false
	p.cruise_speed_kn = 280.0 if tanker else 400.0
	p.max_speed_kn = 320.0 if tanker else 900.0
	p.turn_rate_deg_s = 6.0
	p.accel_kn_s = 8.0
	p.health = 20.0
	p.cruise_altitude_m = 8000.0
	p.max_altitude_m = 15000.0
	p.altitude_rate_m_s = 50.0
	p.endurance_s = 20000.0 if tanker else 3600.0
	p.tanker_offload_s = 6000.0 if tanker else 0.0
	p.can_refuel = not tanker
	p.launch_time_s = 60.0
	p.recovery_time_s = 60.0
	p.launch_requirement = "catobar"
	return p


func _carrier() -> Unit:
	var p := PlatformSpec.new()
	p.short_name = "CVN Test"
	p.domain = "surface"
	p.category = "carrier"
	p.max_speed_kn = 30.0
	p.cruise_speed_kn = 16.0
	p.health = 400.0
	p.aircraft_capacity = 8
	p.aviation_facility = "catobar"
	p.launch_spots = 4
	p.recovery_spots = 1
	p.turnaround_s = 600.0
	var u := Unit.new()
	u.spec = p
	u.faction = "BLUE"
	u.callsign = "Carrier"
	u.health = p.health
	return u


func _airborne(spec: PlatformSpec, home: Unit, pos: Vector2, callsign: String) -> Unit:
	var a := Unit.new()
	a.spec = spec
	a.faction = "BLUE"
	a.callsign = callsign
	a.health = spec.health
	a.home = home
	home.embarked.append(a)
	a.flight_state = Unit.FlightState.AIRBORNE
	a.position = pos
	a.fuel_s = spec.endurance_s
	a.tanker_offload_s = spec.tanker_offload_s
	a.ordered_speed_kn = spec.cruise_speed_kn
	a.speed_kn = spec.cruise_speed_kn
	a.altitude_m = spec.cruise_altitude_m
	a.ordered_altitude_m = spec.cruise_altitude_m
	return a


func test_refuelling_preserves_a_valid_patrol_assignment() -> void:
	Terrain.clear()
	var ship := _carrier()
	var jet := _airborne(_air_spec(), ship, Vector2(0, 40), "Fighter")
	var tanker := _airborne(_air_spec(true), ship, Vector2(0, 44), "Tanker")
	var um := UnitManager.new()
	for u in [ship, jet, tanker]:
		um.add_unit(u)
	var av := AviationManager.new()
	av.unit_manager = um
	var cap := Order.patrol_box(Vector2(-15, 30), Vector2(15, 50))
	cap.station_label = "CAP STATION"
	assert_true(um.issue_order(jet, cap))
	jet.fuel_s = jet.spec.endurance_s * 0.27
	var resumed: Array[String] = []
	um.station_resumed.connect(func(_u: Unit, why: String) -> void: resumed.append(why))
	var now := _run(um, 30.0, av)
	assert_eq(jet.tanking_on, tanker, "bingo sends it to the basket")
	assert_true(not jet.patrol_active, "the circuit is suspended while it refuels")
	assert_eq(jet.station_kind, "patrol", "but not forgotten")
	_run(um, 900.0, av, now)
	assert_eq(jet.tanking_on, null, "topped off")
	assert_true(jet.patrol_active, "and back on its CAP station")
	assert_eq(jet.station_label, "CAP STATION")
	assert_true(resumed.has("Refuelled"))
	av.free()
	um.free()


func test_bingo_and_recovery_outrank_the_station_and_landing_ends_the_sortie() -> void:
	Terrain.clear()
	var ship := _carrier()
	var jet := _airborne(_air_spec(), ship, Vector2(0, 30), "Fighter")
	var um := UnitManager.new()
	um.add_unit(ship)
	um.add_unit(jet)
	var av := AviationManager.new()
	av.unit_manager = um
	jet.auto_return = true
	um.issue_order(jet, Order.patrol_box(Vector2(-15, 25), Vector2(15, 45)))
	jet.fuel_s = jet.spec.endurance_s * 0.27
	var now := _run(um, 5.0, av)
	assert_true(jet.returning, "no tanker: the deck")
	assert_eq(jet.station_kind, "patrol", "the station is held until the sortie ends")
	assert_eq(UnitManager.station_rejection(jet), "Aircraft committed to fuel or recovery")
	assert_true(not um.issue_order(jet, Order.return_to_station()), "fuel outranks the station")
	var t := _track(Vector2(0, 20))
	t.identity = "HOSTILE"
	assert_true(not um.issue_order(jet, Order.investigate(t)), "and combat tasking")
	_run(um, 900.0, av, now)
	assert_true(jet.flight_state in [Unit.FlightState.TURNAROUND, Unit.FlightState.STOWED], "it landed")
	assert_eq(jet.station_kind, "", "the landing ends the sortie's station")
	av.free()
	um.free()


func test_auto_return_order_is_routine_and_reported() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var u := _ship()
	um.add_unit(u)
	assert_true(um.issue_order(u, Order.set_auto_return(true)))
	assert_true(u.auto_return)
	assert_eq(Order.set_auto_return(false).describe(), "AUTO RETURN TO STATION OFF")
	assert_eq(Order.return_to_station().describe(), "RETURN TO STATION")
	um.free()


# --- What the commander sees -------------------------------------------------------------

func _find(items: Array, text: String) -> Dictionary:
	for entry: Dictionary in items:
		if str(entry.get("text", "")).begins_with(text):
			return entry
		var found := _find(entry.get("children", []), text)
		if not found.is_empty():
			return found
	return {}


func test_the_orders_line_and_menu_offer_the_way_back_to_station() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var pair := _screen(um)
	var escort: Unit = pair[1]
	assert_eq(DataDisplay.orders_text(escort), "Station on Guide")
	var t := _track(Vector2(12.0, 14.0))
	um.issue_order(escort, Order.investigate(t))
	assert_true(DataDisplay.orders_text(escort).begins_with("Investigate track"))
	t.classification = Track.Classification.CLASS_KNOWN
	_run(um, DT)
	assert_true(DataDisplay.orders_text(escort).ends_with("S returns to screen station"), DataDisplay.orders_text(escort))
	var back := _find(CdsMenus.orders_items([escort], null, true, true), "Return to station")
	assert_true(not back.is_empty(), "the own-platform menu offers the return")
	assert_true(not bool(back["disabled"]))
	assert_eq((back["action"]["order"] as Order).type, Order.Type.RETURN_TO_STATION)
	var auto := _find(CdsMenus.orders_items([escort], null, true, true), "On")
	assert_eq((auto["action"]["order"] as Order).type, Order.Type.SET_AUTO_RETURN)
	pair[0].alive = false
	_run(um, DT)
	back = _find(CdsMenus.orders_items([escort], null, true, true), "Return to station")
	assert_true(back.is_empty(), "with the guide gone the escort guides the group and has no station")
	assert_eq(DataDisplay.orders_text(escort).contains("guiding the group"), true, DataDisplay.orders_text(escort))
	um.free()


# --- Defects found by probing the first cut ------------------------------------------------

func test_a_refused_landing_order_keeps_the_station_and_the_generation() -> void:
	Terrain.clear()
	var ship := _carrier()
	var jet := _airborne(_air_spec(), ship, Vector2(0, 30), "Fighter")
	var enemy := _carrier()
	enemy.faction = "RED"
	var um := UnitManager.new()
	for u in [ship, jet, enemy]:
		um.add_unit(u)
	um.issue_order(jet, Order.patrol_box(Vector2(-15, 25), Vector2(15, 45)))
	var before := jet.order_generation
	assert_true(not um.issue_order(jet, Order.return_to_base(enemy)), "a hostile deck is no place to land")
	assert_eq(jet.station_kind, "patrol", "the refusal leaves the station alone")
	assert_eq(jet.order_generation, before)
	um.free()


func test_steering_a_returning_or_tanking_aircraft_is_refused_not_overwritten() -> void:
	Terrain.clear()
	var ship := _carrier()
	var jet := _airborne(_air_spec(), ship, Vector2(0, 30), "Fighter")
	var um := UnitManager.new()
	um.add_unit(ship)
	um.add_unit(jet)
	jet.returning = true
	for o: Order in [Order.move(Vector2(40, 40)), Order.set_course(90), Order.set_speed(200), Order.stop()]:
		assert_true(not um.issue_order(jet, o), o.describe())
	jet.returning = false
	jet.tanking_on = ship
	assert_true(not um.issue_order(jet, Order.move(Vector2(40, 40))), "the tanker join is the aviation layer's")
	jet.tanking_on = null
	um.free()


func test_steering_a_consort_takes_it_out_of_formation_and_ends_the_station() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var pair := _screen(um)
	var escort: Unit = pair[1]
	assert_true(um.issue_order(escort, Order.clear_waypoints()))
	assert_true(escort.on_station(), "clearing a route a consort does not have changes nothing")
	assert_true(um.issue_order(escort, Order.move(Vector2(-20, -20))))
	_run(um, DT)
	assert_eq(escort.formation_leader, null, "the consort leaves the formation to go where it was sent")
	assert_eq(escort.station_kind, "", "an explicit order replaces the station")
	assert_true(not escort.waypoints.is_empty(), "and the formation no longer clears its route")
	um.free()


func test_break_formation_keeps_a_patrol_station_for_a_later_return() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var picket := _ship(Vector2.ZERO, "Picket")
	um.add_unit(picket)
	um.issue_order(picket, Order.patrol_box(Vector2(-10, -10), Vector2(10, 10)))
	um.issue_order(picket, Order.break_formation())
	assert_eq(picket.station_kind, "patrol", "breaking a formation is not a new plan for a patrolling ship")
	assert_true(um.issue_order(picket, Order.return_to_station()))
	assert_true(picket.patrol_active)
	um.free()


func test_landing_and_launch_clear_old_task_results() -> void:
	Terrain.clear()
	var ship := _carrier()
	var jet := _airborne(_air_spec(), ship, Vector2(0, 1), "Fighter")
	var um := UnitManager.new()
	um.add_unit(ship)
	um.add_unit(jet)
	var av := AviationManager.new()
	av.unit_manager = um
	jet.attack_result = "Magazines empty"
	jet.attack_track_id = "0107"
	av.request_return(jet, ship)
	_run(um, 400.0, av)
	assert_true(jet.flight_state in [Unit.FlightState.TURNAROUND, Unit.FlightState.STOWED])
	assert_eq(jet.attack_result, "", "a landed airframe does not still report its last engagement")
	assert_eq(DataDisplay.orders_text(jet), "Refuel and rearm" if jet.flight_state == Unit.FlightState.TURNAROUND else "Ready on deck")
	av.free()
	um.free()


func test_return_after_a_flank_speed_intercept_resumes_at_station_speed() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var picket := _ship(Vector2.ZERO, "Picket")
	um.add_unit(picket)
	picket.ordered_speed_kn = 15.0
	um.issue_order(picket, Order.patrol_box(Vector2(-3, -3), Vector2(3, 3)))
	var t := _track(Vector2(30, 0))
	um.issue_order(picket, Order.investigate(t))
	um.issue_order(picket, Order.set_speed(30.0))
	assert_eq(UnitManager.station_rejection(picket), "", "the circuit is judged at its own speed")
	assert_true(um.issue_order(picket, Order.return_to_station()))
	assert_eq(picket.ordered_speed_kn, 15.0, "back at the circuit's speed, not the intercept's")
	um.free()


func test_a_crew_return_lets_an_evasion_run_its_course() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var pair := _screen(um)
	var escort: Unit = pair[1]
	escort.auto_return = true
	var t := _track(Vector2(12.0, 14.0))
	um.issue_order(escort, Order.investigate(t))
	escort.evasion_remaining_s = 40.0
	escort.evasion_course_deg = 200.0
	t.classification = Track.Classification.CLASS_KNOWN
	_run(um, DT)
	assert_eq(escort.formation_leader, pair[0], "the station is taken up")
	assert_true(escort.evasion_remaining_s > 30.0, "but the turn-away is not cut short")
	assert_true(um.issue_order(escort, Order.return_to_station()))
	assert_eq(escort.evasion_remaining_s, 0.0, "the commander's own return does end it")
	um.free()


func test_a_new_guide_carries_on_with_the_lost_guides_route() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var guide := _ship(Vector2.ZERO, "Guide")
	var escort := _ship(Vector2(4, 6), "Escort")
	um.add_unit(guide)
	um.add_unit(escort)
	um.issue_order(guide, Order.move(Vector2(0, 60)))
	um.issue_order(guide, Order.set_speed(14.0))
	um.issue_order(escort, Order.form_up(guide, Vector2(4, 6)))
	guide.alive = false
	_run(um, DT)
	assert_eq(escort.formation_leader, null)
	assert_eq(escort.waypoints, [Vector2(0, 60)], "the convoy keeps steaming for the gate")
	assert_eq(escort.ordered_speed_kn, 14.0)
	um.free()


func test_ai_consorts_keep_their_formation() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var tm := TrackManager.new()
	var guide := _ship(Vector2.ZERO, "Guide")
	var consort := _ship(Vector2(4, 6), "Consort")
	guide.faction = "RED"
	consort.faction = "RED"
	um.add_unit(guide)
	um.add_unit(consort)
	um.issue_order(consort, Order.form_up(guide, Vector2(4, 6)))
	var ai := AIController.new()
	ai.faction = "RED"
	ai.unit_manager = um
	ai.track_manager = tm
	ai.threat_manager = ThreatManager.new()
	ai.weapon_manager = WeaponManager.new()
	ai.weapon_manager.unit_manager = um
	ai.weapon_manager.track_manager = tm
	for i in 5:
		ai.tick(i * 2.0)
	assert_eq(consort.formation_leader, guide, "the AI does not steer a consort out of its station")
	assert_eq(consort.station_kind, "formation")
	ai.weapon_manager.free()
	ai.threat_manager.free()
	ai.free()
	tm.free()
	um.free()
