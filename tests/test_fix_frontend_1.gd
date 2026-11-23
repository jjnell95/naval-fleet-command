extends TestCase
## The front end as a player meets it: the desk's buttons say what they do and why one is out,
## text fits the boxes it is shown in, and work is never thrown away on one click.

var _log_path := ""


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


## A desk on its own, reading a scratch commander's log so a test never sees the player's record.
func _desk() -> ScenarioMenu:
	_log_path = CommanderLog.path_override
	CommanderLog.path_override = "user://test-frontend-one-log-%d.json" % Time.get_ticks_usec()
	var menu := ScenarioMenu.new()
	_root().add_child(menu)
	return menu


func _drop_desk(menu: ScenarioMenu) -> void:
	menu.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CommanderLog.path()))
	CommanderLog.path_override = _log_path


## The mean colour a style box paints its face in, top and bottom.
static func _face(style: StyleBox) -> Color:
	var s := style as JfcStyle
	if s == null:
		return Color.TRANSPARENT
	var top := s.face_top if s.face_top.a > 0.0 else s.face
	return s.face.lerp(top, 0.5)


# --- The desk's ACCEPT and CANCEL ----------------------------------------------------------

func test_desk_accept_and_cancel_are_worded_buttons_and_a_locked_step_says_which_win_opens_it() -> void:
	var menu := _desk()
	assert_eq(menu._play.text, "ACCEPT", "ACCEPT says what it is on its own face")
	assert_eq(menu._close.text, "CANCEL")
	assert_eq(menu._play.theme_type_variation, "MenuBigButton", "the same big bevel as the rest of the desk")
	assert_eq(menu._close.theme_type_variation, "MenuBigButton")
	assert_true(not menu._play.disabled, "an authored operation can be accepted")
	assert_eq(menu._play_reason.text, "", "and nothing is said against it")
	menu._set_era("campaigns")
	menu._list.select(1)
	menu._on_selected(1)
	assert_true(menu._play.disabled, "the second step of a new campaign is locked")
	var reason := menu._play_reason.text
	assert_true(reason.begins_with("LOCKED"), "the reason is shown beside ACCEPT: " + reason)
	assert_true(reason.contains("NORTHERN CONVOY"), "naming the operation to win first: " + reason)
	assert_true(reason.contains("60%"), "and the result it needs: " + reason)
	assert_true(menu._play_reason.visible and menu._play_reason.clip_text, "visible, and clipped if a long name meets a narrow screen")
	menu._list.select(0)
	menu._on_selected(0)
	assert_true(not menu._play.disabled and menu._play_reason.text == "", "the open step clears it")
	_drop_desk(menu)


func test_a_disabled_desk_button_looks_out_of_use() -> void:
	var t := UITheme.build()
	var on := _face(t.get_stylebox("normal", "MenuBigButton"))
	var off := _face(t.get_stylebox("disabled", "MenuBigButton"))
	assert_true(absf(on.get_luminance() - off.get_luminance()) > 0.12, "the face changes visibly: %s against %s" % [on, off])
	var ink := t.get_color("font_color", "MenuBigButton")
	var faded := t.get_color("font_disabled_color", "MenuBigButton")
	var contrast_on := absf(ink.get_luminance() - on.get_luminance())
	var contrast_off := absf(faded.get_luminance() - off.get_luminance())
	assert_true(contrast_off < contrast_on * 0.6, "the lettering fades into it: %.2f against %.2f" % [contrast_off, contrast_on])


# --- The GAMEPLAY summary ------------------------------------------------------------------

## Every summary the desk can show: both presets and every mix of the four gameplay options.
static func _every_option_mix() -> Array[GameOptions]:
	var out: Array[GameOptions] = [GameOptions.normal(), GameOptions.classic()]
	var keys := ["ceiling", "manual_defence", "engage_on_id", "submarine_comms"]
	for mask in 16:
		var o := GameOptions.normal()
		for bit in keys.size():
			if mask & (1 << bit):
				o = o.toggled(keys[bit])
		out.append(o)
	return out


func test_the_gameplay_summary_is_read_whole_for_every_preset_at_either_desk_width() -> void:
	var menu := _desk()
	var label := menu._options_summary
	assert_true(not label.clip_text, "never clipped at its head")
	for width: float in [ScenarioMenu.SUMMARY_WIDTH, ScenarioMenu.SUMMARY_WIDTH_COMPACT]:
		label.size = Vector2(width, label.size.y)
		for o: GameOptions in _every_option_mix():
			menu.set_options(o)
			assert_true(label.text.begins_with(o.summary().get_slice(" · ", 0)), "the ceiling leads: " + label.text)
			assert_true(label.get_line_count() <= label.max_lines_visible, "'%s' fits in %d lines at %d px (needs %d)" % [o.summary(), label.max_lines_visible, int(width), label.get_line_count()])
	menu.set_options(GameOptions.classic())
	label.size = Vector2(ScenarioMenu.SUMMARY_WIDTH, label.size.y)
	var font := label.get_theme_font("font")
	var one_line := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
	assert_true(one_line > ScenarioMenu.SUMMARY_WIDTH, "the classic summary is wider than one line (%d px), so the wrap is what keeps it whole" % int(one_line))
	assert_eq(label.get_line_count(), 2, "and it does wrap, to two lines")
	_drop_desk(menu)


# --- The Reference at every interface size -------------------------------------------------

## The library in a viewport the size a 1600 x 900 window gives at `percent` interface size.
func _library_at(percent: int) -> Array:
	var port := SubViewport.new()
	port.size = Vector2i(roundi(1600.0 * 100.0 / percent), roundi(900.0 * 100.0 / percent))
	port.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_root().add_child(port)
	var lib := PlatformLibrary.new()
	port.add_child(lib)
	return [port, lib]


func test_the_reference_sheet_fits_the_screen_at_every_interface_size() -> void:
	for percent: int in InterfaceScale.PERCENTAGES:
		var made := _library_at(percent)
		var port: SubViewport = made[0]
		var lib: PlatformLibrary = made[1]
		var screen := Vector2(port.size)
		for weapons in [false, true]:
			lib._set_mode(weapons)
			var need := lib.get_combined_minimum_size()
			assert_true(need.y <= screen.y, "%d%%: the sheet needs %d px of a %d px screen (%s)" % [percent, int(need.y), int(screen.y), "ordnance" if weapons else "platforms"])
			assert_true(need.x <= screen.x, "%d%%: and %d px of %d across" % [percent, int(need.x), int(screen.x)])
		if PlatformLibrary.is_compact(screen):
			assert_true(not lib._hint.visible, "%d%%: the orbit hint is not shown cut short" % percent)
			assert_true(lib._stage.tooltip_text != "", "it stays on the stage's tooltip")
		else:
			assert_true(lib._hint.visible, "on a full screen the orbit hint is shown")
		port.free()


# --- The debrief ---------------------------------------------------------------------------

var _save_root := ""
var _clock_speeds: Array[float] = []


## The command screen on an operation with command taken and the clock paused at zero, keeping
## its saves and commander's log out of the player's own.
func _open_main(scenario := "res://data/scenarios/northern_passage.json") -> Main:
	_save_root = SaveGame.root_override
	_log_path = CommanderLog.path_override
	_clock_speeds = SimClock.speeds()
	SaveGame.root_override = "user://test-frontend-one-%d" % Time.get_ticks_usec()
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


## Lays out `control` now, as the next frames would: containers sort top down, and a wrapped
## label's height follows the width it was given, so it is measured again and the sort repeated.
static func _lay_out(control: Control) -> void:
	for pass_index in 3:
		for label: Control in control.find_children("*", "Label", true, false):
			label.update_minimum_size()
		control.propagate_notification(Container.NOTIFICATION_SORT_CHILDREN)


## The arguments of a debrief at the end of a played Northern Passage, as the audit's walk left it.
func _played_debrief() -> Array:
	var main := _open_main()
	SimClock.set_paused(false)
	for i in 40:
		SimClock.advance(1.0)
	SimClock.set_paused(true)
	main._stats = {"hostile_rounds": 10, "intercepted": 4, "decoyed": 1, "hits_taken": 1, "launched": 9, "decoys_used": 3, "own_rounds": 14, "hits_scored": 2, "contacts": 5, "classified": 2, "sorties": 1}
	main._kills = PackedStringArray(["Rassvet"])
	main._on_mission_ended("VICTORY", "The convoy reached the handover box with its cargo intact.")
	var args: Array = main._last_report.duplicate()
	_close_main(main)
	return args


func test_the_debrief_is_sized_from_the_screen_its_results_read_whole_and_its_notes_wrap() -> void:
	var args := _played_debrief()
	for screen: Vector2i in [Vector2i(1600, 900), Vector2i(1455, 818), Vector2i(1280, 720)]:
		var port := SubViewport.new()
		port.size = screen
		port.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_root().add_child(port)
		var report := AfterAction.new()
		port.add_child(report)
		report.callv("show_report", args)
		_lay_out(report)
		var card := report._card.get_global_rect()
		assert_true(card.size.x >= screen.x * 0.6 and card.size.y >= screen.y * 0.75, "%s: the card takes most of the screen, %s" % [screen, card.size])
		assert_true(card.size.x <= screen.x and card.size.y <= screen.y, "%s: and fits on it, %s" % [screen, card.size])
		var body := report._body
		assert_true(body.get_content_height() <= body.size.y + 1.0, "%s: the results need %d px and have %d" % [screen, body.get_content_height(), int(body.size.y)])
		for key: String in report._tiles:
			var note: Label = report._tiles[key]["note"]
			assert_true(not note.clip_text and note.autowrap_mode != TextServer.AUTOWRAP_OFF, "the %s note wraps rather than clips" % key)
			var font := note.get_theme_font("font")
			var words_fit: bool = Array(note.text.split(" ")).all(func(w: String) -> bool: return font.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, note.get_theme_font_size("font_size")).x <= note.size.x)
			assert_true(words_fit, "%s: every word of '%s' fits the tile's %d px" % [screen, note.text, int(note.size.x)])
			assert_true(note.get_visible_line_count() >= note.get_line_count(), "and every line of it is shown")
		assert_true(report._timeline.text.contains("OBSERVED EVENT TIMELINE"), "the observed events have their own column")
		port.free()


func test_no_button_of_the_debrief_has_the_focus_so_space_cannot_close_it() -> void:
	var main := _open_main()
	SimClock.advance(5.0)
	main.simulation.mission_manager._finish(MissionManager.Result.DEFEAT, "The convoy was lost")
	assert_true(main._report.visible)
	# The report gives the focus a frame later; give it now where it will go.
	var first := main._report.default_focus()
	assert_true(first != null and not (first is BaseButton), "the results take the focus, not a button: %s" % first)
	first.grab_focus()
	var e := InputEventKey.new()
	e.keycode = KEY_SPACE
	e.physical_keycode = KEY_SPACE
	e.pressed = true
	main.get_viewport().push_input(e)
	var up := e.duplicate() as InputEventKey
	up.pressed = false
	main.get_viewport().push_input(up)
	assert_true(main._report.visible, "Space leaves the debrief up")
	_close_main(main)


# --- One click never throws work away ------------------------------------------------------

static func _answer(host: Node, yes: bool) -> void:
	var dialog := ConfirmDiscard.asking(host)
	if dialog == null:
		return
	(dialog.get_ok_button() if yes else dialog.get_cancel_button()).pressed.emit()


func _autosaves() -> Array:
	return SaveGame.list_saves().filter(func(h: Dictionary) -> bool: return str(h.get("kind", "")) == "auto")


func test_choosing_an_operation_from_the_desk_mid_mission_asks_and_autosaves_first() -> void:
	var main := _open_main()
	main._autosave_enabled = true
	SimClock.set_paused(false)
	for i in 38:
		SimClock.advance(1.0)
	SimClock.set_paused(true)
	var running := SimClock.sim_time
	main._show_menu()
	main._menu._intro.pressed.emit()
	assert_eq(SimClock.sim_time, running, "one click on START does not end the engagement")
	var dialog := ConfirmDiscard.asking(main)
	assert_true(dialog != null, "it asks first")
	if dialog != null:
		assert_true(dialog.dialog_text.contains("autosaved"), "saying the engagement is kept: " + dialog.dialog_text)
		assert_true(dialog.get_cancel_button().text != "" and dialog.get_ok_button().text != "", "both answers are worded")
	_answer(main, false)
	assert_eq(SimClock.sim_time, running, "keeping it keeps it")
	assert_true(main._command_taken)
	main._menu._intro.pressed.emit()
	_answer(main, true)
	assert_eq(SimClock.sim_time, 0.0, "abandoning it opens the new operation")
	assert_true(main._briefing.visible, "at its briefing")
	assert_eq(_autosaves().size(), 1, "and the abandoned engagement was autosaved on the way out")
	_close_main(main)


func test_restart_from_the_orders_board_mid_mission_asks_first() -> void:
	var main := _open_main()
	main._autosave_enabled = true
	SimClock.set_paused(false)
	for i in 20:
		SimClock.advance(1.0)
	SimClock.set_paused(true)
	var running := SimClock.sim_time
	main._briefing.restart_pressed.emit()
	assert_eq(SimClock.sim_time, running, "one click on RESTART does not restart")
	assert_true(ConfirmDiscard.asking(main) != null, "it asks first")
	_answer(main, false)
	assert_eq(SimClock.sim_time, running, "keeping it keeps it")
	main._briefing.restart_pressed.emit()
	_answer(main, true)
	assert_eq(SimClock.sim_time, 0.0, "confirmed, it restarts")
	assert_eq(_autosaves().size(), 1, "with the old run autosaved")
	_close_main(main)


func test_deleting_a_saved_engagement_asks_first() -> void:
	var main := _open_main()
	SimClock.advance(5.0)
	assert_eq(main.save_engagement("save-1", "manual", "Before the raid"), "")
	var path := SaveGame.slot_path("save-1")
	assert_true(FileAccess.file_exists(path))
	main._toggle_saved_engagements()
	main._saves._delete.pressed.emit()
	assert_true(FileAccess.file_exists(path), "one click on DELETE deletes nothing")
	var dialog := ConfirmDiscard.asking(main._saves)
	assert_true(dialog != null and dialog.dialog_text.contains("Before the raid"), "it names the save it would delete")
	_answer(main._saves, false)
	assert_true(FileAccess.file_exists(path), "keeping it keeps it")
	main._saves._delete.pressed.emit()
	_answer(main._saves, true)
	assert_true(not FileAccess.file_exists(path), "confirmed, it is deleted")
	_close_main(main)


func test_the_editors_new_asks_and_can_be_undone() -> void:
	var editor := ScenarioEditor.new()
	_root().add_child(editor)
	editor.load_dict(ScenarioLoader.load_file("res://data/scenarios/northern_passage.json"))
	var units: int = editor.scenario["units"].size()
	assert_true(units > 0)
	editor._ask_new()
	assert_eq(editor.scenario["units"].size(), units, "one click on NEW clears nothing")
	assert_true(ConfirmDiscard.asking(editor) != null, "it asks first")
	_answer(editor, true)
	assert_eq(editor.scenario["units"].size(), 0, "confirmed, the mission is empty")
	editor.undo()
	assert_eq(editor.scenario["units"].size(), units, "and UNDO brings the mission back")
	assert_eq(str(editor.scenario.get("name", "")), str(ScenarioLoader.load_file("res://data/scenarios/northern_passage.json").get("name", "")))
	editor.redo()
	assert_eq(editor.scenario["units"].size(), 0, "REDO clears it again")
	editor.undo()
	editor._ask_new()
	_answer(editor, false)
	assert_eq(editor.scenario["units"].size(), units, "keeping it keeps it")
	editor.free()
