extends TestCase
## The command screen's text: the data display's rows, the radio net's lines, the status boards'
## comms history and the right-click menus. All of it is built from data, so it is checked here
## without a renderer.


func _unit(platform_id := "usn_ddg_burke_iii", faction := "BLUE", position := Vector2.ZERO) -> Unit:
	var u := Unit.new()
	u.spec = DataDB.platform(platform_id)
	u.faction = faction
	u.position = position
	u.health = u.spec.health
	u.callsign = "USS Test"
	for sensor_id in u.spec.sensor_ids:
		u.sensors.append(DataDB.sensor(sensor_id))
	for wid in u.spec.weapon_loadout:
		var spec := DataDB.weapon(str(wid))
		if spec != null:
			u.weapons.append(spec)
			u.magazines[spec.id] = int(u.spec.weapon_loadout[wid])
	return u


func _track(id: String, identity: String, position: Vector2) -> Track:
	var t := Track.new()
	t.id = id
	t.owner_faction = "BLUE"
	t.identity = identity
	t.position = position
	return t


static func _text(rows: Array) -> String:
	var lines := PackedStringArray()
	for row: Array in rows:
		var line := ""
		for span: Array in row:
			if str(span[0]) != "FLOW" and str(span[0]) != DataDisplay.CELL:
				line += str(span[0])
		lines.append(line)
	return "\n".join(lines)


func test_track_numbers_are_four_digits_for_contacts_and_own_units() -> void:
	var t := _track("T1007", "HOSTILE", Vector2.ZERO)
	assert_eq(DataDisplay.track_number_for_track(t), "1007", "the data display quotes the chart's number")
	assert_eq(DataDisplay.track_number_for_track(t), MapSymbols.track_number(t.id))


func test_own_unit_rows_read_like_the_data_display() -> void:
	var u := _unit()
	u.id = 0
	u.heading_deg = 325.4
	u.speed_kn = 17.6
	var text := _text(DataDisplay.unit_rows(u, null, "0001"))
	assert_true(text.begins_with("USS Test\n"), "the name is the title line")
	assert_true(text.contains("CLASS: %s" % u.spec.display_name.to_upper()), "class in capitals")
	assert_true(text.contains("TRACK #: 0001"))
	assert_true(text.contains("COURSE: 325"), "course is three digits")
	assert_true(text.contains("SPEED: 18 KTS"))
	assert_true(text.contains("%DAMAGE: 0"))
	assert_true(text.contains("ORDERS: "))
	if not u.weapons.is_empty():
		assert_true(text.contains("WEAPONS:"), "an armed ship lists its weapons")
		assert_true(text.contains("%s %d" % [u.weapons[0].compact_name(), u.magazine_count(u.weapons[0].id)]), "weapons read short name and count")


func test_every_weapon_has_a_short_name_that_fits_a_cell() -> void:
	for w: WeaponSpec in DataDB.all_weapons():
		assert_true(w.short_name != "", "%s has a short name for the data display" % w.id)
		assert_true(w.short_name.length() <= 11, "%s's short name '%s' fits a cell" % [w.id, w.short_name])
		assert_eq(w.compact_name(), w.short_name)


func test_weapons_are_listed_by_job_farthest_first() -> void:
	var names: Array = []
	for w: WeaponSpec in DataDisplay.weapons_by_job(_unit("usn_ddg_burke_iii")):
		names.append(w.short_name)
	assert_eq(names, ["Tomahawk", "SM-6", "SM-2", "ESSM", "Phalanx", "Mk 45", "ASROC"], "strike, air defence by reach, close-in, gun, anti-submarine")
	var rows := DataDisplay.unit_rows(_unit("pla_ddg_type055"))
	var cells := 0
	for row: Array in rows:
		if str(row[row.size() - 1][0]) == DataDisplay.CELL:
			cells += 1
	assert_eq(cells, 9, "every one of the Type 055's nine systems gets a cell; the display decides what fits")


func test_the_weapons_grid_never_drops_a_system_silently() -> void:
	assert_eq(DataDisplay.grid_fit(9, 2, 5), {"shown": 9, "more": 0, "lines": 5}, "nine in two columns take five lines")
	assert_eq(DataDisplay.grid_fit(9, 3, 5), {"shown": 9, "more": 0, "lines": 3})
	assert_eq(DataDisplay.grid_fit(9, 2, 4), {"shown": 7, "more": 2, "lines": 4}, "short of room, the last cell says how many more")
	assert_eq(DataDisplay.grid_fit(4, 2, 0), {"shown": 0, "more": 4, "lines": 0})
	assert_eq(DataDisplay.grid_columns(300.0), 2, "a narrow pane takes two columns")
	assert_eq(DataDisplay.grid_columns(584.0), 3, "the pane at 1600 x 900 takes three")
	assert_eq(DataDisplay.grid_columns(120.0), 1)
	assert_eq(DataDisplay.grid_columns(1000.0), DataDisplay.MAX_COLUMNS)


func test_course_and_speed_share_a_line() -> void:
	var u := _unit()
	u.heading_deg = 90.0
	u.speed_kn = 16.0
	var lines := _text(DataDisplay.unit_rows(u)).split("\n")
	assert_true(lines.has("COURSE: 090   SPEED: 16 KTS"), "one line, so the weapons have one more")


func test_the_weapons_line_states_reach_one_figure_per_job() -> void:
	var text := _text(DataDisplay.unit_rows(_unit("usn_ddg_burke_iii")))
	var head := ""
	for line in text.split("\n"):
		if line.begins_with("WEAPONS:"):
			head = line
	assert_true(head != "", "an armed ship has a weapons head")
	# SM-6 is the farthest air-defence round, Tomahawk the farthest strike, Phalanx the close-in mount.
	assert_true(head.contains("STRIKE 250"), head)
	assert_true(head.contains("AAW 100"), head)
	assert_true(head.contains("CIWS 1.2"), head)
	assert_true(head.contains("GUN 13"), head)
	assert_true(head.contains("ASW 12"), head)
	assert_true(head.ends_with(" NM"), "the unit is stated once, at the end")


func test_a_hull_with_one_close_in_gun_reads_as_exactly_that() -> void:
	var head := ""
	for line in _text(DataDisplay.unit_rows(_unit("rn_cvf_queen_elizabeth"))).split("\n"):
		if line.begins_with("WEAPONS:"):
			head = line
	assert_eq(head.strip_edges(), "WEAPONS:  CIWS 1.2 NM", "no strike, no missile defence, and the display says so")


func test_reach_leaves_out_jobs_the_hull_cannot_do_and_the_head_stays_one_row() -> void:
	var rows := DataDisplay.unit_rows(_unit("usn_ddg_burke_iii"))
	var heads := 0
	for row: Array in rows:
		if str(row[0][0]) == "WEAPONS:":
			heads += 1
	assert_eq(heads, 1, "reach shares the WEAPONS: row, so a long weapon list is no shorter of room than before")
	assert_eq(DataDisplay.reach_spans(_unit("cw90_merchant")), [], "an unarmed hull states no reach")
	# A close-in mount's reach is a mile and a bit; rounding it to a whole number would read as 1 nm.
	var spans := DataDisplay.reach_spans(_unit("rn_cvf_queen_elizabeth"))
	assert_eq(str(spans[1][0]), "1.2", "a tenth is kept where the reach is not a whole number of miles")
	assert_eq(str(DataDisplay.reach_spans(_unit("usn_cg_ticonderoga"))[1][0]), "250", "a whole number of miles prints as one")


func test_damage_and_casualties_are_flagged_in_red() -> void:
	var u := _unit()
	u.health = u.spec.health * 0.6
	u.fire = 0.3
	var rows := DataDisplay.unit_rows(u)
	var found := false
	for row: Array in rows:
		if str(row[0][0]).begins_with("%DAMAGE"):
			found = true
			assert_eq(str(row[1][1]), DataDisplay.ALERT, "damage above zero is red")
			assert_eq(str(row[1][0]), "40")
			assert_true(_text([row]).contains("FIRE"), "a fire is shown on the damage line")
	assert_true(found)


func test_orders_text_describes_what_the_unit_is_doing() -> void:
	var u := _unit()
	u.ordered_speed_kn = 0.0
	assert_eq(DataDisplay.orders_text(u), "Hold position")
	u.ordered_speed_kn = 15.0
	u.ordered_heading_deg = 90.0
	assert_eq(DataDisplay.orders_text(u), "Steady on 090")
	u.waypoints.append(Vector2(10, 10))
	assert_eq(DataDisplay.orders_text(u), "Transit (1 wpt)")


func test_orders_text_drops_completed_weapon_engagements() -> void:
	var u := _unit()
	u.ordered_speed_kn = 0.0
	var manager := WeaponManager.new()
	var w := Weapon.new()
	w.shooter = u
	w.target_track = _track("T1001", "HOSTILE", Vector2(10, 0))
	manager.in_flight.append(w)
	assert_eq(DataDisplay.orders_text(u, manager), "Engage track 1001")
	w.phase = Weapon.Phase.DEAD
	assert_eq(DataDisplay.orders_text(u, manager), "Hold position", "a completed round no longer masks the ship's orders")
	manager.free()


func test_contact_rows_never_read_truth() -> void:
	var truth := _unit("usn_ddg_burke_iii", "RED")
	truth.callsign = "SECRET NAME"
	var t := _track("T1001", "UNKNOWN", Vector2(12, 0))
	t.truth = truth
	var ref := _unit()
	var text := _text(DataDisplay.track_rows(t, ref, 0.0))
	assert_true(not text.contains("SECRET NAME"), "an unidentified contact is described only as held")
	assert_true(text.contains("TRACK #: 1001"))
	assert_true(text.contains("IDENTITY: UNKNOWN"))
	assert_true(text.contains("RANGE: 12.0 nm"), "range from the hooked own unit")


func test_bearing_only_contacts_claim_no_range() -> void:
	var t := _track("T1002", "HOSTILE", Vector2(0, 30))
	t.bearing_only = true
	t.tma_quality = 0.1
	var text := _text(DataDisplay.track_rows(t, _unit(), 0.0))
	assert_true(text.contains("bearing only"))
	assert_true(not text.contains("RANGE:"), "a passive bearing is not a measured range")
	assert_true(text.contains("BEARING: "))


func test_radio_lines_name_the_speaker() -> void:
	var u := _unit()
	assert_eq(RadioNet.format_line("Missile away", u), "USS Test: Missile away")
	assert_eq(RadioNet.format_line("USS Test recovered", u), "USS Test recovered", "no doubled callsign")
	assert_eq(RadioNet.format_line("Objective complete", null), "Objective complete")
	var t := _track("T1003", "HOSTILE", Vector2.ZERO)
	assert_eq(RadioNet.format_line("new contact", t), "T1003 UNK: new contact", "a contact goes by what the plot holds")


func test_radio_net_keeps_history_and_lights_the_lamp_for_warnings() -> void:
	var net := RadioNet.new()
	var display := DataDisplay.new()
	net.display = display
	var heard: Array = []
	net.logged.connect(func(text: String, severity: String) -> void: heard.append([text, severity]))
	net.flash("Contact lost")
	net.flash("Vampire, vampire", "alert")
	assert_eq(net.history.size(), 2)
	assert_true(net.history[0].ends_with("Vampire, vampire"), "newest first")
	assert_eq(display.unread_alerts, 1, "only warnings and alerts light the lamp")
	assert_eq(heard.size(), 2, "every line reaches the event log")
	net.set_alert("MISSILE INBOUND - 2 - 34 s")
	assert_eq(display.threat_text, "MISSILE INBOUND - 2 - 34 s")
	net.clear()
	assert_eq(display.unread_alerts, 0)
	assert_eq(display.threat_text, "")
	display.free()


func test_status_boards_keep_escaped_comms_history() -> void:
	var boards := StatusBoards.new()
	boards.add_message("Plain line")
	boards.add_message("Line with [brackets]", "alert")
	assert_eq(boards.message_count(), 2)
	boards.clear_messages()
	assert_eq(boards.message_count(), 0)
	boards.free()


static func _flatten(items: Array) -> Array:
	var out: Array = []
	for it: Dictionary in items:
		if it.get("separator", false):
			continue
		out.append(it)
		if it.has("children"):
			out.append_array(_flatten(it["children"]))
	return out


static func _find(items: Array, text: String) -> Dictionary:
	for it: Dictionary in _flatten(items):
		if str(it.get("text", "")) == text:
			return it
	return {}


func test_orders_menu_offers_what_the_selection_can_do() -> void:
	var u := _unit()
	var items := CdsMenus.orders_items([u], null, true, true)
	assert_true(not _find(items, "Speed").is_empty(), "a ship has speed orders")
	assert_true(not _find(items, "Flank").is_empty())
	assert_true(_find(items, "Depth").is_empty(), "a surface ship has no depth menu")
	assert_true(_find(items, "Engage with").is_empty(), "no engage menu without a hooked contact")
	var radar := _find(items, "Radar off")
	assert_eq(radar["action"]["kind"], "order")
	assert_eq((radar["action"]["order"] as Order).type, Order.Type.SILENCE_RADAR)
	var free := _find(items, "Free")
	assert_eq(int(free["checked"]), 1, "the current weapons state is ticked")


func test_orders_menu_is_disabled_for_platforms_not_under_command() -> void:
	var u := _unit()
	var items := CdsMenus.orders_items([u], null, false, false)
	assert_true(_find(items, "Speed").is_empty(), "no movement orders for a platform you cannot move")
	assert_true(bool(_find(items, "EMCON")["disabled"]), "state orders are greyed rather than hidden")


func test_engage_menu_lists_suitable_weapons_with_salvo_sizes() -> void:
	var shooter := _unit()
	var target := _track("T1004", "HOSTILE", Vector2(20, 0))
	target.domain = "surface"
	target.classification = Track.Classification.SURFACE
	var items := CdsMenus.engage_items([shooter], target, true)
	assert_true(str(items[0]["text"]).begins_with("Track 1004"), "the menu is titled with the track number")
	var engage := _find(items, "Engage with")
	assert_true(not engage.is_empty())
	var weapons: Array = engage["children"]
	assert_eq(weapons.size(), shooter.weapons_for_track(target).size(), "one entry per suitable weapon")
	if not weapons.is_empty():
		var salvos: Array = weapons[0]["children"]
		assert_true(salvos.size() >= 1)
		assert_eq(salvos[0]["action"]["kind"], "engage")
		assert_eq(salvos[0]["action"]["track"], target)


func test_cds_menu_reflects_layer_state() -> void:
	var items := CdsMenus.cds_items({"leaders": true, "tags": false, "symbol_mode": 2})
	assert_eq(int(_find(items, "Velocity leaders  [Shift+V]")["checked"]), 1)
	assert_eq(int(_find(items, "Tags  [Shift+I]")["checked"]), 0)
	assert_eq(int(_find(items, "Medium graphic")["checked"]), 1)
	assert_eq(int(_find(items, "NTDS")["checked"]), 0)
	assert_eq(_find(items, "Missions  [M]")["action"]["id"], "missions")


func test_key_commands_board_lists_the_cds_bindings() -> void:
	var keys := " | ".join(KeyCommands.all_keys())
	for binding in ["Space", "G", "F10", "T", "F9 / F11 / F12 / F8", "A", "Tab", "H", "W", "Ctrl+K", "Ctrl+F10 twice", "Right-click"]:
		assert_true(keys.contains(binding), "the key board lists %s" % binding)


func test_under_the_layer_is_greyed_with_the_reason_where_there_is_no_layer() -> void:
	var saved: Dictionary = Detection.environment.duplicate()
	Detection.environment["layer_depth_m"] = 0.0
	var boat := _unit("fra_ssn_suffren")
	var items := CdsMenus.orders_items([boat], null, true, true)
	var under := _find(items, "Under the layer")
	assert_true(not under.is_empty(), "a submarine has the preset")
	assert_true(bool(under["disabled"]), "with no layer the preset is greyed rather than silently doing nothing")
	assert_true(str(under["tooltip"]).contains("No layer"), "and says why")
	assert_true(not bool(_find(items, "Patrol")["disabled"]), "the other depths stay available")
	Detection.environment = saved


func test_the_scale_footer_answers_left_and_right_clicks_only() -> void:
	var display := DataDisplay.new()
	display._scale_rect = Rect2(100, 100, 60, 18)
	var steps: Array = []
	display.scale_step_requested.connect(func(step: int) -> void: steps.append(step))
	for button in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = true
		e.position = Vector2(120, 108)
		display._gui_input(e)
	assert_eq(steps, [1, -1], "the wheel and middle button do not touch the clock")
	display.free()


func test_reading_the_comms_board_by_any_route_announces_it() -> void:
	var boards := StatusBoards.new()
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(boards)
	for board in 3:
		boards.host(Control.new(), board)
	boards.finish_boards()
	var shown := [0]
	boards.comms_shown.connect(func() -> void: shown[0] += 1)
	boards.open_board(StatusBoards.BOARD_ORDERS)
	assert_eq(shown[0], 0, "the orders board is not the comms board")
	boards._tabs.current_tab = StatusBoards.BOARD_COMMS
	assert_eq(shown[0], 1, "a click on the COMMS tab counts as reading it")
	boards.close_boards()
	boards.open_board(StatusBoards.BOARD_COMMS)
	assert_true(shown[0] >= 2, "so does opening the boards straight onto it")
	boards.queue_free()
