class_name OrdersPanel
extends PanelContainer
## Bottom panel: movement, sensor and weapon orders for the current selection.
## Emits Order objects only; Main routes them to UnitManager for controllable units.

signal inspect_requested(weapon_id: String)
signal order_requested(order: Order)
signal weapon_selection_changed(spec: WeaponSpec)
signal formation_requested(pattern: String)
signal move_mode_requested(active: bool)
signal emcon_toggle_requested()
signal air_operations_requested()
## Orders whose value differs per platform, such as each airframe's own cruise altitude: an Array
## of [Unit, Order] pairs.
signal unit_orders_requested(pairs: Array)

const SPEED_PRESETS: Array[float] = [5.0, 10.0, 15.0, 20.0, 25.0]

var weapon_manager: WeaponManager
var _weapon_art: TextureRect
var _inspect_weapon: Button
var _status: Label
var _tabs: TabContainer
var _move_btn: Button
var _radar_toggle: Button
var _sonar_toggle: Button
var _emcon_toggle: Button
var _roe_btn: Button
var _engagement_tab_btn: Button
var _buttons: Array[Button] = []
var _movement_buttons: Array[Button] = []
var _heading: SpinBox
var _weapon_option: OptionButton
var _salvo: SpinBox
var _engage_btn: Button
var _envelope: Label
var _controllable := false
var _movable := false
var _command_authorized := false
var _movement_authorized := false
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
var _layer_btn: Button
var _alt_label: Label
var _sonar_label: Label
var _launch_btn: Button
var _air_ops_btn: Button
var _rtb_btn: Button
var _buoy_btn: Button
var _mag_signature := ""


func _ready() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	add_child(v)
	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 6)
	quick.custom_minimum_size.y = 34
	v.add_child(quick)
	var chain := VBoxContainer.new()
	chain.add_theme_constant_override("separation", 0)
	chain.alignment = BoxContainer.ALIGNMENT_CENTER
	chain.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chain.custom_minimum_size.x = 220
	quick.add_child(chain)
	chain.add_child(UITheme.eyebrow("Command"))
	_status = Label.new()
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.add_theme_font_override("font", UITheme.semibold_font())
	_status.add_theme_font_size_override("font_size", 13)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chain.add_child(_status)
	_move_btn = _quick_toggle("PLOT MOVE", "Arm a visible left-click move order. Shift adds waypoints; Escape cancels.  [G]", func() -> void:
		move_mode_requested.emit(_move_btn.button_pressed))
	UIIcons.apply(_move_btn, "route", 16)
	quick.add_child(_move_btn)
	_radar_toggle = _quick_toggle("RADAR", "Toggle search radar for each selected platform that carries one.  [R]", _toggle_radar)
	quick.add_child(_radar_toggle)
	_sonar_toggle = _quick_toggle("SONAR", "Toggle active sonar for each selected platform that carries one.  [P]", _toggle_sonar)
	quick.add_child(_sonar_toggle)
	_emcon_toggle = _quick_toggle("EMCON", "Emission control. Silent shuts down radar, active sonar and jammers.  [E]", _toggle_emcon)
	quick.add_child(_emcon_toggle)
	_roe_btn = _quick_button("WPNS —", "Current weapons posture. Opens Doctrine + Formation to change it.", func() -> void: _tabs.current_tab = 3)
	quick.add_child(_roe_btn)
	_engagement_tab_btn = _quick_button("ENGAGE", "Open the engagement solution for the selected shooter and target.", open_engagement.bind(true))
	_engagement_tab_btn.theme_type_variation = "PrimaryButton"
	UIIcons.apply(_engagement_tab_btn, "target", 16)
	quick.add_child(_engagement_tab_btn)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.tab_changed.connect(func(_t: int) -> void: _sync_engage_emphasis())
	v.add_child(_tabs)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.name = "NAVIGATION"
	row.custom_minimum_size.y = 34
	_tabs.add_child(row)

	row.add_child(_label("SPEED"))
	_movement_buttons.append(_add_button(row, "STOP", func() -> void: _emit(Order.stop())))
	for kn in SPEED_PRESETS:
		_movement_buttons.append(_add_button(row, "%d" % int(kn), func() -> void: _emit(Order.set_speed(kn))))
	_movement_buttons.append(_add_button(row, "FLANK", func() -> void: _emit(Order.set_speed(999.0))))

	row.add_child(_spacer(16))
	row.add_child(_label("COURSE"))
	_heading = SpinBox.new()
	_heading.min_value = 0
	_heading.max_value = 359
	_heading.step = 1
	_heading.suffix = "°"
	_heading.custom_minimum_size.x = 86
	row.add_child(_heading)
	_movement_buttons.append(_add_button(row, "SET", func() -> void: _emit(Order.set_course(_heading.value))))
	_movement_buttons.append(_add_button(row, "CLR WPTS", func() -> void: _emit(Order.clear_waypoints())))

	row.add_child(_spacer(16))
	row.add_child(_label("RADAR"))
	_add_button(row, "ON", func() -> void: _emit(Order.activate_radar()))
	_add_button(row, "OFF", func() -> void: _emit(Order.silence_radar()))

	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 6)
	wrow.name = "ENGAGEMENT"
	wrow.custom_minimum_size.y = 34
	_tabs.add_child(wrow)

	wrow.add_child(_label("WEAPON"))
	_weapon_option = OptionButton.new()
	_weapon_option.focus_mode = Control.FOCUS_ALL
	_weapon_option.custom_minimum_size.x = 190
	_weapon_option.clip_text = true
	_weapon_option.item_selected.connect(func(_i: int) -> void: _refresh_envelope())
	wrow.add_child(_weapon_option)
	_weapon_art = TextureRect.new()
	_weapon_art.custom_minimum_size = Vector2(90, 40)
	_weapon_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_weapon_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wrow.add_child(_weapon_art)
	_inspect_weapon = Button.new()
	_inspect_weapon.theme_type_variation = "QuietButton"
	_inspect_weapon.tooltip_text = "Inspect this weapon in the recognition library"
	_inspect_weapon.accessibility_name = "Inspect weapon"
	UIIcons.apply(_inspect_weapon, "eye", 18)
	_inspect_weapon.pressed.connect(func() -> void:
		var spec := current_weapon_spec()
		if spec != null:
			inspect_requested.emit(spec.id))
	wrow.add_child(_inspect_weapon)

	wrow.add_child(_label("SALVO"))
	_salvo = SpinBox.new()
	_salvo.min_value = 1
	_salvo.max_value = 16
	_salvo.value = 2
	_salvo.custom_minimum_size.x = 70
	wrow.add_child(_salvo)

	_engage_btn = Button.new()
	_engage_btn.text = "ENGAGE"
	_engage_btn.theme_type_variation = "PrimaryButton"
	_engage_btn.focus_mode = Control.FOCUS_ALL
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
	_subrow.name = "AVIATION + ASW"
	_subrow.custom_minimum_size.y = 34
	_tabs.add_child(_subrow)
	_depth_label = _label("DEPTH")
	_subrow.add_child(_depth_label)
	_add_depth_button("SURFACE", 0.0)
	_add_depth_button("PERISCOPE", 18.0)
	_add_depth_button("SHALLOW", 60.0)
	_add_depth_button("PATROL", -1.0)
	_add_depth_button("DEEP", 200.0)
	_layer_btn = _add_depth_button("UNDER LAYER", -2.0)
	_alt_label = _label("ALT")
	_subrow.add_child(_alt_label)
	_add_alt_button("LOW", 150.0)
	_add_alt_button("CRUISE", -1.0)
	_add_alt_button("HIGH", -2.0)
	_launch_btn = _make_button("SELECT & LAUNCH", func() -> void: air_operations_requested.emit())
	_subrow.add_child(_launch_btn)
	_launch_btn.tooltip_text = "Choose aircraft type and sortie size in Air Operations."
	_air_ops_btn = _make_button("AIR WING", func() -> void: air_operations_requested.emit())
	_subrow.add_child(_air_ops_btn)
	_rtb_btn = _make_button("RETURN & LAND", func() -> void: air_operations_requested.emit())
	_rtb_btn.tooltip_text = "Choose a friendly carrier or airfield and order this aircraft to land."
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
	_cmdrow.name = "DOCTRINE + FORMATION"
	_cmdrow.custom_minimum_size.y = 34
	_tabs.add_child(_cmdrow)
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

	_tabs.current_tab = 0
	set_units([], false)


func _quick_button(text: String, tip: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.custom_minimum_size.y = 34
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(on_pressed)
	_buttons.append(button)
	return button


func _quick_toggle(text: String, tip: String, on_pressed: Callable) -> Button:
	var button := _quick_button(text, tip, on_pressed)
	button.toggle_mode = true
	return button


func _selection_state(kind: String) -> int:
	var capable := 0
	var active := 0
	for u: Unit in _units:
		var supported := true
		var on := false
		match kind:
			"radar":
				supported = u.has_radar()
				on = u.radar_on
			"sonar":
				supported = u.has_sonar()
				on = u.active_sonar_on
			"emcon":
				on = u.emcon == Unit.Emcon.SILENT
		if not supported:
			continue
		capable += 1
		if on:
			active += 1
	if capable == 0:
		return -1
	if active == 0:
		return 0
	if active == capable:
		return 1
	return 2


func _toggle_radar() -> void:
	_emit_raw(Order.silence_radar() if _selection_state("radar") == 1 else Order.activate_radar())


func _toggle_sonar() -> void:
	_emit_raw(Order.passive_sonar() if _selection_state("sonar") == 1 else Order.active_sonar())


func _toggle_emcon() -> void:
	if _controllable:
		emcon_toggle_requested.emit()


func _sync_quick_actions() -> void:
	if _move_btn == null:
		return
	_move_btn.disabled = not _movable
	if not _movable:
		_move_btn.set_pressed_no_signal(false)
	var radar := _selection_state("radar")
	_radar_toggle.visible = radar >= 0
	_radar_toggle.disabled = not _controllable or radar < 0
	_radar_toggle.set_pressed_no_signal(radar == 1)
	_radar_toggle.text = "RADAR %s" % ("ON" if radar == 1 else ("MIXED" if radar == 2 else "OFF"))
	_mark_mixed(_radar_toggle, radar == 2)
	var sonar := _selection_state("sonar")
	_sonar_toggle.visible = sonar >= 0
	_sonar_toggle.disabled = not _controllable or sonar < 0
	_sonar_toggle.set_pressed_no_signal(sonar == 1)
	_sonar_toggle.text = "SONAR %s" % ("ACTIVE" if sonar == 1 else ("MIXED" if sonar == 2 else "PASSIVE"))
	_mark_mixed(_sonar_toggle, sonar == 2)
	var emcon := _selection_state("emcon")
	_emcon_toggle.disabled = not _controllable
	_emcon_toggle.set_pressed_no_signal(emcon == 1)
	_emcon_toggle.text = "EMCON %s" % ("SILENT" if emcon == 1 else ("MIXED" if emcon == 2 else "FREE"))
	_mark_mixed(_emcon_toggle, emcon == 2)
	var roe := -1
	var roe_mixed := false
	for u: Unit in _units:
		if roe < 0:
			roe = u.roe
		elif roe != u.roe:
			roe_mixed = true
	var roe_text: String = "MIXED" if roe_mixed else (["HOLD", "TIGHT", "FREE"][roe] if roe >= 0 else "—")
	_roe_btn.text = "WPNS %s" % roe_text
	var roe_col := UITheme.COL_AMBER if roe_mixed or roe == Unit.Roe.TIGHT else (UITheme.COL_RED if roe == Unit.Roe.HOLD else UITheme.COL_TEXT)
	for key in ["font_color", "font_hover_color", "font_focus_color"]:
		_roe_btn.add_theme_color_override(key, roe_col)
	_roe_btn.disabled = not _controllable
	_engagement_tab_btn.disabled = not _controllable
	_engagement_tab_btn.text = ("ENGAGE " + _target.id) if _target != null else "ENGAGE"
	_sync_engage_emphasis()
	_refresh_status()


## A MIXED selection state reads amber without tinting the whole button.
func _mark_mixed(button: Button, mixed: bool) -> void:
	for key in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		if mixed:
			button.add_theme_color_override(key, UITheme.COL_AMBER)
		else:
			button.remove_theme_color_override(key)


## Only one primary action at a time: the dock's ENGAGE shortcut steps back once the engagement
## tab and its own ENGAGE button are showing.
func _sync_engage_emphasis() -> void:
	if _engagement_tab_btn == null or _tabs == null:
		return
	var on_tab := _tabs.current_tab == 1
	# Primary only once there is something to engage.
	_engagement_tab_btn.theme_type_variation = "PrimaryButton" if _target != null and not on_tab else ""
	_engagement_tab_btn.visible = not on_tab


func _refresh_status() -> void:
	if _units.is_empty():
		_status.text = "Select a platform on the chart or in the task group"
	elif not _controllable:
		_status.text = "Selection is not under your command"
	else:
		var shooter: String = _units[0].callsign if _units.size() == 1 else "%d platforms" % _units.size()
		var target: String = "select a contact" if _target == null else "%s  ·  %s %s" % [_target.id, _target.identity.to_lower(), _target.domain.to_lower()]
		_status.text = "%s  →  %s" % [shooter, target]
		_status.tooltip_text = "Command chain: selected shooter → selected target → appropriate weapon → engage."


func set_move_mode(active: bool) -> void:
	if _move_btn != null:
		_move_btn.set_pressed_no_signal(active and _movable)


## Shows the engagement tab. Keyboard focus moves to the weapon list only when the player asked
## for the tab explicitly; hooking a contact must leave the chart's keys working.
func open_engagement(take_focus := false) -> void:
	if _tabs != null:
		_tabs.current_tab = 1
		if take_focus and _weapon_option != null and not _weapon_option.disabled:
			_weapon_option.grab_focus()


func _process(delta: float) -> void:
	_refresh_accum += delta
	if _refresh_accum >= 0.3:
		_refresh_accum = 0.0
		_sync_live_eligibility()
		_sync_quick_actions()
		if _controllable:
			if _magazine_signature() != _mag_signature:
				_rebuild_weapons()
			else:
				_refresh_envelope()


func set_units(units: Array, controllable: bool, movable := controllable) -> void:
	_units = units.duplicate()
	_command_authorized = controllable and not units.is_empty()
	_movement_authorized = movable and _command_authorized
	_sync_live_eligibility(true)
	if units.size() == 1:
		_heading.value = roundf(units[0].ordered_heading_deg)
	_sync_quick_actions()


## Ownership and hull capability persist while an aircraft changes deck state; active command
## eligibility does not. Refreshing this on the dock cadence prevents a landed aircraft from
## leaving Plot Move (or any other order) visibly armed against an object no longer on the map.
func _sync_live_eligibility(force := false) -> void:
	var next_controllable := _command_authorized
	if next_controllable:
		for u: Unit in _units:
			if not u.alive or not u.is_engageable():
				next_controllable = false
				break
	var next_movable := _movement_authorized and next_controllable
	if next_movable:
		for u: Unit in _units:
			if u.spec.max_speed_kn <= 0.0 or (u.is_aircraft() and not u.airborne()):
				next_movable = false
				break
	var changed := next_controllable != _controllable or next_movable != _movable
	_controllable = next_controllable
	_movable = next_movable
	if not changed and not force:
		# Deck readiness and consumables can change even while ownership/deployment does not.
		_refresh_row_visibility()
		return
	for b in _buttons:
		b.disabled = not _controllable
	for b in _movement_buttons:
		b.disabled = not _movable
	_heading.editable = _movable
	_refresh_row_visibility()
	_rebuild_weapons()


## The third row serves submarines, aircraft and aviation-capable ships. Only the controls that
## mean something for the current selection are shown, so the row is not a wall of dead buttons.
func _refresh_row_visibility() -> void:
	var can_dive := false
	var has_sonar := false
	var is_air := false
	var can_launch := false
	var has_air_wing := false
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
		if u.spec.aircraft_capacity > 0:
			has_air_wing = true
			if not u.stowed_aircraft().is_empty():
				can_launch = true
	# Individual controls are hidden by capability; the tab remains stable.
	_depth_label.visible = can_dive
	for b in _depth_buttons:
		b.visible = can_dive
	if can_dive:
		_refresh_layer_button()
	_alt_label.visible = is_air
	for b in _alt_buttons:
		b.visible = is_air
	_launch_btn.visible = can_launch
	_air_ops_btn.visible = has_air_wing and not can_launch
	_rtb_btn.visible = is_air
	_buoy_btn.visible = has_buoys
	_sonar_label.visible = has_sonar
	for b in _sonar_buttons:
		b.visible = has_sonar


## The layer is a property of the water under the boat, so this follows it round the chart.
func _refresh_layer_button() -> void:
	var under := -1.0
	var floor_m := -1.0
	for u: Unit in _units:
		if u.spec.max_depth_m > 0.0:
			under = Acoustics.below_layer_depth_m(u)
			floor_m = Acoustics.bottom_m(u)
			break
	_layer_btn.disabled = not _controllable or under < 0.0
	if under >= 0.0:
		_layer_btn.tooltip_text = "Run at %d m, under the %d m layer. A hull sonar above it hears you poorly; a towed body, dipping set or deep buoy does not." % [int(under), int(Acoustics.layer_depth_m())]
	elif Acoustics.layer_depth_m() <= 0.0:
		_layer_btn.tooltip_text = "No layer in this water: it is mixed from the surface down."
	else:
		_layer_btn.tooltip_text = "The %d m layer is below what this boat can reach here (floor %s)." % [int(Acoustics.layer_depth_m()), Bathymetry.format_depth(floor_m)]


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
	var pairs: Array = []
	for u: Unit in _units:
		if not u.is_aircraft():
			continue
		var wanted := metres
		if metres == -1.0:
			wanted = u.spec.cruise_altitude_m
		elif metres == -2.0:
			wanted = u.spec.max_altitude_m
		pairs.append([u, Order.set_altitude(clampf(wanted, 0.0, u.spec.max_altitude_m))])
	if not pairs.is_empty():
		unit_orders_requested.emit(pairs)


func _make_button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 32
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(on_pressed)
	_buttons.append(b)
	return b


## Orders that are not weapon orders still need the controllable gate.
func _emit_raw(order: Order) -> void:
	if _controllable:
		order_requested.emit(order)


func _add_depth_button(text: String, metres: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 32
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func() -> void: _emit_depth(metres))
	_subrow.add_child(b)
	_buttons.append(b)
	_depth_buttons.append(b)
	return b


## -1 means "whatever this boat calls its patrol depth"; -2 means "under the layer, if there is
## one here to get under". The floor still has the last word in Movement.
func _emit_depth(metres: float) -> void:
	var pairs: Array = []
	for u: Unit in _units:
		if u.spec.max_depth_m > 0.0:
			var wanted := u.spec.patrol_depth_m if metres < 0.0 else metres
			if metres == -2.0:
				wanted = Acoustics.below_layer_depth_m(u)
				if wanted < 0.0:
					continue
			pairs.append([u, Order.set_depth(clampf(wanted, 0.0, u.spec.max_depth_m))])
	if not pairs.is_empty():
		unit_orders_requested.emit(pairs)


func set_target_track(t: Track) -> void:
	var changed := t != _target
	_target = t
	_sync_quick_actions()
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
	_weapon_art.texture = PlatformArt.thumbnail(spec.id, true) if spec != null else null
	_inspect_weapon.disabled = spec == null
	_salvo.editable = _controllable and spec != null and _target != null
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
		if check["ok"] and weapon_manager != null and spec.type == "sam" and _target.domain == "air" and not weapon_manager.channel_available(u, _target):
			check["ok"] = false
			check["reason"] = "FIRE CONTROL SATURATED"
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


## Fires the currently selected weapon at the current target if the shot is legal right now.
## Used by the tactical map's quick-engage gesture (ctrl+right-click a contact) so a shooter and
## target already lined up in this panel can be committed without reaching for the ENGAGE button.
## Returns false without effect if there is no controllable shooter, no target, or nothing in
## envelope, so the caller can tell the player why nothing happened.
func try_engage() -> bool:
	if _engage_btn.disabled:
		return false
	_on_engage()
	return true


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
	l.theme_type_variation = "HeaderLabel"
	l.add_theme_font_size_override("font_size", 10)
	return l


func _spacer(px: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.x = px
	return c
