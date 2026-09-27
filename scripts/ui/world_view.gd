class_name WorldView
extends Control
## The command screen's 3D pane: a battle camera rendered from the simulation's state into a
## SubViewport. It shows exactly what WorldPresentation allows, which is what a lookout could see
## and what the plot holds, and nothing else.
##
## The pane fills whatever rect its parent gives it (the bottom-centre slot, the big top slot when
## the screen is swapped, or the whole window) and draws no chrome of its own beyond the camera
## mode, in red at the top left: Tether, Fly-by, Action or Detached. It renders only while it is
## visible in the tree and not suspended behind a modal screen. Mouse input inside it never
## reaches anything underneath; the keyboard stays with Main.

## Legacy visibility modes, kept while Main still cycles them on T: HIDDEN hides the pane, INSET
## and FULL both show it filling its parent.
enum Mode { HIDDEN, INSET, FULL }

signal mode_changed(mode: int)
signal camera_mode_changed(mode: int)

const CAM_TETHER := WorldCamera.TETHER
const CAM_FLYBY := WorldCamera.FLYBY
const CAM_ACTION := WorldCamera.ACTION
const CAM_DETACHED := WorldCamera.DETACHED
const LABEL_COLOR := UITheme.CDS_CAMERA
const LABEL_SIZE := 14
const LABEL_PAD := Vector2(7.0, 5.0)
const MIN_CAMERA_HEIGHT_M := 2.5
const DEFAULT_START_TIME := "1990-03-21T11:00:00"
## Old camera preset names still accepted by set_preset_by_name, as tether framings.
const LEGACY_PRESETS := {
	"BRIDGE": {"az": 180.0, "pitch": 4.0, "zoom": 0.55},
	"ORBIT": {"az": WorldCamera.DEFAULT_AZ, "pitch": WorldCamera.DEFAULT_PITCH, "zoom": 1.0},
	"OVERHEAD": {"az": 180.0, "pitch": 78.0, "zoom": 2.0},
	"CHASE": {"az": 180.0, "pitch": 9.0, "zoom": 1.2},
}

var map: TacticalMap
var simulation: Simulation
var mode: Mode = Mode.HIDDEN
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
var _origin_nm := Vector2.ZERO
var _focus: Dictionary = {}
var _focus_key := ""
## What the hook held on the last frame, to tell a new hook from one that only lost something.
var _hook_units: Array[Unit] = []
var _hook_track: Track = null
var _dragging := false
var _entries: Array = []
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
	visible = mode != Mode.HIDDEN
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
	_hud = Control.new()
	_hud.name = "Hud"
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	add_child(_hud)
	visibility_changed.connect(_sync_visibility)
	resized.connect(_sync_visibility)
	_sync_visibility()


# --- Public API ----------------------------------------------------------------------------

## Tether, Fly-by, Action or Detached (CAM_* constants).
func set_camera_mode(next: int) -> void:
	var before := rig.mode
	rig.set_mode(next)
	if rig.mode != before:
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


## Legacy: shows or hides the pane. INSET and FULL both fill the parent.
func set_mode(next: Mode) -> void:
	if next == mode:
		return
	mode = next
	visible = mode != Mode.HIDDEN
	_sync_visibility()
	if visible:
		refocus()
	mode_changed.emit(mode)


## Legacy: HIDDEN → INSET → FULL → HIDDEN.
func cycle_mode() -> void:
	set_mode(((mode + 1) % 3) as Mode)


func mode_name() -> String:
	return ["hidden", "inset", "full"][mode]


## A camera mode by name (tether, fly-by, action, detached), or one of the old presets (bridge,
## orbit, overhead, chase), which become tether framings.
func set_preset_by_name(preset_name: String) -> void:
	var wanted := preset_name.to_upper().replace("-", "").replace("_", "")
	for i in WorldCamera.MODE_NAMES.size():
		if WorldCamera.MODE_NAMES[i].to_upper().replace("-", "") == wanted:
			set_camera_mode(i)
			return
	if LEGACY_PRESETS.has(wanted):
		var p: Dictionary = LEGACY_PRESETS[wanted]
		set_camera_mode(CAM_TETHER)
		set_orbit(p["az"], p["pitch"], p["zoom"])


## Turns the tether round the subject: `az_deg` from the bow, clockwise; pitch above the water;
## zoom as a multiple of the default range.
func set_orbit(az_deg: float, pitch_deg := NAN, zoom_factor := NAN) -> void:
	rig.orbit_az = wrapf(az_deg, 0.0, 360.0)
	if not is_nan(pitch_deg):
		rig.orbit_pitch = clampf(pitch_deg, WorldCamera.MIN_PITCH, WorldCamera.MAX_PITCH)
	if not is_nan(zoom_factor):
		rig.zoom = clampf(zoom_factor, WorldCamera.MIN_ZOOM, WorldCamera.MAX_ZOOM)
	rig.cut()


## The subject changed: the next frame cuts to it instead of sweeping. The tether orbit and zoom
## are the player's and are kept. Main calls it whenever the selection changes.
func refocus() -> void:
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
	_hook_units.clear()
	_hook_track = null
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
	if not live:
		_dragging = false
	if _hud != null:
		_hud.queue_redraw()


# --- Per frame -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if map == null or simulation == null or not _live():
		return
	if _dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_dragging = false
	var player := simulation.player_faction
	var um := simulation.unit_manager
	var own_units: Array = um.get_faction_units(player) if um != null else []
	var hooked_anew := _hooked_anew()
	var focus := _pick_focus(own_units, hooked_anew)
	_hook_units = map.selected.duplicate()
	_hook_track = map.selected_track
	if String(focus.get("key", "")) != String(_focus.get("key", "")):
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
	var latlon := WorldPresentation.latlon_of(_origin_nm, chart)
	var unix := float(SimClock.start_unix_time if SimClock.start_unix_time > 0 else _default_unix) + SimClock.sim_time + sun_offset_s
	var sun := WorldPresentation.sun_angles(unix, latlon.x, latlon.y)
	_scene.set_time_of_day(WorldPresentation.sun_direction(unix, latlon.x, latlon.y), sun.x)
	var entries: Array = WorldPresentation.unit_entries(um, simulation.track_manager, player, env, simulation.track_manager.neutral_factions)
	entries.append_array(WorldPresentation.weapon_entries(simulation.weapon_manager, simulation.threat_manager, player, map.reference_unit()))
	entries.append_array(WorldPresentation.buoy_entries(simulation.aviation_manager, player, SimClock.sim_time))
	# A subject going down keeps the camera until it has gone, or until something new is hooked.
	if hooked_anew or not _scene.is_dying(_focus_key):
		_focus_key = WorldPresentation.resolve_focus_key(entries, _focus)
	_entries = WorldPresentation.cull(entries, _origin_nm, _focus_key)
	_scene.update(delta, _entries, _focus_key)
	for e: Dictionary in _scene.take_events():
		rig.notify(e["kind"], e["at"], e.get("key", ""))
	_update_camera(delta)


## The subject for this frame: what is hooked (WorldPresentation.choose_focus), except that a
## subject that has just been lost is watched until it has gone down, unless the player has
## hooked something new since.
func _pick_focus(own_units: Array, hooked_anew: bool) -> Dictionary:
	var focus := WorldPresentation.choose_focus(map.selected, map.selected_track, own_units)
	var lost: Unit = _focus.get("unit")
	if not hooked_anew and lost != null and not lost.alive and not lost.departed and String(focus.get("key", "")) != String(_focus.get("key", "")) and _scene.has_record(_focus_key):
		return _focus
	return focus


## True when the hook holds a unit or a contact it did not hold on the last frame: the player has
## hooked something. A hook that only lost something (a ship sunk and pruned from it, a contact
## dropped) is not a new one.
func _hooked_anew() -> bool:
	if map.selected_track != null and map.selected_track != _hook_track:
		return true
	for u: Unit in map.selected:
		if not _hook_units.has(u):
			return true
	return false


func _update_camera(delta: float) -> void:
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

## The camera mode, red, top left, no box.
func _draw_hud() -> void:
	var font := label_font if label_font != null else _default_label_font()
	var ascent := font.get_ascent(LABEL_SIZE)
	_hud.draw_string(font, LABEL_PAD + Vector2(0.0, ascent), rig.mode_name(), HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, LABEL_COLOR)


## The camera label's face when the shell hands in none: the theme's bold data sans.
static func _default_label_font() -> Font:
	return UITheme.data_font()
