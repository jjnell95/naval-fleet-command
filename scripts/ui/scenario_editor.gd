class_name ScenarioEditor
extends PanelContainer
## In-game scenario editor. Place platforms on a chart, set headings, patrol routes, objectives
## and the environment, then save under user://scenarios, share as JSON, or play straight away.
## Produces the same JSON the built-in missions use, so anything the loader accepts can be built.

signal play_requested(path: String)
signal closed()

enum Mode { PLACE, MOVE, PATROL, AREA, COAST }

const FACTIONS := ["BLUE", "RED", "NEUTRAL"]
const OBJECTIVE_KINDS := ["Hold position for a time", "Destroy every hostile unit", "Reach an area"]
## Coastline vertices are snapped much finer than units: half a mile either way is nothing to a
## ship's start position and everything to the shape of a headland.
const COAST_SNAP_NM := 0.1

var scenario: Dictionary = {}
var selected_index := -1
var mode: Mode = Mode.PLACE
var palette_platform := ""
## The coastline being drawn or edited, and a live model of every coastline in the scenario. The
## editor keeps its own Landmass list rather than pushing into the static Terrain, which belongs
## to whatever mission is loaded behind this screen.
var coast_index := -1
var _land: Array[Landmass] = []

var _chart: Chart
var _palette: ItemList
var _preview: PlatformPortrait
var _palette_specs: Array = []
var _status: Label
var _name: LineEdit
var _description: TextEdit
var _extent: SpinBox
var _sea: SpinBox
var _minutes: SpinBox
var _objective_kind: OptionButton
var _objective_text: LineEdit
var _unit_box: VBoxContainer
var _unit_title: Label
var _callsign: LineEdit
var _faction: OptionButton
var _heading: SpinBox
var _speed: SpinBox
var _depth: SpinBox
var _radar: CheckBox
var _protect: CheckBox
var _posture: OptionButton
var _home: OptionButton
var _mode_buttons: Array[Button] = []
var _json_popup: PopupPanel
var _json_text: TextEdit
var _load_menu: OptionButton
var _syncing := false
var _coast_name: LineEdit
var _coast_elevation: SpinBox
var _coast_title: Label


func _ready() -> void:
	theme_type_variation = "OverlayPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 0)
	head.add_child(title_box)
	var eyebrow := Label.new()
	eyebrow.text = "SCENARIO EDITOR"
	eyebrow.theme_type_variation = "HeaderLabel"
	title_box.add_child(eyebrow)
	var title := Label.new()
	title.text = "Build a mission"
	title.theme_type_variation = "TitleLabel"
	title_box.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_load_menu = OptionButton.new()
	_load_menu.focus_mode = Control.FOCUS_NONE
	_load_menu.custom_minimum_size.x = 230
	_load_menu.item_selected.connect(_on_load_selected)
	head.add_child(_load_menu)
	_button(head, "NEW", func() -> void: new_scenario())
	_button(head, "SAVE", save)
	_button(head, "EXPORT JSON", _export_json)
	_button(head, "IMPORT JSON", _import_json)
	var play := _button(head, "SAVE AND PLAY", _play)
	play.theme_type_variation = "PrimaryButton"
	_button(head, "CLOSE", func() -> void: closed.emit())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)

	# Left: platform palette.
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 250
	left.add_theme_constant_override("separation", 6)
	body.add_child(left)
	var ph := Label.new()
	ph.text = "PLATFORMS  ·  click the chart to place"
	ph.theme_type_variation = "HeaderLabel"
	left.add_child(ph)
	_palette = ItemList.new()
	_palette.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_palette.focus_mode = Control.FOCUS_NONE
	_palette.add_theme_font_size_override("font_size", 11)
	_palette.add_theme_constant_override("v_separation", 5)
	_palette.item_selected.connect(func(i: int) -> void:
		palette_platform = _palette_specs[i].id
		_preview.spec_override = _palette_specs[i]
		_set_mode(Mode.PLACE))
	left.add_child(_palette)
	# Recognition preview of the platform about to be placed.
	_preview = PlatformPortrait.new()
	_preview.custom_minimum_size.y = 96
	left.add_child(_preview)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 4)
	left.add_child(modes)
	for entry in [["PLACE", Mode.PLACE], ["MOVE", Mode.MOVE], ["PATROL", Mode.PATROL], ["AREA", Mode.AREA], ["COAST", Mode.COAST]]:
		var b := Button.new()
		b.text = entry[0]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: _set_mode(entry[1]))
		modes.add_child(b)
		_mode_buttons.append(b)
	var hint := Label.new()
	hint.text = "Wheel zooms · right drag pans · Delete removes the selected unit, or the last coastline point in COAST mode"
	hint.theme_type_variation = "DimLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	left.add_child(hint)

	# Centre: chart.
	_chart = Chart.new()
	_chart.editor = self
	_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_chart)

	# Right: properties.
	var right := ScrollContainer.new()
	right.custom_minimum_size.x = 330
	right.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(right)
	var props := VBoxContainer.new()
	props.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	props.add_theme_constant_override("separation", 5)
	right.add_child(props)
	_section(props, "SCENARIO")
	_name = _line(props, "Name", func(t: String) -> void:
		scenario["name"] = t
		scenario["id"] = _slug(t))
	_description = TextEdit.new()
	_description.custom_minimum_size.y = 110
	_description.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_description.placeholder_text = "Situation and intent, shown in the briefing"
	_description.text_changed.connect(func() -> void: scenario["description"] = _description.text)
	props.add_child(_description)
	_extent = _spin(props, "Chart width (nm)", 40, 1200, 10, func(v: float) -> void:
		scenario["map"]["extent_nm"] = v
		_chart.queue_redraw())
	_sea = _spin(props, "Sea state (0 calm – 6 high)", 0, 6, 1, func(v: float) -> void: scenario["environment"]["sea_state"] = int(v))
	_section(props, "OBJECTIVE")
	_objective_kind = OptionButton.new()
	_objective_kind.focus_mode = Control.FOCUS_NONE
	for k in OBJECTIVE_KINDS:
		_objective_kind.add_item(k)
	_objective_kind.item_selected.connect(func(_i: int) -> void: _apply_objective())
	props.add_child(_objective_kind)
	_minutes = _spin(props, "Minutes to hold", 5, 240, 5, func(_v: float) -> void: _apply_objective())
	_objective_text = _line(props, "Mission statement", func(t: String) -> void: scenario["objectives"]["text"] = t)
	var area_hint := Label.new()
	area_hint.text = "For a reach-area objective choose AREA and click the chart. Tick PROTECT on a unit to make its loss end the mission."
	area_hint.theme_type_variation = "DimLabel"
	area_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	area_hint.add_theme_font_size_override("font_size", 10)
	props.add_child(area_hint)

	_unit_box = VBoxContainer.new()
	_unit_box.add_theme_constant_override("separation", 5)
	props.add_child(_unit_box)
	_section(_unit_box, "SELECTED UNIT")
	_unit_title = Label.new()
	_unit_title.theme_type_variation = "DimLabel"
	_unit_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_unit_box.add_child(_unit_title)
	_callsign = _line(_unit_box, "Callsign", func(t: String) -> void: _unit_set("callsign", t))
	_faction = OptionButton.new()
	_faction.focus_mode = Control.FOCUS_NONE
	for f in FACTIONS:
		_faction.add_item(f)
	_faction.item_selected.connect(func(i: int) -> void:
		_unit_set("faction", FACTIONS[i])
		_refresh_home_options())
	_unit_box.add_child(_faction)
	_heading = _spin(_unit_box, "Heading (°)", 0, 359, 1, func(v: float) -> void: _unit_set("heading_deg", v))
	_speed = _spin(_unit_box, "Speed (kn)", 0, 1500, 1, func(v: float) -> void: _unit_set("speed_kn", v))
	_depth = _spin(_unit_box, "Depth (m, submarines)", 0, 600, 5, func(v: float) -> void: _unit_set("depth_m", v))
	_radar = CheckBox.new()
	_radar.text = "Radar on at start"
	_radar.focus_mode = Control.FOCUS_NONE
	_radar.toggled.connect(func(on: bool) -> void: _unit_set("radar_on", on))
	_unit_box.add_child(_radar)
	_protect = CheckBox.new()
	_protect.text = "PROTECT: mission fails if lost"
	_protect.focus_mode = Control.FOCUS_NONE
	_protect.toggled.connect(func(on: bool) -> void: _set_protected(on))
	_unit_box.add_child(_protect)
	_posture = OptionButton.new()
	_posture.focus_mode = Control.FOCUS_NONE
	_posture.add_item("AI posture: standard")
	_posture.add_item("AI posture: breakout (presses on)")
	_posture.item_selected.connect(func(i: int) -> void: _unit_set("ai_posture", "breakout" if i == 1 else "standard"))
	_unit_box.add_child(_posture)
	_home = OptionButton.new()
	_home.focus_mode = Control.FOCUS_NONE
	_home.item_selected.connect(func(i: int) -> void: _unit_set("home", _home.get_item_text(i)))
	_unit_box.add_child(_home)
	var patrol_row := HBoxContainer.new()
	_unit_box.add_child(patrol_row)
	_button(patrol_row, "CLEAR PATROL", func() -> void:
		if selected_index >= 0:
			scenario["units"][selected_index].erase("patrol_nm")
			_chart.queue_redraw())
	_button(patrol_row, "DELETE UNIT", delete_selected)

	_section(props, "COASTLINE")
	_coast_title = Label.new()
	_coast_title.theme_type_variation = "DimLabel"
	_coast_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	props.add_child(_coast_title)
	_coast_name = _line(props, "Landmass name", func(t: String) -> void: _coast_set_name(t))
	_coast_elevation = _spin(props, "Elevation (m)", 0, 3000, 20, func(v: float) -> void: _coast_set_elevation(v))
	var coast_row := HBoxContainer.new()
	props.add_child(coast_row)
	_button(coast_row, "FINISH", func() -> void: finish_coast())
	_button(coast_row, "UNDO POINT", func() -> void: undo_coast_point())
	_button(coast_row, "DELETE", func() -> void: delete_coast())

	_status = Label.new()
	_status.theme_type_variation = "DimLabel"
	_status.clip_text = true
	v.add_child(_status)

	_json_popup = PopupPanel.new()
	var pv := VBoxContainer.new()
	pv.custom_minimum_size = Vector2(760, 460)
	_json_popup.add_child(pv)
	var pl := Label.new()
	pl.text = "Scenario JSON. Copy it to share, or paste one here and press LOAD FROM TEXT."
	pv.add_child(pl)
	_json_text = TextEdit.new()
	_json_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.add_child(_json_text)
	var pb := HBoxContainer.new()
	pv.add_child(pb)
	_button(pb, "LOAD FROM TEXT", func() -> void:
		var parsed = JSON.parse_string(_json_text.text)
		if typeof(parsed) != TYPE_DICTIONARY:
			_say("That is not a scenario JSON object", true)
			return
		load_dict(parsed)
		_json_popup.hide()
		_say("Scenario imported: %s" % scenario.get("name", "?"), false))
	_button(pb, "COPY TO CLIPBOARD", func() -> void:
		DisplayServer.clipboard_set(_json_text.text)
		_say("Copied", false))
	_button(pb, "CLOSE", func() -> void: _json_popup.hide())
	add_child(_json_popup)

	_fill_palette()
	new_scenario()
	_set_mode(Mode.PLACE)


# --- Construction helpers ----------------------------------------------------------------

func _button(parent: Node, text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b


func _section(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "HeaderLabel"
	parent.add_child(l)


func _line(parent: Node, placeholder: String, on_change: Callable) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text_changed.connect(func(t: String) -> void:
		if not _syncing:
			on_change.call(t))
	parent.add_child(e)
	return e


func _spin(parent: Node, label: String, lo: float, hi: float, step: float, on_change: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Label.new()
	l.text = label
	l.theme_type_variation = "DimLabel"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size.x = 92
	s.value_changed.connect(func(v: float) -> void:
		if not _syncing:
			on_change.call(v))
	row.add_child(s)
	return s


func _fill_palette() -> void:
	_palette.clear()
	_palette_specs = DataDB.all_platforms()
	for spec: PlatformSpec in _palette_specs:
		var glyph := MapSymbols.category_glyph(spec.category, spec.domain)
		_palette.add_item("%-3s %s · %s" % [glyph, spec.nation if spec.nation != "" else "—", spec.display_name])
	if not _palette_specs.is_empty():
		_palette.select(0)
		palette_platform = _palette_specs[0].id
		_preview.spec_override = _palette_specs[0]


func _set_mode(m: Mode) -> void:
	mode = m
	for i in _mode_buttons.size():
		_mode_buttons[i].button_pressed = i == int(m)
	match m:
		Mode.PLACE:
			_say("PLACE: click the chart to add a %s" % _spec_name(palette_platform), false)
		Mode.MOVE:
			_say("MOVE: click a unit to select it, drag to move it", false)
		Mode.PATROL:
			_say("PATROL: click the chart to add legs to the selected unit's route", false)
		Mode.AREA:
			_say("AREA: click the chart to set the objective area", false)
		Mode.COAST:
			_say("COAST: click the chart to trace a coastline. FINISH closes it and starts the next one; click inside a finished coast to edit it.", false)


func _spec_name(id: String) -> String:
	var spec := DataDB.platform(id)
	return spec.short_name if spec != null else id


func _say(text: String, warn: bool) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", UITheme.COL_AMBER if warn else UITheme.COL_DIM)


# --- Model -------------------------------------------------------------------------------

func new_scenario() -> void:
	scenario = {
		"id": "custom_mission",
		"order": 100,
		"name": "Custom mission",
		"forces": "",
		"description": "",
		"start_time_utc": "2027-06-01T06:00:00",
		"player_faction": "BLUE",
		"neutral_factions": ["NEUTRAL"],
		"environment": {"sea_state": 2},
		"map": {"center_nm": [0, 0], "extent_nm": 160},
		"terrain": {"land": []},
		"objectives": {"text": "Hold the task group for 30 minutes.", "victory": [{"id": "hold", "type": "time_elapsed", "seconds": 1800, "text": "Hold for 30 minutes"}], "loss": []},
		"units": [],
	}
	selected_index = -1
	coast_index = -1
	_rebuild_land()
	_sync_from_model()
	_refresh_load_menu()
	_chart.fit()


func load_dict(d: Dictionary) -> void:
	scenario = d.duplicate(true)
	if not scenario.has("map"):
		scenario["map"] = {"center_nm": [0, 0], "extent_nm": 160}
	if not scenario.has("environment"):
		scenario["environment"] = {"sea_state": 0}
	if not scenario.has("objectives"):
		scenario["objectives"] = {"text": "", "victory": [], "loss": []}
	if not scenario["objectives"].has("loss"):
		scenario["objectives"]["loss"] = []
	if not scenario["objectives"].has("victory"):
		scenario["objectives"]["victory"] = []
	if not scenario.has("units"):
		scenario["units"] = []
	if typeof(scenario.get("terrain")) != TYPE_DICTIONARY:
		scenario["terrain"] = {"land": []}
	if typeof(scenario["terrain"].get("land")) != TYPE_ARRAY:
		scenario["terrain"]["land"] = []
	selected_index = -1
	coast_index = -1
	_rebuild_land()
	_sync_from_model()
	_chart.fit()


func _sync_from_model() -> void:
	_sync_coast()
	_syncing = true
	_name.text = str(scenario.get("name", ""))
	_description.text = str(scenario.get("description", ""))
	_extent.value = float(scenario["map"].get("extent_nm", 160))
	_sea.value = int(scenario["environment"].get("sea_state", 0))
	_objective_text.text = str(scenario["objectives"].get("text", ""))
	var kind := 0
	var minutes := 30
	for o in scenario["objectives"]["victory"]:
		match o.get("type", ""):
			"time_elapsed":
				kind = 0
				minutes = int(int(o.get("seconds", 1800)) / 60)
			"force_destroyed":
				kind = 1
			"reach_area":
				kind = 2
	_objective_kind.select(kind)
	_minutes.value = minutes
	_syncing = false
	_sync_unit()
	_chart.queue_redraw()


func _apply_objective() -> void:
	var kind := _objective_kind.selected
	var victory: Array = []
	var existing_area: Dictionary = {}
	for o in scenario["objectives"]["victory"]:
		if o.get("type", "") == "reach_area":
			existing_area = o
	match kind:
		0:
			victory.append({"id": "hold", "type": "time_elapsed", "seconds": int(_minutes.value) * 60, "text": "Hold for %d minutes" % int(_minutes.value)})
		1:
			victory.append({"id": "destroy", "type": "force_destroyed", "faction": "RED", "text": "Destroy every hostile unit"})
		2:
			if existing_area.is_empty():
				var c: Array = scenario["map"]["center_nm"]
				existing_area = {"id": "reach", "type": "reach_area", "center_nm": [float(c[0]), float(c[1]) + 20.0], "radius_nm": 8.0, "callsigns": [], "text": "Bring the force into the objective area"}
			victory.append(existing_area)
	scenario["objectives"]["victory"] = victory
	_chart.queue_redraw()


func set_area(world: Vector2) -> void:
	_objective_kind.select(2)
	_apply_objective()
	if on_land(world):
		_say("An objective area on land cannot be reached by a ship", true)
		return
	for o in scenario["objectives"]["victory"]:
		if o.get("type", "") == "reach_area":
			o["center_nm"] = [snappedf(world.x, 0.5), snappedf(world.y, 0.5)]
	_say("Objective area set at %s %s" % [Geo.format_axis(world.x, "E", "W"), Geo.format_axis(world.y, "N", "S")], false)
	_chart.queue_redraw()


func place(world: Vector2) -> void:
	var spec := DataDB.platform(palette_platform)
	if spec == null:
		return
	var faction := "BLUE"
	if spec.nation == "Russia":
		faction = "RED"
	elif spec.category.contains("merchant"):
		faction = "NEUTRAL"
	var ud := {"platform": spec.id, "callsign": _unique_callsign(spec), "faction": faction}
	if spec.domain == "air":
		var home := _nearest_deck(world, faction)
		if home == "":
			_say("An aircraft needs a ship or air station of its own side to fly from. Place one first.", true)
			return
		ud["home"] = home
	else:
		if spec.domain != "land" and on_land(world):
			_say("%s cannot start on land. Place it in the water, or use COAST to reshape the coastline." % spec.short_name, true)
			return
		ud["position_nm"] = [snappedf(world.x, 0.5), snappedf(world.y, 0.5)]
		ud["heading_deg"] = 0
		ud["speed_kn"] = spec.cruise_speed_kn
		if spec.domain == "subsurface":
			ud["depth_m"] = spec.patrol_depth_m
			ud["radar_on"] = false
	scenario["units"].append(ud)
	selected_index = scenario["units"].size() - 1
	_sync_unit()
	_say("Placed %s" % ud["callsign"], false)
	_chart.queue_redraw()


func _unique_callsign(spec: PlatformSpec) -> String:
	var base := spec.short_name
	var n := 1
	var names: Dictionary = {}
	for u in scenario["units"]:
		names[u.get("callsign", "")] = true
	while names.has("%s %d" % [base, n]):
		n += 1
	return "%s %d" % [base, n]


func _nearest_deck(world: Vector2, faction: String) -> String:
	var best := ""
	var best_d := INF
	for u in scenario["units"]:
		if u.get("faction", "") != faction or not u.has("position_nm"):
			continue
		var spec := DataDB.platform(u.get("platform", ""))
		if spec == null or spec.aircraft_capacity <= 0:
			continue
		var embarked := 0
		for a in scenario["units"]:
			if a.get("home", "") == u.get("callsign", ""):
				embarked += 1
		if embarked >= spec.aircraft_capacity:
			continue
		var d := world.distance_to(unit_position(u))
		if d < best_d:
			best_d = d
			best = u["callsign"]
	return best


## Where a unit sits on the chart: its own position, or its home's for an aircraft.
func unit_position(u: Dictionary) -> Vector2:
	if u.has("position_nm"):
		var p: Array = u["position_nm"]
		return Vector2(float(p[0]), float(p[1]))
	for h in scenario["units"]:
		if h.get("callsign", "") == u.get("home", "") and h.has("position_nm"):
			var p: Array = h["position_nm"]
			return Vector2(float(p[0]), float(p[1]))
	return Vector2.ZERO


func select_unit(i: int) -> void:
	selected_index = i
	_sync_unit()
	_chart.queue_redraw()


func move_selected(world: Vector2) -> void:
	if selected_index < 0:
		return
	var u: Dictionary = scenario["units"][selected_index]
	if not u.has("position_nm"):
		return
	var spec := DataDB.platform(u.get("platform", ""))
	if spec != null and spec.domain != "land" and spec.domain != "air" and on_land(world):
		return  # a hull is simply not draggable onto the beach
	u["position_nm"] = [snappedf(world.x, 0.5), snappedf(world.y, 0.5)]
	_chart.queue_redraw()


func add_patrol_leg(world: Vector2) -> void:
	if selected_index < 0:
		_say("Select a unit first", true)
		return
	var u: Dictionary = scenario["units"][selected_index]
	var spec := DataDB.platform(u.get("platform", ""))
	if spec != null and (spec.domain == "surface" or spec.domain == "subsurface") and on_land(world):
		_say("A ship cannot be routed onto land", true)
		return
	if not u.has("patrol_nm"):
		u["patrol_nm"] = []
	u["patrol_nm"].append([snappedf(world.x, 0.5), snappedf(world.y, 0.5)])
	_chart.queue_redraw()


# --- Coastlines --------------------------------------------------------------------------

## The working Landmass list is rebuilt from the model, and written back after every edit, so the
## scenario dictionary stays the single source of truth that save, export and play all read.
func _rebuild_land() -> void:
	_land.clear()
	for entry in scenario.get("terrain", {}).get("land", []):
		if typeof(entry) == TYPE_DICTIONARY:
			_land.append(Landmass.from_dict(entry))


func _write_land() -> void:
	var out: Array = []
	for l in _land:
		out.append(l.to_dict())
	scenario["terrain"] = {"land": out}
	_sync_coast()
	_chart.queue_redraw()


func add_coast_point(world: Vector2) -> void:
	if coast_index < 0 or coast_index >= _land.size():
		var fresh := Landmass.new()
		fresh.name = "Landmass %d" % (_land.size() + 1)
		fresh.id = _slug(fresh.name)
		_land.append(fresh)
		coast_index = _land.size() - 1
	var l := _land[coast_index]
	l.points.append(Vector2(snappedf(world.x, COAST_SNAP_NM), snappedf(world.y, COAST_SNAP_NM)))
	l.recompute()
	_say("%s: %d points — FINISH closes it" % [l.name, l.points.size()], false)
	_write_land()


func select_coast(i: int) -> void:
	coast_index = i
	_say("Editing %s" % _land[i].name, false)
	_sync_coast()
	_chart.queue_redraw()


## A finished coastline is simply one that is no longer being added to; the polygon is always
## closed, so there is no open state to resolve.
func finish_coast() -> void:
	if coast_index < 0 or coast_index >= _land.size():
		return
	var l := _land[coast_index]
	if not l.valid():
		_land.remove_at(coast_index)
		_say("A coastline needs at least three points", true)
	else:
		_say("%s closed with %d points" % [l.name, l.points.size()], false)
	coast_index = -1
	_write_land()


func undo_coast_point() -> void:
	if coast_index < 0 or coast_index >= _land.size():
		return
	var l := _land[coast_index]
	if l.points.is_empty():
		return
	l.points.remove_at(l.points.size() - 1)
	l.recompute()
	_write_land()


func delete_coast() -> void:
	if coast_index < 0 or coast_index >= _land.size():
		_say("Click a coastline to select it first", true)
		return
	_say("Removed %s" % _land[coast_index].name, false)
	_land.remove_at(coast_index)
	coast_index = -1
	_write_land()


func coast_at(world: Vector2) -> int:
	for i in _land.size():
		if _land[i].valid() and _land[i].contains(world):
			return i
	return -1


func on_land(world: Vector2) -> bool:
	return coast_at(world) >= 0


func _coast_set_name(t: String) -> void:
	if coast_index < 0 or coast_index >= _land.size():
		return
	_land[coast_index].name = t
	_land[coast_index].id = _slug(t)
	_write_land()


func _coast_set_elevation(v: float) -> void:
	if coast_index < 0 or coast_index >= _land.size():
		return
	_land[coast_index].elevation_m = v
	_write_land()


func _sync_coast() -> void:
	_syncing = true
	if coast_index >= 0 and coast_index < _land.size():
		var l := _land[coast_index]
		_coast_title.text = "%s · %d points · %.0f m" % [l.name, l.points.size(), l.elevation_m]
		_coast_name.text = l.name
		_coast_elevation.value = l.elevation_m
	else:
		_coast_title.text = "%d coastline%s. Choose COAST and click the chart to trace one; ships cannot enter land and it masks radar, ESM and sonar." % [_land.size(), "" if _land.size() == 1 else "s"]
		_coast_name.text = ""
		_coast_elevation.value = Landmass.DEFAULT_ELEVATION_M
	_syncing = false


func delete_selected() -> void:
	if selected_index < 0:
		return
	var gone: String = scenario["units"][selected_index].get("callsign", "")
	scenario["units"].remove_at(selected_index)
	for u in scenario["units"]:
		if u.get("home", "") == gone:
			u.erase("home")
	_strip_protected(gone)
	selected_index = -1
	_sync_unit()
	_chart.queue_redraw()


func _unit_set(key: String, value) -> void:
	if selected_index < 0 or _syncing:
		return
	var u: Dictionary = scenario["units"][selected_index]
	if key == "callsign":
		var old: String = u.get("callsign", "")
		for a in scenario["units"]:
			if a.get("home", "") == old:
				a["home"] = value
		_rename_protected(old, value)
	u[key] = value
	_chart.queue_redraw()


func _protected_names() -> Array:
	for o in scenario["objectives"]["loss"]:
		if o.get("type", "") == "unit_lost":
			return o.get("callsigns", [])
	return []


func _set_protected(on: bool) -> void:
	if selected_index < 0 or _syncing:
		return
	var cs: String = scenario["units"][selected_index].get("callsign", "")
	var loss: Array = scenario["objectives"]["loss"]
	var entry: Dictionary = {}
	for o in loss:
		if o.get("type", "") == "unit_lost":
			entry = o
	if entry.is_empty():
		entry = {"id": "protect", "type": "unit_lost", "callsigns": [], "text": "A protected unit was lost"}
		loss.append(entry)
	var names: Array = entry["callsigns"]
	if on and not names.has(cs):
		names.append(cs)
	elif not on:
		names.erase(cs)
	entry["callsigns"] = names
	if names.is_empty():
		loss.erase(entry)


func _strip_protected(cs: String) -> void:
	for o in scenario["objectives"]["loss"]:
		if o.get("type", "") == "unit_lost":
			o["callsigns"].erase(cs)


func _rename_protected(old: String, new_name: String) -> void:
	for o in scenario["objectives"]["loss"]:
		if o.get("type", "") == "unit_lost":
			var names: Array = o["callsigns"]
			var i := names.find(old)
			if i >= 0:
				names[i] = new_name


func _sync_unit() -> void:
	_syncing = true
	var has: bool = selected_index >= 0 and selected_index < scenario["units"].size()
	_unit_box.visible = has
	if has:
		var u: Dictionary = scenario["units"][selected_index]
		var spec := DataDB.platform(u.get("platform", ""))
		_unit_title.text = spec.display_name if spec != null else str(u.get("platform", ""))
		_callsign.text = str(u.get("callsign", ""))
		_faction.select(maxi(FACTIONS.find(u.get("faction", "BLUE")), 0))
		_heading.value = float(u.get("heading_deg", 0))
		_speed.value = float(u.get("speed_kn", 0))
		_depth.value = float(u.get("depth_m", 0))
		_radar.button_pressed = bool(u.get("radar_on", true))
		_protect.button_pressed = _protected_names().has(u.get("callsign", ""))
		_posture.select(1 if u.get("ai_posture", "standard") == "breakout" else 0)
		var is_air := spec != null and spec.domain == "air"
		_heading.get_parent().visible = not is_air
		_speed.get_parent().visible = not is_air
		_depth.get_parent().visible = spec != null and spec.domain == "subsurface"
		_radar.visible = not is_air
		_home.visible = is_air
		_posture.visible = not is_air
		if is_air:
			_refresh_home_options()
	_syncing = false


func _refresh_home_options() -> void:
	_home.clear()
	if selected_index < 0:
		return
	var u: Dictionary = scenario["units"][selected_index]
	var faction: String = u.get("faction", "BLUE")
	var chosen := -1
	for h in scenario["units"]:
		var spec := DataDB.platform(h.get("platform", ""))
		if spec == null or spec.aircraft_capacity <= 0 or h.get("faction", "") != faction:
			continue
		_home.add_item(h.get("callsign", ""))
		if h.get("callsign", "") == u.get("home", ""):
			chosen = _home.item_count - 1
	if chosen >= 0:
		_home.select(chosen)
	elif _home.item_count > 0:
		_home.select(0)
		u["home"] = _home.get_item_text(0)


# --- Persistence -------------------------------------------------------------------------

func validate() -> String:
	if str(scenario.get("name", "")).strip_edges() == "":
		return "Give the scenario a name"
	var player: String = scenario.get("player_faction", "BLUE")
	var own := 0
	var names: Dictionary = {}
	for u in scenario["units"]:
		var cs: String = u.get("callsign", "")
		if names.has(cs):
			return "Two units are called %s" % cs
		names[cs] = true
		if u.get("faction", "") == player:
			own += 1
		var spec := DataDB.platform(u.get("platform", ""))
		if spec != null and spec.domain == "air":
			var home_ok := false
			for h in scenario["units"]:
				if h.get("callsign", "") == u.get("home", "") and h.get("faction", "") == u.get("faction", ""):
					home_ok = true
			if not home_ok:
				return "%s has no ship or base to fly from" % cs
	if own == 0:
		return "Place at least one %s unit for the player to command" % player
	if scenario["objectives"]["victory"].is_empty():
		return "Choose an objective"
	return _validate_terrain()


## Terrain is checked against the editor's own coastlines, never against the static Terrain, which
## holds whatever mission is loaded behind this screen.
func _validate_terrain() -> String:
	for l in _land:
		if not l.valid():
			return "%s needs at least three points" % (l.name if l.name != "" else "A coastline")
	if _land.is_empty():
		return ""
	for u in scenario["units"]:
		var spec := DataDB.platform(u.get("platform", ""))
		if spec == null or (spec.domain != "surface" and spec.domain != "subsurface"):
			continue
		var cs: String = u.get("callsign", "")
		if u.has("position_nm") and on_land(_pair(u["position_nm"])):
			return "%s starts on land" % cs
		for leg in u.get("patrol_nm", []):
			if on_land(_pair(leg)):
				return "%s has a patrol leg on land" % cs
	for o in scenario["objectives"]["victory"]:
		if o.get("type", "") == "reach_area" and on_land(_pair(o.get("center_nm", [0, 0]))):
			return "The objective area is on land"
	return ""


func _pair(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1])) if a.size() >= 2 else Vector2.ZERO


func to_json() -> String:
	scenario["forces"] = _forces_summary()
	return JSON.stringify(scenario, "  ")


func _forces_summary() -> String:
	var counts: Dictionary = {}
	for u in scenario["units"]:
		var f: String = u.get("faction", "?")
		var spec := DataDB.platform(u.get("platform", ""))
		var short := spec.short_name if spec != null else str(u.get("platform", ""))
		if not counts.has(f):
			counts[f] = {}
		counts[f][short] = int(counts[f].get(short, 0)) + 1
	var parts := PackedStringArray()
	for f in ["BLUE", "RED", "NEUTRAL"]:
		if not counts.has(f):
			continue
		var items := PackedStringArray()
		for k in counts[f]:
			items.append("%d× %s" % [counts[f][k], k] if counts[f][k] > 1 else k)
		parts.append("%s: %s" % [f, ", ".join(items)])
	return " / ".join(parts)


func save() -> bool:
	var problem := validate()
	if problem != "":
		_say(problem, true)
		return false
	ScenarioIndex.ensure_user_dir()
	var path := ScenarioIndex.custom_path(str(scenario.get("id", "custom_mission")))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_say("Could not write %s" % path, true)
		return false
	f.store_string(to_json())
	f.close()
	_say("Saved %s" % path, false)
	_refresh_load_menu()
	return true


func _play() -> void:
	if save():
		play_requested.emit(ScenarioIndex.custom_path(str(scenario.get("id", "custom_mission"))))


func _export_json() -> void:
	_json_text.text = to_json()
	_json_popup.popup_centered()


func _import_json() -> void:
	_json_text.text = ""
	_json_popup.popup_centered()


func _refresh_load_menu() -> void:
	_load_menu.clear()
	_load_menu.add_item("Open a scenario…")
	for e in ScenarioIndex.list_all():
		_load_menu.add_item("%s%s" % [e["name"], "  (custom)" if e["custom"] else ""])
		_load_menu.set_item_metadata(_load_menu.item_count - 1, e["path"])
	_load_menu.select(0)


func _on_load_selected(i: int) -> void:
	if i <= 0:
		return
	var path: String = _load_menu.get_item_metadata(i)
	var d := ScenarioLoader.load_file(path)
	if d.is_empty():
		_say("Could not read %s" % path, true)
	else:
		load_dict(d)
		if not path.begins_with("user://"):
			scenario["id"] = "custom_" + str(scenario.get("id", "mission"))
			scenario["name"] = str(scenario.get("name", "")) + " (copy)"
			_sync_from_model()
		_say("Opened %s. Saving writes a custom copy." % scenario.get("name", ""), false)
	_load_menu.select(0)


func _slug(text: String) -> String:
	var out := ""
	for ch in text.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif ch == " " or ch == "-" or ch == "_":
			out += "_"
	if out == "":
		out = "custom_mission"
	return "custom_" + out.trim_prefix("custom_")


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.keycode != KEY_DELETE or _callsign.has_focus() or _coast_name.has_focus():
		return
	if mode == Mode.COAST and coast_index >= 0:
		undo_coast_point()
		get_viewport().set_input_as_handled()
	elif selected_index >= 0:
		delete_selected()
		get_viewport().set_input_as_handled()


## The chart: a scrollable, zoomable plan view of the scenario being built.
class Chart extends Control:
	var editor: ScenarioEditor
	var center := Vector2.ZERO
	var ppn := 3.0
	var _font: Font
	var _dragging := false
	var _panning := false
	var _hover := -1
	var _auto_fit := true  # until the user zooms or pans, the chart frames the scenario itself

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true
		_font = get_theme_default_font()
		resized.connect(func() -> void:
			if _auto_fit:
				fit())

	func fit() -> void:
		_auto_fit = true
		if editor == null or editor.scenario.is_empty() or size.x <= 0.0:
			return
		var c: Array = editor.scenario["map"]["center_nm"]
		center = Vector2(float(c[0]), float(c[1]))
		var extent := float(editor.scenario["map"].get("extent_nm", 160.0))
		ppn = maxf(minf(size.x, size.y), 200.0) / maxf(extent, 1.0) * 0.9
		queue_redraw()

	func w2s(w: Vector2) -> Vector2:
		return Vector2(size.x * 0.5 + (w.x - center.x) * ppn, size.y * 0.5 - (w.y - center.y) * ppn)

	func s2w(s: Vector2) -> Vector2:
		return Vector2(center.x + (s.x - size.x * 0.5) / ppn, center.y - (s.y - size.y * 0.5) / ppn)

	func _unit_at(p: Vector2) -> int:
		var best := -1
		var best_d := 14.0
		for i in editor.scenario["units"].size():
			var d := w2s(editor.unit_position(editor.scenario["units"][i])).distance_to(p)
			if d < best_d:
				best_d = d
				best = i
		return best

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var e := event as InputEventMouseButton
			if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
				_zoom(e.position, 1.25)
			elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
				_zoom(e.position, 0.8)
			elif e.button_index == MOUSE_BUTTON_RIGHT or e.button_index == MOUSE_BUTTON_MIDDLE:
				_panning = e.pressed
			elif e.button_index == MOUSE_BUTTON_LEFT:
				if e.pressed:
					_left_down(e.position)
				else:
					_dragging = false
			accept_event()
		elif event is InputEventMouseMotion:
			var m := event as InputEventMouseMotion
			if _panning:
				_auto_fit = false
				center -= Vector2(m.relative.x, -m.relative.y) / ppn
				queue_redraw()
			elif _dragging:
				editor.move_selected(s2w(m.position))
			else:
				var h := _unit_at(m.position)
				if h != _hover:
					_hover = h
					queue_redraw()

	func _zoom(at: Vector2, f: float) -> void:
		_auto_fit = false
		var anchor := s2w(at)
		ppn = clampf(ppn * f, 0.3, 60.0)
		center = Vector2(anchor.x - (at.x - size.x * 0.5) / ppn, anchor.y + (at.y - size.y * 0.5) / ppn)
		queue_redraw()

	func _left_down(p: Vector2) -> void:
		var hit := _unit_at(p)
		match editor.mode:
			ScenarioEditor.Mode.PLACE:
				if hit >= 0:
					editor.select_unit(hit)
				else:
					editor.place(s2w(p))
			ScenarioEditor.Mode.MOVE:
				if hit >= 0:
					editor.select_unit(hit)
					_dragging = editor.scenario["units"][hit].has("position_nm")
			ScenarioEditor.Mode.PATROL:
				if hit >= 0:
					editor.select_unit(hit)
				else:
					editor.add_patrol_leg(s2w(p))
			ScenarioEditor.Mode.AREA:
				editor.set_area(s2w(p))
			ScenarioEditor.Mode.COAST:
				var world := s2w(p)
				var existing := editor.coast_at(world)
				# Clicking inside a finished coast picks it up; anything else extends the one
				# being drawn, or starts a new one.
				if editor.coast_index < 0 and existing >= 0:
					editor.select_coast(existing)
				else:
					editor.add_coast_point(world)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("081320"))
		draw_rect(Rect2(Vector2.ZERO, size), UITheme.COL_BORDER, false, 1.0)
		if editor == null or editor.scenario.is_empty():
			return
		var step := 10.0
		for s in [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0]:
			if s * ppn >= 60.0:
				step = s
				break
		var tl := s2w(Vector2.ZERO)
		var br := s2w(size)
		var x := floorf(tl.x / step) * step
		while x <= br.x:
			var sx := w2s(Vector2(x, 0)).x
			draw_line(Vector2(sx, 0), Vector2(sx, size.y), Color(UITheme.COL_BORDER, 0.5), 1.0)
			draw_string(_font, Vector2(sx + 3, size.y - 6), Geo.format_axis(x, "E", "W"), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.COL_DIM)
			x += step
		var y := floorf(br.y / step) * step
		while y <= tl.y:
			var sy := w2s(Vector2(0, y)).y
			draw_line(Vector2(0, sy), Vector2(size.x, sy), Color(UITheme.COL_BORDER, 0.5), 1.0)
			draw_string(_font, Vector2(4, sy - 3), Geo.format_axis(y, "N", "S"), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.COL_DIM)
			y += step
		_draw_land()
		# Chart extent as the mission will frame it.
		var c: Array = editor.scenario["map"]["center_nm"]
		var half := float(editor.scenario["map"].get("extent_nm", 160.0)) * 0.5
		var mc := Vector2(float(c[0]), float(c[1]))
		var tlp := w2s(mc + Vector2(-half, half))
		var brp := w2s(mc + Vector2(half, -half))
		draw_rect(Rect2(tlp, brp - tlp), Color(UITheme.COL_ACCENT, 0.35), false, 1.0)
		for o in editor.scenario["objectives"]["victory"]:
			if o.get("type", "") == "reach_area":
				var oc: Array = o["center_nm"]
				var op := w2s(Vector2(float(oc[0]), float(oc[1])))
				draw_circle(op, float(o.get("radius_nm", 8.0)) * ppn, Color(TacticalMap.COL_WAYPOINT, 0.08))
				draw_arc(op, float(o.get("radius_nm", 8.0)) * ppn, 0.0, TAU, 48, TacticalMap.COL_WAYPOINT, 1.5, true)
				draw_string(_font, op + Vector2(8, -8), "OBJECTIVE AREA", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TacticalMap.COL_WAYPOINT)
		var protected := editor._protected_names()
		var units: Array = editor.scenario["units"]
		for i in units.size():
			var u: Dictionary = units[i]
			var spec := DataDB.platform(u.get("platform", ""))
			var pos := editor.unit_position(u)
			var sp := w2s(pos)
			var col := TacticalMap.COL_FRIENDLY
			var frame := MapSymbols.Frame.FRIENDLY
			match u.get("faction", "BLUE"):
				"RED":
					col = TacticalMap.COL_HOSTILE
					frame = MapSymbols.Frame.HOSTILE
				"NEUTRAL":
					col = TacticalMap.COL_NEUTRAL
					frame = MapSymbols.Frame.NEUTRAL
			if u.has("patrol_nm"):
				var prev := sp
				for leg in u["patrol_nm"]:
					var lp := w2s(Vector2(float(leg[0]), float(leg[1])))
					draw_dashed_line(prev, lp, Color(col, 0.5), 1.0, 5.0)
					draw_rect(Rect2(lp - Vector2(3, 3), Vector2(6, 6)), Color(col, 0.8), false, 1.0)
					prev = lp
			var domain := spec.domain if spec != null else "surface"
			var is_air := domain == "air"
			var draw_at := sp
			if is_air:
				# Fan embarked aircraft out beside their deck so they stay readable.
				var n := 0
				for j in i:
					if units[j].get("home", "") == u.get("home", "") and units[j].has("home"):
						n += 1
				draw_at = sp + Vector2(22 + n * 16, -18)
				draw_line(sp, draw_at, Color(col, 0.3), 1.0)
			var glyph := MapSymbols.category_glyph(spec.category, spec.domain) if spec != null else ""
			MapSymbols.draw_symbol(self, draw_at, col, frame, domain, float(u.get("heading_deg", 0.0)), not is_air, glyph, _font, 0.9)
			if i == editor.selected_index:
				MapSymbols.draw_selection(self, draw_at, Color.WHITE, 0.0)
			elif i == _hover:
				draw_arc(draw_at, 15.0, 0.0, TAU, 24, Color(col, 0.5), 1.0, true)
			var label: String = u.get("callsign", "")
			if protected.has(label):
				label += " ★"
			if i == editor.selected_index or not is_air:
				draw_string(_font, draw_at + Vector2(14, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(col, 0.9))
		draw_string(_font, Vector2(10, 16), "%s  ·  %d units  ·  sea state %d" % [str(editor.scenario.get("name", "")).to_upper(), units.size(), int(editor.scenario["environment"].get("sea_state", 0))], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.COL_ACCENT)
		draw_string(_font, Vector2(10, size.y - 20), "★ protected · dashed: patrol route · box: mission chart extent · filled: land", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.COL_DIM)


	## Coastlines as they will appear in the mission, plus the vertices while one is being traced.
	func _draw_land() -> void:
		for i in editor._land.size():
			var l: Landmass = editor._land[i]
			var pts := PackedVector2Array()
			for p in l.points:
				pts.append(w2s(p))
			if pts.size() >= 3:
				draw_colored_polygon(pts, TacticalMap.COL_LAND)
			var editing := i == editor.coast_index
			if pts.size() >= 2:
				var ring := pts.duplicate()
				ring.append(pts[0])
				draw_polyline(ring, Color(TacticalMap.COL_COAST, 1.0 if editing else 0.75), 1.5, true)
			if editing or editor.mode == ScenarioEditor.Mode.COAST:
				for sp in pts:
					draw_rect(Rect2(sp - Vector2(2.5, 2.5), Vector2(5, 5)), Color(TacticalMap.COL_COAST, 0.9 if editing else 0.5), not editing, 1.0)
			if l.name != "" and pts.size() >= 3:
				draw_string(_font, w2s(l.centroid) + Vector2(-l.name.length() * 3.0, 0.0), l.name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, TacticalMap.COL_LAND_LABEL)
