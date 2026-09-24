class_name CommandOverview
extends HBoxContainer
## Actionable watch strip. Contact and threat summaries use the held picture.
signal orders_pressed()
signal contacts_pressed()
signal threat_pressed()
signal air_pressed()
signal chart_pressed()

var map: TacticalMap
var contacts: ContactPanel
var wide_chart := false
var _elapsed := 0.0
var _buttons: Array[Button] = []
var _heads: Array[Label] = []
var _values: Array[Label] = []

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var actions := [orders_pressed, contacts_pressed, threat_pressed, air_pressed, chart_pressed]
	var names := ["Mission orders", "Next priority contact", "Focus inbound weapon", "Open air operations", "Expand or restore tactical chart"]
	for i in actions.size():
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_stretch_ratio = 2.0 if i == 0 else 1.0
		button.focus_mode = Control.FOCUS_ALL
		button.accessibility_name = names[i]
		button.pressed.connect(func() -> void: actions[i].emit())
		add_child(button)
		_buttons.append(button)
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		margin.add_theme_constant_override("margin_left", 14)
		margin.add_theme_constant_override("margin_right", 14)
		margin.add_theme_constant_override("margin_top", 10)
		margin.add_theme_constant_override("margin_bottom", 8)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(margin)
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_theme_constant_override("separation", 4)
		margin.add_child(column)
		var head := Label.new()
		head.theme_type_variation = "HeaderLabel"
		head.add_theme_font_size_override("font_size", 14)
		head.clip_text = true
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(head)
		_heads.append(head)
		var value := Label.new()
		value.clip_text = true
		value.add_theme_font_size_override("font_size", 13)
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(value)
		_values.append(value)
	refresh()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.3:
		_elapsed = 0.0
		refresh()

func refresh() -> void:
	if map == null or map.unit_manager == null or _buttons.is_empty():
		return
	var air := 0
	var ready := 0
	for u: Unit in map.unit_manager.get_faction_units(map.player_faction):
		if not u.alive or not u.is_aircraft():
			continue
		if u.in_flight():
			air += 1
		elif u.flight_state == Unit.FlightState.STOWED:
			ready += 1
	var ref := map.reference_unit()
	var tracks := contacts.visible_tracks() if contacts != null else map._visible_tracks()
	var unknown := 0
	for t: Track in tracks:
		if t.identity == "UNKNOWN":
			unknown += 1
	var inbound := AirDefence.inbound_threats(map.unit_manager, map.threat_manager, map.player_faction, ref).size()
	var scenario: Dictionary = map.simulation.scenario if map.simulation != null else {}
	var intent := str(scenario.get("commander_intent", "Read the mission and review objective progress."))
	_set_card(0, "COMMANDER'S ORDERS  /  F1", intent, UITheme.COL_AMBER, "Open mission orders and live objectives.\n" + intent)
	var filter_name := contacts._filter if contacts != null else "ALL"
	_set_card(1, "CONTACTS: %s  /  N" % filter_name, "%d held · %d unknown" % [tracks.size(), unknown], UITheme.COL_ACCENT, "Cycle the next priority contact in the selected filter. Unknown contacts require classification.\nPicture: " + ("shared link" if ref == null or ref.datalink_connected() else "selected unit only"))
	_set_card(2, "THREAT WATCH", "%d inbound · focus" % inbound if inbound else "No detected inbound", UITheme.COL_RED if inbound else UITheme.COL_DIM, "Focus the most urgent detected inbound weapon. No detection does not establish that the sea is clear.")
	_set_card(3, "AIR OPERATIONS  /  F3", "%d flying · %d ready" % [air, ready], UITheme.COL_BLUE, "Select aircraft, launch sorties and choose a landing destination.")
	_set_card(4, "CHART LAYOUT  /  B", "Restore side panels" if wide_chart else "Expand tactical chart", UITheme.COL_AMBER if wide_chart else UITheme.COL_DIM, "Toggle the side panels for a wider chart. Mission orders, contact cycling, aviation and time remain available.")
	_buttons[1].disabled = tracks.is_empty()
	_buttons[2].disabled = inbound == 0

func _set_card(index: int, heading: String, value: String, color: Color, tip: String) -> void:
	_heads[index].text = heading
	_heads[index].add_theme_color_override("font_color", color)
	_values[index].text = value
	_buttons[index].tooltip_text = tip
	_buttons[index].accessibility_description = value + ". " + tip
