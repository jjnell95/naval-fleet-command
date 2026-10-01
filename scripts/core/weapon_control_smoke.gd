extends RefCounted
## Real scene, order routing, modal input and fit checks for weapon control.

static func run(main: Main) -> void:
	var checks := {}
	var scenario := {"id": "weapon_control_check", "name": "Weapon Control Exercise", "player_faction": "BLUE", "environment": {"sea_state": 3}, "map": {"center_nm": [0, 0], "extent_nm": 80}, "objectives": {"text": "Fictional system check", "victory": [{"id": "hold", "type": "time_elapsed", "seconds": 6000}], "loss": []}, "units": [
		{"platform": "usn_cg_ticonderoga", "callsign": "USS Test Cruiser", "faction": "BLUE", "position_nm": [0, 0], "speed_kn": 0},
		{"platform": "usn_ddg_burke_iii", "callsign": "USS Test Destroyer", "faction": "BLUE", "position_nm": [-3, -2], "speed_kn": 0},
		{"platform": "cw90_sovremenny", "callsign": "Hidden Enemy Name", "faction": "RED", "position_nm": [0, 10], "speed_kn": 0}]}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://work"))
	var file := FileAccess.open("res://work/weapon-control-check.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(scenario))
	file.close()
	main.start_scenario("res://work/weapon-control-check.json")
	main._show_briefing()
	main._on_briefing_start()
	main.simulation.ai_enabled = false
	SimClock.set_paused(true)
	var um := main.simulation.unit_manager
	var own: Array = um.get_engageable_units("BLUE")
	var enemy: Unit = um.get_engageable_units("RED")[0]
	main.simulation.track_manager.observe("BLUE", enemy, enemy.position, 1, 1, SimClock.sim_time, 1, 10)
	var track := main.simulation.track_manager.find_track("BLUE", enemy)
	track.identity = "HOSTILE"
	track.domain = "surface"
	main.map.select_units(own)
	main.map.select_track(track)
	main.map.center_nm = Vector2(0, 5)
	main.map.ppn = 14
	await main.get_tree().process_frame
	var key := InputEventKey.new()
	key.keycode = KEY_E
	key.shift_pressed = true
	key.pressed = true
	main._unhandled_key_input(key)
	await main.get_tree().process_frame
	var board := main._weapon_control
	checks["Shift+E opens the firing board and pauses"] = board.visible and SimClock.paused
	checks["both selected hulls are available"] = board.units.size() == 2
	checks["every fitted system has its own row"] = board._items.size() == own[0].weapons.size() + own[1].weapons.size()
	checks["held contact is preselected"] = board.target == track and board._target_option.selected == 1
	checks["contact label does not reveal hidden callsign"] = not board._target_option.get_item_text(1).contains("Hidden Enemy")
	checks["board fits the viewport"] = board.get_minimum_size().x <= main.get_viewport_rect().size.x and board.get_minimum_size().y <= main.get_viewport_rect().size.y
	checks["table keeps usable space"] = board._tree.size.y > 150
	var wm := main.simulation.weapon_manager
	var gun := DataDB.weapon("mk45_mod4_gun")
	var missile := DataDB.weapon("tomahawk_block_v")
	board.set_salvo(own[0], gun, 2)
	board.set_salvo(own[0], missile, 2)
	board.set_salvo(own[1], missile, 2)
	board.refresh()
	checks["mixed-weapon plan enables commit"] = board._plan.size() == 3 and not board._commit.disabled
	checks["plan summary counts all selected rounds"] = board._plan_summary.text.begins_with("6 rounds planned across 3 systems")
	await main.get_tree().process_frame
	checks["firing solution and plan summary retain visible height"] = board._quality.size.y > 0 and board._detail.size.y > 0 and board._plan_summary.size.y > 0 and not board._quality.text.is_empty()
	board._role_option.select(1)
	board._role_option.item_selected.emit(1)
	checks["filtering discloses hidden planned systems"] = board._plan_summary.text.contains("3 systems hidden by filter")
	board._role_option.select(0)
	board._role_option.item_selected.emit(0)
	await _shot(main, "weapon-control-plan")
	# Leave this disposable fixture open for manual browser interaction checks.
	if OS.get_cmdline_user_args().has("--weapon-control-preview"):
		return
	board._commit.pressed.emit()
	checks["all three unit orders were accepted"] = board._receipt.text.contains("6 rounds committed across 3 systems; 0 orders refused")
	checks["mixed-system receipt counts orders without duplicating platforms"] = main.radio.journal[-1].contains("3 orders accepted")
	checks["each independent launcher fires one round"] = wm.in_flight.size() == 3
	checks["remaining salvo rounds are reserved"] = wm.committed_rounds(own[0], gun, track, true) == 1 and wm.committed_rounds(own[0], missile, track, true) == 1 and wm.committed_rounds(own[1], missile, track, true) == 1
	checks["after-action launch count includes only rounds actually fired"] = main._stats["own_rounds"] == 3
	checks["commit clears the editable plan"] = board._plan.is_empty() and board._commit.disabled
	board._cancel_pending()
	checks["cancel leaves only expended rounds deducted"] = own[0].magazine_count(gun.id) == int(own[0].spec.weapon_loadout[gun.id]) - 1
	checks["cancel preserves weapons already away"] = wm.in_flight.size() == 3 and wm.committed_rounds(own[0], missile, track, true) == 0
	board._role_option.select(1)
	board._role_option.item_selected.emit(1)
	checks["air filter lists only air-capable systems"] = board._items.all(func(i: TreeItem) -> bool: return i.get_metadata(0)[1].target_types.has("air"))
	checks["role choice configures the map overlay"] = main.map.show_weapon_ranges and main.map.weapon_range_role == "air"
	board._role_option.select(0)
	board._role_option.item_selected.emit(0)
	main._close_weapon_control()
	checks["closing restores prior paused state"] = SimClock.paused and not board.visible
	main.map.select_units([own[0]])
	main.map.show_weapon_ranges = true
	await _shot(main, "weapon-range-chart")
	checks["original chart and lower panes remain visible"] = main.map.visible and main._bottom_strip.visible and main.data_display.visible
	SimClock.set_paused(false)
	main._toggle_weapon_control()
	main._close_weapon_control()
	checks["closing restores a previously running clock"] = not SimClock.paused
	SimClock.set_paused(true)
	main._toggle_weapon_control()
	board._target_option.select(0)
	board._target_option.item_selected.emit(0)
	checks["clearing the target clears the chart hook"] = main.map.selected_track == null and board.target == null
	checks["no target disables firing"] = board._commit.disabled and board._items.all(func(i: TreeItem) -> bool: return not i.is_editable(8))
	main._close_weapon_control()
	main.command_bar.refresh()
	main.command_bar.buttons["weapon_control"].pressed.emit()
	checks["Attack command key opens weapon control"] = board.visible
	main._close_weapon_control()
	main.command_bar.buttons["open_defence"].pressed.emit()
	await main.get_tree().process_frame
	checks["Defence command key opens defensive controls"] = main.status_boards.visible and main.orders_panel._tabs.current_tab == 4
	checks["command strip fits the viewport"] = main.command_bar.get_minimum_size().x <= main.get_viewport_rect().size.x
	main._toggle_boards()
	main.map.select_units(own)
	own[0].magazines[gun.id] = 1
	own[1].magazines[gun.id] = 3
	main._apply_unit_orders([[own[0], Order.engage(track, gun.id, 1)], [own[1], Order.engage(track, gun.id, 3)]])
	checks["group attack receipt totals actual committed rounds"] = main.radio.journal[-1].contains("4 rounds committed") and main.radio.journal[-1].contains("2 orders accepted")
	var failures := 0
	for name: String in checks:
		print("%s weapon-control: %s" % ["PASS" if checks[name] else "FAIL", name])
		if not checks[name]:
			failures += 1
	print("---- %d weapon-control checks, %d failed ----" % [checks.size(), failures])
	main.get_tree().quit(1 if failures else 0)


static func _shot(main: Main, name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await main.get_tree().create_timer(0.3).timeout
	await main.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var captured := main.get_viewport().get_texture().get_image()
	captured.save_png("res://work/%s-%d.png" % [name, captured.get_width()])
