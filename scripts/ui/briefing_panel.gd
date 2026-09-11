class_name BriefingPanel
extends PanelContainer
## Mission briefing, and the same screen doubles as the live mission-status board. Objectives
## come from MissionManager, so their progress is readable mid-mission rather than only at the end.

signal start_pressed()
signal restart_pressed()
signal menu_pressed()

var mission_manager: MissionManager
var unit_manager: UnitManager

var _eyebrow: Label
var _title: Label
var _body: RichTextLabel
var _start: Button
var _restart: Button
var _menu: Button
var _accum := 0.0
var _scenario_name := ""
var _forces := ""
var _situation := ""
var _environment: Dictionary = {}


func _ready() -> void:
	theme_type_variation = "OverlayPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 110)
	margin.add_theme_constant_override("margin_right", 110)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_bottom", 44)
	add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	_eyebrow = Label.new()
	_eyebrow.text = "MISSION BRIEFING"
	_eyebrow.theme_type_variation = "HeaderLabel"
	v.add_child(_eyebrow)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 32)
	_title.add_theme_color_override("font_color", Color.WHITE)
	v.add_child(_title)

	var card := PanelContainer.new()
	card.theme_type_variation = "CardPanel"
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(card)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = false
	_body.scroll_active = true
	_body.focus_mode = Control.FOCUS_ALL
	_body.accessibility_name = "Mission briefing and objectives"
	_body.accessibility_description = "Scrollable mission text. Use arrow keys, Page Up, or Page Down while focused."
	_body.add_theme_font_size_override("normal_font_size", 15)
	_body.add_theme_font_size_override("bold_font_size", 15)
	card.add_child(_body)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	v.add_child(buttons)
	_start = Button.new()
	_start.text = "TAKE COMMAND"
	_start.theme_type_variation = "PrimaryButton"
	_start.focus_mode = Control.FOCUS_ALL
	_start.custom_minimum_size.y = 44
	_start.pressed.connect(func() -> void:
		SoundFx.play("click")
		start_pressed.emit())
	buttons.add_child(_start)
	_restart = Button.new()
	_restart.text = "RESTART"
	_restart.focus_mode = Control.FOCUS_ALL
	_restart.custom_minimum_size.y = 44
	_restart.pressed.connect(func() -> void: restart_pressed.emit())
	buttons.add_child(_restart)
	_menu = Button.new()
	_menu.text = "MISSIONS"
	_menu.focus_mode = Control.FOCUS_ALL
	_menu.custom_minimum_size.y = 44
	_menu.pressed.connect(func() -> void: menu_pressed.emit())
	buttons.add_child(_menu)
	_set_focus_cycle()


func _set_focus_cycle() -> void:
	var controls: Array[Control] = [_body, _start, _restart, _menu]
	for i in controls.size():
		controls[i].focus_next = controls[i].get_path_to(controls[(i + 1) % controls.size()])
		controls[i].focus_previous = controls[i].get_path_to(controls[posmod(i - 1, controls.size())])


func configure(scenario_name: String, forces: String, situation: String, environment: Dictionary = {}) -> void:
	_scenario_name = scenario_name
	_forces = forces
	_situation = situation
	_environment = environment
	refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum >= 0.5:
		_accum = 0.0
		refresh()


func refresh() -> void:
	if mission_manager == null:
		return
	_title.text = _scenario_name
	var out := PackedStringArray()
	if _forces != "":
		out.append("[color=%s]%s[/color]\n" % [UITheme.HEX_DIM, _forces])
	out.append("[color=%s][b]SITUATION[/b][/color]" % UITheme.HEX_ACCENT)
	out.append(_situation + "\n")
	if mission_manager.briefing != "":
		out.append("[color=%s][b]MISSION[/b][/color]" % UITheme.HEX_ACCENT)
		out.append(mission_manager.briefing + "\n")
	var sea := int(_environment.get("sea_state", 0))
	out.append("[color=%s][b]ENVIRONMENT[/b][/color]" % UITheme.HEX_ACCENT)
	var env_line := "Sea state %d (%s)" % [sea, Detection.SEA_STATE_NAMES[clampi(sea, 0, 6)]]
	if _environment.has("wind_kn"):
		env_line += " · wind %d kn" % int(_environment["wind_kn"])
	if _environment.has("visibility_nm"):
		env_line += " · visibility %d nm" % int(_environment["visibility_nm"])
	if sea >= 3:
		env_line += "\n[color=%s]Passive sonar reach is reduced and sea-skimming missiles are harder to pick out of clutter.[/color]" % UITheme.HEX_AMBER
	out.append(env_line + "\n")
	out.append("[color=%s][b]VICTORY — %s[/b][/color]" % [UITheme.HEX_ACCENT, "COMPLETE EITHER CONDITION" if mission_manager.victory_mode == "any" else "COMPLETE ALL CONDITIONS"])
	for o in mission_manager.victory_objectives:
		out.append(_line(o))
	if not mission_manager.loss_objectives.is_empty():
		out.append("\n[color=%s][b]MISSION FAILS IF[/b][/color]" % UITheme.HEX_ACCENT)
		for o in mission_manager.loss_objectives:
			out.append(_line(o))
	out.append("\n[color=%s][b]COMMAND[/b]  Left click selects; Shift adds to a group. G arms Plot Move, then left-click water; hold Shift to chain waypoints, Escape or right-click to cancel. N / Shift-N cycles priority contacts. R radar, P active sonar, E emission control.\n[b]NAVIGATE[/b]  Wheel or pinch zooms. Middle/right/Option-drag pans. Click or drag the Tactical Overview to recover the picture. C focuses the shooter-target problem, F follows one platform or the hooked contact, Home fits the force.\n[b]DISPLAY + TIME[/b]  Space pauses, 1–6 sets acceleration, F2 symbol key, F4 sensors, F5 trails, F6 terrain, V vectors, M sound. Open the searchable Actions palette with Command-K or Control-K. Land blocks ships and masks radar, ESM, and sonar.[/color]" % UITheme.HEX_MUTED)
	_body.text = "\n".join(out)


func _line(o: MissionObjective) -> String:
	var mark := "[color=%s]DONE[/color]" % UITheme.HEX_GREEN if o.complete else "[color=%s]OPEN[/color]" % UITheme.HEX_AMBER
	var detail := o.progress(unit_manager, SimClock.sim_time) if unit_manager != null else ""
	return "  %s  %s   [color=%s]%s[/color]" % [mark, o.text, UITheme.HEX_DIM, detail]


## Before the mission starts the board is a briefing; afterwards it is a status screen.
func set_mode(pre_mission: bool) -> void:
	_start.text = "TAKE COMMAND" if pre_mission else "RESUME"
	_eyebrow.text = "MISSION BRIEFING" if pre_mission else "MISSION STATUS"


func focus_default() -> void:
	if visible and _start != null:
		_start.grab_focus()
