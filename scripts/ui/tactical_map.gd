class_name TacticalMap
extends Control
## Tactical map display. Renders the nautical-mile world into pixels and turns mouse input into
## selection changes and order requests. Frame-based; contains no simulation logic.
## Own units are drawn from ground truth; other factions are drawn ONLY as Tracks
## (except under Debug.enabled, which overlays true positions).
##
## Controls: wheel = zoom at cursor, middle/right drag = pan, left click = select unit/track,
## shift+click = add/remove unit, left drag = box select, right click water = move order
## (shift = append), right click track = select track, arrow keys / WASD = pan.

signal selection_changed(units: Array)
signal track_selected(track: Track)
signal move_order_requested(world_pos: Vector2, append: bool)

enum DragMode { NONE, PAN, BOX }

const MIN_PPN := 0.2
const MAX_PPN := 300.0
const ZOOM_STEP := 1.25
const CLICK_RADIUS_PX := 14.0
const DRAG_THRESHOLD_PX := 5.0
const LEADER_MINUTES := 30.0
const KEY_PAN_PX_PER_S := 700.0
const HEADER_H := 36.0
const TRAIL_INTERVAL_S := 60.0
const TRAIL_LENGTH := 24
const EFFECT_LIFE_S := 2.2
const NICE_STEPS_NM: Array[float] = [0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0, 1000.0]

const COL_OCEAN := Color(0.024, 0.055, 0.086)
const COL_OCEAN_TOP := Color(0.035, 0.085, 0.125)
const COL_OCEAN_BOTTOM := Color(0.016, 0.036, 0.062)
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
var show_key := true
var show_rings := true
var show_trails := true

var _drag_mode := DragMode.NONE
var _drag_button := MOUSE_BUTTON_NONE
var _drag_start := Vector2.ZERO
var _drag_moved := false
var _mouse := Vector2.ZERO
var _mouse_inside := false
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


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true
	_font = get_theme_default_font()
	mouse_entered.connect(func() -> void: _mouse_inside = true)
	mouse_exited.connect(func() -> void: _mouse_inside = false)
	resized.connect(_apply_pending_fit)


func _process(delta: float) -> void:
	_anim += delta
	_keyboard_pan(delta)
	_prune_selection()
	_record_trails()
	queue_redraw()


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
## kind: "hit", "miss", "intercept", "decoy", "destroyed", "launch", "splash".
func add_effect(pos: Vector2, kind: String) -> void:
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
		"launch":
			col = COL_MISSILE
	_effects.append({"pos": pos, "t0": _anim, "kind": kind, "color": col})
	if _effects.size() > 40:
		_effects.remove_at(0)


func reset_presentation() -> void:
	_trails.clear()
	_effects.clear()
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
					var t := _track_at(e.position)
					if t != null:
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
	return track_manager.get_tracks(player_faction)


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
	_threats = AirDefence.inbound_threats(unit_manager, threat_manager, player_faction) if unit_manager != null and threat_manager != null else []
	_draw_ocean()
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
	var rim := Color(0.0, 0.0, 0.0, 0.0)
	var edge := Color(0.0, 0.01, 0.03, 0.55)
	var w := minf(size.x * 0.22, 260.0)
	var h := minf(size.y * 0.22, 200.0)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, size.y), Vector2(0, size.y)]), PackedColorArray([edge, rim, rim, edge]))
	draw_polygon(PackedVector2Array([Vector2(size.x - w, 0), Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(size.x - w, size.y)]), PackedColorArray([rim, edge, edge, rim]))
	draw_polygon(PackedVector2Array([Vector2(0, size.y - h), Vector2(size.x, size.y - h), Vector2(size.x, size.y), Vector2(0, size.y)]), PackedColorArray([rim, rim, edge, edge]))


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
		var label := Geo.format_axis(x, "E", "W")
		draw_string(_font, Vector2(sx + 4.0, size.y - 8.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_GRID_TEXT)
		x += step
	var y := floorf(br.y / step) * step
	while y <= tl.y:
		var sy := world_to_screen(Vector2(0.0, y)).y
		if sy > HEADER_H + 6.0:
			draw_line(Vector2(0.0, sy), Vector2(size.x, sy), COL_GRID, 1.0)
			draw_string(_font, Vector2(5.0, sy - 4.0), Geo.format_axis(y, "N", "S"), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_GRID_TEXT)
		y += step


## Own-ship-centred range rings and bearing spokes, the way a console keeps the picture
## relative to the ship it is aboard.
func _draw_range_rings() -> void:
	var ref := reference_unit()
	if ref == null:
		return
	var c := world_to_screen(ref.position)
	var step := _nice_step(70.0)
	var max_r := maxf(size.x, size.y) * 1.2
	var i := 1
	while step * i * ppn < max_r and i <= 12:
		var r := step * i * ppn
		draw_arc(c, r, 0.0, TAU, 160, COL_RINGS, 1.0, true)
		var lp := c + Vector2(sin(deg_to_rad(45.0)), -cos(deg_to_rad(45.0))) * r
		if Rect2(Vector2(0, HEADER_H), size - Vector2(0, HEADER_H)).has_point(lp):
			draw_string(_font, lp + Vector2(3.0, -3.0), "%s" % Geo.format_nm(step * i), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(COL_GRID_TEXT, 0.7))
		i += 1
	for deg in range(0, 360, 30):
		var d := Vector2(sin(deg_to_rad(deg)), -cos(deg_to_rad(deg)))
		draw_line(c + d * 24.0, c + d * max_r, Color(COL_RINGS, 0.55), 1.0, true)


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
		if t.has_kinematics and t.speed_kn > 0.5:
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
	for u in _own_units():
		var sp := world_to_screen(u.position)
		if show_trails and _trails.has(u):
			var arr: PackedVector2Array = _trails[u]
			for i in range(1, arr.size()):
				var f := float(i) / float(arr.size())
				draw_line(world_to_screen(arr[i - 1]), world_to_screen(arr[i]), Color(COL_FRIENDLY, 0.05 + 0.22 * f), 1.0, true)
		if not u.waypoints.is_empty():
			var prev := sp
			for wp in u.waypoints:
				var wsp := world_to_screen(wp)
				draw_dashed_line(prev, wsp, COL_WAYPOINT, 1.0, 6.0)
				draw_rect(Rect2(wsp - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), COL_WAYPOINT, false, 1.0)
				prev = wsp
		if u.in_formation():
			var station := world_to_screen(Formation.station_for(u))
			draw_dashed_line(sp, station, Color(COL_FRIENDLY, 0.3), 1.0, 3.0)
			draw_rect(Rect2(station - Vector2(2.5, 2.5), Vector2(5, 5)), Color(COL_FRIENDLY, 0.5), false, 1.0)
		if u.speed_kn > 0.05:
			var lead_nm := u.speed_kn * LEADER_MINUTES / 60.0
			var tip := world_to_screen(u.position + Geo.heading_to_vector(u.heading_deg) * lead_nm)
			draw_line(sp, tip, Color(COL_FRIENDLY, 0.6), 1.0, true)
			draw_circle(tip, 1.5, Color(COL_FRIENDLY, 0.7))
		var health := Damage.health_fraction(u)
		var ucol := COL_FRIENDLY.lerp(Color(1.0, 0.4, 0.3), 1.0 - health)
		var domain := "air" if u.airborne() else ("subsurface" if u.submerged() else u.spec.domain)
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
			sub += " · FL%02d · fuel %d%%" % [int(u.altitude_m / 304.8 / 10.0), int(u.fuel_fraction() * 100.0)]
		if health < 0.99:
			sub += " · hull %d%%" % int(health * 100.0)
		_place_label(sp, name, COL_TEXT if selected.has(u) else Color(COL_TEXT, 0.85), selected.has(u), sub)


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
		var detected := threat_manager != null and threat_manager.is_detected(player_faction, w)
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
		var trail := clampf(w.spec.speed_kn / 60.0, 6.0, 26.0)
		MapSymbols.draw_round(self, sp, w.heading_deg, col, trail, w.spec.is_torpedo())
		if w.spec.profile == "ballistic" and not w.is_interceptor():
			draw_string(_font, sp + Vector2(8.0, -6.0), "BM", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)
		if Debug.enabled:
			draw_dashed_line(sp, world_to_screen(w.aim_point), Color(col, 0.4), 1.0, 5.0)


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
			_:
				draw_arc(sp, 3.0 + 14.0 * f, 0.0, TAU, 20, Color(col, 0.5 * (1.0 - f)), 1.0, true)


func _draw_header() -> void:
	draw_rect(Rect2(0, 0, size.x, HEADER_H), COL_HEADER)
	draw_line(Vector2(0, HEADER_H), Vector2(size.x, HEADER_H), Color(0.16, 0.30, 0.38, 0.8), 1.0)
	draw_string(_font, Vector2(16, 23), "TACTICAL PICTURE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COL_ACCENT)
	var x := 150.0
	var ref := reference_unit()
	if ref != null:
		x = _chip(x, "CENTRE %s" % ref.callsign.to_upper(), COL_TEXT)
	var radiating := 0
	var own := _own_units()
	for u in own:
		if u.radar_emitting():
			radiating += 1
	x = _chip(x, "EMISSIONS %d/%d RADIATING" % [radiating, own.size()], COL_BUOY if radiating > 0 else Color(0.5, 0.6, 0.65))
	if Detection.sea_state > 0:
		x = _chip(x, "SEA STATE %d %s" % [Detection.sea_state, Detection.sea_state_name().to_upper()], COL_AMBER if Detection.sea_state >= 4 else COL_TEXT)
	if not _threats.is_empty():
		var blink := 0.6 + 0.4 * sin(_anim * 8.0)
		var torp := false
		for entry: Dictionary in _threats:
			if (entry["weapon"] as Weapon).spec.is_torpedo():
				torp = true
		x = _chip(x, "%s  %d INBOUND" % ["TORPEDO" if torp else "MISSILE", _threats.size()], Color(COL_HOSTILE, blink))
	if Debug.enabled:
		x = _chip(x, "DEBUG TRUTH", COL_TRUTH)
	var right := "N UP  ·  F2 KEY  ·  F4 RINGS  ·  F5 TRAILS"
	var rw := _font.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(_font, Vector2(size.x - rw - 14.0, 23), right, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(COL_TEXT, 0.7))


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
	draw_string(_font, Vector2(right - px, y - 7.0), "%s nm" % Geo.format_nm(nm), HORIZONTAL_ALIGNMENT_CENTER, int(px), 11, COL_TEXT)


func _draw_readout() -> void:
	if not _mouse_inside:
		return
	var w := screen_to_world(_mouse)
	var text := "CURSOR  %s  %s" % [Geo.format_axis(w.x, "E", "W"), Geo.format_axis(w.y, "N", "S")]
	var ref := reference_unit()
	if ref != null:
		text += "    FROM %s:  BRG %s  RNG %.1f nm" % [ref.callsign, Geo.format_bearing(Geo.bearing_deg(ref.position, w)), Geo.distance_nm(ref.position, w)]
	draw_string(_font, Vector2(16.0, HEADER_H + 20.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(COL_TEXT, 0.85))


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
	var h := 150.0
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
	draw_string(_font, Vector2(x + 12, cy + 4), "Ellipse: uncertainty · dashed line: 30 min leader · dots: plot history", HORIZONTAL_ALIGNMENT_LEFT, int(w - 20), 9, Color(COL_TEXT, 0.7))
	cy += 16.0
	draw_string(_font, Vector2(x + 12, cy + 4), "Rings: radar blue · sonar green · ESM violet · jammer magenta · weapon amber", HORIZONTAL_ALIGNMENT_LEFT, int(w - 20), 9, Color(COL_TEXT, 0.7))
	cy += 16.0
	draw_string(_font, Vector2(x + 12, cy + 4), "Lamps: radiating · link · weapons posture · pinging · repairing", HORIZONTAL_ALIGNMENT_LEFT, int(w - 20), 9, Color(COL_TEXT, 0.7))


## Hovering over a symbol shows what the console knows about it, without a click.
func _draw_hover_card() -> void:
	if not _mouse_inside or _drag_mode != DragMode.NONE:
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
	else:
		var t := _track_at(_mouse)
		if t == null:
			return
		col = track_color(t)
		lines.append("%s  %s" % [t.id, t.description()])
		lines.append("%s · %s · %s" % [t.identity, t.status_text(SimClock.sim_time), t.source.to_upper().replace("_", " ")])
		if t.has_kinematics:
			lines.append("CSE %s  SPD %.0f kn (est)" % [Geo.format_bearing(t.course_deg), t.speed_kn])
		else:
			lines.append("kinematics estimating")
		lines.append("±%.1f nm  ·  observed %s" % [t.position_error_nm, Track._fmt_age(t.observation_time_s)])
	var width := 0.0
	for l in lines:
		width = maxf(width, _font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x)
	width += 20.0
	var height := 12.0 + lines.size() * 15.0
	var pos := _mouse + Vector2(18.0, 18.0)
	if pos.x + width > size.x:
		pos.x = _mouse.x - width - 12.0
	if pos.y + height > size.y:
		pos.y = _mouse.y - height - 12.0
	draw_rect(Rect2(pos, Vector2(width, height)), Color("0b1721", 0.96))
	draw_rect(Rect2(pos, Vector2(width, height)), Color(col, 0.6), false, 1.0)
	for i in lines.size():
		draw_string(_font, pos + Vector2(10.0, 16.0 + i * 15.0), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col if i == 0 else Color(COL_TEXT, 0.85))
