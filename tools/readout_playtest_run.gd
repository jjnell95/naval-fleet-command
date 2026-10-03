extends "res://tools/fleet_command_playtest_run.gd"
## Real scene and native controls. The expanded readout must preserve the watch, consume Escape,
## retain live data and fit the same 125% scale used by the compact command display.

func run(scene_tree: SceneTree) -> void:
	tree = scene_tree
	capture = OS.get_cmdline_user_args().has("--capture")
	output_dir = "res://work/credible-command/readout"
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
	for unit: Unit in main.simulation.unit_manager.get_faction_units("BLUE"):
		if unit.spec.id == "usn_ddg_arleigh_burke_iia": host = unit
	checks["actual briefing loaded"] = host != null
	if host == null:
		_finish()
		return
	main.map.select_units([host])
	var display := main.data_display
	for percent: int in [100, 125]:
		main._run_palette_action("ui_scale_%d" % percent)
		await _frames()
		display.refresh()
		await _frames()
		checks["details control fits %d" % percent] = _fits(display._details_button) and display.get_global_rect().encloses(display._details_button.get_global_rect())
		checks["long rows have full tooltip %d" % percent] = display._row_tooltips.any(func(row: Dictionary) -> bool: return str(row["text"]).contains("CLASS:"))
		await _shot("readout-summary-%d" % percent)
		await _click_control(display._details_button)
		await _frames()
		checks["details visible from mouse %d" % percent] = display._details.visible
		facts["window_%d" % percent] = {"parent_size": str(main.get_window().size), "viewport": str(main.get_viewport_rect()), "stretch": str(main.get_viewport().get_stretch_transform()), "detail_position": str(display._details.position), "detail_size": str(display._details.size)}
		checks["opening preserves paused clock %d" % percent] = SimClock.paused
		checks["detail window fits %d" % percent] = display._details.position.x >= 0 and display._details.position.y >= 0 and Vector2(display._details.position + display._details.size).x <= main.get_viewport_rect().size.x + 1.0 and Vector2(display._details.position + display._details.size).y <= main.get_viewport_rect().size.y + 1.0
		checks["all weapons accessible %d" % percent] = host.weapons.all(func(spec: WeaponSpec) -> bool: return display._details_text.get_parsed_text().contains(spec.compact_name()))
		checks["text selectable and keyboard focusable %d" % percent] = display._details_text.selection_enabled and display._details_text.focus_mode == Control.FOCUS_ALL
		await _shot("readout-expanded-%d" % percent)
		var key := InputEventKey.new()
		key.keycode = KEY_ESCAPE
		key.pressed = true
		display._details.push_input(key)
		await _frames()
		checks["Escape closes only readout %d" % percent] = not display._details.visible and not main._menu.visible
		checks["focus returns to details %d" % percent] = display._details_button.has_focus()
	# Running, too: this is an information window, never an implicit pause or resume order.
	SimClock.set_speed_index(1)
	SimClock.set_paused(false)
	var speed := SimClock.speed_index
	display.open_details()
	await _frames()
	checks["running clock preserved on open"] = not SimClock.paused and SimClock.speed_index == speed
	checks["running state explicit"] = display._details_clock.text.contains("simulation running")
	host.ordered_speed_kn = 0.0
	host.waypoints.clear()
	display.refresh()
	checks["details refresh live"] = display._details_text.get_parsed_text().contains(DataDisplay.orders_text(host, main.simulation.weapon_manager, main.simulation.group_attack_manager))
	display.close_details()
	checks["running clock preserved on close"] = not SimClock.paused and SimClock.speed_index == speed
	SimClock.set_paused(true)
	# A compact weapons fixture makes overflow independent of the scenario's equipment count.
	var fixture := DataDisplay.new()
	tree.root.add_child(fixture)
	fixture.set_process(false)
	fixture.position = Vector2(10, 10)
	fixture.size = Vector2(320, 128)
	fixture._rows = [[["Weapons overflow fixture", DataDisplay.TITLE]], [["WEAPONS:", DataDisplay.LABEL]]]
	for i in 12:
		fixture._rows.append([["System %d" % i, DataDisplay.VALUE], [" 8", DataDisplay.WHITE], [DataDisplay.CELL, ""]])
	fixture.queue_redraw()
	await _frames()
	checks["overflow is an actionable focusable control"] = fixture.grid_hidden > 0 and fixture._more_button.visible and fixture._more_button.focus_mode == Control.FOCUS_ALL
	await _click_control(fixture._more_button)
	checks["more opens full details"] = fixture._details != null and fixture._details.visible
	fixture.close_details()
	fixture.queue_free()
	# Results and replacement engagements own the screen even when the watch was being read
	# through an exclusive subwindow. The old readout must not trap input above the new briefing.
	display.open_details()
	main.start_scenario("res://data/scenarios/training_missile_defence.json")
	await _frames()
	checks["new engagement closes stale details"] = not display._details.visible
	checks["new engagement keeps its paused start"] = SimClock.paused
	main._show_briefing()
	await _frames()
	main._briefing._start.pressed.connect(func() -> void: SimClock.set_paused(true), CONNECT_ONE_SHOT)
	await _click_control(main._briefing._start)
	display.open_details()
	main.simulation.mission_manager._finish(MissionManager.Result.DEFEAT, "Readout lifecycle fixture")
	await _frames()
	checks["mission result closes details before debrief"] = not display._details.visible and main._report.visible
	checks["debrief retains paused clock"] = SimClock.paused
	_finish()
