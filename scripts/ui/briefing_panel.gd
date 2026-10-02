class_name BriefingPanel
extends PanelContainer
## Orders first, with situation and command reference one tab away. The same board reports
## objective progress when reopened during a mission. Before command it is a front-end screen
## over the dusk backdrop; during a mission it is a grey dialog drawn straight over the chart.

signal start_pressed()
signal restart_pressed()
signal menu_pressed()

var mission_manager: MissionManager
var unit_manager: UnitManager
## The gameplay options the operation is played under, one line each (Main sets it): the preset
## is part of the orders, since it decides who fires interceptors and how fast the watch may run.
var options_lines := PackedStringArray()
var options_label := ""
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
var _backdrop: TextureRect
var _sheet: PanelContainer
var _area_caption: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop = UITheme.backdrop()
	add_child(_backdrop)
	_margin = MarginContainer.new()
	add_child(_margin)
	_sheet = PanelContainer.new()
	_margin.add_child(_sheet)
	var v := VBoxContainer.new()
	_layout = v
	v.add_theme_constant_override("separation", 10)
	_sheet.add_child(v)
	_eyebrow = UITheme.caption("Mission briefing")
	v.add_child(_eyebrow)
	_title = _label("", 32, UITheme.MENU_INK)
	_title.add_theme_font_override("font", UITheme.caption_font())
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_title)
	_meta = _label("", 11, UITheme.INK_BLUE)
	_meta.add_theme_font_override("font", UITheme.eyebrow_font())
	_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_meta)
	var intent_card := PanelContainer.new()
	intent_card.theme_type_variation = "CardPanel"
	v.add_child(intent_card)
	var intent_box := VBoxContainer.new()
	intent_box.add_theme_constant_override("separation", 3)
	intent_card.add_child(intent_box)
	intent_box.add_child(_label("COMMANDER'S INTENT", 12, UITheme.INK_BLUE))
	_intent = _label("", 17, UITheme.MENU_INK)
	_intent.add_theme_font_override("font", UITheme.data_font())
	_intent.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intent_box.add_child(_intent)

	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 16)
	v.add_child(main)
	var reading := VBoxContainer.new()
	reading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reading.add_theme_constant_override("separation", 6)
	main.add_child(reading)
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 4)
	reading.add_child(tab_row)
	for entry in [["orders", "ORDERS & OBJECTIVES"], ["situation", "SITUATION"], ["controls", "COMMAND REFERENCE"]]:
		var key: String = entry[0]
		var tab := _button(entry[1])
		tab.theme_type_variation = "TabButton"
		tab.custom_minimum_size.y = 30
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
	_body.add_theme_color_override("default_color", UITheme.MENU_INK)
	_body.add_theme_font_size_override("normal_font_size", 14)
	_body.add_theme_font_size_override("bold_font_size", 14)
	_body.add_theme_constant_override("line_separation", 5)
	card.add_child(_body)
	_rail = VBoxContainer.new()
	_rail.add_theme_constant_override("separation", 6)
	main.add_child(_rail)
	_area_caption = UITheme.caption("Area of operations")
	_rail.add_child(_area_caption)
	_preview = ScenarioPreview.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rail.add_child(_preview)
	_posture = _label("", 13, UITheme.MENU_INK)
	_posture.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rail.add_child(_posture)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	v.add_child(buttons)
	_start = _button("TAKE COMMAND", true)
	_start.custom_minimum_size.x = 260
	_start.pressed.connect(func() -> void:
		SoundFx.play("click")
		start_pressed.emit())
	buttons.add_child(_start)
	_restart = _button("RESTART")
	_restart.tooltip_text = "Reload this operation from its starting positions  [Ctrl+F10]"
	_restart.pressed.connect(func() -> void: restart_pressed.emit())
	buttons.add_child(_restart)
	_menu = _button("ALL OPERATIONS")
	_menu.tooltip_text = "Return to the operations desk  [M]"
	_menu.pressed.connect(func() -> void: menu_pressed.emit())
	buttons.add_child(_menu)
	var pause_note := _label("Space pauses at any time", 12, UITheme.MENU_INK)
	pause_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pause_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pause_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buttons.add_child(pause_note)
	resized.connect(_apply_layout)
	_apply_style()
	_apply_layout()
	_select_section("orders")
	_set_focus_cycle()


## Front end before command, grey dialog during a mission.
func _apply_style() -> void:
	if _sheet == null:
		return
	_backdrop.visible = _pre_mission
	if _pre_mission:
		theme_type_variation = "OverlayPanel"
		remove_theme_stylebox_override("panel")
	else:
		var shade := StyleBoxFlat.new()
		shade.bg_color = UITheme.DIALOG_SHADE
		add_theme_stylebox_override("panel", shade)
	_sheet.theme_type_variation = "MenuPanel" if _pre_mission else "JfcDialog"
	_eyebrow.theme_type_variation = "MenuCaption" if _pre_mission else "TitleLabel"
	_area_caption.theme_type_variation = "MenuCaption" if _pre_mission else "HeaderLabel"
	for b: Button in [_start, _restart, _menu]:
		b.theme_type_variation = "MenuBigButton" if _pre_mission else ("PrimaryButton" if b == _start else "")
		if _pre_mission:
			b.add_theme_font_size_override("font_size", 20 if b == _start else 17)
		else:
			b.remove_theme_font_size_override("font_size")
	_apply_layout()


func _apply_layout() -> void:
	if _margin == null:
		return
	var viewport_size := get_viewport_rect().size
	var compact := viewport_size.x < 1300 or viewport_size.y < 850
	# In a mission the board is a dialog: narrower, and inset from the window's edges.
	var side := 24 if compact else maxi(int((viewport_size.x - (1320.0 if _pre_mission else 1180.0)) * 0.5), 40)
	for key in ["left", "right"]:
		_margin.add_theme_constant_override("margin_" + key, side)
	for key in ["top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + key, 16 if compact else (26 if _pre_mission else 44))
	_rail.custom_minimum_size.x = 240 if compact else 330
	_preview.custom_minimum_size = Vector2(240 if compact else 330, 190 if compact else 280)
	_title.add_theme_font_size_override("font_size", 26 if compact else 32)
	_posture.visible = not compact
	_layout.add_theme_constant_override("separation", 7 if compact else 10)
	_intent.add_theme_font_size_override("font_size", 15 if compact else 17)


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
	_title.text = _scenario_name.replace(" — ", " / ").to_upper()
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
	_meta.text = "  ·  ".join(details).to_upper()
	_meta.visible = not details.is_empty()
	_intent.text = _scenario.get("commander_intent", mission_manager.briefing if mission_manager.briefing != "" else "Establish the tactical picture and accomplish the objectives below.")
	_posture.text = "The clock is paused.\n\nTake Command begins at real time. Press Space whenever you need time to assess contacts or issue orders." if _pre_mission else "The clock is paused.\n\nReview your objectives, then Resume to continue the operation."
	if options_label != "":
		_posture.text += "\n\nGAMEPLAY: %s\n%s" % [options_label, "\n".join(options_lines)]
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
	if not _scenario.get("operation_plan", []).is_empty():
		out.append(_section("OPERATION SEQUENCE"))
		for phase: Dictionary in _scenario["operation_plan"]:
			out.append("[b]%s[/b]  %s\n" % [_safe(str(phase["title"])), _safe(str(phase["task"]))])
	var first_orders: Array = _scenario.get("first_orders", [])
	if not first_orders.is_empty():
		out.append(_section("OPENING ORDERS"))
		for i in first_orders.size():
			out.append("[color=%s][b]%02d[/b][/color]   %s\n" % [UITheme.HEX_INK_BLUE, i + 1, _safe(str(first_orders[i]))])
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
		out.append("[color=%s]Rough water reduces passive sonar reach and obscures low missiles in sea clutter.[/color]" % UITheme.HEX_INK_AMBER)
	var layer := int(_environment.get("layer_depth_m", 0))
	var cz := int(_environment.get("cz_range_nm", 0))
	var water := PackedStringArray()
	water.append("Thermal layer: %d m" % layer if layer > 0 else "Mixed water: no thermal layer")
	if cz > 0:
		water.append("convergence zones every %d nm in deep water" % cz)
	out.append(" · ".join(water))
	if layer > 0:
		out.append("[color=%s]Submarines below the layer are harder for hull sonar to hear. Dipping sonar, deep buoys and towed bodies can search across it.[/color]" % UITheme.HEX_INK_DIM)
	if _scenario.has("historical_note"):
		out.append("\n" + _section("HISTORICAL CONTEXT"))
		out.append(_safe(str(_scenario["historical_note"])))
	elif _scenario.has("setting_note"):
		out.append("\n" + _section("SETTING"))
		out.append(_safe(str(_scenario["setting_note"])))
	elif _scenario.has("force_note"):
		out.append("\n" + _safe(str(_scenario["force_note"])))


## The command reference: the key commands of the command screen, the chart, the 3D view and the
## right-click menus.
func _append_controls(out: PackedStringArray) -> void:
	out.append(_section("HOOK, ORDER, ENGAGE"))
	out.append("[b]Left click[/b] hooks a platform or contact. [b]Shift-click[/b] adds friendly units to a group.\n[b]Right-click[/b] water to send the hooked platform there (Shift adds a waypoint); right-click a hostile contact to [b]attack[/b] it (the platform closes to range, chooses the weapon and keeps firing), an unidentified contact to [b]investigate[/b] it, your own platform for its orders menu, and empty chart with nothing hooked for the display menu. [b]Shift+right-click[/b] a contact for weapons, salvos and the firing board.\n[b]W[/b] arms a route; left-click water for each leg. [b]R[/b] radar, [b]P[/b] active sonar, [b]E[/b] emission control.\n[b]X[/b] fires the hooked ships' interceptors at the inbound weapons they hold, or right-click a detected inbound weapon; with manual missile defence the SAMs fire only then.\n")
	out.append(_section("CHART & CONTACT PICTURE"))
	out.append("[b]Wheel / pinch[/b] zooms. Right-drag, middle-drag or the arrow keys pan. The regional map at the bottom left pans and zooms the chart too.\n[b]Home[/b] fits the force. [b]F[/b] follows the hooked platform or contact. [b]C[/b] centres the shooter-target problem. [b]B[/b] draws a range circle.\n[b]N / Shift-N[/b] cycles priority contacts; [b].[/b] hooks the next own platform. [b]Tab[/b] switches NTDS and graphic symbols; [b]Shift-V / K / I[/b] velocity leaders, track numbers, tags.\n")
	out.append(_section("3D VIEW"))
	out.append("[b]T[/b] cycles the cameras: [b]F9[/b] tether, [b]F11[/b] fly-by, [b]F12[/b] action, [b]F8[/b] detached. [b]G[/b] swaps the chart and the 3D view. [b]F10[/b] gives the 3D view the whole window.\n")
	out.append(_section("BOARDS, AIR OPERATIONS AND SCREENS"))
	out.append("[b]A[/b] opens the status boards: orders, task group, track file and comms. [b]F3[/b] opens the launch dialog: light the LAUNCH lamps, then Ok; select an airborne airframe to return it to a carrier or airfield. [b]F7[/b] reference. [b]M[/b] missions, [b]Ctrl-E[/b] editor, [b]Ctrl-F10[/b] twice restarts.\n")
	out.append(_section("TIME & DISPLAY"))
	out.append("[b]Space[/b] pauses, or click TIME on the data display. [b]%s[/b] sets acceleration up to %d×, or click SCALE. Use real time when contacts close; accelerate when the force is on station.\n[b]F2[/b] symbol key · [b]F4[/b] sensor rings · [b]F5[/b] trails · [b]F6[/b] relief shading · [b]Ctrl-L / S / W[/b] lat-long, scale, radar coverage · [b]Ctrl-M[/b] sound.\n[b]H[/b] lists every key command. [b]Command-K / Control-K[/b] opens the searchable Actions palette." % ["1–%d" % SimClock.speeds().size() if SimClock.speeds().size() > 1 else "1", int(SimClock.ceiling())])


func _line(o: MissionObjective, loss := false) -> String:
	var mark := "[color=%s]COMPLETE[/color]" % UITheme.HEX_INK_GREEN if o.complete else "[color=%s]OPEN[/color]" % UITheme.HEX_INK_AMBER
	if not o.unlocked and not o.complete:
		mark = "[color=%s]PENDING[/color]" % UITheme.HEX_INK_FAINT
	if loss:
		mark = "[color=%s]TRIGGERED[/color]" % UITheme.HEX_INK_RED if o.complete else "[color=%s]AVOID[/color]" % UITheme.HEX_INK_FAINT
	var detail := o.progress(unit_manager, SimClock.sim_time) if unit_manager != null else ""
	return "[font_size=12][b]%s[/b][/font_size]   %s\n[color=%s][font_size=12]%s[/font_size][/color]" % [mark, _safe(o.text), UITheme.HEX_INK_FAINT, _safe(detail)]


func set_mode(pre_mission: bool) -> void:
	_pre_mission = pre_mission
	_start.text = "TAKE COMMAND" if pre_mission else "RESUME OPERATION"
	_eyebrow.text = "MISSION BRIEFING" if pre_mission else "MISSION STATUS"
	_apply_style()
	if pre_mission:
		_select_section("orders")
	refresh()


func focus_default() -> void:
	if visible and _start != null:
		_start.grab_focus()


static func _safe(value: String) -> String:
	return value.replace("[", "[lb]")


static func _section(value: String) -> String:
	return UITheme.section_bb(value, true)


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
	result.custom_minimum_size.y = 40
	if primary:
		result.theme_type_variation = "PrimaryButton"
	return result
