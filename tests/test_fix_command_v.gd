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
