extends TestCase
## The boards and read-outs on the command screen at every interface size, the true time rate, the
## Classic key layout and the radio lines that reach the commander, played through the real screen.

const SCENARIOS := "res://data/scenarios/"
const SIZES := [100, 110, 125]

var _save_root := ""
var _clock_speeds: Array[float] = []
var _window_size := Vector2i.ZERO
var _scale_percent := 100


func _open(scenario: String, o: GameOptions = null, game_seed := 2) -> Main:
	_save_root = SaveGame.root_override
	_clock_speeds = SimClock.speeds()
	SaveGame.root_override = "user://test-command-three-%d" % Time.get_ticks_usec()
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
	# The clock is shared with every other test file: hand it back as it was found.
	SimClock.set_speeds(_clock_speeds)
	SimClock.set_speed_index(0)
	SimClock.set_paused(true)


func _own(main: Main, part: String) -> Unit:
	for u: Unit in main.simulation.unit_manager.units:
		if u.faction == main.simulation.player_faction and u.callsign.contains(part):
			return u
	return null


## A 1600x900 window at an interface size, laid out as a frame would lay it out.
func _window(main: Main, percent: int) -> void:
	var root := main.get_window()
	root.size = Vector2i(1600, 900)
	InterfaceScale.apply(root, percent, false)
	_settle(main)


## Containers sort their children on a deferred call; a test has no frames, so sort them now,
## top down, until nothing moves.
func _settle(main: Main) -> void:
	for pass_index in 6:
		_sort(main)
		if main.status_boards.visible:
			main.status_boards._fit()


func _sort(node: Node) -> void:
	if node is Container:
		node.notification(Container.NOTIFICATION_SORT_CHILDREN)
	elif node is Label and node.autowrap_mode != TextServer.AUTOWRAP_OFF:
		# A wrapped label measures its height again when it is next drawn; ask it now.
		node.update_minimum_size()
	for child in node.get_children():
		_sort(child)


func _inside(inner: Rect2, outer: Rect2) -> bool:
	return outer.grow(0.5).encloses(inner)


# --- The status boards fit the chart at every interface size, on every board -------------------

func test_every_status_board_fits_inside_the_chart_at_every_interface_size() -> void:
	var main := _open("northern_passage.json")
	for percent: int in SIZES:
		_window(main, percent)
		var upper: Rect2 = main._upper.get_global_rect()
		for board in main.status_boards._tabs.get_tab_count():
			main.status_boards.open_board(board)
			_settle(main)
			var rect := main.status_boards.get_global_rect()
			assert_true(_inside(rect, upper), "%d%%, board %d: the boards %s lie inside the chart %s" % [percent, board, str(rect), str(upper)])
	_close(main)


func test_the_orders_board_stands_at_the_foot_of_the_chart_at_its_own_height() -> void:
	var main := _open("northern_passage.json")
	for percent: int in SIZES:
		_window(main, percent)
		main.status_boards.open_board(StatusBoards.BOARD_ORDERS)
		_settle(main)
		var upper: Rect2 = main._upper.get_global_rect()
		var rect := main.status_boards.get_global_rect()
		assert_near(rect.end.y, upper.end.y - 12.0, 1.0, "%d%%: the orders board stands on the foot of the chart" % percent)
		assert_true(rect.size.y < upper.size.y * 0.6, "%d%%: the orders board leaves the plot above it in view (%d of %d px)" % [percent, int(rect.size.y), int(upper.size.y)])
		var orders := main.orders_panel.get_global_rect()
		assert_true(orders.end.y <= rect.end.y + 0.5, "%d%%: every orders control is on the board" % percent)
	_close(main)


# --- The key list fits the window at every interface size -----------------------------------

func test_the_key_list_fits_the_window_at_every_interface_size() -> void:
	var main := _open("northern_passage.json")
	for classic: bool in [false, true]:
		main.set_classic_keys(classic, false)
		for percent: int in SIZES:
			_window(main, percent)
			main._key_help.open()
			_settle(main)
			# The board is centred in the window, so it is on screen when it is no larger than the window.
			var screen := main.get_viewport_rect().size
			var panel: Vector2 = main._key_help._panel.get_combined_minimum_size()
			assert_true(panel.x <= screen.x - 24.0 and panel.y <= screen.y, "%d%%%s: the key list %s fits the window %s" % [percent, " classic" if classic else "", str(panel), str(screen)])
			main._key_help.close()
	main.set_classic_keys(false, false)
	_close(main)


# --- The weapons posture can be read on its grey button --------------------------------------

func _luminance(c: Color) -> float:
	var lin := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * lin.call(c.r) + 0.7152 * lin.call(c.g) + 0.0722 * lin.call(c.b)


func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func test_the_weapons_posture_is_readable_in_every_state() -> void:
	var main := _open("northern_passage.json")
	var u := _own(main, "Truxtun")
	var button: Button = main.orders_panel._roe_btn
	for roe: int in [Unit.Roe.FREE, Unit.Roe.TIGHT, Unit.Roe.HOLD]:
		u.roe = roe
		main.orders_panel.set_units([u], true)
		for pair: Array in [["font_color", "normal"], ["font_hover_color", "hover"], ["font_focus_color", "normal"]]:
			var key: String = pair[0]
			var face: Color = (button.get_theme_stylebox(pair[1]) as JfcStyle).face
			var ink := button.get_theme_color(key)
			var ratio := _contrast(ink, face)
			assert_true(ratio >= 4.5, "%s: %s %s on the face %s is %.2f:1" % [button.text, key, ink.to_html(false), face.to_html(false), ratio])
	assert_true(button.text == "WPNS HOLD", "the button names the posture: %s" % button.text)
	_close(main)


func test_the_grey_surface_inks_read_on_every_button_face() -> void:
	for face: Color in [UITheme.JFC_FACE, UITheme.JFC_FACE_HOVER, UITheme.JFC_FACE_DOWN]:
		for severity: String in StatusBoards.SEVERITY_COLORS:
			var ratio := _contrast(Color(StatusBoards.SEVERITY_COLORS[severity]), face)
			assert_true(ratio >= 4.5, "%s on %s is %.2f:1" % [severity, face.to_html(false), ratio])


# --- The COURSE box reads the course the hooked ship steers ----------------------------------

func test_the_course_box_loads_the_hooked_ships_ordered_course() -> void:
	var main := _open("northern_passage.json")
	var sim := main.simulation
	var u := _own(main, "Truxtun")
	main.map.select_units([u])
	main.status_boards.open_board(StatusBoards.BOARD_ORDERS)
	var spinner: SpinBox = main.orders_panel._heading
	# A move to a point well off her bow: she comes round to steer for it.
	var goal := u.position + Vector2.from_angle(deg_to_rad(229.0 - 90.0)) * 30.0
	sim.unit_manager.issue_order(u, Order.move(goal))
	SimClock.advance(1.0)
	main.orders_panel.refresh()
	var steering := posmod(roundi(u.ordered_heading_deg), 360)
	assert_true(absi(steering - 90) > 20, "the ship now steers away from the opening course (%d)" % steering)
	assert_eq(int(spinner.value), steering, "the COURSE box reads the course she steers")
	# A figure the commander steps to is kept while her course stands, and replaced when it moves.
	spinner.value = 10
	main.orders_panel.refresh()
	assert_eq(int(spinner.value), 10, "a figure not yet set is left alone")
	sim.unit_manager.issue_order(u, Order.set_course(300.0))
	main.orders_panel.refresh()
	assert_eq(int(spinner.value), 300, "a new ordered course replaces it")
	# A group shows its lead's course.
	var other := _own(main, "Amundsen")
	sim.unit_manager.issue_order(other, Order.set_course(45.0))
	main.map.select_units([other, u])
	main.orders_panel.refresh()
	assert_eq(int(spinner.value), 45, "a hooked group reads its lead's course")
	_close(main)


# --- The air-defence board -------------------------------------------------------------------

## Detected rounds of `spec_id` running at `at`, fired by the other side, as the plot holds them.
func _raid(main: Main, at: Unit, spec_id: String, count: int, first_id := 99100) -> Array:
	var sim := main.simulation
	var enemy := ""
	for u: Unit in sim.unit_manager.units:
		if u.faction != sim.player_faction and not sim.track_manager.neutral_factions.has(u.faction):
			enemy = u.faction
			break
	var out := []
	for i in count:
		var w := Weapon.new()
		w.id = first_id + i
		w.spec = DataDB.weapon(spec_id)
		w.faction = enemy
		w.position = at.position + Vector2(0.4 * i, 8.0 + 0.5 * i)
		w.heading_deg = 0
		w.acquired = at
		w.phase = Weapon.Phase.TERMINAL
		sim.weapon_manager.in_flight.append(w)
		sim.threat_manager.mark_detected(sim.player_faction, w, 0, at)
		out.append(w)
	return out


func _defence_board(main: Main) -> DefenceBoard:
	return main.contact_panel.find_children("*", "DefenceBoard", true, false)[0]


func test_the_air_defence_board_names_rounds_short_lists_what_fits_and_counts_bmd_rounds() -> void:
	var main := _open("gulf_01_hormuz.json")
	var target := _own(main, "Paul Ignatius")
	_raid(main, target, "irn_qader", 9)
	var board := _defence_board(main)
	board.size = Vector2(560, 240)
	var shown := board.layout()
	assert_eq(int(shown["inbound"]), 9, "nine rounds inbound")
	var rows: Array = shown["rows"]
	assert_true(rows.size() > 4, "the board lists every row its height has room for, not four: %d" % rows.size())
	assert_eq(rows.size() + int(shown["more"]), 9, "and counts the rest")
	for row: Dictionary in rows:
		assert_true(str(row["weapon"]).begins_with("MSL Qader"), "the round goes by its short name: %s" % row["weapon"])
		assert_true(str(row["target"]) in ["→ Paul Ignatius (DDG 117)", "→ Paul Ignatius", "→ Paul"], "the ship's name is not cut inside a word: %s" % row["target"])
	# A tall board lists all nine.
	board.size = Vector2(560, 460)
	shown = board.layout()
	assert_eq((shown["rows"] as Array).size(), 9, "a board with room lists all nine")
	assert_eq(int(shown["more"]), 0)
	var interceptors := str(shown["rounds"])
	assert_true(interceptors.contains(" SAM / ") and interceptors.ends_with(" BMD"), "a force with ballistic-capable rounds counts them beside the SAMs: %s" % interceptors)
	# A narrow board cuts at a word, never inside one.
	assert_eq(board.fit_words("→ Paul Ignatius (DDG 117)", 60.0, 10), "→ Paul", "a tight column keeps whole words")
	_close(main)


func test_a_gun_round_reads_as_gunfire_on_the_board() -> void:
	var main := _open("gulf_01_hormuz.json")
	var target := _own(main, "Paul Ignatius")
	assert_true(DataDB.weapon("a190_100mm_gun").is_gun(), "the round is a gun's")
	var rounds := _raid(main, target, "a190_100mm_gun", 1)
	assert_eq(DefenceBoard.threat_kind(rounds[0]), "GUN", "a shell is gunfire, not a missile")
	assert_eq(DefenceBoard.threat_kind(_raid(main, target, "irn_qader", 1, 99200)[0]), "MSL")
	_close(main)


func test_the_orders_defence_line_has_no_dangling_separator() -> void:
	var main := _open("northern_passage.json")
	var u := _own(main, "Truxtun")
	main.map.select_units([u])
	main.orders_panel._sync_defence()
	var line: String = main.orders_panel._defence_summary.text
	assert_true(not line.ends_with("/") and not line.ends_with("/ "), "the defence line ends on a value: '%s'" % line)
	_close(main)


# --- The battle assessment board -------------------------------------------------------------

func _enemy_ship(main: Main) -> Unit:
	var sim := main.simulation
	for u: Unit in sim.unit_manager.units:
		if u.faction != sim.player_faction and not sim.track_manager.neutral_factions.has(u.faction) and not u.is_aircraft() and u.alive:
			return u
	return null


func test_the_assessment_board_shows_effectiveness_losses_and_tasks_while_the_mission_runs() -> void:
	var main := _open("gulf_01_hormuz.json")
	var sim := main.simulation
	main.status_boards.open_board(StatusBoards.BOARD_ASSESSMENT)
	assert_eq(main.status_boards.current_board(), StatusBoards.BOARD_ASSESSMENT, "the boards carry an assessment")
	var text: String = main.status_boards._assessment.get_parsed_text()
	var a := sim.mission_manager.assessment()
	assert_true(text.contains("MISSION EFFECTIVENESS  %d%%" % int(a["percent"])), "it opens on the mission's running effectiveness: %s" % text.left(200))
	assert_true(text.contains("ENEMY LOSSES  0") and text.contains("OWN LOSSES  0"), "no losses yet on either side")
	var first_task: MissionObjective = null
	for o: MissionObjective in sim.mission_manager.victory_objectives:
		if not o.phase_only:
			first_task = o
			break
	assert_true(first_task != null and text.contains(first_task.text.left(30)), "each task is listed with its state")
	# A ship of the other side sunk by the force, and one of the force's own lost.
	var enemy := _enemy_ship(main)
	enemy.alive = false
	sim.weapon_manager.unit_destroyed.emit(enemy, sim.player_faction)
	var own := _own(main, "Duncan")
	own.alive = false
	sim.weapon_manager.unit_destroyed.emit(own, "RED")
	main.status_boards.render_assessment()
	text = main.status_boards._assessment.get_parsed_text()
	assert_true(text.contains("ENEMY LOSSES  1"), "the enemy loss is counted: %s" % text)
	assert_true(text.contains("OWN LOSSES  1") and text.contains(own.callsign), "the own loss is named")
	_close(main)


func test_the_assessment_board_fits_the_chart() -> void:
	var main := _open("gulf_01_hormuz.json")
	for percent: int in SIZES:
		_window(main, percent)
		main.status_boards.open_board(StatusBoards.BOARD_ASSESSMENT)
		_settle(main)
		var upper: Rect2 = main._upper.get_global_rect()
		var rect := main.status_boards.get_global_rect()
		assert_true(_inside(rect, upper), "%d%%: the assessment %s lies inside the chart %s" % [percent, str(rect), str(upper)])
	_close(main)


# --- The true time rate ----------------------------------------------------------------------

const ClockScript := preload("res://scripts/simulation/sim_clock.gd")


func test_over_budget_ticks_lower_the_achieved_rate_and_the_screen_says_so() -> void:
	var clock := ClockScript.new()
	clock.set_speed_index(5)
	clock.set_paused(false)
	# A light battle delivers what 60x asks for.
	for frame in 30:
		clock._process(0.1)
	assert_near(clock.achieved_rate(), 60.0, 0.5, "a light battle runs at the asked rate")
	assert_eq(clock.rate_text(), "60x", "and the screen says only the asked rate")
	# A heavy one: each tick costs longer than the whole frame budget, so a frame steps once.
	clock.frame_budget_usec = 1
	clock.tick.connect(func(_dt: float) -> void: OS.delay_usec(200))
	for frame in 150:
		clock._process(0.1)
	# One tick of 0.25 s per 0.1 s frame is 2.5x.
	assert_near(clock.achieved_rate(), 2.5, 0.5, "the achieved rate falls to what the frames step: %.1f" % clock.achieved_rate())
	assert_true(clock.rate_short(), "the shortfall is noticed")
	assert_eq(clock.rate_text(), "60x > 3x", "the screen shows what is asked and what is delivered")
	# A new speed starts from its own figure.
	clock.set_speed_index(0)
	assert_near(clock.achieved_rate(), 1.0, 0.001)
	clock.free()


func test_the_command_bar_and_data_display_show_the_achieved_rate_when_short() -> void:
	var main := _open("northern_passage.json")
	SimClock.set_speed_index(5)
	SimClock.set_paused(false)
	SimClock._achieved = 18.0
	main.command_bar.refresh()
	assert_eq(main.command_bar.buttons["time_menu"].text, "60× > 18× ▾", "the speed button shows both rates")
	assert_true(main.command_bar.buttons["toggle_pause"].text.ends_with("60× > 18×"), main.command_bar.buttons["toggle_pause"].text)
	SimClock._achieved = 58.0
	main.command_bar.refresh()
	assert_eq(main.command_bar.buttons["time_menu"].text, "60× ▾", "within a tenth of the asked rate only the asked rate shows")
	SimClock.set_paused(true)
	_close(main)


# --- Dialogs stand as tall as their content --------------------------------------------------

func _panel_of(dialog: Control) -> PanelContainer:
	return dialog.find_children("*", "PanelContainer", true, false)[0]


func test_fleet_operations_and_weapon_control_are_as_tall_as_their_rows() -> void:
	var main := _open("northern_passage.json")
	_window(main, 100)
	main.map.select_units([_own(main, "Truxtun")])
	main._toggle_fleet_operations()
	_settle(main)
	var screen := main.get_viewport_rect().size
	var fleet := _panel_of(main._fleet_operations).get_global_rect()
	assert_true(fleet.size.y < screen.y * 0.75, "a force of a few groups does not fill the window: %d of %d px" % [int(fleet.size.y), int(screen.y)])
	var list: ItemList = main._fleet_operations._list
	assert_true(list.size.y >= list.item_count * 20.0, "every group row has its height: %d rows in %d px" % [list.item_count, int(list.size.y)])
	main._toggle_fleet_operations()
	main._toggle_weapon_control()
	_settle(main)
	var weapons := _panel_of(main._weapon_control).get_global_rect()
	assert_true(weapons.size.y < screen.y * 0.85, "one ship's systems do not fill the window: %d of %d px" % [int(weapons.size.y), int(screen.y)])
	main._toggle_weapon_control()
	_close(main)


# --- The Classic key layout ------------------------------------------------------------------

func _key(main: Main, keycode: Key, shift := false, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.physical_keycode = keycode
	e.pressed = true
	e.shift_pressed = shift
	e.ctrl_pressed = ctrl
	main.get_viewport().push_input(e)
	var up := e.duplicate() as InputEventKey
	up.pressed = false
	main.get_viewport().push_input(up)


func _click(main: Main, at: Vector2, button: MouseButton, ctrl: bool) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.position = at
		e.global_position = at
		e.pressed = pressed
		e.ctrl_pressed = ctrl
		main.get_viewport().push_input(e)


func test_the_default_layout_is_untouched_until_classic_keys_are_chosen() -> void:
	var main := _open("northern_passage.json")
	assert_true(not main.classic_keys, "the Classic keys are off by default")
	var u := _own(main, "Truxtun")
	main.map.select_units([u])
	main.map.grab_focus()
	var sonar := u.active_sonar_on
	_key(main, KEY_P)
	assert_true(u.active_sonar_on != sonar, "P still works the active sonar")
	assert_true(SimClock.paused, "and does not touch the clock")
	assert_true(" | ".join(KeyCommands.all_rows()).contains("R / P / E: Radar / active sonar / emission control"), "the key list shows the default layout")
	var items := CdsMenus.options_items(main._cds_state())
	var offered := items.filter(func(i: Dictionary) -> bool: return str(i.get("text", i.get("label", ""))).begins_with("Classic keys"))
	assert_eq(offered.size(), 1, "the options menu offers the Classic keys")
	_close(main)


func test_classic_keys_translate_in_front_of_the_default_layout() -> void:
	var main := _open("northern_passage.json")
	_window(main, 100)
	main.set_classic_keys(true, false)
	var u := _own(main, "Truxtun")
	main.map.select_units([u])
	main.map.grab_focus()
	var sonar := u.active_sonar_on
	_key(main, KEY_P)
	assert_true(not SimClock.paused, "P resumes the watch")
	_key(main, KEY_P)
	assert_true(SimClock.paused, "and pauses it")
	assert_eq(u.active_sonar_on, sonar, "the sonar is left alone")
	SimClock.set_speed_index(0)
	_key(main, KEY_T)
	assert_eq(SimClock.speed_index, 1, "T steps to the next time scale")
	_key(main, KEY_TAB)
	assert_true(main.map.selected.size() == 1 and main.map.selected[0] != u, "Tab hooks the next own platform")
	main.map.select_units([u])
	main.map.grab_focus()
	_key(main, KEY_C, true)
	assert_eq(u.emcon, Unit.Emcon.SILENT, "Shift+C sets emission control")
	# A ship keeping station refuses a speed; the guide she keeps it on takes one.
	var guide := _own(main, "Northern Light")
	main.map.select_units([guide])
	main.map.grab_focus()
	_key(main, KEY_1, true)
	assert_near(guide.ordered_speed_kn, guide.effective_max_speed() / 3.0, 0.2, "Shift+1 is a third of her own top speed")
	_key(main, KEY_3, true)
	assert_near(guide.ordered_speed_kn, guide.effective_max_speed(), 0.2, "Shift+3 is all of it")
	main.map.select_units([u])
	main.map.grab_focus()
	var before := main.radio.journal.size()
	_key(main, KEY_8, true)
	_key(main, KEY_B)
	assert_true(main.map.selected.has(u), "B and Shift+8 with a ship hooked change nothing on the chart")
	# Ctrl+click zooms the chart and orders nothing.
	var ppn := main.map.ppn
	var waypoints := u.waypoints.size()
	var centre := main.map.get_global_rect().get_center()
	_click(main, centre, MOUSE_BUTTON_LEFT, true)
	assert_near(main.map.ppn, minf(ppn * 2.0, TacticalMap.MAX_PPN), 0.001, "Ctrl+click zooms the chart in")
	_click(main, centre, MOUSE_BUTTON_RIGHT, true)
	assert_near(main.map.ppn, ppn, 0.001, "Ctrl+right-click zooms it out")
	assert_eq(u.waypoints.size(), waypoints, "and neither orders a move")
	assert_true(main.map.selected.has(u), "nor drops the hook")
	# The key list is built from the layout in use.
	var rows := " | ".join(KeyCommands.all_rows())
	assert_true(rows.contains("P: Pause or resume") and rows.contains("Shift+1 / 2 / 3") and rows.contains("Tab: Hook the next own platform"), "the key list shows the Classic keys")
	assert_true(not rows.contains("R / P / E"), "and not the default keys they replace")
	main.set_classic_keys(false, false)
	assert_true(" | ".join(KeyCommands.all_rows()).contains("R / P / E"), "turned off, the default layout is back")
	assert_true(main.radio.journal.size() >= before, "the radio still answers")
	_close(main)


# --- Reports that reach the commander --------------------------------------------------------

func _said(main: Main, fragment: String, from := 0) -> bool:
	for line: String in main.radio.journal.slice(from):
		if line.contains(fragment):
			return true
	return false


func test_simulation_reports_reach_the_radio() -> void:
	var main := _open("northern_passage.json")
	var sim := main.simulation
	var u := _own(main, "Truxtun")
	var from := main.radio.journal.size()
	sim.unit_manager.blocked_by_coast.emit(u)
	assert_true(_said(main, "blocked by coast — stopped", from), "a ship stopped by the coast says so")
	sim.weapon_manager.self_defence_emcon.emit(u, true)
	assert_true(_said(main, "radar on to engage inbound missiles", from), "a silent ship lighting up to fight says so")
	sim.weapon_manager.self_defence_emcon.emit(u, false)
	assert_true(_said(main, "holds fire: radar silent", from), "and one holding fire silent")
	sim.weapon_manager.torpedo_decoyed.emit(null, u)
	assert_true(_said(main, "Torpedo decoyed, searching", from), "a torpedo pulled off by decoys is reported at once")
	main._on_casualty_event(u, "array_recovering")
	assert_true(_said(main, "Recovering the towed array", from))
	main._on_casualty_event(u, "dip_raising")
	assert_true(_said(main, "Raising the dipping sonar", from))
	u.comms_initiative_report = "Contact report: submarine to the north"
	main._on_casualty_event(u, "initiative_report")
	assert_true(_said(main, "Contact report: submarine to the north", from))
	# Another side's ship stopped by the coast is not the commander's business.
	var before := main.radio.journal.size()
	var enemy := _enemy_ship(main)
	sim.unit_manager.blocked_by_coast.emit(enemy)
	sim.weapon_manager.torpedo_decoyed.emit(null, enemy)
	assert_eq(main.radio.journal.size(), before, "nothing is said for the other side")
	_close(main)


func test_a_move_round_the_coast_says_it_routes_and_a_refused_move_says_why() -> void:
	var main := _open("northern_passage.json")
	var guide := _own(main, "Northern Light")
	main.map.select_units([guide])
	var ashore := Vector2.INF
	var behind := Vector2.INF
	for ring in range(1, 40):
		for step in 24:
			var p: Vector2 = guide.position + Vector2.from_angle(TAU * step / 24.0) * ring * 5.0
			if ashore == Vector2.INF and Terrain.is_land(p):
				ashore = p
			elif behind == Vector2.INF and not Terrain.is_land(p) and Terrain.first_land_contact(guide.position, p) >= 0.0 and Terrain.reachable_by_sea(guide.position, p):
				behind = p
	assert_true(ashore != Vector2.INF and behind != Vector2.INF, "the chart has land and water behind it near the force")
	if behind != Vector2.INF:
		var from := main.radio.journal.size()
		main._apply_order_to_selection(Order.move(behind))
		assert_true(guide.waypoints.size() > 1, "the guide is routed round the land")
		assert_true(_said(main, "Routing round the coast", from), "and the radio says she is routed round: %s" % str(main.radio.journal.slice(from)))
		assert_true(not _said(main, "following the coast", from), "not that she will follow the coast")
	if ashore != Vector2.INF:
		main._apply_order_to_selection(Order.move(ashore))
		assert_true(main.radio.last_advice.contains("destination is ashore"), "a move onto land says why it is refused: %s" % main.radio.last_advice)
	_close(main)


func test_gunfire_is_called_as_gunfire_once_without_the_missile_alarm() -> void:
	var main := _open("gulf_01_hormuz.json")
	var target := _own(main, "Paul Ignatius")
	var from := main.radio.journal.size()
	var shells := _raid(main, target, "a190_100mm_gun", 4)
	for w: Weapon in shells:
		main._announce_threat(w)
	var called := main.radio.journal.slice(from).filter(func(l: String) -> bool: return l.contains("UNDER GUNFIRE"))
	assert_eq(called.size(), 1, "a shoot is called once: %s" % str(main.radio.journal.slice(from)))
	assert_true(not _said(main, "INCOMING", from) and not _said(main, "MISSILE", from), "and never as a missile")
	main._process(0.1)
	var banner: String = main.data_display.threat_text
	assert_true(banner.begins_with("UNDER GUNFIRE") or banner == "", "the banner does not call shells missiles: %s" % banner)
	assert_eq(main._uncleared_inbound(CommanderPicture.inbound(main.simulation.unit_manager, main.simulation.threat_manager, main.simulation.player_faction)), 0, "no shell waits for an order to engage")
	_close(main)


func test_the_x_cue_agrees_with_the_simulation_and_a_standing_raid_clearance() -> void:
	var main := _open("gulf_01_hormuz.json", GameOptions.classic())
	var sim := main.simulation
	var target := _own(main, "Paul Ignatius")
	_raid(main, target, "irn_qader", 3)
	var threats := CommanderPicture.inbound(sim.unit_manager, sim.threat_manager, sim.player_faction)
	var awaiting := AirDefence.awaiting_clearance(sim.unit_manager, sim.threat_manager, sim.player_faction)
	assert_true(awaiting.size() > 0, "on manual defence the rounds wait for the order")
	assert_eq(main._uncleared_inbound(threats), awaiting.size(), "the cue counts what the simulation holds waiting")
	for u: Unit in sim.unit_manager.get_faction_units(sim.player_faction):
		if AirDefence.intercept_rejection(u) == "":
			u.raid_clearance_until_s = SimClock.sim_time + 600.0
			break
	assert_eq(main._uncleared_inbound(threats), 0, "a standing raid clearance leaves nothing waiting")
	_close(main)


# --- The harness ------------------------------------------------------------------------------

func test_the_harness_loads_every_smoke_suite_by_path_and_the_pack_leaves_them_out() -> void:
	var harness := FileAccess.get_file_as_string("res://scripts/core/dev_harness.gd")
	assert_true(not harness.contains("cold_war_probe"), "no flag loads a script that is gone")
	assert_true(not RegEx.create_from_string("\\b(ColdWarSmoke|AviationSmoke)\\b").search(harness), "the harness names no smoke suite by class")
	var config := ConfigFile.new()
	config.load("res://export_presets.cfg")
	var excludes := str(config.get_value("preset.0", "exclude_filter", ""))
	for suite in ["scripts/core/cold_war_smoke.gd", "scripts/core/aviation_smoke.gd"]:
		assert_true(excludes.contains(suite), "%s is not packed for players" % suite)


func test_the_intercept_item_says_what_the_fighters_do() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ui/cds_menus.gd")
	assert_true(not source.contains("A CAP over the contact"), "the intercept is not described as a CAP")
	assert_true(source.contains("go for the contact at dash speed, fire on it"), "it says the fighters dash, fire and come home")


func test_weapon_control_gives_a_torpedos_minimum_range_beyond_its_enable_run() -> void:
	var main := _open("northern_passage.json")
	# A torpedo whose enable run reaches past the minimum range written in its figures.
	var ship := _own(main, "Amundsen")
	for i in ship.weapons.size():
		if ship.weapons[i].is_torpedo():
			var long_run: WeaponSpec = ship.weapons[i].duplicate()
			long_run.run_to_enable_nm = long_run.min_range_nm + 1.0
			ship.weapons[i] = long_run
	main.map.select_units([ship])
	main._toggle_weapon_control()
	var found := 0
	for item: TreeItem in main._weapon_control._items:
		var spec: WeaponSpec = item.get_metadata(0)[1]
		found += int(Combat.minimum_range_nm(spec) > spec.min_range_nm + 0.05)
		var near := Combat.minimum_range_nm(spec)
		assert_true(item.get_text(5).begins_with("%.1f - " % near), "%s reads %s, from %.1f nm" % [spec.id, item.get_text(5), near])
	assert_true(found > 0, "the force carries a torpedo with an enable run beyond its listed minimum")
	main._toggle_weapon_control()
	_close(main)


# --- The time-rate rule -------------------------------------------------------------------------

func test_a_new_esm_line_alone_does_not_drop_the_clock_to_real_time() -> void:
	var main := _open("northern_passage.json")
	var t := _held_contact_any(main)
	assert_true(t != null, "the plot holds a contact")
	if t == null:
		_close(main)
		return
	SimClock.set_paused(false)
	SimClock.set_speed_index(5)
	t.source = "esm"
	t.identity = "UNKNOWN"
	main._contacts_called.erase(main._contact_key(t))
	var from := main.radio.journal.size()
	main._call_new_contact(t)
	assert_eq(SimClock.speed_index, 5, "a new ESM line on its own leaves 60x running")
	assert_true(_said(main, "New contact", from), "but it is still called")
	t.classification = Track.Classification.CLASS_KNOWN
	t.known_class = "Trawler"
	main._call_classification(t)
	assert_eq(SimClock.speed_index, 5, "and so does classifying it, while it is not held hostile")
	# The same contact held hostile, or a radar contact, gives up the compression.
	t.identity = "HOSTILE"
	t.known_class = "Frigate"
	main._call_classification(t)
	assert_eq(SimClock.speed_index, 0, "a contact held hostile drops to real time")
	SimClock.set_speed_index(5)
	t.source = "radar"
	t.identity = "UNKNOWN"
	main._contacts_called.erase(main._contact_key(t))
	main._call_new_contact(t)
	assert_eq(SimClock.speed_index, 0, "a new radar contact still drops to real time")
	SimClock.set_paused(true)
	_close(main)


func _held_contact_any(main: Main) -> Track:
	for step in 40:
		var tracks: Array = main.map._visible_tracks()
		if not tracks.is_empty():
			return tracks[0]
		SimClock.advance(5.0)
	return null


# --- Casualty reports ---------------------------------------------------------------------------

func test_a_ship_on_fire_reports_her_damage_control_state_every_few_minutes() -> void:
	var main := _open("northern_passage.json")
	var u := _own(main, "Amundsen")
	u.fire = 0.4
	u.flooding = 0.1
	u.health = u.spec.health * 0.5
	var from := main.radio.journal.size()
	var reports := func() -> int:
		return main.radio.journal.slice(from).filter(func(l: String) -> bool: return l.contains("Damage control:")).size()
	SimClock.advance(30.0)
	assert_eq(reports.call(), 0, "the first state report waits for the parties to get to work")
	for minute in 7:
		u.fire = 0.4  # held burning, whatever the parties manage
		SimClock.advance(60.0)
	var n: int = reports.call()
	assert_true(n >= 2 and n <= 3, "a report every three minutes or so: %d in seven" % n)
	var line := str(main.radio.journal.slice(from).filter(func(l: String) -> bool: return l.contains("Damage control:"))[0])
	assert_true(line.contains("fire") and line.contains("hull "), "it gives the fire and the hull: %s" % line)
	u.fire = 0.0
	u.flooding = 0.0
	SimClock.advance(400.0)
	assert_eq(reports.call(), n, "a ship with nothing burning makes no report")
	_close(main)
