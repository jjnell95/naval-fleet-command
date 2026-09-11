class_name TacticalMap
extends Control
## Tactical map display. Renders the nautical-mile world into pixels and turns mouse input into
## selection changes and order requests. Frame-based; contains no simulation logic.
## Own units are drawn from ground truth; other factions are drawn ONLY as Tracks
## (except under Debug.enabled, which overlays true positions).
##
## Controls: wheel or +/- = zoom at cursor, middle/right drag = pan, left click = select
## unit/track, shift+click = add/remove unit, left drag = box select, double-click a unit or
## track = recentre on it without changing zoom, right click water = move order (shift = append),
## right click a track = select it as target (ctrl/cmd = also engage with the selected weapon),
## right click a waypoint marker = drop that one leg from the route, arrow keys / WASD = pan,
## Home = fit the whole fleet in view, C = recentre on the current selection.

signal selection_changed(units: Array)
signal track_selected(track: Track)
signal move_order_requested(world_pos: Vector2, append: bool)
signal engage_requested(track: Track)
signal waypoint_delete_requested(unit: Unit, index: int)

enum DragMode { NONE, PAN, BOX }

const MIN_PPN := 0.2
const MAX_PPN := 6000.0
const ZOOM_STEP := 1.25
const KEYBOARD_ZOOM_RATE := 4.0
const CLICK_RADIUS_PX := 14.0
const WAYPOINT_HIT_PX := 9.0
const DRAG_THRESHOLD_PX := 5.0
const DOUBLE_CLICK_MS := 350
const LEADER_MINUTES := 30.0
const KEY_PAN_PX_PER_S := 700.0
const HEADER_H := 36.0
const TRAIL_INTERVAL_S := 60.0
const TRAIL_LENGTH := 24
const EFFECT_LIFE_S := 2.2
const NICE_STEPS_NM: Array[float] = [0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0, 1000.0]

const COL_OCEAN := Color(0.024, 0.055, 0.086)
const COL_OCEAN_TOP := Color(0.034, 0.090, 0.125)
const COL_OCEAN_BOTTOM := Color(0.019, 0.048, 0.080)
# Land is a chart tint, not a photograph: a shade above the water in luminance, pulled off the
# blue so it separates without ever competing with a contact symbol drawn on top of it.
const COL_LAND := Color(0.10, 0.14, 0.15)
const COL_LAND_HIGH := Color(0.16, 0.21, 0.20)
const COL_COAST := Color(0.42, 0.62, 0.66, 0.85)
const COL_SHELF := Color(0.20, 0.45, 0.52, 0.11)
const COL_LAND_LABEL := Color(0.55, 0.68, 0.66, 0.75)
const LAND_HIGH_ELEVATION_M := 600.0  # elevation at which the interior reaches its lightest tint
const SHELF_NM := 2.5  # width of the shallow-water band drawn outside the coast
const COAST_MIN_STEP_PX := 1.2  # coastline detail finer than this is dropped as it is invisible
const LAND_LABEL_MIN_PX := 90.0
const COL_GRID := Color(0.20, 0.42, 0.55, 0.11)
const COL_GRID_MINOR := Color(0.20, 0.42, 0.55, 0.045)
const COL_GRID_TEXT := Color(0.35, 0.60, 0.72, 0.8)
const COL_RINGS := Color(0.24, 0.56, 0.65, 0.16)
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
const COL_HEADER := Color("0c1c29")
const COL_ACCENT := Color("70e2d3")
const COL_AMBER := Color("ffbe77")
const COL_LABEL_BG := Color("0b1a26", 0.92)

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
var show_terrain := true

var _drag_mode := DragMode.NONE
var _drag_button := MOUSE_BUTTON_NONE
var _drag_start := Vector2.ZERO
var _drag_moved := false
var _mouse := Vector2.ZERO
var _mouse_inside := false
var _last_click_ms: int = -1000000
var _last_click_pos := Vector2.ZERO
var show_vectors := false
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
var _water: ImageTexture
var _weapon_trails: Dictionary = {}  # weapon id -> PackedVector2Array of recent positions
var _hit_flash := 0.0
var _land_shelves: Dictionary = {}  # Landmass -> Array[PackedVector2Array], the shallow-water band
var _land_generation := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true
	_font = UITheme.body_font()
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_water = _build_water()
	mouse_entered.connect(func() -> void: _mouse_inside = true)
	mouse_exited.connect(func() -> void: _mouse_inside = false)
	resized.connect(_apply_pending_fit)
	_build_plot_controls()


func _build_plot_controls() -> void:
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	h.position = Vector2(14, -55)
	h.add_theme_constant_override("separation", 4)
	add_child(h)
	for item in [["−", "zoom_out"], ["+", "zoom_in"], ["FIT FLEET", "fleet"], ["CENTER", "center"],  ["SENSORS", "sensors"], ["VECTORS", "vectors"]]:
		var button := Button.new()
		button.text = item[0]
		button.add_theme_font_size_override("font_size", 10)
		button.custom_minimum_size.y = 28
		button.focus_mode = Control.FOCUS_NONE
		if item[1] in ["sensors", "vectors"]:
			button.toggle_mode = true
		button.pressed.connect(_plot_action.bind(item[1]))
		h.add_child(button)


func _plot_action(action: String) -> void:
	match action:
		"zoom_out":
			_zoom_at(size * .5, 1.0 / ZOOM_STEP)
		"zoom_in":
			_zoom_at(size * .5, ZOOM_STEP)
		"fleet":
			fit_to_fleet()
		"center":
			center_on_selection()
		"sensors":
			show_rings = not show_rings
		"vectors":
			show_vectors = not show_vectors


func _process(delta: float) -> void:
	_anim += delta
	if selected_track != null and not selected_track.visible_to(reference_unit()):
		select_track(null)
	_hit_flash = maxf(_hit_flash - delta, 0.0)
	_keyboard_pan(delta)
	_keyboard_zoom(delta)
	_prune_selection()
	_record_trails()
	_record_weapon_trails()
	queue_redraw()


## A seamless noise tile, generated once, gives the water a slow living texture without a
## single asset. Tiled and scrolled at draw time.
func _build_water() -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = 7
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.1
	var img := noise.get_seamless_image(256, 256)
	return ImageTexture.create_from_image(img)


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
	_land_shelves.clear()
	_land_generation = -1
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


func fit_to(center: Vector2, extent_nm: float) -> void:
	_fit_center = center
	_fit_extent = extent_nm
	_pending_fit = true
	_apply_pending_fit()


func _apply_pending_fit() -> void:
	if not _pending_fit or size.x <= 0.0 or size.y <= 0.0:
		return
	_pending_fit = false
	center_nm = _fit_center
	ppn = clampf(minf(size.x, size.y) / maxf(_fit_extent, 1.0), MIN_PPN, MAX_PPN)


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var anchor := screen_to_world(screen_pos)
	ppn = clampf(ppn * factor, MIN_PPN, MAX_PPN)
	center_nm = Vector2(anchor.x - (screen_pos.x - size.x * 0.5) / ppn, anchor.y + (screen_pos.y - size.y * 0.5) / ppn)


## Recentres the view on a point without touching zoom. Used to snap back to a unit or track
## the player has lost track of on a spread-out picture, without re-fitting the whole scale.
func center_on(world_pos: Vector2) -> void:
	center_nm = world_pos


## Recentres on the current selection (or the selected track, lacking a unit selection), holding
## zoom steady. Bound to C so the picture can be re-found after panning away.
func center_on_selection() -> void:
	if selected.is_empty():
		if selected_track != null:
			center_on(selected_track.position)
		else:
			fit_to_fleet()
		return
	var sum := Vector2.ZERO
	for u in selected:
		sum += u.position
	center_on(sum / selected.size())


## Fits the whole own-force to the view, the way the scenario's initial picture does. Recovers
## the display after the fleet has spread out or the view has been panned away from it.
func fit_to_fleet() -> void:
	var own := _own_units()
	if own.is_empty():
		return
	var lo := own[0].position
	var hi := own[0].position
	for u in own:
		lo.x = minf(lo.x, u.position.x)
		lo.y = minf(lo.y, u.position.y)
		hi.x = maxf(hi.x, u.position.x)
		hi.y = maxf(hi.y, u.position.y)
	fit_to((lo + hi) * 0.5, maxf(hi.x - lo.x, hi.y - lo.y) * 1.3 + 6.0)


func _keyboard_pan(delta: float) -> void:
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
		center_nm += dir * KEY_PAN_PX_PER_S * delta / ppn


## +/- (and the numpad equivalents) zoom on the screen centre, for a wheel-free way to work the
## scale — smooth and continuous while held, matching the feel of the wheel step.
func _keyboard_zoom(delta: float) -> void:
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
		_handle_mouse_button(event)
		accept_event()
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _handle_mouse_button(e: InputEventMouseButton) -> void:
	_mouse = e.position
	match e.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if e.pressed:
				_zoom_at(e.position, ZOOM_STEP)
		MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				_zoom_at(e.position, 1.0 / ZOOM_STEP)
		MOUSE_BUTTON_LEFT:
			if e.pressed:
				grab_focus()
				_begin_drag(DragMode.BOX, e)
			elif _drag_button == MOUSE_BUTTON_LEFT:
				if _drag_moved:
					_box_select(Rect2(_drag_start, e.position - _drag_start).abs(), e.shift_pressed)
				else:
					_click_select(e.position, e.shift_pressed)
					_check_double_click(e.position)
				_end_drag()
		MOUSE_BUTTON_MIDDLE:
			if e.pressed:
				_begin_drag(DragMode.PAN, e)
			elif _drag_button == MOUSE_BUTTON_MIDDLE:
				_end_drag()
		MOUSE_BUTTON_RIGHT:
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
						else:
							move_order_requested.emit(screen_to_world(e.position), e.shift_pressed)
				_end_drag()


func _handle_mouse_motion(e: InputEventMouseMotion) -> void:
	_mouse = e.position
	if _drag_mode == DragMode.NONE:
		return
	if not _drag_moved and e.position.distance_to(_drag_start) > DRAG_THRESHOLD_PX:
		_drag_moved = true
	if _drag_mode == DragMode.PAN and _drag_moved:
		center_nm -= Vector2(e.relative.x, -e.relative.y) / ppn


func _begin_drag(mode: DragMode, e: InputEventMouseButton) -> void:
	if _drag_mode != DragMode.NONE:
		return
	_drag_mode = mode
	_drag_button = e.button_index
	_drag_start = e.position
	_drag_moved = false


func _end_drag() -> void:
	_drag_mode = DragMode.NONE
	_drag_button = MOUSE_BUTTON_NONE
	_drag_moved = false


# --- Selection --------------------------------------------------------------------------

## Own units that are actually on the board. An aircraft in a hangar is not drawn, not clickable
## and not box-selectable; it is reached through the ship that carries it.
func _own_units() -> Array[Unit]:
	if unit_manager == null:
		return []
	var out: Array[Unit] = []
	for u in unit_manager.get_faction_units(player_faction):
		if u.is_aircraft() and not u.airborne():
			continue
		out.append(u)
	return out


func _visible_tracks() -> Array:
	if track_manager == null:
		return []
	var ref := reference_unit()
	return track_manager.tracks_for(ref) if ref != null else track_manager.get_tracks(player_faction)


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
	selection_changed.emit(selected)


func _box_select(rect: Rect2, additive: bool) -> void:
	if not additive:
		selected.clear()
	for u in _own_units():
		if rect.has_point(world_to_screen(u.position)) and not selected.has(u):
			selected.append(u)
	selection_changed.emit(selected)


func select_units(units: Array) -> void:
	selected.clear()
	for u in units:
		selected.append(u)
	selection_changed.emit(selected)


func select_track(t: Track) -> void:
	if t == selected_track:
		return
	selected_track = t
	track_selected.emit(t)


func clear_selection() -> void:
	select_track(null)
	if selected.is_empty():
		return
	selected.clear()
	selection_changed.emit(selected)


func _prune_selection() -> void:
	if selected_track != null and selected_track.status == Track.Status.LOST:
		select_track(null)
	var before := selected.size()
	selected = selected.filter(func(u: Unit) -> bool: return u.alive)
	if selected.size() != before:
		selection_changed.emit(selected)


## The unit the display is centred on for bearings and range rings: the selection, otherwise
## the first surface ship the player owns.
func reference_unit() -> Unit:
	if selected.size() >= 1:
		return selected[0]
	for u in _own_units():
		if not u.is_aircraft():
			return u
	var own := _own_units()
	return own[0] if not own.is_empty() else null


# --- Drawing ----------------------------------------------------------------------------

func _draw() -> void:
	_label_rects.clear()
	_threats = AirDefence.inbound_threats(unit_manager, threat_manager, player_faction, reference_unit()) if unit_manager != null and threat_manager != null else []
	_draw_ocean()
	_draw_land()
	_draw_vignette()
	_draw_grid()
	_draw_range_rings()
	_draw_compass()
	_draw_objectives()
	if unit_manager != null:
		if show_rings:
			_draw_sensor_rings()
		_draw_weapon_ring()
		if Debug.enabled:
			_draw_truth()
		_draw_sonobuoys()
		_draw_tracks()
		_draw_units()
		_draw_weapons()
		_draw_effects()
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
	_draw_header()
	_draw_scale_bar()
	_draw_readout()
	_draw_key()
	_draw_hover_card()


func _nice_step(min_px: float) -> float:
	for s in NICE_STEPS_NM:
		if s * ppn >= min_px:
			return s
	return NICE_STEPS_NM[-1]


## Deep water: a vertical gradient with a darker rim so the picture reads as a scope, not a
## flat rectangle.
func _draw_ocean() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_OCEAN)
	var pts := PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	var cols := PackedColorArray([COL_OCEAN_TOP, COL_OCEAN_TOP, COL_OCEAN_BOTTOM, COL_OCEAN_BOTTOM])
	draw_polygon(pts, cols)
	if _water != null:
		# Two layers drifting against each other, scaled with the zoom so the texture reads as
		# surface rather than wallpaper. A rough sea shows more of it.
		var strength := 0.045 + 0.004 * Detection.sea_state
		var scale := clampf(ppn * 0.5, 0.6, 3.0)
		var tile := 256.0 * scale
		var off1 := Vector2(fmod(_anim * 4.0 + center_nm.x * ppn, tile), fmod(_anim * 2.5 - center_nm.y * ppn, tile))
		var off2 := Vector2(fmod(-_anim * 3.0 + center_nm.x * ppn * 0.7, tile), fmod(_anim * 1.5 - center_nm.y * ppn * 0.7, tile))
		draw_texture_rect(_water, Rect2(-off1 - Vector2(tile, tile), size + Vector2(tile * 2.0, tile * 2.0)), true, Color(0.35, 0.75, 1.0, strength))
		draw_texture_rect(_water, Rect2(-off2 - Vector2(tile, tile), size + Vector2(tile * 2.0, tile * 2.0)), true, Color(0.2, 0.55, 0.8, strength * 0.7))


## The scope's darkened rim. Drawn after the land so a coast at the edge of the picture falls away
## into it the way the water does.
func _draw_vignette() -> void:
	var rim := Color(0.0, 0.0, 0.0, 0.0)
	var edge := Color(0.0, 0.01, 0.03, 0.55)
	var w := minf(size.x * 0.22, 260.0)
	var h := minf(size.y * 0.22, 200.0)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, size.y), Vector2(0, size.y)]), PackedColorArray([edge, rim, rim, edge]))
	draw_polygon(PackedVector2Array([Vector2(size.x - w, 0), Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(size.x - w, size.y)]), PackedColorArray([rim, edge, edge, rim]))
	draw_polygon(PackedVector2Array([Vector2(0, size.y - h), Vector2(size.x, size.y - h), Vector2(size.x, size.y), Vector2(0, size.y)]), PackedColorArray([rim, rim, edge, edge]))


## Land: a shallow-water band, an opaque fill that takes the animated water out from under the
## coast, and the coastline itself as the crispest line on the chart. Everything below this in
## the draw order overprints it, the way a chart's graticule and symbols overprint its land tint.
func _draw_land() -> void:
	if not show_terrain or Terrain.is_empty():
		return
	var tl := screen_to_world(Vector2.ZERO)
	var br := screen_to_world(size)
	var view := Rect2(tl, Vector2.ZERO).expand(br)
	if not Terrain.bounds.grow(SHELF_NM).intersects(view):
		return
	if _land_generation != Terrain.generation:
		_rebuild_land_cache()
	var detail := ppn >= 0.7
	for l: Landmass in Terrain.landmasses:
		if not l.bounds.grow(SHELF_NM).intersects(view):
			continue
		if detail:
			for shelf: PackedVector2Array in _land_shelves.get(l, []):
				var band := _project_coast(shelf)
				if band.size() >= 3:
					draw_colored_polygon(band, COL_SHELF)
		var pts := _project_coast(l.points)
		if pts.size() < 3:
			continue
		draw_colored_polygon(pts, COL_LAND.lerp(COL_LAND_HIGH, clampf(l.elevation_m / LAND_HIGH_ELEVATION_M, 0.0, 1.0)))
		var ring := pts.duplicate()
		ring.append(pts[0])
		draw_polyline(ring, COL_COAST, 1.6 if detail else 1.0, true)
		if detail and l.name != "":
			_draw_land_name(l, view)


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
	at.x -= _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x * 0.5
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_LAND_LABEL)


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
		if p.distance_squared_to(last) < COAST_MIN_STEP_PX * COAST_MIN_STEP_PX:
			continue
		out.append(p)
		last = p
	return out


## The shallow-water band is an outward offset of each coastline, computed once per scenario
## rather than per frame.
func _rebuild_land_cache() -> void:
	_land_shelves.clear()
	for l: Landmass in Terrain.landmasses:
		_land_shelves[l] = Geometry2D.offset_polygon(l.points, SHELF_NM)
	_land_generation = Terrain.generation


func _chart_axis(value: float, positive: String, negative: String) -> String:
	if ppn < 1000.0:
		return Geo.format_axis(value, positive, negative)
	return "%s %.3f" % [positive if value >= 0 else negative, absf(value)]


func _draw_grid() -> void:
	var step := _nice_step(110.0)
	var minor := step / 5.0
	var tl := screen_to_world(Vector2.ZERO)
	var br := screen_to_world(size)
	if minor * ppn >= 18.0:
		var x := floorf(tl.x / minor) * minor
		while x <= br.x:
			var sx := world_to_screen(Vector2(x, 0.0)).x
			draw_line(Vector2(sx, HEADER_H), Vector2(sx, size.y), COL_GRID_MINOR, 1.0)
			x += minor
		var y := floorf(br.y / minor) * minor
		while y <= tl.y:
			var sy := world_to_screen(Vector2(0.0, y)).y
			if sy > HEADER_H:
				draw_line(Vector2(0.0, sy), Vector2(size.x, sy), COL_GRID_MINOR, 1.0)
			y += minor
	var x := floorf(tl.x / step) * step
	while x <= br.x:
		var sx := world_to_screen(Vector2(x, 0.0)).x
		draw_line(Vector2(sx, HEADER_H), Vector2(sx, size.y), COL_GRID, 1.0)
		var label := _chart_axis(x, "E", "W")
		draw_string(_font, Vector2(sx + 4.0, size.y - 8.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_GRID_TEXT)
		x += step
	var y := floorf(br.y / step) * step
	while y <= tl.y:
		var sy := world_to_screen(Vector2(0.0, y)).y
		if sy > HEADER_H + 6.0:
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
		if Rect2(Vector2(0, HEADER_H), size - Vector2(0, HEADER_H)).has_point(lp):
			draw_string(_font, lp + Vector2(3.0, -3.0), ("%d m" % int(roundf(step * i * 1852.0))) if step < 0.5 else Geo.format_nm(step * i), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(COL_GRID_TEXT, 0.7))
		i += 1
	for deg in range(0, 360, 90):
		var d := Vector2(sin(deg_to_rad(deg)), -cos(deg_to_rad(deg)))
		draw_line(c + d * 24.0, c + d * max_r, Color(COL_RINGS, 0.055), 1.0, true)


func _draw_compass() -> void:
	var c := size * 0.5
	var radius := minf(size.x, size.y) * 0.47
	for deg in range(0, 360, 5):
		var d := Vector2(sin(deg_to_rad(deg)), -cos(deg_to_rad(deg)))
		var major := deg % 30 == 0
		var tick := 9.0 if major else 4.0
		var p0 := c + d * (radius - tick)
		var p1 := c + d * radius
		if p0.y < HEADER_H + 4.0 or p1.y < HEADER_H + 4.0:
			continue
		draw_line(p0, p1, Color(0.4, 0.7, 0.8, 0.28), 1.0, true)
		if major:
			var lp := c + d * (radius - 22.0) + Vector2(-10, 4)
			draw_string(_font, lp, "%03d" % deg, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(COL_GRID_TEXT, 0.8))


func _draw_objectives() -> void:
	if simulation == null:
		return
	for o in simulation.mission_manager.victory_objectives:
		if o.kind == MissionObjective.Kind.REACH_AREA:
			var sp := world_to_screen(o.center)
			var r := o.radius_nm * ppn
			draw_circle(sp, r, Color(COL_WAYPOINT, 0.05))
			draw_arc(sp, r, 0.0, TAU, 80, Color(COL_WAYPOINT, 0.6), 2.0, true)
			_place_label(sp, "OBJECTIVE AREA", COL_WAYPOINT, false, "")


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
		draw_string(_font, sp + Vector2(0.0, -outer - 5.0), "%s  %s nm" % [weapon_ring.display_name.to_upper(), Geo.format_nm(weapon_ring.max_range_nm)], HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(COL_WEAPON_RING, 0.9))
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
		if t.has_kinematics and t.speed_kn > 0.5 and (show_vectors or selected_track == t):
			var tip := world_to_screen(t.position + Geo.heading_to_vector(t.course_deg) * t.speed_kn * LEADER_MINUTES / 60.0)
			draw_dashed_line(sp, tip, Color(col, 0.6), 1.0, 4.0)
			draw_circle(tip, 1.5, Color(col, 0.7))
		var glyph := ""
		if t.classification >= Track.Classification.CLASS_KNOWN and t.truth != null:
			glyph = MapSymbols.category_glyph(t.truth.spec.category, t.truth.spec.domain)
		MapSymbols.draw_symbol(self, sp, col, MapSymbols.frame_for_identity(t.identity), t.domain, t.course_deg, t.has_kinematics, glyph, _font, 1.0, stale)
		if t.is_bearing_only():
			# A bearing line from the listener: this is all the contact really is.
			if ref != null:
				var lp := world_to_screen(ref.position)
				draw_dashed_line(lp, sp, Color(col, 0.35), 1.0, 6.0)
		if selected_track == t:
			MapSymbols.draw_selection(self, sp, COL_SELECT, _anim)
		if stale:
			draw_string(_font, sp + Vector2(10.0, -12.0), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(col, 0.9))
		var jammed := ref != null and ref.radar_emitting() and Detection.is_jammed_toward(ref, t.position)
		if jammed:
			draw_string(_font, sp + Vector2(-14.0, -14.0), "J", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_JAM)
		var text := t.label()
		var tags := PackedStringArray()
		if t.is_bearing_only(): tags.append("BRG")
		if not t.networked: tags.append("LOCAL")
		if stale: tags.append("STALE %s" % Track._fmt_age(t.age_s(SimClock.sim_time)))
		var sub := ""
		if ref != null:
			sub = "%s / %s nm" % [Geo.format_bearing(Geo.bearing_deg(ref.position, t.position)), Geo.format_nm(Geo.distance_nm(ref.position, t.position))]
		if not tags.is_empty():
			sub += ("  " if sub != "" else "") + " · ".join(tags)
		_place_label(sp, text, col, selected_track == t, sub)


## Last few plots that built the track, fading with age: the console's own memory of the contact.
func _draw_track_history(t: Track, col: Color) -> void:
	var n := t._obs_pos.size()
	if n < 2:
		return
	var take := mini(n, 10)
	for i in range(n - take, n):
		var f := float(i - (n - take) + 1) / float(take)
		draw_circle(world_to_screen(t._obs_pos[i]), 1.5, Color(col, 0.08 + 0.35 * f))


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
	for i in 41:
		var th := TAU * float(i) / 40.0
		pts.append(sp + axis * (cos(th) * major) + perp * (sin(th) * minor))
	draw_colored_polygon(pts, Color(col, 0.05))
	draw_polyline(pts, Color(col, 0.35), 1.0, true)


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
			var lead_nm := u.speed_kn * LEADER_MINUTES / 60.0
			var tip := world_to_screen(u.position + Geo.heading_to_vector(u.heading_deg) * lead_nm)
			draw_line(sp, tip, Color(COL_FRIENDLY, 0.6), 1.0, true)
			draw_circle(tip, 1.5, Color(COL_FRIENDLY, 0.7))
		var health := Damage.health_fraction(u)
		var ucol := COL_FRIENDLY.lerp(Color(1.0, 0.4, 0.3), 1.0 - health)
		var domain := "air" if u.airborne() else ("subsurface" if u.submerged() else u.spec.domain)
		if ppn >= 30.0:
			if u.spec.domain == "surface" and u.speed_kn > 1.0 and ppn > 160.0:
				_draw_wake(u, sp)
			_draw_silhouette(u, sp, ucol)
		MapSymbols.draw_symbol(self, sp, ucol, MapSymbols.Frame.FRIENDLY, domain, u.heading_deg, true, MapSymbols.category_glyph(u.spec.category, u.spec.domain), _font)
		if selected.has(u):
			MapSymbols.draw_selection(self, sp, COL_SELECT, _anim)
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


func _draw_header() -> void:
	draw_rect(Rect2(0, 0, size.x, HEADER_H), COL_HEADER)
	draw_line(Vector2(0, HEADER_H), Vector2(size.x, HEADER_H), Color(COL_ACCENT, 0.35), 1)
	draw_string(_font, Vector2(14, 23), "TACTICAL PLOT", HORIZONTAL_ALIGNMENT_LEFT, 125, 12, COL_ACCENT)
	var ref := reference_unit()
	if ref != null:
		draw_string(_font, Vector2(143, 23), "%s  /  %s" % [ref.callsign.to_upper(), "LINKED" if ref.datalink_connected() else "LOCAL SENSORS"], HORIZONTAL_ALIGNMENT_LEFT, int(size.x - 375), 11, COL_TEXT)
	var text := "N UP  ·  F4 SENSORS  ·  SCROLL ZOOM"
	draw_string(_font, Vector2(size.x - 236, 23), text, HORIZONTAL_ALIGNMENT_LEFT, 228, 10, UITheme.COL_DIM)


func _chip(x: float, text: String, col: Color) -> float:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 14.0
	draw_rect(Rect2(x, 9, w, 19), Color(col, 0.10))
	draw_rect(Rect2(x, 9, 2, 19), Color(col, 0.9))
	draw_string(_font, Vector2(x + 8, 22), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
	return x + w + 8.0


func _draw_scale_bar() -> void:
	var nm := _nice_step(80.0)
	var px := nm * ppn
	var right := size.x - 16.0
	var y := size.y - 24.0
	draw_line(Vector2(right - px, y), Vector2(right, y), COL_TEXT, 2.0)
	draw_line(Vector2(right - px, y - 4.0), Vector2(right - px, y + 4.0), COL_TEXT, 2.0)
	draw_line(Vector2(right, y - 4.0), Vector2(right, y + 4.0), COL_TEXT, 2.0)
	draw_string(_font, Vector2(right - px, y - 7.0), (("%d m" % int(roundf(nm * 1852.0))) if nm < 0.5 else "%s nm" % Geo.format_nm(nm)), HORIZONTAL_ALIGNMENT_CENTER, int(px), 11, COL_TEXT)


func _draw_readout() -> void:
	if not _mouse_inside:
		return
	var w := screen_to_world(_mouse)
	var text := "CURSOR  %s  %s" % [Geo.format_axis(w.x, "E", "W"), Geo.format_axis(w.y, "N", "S")]
	var ref := reference_unit()
	if ref != null:
		text += "    FROM %s:  BRG %s  RNG %.1f nm" % [ref.callsign, Geo.format_bearing(Geo.bearing_deg(ref.position, w)), Geo.distance_nm(ref.position, w)]
	draw_string(_font, Vector2(16.0, HEADER_H + 20.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(COL_TEXT, 0.85))
	if not Terrain.is_empty() and Terrain.is_land(w):
		var wide := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(_font, Vector2(16.0 + wide + 14.0, HEADER_H + 20.0), "LAND", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_AMBER)


## Labels: a dark pill with an identity bar, a primary line and an optional secondary line, placed
## where it does not collide with another label. Leader line back to the symbol.
func _place_label(sp: Vector2, text: String, color: Color, important: bool, sub: String) -> void:
	if not Rect2(Vector2(0, HEADER_H + 20.0), size - Vector2(0, HEADER_H + 100.0)).has_point(sp):
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
		if r.position.y < HEADER_H + 4.0 or r.end.y > size.y - 100:
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


func _draw_key() -> void:
	if not show_key:
		return
	var w := 352.0
	var h := 198.0
	var x := 12.0
	var y := size.y - h - 34.0
	draw_rect(Rect2(x, y, w, h), Color("0b1721", 0.94))
	draw_rect(Rect2(x, y, w, h), Color(0.16, 0.30, 0.38, 0.8), false, 1.0)
	draw_string(_font, Vector2(x + 12, y + 17), "SYMBOL KEY", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_ACCENT)
	draw_string(_font, Vector2(x + 110, y + 17), "F2 hides", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(COL_TEXT, 0.5))
	var cx := x + 26.0
	var cy := y + 42.0
	MapSymbols.draw_key_entry(self, Vector2(cx, cy), COL_FRIENDLY, MapSymbols.Frame.FRIENDLY, "surface", "DD", "Friendly", _font, COL_TEXT)
	MapSymbols.draw_key_entry(self, Vector2(cx + 110, cy), COL_HOSTILE, MapSymbols.Frame.HOSTILE, "surface", "", "Hostile", _font, COL_TEXT)
	MapSymbols.draw_key_entry(self, Vector2(cx + 215, cy), COL_UNKNOWN, MapSymbols.Frame.UNKNOWN, "surface", "", "Unknown", _font, COL_TEXT)
	cy += 30.0
	MapSymbols.draw_key_entry(self, Vector2(cx, cy), COL_FRIENDLY, MapSymbols.Frame.FRIENDLY, "air", "F", "Air", _font, COL_TEXT)
	MapSymbols.draw_key_entry(self, Vector2(cx + 110, cy), COL_FRIENDLY, MapSymbols.Frame.FRIENDLY, "subsurface", "SN", "Subsurface", _font, COL_TEXT)
	MapSymbols.draw_key_entry(self, Vector2(cx + 215, cy), COL_NEUTRAL, MapSymbols.Frame.NEUTRAL, "surface", "M", "Neutral", _font, COL_TEXT)
	cy += 26.0
	draw_string(_font, Vector2(x + 12, cy + 4), "Glyph: CV carrier · CG cruiser · DD · FF · SS/SN sub · F fighter · E AEW · EA jammer", HORIZONTAL_ALIGNMENT_LEFT, int(w - 20), 9, Color(COL_TEXT, 0.7))
	cy += 18.0
	draw_string(_font, Vector2(x + 12, cy + 4), "Ellipse: uncertainty · vectors: 30 min (selection, or VECTORS) · dots: history", HORIZONTAL_ALIGNMENT_LEFT, int(w - 20), 9, Color(COL_TEXT, 0.7))
	cy += 16.0
	draw_string(_font, Vector2(x + 12, cy + 4), "Rings: radar blue · sonar green · ESM violet · jammer magenta · weapon amber", HORIZONTAL_ALIGNMENT_LEFT, int(w - 20), 9, Color(COL_TEXT, 0.7))
	cy += 16.0
	draw_string(_font, Vector2(x + 12, cy + 4), "Lamps: radiating · link · weapons posture · pinging · repairing", HORIZONTAL_ALIGNMENT_LEFT, int(w - 20), 9, Color(COL_TEXT, 0.7))
	cy += 16.0
	draw_string(_font, Vector2(x + 12, cy + 4), "Land: masks radar, ESM and sonar · ships cannot enter it", HORIZONTAL_ALIGNMENT_LEFT, int(w - 20), 9, Color(COL_TEXT, 0.7))
	cy += 16.0
	draw_string(_font, Vector2(x + 12, cy + 4), "Ctrl+right-click a contact: engage · right-click a waypoint: drop that leg", HORIZONTAL_ALIGNMENT_LEFT, int(w - 20), 9, Color(COL_TEXT, 0.7))
	cy += 16.0
	draw_string(_font, Vector2(x + 12, cy + 4), "Double-click: recentre · Home: fit fleet · C: centre selection · +/−: zoom", HORIZONTAL_ALIGNMENT_LEFT, int(w - 20), 9, Color(COL_TEXT, 0.7))


## Hovering over a symbol shows what the console knows about it, without a click.
func _draw_hover_card() -> void:
	if not _mouse_inside or _drag_mode != DragMode.NONE:
		return
	var wp := _waypoint_at(_mouse)
	if not wp.is_empty():
		var wu: Unit = wp["unit"]
		var lines := PackedStringArray()
		lines.append("%s WAYPOINT %d/%d" % [wu.callsign, int(wp["index"]) + 1, wu.waypoints.size()])
		lines.append("right-click to remove this leg")
		_draw_card(lines, COL_WAYPOINT)
		return
	var lines := PackedStringArray()
	var col := COL_TEXT
	var u := _unit_at(_mouse)
	if u != null:
		col = COL_FRIENDLY
		lines.append(u.callsign)
		lines.append(u.spec.display_name)
		lines.append("%s  ·  %s" % [Damage.condition_text(u), Damage.damage_report(u)])
		lines.append(u.status_line())
		_draw_card(lines, col, PlatformArt.profile(u.spec.id))
		return
	else:
		var t := _track_at(_mouse)
		if t == null:
			var lw := screen_to_world(_mouse)
			var l := Terrain.land_at(lw) if not Terrain.is_empty() else null
			if l == null:
				return
			col = COL_LAND_LABEL
			lines.append(l.name if l.name != "" else "LAND")
			lines.append("coastline · masks radar, ESM and sonar")
			lines.append("elevation %d m" % int(l.elevation_m))
			lines.append("%s  %s" % [Geo.format_axis(lw.x, "E", "W"), Geo.format_axis(lw.y, "N", "S")])
			_draw_card(lines, col)
			return
		col = track_color(t)
		lines.append("%s  %s" % [t.id, t.description()])
		lines.append("%s · %s · %s" % [t.identity, t.status_text(SimClock.sim_time), t.source.to_upper().replace("_", " ")])
		if t.has_kinematics:
			lines.append("CSE %s  SPD %.0f kn (est)" % [Geo.format_bearing(t.course_deg), t.speed_kn])
		else:
			lines.append("kinematics estimating")
		lines.append("±%.1f nm  ·  observed %s" % [t.position_error_nm, Track._fmt_age(t.observation_time_s)])
	_draw_card(lines, col)


## A hover card: text lines, and for an own unit its recognition profile across the top so the
## class is recognisable before the name is read.
func _draw_card(lines: PackedStringArray, col: Color, art: Texture2D = null) -> void:
	var width := 0.0
	for l in lines:
		width = maxf(width, _font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x)
	width += 20.0
	var art_h := 0.0
	if art != null:
		width = maxf(width, 200.0)
		art_h = (width - 20.0) * float(art.get_height()) / maxf(float(art.get_width()), 1.0) + 6.0
	var height := 12.0 + lines.size() * 15.0 + art_h
	var pos := _mouse + Vector2(18.0, 18.0)
	if pos.x + width > size.x:
		pos.x = _mouse.x - width - 12.0
	if pos.y + height > size.y:
		pos.y = _mouse.y - height - 12.0
	draw_rect(Rect2(pos, Vector2(width, height)), Color("0b1721", 0.96))
	draw_rect(Rect2(pos, Vector2(width, height)), Color(col, 0.6), false, 1.0)
	if art != null:
		draw_texture_rect(art, Rect2(pos + Vector2(10.0, 8.0), Vector2(width - 20.0, art_h - 6.0)), false, col)
	for i in lines.size():
		draw_string(_font, pos + Vector2(10.0, 16.0 + art_h + i * 15.0), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col if i == 0 else Color(COL_TEXT, 0.85))
