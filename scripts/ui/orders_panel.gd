class_name OrdersPanel
extends PanelContainer
## Bottom panel: movement, sensor and weapon orders for the current selection.
## Emits Order objects only; Main routes them to UnitManager for controllable units.

signal order_requested(order: Order)
signal weapon_selection_changed(spec: WeaponSpec)
signal formation_requested(pattern: String)

const SPEED_PRESETS: Array[float] = [5.0, 10.0, 15.0, 20.0, 25.0]

var _status: Label
var _buttons: Array[Button] = []
var _heading: SpinBox
var _weapon_option: OptionButton
var _salvo: SpinBox
var _engage_btn: Button
var _envelope: Label
var _controllable := false
var _units: Array = []
var _target: Track = null
var _weapon_ids: PackedStringArray = []
var _refresh_accum := 0.0
var _subrow: HBoxContainer
var _cmdrow: HBoxContainer
var _depth_buttons: Array[Button] = []
var _alt_buttons: Array[Button] = []
var _sonar_buttons: Array[Button] = []
var _depth_label: Label
var _alt_label: Label
var _sonar_label: Label
var _launch_btn: Button
var _rtb_btn: Button
var _buoy_btn: Button
var _mag_signature := ""


func _ready() -> void:
	var v := VBoxContainer.new()
	add_child(v)
	_status = Label.new()
	_status.clip_text = true
	v.add_child(_status)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)

	row.add_child(_label("SPEED"))
	_add_button(row, "STOP", func() -> void: _emit(Order.stop()))
	for kn in SPEED_PRESETS:
		_add_button(row, "%d" % int(kn), func() -> void: _emit(Order.set_speed(kn)))
	_add_button(row, "FLANK", func() -> void: _emit(Order.set_speed(999.0)))

	row.add_child(_spacer(16))
	row.add_child(_label("COURSE"))
	_heading = SpinBox.new()
	_heading.min_value = 0
	_heading.max_value = 359
	_heading.step = 1
	_heading.suffix = "°"
	_heading.custom_minimum_size.x = 86
	row.add_child(_heading)
	_add_button(row, "SET", func() -> void: _emit(Order.set_course(_heading.value)))
	_add_button(row, "CLR WPTS", func() -> void: _emit(Order.clear_waypoints()))

	row.add_child(_spacer(16))
	row.add_child(_label("RADAR"))
	_add_button(row, "ON", func() -> void: _emit(Order.activate_radar()))
	_add_button(row, "OFF", func() -> void: _emit(Order.silence_radar()))

	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 6)
	v.add_child(wrow)

	wrow.add_child(_label("WEAPON"))
	_weapon_option = OptionButton.new()
	_weapon_option.focus_mode = Control.FOCUS_NONE
	_weapon_option.custom_minimum_size.x = 190
	_weapon_option.clip_text = true
	_weapon_option.item_selected.connect(func(_i: int) -> void: _refresh_envelope())
	wrow.add_child(_weapon_option)

	wrow.add_child(_label("SALVO"))
	_salvo = SpinBox.new()
	_salvo.min_value = 1
	_salvo.max_value = 16
	_salvo.value = 2
	_salvo.custom_minimum_size.x = 70
	wrow.add_child(_salvo)

	_engage_btn = Button.new()
	_engage_btn.text = "ENGAGE"
	_engage_btn.focus_mode = Control.FOCUS_NONE
	_engage_btn.pressed.connect(_on_engage)
	wrow.add_child(_engage_btn)

	_envelope = Label.new()
	# Let this shrink instead of forcing the whole window wider than it is.
	_envelope.clip_text = true
	_envelope.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_envelope.custom_minimum_size.x = 0
	wrow.add_child(_envelope)

	_subrow = HBoxContainer.new()
	_subrow.add_theme_constant_override("separation", 6)
	v.add_child(_subrow)
	_depth_label = _label("DEPTH")
	_subrow.add_child(_depth_label)
	_add_depth_button("SURFACE", 0.0)
	_add_depth_button("PERISCOPE", 18.0)
	_add_depth_button("SHALLOW", 60.0)
	_add_depth_button("PATROL", -1.0)
	_add_depth_button("DEEP", 200.0)
	_alt_label = _label("ALT")
	_subrow.add_child(_alt_label)
	_add_alt_button("LOW", 150.0)
	_add_alt_button("CRUISE", -1.0)
	_add_alt_button("HIGH", -2.0)
	_launch_btn = _make_button("LAUNCH", func() -> void: _emit_raw(Order.launch_aircraft()))
	_subrow.add_child(_launch_btn)
	_rtb_btn = _make_button("RTB", func() -> void: _emit_raw(Order.return_to_base()))
	_subrow.add_child(_rtb_btn)
	_buoy_btn = _make_button("BUOY", func() -> void: _emit_raw(Order.deploy_sonobuoy()))
	_subrow.add_child(_buoy_btn)

	_subrow.add_child(_spacer(16))
	_sonar_label = _label("SONAR")
	_subrow.add_child(_sonar_label)
	_sonar_buttons.append(_add_button(_subrow, "PING", func() -> void: _emit(Order.active_sonar())))
	_sonar_buttons.append(_add_button(_subrow, "PASSIVE", func() -> void: _emit(Order.passive_sonar())))

	_cmdrow = HBoxContainer.new()
	_cmdrow.add_theme_constant_override("separation", 6)
	v.add_child(_cmdrow)
	_cmdrow.add_child(_label("EMCON"))
	_add_button(_cmdrow, "RADIATE", func() -> void: _emit_raw(Order.set_emcon(false)))
	_add_button(_cmdrow, "SILENT", func() -> void: _emit_raw(Order.set_emcon(true)))
	_cmdrow.add_child(_spacer(14))
	_cmdrow.add_child(_label("WEAPONS"))
	_add_button(_cmdrow, "HOLD", func() -> void: _emit_raw(Order.set_roe(Unit.Roe.HOLD)))
	_add_button(_cmdrow, "TIGHT", func() -> void: _emit_raw(Order.set_roe(Unit.Roe.TIGHT)))
	_add_button(_cmdrow, "FREE", func() -> void: _emit_raw(Order.set_roe(Unit.Roe.FREE)))
	_cmdrow.add_child(_spacer(14))
	_cmdrow.add_child(_label("FORM"))
	for pattern in ["screen", "column", "abreast"]:
		_add_button(_cmdrow, pattern.to_upper(), func() -> void: formation_requested.emit(pattern))
	_add_button(_cmdrow, "BREAK", func() -> void: _emit_raw(Order.break_formation()))

	set_units([], false)


func _process(delta: float) -> void:
	_refresh_accum += delta
	if _refresh_accum >= 0.3:
		_refresh_accum = 0.0
		if _controllable:
			if _magazine_signature() != _mag_signature:
				_rebuild_weapons()
			else:
				_refresh_envelope()


func set_units(units: Array, controllable: bool) -> void:
	_units = units.duplicate()
	_controllable = controllable and not units.is_empty()
	for b in _buttons:
		b.disabled = not _controllable
	_heading.editable = _controllable
	if units.is_empty():
		_status.text = "ORDERS — no selection"
	elif not controllable:
		_status.text = "ORDERS — selection is not under your command"
	elif units.size() == 1:
		_status.text = "ORDERS — %s" % units[0].callsign
		_heading.value = roundf(units[0].ordered_heading_deg)
	else:
		_status.text = "ORDERS — %d units" % units.size()
	_refresh_row_visibility()
	_rebuild_weapons()


## The third row serves submarines, aircraft and aviation-capable ships. Only the controls that
## mean something for the current selection are shown, so the row is not a wall of dead buttons.
func _refresh_row_visibility() -> void:
	var can_dive := false
	var has_sonar := false
	var is_air := false
	var can_launch := false
	var has_buoys := false
	for u: Unit in _units:
		if u.spec.max_depth_m > 0.0:
			can_dive = true
		if u.has_sonar():
			has_sonar = true
		if u.is_aircraft():
			is_air = true
			if u.sonobuoys > 0:
				has_buoys = true
		if u.spec.aircraft_capacity > 0 and not u.stowed_aircraft().is_empty():
			can_launch = true
	_subrow.visible = can_dive or has_sonar or is_air or can_launch
	_depth_label.visible = can_dive
	for b in _depth_buttons:
		b.visible = can_dive
	_alt_label.visible = is_air
	for b in _alt_buttons:
		b.visible = is_air
	_launch_btn.visible = can_launch
	_rtb_btn.visible = is_air
	_buoy_btn.visible = has_buoys
	_sonar_label.visible = has_sonar
	for b in _sonar_buttons:
		b.visible = has_sonar


## Cheap change detector so spent magazines are reflected in the weapon list without rebuilding
## the dropdown every frame.
func _magazine_signature() -> String:
	var parts := PackedStringArray()
	for u: Unit in _units:
		for wid in _weapon_ids:
			parts.append("%d" % u.magazine_count(wid))
	return ",".join(parts)


## Depth controls only make sense for something that can dive, and pinging only for something
## with a sonar, so the row hides itself the rest of the time.
## Altitude presets. A negative value means "whatever this airframe calls cruise", or its ceiling.
func _add_alt_button(text: String, metres: float) -> void:
	var b := _make_button(text, func() -> void: _emit_altitude(metres))
	_subrow.add_child(b)
	_alt_buttons.append(b)


func _emit_altitude(metres: float) -> void:
	for u: Unit in _units:
		if not u.is_aircraft():
			continue
		var wanted := metres
		if metres == -1.0:
			wanted = u.spec.cruise_altitude_m
		elif metres == -2.0:
			wanted = u.spec.max_altitude_m
		order_requested.emit(Order.set_altitude(clampf(wanted, 0.0, u.spec.max_altitude_m)))
		return


func _make_button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_pressed)
	_buttons.append(b)
	return b


## Orders that are not weapon orders still need the controllable gate.
func _emit_raw(order: Order) -> void:
	if _controllable:
		order_requested.emit(order)


func _add_depth_button(text: String, metres: float) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void: _emit_depth(metres))
	_subrow.add_child(b)
	_buttons.append(b)
	_depth_buttons.append(b)


## A negative value means "whatever this boat calls its patrol depth".
func _emit_depth(metres: float) -> void:
	if _units.is_empty():
		return
	for u: Unit in _units:
		if u.spec.max_depth_m > 0.0:
			var wanted := u.spec.patrol_depth_m if metres < 0.0 else metres
			order_requested.emit(Order.set_depth(clampf(wanted, 0.0, u.spec.max_depth_m)))
			return


func set_target_track(t: Track) -> void:
	var changed := t != _target
	_target = t
	if changed:
		_rebuild_weapons()
	else:
		_refresh_envelope()


func current_weapon_spec() -> WeaponSpec:
	var i := _weapon_option.selected
	if i < 0 or i >= _weapon_ids.size():
		return null
	return DataDB.weapon(_weapon_ids[i])


func refresh() -> void:
	_refresh_envelope()


func _rebuild_weapons() -> void:
	var previous := ""
	if _weapon_option.selected >= 0 and _weapon_option.selected < _weapon_ids.size():
		previous = _weapon_ids[_weapon_option.selected]
	_weapon_option.clear()
	_weapon_ids = PackedStringArray()
	if _controllable:
		# Every weapon carried by any selected unit. An ENGAGE order is applied only to the
		# units that actually carry it, so a mixed task force still has usable options.
		for u: Unit in _units:
			# With a contact selected, offer what actually suits it. Without one, the anti-surface
			# weapons are the sensible default to look at.
			var options: Array = u.weapons_for_track(_target) if _target != null else u.offensive_weapons()
			for spec: WeaponSpec in options:
				if not _weapon_ids.has(spec.id):
					_weapon_ids.append(spec.id)
	for i in _weapon_ids.size():
		var spec := DataDB.weapon(_weapon_ids[i])
		var rounds := 0
		var carriers := 0
		for u: Unit in _units:
			rounds += u.magazine_count(spec.id)
			if u.get_weapon(spec.id) != null:
				carriers += 1
		var suffix := "  [%d]" % rounds if carriers == _units.size() else "  [%d, %d ship(s)]" % [rounds, carriers]
		_weapon_option.add_item(spec.display_name + suffix)
		if _weapon_ids[i] == previous:
			_weapon_option.select(i)
	_weapon_option.disabled = _weapon_ids.is_empty()
	_mag_signature = _magazine_signature()
	_refresh_envelope()


func _refresh_envelope() -> void:
	var spec := current_weapon_spec()
	weapon_selection_changed.emit(spec)
	if not _controllable or spec == null:
		_engage_btn.disabled = true
		_envelope.text = ""
		return
	_salvo.max_value = maxi(spec.salvo_default * 2, 1)
	if _target == null:
		_engage_btn.disabled = true
		_envelope.text = "no target — select a contact"
		_envelope.modulate = Color(0.6, 0.7, 0.78)
		return
	var ready := 0
	var reason := ""
	var nearest := INF
	var farthest := 0.0
	var carriers := 0
	for u: Unit in _units:
		if u.get_weapon(spec.id) == null:
			continue
		carriers += 1
		var check := Combat.check_engagement(u, spec, _target)
		nearest = minf(nearest, check["range_nm"])
		farthest = maxf(farthest, check["range_nm"])
		if check["ok"]:
			ready += 1
		else:
			reason = check["reason"]
	_engage_btn.disabled = ready == 0
	if carriers == 0:
		_envelope.text = "no selected ship carries this weapon"
		_envelope.modulate = Color(1.0, 0.6, 0.45)
	elif ready > 0:
		var tof := Combat.time_of_flight_s(spec, farthest)
		_envelope.text = "%s  RNG %.1f-%.1f / %.0f nm  ·  %s to target  —  %d of %d in envelope" % [_target.id, nearest, farthest, spec.max_range_nm, _fmt_tof(tof), ready, carriers]
		_envelope.modulate = Color(0.5, 1.0, 0.6) if tof < 480.0 else Color(0.95, 0.85, 0.45)
	else:
		_envelope.text = "%s  RNG %.1f / %.0f nm  —  %s" % [_target.id, nearest, spec.max_range_nm, reason]
		_envelope.modulate = Color(1.0, 0.6, 0.45)


func _fmt_tof(seconds: float) -> String:
	if seconds < 90.0:
		return "%ds" % int(seconds)
	return "%dm%02ds" % [int(seconds / 60.0), int(seconds) % 60]


func _on_engage() -> void:
	var spec := current_weapon_spec()
	if spec == null or _target == null:
		return
	_emit(Order.engage(_target, spec.id, int(_salvo.value)))
	_rebuild_weapons()


func _emit(order: Order) -> void:
	if _controllable:
		order_requested.emit(order)


func _add_button(parent: Node, text: String, on_pressed: Callable) -> Button:
	var b := _make_button(text, on_pressed)
	parent.add_child(b)
	return b


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Color(0.6, 0.75, 0.85)
	return l


func _spacer(px: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.x = px
	return c
