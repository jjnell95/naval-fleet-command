class_name ColdWarSmoke
extends RefCounted
## Integration checks run through the actual scene, input, screen lifecycle and simulation.

static func run(main: Main) -> void:
	var checks: Dictionary = {}
	var menu := main._menu
	main._show_menu()
	await main.get_tree().process_frame
	menu._set_era("cold_war")
	checks["four period missions on the Cold War shelf"] = menu._entries.filter(func(e: Dictionary) -> bool: return str(e["path"]).begins_with("res://")).size() == 4
	checks["all period shelf entries are dated 1990"] = menu._entries.all(func(e: Dictionary) -> bool: return int(e["year"]) == 1990)
	checks["period portrait uses the historical catalogue"] = menu._portrait.spec_override != null and menu._portrait.spec_override.id.begins_with("cw90_")
	checks["mission desk exposes first orders and date"] = menu._detail.text.contains("YOUR FIRST ORDERS") and menu._mission_meta.text.contains("1990")
	menu._set_era("modern")
	checks["existing modern operations remain available"] = menu._entries.size() >= 11 and menu._entries.all(func(e: Dictionary) -> bool: return int(e["year"]) != 1990)
	menu._set_era("all")
	checks["all operations includes both eras"] = menu._entries.size() >= 15
	menu._set_era("cold_war")
	menu._play.pressed.emit()
	await main.get_tree().process_frame
	checks["mission button loads convoy into paused briefing"] = main.simulation.scenario_path == Main.DEFAULT_SCENARIO and main._briefing.visible and not menu.visible and SimClock.paused
	checks["briefing opens on actionable orders"] = main._briefing._active_section == "orders" and main._briefing._body.text.contains("OPENING ORDERS") and main._briefing._body.text.contains("SUCCESS CONDITIONS")
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
	main.start_scenario(Main.DEFAULT_SCENARIO)
	main._show_briefing()
	var b := InputEventKey.new()
	b.keycode = KEY_B
	b.pressed = true
	main._unhandled_key_input(b)
	checks["briefing blocks chart shortcut"] = not main._wide_chart and SimClock.paused
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
	main._watch.refresh()
	checks["watch counts follow the selected contact filter"] = main._watch._buttons[1].disabled == main.contact_panel.visible_tracks().is_empty()
	if not main.contact_panel.visible_tracks().is_empty():
		main._watch._buttons[1].pressed.emit()
		checks["watch contact action selects a held track"] = main.contact_panel.visible_tracks().has(main.map.selected_track)
	main.contact_panel._filter = "AIR"
	main.contact_panel.refresh()
	main._watch.refresh()
	checks["empty contact filter disables watch cycling"] = main._watch._buttons[1].disabled == main.contact_panel.visible_tracks().is_empty()
	main.contact_panel._filter = "ALL"
	main.contact_panel.refresh()
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	var before := main.map.size.x
	main._watch._buttons[4].pressed.emit()
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	checks["wide chart makes room without losing command dock"] = main._wide_chart and not main.unit_panel.visible and not main.contact_panel.visible and main.orders_panel.visible and main.map.size.x > before + 400.0
	checks["layout change preserves pause"] = SimClock.paused
	main._unhandled_key_input(b)
	await main.get_tree().process_frame
	checks["B restores both side panels"] = not main._wide_chart and main.unit_panel.visible and main.contact_panel.visible
	main._watch.refresh()
	checks["watch strip shows scenario intent"] = main._watch._values[0].text == str(main.simulation.scenario.get("commander_intent", ""))
	main._watch._buttons[0].pressed.emit()
	checks["watch orders opens the mission status"] = main._briefing.visible and SimClock.paused
	main._hide_screens()
	checks["closing watch orders preserves prior pause"] = SimClock.paused
	main._watch._buttons[3].pressed.emit()
	await main.get_tree().process_frame
	checks["watch air operations opens launch controls"] = main._air_operations.visible and SimClock.paused
	main._close_air_operations(false)
	checks["air operations closes without unpausing"] = not main._air_operations.visible and SimClock.paused
	main._toggle_command_palette()
	checks["chart layout is discoverable in actions"] = main._command_palette._actions.any(func(a: Dictionary) -> bool: return a["id"] == "wide_chart")
	main._command_palette.close_palette()
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	var bounds := main.get_viewport_rect().grow(1.0)
	var fits := true
	for control: Control in [main, main.top_bar, main._watch, main.map, main.unit_panel, main.contact_panel, main.orders_panel]:
		var rect := control.get_global_rect()
		if not bounds.encloses(rect):
			print("[Layout] %s %s outside %s" % [control.name, rect, bounds])
		fits = fits and bounds.encloses(rect) and rect.size.x > 0 and rect.size.y > 0
	checks["command deck fits the viewport"] = fits
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
