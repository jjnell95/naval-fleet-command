class_name AviationSmoke
extends RefCounted
## End-to-end developer validation in the real scene, not a substitute simulation fixture.


static func run(main: Main) -> void:
	var checks: Dictionary = {}
	main.start_scenario("res://data/scenarios/carrier_qualification.json")
	main.simulation.ai_enabled = false
	main._hide_screens()
	var carrier := _find(main, "Charles de Gaulle (R 91)")
	var field := _find(main, "Bodo training airfield")
	if carrier == null or field == null:
		push_error("Aviation smoke: exercise failed to load")
		main.get_tree().quit(1)
		return
	main.map.select_units([carrier])
	SimClock.set_paused(false)
	SimClock.set_speed_index(2)
	main._toggle_air_operations()
	await main.get_tree().process_frame
	var panel := main._air_operations
	checks["planning screen pauses the mission and isolates chart input"] = panel.visible and SimClock.paused and not main.map.keyboard_navigation_enabled
	checks["selected carrier opens with its actual air wing"] = panel._base == carrier and panel._type_ids.has("fra_fighter_rafale_m") and panel._type_ids.has("fra_aew_e2c")
	panel._type_id = "fra_fighter_rafale_m"
	panel._refresh_launch()
	panel._count.value = 2
	panel._launch_selected()
	var launched: Array[Unit] = []
	var non_fighters_ready := true
	for a in carrier.embarked:
		if a.flight_state == Unit.FlightState.LAUNCHING:
			launched.append(a)
		if a.spec.id != "fra_fighter_rafale_m" and not a.ready_to_launch():
			non_fighters_ready = false
	checks["type and quantity controls launch exactly two Rafales"] = launched.size() == 2 and launched.all(func(a: Unit) -> bool: return a.spec.id == "fra_fighter_rafale_m") and non_fighters_ready
	if launched.size() != 2:
		_finish(main, checks)
		return
	main._close_air_operations()
	checks["Close restores the running clock and selected speed"] = not SimClock.paused and SimClock.speed_index == 2 and main.map.keyboard_navigation_enabled
	SimClock.advance(180.0)
	var divert := launched[0]
	var recover := launched[1]
	checks["both selected airframes become airborne"] = divert.airborne() and recover.airborne()
	main.map.select_units([divert])
	main._toggle_air_operations()
	checks["an aircraft selection opens its landing controls"] = panel._aircraft == divert and panel._destinations.has(field) and panel._destinations.has(carrier)
	panel._destination.select(panel._destinations.find(field))
	panel._return_selected()
	checks["landing order reserves shore destination while retaining home"] = divert.returning and divert.recovery_base == field and divert.home == carrier
	panel._aircraft = recover
	panel._refresh_recovery()
	checks["switching airframes defaults to that aircraft home"] = panel._destinations[panel._destination.selected] == carrier
	panel._return_selected()
	checks["second airframe receives carrier recovery"] = recover.returning and recover.recovery_base == carrier
	var weapon_id: String = divert.spec.weapon_loadout.keys()[0]
	divert.magazines[weapon_id] = 0
	main._close_air_operations()
	var elapsed := 0.0
	while elapsed < 1500.0 and divert.flight_state != Unit.FlightState.RECOVERING:
		SimClock.advance(5.0)
		elapsed += 5.0
	main.map.select_units([divert])
	main._toggle_air_operations()
	checks["final approach shows the committed destination and keeps the aircraft on the chart"] = divert.flight_state == Unit.FlightState.RECOVERING and panel._destination.get_item_text(0) == field.callsign and panel._destination.disabled and panel._return.disabled and not panel._focus.disabled
	main._close_air_operations()
	SimClock.advance(1500.0 - elapsed)
	checks["diverted aircraft lands at shore and transfers membership"] = divert.completed_sorties == 1 and divert.home == field and field.embarked.has(divert) and not carrier.embarked.has(divert)
	checks["other aircraft lands aboard its carrier"] = recover.completed_sorties == 1 and recover.home == carrier
	checks["landing enters turnaround rather than instant ready state"] = divert.flight_state == Unit.FlightState.TURNAROUND and recover.flight_state == Unit.FlightState.TURNAROUND
	checks["exercise completes only after both kinds of landing"] = main.simulation.mission_manager.result == MissionManager.Result.VICTORY
	checks["shore recovery releases its incoming reservation"] = divert.recovery_base == null and not field.inbound_aircraft.has(divert)
	SimClock.advance(3800.0)
	checks["diversion refuels but cannot create unavailable foreign ordnance"] = divert.ready_to_launch() and is_equal_approx(divert.fuel_fraction(), 1.0) and divert.magazine_count(weapon_id) == 0 and int(field.aviation_stores.get(weapon_id, 0)) == 0
	main._close_report()
	main.map.select_units([field])
	SimClock.set_paused(true)
	main._toggle_air_operations()
	checks["diverted aircraft type becomes available at new airfield"] = panel._base == field and panel._type_ids.has(divert.spec.id)
	panel._type_id = divert.spec.id
	panel._refresh_launch()
	panel._count.value = 1
	panel._launch_selected()
	checks["recovered type can launch again from shore"] = divert.flight_state == Unit.FlightState.LAUNCHING
	main._close_air_operations()
	checks["closing planning preserves an existing pause"] = SimClock.paused and main.map.keyboard_navigation_enabled
	main.start_scenario("res://data/scenarios/carrier_qualification.json")
	checks["scenario reset clears stale aviation selections"] = panel._aircraft == null and panel._base == null and panel._bases.is_empty() and panel._destinations.is_empty()
	var escort := _find(main, "Andrea Doria (D 553)")
	main.map.select_units([escort])
	main._toggle_air_operations()
	panel._launch_selected()
	main._close_air_operations()
	main._toggle_air_operations()
	checks["reopening a selected one-aircraft deck during launch keeps that host and its cycling aircraft"] = escort.launch_spots_busy() == 1 and panel._base == escort and panel._deck_rows == escort.embarked and panel._launch.disabled
	main._close_air_operations()
	await _check_roster_navigation(main, checks)
	_finish(main, checks)


static func _check_roster_navigation(main: Main, checks: Dictionary) -> void:
	# A crowded airborne roster and a previously inspected contact far from the air wing.
	var airborne: Array[Unit] = []
	for a: Unit in main.simulation.unit_manager.get_faction_units(main.simulation.player_faction):
		if a.is_aircraft():
			a.flight_state = Unit.FlightState.AIRBORNE
			airborne.append(a)
	var wanted := airborne.back() as Unit
	var reported_ship := Unit.new()
	reported_ship.faction = "NEUTRAL"
	reported_ship.spec = DataDB.platform("civ_fishing_trawler")
	var held := main.simulation.track_manager.report_intel(main.simulation.player_faction, reported_ship, wanted.position + Vector2(150, 90), 2.0, SimClock.sim_time, "Exercise contact report")
	main.map.select_units([wanted])
	main.map.select_track(held)
	var zoom := main.map.ppn
	main._toggle_air_operations()
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	var panel := main._air_operations
	var row := panel._roster.get_selected()
	var bounds := panel._roster.get_item_area_rect(row) if row != null else Rect2()
	var visible_row := row != null and bounds.position.y >= 0.0 and bounds.end.y <= panel._roster.size.y
	if not visible_row or not panel._roster.has_focus():
		print("[Aviation smoke] Hooked row ", bounds, " in roster ", panel._roster.size, ", focused ", panel._roster.has_focus(), ", scroll ", panel._roster.get_scroll())
	checks["F3 focuses and scrolls to the hooked airframe in a crowded airborne roster"] = panel._roster.has_focus() and visible_row and row.get_metadata(0) == wanted
	panel._focus.pressed.emit()
	checks["Show on Chart centers that aircraft at the same scale and keeps the previously held contact"] = not panel.visible and main.map.selected == [wanted] and main.map.selected_track == held and is_equal_approx(main.map.ppn, zoom) and main.map.world_to_screen(wanted.position).distance_to(main.map.unobstructed_chart_rect().get_center()) < 1.0
	main._toggle_world_full()
	main._toggle_air_operations()
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	for down: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_ENTER
		key.pressed = down
		main.get_viewport().push_input(key, true)
		await main.get_tree().process_frame
	checks["Enter on the hooked roster row returns from full-screen 3D to its aircraft on the visible chart"] = not panel.visible and main.map.selected == [wanted] and not main._world_full and main.map.is_visible_in_tree()
	if panel.visible:
		main._close_air_operations()


static func _find(main: Main, callsign: String) -> Unit:
	for u in main.simulation.unit_manager.units:
		if u.callsign == callsign:
			return u
	return null


static func _finish(main: Main, checks: Dictionary) -> void:
	var failed := 0
	for label in checks:
		print("[Aviation smoke] %s %s" % ["PASS" if checks[label] else "FAIL", label])
		if not checks[label]:
			failed += 1
	print("[Aviation smoke] %d checks, %d failed" % [checks.size(), failed])
	main.get_tree().quit(1 if failed else 0)
