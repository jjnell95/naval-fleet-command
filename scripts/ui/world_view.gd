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
## The tether's pointer to the Action camera: how long the caption names an event out of frame,
## how far off an event in the frame still counts as out of it, and which events are worth it.
const HINT_S := 3.0
const HINT_FRAME_M := 12000.0
const HINT_KINDS: Array[String] = ["hit", "destroyed", "intercept", "inbound", "launch"]
const HINT_SUFFIX := " · F12 to watch"
## A jump of the floating origin longer than this is the view moving, not its subject.
const SETTLE_JUMP_NM := 5.0
## Inbound rounds already offered are remembered by key; past this many, the ones not seen for
## INBOUND_FORGET_S of simulation time are forgotten.
const INBOUND_MEMORY := 64
const INBOUND_FORGET_S := 120.0
## What the caption calls each kind of event Action shows or the tether points to.
const EVENT_CAPTIONS := {
	"launch": "Weapon launch", "air_launch": "Aircraft launch", "recovery": "Aircraft recovery",
	"hit": "Weapon impact", "destroyed": "Target destroyed", "intercept": "Intercept",
	"inbound": "Inbound weapon", "miss": "Weapon missed", "lost": "Round lost",
}

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
## While Action follows an entity, the floating origin is where the entries last put it (its
## simulation position, as the hook's is), so it moves on ticks and not every frame.
var _action_anchor := Vector2.ZERO
var _action_anchor_key := ""
var _entries_action_serial := -1
## Where the entries were last culled around, to tell a jump of the view from its subject moving.
var _cull_centre := Vector2.INF
## Rounds of another side already offered as inbound: key -> simulation time last seen.
var _inbound_seen: Dictionary = {}
## The tether's caption for an event out of frame ({kind, at, key, extra, priority, text}), how
## long it has left, and a count of them for the caption's change check.
var _hint: Dictionary = {}
var _hint_left := 0.0
var _hint_serial := 0
## What the caption was last built from; it is rebuilt only when one of these changes.
var _caption_mode := -1
var _caption_serial := -1
var _caption_hint_serial := -1
var _caption_hinting := false
var _caption_focus_key := ""
var _caption_name := ""
var _caption_detail := ""


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
		# "F12 to watch": the event the tether was pointing to is the first thing Action shows.
		if rig.mode == CAM_ACTION and _hint_left > 0.0 and not _hint.is_empty():
			rig.notify(_hint["kind"], _hint["at"], _hint["key"], _hint["extra"])
		_hint_left = 0.0
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
## themselves as they appear. Action may cut to a witnessed hit, kill or intercept anywhere on
## the plot: the view moves its origin there and draws what WorldPresentation allows around it.
## In the tether, one out of frame is named in the caption instead.
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
	if kind in WorldCamera.RESOLUTIONS:
		# `own` is Main's "it happened to one of ours" for a hit, miss or kill; for an intercept
		# it means our defence did it, which is no loss.
		var ours := own and kind != "intercept"
		# Drawn at a held plot, the event carries that plot's own uncertainty, never truth.
		var radius := 0.0
		if at != pos:
			for t: Track in tracks:
				if t.position == at:
					radius = maxf(WorldPresentation.WITNESS_PLOT_NM, t.position_error_nm * 1.5)
					break
		_witnessed(kind, Vector3(at.x, at.y, h), "", {"own": ours, "label": _event_label(ours, target), "radius": radius})


## A witnessed event the cameras may want: Action queues it; the tether names it in the caption
## when it is out of frame. Other cameras ignore it.
func _witnessed(kind: String, at: Vector3, key: String, extra: Dictionary) -> void:
	if rig.mode == CAM_ACTION:
		rig.notify(kind, at, key, extra)
	elif rig.mode == CAM_TETHER:
		_offer_hint(kind, at, key, extra)


## What the caption may call what an event happened to: one of ours by its callsign, anything
## else only by the track the plot holds on it (associated, as the chart does, by its unit).
func _event_label(own: bool, target: Unit) -> String:
	if target == null:
		return ""
	if own or target.faction == simulation.player_faction:
		return target.callsign
	var tm := simulation.track_manager
	var t: Track = tm.find_track(simulation.player_faction, target) if tm != null else null
	if t == null or t.status == Track.Status.LOST:
		return ""
	var number := MapSymbols.track_number(t.id)
	return "Track " + (number if number != "" else t.id)


## The tether's pointer to the Action camera: an event worth a cut that the frame does not show
## is named for HINT_S seconds. A lesser event does not replace a greater one still showing.
func _offer_hint(kind: String, at: Vector3, key: String, extra: Dictionary) -> void:
	if not HINT_KINDS.has(kind) or (kind == "launch" and not bool(extra.get("pursue", false))):
		return
	var own := bool(extra.get("own", false))
	var priority := WorldCamera.event_priority(kind, own)
	if _hint_left > 0.0 and priority < int(_hint.get("priority", -1)):
		return
	if _in_frame(at):
		return
	_hint = {"kind": kind, "at": at, "key": key, "extra": extra, "priority": priority, "text": event_caption(kind, own, String(extra.get("label", ""))) + HINT_SUFFIX}
	_hint_left = HINT_S
	_hint_serial += 1


## True when a chart point (nm, nm, metres up) is inside the camera's frame and near enough to
## be made out there.
func _in_frame(at: Vector3) -> bool:
	var cam := _scene.camera
	if cam == null or not cam.is_inside_tree():
		return false
	var p := WorldPresentation.to_world(Vector2(at.x, at.y), _origin_nm, at.z)
	if p.distance_to(cam.global_position) > HINT_FRAME_M:
		return false
	return cam.is_position_in_frustum(p)


## The caption for an event: what happened, and to what.
static func event_caption(kind: String, own: bool, label: String) -> String:
	var text: String = "Unit lost" if kind == "destroyed" and own else String(EVENT_CAPTIONS.get(kind, "Action"))
	return text + " · " + label if label != "" else text


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
	_action_anchor_key = ""
	_entries_action_serial = -1
	_cull_centre = Vector2.INF
	_inbound_seen.clear()
	_hint = {}
	_hint_left = 0.0
	_caption_serial = -1
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
	# Action decides what it shows before the origin is placed: the origin goes with the shot,
	# so a round 90 nm off, or a hit 120 nm off, has its own sea, land and neighbours round it.
	rig.advance(delta)
	var subject_key := rig.action_subject_key()
	var action_serial := rig.action_serial()
	_origin_nm = _view_origin(subject_key)
	if _hint_left > 0.0:
		_hint_left -= delta
	_scene.sim_now = SimClock.sim_time
	_scene.paused = SimClock.paused
	_scene.time_rate = SimClock.multiplier()
	if _chart_generation != Terrain.generation:
		_chart_generation = Terrain.generation
		_scene.set_chart(_charted_rect())
	_scene.lead_s = 0.0 if SimClock.paused else clampf(SimClock._accum, 0.0, SimClock.TICK_DT)
	var env := Detection.environment
	_scene.set_weather(Detection.sea_state, WorldPresentation.visibility_nm(env), env)
	var reference := map.reference_unit()
	var weapon_revision := simulation.weapon_manager.revision if simulation.weapon_manager != null else -1
	var threat_revision := simulation.threat_manager.revision if simulation.threat_manager != null else -1
	var datalink := reference != null and reference.datalink_connected()
	if SimClock.sim_time != _entries_time or reference != _entries_reference or weapon_revision != _entries_weapon_revision or threat_revision != _entries_threat_revision or datalink != _entries_datalink or focus_changed or hooked_anew or action_serial != _entries_action_serial or Debug.enabled:
		_entries_time = SimClock.sim_time
		_entries_reference = reference
		_entries_weapon_revision = weapon_revision
		_entries_threat_revision = threat_revision
		_entries_datalink = datalink
		_entries_action_serial = action_serial
		var entries: Array = WorldPresentation.unit_entries(um, simulation.track_manager, player, env, simulation.track_manager.neutral_factions)
		var rounds := WorldPresentation.weapon_entries(simulation.weapon_manager, simulation.threat_manager, player, reference)
		_offer_inbound(rounds)
		entries.append_array(rounds)
		entries.append_array(WorldPresentation.buoy_entries(simulation.aviation_manager, player, SimClock.sim_time))
		if subject_key != "":
			_anchor_on(entries, subject_key)
		# A subject going down keeps the camera until it has gone, or until something new is hooked.
		if hooked_anew or not _scene.is_dying(_focus_key):
			_focus_key = WorldPresentation.resolve_focus_key(entries, _focus)
		if _cull_centre != Vector2.INF and _cull_centre.distance_to(_origin_nm) > SETTLE_JUMP_NM:
			_scene.settle()
		_cull_centre = _origin_nm
		_entries = WorldPresentation.cull(entries, _origin_nm, _focus_key, WorldPresentation.MAX_RANGE_NM, WorldPresentation.MAX_ENTITIES, subject_key)
	_scene.origin_nm = _origin_nm
	var chart: Dictionary = simulation.scenario.get("map", {})
	var unix := float(SimClock.start_unix_time if SimClock.start_unix_time > 0 else _default_unix) + SimClock.sim_time + sun_offset_s
	_update_sun(unix, chart)
	_scene.update(delta, _entries, subject_key if subject_key != "" else _focus_key)
	for e: Dictionary in _scene.take_events():
		_witnessed(e["kind"], e["at"], e.get("key", ""), e)
	_update_camera(delta)
	_update_subject_label()
	_rain.visible = _scene.rain_intensity > 0.0 and _scene.camera.position.y < _scene.cloud_base_m
	if _rain.visible:
		_rain_material.set_shader_parameter("weather_time", _scene.weather_time)
		_rain_material.set_shader_parameter("intensity", _scene.rain_intensity)
		_rain_material.set_shader_parameter("daylight", _scene.daylight)
		_rain_material.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	Debug.time_add("world", Time.get_ticks_usec() - t0)


## The floating origin for this frame: what Action shows when it shows something (the entity it
## follows, at its simulation position, or the place it watches), else the hooked subject.
func _view_origin(subject_key: String) -> Vector2:
	if rig.mode == CAM_ACTION:
		var a := rig.action()
		if not a.is_empty():
			if subject_key != "" and subject_key == _action_anchor_key:
				return _action_anchor
			var at: Vector3 = a["at"]
			return Vector2(at.x, at.y)
	return _focus.get("position", _origin_nm)


## Puts the origin on the entity Action follows, as these entries have it. A round that has gone
## leaves the origin where Action last saw it.
func _anchor_on(entries: Array, key: String) -> void:
	for e: Dictionary in entries:
		if e["key"] == key:
			_action_anchor = e["position"]
			_action_anchor_key = key
			_origin_nm = _action_anchor
			return
	_action_anchor_key = ""


## Rounds of another side the reference unit's picture holds (the only ones in `rounds`) are
## offered once each, as they first appear, as low-priority events. Interceptors and gunfire are
## not; nor is anything this picture does not hold.
func _offer_inbound(rounds: Array) -> void:
	for e: Dictionary in rounds:
		if e["own"] or e["gun"] or e["interceptor"]:
			continue
		var key: String = e["key"]
		var seen := _inbound_seen.has(key)
		_inbound_seen[key] = SimClock.sim_time
		if seen:
			continue
		var p: Vector2 = e["position"]
		_witnessed("inbound", Vector3(p.x, p.y, float(e["height_m"])), key, {})
	if _inbound_seen.size() > INBOUND_MEMORY:
		for key: String in _inbound_seen.keys():
			if SimClock.sim_time - float(_inbound_seen[key]) > INBOUND_FORGET_S:
				_inbound_seen.erase(key)


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
	var shot := rig.frame_shot(delta, _origin_nm, subject, _frame_lookup)
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


## The caption under the camera controls: the subject, what Action is showing, or in the tether
## an event out of frame worth switching to Action for. Rebuilt only when what it reads changes.
func _update_subject_label() -> void:
	var hinting := rig.mode == CAM_TETHER and _hint_left > 0.0
	var serial := rig.action_serial()
	var subject_name: String = _focus.get("name", "")
	var detail: String = _focus.get("detail", "")
	var track: Track = map.inspection_track() if map != null else null
	if track == null:
		track = _focus.get("track")
	if track != null:
		detail = WorldPresentation.contact_caption(track, _focus_key.begins_with("u:"))
	if rig.mode == _caption_mode and serial == _caption_serial and hinting == _caption_hinting and _hint_serial == _caption_hint_serial and _focus_key == _caption_focus_key and subject_name == _caption_name and detail == _caption_detail:
		return
	_caption_mode = rig.mode
	_caption_serial = serial
	_caption_hinting = hinting
	_caption_hint_serial = _hint_serial
	_caption_focus_key = _focus_key
	_caption_name = subject_name
	_caption_detail = detail
	var caption := subject_name
	var action := rig.action()
	if hinting:
		caption = _hint["text"]
	elif rig.mode == CAM_ACTION and not action.is_empty():
		var label := String(action.get("label", ""))
		var key := String(action.get("key", ""))
		if label == "" and key != "":
			for e: Dictionary in _entries:
				if e["key"] == key:
					label = e.get("label", "")
					break
		caption = event_caption(String(action.get("kind", "")), bool(action.get("own", false)), label)
	elif track != null:
		caption = detail
	_subject_label.text = caption
	_subject_label.tooltip_text = caption


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
