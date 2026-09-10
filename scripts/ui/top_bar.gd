class_name TopBar
extends PanelContainer
## Mission status, simulation time, pause and time-acceleration controls, and the event ticker.

signal briefing_pressed()
signal restart_pressed()
signal menu_pressed()
signal logged(text: String, severity: String)

const FLASH_S := 12.0

var history: Array[String] = []
var _title: Label
var _mission: Label
var _objective: Label
var _event: Label
var _alert: Label
var _flash_left := 0.0
var _time: Label
var _pause_btn: Button
var _speed_btns: Array[Button] = []
var _event_color := Color.WHITE
var _alert_anim := 0.0


func _ready() -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	add_child(h)

	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 0)
	title_box.custom_minimum_size.x = 190
	h.add_child(title_box)
	_title = Label.new()
	_title.text = "AEGIS COMMAND"
	# Every label up here clips rather than growing, or a long mission name or event message
	# widens the whole window and pushes the side panels off screen.
	_title.clip_text = true
	_title.add_theme_font_size_override("font_size", 16)
	_title.add_theme_color_override("font_color", UITheme.COL_ACCENT)
	title_box.add_child(_title)
	_mission = Label.new()
	_mission.clip_text = true
	_mission.theme_type_variation = "DimLabel"
	_mission.add_theme_font_size_override("font_size", 10)
	title_box.add_child(_mission)

	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 0)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.custom_minimum_size.x = 0
	h.add_child(mid)
	_objective = Label.new()
	_objective.theme_type_variation = "DimLabel"
	_objective.clip_text = true
	_objective.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_objective.custom_minimum_size.x = 0
	mid.add_child(_objective)
	_event = Label.new()
	_event.modulate = Color(1.0, 0.8, 0.4)
	_event.clip_text = true
	_event.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_event.custom_minimum_size.x = 0
	_event.add_theme_font_size_override("font_size", 13)
	mid.add_child(_event)

	_alert = Label.new()
	_alert.clip_text = true
	_alert.custom_minimum_size.x = 210
	_alert.add_theme_font_size_override("font_size", 13)
	_alert.add_theme_color_override("font_color", UITheme.COL_RED)
	_alert.visible = false
	h.add_child(_alert)

	_time = Label.new()
	_time.clip_text = true
	_time.custom_minimum_size.x = 150
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time.add_theme_font_size_override("font_size", 14)
	h.add_child(_time)

	_pause_btn = Button.new()
	_pause_btn.focus_mode = Control.FOCUS_NONE
	_pause_btn.custom_minimum_size.x = 78
	_pause_btn.pressed.connect(SimClock.toggle_pause)
	h.add_child(_pause_btn)

	var group := ButtonGroup.new()
	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 2)
	h.add_child(speeds)
	for i in SimClock.SPEEDS.size():
		var b := Button.new()
		b.text = "%d×" % int(SimClock.SPEEDS[i])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.x = 38
		b.pressed.connect(SimClock.set_speed_index.bind(i))
		speeds.add_child(b)
		_speed_btns.append(b)

	var spacer := Control.new()
	spacer.custom_minimum_size.x = 6
	h.add_child(spacer)
	for entry in [["BRIEF  F1", briefing_pressed], ["RESTART", restart_pressed], ["MISSIONS", menu_pressed]]:
		var b := Button.new()
		b.text = entry[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: entry[1].emit())
		h.add_child(b)

	SimClock.speed_changed.connect(func(_i: int, _m: float) -> void: _refresh())
	SimClock.paused_changed.connect(func(_p: bool) -> void: _refresh())
	_refresh()


func _process(delta: float) -> void:
	_time.text = SimClock.datetime_string()
	_alert_anim += delta
	if _alert.visible:
		_alert.modulate.a = 0.55 + 0.45 * absf(sin(_alert_anim * 5.0))
	if _flash_left > 0.0:
		_flash_left -= delta
		_event.modulate = Color(_event_color, clampf(_flash_left / 3.0, 0.0, 1.0))


## Severity colours the ticker and the log: "info", "warn", "alert", "good".
func flash(msg: String, severity := "info") -> void:
	history.push_front(SimClock.datetime_string() + "  " + msg)
	if history.size() > 40:
		history.resize(40)
	_event.tooltip_text = "\n".join(history)
	_event.text = "▸ " + msg
	match severity:
		"alert":
			_event_color = UITheme.COL_RED
		"warn":
			_event_color = UITheme.COL_AMBER
		"good":
			_event_color = UITheme.COL_GREEN
		_:
			_event_color = UITheme.COL_TEXT
	_event.modulate = _event_color
	_flash_left = FLASH_S
	logged.emit(msg, severity)


func set_alert(text: String) -> void:
	_alert.visible = text != ""
	_alert.text = text


func set_scenario_name(scenario_name: String) -> void:
	_mission.text = scenario_name
	_mission.tooltip_text = scenario_name


func set_objective_text(text: String) -> void:
	_objective.text = text


func _refresh() -> void:
	_pause_btn.text = "PAUSED" if SimClock.paused else "RUNNING"
	_pause_btn.modulate = UITheme.COL_AMBER if SimClock.paused else Color.WHITE
	for i in _speed_btns.size():
		_speed_btns[i].button_pressed = i == SimClock.speed_index
