class_name AirOperations
extends PanelContainer
## Own-force air plan. Commands always go through Main and UnitManager.
signal closed(execute: bool)
signal order_requested(unit: Unit, order: Order)
signal aircraft_selected(aircraft: Unit)

var simulation: Simulation
var _base_picker: OptionButton
var _types: ItemList
var _portrait: TextureRect
var _type_detail: Label
var _count: SpinBox
var _launch: Button
var _launch_hint: Label
var _roster: Tree
var _aircraft_detail: Label
var _destination: OptionButton
var _return: Button
var _focus: Button
var _receipt: Label
var _summary: Label
var _back: Button
var _bases: Array[Unit] = []
var _destinations: Array[Unit] = []
var _type_ids: Array[String] = []
var _base: Unit
var _aircraft: Unit
var _destination_aircraft: Unit
var _type_id := ""
var _accum := 0.0


func _ready() -> void:
	theme_type_variation = "OverlayPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	margin.add_child(page)
	var header := HBoxContainer.new()
	page.add_child(header)
	var title := _label("AIR OPERATIONS", 32)
	title.add_theme_font_override("font", UITheme.heading_font())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_back = _button("RETURN TO CHART  /  F3", func() -> void: closed.emit(false))
	header.add_child(_back)
	_summary = _label("", 16)
	_summary.add_theme_color_override("font_color", UITheme.COL_ACCENT)
	page.add_child(_summary)
	var hint := _label("Plan while paused. Select a host and aircraft type to launch; select an airframe and destination to return and land.", 14)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(hint)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	var launch_column := VBoxContainer.new()
	launch_column.custom_minimum_size.x = 370
	launch_column.size_flags_stretch_ratio = 0.36
	launch_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	launch_column.add_theme_constant_override("separation", 10)
	body.add_child(launch_column)
	launch_column.add_child(_label("01  /  PREPARE A SORTIE", 18))
	_base_picker = OptionButton.new()
	_base_picker.custom_minimum_size.y = 44
	_base_picker.clip_text = true
	_base_picker.accessibility_name = "Launch carrier or airfield"
	_base_picker.item_selected.connect(func(i: int) -> void:
		_base = _bases[i] if i >= 0 and i < _bases.size() else null
		_type_id = ""
		_refresh_types())
	launch_column.add_child(_base_picker)
	_types = ItemList.new()
	_types.custom_minimum_size.y = 180
	_types.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_types.add_theme_constant_override("v_separation", 12)
	_types.accessibility_name = "Embarked aircraft types and readiness"
	_types.item_selected.connect(func(i: int) -> void:
		_type_id = _type_ids[i]
		_refresh_launch())
	launch_column.add_child(_types)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size.y = 130
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	launch_column.add_child(_portrait)
	_type_detail = _label("", 14)
	_type_detail.custom_minimum_size.y = 78
	_type_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	launch_column.add_child(_type_detail)
	var launch_row := HBoxContainer.new()
	launch_column.add_child(launch_row)
	launch_row.add_child(_label("AIRCRAFT", 12))
	_count = SpinBox.new()
	_count.min_value = 1
	_count.max_value = 4
	_count.value = 1
	_count.custom_minimum_size = Vector2(80, 44)
	_count.accessibility_name = "Number of aircraft to launch"
	_count.value_changed.connect(func(_v: float) -> void: _refresh_launch())
	launch_row.add_child(_count)
	_launch = _button("LAUNCH SELECTED TYPE", _launch_selected)
	_launch.theme_type_variation = "PrimaryButton"
	_launch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	launch_row.add_child(_launch)
	_launch_hint = _label("", 13)
	_launch_hint.custom_minimum_size.y = 52
	_launch_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	launch_column.add_child(_launch_hint)
	var recovery_column := VBoxContainer.new()
	recovery_column.size_flags_stretch_ratio = 0.64
	recovery_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recovery_column.add_theme_constant_override("separation", 10)
	body.add_child(recovery_column)
	recovery_column.add_child(_label("02  /  MANAGE THE AIR WING", 18))
	_roster = Tree.new()
	_roster.hide_root = true
	_roster.columns = 5
	_roster.column_titles_visible = true
	_roster.select_mode = Tree.SELECT_ROW
	_roster.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_roster.custom_minimum_size.y = 220
	_roster.add_theme_constant_override("v_separation", 10)
	_roster.accessibility_name = "Friendly aircraft status roster"
	var columns := ["AIRFRAME / TYPE", "STATE", "FUEL", "BASE", "CYCLE"]
	for i in columns.size():
		_roster.set_column_title(i, columns[i])
	_roster.set_column_expand_ratio(0, 4)
	_roster.set_column_expand_ratio(1, 2)
	_roster.set_column_expand_ratio(3, 3)
	_roster.set_column_custom_minimum_width(2, 60)
	_roster.set_column_custom_minimum_width(4, 60)
	_roster.item_selected.connect(func() -> void:
		var item := _roster.get_selected()
		_aircraft = item.get_metadata(0) as Unit if item != null else null
		_refresh_recovery())
	recovery_column.add_child(_roster)
	_aircraft_detail = _label("Select an airframe to see fuel, ordnance and landing options.", 15)
	_aircraft_detail.custom_minimum_size.y = 100
	_aircraft_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	recovery_column.add_child(_aircraft_detail)
	var recovery_row := HBoxContainer.new()
	recovery_column.add_child(recovery_row)
	recovery_row.add_child(_label("LAND AT", 12))
	_destination = OptionButton.new()
	_destination.custom_minimum_size = Vector2(220, 44)
	_destination.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_destination.clip_text = true
	_destination.accessibility_name = "Recovery carrier or airfield"
	_destination.item_selected.connect(func(_i: int) -> void: _refresh_recovery_hint())
	recovery_row.add_child(_destination)
	_return = _button("RETURN & LAND", _return_selected)
	_return.theme_type_variation = "PrimaryButton"
	recovery_row.add_child(_return)
	_focus = _button("SHOW ON CHART", func() -> void:
		if _aircraft != null and _aircraft.is_engageable():
			aircraft_selected.emit(_aircraft))
	recovery_column.add_child(_focus)
	_receipt = _label("Choose an aircraft type. Launches use available deck spots; recovered aircraft must refuel and rearm before another sortie.", 14)
	_receipt.custom_minimum_size.y = 42
	_receipt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_receipt)
	var footer := HBoxContainer.new()
	page.add_child(footer)
	var note := _label("Return to chart restores your previous pause state. Execute & resume starts the clock at 1×.", 13)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(note)
	footer.add_child(_button("EXECUTE & RESUME", func() -> void: closed.emit(true)))


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 44
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(action)
	return b


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label


func open_for(selection: Array) -> void:
	_base = null
	_aircraft = null
	_destination_aircraft = null
	_type_id = ""
	for u: Unit in selection:
		if u.faction != simulation.player_faction or not u.alive:
			continue
		if u.is_aircraft():
			_aircraft = u
			_base = u.home
			_type_id = u.spec.id
			break
		if u.spec.aircraft_capacity > 0:
			_base = u
			break
	show()
	refresh()
	_base_picker.call_deferred("grab_focus")


func clear_selection() -> void:
	_base = null
	_aircraft = null
	_destination_aircraft = null
	_bases.clear()
	_destinations.clear()
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
	_summary.text = "%02d READY  /  %02d IN FLIGHT  /  %02d IN DECK CYCLE  /  %02d HOSTS    •    SIMULATION PAUSED" % [ready, flying, cycling, _bases.size()]
	_refresh_types()
	_refresh_roster()
	_refresh_recovery()


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
	_types.clear()
	_type_ids.clear()
	for group in inventory(_base):
		var spec := DataDB.platform(group["id"])
		_type_ids.append(spec.id)
		_types.add_item("%s   |   %d ready / %d total" % [spec.short_name, group["ready"], group["total"]])
		_types.set_item_tooltip(_type_ids.size() - 1, spec.display_name + "\n" + spec.role)
	if not _type_ids.has(_type_id):
		_type_id = _type_ids[0] if not _type_ids.is_empty() else ""
	if _type_id != "":
		_types.select(_type_ids.find(_type_id))
	_refresh_launch()


func _refresh_launch() -> void:
	if _launch == null or simulation == null:
		return
	var spec := DataDB.platform(_type_id) if _type_id != "" else null
	_portrait.texture = PlatformArt.beauty(_type_id) if spec != null else null
	if _base == null or spec == null:
		_launch.disabled = true
		_count.editable = false
		_type_detail.text = "No embarked aircraft. Choose another host, or load the Carrier Qualification exercise."
		_launch_hint.text = "No aircraft type selected."
		return
	_type_detail.text = "%s\n%s\n%s operations • %d kn cruise • %.0f min endurance" % [spec.display_name, spec.role, spec.flight_requirement().to_upper(), int(spec.cruise_speed_kn), spec.endurance_s / 60.0]
	var reason := simulation.aviation_manager.launch_rejection_reason(_base, _type_id)
	var ready := 0
	for a: Unit in _base.stowed_aircraft():
		if a.spec.id == _type_id:
			ready += 1
	var spots := maxi(_base.spec.launch_capacity() - _base.launch_spots_busy(), 0)
	var maximum := mini(ready, spots)
	_count.max_value = maxi(maximum, 1)
	_count.editable = reason == "" and maximum > 0
	_launch.disabled = reason != "" or maximum <= 0
	_launch_hint.text = reason if reason != "" else "%d ready • %d deck spots free. Launch %d × %s; airborne in about %.0f s after resuming." % [ready, spots, int(_count.value), spec.short_name, spec.launch_time_s]
	_launch.tooltip_text = _launch_hint.text


func _launch_selected() -> void:
	if _base == null or _type_id == "" or _launch.disabled:
		return
	order_requested.emit(_base, Order.launch_flight(_type_id, int(_count.value)))
	refresh()


static func status_text(a: Unit) -> String:
	match a.flight_state:
		Unit.FlightState.STOWED: return "READY"
		Unit.FlightState.LAUNCHING: return "LAUNCHING"
		Unit.FlightState.RECOVERING: return "LANDING"
		Unit.FlightState.TURNAROUND: return "REFUEL / REARM"
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
		item.set_custom_color(1, UITheme.COL_GREEN if a.ready_to_launch() else UITheme.COL_AMBER if a.returning else UITheme.COL_TEXT)
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
	_aircraft_detail.text = "%s  /  %s\n%s • Fuel %d%% (%.0f min at cruise) • %.0f m / %.0f kn\n%s" % [a.callsign, a.spec.display_name, status_text(a), int(a.fuel_fraction() * 100.0), a.fuel_s / 60.0, a.altitude_m, a.speed_kn, ", ".join(stores) if not stores.is_empty() else "No expendable weapons carried"]
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


func show_receipt(message: String, accepted: bool) -> void:
	_receipt.text = message
	_receipt.add_theme_color_override("font_color", UITheme.COL_GREEN if accepted else UITheme.COL_AMBER)
