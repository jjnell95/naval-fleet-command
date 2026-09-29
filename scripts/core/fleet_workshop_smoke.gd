extends RefCounted
## New-feature integration checks through the real Main scene, command routing and storage.

static func run(main: Main) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://work"))
	var checks: Dictionary = {}
	main._show_menu()
	await main.get_tree().process_frame
	checks["custom library is the default front door"] = main._menu._era == "custom"
	checks["normal mission shelf contains only custom files"] = main._menu._entries.all(func(e: Dictionary) -> bool: return e["custom"])
	main._show_editor()
	var editor := main._editor
	var recipe := {"seed": 92729, "blue_ships": 14, "red_ships": 12, "blue_carriers": 1, "red_carriers": 1, "blue_subs": 2, "red_subs": 2, "aircraft_per_carrier": 12}
	editor.load_dict(ScenarioWorkshop.generate(recipe))
	await main.get_tree().process_frame
	checks["generated scenario is valid in the editor"] = editor.validate() == ""
	checks["editor toolbar stays inside the viewport"] = editor.get_minimum_size().x <= main.get_viewport_rect().size.x
	checks["chart retains working room"] = editor._chart.size.x >= 250 and editor._chart.size.y >= 250
	editor._open_recipe()
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	checks["fleet builder fits inside the desktop viewport"] = editor._recipe_popup.size.x <= main.get_viewport_rect().size.x and editor._recipe_popup.size.y <= main.get_viewport_rect().size.y * 0.85
	await _shot(main, "workshop-builder")
	editor._recipe_popup.hide()
	var authored: int = editor.scenario["units"].size()
	editor.palette_platform = "usn_ddg_arleigh_burke_iia"
	editor._place_count.value = 6
	editor.place(Vector2(70, -30))
	checks["bulk placement creates six independently editable hulls"] = editor.scenario["units"].size() == authored + 6
	editor.undo()
	checks["undo restores the fleet before bulk placement"] = editor.scenario["units"].size() == authored
	editor.redo()
	checks["redo restores all six hulls"] = editor.scenario["units"].size() == authored + 6
	editor.select_unit(0)
	checks["carrier air wing has editable controls"] = editor._wing_box.get_child_count() > 1
	checks["weapon fit has editable controls"] = editor._loadout_box.get_child_count() > 1
	editor.duplicate_selected()
	var cloned_force := UnitManager.new()
	ScenarioLoader.populate(cloned_force, ScenarioWorkshop.export_scenario(editor.scenario))
	var aircraft_names: Dictionary = {}
	var aircraft_count := 0
	for u: Unit in cloned_force.units:
		if u.is_aircraft():
			aircraft_count += 1
			aircraft_names[u.faction + ":" + u.callsign] = true
	checks["cloning a carrier gives its air wing distinct callsigns"] = aircraft_names.size() == aircraft_count
	cloned_force.free()
	editor.undo()
	editor.select_unit(0)
	editor._add_task()
	editor._objective_kind.select(3)
	editor._minutes.value = 10
	editor._apply_objective()
	checks["adding a phase preserves the previous battle objective"] = editor.scenario["objectives"]["victory"].size() == 2 and editor.scenario["objectives"]["victory"][0]["type"] == "force_destroyed"
	checks["hold-area phase follows its prerequisite"] = editor.scenario["objectives"]["victory"][1]["type"] == "hold_area" and editor.scenario["objectives"]["victory"][1]["after"].has("defeat_red")
	var red_index := -1
	for i in editor.scenario["units"].size():
		if editor.scenario["units"][i]["faction"] == "RED" and not editor.scenario["units"][i].has("formation_leader"):
			red_index = i
	# A standalone submarine makes a reinforcement without stranding the group's flagship.
	for i in editor.scenario["units"].size():
		if editor.scenario["units"][i]["faction"] == "RED" and DataDB.platform(editor.scenario["units"][i]["platform"]).domain == "subsurface":
			red_index = i
	if red_index >= 0:
		editor.select_unit(red_index)
		editor._unit_set("editor_arrival_s", 600.0)
	var json_text := editor.to_json()
	var exported: Dictionary = JSON.parse_string(json_text)
	checks["arrival time exports a reinforcement event"] = exported["events"].size() == 1
	checks["battle objective waits for hostile reinforcement"] = exported["objectives"]["victory"][0]["after"].has("waves_arrived_red")
	editor.load_dict(exported)
	checks["wave units round-trip into the editor without duplication"] = editor.scenario["units"].size() == authored + 6 and editor.to_json().count("editor_wave_600") == 1
	checks["custom mission saves"] = editor.save()
	var first_path := editor._opened_path
	checks["second save updates the opened mission"] = editor.save() and editor._opened_path == first_path
	editor.select_unit(0)
	await _shot(main, "workshop-editor")
	main.start_scenario(first_path)
	main._show_briefing()
	checks["custom mission enters its paused briefing"] = main._briefing.visible and SimClock.paused
	checks["loader builds the full authored carrier air wing"] = main.simulation.unit_manager.units[0].embarked.size() == 12
	checks["mission does not resolve on load"] = main.simulation.mission_manager.result == MissionManager.Result.RUNNING
	main._on_briefing_start()
	SimClock.set_paused(true)
	var own: Array = []
	for u in main.simulation.unit_manager.get_engageable_units("BLUE"):
		if u.spec.domain == "surface":
			own.append(u)
	main.map.select_units(own)
	main._store_control_group(1)
	main.map.clear_selection()
	main._recall_control_group(1)
	checks["control groups recall the full fleet selection"] = main.map.selected.size() == own.size()
	main._apply_formation("dispersed")
	var stations: Dictionary = {}
	for i in range(1, own.size()):
		stations[own[i].formation_offset] = true
	checks["large fleet receives distinct stations through player orders"] = stations.size() == own.size() - 1
	main._toggle_fleet_operations()
	await main.get_tree().process_frame
	checks["fleet board groups all friendly surface platforms"] = main._fleet_operations._groups.any(func(g: Dictionary) -> bool: return g["members"].size() == own.size())
	checks["fleet board fits the viewport"] = main._fleet_operations.get_minimum_size().x <= main.get_viewport_rect().size.x
	await _shot(main, "workshop-fleet")
	main._close_fleet_operations()
	var flagship: Unit = own[0]
	main.map.select_units([flagship])
	main._apply_order_to_selection(Order.set_auto_countermeasures(false))
	var packs := flagship.decoys
	main._apply_order_to_selection(Order.deploy_countermeasures("radar"))
	main.orders_panel._sync_quick_actions()
	checks["manual countermeasure button routes and consumes a pack"] = flagship.decoys == packs - 1 and flagship.countermeasure_remaining_s > 0
	checks["orders panel shows remaining packs and an active window"] = main.orders_panel._defence_summary.text.contains("ACTIVE")
	var threat := Weapon.new()
	threat.id = 99001
	threat.spec = DataDB.weapon("p800_oniks")
	if threat.spec == null:
		threat.spec = DataDB.weapon("cw90_harpoon")
	threat.faction = "RED"
	threat.position = flagship.position + Vector2(0, 3)
	threat.heading_deg = 180
	threat.acquired = flagship
	threat.phase = Weapon.Phase.TERMINAL
	main.simulation.weapon_manager.in_flight.append(threat)
	main.simulation.threat_manager.mark_detected("BLUE", threat, 0, flagship)
	main._apply_order_to_selection(Order.evade())
	checks["player evasion order reaches the detected-threat model"] = flagship.evasion_remaining_s > 0
	main.status_boards.open_board(StatusBoards.BOARD_ORDERS)
	main.orders_panel._tabs.current_tab = 4
	main.orders_panel._sync_quick_actions()
	await _shot(main, "workshop-defence")
	main._apply_order_to_selection(Order.resume_plan())
	checks["resume-plan command ends emergency steering"] = flagship.evasion_remaining_s == 0
	main.start_scenario(first_path)
	checks["scenario replacement clears stale selection groups"] = main._control_groups.is_empty()
	main._show_editor()
	editor.load_dict(exported)
	checks["imported mission with duplicate seed saves a distinct copy"] = editor.save() and editor._opened_path != first_path and FileAccess.file_exists(first_path)
	var out := FileAccess.open("res://work/validation-workshop-ui-%d.json" % int(main.get_viewport_rect().size.x), FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify(checks, "  "))
	var failed := 0
	for label: String in checks:
		print("[Workshop] %s %s" % ["PASS" if checks[label] else "FAIL", label])
		failed += int(not checks[label])
	print("[Workshop] %d checks, %d failed" % [checks.size(), failed])
	main.get_tree().quit(1 if failed > 0 else 0)


static func _shot(main: Main, label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Periodic display caches settle after selection and scenario replacement.
	await main.get_tree().create_timer(0.25).timeout
	await main.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://work/%s-%d.png" % [label, int(main.get_viewport_rect().size.x)]
	main.get_viewport().get_texture().get_image().save_png(path)
