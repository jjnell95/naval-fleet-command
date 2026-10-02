class_name CommandBar
extends PanelContainer
## Small, persistent command keys between the chart and the three lower panes. Every key routes
## through Main's existing actions; this control owns no simulation or hidden contact state.

signal action_requested(id: String)

var map: TacticalMap
var buttons: Dictionary = {}
## The gameplay preset on the chip ("NORMAL", "CLASSIC 4×", "CUSTOM 10×") and its options, one per
## line, for the tooltip. Main sets both whenever the options change.
var options_label := "NORMAL"
var options_tooltip := ""
var _hint: Label
var _refresh := 0.0

const KEYS := [
	["missions", "Mission", "Operations desk [M]"],
	["chart_menu", "Chart ▾", "Graphic symbols, readable labels, sensor ranges and chart navigation"],
	["orders_menu", "Orders ▾", "Route, patrol, return to station and platform settings. Status boards [A]"],
	["weapon_control", "Attack", "Weapon, salvo and target-quality control [Shift+E]"],
	["open_defence", "Defence", "Countermeasures, evasion, interceptor policy and inbound weapon tracking"],
	["air_operations", "Air  F3", "Launch, task and recover aircraft"],
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
	# The active preset, always in view: the rules this watch is being played under.
	var chip := Button.new()
	# Sized to its words (at most "CUSTOM 60×"), never clipped: the hint beside it gives way instead.
	chip.custom_minimum_size.x = 96.0
	chip.focus_mode = Control.FOCUS_NONE
	chip.add_theme_font_size_override("font_size", 13)
	chip.pressed.connect(func() -> void: action_requested.emit("options_menu"))
	row.add_child(chip)
	buttons["options_menu"] = chip
	var speed := Button.new()
	speed.custom_minimum_size.x = 62.0
	speed.focus_mode = Control.FOCUS_NONE
	speed.add_theme_font_size_override("font_size", 14)
	speed.tooltip_text = "Choose time acceleration. Combat returns the watch to 1×."
	speed.pressed.connect(func() -> void: action_requested.emit("time_menu"))
	row.add_child(speed)
	buttons["time_menu"] = speed
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
	buttons["weapon_control"].disabled = map.selected.is_empty()
	buttons["time_menu"].text = "%d× ▾" % int(SimClock.multiplier())
	buttons["options_menu"].text = options_label
	buttons["options_menu"].tooltip_text = "Gameplay options: choose Normal, Classic or single options.\n" + options_tooltip
	buttons["open_defence"].disabled = map.selected.is_empty()
	buttons["toggle_pause"].text = "RESUME  ▷" if SimClock.paused else "PAUSE  %d×" % int(SimClock.multiplier())
	if map.interaction_mode == TacticalMap.InteractionMode.PATROL:
		_hint.text = "PATROL: two corners • allow turning room • right-click cancels"
	elif map.interaction_mode == TacticalMap.InteractionMode.MOVE:
		_hint.text = "ROUTE: click destination • Shift adds a leg • right-click cancels"
	elif map.selected.size() == 1:
		var u: Unit = map.selected[0]
		if map.inspection_track() != null:
			_hint.text = "%s → TRACK %s" % [u.callsign, map.track_number_text(map.inspection_track())]
		else:
			_hint.text = "%s  |  %s" % [u.callsign, DataDisplay.orders_text(u)]
	elif not map.selected.is_empty():
		_hint.text = "%d platforms hooked • right-click for orders" % map.selected.size()
	else:
		_hint.text = "Hook a platform to command • right-click for context • H for keys"
	_hint.tooltip_text = _hint.text


## The basic chart tools are available even with a shooter selected, without knowing a key.
static func chart_items(chart: TacticalMap) -> Array:
	return [
		CdsMenus.item("Graphic ship & aircraft symbols", {"kind": "symbols", "mode": TacticalMap.SymbolMode.MEDIUM}, false, "Recognized platforms use their plan-view silhouettes; uncertain contacts retain their reported symbols.", 1 if chart.symbol_mode != TacticalMap.SymbolMode.NTDS else 0),
		CdsMenus.item("Classic tactical symbols", {"kind": "symbols", "mode": TacticalMap.SymbolMode.NTDS}, false, "", 1 if chart.symbol_mode == TacticalMap.SymbolMode.NTDS else 0),
		CdsMenus.item("Platform names & contact labels", {"kind": "layer", "name": "tags"}, false, "Contact names show only what your sensors have established.", 1 if chart.show_tags else 0),
		CdsMenus.item("Explain symbols", {"kind": "layer", "name": "key"}, false, "", 1 if chart.show_key else 0),
		CdsMenus.sep(),
		CdsMenus.item("Sensor ranges", {"kind": "layer", "name": "sensors"}, false, "", 1 if chart.show_rings else 0),
		CdsMenus.item("Weapon ranges", {"kind": "layer", "name": "weapon_ranges"}, false, "", 1 if chart.show_weapon_ranges else 0),
		CdsMenus.item("Movement trails", {"kind": "layer", "name": "trails"}, false, "", 1 if chart.show_trails else 0),
		CdsMenus.sep(),
		CdsMenus.item("Zoom in", {"kind": "palette", "id": "chart_zoom_in"}),
		CdsMenus.item("Zoom out", {"kind": "palette", "id": "chart_zoom_out"}),
		CdsMenus.item("Frame selected platforms & target", {"kind": "palette", "id": "focus_selection"}),
		CdsMenus.item("Find my fleet", {"kind": "palette", "id": "fit_fleet"}),
		CdsMenus.item("Whole theatre", {"kind": "palette", "id": "fit_theatre"}),
		CdsMenus.sep(),
		CdsMenus.item("Next priority contact  [N]", {"kind": "palette", "id": "next_contact"}),
	]


## The time ladder in use, so a 4× ceiling offers 1×, 2× and 4× and nothing faster.
static func time_items() -> Array:
	var items: Array = []
	var ladder := SimClock.speeds()
	for i in ladder.size():
		var note := "  Real time" if i == 0 else ("  Ceiling" if i == ladder.size() - 1 and ladder.size() < SimClock.SPEEDS.size() else "")
		items.append(CdsMenus.item("%d×%s  [%d]" % [int(ladder[i]), note, i + 1],
			{"kind": "palette", "id": "speed_%d" % i}, false, "Choosing a speed leaves a paused watch paused.", 1 if SimClock.speed_index == i else 0))
	return items
