class_name TacticalMap
extends Control
## Tactical map display. Renders the nautical-mile world into pixels and turns mouse input into
## selection changes and order requests. Frame-based; contains no simulation logic.
## Own units are drawn from ground truth; other factions are drawn ONLY as Tracks
## (except under Debug.enabled, which overlays true positions).
##
## The chart runs edge to edge with no chrome of its own: relief and depth bands underneath
## (ChartFloor, ChartLand), then marks and symbols, then the bottom-left position / depth / scale
## readout and the bottom-centre radio line (post_message), all in white bold with a 1 px shadow.
##
## Controls: wheel/pinch or +/- = zoom, middle/right/Option drag = pan, left click = select,
## shift+click = add/remove unit, left drag = box select, double-click = recentre, Plot Move arms
## the explicit left-click move tool (Shift chains waypoints), right-click a track = target it
## (Ctrl/Cmd also engages), right-click a waypoint = remove that leg, arrows/WASD = pan,
## Home = fit the fleet, C = focus the current command problem, F = follow it.

signal selection_changed(units: Array)
signal track_selected(track: Track)
signal move_order_requested(world_pos: Vector2, append: bool)
signal engage_requested(track: Track)
signal waypoint_delete_requested(unit: Unit, index: int)
signal interaction_mode_changed(active: bool)
## Kept for the shell's wiring; the chart has no button of its own that emits it any more.
signal world_view_requested

enum DragMode { NONE, PAN, BOX }
enum InteractionMode { SELECT, MOVE }

const MIN_PPN := 0.2
const MAX_PPN := 6000.0
const ZOOM_STEP := 1.25
const KEYBOARD_ZOOM_RATE := 4.0
const CLICK_RADIUS_PX := 18.0
const WAYPOINT_HIT_PX := 14.0
const DRAG_THRESHOLD_PX := 5.0
const DOUBLE_CLICK_MS := 350
const LEADER_MINUTES := 30.0
const KEY_PAN_PX_PER_S := 700.0
## Compatibility shim: the chart has no footer bar any more, but the world view's inset card still
## anchors itself this far above the chart's bottom edge.
const FOOTER_H := 24.0
## Bottom-left readout and bottom-centre radio line.
const READOUT_MARGIN := 10.0
const READOUT_FONT_SIZE := 13
const READOUT_LINE_H := 16.0
const RADIO_BOTTOM_PX := 8.0
const SPEAKER_RING_PX := 15.0
const TRAIL_INTERVAL_S := 60.0
const TRAIL_LENGTH := 24
const EFFECT_LIFE_S := 2.2
const NICE_STEPS_NM: Array[float] = [0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0, 1000.0]

## Deep water where no floor layer is drawing (a map outside the tree): the chart's 2000 m band.
const COL_OCEAN := Color8(0, 0, 98)
# Flat land for the views without the chart's land shader (the scenario editor and the mission
# preview): the chart's lowland green, and a darker green coastline.
const COL_LAND := Color8(0, 98, 0)
const COL_COAST := Color8(90, 170, 80)
## The chart's own coastline stroke over the shaded land: thin and dark, a hard land/sea edge.
const COL_COASTLINE := Color8(0, 58, 6, 235)
const COL_LAND_LABEL := Color(0.86, 0.92, 0.84, 0.85)
const COAST_MIN_STEP_PX := 1.2  # coastline detail finer than this is dropped as it is invisible
const LAND_LABEL_MIN_PX := 90.0
## Graticule and range rings (both off by default): thin white over the relief.
const COL_GRID := Color(1.0, 1.0, 1.0, 0.20)
const COL_GRID_MINOR := Color(1.0, 1.0, 1.0, 0.08)
const COL_GRID_TEXT := Color(1.0, 1.0, 1.0, 0.75)
const COL_RINGS := Color(1.0, 1.0, 1.0, 0.22)
const COL_TEXT := Color(0.80, 0.90, 0.96)
const COL_SELECT := Color(1.0, 1.0, 1.0, 0.92)
const COL_BOX := Color(0.6, 0.9, 1.0, 0.8)
const COL_WAYPOINT := Color(0.55, 0.95, 0.75, 0.85)
const COL_FRIENDLY := Color(0.42, 0.75, 1.0)
const COL_HOSTILE := Color(1.0, 0.40, 0.38)
const COL_UNKNOWN := Color(1.0, 0.85, 0.32)
const COL_NEUTRAL := Color(0.55, 0.90, 0.60)
const COL_RING := Color(0.36, 0.72, 1.0, 0.45)
const COL_RING_SILENT := Color(0.5, 0.6, 0.65, 0.35)
const COL_SONAR_RING := Color(0.45, 0.95, 0.75, 0.32)
const COL_SONAR_ACTIVE := Color(0.55, 1.0, 0.6, 0.55)
const COL_BUOY := Color(0.5, 0.95, 0.8, 0.85)
const COL_ESM_RING := Color(0.85, 0.7, 1.0, 0.30)
const COL_JAM := Color(0.95, 0.55, 0.95)
const COL_TRUTH := Color(1.0, 0.5, 0.5, 0.45)
const COL_WEAPON_RING := Color(1.0, 0.72, 0.35, 0.55)
const COL_MISSILE := Color(1.0, 0.85, 0.35)
const COL_MISSILE_HOSTILE := Color(1.0, 0.45, 0.35)
const COL_INTERCEPTOR := Color(0.55, 0.95, 1.0)
const COL_ACCENT := UITheme.COL_ACCENT
const COL_AMBER := UITheme.COL_AMBER
## Label plate behind unit and track labels. The world view's labels share it.
const COL_LABEL_BG := Color("08111a", 0.9)
const COL_READOUT := Color.WHITE
const COL_READOUT_SHADOW := Color(0.0, 0.0, 0.0, 0.9)
const COL_RADIO_ALERT := Color("ff5050")
const COL_FIRE := Color(1.0, 0.55, 0.22)
const COL_SMOKE := Color(0.66, 0.66, 0.68)
const COL_FLOOD := Color(0.35, 0.62, 1.0)
const DEFAULT_WIND_FROM_DEG := 250.0  # prevailing winter westerlies, when a scenario names none

var unit_manager: UnitManager
var track_manager: TrackManager
var weapon_manager: WeaponManager
var threat_manager: ThreatManager
var aviation_manager: AviationManager
var simulation: Simulation  # debug overlay only
var weapon_ring: WeaponSpec
var player_faction := "BLUE"
var center_nm := Vector2.ZERO
var ppn := 4.0  # pixels per nautical mile
var selected: Array[Unit] = []
var selected_track: Track = null
var show_key := false
var show_rings := false
var show_trails := true
## Relief shading on land and sea floor (F6). Land and water are always drawn.
var show_terrain := true
## Lat/long graticule (off, as on the classic display) and the bottom-left readouts.
var show_graticule := false
var show_latlon := true
var show_scale := true

var _drag_mode := DragMode.NONE
var _drag_button := MOUSE_BUTTON_NONE
var _drag_start := Vector2.ZERO
var _drag_moved := false
var _mouse := Vector2.ZERO
var _mouse_inside := false
var _last_click_ms: int = -1000000
var _last_click_pos := Vector2.ZERO
var show_vectors := false
var follow_selection := false
var interaction_mode := InteractionMode.SELECT
var keyboard_navigation_enabled := true
var _trail_reference: Unit
var _pending_fit := false
var _fit_center := Vector2.ZERO
var _fit_extent := 0.0
var _font: Font
var _label_rects: Array[Rect2] = []
var _trails: Dictionary = {}  # Unit -> PackedVector2Array (presentation memory only)
var _trail_last_s := -1.0e9
var _effects: Array = []  # {pos, t0, kind, color}
var _anim := 0.0
var _threats: Array = []
var _weapon_trails: Dictionary = {}  # weapon id -> PackedVector2Array of recent positions
var _hit_flash := 0.0
var show_range_grid := false
var _floor: ChartFloor
var _land: ChartLand
var _radio := RadioLine.new()
var _coast_runs: Dictionary = {}  # Landmass -> Array[PackedVector2Array], clip edges removed
var _coast_key := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true
	_font = UITheme.body_font()
	mouse_entered.connect(func() -> void: _mouse_inside = true)
	mouse_exited.connect(func() -> void: _mouse_inside = false)
	resized.connect(_apply_pending_fit)
	# The shaded chart: sea floor first, then the scenario's land, both behind this item's own drawing.
	_floor = ChartFloor.new()
	_floor.name = "ChartFloor"
	_floor.map = self
	add_child(_floor)
	move_child(_floor, 0)
	_land = ChartLand.new()
	_land.name = "ChartLand"
	_land.map = self
	add_child(_land)
	move_child(_land, 1)


func zoom_at_center(factor: float) -> void:
	_zoom_at(size * 0.5, factor)


## One state path serves the shortcuts, the palette and the menus. "terrain" (F6) and "relief" are
## the same switch: relief shading. Land and water are always drawn.
func toggle_layer(layer: String) -> bool:
	var enabled := false
	match layer:
		"key":
			show_key = not show_key
			enabled = show_key
		"sensors":
			show_rings = not show_rings
			enabled = show_rings
		"trails":
			show_trails = not show_trails
			enabled = show_trails
		"terrain", "relief":
			show_terrain = not show_terrain
			enabled = show_terrain
		"vectors":
			show_vectors = not show_vectors
			enabled = show_vectors
		"range_grid":
			show_range_grid = not show_range_grid
			enabled = show_range_grid
		"graticule":
			show_graticule = not show_graticule
			enabled = show_graticule
		"latlon":
			show_latlon = not show_latlon
			enabled = show_latlon
		"scale":
			show_scale = not show_scale
			enabled = show_scale
	return enabled


func set_follow_selection(enabled: bool) -> void:
	follow_selection = enabled and (selected.size() == 1 or selected_track != null)


func set_move_mode(enabled: bool) -> void:
	var next := InteractionMode.MOVE if enabled and _has_controllable_selection() else InteractionMode.SELECT
	if interaction_mode == next:
		return
	interaction_mode = next
	# A pan or box drag in progress would otherwise never see its release, which the move tool
	# swallows, and stay latched to the pointer.
	if _drag_mode != DragMode.NONE:
		_end_drag()
	mouse_default_cursor_shape = Control.CURSOR_CROSS if interaction_mode == InteractionMode.MOVE else Control.CURSOR_ARROW
	interaction_mode_changed.emit(interaction_mode == InteractionMode.MOVE)


func cancel_interaction_mode() -> bool:
	if interaction_mode == InteractionMode.SELECT:
		return false
	set_move_mode(false)
	return true


func _has_controllable_selection() -> bool:
	if selected.is_empty():
		return false
	for u: Unit in selected:
		if u.faction != player_faction or not u.alive or not u.is_engageable() or u.spec.max_speed_kn <= 0.0 or (u.is_aircraft() and not u.airborne()):
			return false
	return true


func _normalize_interaction_state() -> void:
	if interaction_mode == InteractionMode.MOVE and not _has_controllable_selection():
		interaction_mode = InteractionMode.SELECT
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		interaction_mode_changed.emit(false)
	if follow_selection and selected_track == null and selected.size() != 1:
		follow_selection = false


## Compatibility shim: the chart no longer carries a theatre inset (the regional map replaced it),
## but the world view still calls this when its inset card opens and closes.
func set_overview_suppressed(_suppressed: bool) -> void:
	pass


## A line on the radio line, bottom-centre: held HOLD_S, then faded; the newest few stack with the
## latest at the bottom. "alert" severity reads red. With a speaker (an own Unit, or a Track as the
## plot holds it) the line reads "<callsign>: <text>" and the speaker's symbol is ringed in white
## while the line is up.
func post_message(text: String, severity := "info", speaker = null) -> void:
	_radio.post(text, severity, speaker, _anim)


func _process(delta: float) -> void:
	_anim += delta
	if selected_track != null and not selected_track.visible_to(reference_unit()):
		select_track(null)
	_hit_flash = maxf(_hit_flash - delta, 0.0)
	_keyboard_pan(delta)
	_keyboard_zoom(delta)
	_prune_selection()
	if follow_selection and _drag_mode == DragMode.NONE:
		if selected_track != null:
			_center_world_in_chart(selected_track.position)
		elif selected.size() == 1:
			_center_world_in_chart((selected[0] as Unit).position)
	_record_trails()
	_record_weapon_trails()
	queue_redraw()


## Recent positions of every round in flight, so a missile draws a real curved trail rather
## than a straight stub. Presentation memory only; dropped when the round is gone.
func _record_weapon_trails() -> void:
	if weapon_manager == null:
		return
	var ref := reference_unit()
	if _trail_reference != ref:
		_weapon_trails.clear()
		_trail_reference = ref
	var live: Dictionary = {}
	for w: Weapon in weapon_manager.in_flight:
		if w.faction != player_faction and not Debug.enabled and (threat_manager == null or ref == null or not threat_manager.visible_to(ref, w)):
			continue
		live[w.id] = true
		var arr: PackedVector2Array = _weapon_trails.get(w.id, PackedVector2Array())
		if arr.is_empty() or arr[arr.size() - 1].distance_to(w.position) > 0.02:
			arr.append(w.position)
			if arr.size() > 36:
				arr.remove_at(0)
			_weapon_trails[w.id] = arr
	for id in _weapon_trails.keys():
		if not live.has(id):
			_weapon_trails.erase(id)


## Presentation-only memory of where own units have been, sampled on simulation time so a
## trail reads the same at any acceleration.
func _record_trails() -> void:
	if unit_manager == null:
		return
	var now := SimClock.sim_time
	if now < _trail_last_s:
		_trails.clear()  # scenario restarted
	if now - _trail_last_s < TRAIL_INTERVAL_S:
		return
	_trail_last_s = now
	for u in _own_units():
		if not _trails.has(u):
			_trails[u] = PackedVector2Array()
		var arr: PackedVector2Array = _trails[u]
		arr.append(u.position)
		if arr.size() > TRAIL_LENGTH:
			arr.remove_at(0)
		_trails[u] = arr


## Called by Main when the simulation reports something worth a flash on the map.
## kind: "hit", "miss", "intercept", "decoy", "destroyed", "launch", "splash", "refused".
func add_effect(pos: Vector2, kind: String, own := false) -> void:
	if own and (kind == "hit" or kind == "destroyed"):
		_hit_flash = 1.2
	var col := COL_AMBER
	match kind:
		"hit", "destroyed":
			col = COL_HOSTILE
		"intercept":
			col = COL_INTERCEPTOR
		"decoy":
			col = COL_NEUTRAL
		"miss", "splash":
			col = Color(0.6, 0.7, 0.8)
		"refused":
			col = COL_AMBER
		"launch":
			col = COL_MISSILE
	_effects.append({"pos": pos, "t0": _anim, "kind": kind, "color": col})
	if _effects.size() > 40:
		_effects.remove_at(0)


func reset_presentation() -> void:
	_radio.clear()
	_trails.clear()
	_weapon_trails.clear()
	_effects.clear()
	_hit_flash = 0.0
	_trail_last_s = -1.0e9


# --- View transform ---------------------------------------------------------------------

func world_to_screen(w: Vector2) -> Vector2:
	var d := w - center_nm
	return Vector2(size.x * 0.5 + d.x * ppn, size.y * 0.5 - d.y * ppn)


func screen_to_world(s: Vector2) -> Vector2:
	return Vector2(center_nm.x + (s.x - size.x * 0.5) / ppn, center_nm.y - (s.y - size.y * 0.5) / ppn)


## Bounds left clear for fitted units and targets. The chart carries no chrome, so this is the whole
## control, less the symbol key's strip on the left while the key is showing.
func unobstructed_chart_rect() -> Rect2:
	var left := 0.0
	if show_key:
		var key := _symbol_key_rect()
		left = minf(key.position.x + key.size.x + 8.0, maxf(size.x - 1.0, 0.0))
	return Rect2(Vector2(left, 0.0), Vector2(maxf(size.x - left, 1.0), maxf(size.y, 1.0)))


func fit_to(center: Vector2, extent_nm: float) -> void:
	set_follow_selection(false)
	_fit_center = center
	_fit_extent = extent_nm
	_pending_fit = true
	_apply_pending_fit()


func _apply_pending_fit() -> void:
	if not _pending_fit or size.x <= 0.0 or size.y <= 0.0:
		return
	_pending_fit = false
	var chart := unobstructed_chart_rect()
	ppn = clampf(minf(chart.size.x, chart.size.y) / maxf(_fit_extent, 1.0), MIN_PPN, MAX_PPN)
	_center_world_in_chart(_fit_center)


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var anchor := screen_to_world(screen_pos)
	ppn = clampf(ppn * factor, MIN_PPN, MAX_PPN)
	center_nm = Vector2(anchor.x - (screen_pos.x - size.x * 0.5) / ppn, anchor.y + (screen_pos.y - size.y * 0.5) / ppn)


## Recentres the view on a point without touching zoom. Used to snap back to a unit or track
## the player has lost track of on a spread-out picture, without re-fitting the whole scale.
func center_on(world_pos: Vector2) -> void:
	set_follow_selection(false)
	_center_world_in_chart(world_pos)


func _center_world_in_chart(world_pos: Vector2) -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		center_nm = world_pos
		return
	var target := unobstructed_chart_rect().get_center()
	var delta := target - size * 0.5
	center_nm = world_pos - Vector2(delta.x / maxf(ppn, MIN_PPN), -delta.y / maxf(ppn, MIN_PPN))


## Focuses the current command problem. A single platform keeps the current zoom; a group or a
## shooter/target pair is fitted together so "focus" cannot leave every selected symbol offscreen.
func center_on_selection() -> void:
	if selected.is_empty():
		if selected_track != null:
			center_on(selected_track.position)
		else:
			fit_to_fleet()
		return
	if selected.size() == 1 and selected_track == null:
		center_on((selected[0] as Unit).position)
		return
	var points := PackedVector2Array()
	for u: Unit in selected:
		points.append(u.position)
	if selected_track != null:
		points.append(selected_track.position)
	_fit_points(points)


func _fit_points(points: PackedVector2Array) -> void:
	if points.is_empty():
		return
	var lo := points[0]
	var hi := points[0]
	for point in points:
		lo.x = minf(lo.x, point.x)
		lo.y = minf(lo.y, point.y)
		hi.x = maxf(hi.x, point.x)
		hi.y = maxf(hi.y, point.y)
	fit_to((lo + hi) * 0.5, maxf(hi.x - lo.x, hi.y - lo.y) * 1.35 + 6.0)


## Fits the whole own-force to the view, the way the scenario's initial picture does. Recovers
## the display after the fleet has spread out or the view has been panned away from it.
func fit_to_fleet() -> void:
	var own := _own_units()
	if own.is_empty():
		return
	var points := PackedVector2Array()
	for u in own:
		points.append(u.position)
	_fit_points(points)


func _keyboard_pan(delta: float) -> void:
	if not keyboard_navigation_enabled:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and focus != self:
		return
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		dir.y += 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		dir.y -= 1.0
	if dir != Vector2.ZERO:
		set_follow_selection(false)
		center_nm += dir.normalized() * KEY_PAN_PX_PER_S * delta / ppn


## +/- (and the numpad equivalents) zoom on the screen centre, for a wheel-free way to work the
## scale — smooth and continuous while held, matching the feel of the wheel step.
func _keyboard_zoom(delta: float) -> void:
	if not keyboard_navigation_enabled:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and focus != self:
		return
	var dir := 0.0
	if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD):
		dir += 1.0
	if Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
		dir -= 1.0
	if dir != 0.0:
		_zoom_at(size * 0.5, pow(ZOOM_STEP, dir * delta * KEYBOARD_ZOOM_RATE))


# --- Input ------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		# A drag owns its matching release even when the pointer leaves the chart. Otherwise the
		# rejected release leaves the pan/box latch active indefinitely.
		var finishes_drag := not mouse.pressed and _drag_mode != DragMode.NONE and mouse.button_index == _drag_button
		if not finishes_drag and not _chart_accepts_point(mouse.position):
			accept_event()
			return
		_handle_mouse_button(event)
		accept_event()
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventPanGesture:
		var pan := event as InputEventPanGesture
		set_follow_selection(false)
		center_nm += Vector2(pan.delta.x, -pan.delta.y) * 28.0 / maxf(ppn, MIN_PPN)
		accept_event()
	elif event is InputEventMagnifyGesture:
		var magnify := event as InputEventMagnifyGesture
		_zoom_at(magnify.position, clampf(magnify.factor, 0.5, 2.0))
		accept_event()


## The whole chart takes commands: there is no header, footer or card to click through to.
func _chart_accepts_point(point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(point)


func _handle_mouse_button(e: InputEventMouseButton) -> void:
	_mouse = e.position
	match e.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if e.pressed:
				_zoom_at(e.position, pow(ZOOM_STEP, maxf(e.factor, 0.25)))
		MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				_zoom_at(e.position, 1.0 / pow(ZOOM_STEP, maxf(e.factor, 0.25)))
		MOUSE_BUTTON_LEFT:
			# Option-drag is always a camera gesture, including while Plot Move is armed.
			if e.pressed and e.alt_pressed:
				grab_focus()
				_begin_drag(DragMode.PAN, e)
				return
			if not e.pressed and _drag_button == MOUSE_BUTTON_LEFT and _drag_mode == DragMode.PAN:
				_end_drag()
				return
			if interaction_mode == InteractionMode.MOVE:
				if e.pressed:
					grab_focus()
					if _unit_at(e.position) != null or _track_at(e.position) != null:
						_click_select(e.position, e.shift_pressed)
					else:
						var target := screen_to_world(e.position)
						var acceptance := _move_acceptance(target)
						if int(acceptance["accepted"]) == 0:
							add_effect(target, "refused")
						else:
							move_order_requested.emit(target, e.shift_pressed)
							if not e.shift_pressed:
								set_move_mode(false)
				return
			if e.pressed:
				grab_focus()
				_begin_drag(DragMode.BOX, e)
			elif _drag_button == MOUSE_BUTTON_LEFT:
				if _drag_moved and _drag_mode == DragMode.BOX:
					_box_select(Rect2(_drag_start, e.position - _drag_start).abs(), e.shift_pressed)
				elif not _drag_moved:
					_click_select(e.position, e.shift_pressed)
					_check_double_click(e.position)
				_end_drag()
		MOUSE_BUTTON_MIDDLE:
			if e.pressed:
				_begin_drag(DragMode.PAN, e)
			elif _drag_button == MOUSE_BUTTON_MIDDLE:
				_end_drag()
		MOUSE_BUTTON_RIGHT:
			if interaction_mode == InteractionMode.MOVE:
				if e.pressed:
					set_move_mode(false)
				return
			if e.pressed:
				_begin_drag(DragMode.PAN, e)
			elif _drag_button == MOUSE_BUTTON_RIGHT:
				if not _drag_moved:
					var wp := _waypoint_at(e.position)
					if not wp.is_empty():
						waypoint_delete_requested.emit(wp["unit"], wp["index"])
					else:
						var t := _track_at(e.position)
						if t != null:
							if e.ctrl_pressed or e.meta_pressed:
								engage_requested.emit(t)
							else:
								select_track(t)
				_end_drag()


func _handle_mouse_motion(e: InputEventMouseMotion) -> void:
	_mouse = e.position
	if _drag_mode == DragMode.NONE:
		return
	if not _drag_moved and e.position.distance_to(_drag_start) > DRAG_THRESHOLD_PX:
		_drag_moved = true
	if _drag_mode == DragMode.PAN and _drag_moved:
		set_follow_selection(false)
		center_nm -= Vector2(e.relative.x, -e.relative.y) / ppn


func _begin_drag(mode: DragMode, e: InputEventMouseButton) -> void:
	if _drag_mode != DragMode.NONE:
		return
	_drag_mode = mode
	_drag_button = e.button_index
	_drag_start = e.position
	_drag_moved = false
	if mode == DragMode.PAN:
		mouse_default_cursor_shape = Control.CURSOR_DRAG


func _end_drag() -> void:
	_drag_mode = DragMode.NONE
	_drag_button = MOUSE_BUTTON_NONE
	_drag_moved = false
	mouse_default_cursor_shape = Control.CURSOR_CROSS if interaction_mode == InteractionMode.MOVE else Control.CURSOR_ARROW


# --- Selection --------------------------------------------------------------------------

## Own units that are actually on the board. An aircraft in a hangar is not drawn, not clickable
## and not box-selectable; it is reached through the ship that carries it.
func _own_units() -> Array[Unit]:
	if unit_manager == null:
		return []
	var out: Array[Unit] = []
	for u in unit_manager.get_faction_units(player_faction):
		if u.is_aircraft() and not u.in_flight():
			continue
		out.append(u)
	return out


func _visible_tracks() -> Array:
	if track_manager == null:
		return []
	var ref := reference_unit()
	return track_manager.tracks_for(ref) if ref != null else track_manager.get_tracks(player_faction)


## Priority navigation keeps a busy watch actionable: confirmed hostiles first, then unknowns,
## fresh plots before stale ones, and the nearest problem before a remote one.
func priority_tracks() -> Array:
	var tracks: Array = _visible_tracks().duplicate()
	var ref := reference_unit()
	tracks.sort_custom(func(a: Track, b: Track) -> bool: return _track_precedes(a, b, ref))
	return tracks


static func _track_precedes(a: Track, b: Track, ref: Unit) -> bool:
	var a_identity := 0 if a.identity == "HOSTILE" else (1 if a.identity == "UNKNOWN" else 2)
	var b_identity := 0 if b.identity == "HOSTILE" else (1 if b.identity == "UNKNOWN" else 2)
	if a_identity != b_identity:
		return a_identity < b_identity
	var a_stale := 1 if a.status == Track.Status.STALE else 0
	var b_stale := 1 if b.status == Track.Status.STALE else 0
	if a_stale != b_stale:
		return a_stale < b_stale
	if ref != null:
		var ad := ref.position.distance_squared_to(a.position)
		var bd := ref.position.distance_squared_to(b.position)
		if not is_equal_approx(ad, bd):
			return ad < bd
	return a.id < b.id


func cycle_priority_track(step := 1) -> Track:
	var tracks := priority_tracks()
	if tracks.is_empty():
		return null
	var index := tracks.find(selected_track)
	index = posmod(index + step, tracks.size()) if index >= 0 else (tracks.size() - 1 if step < 0 else 0)
	var next := tracks[index] as Track
	select_track(next)
	set_follow_selection(false)
	center_on(next.position)
	return next


func _unit_at(screen_pos: Vector2) -> Unit:
	var best: Unit = null
	var best_d := CLICK_RADIUS_PX
	for u in _own_units():
		var d := world_to_screen(u.position).distance_to(screen_pos)
		if d <= best_d:
			best = u
			best_d = d
	return best


func _track_at(screen_pos: Vector2) -> Track:
	var best: Track = null
	var best_d := CLICK_RADIUS_PX
	for t: Track in _visible_tracks():
		var d := world_to_screen(t.position).distance_to(screen_pos)
		if d <= best_d:
			best = t
			best_d = d
	return best


## The nearest own waypoint marker to the cursor, if any is close enough to act on. Shared by the
## right-click handler (delete that leg) and the hover card (hint that it is clickable).
func _waypoint_at(screen_pos: Vector2) -> Dictionary:
	var best := {}
	var best_d := WAYPOINT_HIT_PX
	for u in _own_units():
		for i in u.waypoints.size():
			var d := world_to_screen(u.waypoints[i]).distance_to(screen_pos)
			if d <= best_d:
				best = {"unit": u, "index": i}
				best_d = d
	return best


## A second click on the same unit or track within the window recentres the view on it, without
## touching zoom or selection — the "find the ship again" gesture on a spread-out picture.
func _check_double_click(screen_pos: Vector2) -> void:
	var now := Time.get_ticks_msec()
	var is_double := now - _last_click_ms <= DOUBLE_CLICK_MS and screen_pos.distance_to(_last_click_pos) <= DRAG_THRESHOLD_PX
	if is_double:
		var u := _unit_at(screen_pos)
		if u != null:
			center_on(u.position)
		else:
			var t := _track_at(screen_pos)
			if t != null:
				center_on(t.position)
		_last_click_ms = -1000000
	else:
		_last_click_ms = now
		_last_click_pos = screen_pos


func _click_select(screen_pos: Vector2, additive: bool) -> void:
	var hit := _unit_at(screen_pos)
	if hit == null:
		var t := _track_at(screen_pos)
		if t != null:
			select_track(t)
			return
	if additive:
		if hit != null:
			if selected.has(hit):
				selected.erase(hit)
			else:
				selected.append(hit)
	else:
		selected.clear()
		if hit != null:
			selected.append(hit)
		else:
			select_track(null)
	_normalize_interaction_state()
	selection_changed.emit(selected)


func _box_select(rect: Rect2, additive: bool) -> void:
	if not additive:
		selected.clear()
	for u in _own_units():
		if rect.has_point(world_to_screen(u.position)) and not selected.has(u):
			selected.append(u)
	_normalize_interaction_state()
	selection_changed.emit(selected)


func select_units(units: Array) -> void:
	selected.clear()
	for u in units:
		selected.append(u)
	_normalize_interaction_state()
	selection_changed.emit(selected)


func select_track(t: Track) -> void:
	if t == selected_track:
		return
	selected_track = t
	_normalize_interaction_state()
	track_selected.emit(t)


func clear_selection() -> void:
	select_track(null)
	if selected.is_empty():
		_normalize_interaction_state()
		return
	selected.clear()
	_normalize_interaction_state()
	selection_changed.emit(selected)


func _prune_selection() -> void:
	if selected_track != null and selected_track.status == Track.Status.LOST:
		select_track(null)
	var before := selected.size()
	selected = selected.filter(func(u: Unit) -> bool: return u.alive)
	if selected.size() != before:
		_normalize_interaction_state()
		selection_changed.emit(selected)
	else:
		_normalize_interaction_state()


## The unit the display is centred on for bearings and range rings: the selection, otherwise
## the first surface ship the player owns.
func reference_unit() -> Unit:
	for u: Unit in selected:
		if not u.is_aircraft() or u.in_flight():
			return u
	# An airframe on deck has its sensors dark and is off the link. It sees through its ship,
	# or the picture (and every contact and threat alert keyed to it) would go blank.
	for u: Unit in selected:
		if u.home != null and u.home.alive:
			return u.home
	for u in _own_units():
		if not u.is_aircraft():
			return u
	var own := _own_units()
	return own[0] if not own.is_empty() else null


# --- Drawing ----------------------------------------------------------------------------

func _draw() -> void:
	_label_rects.clear()
	if selected_track != null and not show_key:
		_label_rects.append(_solution_rect())
	# Labels keep clear of the readout block, and of the radio line while it is speaking.
	_label_rects.append(_readout_rect())
	if not _radio.visible(_anim).is_empty():
		_label_rects.append(_radio_rect())
	_threats = AirDefence.inbound_threats(unit_manager, threat_manager, player_faction, reference_unit()) if unit_manager != null and threat_manager != null else []
	_draw_ocean()
	_draw_land()
	if show_graticule:
		_draw_grid()
	if show_range_grid:
		_draw_range_rings()
	_draw_chart_labels()
	_draw_objectives()
	_draw_move_preview()
	if unit_manager != null:
		if show_rings:
			_draw_sensor_rings()
		_draw_weapon_ring()
		if Debug.enabled:
			_draw_truth()
		_draw_sonobuoys()
		_draw_relative_motion()
		_draw_tracks()
		_draw_units()
		_draw_weapons()
		_draw_effects()
		_draw_speaker_rings()
	if _hit_flash > 0.0:
		var a := 0.35 * (_hit_flash / 1.2)
		var clear := Color(1.0, 0.3, 0.25, 0.0)
		var edge := Color(1.0, 0.3, 0.25, a)
		var w := 90.0
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, w), Vector2(w, size.y - w), Vector2(0, size.y)]), PackedColorArray([edge, clear, clear, edge]))
		draw_polygon(PackedVector2Array([Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(size.x - w, size.y - w), Vector2(size.x - w, w)]), PackedColorArray([edge, edge, clear, clear]))
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x - w, w), Vector2(w, w)]), PackedColorArray([edge, edge, clear, clear]))
		draw_polygon(PackedVector2Array([Vector2(0, size.y), Vector2(w, size.y - w), Vector2(size.x - w, size.y - w), Vector2(size.x, size.y)]), PackedColorArray([edge, clear, clear, edge]))
	if _drag_mode == DragMode.BOX and _drag_moved:
		var r := Rect2(_drag_start, _mouse - _drag_start).abs()
		draw_rect(r, Color(COL_BOX, 0.08))
		draw_rect(r, COL_BOX, false, 1.0)
	_draw_readout()
	_draw_radio_line()
	_draw_key()
	_draw_solution_card()
	_draw_hover_card()


func _draw_move_preview() -> void:
	if interaction_mode != InteractionMode.MOVE or not _mouse_inside or not _chart_accepts_point(_mouse):
		return
	if _unit_at(_mouse) != null or _track_at(_mouse) != null:
		return
	var target := screen_to_world(_mouse)
	var append := Input.is_key_pressed(KEY_SHIFT)
	var acceptance := _move_acceptance(target)
	var accepted := int(acceptance["accepted"])
	var total := int(acceptance["total"])
	for u: Unit in selected:
		if u.faction != player_faction:
			continue
		var start := u.waypoints[-1] if append and not u.waypoints.is_empty() else u.position
		var a := world_to_screen(start)
		var hit := Terrain.first_land_contact(start, target) if u.needs_sea_room() and not Terrain.is_empty() else -1.0
		if hit >= 0.0:
			var beach := world_to_screen(start.lerp(target, hit))
			draw_dashed_line(a, beach, COL_WAYPOINT, 2.0, 8.0)
			draw_dashed_line(beach, _mouse, Color(COL_HOSTILE, 0.9), 2.0, 8.0)
		else:
			draw_dashed_line(a, _mouse, COL_WAYPOINT, 2.0, 8.0)
	var col := COL_HOSTILE if accepted == 0 else (COL_AMBER if accepted < total else COL_WAYPOINT)
	draw_circle(_mouse, 11.0, Color(col, 0.12))
	draw_arc(_mouse, 11.0, 0.0, TAU, 24, col, 2.0, true)
	draw_line(_mouse + Vector2(-16, 0), _mouse + Vector2(16, 0), Color(col, 0.7), 1.0)
	draw_line(_mouse + Vector2(0, -16), _mouse + Vector2(0, 16), Color(col, 0.7), 1.0)
	var label := "LAND — PICK WATER" if accepted == 0 else ("%d OF %d CAN MOVE HERE" % [accepted, total] if accepted < total else ("ADD WAYPOINT" if append else "SET COURSE"))
	draw_string(_font, _mouse + Vector2(17, -12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)


func _move_acceptance(target: Vector2) -> Dictionary:
	var total := 0
	var accepted := 0
	var target_is_land := not Terrain.is_empty() and Terrain.is_land(target)
	for u: Unit in selected:
		if u.faction != player_faction or not u.alive or not u.is_engageable() or u.spec.max_speed_kn <= 0.0 or (u.is_aircraft() and not u.airborne()):
			continue
		total += 1
		if not target_is_land or not u.needs_sea_room():
			accepted += 1
	return {"accepted": accepted, "total": total}


func _nice_step(min_px: float) -> float:
	for s in NICE_STEPS_NM:
		if s * ppn >= min_px:
			return s
	return NICE_STEPS_NM[-1]


## The sea is ChartFloor's, painted behind this item. A map outside the tree (a test, a tool) has no
## floor, and gets plain deep water instead.
func _draw_ocean() -> void:
	if _floor == null or not _floor.is_inside_tree():
		draw_rect(Rect2(Vector2.ZERO, size), COL_OCEAN)


## The scenario's coastline, the land the simulation uses. ChartLand has already filled it with
## the shaded land tint; this strokes a crisp, thin, anti-aliased edge over the fill's hard pixel
## edge. With no ChartLand (a map outside the tree) the land is filled flat.
func _draw_land() -> void:
	if Terrain.is_empty():
		return
	var view := Rect2(screen_to_world(Vector2.ZERO), Vector2.ZERO).expand(screen_to_world(size))
	var flat := _land == null or not _land.is_inside_tree()
	var meshes := ChartLand.land_meshes() if flat else {}
	var transform := Transform2D(Vector2(ppn, 0), Vector2(0, ppn), world_to_screen(Vector2.ZERO))
	var box := ChartFloor.charted_box(simulation)
	var key := "%d:%s" % [Terrain.generation, box]
	if key != _coast_key:
		_coast_key = key
		_coast_runs.clear()
		for l: Landmass in Terrain.landmasses:
			_coast_runs[l] = coast_runs(l.points, box)
	for l: Landmass in Terrain.landmasses:
		if not l.bounds.intersects(view):
			continue
		var mesh: ArrayMesh = meshes.get(l)
		if mesh != null:
			draw_mesh(mesh, null, transform, COL_LAND)
		for run: PackedVector2Array in _coast_runs.get(l, []):
			var line := _project_coast(run)
			if line.size() >= 2:
				draw_polyline(line, COL_COASTLINE, 1.25, true)
		if l.name != "":
			_draw_land_name(l, view)


## A coastline as the runs to stroke. Where a polygon runs along the charted box's edge the scenario
## clipped it there: that straight edge is not a coast (the land carries on past it on the raster),
## so the ring is split and those segments are left out. A ring with no clip edge comes back whole
## and closed.
static func coast_runs(points: PackedVector2Array, box: Rect2) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var n := points.size()
	if n < 2:
		return out
	var start := -1
	if box.size.x > 0.0:
		for i in n:
			if _on_box_edge(points[i], points[(i + 1) % n], box):
				start = i
				break
	if start < 0:
		var ring := points.duplicate()
		ring.append(points[0])
		out.append(ring)
		return out
	var run := PackedVector2Array()
	for k in n:
		var i := (start + 1 + k) % n
		var a := points[i]
		var b := points[(i + 1) % n]
		if _on_box_edge(a, b, box):
			if run.size() >= 2:
				out.append(run)
			run = PackedVector2Array()
			continue
		if run.is_empty():
			run.append(a)
		run.append(b)
	if run.size() >= 2:
		out.append(run)
	return out


## Both ends within the clip margin of the same side of the box. Scenario polygons are clipped at
## or a little inside their stated box (and simplified afterwards), so this is a margin, not an
## exact match; ChartFloor lets the raster own the coast inside the same margin.
static func _on_box_edge(a: Vector2, b: Vector2, box: Rect2) -> bool:
	const EPS := ChartFloor.CLIP_MARGIN_NM
	for x in [box.position.x, box.end.x]:
		if absf(a.x - x) < EPS and absf(b.x - x) < EPS:
			return true
	for y in [box.position.y, box.end.y]:
		if absf(a.y - y) < EPS and absf(b.y - y) < EPS:
			return true
	return false


## Names the coast in the middle of the part of it that is actually on screen, so a mainland
## running off the chart is still named instead of labelling itself somewhere out of sight.
func _draw_land_name(l: Landmass, view: Rect2) -> void:
	var shown := l.bounds.intersection(view)
	if shown.size.x * ppn < LAND_LABEL_MIN_PX:
		return
	var anchor := shown.get_center()
	if not l.contains(anchor):
		if not view.has_point(l.centroid):
			return
		anchor = l.centroid
	var text := l.name.to_upper()
	var at := world_to_screen(anchor)
	at.x -= _readout_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x * 0.5
	_shadow_text(at, text, 11, COL_LAND_LABEL)


## Projects a coastline and throws away detail finer than a pixel or so. A scenario chart is
## viewed from a whole ocean down to a single bay, and at the far end most of the vertices in a
## coastline land on top of each other.
func _project_coast(world: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	if world.is_empty():
		return out
	var last := world_to_screen(world[0])
	out.append(last)
	for i in range(1, world.size()):
		var p := world_to_screen(world[i])
		if p.distance_squared_to(last) < COAST_MIN_STEP_PX * COAST_MIN_STEP_PX and i < world.size() - 1:
			continue
		out.append(p)
		last = p
	return out


func _geo_map() -> Dictionary:
	return simulation.scenario.get("map", {}) if simulation != null else {}


## The scenario's place names, in the chart's white bold with a shadow and no plate.
func _draw_chart_labels() -> void:
	var m := _geo_map()
	var safe := Rect2(Vector2(8, 8), size - Vector2(16, 16))
	var occupied: Array[Rect2] = []
	var font := _readout_font()
	for entry in m.get("labels", []):
		var p: Array = entry["position_nm"]
		var at := world_to_screen(Vector2(p[0], p[1]))
		var text := str(entry["text"])
		var water: bool = entry.get("kind", "land") == "water"
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var rect := Rect2(at - Vector2(width / 2, 12), Vector2(width, 18))
		if not safe.encloses(rect):
			continue
		var collision := false
		for other in occupied:
			if other.grow(10).intersects(rect): collision = true
		if collision: continue
		occupied.append(rect)
		_shadow_text(at - Vector2(width / 2, 0), text, 11, Color(COL_READOUT, 0.72 if water else 0.9))


func _chart_axis(value: float, positive: String, negative: String) -> String:
	if ppn < 1000.0:
		return Geo.format_axis(value, positive, negative)
	return "%s %.3f" % [positive if value >= 0 else negative, absf(value)]


func _draw_grid() -> void:
	if _geo_map().has("anchor_lat"):
		_draw_graticule()
		return
	var step := _nice_step(110.0)
	var minor := step / 5.0
	var tl := screen_to_world(Vector2.ZERO)
	var br := screen_to_world(size)
	if minor * ppn >= 18.0:
		var x := floorf(tl.x / minor) * minor
		while x <= br.x:
			var sx := world_to_screen(Vector2(x, 0.0)).x
			draw_line(Vector2(sx, 0.0), Vector2(sx, size.y), COL_GRID_MINOR, 1.0)
			x += minor
		var y := floorf(br.y / minor) * minor
		while y <= tl.y:
			var sy := world_to_screen(Vector2(0.0, y)).y
			if sy > 0.0:
				draw_line(Vector2(0.0, sy), Vector2(size.x, sy), COL_GRID_MINOR, 1.0)
			y += minor
	var x := floorf(tl.x / step) * step
	while x <= br.x:
		var sx := world_to_screen(Vector2(x, 0.0)).x
		draw_line(Vector2(sx, 0.0), Vector2(sx, size.y), COL_GRID, 1.0)
		var label := _chart_axis(x, "E", "W")
		draw_string(_font, Vector2(sx + 4.0, 14.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_GRID_TEXT)
		x += step
	var y := floorf(br.y / step) * step
	while y <= tl.y:
		var sy := world_to_screen(Vector2(0.0, y)).y
		if sy > 20.0:
			draw_line(Vector2(0.0, sy), Vector2(size.x, sy), COL_GRID, 1.0)
			draw_string(_font, Vector2(5.0, sy - 4.0), _chart_axis(y, "N", "S"), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_GRID_TEXT)
		y += step


## Own-ship-centred range rings and bearing spokes, the way a console keeps the picture
## relative to the ship it is aboard.
func _draw_range_rings() -> void:
	var ref := reference_unit()
	if ref == null:
		return
	var c := world_to_screen(ref.position)
	var step := _nice_step(140.0)
	var max_r := maxf(size.x, size.y) * 1.2
	var i := 1
	while step * i * ppn < max_r and i <= 12:
		var r := step * i * ppn
		draw_arc(c, r, 0.0, TAU, 160, COL_RINGS, 1.0, true)
		var lp := c + Vector2(sin(deg_to_rad(45.0)), -cos(deg_to_rad(45.0))) * r
		if Rect2(Vector2.ZERO, size).has_point(lp):
			draw_string(_font, lp + Vector2(3.0, -3.0), ("%d m" % int(roundf(step * i * 1852.0))) if step < 0.5 else Geo.format_nm(step * i), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(COL_GRID_TEXT, 0.7))
		i += 1
	for deg in range(0, 360, 90):
		var d := Vector2(sin(deg_to_rad(deg)), -cos(deg_to_rad(deg)))
		draw_line(c + d * 24.0, c + d * max_r, Color(COL_RINGS, 0.055), 1.0, true)


func _draw_graticule() -> void:
	var m := _geo_map()
	var lat0 := float(m["anchor_lat"])
	var lon0 := float(m["anchor_lon"])
	var tl := Geo.world_to_latlon(screen_to_world(Vector2.ZERO), lat0, lon0)
	var br := Geo.world_to_latlon(screen_to_world(size), lat0, lon0)
	var coslat := cos(deg_to_rad(lat0))
	var steps := [0.0001, 0.0002, 0.0005, 0.001, 0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0]
	var lat_step := 30.0
	var lon_step := 30.0
	for step: float in steps:
		if step * 60 * ppn >= 100:
			lat_step = step
			break
	for step: float in steps:
		if step * 60 * coslat * ppn >= 130:
			lon_step = step
			break
	var lat := ceilf(br.x / lat_step) * lat_step
	while lat <= tl.x:
		var y := world_to_screen(Vector2(0, (lat - lat0)*60)).y
		if y > 22 and y < size.y - 85:
			draw_line(Vector2(0, y), Vector2(size.x, y), COL_GRID, 1)
			draw_string(_font, Vector2(7, y-5), Geo.format_latlon(lat), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_GRID_TEXT)
		lat += lat_step
	var lon := ceilf(tl.y / lon_step) * lon_step
	while lon <= br.y:
		var x := world_to_screen(Vector2((lon-lon0)*60*coslat, 0)).x
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), COL_GRID, 1)
		if x > 90 and x < size.x-100:
			draw_string(_font, Vector2(x+4, 15), Geo.format_latlon(lon, false), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_GRID_TEXT)
		lon += lon_step


func _draw_objectives() -> void:
	if simulation == null:
		return
	var mission := simulation.mission_manager
	for o in mission.victory_objectives + mission.loss_objectives:
		if o.kind == MissionObjective.Kind.REACH_AREA:
			var sp := world_to_screen(o.center)
			var r := o.radius_nm * ppn
			var danger: bool = mission.loss_objectives.has(o)
			var col := COL_AMBER if danger else COL_WAYPOINT
			draw_circle(sp, r, Color(col, 0.07))
			draw_arc(sp, r, 0.0, TAU, 80, Color(col, 0.65), 1.5, true)
			_place_label(sp, "DENY EXIT" if danger else "OBJECTIVE AREA", col, false, "")


func _draw_sensor_rings() -> void:
	for u in _own_units():
		if not (Debug.enabled or selected.has(u)):
			continue
		var sp := world_to_screen(u.position)
		var esm := Detection.nominal_esm_ring_nm(u)
		if esm > 0.0:
			draw_arc(sp, esm * ppn, 0.0, TAU, 128, COL_ESM_RING, 1.0, true)
		var sonar := Detection.nominal_passive_ring_nm(u)
		if sonar > 0.0:
			draw_arc(sp, sonar * ppn, 0.0, TAU, 96, COL_SONAR_RING, 1.0, true)
		if Acoustics.cz_available(u):
			_draw_convergence_zones(sp)
		var active := Detection.best_active_sonar_nm(u)
		if active > 0.0:
			draw_arc(sp, active * ppn, 0.0, TAU, 72, COL_SONAR_ACTIVE, 1.5, true)
			# The ping itself: an expanding pulse out to the active reach.
			var pulse := fmod(_anim * 0.35, 1.0)
			draw_arc(sp, active * ppn * pulse, 0.0, TAU, 72, Color(COL_SONAR_ACTIVE, 0.6 * (1.0 - pulse)), 2.0, true)
		if u.has_jammer():
			for s in u.sensors:
				if s.kind == "jammer":
					var col := COL_JAM if u.jamming() else Color(COL_JAM, 0.35)
					_draw_dashed_circle(sp, s.jam_range_nm * ppn, Color(col, 0.55), 64)
					draw_string(_font, sp + Vector2(0.0, -s.jam_range_nm * ppn - 5.0), "EA REACH" if u.jamming() else "EA OFF", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(col, 0.8))
		var r := Detection.nominal_radar_ring_nm(u)
		if r <= 0.0:
			continue
		var air := 0.0
		for s in u.sensors:
			if s.kind == "radar":
				air = maxf(air, s.range_air_nm)
		if air > r + 1.0 and u.radar_emitting():
			_draw_dashed_circle(sp, air * ppn, Color(COL_RING, 0.35), 96)
			draw_string(_font, sp + Vector2(0.0, -air * ppn - 5.0), "AIR SEARCH %s nm" % Geo.format_nm(air), HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color(COL_RING, 0.7))
		if u.radar_emitting():
			draw_arc(sp, r * ppn, 0.0, TAU, 128, COL_RING, 1.0, true)
			_draw_sweep(sp, r * ppn)
		else:
			draw_arc(sp, r * ppn, 0.0, TAU, 128, COL_RING_SILENT, 1.0, true)
			draw_string(_font, sp + Vector2(0.0, -r * ppn - 5.0), "RADAR SILENT", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, COL_RING_SILENT)


## Convergence-zone annuli: where sound from a loud source comes back to the surface in deep
## water. Drawn as faint bands with the zone number, because a contact out there is heard in the
## ring, not between the rings.
func _draw_convergence_zones(sp: Vector2) -> void:
	for z: Dictionary in Acoustics.zones():
		var r: float = float(z["range_nm"]) * ppn
		var hw: float = float(z["half_width_nm"]) * ppn
		if r + hw < 8.0:
			continue
		var fade := 0.55 if int(z["index"]) == 1 else 0.35
		draw_arc(sp, r, 0.0, TAU, 128, Color(COL_SONAR_RING, 0.06 * fade * 2.0), maxf(hw * 2.0, 1.0), true)
		_draw_dashed_circle(sp, r - hw, Color(COL_SONAR_RING, 0.45 * fade), 96)
		_draw_dashed_circle(sp, r + hw, Color(COL_SONAR_RING, 0.45 * fade), 96)
		draw_string(_font, sp + Vector2(r * 0.7071 + 4.0, -r * 0.7071), "CZ%d" % int(z["index"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(COL_SONAR_RING, 0.8 * fade + 0.2))


## A rotating sweep with a fading wake, a reminder that the ship is on the air.
func _draw_sweep(c: Vector2, r: float) -> void:
	var a := fmod(_anim * 1.4, TAU)
	var steps := 18
	var pts := PackedVector2Array([c])
	var cols := PackedColorArray([Color(COL_RING, 0.20)])
	for i in steps + 1:
		var f := float(i) / float(steps)
		var ang := a - 0.7 + f * 0.7
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
		cols.append(Color(COL_RING, 0.0 + f * 0.14))
	draw_polygon(pts, cols)
	draw_line(c, c + Vector2(cos(a), sin(a)) * r, Color(COL_RING, 0.55), 1.0, true)


func _draw_dashed_circle(c: Vector2, r: float, col: Color, segs: int) -> void:
	for i in segs:
		if i % 2 == 1:
			continue
		var a0 := TAU * float(i) / segs
		var a1 := TAU * float(i + 1) / segs
		draw_arc(c, r, a0, a1, 4, col, 1.0, true)


func _draw_weapon_ring() -> void:
	if weapon_ring == null:
		return
	for u in _own_units():
		if not selected.has(u) or u.magazine_count(weapon_ring.id) <= 0:
			continue
		var sp := world_to_screen(u.position)
		var outer := weapon_ring.max_range_nm * ppn
		var inner := maxf(weapon_ring.min_range_nm, 0.0) * ppn
		if outer - inner > 2.0:
			draw_arc(sp, (outer + inner) * 0.5, 0.0, TAU, 160, Color(COL_WEAPON_RING, 0.07), outer - inner, false)
		draw_arc(sp, outer, 0.0, TAU, 160, COL_WEAPON_RING, 1.2, true)
		if weapon_ring.min_range_nm > 0.5:
			draw_arc(sp, inner, 0.0, TAU, 48, Color(COL_WEAPON_RING, 0.4), 1.0, true)
		# Keep the ring's name on the chart when its top edge runs off the top.
		var ring_label := sp + Vector2(0.0, maxf(-outer - 5.0, 16.0 - sp.y))
		draw_string(_font, ring_label, "%s  %s nm" % [weapon_ring.display_name.to_upper(), Geo.format_nm(weapon_ring.max_range_nm)], HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(COL_WEAPON_RING, 0.9))
		if selected_track != null and Combat.suits_track(weapon_ring, selected_track) and Combat.check_engagement(u, weapon_ring, selected_track)["ok"]:
			# The firing solution: where the round would meet the contact if it held course.
			var aim := Combat.intercept_point(u.position, weapon_ring.speed_kn, selected_track.position, selected_track.course_deg, selected_track.speed_kn, selected_track.has_kinematics)
			var ap := world_to_screen(aim)
			var check := Combat.check_engagement(u, weapon_ring, selected_track)
			var lcol := COL_WEAPON_RING if check["ok"] else Color(COL_HOSTILE, 0.7)
			draw_dashed_line(sp, ap, lcol, 1.0, 6.0)
			draw_arc(ap, 6.0, 0.0, TAU, 16, lcol, 1.0, true)
			draw_line(ap + Vector2(-9, 0), ap + Vector2(9, 0), lcol, 1.0)
			draw_line(ap + Vector2(0, -9), ap + Vector2(0, 9), lcol, 1.0)
			var tof := Combat.time_of_flight_s(weapon_ring, u.position.distance_to(aim))
			draw_string(_font, ap + Vector2(10, -8), "%s  %ds" % ["SOLUTION" if check["ok"] else str(check["reason"]), int(tof)], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, lcol)


## Buoys are cheap, numerous and easy to lose track of, so they are drawn plainly.
func _draw_sonobuoys() -> void:
	if aviation_manager == null:
		return
	for b: Sonobuoy in aviation_manager.sonobuoys:
		if b.faction != player_faction:
			continue
		var sp := world_to_screen(b.position)
		draw_circle(sp, 2.5, COL_BUOY)
		draw_arc(sp, 5.0, 0.0, TAU, 12, Color(COL_BUOY, 0.35), 1.0, true)


func _draw_truth() -> void:
	for u in unit_manager.units:
		if not u.is_engageable() or u.faction == player_faction:
			continue
		var sp := world_to_screen(u.position)
		var domain := "air" if u.airborne() else ("subsurface" if u.submerged() else u.spec.domain)
		MapSymbols.draw_symbol(self, sp, COL_TRUTH, MapSymbols.Frame.HOSTILE, domain, u.heading_deg, true, MapSymbols.category_glyph(u.spec.category, u.spec.domain), _font, 0.9, true)
		var r := Detection.nominal_radar_ring_nm(u)
		if r > 0.0 and u.radar_on:
			draw_arc(sp, r * ppn, 0.0, TAU, 96, Color(COL_TRUTH, 0.25), 1.0, true)
		draw_string(_font, sp + Vector2(12.0, 14.0), "TRUE %s %s" % [u.callsign, u.status_line()], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_TRUTH)
		if simulation != null:
			var ai := simulation.ai_state_for(u)
			if ai != "":
				draw_string(_font, sp + Vector2(12.0, 26.0), "AI %s  hp %.0f%%" % [ai, Damage.health_fraction(u) * 100.0], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_TRUTH)


func track_color(t: Track) -> Color:
	match t.identity:
		"HOSTILE":
			return COL_HOSTILE
		"NEUTRAL":
			return COL_NEUTRAL
		"FRIENDLY":
			return COL_FRIENDLY
	return COL_UNKNOWN


func _draw_tracks() -> void:
	var ref := reference_unit()
	for t: Track in _visible_tracks():
		var sp := world_to_screen(t.position)
		var col := track_color(t)
		var stale := t.status == Track.Status.STALE
		if stale:
			col.a = 0.55
		_draw_uncertainty(sp, t, col)
		if show_trails:
			_draw_track_history(t, col)
		if t.has_kinematics and not t.is_bearing_only() and t.speed_kn > 0.5 and (show_vectors or selected_track == t):
			_draw_motion_vector(t.position, t.course_deg, t.speed_kn, t.domain, col, true, selected_track == t)
		var glyph := ""
		if t.classification >= Track.Classification.CLASS_KNOWN:
			glyph = MapSymbols.category_glyph(t.known_category, t.domain)
		MapSymbols.draw_symbol(self, sp, col, MapSymbols.frame_for_identity(t.identity), t.domain, t.course_deg, t.has_kinematics, glyph, _font, 1.0, stale)
		if t.is_bearing_only():
			# A bearing line from the listener: this is all the contact really is.
			if ref != null:
				var lp := world_to_screen(ref.position)
				draw_dashed_line(lp, sp, Color(col, 0.35), 1.0, 6.0)
		if selected_track == t:
			MapSymbols.draw_selection(self, sp, COL_HOSTILE if t.identity == "HOSTILE" else COL_AMBER, _anim)
		if stale:
			draw_string(_font, sp + Vector2(10.0, -12.0), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(col, 0.9))
		var jammed := ref != null and ref.radar_emitting() and Detection.is_jammed_toward(ref, t.position)
		if jammed:
			draw_string(_font, sp + Vector2(-14.0, -14.0), "J", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_JAM)
		var text := t.label()
		var tags := PackedStringArray()
		if t.source == "sonar_cz": tags.append("CZ")
		if t.is_bearing_only(): tags.append("BRG")
		if not t.networked: tags.append("LOCAL")
		if stale: tags.append("STALE %s" % Track._fmt_age(t.age_s(SimClock.sim_time)))
		var sub := ""
		if ref != null:
			sub = "%s / %s" % [Geo.format_bearing(Geo.bearing_deg(ref.position, t.position)), "RNG ?" if t.is_bearing_only() else "~%s nm" % Geo.format_nm(Geo.distance_nm(ref.position, t.position))]
		if not tags.is_empty():
			sub += ("  " if sub != "" else "") + " · ".join(tags)
		_place_label(sp, text, col, selected_track == t, sub)


## Last few plots that built the track, fading with age: the console's own memory of the contact.
func _draw_track_history(t: Track, col: Color) -> void:
	var n := t.history_positions.size()
	if n < 2:
		return
	for i in n:
		var age := maxf(SimClock.sim_time - t.history_times[i], 0.0)
		var alpha := 0.42 * clampf(1.0 - age / 1440.0, 0.0, 1.0)
		if alpha < 0.02:
			continue
		var p := world_to_screen(t.history_positions[i])
		# Only join reports with continuous coverage. Do not draw a fictitious route
		# through the interval when the contact was missing.
		if i > 0 and t.history_times[i] - t.history_times[i - 1] <= Track.STALE_AFTER_S:
			draw_line(world_to_screen(t.history_positions[i - 1]), p, Color(col, alpha * 0.45), 1.0, true)
		draw_circle(p, 1.8 if selected_track == t else 1.2, Color(col, alpha))


## Uncertainty is an ellipse. For a passive sonar contact it is a long thin sliver lying along
## the bearing, which is the whole difference between hearing something and knowing where it is.
func _draw_uncertainty(sp: Vector2, t: Track, col: Color) -> void:
	var major := t.error_major_nm * ppn
	var minor := t.error_minor_nm * ppn
	if maxf(major, minor) <= MapSymbols.RADIUS + 3.0:
		return
	var ang := deg_to_rad(t.error_axis_deg)
	var axis := Vector2(sin(ang), -cos(ang))
	var perp := axis.orthogonal()
	var pts := PackedVector2Array()
	for i in 40:
		var th := TAU * float(i) / 40.0
		pts.append(sp + axis * (cos(th) * major) + perp * (sin(th) * minor))
	draw_colored_polygon(pts, Color(col, 0.05))
	pts.append(pts[0])
	draw_polyline(pts, Color(col, 0.55 if selected_track == t else 0.25), 1.5 if selected_track == t else 1.0, true)


func _draw_units() -> void:
	var zoomed_out := ppn < 0.7
	var own := _own_units()
	for u in own:
		var sp := world_to_screen(u.position)
		if show_trails and _trails.has(u):
			var arr: PackedVector2Array = _trails[u]
			for i in range(1, arr.size()):
				var f := float(i) / float(arr.size())
				draw_line(world_to_screen(arr[i - 1]), world_to_screen(arr[i]), Color(COL_FRIENDLY, 0.05 + 0.22 * f), 1.0, true)
		if not u.waypoints.is_empty():
			var prev := sp
			var prev_world := u.position
			var check_land := selected.has(u) and u.needs_sea_room() and not Terrain.is_empty()
			for wp in u.waypoints:
				var wsp := world_to_screen(wp)
				var hit := Terrain.first_land_contact(prev_world, wp) if check_land else -1.0
				if hit >= 0.0:
					# The leg is legal to order but the coast is in the way; show where.
					var beach := world_to_screen(prev_world.lerp(wp, hit))
					draw_dashed_line(prev, beach, COL_WAYPOINT, 1.0, 6.0)
					draw_dashed_line(beach, wsp, Color(COL_HOSTILE, 0.7), 1.0, 6.0)
					draw_line(beach - Vector2(4, 4), beach + Vector2(4, 4), COL_HOSTILE, 1.5)
					draw_line(beach - Vector2(4, -4), beach + Vector2(4, -4), COL_HOSTILE, 1.5)
				else:
					draw_dashed_line(prev, wsp, COL_WAYPOINT, 1.0, 6.0)
				var hovered := _mouse_inside and _drag_mode == DragMode.NONE and wsp.distance_to(_mouse) <= WAYPOINT_HIT_PX
				if hovered:
					draw_rect(Rect2(wsp - Vector2(5.5, 5.5), Vector2(11.0, 11.0)), COL_SELECT, false, 1.5)
				else:
					draw_rect(Rect2(wsp - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), COL_WAYPOINT, false, 1.0)
				prev = wsp
				prev_world = wp
		if u.in_formation():
			var station := world_to_screen(Formation.station_for(u))
			draw_dashed_line(sp, station, Color(COL_FRIENDLY, 0.3), 1.0, 3.0)
			draw_rect(Rect2(station - Vector2(2.5, 2.5), Vector2(5, 5)), Color(COL_FRIENDLY, 0.5), false, 1.0)
		if u.speed_kn > 0.05 and (show_vectors or selected.has(u)):
			_draw_motion_vector(u.position, u.heading_deg, u.speed_kn, u.spec.domain, COL_FRIENDLY, false, selected.size() == 1 and selected.has(u))
		var health := Damage.health_fraction(u)
		var ucol := COL_FRIENDLY.lerp(Color(1.0, 0.4, 0.3), 1.0 - health)
		var domain := "air" if u.airborne() else ("subsurface" if u.submerged() else u.spec.domain)
		if u.fire > 0.0:
			_draw_smoke(u, sp)
		if ppn >= 30.0:
			if u.spec.domain == "surface" and u.speed_kn > 1.0 and ppn > 160.0:
				_draw_wake(u, sp)
			_draw_silhouette(u, sp, ucol)
		MapSymbols.draw_symbol(self, sp, ucol, MapSymbols.Frame.FRIENDLY, domain, u.heading_deg, true, MapSymbols.category_glyph(u.spec.category, u.spec.domain), _font)
		if selected.has(u):
			MapSymbols.draw_selection(self, sp, COL_ACCENT, _anim)
		_draw_threat_marks(u, sp)
		_draw_status_lamps(u, sp)
		if zoomed_out and not selected.has(u):
			continue
		var name := u.callsign
		var sub := "%03d° · %d kn" % [int(u.heading_deg), int(u.speed_kn)]
		if u.is_submarine():
			sub += " · %.0f m" % u.depth_m
		elif u.is_aircraft():
			sub += " · FL%03d · fuel %d%%" % [int(u.altitude_m / 30.48), int(u.fuel_fraction() * 100.0)]
		if health < 0.99:
			sub += " · hull %d%%" % int(health * 100.0)
		if own.size() > 8 and not selected.has(u):
			sub = ""
		_place_label(sp, name, COL_TEXT if selected.has(u) else Color(COL_TEXT, 0.85), selected.has(u), sub)


## True motion: 5 minutes for aircraft, 30 for hulls, with explicit time ticks.
func _draw_motion_vector(pos: Vector2, course: float, speed: float, domain: String, col: Color, estimated: bool, labelled: bool) -> void:
	var minutes := 5.0 if domain == "air" else LEADER_MINUTES
	var start := world_to_screen(pos)
	var end := world_to_screen(pos + Geo.heading_to_vector(course) * speed * minutes / 60.0)
	if start.distance_to(end) < 12.0:
		return
	if estimated:
		draw_dashed_line(start, end, Color(col, 0.5), 1.0, 5.0)
	else:
		draw_line(start, end, Color(col, 0.5), 1.0, true)
	var side := (end - start).normalized().orthogonal() * 3.0
	var count := 5 if domain == "air" else 6
	for i in range(1, count + 1):
		var at := start.lerp(end, float(i) / count)
		draw_line(at - side, at + side, Color(col, 0.7), 1.0, true)
	if labelled:
		draw_string(_font, end + Vector2(6, -5), "+%dm%s" % [int(minutes), " EST" if estimated else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(col, 0.85))


func _solution_rect() -> Rect2:
	return Rect2(READOUT_MARGIN, READOUT_MARGIN, 320.0, READOUT_LINE_H * 4.0 + 8.0)


func _draw_relative_motion() -> void:
	if selected_track == null:
		return
	var ref := reference_unit()
	var solution := RelativeMotion.solution(ref, selected_track, SimClock.sim_time)
	if not solution.valid:
		return
	var own_end := world_to_screen(solution.own_position)
	var contact_end := world_to_screen(solution.contact_position)
	draw_dashed_line(world_to_screen(ref.position), own_end, Color(COL_ACCENT, 0.6), 1.5, 6.0)
	draw_dashed_line(world_to_screen(selected_track.position), contact_end, Color(COL_AMBER, 0.65), 1.5, 6.0)
	draw_line(own_end, contact_end, Color(COL_ACCENT, 0.85), 1.5, true)
	for endpoint in [own_end, contact_end]:
		draw_arc(endpoint, 5.0, 0.0, TAU, 24, COL_ACCENT, 1.4, true)
	var middle := own_end.lerp(contact_end, 0.5)
	var text := "CPA %.1f nm / %s" % [solution.distance_nm, Track._fmt_age(solution.time_s)]
	_shadow_text(middle + Vector2(4, -4), text, 11)


## The hooked contact's geometry from the reference unit, top-left, as plain readout lines.
func _draw_solution_card() -> void:
	if selected_track == null or show_key:
		return
	var t := selected_track
	var ref := reference_unit()
	var lines := PackedStringArray()
	lines.append("%s  %s" % [t.id, t.description()])
	lines.append(t.range_text_from(ref.position) if ref != null else "No reference ship")
	var solution := RelativeMotion.solution(ref, t, SimClock.sim_time)
	if solution.valid:
		lines.append("CPA %.1f nm in %s" % [solution.distance_nm, Track._fmt_age(solution.time_s)])
		lines.append("Closing %.0f kts  +/-%.1f nm" % [solution.closing_kn, solution.uncertainty_nm])
	else:
		lines.append(str(solution.reason))
	_draw_text_block(_solution_rect().position + Vector2(0.0, READOUT_FONT_SIZE), lines)


func _draw_wake(u: Unit, sp: Vector2) -> void:
	var h := Geo.heading_to_vector(u.heading_deg)
	var f := Vector2(h.x, -h.y)
	var side := f.orthogonal()
	var length := u.spec.length_m / 1852.0 * ppn
	var stern := sp - f * length * .47
	var wake_length := length * clampf(u.speed_kn / 18.0, .3, 1.5)
	for j in range(5):
		var t := float(j) / 5.0
		var alpha := .12 * (1.0 - t)
		for sign in [-1.0, 1.0]:
			draw_line(stern - f * wake_length * t + side * sign * length * .035, stern - f * wake_length + side * sign * length * (.17 + t*.06), Color(.68,.86,.91,alpha), 1.4, true)
	draw_line(stern, stern - f * wake_length * .8, Color(.64,.86,.9,.13), maxf(2, length*.04), true)


## Close in, the symbol sits on an oriented silhouette scaled to the hull's real length, so a
## carrier and a corvette stop looking the same size. The silhouette is the platform's rendered
## plan view from assets/platforms when one exists, tinted with the unit colour; the polygon
## below is the fallback for a platform without art.
func _draw_silhouette(u: Unit, sp: Vector2, col: Color) -> void:
	var length_px := maxf(u.spec.length_m / 1852.0 * ppn, 16.0)
	var dir := Geo.heading_to_vector(u.heading_deg)
	var f := Vector2(dir.x, -dir.y)
	var s := f.orthogonal()
	var plan: Texture2D = PlatformArt.plan(u.spec.id)
	if plan != null and length_px < MapSymbols.RADIUS * 2.2:
		return  # entirely under the symbol frame: nothing to see, nothing to draw
	if plan != null:
		if u.spec.domain == "land":
			# A base has no length in its spec; the render is 1,800 m across and drawn to scale.
			length_px = maxf(1800.0 / 1852.0 * ppn, 16.0)
		var scale := length_px * PlatformArt.PLAN_MARGIN / maxf(float(plan.get_width()), 1.0)
		var tex_size := Vector2(plan.get_size())
		var alpha := clampf((length_px - 12.0) / 30.0, 0.35, 0.9)
		draw_set_transform(sp, f.angle(), Vector2(scale, scale))
		draw_texture_rect(plan, Rect2(-tex_size * 0.5, tex_size), false, Color(1, 1, 1, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var pts := PackedVector2Array()
	if u.is_aircraft():
		var w := length_px * 0.9
		pts = PackedVector2Array([sp + f * length_px * 0.5, sp + f * length_px * 0.05 + s * w * 0.5, sp - f * length_px * 0.3 + s * w * 0.15, sp - f * length_px * 0.5 + s * w * 0.3, sp - f * length_px * 0.5 - s * w * 0.3, sp - f * length_px * 0.3 - s * w * 0.15, sp + f * length_px * 0.05 - s * w * 0.5])
	elif u.is_submarine():
		var w := length_px * 0.12
		pts = PackedVector2Array([sp + f * length_px * 0.5, sp + f * length_px * 0.35 + s * w, sp - f * length_px * 0.4 + s * w, sp - f * length_px * 0.5, sp - f * length_px * 0.4 - s * w, sp + f * length_px * 0.35 - s * w])
	else:
		var w := length_px * (0.16 if u.spec.category.contains("carrier") else 0.12)
		pts = PackedVector2Array([sp + f * length_px * 0.5, sp + f * length_px * 0.25 + s * w, sp - f * length_px * 0.5 + s * w * 0.8, sp - f * length_px * 0.5 - s * w * 0.8, sp + f * length_px * 0.25 - s * w])
	draw_colored_polygon(pts, Color(col, 0.18))
	pts.append(pts[0])
	draw_polyline(pts, Color(col, 0.6), 1.0, true)


## A row of small lamps under the symbol: emitting, on the link, weapons posture, damage,
## repair. Shape and colour, not text.
func _draw_status_lamps(u: Unit, sp: Vector2) -> void:
	var y := sp.y + MapSymbols.RADIUS + 9.0
	var x := sp.x - 10.0
	draw_circle(Vector2(x, y), 2.0, COL_BUOY if u.radar_emitting() else Color(0.35, 0.45, 0.5))
	x += 6.0
	if not u.datalink_connected():
		draw_line(Vector2(x - 2.0, y - 2.0), Vector2(x + 2.0, y + 2.0), COL_UNKNOWN, 1.5)
		draw_line(Vector2(x - 2.0, y + 2.0), Vector2(x + 2.0, y - 2.0), COL_UNKNOWN, 1.5)
	else:
		draw_circle(Vector2(x, y), 2.0, Color(COL_FRIENDLY, 0.8))
	x += 6.0
	match u.roe:
		Unit.Roe.HOLD:
			draw_rect(Rect2(x - 2.0, y - 2.0, 4.0, 4.0), COL_HOSTILE)
		Unit.Roe.TIGHT:
			draw_rect(Rect2(x - 2.0, y - 2.0, 4.0, 4.0), COL_AMBER)
		_:
			draw_rect(Rect2(x - 2.0, y - 2.0, 4.0, 4.0), Color(COL_NEUTRAL, 0.8))
	x += 6.0
	if u.active_sonar_emitting():
		draw_circle(Vector2(x, y), 2.0, COL_SONAR_ACTIVE)
		x += 6.0
	if Damage.repairing(u):
		var blink := 0.5 + 0.5 * sin(_anim * 6.0)
		draw_circle(Vector2(x, y), 2.0, Color(COL_AMBER, 0.4 + 0.6 * blink))
		x += 6.0
	if u.fire > 0.0:
		var flicker := 0.6 + 0.4 * sin(_anim * 11.0 + u.id)
		draw_colored_polygon(PackedVector2Array([Vector2(x, y - 3.0), Vector2(x + 2.5, y + 2.0), Vector2(x - 2.5, y + 2.0)]), Color(COL_FIRE, flicker))
		x += 6.0
	if u.flooding > 0.0:
		draw_rect(Rect2(x - 2.0, y - 1.0, 4.0, 3.0), COL_FLOOD)
		draw_line(Vector2(x - 2.5, y - 2.0), Vector2(x + 2.5, y - 2.0), Color(COL_FLOOD, 0.6), 1.0)


## A burning ship trails smoke downwind. Screen-space and procedural, so it reads at theatre zoom
## and needs no particle state: puffs march out along the wind and fade as they spread. The size
## of the plume says how bad the fire is.
func _draw_smoke(u: Unit, sp: Vector2) -> void:
	var wind_from := float(Detection.environment.get("wind_from_deg", DEFAULT_WIND_FROM_DEG))
	var downwind := Geo.heading_to_vector(wind_from + 180.0)
	var dir := Vector2(downwind.x, -downwind.y)  # screen y runs south
	var side := Vector2(-dir.y, dir.x)
	# Long enough to clear the ship's own label, which usually sits downwind of a westerly.
	var length := 150.0 * (0.55 + 0.45 * u.fire)
	var puffs := 22
	var drift := fmod(_anim * 0.35, 1.0)
	for i in puffs:
		var f := (float(i) + drift) / float(puffs)
		var wobble := sin(_anim * 0.9 + float(i) * 1.7 + u.id) * 3.0 * f
		var at := sp + dir * (6.0 + length * f) + side * wobble
		var r := 3.0 + 16.0 * f * (0.6 + 0.4 * u.fire)
		var a := 0.3 * pow(1.0 - f, 0.8) * (0.55 + 0.45 * u.fire)
		draw_circle(at, r * 1.7, Color(COL_SMOKE, a * 0.3))
		draw_circle(at, r, Color(COL_SMOKE, a))
	var glow := 0.5 + 0.5 * sin(_anim * 9.0 + u.id * 3.0)
	draw_circle(sp, MapSymbols.RADIUS + 3.0 + 2.0 * glow, Color(COL_FIRE, 0.10 + 0.15 * u.fire))


## Rounds detected inbound on this ship: a pulsing ring and a line back to the round.
func _draw_threat_marks(u: Unit, sp: Vector2) -> void:
	for entry: Dictionary in _threats:
		if entry["target"] != u:
			continue
		var w: Weapon = entry["weapon"]
		MapSymbols.draw_threat_ring(self, sp, COL_HOSTILE, _anim)
		var wp := world_to_screen(w.position)
		draw_line(wp, sp, Color(COL_HOSTILE, 0.35), 1.0, true)
		var mid := (wp + sp) * 0.5
		draw_string(_font, mid + Vector2(4.0, -4.0), "%ds" % int(entry["time_s"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_HOSTILE)


func _draw_weapons() -> void:
	if weapon_manager == null:
		return
	for w: Weapon in weapon_manager.in_flight:
		var own := w.faction == player_faction
		var detected := threat_manager != null and threat_manager.visible_to(reference_unit(), w) if reference_unit() != null else false
		if not own and not detected and not Debug.enabled:
			continue  # an undetected round is invisible, which is the whole problem
		var sp := world_to_screen(w.position)
		var col := COL_MISSILE if own else COL_MISSILE_HOSTILE
		if w.is_interceptor():
			col = COL_INTERCEPTOR
			if w.intercept_target != null:
				draw_line(sp, world_to_screen(w.intercept_target.position), Color(col, 0.3), 1.0, true)
		elif own and w.target_track != null and w.phase == Weapon.Phase.CRUISE:
			draw_dashed_line(sp, world_to_screen(w.aim_point), Color(col, 0.3), 1.0, 5.0)
		if not own and detected and not w.is_interceptor():
			draw_arc(sp, 10.0, 0.0, TAU, 20, Color(col, 0.55), 1.0, true)
		if _weapon_trails.has(w.id):
			var arr: PackedVector2Array = _weapon_trails[w.id]
			for i in range(1, arr.size()):
				var f := float(i) / float(arr.size())
				draw_line(world_to_screen(arr[i - 1]), world_to_screen(arr[i]), Color(col, 0.05 + 0.45 * f), 1.5 if f > 0.6 else 1.0, true)
		_draw_weapon_sprite(w, sp, col)
		if w.spec.profile == "ballistic" and not w.is_interceptor():
			draw_string(_font, sp + Vector2(8.0, -6.0), "BM", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)
		if Debug.enabled:
			draw_dashed_line(sp, world_to_screen(w.aim_point), Color(col, 0.4), 1.0, 5.0)


func _draw_weapon_sprite(w: Weapon, sp: Vector2, col: Color) -> void:
	var direction := Geo.heading_to_vector(w.heading_deg)
	var forward := Vector2(direction.x, -direction.y)
	var side := forward.orthogonal()
	var torpedo := w.spec.is_torpedo()
	var radius := 6.0 if torpedo else 7.0
	if not torpedo:
		# Layered exhaust is a visual treatment for a detected weapon, never a new detection.
		for j in range(3, 0, -1):
			draw_line(sp - forward * 4, sp - forward * (13 + j * 5), Color(col, .055 * (4 - j)), j * 2.3, true)
		draw_line(sp - forward * 4, sp - forward * 15, Color("ffe6b0"), 1.8, true)
	else:
		draw_arc(sp - forward * 5, 6, forward.angle() + 1.3, forward.angle() + 5.0, 16, Color(col, .3), 1, true)
	var body := PackedVector2Array([sp + forward * radius, sp + side * 1.6, sp - forward * radius + side * 1.4, sp - forward * radius - side * 1.4, sp - side * 1.6])
	draw_colored_polygon(body, Color("e1eced"))
	for sign in [-1.0, 1.0]:
		var fin := PackedVector2Array([sp - forward * 2, sp - forward * 6 + side * 4 * sign, sp - forward * 6])
		draw_colored_polygon(fin, col)
	draw_circle(sp, 1.3, col)


func _draw_effects() -> void:
	for i in range(_effects.size() - 1, -1, -1):
		var e: Dictionary = _effects[i]
		var age: float = _anim - float(e["t0"])
		if age > EFFECT_LIFE_S:
			_effects.remove_at(i)
			continue
		var f := age / EFFECT_LIFE_S
		var sp := world_to_screen(e["pos"])
		var col: Color = e["color"]
		var kind: String = e["kind"]
		match kind:
			"hit", "destroyed":
				draw_circle(sp, 4.0 + 26.0 * f, Color(col, 0.35 * (1.0 - f)))
				draw_arc(sp, 6.0 + 40.0 * f, 0.0, TAU, 32, Color(col, 0.8 * (1.0 - f)), 2.0, true)
				if kind == "destroyed":
					draw_arc(sp, 10.0 + 60.0 * f, 0.0, TAU, 32, Color(col, 0.5 * (1.0 - f)), 1.0, true)
			"intercept", "decoy":
				draw_arc(sp, 3.0 + 22.0 * f, 0.0, TAU, 24, Color(col, 0.9 * (1.0 - f)), 1.5, true)
				for k in 6:
					var a := TAU * k / 6.0 + f
					draw_line(sp + Vector2(cos(a), sin(a)) * (4.0 + 10.0 * f), sp + Vector2(cos(a), sin(a)) * (8.0 + 18.0 * f), Color(col, 0.7 * (1.0 - f)), 1.0)
			"launch":
				draw_arc(sp, 4.0 + 14.0 * f, 0.0, TAU, 20, Color(col, 0.6 * (1.0 - f)), 1.0, true)
			"refused":
				var r := 16.0 - 8.0 * f
				var a := Color(col, 0.9 * (1.0 - f))
				draw_arc(sp, r, 0.0, TAU, 24, a, 1.5, true)
				draw_line(sp + Vector2(-r, -r) * 0.6, sp + Vector2(r, r) * 0.6, a, 1.5)
				draw_line(sp + Vector2(-r, r) * 0.6, sp + Vector2(r, -r) * 0.6, a, 1.5)
			_:
				draw_arc(sp, 3.0 + 14.0 * f, 0.0, TAU, 20, Color(col, 0.5 * (1.0 - f)), 1.0, true)


# --- Readouts and radio line --------------------------------------------------------------

## The chart's text face: the theme's boldest data font.
func _readout_font() -> Font:
	return UITheme.semibold_font()


## White bold text with a 1 px black drop shadow and no plate, the chart's only text style.
func _shadow_text(at: Vector2, text: String, font_size: int, col := COL_READOUT, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var font := _readout_font()
	draw_string(font, at + Vector2(1.0, 1.0), text, align, width, font_size, Color(COL_READOUT_SHADOW, COL_READOUT_SHADOW.a * col.a))
	draw_string(font, at, text, align, width, font_size, col)


func _draw_text_block(first_baseline: Vector2, lines: PackedStringArray, col := COL_READOUT) -> void:
	for i in lines.size():
		_shadow_text(first_baseline + Vector2(0.0, i * READOUT_LINE_H), lines[i], READOUT_FONT_SIZE, col)


## Where the bottom-left readout sits, so labels can keep clear of it.
func _readout_rect() -> Rect2:
	var h := READOUT_LINE_H * 4.0 + READOUT_MARGIN
	return Rect2(Vector2(0.0, size.y - h), Vector2(READOUT_MARGIN + 170.0, h))


## The world point the readout describes: the cursor over the chart, otherwise the chart's centre.
func _readout_point() -> Vector2:
	if _mouse_inside and Rect2(Vector2.ZERO, size).has_point(_mouse):
		return screen_to_world(_mouse)
	return screen_to_world(size * 0.5)


## Bottom-left: "DD-MM N / DDD-MM E", "Depth: 1,014 ft" or "Height: 337 ft", then the scale bar
## with its length in nmi under it. Always on (the chart's centre when the cursor is elsewhere).
func _draw_readout() -> void:
	var x := READOUT_MARGIN
	var baseline := size.y - READOUT_MARGIN - 2.0
	if show_scale:
		var nm := ChartReadout.scale_step_nm(ppn)
		var px := roundf(nm * ppn)
		_shadow_text(Vector2(x, baseline), ChartReadout.format_nmi(nm), READOUT_FONT_SIZE)
		var bar_y := roundf(baseline - READOUT_FONT_SIZE - 3.0) + 0.5
		for pass_i in 2:
			var o := Vector2(1.0, 1.0) if pass_i == 0 else Vector2.ZERO
			var col := COL_READOUT_SHADOW if pass_i == 0 else COL_READOUT
			draw_line(Vector2(x, bar_y) + o, Vector2(x + px, bar_y) + o, col, 1.0)
			draw_line(Vector2(x + 0.5, bar_y - 5.0) + o, Vector2(x + 0.5, bar_y) + o, col, 1.0)
			draw_line(Vector2(x + px - 0.5, bar_y - 5.0) + o, Vector2(x + px - 0.5, bar_y) + o, col, 1.0)
		baseline = bar_y - 10.0
	if not show_latlon:
		return
	var w := _readout_point()
	var line := _depth_readout(w)
	if line != "":
		_shadow_text(Vector2(x, baseline), line, READOUT_FONT_SIZE)
		baseline -= READOUT_LINE_H
	var m := _geo_map()
	var position := ChartReadout.format_offset(w)
	if m.has("anchor_lat"):
		var ll := Geo.world_to_latlon(w, float(m["anchor_lat"]), float(m["anchor_lon"]))
		position = ChartReadout.format_position(ll.x, ll.y)
	_shadow_text(Vector2(x, baseline), position, READOUT_FONT_SIZE)


## Depth over water, height over land, from the chart's rasters. Inside the charted box the
## scenario's coastline says which is which; beyond it the raster's own coast does.
func _depth_readout(w: Vector2) -> String:
	var land := not Terrain.is_empty() and Terrain.is_land(w)
	var depth := Bathymetry.depth_at(w)
	if not land and Bathymetry.active:
		var charted := _floor.charted_rect() if _floor != null else Rect2()
		land = not charted.has_point(w) and depth >= 0.0 and depth < 0.5
	var height := ChartRelief.height_at(w) if land else -1.0
	if land and height < 0.0 and not Bathymetry.active:
		return ""
	return ChartReadout.depth_line(land, maxf(height, 0.0), depth)


func _radio_rect() -> Rect2:
	var h := READOUT_LINE_H * RadioLine.MAX_LINES + RADIO_BOTTOM_PX
	return Rect2(Vector2(size.x * 0.25, size.y - h), Vector2(size.x * 0.5, h))


## Bottom-centre: the newest radio lines, the latest at the bottom, each fading after its hold.
func _draw_radio_line() -> void:
	var lines := _radio.visible(_anim)
	var baseline := size.y - RADIO_BOTTOM_PX - 3.0
	for i in range(lines.size() - 1, -1, -1):
		var e: Dictionary = lines[i]
		var alpha := RadioLine.alpha_at(_anim - float(e["t0"]))
		var col := COL_RADIO_ALERT if e["severity"] == "alert" else COL_READOUT
		_shadow_text(Vector2(0.0, baseline), e["text"], READOUT_FONT_SIZE, Color(col, alpha), HORIZONTAL_ALIGNMENT_CENTER, size.x)
		baseline -= READOUT_LINE_H


## A white circle round each platform whose message is on the radio line: it is transmitting.
## Only symbols the chart draws anyway: an own unit on the board, or a contact the plot holds.
func _draw_speaker_rings() -> void:
	var speakers := _radio.speakers(_anim)
	if speakers.is_empty():
		return
	var own := _own_units()
	var tracks := _visible_tracks()
	for s in speakers:
		var at := Vector2.INF
		if s is Unit and (s as Unit).alive and own.has(s):
			at = world_to_screen((s as Unit).position)
		elif s is Track and tracks.has(s):
			at = world_to_screen((s as Track).position)
		if at != Vector2.INF:
			draw_arc(at, SPEAKER_RING_PX, 0.0, TAU, 40, COL_READOUT, 1.5, true)


## Labels: a dark pill with an identity bar, a primary line and an optional secondary line, placed
## where it does not collide with another label. Leader line back to the symbol.
func _place_label(sp: Vector2, text: String, color: Color, important: bool, sub: String) -> void:
	if not Rect2(Vector2.ZERO, size).has_point(sp):
		return
	var w1 := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var w2 := _font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x if sub != "" else 0.0
	var width := minf(maxf(w1, w2) + 18.0, 260.0)
	var height := 21.0 if sub == "" else 33.0
	for attempt in 18:
		var row := (attempt + 1) / 2
		var offset := Vector2(20, -12 + row * (height + 4) * (1 if attempt % 2 == 0 else -1))
		var r := Rect2(sp + offset, Vector2(width, height))
		if r.end.x > size.x - 12:
			r.position.x = sp.x - width - 22
		if r.position.y < 4.0 or r.end.y > size.y - 4.0 or r.end.x > size.x - 12.0:
			continue
		var overlaps := false
		for used in _label_rects:
			if used.grow(3).intersects(r):
				overlaps = true
				break
		if overlaps:
			continue
		_label_rects.append(r)
		draw_line(sp, Vector2(r.position.x if r.position.x > sp.x else r.end.x, r.get_center().y), Color(color, 0.3), 1.0, true)
		draw_rect(r, COL_LABEL_BG)
		draw_rect(Rect2(r.position, Vector2(2.0, height)), Color(color, 0.9))
		if important:
			draw_rect(r, Color(color, 0.55), false, 1.0)
		draw_string(_font, r.position + Vector2(9, 15), text, HORIZONTAL_ALIGNMENT_LEFT, int(width - 12), 12, color)
		if sub != "":
			draw_string(_font, r.position + Vector2(9, 28), sub, HORIZONTAL_ALIGNMENT_LEFT, int(width - 12), 10, Color(color, 0.7))
		return


## F2: the symbol key, top-left, in the chart's plain white readout style with no card behind it.
func _draw_key() -> void:
	if not show_key:
		return
	var rect := _symbol_key_rect()
	var x := rect.position.x
	var y := rect.position.y
	_shadow_text(Vector2(x, y + 12), "SYMBOL KEY  (F2 hides)", 11)
	var cx := x + 14.0
	var cy := y + 36.0
	MapSymbols.draw_key_entry(self, Vector2(cx, cy), COL_FRIENDLY, MapSymbols.Frame.FRIENDLY, "surface", "DD", "Friendly", _font, COL_READOUT)
	MapSymbols.draw_key_entry(self, Vector2(cx + 110, cy), COL_HOSTILE, MapSymbols.Frame.HOSTILE, "surface", "", "Hostile", _font, COL_READOUT)
	MapSymbols.draw_key_entry(self, Vector2(cx + 215, cy), COL_UNKNOWN, MapSymbols.Frame.UNKNOWN, "surface", "", "Unknown", _font, COL_READOUT)
	cy += 30.0
	MapSymbols.draw_key_entry(self, Vector2(cx, cy), COL_FRIENDLY, MapSymbols.Frame.FRIENDLY, "air", "F", "Air", _font, COL_READOUT)
	MapSymbols.draw_key_entry(self, Vector2(cx + 110, cy), COL_FRIENDLY, MapSymbols.Frame.FRIENDLY, "subsurface", "SN", "Subsurface", _font, COL_READOUT)
	MapSymbols.draw_key_entry(self, Vector2(cx + 215, cy), COL_NEUTRAL, MapSymbols.Frame.NEUTRAL, "surface", "M", "Neutral", _font, COL_READOUT)
	var lines := PackedStringArray([
		"Glyph: CV carrier, CG cruiser, DD, FF, SS/SN sub, F fighter, E AEW",
		"Ellipse: uncertainty. Vectors: 30 min. Dots: history",
		"Rings: radar, sonar, ESM, jammer, weapon range",
		"Lamps: radiating, link, weapons posture, pinging, repairing",
		"Land: tinted by height, relief shading on F6. Masks radar",
		"Sea: lighter is shallower, bands at 20 m to 4,000 m",
		"Ctrl+right-click a contact: engage. Right-click a waypoint: drop it",
		"Double-click: recentre. Home: fit fleet. C: centre. +/-: zoom",
	])
	cy += 26.0
	for line in lines:
		_shadow_text(Vector2(x, cy), line, 11, Color(COL_READOUT, 0.9))
		cy += 15.0


func _symbol_key_rect() -> Rect2:
	# Top-left, clear of the bottom-left readout. Fitted content keeps out of it while it shows.
	return Rect2(12.0, 12.0, 390.0, 206.0)


## Hovering over a symbol shows what the console knows about it, without a click: plain readout
## lines beside the cursor, no card.
func _draw_hover_card() -> void:
	if not _mouse_inside or _drag_mode != DragMode.NONE:
		return
	var wp := _waypoint_at(_mouse)
	if not wp.is_empty():
		var wu: Unit = wp["unit"]
		var lines := PackedStringArray()
		lines.append("%s waypoint %d/%d" % [wu.callsign, int(wp["index"]) + 1, wu.waypoints.size()])
		lines.append("Right-click to remove this leg")
		_draw_card(lines)
		return
	var lines := PackedStringArray()
	var u := _unit_at(_mouse)
	if u != null:
		lines.append(u.callsign)
		lines.append(u.spec.display_name)
		lines.append("%s  ·  %s" % [Damage.condition_text(u), Damage.damage_report(u)])
		lines.append(u.status_line())
		_draw_card(lines)
		return
	var t := _track_at(_mouse)
	if t == null:
		var lw := screen_to_world(_mouse)
		var l := Terrain.land_at(lw) if not Terrain.is_empty() else null
		if l == null:
			return
		lines.append(l.name if l.name != "" else "Land")
		lines.append("Masks radar, ESM and sonar")
		lines.append("Masking height %d m (game estimate)" % int(l.elevation_m))
		_draw_card(lines)
		return
	lines.append("%s  %s" % [t.id, t.description()])
	lines.append("%s · %s · %s" % [t.identity, t.status_text(SimClock.sim_time), t.source.to_upper().replace("_", " ")])
	if t.has_kinematics:
		lines.append("CSE %s  SPD %.0f kts (est)" % [Geo.format_bearing(t.course_deg), t.speed_kn])
	else:
		lines.append("Kinematics estimating")
	lines.append("+/-%.1f nm  ·  observed %s" % [t.position_error_nm, Track._fmt_age(t.observation_time_s)])
	_draw_card(lines)


## Hover text beside the cursor, flipped to stay on the chart.
func _draw_card(lines: PackedStringArray) -> void:
	var font := _readout_font()
	var width := 0.0
	for l in lines:
		width = maxf(width, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)
	var height := lines.size() * 15.0
	var pos := _mouse + Vector2(18.0, 16.0)
	if pos.x + width > size.x - 4.0:
		pos.x = _mouse.x - width - 12.0
	if pos.y + height > size.y - 4.0:
		pos.y = _mouse.y - height - 10.0
	for i in lines.size():
		_shadow_text(pos + Vector2(0.0, 12.0 + i * 15.0), lines[i], 12)
