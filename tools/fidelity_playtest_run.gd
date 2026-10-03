extends "res://tools/air_mission_playtest_run.gd"
## Existing missions edited by viewport gestures, expanded data, and delayed submarine orders.
## Scenario load and camera framing are harness setup; every tested command uses real input.

func run(scene_tree: SceneTree) -> void:
	tree = scene_tree
	capture = OS.get_cmdline_user_args().has("--capture")
	output_dir = "res://work/fidelity/native"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output-dir="): output_dir = arg.trim_prefix("--output-dir=")
	DirAccess.make_dir_recursive_absolute(output_dir)
	CommanderLog.path_override = output_dir.path_join("commander_log.json")
	SaveGame.root_override = output_dir.path_join("saves")
	errors = load("res://tests/test_error_log.gd").new()
	OS.add_logger(errors)
	main = load("res://scenes/main/Main.tscn").instantiate()
	tree.root.add_child(main)
	await _frames()
	main.start_scenario(CARRIER_WATCH)
	await _take_command()
	Debug.log_events = false
	main._command_guide.enabled = false
	main._command_guide.hide()
	facts["interface_scale"] = InterfaceScale.percent
	await _mission_editing()
	await _expanded_readout()
	await _submarine_windows()
	_finish()


func _mission_editing() -> void:
	var carrier := _find("USS Dwight D. Eisenhower (CVN 69)")
	checks["carrier exists"] = carrier != null
	if carrier == null: return
	main.map.select_units([carrier])
	main.map.center_on_selection()
	await _key(KEY_F3)
	var panel := main._air_operations
	var tabs := panel._plan_tabs.get_tab_bar()
	await _click(tabs.global_position + tabs.get_tab_rect(1).get_center())
	await _click_control(panel._mission_picker)
	await _popup_click(panel._mission_picker.get_popup(), AirMission.Kind.CAP)
	var tomcat := panel._type_ids.find("cw90_f14a")
	if tomcat >= 0 and panel._type_picker.selected != tomcat:
		await _click_control(panel._type_picker)
		await _popup_click(panel._type_picker.get_popup(), tomcat)
	checks["mission planning controls fit"] = _fits(panel._launch) and _fits(panel._station_button) and _fits(panel._radius)
	await _click_control(panel._station_button)
	var station := carrier.position + Vector2(8, 22)
	await _chart_click(station)
	await _click_control(panel._launch)
	var missions := main.simulation.air_mission_manager.active_missions("BLUE")
	checks["one CAP assigned through controls"] = missions.size() == 1
	if missions.is_empty(): return
	var mission: AirMission = missions[0]
	var aircraft := mission.aircraft.duplicate()
	var launched := mission.launched_total
	checks["CAP has assigned aircraft"] = not aircraft.is_empty()
	await _click_control(panel._back)
	main.map.center_on(mission.station)
	main.map.ppn = 4.0
	main.map.queue_redraw()
	await _frames()
	var moved := mission.station + Vector2(6, -4)
	await _drag_chart(mission.station, moved)
	checks["dragging station changes the existing mission"] = mission.station.distance_to(moved) < 0.5 and main.simulation.air_mission_manager.active_missions("BLUE").size() == 1
	checks["station drag preserves assigned aircraft"] = mission.aircraft == aircraft and mission.launched_total == launched
	await _shot("mission-station-moved")
	var before_radius := mission.radius_nm
	await _drag_chart(mission.station + Vector2(before_radius, 0), mission.station + Vector2(before_radius + 3.0, 0))
	checks["east handle resizes existing mission"] = absf(mission.radius_nm - before_radius - 3.0) < 0.5
	checks["radius drag preserves aircraft and launch count"] = mission.aircraft == aircraft and mission.launched_total == launched
	await _shot("mission-area-resized")
	# Escape cancels a preview instead of committing a station move or leaving the game.
	var retained_station := mission.station
	await _drag_chart(mission.station, mission.station + Vector2(-8, 3), true)
	checks["Escape cancels station drag"] = mission.station == retained_station and not main._menu.visible
	await _key(KEY_F3)
	await _frames()
	var lower := panel._lower_tabs.get_tab_bar()
	await _click(lower.global_position + lower.get_tab_rect(1).get_center())
	checks["Edit mission action fits"] = _fits(panel._edit_mission) and not panel._edit_mission.disabled
	await _click_control(panel._edit_mission)
	checks["Edit opens same mission"] = panel._editing_mission == mission and panel._launch.text.contains("UPDATE")
	var edit_radius := mission.radius_nm + 2.0
	await _set_number(panel._radius, int(edit_radius))
	await _shot("edit-existing-mission")
	await _click_control(panel._launch)
	checks["Update changes radius on same mission"] = is_equal_approx(mission.radius_nm, edit_radius) and main.simulation.air_mission_manager.active_missions("BLUE").size() == 1
	checks["Update retains aircraft without launching replacements"] = mission.aircraft == aircraft and mission.launched_total == launched
	checks["mission report has a timestamp"] = mission.last_report().contains(":")
	await _shot("mission-updated")
	await _click_control(panel._back)


func _expanded_readout() -> void:
	var cruiser := _find("USS Ticonderoga (CG 47)")
	if cruiser == null:
		for unit: Unit in main.simulation.unit_manager.get_faction_units("BLUE"):
			if unit.spec.category == "cruiser": cruiser = unit
	checks["cruiser available for detailed readout"] = cruiser != null
	if cruiser == null: return
	main.map.select_units([cruiser])
	await _frames()
	var display := main.data_display
	checks["Details action fits"] = _fits(display._details_button)
	await _click_control(display._details_button)
	checks["Details opens complete readout"] = display._details.visible and cruiser.weapons.all(func(spec: WeaponSpec) -> bool: return display._details_text.get_parsed_text().contains(spec.compact_name()))
	checks["Details preserves paused clock"] = SimClock.paused
	await _shot("full-platform-readout")
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	display._details.push_input(key)
	await _frames()
	checks["Escape closes Details without operations desk"] = not display._details.visible and not main._menu.visible
	if display._more_button.visible:
		await _click_control(display._more_button)
		checks["More opens complete readout through mouse"] = display._details.visible
		display._details.push_input(key)
		await _frames()
	else:
		facts["more_button"] = "All actual cruiser weapons fit; no overflow action needed at this window size."


func _submarine_windows() -> void:
	main.start_scenario("res://data/scenarios/cold_war_02_barrier.json")
	await _take_command()
	Debug.log_events = false
	var boat: Unit = null
	for unit: Unit in main.simulation.unit_manager.get_faction_units("BLUE"):
		if unit.is_submarine(): boat = unit
	checks["operation includes own submarine"] = boat != null
	if boat == null: return
	await _click_control(main.command_bar.buttons["options_menu"])
	await _choose_action({"kind": "palette", "id": "option_submarine_comms"})
	checks["option enables submarine communication windows"] = main.options.submarine_comms and boat.comms_enabled
	main.map.select_units([boat])
	main.map.center_on_selection()
	await _frames()
	checks["boat starts below communication depth"] = not SubmarineComms.connected(boat)
	var old_route := boat.waypoints.duplicate()
	var destination := boat.position + Vector2(5, 0)
	await _chart_click(destination, MOUSE_BUTTON_RIGHT)
	checks["chart move is queued while submarine is deep"] = boat.comms_pending.size() == 1 and boat.waypoints == old_route
	checks["last report and pending order are visible"] = SubmarineComms.status(boat, SimClock.sim_time).to_lower().contains("report") and SubmarineComms.detail(boat, SimClock.sim_time).to_lower().contains("pending")
	await _shot("submarine-order-pending")
	await _click_control(main.command_bar.buttons["orders_menu"])
	await _menu_path(["Navigation", "Communications", "Request check-in now"])
	checks["menu requests check-in without delivering deep orders"] = boat.comms_phase == "ascending" and boat.comms_pending.size() == 1
	for second in 1200:
		SimClock.advance(1.0)
		if boat.comms_phase == "reporting": break
	checks["crew reaches communication depth before delivery"] = boat.comms_phase == "reporting" and SubmarineComms.connected(boat)
	checks["queued route arrives at check-in"] = boat.comms_pending.is_empty() and not boat.waypoints.is_empty() and boat.waypoints[-1].distance_to(destination) < 0.5
	checks["last report updates at check-in"] = boat.comms_last_report_s > 0.0
	await _shot("submarine-check-in")


func _menu_path(labels: Array) -> void:
	var popup: PopupMenu = main._cds_menus._root
	for wanted: String in labels:
		var found := -1
		for i in popup.item_count:
			if popup.get_item_text(i) == wanted: found = i
		if found < 0:
			checks["menu item available: " + wanted] = false
			main._cds_menus.close()
			return
		var submenu := popup.get_item_submenu(found)
		await _popup_click(popup, found)
		if submenu != "": popup = popup.get_node(submenu) as PopupMenu


func _set_number(spin: SpinBox, value: int) -> void:
	await _click_control(spin.get_line_edit())
	await _key(KEY_A, false, true)
	for character: String in str(value):
		var event := InputEventKey.new()
		event.unicode = character.unicode_at(0)
		event.keycode = character.unicode_at(0)
		event.pressed = true
		main.get_viewport().push_input(event, true)
		await tree.process_frame
	await _key(KEY_ENTER)


func _drag_chart(from: Vector2, to: Vector2, cancel := false) -> void:
	var start := main.map.get_global_transform_with_canvas() * main.map.world_to_screen(from)
	var end := main.map.get_global_transform_with_canvas() * main.map.world_to_screen(to)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = start
	down.pressed = true
	main.get_viewport().push_input(down, true)
	await tree.process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = end
	motion.relative = end - start
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	main.get_viewport().push_input(motion, true)
	await _frames()
	if cancel: await _key(KEY_ESCAPE)
	down = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = end
	down.pressed = false
	main.get_viewport().push_input(down, true)
	await _frames()


func _fits(control: Control) -> bool:
	return main.get_viewport_rect().grow(1).encloses(control.get_global_rect())


func _finish() -> void:
	var logged: Array[String] = errors.take_errors()
	checks["no unexpected engine errors"] = logged.is_empty()
	var failed := 0
	for check: String in checks:
		if not checks[check]:
			print("FAIL: " + check)
			failed += 1
	var file := FileAccess.open(output_dir.path_join("fidelity-%d.json" % tree.root.size.x), FileAccess.WRITE)
	file.store_string(JSON.stringify({"window": [tree.root.size.x, tree.root.size.y], "checks": checks, "facts": facts, "errors": logged, "screenshots": shots}, "\t") + "\n")
	file.close()
	print("[Fleet fidelity] %d checks, %d failed" % [checks.size(), failed])
	OS.remove_logger(errors)
	tree.quit(1 if failed else 0)
