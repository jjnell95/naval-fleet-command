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
			if str(span[0]) != "FLOW":
				line += str(span[0])
		lines.append(line)
	return "\n".join(lines)


func test_track_numbers_are_four_digits_for_contacts_and_own_units() -> void:
	var t := _track("T1007", "HOSTILE", Vector2.ZERO)
	assert_eq(DataDisplay.track_number_for_track(t), "1007")
	var u := _unit()
	u.id = 4
	assert_eq(DataDisplay.track_number_for_unit(u), "0005", "own units number from one, zero-padded")


func test_own_unit_rows_read_like_the_data_display() -> void:
	var u := _unit()
	u.id = 0
	u.heading_deg = 325.4
	u.speed_kn = 17.6
	var text := _text(DataDisplay.unit_rows(u))
	assert_true(text.begins_with("USS Test\n"), "the name is the title line")
	assert_true(text.contains("CLASS: %s" % u.spec.display_name.to_upper()), "class in capitals")
	assert_true(text.contains("TRACK #: 0001"))
	assert_true(text.contains("COURSE: 325"), "course is three digits")
	assert_true(text.contains("SPEED: 18 KTS"))
	assert_true(text.contains("%DAMAGE: 0"))
	assert_true(text.contains("ORDERS: "))
	if not u.weapons.is_empty():
		assert_true(text.contains("WEAPONS:"), "an armed ship lists its weapons")
		assert_true(text.contains("%s - %d" % [u.weapons[0].display_name, u.magazine_count(u.weapons[0].id)]), "weapons read name - count")


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
	assert_eq(RadioNet.format_line("new contact", t), "Track 1003: new contact")


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
