class_name ScenarioEditor
extends PanelContainer
## In-game scenario editor. Place platforms on a chart, set headings, patrol routes, objectives
## and the environment, then save under user://scenarios, share as JSON, or play straight away.
## Produces the same JSON the built-in missions use, so anything the loader accepts can be built.

signal play_requested(path: String)
signal closed()

enum Mode { PLACE, MOVE, PATROL, AREA, COAST }

const FACTIONS := ["BLUE", "RED", "NEUTRAL"]
const OBJECTIVE_KINDS := ["Survive for a time", "Destroy the opposing force", "Reach an area", "Hold an area continuously", "Recover aircraft"]
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
var _layer: SpinBox
var _cz: SpinBox
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
var _palette_search: LineEdit
var _palette_era: OptionButton
var _place_count: SpinBox
var _tasks: ItemList
var _task_index := 0
var _sequence: CheckBox
var _scope: OptionButton
var _objective_radius: SpinBox
var _objective_count: SpinBox
var _victory_mode: OptionButton
var _arrival: SpinBox
var _unit_policy: OptionButton
var _loadout_box: VBoxContainer
var _wing_box: VBoxContainer
var _recipe_popup: PopupPanel
var _recipe := {"seed": 29, "year": 2027, "region": 0, "blue_ships": 6, "red_ships": 6, "blue_carriers": 1, "red_carriers": 0, "blue_subs": 1, "red_subs": 1, "aircraft_per_carrier": 24, "formation": "screen", "sea_state": 2, "coastlines": false}
var _history: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _opened_path := ""


func _ready() -> void:
	theme_type_variation = "OverlayPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# A front-end screen: the dusk backdrop under one grey-metal panel.
	add_child(UITheme.backdrop())
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, 20)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)
	var sheet := PanelContainer.new()
	sheet.theme_type_variation = "MenuPanel"
	# A tighter margin than the menus': the chart wants the room.
	sheet.add_theme_stylebox_override("panel", UITheme.metal_panel(14))
	margin.add_child(sheet)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	sheet.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 0)
	head.add_child(title_box)
	var eyebrow := UITheme.caption("Mission editor")
	title_box.add_child(eyebrow)
	var title := Label.new()
	title.text = "Build a mission"
	title.theme_type_variation = "TitleLabel"
	title_box.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_load_menu = OptionButton.new()
	_load_menu.focus_mode = Control.FOCUS_ALL
	_load_menu.custom_minimum_size.x = 230
	_load_menu.item_selected.connect(_on_load_selected)
	head.add_child(_load_menu)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	v.add_child(tools)
	_button(tools, "FLEET BUILDER", _open_recipe)
	_button(tools, "NEW", func() -> void: new_scenario())
	_button(tools, "UNDO", undo)
	_button(tools, "REDO", redo)
	_button(tools, "SAVE", save)
	_button(tools, "EXPORT JSON", _export_json)
	_button(tools, "IMPORT JSON", _import_json)
	var play := _button(tools, "SAVE AND PLAY", _play)
	play.theme_type_variation = "PrimaryButton"
	_button(tools, "CLOSE", func() -> void: closed.emit())

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
	_palette_search = LineEdit.new()
	_palette_search.placeholder_text = "Search class, nation or platform"
	_palette_search.text_changed.connect(func(_text: String) -> void: _fill_palette())
	left.add_child(_palette_search)
	_palette_era = OptionButton.new()
	for text: String in ["All equipment", "Modern equipment", "1990 equipment"]:
		_palette_era.add_item(text)
	_palette_era.item_selected.connect(func(_i: int) -> void: _fill_palette())
	left.add_child(_palette_era)
	_place_count = _spin(left, "Place together", 1, 24, 1, func(_v: float) -> void: pass)
	_palette = ItemList.new()
	_palette.theme_type_variation = "MenuList"
	_palette.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_palette.focus_mode = Control.FOCUS_ALL
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
		b.theme_type_variation = "SegmentButton"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_ALL
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
		if _syncing:
			return
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
	# The water column. A layer hides a boat below it from hull sonars; convergence zones need a
	# charted deep basin as well as a range here. Zero turns either off.
	_layer = _spin(props, "Thermal layer depth (m, 0 none)", 0, 600, 10, func(v: float) -> void:
		scenario["environment"]["layer_depth_m"] = int(v)
		if v > 0.0 and float(scenario["environment"].get("layer_strength", 0.0)) <= 0.0:
			scenario["environment"]["layer_strength"] = 0.7)
	_cz = _spin(props, "Convergence zone range (nm, 0 none)", 0, 40, 1, func(v: float) -> void: scenario["environment"]["cz_range_nm"] = int(v))
	_section(props, "OBJECTIVE")
	_tasks = ItemList.new()
	_tasks.custom_minimum_size.y = 90
	_tasks.item_selected.connect(func(i: int) -> void:
		_task_index = i
		_sync_task())
	props.add_child(_tasks)
	var tasks_row := HBoxContainer.new()
	props.add_child(tasks_row)
	_button(tasks_row, "ADD TASK", _add_task)
	_button(tasks_row, "REMOVE TASK", _remove_task)
	_victory_mode = OptionButton.new()
	_victory_mode.add_item("Complete every victory task")
	_victory_mode.add_item("Complete any victory task")
	_victory_mode.item_selected.connect(func(i: int) -> void:
		if not _syncing:
			scenario["victory_mode"] = "all" if i == 0 else "any")
	props.add_child(_victory_mode)
	_objective_kind = OptionButton.new()
	_objective_kind.focus_mode = Control.FOCUS_ALL
	for k in OBJECTIVE_KINDS:
		_objective_kind.add_item(k)
	_objective_kind.item_selected.connect(func(_i: int) -> void: _apply_objective())
	props.add_child(_objective_kind)
	_minutes = _spin(props, "Minutes to hold", 5, 240, 5, func(_v: float) -> void: _apply_objective())
	_scope = OptionButton.new()
	_scope.item_selected.connect(func(_i: int) -> void: _apply_objective())
	props.add_child(_scope)
	_objective_radius = _spin(props, "Area radius (nm)", 1, 100, 1, func(_v: float) -> void: _apply_objective())
	_objective_count = _spin(props, "Platforms / sorties required", 1, 96, 1, func(_v: float) -> void: _apply_objective())
	_sequence = CheckBox.new()
	_sequence.text = "After the preceding task"
	_sequence.toggled.connect(func(_on: bool) -> void: _apply_objective())
	props.add_child(_sequence)
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
	_faction.focus_mode = Control.FOCUS_ALL
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
	_radar.focus_mode = Control.FOCUS_ALL
	_radar.toggled.connect(func(on: bool) -> void: _unit_set("radar_on", on))
	_unit_box.add_child(_radar)
	_protect = CheckBox.new()
	_protect.text = "PROTECT: mission fails if lost"
	_protect.focus_mode = Control.FOCUS_ALL
	_protect.toggled.connect(func(on: bool) -> void: _set_protected(on))
	_unit_box.add_child(_protect)
	_posture = OptionButton.new()
	_posture.focus_mode = Control.FOCUS_ALL
	_posture.add_item("AI posture: standard")
	_posture.add_item("AI posture: breakout (presses on)")
	_posture.item_selected.connect(func(i: int) -> void: _unit_set("ai_posture", "breakout" if i == 1 else "standard"))
	_unit_box.add_child(_posture)
	_home = OptionButton.new()
	_home.focus_mode = Control.FOCUS_ALL
	_home.item_selected.connect(func(i: int) -> void: _unit_set("home", _home.get_item_text(i)))
	_unit_box.add_child(_home)
	_arrival = _spin(_unit_box, "Arrival (min, 0 = opening force)", 0, 480, 1, func(v: float) -> void: _unit_set("editor_arrival_s", v * 60))
	_unit_policy = OptionButton.new()
	for policy: String in ["balanced", "conserve", "saturation"]:
		_unit_policy.add_item("Defence: " + policy)
	_unit_policy.item_selected.connect(func(i: int) -> void: _unit_set("defence_policy", ["balanced", "conserve", "saturation"][i]))
	_unit_box.add_child(_unit_policy)
	_loadout_box = VBoxContainer.new()
	_unit_box.add_child(_loadout_box)
	_wing_box = VBoxContainer.new()
	_unit_box.add_child(_wing_box)
	var patrol_row := HBoxContainer.new()
	_unit_box.add_child(patrol_row)
	_button(patrol_row, "CLEAR PATROL", func() -> void:
		if selected_index >= 0:
			_checkpoint()
			scenario["units"][selected_index].erase("patrol_nm")
			_chart.queue_redraw())
	_button(patrol_row, "DELETE UNIT", delete_selected)
	_button(patrol_row, "CLONE", duplicate_selected)

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
		var problem := ScenarioWorkshop.structural_problem(parsed)
		if problem != "":
			_say(problem, true)
			return
		load_dict(parsed)
		_json_popup.hide()
		_say("Scenario imported: %s" % scenario.get("name", "?"), false))
	_button(pb, "COPY TO CLIPBOARD", func() -> void:
		DisplayServer.clipboard_set(_json_text.text)
		_say("Copied", false))
	_button(pb, "CLOSE", func() -> void: _json_popup.hide())
	add_child(_json_popup)
	_build_recipe_popup()

	_fill_palette()
	new_scenario()
	_set_mode(Mode.PLACE)


func focus_default() -> void:
	if visible and _load_menu != null:
		_load_menu.grab_focus()


# --- Construction helpers ----------------------------------------------------------------

func _button(parent: Node, text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
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
	_palette_specs = []
	var query := _palette_search.text.to_lower() if _palette_search != null else ""
	var era := _palette_era.selected if _palette_era != null else 0
	for spec: PlatformSpec in DataDB.all_platforms():
		if era == 1 and spec.id.begins_with("cw90_"):
			continue
		if era == 2 and not spec.id.begins_with("cw90_"):
			continue
		if query != "" and not (spec.id + " " + spec.display_name + " " + spec.nation + " " + spec.category).to_lower().contains(query):
			continue
		_palette_specs.append(spec)
	for spec: PlatformSpec in _palette_specs:
		var glyph := MapSymbols.category_glyph(spec.category, spec.domain)
		_palette.add_item("%-3s %s · %s" % [glyph, spec.nation if spec.nation != "" else "—", spec.display_name])
	if not _palette_specs.is_empty():
		# Start on a surface ship: an aircraft cannot be placed until a deck exists, so opening
		# on one makes the first click on the chart fail.
		var first := 0
		for i in _palette_specs.size():
			if _palette_specs[i].domain == "surface":
				first = i
				break
		_palette.select(first)
		_palette.ensure_current_is_visible()
		palette_platform = _palette_specs[first].id
		_preview.spec_override = _palette_specs[first]


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
	_status.add_theme_color_override("font_color", UITheme.INK_RED if warn else UITheme.INK_DIM)


# --- Model -------------------------------------------------------------------------------

func new_scenario() -> void:
	_history.clear()
	_redo.clear()
	_opened_path = ""
	_task_index = 0
	scenario = {
		"id": "custom_mission_%d" % Time.get_unix_time_from_system(),
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
	var problem := ScenarioWorkshop.structural_problem(d)
	if problem != "":
		_say(problem, true)
		return
	scenario = d.duplicate(true)
	_opened_path = ""
	_task_index = 0
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
	var kept_events: Array = []
	for event: Dictionary in scenario.get("events", []):
		if bool(event.get("editor_wave", false)):
			for u: Dictionary in event.get("reinforcements", []):
				u["editor_arrival_s"] = float(event.get("at_s", 0))
				scenario["units"].append(u)
		else:
			kept_events.append(event)
	scenario["events"] = kept_events
	var tasks: Array = []
	for objective: Dictionary in scenario["objectives"]["victory"]:
		if str(objective.get("id", "")).begins_with("waves_arrived_"):
			continue
		var after: Array = []
		for id in objective.get("after", []):
			if not str(id).begins_with("waves_arrived_"):
				after.append(id)
		if not after.is_empty():
			objective["after"] = after
		else:
			objective.erase("after")
		tasks.append(objective)
	scenario["objectives"]["victory"] = tasks
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
	_layer.value = int(scenario["environment"].get("layer_depth_m", 0))
	_cz.value = int(scenario["environment"].get("cz_range_nm", 0))
	_objective_text.text = str(scenario["objectives"].get("text", ""))
	_victory_mode.select(1 if scenario.get("victory_mode", "all") == "any" else 0)
	_syncing = false
	_sync_tasks()
	_sync_task()
	_sync_unit()
	_chart.queue_redraw()


func _apply_objective() -> void:
	if _syncing or scenario.is_empty():
		return
	var kind := _objective_kind.selected
	var victory: Array = scenario["objectives"]["victory"]
	if victory.is_empty():
		victory.append({"id": "task_1", "type": "time_elapsed", "seconds": 1800})
	_task_index = clampi(_task_index, 0, victory.size() - 1)
	var original: Dictionary = victory[_task_index]
	var existing_area: Dictionary = {}
	if original.get("type", "") in ["reach_area", "hold_area"]:
		existing_area = original.duplicate(true)
	var objective: Dictionary = {}
	match kind:
		0:
			objective = {"type": "time_elapsed", "seconds": int(_minutes.value) * 60, "text": "Survive for %d minutes" % int(_minutes.value)}
		1:
			objective = {"type": "force_destroyed", "faction": "RED", "text": "Defeat the opposing force"}
		2, 3:
			if existing_area.is_empty():
				var c: Array = scenario["map"]["center_nm"]
				existing_area = {"faction": str(scenario.get("player_faction", "BLUE")), "center_nm": [float(c[0]), float(c[1]) + 20.0]}
			objective = existing_area
			objective["type"] = "reach_area" if kind == 2 else "hold_area"
			objective["radius_nm"] = _objective_radius.value
			objective["count"] = int(_objective_count.value)
			objective["seconds"] = _minutes.value * 60
			objective["text"] = "Reach the objective area" if kind == 2 else "Hold the objective area continuously"
		4:
			objective = {"type": "aircraft_recovered", "faction": str(scenario.get("player_faction", "BLUE")), "count": int(_objective_count.value), "text": "Complete %d aircraft recoveries" % int(_objective_count.value)}
	objective["id"] = original.get("id", "task_%d" % (_task_index + 1))
	if original.get("phase_only", false):
		objective["phase_only"] = true
	if _scope != null and _scope.selected > 0 and kind in [2, 3, 4]:
		objective["callsigns"] = [_scope.get_item_text(_scope.selected)]
	else:
		objective["callsigns"] = []
	if _sequence.button_pressed and _task_index > 0:
		objective["after"] = [victory[_task_index - 1]["id"]]
	victory[_task_index] = objective
	_sync_tasks()
	_sync_task()
	_chart.queue_redraw()


func set_area(world: Vector2) -> void:
	if _objective_kind.selected not in [2, 3]:
		_objective_kind.select(2)
	_apply_objective()
	if on_land(world):
		_say("An objective area on land cannot be reached by a ship", true)
		return
	var o: Dictionary = scenario["objectives"]["victory"][_task_index]
	o["center_nm"] = [snappedf(world.x, 0.5), snappedf(world.y, 0.5)]
	_say("Objective area set at %s %s" % [Geo.format_axis(world.x, "E", "W"), Geo.format_axis(world.y, "N", "S")], false)
	_chart.queue_redraw()


func place(world: Vector2) -> void:
	_checkpoint()
	var count := int(_place_count.value) if _place_count != null else 1
	for i in count:
		_place_one(world + Vector2((i % 4) * 2.0, floori(i / 4.0) * 2.0))
	_sync_tasks()


func _place_one(world: Vector2) -> void:
	var spec := DataDB.platform(palette_platform)
	if spec == null:
		return
	var faction := "BLUE"
	if spec.nation in ["Russia", "China", "Iran"]:
		faction = "RED"
	elif spec.category.contains("merchant"):
		faction = "NEUTRAL"
	var ud := {"platform": spec.id, "callsign": _unique_callsign(spec), "faction": faction}
	if spec.domain == "air":
		var home := _nearest_deck(world, faction, spec)
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


func _nearest_deck(world: Vector2, faction: String, aircraft: PlatformSpec) -> String:
	var best := ""
	var best_d := INF
	for u in scenario["units"]:
		if u.get("faction", "") != faction or not u.has("position_nm"):
			continue
		var spec := DataDB.platform(u.get("platform", ""))
		if spec == null or not spec.can_operate(aircraft):
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
	_checkpoint()
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
	_checkpoint()
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
	_checkpoint()
	if selected_index < 0:
		return
	var gone: String = scenario["units"][selected_index].get("callsign", "")
	scenario["units"].remove_at(selected_index)
	for u in scenario["units"]:
		if u.get("home", "") == gone:
			u.erase("home")
		if u.get("formation_leader", "") == gone:
			u.erase("formation_leader")
			u.erase("formation_offset_nm")
	_strip_protected(gone)
	selected_index = -1
	_sync_unit()
	_chart.queue_redraw()


func _unit_set(key: String, value) -> void:
	if selected_index < 0 or _syncing:
		return
	_checkpoint()
	var u: Dictionary = scenario["units"][selected_index]
	if key == "callsign":
		var old: String = u.get("callsign", "")
		for a in scenario["units"]:
			if a.get("home", "") == old:
				a["home"] = value
		_rename_protected(old, value)
		for member in scenario["units"]:
			if member.get("formation_leader", "") == old:
				member["formation_leader"] = value
		for objective in scenario["objectives"]["victory"]:
			var scope: Array = objective.get("callsigns", [])
			for i in scope.size():
				if scope[i] == old:
					scope[i] = value
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
		_arrival.value = float(u.get("editor_arrival_s", 0)) / 60
		_unit_policy.select(maxi(["balanced", "conserve", "saturation"].find(u.get("defence_policy", "balanced")), 0))
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
	_rebuild_fit_controls()


func _checkpoint() -> void:
	if _syncing or scenario.is_empty():
		return
	_history.append(scenario.duplicate(true))
	if _history.size() > 60:
		_history.pop_front()
	_redo.clear()


func undo() -> void:
	if _history.is_empty():
		return
	_redo.append(scenario.duplicate(true))
	var path := _opened_path
	load_dict(_history.pop_back())
	_opened_path = path
	_say("Undid the last edit", false)


func redo() -> void:
	if _redo.is_empty():
		return
	_history.append(scenario.duplicate(true))
	var path := _opened_path
	load_dict(_redo.pop_back())
	_opened_path = path
	_say("Redid the last edit", false)


func duplicate_selected() -> void:
	if selected_index < 0:
		return
	_checkpoint()
	var copy: Dictionary = scenario["units"][selected_index].duplicate(true)
	var spec := DataDB.platform(str(copy["platform"]))
	copy["callsign"] = _unique_callsign(spec)
	# A cloned carrier needs its own flight identities, not a second set bearing the old
	# carrier's callsigns. Keep its aircraft types, counts, loadouts and readiness settings.
	for entry: Dictionary in copy.get("air_wing", []):
		var aircraft := DataDB.platform(str(entry.get("platform", "")))
		if aircraft != null:
			entry["callsign"] = "%s %s" % [copy["callsign"], aircraft.short_name]
	if copy.has("position_nm"):
		var p: Array = copy["position_nm"]
		copy["position_nm"] = [float(p[0]) + 2.0, float(p[1]) + 2.0]
	scenario["units"].append(copy)
	selected_index = scenario["units"].size() - 1
	_sync_unit()
	_sync_tasks()
	_chart.queue_redraw()


func _sync_tasks() -> void:
	if _tasks == null:
		return
	_tasks.clear()
	var victory: Array = scenario.get("objectives", {}).get("victory", [])
	for i in victory.size():
		var o: Dictionary = victory[i]
		_tasks.add_item("%d. %s" % [i + 1, o.get("text", o.get("type", "Task"))])
	if not victory.is_empty():
		_task_index = clampi(_task_index, 0, victory.size() - 1)
		_tasks.select(_task_index)


func _sync_task() -> void:
	var victory: Array = scenario.get("objectives", {}).get("victory", [])
	if victory.is_empty():
		return
	_syncing = true
	_task_index = clampi(_task_index, 0, victory.size() - 1)
	var o: Dictionary = victory[_task_index]
	var kinds := ["time_elapsed", "force_destroyed", "reach_area", "hold_area", "aircraft_recovered"]
	var kind := maxi(kinds.find(o.get("type", "time_elapsed")), 0)
	_objective_kind.select(kind)
	_minutes.value = float(o.get("seconds", 1800)) / 60
	_minutes.get_parent().visible = kind in [0, 3]
	_objective_radius.value = float(o.get("radius_nm", 8))
	_objective_radius.get_parent().visible = kind in [2, 3]
	_objective_count.value = int(o.get("count", 1))
	_objective_count.get_parent().visible = kind in [2, 3, 4]
	_scope.clear()
	_scope.add_item("Any player platform")
	var names: Array = o.get("callsigns", [])
	for u: Dictionary in scenario.get("units", []):
		if u.get("faction", "BLUE") == scenario.get("player_faction", "BLUE"):
			_scope.add_item(str(u["callsign"]))
			if names.has(u["callsign"]):
				_scope.select(_scope.item_count - 1)
	_scope.visible = kind in [2, 3, 4]
	_sequence.disabled = _task_index == 0
	_sequence.set_pressed_no_signal(not o.get("after", []).is_empty())
	_syncing = false


func _add_task() -> void:
	_checkpoint()
	var tasks: Array = scenario["objectives"]["victory"]
	var id := "task_%d" % (tasks.size() + 1)
	var ids: Array = []
	for task in tasks:
		ids.append(task.get("id", ""))
	while ids.has(id):
		id += "_new"
	var task := {"id": id, "type": "time_elapsed", "seconds": 1800, "text": "Survive for 30 minutes"}
	if not tasks.is_empty():
		task["after"] = [tasks.back()["id"]]
	tasks.append(task)
	_task_index = tasks.size() - 1
	_sync_tasks()
	_sync_task()


func _remove_task() -> void:
	var tasks: Array = scenario["objectives"]["victory"]
	if tasks.is_empty():
		return
	_checkpoint()
	var id: String = tasks[_task_index].get("id", "")
	tasks.remove_at(_task_index)
	for task in tasks:
		var after: Array = task.get("after", [])
		after.erase(id)
	_task_index = maxi(_task_index - 1, 0)
	_sync_tasks()
	_sync_task()
	_chart.queue_redraw()


func _rebuild_fit_controls() -> void:
	if _loadout_box == null:
		return
	for box in [_loadout_box, _wing_box]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	if selected_index < 0 or selected_index >= scenario["units"].size():
		return
	var u: Dictionary = scenario["units"][selected_index]
	var spec := DataDB.platform(str(u["platform"]))
	if spec == null:
		return
	if not spec.weapon_loadout.is_empty():
		_section(_loadout_box, "WEAPON FIT / ROUNDS")
		for wid: String in spec.weapon_loadout:
			var weapon := DataDB.weapon(wid)
			if weapon == null:
				continue
			var maximum := spec.vls_cells * weapon.vls_pack if weapon.vls_pack > 0 and spec.vls_cells > 0 else int(spec.weapon_loadout[wid])
			var spin := _spin(_loadout_box, weapon.display_name, 0, maximum, 1, func(value: float) -> void:
				if _syncing or selected_index < 0:
					return
				_checkpoint()
				var unit: Dictionary = scenario["units"][selected_index]
				if not unit.has("loadout"):
					unit["loadout"] = spec.weapon_loadout.duplicate()
				unit["loadout"][wid] = int(value))
			spin.set_value_no_signal(int(u.get("loadout", spec.weapon_loadout).get(wid, 0)))
	if spec.aircraft_capacity > 0:
		_section(_wing_box, "AIR WING / CAPACITY %d" % spec.aircraft_capacity)
		for aircraft: PlatformSpec in DataDB.all_platforms():
			if not spec.can_operate(aircraft) or aircraft.id.begins_with("cw90_") != spec.id.begins_with("cw90_"):
				continue
			# Show the host's own national equipment and its default detachment. The full
			# palette can still place compatible allied airframes individually.
			if aircraft.nation != spec.nation and not spec.default_air_wing.has(aircraft.id):
				continue
			var pid := aircraft.id
			var spin := _spin(_wing_box, aircraft.short_name, 0, spec.aircraft_capacity, 1, func(value: float) -> void: _set_wing_count(pid, int(value)))
			var count := 0
			for entry in u.get("air_wing", ScenarioLoader._default_wing(spec)):
				if entry.get("platform", "") == pid:
					count += int(entry.get("count", 0))
			spin.set_value_no_signal(count)


func _set_wing_count(pid: String, count: int) -> void:
	if _syncing or selected_index < 0:
		return
	_checkpoint()
	var u: Dictionary = scenario["units"][selected_index]
	var spec := DataDB.platform(str(u["platform"]))
	var entries: Array = u.get("air_wing", ScenarioLoader._default_wing(spec)).duplicate(true)
	var found := false
	for entry: Dictionary in entries:
		if entry.get("platform", "") == pid:
			entry["count"] = count
			found = true
	if not found and count > 0:
		entries.append({"platform": pid, "count": count, "callsign": "%s %s" % [u["callsign"], DataDB.platform(pid).short_name]})
	var kept: Array = []
	for entry: Dictionary in entries:
		if int(entry.get("count", 0)) > 0:
			kept.append(entry)
	u["air_wing"] = kept


func _build_recipe_popup() -> void:
	_recipe_popup = PopupPanel.new()
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_recipe_popup.add_child(margin)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 700
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	_section(box, "FLEET BUILDER")
	var hint := Label.new()
	hint.text = "Build a reproducible starting force, then edit every hull, air wing, task and arrival time. A seed changes the fleet mix."
	hint.custom_minimum_size.x = 700
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	var options := HBoxContainer.new()
	box.add_child(options)
	var era := OptionButton.new()
	era.add_item("Modern 2027")
	era.add_item("Cold War 1990")
	era.item_selected.connect(func(i: int) -> void: _recipe["year"] = 2027 if i == 0 else 1990)
	options.add_child(era)
	var region := OptionButton.new()
	for text in ["North Atlantic", "Western Pacific", "Arabian Sea", "Mediterranean"]:
		region.add_item(text)
	region.item_selected.connect(func(i: int) -> void: _recipe["region"] = i)
	options.add_child(region)
	var formation := OptionButton.new()
	for pattern: String in ["screen", "column", "abreast", "wedge", "dispersed"]:
		formation.add_item(pattern.capitalize())
	formation.item_selected.connect(func(i: int) -> void: _recipe["formation"] = ["screen", "column", "abreast", "wedge", "dispersed"][i])
	options.add_child(formation)
	var sides := HBoxContainer.new()
	box.add_child(sides)
	for side: String in ["blue", "red"]:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sides.add_child(column)
		_section(column, side.to_upper() + " FORCE")
		for entry in [["ships", "Surface ships", 1, 48], ["carriers", "Carriers (included above)", 0, 2], ["subs", "Submarines", 0, 12]]:
			var key := side + "_" + str(entry[0])
			var spin := _spin(column, entry[1], entry[2], entry[3], 1, func(value: float) -> void: _recipe[key] = int(value))
			spin.set_value_no_signal(_recipe[key])
	var seed_spin := _spin(box, "Seed", 0, 999999, 1, func(value: float) -> void: _recipe["seed"] = int(value))
	seed_spin.set_value_no_signal(29)
	var aircraft_spin := _spin(box, "Aircraft per carrier", 0, 72, 2, func(value: float) -> void: _recipe["aircraft_per_carrier"] = int(value))
	aircraft_spin.set_value_no_signal(24)
	var coast := CheckBox.new()
	coast.text = "Use charted coastlines (unchecked = open-water exercise)"
	coast.toggled.connect(func(on: bool) -> void: _recipe["coastlines"] = on)
	box.add_child(coast)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	_button(actions, "GENERATE FLEETS", func() -> void:
		_checkpoint()
		load_dict(ScenarioWorkshop.generate(_recipe))
		_recipe_popup.hide()
		_palette_era.select(2 if int(_recipe["year"]) == 1990 else 1)
		_fill_palette()
		_say("Generated %d authored units. Select a ship to edit weapons, air wing or arrival time." % scenario["units"].size(), false))
	_button(actions, "CANCEL", func() -> void: _recipe_popup.hide())
	add_child(_recipe_popup)


func _open_recipe() -> void:
	_recipe_popup.popup_centered(Vector2i(760, 420))


func _refresh_home_options() -> void:
	_home.clear()
	if selected_index < 0:
		return
	var u: Dictionary = scenario["units"][selected_index]
	var faction: String = u.get("faction", "BLUE")
	var chosen := -1
	for h in scenario["units"]:
		var spec := DataDB.platform(h.get("platform", ""))
		if spec == null or not spec.can_operate(DataDB.platform(u.get("platform", ""))) or h.get("faction", "") != faction:
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
	var problem := ScenarioWorkshop.validate(ScenarioWorkshop.export_scenario(scenario))
	return problem if problem != "" else _validate_terrain()


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
	return JSON.stringify(ScenarioWorkshop.export_scenario(scenario), "  ")


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


## The custom mission file this editor last opened or saved, or "".
func opened_path() -> String:
	return _opened_path


func save() -> bool:
	var problem := validate()
	if problem != "":
		_say(problem, true)
		return false
	ScenarioIndex.ensure_user_dir()
	var path := ScenarioIndex.custom_path(str(scenario.get("id", "custom_mission")))
	# A new recipe or import must not replace an unrelated mission with the same seed or slug.
	if path != _opened_path and FileAccess.file_exists(path):
		var base_id := str(scenario["id"])
		var suffix := 2
		while FileAccess.file_exists(ScenarioIndex.custom_path("%s_%d" % [base_id, suffix])):
			suffix += 1
		scenario["id"] = "%s_%d" % [base_id, suffix]
		path = ScenarioIndex.custom_path(scenario["id"])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_say("Could not write %s" % path, true)
		return false
	f.store_string(to_json())
	f.close()
	_opened_path = path
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
		if path.begins_with(ScenarioIndex.user_root()):
			_opened_path = path
		else:
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
	if k == null or not k.pressed:
		return
	if k.ctrl_pressed or k.meta_pressed:
		if k.keycode == KEY_Z:
			if k.shift_pressed:
				redo()
			else:
				undo()
			get_viewport().set_input_as_handled()
			return
		if k.keycode == KEY_Y:
			redo()
			get_viewport().set_input_as_handled()
			return
	if k.keycode != KEY_DELETE or _callsign.has_focus() or _coast_name.has_focus():
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
		_font = UITheme.body_font()
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
		draw_rect(Rect2(Vector2.ZERO, size), UITheme.CHART_SEA)
		if editor == null or editor.scenario.is_empty():
			UITheme.draw_bevel_frame(self, Rect2(Vector2.ZERO, size))
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
		var label_jobs: Array[Dictionary] = []
		var label_blockers: Array[Rect2] = []
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
				MapSymbols.draw_brackets(self, draw_at, Color.WHITE)
			elif i == _hover:
				draw_arc(draw_at, 15.0, 0.0, TAU, 24, Color(col, 0.5), 1.0, true)
			var label: String = u.get("callsign", "")
			if protected.has(label):
				label += "  (P)"
			if i == editor.selected_index or not is_air:
				label_jobs.append({"label": label, "at": draw_at, "color": col, "priority": 2 if i == editor.selected_index else (1 if i == _hover else 0)})
			label_blockers.append(Rect2(draw_at - Vector2(8, 8), Vector2(16, 16)))
		label_jobs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["priority"] > b["priority"])
		for job in label_jobs:
			var label_size := Vector2(_font.get_string_size(job["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 4, 14)
			for offset: Vector2 in [Vector2(14, -10), Vector2(14, -26), Vector2(14, 8), Vector2(-label_size.x - 14, -10), Vector2(-label_size.x - 14, 8)]:
				var rect := Rect2(job["at"] + offset, label_size)
				if not Rect2(Vector2(3, 22), size - Vector2(6, 46)).encloses(rect):
					continue
				if label_blockers.any(func(other: Rect2) -> bool: return rect.intersects(other)):
					continue
				draw_string(_font, rect.position + Vector2(2, 11), job["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(job["color"], 0.9))
				label_blockers.append(rect.grow(2))
				break
		draw_string(_font, Vector2(10, 16), "%s  ·  %d units  ·  sea state %d" % [str(editor.scenario.get("name", "")).to_upper(), units.size(), int(editor.scenario["environment"].get("sea_state", 0))], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.COL_ACCENT)
		draw_string(_font, Vector2(10, size.y - 20), "(P) protected · dashed: patrol route · box: mission chart extent · filled: land", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.COL_DIM)
		UITheme.draw_bevel_frame(self, Rect2(Vector2.ZERO, size))


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
