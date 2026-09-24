class_name ScenarioMenu
extends PanelContainer
## Operations desk. Scenario files supply the briefing and period, including custom missions.

signal scenario_chosen(path: String)
signal dismissed()
signal editor_requested()
signal library_requested()

const RowList = preload("res://scripts/ui/tactical_row_list.gd")

var _list: RowList
var _detail: RichTextLabel
var _preview: ScenarioPreview
var _play: Button
var _close: Button
var _entries: Array = []
var _all_entries: Array = []
var _era := "cold_war"
var _filters: Dictionary = {}
var _mission_title: Label
var _mission_meta: Label
var _intent: Label
var _count: Label
var _portrait: PlatformPortrait
var _ship_caption: Label
var _margin: MarginContainer
var _left: VBoxContainer
var _rail: VBoxContainer
var _title: Label
var _initial_refresh := true
var _layout: VBoxContainer
var _subtitle: Label
var _mast_note: Label


func _ready() -> void:
	theme_type_variation = "OverlayPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_margin = MarginContainer.new()
	add_child(_margin)
	var v := VBoxContainer.new()
	_layout = v
	v.add_theme_constant_override("separation", 18)
	_margin.add_child(v)

	var masthead := HBoxContainer.new()
	masthead.add_theme_constant_override("separation", 18)
	v.add_child(masthead)
	var mark := TextureRect.new()
	mark.texture = UIIcons.get_icon("mark", 54, UITheme.COL_BRASS)
	mark.custom_minimum_size = Vector2(54, 54)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	masthead.add_child(mark)
	var brand := VBoxContainer.new()
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.add_theme_constant_override("separation", 0)
	masthead.add_child(brand)
	var eyebrow := UITheme.eyebrow("Cold War / 1990  ·  North Atlantic & Northern Europe")
	eyebrow.add_theme_color_override("font_color", UITheme.COL_BRASS)
	brand.add_child(eyebrow)
	_title = _label("NAVAL FLEET COMMAND", 46, Color.WHITE)
	_title.add_theme_font_override("font", UITheme.heading_font())
	brand.add_child(_title)
	_subtitle = _label("Build the picture. Protect the force. Control the sea.", 16, UITheme.COL_DIM)
	brand.add_child(_subtitle)
	var mast_note := _label("Choose an operation, read the orders,\nthen take command. The clock waits for you.", 13, UITheme.COL_MUTED)
	mast_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mast_note.size_flags_vertical = Control.SIZE_SHRINK_END
	masthead.add_child(mast_note)
	_mast_note = mast_note
	var rule := ColorRect.new()
	rule.color = Color(UITheme.COL_BRASS, 0.45)
	rule.custom_minimum_size.y = 1
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(rule)

	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 12)
	v.add_child(filter_row)
	var filter_frame := PanelContainer.new()
	filter_frame.theme_type_variation = "SegmentedPanel"
	filter_row.add_child(filter_frame)
	var segments := HBoxContainer.new()
	segments.add_theme_constant_override("separation", 2)
	filter_frame.add_child(segments)
	for entry in [["cold_war", "COLD WAR 1990"], ["modern", "MODERN"], ["all", "ALL OPERATIONS"]]:
		var key: String = entry[0]
		var button := _button(entry[1])
		button.theme_type_variation = "SegmentButton"
		button.custom_minimum_size = Vector2(128, 32)
		button.add_theme_font_size_override("font_size", 12)
		button.toggle_mode = true
		button.pressed.connect(func() -> void: _set_era(key))
		segments.add_child(button)
		_filters[key] = button
	_count = UITheme.eyebrow("")
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	filter_row.add_child(_count)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	_left = VBoxContainer.new()
	_left.add_theme_constant_override("separation", 10)
	body.add_child(_left)
	_left.add_child(UITheme.eyebrow("Available operations"))
	_list = RowList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.focus_mode = Control.FOCUS_ALL
	_list.accessibility_name = "Available operations"
	_list.accessibility_description = "Choose a mission to read its task and first orders. Enter opens the briefing."
	_list.max_columns = 1
	_list.max_text_lines = 2
	_list.configure_rows(16, 12, 52)
	_list.add_theme_font_size_override("font_size", 16)
	_list.add_theme_constant_override("v_separation", 12)
	_list.add_theme_constant_override("line_separation", 8)
	_list.item_selected.connect(_on_selected)
	_list.item_activated.connect(func(_i: int) -> void: _on_play())
	_left.add_child(_list)
	var list_hint := _label("↑ ↓  choose     Enter  read the briefing", 12, UITheme.COL_MUTED)
	_left.add_child(list_hint)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 16)
	body.add_child(right)
	var operation_card := _card()
	right.add_child(operation_card)
	var operation := VBoxContainer.new()
	operation.add_theme_constant_override("separation", 8)
	operation_card.add_child(operation)
	_mission_title = _label("", 32, Color.WHITE)
	_mission_title.add_theme_font_override("font", UITheme.heading_font())
	_mission_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	operation.add_child(_mission_title)
	_mission_meta = _label("", 12, UITheme.COL_BRASS)
	_mission_meta.add_theme_font_override("font", UITheme.eyebrow_font())
	_mission_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	operation.add_child(_mission_meta)
	_intent = _label("", 19, UITheme.COL_TEXT)
	_intent.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intent.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	operation.add_child(_intent)

	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	right.add_child(content)
	var detail_card := _card()
	detail_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(detail_card)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.fit_content = false
	_detail.scroll_active = true
	_detail.focus_mode = Control.FOCUS_ALL
	_detail.accessibility_name = "Selected operation plan"
	_detail.add_theme_font_size_override("normal_font_size", 15)
	_detail.add_theme_font_size_override("bold_font_size", 15)
	_detail.add_theme_constant_override("line_separation", 6)
	detail_card.add_child(_detail)
	_rail = VBoxContainer.new()
	_rail.add_theme_constant_override("separation", 10)
	content.add_child(_rail)
	_preview = ScenarioPreview.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rail.add_child(_preview)
	_portrait = PlatformPortrait.new()
	_portrait.show_captions = false
	_rail.add_child(_portrait)
	_ship_caption = _label("", 13, UITheme.COL_DIM)
	_ship_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rail.add_child(_ship_caption)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	v.add_child(buttons)
	_play = _button("READ BRIEFING", true)
	_play.custom_minimum_size.x = 250
	_play.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UIIcons.apply(_play, "arrow_right", 18)
	_play.pressed.connect(_on_play)
	buttons.add_child(_play)
	var edit := _button("SCENARIO EDITOR")
	edit.tooltip_text = "Build or modify a mission  [F8]"
	UIIcons.apply(edit, "route", 18)
	edit.pressed.connect(func() -> void: editor_requested.emit())
	buttons.add_child(edit)
	var library := _button("FLEET & ORDNANCE")
	library.tooltip_text = "Recognition library of every platform and weapon  [F7]"
	UIIcons.apply(library, "library", 18)
	library.pressed.connect(func() -> void: library_requested.emit())
	buttons.add_child(library)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	_close = _button("RETURN TO CHART")
	_close.theme_type_variation = "QuietButton"
	_close.tooltip_text = "Close this desk and return to the operation already loaded  [Esc]"
	UIIcons.apply(_close, "close", 16)
	_close.pressed.connect(func() -> void: dismissed.emit())
	buttons.add_child(_close)
	var note := _label("Historical equipment, fictional operations. Performance and detection values are simulation estimates.", 12, UITheme.COL_FAINT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	resized.connect(_apply_layout)
	_apply_layout()
	refresh()


func _apply_layout() -> void:
	if _margin == null:
		return
	var viewport_size := get_viewport_rect().size
	var compact := viewport_size.x < 1300.0 or viewport_size.y < 850.0
	var edge := 22 if compact else 40
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, edge)
	_left.custom_minimum_size.x = 286 if compact else 356
	_list.fixed_column_width = 260 if compact else 330
	_rail.custom_minimum_size.x = 236 if compact else 318
	_preview.custom_minimum_size = Vector2(236 if compact else 318, 170 if compact else 220)
	_portrait.custom_minimum_size.y = 130
	_portrait.visible = not compact and _portrait.spec_override != null
	_ship_caption.visible = not compact
	_subtitle.visible = not compact
	_mast_note.visible = not compact
	_layout.add_theme_constant_override("separation", 12 if compact else 16)
	_intent.max_lines_visible = 2 if compact else 3
	_intent.add_theme_font_size_override("font_size", 18 if compact else 20)
	_mission_title.add_theme_font_size_override("font_size", 27 if compact else 32)
	_title.add_theme_font_size_override("font_size", 34 if compact else 46)


func refresh(current_path := "") -> void:
	_all_entries = ScenarioIndex.list_all()
	# First visit opens the Cold War shelf. Reopening a mission keeps its era and selection.
	if current_path != "":
		for entry: Dictionary in _all_entries:
			if entry["path"] == current_path:
				if not _initial_refresh:
					_era = "all" if entry["custom"] else ("cold_war" if _is_cold_war(entry) else "modern")
				break
	var has_cold_war := false
	for entry: Dictionary in _all_entries:
		has_cold_war = has_cold_war or _is_cold_war(entry)
	if _initial_refresh and not has_cold_war:
		_era = "all"
	_initial_refresh = false
	_populate(current_path)


func _set_era(era: String) -> void:
	_era = era
	_populate()


func _populate(current_path := "") -> void:
	_entries.clear()
	_list.clear_rows()
	for key: String in _filters:
		var button: Button = _filters[key]
		button.set_pressed_no_signal(key == _era)
	for entry: Dictionary in _all_entries:
		if _era == "cold_war" and not _is_cold_war(entry):
			continue
		if _era == "modern" and (_is_cold_war(entry) or entry["custom"]):
			continue
		_entries.append(entry)
	var selected := 0
	for i in _entries.size():
		var e: Dictionary = _entries[i]
		var period := "CUSTOM" if e["custom"] else (str(e["year"]) if int(e["year"]) > 0 else "MODERN")
		var level: String = str(e.get("difficulty", "Open command"))
		var mission_name := str(e["name"]).replace(" — ", " / ")
		_list.add_row("%02d  %s" % [i + 1, mission_name], "%s  ·  %s" % [period, level])
		_list.set_item_tooltip(i, "%s\n%s\n%s" % [e["name"], e.get("role", "Task force command"), e["description"]])
		if e["path"] == current_path:
			selected = i
	_count.text = "%d OPERATIONS  /  %s" % [_entries.size(), "1990" if _era == "cold_war" else ("CONTEMPORARY" if _era == "modern" else "ALL ERAS + CUSTOM")]
	_play.disabled = _entries.is_empty()
	if not _entries.is_empty():
		_list.select(selected)
		_on_selected(selected)
	else:
		_mission_title.text = "NO OPERATIONS AVAILABLE"
		_mission_meta.text = "Select another era or build a custom mission."
		_intent.text = ""
		_detail.text = "Custom missions appear under All operations."
		_preview.set_scenario({})
		_portrait.spec_override = null
		_portrait.visible = false
		_ship_caption.text = ""


static func _is_cold_war(entry: Dictionary) -> bool:
	return int(entry.get("year", 0)) == 1990


func allow_back(can_go_back: bool) -> void:
	_close.visible = can_go_back


func focus_default() -> void:
	if visible and _list != null:
		_list.grab_focus()


func _on_selected(i: int) -> void:
	if i < 0 or i >= _entries.size():
		return
	var e: Dictionary = _entries[i]
	var sc := ScenarioLoader.load_file(e["path"])
	_preview.set_scenario(sc)
	_mission_title.text = str(e["name"]).replace(" — ", " / ")
	var details := PackedStringArray()
	var date := str(sc.get("start_time_utc", ""))
	if date.length() >= 10:
		details.append(date.substr(0, 10))
	details.append(str(e.get("role", "Task force command")))
	details.append(str(e.get("difficulty", "Open command")))
	var duration := int(e.get("duration_minutes", 0))
	if duration > 0:
		details.append("about %d min" % duration)
	_mission_meta.text = "  ·  ".join(details).to_upper()
	var objective: Dictionary = sc.get("objectives", {})
	_intent.text = sc.get("commander_intent", objective.get("text", "Read the situation and establish your command priorities."))
	var lines := PackedStringArray()
	var first_orders: Array = sc.get("first_orders", [])
	if not first_orders.is_empty():
		lines.append(_section("YOUR FIRST ORDERS"))
		for n in first_orders.size():
			lines.append("[color=%s][b]%02d[/b][/color]   %s" % [UITheme.HEX_BRASS, n + 1, _safe(str(first_orders[n]))])
		lines.append("")
	lines.append(_section("FORCE UNDER YOUR COMMAND"))
	lines.append(_safe(str(e["forces"])) + "\n")
	var own_surface := 0
	var air := 0
	var subs := 0
	var representative: PlatformSpec = null
	var ship_name := ""
	var player: String = sc.get("player_faction", "BLUE")
	for ud: Dictionary in sc.get("units", []):
		if ud.get("faction", "") != player:
			continue
		var spec := DataDB.platform(ud.get("platform", ""))
		if spec == null:
			continue
		if spec.domain == "air":
			air += 1
		elif spec.domain == "subsurface":
			subs += 1
		elif spec.domain == "surface":
			own_surface += 1
			if representative == null:
				representative = spec
				ship_name = ud.get("callsign", spec.short_name)
		if spec.aircraft_capacity > 0:
			var capacity := spec.aircraft_capacity
			for placed: Dictionary in sc.get("units", []):
				if placed.get("home", "") == ud.get("callsign", spec.short_name):
					capacity -= 1
			var wing: Array = ud.get("air_wing", ScenarioLoader._default_wing(spec))
			for entry: Dictionary in wing:
				var aircraft := DataDB.platform(str(entry.get("platform", "")))
				if aircraft != null and spec.can_operate(aircraft):
					var added := mini(maxi(int(entry.get("count", 1)), 0), maxi(capacity, 0))
					air += added
					capacity -= added
	_portrait.spec_override = representative
	_portrait.visible = representative != null
	_ship_caption.text = "%s\n%s" % [ship_name, representative.short_name] if representative != null else ""
	lines.append("[color=%s]%d surface  ·  %d submarine%s  ·  %d aircraft[/color]\n" % [UITheme.HEX_MUTED, own_surface, subs, "" if subs == 1 else "s", air])
	lines.append(_section("SITUATION"))
	lines.append(_safe(str(e["description"])) + "\n")
	if sc.has("learning"):
		lines.append(_section("COMMAND CHALLENGE"))
		lines.append(_safe(str(sc["learning"])) + "\n")
	if sc.has("historical_note"):
		lines.append(_section("HISTORICAL CONTEXT"))
		lines.append("[color=%s]%s[/color]" % [UITheme.HEX_DIM, _safe(str(sc["historical_note"]))])
	elif sc.has("force_note"):
		lines.append("[color=%s]%s[/color]" % [UITheme.HEX_DIM, _safe(str(sc["force_note"]))])
	_detail.text = "\n".join(lines)
	_detail.scroll_to_line(0)
	_apply_layout()


func _on_play() -> void:
	var selected := _list.get_selected_items()
	if selected.is_empty() or selected[0] >= _entries.size():
		return
	SoundFx.play("click")
	scenario_chosen.emit(_entries[selected[0]]["path"])


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


static func _card() -> PanelContainer:
	var result := PanelContainer.new()
	result.theme_type_variation = "CardPanel"
	return result
