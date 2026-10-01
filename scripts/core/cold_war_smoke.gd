class_name ColdWarSmoke
extends RefCounted
## Integration checks run through the actual scene, input, screen lifecycle and simulation.

static func run(main: Main) -> void:
	var checks: Dictionary = {}
	var menu := main._menu
	main._show_menu()
	await main.get_tree().process_frame
	menu._set_era("cold_war")
	checks["five period missions on the Cold War shelf"] = menu._entries.filter(func(e: Dictionary) -> bool: return str(e["path"]).begins_with("res://")).size() == 5
	checks["all period shelf entries are dated 1990"] = menu._entries.all(func(e: Dictionary) -> bool: return int(e["year"]) == 1990)
	checks["period portrait uses the historical catalogue"] = menu._portrait.spec_override != null and menu._portrait.spec_override.id.begins_with("cw90_")
	checks["mission desk exposes first orders and date"] = menu._detail.text.contains("YOUR FIRST ORDERS") and menu._mission_meta.text.contains("1990")
	menu._set_era("exercises")
	checks["eight existing exercises plus Northern Passage remain available"] = menu._entries.size() == 9 and menu._entries.any(func(e: Dictionary) -> bool: return e["id"] == "northern_passage")
	menu._set_era("atlantic")
	checks["Atlantic shelf consolidates into three expanded operations"] = menu._entries.size() == 3
	checks["operation desk displays the authored sequence"] = menu._detail.text.contains("OPERATION SEQUENCE")
	menu._set_era("modern")
	checks["existing modern operations remain available"] = menu._entries.size() >= 11 and menu._entries.all(func(e: Dictionary) -> bool: return int(e["year"]) != 1990)
	menu._set_era("all")
	checks["all operations includes both eras"] = menu._entries.size() >= 15
	menu._set_era("cold_war")
	menu._play.pressed.emit()
	await main.get_tree().process_frame
	checks["mission button loads convoy into paused briefing"] = main.simulation.scenario_path == "res://data/scenarios/cold_war_01_convoy.json" and main._briefing.visible and not menu.visible and SimClock.paused
	checks["briefing opens on actionable orders"] = main._briefing._active_section == "orders" and main._briefing._body.text.contains("OPENING ORDERS") and main._briefing._body.text.contains("SUCCESS CONDITIONS")
	checks["briefing shows phased orders and pending objectives"] = main._briefing._body.text.contains("OPERATION SEQUENCE") and main._briefing._body.text.contains("PENDING")
	main._briefing._tabs["controls"].pressed.emit()
	checks["controls have their own page"] = main._briefing._active_section == "controls" and main._briefing._body.text.contains("CHART")
	main._briefing._tabs["situation"].pressed.emit()
	checks["situation preserves historical context"] = main._briefing._body.text.contains("HISTORICAL CONTEXT")
	# Exercise deferred RichTextLabel scrolling across pages and scenario replacement.
	# Extra blank reference lines guarantee scrollable content at either validation size.
	main._briefing.set_process(false)
	main._briefing._select_section("controls")
	main._briefing._body.append_text("\n".repeat(40))
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	main._briefing._body.get_v_scroll_bar().value = 200.0
	var prior_scroll := main._briefing._body.get_v_scroll_bar().value
	main._briefing._select_section("orders")
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	checks["switching briefing tabs returns to the first orders"] = prior_scroll > 0.0 and main._briefing._body.get_v_scroll_bar().value == 0.0
	main._briefing._select_section("controls")
	main._briefing._body.append_text("\n".repeat(40))
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	main._briefing._body.get_v_scroll_bar().value = 200.0
	prior_scroll = main._briefing._body.get_v_scroll_bar().value
	main.start_scenario("res://data/scenarios/cold_war_02_barrier.json")
	main._show_briefing()
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	checks["new operation starts briefing at the top"] = prior_scroll > 0.0 and main._briefing._active_section == "orders" and main._briefing._body.get_v_scroll_bar().value == 0.0
	main._briefing.set_process(true)
	main.start_scenario("res://data/scenarios/cold_war_01_convoy.json")
	main._show_briefing()
	main._unhandled_key_input(_key(KEY_G))
	checks["briefing blocks chart shortcuts"] = not main._views_swapped and SimClock.paused
	main._briefing._select_section("orders")
	main._briefing._start.pressed.emit()
	checks["take command begins the mission at real time"] = not main._briefing.visible and not SimClock.paused and SimClock.speed_index == 0
	SimClock.set_paused(true)
	SimClock.advance(120.0)
	main.contact_panel.refresh()
	var search_seconds := 0.0
	while main.contact_panel.visible_tracks().is_empty() and search_seconds < 1200.0:
		SimClock.advance(60.0)
		search_seconds += 60.0
		main.contact_panel.refresh()
	checks["convoy watch develops actual sensor contacts"] = not main.contact_panel.visible_tracks().is_empty()
	# The status boards hold the old command dock; they sit over the chart and do not stop the clock.
	main._unhandled_key_input(_key(KEY_A))
	await main.get_tree().process_frame
	checks["A opens the status boards without touching the clock"] = main.status_boards.visible and SimClock.paused and main.orders_panel.is_visible_in_tree()
	checks["status boards carry orders, task group, track file and comms"] = main.status_boards._tabs.get_tab_count() == 4
	main._unhandled_key_input(_key(KEY_ESCAPE))
	checks["Escape puts the status boards away"] = not main.status_boards.visible
	if not main.contact_panel.visible_tracks().is_empty():
		main._cycle_priority_track(1)
		checks["N hooks a held track from the filtered track file"] = main.contact_panel.visible_tracks().has(main.map.selected_track)
	main.contact_panel._filter = "AIR"
	main.contact_panel.refresh()
	checks["an empty contact filter leaves nothing to cycle"] = main.contact_panel.visible_tracks().is_empty() == (main.contact_panel.cycle_visible_track(1) == null)
	main.contact_panel._filter = "ALL"
	main.contact_panel.refresh()
	# The data display describes the hook: a contact as held, a platform in full, else the mission.
	var ship: Unit = null
	for u in main.simulation.unit_manager.get_faction_units(main.simulation.player_faction):
		if not u.is_aircraft() and u.spec.max_speed_kn > 0.0:
			ship = u
			break
	main.map.select_units([])
	var held: Array = main.contact_panel.visible_tracks()
	if not held.is_empty():
		main.map.select_track(held[0])
		checks["data display describes the hooked contact"] = _rows_text(main.data_display.build_rows()).contains("TRACK #: %s" % DataDisplay.track_number_for_track(held[0]))
	main.map.select_track(null)
	checks["data display shows the tasking with nothing hooked"] = _rows_text(main.data_display.build_rows()).contains("CONTACTS:")
	main.map.select_units([ship])
	checks["data display describes the hooked platform"] = _rows_text(main.data_display.build_rows()).contains("CLASS: %s" % ship.spec.display_name.to_upper())
	checks["the biggest ship's weapons all fit the data display"] = await _largest_loadout_fits(main)
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	var wide := main.map.size.x
	main._unhandled_key_input(_key(KEY_G))
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	checks["G puts the 3D view on top and the chart in the pane"] = main._world_view.get_parent() == main._upper and main.map.get_parent() == main._view_frame and main.map.size.x < wide - 400.0
	main._unhandled_key_input(_key(KEY_G))
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	checks["G again restores the chart to the top"] = main.map.get_parent() == main._upper and absf(main.map.size.x - wide) < 1.0
	main._unhandled_key_input(_key(KEY_F10))
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	var screen := main.get_viewport_rect()
	checks["F10 gives the 3D view the whole window"] = main._world_view.get_global_rect().size.y > screen.size.y * 0.95 and not main._bottom_strip.visible
	main._unhandled_key_input(_key(KEY_ESCAPE))
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	checks["Escape returns from the full-screen 3D view"] = main._bottom_strip.visible and main.map.get_parent() == main._upper and main.map.visible
	checks["layout changes preserve pause"] = SimClock.paused
	# Right-click: the CDS menu with nothing hooked, the Orders menu on a platform.
	main._on_map_context(main.map.size * 0.5, {"kind": "empty"})
	checks["right-click opens the CDS menu"] = main._cds_menus.is_open()
	main._cds_menus.close()
	main._on_map_context(main.map.world_to_screen(ship.position), {"kind": "own_unit", "unit": ship})
	checks["right-click on a platform opens its orders"] = main._cds_menus.is_open() and main._cds_menus._root.item_count >= 6
	main._cds_menus.close()
	var water := ship.position + Vector2(0.0, 3.0)
	if Terrain.is_land(water):
		water = ship.position + Vector2(0.0, -3.0)
	main.map.move_order_requested.emit(water, false)
	checks["right-click on water sends the hooked platform there"] = not ship.waypoints.is_empty() and ship.waypoints[ship.waypoints.size() - 1].distance_to(water) < 0.01
	main.radio.flash("Radio check", "warn", ship)
	checks["the radio net reaches the chart, the comms board and the lamp"] = main.radio.history[0].ends_with("%s: Radio check" % ship.callsign) and main.status_boards.message_count() > 0 and main.data_display.unread_alerts > 0
	# The crew you can hear, through a recording sink: a scripted run never reaches the OS speech.
	checks["a scripted run never installs the operating system's speech"] = not main.voice.os_speech and not main.voice.sink.is_valid()
	var heard: Array = []
	main.voice.sink = func(line: Dictionary) -> void: heard.append(line)
	main.voice.muted = Callable()
	main.voice.compression = func() -> float: return 1.0
	main.voice.enabled = true
	main._apply_order_to_selection(Order.activate_radar() if ship.radar_on else Order.silence_radar())
	var receipt: String = main.radio.journal.back()
	checks["an accepted order is acknowledged aloud by the platform, not read off the radio"] = heard.size() == 1 and heard[0]["event"] == "order_ack" and str(heard[0]["text"]).begins_with(CrewVoice.spoken_name(ship.callsign)) and not receipt.ends_with(str(heard[0]["text"]))
	var journal_before: int = main.radio.journal.size()
	main.voice._last_spoken_s = -1000.0
	main._apply_order_to_selection(Order.patrol([ship.position, ship.position, ship.position]))
	checks["a refused order is spoken as a refusal and explained as advice"] = heard.size() == 2 and heard[1]["event"] == "order_refused" and main.radio.last_advice != "" and main.radio.journal.size() == journal_before
	main.voice.enabled = false
	main.voice.sink = Callable()
	main._run_palette_action("air_operations")
	await main.get_tree().process_frame
	checks["air operations opens launch controls"] = main._air_operations.visible and SimClock.paused
	main._close_air_operations(false)
	checks["air operations closes without unpausing"] = not main._air_operations.visible and SimClock.paused
	main._unhandled_key_input(_key(KEY_H))
	checks["H shows the key commands and pauses"] = main._key_help.visible and SimClock.paused
	main._unhandled_key_input(_key(KEY_X))
	checks["any key puts the key commands away"] = not main._key_help.visible and SimClock.paused
	# Space pauses exactly once even with a button holding keyboard focus; a focused button
	# would otherwise also answer Space.
	main._hide_screens()
	main.status_boards.open_board(StatusBoards.BOARD_ORDERS)
	await main.get_tree().process_frame
	var paused_before := SimClock.paused
	var button: Button = main.orders_panel._move_btn
	button.focus_mode = Control.FOCUS_ALL
	button.grab_focus()
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	main.get_viewport().push_input(space)
	checks["space toggles pause once with a button focused"] = SimClock.paused != paused_before
	main.status_boards.close_boards()
	SimClock.set_paused(true)
	main._toggle_command_palette()
	checks["the chart and 3D layout is discoverable in actions"] = main._command_palette._actions.any(func(a: Dictionary) -> bool: return a["id"] == "swap_views")
	main._command_palette.close_palette()
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	var bounds := main.get_viewport_rect().grow(1.0)
	var fits := true
	for control: Control in [main, main.map, main.regional, main._world_view, main.data_display]:
		var rect := control.get_global_rect()
		if not bounds.encloses(rect):
			print("[Layout] %s %s outside %s" % [control.name, rect, bounds])
		fits = fits and bounds.encloses(rect) and rect.size.x > 0 and rect.size.y > 0
	checks["command screen fits the viewport"] = fits
	checks["the chart has the top two-thirds of the screen"] = absf(main.map.size.y / bounds.size.y - 0.68) < 0.03 and main.map.size.x >= bounds.size.x - 3.0
	checks["the regional map is square"] = absf(main.regional.size.x - main.regional.size.y) < 4.0
	# A new operation opens on the normal layout at its own framing, even from a swapped screen.
	main.start_scenario("res://data/scenarios/cold_war_01_convoy.json")
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	var opening_ppn := main.map.ppn
	main._swap_views()
	await main.get_tree().process_frame
	main.start_scenario("res://data/scenarios/cold_war_01_convoy.json")
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	checks["a scenario started from a swapped screen opens on the chart at its own framing"] = not main._views_swapped and main.map.get_parent() == main._upper and absf(main.map.ppn - opening_ppn) < 0.001
	var failed := 0
	for label: String in checks:
		print("[Cold War UI] %s %s" % ["PASS" if checks[label] else "FAIL", label])
		if not checks[label]:
			failed += 1
	print("[Cold War UI] %d checks, %d failed" % [checks.size(), failed])
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			await main.get_tree().create_timer(0.6).timeout
			await RenderingServer.frame_post_draw
			var output := arg.get_slice("=", 1)
			var error := main.get_viewport().get_texture().get_image().save_png(output)
			if error != OK:
				failed += 1
				push_error("Failed to write Cold War command capture: %s" % error)
	main.get_tree().quit(1 if failed else 0)


static func _key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	return k


## Draws the board for the hull with the most weapon systems in the catalogue on the real pane, as
## it stands in play (its sensors, and its air wing aboard, each a line of their own), and reports
## whether the weapons grid showed every one of them. Ties go to a hull that carries aircraft.
static func _largest_loadout_fits(main: Main) -> bool:
	var biggest: PlatformSpec = null
	var most := -1
	for spec: PlatformSpec in DataDB.all_platforms():
		var size := spec.weapon_loadout.size() * 2 + (1 if spec.aircraft_capacity > 0 else 0)
		if spec.domain != "air" and size > most:
			biggest = spec
			most = size
	var u := Unit.new()
	u.spec = biggest
	u.callsign = biggest.display_name
	u.alive = true
	u.health = biggest.health
	for sid in biggest.sensor_ids:
		var sensor := DataDB.sensor(sid)
		if sensor != null:
			u.sensors.append(sensor)
	for wid in biggest.weapon_loadout:
		var w := DataDB.weapon(str(wid))
		if w != null:
			u.weapons.append(w)
			u.magazines[w.id] = int(biggest.weapon_loadout[wid])
	if biggest.aircraft_capacity > 0:
		var aircraft := Unit.new()
		aircraft.alive = true
		for spec: PlatformSpec in DataDB.all_platforms():
			if spec.domain == "air":
				aircraft.spec = spec
				break
		u.embarked.append(aircraft)
	var display := main.data_display
	display._accum = -60.0  # hold off the board's own refresh while this one is drawn
	display._rows = DataDisplay.unit_rows(u, null, "0001")
	display.grid_hidden = -1
	display.queue_redraw()
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	var fits := display.grid_hidden == 0
	display._accum = 0.0
	display.refresh()
	return fits


static func _rows_text(rows: Array) -> String:
	var lines := PackedStringArray()
	for row: Array in rows:
		var line := ""
		for span: Array in row:
			if str(span[0]) != "FLOW" and str(span[0]) != DataDisplay.CELL:
				line += str(span[0])
		lines.append(line)
	return "\n".join(lines)
