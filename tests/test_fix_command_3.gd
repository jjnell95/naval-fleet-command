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
