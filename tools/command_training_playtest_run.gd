extends "res://tools/command_priorities_playtest_run.gd"
## Lessons in the real command shell at the largest interface scale: ordinary menu actions,
## native chart inspection, real sensor reports and no invented tracks or replaced magazines.

func run(scene_tree: SceneTree) -> void:
	tree = scene_tree
	capture = OS.get_cmdline_user_args().has("--capture")
	output_dir = "res://work/credible-command/training"
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
	main._run_palette_action("ui_scale_125")
	await _open_lesson("training_missile_defence")
	checks["missile guide enabled and readable"] = main._command_guide.enabled and _fits(main._command_guide) and main._command_guide._body.text.contains("Manual missile defence")
	await _shot("manual-defence-guide")
	await _click_control(main.command_bar.buttons["options_menu"])
	await _choose_action({"kind": "palette", "id": "option_manual_defence"})
	checks["manual mode earns actual order credit"] = main.simulation.mission_manager.objective("manual_defence").complete
	await _open_lesson("training_asw")
	facts["asw_ui"] = {"taken": main._command_taken, "guide_enabled": main._command_guide.enabled, "guide_visible": main._command_guide.visible, "guide_rect": str(main._command_guide.get_global_rect()), "viewport": str(main.get_viewport_rect()), "briefing": main._briefing.visible, "menu": main._menu.visible, "guide_text": main._command_guide._body.text, "briefing_start": str(main._briefing._start.get_global_rect())}
	await _shot("asw-deployment-guide")
	checks["ASW guide enabled and fits 125"] = main._command_guide.enabled and _fits(main._command_guide)
	await _click_control(main._command_guide._action)
	helo = main.map.selected[0] if not main.map.selected.is_empty() else null
	checks["guide selects actual aircraft"] = helo != null and helo.callsign == "Seahawk Practice"
	if helo == null:
		_finish()
		return
	await _click_control(main.command_bar.buttons["orders_menu"])
	await _choose_order(Order.Type.DEPLOY_DIPPING_SONAR)
	for second in 180:
		SimClock.advance(1.0)
		if main.simulation.mission_manager.objective("dip_listen").complete: break
	checks["deployment menu completes deliberate cycle"] = DippingSonar.listening(helo)
	var datum: Track
	for second in 120:
		SimClock.advance(1.0)
		for track: Track in main.simulation.track_manager.tracks_for(helo):
			if track.is_bearing_only() and track.source == "sonar_passive": datum = track
		if datum != null: break
	checks["passive lesson supplies real unresolved bearing"] = datum != null
	if datum == null:
		_finish()
		return
	main.map.select_track(datum)
	await _frames()
	checks["actual contact selection records inspection"] = main.simulation.mission_manager.objective("passive_datum").complete
	await _shot("passive-bearing-inspected")
	main.map.select_units([helo])
	await _click_control(main.command_bar.buttons["orders_menu"])
	await _choose_order(Order.Type.ACTIVE_SONAR)
	for second in 120:
		SimClock.advance(1.0)
		if main.simulation.mission_manager.objective("active_fix").complete: break
	checks["active localization waits for identified measured report"] = main.simulation.mission_manager.objective("active_fix").complete
	main.map.select_track(datum)
	main.data_display.refresh()
	await _click_control(main.data_display._details_button)
	checks["readout exposes measured range and briefed identity"] = main.data_display._details_text.get_parsed_text().contains("MEASURED FIX") and main.data_display._details_text.get_parsed_text().contains("IDENTITY: HOSTILE")
	await _shot("localized-contact-details")
	main.data_display.close_details()
	await _frames()
	checks["guide authorization step remains pending"] = not main.simulation.mission_manager.objective("authorize_attack").complete and main._command_guide._body.text.to_lower().contains("fire one torpedo")
	_finish()

func _open_lesson(id: String) -> void:
	main._menu.scenario_chosen.emit("res://data/scenarios/%s.json" % id)
	await _frames()
	checks["briefing offers resumable guide " + id] = main._briefing._guide.visible and main._briefing._guide.button_pressed
	main._briefing._start.pressed.connect(func() -> void: SimClock.set_paused(true), CONNECT_ONE_SHOT)
	await _click_control(main._briefing._start)
	await tree.create_timer(0.3).timeout
	await _frames()
	Debug.log_events = false
