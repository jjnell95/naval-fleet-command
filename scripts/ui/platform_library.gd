class_name PlatformLibrary
extends PanelContainer
## Public catalogue and interactive art viewer; it never reads unknown scenario identities.
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
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	margin.add_child(v)
	var masthead := HBoxContainer.new()
	v.add_child(masthead)
	var brand := Label.new()
	brand.text = "FLEET RECOGNITION"
	brand.add_theme_font_override("font", UITheme.heading_font())
	brand.add_theme_font_size_override("font_size", 32)
	masthead.add_child(brand)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	masthead.add_child(spacer)
	var back := Button.new()
	back.text = "BACK  /  F7"
	back.pressed.connect(func() -> void: closed.emit())
	masthead.add_child(back)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 12)
	v.add_child(toolbar)
	var group := ButtonGroup.new()
	_platform_button = Button.new()
	_platform_button.text = "PLATFORMS  /  %02d" % DataDB.all_platforms().size()
	_platform_button.toggle_mode = true
	_platform_button.button_group = group
	_platform_button.button_pressed = true
	_platform_button.pressed.connect(func() -> void: _set_mode(false))
	toolbar.add_child(_platform_button)
	_weapon_button = Button.new()
	_weapon_button.text = "ORDNANCE  /  %02d" % DataDB.all_weapons().size()
	_weapon_button.toggle_mode = true
	_weapon_button.button_group = group
	_weapon_button.pressed.connect(func() -> void: _set_mode(true))
	toolbar.add_child(_weapon_button)
	_search = LineEdit.new()
	_search.placeholder_text = "Search class, aircraft, weapon, nation or role…"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(_filter)
	toolbar.add_child(_search)
	_domain_picker = OptionButton.new()
	_domain_picker.custom_minimum_size.x = 170
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
	_count = Label.new()
	_count.theme_type_variation = "HeaderLabel"
	left.add_child(_count)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.fixed_icon_size = Vector2i(48, 30)
	_list.add_theme_constant_override("v_separation", 14)
	_list.add_theme_font_size_override("font_size", 13)
	_list.item_selected.connect(_select)
	left.add_child(_list)
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 8)
	body.add_child(center)
	_eyebrow = Label.new()
	_eyebrow.theme_type_variation = "HeaderLabel"
	center.add_child(_eyebrow)
	_title = Label.new()
	_title.add_theme_font_override("font", UITheme.heading_font())
	_title.add_theme_font_size_override("font_size", 46)
	_title.clip_text = true
	center.add_child(_title)
	_subtitle = Label.new()
	_subtitle.theme_type_variation = "DimLabel"
	_subtitle.clip_text = true
	center.add_child(_subtitle)
	_stage = ModelStage.new()
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.custom_minimum_size = Vector2(260, 240)
	center.add_child(_stage)
	var view_bar := HBoxContainer.new()
	center.add_child(view_bar)
	for view in [["3D", "three_quarter"], ["PROFILE", "profile"], ["PLAN", "plan"]]:
		var button := Button.new()
		button.text = view[0]
		button.pressed.connect(func() -> void:
			_stage.set_view(view[1])
			_spin_button.set_pressed_no_signal(false))
		view_bar.add_child(button)
	_spin_button = Button.new()
	_spin_button.text = "AUTO ROTATE"
	_spin_button.toggle_mode = true
	_spin_button.toggled.connect(_stage.set_spin)
	view_bar.add_child(_spin_button)
	var hint := Label.new()
	hint.text = "  DRAG TO ORBIT  ·  SCROLL TO ZOOM"
	hint.theme_type_variation = "DimLabel"
	hint.add_theme_font_size_override("font_size", 10)
	hint.clip_text = true
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_bar.add_child(hint)
	_loadout_title = Label.new()
	_loadout_title.theme_type_variation = "HeaderLabel"
	center.add_child(_loadout_title)
	var belt := ScrollContainer.new()
	belt.custom_minimum_size.y = 110
	belt.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(belt)
	_loadout = HBoxContainer.new()
	_loadout.add_theme_constant_override("separation", 8)
	belt.add_child(_loadout)
	var dossier := PanelContainer.new()
	dossier.theme_type_variation = "CardPanel"
	dossier.custom_minimum_size.x = 282
	body.add_child(dossier)
	var dossier_v := VBoxContainer.new()
	dossier.add_child(dossier_v)
	var dh := Label.new()
	dh.text = "CAPABILITY DOSSIER"
	dh.theme_type_variation = "HeaderLabel"
	dossier_v.add_child(dh)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_theme_font_size_override("normal_font_size", 14)
	_detail.add_theme_font_size_override("bold_font_size", 14)
	dossier_v.add_child(_detail)
	var note := Label.new()
	note.text = "ILLUSTRATIVE CLASS MODELS   /   Public recognition features. Combat figures describe the game fit."
	note.theme_type_variation = "DimLabel"
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
		entries = [["All weapon types", "all"], ["Air defence", "sam"], ["Anti-ship", "asm"], ["Undersea", "torpedo"], ["Naval guns", "gun"], ["Close-in defence", "ciws"]]
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
		if (not query.is_empty() and query.to_lower() not in search_text.to_lower()) or (_domain != "all" and category != _domain):
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
	lines.append("[color=%s]LENGTH[/color]   %.1f m" % [UITheme.HEX_DIM, p.length_m])
	if p.aircraft_capacity > 0:
		lines.append("[color=%s]AVIATION[/color]   %s" % [UITheme.HEX_DIM, p.flight_facility().to_upper()])
		lines.append("%d game airframes" % p.aircraft_capacity)
	elif p.domain == "air":
		lines.append("[color=%s]BASING[/color]   %s" % [UITheme.HEX_DIM, p.flight_requirement().to_upper()])
	if p.vls_cells > 0:
		lines.append("[color=%s]VLS CELLS[/color]   %d / %d allocated" % [UITheme.HEX_DIM, p.occupied_vls_cells(), p.vls_cells])
	lines.append("\n[color=%s][b]SENSOR FIT[/b][/color]" % UITheme.HEX_ACCENT)
	for sid in p.sensor_ids:
		var sensor := DataDB.sensor(sid)
		if sensor != null:
			lines.append("• " + sensor.display_name)
	lines.append("\n[color=%s]%s[/color]" % [UITheme.HEX_DIM, p.service_note])
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
	_detail.text = "[font_size=18][b]%s[/b][/font_size]\n\n[color=%s]TARGET DOMAIN[/color]\n%s\n\n[color=%s]GUIDANCE MODEL[/color]\n%s\n\n[color=%s]GAME ENVELOPE[/color]\n%.1f–%.1f nm\n\n[color=%s]SYSTEM PROFILE[/color]\n%s\n\n[color=%s]Family recognition model. Variants and real configurations differ. These figures describe simulation tuning.[/color]" % [w.display_name, UITheme.HEX_ACCENT, ", ".join(w.target_types).to_upper(), UITheme.HEX_ACCENT, w.guidance.replace("_", " "), UITheme.HEX_ACCENT, w.min_range_nm, w.max_range_nm, UITheme.HEX_ACCENT, ("Gun mount / projectile" if w.type in ["gun", "ciws"] else w.profile.replace("_", " ")), UITheme.HEX_DIM]
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
	button.custom_minimum_size = Vector2(168, 92)
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
	image.custom_minimum_size.y = 45
	v.add_child(image)
	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = "%02d × %s" % [count, w.family.replace(" family", "")]
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	v.add_child(name_label)
