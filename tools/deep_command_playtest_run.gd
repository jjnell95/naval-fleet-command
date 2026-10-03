extends "res://tools/fleet_command_playtest_run.gd"
## Uses the same viewport helpers as the contact-intent suite. No invented contacts, fuel,
## damage or enemy positions. Only ordinary UI commands and deterministic clock advancement.

func run(scene_tree: SceneTree) -> void:
	tree = scene_tree
	capture = OS.get_cmdline_user_args().has("--capture")
	output_dir = "res://work/deep-review/native"
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
	checks["intro briefing offers an optional guide"] = main._briefing._guide.visible and main._briefing._guide.button_pressed
	await _shot("guided-briefing")
	main._briefing._start.pressed.connect(func() -> void: SimClock.set_paused(true), CONNECT_ONE_SHOT)
	await _click_control(main._briefing._start)
	Debug.log_events = false
	await _settle_guide()
	var guide := main._command_guide
	checks["guide begins with launch and fits chart"] = guide.step() == 0 and guide.visible and main.map.get_global_rect().encloses(guide.get_global_rect())
	checks["guide leaves command strip accessible"] = not guide.get_global_rect().intersects(main.command_bar.get_global_rect())
	await _shot("guided-command")
	await _click_control(guide._action)
	var air := main._air_operations
	checks["guide opens the real Air Operations dialog"] = air.visible and SimClock.paused
	await _settle_guide()
	checks["guide hides behind a modal"] = not guide.visible
	if air._selection_labels.is_empty():
		checks["intro aircraft available on flight deck"] = false
		_finish()
		return
	checks["quantity defaults to one ready aircraft"] = int(air._count.value) == 1 and not air._launch.disabled
	await _click_control(air._launch)
	await _click_control(air._back)
	SimClock.set_paused(true)
	for u: Unit in main.simulation.unit_manager.get_faction_units("BLUE"):
		if u.spec.id == "usn_ddg_arleigh_burke_iia": host = u
		if u.spec.id == "rnon_ffg_fridtjof_nansen": frigate = u
		if u.is_aircraft(): helo = u
	for second in int(helo.spec.launch_time_s) + 1: SimClock.advance(1.0)
	await _settle_guide()
	checks["real deck cycle advances the guide"] = helo.airborne() and guide.step() == 1
	await _click_control(guide._action)
	checks["guide selects the aircraft without issuing orders"] = main.map.selected == [helo] and not helo.patrol_active
	await _click_control(main.command_bar.buttons["orders_menu"])
	await _choose_action({"kind": "palette", "id": "plot_patrol"})
	await _chart_click(Vector2(2, 2))
	await _chart_click(Vector2(4, 4))
	await _settle_guide()
	checks["two chart corners give a real patrol and advance the guide"] = helo.patrol_active and guide.step() == 2
	await _shot("guided-patrol")
	var unknown: Track
	for t: Track in main.simulation.track_manager.tracks_for(helo):
		if t.identity == "UNKNOWN":
			unknown = t
			if UnitManager.investigation_rejection(helo, t) == "": break
	facts["reports_at_investigation_s"] = SimClock.sim_time
	facts["held_reports"] = []
	for t: Track in main.simulation.track_manager.tracks_for(helo):
		facts["held_reports"].append({"id": t.id, "identity": t.identity, "class": t.description(), "rejection": UnitManager.investigation_rejection(helo, t)})
	checks["sensors hold an unknown report"] = unknown != null
	if unknown == null:
		_finish()
		return
	main.map.center_nm = unknown.position
	main.map.queue_redraw()
	await _chart_click(unknown.position)
	await _settle_guide()
	checks["inspection advances without discarding the aircraft"] = guide.step() == 3 and main.map.selected == [helo]
	await _shot("guided-contact")
	var investigation_reason := UnitManager.investigation_rejection(helo, unknown)
	var can_investigate := investigation_reason == ""
	if can_investigate:
		await _chart_click(unknown.position, MOUSE_BUTTON_RIGHT)
	else:
		checks["guide explains why this report cannot be investigated"] = guide._body.text.contains(investigation_reason)
		if unknown.is_bearing_only():
			checks["bearing-only world caption does not imply a positioned model"] = main._world_view._subject_label.text.begins_with("BEARING ONLY")
		else:
			checks["classified contact with unknown allegiance is not a bearing-only report"] = unknown.classification >= Track.Classification.CLASS_KNOWN and not main._world_view._subject_label.text.begins_with("BEARING ONLY")
		await _click_control(guide._skip)
	await _settle_guide()
	checks["guide advances by a real investigation or an explicit skip"] = guide.step() == 4 and ((helo.investigation_track == unknown and guide.done.has("investigate")) if can_investigate else (guide.skipped.has("investigate") and not guide.done.has("investigate")))
	checks["escort stays with the convoy"] = frigate.in_formation() and host.in_formation()
	await _shot("guided-investigation")
	var progress := guide.to_dict()
	checks["active guide can be saved"] = main.save_engagement("guide", "manual", "Guided investigation") == ""
	await _click_control(guide._close)
	checks["close hides guidance without stopping the watch"] = not guide.enabled and not guide.visible and SimClock.paused
	checks["load restores the guide with the battle"] = main.load_engagement(SaveGame.slot_path("guide")) == "" and guide.to_dict() == progress
	helo = guide.aircraft(main.simulation.unit_manager)
	if not can_investigate:
		await _settle_guide()
		await _click_control(guide._action)
		await _click_control(main.command_bar.buttons["air_operations"])
		checks["the recovery control is available for the selected aircraft"] = not air._return.disabled
		await _click_control(air._return)
		await _click_control(air._back)
		checks["recovery is a real accepted order"] = guide.recovery_ordered and helo.returning
	for second in 1100:
		SimClock.advance(1.0)
		if second % 30 == 0:
			await _settle_guide()
		if guide.done.has("return"): break
	await _settle_guide()
	checks["classification and station return, or safe deck recovery, complete practice"] = guide.done.has("return") and guide.step() == 5 and ((guide.classified and helo.on_station()) if can_investigate else helo.flight_state == Unit.FlightState.TURNAROUND)
	facts["guide_steps"] = guide.to_dict()
	facts["completed_at_s"] = SimClock.sim_time
	await _shot("guided-complete")
	# Reopening the guide is an explicit choice in the briefing, and does not reset its progress.
	await _click_control(guide._close)
	await _key_input(KEY_F1)
	checks["F1 offers to resume a closed guide"] = main._briefing.visible and not main._briefing._guide.button_pressed
	await _click_control(main._briefing._guide)
	main._briefing._start.pressed.connect(func() -> void: SimClock.set_paused(true), CONNECT_ONE_SHOT)
	await _click_control(main._briefing._start)
	await _settle_guide()
	checks["resuming guide preserves completed practice"] = guide.visible and guide.enabled and guide.step() == 5
	_finish()


func _settle_guide() -> void:
	await tree.create_timer(0.6).timeout
	await _frames()


func _key_input(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		main.get_viewport().push_input(event, true)
		await tree.process_frame
	await _frames()
