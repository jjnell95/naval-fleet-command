extends RefCounted
## Real scene, real detected contacts and viewport input. No invented observations, ammunition,
## damage or hidden positions. Popup actions are located by their semantic data, then clicked.

var tree: SceneTree
var main: Main
var checks := {}
var facts := {}
var shots: Array[String] = []
var errors: Logger
var capture := false
var output_dir := "res://work/m33"
var host: Unit
var frigate: Unit
var helo: Unit


func run(scene_tree: SceneTree) -> void:
	tree = scene_tree
	capture = OS.get_cmdline_user_args().has("--capture")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			output_dir = argument.trim_prefix("--output-dir=").trim_suffix("/")
	DirAccess.make_dir_recursive_absolute(output_dir)
	CommanderLog.path_override = output_dir.path_join("commander_log.json")  # never the developer's own record
	errors = load("res://tests/test_error_log.gd").new()
	OS.add_logger(errors)
	main = load("res://scenes/main/Main.tscn").instantiate()
	tree.root.add_child(main)
	await _frames()
	await _click_control(main._menu._intro)
	main._briefing._start.pressed.connect(func() -> void: SimClock.set_paused(true), CONNECT_ONE_SHOT)
	await _click_control(main._briefing._start)
	Debug.log_events = false
	for unit: Unit in main.simulation.unit_manager.get_faction_units("BLUE"):
		if unit.spec.id == "usn_ddg_arleigh_burke_iia": host = unit
		if unit.spec.id == "rnon_ffg_fridtjof_nansen": frigate = unit
		if unit.is_aircraft(): helo = unit
	checks["mission opens through mouse input"] = main._command_taken and not main._menu.visible and not main._briefing.visible
	checks["intro force available"] = host != null and frigate != null and helo != null
	if not checks["intro force available"]:
		_finish()
		return
	if OS.get_cmdline_user_args().has("--aircraft-capture-only"):
		main.simulation.unit_manager.issue_order(host, Order.launch_aircraft())
		await _aircraft_weather()
		if OS.get_cmdline_user_args().has("--receipt-check"):
			await _receipt_check()
		_finish()
		return
	await _chart_click(frigate.position)
	checks["own ship selected through chart input"] = main.map.selected == [frigate]
	await _shot("command")
	await _chart_and_clock()
	await _camera_controls()
	main.simulation.unit_manager.issue_order(frigate, Order.set_roe(Unit.Roe.TIGHT))
	main.simulation.unit_manager.issue_order(host, Order.launch_aircraft())
	var unknown: Track
	for second in 90:
		SimClock.advance(1.0)
		for track: Track in main.simulation.track_manager.tracks_for(frigate):
			if track.identity == "UNKNOWN" and UnitManager.investigation_rejection(frigate, track) == "":
				unknown = track
				break
		if unknown != null: break
	checks["sensors produce an investigable unknown"] = unknown != null
	if unknown != null:
		await _hover_readout(unknown)
		await _contact_and_investigation(unknown)
	await _aircraft_and_engagement()
	_finish()


func _chart_and_clock() -> void:
	for id: String in main.command_bar.buttons:
		checks["command control fits: " + id] = main.command_bar.get_global_rect().encloses(main.command_bar.buttons[id].get_global_rect())
	checks["all command panes fit"] = _fits(main.map) and _fits(main.regional) and _fits(main._world_view) and _fits(main.data_display)
	await _click_control(main.command_bar.buttons["chart_menu"])
	await _choose_action({"kind": "symbols", "mode": TacticalMap.SymbolMode.NTDS})
	checks["chart menu selects tactical symbols"] = main.map.symbol_mode == TacticalMap.SymbolMode.NTDS
	await _click_control(main.command_bar.buttons["chart_menu"])
	await _choose_action({"kind": "symbols", "mode": TacticalMap.SymbolMode.MEDIUM})
	checks["chart menu selects graphic symbols"] = main.map.symbol_mode == TacticalMap.SymbolMode.MEDIUM
	var tags: bool = main.map.show_tags
	await _click_control(main.command_bar.buttons["chart_menu"])
	await _choose_action({"kind": "layer", "name": "tags"})
	checks["chart menu toggles labels"] = main.map.show_tags != tags
	if not main.map.show_tags:
		await _click_control(main.command_bar.buttons["chart_menu"])
		await _choose_action({"kind": "layer", "name": "tags"})
	var paused_time := SimClock.sim_time
	await _click_control(main.command_bar.buttons["time_menu"])
	await _choose_action({"kind": "palette", "id": "speed_3"})
	checks["time menu changes speed without resuming"] = SimClock.paused and SimClock.speed_index == 3 and SimClock.sim_time == paused_time
	await _click_control(main.command_bar.buttons["time_menu"])
	await _choose_action({"kind": "palette", "id": "speed_0"})
	checks["time menu returns to real time while paused"] = SimClock.paused and SimClock.speed_index == 0


func _camera_controls() -> void:
	var view := main._world_view
	for mode in WorldCamera.MODE_NAMES.size():
		await _click_control(view._camera_select)
		await _popup_click(view._camera_select.get_popup(), mode)
		checks["mouse selects camera mode %d" % mode] = view.camera_mode() == mode
	await _click_control(view._camera_select)
	await _popup_click(view._camera_select.get_popup(), WorldCamera.TETHER)
	await _click_control(view._swap_button)
	checks["camera swap control enlarges live view"] = main._views_swapped and view.get_parent() == main._upper
	await _shot("ship-weather")
	await _click_control(view._full_button)
	checks["camera full control fills window"] = main._world_full and not main.map.visible and not main.command_bar.visible
	checks["fullscreen return control remains visible"] = _fits(view._full_button)
	await _shot("ship-fullscreen")
	await _click_control(view._full_button)
	checks["camera return control restores panes"] = not main._world_full and main.map.visible and main.command_bar.visible
	await _click_control(view._swap_button)
	checks["camera swap returns chart to top"] = not main._views_swapped and main.map.get_parent() == main._upper
	checks["scenario clouds and rain reach live renderer"] = view._scene.cloud_cover > 0.0 and view._scene.rain_intensity > 0.0 and view._rain.visible
	var weather_time: float = view._scene.weather_time
	await _frames()
	checks["weather animation preserves pause"] = view._scene.weather_time == weather_time


## With nothing hooked, the cursor over a contact fills the data display with its readout, and
## moving off the chart restores the mission page.
func _hover_readout(track: Track) -> void:
	main.map.clear_selection()
	await _frames()
	checks["nothing hooked before the hover"] = main.map.selected.is_empty() and main.map.inspection_track() == null
	await _move(main.map.get_global_transform_with_canvas() * main.map.world_to_screen(track.position))
	var rows := _rows_text(main.data_display.build_rows())
	# _rows_text joins spans with a space, so a label and its value read "TRACK #:  1001".
	checks["hovering a contact with nothing hooked reads it out"] = main.map.hovered_track() == track and rows.contains("TRACK #:  %s" % DataDisplay.track_number_for_track(track))
	checks["hover readout names the reporting platform and set"] = rows.contains("SOURCE:  %s" % DataDisplay.source_readout(track)) and track.source_platform != "" and track.source_sensor != ""
	checks["hover readout carries the damage estimate"] = rows.contains("%DAMAGE:  ")
	facts["hover"] = {"track": track.id, "rows": rows}
	await _shot("hover-readout")
	await _move(main.data_display.get_global_rect().get_center())
	checks["moving off the contact restores the mission page"] = main.map.hovered_track() == null and _rows_text(main.data_display.build_rows()).contains("CONTACTS:")


func _move(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	main.get_viewport().push_input(motion, true)
	await _frames()


func _contact_and_investigation(track: Track) -> void:
	main.map.select_units([frigate])
	main.map.select_track(track)
	main.map.center_on_selection()
	await _chart_click(frigate.position)
	await _chart_click(track.position)
	checks["contact click retains commanded shooter"] = main.map.selected == [frigate] and main.map.inspection_track() == track
	var rows := _rows_text(main.data_display.build_rows())
	checks["contact data shows held report and command platform"] = rows.to_upper().contains(track.description().to_upper()) and rows.contains(frigate.callsign)
	checks["contact click moves camera to held track"] = main._world_view._focus.get("track") == track
	await _shot("inspected-contact")
	var rounds_before := _rounds(frigate)
	var leader := frigate.formation_leader
	var offset := frigate.formation_offset
	var paused_time := SimClock.sim_time
	checks["cursor over an unknown offers to investigate"] = main.map.hover_cursor_shape(main.map.world_to_screen(track.position)) == Control.CURSOR_HELP
	await _chart_click(track.position, MOUSE_BUTTON_RIGHT)
	checks["bare right-click on an unknown investigates it at once"] = frigate.investigation_track == track and (main._cds_menus._root == null or not main._cds_menus._root.visible)
	checks["the direct investigation keeps the watch paused"] = SimClock.paused and SimClock.sim_time == paused_time
	await _chart_click(track.position, MOUSE_BUTTON_RIGHT, true)
	var menu := main._cds_menus._root
	checks["shift-right-click opens the contact menu"] = menu != null and menu.visible
	checks["unknown has a visible blocked attack choice"] = menu != null and menu.visible and menu.item_count > 1 and menu.is_item_disabled(1) and menu.get_item_text(1).begins_with("Attack track") and not menu.get_item_tooltip(1).is_empty()
	checks["opening contact menu spends no rounds"] = _rounds(frigate) == rounds_before
	await _shot("unknown-orders")
	await _choose_action({"kind": "investigate"})
	checks["investigate click tasks the retained shooter while paused"] = frigate.investigation_track == track and SimClock.paused and SimClock.sim_time == paused_time
	var initial_plot := track.position
	var plot_moved := false
	var route_followed := false
	for tick in 1200:
		var held := track.position
		SimClock.advance(SimClock.TICK_DT)
		if frigate.investigation_track != null:
			plot_moved = plot_moved or track.position.distance_to(initial_plot) > 0.01
			# Unit motion consumes the held report before sensors update it for the next tick.
			route_followed = route_followed or (plot_moved and not frigate.waypoints.is_empty() and frigate.waypoints[0].distance_to(held) < 0.001)
		else:
			break
		if tick % 120 == 0: await _frames()
	checks["investigate route follows changing held report"] = plot_moved and route_followed
	checks["investigation ends on real classification"] = frigate.investigation_track == null and track.classification >= Track.Classification.CLASS_KNOWN
	checks["investigation spends no offensive rounds"] = _rounds(frigate) == rounds_before
	facts["investigation"] = {"track": track.id, "time_s": SimClock.sim_time, "result": frigate.investigation_result}
	await _shot("investigation-result")
	if leader != null:
		main.simulation.unit_manager.issue_order(frigate, Order.form_up(leader, offset))
	await _chart_click(frigate.position)
	checks["own click restores data and camera without losing target"] = main.map.inspection_track() == null and main.map.selected == [frigate] and main.map.selected_track == track and main._world_view._focus.get("unit") == frigate


func _aircraft_weather() -> void:
	for second in 180:
		if helo.airborne(): break
		SimClock.advance(1.0)
	checks["normal deck cycle launches aircraft"] = helo.airborne()
	if not helo.airborne(): return
	main.map.select_units([helo])
	await _frames()
	await _click_control(main._world_view._swap_button)
	var scene := main._world_view._scene
	var host_world := WorldPresentation.to_world(host.position, scene.origin_nm, 0.0)
	var camera_offset := scene.camera.position - host_world
	checks["launch camera retains the aircraft subject"] = main.map.selected == [helo] and main._world_view._focus.get("unit") == helo
	checks["launch camera stays outside the own host hull"] = Vector2(camera_offset.x, camera_offset.z).length() > host.spec.length_m * 0.5
	facts["launch_camera"] = {"time_s": SimClock.sim_time, "aircraft_altitude_m": helo.altitude_m, "horizontal_host_clearance_m": Vector2(camera_offset.x, camera_offset.z).length(), "host_length_m": host.spec.length_m}
	await _shot("aircraft-launch")
	await _click_control(main._world_view._swap_button)
	main.simulation.unit_manager.issue_order(helo, Order.move(Vector2(7, 2)))
	# Being airborne starts the climb; wait for ordinary flight to clear the host hull before
	# judging the aircraft camera. This also catches a launch that never becomes usable flight.
	for second in 180:
		if helo.altitude_m >= 500.0 and helo.position.distance_to(host.position) >= 1.0: break
		SimClock.advance(1.0)
		if second % 15 == 0: await _frames()
	checks["aircraft clears host through normal climb and transit"] = helo.airborne() and helo.altitude_m >= 500.0 and helo.position.distance_to(host.position) >= 1.0
	facts["aircraft"] = {"time_s": SimClock.sim_time, "altitude_m": helo.altitude_m, "host_distance_nm": helo.position.distance_to(host.position), "speed_kn": helo.speed_kn}
	main.map.select_units([helo])
	await _frames()
	await _click_control(main._world_view._swap_button)
	checks["cruise camera keeps the same aircraft subject"] = main.map.selected == [helo] and main._world_view._focus.get("unit") == helo
	await _shot("aircraft-weather")
	await _click_control(main._world_view._swap_button)


func _aircraft_and_engagement() -> void:
	await _aircraft_weather()
	main.map.select_units([frigate])
	var target: Track
	var direct := {}
	for second in 600:
		for track: Track in main.simulation.track_manager.tracks_for(frigate):
			if track.identity != "HOSTILE": continue
			var choice := CdsMenus.quick_engage_item([frigate], track, main.simulation.weapon_manager)
			if not choice.get("disabled", true):
				target = track
				direct = choice
				break
		if target != null: break
		SimClock.advance(1.0)
		if second % 60 == 0: await _frames()
	checks["real hostile enters a ready weapon envelope"] = target != null
	if target == null: return
	main.map.select_track(target)
	main.map.center_on_selection()
	await _frames()
	var order: Order = direct["action"]["pairs"][0][1]
	var before := frigate.magazine_count(order.weapon_id)
	var paused_time := SimClock.sim_time
	var leader := frigate.formation_leader
	var offset := frigate.formation_offset
	checks["cursor over a hostile offers to attack"] = main.map.hover_cursor_shape(main.map.world_to_screen(target.position)) == Control.CURSOR_CROSS
	await _chart_click(target.position, MOUSE_BUTTON_RIGHT)
	checks["bare right-click on a hostile orders a standing attack"] = frigate.attack_track == target and (main._cds_menus._root == null or not main._cds_menus._root.visible)
	checks["the attack order spends nothing while paused"] = frigate.magazine_count(order.weapon_id) == before and SimClock.paused and SimClock.sim_time == paused_time
	checks["the orders line narrates the attack"] = DataDisplay.orders_text(frigate, main.simulation.weapon_manager).begins_with("Intercept track") or DataDisplay.orders_text(frigate, main.simulation.weapon_manager).begins_with("Engage track")
	checks["the attack order is acknowledged on the radio"] = main.radio.journal.back().contains("Attacking track")
	facts["attack"] = {"track": target.id, "orders": DataDisplay.orders_text(frigate, main.simulation.weapon_manager), "time_s": SimClock.sim_time}
	await _shot("standing-attack")
	if leader != null:
		main.simulation.unit_manager.issue_order(frigate, Order.form_up(leader, offset))
	else:
		main.simulation.unit_manager.issue_order(frigate, Order.stop())
	checks["navigation replaces the attack"] = frigate.attack_track == null
	await _chart_click(target.position, MOUSE_BUTTON_RIGHT, true)
	await _shot("ready-engagement")
	await _choose_action({"kind": "unit_orders"})
	checks["direct engage commits exactly the displayed finite salvo"] = before - frigate.magazine_count(order.weapon_id) == order.salvo and order.salvo > 0
	checks["direct engage preserves pause and shooter"] = SimClock.paused and SimClock.sim_time == paused_time and main.map.selected == [frigate]
	facts["engagement"] = {"track": target.id, "weapon": order.weapon_id, "salvo": order.salvo, "before": before, "after": frigate.magazine_count(order.weapon_id), "time_s": SimClock.sim_time}
	main.map.select_units([frigate])
	await _click_control(main._world_view._camera_select)
	await _popup_click(main._world_view._camera_select.get_popup(), WorldCamera.ACTION)
	await _click_control(main._world_view._swap_button)
	await _shot("action")


func _receipt_check() -> void:
	# Exercise both ordinary shell order routes with a stale requested quantity larger than
	# the real magazine. Use only actual sensor tracks and the weapons already aboard.
	facts["receipts"] = []
	for shooter: Unit in [frigate, host]:
		var target: Track
		var chosen: WeaponSpec
		for second in 600:
			for track: Track in main.simulation.track_manager.tracks_for(shooter):
				if track.identity != "HOSTILE" or track.classification < Track.Classification.CLASS_KNOWN: continue
				var option := CdsMenus.quick_engage_item([shooter], track, main.simulation.weapon_manager)
				if not option.get("disabled", true):
					target = track
					chosen = shooter.get_weapon(option["action"]["pairs"][0][1].weapon_id)
					break
			if target != null: break
			SimClock.advance(1.0)
			if second % 60 == 0: await _frames()
		var route := "unit orders" if shooter == frigate else "selection orders"
		checks[route + " receipt has a real ready target"] = target != null and chosen != null
		if target == null or chosen == null: continue
		main.map.select_units([shooter])
		if shooter == frigate:
			main.map.select_track(target)
			main.map.center_on_selection()
			await _frames()
			await _chart_click(target.position)
			await _shot("inspected-hostile")
			await _chart_click(target.position, MOUSE_BUTTON_RIGHT, true)
			await _shot("ready-engagement")
			var window_id := main._cds_menus._root.get_window_id()
			for pressed: bool in [true, false]:
				var key := InputEventKey.new()
				key.window_id = window_id
				key.keycode = KEY_ESCAPE
				key.pressed = pressed
				Input.parse_input_event(key)
				await tree.process_frame
			await _frames()
		var before := shooter.magazine_count(chosen.id)
		var requested := before + 5
		var time_before := SimClock.sim_time
		var order := Order.engage(target, chosen.id, requested)
		if shooter == frigate:
			main._apply_unit_orders([[shooter, order]])
		else:
			main._apply_order_to_selection(order)
		var committed := before - shooter.magazine_count(chosen.id)
		var receipt: String = main.radio.journal.back()
		checks[route + " caps an oversized salvo at remaining inventory"] = committed == before and committed > 0 and requested > committed
		checks[route + " receipt reports actual committed rounds"] = receipt.contains("%d × %s" % [committed, chosen.compact_name()]) and not receipt.contains("%d × %s" % [requested, chosen.compact_name()])
		checks[route + " receipt preserves the paused watch"] = SimClock.paused and SimClock.sim_time == time_before
		facts["receipts"].append({"route": route, "shooter": shooter.callsign, "weapon": chosen.id, "requested": requested, "committed": committed, "receipt": receipt})


func _rounds(unit: Unit) -> int:
	var count := 0
	for weapon: WeaponSpec in unit.weapons:
		if weapon.type == "asm": count += unit.magazine_count(weapon.id)
	return count


func _rows_text(rows: Array) -> String:
	var text := ""
	for row: Array in rows:
		for fragment: Array in row: text += str(fragment[0]) + " "
	return text


func _choose_action(wanted: Dictionary) -> void:
	var menu := main._cds_menus._root
	if menu == null:
		checks["menu available for " + str(wanted)] = false
		return
	var table: Dictionary = main._cds_menus._actions.get(menu.get_instance_id(), {})
	for id: int in table:
		var action: Dictionary = table[id]
		var matches := true
		for key: String in wanted:
			if action.get(key) != wanted[key]: matches = false
		if matches:
			await _popup_click(menu, menu.get_item_index(id))
			return
	checks["action available: " + str(wanted)] = false
	main._cds_menus.close()
	await _frames()


func _popup_click(menu: PopupMenu, index: int) -> void:
	# Embedded popup hit testing reads the actual pointer. Warp and wait for its OS motion;
	# selection still happens through a normal mouse press/release routed to the window.
	await tree.create_timer(0.2).timeout
	var point := Vector2(-1, -1)
	for y in range(6, menu.size.y, 5):
		var candidate := Vector2(menu.size.x * 0.5, y)
		menu.warp_mouse(candidate)
		await _frames()
		if menu.get_focused_item() == index:
			point = candidate
			break
	if point.x < 0:
		checks["popup row hittable: %d" % index] = false
		menu.hide()
		await _frames()
		return
	var window_id := menu.get_window_id()
	var input_point := Vector2(DisplayServer.mouse_get_position() - DisplayServer.window_get_position(window_id))
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.window_id = window_id
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = input_point
		event.pressed = pressed
		Input.parse_input_event(event)
		await tree.process_frame
	await _frames()


func _frames() -> void:
	await tree.process_frame
	await tree.process_frame


func _fits(control: Control) -> bool:
	return control.is_visible_in_tree() and main.get_viewport_rect().encloses(control.get_global_rect())


func _click_control(control: Control) -> void:
	await _click(control.get_global_rect().get_center())


func _chart_click(world: Vector2, button := MOUSE_BUTTON_LEFT, shift := false) -> void:
	await _click(main.map.get_global_transform_with_canvas() * main.map.world_to_screen(world), button, shift)


func _click(point: Vector2, button := MOUSE_BUTTON_LEFT, shift := false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	main.get_viewport().push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.position = point
		event.pressed = pressed
		event.shift_pressed = shift
		main.get_viewport().push_input(event, true)
		await tree.process_frame
	await _frames()


func _shot(label: String) -> void:
	if not capture: return
	await _frames()
	await RenderingServer.frame_post_draw
	var frame := main.get_viewport().get_texture().get_image()
	var path := output_dir.path_join("%s-%d.png" % [label, frame.get_width()])
	checks["screenshot: " + label] = frame.save_png(path) == OK
	shots.append(path)


func _finish() -> void:
	var logged: Array[String] = errors.take_errors()
	checks["no unexpected engine errors"] = logged.is_empty()
	var failures := 0
	for check: String in checks:
		if not checks[check]:
			print("FAIL: " + check)
			failures += 1
	var result := {"window": [tree.root.size.x, tree.root.size.y], "checks": checks, "facts": facts, "errors": logged, "screenshots": shots}
	var suffix := "-aircraft" if OS.get_cmdline_user_args().has("--aircraft-capture-only") else ""
	var file := FileAccess.open(output_dir.path_join("fleet-command%s-%d.json" % [suffix, tree.root.size.x]), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t") + "\n")
	file.close()
	print("[Fleet Command] %d checks, %d failed" % [checks.size(), failures])
	OS.remove_logger(errors)
	tree.quit(1 if failures else 0)
