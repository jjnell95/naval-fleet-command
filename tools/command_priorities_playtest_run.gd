extends "res://tools/fleet_command_playtest_run.gd"
## UI commands through viewport input, including scaling and both modal clock states.

func run(scene_tree: SceneTree) -> void:
	tree = scene_tree
	capture = OS.get_cmdline_user_args().has("--capture")
	output_dir = "res://work/next-priorities/native"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output-dir="): output_dir = arg.trim_prefix("--output-dir=")
	DirAccess.make_dir_recursive_absolute(output_dir)
	CommanderLog.path_override = output_dir.path_join("commander_log.json")
	SaveGame.root_override = output_dir.path_join("saves")
	errors = load("res://tests/test_error_log.gd").new()
	OS.add_logger(errors)
	main = load("res://scenes/main/Main.tscn").instantiate()
	tree.root.add_child(main)
	await _frames()
	await _click_control(main._menu._intro)
	main._briefing._start.pressed.connect(func() -> void: SimClock.set_paused(true), CONNECT_ONE_SHOT)
	await _click_control(main._briefing._start)
	Debug.log_events = false
	main._command_guide.enabled = false
	main._command_guide.hide()
	var air := main._air_operations
	for percent: int in InterfaceScale.PERCENTAGES:
		await _click_control(main.command_bar.buttons["options_menu"])
		await _choose_action({"kind": "palette", "id": "ui_scale_%d" % percent})
		await _frames()
		checks["scale chosen from menu %d" % percent] = InterfaceScale.percent == percent and is_equal_approx(tree.root.content_scale_factor, percent / 100.0)
		facts["viewport_%d" % percent] = str(main.get_viewport_rect())
		for control: Control in [main.map, main.regional, main._world_view, main.data_display, main.command_bar]:
			checks["%s fits at %d" % [control.name, percent]] = _fits(control)
		await _shot("command-%d" % percent)
		await _click_control(main.command_bar.buttons["air_operations"])
		checks["launch fits at %d" % percent] = _fits(air._launch) and _fits(air._back) and _fits(air._base_picker) and _fits(air._plan_tabs)
		checks["quantity is sole selector %d" % percent] = air._selection_labels.size() > 0 and air._selection_labels[0] is Label
		checks["launch names its quantity %d" % percent] = air._count.value == 1 and air._launch.text.contains("1 ×")
		await _shot("launch-%d" % percent)
		var bar := air._plan_tabs.get_tab_bar()
		await _click(bar.global_position + bar.get_tab_rect(1).get_center())
		checks["mission plan fits at %d" % percent] = _fits(air._mission_picker) and _fits(air._station_button) and _fits(air._back) and _fits(air._launch)
		await _shot("mission-plan-%d" % percent)
		await _click_control(air._back)
		checks["Close preserves pause and sends no launch %d" % percent] = SimClock.paused and not air.visible and main.simulation.unit_manager.units.filter(func(u: Unit) -> bool: return u.flight_state == Unit.FlightState.LAUNCHING).is_empty()
	# Preserve a running clock and its chosen compression across the modal.
	SimClock.set_speed_index(2)
	SimClock.set_paused(false)
	await _click_control(main.command_bar.buttons["air_operations"])
	checks["modal explains clock restoration"] = air._clock_hint.text.contains("Close resumes") and SimClock.paused
	var held_speed := SimClock.speed_index
	facts["speed_on_open"] = held_speed
	air._back.pressed.connect(func() -> void:
		checks["Close restores running speed"] = not SimClock.paused and SimClock.speed_index == held_speed, CONNECT_ONE_SHOT)
	await _click_control(air._back)
	SimClock.set_paused(true)
	await _click_control(main.command_bar.buttons["air_operations"])
	await _click_control(air._launch)
	checks["launch clears quantity and stays paused"] = air._count.value == 0 and air._launch.disabled and SimClock.paused
	await _click_control(air._back)
	for u: Unit in main.simulation.unit_manager.get_faction_units("BLUE"):
		if u.is_aircraft(): helo = u
	for second in int(helo.spec.launch_time_s) + 1: SimClock.advance(1.0)
	checks["one explicit launch completes a deck cycle"] = helo.airborne()
	main.map.select_units([helo])
	main.map.center_on_selection()
	await _frames()
	await _click_control(main.command_bar.buttons["orders_menu"])
	await _choose_order(Order.Type.DEPLOY_DIPPING_SONAR)
	checks["sensor menu issues deployment"] = helo.dip_phase == DippingSonar.Phase.POSITIONING
	checks["deployment is not immediate detection"] = not DippingSonar.listening(helo)
	for second in 200:
		SimClock.advance(1.0)
		if DippingSonar.listening(helo): break
	checks["crew finishes lowering before listening"] = DippingSonar.listening(helo)
	await _shot("sonar-listening")
	await _click_control(main.command_bar.buttons["orders_menu"])
	await _choose_order(Order.Type.RECOVER_DIPPING_SONAR)
	checks["raise command disables sonar immediately"] = helo.dip_phase == DippingSonar.Phase.RAISING and not DippingSonar.listening(helo)
	await _shot("sonar-raising")
	main._run_palette_action("missions")
	await _frames()
	checks["operations desk fits at 125"] = _fits(main._menu._intro) and _fits(main._menu._options_menu)
	await _shot("operations-desk-125")
	await _click_control(main._menu._intro)
	checks["briefing start fits at 125"] = _fits(main._briefing._start)
	await _shot("briefing-125")
	_finish()


func _choose_order(type: Order.Type) -> void:
	var root := main._cds_menus._root
	if root == null:
		checks["orders menu available"] = false
		return
	for i in root.item_count:
		if root.get_item_text(i) != "Sensors": continue
		await _popup_click(root, i)
		var submenu := root.get_node(root.get_item_submenu(i)) as PopupMenu
		var actions: Dictionary = main._cds_menus._actions.get(submenu.get_instance_id(), {})
		for id: int in actions:
			var order: Order = actions[id].get("order")
			if order != null and order.type == type:
				await _popup_click(submenu, submenu.get_item_index(id))
				return
	checks["sonar order available %d" % type] = false
	main._cds_menus.close()
