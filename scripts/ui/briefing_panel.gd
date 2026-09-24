class_name BriefingPanel
extends PanelContainer
## Orders first, with situation and command reference one tab away. The same board reports
## objective progress when reopened during a mission.

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
var _scenario: Dictionary = {}
var _active_section := "orders"
var _tabs: Dictionary = {}
var _preview: ScenarioPreview
var _meta: Label
var _intent: Label
var _posture: Label
var _margin: MarginContainer
var _rail: VBoxContainer
var _pre_mission := true
var _layout: VBoxContainer


func _ready() -> void:
	theme_type_variation = "OverlayPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_margin = MarginContainer.new()
	add_child(_margin)
	var v := VBoxContainer.new()
	_layout = v
	v.add_theme_constant_override("separation", 16)
	_margin.add_child(v)
	_eyebrow = UITheme.eyebrow("Operation orders  ·  Mission briefing")
	_eyebrow.add_theme_color_override("font_color", UITheme.COL_BRASS)
	v.add_child(_eyebrow)
	_title = _label("", 40, Color.WHITE)
	_title.add_theme_font_override("font", UITheme.heading_font())
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_title)
	_meta = _label("", 12, UITheme.COL_MUTED)
	_meta.add_theme_font_override("font", UITheme.eyebrow_font())
	_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_meta)
	var intent_card := PanelContainer.new()
	intent_card.add_theme_stylebox_override("panel", UITheme.stripe_card(UITheme.COL_BRASS))
	v.add_child(intent_card)
	var intent_box := VBoxContainer.new()
	intent_box.add_theme_constant_override("separation", 6)
	intent_card.add_child(intent_box)
	intent_box.add_child(UITheme.eyebrow("Commander's intent"))
	_intent = _label("", 21, UITheme.COL_TEXT)
	_intent.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intent_box.add_child(_intent)

	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 20)
	v.add_child(main)
	var reading := VBoxContainer.new()
	reading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reading.add_theme_constant_override("separation", 10)
	main.add_child(reading)
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 22)
	reading.add_child(tab_row)
	for entry in [["orders", "ORDERS & OBJECTIVES"], ["situation", "SITUATION"], ["controls", "COMMAND REFERENCE"]]:
		var key: String = entry[0]
		var tab := _button(entry[1])
		tab.theme_type_variation = "TabButton"
		tab.custom_minimum_size.y = 36
		tab.add_theme_font_size_override("font_size", 13)
		tab.toggle_mode = true
		tab.pressed.connect(func() -> void: _select_section(key))
		tab_row.add_child(tab)
		_tabs[key] = tab
	var card := PanelContainer.new()
	card.theme_type_variation = "CardPanel"
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	reading.add_child(card)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = false
	_body.scroll_active = true
	_body.focus_mode = Control.FOCUS_ALL
	_body.accessibility_name = "Mission orders and objectives"
	_body.accessibility_description = "Scrollable briefing. Use arrows, Page Up, or Page Down while focused."
	_body.add_theme_font_size_override("normal_font_size", 16)
	_body.add_theme_font_size_override("bold_font_size", 16)
	_body.add_theme_constant_override("line_separation", 7)
	card.add_child(_body)
	_rail = VBoxContainer.new()
	_rail.add_theme_constant_override("separation", 12)
	main.add_child(_rail)
	_rail.add_child(UITheme.eyebrow("Area of operations"))
	_preview = ScenarioPreview.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rail.add_child(_preview)
	_posture = _label("", 14, UITheme.COL_DIM)
	_posture.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rail.add_child(_posture)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	v.add_child(buttons)
	_start = _button("TAKE COMMAND", true)
	_start.custom_minimum_size.x = 250
	_start.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UIIcons.apply(_start, "arrow_right", 18)
	_start.pressed.connect(func() -> void:
		SoundFx.play("click")
		start_pressed.emit())
	buttons.add_child(_start)
	_restart = _button("RESTART")
	_restart.tooltip_text = "Reload this operation from its starting positions  [F10]"
	UIIcons.apply(_restart, "restart", 16)
	_restart.pressed.connect(func() -> void: restart_pressed.emit())
	buttons.add_child(_restart)
	_menu = _button("ALL OPERATIONS")
	_menu.tooltip_text = "Return to the operations desk  [F9]"
	UIIcons.apply(_menu, "menu", 16)
	_menu.pressed.connect(func() -> void: menu_pressed.emit())
	buttons.add_child(_menu)
	var pause_note := _label("Space pauses at any time", 12, UITheme.COL_MUTED)
	pause_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pause_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(pause_note)
	resized.connect(_apply_layout)
	_apply_layout()
	_select_section("orders")
	_set_focus_cycle()


func _apply_layout() -> void:
	if _margin == null:
		return
	var viewport_size := get_viewport_rect().size
	var compact := viewport_size.x < 1300 or viewport_size.y < 850
	for side in ["left", "right"]:
		_margin.add_theme_constant_override("margin_" + side, 32 if compact else 76)
	for side in ["top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, 24 if compact else 40)
	_rail.custom_minimum_size.x = 244 if compact else 350
	_preview.custom_minimum_size = Vector2(244 if compact else 350, 190 if compact else 280)
	_title.add_theme_font_size_override("font_size", 32 if compact else 40)
	_posture.visible = not compact
	_layout.add_theme_constant_override("separation", 12 if compact else 16)
	_intent.add_theme_font_size_override("font_size", 20 if compact else 22)


func _set_focus_cycle() -> void:
	var controls: Array[Control] = [_tabs["orders"], _tabs["situation"], _tabs["controls"], _body, _start, _restart, _menu]
	for i in controls.size():
		controls[i].focus_next = controls[i].get_path_to(controls[(i + 1) % controls.size()])
		controls[i].focus_previous = controls[i].get_path_to(controls[posmod(i - 1, controls.size())])


func configure(scenario_name: String, forces: String, situation: String, environment: Dictionary = {}, scenario: Dictionary = {}) -> void:
	_scenario_name = scenario_name
	_forces = forces
	_situation = situation
	_environment = environment
	_scenario = scenario
	_active_section = "orders"
	if _preview != null:
		_preview.set_scenario(scenario)
	refresh(true)
	if _body != null:
		_body.scroll_to_line(0)


func _select_section(section: String) -> void:
	_active_section = section
	refresh(true)
	if _body != null:
		_body.scroll_to_line(0)


func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum >= 0.5:
		_accum = 0.0
		refresh()


func refresh(reset_scroll := false) -> void:
	if mission_manager == null or _body == null:
		return
	_title.text = _scenario_name.replace(" — ", " / ")
	var details := PackedStringArray()
	var date := str(_scenario.get("start_time_utc", ""))
	if date.length() >= 16:
		details.append(date.substr(0, 10) + "  " + date.substr(11, 5) + " Z")
	if _scenario.has("role"):
		details.append(str(_scenario["role"]))
	if _scenario.has("difficulty"):
		details.append(str(_scenario["difficulty"]))
	var duration := int(_scenario.get("duration_minutes", 0))
	if duration > 0:
		details.append("About %d min play" % duration)
	_meta.text = "  ·  ".join(details)
	_meta.visible = not details.is_empty()
	_intent.text = _scenario.get("commander_intent", mission_manager.briefing if mission_manager.briefing != "" else "Establish the tactical picture and accomplish the objectives below.")
	_posture.text = "The clock is paused.\n\nTake Command begins at real time. Press Space whenever you need time to assess contacts or issue orders." if _pre_mission else "The clock is paused.\n\nReview your objectives, then Resume to continue the operation."
	for key: String in _tabs:
		var button: Button = _tabs[key]
		button.set_pressed_no_signal(key == _active_section)
	var out := PackedStringArray()
	match _active_section:
		"situation":
			_append_situation(out)
		"controls":
			_append_controls(out)
		_:
			_append_orders(out)
	var next_text := "\n".join(out)
	# Preserve position only for live updates within a page. A new page or operation must
	# start at its opening orders after the RichTextLabel has finished its deferred layout.
	if _body.text != next_text:
		var scroll := 0.0 if reset_scroll else _body.get_v_scroll_bar().value
		_body.text = next_text
		_body.get_v_scroll_bar().set_deferred("value", scroll)
	elif reset_scroll:
		_body.get_v_scroll_bar().set_deferred("value", 0.0)


func _append_orders(out: PackedStringArray) -> void:
	var first_orders: Array = _scenario.get("first_orders", [])
	if not first_orders.is_empty():
		out.append(_section("OPENING ORDERS"))
		for i in first_orders.size():
			out.append("[color=%s][b]%02d[/b][/color]   %s\n" % [UITheme.HEX_BRASS, i + 1, _safe(str(first_orders[i]))])
	elif mission_manager.briefing != "":
		out.append(_section("YOUR TASK"))
		out.append(_safe(mission_manager.briefing) + "\n")
	else:
		out.append(_section("OPENING ORDERS"))
		out.append("01   Select your command ship and review the force.\n02   Set your course, speed and emissions before committing.\n03   Classify contacts and protect the units named below.\n")
	out.append(_section("SUCCESS CONDITIONS  /  " + ("COMPLETE EITHER" if mission_manager.victory_mode == "any" else "COMPLETE ALL")))
	if mission_manager.victory_objectives.is_empty():
		out.append("Free command. This operation has no fixed victory conditions.")
	for o in mission_manager.victory_objectives:
		out.append(_line(o))
	if not mission_manager.loss_objectives.is_empty():
		out.append("\n" + _section("PROTECT AGAINST"))
		for o in mission_manager.loss_objectives:
			out.append(_line(o, true))
	if _scenario.has("learning"):
		out.append("\n" + _section("COMMAND CHALLENGE"))
		out.append(_safe(str(_scenario["learning"])))


func _append_situation(out: PackedStringArray) -> void:
	out.append(_section("SITUATION"))
	out.append(_safe(_situation) + "\n")
	if _forces != "":
		out.append(_section("FORCE UNDER YOUR COMMAND"))
		out.append(_safe(_forces) + "\n")
	out.append(_section("WEATHER & ACOUSTIC CONDITIONS"))
	var sea := int(_environment.get("sea_state", 0))
	var env_line := "Sea state %d (%s)" % [sea, Detection.SEA_STATE_NAMES[clampi(sea, 0, 6)]]
	if _environment.has("wind_kn"):
		env_line += " · wind %d kn" % int(_environment["wind_kn"])
	if _environment.has("visibility_nm"):
		env_line += " · visibility %d nm" % int(_environment["visibility_nm"])
	out.append(env_line)
	if sea >= 3:
		out.append("[color=%s]Rough water reduces passive sonar reach and obscures low missiles in sea clutter.[/color]" % UITheme.HEX_AMBER)
	var layer := int(_environment.get("layer_depth_m", 0))
	var cz := int(_environment.get("cz_range_nm", 0))
	var water := PackedStringArray()
	water.append("Thermal layer: %d m" % layer if layer > 0 else "Mixed water: no thermal layer")
	if cz > 0:
		water.append("convergence zones every %d nm in deep water" % cz)
	out.append(" · ".join(water))
	if layer > 0:
		out.append("[color=%s]Submarines below the layer are harder for hull sonar to hear. Dipping sonar, deep buoys and towed bodies can search across it.[/color]" % UITheme.HEX_DIM)
	if _scenario.has("historical_note"):
		out.append("\n" + _section("HISTORICAL CONTEXT"))
		out.append(_safe(str(_scenario["historical_note"])))
	elif _scenario.has("force_note"):
		out.append("\n" + _safe(str(_scenario["force_note"])))


func _append_controls(out: PackedStringArray) -> void:
	out.append(_section("SELECT, PLOT, COMMIT"))
	out.append("[b]Left click[/b] selects a ship or contact. [b]Shift-click[/b] adds friendly units to a group.\n[b]G[/b] arms Plot Move; left-click water to set the destination. Hold Shift to chain waypoints. Escape or right-click cancels.\n[b]R[/b] toggles radar, [b]P[/b] active sonar, [b]E[/b] emission control.\n")
	out.append(_section("CHART & CONTACT PICTURE"))
	out.append("[b]Wheel / pinch[/b] zooms. Middle/right/Option-drag pans.\n[b]B[/b] expands or restores the chart. [b]Home[/b] fits the force. [b]F[/b] follows the selected platform or contact. [b]C[/b] focuses the shooter-target problem.\n[b]N / Shift-N[/b] cycles priority contacts. The Tactical Overview recentres the chart.\n")
	out.append(_section("AIR OPERATIONS"))
	out.append("[b]AIR / F3[/b] opens aircraft selection, sortie size, readiness and landing controls.\nSelect airborne aircraft, choose a landing facility, then [b]Return & Land[/b]. Landed aircraft refuel and rearm before relaunch.\n")
	out.append(_section("TIME & DISPLAY"))
	out.append("[b]Space[/b] pauses. [b]1–6[/b] sets acceleration. Use real time when contacts close; accelerate when the force is on station.\n[b]F2[/b] symbol key · [b]F4[/b] sensor rings · [b]F5[/b] trails · [b]F6[/b] terrain · [b]V[/b] vectors · [b]M[/b] sound.\n[b]Command-K / Control-K[/b] opens the searchable Actions palette.")


func _line(o: MissionObjective, loss := false) -> String:
	var mark := "[color=%s]COMPLETE[/color]" % UITheme.HEX_GREEN if o.complete else "[color=%s]OPEN[/color]" % UITheme.HEX_AMBER
	if loss:
		mark = "[color=%s]TRIGGERED[/color]" % UITheme.HEX_RED if o.complete else "[color=%s]AVOID[/color]" % UITheme.HEX_MUTED
	var detail := o.progress(unit_manager, SimClock.sim_time) if unit_manager != null else ""
	return "[font_size=12]%s[/font_size]   %s\n[color=%s][font_size=13]%s[/font_size][/color]" % [mark, _safe(o.text), UITheme.HEX_MUTED, _safe(detail)]


func set_mode(pre_mission: bool) -> void:
	_pre_mission = pre_mission
	_start.text = "TAKE COMMAND" if pre_mission else "RESUME OPERATION"
	_eyebrow.text = "OPERATION ORDERS  ·  MISSION BRIEFING" if pre_mission else "OPERATION ORDERS  ·  MISSION STATUS"
	if pre_mission:
		_select_section("orders")
	refresh()


func focus_default() -> void:
	if visible and _start != null:
		_start.grab_focus()


static func _safe(value: String) -> String:
	return value.replace("[", "[lb]")


static func _section(value: String) -> String:
	return UITheme.section_bb(value)


static func _label(value: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result


static func _button(value: String, primary := false) -> Button:
	var result := Button.new()
	result.text = value
	result.focus_mode = Control.FOCUS_ALL
	result.custom_minimum_size.y = 44
	result.add_theme_font_size_override("font_size", 13)
	if primary:
		result.theme_type_variation = "PrimaryButton"
	return result
