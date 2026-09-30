extends RefCounted
## Real scene and viewport mouse events. Run under Xvfb at the requested physical window size.
var tree: SceneTree
var main: Main
var checks := {}
var capture := false
var errors: Logger
var shots: Array[String] = []

func run(scene_tree: SceneTree) -> void:
	tree = scene_tree
	capture = OS.get_cmdline_user_args().has("--capture")
	DirAccess.make_dir_recursive_absolute("res://work/m32")
	errors = load("res://tests/test_error_log.gd").new()
	OS.add_logger(errors)
	main = load("res://scenes/main/Main.tscn").instantiate()
	tree.root.add_child(main)
	await _frames()
	await _click_control(main._menu._intro)
	# Stop on the same signal as Take Command so software-rendering frame time cannot change
	# the scenario's simulated opening while the next viewport mouse release is delivered.
	main._briefing._start.pressed.connect(func() -> void: SimClock.set_paused(true), CONNECT_ONE_SHOT)
	await _click_control(main._briefing._start)
	SimClock.set_paused(true)
	Debug.log_events = false
	var host: Unit
	var frigate: Unit
	var helo: Unit
	for u: Unit in main.simulation.unit_manager.get_faction_units("BLUE"):
		if u.spec.id == "usn_ddg_arleigh_burke_iia": host = u
		if u.spec.id == "rnon_ffg_fridtjof_nansen": frigate = u
		if u.is_aircraft(): helo = u
	checks["real mission opened through mouse clicks"] = main._command_taken and not main._menu.visible and not main._briefing.visible
	main.map.select_units([frigate])
	var escort_leader := frigate.formation_leader
	var escort_offset := frigate.formation_offset
	checks["opening chart uses command scale"] = main.simulation.scenario.map.focus_extent_nm == 32
	await _frames()
	main.command_bar.refresh()
	var paused_at := SimClock.sim_time
	checks["command strip fits viewport"] = main.get_viewport_rect().encloses(main.command_bar.get_global_rect())
	for id: String in main.command_bar.buttons:
		checks["command key fits: " + id] = main.command_bar.get_global_rect().encloses(main.command_bar.buttons[id].get_global_rect())
	checks["four panes fit viewport"] = _fits(main.map) and _fits(main.regional) and _fits(main._world_view) and _fits(main.data_display)
	await _shot("command")
	await _key(KEY_W, true)
	checks["Shift W arms patrol through viewport keyboard input"] = main.map.interaction_mode == TacticalMap.InteractionMode.PATROL
	await _key(KEY_ESCAPE)
	checks["Escape cancels patrol through viewport keyboard input"] = main.map.interaction_mode == TacticalMap.InteractionMode.SELECT
	await _click_control(main.command_bar.buttons["plot_patrol"])
	checks["patrol command arms from strip"] = main.map.interaction_mode == TacticalMap.InteractionMode.PATROL
	await _chart_click(Vector2(-3, 2))
	await _chart_motion(Vector2(-1, 4))
	checks["first corner issues no order"] = not frigate.patrol_active
	await _shot("patrol-preview")
	await _chart_click(Vector2(-1, 4))
	checks["second corner assigns circuit while paused"] = frigate.patrol_active and frigate.waypoints.size() == 4 and SimClock.sim_time == paused_at
	checks["tool returns to selection"] = main.map.interaction_mode == TacticalMap.InteractionMode.SELECT
	checks["patrol visible in platform data"] = DataDisplay.orders_text(frigate).contains("Patrol circuit")
	await _shot("patrol-orders")
	# Restore the escort with ordinary formation orders, then exercise the same task on an aircraft.
	main.simulation.unit_manager.issue_order(frigate, Order.form_up(escort_leader, escort_offset))
	main.simulation.unit_manager.issue_order(host, Order.launch_aircraft())
	for second in int(helo.spec.launch_time_s) + 1:
		SimClock.advance(1.0)
	checks["actual deck cycle launches the helicopter"] = helo.airborne()
	main.map.select_units([helo])
	main.command_bar.refresh()
	await _click_control(main.command_bar.buttons["plot_patrol"])
	await _chart_click(Vector2(2, 3))
	await _chart_click(Vector2(3, 4))
	checks["aircraft accepts area through same mouse tool"] = helo.patrol_active
	var fuel := helo.fuel_s
	for second in 480:
		SimClock.advance(1.0)
		if second % 60 == 0:
			await tree.process_frame
		if helo.patrol_legs_completed >= 5: break
	checks["aircraft repeats a full patrol in actual battle"] = helo.patrol_legs_completed >= 5 and helo.alive
	checks["patrol consumes endurance"] = helo.fuel_s < fuel
	checks["patrol has held reconnaissance contacts"] = main.simulation.track_manager.get_tracks("BLUE").any(func(t: Track) -> bool: return t.contributors.has(helo))
	# Move the pointer clear of the plot so a waypoint tooltip does not hide the patrol itself.
	await _chart_motion(Vector2(8, 9))
	await _shot("air-patrol")
	main.simulation.unit_manager.issue_order(helo, Order.return_to_base())
	checks["return order cancels patrol"] = helo.returning and not helo.patrol_active
	for second in 420:
		SimClock.advance(1.0)
		if second % 60 == 0:
			await tree.process_frame
		if helo.completed_sorties >= 1: break
	checks["patrol aircraft recovers alive"] = helo.alive and helo.completed_sorties == 1
	main.map.select_units([frigate])
	await _click_control(main.command_bar.buttons["swap_views"])
	checks["3D key swaps the real live view"] = main._views_swapped and main._world_view.get_parent() == main._upper
	await _shot("frigate-3d")
	await _click_control(main.command_bar.buttons["swap_views"])
	await _click_control(main.command_bar.buttons["air_operations"])
	checks["air key opens flight deck"] = main._air_operations.visible and SimClock.paused
	main._close_air_operations(false)
	await _click_control(main.command_bar.buttons["weapon_control"])
	checks["weapons key opens weapon control"] = main._weapon_control.visible and SimClock.paused
	main._close_weapon_control()
	await _click_control(main.command_bar.buttons["status_boards"])
	checks["orders key opens boards"] = main.status_boards.visible
	main.status_boards.close_boards()
	await _click_control(main.command_bar.buttons["toggle_pause"])
	checks["resume key runs time"] = not SimClock.paused
	await _click_control(main.command_bar.buttons["toggle_pause"])
	checks["pause key stops time"] = SimClock.paused
	if capture:
		for id: String in ["gulf_01_hormuz", "med_01_tartus", "pacific_03_spratly"]:
			var path := "res://data/scenarios/%s.json" % id
			if not FileAccess.file_exists(path):
				checks["theatre exists: " + id] = false
				continue
			main.start_scenario(path)
			main._hide_screens()
			SimClock.set_paused(true)
			for second in 120:
				SimClock.advance(1.0)
			var own := main.simulation.unit_manager.get_faction_units("BLUE")
			if not own.is_empty(): main.map.select_units([own[0]])
			await _shot(id)
	var logged: Array[String] = errors.take_errors()
	checks["no unexpected engine errors"] = logged.is_empty()
	var result := {"window": [tree.root.size.x, tree.root.size.y], "checks": checks, "errors": logged, "screenshots": shots, "helicopter": {"legs_completed": helo.patrol_legs_completed, "alive": helo.alive, "sorties_completed": helo.completed_sorties, "flight_state": helo.flight_state, "position": [helo.position.x, helo.position.y], "fuel_s": helo.fuel_s}}
	var f := FileAccess.open("res://work/m32/command-watch-%d.json" % tree.root.size.x, FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "\t") + "\n")
	f.close()
	var failures := 0
	for check: String in checks:
		if not checks[check]:
			print("FAIL: " + check)
			failures += 1
	print("[Command Watch] %d checks, %d failed" % [checks.size(), failures])
	OS.remove_logger(errors)
	tree.quit(1 if failures else 0)

func _frames() -> void:
	await tree.process_frame
	await tree.process_frame

func _fits(c: Control) -> bool:
	return main.get_viewport_rect().encloses(c.get_global_rect())

func _click_control(c: Control) -> void:
	await _click(c.get_global_rect().get_center())

func _key(code: Key, shift := false) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.shift_pressed = shift
		event.pressed = pressed
		main.get_viewport().push_input(event, true)
		await tree.process_frame
	await _frames()

func _chart_click(world: Vector2) -> void:
	await _click(main.map.get_global_transform_with_canvas() * main.map.world_to_screen(world))

func _chart_motion(world: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = main.map.get_global_transform_with_canvas() * main.map.world_to_screen(world)
	main.get_viewport().push_input(event, true)
	await _frames()

func _click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	main.get_viewport().push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		main.get_viewport().push_input(event, true)
		await tree.process_frame
	await _frames()

func _shot(label: String) -> void:
	if not capture: return
	await _frames()
	await RenderingServer.frame_post_draw
	var frame := main.get_viewport().get_texture().get_image()
	var path := "res://work/m32/%s-%d.png" % [label, frame.get_width()]
	checks["screenshot: " + label] = frame.save_png(path) == OK
	shots.append(path)
