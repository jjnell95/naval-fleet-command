class_name ScenarioMenu
extends PanelContainer
## Full-screen mission selector. Built from ScenarioIndex, so dropping a new JSON file into
## data/scenarios is enough to make it appear here.

signal scenario_chosen(path: String)
signal dismissed()
signal editor_requested()

var _list: ItemList
var _detail: RichTextLabel
var _preview: ScenarioPreview
var _play: Button
var _close: Button
var _entries: Array = []


func _ready() -> void:
	theme_type_variation = "OverlayPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_top", 44)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	var eyebrow := Label.new()
	eyebrow.text = "NORTH ATLANTIC   ·   FICTIONAL OPERATIONS   ·   AEGIS COMMAND"
	eyebrow.theme_type_variation = "HeaderLabel"
	v.add_child(eyebrow)
	var title := Label.new()
	title.text = "NAVAL FLEET COMMAND"
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color.WHITE)
	v.add_child(title)
	var sub := Label.new()
	sub.text = "Build the picture. Manage the shield. Decide when to shoot."
	sub.theme_type_variation = "DimLabel"
	sub.add_theme_font_size_override("font_size", 15)
	v.add_child(sub)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 360
	left.add_theme_constant_override("separation", 6)
	body.add_child(left)
	var lh := Label.new()
	lh.text = "MISSIONS"
	lh.theme_type_variation = "HeaderLabel"
	left.add_child(lh)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.focus_mode = Control.FOCUS_NONE
	_list.add_theme_font_size_override("font_size", 14)
	_list.add_theme_constant_override("v_separation", 12)
	_list.item_selected.connect(_on_selected)
	_list.item_activated.connect(func(_i: int) -> void: _on_play())
	left.add_child(_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	body.add_child(right)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(top)
	var card := PanelContainer.new()
	card.theme_type_variation = "CardPanel"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top.add_child(card)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.fit_content = false
	_detail.scroll_active = true
	_detail.add_theme_font_size_override("normal_font_size", 15)
	_detail.add_theme_font_size_override("bold_font_size", 15)
	card.add_child(_detail)
	_preview = ScenarioPreview.new()
	_preview.custom_minimum_size = Vector2(300, 300)
	_preview.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(_preview)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	v.add_child(buttons)
	_play = Button.new()
	_play.text = "BRIEF AND DEPLOY"
	_play.theme_type_variation = "PrimaryButton"
	_play.focus_mode = Control.FOCUS_NONE
	_play.pressed.connect(_on_play)
	buttons.add_child(_play)
	var edit := Button.new()
	edit.text = "SCENARIO EDITOR  F8"
	edit.focus_mode = Control.FOCUS_NONE
	edit.pressed.connect(func() -> void: editor_requested.emit())
	buttons.add_child(edit)
	_close = Button.new()
	_close.text = "BACK TO THE PICTURE"
	_close.focus_mode = Control.FOCUS_NONE
	_close.pressed.connect(func() -> void: dismissed.emit())
	buttons.add_child(_close)
	var note := Label.new()
	note.text = "     Desktop keyboard and mouse. Public platform families; every combat number is a gameplay estimate."
	note.theme_type_variation = "DimLabel"
	note.clip_text = true
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(note)

	refresh()


func refresh(current_path := "") -> void:
	_entries = ScenarioIndex.list_all()
	_list.clear()
	var select := 0
	for i in _entries.size():
		var e: Dictionary = _entries[i]
		_list.add_item("%02d   %s%s" % [i + 1, e["name"], "   · custom" if e["custom"] else ""])
		if e["path"] == current_path:
			select = i
	if not _entries.is_empty():
		_list.select(select)
		_on_selected(select)


func allow_back(can_go_back: bool) -> void:
	_close.visible = can_go_back


func _on_selected(i: int) -> void:
	if i < 0 or i >= _entries.size():
		return
	var e: Dictionary = _entries[i]
	var sc := ScenarioLoader.load_file(e["path"])
	_preview.set_scenario(sc)
	var own := 0
	var air := 0
	var subs := 0
	var player: String = sc.get("player_faction", "BLUE")
	for ud in sc.get("units", []):
		if ud.get("faction", "") != player:
			continue
		own += 1
		var spec := DataDB.platform(ud.get("platform", ""))
		if spec != null and spec.domain == "air":
			air += 1
		elif spec != null and spec.domain == "subsurface":
			subs += 1
	var env: Dictionary = sc.get("environment", {})
	var sea := int(env.get("sea_state", 0))
	var coasts: int = sc.get("terrain", {}).get("land", []).size()
	var lines := PackedStringArray()
	lines.append("[b][color=#ffffff]%s[/color][/b]" % e["name"])
	var water := "open ocean" if coasts == 0 else ("coastal · %d landmass%s" % [coasts, "" if coasts == 1 else "es"])
	lines.append("[color=%s]%d own units · %d aircraft · %d submarine%s · sea state %d (%s) · %s[/color]\n" % [UITheme.HEX_DIM, own, air, subs, "" if subs == 1 else "s", sea, Detection.SEA_STATE_NAMES[clampi(sea, 0, 6)], water])
	lines.append("[color=%s][b]FORCES[/b][/color]" % UITheme.HEX_ACCENT)
	lines.append("%s\n" % e["forces"])
	lines.append("[color=%s][b]SITUATION[/b][/color]" % UITheme.HEX_ACCENT)
	lines.append(e["description"])
	var obj: Dictionary = sc.get("objectives", {})
	if obj.has("text"):
		lines.append("\n[color=%s][b]MISSION[/b][/color]" % UITheme.HEX_ACCENT)
		lines.append(str(obj["text"]))
	_detail.text = "\n".join(lines)


func _on_play() -> void:
	var i := _list.get_selected_items()
	if i.is_empty():
		return
	SoundFx.play("click")
	scenario_chosen.emit(_entries[i[0]]["path"])
