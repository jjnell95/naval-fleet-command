class_name TopBar
extends PanelContainer
## Mission status, simulation time, pause and time-acceleration controls, and the event ticker.
##
## Left to right: wordmark and operation, the live objective over the latest event, any inbound
## alert, the clock, play/pause and time compression, then the utilities. Keyboard shortcuts live
## in tooltips rather than on the buttons.

signal library_pressed()
signal air_operations_pressed()
signal briefing_pressed()
signal restart_pressed()
signal menu_pressed()
signal commands_pressed()
signal alert_pressed()
signal logged(text: String, severity: String)

const FLASH_S := 12.0

var history: Array[String] = []
var _title: Label
var _mission: Label
var _objective: Label
var _event: Label
var _alert: Button
var _flash_left := 0.0
var _time: Label
var _date: Label
var _state: Label
var _pause_btn: Button
var _speed_btns: Array[Button] = []
var _event_color := Color.WHITE
var _alert_anim := 0.0


func _ready() -> void:
	var bar := StyleBoxFlat.new()
	bar.bg_color = UITheme.COL_PANEL_DEEP
	bar.content_margin_left = 16
	bar.content_margin_right = 12
	bar.content_margin_top = 8
	bar.content_margin_bottom = 8
	add_theme_stylebox_override("panel", bar)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	add_child(h)

	# Wordmark and operation.
	var brand := HBoxContainer.new()
	brand.add_theme_constant_override("separation", 10)
	brand.custom_minimum_size.x = 214
	h.add_child(brand)
	var mark := TextureRect.new()
	mark.texture = UIIcons.get_icon("mark", 26, UITheme.COL_BRASS)
	mark.custom_minimum_size = Vector2(26, 26)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand.add_child(mark)
	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", -2)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	brand.add_child(title_box)
	_title = Label.new()
	_title.text = "FLEET COMMAND"
	_title.add_theme_font_override("font", UITheme.heading_font())
	# Every label up here clips rather than growing, or a long mission name or event message
	# widens the whole window and pushes the side panels off screen.
	_title.clip_text = true
	_title.add_theme_font_size_override("font_size", 21)
	_title.add_theme_color_override("font_color", UITheme.COL_TEXT)
	title_box.add_child(_title)
	_mission = Label.new()
	_mission.clip_text = true
	_mission.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_mission.theme_type_variation = "HeaderLabel"
	_mission.add_theme_font_size_override("font_size", 10)
	_mission.add_theme_color_override("font_color", UITheme.COL_BRASS)
	title_box.add_child(_mission)

	h.add_child(_divider())

	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 1)
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.custom_minimum_size.x = 0
	h.add_child(mid)
	_objective = Label.new()
	_objective.theme_type_variation = "DimLabel"
	_objective.clip_text = true
	_objective.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_objective.custom_minimum_size.x = 0
	_objective.accessibility_name = "Current mission objective"
	_objective.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mid.add_child(_objective)
	_event = Label.new()
	_event.clip_text = true
	_event.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_event.custom_minimum_size.x = 0
	_event.add_theme_font_override("font", UITheme.semibold_font())
	_event.add_theme_font_size_override("font_size", 13)
	_event.accessibility_name = "Latest command and combat event"
	_event.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_event.mouse_filter = Control.MOUSE_FILTER_PASS
	mid.add_child(_event)

	_alert = Button.new()
	_alert.clip_text = true
	_alert.custom_minimum_size = Vector2(200, 36)
	_alert.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_alert.focus_mode = Control.FOCUS_ALL
	_alert.theme_type_variation = "DangerButton"
	_alert.add_theme_font_size_override("font_size", 12)
	_alert.accessibility_name = "Active threat alert"
	_alert.tooltip_text = "Focus the most urgent inbound threat"
	UIIcons.apply(_alert, "alert", 16)
	_alert.pressed.connect(func() -> void: alert_pressed.emit())
	_alert.visible = false
	h.add_child(_alert)

	# Clock: time large, date and run state beneath.
	var clock := VBoxContainer.new()
	clock.add_theme_constant_override("separation", -1)
	clock.alignment = BoxContainer.ALIGNMENT_CENTER
	clock.custom_minimum_size.x = 118
	h.add_child(clock)
	_time = Label.new()
	_time.clip_text = true
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time.add_theme_font_size_override("font_size", 17)
	_time.add_theme_font_override("font", UITheme.mono_font())
	_time.accessibility_name = "Simulation time"
	clock.add_child(_time)
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", 6)
	sub.alignment = BoxContainer.ALIGNMENT_END
	clock.add_child(sub)
	_date = Label.new()
	_date.add_theme_font_override("font", UITheme.mono_font())
	_date.add_theme_font_size_override("font_size", 10)
	_date.add_theme_color_override("font_color", UITheme.COL_MUTED)
	sub.add_child(_date)
	_state = Label.new()
	_state.add_theme_font_override("font", UITheme.eyebrow_font())
	_state.add_theme_font_size_override("font_size", 10)
	sub.add_child(_state)

	_pause_btn = Button.new()
	_pause_btn.focus_mode = Control.FOCUS_ALL
	_pause_btn.custom_minimum_size = Vector2(38, 36)
	_pause_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pause_btn.pressed.connect(SimClock.toggle_pause)
	h.add_child(_pause_btn)

	var group := ButtonGroup.new()
	var speed_frame := PanelContainer.new()
	speed_frame.theme_type_variation = "SegmentedPanel"
	speed_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(speed_frame)
	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 2)
	speed_frame.add_child(speeds)
	for i in SimClock.SPEEDS.size():
		var b := Button.new()
		b.text = "%d×" % int(SimClock.SPEEDS[i])
		b.theme_type_variation = "SegmentButton"
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size = Vector2(38, 28)
		b.add_theme_font_override("font", UITheme.mono_font())
		b.add_theme_font_size_override("font_size", 12)
		b.tooltip_text = "Time compression %d×  [%d]" % [int(SimClock.SPEEDS[i]), i + 1]
		b.accessibility_name = "Time compression %d times" % int(SimClock.SPEEDS[i])
		b.pressed.connect(SimClock.set_speed_index.bind(i))
		speeds.add_child(b)
		_speed_btns.append(b)

	h.add_child(_divider())

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 2)
	h.add_child(tools)
	for entry in [
		["aircraft", "AIR", air_operations_pressed, "Air operations: launch, recover and turn round aircraft  [F3]"],
		["command", "ACTIONS", commands_pressed, "Search every command  [Cmd+K / Ctrl+K]"],
		["orders", "", briefing_pressed, "Mission orders, objectives and controls  [F1]"],
		["library", "", library_pressed, "Fleet recognition library  [F7]"],
		["restart", "", restart_pressed, "Restart this operation from the beginning  [F10]"],
		["menu", "", menu_pressed, "Operations menu  [F9]"],
	]:
		var b := Button.new()
		b.theme_type_variation = "QuietButton"
		b.text = entry[1]
		b.tooltip_text = entry[3]
		b.accessibility_name = str(entry[3]).get_slice("  [", 0)
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size = Vector2(36, 36)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UIIcons.apply(b, entry[0], 18)
		var sig: Signal = entry[2]
		b.pressed.connect(func() -> void: sig.emit())
		tools.add_child(b)

	SimClock.speed_changed.connect(func(_i: int, _m: float) -> void: _refresh())
	SimClock.paused_changed.connect(func(_p: bool) -> void: _refresh())
	_refresh()


func _divider() -> Control:
	var rule := UITheme.hairline(true)
	rule.size_flags_vertical = Control.SIZE_FILL
	return rule


func _process(delta: float) -> void:
	var stamp := SimClock.datetime_string()
	var parts := stamp.split(" ", false, 1)
	_time.text = parts[1] if parts.size() > 1 else stamp
	_date.text = parts[0] if parts.size() > 1 else ""
	_alert_anim += delta
	if _alert.visible:
		_alert.modulate.a = 0.65 + 0.35 * absf(sin(_alert_anim * 4.0))
	if _flash_left > 0.0:
		_flash_left -= delta
		_event.modulate = Color(_event_color, clampf(_flash_left / 3.0, 0.35, 1.0))


## Severity colours the ticker and the log: "info", "warn", "alert", "good".
func flash(msg: String, severity := "info") -> void:
	history.push_front(SimClock.datetime_string() + "  " + msg)
	if history.size() > 40:
		history.resize(40)
	_event.tooltip_text = "\n".join(history)
	_event.text = msg
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
	_alert.accessibility_description = text + ". Activate to focus the most urgent threat." if text != "" else "No active threat."


func set_scenario_name(scenario_name: String) -> void:
	_mission.text = scenario_name.to_upper()
	_mission.tooltip_text = scenario_name


func set_objective_text(text: String) -> void:
	_objective.text = text


func _refresh() -> void:
	var paused := SimClock.paused
	UIIcons.apply(_pause_btn, "play" if paused else "pause", 18)
	_pause_btn.theme_type_variation = "PrimaryButton" if paused else ""
	_pause_btn.add_theme_constant_override("h_separation", 0)
	_pause_btn.add_theme_stylebox_override("normal", _pause_style(paused, false))
	_pause_btn.add_theme_stylebox_override("hover", _pause_style(paused, true))
	_pause_btn.add_theme_stylebox_override("pressed", _pause_style(paused, true))
	_pause_btn.tooltip_text = "Resume  [Space]" if paused else "Pause  [Space]"
	_state.text = "PAUSED" if paused else "RUNNING"
	_state.add_theme_color_override("font_color", UITheme.COL_AMBER if paused else UITheme.COL_GREEN)
	_pause_btn.accessibility_name = "Resume simulation" if paused else "Pause simulation"
	_pause_btn.accessibility_description = "Simulation paused at %d times acceleration." % int(SimClock.multiplier()) if paused else "Simulation running at %d times acceleration." % int(SimClock.multiplier())
	for i in _speed_btns.size():
		_speed_btns[i].button_pressed = i == SimClock.speed_index


## Paused, the button is the amber call to resume; running, it is a quiet pause control.
func _pause_style(paused: bool, hover: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(UITheme.RADIUS)
	s.set_border_width_all(1)
	s.content_margin_left = 9
	s.content_margin_right = 9
	if paused:
		s.bg_color = UITheme.COL_AMBER.lightened(0.12) if hover else UITheme.COL_AMBER
		s.border_color = s.bg_color
	else:
		s.bg_color = UITheme.COL_HOVER if hover else UITheme.COL_RAISED
		s.border_color = UITheme.COL_BORDER_LIGHT if hover else UITheme.COL_BORDER
	return s
