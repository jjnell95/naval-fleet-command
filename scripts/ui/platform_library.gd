class_name PlatformLibrary
extends PanelContainer
## Public recognition database; never exposes the identity of an unknown scenario track.
signal closed()
var _list: ItemList
var _detail: RichTextLabel
var _portrait: PlatformPortrait
var _search: LineEdit
var _specs: Array = []

func _ready() -> void:
	theme_type_variation = "OverlayPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 38)
	add_child(margin)
	var v := VBoxContainer.new()
	margin.add_child(v)
	var eyebrow := Label.new()
	eyebrow.text = "FLEET INTELLIGENCE  /  PUBLIC RECOGNITION LIBRARY"
	eyebrow.theme_type_variation = "HeaderLabel"
	v.add_child(eyebrow)
	var title := Label.new()
	title.text = "Know the platforms. Understand their roles."
	title.add_theme_font_size_override("font_size", 30)
	v.add_child(title)
	_search = LineEdit.new()
	_search.placeholder_text = "Search class, aircraft, nation or role…"
	_search.text_changed.connect(_filter)
	v.add_child(_search)
	var h := HBoxContainer.new()
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 24)
	v.add_child(h)
	_list = ItemList.new()
	_list.custom_minimum_size.x = 380
	_list.item_selected.connect(_select)
	h.add_child(_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	_portrait = PlatformPortrait.new()
	_portrait.custom_minimum_size.y = 240
	right.add_child(_portrait)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_theme_font_size_override("normal_font_size", 16)
	right.add_child(_detail)
	var close := Button.new()
	close.text = "RETURN TO COMMAND  /  F7"
	close.theme_type_variation = "PrimaryButton"
	close.pressed.connect(func() -> void: closed.emit())
	v.add_child(close)
	_filter("")

func _filter(query: String) -> void:
	_list.clear()
	_specs.clear()
	for p: PlatformSpec in DataDB.all_platforms():
		if query.to_lower() not in (p.display_name + " " + p.nation + " " + p.role).to_lower():
			continue
		_specs.append(p)
		_list.add_item("%s  ·  %s" % [p.nation, p.display_name])
	if not _specs.is_empty():
		_list.select(0)
		_select(0)
	else:
		_portrait.spec_override = null
		_detail.text = "No matching platforms."

func _select(index: int) -> void:
	var p: PlatformSpec = _specs[index]
	_portrait.spec_override = p
	var lines := PackedStringArray()
	lines.append("[font_size=24][b]%s[/b][/font_size]" % p.display_name)
	lines.append("[color=%s]%s[/color]\n" % [UITheme.HEX_ACCENT, p.role])
	lines.append("%s  /  %s  /  %.1f m" % [p.nation, p.domain.to_upper(), p.length_m])
	if p.aircraft_capacity > 0:
		lines.append("Aviation: %s • %d game airframes" % [p.flight_facility().to_upper(), p.aircraft_capacity])
	elif p.domain == "air":
		lines.append("Basing: %s" % p.flight_requirement().to_upper())
	if p.vls_cells > 0:
		lines.append("VLS: %d physical cells • %d allocated in this fit" % [p.vls_cells, p.occupied_vls_cells()])
	lines.append("\n[b]SENSOR FIT[/b]")
	for sid in p.sensor_ids:
		var sensor := DataDB.sensor(sid)
		if sensor != null:
			lines.append("  %s" % sensor.display_name)
	lines.append("\n[b]SCENARIO LOADOUT[/b]")
	if p.weapon_loadout.is_empty():
		lines.append("  Unarmed")
	for wid in p.weapon_loadout:
		var w := DataDB.weapon(wid)
		if w != null:
			lines.append("  %d × %s" % [p.weapon_loadout[wid], w.display_name])
	lines.append("\n[color=%s]%s\n\nCombat numbers are game estimates. Configuration and availability vary by hull and era. See docs/REALISM.md for sources.[/color]" % [UITheme.HEX_DIM, p.service_note])
	_detail.text = "\n".join(lines)
