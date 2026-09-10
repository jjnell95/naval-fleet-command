class_name BriefingPanel
extends PanelContainer
## Mission briefing, and the same screen doubles as the live mission-status board. Objectives
## come from MissionManager, so their progress is readable mid-mission rather than only at the end.

signal start_pressed()
signal restart_pressed()
signal menu_pressed()

var mission_manager: MissionManager
var unit_manager: UnitManager

var _title: Label
var _body: RichTextLabel
var _start: Button
var _restart: Button
var _menu: Button
var _accum := 0.0
var _scenario_name := ""
var _forces := ""
var _situation := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 110)
	margin.add_theme_constant_override("margin_right", 110)
	margin.add_theme_constant_override("margin_top", 55)
	margin.add_theme_constant_override("margin_bottom", 55)
	add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	v.add_child(_title)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = false
	_body.scroll_active = true
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_body)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	v.add_child(buttons)
	_start = Button.new()
	_start.text = "TAKE COMMAND"
	_start.focus_mode = Control.FOCUS_NONE
	_start.pressed.connect(func() -> void:
		SimClock.set_paused(false)
		start_pressed.emit())
	buttons.add_child(_start)
	_restart = Button.new()
	_restart.text = "RESTART"
	_restart.focus_mode = Control.FOCUS_NONE
	_restart.pressed.connect(func() -> void: restart_pressed.emit())
	buttons.add_child(_restart)
	_menu = Button.new()
	_menu.text = "SCENARIOS"
	_menu.focus_mode = Control.FOCUS_NONE
	_menu.pressed.connect(func() -> void: menu_pressed.emit())
	buttons.add_child(_menu)


func configure(scenario_name: String, forces: String, situation: String) -> void:
	_scenario_name = scenario_name
	_forces = forces
	_situation = situation
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
		out.append("[color=#8fb6c9]%s[/color]\n" % _forces)
	out.append("[b]SITUATION[/b]")
	out.append(_situation + "\n")
	if mission_manager.briefing != "":
		out.append("[b]MISSION[/b]")
		out.append(mission_manager.briefing + "\n")
	out.append("[b]VICTORY[/b]")
	for o in mission_manager.victory_objectives:
		out.append(_line(o))
	if not mission_manager.loss_objectives.is_empty():
		out.append("\n[b]MISSION FAILS IF[/b]")
		for o in mission_manager.loss_objectives:
			out.append(_line(o))
	out.append("\n[color=#6d8494]Left click selects. Right click on water orders a move, on a contact selects it. Wheel zooms, middle or right drag pans. Space pauses, 1 to 6 sets time acceleration, R toggles radar, F1 shows this board, F3 shows debug truth.[/color]")
	_body.text = "\n".join(out)


func _line(o: MissionObjective) -> String:
	var mark := "[color=#7fd08a]DONE[/color]" if o.complete else "[color=#c8a24a]OPEN[/color]"
	var detail := o.progress(unit_manager, SimClock.sim_time) if unit_manager != null else ""
	return "  %s  %s   [color=#6d8494]%s[/color]" % [mark, o.text, detail]


## Before the mission starts the board is a briefing; afterwards it is a status screen.
func set_mode(pre_mission: bool) -> void:
	_start.text = "TAKE COMMAND" if pre_mission else "RESUME"
