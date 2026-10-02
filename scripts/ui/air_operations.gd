class_name AirOperations
extends PanelContainer
## Own-force air plan, drawn as the grey in-mission launch dialog. Choose a host and an aircraft
## type, light the LAUNCH lamps of the airframes to send, then Ok to launch them and resume.
## Below, choose an airborne airframe and where it should land. Commands always go through Main
## and UnitManager.
signal closed(execute: bool)
signal order_requested(unit: Unit, order: Order)
signal aircraft_selected(aircraft: Unit)
## Hand the chart to the commander to pick a station or search area (false) or a strike target.
signal chart_pick_requested(contact: bool)

const DIALOG_SIZE := Vector2(880.0, 690.0)
const DECK_COLUMNS := ["AIRFRAME", "LAUNCH", "TIME", "STATE", "FUEL"]
## The mission picker's rows: "launch only", then AirMission.Kind in order.
const MISSION_CHOICES := ["None — launch only", "Combat air patrol", "Reconnaissance / identification", "ASW search", "Strike"]

var simulation: Simulation
var _base_picker: OptionButton
var _type_picker: OptionButton
var _portrait: TextureRect
var _type_detail: Label
var _count: SpinBox
var _launch: Button
var _launch_hint: Label
var _deck: GridContainer
var _deck_rows: Array[Unit] = []
var _deck_key := ""
var _leds: Array[Button] = []
var _roster: Tree
var _aircraft_detail: Label
var _destination: OptionButton
var _return: Button
var _focus: Button
var _receipt: Label
var _summary: Label
var _back: Button
var _ok: Button
var _bases: Array[Unit] = []
var _destinations: Array[Unit] = []
var _type_ids: Array[String] = []
var _base: Unit
var _aircraft: Unit
var _destination_aircraft: Unit
var _type_id := ""
var _accum := 0.0
var _mission_picker: OptionButton
var _station_button: Button
var _station_label: Label
var _radius: SpinBox
var _relief: CheckBox
var _auto_return: CheckBox
var _lower_tabs: TabContainer
var _missions: Tree
var _mission_detail: Label
var _cancel_mission: Button
## -1 launches airframes with no mission, as before; otherwise an AirMission.Kind.
var _mission_kind := -1
var _station := Vector2.INF
var _target: Track
var _selected_mission: AirMission


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# The dialog sits straight over the chart, as the originals did, with the faintest shade.
	var shade := StyleBoxFlat.new()
	shade.bg_color = UITheme.DIALOG_SHADE
	add_theme_stylebox_override("panel", shade)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var dialog := PanelContainer.new()
	dialog.theme_type_variation = "JfcDialog"
	dialog.custom_minimum_size = DIALOG_SIZE
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(dialog)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 7)
	dialog.add_child(page)

	var header := HBoxContainer.new()
	page.add_child(header)
	var title := _label("AIR OPERATIONS", 14)
	title.add_theme_font_override("font", UITheme.data_font())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_summary = _label("", 11, UITheme.INK_DIM)
	_summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_summary)

	var pickers := HBoxContainer.new()
	pickers.add_theme_constant_override("separation", 10)
	page.add_child(pickers)
	_base_picker = OptionButton.new()
	_base_picker.custom_minimum_size = Vector2(340, 28)
	_base_picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_base_picker.clip_text = true
	_base_picker.accessibility_name = "Launch carrier or airfield"
	_base_picker.tooltip_text = "The carrier, deck or airfield to launch from"
	_base_picker.item_selected.connect(func(i: int) -> void:
		_base = _bases[i] if i >= 0 and i < _bases.size() else null
		_type_id = ""
		_count.set_value_no_signal(0)
		_refresh_types())
	pickers.add_child(_base_picker)
	_type_picker = OptionButton.new()
	_type_picker.custom_minimum_size = Vector2(290, 28)
	_type_picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_type_picker.clip_text = true
	_type_picker.accessibility_name = "Embarked aircraft type"
	_type_picker.tooltip_text = "The aircraft type to launch, with how many are ready"
	_type_picker.item_selected.connect(func(i: int) -> void:
		if i >= 0 and i < _type_ids.size():
			_type_id = _type_ids[i]
			_count.set_value_no_signal(0)
			_refresh_launch())
	pickers.add_child(_type_picker)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pickers.add_child(gap)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(120, 52)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pickers.add_child(_portrait)
	_type_detail = _label("", 12, UITheme.INK_DIM)
	_type_detail.clip_text = true
	page.add_child(_type_detail)

	# The mission: what the sortie is for, where, and whether the deck keeps it manned.
	var mission_row := HBoxContainer.new()
	mission_row.add_theme_constant_override("separation", 10)
	page.add_child(mission_row)
	mission_row.add_child(_label("MISSION", 12))
	_mission_picker = OptionButton.new()
	_mission_picker.custom_minimum_size = Vector2(250, 28)
	_mission_picker.clip_text = true
	_mission_picker.accessibility_name = "Air mission"
	_mission_picker.tooltip_text = "Launch to a mission: the deck keeps the airframes tasked, queues what it cannot launch yet, and brings them home on fuel."
	for choice: String in MISSION_CHOICES:
		_mission_picker.add_item(choice)
	_mission_picker.item_selected.connect(func(i: int) -> void: set_mission_kind(i - 1))
	mission_row.add_child(_mission_picker)
	_station_button = _button("PICK ON CHART", func() -> void: chart_pick_requested.emit(_mission_kind == AirMission.Kind.STRIKE))
	_station_button.tooltip_text = "Close this dialog and click the station or search area on the chart; a strike picks a held contact"
	mission_row.add_child(_station_button)
	mission_row.add_child(_label("RADIUS", 12))
	_radius = SpinBox.new()
	_radius.min_value = AirMissionManager.MIN_RADIUS_NM
	_radius.max_value = AirMissionManager.MAX_RADIUS_NM
	_radius.step = 1.0
	_radius.suffix = "nm"
	_radius.custom_minimum_size = Vector2(82, 28)
	_radius.accessibility_name = "Station or search radius"
	_radius.value_changed.connect(func(_v: float) -> void: _refresh_launch())
	mission_row.add_child(_radius)
	_relief = CheckBox.new()
	_relief.text = "Relief"
	_relief.tooltip_text = "Launch a ready reserve airframe in time to take over as each one on station turns for home"
	_relief.toggled.connect(func(_on: bool) -> void: _refresh_launch())
	mission_row.add_child(_relief)
	_auto_return = CheckBox.new()
	_auto_return.text = "Back to station"
	_auto_return.button_pressed = true
	_auto_return.tooltip_text = "After identifying or intercepting a contact, return to the station without being told"
	mission_row.add_child(_auto_return)
	_station_label = _label("", 12, UITheme.INK_DIM)
	_station_label.clip_text = true
	page.add_child(_station_label)

	# The deck: one row per airframe of the chosen type aboard the host, in the order the deck
	# will send them, each with its LAUNCH lamp.
	var deck_frame := ScrollContainer.new()
	deck_frame.custom_minimum_size.y = 132
	deck_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck_frame.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(deck_frame)
	_deck = GridContainer.new()
	_deck.columns = DECK_COLUMNS.size()
	_deck.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deck.add_theme_constant_override("h_separation", 30)
	_deck.add_theme_constant_override("v_separation", 3)
	deck_frame.add_child(_deck)

	var launch_row := HBoxContainer.new()
	launch_row.add_theme_constant_override("separation", 10)
	page.add_child(launch_row)
	launch_row.add_child(_label("AIRCRAFT", 12))
	_count = SpinBox.new()
	_count.min_value = 0
	_count.max_value = 4
	_count.value = 0
	_count.custom_minimum_size = Vector2(72, 28)
	_count.accessibility_name = "Number of aircraft to launch"
	_count.tooltip_text = "How many of the ready airframes to launch; the lamps follow"
	_count.value_changed.connect(func(_v: float) -> void: _refresh_launch())
	launch_row.add_child(_count)
	_launch = _button("LAUNCH NOW", _launch_selected)
	_launch.theme_type_variation = "PrimaryButton"
	launch_row.add_child(_launch)
	_launch_hint = _label("", 12, UITheme.INK_DIM)
	_launch_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_launch_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	launch_row.add_child(_launch_hint)

	_lower_tabs = TabContainer.new()
	_lower_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_lower_tabs)
	var airborne_page := VBoxContainer.new()
	airborne_page.name = "AIRBORNE & RECOVERY"
	_lower_tabs.add_child(airborne_page)
	var recovery_head := HBoxContainer.new()
	airborne_page.add_child(recovery_head)
	var recovery_title := _label("RECOVERY", 13)
	recovery_title.add_theme_font_override("font", UITheme.data_font())
	recovery_head.add_child(recovery_title)
	var recovery_hint := _label("Select an airborne airframe, choose where it lands, then Return & Land.", 12, UITheme.INK_DIM)
	recovery_hint.clip_text = true
	recovery_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recovery_head.add_child(recovery_hint)
	_roster = Tree.new()
	_roster.hide_root = true
	_roster.columns = 6
	_roster.column_titles_visible = true
	_roster.select_mode = Tree.SELECT_ROW
	_roster.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_roster.custom_minimum_size.y = 150
	_roster.accessibility_name = "Friendly aircraft status roster"
	var columns := ["AIRFRAME / TYPE", "STATE", "FUEL", "BASE", "CYCLE", "MISSION"]
	for i in columns.size():
		_roster.set_column_title(i, columns[i])
		_roster.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT)
	_roster.set_column_expand_ratio(0, 4)
	_roster.set_column_expand_ratio(1, 2)
	_roster.set_column_expand_ratio(3, 3)
	_roster.set_column_custom_minimum_width(2, 64)
	_roster.set_column_custom_minimum_width(4, 64)
	_roster.set_column_expand_ratio(5, 3)
	_roster.item_selected.connect(func() -> void:
		var item := _roster.get_selected()
		_aircraft = item.get_metadata(0) as Unit if item != null else null
		_refresh_recovery())
	airborne_page.add_child(_roster)
	_aircraft_detail = _label("Select an airframe to see fuel, ordnance and landing options.", 12, UITheme.INK_DIM)
	_aircraft_detail.custom_minimum_size.y = 34
	_aircraft_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	airborne_page.add_child(_aircraft_detail)
	var recovery_row := HBoxContainer.new()
	recovery_row.add_theme_constant_override("separation", 10)
	airborne_page.add_child(recovery_row)
	recovery_row.add_child(_label("LAND AT", 12))
	_destination = OptionButton.new()
	_destination.custom_minimum_size = Vector2(220, 28)
	_destination.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_destination.clip_text = true
	_destination.accessibility_name = "Recovery carrier or airfield"
	_destination.item_selected.connect(func(_i: int) -> void: _refresh_recovery_hint())
	recovery_row.add_child(_destination)
	_return = _button("RETURN & LAND", _return_selected)
	recovery_row.add_child(_return)
	_focus = _button("SHOW ON CHART", func() -> void:
		if _aircraft != null and _aircraft.is_engageable():
			aircraft_selected.emit(_aircraft))
	_focus.tooltip_text = "Close this dialog and hook the airframe on the chart"
	recovery_row.add_child(_focus)

	# Missions in hand: what each deck has been told to keep in the air and what each airframe on
	# it is doing now, from QUEUED to RECOVERING.
	var missions_page := VBoxContainer.new()
	missions_page.name = "MISSIONS"
	_lower_tabs.add_child(missions_page)
	_missions = Tree.new()
	_missions.hide_root = true
	_missions.columns = 4
	_missions.column_titles_visible = true
	_missions.select_mode = Tree.SELECT_ROW
	_missions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_missions.custom_minimum_size.y = 150
	_missions.accessibility_name = "Air missions and the state of each airframe"
	var mission_columns := ["MISSION / AIRFRAME", "STATE", "FUEL", "DECK"]
	for i in mission_columns.size():
		_missions.set_column_title(i, mission_columns[i])
		_missions.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT)
	_missions.set_column_expand_ratio(0, 4)
	_missions.set_column_expand_ratio(1, 3)
	_missions.set_column_custom_minimum_width(2, 64)
	_missions.set_column_expand_ratio(3, 2)
	_missions.item_selected.connect(func() -> void:
		var item := _missions.get_selected()
		var meta: Variant = item.get_metadata(0) if item != null else null
		_selected_mission = meta as AirMission if meta is AirMission else null
		_refresh_mission_detail())
	missions_page.add_child(_missions)
	_mission_detail = _label("Assign a mission above; its airframes and what each is doing appear here.", 12, UITheme.INK_DIM)
	_mission_detail.custom_minimum_size.y = 34
	_mission_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	missions_page.add_child(_mission_detail)
	var mission_buttons := HBoxContainer.new()
	mission_buttons.add_theme_constant_override("separation", 10)
	missions_page.add_child(mission_buttons)
	_cancel_mission = _button("CANCEL MISSION", _cancel_selected_mission)
	_cancel_mission.tooltip_text = "Strike off queued launches and bring the mission's airborne aircraft home"
	mission_buttons.add_child(_cancel_mission)
	_receipt = _label("Light the LAUNCH lamps of the airframes to send, then Ok. Recovered aircraft refuel and rearm before another sortie.", 12, UITheme.INK)
	_receipt.custom_minimum_size.y = 32
	_receipt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_receipt)

	# Ok and Cancel, each a caption over an empty bevel button.
	var footer := HBoxContainer.new()
	page.add_child(footer)
	_ok = Button.new()
	_ok.tooltip_text = "Launch the lit airframes and resume at 1×"
	_ok.pressed.connect(_on_ok)
	footer.add_child(_captioned(_ok, "Ok"))
	var footer_gap := Control.new()
	footer_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_gap)
	_back = Button.new()
	_back.tooltip_text = "Close without launching; the clock keeps its previous pause state  [F3 / Esc]"
	_back.pressed.connect(func() -> void: closed.emit(false))
	footer.add_child(_captioned(_back, "Cancel"))


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 28
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(action)
	return b


## A dialog button as the originals drew it: the word above an empty bevel button.
func _captioned(button: Button, caption: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var label := _label(caption, 13)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	button.custom_minimum_size = Vector2(64, 30)
	button.focus_mode = Control.FOCUS_ALL
	button.accessibility_name = caption
	box.add_child(button)
	return box


func _label(text: String, font_size: int, color := UITheme.INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func open_for(selection: Array) -> void:
	_base = null
	_aircraft = null
	_destination_aircraft = null
	_type_id = ""
	_count.set_value_no_signal(0)
	_station = Vector2.INF
	_target = null
	set_mission_kind(-1)
	for u: Unit in selection:
		if u.faction != simulation.player_faction or not u.alive:
			continue
		if u.is_aircraft():
			_aircraft = u
			_base = u.home
			_type_id = u.spec.id
			break
		if u.spec.aircraft_capacity > 0 and not u.stowed_aircraft().is_empty():
			_base = u
			break
	show()
	refresh()
	_base_picker.call_deferred("grab_focus")


## Opens on a strike at a held contact: from the contact menu's "Air strike...".
func open_strike(selection: Array, target: Track) -> void:
	open_for(selection)
	if _base == null:
		for b in _bases:
			if b.alive and not b.stowed_aircraft().is_empty():
				_base = b
				break
		refresh()
	set_mission_kind(AirMission.Kind.STRIKE)
	_target = target
	# Open on a type that can carry it out, if the deck has one.
	if _base != null and not AirMissionManager.type_suits(DataDB.platform(_type_id), AirMission.Kind.STRIKE):
		for group in inventory(_base):
			if AirMissionManager.type_suits(DataDB.platform(group["id"]), AirMission.Kind.STRIKE):
				_type_id = group["id"]
				break
	_refresh_types()


## -1 launches with no mission; otherwise an AirMission.Kind. A section of two is the default.
func set_mission_kind(kind: int) -> void:
	_mission_kind = kind
	if _mission_picker == null:
		return
	_mission_picker.select(kind + 1)
	_station_button.disabled = kind < 0
	_radius.editable = kind >= 0 and kind != AirMission.Kind.STRIKE
	_relief.disabled = kind < 0 or kind == AirMission.Kind.STRIKE
	_auto_return.disabled = kind < 0 or kind == AirMission.Kind.STRIKE
	_station_button.text = "PICK TARGET" if kind == AirMission.Kind.STRIKE else "PICK ON CHART"
	if kind >= 0 and kind != AirMission.Kind.STRIKE:
		_radius.set_value_no_signal(AirMissionManager.default_radius(kind))
	if kind < 0:
		_relief.set_pressed_no_signal(false)
	elif int(_count.value) == 0:
		_count.set_value_no_signal(2 if kind != AirMission.Kind.STRIKE else 2)
	_refresh_launch()


func mission_kind() -> int:
	return _mission_kind


## What the chart pick should look like: a point with the station's radius, or a held contact.
func pick_context() -> Dictionary:
	var strike := _mission_kind == AirMission.Kind.STRIKE
	var prompt := "Strike: click a held contact" if strike else "%s: click the %s" % [AirMission.KIND_LABELS[maxi(_mission_kind, 0)], "station" if _mission_kind == AirMission.Kind.CAP else "search area"]
	return {"contact": strike, "prompt": prompt, "origin": _base.position if _base != null else Vector2.INF, "radius_nm": 0.0 if strike else float(_radius.value)}


func apply_station(pos: Vector2) -> void:
	_station = pos
	_refresh_launch()


func apply_target(t: Track) -> void:
	_target = t
	_refresh_launch()


func clear_selection() -> void:
	_base = null
	_aircraft = null
	_destination_aircraft = null
	_bases.clear()
	_destinations.clear()
	_deck_rows.clear()
	_deck_key = ""
	if _roster != null:
		_roster.clear()


func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum >= 0.5:
		_accum = 0.0
		# Simulation is paused here. Refresh readiness without rebuilding a focused list.
		_refresh_launch()


func refresh() -> void:
	if simulation == null:
		return
	_bases.clear()
	_base_picker.clear()
	var ready := 0
	var flying := 0
	var cycling := 0
	for u: Unit in simulation.unit_manager.units:
		if not u.alive or u.faction != simulation.player_faction:
			continue
		if u.spec.aircraft_capacity > 0:
			_bases.append(u)
			_base_picker.add_item(u.callsign + " / " + u.spec.flight_facility().to_upper())
		if u.is_aircraft():
			if u.ready_to_launch():
				ready += 1
			elif u.flight_state in [Unit.FlightState.AIRBORNE, Unit.FlightState.RECOVERING]:
				flying += 1
			else:
				cycling += 1
	if not _bases.has(_base):
		_base = _bases[0] if not _bases.is_empty() else null
	_base_picker.disabled = _bases.is_empty()
	if _base != null:
		_base_picker.select(_bases.find(_base))
	var on_mission := simulation.air_mission_manager.active_missions(simulation.player_faction).size()
	_summary.text = "%02d READY  ·  %02d IN FLIGHT  ·  %02d IN DECK CYCLE  ·  %02d MISSIONS  ·  PAUSED" % [ready, flying, cycling, on_mission]
	_refresh_types()
	_refresh_roster()
	_refresh_recovery()
	_refresh_missions()


static func inventory(base: Unit) -> Array[Dictionary]:
	var groups: Dictionary = {}
	if base == null:
		return []
	for a: Unit in base.embarked:
		if not a.alive:
			continue
		if not groups.has(a.spec.id):
			groups[a.spec.id] = {"id": a.spec.id, "ready": 0, "total": 0}
		groups[a.spec.id]["total"] += 1
		if a.ready_to_launch():
			groups[a.spec.id]["ready"] += 1
	var out: Array[Dictionary] = []
	for id: String in groups:
		out.append(groups[id])
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return DataDB.platform(a["id"]).display_name < DataDB.platform(b["id"]).display_name)
	return out


func _refresh_types() -> void:
	_type_picker.clear()
	_type_ids.clear()
	var most_ready := ""
	var most := -1
	for group in inventory(_base):
		var spec := DataDB.platform(group["id"])
		_type_ids.append(spec.id)
		_type_picker.add_item("%s  —  %d ready of %d" % [spec.short_name, group["ready"], group["total"]])
		if int(group["ready"]) > most:
			most = int(group["ready"])
			most_ready = spec.id
	# With nothing chosen, open on the type with the most airframes ready: the deck's main effort.
	if not _type_ids.has(_type_id):
		_type_id = most_ready
	_type_picker.disabled = _type_ids.is_empty()
	_refresh_launch()


## The airframes of the chosen type aboard the host, in deck order: the order the deck sends them.
static func deck_rows(base: Unit, type_id: String) -> Array[Unit]:
	var out: Array[Unit] = []
	if base == null or type_id == "":
		return out
	for a: Unit in base.embarked:
		if a.alive and a.spec.id == type_id:
			out.append(a)
	return out


## Which LAUNCH lamps are lit when `count` aircraft will go: the first `count` ready airframes in
## deck order, which are exactly the ones the deck launches. Pure, so the rule is pinned by tests.
static func lit_lamps(rows: Array[Unit], count: int) -> Array[bool]:
	var out: Array[bool] = []
	var lit := 0
	for a in rows:
		var on := a.ready_to_launch() and lit < count
		if on:
			lit += 1
		out.append(on)
	return out


## The sortie size after pressing the lamp of `row`: a dark lamp lights every ready airframe up to
## and including it; the last lit lamp goes dark. Unready airframes change nothing.
static func count_after_press(rows: Array[Unit], row: int, count: int) -> int:
	if row < 0 or row >= rows.size() or not rows[row].ready_to_launch():
		return count
	var position := 0
	for i in row:
		if rows[i].ready_to_launch():
			position += 1
	return position if count == position + 1 else position + 1


func _refresh_launch() -> void:
	if _launch == null or simulation == null:
		return
	if _type_ids.has(_type_id) and _type_picker.selected != _type_ids.find(_type_id):
		_type_picker.select(_type_ids.find(_type_id))
	var spec := DataDB.platform(_type_id) if _type_id != "" else null
	_portrait.texture = PlatformArt.beauty(_type_id) if spec != null else null
	if _base == null or spec == null:
		_launch.disabled = true
		_count.editable = false
		_count.max_value = 0
		_type_detail.text = "No embarked aircraft. Choose another host, or load the Carrier Qualification exercise."
		_launch_hint.text = "No aircraft type selected."
		_rebuild_deck([])
		return
	_type_detail.text = "%s  ·  %s  ·  %s operations  ·  %d kn cruise  ·  %.0f min endurance" % [spec.display_name, spec.role, spec.flight_requirement().to_upper(), int(spec.cruise_speed_kn), spec.endurance_s / 60.0]
	var reloads := PackedStringArray()
	for wid: String in spec.weapon_loadout:
		var weapon := DataDB.weapon(wid)
		reloads.append("%s %d" % [weapon.display_name if weapon != null else wid, int(_base.aviation_stores.get(wid, 0))])
	_type_detail.text += "\nBASE RELOAD STOCK: %s  /  %d sonobuoys" % [", ".join(reloads) if not reloads.is_empty() else "No weapon reloads required", _base.aviation_buoys]
	var reason := simulation.aviation_manager.launch_rejection_reason(_base, _type_id)
	var ready := 0
	for a: Unit in _base.stowed_aircraft():
		if a.spec.id == _type_id:
			ready += 1
	var spots := maxi(_base.spec.launch_capacity() - _base.launch_spots_busy(), 0)
	var maximum := mini(ready, spots) if reason == "" else 0
	if _mission_kind >= 0:
		_refresh_mission_plan(spec, ready, spots, reason)
		_rebuild_deck(deck_rows(_base, _type_id))
		return
	_launch.text = "LAUNCH NOW"
	_station_label.text = "Choose a mission to have the deck keep a station, search an area or strike a held contact."
	_count.max_value = maximum
	_count.editable = maximum > 0
	var count := int(_count.value)
	_launch.disabled = maximum <= 0 or count <= 0
	if reason != "":
		_launch_hint.text = reason.capitalize()
	elif count <= 0:
		_launch_hint.text = "%d ready  ·  %d deck spot%s free. Light a LAUNCH lamp to choose the sortie." % [ready, spots, "" if spots == 1 else "s"]
	else:
		_launch_hint.text = "Launch %d × %s; airborne about %.0f s after resuming." % [count, spec.short_name, spec.launch_time_s]
	_launch.tooltip_text = _launch_hint.text
	_rebuild_deck(deck_rows(_base, _type_id))


## A mission may ask for more airframes than are ready: the deck queues the rest, launching each as
## a catapult frees and an airframe comes out of turnaround or reserve. The lamps show the ones that
## go now.
func _refresh_mission_plan(spec: PlatformSpec, ready: int, spots: int, deck_reason: String) -> void:
	var amm := simulation.air_mission_manager
	_launch.text = "ASSIGN MISSION"
	var available := amm.available_for(_base, _type_id, _mission_kind, _target)
	_count.max_value = available
	_count.editable = available > 0
	var count := mini(int(_count.value), available)
	var why := amm.mission_rejection(_base, _mission_kind, _type_id, _station, _target)
	var now := mini(count, ready if deck_reason == "" else 0)
	now = mini(now, spots)
	var where := ""
	if _mission_kind == AirMission.Kind.STRIKE:
		if _target != null:
			where = "TARGET: track %s  %s  ·  %.0f nm %s" % [_target.id, _target.description(), _base.position.distance_to(_target.position), Geo.format_bearing(Geo.bearing_deg(_base.position, _target.position))]
		else:
			where = "TARGET: none — PICK TARGET, or open Air strike from a contact's menu"
	elif _station.is_finite():
		var on_station := AirMissionManager.station_time_s(spec, _base.position.distance_to(_station))
		where = "STATION: %s  ·  %.0f nm %s from %s  ·  radius %.0f nm  ·  about %d min on station each" % [_position_text(_station), _base.position.distance_to(_station), Geo.format_bearing(Geo.bearing_deg(_base.position, _station)), _base.callsign, _radius.value, maxi(int(on_station / 60.0), 0)]
	else:
		where = "STATION: none — PICK ON CHART to place it"
	_station_label.text = where
	_launch.disabled = why != "" or count <= 0
	if why != "":
		_launch_hint.text = why
	elif count <= 0:
		_launch_hint.text = "%d %s available to this deck. Set how many fly the mission." % [available, spec.short_name]
	else:
		var queued := count - now
		_launch_hint.text = "%d launch now%s%s." % [now, ", %d queued (%s)" % [queued, ("catapults committed" if deck_reason != "" or spots < count else "awaiting ready aircraft")] if queued > 0 else "", ", relieved from ready reserve" if _relief.button_pressed else ""]
	_launch.tooltip_text = _launch_hint.text
	_count.set_value_no_signal(count)


## Builds the deck table when its rows change, and otherwise only updates lamps and readings, so
## a focused lamp keeps its focus through the half-second refresh.
func _rebuild_deck(rows: Array[Unit]) -> void:
	var ids := PackedStringArray()
	for a in rows:
		ids.append(str(a.get_instance_id()))
	var key := ",".join(ids)
	if key != _deck_key or _deck.get_child_count() == 0:
		_deck_key = key
		_deck_rows = rows
		_leds.clear()
		for child in _deck.get_children():
			_deck.remove_child(child)
			child.queue_free()
		for heading: String in DECK_COLUMNS:
			var h := _label(heading, 12)
			h.add_theme_font_override("font", UITheme.data_font())
			h.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if heading == "AIRFRAME" else HORIZONTAL_ALIGNMENT_CENTER
			if heading == "AIRFRAME":
				h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_deck.add_child(h)
		for i in rows.size():
			var a := rows[i]
			var name_label := _label("%s  (%s)" % [a.callsign, a.spec.short_name], 13)
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_deck.add_child(name_label)
			var led := Button.new()
			led.theme_type_variation = "LedToggle"
			led.toggle_mode = true
			led.focus_mode = Control.FOCUS_ALL
			led.custom_minimum_size = Vector2(44, 22)
			led.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			led.accessibility_name = "Launch %s" % a.callsign
			var row := i
			led.pressed.connect(func() -> void:
				_count.value = count_after_press(_deck_rows, row, int(_count.value))
				_refresh_launch())
			_deck.add_child(led)
			_leds.append(led)
			for _j in 3:
				var cell := _label("", 13)
				cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				cell.add_theme_font_override("font", UITheme.data_font())
				_deck.add_child(cell)
		if rows.is_empty():
			_deck.add_child(_label("No airframes of this type aboard.", 12, UITheme.INK_DIM))
	var lit := lit_lamps(_deck_rows, int(_count.value))
	var launchable := int(_count.max_value)
	var ready_seen := 0
	for i in _deck_rows.size():
		var a := _deck_rows[i]
		var led := _leds[i]
		led.set_pressed_no_signal(lit[i])
		var ready := a.ready_to_launch()
		led.disabled = not ready or ready_seen >= launchable
		if ready:
			ready_seen += 1
		if not ready:
			led.tooltip_text = "%s is not ready: %s" % [a.callsign, status_text(a).to_lower()]
		elif led.disabled:
			led.tooltip_text = "No free deck spot for another launch"
		else:
			led.tooltip_text = "Launch %s" % a.callsign
		var base_cell := DECK_COLUMNS.size() * (i + 1)
		var time_s := a.spec.launch_time_s if ready else a.state_timer_s
		(_deck.get_child(base_cell + 2) as Label).text = "%02d:%02d" % [int(time_s) / 60, int(time_s) % 60] if time_s > 0.0 else "--:--"
		var state := _deck.get_child(base_cell + 3) as Label
		state.text = status_text(a)
		state.add_theme_color_override("font_color", UITheme.INK_GREEN if ready else UITheme.INK_AMBER if a.returning else UITheme.INK)
		(_deck.get_child(base_cell + 4) as Label).text = "%d%%" % int(a.fuel_fraction() * 100.0)


## A chart position as the chart's own readout writes it: latitude and longitude where the scenario
## is charted, nautical miles from the origin otherwise.
func _position_text(p: Vector2) -> String:
	var m: Dictionary = simulation.scenario.get("map", {})
	if m.has("anchor_lat"):
		var ll := Geo.world_to_latlon(p, float(m["anchor_lat"]), float(m["anchor_lon"]))
		return ChartReadout.format_position(ll.x, ll.y)
	return ChartReadout.format_offset(p)


func _launch_selected() -> void:
	if _base == null or _type_id == "" or _launch.disabled or int(_count.value) <= 0:
		return
	if _mission_kind >= 0:
		order_requested.emit(_base, Order.air_mission(_mission_kind, _type_id, int(_count.value), _station, float(_radius.value), _target, _relief.button_pressed, _auto_return.button_pressed))
		# As a launch does: the lamps go dark, so Ok afterwards resumes rather than assigning again.
		_count.set_value_no_signal(0)
		_lower_tabs.current_tab = 1
		refresh()
		return
	order_requested.emit(_base, Order.launch_flight(_type_id, int(_count.value)))
	_count.set_value_no_signal(0)
	refresh()


## Ok: launch whatever is lit, then close and resume, as the original dialog did.
func _on_ok() -> void:
	if int(_count.value) > 0 and not _launch.disabled:
		_launch_selected()
	closed.emit(true)


static func status_text(a: Unit) -> String:
	match a.flight_state:
		Unit.FlightState.STOWED: return "READY"
		Unit.FlightState.LAUNCHING: return "LAUNCHING"
		Unit.FlightState.RECOVERING: return "LANDING"
		Unit.FlightState.TURNAROUND: return "REFUEL / REARM"
		Unit.FlightState.RESERVE: return "RESERVE %.0f MIN" % ceilf(a.state_timer_s / 60.0)
	if a.returning:
		return "RETURNING"
	if a.tanking_on != null:
		return "TANKING"
	return "AIRBORNE"


func _refresh_roster() -> void:
	_roster.clear()
	var root := _roster.create_item()
	for a: Unit in simulation.unit_manager.units:
		if not a.alive or a.faction != simulation.player_faction or not a.is_aircraft():
			continue
		var item := _roster.create_item(root)
		item.set_metadata(0, a)
		item.set_text(0, "%s / %s" % [a.callsign, a.spec.short_name])
		item.set_text(1, status_text(a))
		item.set_text(2, "%d%%" % int(a.fuel_fraction() * 100.0))
		var destination := a.recovery_base if a.recovery_base != null else a.home
		item.set_text(3, destination.callsign if destination != null else "OFF MAP")
		item.set_text(4, "%d:%02d" % [int(a.state_timer_s) / 60, int(a.state_timer_s) % 60] if a.state_timer_s > 0.0 else "")
		item.set_tooltip_text(0, "%s\n%s\n%s" % [a.callsign, a.spec.display_name, a.squadron])
		item.set_custom_color(1, UITheme.INK_GREEN if a.ready_to_launch() else UITheme.INK_AMBER if a.returning else UITheme.INK)
		var m := simulation.air_mission_manager.mission_for(a)
		item.set_text(5, "%s · %s" % [m.kind_name(), m.state_of(a)] if m != null else "")
		if a == _aircraft:
			item.select(0)


func _refresh_recovery() -> void:
	var previous: Unit = _destinations[_destination.selected] if _destination_aircraft == _aircraft and _destination.selected >= 0 and _destination.selected < _destinations.size() else null
	_destination_aircraft = _aircraft
	_destination.clear()
	_destinations.clear()
	_focus.disabled = _aircraft == null or not _aircraft.is_engageable()
	if _aircraft == null or not _aircraft.alive:
		_aircraft_detail.text = "Select an airframe to see fuel, ordnance and landing options."
		_destination.add_item("Select an airframe above")
		_return.disabled = true
		_destination.disabled = true
		return
	var a := _aircraft
	var stores := PackedStringArray()
	for wid in a.magazines:
		if int(a.magazines[wid]) > 0:
			var spec := DataDB.weapon(wid)
			stores.append("%d × %s" % [int(a.magazines[wid]), spec.display_name if spec != null else wid])
	_aircraft_detail.text = "%s  /  %s  ·  %s  ·  Fuel %d%% (%.0f min at cruise)  ·  %.0f m  ·  %.0f kn\n%s" % [a.callsign, a.spec.display_name, status_text(a), int(a.fuel_fraction() * 100.0), a.fuel_s / 60.0, a.altitude_m, a.speed_kn, ", ".join(stores) if not stores.is_empty() else "No expendable weapons carried"]
	if a.airborne():
		_destinations = simulation.aviation_manager.available_recovery_bases(a)
	for base in _destinations:
		var kind := "AIRFIELD" if base.spec.flight_facility() == "airfield" else "DECK"
		_destination.add_item("%s / %s / %.0f nm" % [base.callsign, kind, a.position.distance_to(base.position)])
	var preferred := previous if _destinations.has(previous) else a.recovery_base if a.recovery_base != null else a.home
	if _destinations.has(preferred):
		_destination.select(_destinations.find(preferred))
	if _destinations.is_empty():
		_destination.add_item("No compatible destination" if a.airborne() else "Available when airborne")
	_destination.disabled = _destinations.is_empty()
	_refresh_recovery_hint()


func _refresh_recovery_hint() -> void:
	_return.disabled = _aircraft == null or not _aircraft.airborne() or _destinations.is_empty()
	if not _return.disabled:
		var base := _destinations[_destination.selected]
		var reason := simulation.aviation_manager.recovery_rejection_reason(_aircraft, base)
		_return.disabled = reason != ""
		_return.tooltip_text = reason if reason != "" else "Return to %s, land, then refuel and rearm. Replaces the aircraft's current route." % base.callsign
	else:
		_return.tooltip_text = "Select an airborne aircraft and a compatible friendly carrier or airfield."


func _return_selected() -> void:
	if _return.disabled:
		return
	order_requested.emit(_aircraft, Order.return_to_base(_destinations[_destination.selected]))
	refresh()


func _refresh_missions() -> void:
	if _missions == null:
		return
	_missions.clear()
	var root := _missions.create_item()
	var amm := simulation.air_mission_manager
	var list := amm.active_missions(simulation.player_faction)
	if not list.has(_selected_mission):
		_selected_mission = list[0] if not list.is_empty() else null
	for m in list:
		var head := _missions.create_item(root)
		head.set_metadata(0, m)
		head.set_text(0, "%s %d  ·  %d × %s" % [m.kind_name(), m.id, m.requested, DataDB.platform(m.platform_id).short_name])
		head.set_text(1, m.summary().trim_prefix(m.kind_name() + " · "))
		head.set_text(3, m.base_callsign)
		head.set_tooltip_text(0, m.note)
		for row: Dictionary in m.board_rows():
			var child := _missions.create_item(head)
			child.set_metadata(0, m)
			var a: Unit = row["aircraft"]
			child.set_text(0, "   " + (a.callsign if a != null else "(awaiting launch)"))
			child.set_text(1, str(row["state"]))
			child.set_text(2, "%d%%" % int(a.fuel_fraction() * 100.0) if a != null else "")
			var state := str(row["state"])
			child.set_custom_color(1, UITheme.INK_GREEN if state == AirMission.ON_STATION else UITheme.INK_AMBER if state in [AirMission.RETURNING, AirMission.REFUELLING, AirMission.QUEUED, AirMission.HOLDING] else UITheme.INK)
		if m == _selected_mission:
			head.select(0)
	_refresh_mission_detail()


func _refresh_mission_detail() -> void:
	if _mission_detail == null:
		return
	_cancel_mission.disabled = _selected_mission == null or not _selected_mission.active
	if _selected_mission == null:
		_mission_detail.text = "No missions. Choose a mission above, place it on the chart, then ASSIGN MISSION."
		return
	var m := _selected_mission
	var where := "track %s" % m.target_id if m.kind == AirMission.Kind.STRIKE else "%.0f nm radius" % m.radius_nm
	_mission_detail.text = "%s from %s, %s%s%s.\nLast report: %s" % [m.label(), m.base_callsign, where, " · relief from reserve" if m.relief else "", " · back to station after a task" if m.auto_return and m.kind != AirMission.Kind.STRIKE else "", m.note]


func _cancel_selected_mission() -> void:
	if _selected_mission == null or not _selected_mission.active or _selected_mission.base == null:
		return
	order_requested.emit(_selected_mission.base, Order.cancel_air_mission(_selected_mission.id))
	refresh()


func show_receipt(message: String, accepted: bool) -> void:
	_receipt.text = message
	_receipt.add_theme_color_override("font_color", UITheme.INK_GREEN if accepted else UITheme.INK_RED)
