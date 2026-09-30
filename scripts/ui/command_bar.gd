class_name CommandBar
extends PanelContainer
## Small, persistent command keys between the chart and the three lower panes. Every key routes
## through Main's existing actions; this control owns no simulation or hidden contact state.

signal action_requested(id: String)

var map: TacticalMap
var buttons: Dictionary = {}
var _hint: Label
var _refresh := 0.0

const KEYS := [
	["missions", "Mission", "Operations desk [M]"],
	["status_boards", "Orders  A", "Orders, task group, track file and communications"],
	["plot_move", "Route  W", "Plot a route; hold Shift to append waypoints"],
	["plot_patrol", "Patrol", "Assign a repeating patrol: click two opposite corners [Shift+W]"],
	["weapon_control", "Weapons", "Weapon, salvo and target-quality control [Shift+E]"],
	["air_operations", "Air  F3", "Launch, task and recover aircraft"],
	["next_contact", "Contact  N", "Hook the next priority contact"],
	["swap_views", "3D  G", "Exchange the chart and the live camera"],
]


func _ready() -> void:
	custom_minimum_size.y = 30.0
	var face := UITheme.bevel(UITheme.JFC_GREY, false, 0.0)
	face.content_margin_left = 4.0
	face.content_margin_right = 4.0
	face.content_margin_top = 2.0
	face.content_margin_bottom = 2.0
	add_theme_stylebox_override("panel", face)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	add_child(row)
	for key: Array in KEYS:
		var button := Button.new()
		button.text = key[1]
		button.tooltip_text = key[2]
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 14)
		var id: String = key[0]
		button.pressed.connect(func() -> void: action_requested.emit(id))
		row.add_child(button)
		buttons[id] = button
	_hint = Label.new()
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.clip_text = true
	_hint.add_theme_font_size_override("font_size", 13)
	row.add_child(_hint)
	var pause := Button.new()
	pause.custom_minimum_size.x = 130.0
	pause.focus_mode = Control.FOCUS_NONE
	pause.add_theme_font_size_override("font_size", 14)
	pause.tooltip_text = "Pause / resume [Space]. Orders can be issued while paused."
	pause.pressed.connect(func() -> void: action_requested.emit("toggle_pause"))
	row.add_child(pause)
	buttons["toggle_pause"] = pause
	refresh()


func _process(delta: float) -> void:
	_refresh += delta
	if _refresh >= 0.15:
		_refresh = 0.0
		refresh()


func refresh() -> void:
	if map == null or buttons.is_empty():
		return
	var movable := map._has_controllable_selection()
	for id: String in ["plot_move", "plot_patrol"]:
		buttons[id].disabled = not movable
	buttons["plot_move"].text = "Route *" if map.interaction_mode == TacticalMap.InteractionMode.MOVE else "Route  W"
	buttons["plot_patrol"].text = "Patrol *" if map.interaction_mode == TacticalMap.InteractionMode.PATROL else "Patrol"
	buttons["weapon_control"].disabled = map.selected.is_empty()
	buttons["toggle_pause"].text = "RESUME  ▷" if SimClock.paused else "PAUSE  %d×" % int(SimClock.multiplier())
	if map.interaction_mode == TacticalMap.InteractionMode.PATROL:
		_hint.text = "PATROL: two corners • allow turning room • right-click cancels"
	elif map.interaction_mode == TacticalMap.InteractionMode.MOVE:
		_hint.text = "ROUTE: click destination • Shift adds a leg • right-click cancels"
	elif map.selected.size() == 1:
		var u: Unit = map.selected[0]
		_hint.text = "%s  |  %s" % [u.callsign, DataDisplay.orders_text(u)]
	elif not map.selected.is_empty():
		_hint.text = "%d platforms hooked • right-click for orders" % map.selected.size()
	else:
		_hint.text = "Hook a platform to command • right-click for context • H for keys"
