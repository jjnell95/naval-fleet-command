class_name WorldView
extends Control
## The command screen's 3D pane: a battle camera rendered from the simulation's state into a
## SubViewport. It shows exactly what WorldPresentation allows, which is what a lookout could see
## and what the plot holds, and nothing else.
##
## The pane fills whatever rect its parent gives it (the bottom-centre slot, the big top slot when
## the screen is swapped, or the whole window). The camera mode stays in red at the top left;
## compact mouse controls and a subject caption keep every camera discoverable. It renders only while it is
## visible in the tree and not suspended behind a modal screen. Mouse input inside it never
## reaches anything underneath; the keyboard stays with Main.

signal camera_mode_changed(mode: int)
signal swap_requested
signal fullscreen_requested

const CAM_TETHER := WorldCamera.TETHER
const CAM_FLYBY := WorldCamera.FLYBY
const CAM_ACTION := WorldCamera.ACTION
const CAM_DETACHED := WorldCamera.DETACHED
const LABEL_COLOR := UITheme.CDS_CAMERA
const LABEL_SIZE := 14
const LABEL_PAD := Vector2(7.0, 5.0)
const MIN_CAMERA_HEIGHT_M := 2.5
## Sun shadows cost a second pass over every model. The always-on pane under the chart is too small
## for them to show; full screen, or swapped with the chart, they are worth it.
const SHADOW_MIN_WIDTH_PX := 900.0
const DEFAULT_START_TIME := "1990-03-21T11:00:00"

var map: TacticalMap
var simulation: Simulation
## The camera: modes, orbit and zoom, remembered for the session.
var rig := WorldCamera.new()
## The font for the camera label; the screen shell may hand in its own data face.
var label_font: Font
## True while a modal screen covers the pane: nothing renders, nothing is processed.
var suspended := false
## Dev only: seconds added to the clock for the sun, to look at dusk or night on demand.
var sun_offset_s := 0.0

var _container: SubViewportContainer
var _viewport: SubViewport
var _scene: WorldScene
var _hud: Control
var _camera_select: OptionButton
var _swap_button: Button
var _full_button: Button
var _subject_label: Label
var _rain: ColorRect
var _rain_material: ShaderMaterial
var _origin_nm := Vector2.ZERO
var _focus: Dictionary = {}
var _focus_key := ""
## What the hook held on the last frame, to tell a new hook from one that only lost something.
var _hook_units: Array[Unit] = []
var _hook_track: Track = null
var _hook_inspection: Track = null
var _dragging := false
var _entries: Array = []
## The simulation only moves on its ticks, so the entries (what may be drawn, and where) are rebuilt
## when it has ticked or the hook has changed, not every frame; in between the scene carries things
## on along their courses itself.
var _entries_time := -1.0
var _entries_reference: Unit = null
var _entries_weapon_revision := -1
var _entries_threat_revision := -1
var _entries_datalink := false
var _sun_unix := -INF
var _sun_origin := Vector2(INF, INF)
var _sun_anchor := Vector2(INF, INF)
var _default_unix := 0
var _frame_lookup: Callable
var _chart_generation := -1


func _ready() -> void:
	name = "WorldView"
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.gui_disable_input = true
	_container.add_child(_viewport)
	_scene = WorldScene.new()
	_viewport.add_child(_scene)
	_scene.build()
	_frame_lookup = _scene.focus_frame
	_rain = ColorRect.new()
	_rain.name = "Rain"
	_rain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rain_material = ShaderMaterial.new()
	_rain_material.shader = load("res://scripts/ui/world_rain.gdshader")
	_rain.material = _rain_material
	_rain.hide()
	add_child(_rain)
	_hud = Control.new()
	_hud.name = "Hud"
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	add_child(_hud)
	_build_camera_controls()
	visibility_changed.connect(_sync_visibility)
	resized.connect(_sync_visibility)
	_sync_visibility()


# --- Public API ----------------------------------------------------------------------------

## Tether, Fly-by, Action or Detached (CAM_* constants).
func set_camera_mode(next: int) -> void:
	var before := rig.mode
	rig.set_mode(next)
	if rig.mode != before:
		if _camera_select != null:
			_camera_select.select(rig.mode)
		camera_mode_changed.emit(rig.mode)
		if _hud != null:
			_hud.queue_redraw()


## Tether, Fly-by, Action, Detached, and round again.
func cycle_camera_mode() -> void:
	set_camera_mode((rig.mode + 1) % WorldCamera.MODE_NAMES.size())


func camera_mode() -> int:
	return rig.mode


func camera_mode_name() -> String:
	return rig.mode_name()


## Stops rendering while a modal screen covers the pane, and starts it again after.
func set_suspended(on: bool) -> void:
	suspended = on
	_sync_visibility()


## Turns the tether round the subject: `az_deg` from the bow, clockwise; pitch above the water;
## zoom as a multiple of the default range.
func set_orbit(az_deg: float, pitch_deg := NAN, zoom_factor := NAN) -> void:
	rig.orbit_az = wrapf(az_deg, 0.0, 360.0)
	if not is_nan(pitch_deg):
		rig.orbit_pitch = clampf(pitch_deg, WorldCamera.MIN_PITCH, WorldCamera.MAX_PITCH)
	if not is_nan(zoom_factor):
		rig.zoom = clampf(zoom_factor, WorldCamera.MIN_ZOOM, WorldCamera.MAX_ZOOM)
	rig.cut()


## The hook changed: if that changes the subject, the next frame cuts to it instead of sweeping.
## When the subject is the one already shown (a contact hooked beside the ship, the same ship
## hooked again, a lost ship still being watched as it goes down) nothing happens, so a detached
## eye stays where it is and a fly-by keeps its station. The tether orbit and zoom are the
## player's and are always kept. Main calls it whenever the selection changes.
func refocus() -> void:
	if map == null or simulation == null:
		rig.cut()
		return
	var um := simulation.unit_manager
	var own_units: Array = um.get_faction_units(simulation.player_faction) if um != null else []
	if String(_pick_focus(own_units, _hooked_anew()).get("key", "")) != String(_focus.get("key", "")):
		rig.cut()


## A simulation event at a chart position, beside the chart's own `add_effect`. `height_m`
## places an airburst; leave it negative for something at the surface. `target` is the unit a
## hit, miss or kill happened to; left out, it is taken to be the unit standing at `pos`, which is
## where Main reports those events. Only events the player could witness are drawn, and one known
## only from the plot is drawn where the plot has it; launches are drawn from the rounds
## themselves as they appear. Action cuts only to events inside the view's range, where what they
## happened to can be drawn around them.
func add_effect(pos: Vector2, kind: String, own := false, height_m := -1.0, target: Unit = null) -> void:
	if _scene == null or not _live() or simulation == null:
		return
	if kind == "launch" or kind == "refused":
		return
	var um := simulation.unit_manager
	var tm := simulation.track_manager
	var own_units: Array = um.get_faction_units(simulation.player_faction) if um != null else []
	var tracks: Array = tm.get_tracks(simulation.player_faction) if tm != null else []
	var at := pos
	if not own:
		if target == null and kind in ["hit", "miss", "destroyed"]:
			target = _unit_at(pos)
		at = WorldPresentation.witness_point(pos, own_units, tracks, Detection.environment, target)
	if at == Vector2.INF:
		return
	var h := _scene.add_effect(at, kind, own, height_m)
	if kind in ["hit", "destroyed", "intercept"] and at.distance_to(_origin_nm) <= WorldPresentation.MAX_RANGE_NM:
		rig.notify(kind, Vector3(at.x, at.y, h))


## The unit an event at `pos` happened to, when the caller gave only the place: a unit standing
## exactly there, dead or alive, but not an airframe parked on a deck.
func _unit_at(pos: Vector2) -> Unit:
	var um := simulation.unit_manager
	if um == null:
		return null
	for u: Unit in um.units:
		if u.alive and not u.is_engageable():
			continue
		if u.position.is_equal_approx(pos):
			return u
	return null


## A new scenario: forget wakes, smoke, sinking hulls and the camera's memory of the last one.
func reset_presentation() -> void:
	if _scene != null:
		_scene.reset()
	_focus = {}
	_focus_key = ""
	_entries = []
	_entries_time = -1.0
	_entries_reference = null
	_entries_weapon_revision = -1
	_entries_threat_revision = -1
	_sun_unix = -INF
	_hook_units.clear()
	_hook_track = null
	_hook_inspection = null
	_chart_generation = -1
	rig.reset()


# --- Visibility ----------------------------------------------------------------------------

func _live() -> bool:
	return is_visible_in_tree() and not suspended and size.x >= 2.0 and size.y >= 2.0


func _sync_visibility() -> void:
	var live := _live()
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if live else SubViewport.UPDATE_DISABLED
	set_process(live)
	if _scene != null:
		_scene.set_running(live)
		_scene.set_shadows(live and size.x >= SHADOW_MIN_WIDTH_PX)
	if not live:
		_dragging = false
	if _hud != null:
		_hud.queue_redraw()
	if _swap_button != null:
		_swap_button.visible = size.x >= 350.0


# --- Per frame -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if map == null or simulation == null or not _live():
		return
	var t0 := Time.get_ticks_usec()
	if _dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_dragging = false
	var player := simulation.player_faction
	var um := simulation.unit_manager
	var own_units: Array = um.get_faction_units(player) if um != null else []
	var hooked_anew := _hooked_anew()
	var focus := _pick_focus(own_units, hooked_anew)
	_hook_units = map.selected.duplicate()
	_hook_track = map.selected_track
	_hook_inspection = map.inspection_track()
	var focus_changed := String(focus.get("key", "")) != String(_focus.get("key", ""))
	if focus_changed:
		rig.cut()
	_focus = focus
	_origin_nm = _focus.get("position", _origin_nm)
	_scene.origin_nm = _origin_nm
	_scene.sim_now = SimClock.sim_time
	_scene.paused = SimClock.paused
	_scene.time_rate = SimClock.multiplier()
	if _chart_generation != Terrain.generation:
		_chart_generation = Terrain.generation
		_scene.set_chart(_charted_rect())
	_scene.lead_s = 0.0 if SimClock.paused else clampf(SimClock._accum, 0.0, SimClock.TICK_DT)
	var env := Detection.environment
	_scene.set_weather(Detection.sea_state, WorldPresentation.visibility_nm(env), env)
	var chart: Dictionary = simulation.scenario.get("map", {})
	var unix := float(SimClock.start_unix_time if SimClock.start_unix_time > 0 else _default_unix) + SimClock.sim_time + sun_offset_s
	_update_sun(unix, chart)
	var reference := map.reference_unit()
	var weapon_revision := simulation.weapon_manager.revision if simulation.weapon_manager != null else -1
	var threat_revision := simulation.threat_manager.revision if simulation.threat_manager != null else -1
	var datalink := reference != null and reference.datalink_connected()
	if SimClock.sim_time != _entries_time or reference != _entries_reference or weapon_revision != _entries_weapon_revision or threat_revision != _entries_threat_revision or datalink != _entries_datalink or focus_changed or hooked_anew or Debug.enabled:
		_entries_time = SimClock.sim_time
		_entries_reference = reference
		_entries_weapon_revision = weapon_revision
		_entries_threat_revision = threat_revision
		_entries_datalink = datalink
		var entries: Array = WorldPresentation.unit_entries(um, simulation.track_manager, player, env, simulation.track_manager.neutral_factions)
		entries.append_array(WorldPresentation.weapon_entries(simulation.weapon_manager, simulation.threat_manager, player, reference))
		entries.append_array(WorldPresentation.buoy_entries(simulation.aviation_manager, player, SimClock.sim_time))
		# A subject going down keeps the camera until it has gone, or until something new is hooked.
		if hooked_anew or not _scene.is_dying(_focus_key):
			_focus_key = WorldPresentation.resolve_focus_key(entries, _focus)
		_entries = WorldPresentation.cull(entries, _origin_nm, _focus_key)
	_scene.update(delta, _entries, _focus_key)
	for e: Dictionary in _scene.take_events():
		rig.notify(e["kind"], e["at"], e.get("key", ""))
	_update_camera(delta)
	_update_subject_label()
	_rain.visible = _scene.rain_intensity > 0.0 and _scene.camera.position.y < _scene.cloud_base_m
	if _rain.visible:
		_rain_material.set_shader_parameter("weather_time", _scene.weather_time)
		_rain_material.set_shader_parameter("intensity", _scene.rain_intensity)
		_rain_material.set_shader_parameter("daylight", _scene.daylight)
		_rain_material.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	Debug.time_add("world", Time.get_ticks_usec() - t0)


## The sun and observer position move on simulation ticks. A paused pane only needs another
## solar calculation when its focus, chart anchor, or the developer's time offset changes.
func _update_sun(unix: float, chart: Dictionary) -> void:
	var anchor := Vector2(float(chart.get("anchor_lat", 60.0)), float(chart.get("anchor_lon", 0.0)))
	if unix == _sun_unix and _origin_nm == _sun_origin and anchor == _sun_anchor and not _scene.sunlight_needs_update():
		return
	_sun_unix = unix
	_sun_origin = _origin_nm
	_sun_anchor = anchor
	var latlon := WorldPresentation.latlon_of(_origin_nm, chart)
	var sun := WorldPresentation.sun_angles(unix, latlon.x, latlon.y)
	_scene.set_time_of_day(WorldPresentation.sun_direction_from_angles(sun), sun.x)


## The subject for this frame: what is hooked (WorldPresentation.choose_focus), except that a
## subject that has just been lost is watched until it has gone down, unless the player has
## hooked something new since.
func _pick_focus(own_units: Array, hooked_anew: bool) -> Dictionary:
	var inspected := map.inspection_track()
	var focus := WorldPresentation.choose_focus([] if inspected != null else map.selected, inspected if inspected != null else map.selected_track, own_units)
	var lost: Unit = _focus.get("unit")
	if not hooked_anew and lost != null and not lost.alive and not lost.departed and String(focus.get("key", "")) != String(_focus.get("key", "")) and _scene.has_record(_focus_key):
		return _focus
	return focus


## True when the hook holds a unit or a contact it did not hold on the last frame: the player has
## hooked something. A hook that only lost something (a ship sunk and pruned from it, a contact
## dropped) is not a new one.
func _hooked_anew() -> bool:
	if map.inspection_track() != _hook_inspection:
		return true
	if map.selected_track != null and map.selected_track != _hook_track:
		return true
	for u: Unit in map.selected:
		if not _hook_units.has(u):
			return true
	return false


func _update_camera(delta: float) -> void:
	rig.viewport_aspect = size.x / maxf(size.y, 1.0)
	var subject := _scene.focus_frame(_focus_key)
	if subject.is_empty() and not _focus.is_empty():
		subject = _point_frame(_focus)
	var shot := rig.update(delta, _origin_nm, subject, _frame_lookup)
	if shot.is_empty():
		return
	var cam := _scene.camera
	cam.fov = shot["fov"]
	var eye: Vector3 = shot["eye"]
	eye.y = maxf(eye.y, MIN_CAMERA_HEIGHT_M + _scene.swell_at(eye))
	eye.y = maxf(eye.y, _scene.ground_at(eye) + MIN_CAMERA_HEIGHT_M * 4.0)
	var look: Vector3 = shot["look"]
	if eye.distance_squared_to(look) < 1.0:
		look = eye + Vector3(0.0, 0.0, -1.0)
	var up := Vector3.UP if absf((look - eye).normalized().y) < 0.995 else Vector3.FORWARD
	cam.look_at_from_position(eye, look, up)
	_scene.camera_moved()


## The chart box the scenario's coastline polygons cover, as the chart floor reads it; empty
## when they cover everything.
func _charted_rect() -> Rect2:
	var box = simulation.scenario.get("map", {}).get("charted_nm", [])
	if typeof(box) != TYPE_ARRAY or box.size() != 4:
		return Rect2()
	return Rect2(float(box[0]), float(box[1]), float(box[2]) - float(box[0]), float(box[3]) - float(box[1]))


## A focus with no entity on the view (the force centre, or a contact the camera has not built
## yet): a point at the water with a nominal size and course.
func _point_frame(focus: Dictionary) -> Dictionary:
	var unit: Unit = focus.get("unit")
	var height := 0.0
	var length := float(focus.get("length_m", 150.0))
	var heading := float(focus.get("heading_deg", 0.0))
	var domain := "surface"
	if unit != null:
		height = WorldPresentation.height_of(unit)
		length = WorldPresentation.length_of(unit.spec)
		heading = unit.heading_deg
		domain = WorldPresentation.domain_of(unit)
	return {"position": WorldPresentation.to_world(focus.get("position", _origin_nm), _origin_nm, height), "length": length, "heading": heading, "domain": domain, "height": 0.0, "speed_mps": 0.0}


# --- Input ---------------------------------------------------------------------------------

## Left drag orbits the tether, the wheel zooms it, a double-click on one of ours hooks it on the
## chart. Every mouse event is consumed here so nothing falls through to what lies underneath.
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
					rig.zoom_by(0.87)
			MOUSE_BUTTON_WHEEL_DOWN:
				if e.pressed:
					rig.zoom_by(1.15)
		accept_event()
	elif event is InputEventMouseMotion:
		var m := event as InputEventMouseMotion
		if _dragging and (m.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			rig.orbit(m.relative.x, m.relative.y)
		accept_event()
	elif event is InputEventMagnifyGesture:
		rig.zoom_by(1.0 / maxf((event as InputEventMagnifyGesture).factor, 0.01))
		accept_event()
	elif event is InputEventPanGesture:
		rig.zoom_by(1.0 + (event as InputEventPanGesture).delta.y * 0.02)
		accept_event()


func _select_at(screen: Vector2) -> void:
	var u := _scene.pick_own_unit(screen)
	if u != null and map != null:
		map.select_units([u])


# --- HUD -----------------------------------------------------------------------------------

## The four camera modes and pane controls are available by mouse where the view is displayed.
## The shell owns layout; these signals keep it out of the rendering/presentation boundary.
func _build_camera_controls() -> void:
	var row := HBoxContainer.new()
	row.name = "CameraControls"
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.offset_left = -244.0
	row.offset_top = 5.0
	row.offset_right = -6.0
	row.offset_bottom = 30.0
	row.add_theme_constant_override("separation", 3)
	add_child(row)
	_camera_select = OptionButton.new()
	_camera_select.custom_minimum_size = Vector2(96, 25)
	_camera_select.add_theme_font_size_override("font_size", 12)
	_camera_select.focus_mode = Control.FOCUS_NONE
	_camera_select.tooltip_text = "Choose camera · drag to orbit · wheel to zoom"
	for mode in WorldCamera.MODE_NAMES:
		_camera_select.add_item(mode)
	_camera_select.item_selected.connect(set_camera_mode)
	row.add_child(_camera_select)
	_swap_button = _view_button("Swap", "Swap the chart and 3D view", func() -> void: swap_requested.emit())
	row.add_child(_swap_button)
	_full_button = _view_button("Full", "Expand the 3D view to the whole screen", func() -> void: fullscreen_requested.emit())
	row.add_child(_full_button)
	_subject_label = Label.new()
	_subject_label.name = "CameraSubject"
	_subject_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_subject_label.offset_left = 7.0
	_subject_label.offset_right = -7.0
	_subject_label.offset_top = 33.0
	_subject_label.offset_bottom = 51.0
	_subject_label.clip_text = true
	_subject_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subject_label.add_theme_font_override("font", _default_label_font())
	_subject_label.add_theme_font_size_override("font_size", 12)
	_subject_label.add_theme_color_override("font_color", Color("f0f3f7"))
	_subject_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_subject_label.add_theme_constant_override("shadow_offset_x", 1)
	_subject_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_subject_label)


func _update_subject_label() -> void:
	var caption := String(_focus.get("name", ""))
	var action := rig.action()
	if rig.mode == WorldCamera.ACTION and not action.is_empty():
		var names := {"launch": "Weapon launch", "air_launch": "Aircraft launch", "recovery": "Aircraft recovery", "hit": "Weapon impact", "destroyed": "Unit lost", "intercept": "Intercept"}
		caption = names.get(String(action.get("kind", "")), "Action")
		for e: Dictionary in _entries:
			if e["key"] == action.get("key", ""):
				caption += " · " + String(e.get("label", ""))
				break
	elif _focus.get("track") != null:
		caption += " · " + String(_focus.get("detail", ""))
		if _focus_key.begins_with("t:"):
			caption = "SENSOR ESTIMATE · " + caption
	_subject_label.text = caption


func _view_button(text: String, hint: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = hint
	b.custom_minimum_size = Vector2(54, 25)
	b.add_theme_font_size_override("font_size", 12)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	return b


func set_layout_state(swapped: bool, full: bool) -> void:
	if _swap_button == null:
		return
	_swap_button.disabled = full
	_swap_button.text = "Chart" if swapped else "Swap"
	_full_button.text = "Back" if full else "Full"
	_full_button.tooltip_text = "Return to the command screen" if full else "Expand the 3D view to the whole screen"

## The camera mode, red, top left, no box.
func _draw_hud() -> void:
	var font := label_font if label_font != null else _default_label_font()
	var ascent := font.get_ascent(LABEL_SIZE)
	_hud.draw_string(font, LABEL_PAD + Vector2(0.0, ascent), rig.mode_name(), HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, LABEL_COLOR)


## The camera label's face when the shell hands in none: the theme's bold data sans.
static func _default_label_font() -> Font:
	return UITheme.data_font()
