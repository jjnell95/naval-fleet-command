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
	main._close_air_operations(true)
	checks["execute resumes at real time"] = not SimClock.paused and SimClock.speed_index == 0 and main.map.keyboard_navigation_enabled
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
	main._close_air_operations(true)
	SimClock.advance(1500.0)
	checks["diverted aircraft lands at shore and transfers membership"] = divert.completed_sorties == 1 and divert.home == field and field.embarked.has(divert) and not carrier.embarked.has(divert)
	checks["other aircraft lands aboard its carrier"] = recover.completed_sorties == 1 and recover.home == carrier
	checks["landing enters turnaround rather than instant ready state"] = divert.flight_state == Unit.FlightState.TURNAROUND and recover.flight_state == Unit.FlightState.TURNAROUND
	checks["exercise completes only after both kinds of landing"] = main.simulation.mission_manager.result == MissionManager.Result.VICTORY
	checks["shore recovery releases its incoming reservation"] = divert.recovery_base == null and not field.inbound_aircraft.has(divert)
	SimClock.advance(3800.0)
	checks["turnaround refuels rearms and makes aircraft ready"] = divert.ready_to_launch() and is_equal_approx(divert.fuel_fraction(), 1.0) and divert.magazine_count(weapon_id) == int(divert.spec.weapon_loadout[weapon_id])
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
	main._close_air_operations(false)
	checks["closing planning preserves an existing pause"] = SimClock.paused and main.map.keyboard_navigation_enabled
	main.start_scenario("res://data/scenarios/carrier_qualification.json")
	checks["scenario reset clears stale aviation selections"] = panel._aircraft == null and panel._base == null and panel._bases.is_empty() and panel._destinations.is_empty()
	_finish(main, checks)


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
