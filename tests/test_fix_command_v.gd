extends TestCase
## The command screen played through its real keys and surfaces: the Classic key layout on the
## keys the old games used most, the reports of the player's own salvos, gunfire against own
## ships, the 3D view's contact menu, the clock of an ended mission and the dialogs' one heading.

const SCENARIOS := "res://data/scenarios/"

var _save_root := ""
var _clock_speeds: Array[float] = []
var _window_size := Vector2i.ZERO
var _scale_percent := 100


func _open(scenario: String, o: GameOptions = null, game_seed := 2) -> Main:
	_save_root = SaveGame.root_override
	_clock_speeds = SimClock.speeds()
	SaveGame.root_override = "user://test-command-v-%d" % Time.get_ticks_usec()
	var root := (Engine.get_main_loop() as SceneTree).root
	_window_size = root.size
	_scale_percent = InterfaceScale.percent
	var main: Main = preload("res://scenes/main/Main.tscn").instantiate()
	root.add_child(main)
	main._apply_options(o if o != null else GameOptions.normal(), false, false)
	main.simulation.seed_override = game_seed
	main.start_scenario(scenario if scenario.contains("://") else SCENARIOS + scenario)
	main._on_briefing_start()
	SimClock.set_paused(true)
	return main


func _close(main: Main) -> void:
	main.set_classic_keys(false, false)
	var root := main.get_window()
	main.free()
	root.size = _window_size
	InterfaceScale.apply(root, _scale_percent, false)
	var dir := DirAccess.open(SaveGame.root_override)
	if dir != null:
		for file in dir.get_files():
			dir.remove(file)
		DirAccess.remove_absolute(SaveGame.root_override)
	SaveGame.root_override = _save_root
	SimClock.set_speeds(_clock_speeds)
	SimClock.set_speed_index(0)
	SimClock.set_paused(true)


func _own(main: Main, part: String) -> Unit:
	for u: Unit in main.simulation.unit_manager.units:
		if u.faction == main.simulation.player_faction and u.callsign.contains(part):
			return u
	return null


func _window(main: Main) -> void:
	var root := main.get_window()
	root.size = Vector2i(1600, 900)
	InterfaceScale.apply(root, 100, false)
	_settle(main)


func _settle(node: Node) -> void:
	for pass_index in 6:
		_sort(node)


func _sort(node: Node) -> void:
	if node is Container:
		node.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for child in node.get_children():
		_sort(child)


func _key(main: Main, keycode: Key, shift := false, ctrl := false, alt := false) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.physical_keycode = keycode
	e.pressed = true
	e.shift_pressed = shift
	e.ctrl_pressed = ctrl
	e.alt_pressed = alt
	main.get_viewport().push_input(e)
	var up := e.duplicate() as InputEventKey
	up.pressed = false
	main.get_viewport().push_input(up)


func _click(main: Main, at: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	main.get_viewport().push_input(motion)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.position = at
		e.global_position = at
		e.pressed = pressed
		main.get_viewport().push_input(e)


func _hostile_track(main: Main) -> Track:
	for step in 40:
		for t: Track in main.map._visible_tracks():
			if t.identity == "HOSTILE" and not t.is_bearing_only():
				return t
		SimClock.advance(15.0)
	return null


# --- The Classic keys on the keys the old games used most -------------------------------------

func test_classic_e_arms_an_engage_cursor_and_leaves_the_emitters_alone() -> void:
	var main := _open("northern_passage.json")
	_window(main)
	main.set_classic_keys(true, false)
	var u := _own(main, "Truxtun")
	var emcon := u.emcon
	var radar := u.radar_on
	main.map.select_units([u])
	main.map.grab_focus()
	_key(main, KEY_E)
	assert_eq(u.emcon, emcon, "E leaves emission control as it was")
	assert_eq(u.radar_on, radar, "and the radar on")
	assert_eq(main.map.interaction_mode, TacticalMap.InteractionMode.PICK, "E puts up the engage cursor")
	_key(main, KEY_E)
	assert_eq(main.map.interaction_mode, TacticalMap.InteractionMode.SELECT, "E again puts it away")
	assert_true(main.map.selected.has(u), "keeping the hook")
	var t := _hostile_track(main)
	assert_true(t != null, "a hostile contact is held")
	if t == null:
		_close(main)
		return
	main.map.select_units([u])
	main.map.fit_to(t.position, 30.0)
	main.map.grab_focus()
	_key(main, KEY_E)
	var at: Vector2 = main.map.get_global_transform_with_canvas() * main.map.world_to_screen(t.position)
	_click(main, at)
	assert_eq(main.map.interaction_mode, TacticalMap.InteractionMode.SELECT, "the click takes the cursor away")
	assert_true(main.map.selected.has(u), "and the hook stays on the shooter")
	var attacked := u.attack_track == t
	assert_true(attacked, "the contact clicked is the one the hook is ordered to attack (attack %s, advice '%s')" % [u.attack_track.id if u.attack_track != null else "none", main.radio.last_advice])
	assert_eq(u.emcon, emcon, "the radar is still free after the engagement order")
	_close(main)


func test_classic_number_row_recalls_groups_not_the_time_scale() -> void:
	var main := _open("gulf_01_hormuz.json")
	_window(main)
	main.set_classic_keys(true, false)
	var ddg := _own(main, "Paul Ignatius")
	var duncan := _own(main, "Duncan")
	main.map.select_units([ddg, duncan])
	main.map.grab_focus()
	_key(main, KEY_1, false, true)
	main.map.select_units([])
	SimClock.set_speed_index(0)
	_key(main, KEY_1)
	assert_true(main.map.selected.has(ddg) and main.map.selected.has(duncan) and main.map.selected.size() == 2, "1 recalls the group saved with Ctrl+1: %s" % str(main.map.selected.map(func(x: Unit) -> String: return x.callsign)))
	for key: Key in [KEY_3, KEY_6]:
		_key(main, key)
		assert_eq(SimClock.speed_index, 0, "%s leaves the time scale alone" % OS.get_keycode_string(key))
	assert_true(main.radio.last_advice.contains("Group"), "an empty group says so: %s" % main.radio.last_advice)
	_key(main, KEY_T)
	assert_eq(SimClock.speed_index, 1, "T is still the time key")
	main.set_classic_keys(false, false)
	SimClock.set_speed_index(0)
	_key(main, KEY_3)
	assert_eq(SimClock.speed_index, 2, "the default layout keeps the number row on the time scale")
	_close(main)


func test_classic_space_hooks_the_platform_on_the_radio_and_p_pauses() -> void:
	var main := _open("gulf_01_hormuz.json")
	_window(main)
	main.set_classic_keys(true, false)
	var ddg := _own(main, "Paul Ignatius")
	var duncan := _own(main, "Duncan")
	main.map.select_units([ddg])
	main.map.grab_focus()
	main.radio.flash("Contact report", "info", duncan)
	SimClock.set_paused(true)
	_key(main, KEY_SPACE)
	assert_true(SimClock.paused, "Space does not run the clock under the Classic keys")
	assert_eq(main.map.selected, [duncan], "Space hooks the platform heard last")
	_key(main, KEY_P)
	assert_true(not SimClock.paused, "P resumes")
	_key(main, KEY_P)
	assert_true(SimClock.paused, "and pauses")
	main.set_classic_keys(false, false)
	_key(main, KEY_SPACE)
	assert_true(not SimClock.paused, "the default layout's Space still resumes")
	SimClock.set_paused(true)
	_close(main)


func test_the_key_list_names_the_classic_keys_it_now_has() -> void:
	var main := _open("northern_passage.json")
	main.set_classic_keys(true, false)
	var rows := " | ".join(KeyCommands.all_rows())
	assert_true(rows.contains("E: Engage cursor"), "E is listed as the engage cursor: %s" % rows)
	assert_true(rows.contains("1..9: Recall a fleet selection group"), "the number row recalls groups")
	assert_true(rows.contains("Space: Hook the platform heard last on the radio"), "Space hooks the speaker")
	assert_true(rows.contains("P: Pause or resume"), "P pauses")
	assert_true(not rows.contains("Time scale 1x"), "the number row no longer lists the time scales")
	assert_true(not rows.contains("R / P / E"), "nor the default emitters row")
	var keys := KeyCommands.all_keys()
	var seen := {}
	for k: String in keys:
		assert_true(not seen.has(k), "%s is listed once" % k)
		seen[k] = true
	main.set_classic_keys(false, false)
	assert_true(" | ".join(KeyCommands.all_rows()).contains("Time scale 1x"), "the default layout lists the time scales again")
	_close(main)


# --- The player's own salvo shot down is one report -------------------------------------------

const RANGE_SCENARIO := {"id": "test_salvo_report", "name": "Salvo Report", "player_faction": "BLUE", "environment": {"sea_state": 3}, "map": {"center_nm": [0, 0], "extent_nm": 120},
	"objectives": {"text": "Range", "victory": [{"id": "hold", "type": "time_elapsed", "seconds": 60000}], "loss": []}, "units": [
	{"platform": "usn_ddg_burke_iii", "callsign": "USS Shooter", "faction": "BLUE", "position_nm": [0, 0], "speed_kn": 0},
	{"platform": "rfn_cg_slava", "callsign": "Defended Cruiser", "faction": "RED", "position_nm": [0, 30], "speed_kn": 0}]}


func _range(main_seed: int) -> Main:
	var path := "user://test-salvo-report-%d.json" % Time.get_ticks_usec()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(RANGE_SCENARIO))
	file.close()
	var main := _open(path, null, main_seed)
	DirAccess.remove_absolute(path)
	return main


func test_a_salvo_shot_down_over_minutes_is_one_radio_line() -> void:
	var main := _range(3)
	var sim := main.simulation
	var own: Unit = sim.unit_manager.get_engageable_units("BLUE")[0]
	var enemy: Unit = sim.unit_manager.get_engageable_units("RED")[0]
	enemy.radar_on = true
	sim.track_manager.observe("BLUE", enemy, enemy.position, 1, 1, SimClock.sim_time, 1, 10)
	var track := sim.track_manager.find_track("BLUE", enemy)
	track.identity = "HOSTILE"
	track.domain = "surface"
	main.map.select_units([own])
	main.map.select_track(track)
	var lost: Array[float] = []
	sim.weapon_manager.weapon_resolved.connect(func(w: Weapon) -> void:
		if w.faction == "BLUE" and w.spec.id == "tomahawk_block_v" and Main.ROUND_LOSS_WORDS.has(w.dead_reason):
			lost.append(SimClock.sim_time))
	var from := main.radio.journal.size()
	main._apply_order_to_selection(Order.engage(track, "tomahawk_block_v", 8))
	var paused_once := false
	for step in 120:
		SimClock.advance(5.0)
		if not lost.is_empty() and not paused_once:
			# The commander stops the clock with the salvo still on its way: nothing is said early.
			paused_once = true
			SimClock.set_paused(true)
			main._process(0.016)
	var lines := main.radio.journal.slice(from).filter(func(l: String) -> bool: return l.contains("Tomahawk at track") and not l.contains("away"))
	assert_true(lost.size() >= 4, "the cruiser defeats most of the salvo: %d" % lost.size())
	assert_true(lost.max() - lost.min() > 30.0, "over a long interval (%.0f s), not in one instant" % (lost.max() - lost.min()))
	assert_eq(lines.size(), 1, "the salvo is one line on the radio: %s" % str(lines))
	if lines.size() == 1:
		assert_true(str(lines[0]).contains("%d × Tomahawk at track" % lost.size()), "naming every round lost: %s" % lines[0])
	_close(main)


# --- Gunfire is called gunfire, not a missile --------------------------------------------------

const GUN_SCENARIO := {"id": "test_gunfire_call", "name": "Gunfire Call", "player_faction": "BLUE", "environment": {"sea_state": 2}, "map": {"center_nm": [0, 0], "extent_nm": 60},
	"objectives": {"text": "Range", "victory": [{"id": "hold", "type": "time_elapsed", "seconds": 60000}], "loss": []}, "units": [
	{"platform": "usn_ddg_burke_iii", "callsign": "USS Target", "faction": "BLUE", "position_nm": [0, 0], "speed_kn": 0},
	{"platform": "rfn_ddg_udaloy", "callsign": "Gunner", "faction": "RED", "position_nm": [0, 7], "heading_deg": 90.0, "speed_kn": 0}]}


func test_an_enemy_gun_shoot_is_called_gunfire_everywhere_the_commander_reads() -> void:
	for manual: bool in [false, true]:
		var path := "user://test-gunfire-%d.json" % Time.get_ticks_usec()
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(GUN_SCENARIO))
		file.close()
		var main := _open(path, GameOptions.classic() if manual else GameOptions.normal(), 3)
		DirAccess.remove_absolute(path)
		var sim := main.simulation
		var own: Unit = sim.unit_manager.get_engageable_units("BLUE")[0]
		var enemy: Unit = sim.unit_manager.get_engageable_units("RED")[0]
		sim.track_manager.observe("RED", own, own.position, 1, 1, SimClock.sim_time, 1, 10)
		var t := sim.track_manager.find_track("RED", own)
		t.identity = "HOSTILE"
		var from := main.radio.journal.size()
		assert_true(sim.weapon_manager.launch(enemy, DataDB.weapon("ak100_gun"), t, 6, SimClock.sim_time), "the enemy gun opens fire")
		var banner := ""
		var guide := ""
		var kind := ""
		for step in 60:
			SimClock.advance(0.5)
			main._process(0.016)
			if main.data_display.threat_text != "":
				banner = main.data_display.threat_text
				guide = main._command_guide._body.text
				for w: Weapon in sim.weapon_manager.in_flight:
					if w.faction == "RED":
						kind = DefenceBoard.threat_kind(w)
				break
		var said := " | ".join(main.radio.journal.slice(from))
		var mode := "manual" if manual else "automatic"
		assert_true(said.contains("UNDER GUNFIRE"), "%s: the radio calls gunfire: %s" % [mode, said])
		assert_true(not said.contains("INCOMING") and not said.contains("MISSILE"), "%s: and no missile: %s" % [mode, said])
		assert_true(banner.begins_with("UNDER GUNFIRE"), "%s: the banner says gunfire: '%s'" % [mode, banner])
		assert_eq(kind, "GUN", "%s: the defence board's row is a gun round" % mode)
		assert_true(guide.contains("gunfire") and not guide.contains("missile"), "%s: the guide does not send the commander to the missile defence: '%s'" % [mode, guide])
		_close(main)


# --- A right-click on a contact in the 3D view opens that contact's menu ----------------------

func test_right_click_on_a_contact_in_the_3d_view_opens_its_menu() -> void:
	var main := _open("northern_passage.json")
	var u := _own(main, "Truxtun")
	main.map.select_units([u])
	var t := _hostile_track(main)
	assert_true(t != null, "a hostile contact is held")
	if t == null:
		_close(main)
		return
	var view := main._world_view
	main._swap_views()
	main._toggle_world_full()
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(640, 360)
	main.map.select_units([u])
	main.map.select_track(t)
	for i in 3:
		view._process(0.016)
	var at := Vector2.INF
	for rec: Dictionary in view._scene._records.values():
		if rec["entry"].get("track") == t and rec["entry"].get("kind") in ["visual", "plotted"]:
			var root: Node3D = rec["root"]
			at = view._scene.camera.unproject_position(root.global_transform * (rec["bounds"] as AABB).get_center())
	assert_true(at.is_finite(), "the contact is drawn in the 3D view")
	if not at.is_finite():
		_close(main)
		return
	assert_eq(view._scene.pick_entry(at).get("track"), t, "and lies under the cursor at %s" % at)
	main.map.select_units([u])
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = true
	e.position = at
	view._gui_input(e)
	var up := e.duplicate() as InputEventMouseButton
	up.pressed = false
	view._gui_input(up)
	assert_true(main._cds_menus.is_open(), "the right-click opens a menu")
	var first: String = main._cds_menus._root.get_item_text(0) if main._cds_menus.is_open() else ""
	assert_true(first.begins_with("Track %s" % DataDisplay.track_number_for_track(t)), "the contact's own menu, not the hooked ship's: '%s'" % first)
	var texts := PackedStringArray()
	if main._cds_menus.is_open():
		for i in main._cds_menus._root.item_count:
			texts.append(main._cds_menus._root.get_item_text(i))
	assert_true(" | ".join(texts).to_lower().contains("attack"), "offering the attack: %s" % " | ".join(texts))
	assert_eq(main.map.selected, [u], "the hooked ship stays hooked as the shooter")
	main._cds_menus.close()
	_close(main)


# --- An ended mission's clock stays stopped ----------------------------------------------------

func test_the_clock_of_an_ended_mission_does_not_run_again() -> void:
	var main := _open("northern_passage.json")
	_window(main)
	SimClock.set_paused(false)
	main.simulation.mission_manager.mission_ended.emit("DEFEAT", "The convoy was lost.")
	assert_true(SimClock.paused, "the mission's end stops the clock")
	assert_true(main._report.visible, "and shows the debrief")
	_key(main, KEY_SPACE)
	assert_true(SimClock.paused and main._report.visible, "Space on the debrief does nothing")
	main._close_report()
	main.map.grab_focus()
	_key(main, KEY_SPACE)
	assert_true(SimClock.paused, "Space on the chart after the debrief does not run the ended mission")
	assert_true(main.radio.last_advice.contains("ended"), "and says why: %s" % main.radio.last_advice)
	main._run_palette_action("toggle_pause")
	assert_true(SimClock.paused, "nor does the pause action")
	main.data_display.pause_requested.emit()
	assert_true(SimClock.paused, "nor the watch time button")
	main._show_key_commands()
	main._key_help.close()
	assert_true(SimClock.paused, "nor putting away a board that paused it")
	main.set_classic_keys(true, false)
	_key(main, KEY_P)
	assert_true(SimClock.paused, "nor the Classic P")
	main.set_classic_keys(false, false)
	# A new mission runs as before.
	main.start_scenario(SCENARIOS + "northern_passage.json")
	main._on_briefing_start()
	SimClock.set_paused(true)
	main.map.grab_focus()
	_key(main, KEY_SPACE)
	assert_true(not SimClock.paused, "the next mission's Space resumes its watch")
	SimClock.set_paused(true)
	_close(main)


# --- Every in-mission dialog names itself and closes the same way -----------------------------

func test_the_in_mission_dialogs_share_one_heading_and_one_close() -> void:
	var main := _open("northern_passage.json")
	_window(main)
	main.map.select_units([_own(main, "Truxtun")])
	var cases := [
		[KEY_E, true, false, "WEAPON CONTROL", main._weapon_control],
		[KEY_J, false, false, "FLEET OPERATIONS", main._fleet_operations],
		[KEY_A, false, false, "STATUS BOARDS", main.status_boards],
		[KEY_K, false, true, "ACTIONS", main._command_palette],
		[KEY_H, false, false, "KEY COMMANDS", main._key_help],
	]
	for c: Array in cases:
		main.map.grab_focus()
		_key(main, c[0], c[1], c[2])
		var dialog: Control = c[4]
		assert_true(dialog.visible, "%s opens from its key" % c[3])
		var header := dialog.find_child("DialogHeader", true, false)
		assert_true(header != null, "%s has the shared dialog header" % c[3])
		if header == null:
			continue
		var title := header.get_node("Title") as Label
		var close := header.get_node("Close") as Button
		assert_eq(title.text, c[3], "%s names itself in the header" % c[3])
		assert_eq(title.theme_type_variation, "TitleLabel", "%s in the one title face" % c[3])
		assert_eq(close.text, UITheme.DIALOG_CLOSE, "%s closes with the one CLOSE" % c[3])
		assert_eq(close.get_index(), header.get_child_count() - 1, "%s keeps CLOSE at the right" % c[3])
		var stray := dialog.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text.contains("RETURN TO CHART") or b.text.contains("CLOSE  ["))
		assert_true(stray.is_empty(), "%s has no second way to close: %s" % [c[3], str(stray.map(func(b: Button) -> String: return b.text))])
		close.pressed.emit()
		assert_true(not dialog.visible, "%s's CLOSE puts it away" % c[3])
	assert_true(not main._has_visible_modal(), "and nothing is left open")
	_close(main)
