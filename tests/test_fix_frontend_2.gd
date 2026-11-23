extends TestCase
## Saving as a player meets it: an autosave does not stop the game while it is written, it still
## brings back the moment it was taken, and a run can make one happen to measure it.

var _save_root := ""
var _log_path := ""
var _clock_speeds: Array[float] = []
var _use_worker := true


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


## The command screen on an operation with command taken and the clock paused at zero, keeping
## its saves and commander's log out of the player's own.
func _open_main(scenario := "res://data/scenarios/northern_passage.json") -> Main:
	_save_root = SaveGame.root_override
	_log_path = CommanderLog.path_override
	_clock_speeds = SimClock.speeds()
	_use_worker = SaveGame.use_worker
	SaveGame.root_override = "user://test-frontend-two-%d" % Time.get_ticks_usec()
	CommanderLog.path_override = SaveGame.root_override + "-log.json"
	var main: Main = preload("res://scenes/main/Main.tscn").instantiate()
	_root().add_child(main)
	main._apply_options(GameOptions.normal(), false, false)
	main.simulation.seed_override = 2
	main.start_scenario(scenario)
	main._on_briefing_start()
	SimClock.set_paused(true)
	return main


func _close_main(main: Main) -> void:
	SaveGame.finish_writing()
	SaveGame.force_next_autosave = false
	SaveGame.use_worker = _use_worker
	main.free()
	var dir := DirAccess.open(SaveGame.root_override)
	if dir != null:
		for file in dir.get_files():
			dir.remove(file)
		DirAccess.remove_absolute(SaveGame.root_override)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CommanderLog.path()))
	SaveGame.root_override = _save_root
	CommanderLog.path_override = _log_path
	SimClock.set_speeds(_clock_speeds)
	SimClock.set_speed_index(0)
	SimClock.set_paused(true)


func _autosaves() -> Array:
	return SaveGame.list_saves().filter(func(h: Dictionary) -> bool: return str(h.get("kind", "")) == "auto")


## Plays `seconds` of the engagement with the clock running, as the autosave expects.
static func _play(seconds: int) -> void:
	SimClock.set_paused(false)
	for i in seconds:
		SimClock.advance(1.0)


## The autosave the player's own session takes when its interval comes round.
static func _due_autosave(main: Main) -> void:
	main._autosave_enabled = true
	main._autosaved_at = SimClock.sim_time - SaveGame.AUTOSAVE_INTERVAL_S
	main._autosave_if_due()


func test_an_autosave_is_written_over_the_frames_after_it_is_taken_and_brings_that_moment_back() -> void:
	var main := _open_main()
	SaveGame.use_worker = false  # the browser build's way, frame by frame
	_play(30)
	var taken := SimClock.sim_time
	_due_autosave(main)
	assert_eq(_autosaves().size(), 0, "the frame that takes the autosave only captures it: nothing is encoded or written in it")
	var job := SaveGame.writing()
	assert_true(job != null, "the autosave is under way")
	var frames := 0
	while job != null and not job.step() and frames < 20:
		frames += 1
		SimClock.advance(1.0)  # the battle goes on while it is written
	assert_true(job != null and job.done, "it finishes")
	assert_true(frames >= 3, "the encoding, the compression and the file each take a frame of their own, %d frames" % frames)
	assert_eq(job.error, "")
	assert_eq(_autosaves().size(), 1, "and then it is on disk")
	assert_true(SimClock.sim_time > taken, "the engagement ran on meanwhile")
	SimClock.set_paused(true)
	assert_eq(main.load_engagement(str(_autosaves()[0]["path"])), "", "the autosave loads")
	assert_eq(SimClock.sim_time, taken, "at the moment it was taken, not the one it was finished at")
	_close_main(main)


func test_where_there_are_threads_the_file_is_written_on_a_worker() -> void:
	if not OS.has_feature("threads"):
		return
	var main := _open_main()
	SaveGame.use_worker = true
	_play(20)
	var taken := SimClock.sim_time
	_due_autosave(main)
	var job := SaveGame.writing()
	assert_true(job != null and _autosaves().is_empty(), "taking it writes nothing in that frame")
	if job != null:
		job.step()  # the next frame encodes it and hands the rest to a worker
		assert_true(job._task >= 0 or job.done, "the compression and the file are on a worker")
		assert_eq(job.finish(), "")
	assert_eq(_autosaves().size(), 1)
	SimClock.set_paused(true)
	assert_eq(main.load_engagement(str(_autosaves()[0]["path"])), "")
	assert_eq(SimClock.sim_time, taken)
	_close_main(main)


func test_a_run_can_force_an_autosave_to_exercise_it() -> void:
	var main := _open_main()
	main._scripted_session = true  # a dev-harness run, which never autosaves on its own
	_play(10)
	SimClock.set_paused(true)
	main._autosave_if_due()
	SaveGame.finish_writing()
	assert_eq(_autosaves().size(), 0, "a driven run leaves the saves alone")
	SaveGame.force_next_autosave = true
	main._autosave_if_due()
	assert_true(not SaveGame.force_next_autosave, "the request is used up")
	assert_eq(SaveGame.finish_writing(), "")
	assert_eq(_autosaves().size(), 1, "paused and driven, the forced autosave is taken")
	main._autosave_if_due()
	SaveGame.finish_writing()
	assert_eq(_autosaves().size(), 1, "once")
	_close_main(main)


func test_leaving_finishes_the_autosave_under_way_and_writes_its_own_before_it_returns() -> void:
	var main := _open_main()
	SaveGame.use_worker = false
	_play(15)
	_due_autosave(main)
	assert_true(SaveGame.writing() != null, "one autosave is still being written")
	_play(5)
	SimClock.set_paused(true)
	main._autosave_if_due(true)
	assert_true(SaveGame.writing() == null, "nothing is left half written when the engagement is replaced")
	var slots: Array = _autosaves().map(func(h: Dictionary) -> String: return str(h["slot"]))
	slots.sort()
	assert_eq(slots, [SaveGame.AUTOSAVE_PREFIX + "1", SaveGame.AUTOSAVE_PREFIX + "2"], "both are on disk, in the order taken")
	_close_main(main)


func test_staged_autosaves_keep_only_the_newest() -> void:
	var main := _open_main()
	SaveGame.use_worker = false
	for i in SaveGame.AUTOSAVE_KEEP + 2:
		_play(2)
		_due_autosave(main)
	SaveGame.finish_writing()
	var autos := _autosaves()
	assert_eq(autos.size(), SaveGame.AUTOSAVE_KEEP, "the oldest are dropped")
	assert_eq(str(autos[0]["slot"]), SaveGame.AUTOSAVE_PREFIX + str(SaveGame.AUTOSAVE_KEEP + 2), "newest first")
	_close_main(main)


# --- The grey-surface severity inks are the theme's -------------------------------------------

static func _luminance(c: Color) -> float:
	var lin := func(x: float) -> float: return x / 12.92 if x <= 0.04045 else pow((x + 0.055) / 1.055, 2.4)
	return 0.2126 * lin.call(c.r) + 0.7152 * lin.call(c.g) + 0.0722 * lin.call(c.b)


static func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func test_the_theme_names_severity_inks_that_read_on_every_grey_face() -> void:
	var inks := {"alert": [UITheme.FACE_INK_ALERT, UITheme.HEX_FACE_INK_ALERT], "warn": [UITheme.FACE_INK_WARN, UITheme.HEX_FACE_INK_WARN], "good": [UITheme.FACE_INK_GOOD, UITheme.HEX_FACE_INK_GOOD]}
	for severity: String in inks:
		var ink: Color = inks[severity][0]
		assert_eq(Color(str(inks[severity][1])), ink, "%s: the colour and its hex agree" % severity)
		for face: Color in [UITheme.JFC_FACE, UITheme.JFC_FACE_HOVER, UITheme.JFC_FACE_DOWN]:
			var ratio := _contrast(ink, face)
			assert_true(ratio >= 4.5, "%s on %s is %.2f:1" % [severity, face.to_html(false), ratio])
		assert_eq(Color(str(StatusBoards.SEVERITY_COLORS[severity])), ink, "the boards' %s message ink is the theme's" % severity)


# --- The desk's list takes the height of its rows; the orders get the rest --------------------

## Lays out `control` now, as the next frames would: containers sort top down, and a wrapped
## label's height follows the width it was given, so it is measured again and the sort repeated.
static func _lay_out(control: Control) -> void:
	for pass_index in 3:
		for label: Control in control.find_children("*", "Label", true, false):
			label.update_minimum_size()
		control.propagate_notification(Container.NOTIFICATION_SORT_CHILDREN)


func test_the_desk_list_stands_as_tall_as_its_rows_and_the_orders_box_gets_the_rest() -> void:
	var log_path := CommanderLog.path_override
	CommanderLog.path_override = "user://test-frontend-two-log-%d.json" % Time.get_ticks_usec()
	# 1600x900 at 100 percent, and the same window at 125 percent.
	for screen: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		var port := SubViewport.new()
		port.size = screen
		port.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_root().add_child(port)
		var themed := Control.new()
		themed.theme = UITheme.build()
		themed.size = Vector2(screen)
		port.add_child(themed)
		var menu := ScenarioMenu.new()
		themed.add_child(menu)
		menu._set_era("operations")
		_lay_out(menu)
		var list := menu._list
		assert_true(list.item_count >= 5, "the operations shelf is listed")
		list.force_update_list_size()
		var last := list.get_item_rect(list.item_count - 1)
		var frame := list.get_theme_stylebox("panel").get_minimum_size().y
		var inside := list.size.y - list.get_theme_stylebox("panel").get_margin(SIDE_BOTTOM)
		assert_true(inside >= last.end.y - 1.0, "%s: every row is shown (%d px for %d px of rows)" % [screen, int(inside), int(last.end.y)])
		var head := menu._top.size.y - list.size.y
		var needed := maxf(head + last.end.y + frame * 0.5, menu._map_min_side)
		assert_true(menu._top.size.y <= needed + last.size.y * 0.5, "%s: the list and map stand %d px tall where %d px hold every row" % [screen, int(menu._top.size.y), int(needed)])
		assert_true(menu._preview.size.y >= menu._map_min_side, "the map keeps a readable size")
		# At 100 percent a short shelf hands about 65 px to the orders; at 125 percent the list
		# already fills the map's height, so there is nothing to hand over and nothing is lost.
		var least := 200.0 if screen.x == 1600 else 110.0
		assert_true(menu._detail.size.y >= least, "%s: the orders box has the height the list does not need, %d px" % [screen, int(menu._detail.size.y)])
		port.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CommanderLog.path()))
	CommanderLog.path_override = log_path


# --- Every way of replacing a running engagement asks first and autosaves it ------------------

static func _answer(host: Node, yes: bool) -> void:
	var dialog := ConfirmDiscard.asking(host)
	if dialog == null:
		return
	(dialog.get_ok_button() if yes else dialog.get_cancel_button()).pressed.emit()


func test_save_and_play_from_the_editor_mid_mission_asks_and_autosaves_first() -> void:
	var main := _open_main()
	main._autosave_enabled = true
	_play(25)
	SimClock.set_paused(true)
	var running := SimClock.sim_time
	main._show_editor()
	main._editor.play_requested.emit("res://data/scenarios/northern_passage.json")
	assert_eq(SimClock.sim_time, running, "SAVE AND PLAY does not drop the engagement on one click")
	var dialog := ConfirmDiscard.asking(main)
	assert_true(dialog != null and dialog.question().contains("autosaved"), "it asks, saying the engagement is kept")
	_answer(main, false)
	assert_eq(SimClock.sim_time, running, "keeping it keeps it")
	assert_true(main._command_taken)
	main._editor.play_requested.emit("res://data/scenarios/northern_passage.json")
	_answer(main, true)
	assert_eq(SimClock.sim_time, 0.0, "confirmed, the mission opens")
	assert_true(main._briefing.visible, "at its briefing")
	assert_eq(_autosaves().size(), 1, "and the abandoned engagement was autosaved")
	_close_main(main)


func test_ctrl_f10_and_the_debrief_restart_ask_while_the_engagement_runs() -> void:
	var main := _open_main()
	main._autosave_enabled = true
	_play(20)
	SimClock.set_paused(true)
	var running := SimClock.sim_time
	main._request_restart()
	assert_eq(SimClock.sim_time, running, "Ctrl+F10 does not restart on its own")
	assert_true(ConfirmDiscard.asking(main) != null, "it puts the question")
	_answer(main, false)
	main._request_restart()
	assert_eq(SimClock.sim_time, running, "nor on a second press")
	_answer(main, true)
	assert_eq(SimClock.sim_time, 0.0, "confirmed, it restarts")
	assert_eq(_autosaves().size(), 1, "with the old run autosaved")
	# Once the engagement has ended there is nothing to keep: the debrief's RESTART is the choice.
	main._on_briefing_start()
	_play(5)
	SimClock.set_paused(true)
	main.simulation.mission_manager._finish(MissionManager.Result.DEFEAT, "The convoy was lost")
	main._report.restart_pressed.emit()
	assert_true(ConfirmDiscard.asking(main) == null, "an ended engagement restarts without a question")
	assert_eq(SimClock.sim_time, 0.0)
	for action: Dictionary in main._palette_actions():
		if str(action["id"]) == "restart":
			assert_true(not str(action["description"]).contains("twice"), "the actions list no longer asks for a double press")
			assert_true(str(action["description"]).contains("asks first"))
	_close_main(main)


func test_quickload_autosaves_the_engagement_it_replaces() -> void:
	var main := _open_main()
	main._autosave_enabled = true
	_play(10)
	SimClock.set_paused(true)
	var saved_at := SimClock.sim_time
	main.quicksave()
	_play(30)
	SimClock.set_paused(true)
	var left_at := SimClock.sim_time
	main.quickload()
	assert_eq(SimClock.sim_time, saved_at, "the quicksave is back")
	var autos := _autosaves()
	assert_eq(autos.size(), 1, "and the engagement it replaced was autosaved")
	if autos.size() == 1:
		assert_eq(float(autos[0]["sim_time"]), left_at, "at the moment it was left")
	_close_main(main)
