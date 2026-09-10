class_name TopBar
extends PanelContainer
## Mission status, simulation time, pause and time-acceleration controls.

signal briefing_pressed()
signal restart_pressed()
signal menu_pressed()

const FLASH_S := 12.0

var _title: Label
var _objective: Label
var _event: Label
var _flash_left := 0.0
var _time: Label
var _pause_btn: Button
var _speed_btns: Array[Button] = []


func _ready() -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	add_child(h)

	_title = Label.new()
	_title.text = "NAVAL FLEET COMMAND"
	# Every label up here clips rather than growing, or a long mission name or event message
	# widens the whole window and pushes the side panels off screen.
	_title.clip_text = true
	_title.custom_minimum_size.x = 250
	h.add_child(_title)

	_objective = Label.new()
	_objective.modulate = Color(0.55, 0.70, 0.80)
	_objective.clip_text = true
	_objective.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_objective.custom_minimum_size.x = 0
	h.add_child(_objective)

	_event = Label.new()
	_event.modulate = Color(1.0, 0.8, 0.4)
	_event.clip_text = true
	_event.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_event.custom_minimum_size.x = 0
	h.add_child(_event)

	_time = Label.new()
	_time.clip_text = true
	_time.custom_minimum_size.x = 175
	h.add_child(_time)

	_pause_btn = Button.new()
	_pause_btn.focus_mode = Control.FOCUS_NONE
	_pause_btn.custom_minimum_size.x = 80
	_pause_btn.pressed.connect(SimClock.toggle_pause)
	h.add_child(_pause_btn)

	var group := ButtonGroup.new()
	for i in SimClock.SPEEDS.size():
		var b := Button.new()
		b.text = "%dx" % int(SimClock.SPEEDS[i])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(SimClock.set_speed_index.bind(i))
		h.add_child(b)
		_speed_btns.append(b)

	for entry in [["BRIEF", briefing_pressed], ["RESTART", restart_pressed], ["MENU", menu_pressed]]:
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
	if _flash_left > 0.0:
		_flash_left -= delta
		_event.modulate.a = clampf(_flash_left / 3.0, 0.0, 1.0)


func flash(msg: String) -> void:
	_event.text = "▶ " + msg
	_event.modulate.a = 1.0
	_flash_left = FLASH_S


func set_scenario_name(scenario_name: String) -> void:
	_title.text = "NAVAL FLEET COMMAND  —  %s" % scenario_name


func set_objective_text(text: String) -> void:
	_objective.text = "   %s" % text if text != "" else ""


func _refresh() -> void:
	_pause_btn.text = "PAUSED" if SimClock.paused else "RUN"
	_pause_btn.modulate = Color(1.0, 0.75, 0.4) if SimClock.paused else Color.WHITE
	for i in _speed_btns.size():
		_speed_btns[i].button_pressed = i == SimClock.speed_index
