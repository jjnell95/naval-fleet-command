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
	for percent: int in SIZES:
		_window(main, percent)
		main._key_help.open()
		_settle(main)
		# The board is centred in the window, so it is on screen when it is no larger than the window.
		var screen := main.get_viewport_rect().size
		var panel: Vector2 = main._key_help._panel.get_combined_minimum_size()
		assert_true(panel.x <= screen.x - 24.0 and panel.y <= screen.y, "%d%%: the key list %s fits the window %s" % [percent, str(panel), str(screen)])
		main._key_help.close()
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
