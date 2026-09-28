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
## Platforms are NTDS symbols (MapSymbols) in the identity colours with 6-minute velocity leaders
## and white four-digit track numbers; the graphic symbol modes draw the platforms' plan views.
##
## Controls: wheel/pinch or +/- = zoom, middle/right/Option drag = pan, left click = hook,
## shift+click = add/remove unit, left drag = box select, double-click = recentre, Plot Move arms
## the explicit left-click move tool (Shift chains waypoints), arrow keys = pan (the letters are CDS hotkeys), Home = fit the
## fleet, C = focus the current command problem, F = follow it.
## Right-click without a drag: with a controllable own unit hooked, open water (or land, for an
## aircraft) orders it there at once (Shift appends a leg); on anything else it asks the shell for
## a menu (context_menu_requested), hooking the track or own unit under the cursor first. Ctrl/Cmd
## + right-click on a track engages it. In Plot Move, right-click cancels the move.

signal selection_changed(units: Array)
signal track_selected(track: Track)
signal move_order_requested(world_pos: Vector2, append: bool)
signal engage_requested(track: Track)
## Emitted by the shell's "Delete leg" menu item via request_waypoint_delete(); the chart no longer
## deletes a leg on a bare right-click.
signal waypoint_delete_requested(unit: Unit, index: int)
## A right-click the chart does not act on by itself. `screen_pos` is in the chart's own pixels
## (as world_to_screen); `context` is context_at(screen_pos) plus "viewport_pos" for placing a popup.
signal context_menu_requested(screen_pos: Vector2, context: Dictionary)
signal interaction_mode_changed(active: bool)
## Kept for the shell's wiring; the chart has no button of its own that emits it any more.
signal world_view_requested

enum DragMode { NONE, PAN, BOX }
enum InteractionMode { SELECT, MOVE }
## NTDS frames, or the platforms' plan views at three sizes (JFC's graphic symbols).
enum SymbolMode { NTDS, SMALL, MEDIUM, LARGE }
## The quick range circle: off, following the cursor, fixed.
enum RangeCircle { OFF, ARMED, FIXED }

const MIN_PPN := 0.2
const MAX_PPN := 6000.0
const ZOOM_STEP := 1.25
const KEYBOARD_ZOOM_RATE := 4.0
const CLICK_RADIUS_PX := 18.0
const WAYPOINT_HIT_PX := 14.0
const DRAG_THRESHOLD_PX := 5.0
const DOUBLE_CLICK_MS := 350
## Velocity leaders show this much travel (MapSymbols clamps them to 6-48 px).
const LEADER_MINUTES := MapSymbols.LEADER_MINUTES
const KEY_PAN_PX_PER_S := 700.0
## Graphic symbol length, bow to stern, per SymbolMode (NTDS draws frames instead).
const GRAPHIC_SYMBOL_PX: Array[float] = [0.0, 28.0, 40.0, 56.0]
const SYMBOL_MODE_NAMES: Array[String] = ["NTDS", "Small", "Medium", "Large"]
## Track number: white bold, its left edge and baseline this far from the symbol centre.
const TRACK_NUMBER_FONT_SIZE := 12
const TRACK_NUMBER_OFFSET := Vector2(7.0, 17.0)
const TAG_FONT_SIZE := 11
const STALE_ALPHA := 0.55
const UNCERTAINTY_ALPHA := 0.35
const BEARING_LINE_ALPHA := 0.6
const SENSOR_RING_ALPHA := 0.45
## A sunk or shot-down own platform stays on the plot in grey this long (sim seconds).
const WRECK_S := 600.0
## Compatibility shim: the chart has no footer bar any more, but the world view's inset card still
## anchors itself this far above the chart's bottom edge.
const FOOTER_H := 24.0
## Bottom-left readout and bottom-centre radio line.
const READOUT_MARGIN := 10.0
const READOUT_FONT_SIZE := 13
const READOUT_LINE_H := 16.0
const RADIO_BOTTOM_PX := 8.0
const SPEAKER_RING_PX := 14.0
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
## Hook brackets, routes (PIM legs), waypoints, objective areas and the range circle: white.
const COL_SELECT := Color.WHITE
const COL_ROUTE := Color.WHITE
const COL_BOX := Color(1.0, 1.0, 1.0, 0.8)
## The scenario editor's and the mission preview's route and objective colour.
const COL_WAYPOINT := Color(0.55, 0.95, 0.75, 0.85)
## Identity colours, the classic display's: colour means identity and nothing else.
const COL_FRIENDLY := Color8(64, 200, 255)
const COL_ALLIED := Color8(255, 150, 40)
const COL_HOSTILE := Color8(235, 30, 30)
const COL_UNKNOWN := Color8(245, 235, 30)
const COL_NEUTRAL := Color8(40, 220, 60)
## Destroyed: a lost own platform's grey, and the darker grey for anything else the player saw
## destroyed (the chart itself only ever marks its own losses; a kill report is the shell's).
const COL_DESTROYED_OWN := Color8(200, 200, 200)
const COL_DESTROYED := Color8(110, 110, 110)
## Sensor rings (F4) are thin own-identity circles; these keep their older names for callers.
const COL_RING := Color(COL_FRIENDLY, SENSOR_RING_ALPHA)
const COL_RING_SILENT := Color(COL_FRIENDLY, 0.2)
const COL_SONAR_RING := Color(COL_FRIENDLY, SENSOR_RING_ALPHA)
const COL_SONAR_ACTIVE := Color(COL_FRIENDLY, SENSOR_RING_ALPHA)
const COL_BUOY := COL_FRIENDLY
const COL_ESM_RING := Color(COL_FRIENDLY, SENSOR_RING_ALPHA)
const COL_JAM := Color(COL_FRIENDLY, SENSOR_RING_ALPHA)
const COL_TRUTH := Color(1.0, 0.5, 0.5, 0.45)
## The selected weapon's reach: a thin red circle.
const COL_WEAPON_RING := Color(COL_HOSTILE, 0.9)
## Rounds as the world view colours them (the chart draws rounds in their identity colours).
const COL_MISSILE := Color(1.0, 0.85, 0.35)
const COL_MISSILE_HOSTILE := Color(1.0, 0.45, 0.35)
const COL_INTERCEPTOR := Color(0.55, 0.95, 1.0)
const COL_ACCENT := UITheme.COL_ACCENT
## Compatibility shim: the chart has no label plates any more, but the world view's labels use it.
const COL_LABEL_BG := Color("08111a", 0.9)
const COL_READOUT := Color.WHITE
const COL_READOUT_SHADOW := Color(0.0, 0.0, 0.0, 0.9)
const COL_RADIO_ALERT := Color("ff5050")
const COL_FIRE := Color(1.0, 0.55, 0.22)
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
## Symbol controls: velocity leaders (Shift+V), track numbers (Shift+K), tags (Shift+I), PIM legs.
var show_leaders := true
var show_track_numbers := true
var show_tags := false
var show_routes := true
## Compatibility name for the velocity leaders (the old "vectors" layer, V).
var show_vectors: bool:
	get:
		return show_leaders
	set(value):
		show_leaders = value
## Identity filters (the CDS menu's Filters): a filtered contact is neither drawn nor hit.
var show_hostiles := true
var show_allied := true
var show_neutrals := true
var show_unknowns := true
var symbol_mode := SymbolMode.NTDS
var range_circle := RangeCircle.OFF

var _drag_mode := DragMode.NONE
var _drag_button := MOUSE_BUTTON_NONE
var _drag_start := Vector2.ZERO
var _drag_moved := false
var _mouse := Vector2.ZERO
var _mouse_inside := false
var _last_click_ms: int = -1000000
var _last_click_pos := Vector2.ZERO
var follow_selection := false
var interaction_mode := InteractionMode.SELECT
var keyboard_navigation_enabled := true
var _trail_reference: Unit
var _pending_fit := false
var _fit_center := Vector2.ZERO
var _fit_extent := 0.0
var _font: Font
var _trails: Dictionary = {}  # Unit -> PackedVector2Array (presentation memory only)
var _own_numbers: Dictionary = {}  # Unit -> own track number, stable for the mission
var _wrecks: Dictionary = {}  # own Unit lost -> {pos, domain, rotary, t} (presentation memory only)
var _own_alive: Dictionary = {}  # own Unit -> true while it was alive at the last check
var _range_unit: Unit
var _range_track: Track
var _range_radius_nm := 0.0
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
	# Graphic symbols draw 500-800 px plan views at 28-56 px: sample their mipmaps, not a shimmer.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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


## Every switchable chart layer and the member that holds it. One state path serves the
## shortcuts, the palette and the menus. "terrain" (F6) and "relief" are the same switch, relief
## shading (land and water are always drawn); "vectors" is the old name of "leaders"; "threats"
## is the CDS menu's name for the hostile filter.
const LAYERS := {
	"key": "show_key",
	"sensors": "show_rings",
	"trails": "show_trails",
	"terrain": "show_terrain",
	"relief": "show_terrain",
	"leaders": "show_leaders",
	"vectors": "show_leaders",
	"track_numbers": "show_track_numbers",
	"tags": "show_tags",
	"routes": "show_routes",
	"range_grid": "show_range_grid",
	"graticule": "show_graticule",
	"latlon": "show_latlon",
	"scale": "show_scale",
	"hostiles": "show_hostiles",
	"threats": "show_hostiles",
	"allied": "show_allied",
	"neutrals": "show_neutrals",
	"unknowns": "show_unknowns",
}


## Flips a layer and returns its new state (false for a name the chart does not know).
func toggle_layer(layer: String) -> bool:
	if not LAYERS.has(layer):
		return false
	var member: String = LAYERS[layer]
	set(member, not bool(get(member)))
	return bool(get(member))


## Whether a layer is showing, for menus that draw check marks.
func has_layer(layer: String) -> bool:
	return bool(get(LAYERS[layer])) if LAYERS.has(layer) else false


## Tab: NTDS -> small -> medium -> large graphic symbols -> NTDS. Returns the new mode.
func cycle_symbol_mode() -> SymbolMode:
	set_symbol_mode((symbol_mode + 1) % SymbolMode.size())
	return symbol_mode


func set_symbol_mode(mode: int) -> void:
	symbol_mode = clampi(mode, 0, SymbolMode.size() - 1) as SymbolMode


func symbol_mode_name() -> String:
	return SYMBOL_MODE_NAMES[symbol_mode]


## B: the quick range circle. The first call arms a white circle centred on the hooked unit (the
## hooked contact when no own unit is hooked) through the cursor; the second fixes its radius; the
## third clears it. Returns the new state; with nothing hooked it stays off.
func toggle_range_circle() -> RangeCircle:
	match range_circle:
		RangeCircle.OFF:
			_range_unit = selected[0] if not selected.is_empty() else null
			_range_track = selected_track if _range_unit == null else null
			if _range_unit != null or _range_track != null:
				range_circle = RangeCircle.ARMED
				_range_radius_nm = _range_centre().distance_to(screen_to_world(_mouse))
		RangeCircle.ARMED:
			_range_radius_nm = _range_centre().distance_to(screen_to_world(_mouse))
			range_circle = RangeCircle.FIXED
		_:
			_clear_range_circle()
	return range_circle


## The quick range circle's radius in nautical miles (0 when off).
func range_circle_nm() -> float:
	if range_circle == RangeCircle.OFF:
		return 0.0
	if range_circle == RangeCircle.ARMED:
		return _range_centre().distance_to(screen_to_world(_mouse))
	return _range_radius_nm


func _range_centre() -> Vector2:
	if _range_unit != null:
		return _range_unit.position
	return _range_track.position if _range_track != null else Vector2.ZERO


func _clear_range_circle() -> void:
	range_circle = RangeCircle.OFF
	_range_unit = null
	_range_track = null
	_range_radius_nm = 0.0


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
	_record_wrecks()
	if (_range_unit != null and not _range_unit.alive) or (_range_track != null and _range_track.status == Track.Status.LOST):
		_clear_range_circle()
	queue_redraw()


## Own platforms lost this mission, remembered where they went down so the plot shows them in
## grey for a while. Own units only: an opposing loss is never shown unless the plot saw it.
func _record_wrecks() -> void:
	if unit_manager == null:
		return
	var now := SimClock.sim_time
	for u: Unit in unit_manager.units:
		if u.faction != player_faction:
			continue
		if u.alive:
			if not u.is_aircraft() or u.in_flight():
				_own_alive[u] = true
			else:
				_own_alive.erase(u)  # back aboard: a deck loss is its ship's, not its own mark
		elif _own_alive.has(u):
			_own_alive.erase(u)
			var domain := "air" if u.is_aircraft() else u.spec.domain
			_wrecks[u] = {"pos": u.position, "domain": domain, "rotary": u.spec.can_hover, "t": now}
	for u in _wrecks.keys():
		var t: float = _wrecks[u]["t"]
		if now - t > WRECK_S or now < t:
			_wrecks.erase(u)


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
	# Flashes are white: on this chart a colour means an identity. A refused order reads in the
	# radio line's alert red.
	var col := COL_READOUT
	match kind:
		"miss", "splash", "decoy":
			col = Color(COL_READOUT, 0.7)
		"refused":
			col = COL_RADIO_ALERT
	_effects.append({"pos": pos, "t0": _anim, "kind": kind, "color": col})
	if _effects.size() > 40:
		_effects.remove_at(0)


func reset_presentation() -> void:
	_radio.clear()
	_trails.clear()
	_own_numbers.clear()
	_wrecks.clear()
	_own_alive.clear()
	_clear_range_circle()
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
	# Arrow keys only: A, W and S are command-screen hotkeys (status boards, route, scale), and a
	# tap on one of them must not also nudge the chart.
	if Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_UP):
		dir.y += 1.0
	if Input.is_key_pressed(KEY_DOWN):
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
				var clicked := not _drag_moved
				_end_drag()
				if clicked:
					_right_click(e)


## A right-click without a drag, the classic display's way: transit at once on open water with a
## controllable unit hooked, otherwise hook what is under the cursor and ask the shell for a menu.
func _right_click(e: InputEventMouseButton) -> void:
	var ctx := context_at(e.position)
	match String(ctx["kind"]):
		"track":
			var t: Track = ctx["track"]
			if e.ctrl_pressed or e.meta_pressed:
				engage_requested.emit(t)
				return
			select_track(t)
		"own_unit":
			var u: Unit = ctx["unit"]
			if not selected.has(u):
				select_units([u])
		"water", "empty":
			var world: Vector2 = ctx["world_pos"]
			if _has_controllable_selection() and int(_move_acceptance(world)["accepted"]) > 0:
				move_order_requested.emit(world, e.shift_pressed)
				return
	ctx["viewport_pos"] = get_global_transform_with_canvas() * e.position if is_inside_tree() else e.position
	context_menu_requested.emit(e.position, ctx)


## What a right-click at this chart pixel is on, for the shell's menus: kind is "own_unit",
## "track", "waypoint", "water" (open water) or "empty" (land the chart shows); the matching
## fields are filled and the rest are null / -1. Own units win over contacts, and both over a
## waypoint, as they do for a left-click.
func context_at(screen_pos: Vector2) -> Dictionary:
	var world := screen_to_world(screen_pos)
	var ctx := {"kind": "water", "unit": null, "track": null, "waypoint_unit": null, "waypoint_index": -1, "world_pos": world}
	var u := _unit_at(screen_pos)
	if u != null:
		ctx["kind"] = "own_unit"
		ctx["unit"] = u
		return ctx
	var t := _track_at(screen_pos)
	if t != null:
		ctx["kind"] = "track"
		ctx["track"] = t
		return ctx
	var wp := _waypoint_at(screen_pos)
	if not wp.is_empty():
		ctx["kind"] = "waypoint"
		ctx["waypoint_unit"] = wp["unit"]
		ctx["waypoint_index"] = wp["index"]
		return ctx
	if _chart_land_at(world):
		ctx["kind"] = "empty"
	return ctx


## The shell's "Delete leg" for a waypoint the chart reported in a context menu.
func request_waypoint_delete(unit: Unit, index: int) -> void:
	if unit != null and index >= 0 and index < unit.waypoints.size():
		waypoint_delete_requested.emit(unit, index)


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


## The contacts the chart draws: those this reference holds, less any identity the Filters hide.
func _plotted_tracks() -> Array:
	var all := _visible_tracks()
	if show_hostiles and show_allied and show_neutrals and show_unknowns:
		return all
	return all.filter(func(t: Track) -> bool: return identity_shown(t.identity))


func identity_shown(identity: String) -> bool:
	match identity:
		"HOSTILE":
			return show_hostiles
		"NEUTRAL":
			return show_neutrals
		"ALLIED":
			return show_allied
		"FRIENDLY":
			return true
	return show_unknowns


func _track_at(screen_pos: Vector2) -> Track:
	var best: Track = null
	var best_d := CLICK_RADIUS_PX
	for t: Track in _plotted_tracks():
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


## An own platform's stable track number (1, 2, ...): roster order, assigned on first sight and
## kept for the mission, so a loss, a launch or a landing never renumbers the rest.
func own_track_number(u: Unit) -> int:
	if not _own_numbers.has(u):
		if unit_manager != null:
			for other: Unit in unit_manager.units:
				if other.faction == player_faction and not _own_numbers.has(other):
					_own_numbers[other] = _own_numbers.size() + 1
		if not _own_numbers.has(u):
			_own_numbers[u] = _own_numbers.size() + 1
	return int(_own_numbers[u])


## The four-digit track number the chart prints beside an own Unit or a contact Track, for the
## data display and menus to quote the same number.
func track_number_text(item: Variant) -> String:
	if item is Unit:
		return MapSymbols.own_track_number(own_track_number(item))
	if item is Track:
		return MapSymbols.track_number((item as Track).id)
	return ""


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
	_draw_range_circle()
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
	_draw_hover_card()


## Plot Move: dashed white legs from each hooked unit to the cursor (red past a coast in the way),
## a crosshair at the cursor, and what a click there would do.
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
			draw_dashed_line(a, beach, COL_ROUTE, 1.0, 6.0)
			draw_dashed_line(beach, _mouse, Color(COL_HOSTILE, 0.9), 1.0, 6.0)
		else:
			draw_dashed_line(a, _mouse, COL_ROUTE, 1.0, 6.0)
	var col := COL_HOSTILE if accepted == 0 else COL_ROUTE
	var m := _mouse.round() + Vector2(0.5, 0.5)
	draw_arc(m, 7.0, 0.0, TAU, 24, col, 1.0, true)
	for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(m + d * 10.0, m + d * 15.0, col, 1.0)
	var label := "Land - pick water" if accepted == 0 else ("%d of %d can move here" % [accepted, total] if accepted < total else ("Add waypoint" if append else "Set course"))
	_shadow_text(_mouse + Vector2(17, -10), label, 11, COL_RADIO_ALERT if accepted == 0 else COL_READOUT)


func _move_acceptance(target: Vector2) -> Dictionary:
	var total := 0
	var accepted := 0
	var target_is_land := _chart_land_at(target)
	for u: Unit in selected:
		if u.faction != player_faction or not u.alive or not u.is_engageable() or u.spec.max_speed_kn <= 0.0 or (u.is_aircraft() and not u.airborne()):
			continue
		total += 1
		if not target_is_land or not u.needs_sea_room():
			accepted += 1
	return {"accepted": accepted, "total": total}


## Land as the chart draws it: the scenario's coastline polygons inside the charted box, and beyond
## it the raster's own coast (with a floor in the tree to say where the box is). A hull is never
## sent onto land the player can see, even where the simulation's polygons stop.
func _chart_land_at(w: Vector2) -> bool:
	if not Terrain.is_empty() and Terrain.is_land(w):
		return true
	if _floor == null or not Bathymetry.active or _floor.charted_rect().has_point(w):
		return false
	var depth := Bathymetry.depth_at(w)
	return depth >= 0.0 and depth < 0.5


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
	if (_land == null or not _land.is_inside_tree()) and Terrain.bounds.intersects(view):
		var mesh := ChartLand.land_mesh()
		if mesh != null:
			draw_mesh(mesh, null, Transform2D(Vector2(ppn, 0), Vector2(0, ppn), world_to_screen(Vector2.ZERO)), COL_LAND)
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


## The scenario's place names in the chart's white bold with a shadow and no plate: a land name
## beside a small white + at its position, a sea name centred on it.
func _draw_chart_labels() -> void:
	var m := _geo_map()
	var safe := Rect2(Vector2(8, 8), size - Vector2(16, 16))
	var occupied: Array[Rect2] = []
	var font := _readout_font()
	for entry in m.get("labels", []):
		var p: Array = entry["position_nm"]
		var at := world_to_screen(Vector2(p[0], p[1])).round()
		var text := str(entry["text"])
		var water: bool = entry.get("kind", "land") == "water"
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var left := roundf(at.x - width / 2) if water else at.x + 6.0
		var rect := Rect2(Vector2(left, at.y - 12), Vector2(width, 18))
		if not water:
			rect = rect.expand(at - Vector2(4, 4))
		if not safe.encloses(rect):
			continue
		var collision := false
		for other in occupied:
			if other.grow(10).intersects(rect): collision = true
		if collision: continue
		occupied.append(rect)
		if water:
			_shadow_text(Vector2(left, at.y), text, 11, Color(COL_READOUT, 0.72))
		else:
			_draw_plus(at, 3.0, COL_READOUT, 1.0, true)
			_shadow_text(Vector2(left, at.y + 4.0), text, 11, Color(COL_READOUT, 0.9))


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


## Mission objective areas: a thin white circle with its name over it, no plate.
func _draw_objectives() -> void:
	if simulation == null:
		return
	var mission := simulation.mission_manager
	for o in mission.victory_objectives + mission.loss_objectives:
		if o.kind != MissionObjective.Kind.REACH_AREA:
			continue
		var sp := world_to_screen(o.center)
		var r := o.radius_nm * ppn
		draw_arc(sp, r, 0.0, TAU, _arc_segments(r), COL_ROUTE, 1.0, true)
		var text := "DENY EXIT" if mission.loss_objectives.has(o) else "OBJECTIVE AREA"
		_centred_text(sp + Vector2(0.0, -maxf(r, 8.0) - 5.0), text, 11)


## F4: each hooked own unit's sensor reach (every own unit's under Debug) as thin own-identity
## circles at 45% alpha: radar and sonar solid, ESM, air search, jammer and a silent radar dashed.
func _draw_sensor_rings() -> void:
	for u in _own_units():
		if not (Debug.enabled or selected.has(u)):
			continue
		var sp := world_to_screen(u.position)
		var esm := Detection.nominal_esm_ring_nm(u)
		if esm > 0.0:
			_draw_dashed_circle(sp, esm * ppn, COL_ESM_RING, 160)
		var sonar := Detection.nominal_passive_ring_nm(u)
		if sonar > 0.0:
			draw_arc(sp, sonar * ppn, 0.0, TAU, _arc_segments(sonar * ppn), COL_SONAR_RING, 1.0, true)
		if Acoustics.cz_available(u):
			_draw_convergence_zones(sp)
		var active := Detection.best_active_sonar_nm(u)
		if active > 0.0:
			draw_arc(sp, active * ppn, 0.0, TAU, _arc_segments(active * ppn), COL_SONAR_ACTIVE, 1.0, true)
		if u.has_jammer():
			for s in u.sensors:
				if s.kind == "jammer":
					_draw_dashed_circle(sp, s.jam_range_nm * ppn, COL_JAM if u.jamming() else COL_RING_SILENT, 64)
					_ring_label(sp, s.jam_range_nm * ppn, "EA reach" if u.jamming() else "EA off")
		var r := Detection.nominal_radar_ring_nm(u)
		if r <= 0.0:
			continue
		var air := 0.0
		for s in u.sensors:
			if s.kind == "radar":
				air = maxf(air, s.range_air_nm)
		if air > r + 1.0 and u.radar_emitting():
			_draw_dashed_circle(sp, air * ppn, COL_RING, 96)
			_ring_label(sp, air * ppn, "Air search %s nm" % Geo.format_nm(air))
		if u.radar_emitting():
			draw_arc(sp, r * ppn, 0.0, TAU, _arc_segments(r * ppn), COL_RING, 1.0, true)
		else:
			_draw_dashed_circle(sp, r * ppn, COL_RING_SILENT, 128)
			_ring_label(sp, r * ppn, "Radar silent")


## Convergence-zone annuli: where sound from a loud source comes back to the surface in deep
## water. Each zone is a pair of dashed rings with its number, because a contact out there is heard
## in the ring, not between the rings.
func _draw_convergence_zones(sp: Vector2) -> void:
	for z: Dictionary in Acoustics.zones():
		var r: float = float(z["range_nm"]) * ppn
		var hw: float = float(z["half_width_nm"]) * ppn
		if r + hw < 8.0:
			continue
		var col := Color(COL_SONAR_RING, COL_SONAR_RING.a * (1.0 if int(z["index"]) == 1 else 0.7))
		_draw_dashed_circle(sp, r - hw, col, 96)
		_draw_dashed_circle(sp, r + hw, col, 96)
		_shadow_text(sp + Vector2(r * 0.7071 + 4.0, -r * 0.7071), "CZ%d" % int(z["index"]), 10, Color(COL_READOUT, 0.7))


## A ring's name over its top, in the readout style.
func _ring_label(c: Vector2, r: float, text: String) -> void:
	_centred_text(c + Vector2(0.0, -r - 4.0), text, 10, Color(COL_READOUT, 0.8))


func _draw_dashed_circle(c: Vector2, r: float, col: Color, segs: int) -> void:
	for i in segs:
		if i % 2 == 1:
			continue
		var a0 := TAU * float(i) / segs
		var a1 := TAU * float(i + 1) / segs
		draw_arc(c, r, a0, a1, 4, col, 1.0, true)


## Enough segments that a circle stays round at any radius the chart can show.
static func _arc_segments(r: float) -> int:
	return clampi(int(r * 0.35), 32, 360)


## The selected weapon's reach from each hooked shooter that carries it: a thin red circle, its
## minimum range dashed, and the firing solution when the hooked contact can be engaged.
func _draw_weapon_ring() -> void:
	if weapon_ring == null:
		return
	for u in _own_units():
		if not selected.has(u) or u.magazine_count(weapon_ring.id) <= 0:
			continue
		var sp := world_to_screen(u.position)
		var outer := weapon_ring.max_range_nm * ppn
		draw_arc(sp, outer, 0.0, TAU, _arc_segments(outer), COL_WEAPON_RING, 1.0, true)
		if weapon_ring.min_range_nm > 0.5:
			_draw_dashed_circle(sp, weapon_ring.min_range_nm * ppn, Color(COL_WEAPON_RING, 0.5), 48)
		# Keep the ring's name on the chart when its top edge runs off the top.
		_centred_text(sp + Vector2(0.0, maxf(-outer - 5.0, 16.0 - sp.y)), "%s  %s nm" % [weapon_ring.display_name, Geo.format_nm(weapon_ring.max_range_nm)], 11)
		if selected_track == null or not Combat.suits_track(weapon_ring, selected_track) or not Combat.check_engagement(u, weapon_ring, selected_track)["ok"]:
			continue
		# The firing solution: where the round would meet the contact if it held course.
		var aim := Combat.intercept_point(u.position, weapon_ring.speed_kn, selected_track.position, selected_track.course_deg, selected_track.speed_kn, selected_track.has_kinematics)
		var ap := world_to_screen(aim)
		draw_dashed_line(sp, ap, Color(COL_WEAPON_RING, 0.6), 1.0, 6.0)
		draw_arc(ap, 6.0, 0.0, TAU, 16, COL_WEAPON_RING, 1.0, true)
		draw_line(ap + Vector2(-9, 0), ap + Vector2(9, 0), COL_WEAPON_RING, 1.0)
		draw_line(ap + Vector2(0, -9), ap + Vector2(0, 9), COL_WEAPON_RING, 1.0)
		var tof := Combat.time_of_flight_s(weapon_ring, u.position.distance_to(aim))
		_shadow_text(ap + Vector2(10, -8), "Solution  %ds" % int(tof), 11)


## Own sonobuoys: 3 px dots.
func _draw_sonobuoys() -> void:
	if aviation_manager == null:
		return
	for b: Sonobuoy in aviation_manager.sonobuoys:
		if b.faction == player_faction:
			MapSymbols.draw_buoy(self, world_to_screen(b.position), COL_BUOY)


func _draw_truth() -> void:
	for u in unit_manager.units:
		if not u.is_engageable() or u.faction == player_faction:
			continue
		var sp := world_to_screen(u.position)
		MapSymbols.draw_ntds(self, sp, COL_TRUTH, MapSymbols.Frame.HOSTILE, _unit_domain(u), u.spec.can_hover)
		MapSymbols.draw_leader(self, sp, u.heading_deg, MapSymbols.leader_px(u.speed_kn, ppn), COL_TRUTH)
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
		"ALLIED":
			return COL_ALLIED
	return COL_UNKNOWN


## The symbol's domain as drawn: an airframe is always an air symbol and a boat deep enough to be
## hidden a subsurface one; a boat on the surface is a surface ship.
static func _unit_domain(u: Unit) -> String:
	if u.is_aircraft():
		return "air"
	return "subsurface" if u.submerged() else u.spec.domain


func _draw_tracks() -> void:
	var ref := reference_unit()
	var view := Rect2(Vector2.ZERO, size).grow(64.0)
	for t: Track in _plotted_tracks():
		var sp := world_to_screen(t.position)
		var col := track_color(t)
		if t.status == Track.Status.STALE:
			col.a = STALE_ALPHA
		_draw_uncertainty(sp, t, col)
		if show_trails:
			_draw_track_history(t, col)
		if t.is_bearing_only() and ref != null:
			# A bearing line from the listener through the contact: this is all it really is.
			var from := ref.position
			var far := from + (t.position - from).normalized() * (from.distance_to(t.position) + t.error_major_nm)
			draw_line(world_to_screen(from), world_to_screen(far), Color(col, col.a * BEARING_LINE_ALPHA), 1.0, true)
		if not view.has_point(sp):
			continue
		sp = sp.round()
		var rotary := t.classification >= Track.Classification.CLASS_KNOWN and MapSymbols.is_rotary(t.known_category)
		var extent := _draw_platform(sp, col, MapSymbols.frame_for_identity(t.identity), t.domain, rotary, _track_platform(t), t.course_deg if t.has_kinematics else 0.0)
		if show_leaders and t.has_kinematics and not t.is_bearing_only():
			MapSymbols.draw_leader(self, sp, t.course_deg, MapSymbols.leader_px(t.speed_kn, ppn), col, extent)
		if selected_track == t:
			# The hook when it stands alone; the target (in its identity colour) when a shooter is hooked too.
			MapSymbols.draw_brackets(self, sp, COL_SELECT if selected.is_empty() else track_color(t), _bracket_box(extent))
		_draw_track_number(sp, extent, MapSymbols.track_number(t.id), t.description(), col.a)


## One platform: its plan view in a graphic symbol mode when there is art for it, the NTDS frame
## otherwise. Returns the symbol's half-size, where leaders start and the number sits.
func _draw_platform(sp: Vector2, col: Color, frame: MapSymbols.Frame, domain: String, rotary: bool, platform_id: String, course_deg: float) -> float:
	if symbol_mode != SymbolMode.NTDS and platform_id != "":
		var length := GRAPHIC_SYMBOL_PX[symbol_mode]
		if MapSymbols.draw_graphic(self, sp, platform_id, course_deg, length, col):
			return length * 0.5
	MapSymbols.draw_ntds(self, sp, col, frame, domain, rotary)
	return MapSymbols.RADIUS


## The platform whose art stands for a contact: only once its class is known, and only from what
## the plot holds.
func _track_platform(t: Track) -> String:
	if symbol_mode == SymbolMode.NTDS or t.classification < Track.Classification.CLASS_KNOWN:
		return ""
	return MapSymbols.platform_for_class(t.known_class, t.known_category)


static func _bracket_box(extent: float) -> float:
	return maxf(MapSymbols.BRACKET_BOX, extent * 2.0 + 8.0)


## The white track number at the symbol's lower right and, with tags on, the name or
## classification under it. Both in the readout style; `alpha` fades them with a stale track.
func _draw_track_number(sp: Vector2, extent: float, number: String, tag: String, alpha := 1.0) -> void:
	var at := sp + TRACK_NUMBER_OFFSET + Vector2.ONE * (extent - MapSymbols.RADIUS) * 0.4
	if show_track_numbers and number != "":
		_shadow_text(at, number, TRACK_NUMBER_FONT_SIZE, Color(COL_READOUT, alpha))
		at.y += TRACK_NUMBER_FONT_SIZE + 1.0
	if show_tags and tag != "":
		_shadow_text(at, tag, TAG_FONT_SIZE, Color(COL_READOUT, alpha))


## F5: the last few plots that built the track, as fading 2 px dots. Reports only, never a line
## through a gap in coverage.
func _draw_track_history(t: Track, col: Color) -> void:
	var n := t.history_positions.size()
	if n < 2:
		return
	for i in n:
		var age := maxf(SimClock.sim_time - t.history_times[i], 0.0)
		var alpha := col.a * 0.5 * clampf(1.0 - age / 1440.0, 0.0, 1.0)
		if alpha >= 0.03:
			draw_circle(world_to_screen(t.history_positions[i]), 1.0, Color(col, alpha), true, -1.0, true)


## Uncertainty is an ellipse, 1 px at 35% alpha. For a passive sonar contact it is a long thin
## sliver lying along the bearing, which is the whole difference between hearing something and
## knowing where it is.
func _draw_uncertainty(sp: Vector2, t: Track, col: Color) -> void:
	var major := t.error_major_nm * ppn
	var minor := t.error_minor_nm * ppn
	if maxf(major, minor) <= MapSymbols.RADIUS + 3.0:
		return
	var ang := deg_to_rad(t.error_axis_deg)
	var axis := Vector2(sin(ang), -cos(ang))
	var perp := axis.orthogonal()
	var pts := PackedVector2Array()
	for i in 49:
		var th := TAU * float(i) / 48.0
		pts.append(sp + axis * (cos(th) * major) + perp * (sin(th) * minor))
	draw_polyline(pts, Color(col, col.a * UNCERTAINTY_ALPHA), 1.0, true)


func _draw_units() -> void:
	for u: Unit in _wrecks:
		var wreck: Dictionary = _wrecks[u]
		MapSymbols.draw_ntds(self, world_to_screen(wreck["pos"]).round(), COL_DESTROYED_OWN, MapSymbols.Frame.FRIENDLY, wreck["domain"], wreck["rotary"])
	var view := Rect2(Vector2.ZERO, size).grow(64.0)
	for u in _own_units():
		var sp := world_to_screen(u.position)
		if show_trails and _trails.has(u):
			var arr: PackedVector2Array = _trails[u]
			for i in arr.size():
				var dot := world_to_screen(arr[i])
				if dot.distance_to(sp) > MapSymbols.RADIUS + 2.0:
					draw_circle(dot, 1.0, Color(COL_FRIENDLY, 0.1 + 0.4 * float(i + 1) / float(arr.size())), true, -1.0, true)
		if show_routes:
			_draw_route(u, sp)
		if u.in_formation():
			var station := world_to_screen(Formation.station_for(u))
			draw_dashed_line(sp, station, Color(COL_ROUTE, 0.3), 1.0, 3.0)
			draw_rect(Rect2(station - Vector2(2.5, 2.5), Vector2(5, 5)), Color(COL_ROUTE, 0.5), false, 1.0)
		if not view.has_point(sp):
			continue
		sp = sp.round()
		var extent := _draw_platform(sp, COL_FRIENDLY, MapSymbols.Frame.FRIENDLY, _unit_domain(u), u.spec.can_hover, u.spec.id, u.heading_deg)
		if show_leaders:
			MapSymbols.draw_leader(self, sp, u.heading_deg, MapSymbols.leader_px(u.speed_kn, ppn), COL_FRIENDLY, extent)
		if selected.has(u):
			MapSymbols.draw_brackets(self, sp, COL_SELECT, _bracket_box(extent))
		_draw_casualty_ticks(u, sp, extent)
		_draw_threat_marks(u, sp)
		_draw_track_number(sp, extent, track_number_text(u), u.callsign)


## A route as PIM legs: thin white lines from the symbol's edge through small white + waypoints.
## Where the coast is in the way of a hooked hull's leg, the leg turns red past the beach, with an
## X where it hits.
func _draw_route(u: Unit, sp: Vector2) -> void:
	if u.waypoints.is_empty():
		return
	var prev := sp
	var first := world_to_screen(u.waypoints[0])
	if first.distance_to(sp) > MapSymbols.RADIUS:
		prev = sp + (first - sp).normalized() * MapSymbols.RADIUS
	var prev_world := u.position
	var check_land := selected.has(u) and u.needs_sea_room() and not Terrain.is_empty()
	for wp in u.waypoints:
		var wsp := world_to_screen(wp)
		var hit := Terrain.first_land_contact(prev_world, wp) if check_land else -1.0
		if hit >= 0.0:
			# The leg is legal to order but the coast is in the way; show where.
			var beach := world_to_screen(prev_world.lerp(wp, hit))
			draw_line(prev, beach, COL_ROUTE, 1.0, true)
			draw_dashed_line(beach, wsp, Color(COL_HOSTILE, 0.8), 1.0, 5.0)
			draw_line(beach - Vector2(4, 4), beach + Vector2(4, 4), COL_HOSTILE, 1.5, true)
			draw_line(beach - Vector2(4, -4), beach + Vector2(4, -4), COL_HOSTILE, 1.5, true)
		else:
			draw_line(prev, wsp, COL_ROUTE, 1.0, true)
		var hovered := _mouse_inside and _drag_mode == DragMode.NONE and wsp.distance_to(_mouse) <= WAYPOINT_HIT_PX
		_draw_plus(wsp, 5.0 if hovered else 3.5, COL_ROUTE, 2.0 if hovered else 1.0)
		prev = wsp
		prev_world = wp


## A small + mark: waypoints and place names.
func _draw_plus(c: Vector2, arm: float, col: Color, width := 1.0, shadow := false) -> void:
	var p := c.round() + Vector2(0.5, 0.5)
	if shadow:
		var s := Color(COL_READOUT_SHADOW, COL_READOUT_SHADOW.a * col.a)
		draw_line(p + Vector2(1.0 - arm, 1.0), p + Vector2(1.0 + arm, 1.0), s, width)
		draw_line(p + Vector2(1.0, 1.0 - arm), p + Vector2(1.0, 1.0 + arm), s, width)
	draw_line(p + Vector2(-arm, 0.0), p + Vector2(arm, 0.0), col, width)
	draw_line(p + Vector2(0.0, -arm), p + Vector2(0.0, arm), col, width)


## Fire and flooding aboard: a short orange and a short red tick left of the symbol. The rest of
## the damage picture is the data display's.
func _draw_casualty_ticks(u: Unit, sp: Vector2, extent: float) -> void:
	var x := sp.x - extent - 4.0
	if u.fire > 0.0:
		draw_line(Vector2(x, sp.y - 7.0), Vector2(x, sp.y - 1.0), COL_FIRE, 2.0)
		x -= 4.0
	if u.flooding > 0.0:
		draw_line(Vector2(x, sp.y - 7.0), Vector2(x, sp.y - 1.0), COL_HOSTILE, 2.0)


## Rounds detected inbound on this ship: a pulsing ring, a line back to the round and its time to go.
func _draw_threat_marks(u: Unit, sp: Vector2) -> void:
	for entry: Dictionary in _threats:
		if entry["target"] != u:
			continue
		var w: Weapon = entry["weapon"]
		MapSymbols.draw_threat_ring(self, sp, COL_HOSTILE, _anim)
		var wp := world_to_screen(w.position)
		draw_line(wp, sp, Color(COL_HOSTILE, 0.35), 1.0, true)
		_shadow_text((wp + sp) * 0.5 + Vector2(4.0, -4.0), "%ds" % int(entry["time_s"]), 11)


## The hooked pair's relative motion (the hooked own unit and its target): where each will be at
## the closest point of approach, in thin white.
func _draw_relative_motion() -> void:
	if selected_track == null or selected.is_empty():
		return
	var ref := reference_unit()
	var solution := RelativeMotion.solution(ref, selected_track, SimClock.sim_time)
	if not solution.valid:
		return
	var own_end := world_to_screen(solution.own_position)
	var contact_end := world_to_screen(solution.contact_position)
	draw_dashed_line(world_to_screen(ref.position), own_end, Color(COL_ROUTE, 0.6), 1.0, 6.0)
	draw_dashed_line(world_to_screen(selected_track.position), contact_end, Color(COL_ROUTE, 0.6), 1.0, 6.0)
	draw_line(own_end, contact_end, Color(COL_ROUTE, 0.85), 1.0, true)
	for endpoint: Vector2 in [own_end, contact_end]:
		draw_arc(endpoint, 4.0, 0.0, TAU, 16, Color(COL_ROUTE, 0.85), 1.0, true)
	var middle := own_end.lerp(contact_end, 0.5)
	_shadow_text(middle + Vector2(4, -4), "CPA %.1f nm / %s" % [solution.distance_nm, Track._fmt_age(solution.time_s)], 11)


## Rounds in flight: own ones always, an opposing one only while the plot holds it. Each is a small
## filled arrowhead (a dot for a torpedo) in its identity colour with a thin fading trail.
func _draw_weapons() -> void:
	if weapon_manager == null:
		return
	var ref := reference_unit()
	for w: Weapon in weapon_manager.in_flight:
		var own := w.faction == player_faction
		var detected := ref != null and threat_manager != null and threat_manager.visible_to(ref, w)
		if not own and not detected and not Debug.enabled:
			continue  # an undetected round is invisible, which is the whole problem
		var sp := world_to_screen(w.position)
		var col := COL_FRIENDLY if own else COL_HOSTILE
		if w.is_interceptor() and w.intercept_target != null:
			draw_line(sp, world_to_screen(w.intercept_target.position), Color(col, 0.3), 1.0, true)
		elif own and w.target_track != null and w.phase == Weapon.Phase.CRUISE:
			draw_dashed_line(sp, world_to_screen(w.aim_point), Color(col, 0.3), 1.0, 5.0)
		if _weapon_trails.has(w.id):
			var arr: PackedVector2Array = _weapon_trails[w.id]
			for i in range(1, arr.size()):
				var f := float(i) / float(arr.size())
				draw_line(world_to_screen(arr[i - 1]), world_to_screen(arr[i]), Color(col, 0.05 + 0.35 * f), 1.0, true)
		MapSymbols.draw_weapon(self, sp, w.heading_deg, col, w.spec.is_torpedo())
		if Debug.enabled:
			draw_dashed_line(sp, world_to_screen(w.aim_point), Color(col, 0.4), 1.0, 5.0)


## B: the quick range circle, white, with its radius in nmi over its top.
func _draw_range_circle() -> void:
	if range_circle == RangeCircle.OFF:
		return
	var c := world_to_screen(_range_centre())
	var nm := range_circle_nm()
	var r := nm * ppn
	if r < 2.0:
		return
	draw_arc(c, r, 0.0, TAU, _arc_segments(r), COL_ROUTE, 1.0, true)
	_centred_text(c + Vector2(0.0, maxf(-r - 5.0, 16.0 - c.y)), ChartReadout.format_range_nmi(nm), READOUT_FONT_SIZE)


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

static var _bold_font: Font

## The chart's text face: a bold cut of the theme's data sans, for the track numbers and readouts.
func _readout_font() -> Font:
	if _bold_font == null:
		_bold_font = UITheme.data_font()
	return _bold_font


## White bold text with a 1 px black drop shadow and no plate, the chart's only text style.
func _shadow_text(at: Vector2, text: String, font_size: int, col := COL_READOUT, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var font := _readout_font()
	draw_string(font, at + Vector2(1.0, 1.0), text, align, width, font_size, Color(COL_READOUT_SHADOW, COL_READOUT_SHADOW.a * col.a))
	draw_string(font, at, text, align, width, font_size, col)


func _draw_text_block(first_baseline: Vector2, lines: PackedStringArray, col := COL_READOUT) -> void:
	for i in lines.size():
		_shadow_text(first_baseline + Vector2(0.0, i * READOUT_LINE_H), lines[i], READOUT_FONT_SIZE, col)


## Readout text centred on a point of its baseline, whole-pixel aligned.
func _centred_text(baseline_centre: Vector2, text: String, font_size: int, col := COL_READOUT) -> void:
	var w := _readout_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_shadow_text(Vector2(roundf(baseline_centre.x - w * 0.5), roundf(baseline_centre.y)), text, font_size, col)


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
	var land := _chart_land_at(w)
	var depth := Bathymetry.depth_at(w)
	var height := ChartRelief.height_at(w) if land else -1.0
	if land and height < 0.0 and not Bathymetry.active:
		return ""
	return ChartReadout.depth_line(land, maxf(height, 0.0), depth)


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


## F2: the symbol key, top-left, in the chart's plain white readout style with no card behind it.
func _draw_key() -> void:
	if not show_key:
		return
	var rect := _symbol_key_rect()
	var x := rect.position.x
	var y := rect.position.y
	var font := _readout_font()
	_shadow_text(Vector2(x, y + 12), "SYMBOL KEY  (F2 hides)", 11)
	# Identity down, domain across: the frame is the whole symbol.
	var col_x: Array[float] = [x + 96.0, x + 150.0, x + 204.0]
	var cy := y + 34.0
	for i in 3:
		_centred_text(Vector2(col_x[i], cy), ["Air", "Surface", "Sub"][i], 11, Color(COL_READOUT, 0.8))
	var rows := [
		[COL_FRIENDLY, MapSymbols.Frame.FRIENDLY, "Own"],
		[COL_ALLIED, MapSymbols.Frame.ALLIED, "Allied"],
		[COL_HOSTILE, MapSymbols.Frame.HOSTILE, "Hostile"],
		[COL_UNKNOWN, MapSymbols.Frame.UNKNOWN, "Unknown"],
		[COL_NEUTRAL, MapSymbols.Frame.NEUTRAL, "Neutral"],
	]
	for row: Array in rows:
		cy += 22.0
		_shadow_text(Vector2(x, cy + 4.0), row[2], 11)
		for i in 3:
			MapSymbols.draw_ntds(self, Vector2(col_x[i], cy), row[0], row[1], ["air", "surface", "subsurface"][i])
	cy += 28.0
	var cx := x + 8.0
	MapSymbols.draw_key_entry(self, Vector2(cx, cy), COL_FRIENDLY, MapSymbols.Frame.FRIENDLY, "land", false, "Shore", font, COL_READOUT)
	MapSymbols.draw_key_entry(self, Vector2(cx + 74.0, cy), COL_FRIENDLY, MapSymbols.Frame.FRIENDLY, "air", true, "Helo", font, COL_READOUT)
	MapSymbols.draw_weapon(self, Vector2(cx + 142.0, cy), 45.0, COL_HOSTILE, false)
	_shadow_text(Vector2(cx + 156.0, cy + 4.0), "Missile", 11)
	MapSymbols.draw_weapon(self, Vector2(cx + 222.0, cy), 0.0, COL_HOSTILE, true)
	_shadow_text(Vector2(cx + 232.0, cy + 4.0), "Torpedo", 11)
	MapSymbols.draw_buoy(self, Vector2(cx + 300.0, cy), COL_FRIENDLY)
	_shadow_text(Vector2(cx + 308.0, cy + 4.0), "Buoy", 11)
	var lines := PackedStringArray([
		"Leader: 6 minutes of travel. Grey: destroyed. Faded: stale",
		"Ellipse: position uncertainty. Dots: history (F5)",
		"Shift+V leaders, Shift+K track numbers, Shift+I tags",
		"Tab: graphic symbols (now %s). B: range circle" % symbol_mode_name(),
		"Right-click water: transit there. On a platform: menu",
		"Ctrl/Cmd+right-click a contact: engage",
		"Land tinted by height, relief shading on F6",
		"Double-click: recentre. Home: fit fleet. +/-: zoom",
	])
	cy += 26.0
	for line in lines:
		_shadow_text(Vector2(x, cy), line, 11, Color(COL_READOUT, 0.9))
		cy += 15.0


func _symbol_key_rect() -> Rect2:
	# Top-left, clear of the bottom-left readout. Fitted content keeps out of it while it shows.
	return Rect2(12.0, 12.0, 390.0, 322.0)


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
		lines.append("Right-click for leg options")
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
	lines.append("%s  %s" % [MapSymbols.track_number(t.id), t.description()])
	lines.append("%s · %s · %s" % [t.identity, t.status_text(SimClock.sim_time), t.source.to_upper().replace("_", " ")])
	if t.has_kinematics:
		lines.append("CSE %s  SPD %.0f kts (est)" % [Geo.format_bearing(t.course_deg), t.speed_kn])
	else:
		lines.append("Kinematics estimating")
	lines.append("+/-%.1f nm  ·  observed %s" % [t.position_error_nm, Track._fmt_age(t.observation_time_s)])
	var ref := reference_unit()
	if ref != null and ref.radar_emitting() and Detection.is_jammed_toward(ref, t.position):
		lines.append("Radar jammed on this bearing")
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
