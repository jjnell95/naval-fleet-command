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
