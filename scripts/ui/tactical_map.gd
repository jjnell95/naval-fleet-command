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
const NICE_STEPS_NM: Array[float] = [0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0, 1000.0]

const COL_OCEAN := Color(0.024, 0.055, 0.086)
const COL_GRID := Color(0.20, 0.42, 0.55, 0.13)
const COL_GRID_TEXT := Color(0.35, 0.60, 0.72, 0.75)
const COL_TEXT := Color(0.72, 0.86, 0.95)
const COL_SELECT := Color(1.0, 1.0, 1.0, 0.9)
const COL_BOX := Color(0.6, 0.9, 1.0, 0.8)
const COL_WAYPOINT := Color(0.55, 0.95, 0.75, 0.8)
const COL_FRIENDLY := Color(0.36, 0.72, 1.0)
const COL_HOSTILE := Color(1.0, 0.36, 0.36)
const COL_UNKNOWN := Color(1.0, 0.85, 0.3)
const COL_RING := Color(0.36, 0.72, 1.0, 0.4)
const COL_RING_SILENT := Color(0.5, 0.6, 0.65, 0.35)
const COL_SONAR_RING := Color(0.45, 0.95, 0.75, 0.30)
const COL_SONAR_ACTIVE := Color(0.55, 1.0, 0.6, 0.5)
const COL_BUOY := Color(0.5, 0.95, 0.8, 0.85)
const COL_ESM_RING := Color(0.85, 0.7, 1.0, 0.28)
const COL_TRUTH := Color(1.0, 0.5, 0.5, 0.45)
const COL_WEAPON_RING := Color(1.0, 0.72, 0.35, 0.5)
const COL_MISSILE := Color(1.0, 0.85, 0.35)
const COL_MISSILE_HOSTILE := Color(1.0, 0.45, 0.35)

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
var show_key := true
var show_rings := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true
	_font = get_theme_default_font()
	mouse_entered.connect(func() -> void: _mouse_inside = true)
	mouse_exited.connect(func() -> void: _mouse_inside = false)
	resized.connect(_apply_pending_fit)


func _process(delta: float) -> void:
	_keyboard_pan(delta)
	_prune_selection()
	queue_redraw()


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
		if u.is_aircraft() and not u.airborne():
			continue
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


# --- Drawing ----------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_OCEAN)
	_label_rects.clear()
	_draw_grid()
	_draw_scope()
	if unit_manager != null:
		if show_rings:
			_draw_sensor_rings()
		_draw_weapon_ring()
		if Debug.enabled:
			_draw_truth()
		_draw_tracks()
		_draw_units()
		_draw_weapons()
	if _drag_mode == DragMode.BOX and _drag_moved:
		draw_rect(Rect2(_drag_start, _mouse - _drag_start).abs(), COL_BOX, false, 1.0)
	_draw_scale_bar()
	_draw_readout()
	_draw_key()


func _nice_step(min_px: float) -> float:
	for s in NICE_STEPS_NM:
		if s * ppn >= min_px:
			return s
	return NICE_STEPS_NM[-1]


func _draw_grid() -> void:
	var step := _nice_step(90.0)
	var tl := screen_to_world(Vector2.ZERO)
	var br := screen_to_world(size)
	var x := floorf(tl.x / step) * step
	while x <= br.x:
		var sx := world_to_screen(Vector2(x, 0.0)).x
		draw_line(Vector2(sx, 0.0), Vector2(sx, size.y), COL_GRID, 1.0)
		draw_string(_font, Vector2(sx + 3.0, size.y - 6.0), Geo.format_axis(x, "E", "W"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_GRID_TEXT)
		x += step
	var y := floorf(br.y / step) * step
	while y <= tl.y:
		var sy := world_to_screen(Vector2(0.0, y)).y
		draw_line(Vector2(0.0, sy), Vector2(size.x, sy), COL_GRID, 1.0)
		draw_string(_font, Vector2(4.0, sy - 3.0), Geo.format_axis(y, "N", "S"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_GRID_TEXT)
		y += step


func _draw_sensor_rings() -> void:
	_draw_sonobuoys()
	for u in _own_units():
		if u.is_aircraft() and not u.airborne():
			continue
		if not (Debug.enabled or selected.has(u)):
			continue
		var esm := Detection.nominal_esm_ring_nm(u)
		if esm > 0.0:
			draw_arc(world_to_screen(u.position), esm * ppn, 0.0, TAU, 96, COL_ESM_RING, 1.0)
		var sonar := Detection.nominal_passive_ring_nm(u)
		if sonar > 0.0:
			draw_arc(world_to_screen(u.position), sonar * ppn, 0.0, TAU, 96, COL_SONAR_RING, 1.0)
		var active := Detection.best_active_sonar_nm(u)
		if active > 0.0:
			draw_arc(world_to_screen(u.position), active * ppn, 0.0, TAU, 72, COL_SONAR_ACTIVE, 1.5)
		var r := Detection.nominal_radar_ring_nm(u)
		if r <= 0.0:
			continue
		var sp := world_to_screen(u.position)
		if u.radar_on:
			draw_arc(sp, r * ppn, 0.0, TAU, 96, COL_RING, 1.0)
		else:
			draw_arc(sp, r * ppn, 0.0, TAU, 96, COL_RING_SILENT, 1.0)
			draw_string(_font, sp + Vector2(0.0, -r * ppn - 4.0), "RADAR SILENT", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, COL_RING_SILENT)


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
		if not own and detected:
			draw_arc(sp, 11.0, 0.0, TAU, 20, Color(col, 0.55), 1.0)
		var dir := Vector2(sin(deg_to_rad(w.heading_deg)), -cos(deg_to_rad(w.heading_deg)))
		var side := dir.orthogonal() * 2.5
		draw_polyline(PackedVector2Array([sp + dir * 5.0, sp - dir * 3.0 + side, sp - dir * 3.0 - side, sp + dir * 5.0]), col, 1.5)
		if Debug.enabled:
			draw_dashed_line(sp, world_to_screen(w.aim_point), Color(col, 0.4), 1.0, 5.0)


func _draw_weapon_ring() -> void:
	if weapon_ring == null:
		return
	for u in _own_units():
		if not selected.has(u) or u.magazine_count(weapon_ring.id) <= 0:
			continue
		var sp := world_to_screen(u.position)
		draw_arc(sp, weapon_ring.max_range_nm * ppn, 0.0, TAU, 128, COL_WEAPON_RING, 1.0)
		if weapon_ring.min_range_nm > 0.5:
			draw_arc(sp, weapon_ring.min_range_nm * ppn, 0.0, TAU, 48, Color(COL_WEAPON_RING, 0.35), 1.0)


## Buoys are cheap, numerous and easy to lose track of, so they are drawn plainly.
func _draw_sonobuoys() -> void:
	if aviation_manager == null:
		return
	for b: Sonobuoy in aviation_manager.sonobuoys:
		if b.faction != player_faction:
			continue
		var sp := world_to_screen(b.position)
		draw_circle(sp, 2.5, COL_BUOY)
		draw_arc(sp, 4.5, 0.0, TAU, 10, Color(COL_BUOY, 0.35), 1.0)


func _draw_truth() -> void:
	for u in unit_manager.units:
		if not u.is_engageable() or u.faction == player_faction:
			continue
		var sp := world_to_screen(u.position)
		MapSymbols.draw_surface(self, sp, COL_TRUTH, true, u.heading_deg)
		if u.airborne():
			MapSymbols.draw_air_mark(self, sp, COL_TRUTH)
		var r := Detection.nominal_radar_ring_nm(u)
		if r > 0.0 and u.radar_on:
			draw_arc(sp, r * ppn, 0.0, TAU, 96, Color(COL_TRUTH, 0.25), 1.0)
		draw_string(_font, sp + Vector2(12.0, 14.0), "TRUE %s %s" % [u.callsign, u.status_line()], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_TRUTH)
		if simulation != null:
			var ai := simulation.ai_state_for(u)
			if ai != "":
				draw_string(_font, sp + Vector2(12.0, 26.0), "AI %s  hp %.0f%%" % [ai, Damage.health_fraction(u) * 100.0], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_TRUTH)


func _draw_tracks() -> void:
	var now := SimClock.sim_time
	for t: Track in _visible_tracks():
		var sp := world_to_screen(t.position)
		var col := COL_HOSTILE if t.identity == "HOSTILE" else COL_UNKNOWN
		if t.status == Track.Status.STALE:
			col.a = 0.55
		_draw_uncertainty(sp, t, col)
		if t.has_kinematics and t.speed_kn > 0.5:
			var tip := world_to_screen(t.position + Geo.heading_to_vector(t.course_deg) * t.speed_kn * LEADER_MINUTES / 60.0)
			draw_dashed_line(sp, tip, Color(col, 0.6), 1.0, 4.0)
		MapSymbols.draw_track(self, sp, col, t.identity == "HOSTILE", t.has_kinematics, t.course_deg)
		if t.domain == "subsurface":
			MapSymbols.draw_subsurface_mark(self, sp, col)
		elif t.domain == "air":
			MapSymbols.draw_air_mark(self, sp, col)
		if selected_track == t:
			MapSymbols.draw_selection(self, sp, COL_SELECT)
		var text := t.label()
		if t.is_bearing_only(): text += " / BRG"
		if not t.networked: text += " / LOCAL"
		if t.status == Track.Status.STALE: text += " / STALE"
		_place_label(sp, text, col, selected_track == t)



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
	draw_polyline(pts, Color(col, 0.35), 1.0)


func _draw_units() -> void:
	for u in _own_units():
		if u.is_aircraft() and not u.airborne():
			continue  # in the hangar, not on the board
		var sp := world_to_screen(u.position)
		if not u.waypoints.is_empty():
			var prev := sp
			for wp in u.waypoints:
				var wsp := world_to_screen(wp)
				draw_dashed_line(prev, wsp, COL_WAYPOINT, 1.0, 6.0)
				draw_rect(Rect2(wsp - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), COL_WAYPOINT, false, 1.0)
				prev = wsp
		if u.speed_kn > 0.05:
			var lead_nm := u.speed_kn * LEADER_MINUTES / 60.0
			var tip := world_to_screen(u.position + Geo.heading_to_vector(u.heading_deg) * lead_nm)
			draw_line(sp, tip, Color(COL_FRIENDLY, 0.6), 1.0)
		var ucol := COL_FRIENDLY.lerp(Color(1.0, 0.4, 0.3), 1.0 - Damage.health_fraction(u))
		MapSymbols.draw_surface(self, sp, ucol, false, u.heading_deg)
		if u.submerged():
			MapSymbols.draw_subsurface_mark(self, sp, ucol)
		elif u.airborne():
			MapSymbols.draw_air_mark(self, sp, ucol)
		if selected.has(u):
			MapSymbols.draw_selection(self, sp, COL_SELECT)
		var name := u.callsign
		if selected.has(u):
			name += " / %03d° · %02d kn" % [int(u.heading_deg), int(u.speed_kn)]
		# Two state lamps: emissions and link; details remain in the unit panel.
		draw_circle(sp + Vector2(-5, 19), 2.0, COL_BUOY if u.radar_emitting() else COL_GRID_TEXT)
		if not u.datalink_connected():
			draw_line(sp + Vector2(2, 17), sp + Vector2(7, 22), COL_UNKNOWN, 2.0)
		_place_label(sp, name, COL_TEXT, selected.has(u))



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
	if selected.size() == 1:
		var u := selected[0]
		text += "    FROM %s:  BRG %s  RNG %.1f nm" % [u.callsign, Geo.format_bearing(Geo.bearing_deg(u.position, w)), Geo.distance_nm(u.position, w)]
	if Debug.enabled:
		text += "    [DEBUG]"
	draw_string(_font, Vector2(16.0, 57.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_TEXT)


func _place_label(sp: Vector2, text: String, color: Color, important: bool) -> void:
	if not Rect2(Vector2(0, 65), size - Vector2(0, 160)).has_point(sp): return
	var width := minf(_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 16, 255)
	for attempt in 18:
		var row := (attempt + 1) / 2
		var offset := Vector2(20, -25 + row * 23 * (1 if attempt % 2 == 0 else -1))
		var r := Rect2(sp + offset, Vector2(width, 21))
		if r.end.x > size.x - 12: r.position.x = sp.x - width - 22
		if r.position.y < 67 or r.end.y > size.y - 100: continue
		var overlaps := false
		for used in _label_rects:
			if used.grow(3).intersects(r):
				overlaps = true
				break
		if overlaps: continue
		_label_rects.append(r)
		draw_line(sp, r.get_center(), Color(color, 0.3), 1)
		draw_rect(r, Color("0b1a26"))
		if important: draw_rect(r, Color(color, 0.6), false, 1)
		draw_string(_font, r.position + Vector2(8, 15), text, HORIZONTAL_ALIGNMENT_LEFT, int(width - 16), 12, color)
		return


func _draw_scope() -> void:
	var c := size * 0.5
	var radius := minf(size.x, size.y) * 0.44
	for i in range(1, 5):
		draw_arc(c, radius * i / 4, 0, TAU, 128, Color(0.24, 0.56, 0.65, 0.10), 1, true)
	for deg in range(0, 360, 5):
		var d := Vector2(sin(deg_to_rad(deg)), -cos(deg_to_rad(deg)))
		var major := deg % 30 == 0
		draw_line(c + d * radius, c + d * (radius + (9 if major else 4)), Color(0.4, 0.7, 0.8, 0.25), 1, true)
		if major:
			draw_string(_font, c + d * (radius + 21) + Vector2(-10, 4), "%03d" % deg, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_GRID_TEXT)
	draw_rect(Rect2(0, 0, size.x, 36), Color("0d202d"))
	draw_string(_font, Vector2(16, 23), "TACTICAL PICTURE  /  LOCAL NM GRID", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("70e2d3"))
	draw_string(_font, Vector2(size.x - 206, 23), "NORTH   ·   F2 KEY   ·   F4 RINGS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_TEXT)
	if simulation != null:
		for o in simulation.mission_manager.victory_objectives:
			if o.kind == MissionObjective.Kind.REACH_AREA:
				var sp := world_to_screen(o.center)
				draw_arc(sp, o.radius_nm * ppn, 0, TAU, 80, Color(COL_WAYPOINT, 0.5), 2, true)
				_place_label(sp, "OBJECTIVE / RENDEZVOUS", COL_WAYPOINT, false)


func _draw_key() -> void:
	if not show_key: return
	var y := size.y - 85
	draw_rect(Rect2(12, y, 385, 60), Color("101f2c"))
	MapSymbols.draw_surface(self, Vector2(26, y + 14), COL_FRIENDLY, false, 0)
	MapSymbols.draw_track(self, Vector2(143, y + 14), COL_HOSTILE, true, false, 0)
	MapSymbols.draw_track(self, Vector2(255, y + 14), COL_UNKNOWN, false, false, 0)
	draw_string(_font, Vector2(42, y + 19), "FRIENDLY", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_TEXT)
	draw_string(_font, Vector2(159, y + 19), "HOSTILE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_TEXT)
	draw_string(_font, Vector2(271, y + 19), "UNKNOWN", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_TEXT)
	draw_string(_font, Vector2(25, y + 37), "Arc above: air · below: submarine · ellipse: uncertainty", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_GRID_TEXT)
	draw_string(_font, Vector2(25, y + 52), "Rings: radar blue / sonar green / ESM violet / weapon amber", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_GRID_TEXT)
