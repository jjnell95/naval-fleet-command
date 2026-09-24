class_name CommandOverview
extends PanelContainer
## Actionable status rail under the top bar. Each segment is one line: an icon, a quiet label and
## the live value; clicking it acts. Contact and threat summaries use the held picture.
signal orders_pressed()
signal contacts_pressed()
signal threat_pressed()
signal air_pressed()
signal chart_pressed()

const ICONS := ["orders", "contacts", "alert", "aircraft", "expand"]

var map: TacticalMap
var contacts: ContactPanel
var wide_chart := false
var _elapsed := 0.0
var _buttons: Array[Button] = []
var _heads: Array[Label] = []
var _values: Array[Label] = []
var _icons: Array[TextureRect] = []
var _tints: Array[Color] = []


func _ready() -> void:
	theme_type_variation = "RailPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	var actions := [orders_pressed, contacts_pressed, threat_pressed, air_pressed, chart_pressed]
	var names := ["Mission orders", "Next priority contact", "Focus inbound weapon", "Open air operations", "Expand or restore tactical chart"]
	for i in actions.size():
		if i > 0:
			row.add_child(UITheme.hairline(true))
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_stretch_ratio = [3.2, 1.35, 1.35, 1.2, 0.95][i]
		button.custom_minimum_size.x = 0
		button.focus_mode = Control.FOCUS_ALL
		button.accessibility_name = names[i]
		button.theme_type_variation = "QuietButton"
		for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
			var box := StyleBoxFlat.new()
			box.bg_color = UITheme.COL_HOVER if state == "hover" else Color.TRANSPARENT
			button.add_theme_stylebox_override(state, box)
		button.pressed.connect(func() -> void: actions[i].emit())
		row.add_child(button)
		_buttons.append(button)
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		margin.add_theme_constant_override("margin_left", 14)
		margin.add_theme_constant_override("margin_right", 12)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(margin)
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 8)
		margin.add_child(line)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(16, 16)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(icon)
		_icons.append(icon)
		_tints.append(Color.TRANSPARENT)
		var head := Label.new()
		head.theme_type_variation = "HeaderLabel"
		head.clip_text = false
		head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(head)
		_heads.append(head)
		var value := Label.new()
		value.clip_text = true
		value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		value.custom_minimum_size.x = 0
		value.add_theme_font_size_override("font_size", 12)
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(value)
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
	var hostile := 0
	for t: Track in tracks:
		if t.identity == "UNKNOWN":
			unknown += 1
		elif t.identity == "HOSTILE":
			hostile += 1
	var inbound := AirDefence.inbound_threats(map.unit_manager, map.threat_manager, map.player_faction, ref).size()
	var scenario: Dictionary = map.simulation.scenario if map.simulation != null else {}
	var intent := str(scenario.get("commander_intent", "Read the mission and review objective progress."))
	_set_card(0, "ORDERS", intent, UITheme.COL_BRASS, "Open mission orders and live objectives  [F1]\n" + intent)
	var filter_name := contacts._filter if contacts != null else "ALL"
	var picture := "%d held" % tracks.size()
	if hostile:
		picture += " · %d hostile" % hostile
	if unknown:
		picture += " · %d unknown" % unknown
	var contact_tint := UITheme.COL_RED if hostile else (UITheme.COL_AMBER if unknown else UITheme.COL_MUTED)
	_set_card(1, "CONTACTS" if filter_name == "ALL" else "CONTACTS · %s" % filter_name, picture, contact_tint, "Cycle to the next priority contact in the current filter  [N]\nUnknown contacts need classifying.\nPicture: " + ("shared link" if ref == null or ref.datalink_connected() else "selected unit only"))
	_set_card(2, "THREATS", "%d inbound" % inbound if inbound else "None detected", UITheme.COL_RED if inbound else UITheme.COL_MUTED, "Focus the most urgent detected inbound weapon.\nNo detection does not mean the sea is clear.")
	_set_card(3, "AIR", "%d flying · %d ready" % [air, ready], UITheme.COL_BLUE if air else UITheme.COL_MUTED, "Select aircraft, launch sorties and choose where they land  [F3]")
	_set_card(4, "", "Restore panels" if wide_chart else "Wide chart", UITheme.COL_ACCENT if wide_chart else UITheme.COL_MUTED, "Hide or restore the side panels for a wider chart  [B]")
	_icons[4].texture = UIIcons.get_icon("collapse" if wide_chart else "expand", 16, _tints[4])
	_buttons[1].disabled = tracks.is_empty()
	_buttons[2].disabled = inbound == 0
	var threat_box := StyleBoxFlat.new()
	threat_box.bg_color = Color(UITheme.COL_RED, 0.16) if inbound else Color.TRANSPARENT
	_buttons[2].add_theme_stylebox_override("normal", threat_box)
	_values[2].add_theme_color_override("font_color", UITheme.COL_RED if inbound else UITheme.COL_DIM)


func _set_card(index: int, heading: String, value: String, color: Color, tip: String) -> void:
	_heads[index].text = heading
	_heads[index].visible = heading != ""
	_values[index].text = value
	if _tints[index] != color:
		_tints[index] = color
		_icons[index].texture = UIIcons.get_icon(ICONS[index], 16, color)
	_buttons[index].tooltip_text = tip
	_buttons[index].accessibility_description = value + ". " + tip
