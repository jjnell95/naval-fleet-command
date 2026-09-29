class_name PlatformLibrary
extends PanelContainer
## Public catalogue and interactive art viewer; it never reads unknown scenario identities.
## The front end's REFERENCE: the dusk backdrop, a grey-metal panel, a starred-list look for the
## catalogue, the 3D stage in the three-line frame and the dossier in a text box.
signal closed()
var _list: ItemList
var _detail: RichTextLabel
var _stage: ModelStage
var _search: LineEdit
var _specs: Array = []
var _weapons := false
var _domain := "all"
var _domain_picker: OptionButton
var _title: Label
var _subtitle: Label
var _eyebrow: Label
var _count: Label
var _loadout: HBoxContainer
var _loadout_title: Label
var _platform_button: Button
var _weapon_button: Button
var _spin_button: Button

func _ready() -> void:
	theme_type_variation = "OverlayPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UITheme.backdrop())
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var sheet := PanelContainer.new()
	sheet.theme_type_variation = "MenuPanel"
	margin.add_child(sheet)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	sheet.add_child(v)
	var masthead := HBoxContainer.new()
	v.add_child(masthead)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 2)
	masthead.add_child(heading)
	var brand := UITheme.caption("Reference")
	brand.add_theme_font_size_override("font_size", 34)
	heading.add_child(brand)
	var kicker := Label.new()
	kicker.text = "Platforms and ordnance: recognition, fit and game envelope"
	kicker.theme_type_variation = "MenuLabel"
	heading.add_child(kicker)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	masthead.add_child(spacer)
	var back := Button.new()
	back.text = "CLOSE"
	back.theme_type_variation = "MenuBigButton"
	back.add_theme_font_size_override("font_size", 18)
	back.custom_minimum_size = Vector2(140, 40)
	back.tooltip_text = "Close the reference  [F7 / Esc]"
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void: closed.emit())
	masthead.add_child(back)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 12)
	v.add_child(toolbar)
	var group := ButtonGroup.new()
	var mode_frame := PanelContainer.new()
	mode_frame.theme_type_variation = "SegmentedPanel"
	toolbar.add_child(mode_frame)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 2)
	mode_frame.add_child(modes)
	_platform_button = Button.new()
	_platform_button.theme_type_variation = "SegmentButton"
	_platform_button.custom_minimum_size = Vector2(140, 32)
	_platform_button.text = "PLATFORMS  %d" % DataDB.all_platforms().size()
	_platform_button.toggle_mode = true
	_platform_button.button_group = group
	_platform_button.button_pressed = true
	_platform_button.pressed.connect(func() -> void: _set_mode(false))
	modes.add_child(_platform_button)
	_weapon_button = Button.new()
	_weapon_button.theme_type_variation = "SegmentButton"
	_weapon_button.custom_minimum_size = Vector2(140, 32)
	_weapon_button.text = "ORDNANCE  %d" % DataDB.all_weapons().size()
	_weapon_button.toggle_mode = true
	_weapon_button.button_group = group
	_weapon_button.pressed.connect(func() -> void: _set_mode(true))
	modes.add_child(_weapon_button)
	_search = LineEdit.new()
	_search.placeholder_text = "Search class, aircraft, weapon, nation or role"
	_search.right_icon = UIIcons.get_icon("search", 16, UITheme.INK_FAINT, 1.0)
	_search.custom_minimum_size.y = 30
	_search.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(_filter)
	toolbar.add_child(_search)
	_domain_picker = OptionButton.new()
	_domain_picker.custom_minimum_size = Vector2(190, 30)
	_domain_picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_domain_picker.item_selected.connect(func(index: int) -> void:
		_domain = _domain_picker.get_item_metadata(index)
		_filter(_search.text))
	toolbar.add_child(_domain_picker)
	_build_domains()
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	v.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 258
	body.add_child(left)
	_count = UITheme.caption("")
	_count.add_theme_font_size_override("font_size", 17)
	left.add_child(_count)
	_list = ItemList.new()
	_list.theme_type_variation = "MenuList"
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.fixed_icon_size = Vector2i(48, 30)
	_list.add_theme_constant_override("v_separation", 6)
	_list.add_theme_font_size_override("font_size", 13)
	_list.item_selected.connect(_select)
	left.add_child(_list)
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 8)
	body.add_child(center)
	_eyebrow = Label.new()
	_eyebrow.theme_type_variation = "HeaderLabel"
	_eyebrow.add_theme_color_override("font_color", UITheme.INK_BLUE)
	center.add_child(_eyebrow)
	_title = Label.new()
	_title.add_theme_font_override("font", UITheme.caption_font())
	_title.add_theme_font_size_override("font_size", 40)
	_title.add_theme_color_override("font_color", UITheme.MENU_INK)
	_title.clip_text = true
	center.add_child(_title)
	_subtitle = Label.new()
	_subtitle.theme_type_variation = "MenuLabel"
	_subtitle.clip_text = true
	center.add_child(_subtitle)
	var stage_frame := PanelContainer.new()
	stage_frame.theme_type_variation = "BevelFrame"
	stage_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(stage_frame)
	_stage = ModelStage.new()
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.custom_minimum_size = Vector2(260, 240)
	stage_frame.add_child(_stage)
	var view_bar := HBoxContainer.new()
	center.add_child(view_bar)
	var view_frame := PanelContainer.new()
	view_frame.theme_type_variation = "SegmentedPanel"
	view_bar.add_child(view_frame)
	var views := HBoxContainer.new()
	views.add_theme_constant_override("separation", 2)
	view_frame.add_child(views)
	for view in [["3D", "three_quarter"], ["PROFILE", "profile"], ["PLAN", "plan"]]:
		var button := Button.new()
		button.theme_type_variation = "TabButton"
		button.custom_minimum_size = Vector2(76, 28)
		button.text = view[0]
		button.pressed.connect(func() -> void:
			_stage.set_view(view[1])
			_spin_button.set_pressed_no_signal(false))
		views.add_child(button)
	_spin_button = Button.new()
	_spin_button.theme_type_variation = "QuietButton"
	_spin_button.text = "AUTO ROTATE"
	UIIcons.apply(_spin_button, "restart", 16)
	_spin_button.toggle_mode = true
	_spin_button.toggled.connect(_stage.set_spin)
	view_bar.add_child(_spin_button)
	var hint := Label.new()
	hint.text = "  DRAG TO ORBIT  ·  SCROLL TO ZOOM"
	hint.theme_type_variation = "MenuLabel"
	hint.add_theme_font_size_override("font_size", 11)
	hint.clip_text = true
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_bar.add_child(hint)
	_loadout_title = UITheme.caption("")
	_loadout_title.add_theme_font_size_override("font_size", 16)
	center.add_child(_loadout_title)
	var belt := ScrollContainer.new()
	belt.custom_minimum_size.y = 116
	belt.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(belt)
	_loadout = HBoxContainer.new()
	_loadout.add_theme_constant_override("separation", 8)
	belt.add_child(_loadout)
	var dossier := PanelContainer.new()
	dossier.theme_type_variation = "CardPanel"
	dossier.custom_minimum_size.x = 300
	body.add_child(dossier)
	var dossier_v := VBoxContainer.new()
	dossier.add_child(dossier_v)
	var dh := Label.new()
	dh.text = "CAPABILITY DOSSIER"
	dh.add_theme_color_override("font_color", UITheme.INK_BLUE)
	dh.add_theme_font_override("font", UITheme.data_font())
	dossier_v.add_child(dh)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_theme_font_size_override("normal_font_size", 14)
	_detail.add_theme_font_size_override("bold_font_size", 14)
	dossier_v.add_child(_detail)
	var note := Label.new()
	note.text = "Illustrative class models  ·  public recognition features  ·  combat figures describe the game fit"
	note.theme_type_variation = "MenuLabel"
	note.add_theme_font_size_override("font_size", 11)
	v.add_child(note)
	_filter("")


func focus_default() -> void:
	if _search != null:
		_search.grab_focus()

func _build_domains() -> void:
	_domain_picker.clear()
	var entries := [["All domains", "all"], ["Surface ships", "surface"], ["Aircraft", "air"], ["Submarines", "subsurface"], ["Shore stations", "land"]]
	if _weapons:
		entries = [["All weapon types", "all"], ["Air defence / AAM", "air"], ["Anti-ship", "surface"], ["ASW", "subsurface"], ["Land strike", "land"], ["Guns / CIWS", "gun"]]
	for entry in entries:
		_domain_picker.add_item(entry[0])
		_domain_picker.set_item_metadata(_domain_picker.item_count - 1, entry[1])
	_domain = "all"

func _set_mode(weapons: bool) -> void:
	if _weapons != weapons:
		_search.text = ""
	_weapons = weapons
	_platform_button.button_pressed = not weapons
	_weapon_button.button_pressed = weapons
	_build_domains()
	_filter(_search.text)

func inspect(asset_id: String, weapon := false) -> void:
	_search.text = ""
	_set_mode(weapon)
	for i in _specs.size():
		if _specs[i].id == asset_id:
			_list.select(i)
			_list.ensure_current_is_visible()
			_select(i)
			return

func _filter(query: String) -> void:
	_list.clear()
	_specs.clear()
	var records := DataDB.all_weapons() if _weapons else DataDB.all_platforms()
	for p in records:
		var search_text: String = p.display_name + " " + (p.family if _weapons else p.nation + " " + p.role)
		var category: String = p.type if _weapons else p.domain
		if (not query.is_empty() and query.to_lower() not in search_text.to_lower()) or (_domain != "all" and (not WeaponPresentation.matches(p, _domain) if _weapons else category != _domain)):
			continue
		_specs.append(p)
		_list.add_item(p.family if _weapons else p.short_name, PlatformArt.thumbnail(p.id, _weapons))
		_list.set_item_tooltip(_list.item_count - 1, p.display_name)
	_count.text = "%02d %s" % [_specs.size(), "WEAPON SYSTEMS" if _weapons else "PLATFORM CLASSES"]
	if not _specs.is_empty():
		_list.select(0)
		_select(0)
	else:
		_stage.show_asset("", _weapons)
		_title.text = "NO MATCHES"
		_subtitle.text = "Try another search or domain."
		_eyebrow.text = "RECOGNITION LIBRARY"
		_detail.text = ""
		_clear_loadout()
		_loadout_title.text = ""

func _clear_loadout() -> void:
	for child in _loadout.get_children():
		_loadout.remove_child(child)
		child.queue_free()

func _select(index: int) -> void:
	if index < 0 or index >= _specs.size():
		return
	var p = _specs[index]
	_stage.show_asset(p.id, _weapons)
	_spin_button.set_pressed_no_signal(false)
	_clear_loadout()
	if _weapons:
		_show_weapon(p)
		return
	_eyebrow.text = "%s  /  %s  /  %s" % [p.nation, p.domain.to_upper(), p.category.to_upper()]
	_title.text = p.short_name.to_upper()
	_subtitle.text = p.display_name
	var lines := PackedStringArray()
	lines.append("[font_size=18][b]%s[/b][/font_size]\n" % p.role)
	lines.append("[color=%s]LENGTH[/color]   %.1f m" % [UITheme.HEX_INK_DIM, p.length_m])
	if p.aircraft_capacity > 0:
		lines.append("[color=%s]AVIATION[/color]   %s" % [UITheme.HEX_INK_DIM, p.flight_facility().to_upper()])
		lines.append("%d game airframes" % p.aircraft_capacity)
	elif p.domain == "air":
		lines.append("[color=%s]BASING[/color]   %s" % [UITheme.HEX_INK_DIM, p.flight_requirement().to_upper()])
	if p.vls_cells > 0:
		lines.append("[color=%s]VLS CELLS[/color]   %d / %d allocated" % [UITheme.HEX_INK_DIM, p.occupied_vls_cells(), p.vls_cells])
	lines.append("\n" + UITheme.section_bb("Sensor fit", true))
	for sid in p.sensor_ids:
		var sensor := DataDB.sensor(sid)
		if sensor != null:
			lines.append("• " + sensor.display_name)
	lines.append("\n[color=%s]%s[/color]" % [UITheme.HEX_INK_DIM, p.service_note])
	_detail.text = "\n".join(lines)
	_loadout_title.text = "FITTED ORDNANCE  /  SELECT TO INSPECT"
	for wid in p.weapon_loadout:
		var w := DataDB.weapon(wid)
		if w != null:
			_loadout_card(w, int(p.weapon_loadout[wid]))
	if p.weapon_loadout.is_empty():
		_loadout_title.text = "UNARMED PLATFORM"

func _show_weapon(w: WeaponSpec) -> void:
	_eyebrow.text = "ORDNANCE  /  %s  /  %s" % [w.type.to_upper(), ("GUN MOUNT" if w.type in ["gun", "ciws"] else w.profile.replace("_", " ").to_upper())]
	_title.text = w.family.to_upper()
	_subtitle.text = w.display_name
	_detail.text = "[font_size=18][b]%s[/b][/font_size]\n\n[font_size=11][color=%s]TARGET DOMAIN[/color][/font_size]\n%s\n\n[font_size=11][color=%s]GUIDANCE MODEL[/color][/font_size]\n%s\n\n[font_size=11][color=%s]GAME ENVELOPE[/color][/font_size]\n%.1f–%.1f nm\n\n[font_size=11][color=%s]SYSTEM PROFILE[/color][/font_size]\n%s\n\n[color=%s]Family recognition model. Variants and real configurations differ. These figures describe simulation tuning.[/color]" % [w.display_name, UITheme.HEX_INK_BLUE, ", ".join(w.target_types).to_upper(), UITheme.HEX_INK_BLUE, w.guidance.replace("_", " "), UITheme.HEX_INK_BLUE, w.min_range_nm, w.max_range_nm, UITheme.HEX_INK_BLUE, ("Gun mount / projectile" if w.type in ["gun", "ciws"] else w.profile.replace("_", " ")), UITheme.HEX_INK_DIM]
	_loadout_title.text = "CARRIED BY  /  SELECT TO INSPECT"
	for p: PlatformSpec in DataDB.all_platforms():
		if not p.weapon_loadout.has(w.id):
			continue
		var button := Button.new()
		button.text = p.short_name
		button.icon = PlatformArt.thumbnail(p.id)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 90)
		button.custom_minimum_size = Vector2(170, 85)
		button.pressed.connect(func() -> void: inspect(p.id))
		_loadout.add_child(button)

func _loadout_card(w: WeaponSpec, count: int) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(168, 100)
	button.tooltip_text = "Inspect " + w.display_name
	button.pressed.connect(func() -> void: inspect(w.id, true))
	_loadout.add_child(button)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 9
	v.offset_right = -9
	v.offset_top = 4
	button.add_child(v)
	var image := TextureRect.new()
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.texture = PlatformArt.thumbnail(w.id, true)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size.y = 42
	v.add_child(image)
	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = "%02d × %s" % [count, w.family.replace(" family", "")]
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Two lines, then an ellipsis: centred text that simply clipped lost both of its ends.
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.max_lines_visible = 2
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size.x = 150
	v.add_child(name_label)
