class_name PlatformLibrary
extends PanelContainer
## Public catalogue and interactive art viewer; it never reads unknown scenario identities.
## The front end's REFERENCE: the dusk backdrop, a grey-metal panel, a starred-list look for the
## catalogue, the 3D stage in the three-line frame and the dossier in a text box.
signal closed()
const ORBIT_HINT := "DRAG TO ORBIT  ·  SCROLL TO ZOOM"
const FACILITY_NAMES := {
	"airfield": "Airfield",
	"helicopter": "Helicopter deck",
	"stovl": "STOVL deck",
	"stobar": "Ski-jump carrier",
	"catobar": "Catapult carrier"
}
## The order the list runs in within a nation, and the words for each kind of weapon, by which
## the ordnance list is grouped and its dossier says what a round is for.
const DOMAIN_ORDER := ["surface", "subsurface", "air", "land"]
const WEAPON_TYPES := {
	"asm": "Anti-ship and strike missiles",
	"sam": "Surface-to-air missiles",
	"aam": "Air-to-air missiles",
	"torpedo": "Torpedoes",
	"asw_rocket": "Anti-submarine rockets",
	"bomb": "Bombs",
	"gun": "Guns",
	"ciws": "Close-in weapon systems",
}
## A seeker's label in the data, said in words.
const SEEKERS := {
	"acoustic_homing": "acoustic homing, active and passive sonar",
	"active_radar": "active radar",
	"active_radar_homing": "active radar homing",
	"autonomous_imaging_infrared": "imaging infrared, autonomous target choice",
	"ballistic": "none: a ballistic round on a computed trajectory",
	"fire_control_directed": "none: aimed by the ship's fire-control radar",
	"gps_inertial": "satellite-aided inertial navigation to a fixed point",
	"imaging_infrared": "imaging infrared",
	"inertial_active": "inertial midcourse, active radar terminal homing",
	"inertial_delivery": "inertial flight to the drop point, then the payload's own seeker",
	"inertial_electro_optical": "inertial midcourse, electro-optical terminal homing",
	"inertial_infrared_hit_to_kill": "inertial midcourse, infrared homing to a direct hit",
	"inertial_terminal": "inertial midcourse, terminal seeker",
	"inertial_terminal_seeker": "inertial midcourse, terminal seeker",
	"inertial_terrain_matching": "inertial with terrain matching over land",
	"infrared": "infrared",
	"infrared_homing": "infrared homing",
	"laser_abstract": "laser guidance",
	"passive_radar_homing": "passive radar homing on the target's emissions",
	"passive_rf_infrared": "passive radio-frequency and infrared homing",
	"radar_directed": "none: aimed by its mount's own radar",
	"semi_active_abstract": "semi-active, on the launcher's illuminating radar",
	"semi_active_laser": "semi-active laser, on a designator's spot",
	"track_via_missile": "track-via-missile, guided from the launching ship",
	"unguided": "none: an unguided round",
	"wake_homing_abstracted": "wake homing, following the ship's wake",
}
const PROFILES := {
	"sea_skimming": "sea-skimming",
	"high": "high, diving on the target",
	"direct": "direct fire",
	"subsurface": "under water",
	"ballistic": "ballistic",
	"exoatmospheric": "above the atmosphere",
}

var _list: ItemList
var _detail: RichTextLabel
var _stage: ModelStage
var _search: LineEdit
var _specs: Array = []
## The list's rows: an index into _specs, or -1 for a heading row.
var _rows: Array[int] = []
## Set by Main when it can; otherwise the sibling Simulation node is used. The library opens on
## the player's flagship from it, when it is opened without a subject.
var simulation: Simulation
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
var _margin: MarginContainer
var _layout: VBoxContainer
var _kicker: Label
var _hint: Label
var _belt: ScrollContainer

func _ready() -> void:
	theme_type_variation = "OverlayPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UITheme.backdrop())
	var margin := MarginContainer.new()
	_margin = margin
	add_child(margin)
	var sheet := PanelContainer.new()
	sheet.theme_type_variation = "MenuPanel"
	margin.add_child(sheet)
	var v := VBoxContainer.new()
	_layout = v
	sheet.add_child(v)
	var masthead := HBoxContainer.new()
	v.add_child(masthead)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 2)
	masthead.add_child(heading)
	var brand := UITheme.caption("Reference")
	brand.add_theme_font_size_override("font_size", 34)
	heading.add_child(brand)
	_kicker = Label.new()
	_kicker.text = "Platforms and ordnance: recognition, fit and game envelope"
	_kicker.theme_type_variation = "MenuLabel"
	heading.add_child(_kicker)
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
	_list.item_selected.connect(func(row: int) -> void: _select(_spec_index(row)))
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
	for view in [["3D", "three_quarter"], ["PROFILE", "profile"], ["PLAN", "plan"], ["FRONT", "front"]]:
		var button := Button.new()
		button.theme_type_variation = "TabButton"
		button.custom_minimum_size = Vector2(76, 28)
		button.text = view[0]
		button.pressed.connect(_stage.set_view.bind(view[1]))
		views.add_child(button)
	_spin_button = Button.new()
	_spin_button.theme_type_variation = "QuietButton"
	_spin_button.text = "AUTO ROTATE"
	UIIcons.apply(_spin_button, "restart", 16)
	_spin_button.toggle_mode = true
	_spin_button.toggled.connect(_stage.set_spin)
	_stage.spin_changed.connect(_spin_button.set_pressed_no_signal)
	_spin_button.button_pressed = true
	view_bar.add_child(_spin_button)
	_hint = Label.new()
	_hint.text = "  " + ORBIT_HINT
	_hint.theme_type_variation = "MenuLabel"
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.clip_text = true
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_bar.add_child(_hint)
	_stage.tooltip_text = ORBIT_HINT.capitalize()
	_loadout_title = UITheme.caption("")
	_loadout_title.add_theme_font_size_override("font_size", 16)
	center.add_child(_loadout_title)
	var belt := ScrollContainer.new()
	_belt = belt
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
	resized.connect(_apply_layout)
	_apply_layout()
	visibility_changed.connect(func() -> void:
		if visible:
			open_home())
	_filter("")


## A short screen (a laptop, or a larger interface size) takes a compact sheet, as the desk and
## the briefing do: tighter margins, a lower model stage and loadout belt, and the orbit hint left
## to the stage's tooltip rather than cut short beside the view buttons.
func _apply_layout() -> void:
	if _margin == null:
		return
	var compact := is_compact(get_viewport_rect().size)
	for side in ["left", "right"]:
		_margin.add_theme_constant_override("margin_" + side, 16 if compact else 36)
	for side in ["top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, 10 if compact else 24)
	_layout.add_theme_constant_override("separation", 6 if compact else 12)
	_kicker.visible = not compact
	_hint.visible = not compact
	_title.add_theme_font_size_override("font_size", 28 if compact else 40)
	_stage.custom_minimum_size = Vector2(260, 150 if compact else 240)
	_belt.custom_minimum_size.y = 100 if compact else 116


static func is_compact(viewport_size: Vector2) -> bool:
	return viewport_size.x < 1300.0 or viewport_size.y < 850.0


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

func _set_mode(weapons: bool, refresh := true) -> void:
	if _weapons != weapons:
		_search.text = ""
	_weapons = weapons
	_platform_button.button_pressed = not weapons
	_weapon_button.button_pressed = weapons
	_build_domains()
	if refresh:
		_filter(_search.text)

## The reference entry for a contact, from what its track reports and nothing else: the class
## short name held once the contact is CLASS_KNOWN, matched against the catalogue. `hint_id` (an
## own platform's id) picks between the 1990 and 2027 catalogues where they share a name. Null
## when the class is not known or not in the catalogue.
static func entry_for_track(t: Track, hint_id := "") -> PlatformSpec:
	if t == null or t.classification < Track.Classification.CLASS_KNOWN or t.known_class == "":
		return null
	return DataDB.platform_by_short_name(t.known_class, hint_id)

## Match only the reported class. If multiple operators use it, let the player compare entries.
func inspect_track(t: Track, hint_id: String) -> void:
	var entry := entry_for_track(t, hint_id)
	if entry != null:
		var variants := DataDB.platforms_by_short_name(t.known_class, hint_id)
		if variants.size() == 1:
			inspect(entry.id)
			return
		_set_mode(false, false)
		_search.text = t.known_class
		_filter(_search.text, variants, false)
		_empty_entry(t.known_class, "Choose a catalogue variant to inspect.")
		return
	_set_mode(false, false)
	_search.text = ""
	_filter("", [], false)
	var title := "Class unreported"
	if t != null and t.classification >= Track.Classification.CLASS_KNOWN and t.known_class != "":
		title = t.known_class
	_empty_entry(title, "Browse the catalogue to compare recognition models.")

func inspect(asset_id: String, weapon := false) -> void:
	_search.text = ""
	_set_mode(weapon, false)
	_filter("", [], false)
	for i in _specs.size():
		if _specs[i].id == asset_id:
			_list.select(_rows.find(i))
			_list.ensure_current_is_visible()
			_select(i)
			return
	_empty_entry("Catalogue entry unavailable", "Choose a platform or ordnance entry.")


## The platform the library opens on: the player's flagship in the loaded operation, or "".
func home_id() -> String:
	var sim := simulation
	if sim == null and get_parent() != null:
		sim = get_parent().get_node_or_null("Simulation") as Simulation
	if sim == null or sim.unit_manager == null:
		return ""
	var flag := CommanderPicture.default_hook(sim.unit_manager, sim.player_faction)
	return flag.spec.id if flag != null and flag.spec != null else ""


## Opens on the flagship: every opening without a subject starts there, as the dossier of the
## ship the commander is in. Main inspects a contact or a hooked unit after this when it has one.
func open_home() -> void:
	var id := home_id()
	if id != "":
		inspect(id)


func _spec_index(row: int) -> int:
	return _rows[row] if row >= 0 and row < _rows.size() else -1

func _filter(query: String, candidates: Array = [], select_first := true) -> void:
	_list.clear()
	_specs.clear()
	_rows.clear()
	# The whole catalogue runs by nation and then by type under headings; a short list of operator
	# variants keeps the order it was given.
	var grouped := candidates.is_empty()
	var records := candidates
	if records.is_empty():
		records = sorted_catalogue(_weapons)
	var terms := Array(query.to_lower().split(" ", false))
	for p in records:
		var name_text: String = p.family if _weapons else p.short_name
		var search_text: String = p.display_name + " " + name_text
		if not _weapons:
			var era := "1990" if p.id.begins_with(DataDB.COLD_WAR_PREFIX) else "2027"
			search_text += " " + " ".join([p.nation, p.role, p.category, era])
			if DataDB.platforms_by_short_name(p.short_name).size() > 1:
				var qualifier: String = era if DataDB.platforms_by_short_name(p.short_name, p.id).size() == 1 else p.nation
				name_text += " · " + qualifier
		var category: String = p.type if _weapons else p.domain
		search_text = search_text.to_lower()
		if not terms.all(func(term: String) -> bool: return term in search_text) or (_domain != "all" and (not WeaponPresentation.matches(p, _domain) if _weapons else category != _domain)):
			continue
		if grouped:
			var heading := group_name(p, _weapons)
			if _specs.is_empty() or group_name(_specs[-1], _weapons) != heading:
				_list.add_item(heading.to_upper())
				var head_row := _list.item_count - 1
				_list.set_item_selectable(head_row, false)
				_list.set_item_custom_fg_color(head_row, UITheme.INK_BLUE)
				_list.set_item_tooltip_enabled(head_row, false)
				_rows.append(-1)
		_specs.append(p)
		_rows.append(_specs.size() - 1)
		_list.add_item(name_text, PlatformArt.thumbnail(p.id, _weapons))
		_list.set_item_tooltip(_list.item_count - 1, p.display_name)
	_count.text = count_text(_specs.size(), _weapons)
	if select_first and not _specs.is_empty():
		_list.select(_rows.find(0))
		_select(0)
	elif _specs.is_empty():
		_empty_entry("No matches", "Try another search or domain.")

## "140 PLATFORM CLASSES", "1 WEAPON SYSTEM", "NO MATCHES".
static func count_text(n: int, weapons: bool) -> String:
	if n == 0:
		return "NO MATCHES"
	if weapons:
		return "%d WEAPON SYSTEM%s" % [n, "" if n == 1 else "S"]
	return "%d PLATFORM CLASS%s" % [n, "" if n == 1 else "ES"]


## The heading a catalogue entry sits under: its nation, or for ordnance its kind.
static func group_name(entry: Resource, weapons: bool) -> String:
	if weapons:
		return WEAPON_TYPES.get((entry as WeaponSpec).type, "Other ordnance")
	return (entry as PlatformSpec).nation


## The catalogue in reading order: platforms by nation, then surface, submarine, air and shore,
## then kind and name; ordnance by kind, then family and name.
static func sorted_catalogue(weapons: bool) -> Array:
	var out: Array = (DataDB.all_weapons() if weapons else DataDB.all_platforms()).duplicate()
	if weapons:
		var kinds := WEAPON_TYPES.keys()
		out.sort_custom(func(a: WeaponSpec, b: WeaponSpec) -> bool:
			var ka := kinds.find(a.type) if kinds.has(a.type) else kinds.size()
			var kb := kinds.find(b.type) if kinds.has(b.type) else kinds.size()
			if ka != kb:
				return ka < kb
			if a.family != b.family:
				return a.family.naturalnocasecmp_to(b.family) < 0
			return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	else:
		out.sort_custom(func(a: PlatformSpec, b: PlatformSpec) -> bool:
			var na := _nation_key(a.nation)
			var nb := _nation_key(b.nation)
			if na != nb:
				return na < nb
			var da := DOMAIN_ORDER.find(a.domain)
			var db := DOMAIN_ORDER.find(b.domain)
			if da != db:
				return da < db
			if a.category != b.category:
				return a.category.naturalnocasecmp_to(b.category) < 0
			if a.short_name != b.short_name:
				return a.short_name.naturalnocasecmp_to(b.short_name) < 0
			return a.id < b.id)
	return out


## Nations alphabetically, with merchant and civilian shipping after every navy.
static func _nation_key(nation: String) -> String:
	return ("~" if nation.begins_with("Civil") else "") + nation.to_lower()


func _empty_entry(title: String, subtitle: String) -> void:
	_stage.show_asset("", _weapons)
	_title.text = title.to_upper()
	_subtitle.text = subtitle
	_eyebrow.text = "RECOGNITION LIBRARY"
	_detail.text = ""
	_clear_loadout()
	_loadout_title.text = ""

func _clear_loadout() -> void:
	for child in _loadout.get_children():
		_loadout.remove_child(child)
		child.queue_free()

## Use the same compatibility rule as the flight deck, including aircraft that can use land bases.
static func basing_options(aircraft: PlatformSpec) -> PackedStringArray:
	var available := {}
	for host: PlatformSpec in DataDB.all_platforms():
		if host.can_operate(aircraft):
			available[host.flight_facility()] = true
	var labels := PackedStringArray()
	for facility: String in FACILITY_NAMES:
		if available.has(facility):
			labels.append(FACILITY_NAMES[facility])
	return labels

func _select(index: int) -> void:
	if index < 0 or index >= _specs.size():
		return
	var p = _specs[index]
	_stage.show_asset(p.id, _weapons)
	_clear_loadout()
	if _weapons:
		_show_weapon(p)
		return
	_eyebrow.text = "%s  /  %s  /  %s" % [p.nation, p.domain.to_upper(), p.category.to_upper()]
	_title.text = p.short_name.to_upper()
	_subtitle.text = p.display_name
	var lines := PackedStringArray()
	lines.append("[font_size=18][b]%s[/b][/font_size]\n" % p.role)
	if p.recognition_note != "":
		lines.append(UITheme.section_bb("Recognition", true))
		lines.append(p.recognition_note + "\n")
	lines.append(UITheme.section_bb("General", true))
	for row: Array in general_rows(p):
		lines.append(_row_bb(row))
	if p.aircraft_capacity > 0:
		lines.append("[color=%s]AVIATION[/color]   %s" % [UITheme.HEX_INK_DIM, FACILITY_NAMES.get(p.flight_facility(), p.flight_facility())])
		lines.append("[color=%s]GAME AIRFRAME CAPACITY[/color]   %d" % [UITheme.HEX_INK_DIM, p.aircraft_capacity])
	elif p.domain == "air":
		lines.append("[color=%s]IN-GAME BASING[/color]   %s" % [UITheme.HEX_INK_DIM, ", ".join(basing_options(p))])
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

static func _row_bb(row: Array) -> String:
	return "[color=%s]%s[/color]   %s" % [UITheme.HEX_INK_DIM, str(row[0]).to_upper(), str(row[1])]


## A platform's general figures as [label, words] rows: size, speed, reach, ceiling or depth and
## countermeasures, each only where the catalogue holds it. The game's estimates, said plainly.
static func general_rows(p: PlatformSpec) -> Array:
	var rows: Array = []
	if p.length_m > 0.0:
		rows.append(["Length", "%.1f m" % p.length_m])
	if p.domain in ["surface", "subsurface"] and p.displacement_t > 0.0:
		rows.append(["Displacement", "%s t" % _thousands(roundi(p.displacement_t))])
	if p.domain == "land":
		rows.append(["Basing", "ashore: %s" % p.category])
	var top := maxf(p.max_speed_kn, p.dash_speed_kn) if p.domain == "air" else p.max_speed_kn
	if top > 0.0:
		rows.append(["Top speed", "%d kn%s" % [roundi(top), " submerged" if p.domain == "subsurface" else ""]])
	if p.cruise_speed_kn > 0.0 and p.cruise_speed_kn < top:
		rows.append(["Cruise", "%d kn" % roundi(p.cruise_speed_kn)])
	if p.domain == "air" and p.endurance_s > 0.0:
		var hours := p.endurance_s / 3600.0
		rows.append(["Endurance", "%s at cruise, about %s nm" % [_hours(hours), _thousands(roundi(hours * p.cruise_speed_kn / 10.0) * 10)]])
	if p.domain == "subsurface":
		if p.category.contains("nuclear"):
			rows.append(["Endurance", "nuclear plant: submerged for the whole patrol"])
		elif p.battery_hotel_h > 0.0 or p.battery_sprint_h > 0.0:
			rows.append(["Battery", "about %s stopped, %s flat out" % [_hours(p.battery_hotel_h), _hours(p.battery_sprint_h)]])
		if p.aip_endurance_h > 0.0:
			rows.append(["Air-independent", "%s at up to %d kn" % [_hours(p.aip_endurance_h), roundi(p.aip_speed_kn)]])
		if p.max_depth_m > 0.0:
			rows.append(["Depth", "%d m (%s ft)" % [roundi(p.max_depth_m), _thousands(roundi(p.max_depth_m * 3.28084 / 10.0) * 10)]])
	if p.domain == "air" and p.max_altitude_m > 0.0:
		rows.append(["Ceiling", "%s ft" % _thousands(roundi(p.max_altitude_m * 3.28084 / 100.0) * 100)])
	var measures := PackedStringArray()
	if p.decoy_count > 0:
		measures.append("%d %s" % [p.decoy_count, "flare and chaff loads" if p.domain == "air" else ("noisemaker canisters" if p.domain == "subsurface" else "chaff and decoy salvoes")])
	if p.torpedo_decoy != "":
		measures.append("%s%s" % [p.torpedo_decoy, ", towed" if p.towed_torpedo_decoy else (", %d torpedo decoys" % p.torpedo_decoy_count if p.torpedo_decoy_count > 0 else "")])
	if not measures.is_empty():
		rows.append(["Countermeasures", "; ".join(measures)])
	if p.sonobuoy_count > 0:
		rows.append(["Sonobuoys", str(p.sonobuoy_count)])
	return rows


## A weapon's general figures as [label, words] rows: what it is for, how fast and far it goes,
## its warhead and its seeker, in words rather than the game's labels.
static func weapon_rows(w: WeaponSpec) -> Array:
	var rows: Array = []
	rows.append(["Kind", {"asm": "anti-ship or strike missile", "sam": "surface-to-air missile", "aam": "air-to-air missile", "torpedo": "torpedo", "asw_rocket": "anti-submarine rocket", "bomb": "bomb", "gun": "gun mount", "ciws": "close-in weapon system"}.get(w.type, "ordnance")])
	var targets := PackedStringArray()
	for t: String in w.target_types:
		targets.append({"surface": "ships", "subsurface": "submarines", "air": "aircraft", "land": "targets ashore", "missile": "missiles", "torpedo": "torpedoes"}.get(t, t))
	rows.append(["Targets", ", ".join(targets)])
	if w.speed_kn > 0.0:
		var mach := "" if w.type == "torpedo" else "  (Mach %.1f)" % (w.speed_kn / 661.5)
		rows.append(["Speed", "%s kn%s" % [_thousands(roundi(w.speed_kn)), mach]])
	rows.append(["Range", "%s to %s nm" % [_figure(w.min_range_nm), _figure(w.max_range_nm)]])
	rows.append(["Warhead", warhead_words(w)])
	rows.append(["Seeker", SEEKERS.get(w.guidance, w.guidance.replace("_", " "))])
	if not w.type in ["gun", "ciws"]:
		rows.append(["Flight", PROFILES.get(w.profile, w.profile.replace("_", " "))])
	return rows


## The warhead in words, from the game's damage figure and the kind of round.
static func warhead_words(w: WeaponSpec) -> String:
	if w.type == "ciws":
		return "small-calibre rounds in a stream"
	if w.type == "gun":
		return "high-explosive shells"
	if w.type == "torpedo":
		return "heavyweight torpedo charge" if w.damage >= 60.0 else "lightweight torpedo charge"
	if w.damage < 15.0:
		return "light, against aircraft and small craft"
	if w.damage < 40.0:
		return "medium"
	if w.damage < 70.0:
		return "heavy, ship-killing"
	return "very heavy"


static func _figure(nm: float) -> String:
	return ("%.1f" % nm) if nm < 10.0 else str(roundi(nm))


static func _hours(h: float) -> String:
	if h >= 48.0:
		return "%d days" % roundi(h / 24.0)
	var minutes := roundi(h * 60.0 / 5.0) * 5
	if minutes >= 60:
		return ("%d h" % (minutes / 60)) if minutes % 60 == 0 else "%d h %02d min" % [minutes / 60, minutes % 60]
	return "%d min" % maxi(roundi(h * 60.0), 1)


static func _thousands(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out


func _show_weapon(w: WeaponSpec) -> void:
	_eyebrow.text = "ORDNANCE  /  %s  /  %s" % [w.type.to_upper(), ("GUN MOUNT" if w.type in ["gun", "ciws"] else w.profile.replace("_", " ").to_upper())]
	_title.text = w.family.to_upper()
	_subtitle.text = w.display_name
	var lines := PackedStringArray(["[font_size=18][b]%s[/b][/font_size]\n" % w.display_name, UITheme.section_bb("General", true)])
	for row: Array in weapon_rows(w):
		lines.append(_row_bb(row))
	lines.append("\n[color=%s]Family recognition model. Variants and real configurations differ. These figures are the game's own estimates, not the real system's performance.[/color]" % UITheme.HEX_INK_DIM)
	_detail.text = "\n".join(lines)
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
