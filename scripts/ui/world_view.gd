class_name WorldView
extends Control
## A window on the sea around the commander's focus: a battle camera rendered from the
## simulation's state into a SubViewport. It shows exactly what WorldPresentation allows, which
## is what a lookout could see and what the plot holds, and nothing else.
##
## Three modes: HIDDEN, INSET (a floating card in the chart's lower-right corner) and FULL (the
## whole chart rect). Mouse input inside the view never reaches the chart underneath; the
## keyboard stays with Main, which cycles the modes on T and hands the view its effects.

enum Mode { HIDDEN, INSET, FULL }
enum Preset { BRIDGE, ORBIT, OVERHEAD, CHASE }

signal mode_changed(mode: int)

const INSET_SIZE := Vector2(420, 236)
const INSET_MARGIN := 12.0
const PRESET_NAMES := ["BRIDGE", "ORBIT", "OVERHEAD", "CHASE"]
const PRESET_TIPS := ["Bridge: low, aft of the bridge, looking forward", "Orbit: an elevated three-quarter view", "Overhead: nearly straight down", "Chase: behind, along the heading"]
## rel_az is the bearing from the focus to the camera relative to the focus heading, pitch is in
## degrees above the water, dist is a multiple of the focus's length.
const PRESETS := {
	Preset.BRIDGE: {"rel_az": 0.0, "pitch": -3.0, "dist": 0.0, "fov": 62.0},
	Preset.ORBIT: {"rel_az": 135.0, "pitch": 15.0, "dist": 2.3, "fov": 50.0},
	Preset.OVERHEAD: {"rel_az": 180.0, "pitch": 78.0, "dist": 5.0, "fov": 50.0},
	Preset.CHASE: {"rel_az": 180.0, "pitch": 10.0, "dist": 3.0, "fov": 58.0},
}
const ORIGIN_RATE := 6.0
const CAMERA_RATE := 3.0
const HUD_PAD := 12.0
const LABEL_LIMIT_FULL := 24
const LABEL_LIMIT_INSET := 6
const LABEL_RANGE_M := 22.0 * WorldPresentation.NM_TO_M
const MIN_CAMERA_HEIGHT_M := 2.5
const DEFAULT_START_TIME := "1990-03-21T11:00:00"
const FOOTER_TEXT := "WORLD VIEW  ·  what you can see, and what you hold on the plot"

var map: TacticalMap
var simulation: Simulation
var mode: Mode = Mode.HIDDEN
var preset: Preset = Preset.ORBIT

var _container: SubViewportContainer
var _viewport: SubViewport
var _scene: WorldScene
var _hud: Control
var _controls: HBoxContainer
var _preset_panel: PanelContainer
var _preset_buttons: Array[Button] = []
var _cycle_button: Button
var _expand_button: Button
var _close_button: Button
var _frame: StyleBoxFlat
var _origin_nm := Vector2.ZERO
var _origin_valid := false
var _focus: Dictionary = {}
var _focus_key := ""
var _cam_az := 0.0
var _cam_pitch := 21.0
var _cam_dist := 500.0
var _cam_valid := false
var _az_offset := 0.0
var _pitch_user := NAN
var _dist_factor := 1.0
var _dragging := false
var _entries: Array = []
var _anchors: Array[Dictionary] = []
var _label_rects: Array[Rect2] = []
var _sun_angles := Vector2.ZERO
var _default_unix := 0
var _shown := {"own": 0, "visual": 0, "plotted": 0, "weapon": 0}


func _ready() -> void:
	name = "WorldView"
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	visible = false
	_frame = UITheme.floating_panel(0)
	_default_unix = Time.get_unix_time_from_datetime_string(DEFAULT_START_TIME)
	_container = SubViewportContainer.new()
	_container.name = "ViewportContainer"
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.gui_disable_input = true
	_container.add_child(_viewport)
	_scene = WorldScene.new()
	_viewport.add_child(_scene)
	_scene.build()
	_hud = Control.new()
	_hud.name = "Hud"
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	add_child(_hud)
	_build_controls()
	visibility_changed.connect(_sync_visibility)
	resized.connect(_layout_controls)
	_apply_mode_layout()
	_sync_visibility()


# --- Public API (Main) -------------------------------------------------------------------

func set_mode(next: Mode) -> void:
	if next == mode:
		return
	mode = next
	_apply_mode_layout()
	visible = mode != Mode.HIDDEN
	if map != null:
		map.set_overview_suppressed(visible)
	_sync_visibility()
	if visible:
		refocus()
	mode_changed.emit(mode)


## HIDDEN → INSET → FULL → HIDDEN.
func cycle_mode() -> void:
	set_mode(((mode + 1) % 3) as Mode)


func mode_name() -> String:
	return ["hidden", "inset", "full"][mode]


func set_preset(next: Preset) -> void:
	preset = next
	for i in _preset_buttons.size():
		_preset_buttons[i].set_pressed_no_signal(i == preset)
	refocus()


func set_preset_by_name(preset_name: String) -> void:
	var index := PRESET_NAMES.find(preset_name.to_upper())
	if index >= 0:
		set_preset(index as Preset)


## Drops any orbit, tilt or zoom the player applied so the camera returns to the preset's
## framing of the current focus. Main calls it whenever the selection changes.
func refocus() -> void:
	_az_offset = 0.0
	_pitch_user = NAN
	_dist_factor = 1.0


## A simulation event at a chart position, beside the chart's own `add_effect`. `height_m`
## places an airburst; leave it negative for something at the surface.
func add_effect(pos: Vector2, kind: String, own := false, height_m := -1.0) -> void:
	if _scene != null and is_visible_in_tree():
		_scene.add_effect(pos, kind, own, height_m)


## A new scenario: forget wakes, smoke, sinking hulls and the camera's memory.
func reset_presentation() -> void:
	if _scene != null:
		_scene.reset()
	_origin_valid = false
	_cam_valid = false
	_focus = {}
	_focus_key = ""
	refocus()


# --- Layout ------------------------------------------------------------------------------

func _apply_mode_layout() -> void:
	if mode == Mode.FULL:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		offset_left = -(INSET_MARGIN + INSET_SIZE.x)
		offset_right = -INSET_MARGIN
		offset_top = -(TacticalMap.FOOTER_H + 10.0 + INSET_SIZE.y)
		offset_bottom = -(TacticalMap.FOOTER_H + 10.0)
		_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 1)
	if _preset_panel != null:
		_preset_panel.visible = mode == Mode.FULL
		_cycle_button.visible = mode != Mode.FULL
		UIIcons.apply(_expand_button, "collapse" if mode == Mode.FULL else "expand", 18)
		_expand_button.tooltip_text = "Back to the inset card" if mode == Mode.FULL else "Expand to the full chart"
	queue_redraw()
	call_deferred("_layout_controls")


func _build_controls() -> void:
	_controls = HBoxContainer.new()
	_controls.name = "Controls"
	_controls.add_theme_constant_override("separation", 6)
	_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_controls)
	_preset_panel = PanelContainer.new()
	_preset_panel.theme_type_variation = "SegmentedPanel"
	_preset_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_controls.add_child(_preset_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	_preset_panel.add_child(row)
	var group := ButtonGroup.new()
	for i in PRESET_NAMES.size():
		var b := Button.new()
		b.theme_type_variation = "SegmentButton"
		b.text = PRESET_NAMES[i]
		b.tooltip_text = PRESET_TIPS[i]
		b.accessibility_name = PRESET_TIPS[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == preset
		b.focus_mode = Control.FOCUS_ALL
		b.add_theme_font_size_override("font_size", 10)
		b.pressed.connect(set_preset.bind(i as Preset))
		row.add_child(b)
		_preset_buttons.append(b)
	var tools := PanelContainer.new()
	tools.theme_type_variation = "ToolbarPanel"
	tools.mouse_filter = Control.MOUSE_FILTER_STOP
	_controls.add_child(tools)
	var tool_row := HBoxContainer.new()
	tool_row.add_theme_constant_override("separation", 2)
	tools.add_child(tool_row)
	_cycle_button = _icon_button("focus", "Next camera: bridge, orbit, overhead, chase", func() -> void: set_preset(((preset + 1) % PRESET_NAMES.size()) as Preset))
	tool_row.add_child(_cycle_button)
	_expand_button = _icon_button("expand", "Expand to the full chart", _toggle_expand)
	tool_row.add_child(_expand_button)
	_close_button = _icon_button("close", "Close the world view  [T cycles inset, full, hidden]", func() -> void: set_mode(Mode.HIDDEN))
	tool_row.add_child(_close_button)


func _icon_button(icon_name: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.theme_type_variation = "QuietButton"
	b.tooltip_text = tip
	b.accessibility_name = tip.get_slice("  [", 0)
	b.custom_minimum_size = Vector2(32, 32)
	b.focus_mode = Control.FOCUS_ALL
	UIIcons.apply(b, icon_name, 18)
	b.pressed.connect(action)
	return b


func _toggle_expand() -> void:
	set_mode(Mode.INSET if mode == Mode.FULL else Mode.FULL)


func _layout_controls() -> void:
	if _controls == null:
		return
	var wanted := _controls.get_combined_minimum_size()
	_controls.size = wanted
	_controls.position = Vector2(size.x - HUD_PAD - wanted.x, HUD_PAD if mode == Mode.FULL else 8.0)
	if _hud != null:
		_hud.queue_redraw()


func _sync_visibility() -> void:
	var live := is_visible_in_tree()
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if live else SubViewport.UPDATE_DISABLED
	set_process(live)
	if not live:
		_dragging = false


func _draw() -> void:
	if mode == Mode.INSET:
		draw_style_box(_frame, Rect2(Vector2.ZERO, size))


# --- Per frame ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if map == null or simulation == null or not is_visible_in_tree():
		return
	if _dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_dragging = false
	var player := simulation.player_faction
	var um := simulation.unit_manager
	var own_units: Array = um.get_faction_units(player) if um != null else []
	_focus = WorldPresentation.choose_focus(map.selected, map.selected_track, own_units)
	var focus_pos: Vector2 = _focus.get("position", _origin_nm)
	_focus_key = _focus.get("key", "")
	if not _origin_valid:
		_origin_nm = focus_pos
		_origin_valid = true
	else:
		_origin_nm = _origin_nm.lerp(focus_pos, 1.0 - exp(-ORIGIN_RATE * delta))
		if _origin_nm.distance_to(focus_pos) < 1.0e-5:
			_origin_nm = focus_pos
	_scene.origin_nm = _origin_nm
	_scene.sim_now = SimClock.sim_time
	var env := Detection.environment
	_scene.set_weather(Detection.sea_state, WorldPresentation.visibility_nm(env), env)
	var chart: Dictionary = simulation.scenario.get("map", {})
	var latlon := WorldPresentation.latlon_of(focus_pos, chart)
	var unix := float(SimClock.start_unix_time if SimClock.start_unix_time > 0 else _default_unix) + SimClock.sim_time
	_sun_angles = WorldPresentation.sun_angles(unix, latlon.x, latlon.y)
	_scene.shadows_allowed = mode == Mode.FULL
	_scene.focus_ring = preset != Preset.BRIDGE
	_scene.set_time_of_day(WorldPresentation.sun_direction(unix, latlon.x, latlon.y), _sun_angles.x)
	var entries: Array = WorldPresentation.unit_entries(um, simulation.track_manager, player, env, simulation.track_manager.neutral_factions)
	entries.append_array(WorldPresentation.weapon_entries(simulation.weapon_manager, simulation.threat_manager, player, map.reference_unit()))
	entries.append_array(WorldPresentation.buoy_entries(simulation.aviation_manager, player, SimClock.sim_time))
	_entries = WorldPresentation.cull(entries, focus_pos, _focus_key)
	for k in _shown:
		_shown[k] = 0
	for e: Dictionary in _entries:
		var kind: String = e["kind"]
		if _shown.has(kind):
			_shown[kind] += 1
	_scene.update(delta, _entries, _focus_key)
	_update_camera(delta)
	_anchors = _scene.anchors()
	_hud.queue_redraw()


func _update_camera(delta: float) -> void:
	var cam := _scene.camera
	var frame := _scene.focus_frame(_focus_key)
	var target: Vector3
	var length := 150.0
	var heading := 0.0
	var domain := "surface"
	if frame.is_empty():
		var height := 0.0
		var unit: Unit = _focus.get("unit")
		if unit != null:
			height = WorldPresentation.height_of(unit)
			heading = unit.heading_deg
			length = WorldPresentation.length_of(unit.spec)
			domain = WorldPresentation.domain_of(unit)
		target = WorldPresentation.to_world(_focus.get("position", _origin_nm), _origin_nm, height)
	else:
		target = frame["position"]
		length = frame["length"]
		heading = frame["heading"]
		domain = frame["domain"]
	var p: Dictionary = PRESETS[preset]
	cam.fov = p["fov"]
	var rate := 1.0 - exp(-CAMERA_RATE * delta)
	var want_az: float = heading + p["rel_az"] + _az_offset
	var want_pitch: float = _pitch_user if not is_nan(_pitch_user) else p["pitch"]
	var want_dist := clampf(length * p["dist"] * _dist_factor, maxf(length * 0.8, 40.0), 80000.0)
	if not _cam_valid:
		_cam_az = want_az
		_cam_pitch = want_pitch
		_cam_dist = want_dist
		_cam_valid = true
	else:
		_cam_az += Geo.heading_delta(_cam_az, want_az) * rate
		_cam_pitch = lerpf(_cam_pitch, want_pitch, rate)
		_cam_dist = lerpf(_cam_dist, want_dist, rate)
	if preset == Preset.BRIDGE:
		var fwd := WorldPresentation.heading_vector(heading)
		var eye: Vector3
		if domain == "air":
			eye = target + fwd * length * 0.32 + Vector3(0.0, length * 0.08, 0.0)
		else:
			eye = target + fwd * length * 0.04 + Vector3(0.0, maxf(length * 0.12, 6.0) + 2.0, 0.0)
			eye.y = maxf(eye.y, MIN_CAMERA_HEIGHT_M + _scene.swell_at(eye) + 2.0)
		var look_dir := WorldPresentation.heading_vector(_cam_az)
		var tilt := deg_to_rad(clampf(_cam_pitch, -40.0, 40.0))
		look_dir = Vector3(look_dir.x * cos(tilt), sin(tilt), look_dir.z * cos(tilt))
		cam.look_at_from_position(eye, eye + look_dir * 100.0, Vector3.UP)
		return
	var az_dir := WorldPresentation.heading_vector(_cam_az)
	var pr := deg_to_rad(clampf(_cam_pitch, 2.0, 86.0))
	var eye := target + az_dir * cos(pr) * _cam_dist + Vector3(0.0, sin(pr) * _cam_dist, 0.0)
	eye.y = maxf(eye.y, MIN_CAMERA_HEIGHT_M + _scene.swell_at(eye))
	cam.look_at_from_position(eye, target, Vector3.UP)


# --- Input -------------------------------------------------------------------------------

## Left drag orbits, the wheel zooms, a double-click on one of ours selects it on the chart.
## Every mouse event is consumed here so nothing falls through to the plot underneath.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		match e.button_index:
			MOUSE_BUTTON_LEFT:
				if e.pressed:
					if e.double_click:
						_select_at(e.position)
					_dragging = true
				else:
					_dragging = false
			MOUSE_BUTTON_WHEEL_UP:
				if e.pressed:
					_zoom(0.85)
			MOUSE_BUTTON_WHEEL_DOWN:
				if e.pressed:
					_zoom(1.18)
		accept_event()
	elif event is InputEventMouseMotion:
		var m := event as InputEventMouseMotion
		if _dragging and (m.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_az_offset = wrapf(_az_offset - m.relative.x * 0.35, -180.0, 180.0)
			var current := _pitch_user if not is_nan(_pitch_user) else float(PRESETS[preset]["pitch"])
			var low := -40.0 if preset == Preset.BRIDGE else 2.0
			var high := 40.0 if preset == Preset.BRIDGE else 86.0
			_pitch_user = clampf(current + m.relative.y * 0.25, low, high)
		accept_event()
	elif event is InputEventMagnifyGesture:
		_zoom(1.0 / maxf((event as InputEventMagnifyGesture).factor, 0.01))
		accept_event()
	elif event is InputEventPanGesture:
		_zoom(1.0 + (event as InputEventPanGesture).delta.y * 0.02)
		accept_event()


func _zoom(factor: float) -> void:
	_dist_factor = clampf(_dist_factor * factor, 0.2, 30.0)


func _select_at(screen: Vector2) -> void:
	var u := _scene.pick_own_unit(screen)
	if u != null and map != null:
		map.select_units([u])


# --- HUD ---------------------------------------------------------------------------------

func _draw_hud() -> void:
	var h := _hud
	var full := mode == Mode.FULL
	_label_rects.clear()
	if _controls != null:
		_label_rects.append(_controls.get_rect().grow(6.0))
	_draw_scrim(h, Rect2(0.0, 0.0, size.x, 84.0 if full else 52.0), true)
	_draw_scrim(h, Rect2(0.0, size.y - (30.0 if full else 22.0), size.x, 30.0 if full else 22.0), false)
	if not full:
		h.draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2.ONE), UITheme.COL_BORDER, false, 1.0)
	_draw_labels(h, full)
	var eyebrow := UITheme.eyebrow_font()
	var heading_font := UITheme.heading_font()
	var body := UITheme.body_font()
	var x := HUD_PAD
	var y := HUD_PAD + 6.0
	var controls_w := 0.0 if full or _controls == null else _controls.size.x + 16.0
	var max_w := maxf(size.x - HUD_PAD * 2.0 - controls_w, 40.0)
	h.draw_string(eyebrow, Vector2(x, y), "WORLD VIEW  ·  CAMERA %s" % PRESET_NAMES[preset], HORIZONTAL_ALIGNMENT_LEFT, int(max_w), 10, UITheme.COL_DIM)
	var focus_name: String = _focus.get("name", "NO FOCUS")
	h.draw_string(heading_font, Vector2(x, y + (26.0 if full else 21.0)), focus_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, int(max_w), 24 if full else 17, Color.WHITE)
	h.draw_string(body, Vector2(x, y + (46.0 if full else 37.0)), _focus_detail(), HORIZONTAL_ALIGNMENT_LEFT, int(max_w), 12 if full else 11, UITheme.COL_DIM)
	if full:
		var conditions := "%s  ·  sun %s  ·  visibility %d nm  ·  sea state %d, %s" % [SimClock.datetime_string(), _sun_text(), int(WorldPresentation.visibility_nm(Detection.environment)), Detection.sea_state, Detection.sea_state_name()]
		h.draw_string(body, Vector2(x, y + 64.0), conditions, HORIZONTAL_ALIGNMENT_LEFT, int(max_w), 11, UITheme.COL_DIM)
	var fy := size.y - 9.0
	h.draw_string(eyebrow, Vector2(x, fy), FOOTER_TEXT, HORIZONTAL_ALIGNMENT_LEFT, int(size.x * 0.62 if full else size.x - HUD_PAD * 2.0), 10 if full else 9, UITheme.COL_DIM)
	if full:
		var counts := "%d own  ·  %d sighted  ·  %d on the plot  ·  %d rounds in the air" % [_shown["own"], _shown["visual"], _shown["plotted"], _shown["weapon"]]
		var w := body.get_string_size(counts, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		h.draw_string(body, Vector2(size.x - HUD_PAD - w, fy), counts, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.COL_DIM)


## A soft dark band so the type reads over sky or glare.
func _draw_scrim(h: Control, rect: Rect2, from_top: bool) -> void:
	var steps := 8
	for i in steps:
		var f := float(i) / float(steps)
		var alpha := 0.5 * (1.0 - f) if from_top else 0.4 * f
		var band := Rect2(rect.position.x, rect.position.y + rect.size.y * f, rect.size.x, rect.size.y / float(steps) + 1.0)
		h.draw_rect(band, Color(0.02, 0.04, 0.06, alpha))


func _focus_detail() -> String:
	var unit: Unit = _focus.get("unit")
	if unit != null:
		return "%s  ·  %s" % [unit.spec.display_name, WorldPresentation.motion_text(unit.heading_deg, unit.speed_kn, WorldPresentation.height_of(unit), WorldPresentation.domain_of(unit))]
	var track: Track = _focus.get("track")
	if track != null:
		var motion := "course %03d°  ·  %d kn" % [int(track.course_deg), int(track.speed_kn)] if track.has_kinematics else "no course solution yet"
		return "%s  ·  %s  ·  %s" % [track.description(), track.identity, motion]
	return "select a unit or hook a contact"


func _sun_text() -> String:
	var el := _sun_angles.x
	if absf(el) < 0.5:
		return "on the horizon"
	return "%d° %s the horizon" % [int(roundf(absf(el))), "above" if el > 0.0 else "below"]


func _draw_labels(h: Control, full: bool) -> void:
	var cam := _scene.camera
	if cam == null:
		return
	var limit := LABEL_LIMIT_FULL if full else LABEL_LIMIT_INSET
	var sorted := _anchors.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["key"] == _focus_key:
			return true
		if b["key"] == _focus_key:
			return false
		return float(a["distance_m"]) < float(b["distance_m"]))
	var top := 84.0 if full else 52.0
	var safe := Rect2(Vector2(HUD_PAD, top), Vector2(size.x - HUD_PAD * 2.0, size.y - top - (34.0 if full else 26.0)))
	var placed := 0
	for a: Dictionary in sorted:
		if placed >= limit:
			break
		var focus: bool = a["key"] == _focus_key
		if float(a["distance_m"]) > LABEL_RANGE_M and not focus:
			continue
		var world: Vector3 = a["world"]
		if cam.is_position_behind(world):
			continue
		var sp := cam.unproject_position(world)
		if not safe.grow(40.0).has_point(sp):
			continue
		var sub: String = a["sublabel"] if (full or focus) else ""
		if _place_label(h, sp, a["label"], a["color"], focus, sub, safe, full):
			placed += 1


## The chart's label chip, placed clear of the others and of the HUD controls.
func _place_label(h: Control, sp: Vector2, text: String, color: Color, important: bool, sub: String, safe: Rect2, full: bool) -> bool:
	var font := UITheme.body_font()
	var main_size := 12 if full else 11
	var sub_size := 10 if full else 9
	var w1 := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, main_size).x
	var w2 := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size).x if sub != "" else 0.0
	var width := minf(maxf(w1, w2) + 18.0, 260.0)
	var height := 21.0 if sub == "" else 33.0
	for attempt in 12:
		var row := int((attempt + 1) / 2.0)
		var offset := Vector2(18.0, -12.0 + row * (height + 4.0) * (1 if attempt % 2 == 0 else -1))
		var r := Rect2(sp + offset, Vector2(width, height))
		if r.end.x > safe.end.x:
			r.position.x = sp.x - width - 18.0
		if r.position.y < safe.position.y or r.end.y > safe.end.y or r.position.x < safe.position.x:
			continue
		var overlaps := false
		for used in _label_rects:
			if used.grow(3.0).intersects(r):
				overlaps = true
				break
		if overlaps:
			continue
		_label_rects.append(r)
		h.draw_line(sp, Vector2(r.position.x if r.position.x > sp.x else r.end.x, r.get_center().y), Color(color, 0.35), 1.0, true)
		h.draw_circle(sp, 2.0, Color(color, 0.8))
		h.draw_rect(r, TacticalMap.COL_LABEL_BG)
		h.draw_rect(Rect2(r.position, Vector2(2.0, height)), Color(color, 0.9))
		if important:
			h.draw_rect(r, Color(color, 0.55), false, 1.0)
		h.draw_string(font, r.position + Vector2(9.0, 15.0), text, HORIZONTAL_ALIGNMENT_LEFT, int(width - 12.0), main_size, color)
		if sub != "":
			h.draw_string(font, r.position + Vector2(9.0, 28.0), sub, HORIZONTAL_ALIGNMENT_LEFT, int(width - 12.0), sub_size, Color(color, 0.72))
		return true
	return false
