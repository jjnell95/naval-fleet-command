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
signal patrol_order_requested(order: Order)
signal engage_requested(track: Track)
## The classic display's default verbs: a bare right-click on a hostile contact attacks it with
## the hooked platforms, on an unidentified one investigates it. Main issues the orders.
signal attack_requested(track: Track)
signal investigate_requested(track: Track)
## Emitted by the shell's "Delete leg" menu item via request_waypoint_delete(); the chart no longer
## deletes a leg on a bare right-click.
signal waypoint_delete_requested(unit: Unit, index: int)
## A right-click the chart does not act on by itself. `screen_pos` is in the chart's own pixels
## (as world_to_screen); `context` is context_at(screen_pos) plus "viewport_pos" for placing a popup.
signal context_menu_requested(screen_pos: Vector2, context: Dictionary)
signal interaction_mode_changed(active: bool)

enum DragMode { NONE, PAN, BOX }
enum InteractionMode { SELECT, MOVE, PATROL }
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
## Track number: white bold, placed by ChartLabels (its left edge and baseline 7 and 17 px from
## the symbol centre where nothing is in the way).
const TRACK_NUMBER_FONT_SIZE := 14
const TAG_FONT_SIZE := 11
const STALE_ALPHA := 0.55
const UNCERTAINTY_ALPHA := 0.35
const BEARING_LINE_ALPHA := 0.6
const SENSOR_RING_ALPHA := 0.45
## A sunk or shot-down own platform stays on the plot in grey this long (sim seconds).
const WRECK_S := 600.0
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
const COL_OCEAN := Color8(8, 17, 76)
# Flat land for the views without the chart's land shader (the scenario editor and the mission
# preview): the chart's lowland green, and a darker green coastline.
const COL_LAND := Color8(32, 76, 35)
const COL_COAST := Color8(90, 170, 80)
## The chart's own coastline stroke over the shaded land: thin and dark, a hard land/sea edge.
const COL_COASTLINE := Color8(0, 58, 6, 235)
const COL_LAND_LABEL := Color(0.86, 0.92, 0.84, 0.85)
const COAST_MIN_STEP_PX := 1.2  # coastline detail finer than this is dropped as it is invisible
const COAST_STROKE_MIN_PX := 3.0  # a landmass smaller than this on screen is filled, not stroked
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
var show_weapon_ranges := false
var weapon_range_role := "all"
var player_faction := "BLUE"
var center_nm := Vector2.ZERO
var ppn := 4.0  # pixels per nautical mile
var selected: Array[Unit] = []
var selected_track: Track = null
## The last object inspected is separate from the platforms receiving commands. A contact can
## drive the data display and camera while the selected shooter remains ready to engage it.
var _inspecting_track := false
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
var _patrol_corner := Vector2.ZERO
var _patrol_started := false
var keyboard_navigation_enabled := true
## A right-click menu is up. Its window takes the keys, but the chart polls the keyboard itself, so
## without this the arrows that walk the menu would scroll the chart underneath it.
var menu_open := false
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
var _threat_candidates: Array = []
var _threat_cache_time := -1.0
var _threat_cache_revision := -1
var _weapon_trails: Dictionary = {}  # weapon id -> PackedVector2Array of recent positions
var _weapon_trail_time := -1.0
var _weapon_trail_revision := -1
var _weapon_trail_threat_revision := -1
var _hit_flash := 0.0
var show_range_grid := false
var _floor: ChartFloor
var _land: ChartLand
var _radio := RadioLine.new()
## Track numbers and tags are queued as the symbols are drawn and printed together afterwards,
## each placed clear of the others (ChartLabels).
var _labels := ChartLabels.new()
var _label_queue: Array = []
var _text_widths: Dictionary = {}  # "text@size" -> px
## A status board covers the chart: its readouts and radio line are not drawn under it.
var overlay_covered := false
var _coast_runs: Dictionary = {}  # Landmass -> Array[PackedVector2Array], clip edges removed
var _coast_key := ""
## The coast projected to the screen for the current view (Landmass -> Array[PackedVector2Array]),
## kept until the view moves: a still chart does not re-project every vertex of Norway each frame.
var _coast_screen: Dictionary = {}
var _coast_view := PackedFloat32Array()


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
	"weapon_ranges": "show_weapon_ranges",
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
	_patrol_started = false
	# A pan or box drag in progress would otherwise never see its release, which the move tool
	# swallows, and stay latched to the pointer.
	if _drag_mode != DragMode.NONE:
		_end_drag()
	mouse_default_cursor_shape = Control.CURSOR_CROSS if interaction_mode != InteractionMode.SELECT else Control.CURSOR_ARROW
	interaction_mode_changed.emit(interaction_mode == InteractionMode.MOVE)


func set_patrol_mode(enabled: bool) -> void:
	set_move_mode(false)
	if enabled and _has_controllable_selection():
		interaction_mode = InteractionMode.PATROL
		_patrol_started = false
		mouse_default_cursor_shape = Control.CURSOR_CROSS
		interaction_mode_changed.emit(false)


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
	if interaction_mode != InteractionMode.SELECT and not _has_controllable_selection():
		interaction_mode = InteractionMode.SELECT
		_patrol_started = false
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		interaction_mode_changed.emit(false)
	if follow_selection and selected_track == null and selected.size() != 1:
		follow_selection = false


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
		if inspection_track() != null:
			_center_world_in_chart(inspection_track().position)
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
	var threat_revision := threat_manager.revision if threat_manager != null else -1
	if _trail_reference == ref and _weapon_trail_time == SimClock.sim_time and _weapon_trail_revision == weapon_manager.revision and _weapon_trail_threat_revision == threat_revision:
		return
	_weapon_trail_time = SimClock.sim_time
	_weapon_trail_revision = weapon_manager.revision
	_weapon_trail_threat_revision = threat_revision
	if _trail_reference != ref:
		_weapon_trails.clear()
		_trail_reference = ref
	var live: Dictionary = {}
	for w: Weapon in weapon_manager.in_flight:
		if w.phase == Weapon.Phase.DEAD:
			continue
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
## `own` marks our own events: our launches and defences, hits on and losses of our units. Any
## other event flashes only where the player could know of it, by the 3D view's witness rule: at
## the truth if a lookout could see it, at the plotted position if the plot holds `target`, and
## not at all otherwise. A refused order is the player's own mark and always shows.
func add_effect(pos: Vector2, kind: String, own := false, target: Unit = null) -> void:
	if not own and kind != "refused":
		pos = _witness(pos, target)
		if pos == Vector2.INF:
			return
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


## Where the player could place an event at `pos` (see `add_effect`), or Vector2.INF.
func _witness(pos: Vector2, target: Unit) -> Vector2:
	if unit_manager == null:
		return pos  # a chart with no picture behind it has nothing to keep back
	var tracks: Array = track_manager.get_tracks(player_faction) if track_manager != null else []
	return WorldPresentation.witness_point(pos, unit_manager.get_faction_units(player_faction), tracks, Detection.environment, target)


func reset_presentation() -> void:
	_threats.clear()
	_threat_candidates.clear()
	_threat_cache_time = -1.0
	_threat_cache_revision = -1
	_radio.clear()
	_labels.clear()
	_label_queue.clear()
	_trails.clear()
	_own_numbers.clear()
	_wrecks.clear()
	_own_alive.clear()
	_clear_range_circle()
	_weapon_trails.clear()
	_trail_reference = null
	_weapon_trail_time = -1.0
	_weapon_trail_revision = -1
	_weapon_trail_threat_revision = -1
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
	if not keyboard_navigation_enabled or menu_open or not is_visible_in_tree():
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
	if not keyboard_navigation_enabled or menu_open or not is_visible_in_tree():
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


## Inspect a plotted round without changing the shooter or contact selection. Enemy rounds
## use the hooked observer's picture and never expose a launcher or an enemy target at truth.
func _get_tooltip(at: Vector2) -> String:
	var w := _weapon_at(at)
	if w == null:
		return ""
	var own := w.faction == player_faction
	var lines := PackedStringArray(["%s #%d — %s" % ["OWN WEAPON" if own else "DETECTED WEAPON", w.id, w.spec.display_name]])
	lines.append("Course %03d° · Speed %d kn" % [int(roundf(w.heading_deg)) % 360, int(w.spec.speed_kn)])
	if own:
		if w.shooter != null:
			lines.append("Fired by %s" % w.shooter.callsign)
		if w.is_interceptor():
			lines.append("Intercepting weapon #%d · estimated %s" % [w.intercept_target.id, Track._fmt_age(w.time_to_reach_s(w.intercept_target.position))])
		elif w.target_track != null:
			lines.append("Target %s · estimated %s to aim point" % [w.target_track.label(), Track._fmt_age(w.time_to_reach_s(w.aim_point))])
		lines.append("%s · %.1f nm range remaining" % ["Terminal" if w.phase == Weapon.Phase.TERMINAL else "Cruise", maxf(w.spec.max_range_nm - w.distance_flown_nm, 0.0)])
	else:
		lines.append("%s · visible to the current platform" % w.threat_class().capitalize())
	return "\n".join(lines)


func _weapon_at(screen_pos: Vector2) -> Weapon:
	if weapon_manager == null or not _chart_accepts_point(screen_pos):
		return null
	var observer := reference_unit()
	var best: Weapon = null
	var distance_sq := 12.0 * 12.0
	for w: Weapon in weapon_manager.in_flight:
		if w.phase == Weapon.Phase.DEAD:
			continue
		if w.faction != player_faction and (observer == null or threat_manager == null or not threat_manager.visible_to(observer, w)):
			continue
		var d := world_to_screen(w.position).distance_squared_to(screen_pos)
		if d < distance_sq:
			best = w
			distance_sq = d
	return best


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
			if interaction_mode == InteractionMode.PATROL:
				if e.pressed:
					grab_focus()
					if not _patrol_started:
						_patrol_corner = screen_to_world(e.position)
						_patrol_started = true
					else:
						var patrol := Order.patrol_box(_patrol_corner, screen_to_world(e.position))
						var valid := false
						for u: Unit in selected:
							valid = valid or UnitManager.patrol_rejection(u, patrol.route) == ""
						if valid:
							patrol_order_requested.emit(patrol)
							set_move_mode(false)
						else:
							add_effect(screen_to_world(e.position), "refused")
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
			if interaction_mode != InteractionMode.SELECT:
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
## controllable unit hooked; attack a hostile or investigate an unknown at once with one hooked;
## otherwise hook what is under the cursor and ask the shell for a menu. Shift always asks for
## the menu on a contact, for the weapon and salvo choices.
func _right_click(e: InputEventMouseButton) -> void:
	var ctx := context_at(e.position)
	match String(ctx["kind"]):
		"track":
			var t: Track = ctx["track"]
			if e.ctrl_pressed or e.meta_pressed:
				engage_requested.emit(t)
				return
			select_track(t)
			if not e.shift_pressed and _has_controllable_selection():
				match default_contact_verb(t):
					"attack":
						attack_requested.emit(t)
						return
					"investigate":
						investigate_requested.emit(t)
						return
		"own_unit":
			var u: Unit = ctx["unit"]
			if not selected.has(u):
				select_units([u])
			elif _inspecting_track:
				_inspecting_track = false
				selection_changed.emit(selected)
		"water", "empty":
			var world: Vector2 = ctx["world_pos"]
			if _has_controllable_selection() and int(_move_acceptance(world)["accepted"]) > 0:
				move_order_requested.emit(world, e.shift_pressed)
				return
	ctx["viewport_pos"] = get_global_transform_with_canvas() * e.position if is_inside_tree() else e.position
	context_menu_requested.emit(e.position, ctx)


## What a bare right-click does to a contact, from the plot alone: "attack" a contact the plot
## calls hostile, "investigate" one it has not yet classified, "" (the menu) for a neutral or
## friendly one, a classified contact of unknown allegiance, or a contact already lost.
static func default_contact_verb(t: Track) -> String:
	if t == null or t.status == Track.Status.LOST:
		return ""
	if t.identity == "HOSTILE":
		return "attack"
	if t.identity == "UNKNOWN" and t.classification < Track.Classification.CLASS_KNOWN:
		return "investigate"
	return ""


## The cursor over the chart says what a right-click would do: a cross over a contact the hooked
## platforms would attack, a query over one they would investigate, the arrow otherwise.
func hover_cursor_shape(screen_pos: Vector2) -> Control.CursorShape:
	if interaction_mode != InteractionMode.SELECT:
		return Control.CURSOR_CROSS
	if not _has_controllable_selection() or _unit_at(screen_pos) != null:
		return Control.CURSOR_ARROW
	match default_contact_verb(_track_at(screen_pos)):
		"attack":
			return Control.CURSOR_CROSS
		"investigate":
			return Control.CURSOR_HELP
	return Control.CURSOR_ARROW


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
		mouse_default_cursor_shape = hover_cursor_shape(e.position)
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


## Drops any drag in progress. The chart moves between the top area and the 3D pane (G, F10), and
## a control that leaves the tree mid-drag never hears the release that would have ended it.
func cancel_drag() -> void:
	if _drag_mode != DragMode.NONE:
		_end_drag()


func _end_drag() -> void:
	_drag_mode = DragMode.NONE
	_drag_button = MOUSE_BUTTON_NONE
	_drag_moved = false
	mouse_default_cursor_shape = Control.CURSOR_CROSS if interaction_mode != InteractionMode.SELECT else Control.CURSOR_ARROW


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
	_inspecting_track = false
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
	_inspecting_track = false
	if not additive:
		selected.clear()
	for u in _own_units():
		if rect.has_point(world_to_screen(u.position)) and not selected.has(u):
			selected.append(u)
	_normalize_interaction_state()
	selection_changed.emit(selected)


func select_units(units: Array) -> void:
	_inspecting_track = false
	# Some callers reselect the current formation to inspect it after viewing a contact.
	var next := units.duplicate()
	selected.clear()
	for u in next:
		selected.append(u)
	_normalize_interaction_state()
	selection_changed.emit(selected)


func select_track(t: Track) -> void:
	var inspecting := t != null
	if t == selected_track and _inspecting_track == inspecting:
		return
	selected_track = t
	_inspecting_track = inspecting
	_normalize_interaction_state()
	track_selected.emit(t)


## Which contact the player is inspecting, independently of the retained command selection.
func inspection_track() -> Track:
	if (_inspecting_track or selected.is_empty()) and selected_track != null and selected_track.status != Track.Status.LOST:
		return selected_track
	return null


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

## Geometry changes on simulation ticks or new detections. Visibility still follows the
## selected observer every frame, so a disconnected ship cannot inherit another sensor picture.
func _refresh_threats() -> void:
	_threats.clear()
	if unit_manager == null or threat_manager == null:
		return
	if _threat_cache_time != SimClock.sim_time or _threat_cache_revision != threat_manager.revision:
		_threat_candidates = AirDefence.inbound_threats(unit_manager, threat_manager, player_faction)
		_threat_cache_time = SimClock.sim_time
		_threat_cache_revision = threat_manager.revision
	var observer := reference_unit()
	for entry: Dictionary in _threat_candidates:
		var w: Weapon = entry["weapon"]
		var victim: Unit = entry["target"]
		if w.phase != Weapon.Phase.DEAD and victim.alive and (observer == null or threat_manager.visible_to(observer, w)):
			_threats.append(entry)


func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_refresh_threats()
	var t1 := Time.get_ticks_usec()
	_draw_ocean()
	_draw_land()
	if show_graticule:
		_draw_grid()
	if show_range_grid:
		_draw_range_rings()
	var t2 := Time.get_ticks_usec()
	_draw_chart_labels()
	_draw_objectives()
	_draw_move_preview()
	var t3 := Time.get_ticks_usec()
	if unit_manager != null:
		if show_rings:
			_draw_sensor_rings()
		_draw_weapon_ring()
		if Debug.enabled:
			_draw_truth()
		_draw_sonobuoys()
		_draw_relative_motion()
		var plot_start := Time.get_ticks_usec()
		_draw_tracks()
		var tracks_end := Time.get_ticks_usec()
		_draw_units()
		var units_end := Time.get_ticks_usec()
		_draw_labels()
		var labels_end := Time.get_ticks_usec()
		_draw_weapons()
		var weapons_end := Time.get_ticks_usec()
		Debug.time_add("plot/tracks", tracks_end - plot_start)
		Debug.time_add("plot/units", units_end - tracks_end)
		Debug.time_add("plot/labels", labels_end - units_end)
		Debug.time_add("plot/weapons", weapons_end - labels_end)
		_draw_effects()
		_draw_speaker_rings()
	_draw_range_circle()
	var t4 := Time.get_ticks_usec()
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
	if not overlay_covered:
		_draw_readout()
		_draw_radio_line()
		_draw_key()
		_draw_hover_card()
	var t5 := Time.get_ticks_usec()
	# The whole chart, and where it went (the parts add up to the whole).
	Debug.time_add("chart", t5 - t0)
	Debug.time_add("chart/threats", t1 - t0)
	Debug.time_add("chart/coast", t2 - t1)
	Debug.time_add("chart/names", t3 - t2)
	Debug.time_add("chart/plot", t4 - t3)
	Debug.time_add("chart/readout", t5 - t4)


## Plot Move: dashed white legs from each hooked unit to the cursor (red past a coast in the way),
## a crosshair at the cursor, and what a click there would do.
func _draw_move_preview() -> void:
	if interaction_mode == InteractionMode.PATROL:
		_draw_patrol_preview()
		return
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


func _draw_patrol_preview() -> void:
	if not _mouse_inside or not _chart_accepts_point(_mouse):
		return
	var label := "PATROL: click first corner"
	var col := COL_ROUTE
	if _patrol_started:
		var patrol := Order.patrol_box(_patrol_corner, screen_to_world(_mouse))
		var reason := ""
		var accepted := 0
		for u: Unit in selected:
			reason = UnitManager.patrol_rejection(u, patrol.route)
			if reason == "":
				accepted += 1
		col = COL_ROUTE if accepted > 0 else COL_HOSTILE
		var rect := Rect2(world_to_screen(_patrol_corner), _mouse - world_to_screen(_patrol_corner)).abs()
		draw_rect(rect, Color(col, 0.06))
		for i in patrol.route.size():
			var a := world_to_screen(patrol.route[i])
			var b := world_to_screen(patrol.route[(i + 1) % patrol.route.size()])
			draw_dashed_line(a, b, col, 1.0, 6.0)
			_draw_plus(a, 4.0, col)
		var span := (screen_to_world(_mouse) - _patrol_corner).abs()
		label = "PATROL %.1f × %.1f NM — click to assign (%d/%d)" % [span.x, span.y, accepted, selected.size()] if accepted > 0 else reason
	_shadow_text(_mouse + Vector2(17, -10), label, 12, col)


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
	# The same box the floor draws with, so land in the clip margin counts as the land it shows.
	if _floor == null or not Bathymetry.active or _floor.owned_rect().has_point(w):
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
	var box := ChartFloor.stated_charted_box(simulation)
	var key := "%d:%s" % [Terrain.generation, box]
	if key != _coast_key:
		_coast_key = key
		_coast_runs.clear()
		_coast_screen.clear()
		for l: Landmass in Terrain.landmasses:
			_coast_runs[l] = coast_runs(l.points, box)
	var view_key := PackedFloat32Array([center_nm.x, center_nm.y, ppn, size.x, size.y])
	if view_key != _coast_view:
		_coast_view = view_key
		_coast_screen.clear()
	for l: Landmass in Terrain.landmasses:
		if not l.bounds.intersects(view):
			continue
		# A skerry smaller than a pixel or two has its fill and no stroke: the hundreds of them
		# along a coast like Norway's are most of the vertices and none of the picture.
		if maxf(l.bounds.size.x, l.bounds.size.y) * ppn < COAST_STROKE_MIN_PX:
			continue
		var lines: Array = _coast_screen.get(l, [])
		if lines.is_empty():
			for run: PackedVector2Array in _coast_runs.get(l, []):
				lines.append(_project_coast(run))
			_coast_screen[l] = lines
		for line: PackedVector2Array in lines:
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
	at.x -= _text_width(text, 11) * 0.5
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
	# A swap briefly reparents this control through a zero-size slot before layout settles.
	if size.x <= 16.0 or size.y <= 16.0:
		return
	var m := _geo_map()
	var safe := Rect2(Vector2(8, 8), size - Vector2(16, 16))
	var occupied: Array[Rect2] = []
	for entry in m.get("labels", []):
		var p: Array = entry["position_nm"]
		var at := world_to_screen(Vector2(p[0], p[1])).round()
		var text := str(entry["text"])
		var water: bool = entry.get("kind", "land") == "water"
		var width := _text_width(text, 11)
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
	for mark: Dictionary in objective_marks(mission.victory_objectives, mission.loss_objectives):
		var sp := world_to_screen(mark["center"])
		var r := float(mark["radius_nm"]) * ppn
		draw_arc(sp, r, 0.0, TAU, _arc_segments(r), COL_ROUTE, 1.0, true)
		_centred_text(sp + Vector2(0.0, -maxf(r, 8.0) - 5.0), mark["text"], 11)


## The areas the chart marks, one circle and one name each: {center, radius_nm, text}. Several
## tasks can share an area (reach the box, then hold it), so where they do the name is the one
## that matters now, in this order: a box to deny, a station to hold, an objective area, a station
## to hold later. A task still to come never prints over the one in hand.
static func objective_marks(victory: Array, loss: Array) -> Array:
	var marks: Dictionary = {}
	for o: MissionObjective in victory + loss:
		if o.kind not in [MissionObjective.Kind.REACH_AREA, MissionObjective.Kind.HOLD_AREA] or o.complete:
			continue
		var text := "OBJECTIVE AREA"
		var rank := 2
		if loss.has(o):
			text = "DENY EXIT"
			rank = 0
		elif o.kind == MissionObjective.Kind.HOLD_AREA:
			text = "HOLD STATION" if o.unlocked else "LATER HOLD AREA"
			rank = 1 if o.unlocked else 3
		var key := "%.3f,%.3f,%.3f" % [o.center.x, o.center.y, o.radius_nm]
		if not marks.has(key) or rank < int(marks[key]["rank"]):
			marks[key] = {"center": o.center, "radius_nm": o.radius_nm, "text": text, "rank": rank}
	return marks.values()


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


## The selected weapon's reach from each hooked shooter that carries it: a role-coloured circle, its
## minimum range dashed, and the firing solution when the hooked contact can be engaged.
func _draw_weapon_ring() -> void:
	if show_weapon_ranges:
		var ref := reference_unit()
		if ref != null and ref.faction == player_faction:
			var row := 0
			var specs: Array = ref.weapons.filter(func(spec: WeaponSpec) -> bool: return ref.magazine_count(spec.id) > 0 and WeaponPresentation.matches(spec, weapon_range_role))
			var legend := Vector2(14.0, 24.0)
			_shadow_text(legend, "WEAPON ENVELOPES  " + ref.callsign, 11)
			for spec: WeaponSpec in specs:
				var col := WeaponPresentation.color(spec)
				var radius := Combat.effective_range_nm(ref, spec) * ppn
				var center := world_to_screen(ref.position)
				if spec.type in ["torpedo", "asw_rocket", "bomb"]:
					_draw_dashed_circle(center, radius, Color(col, 0.65), _arc_segments(radius))
				else:
					draw_arc(center, radius, 0.0, TAU, _arc_segments(radius), Color(col, 0.65), 1.0, true)
				if spec.min_range_nm > 0.0:
					_draw_dashed_circle(center, spec.min_range_nm * ppn, Color(col, 0.3), 32)
				if row < 10:
					row += 1
					_shadow_text(legend + Vector2(0, row * 17), "%s  %s  %.1f-%s nm" % [WeaponPresentation.role_name(spec), spec.compact_name(), spec.min_range_nm, Geo.format_nm(Combat.effective_range_nm(ref, spec))], 11, col)
	if weapon_ring == null:
		return
	var col := WeaponPresentation.color(weapon_ring)
	for u in _own_units():
		if not selected.has(u) or u.magazine_count(weapon_ring.id) <= 0:
			continue
		var sp := world_to_screen(u.position)
		var reach := Combat.effective_range_nm(u, weapon_ring)
		var outer := reach * ppn
		draw_arc(sp, outer, 0.0, TAU, _arc_segments(outer), col, 1.5, true)
		if weapon_ring.min_range_nm > 0.0:
			_draw_dashed_circle(sp, weapon_ring.min_range_nm * ppn, Color(col, 0.5), 48)
		if u == reference_unit():
			_centred_text(sp + Vector2(0.0, maxf(-outer - 5.0, 16.0 - sp.y)), "%s  %s nm" % [weapon_ring.compact_name(), Geo.format_nm(reach)], 11)
		if selected_track == null:
			continue
		var check := Combat.check_engagement(u, weapon_ring, selected_track)
		if not check.ok:
			continue
		var aim: Vector2 = check.aim_point
		var ap := world_to_screen(aim)
		draw_dashed_line(sp, ap, Color(col, 0.6), 1.0, 6.0)
		draw_arc(ap, 6.0, 0.0, TAU, 16, col, 1.0, true)
		draw_line(ap + Vector2(-9, 0), ap + Vector2(9, 0), col, 1.0)
		draw_line(ap + Vector2(0, -9), ap + Vector2(0, 9), col, 1.0)
		# The seeker basket makes contact uncertainty a visible targeting decision.
		_draw_dashed_circle(ap, weapon_ring.acquisition_radius_nm() * ppn, Color(col, 0.35), 48)
		var warning := " / UNCERTAIN" if selected_track.position_error_nm > weapon_ring.acquisition_radius_nm() or selected_track.status == Track.Status.STALE else ""
		var solution_label := "SEARCH" if selected_track.is_bearing_only() else "INTERCEPT"
		if u == reference_unit():
			_shadow_text(ap + Vector2(10, -8), "%s %ds%s" % [solution_label, int(check.flight_time_s), warning], 11, col)


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
		_queue_label("t:" + t.id, sp, extent, MapSymbols.track_number(t.id), t.description(), col.a, selected_track == t)


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


## Queues a symbol's white track number and, with tags on, the name or classification under it,
## for `_draw_labels`. `alpha` fades them with a stale track; a `priority` label (the hook) is
## placed first and never left off.
func _queue_label(key: String, sp: Vector2, extent: float, number: String, tag: String, alpha: float, priority: bool) -> void:
	var number_text := number if show_track_numbers else ""
	var tag_text := tag if show_tags else ""
	if number_text == "" and tag_text == "":
		return
	var font := _readout_font()
	var width := 0.0
	var ascent := 0.0
	var height := 0.0
	if number_text != "":
		width = _text_width(number_text, TRACK_NUMBER_FONT_SIZE)
		ascent = font.get_ascent(TRACK_NUMBER_FONT_SIZE)
		height = ascent + font.get_descent(TRACK_NUMBER_FONT_SIZE)
	if tag_text != "":
		width = maxf(width, _text_width(tag_text, TAG_FONT_SIZE))
		if number_text == "":
			ascent = font.get_ascent(TAG_FONT_SIZE)
			height = ascent + font.get_descent(TAG_FONT_SIZE)
		else:
			height += TRACK_NUMBER_FONT_SIZE + 1.0
	_label_queue.append({"key": key, "at": sp, "extent": extent, "size": Vector2(width, height), "ascent": ascent, "priority": priority, "number": number_text, "tag": tag_text, "alpha": alpha})


## Prints the queued track numbers and tags, each at the classic place below and right of its
## symbol unless that would print over another, in which case ChartLabels has moved it or, on a
## spot too crowded for it, left it off. Drawn after every symbol so a symbol never covers a number.
func _draw_labels() -> void:
	if _label_queue.is_empty():
		return
	if _labels.due(_anim, _label_queue.size()):
		_labels.assign(_label_queue, _anim)
	for l: Dictionary in _label_queue:
		var k := _labels.slot(l["key"])
		if k == ChartLabels.HIDDEN:
			continue
		var rect := ChartLabels.box(l["at"], l["extent"], l["size"], l["ascent"], ChartLabels.OFFSETS[k])
		var at := ChartLabels.baseline(rect, l["ascent"]).round()
		var col := Color(COL_READOUT, l["alpha"])
		if l["number"] != "":
			_shadow_text(at, l["number"], TRACK_NUMBER_FONT_SIZE, col)
			at.y += TRACK_NUMBER_FONT_SIZE + 1.0
		if l["tag"] != "":
			_shadow_text(at, l["tag"], TAG_FONT_SIZE, col)
	_label_queue.clear()


## The width of a label's text, measured once per string and size.
func _text_width(text: String, font_size: int) -> float:
	var key := "%s@%d" % [text, font_size]
	if not _text_widths.has(key):
		if _text_widths.size() >= 2048:
			_text_widths.clear()
		_text_widths[key] = _readout_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return float(_text_widths[key])


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
			_draw_dot(world_to_screen(t.history_positions[i]), Color(col, alpha))


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
					_draw_dot(dot, Color(COL_FRIENDLY, 0.1 + 0.4 * float(i + 1) / float(arr.size())))
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
		_queue_label("u:%d" % u.id, sp, extent, track_number_text(u), u.callsign, 1.0, selected.has(u))


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
	if u.patrol_active and u.waypoints.size() >= 3:
		draw_dashed_line(prev, first, COL_ROUTE, 1.0, 5.0)
		_shadow_text(first + Vector2(8, -8), "PATROL", 11, COL_ROUTE)


## A 2 px dot for trails and plot history: a filled square, which costs a fraction of an
## antialiased circle and reads the same at that size. A busy plot draws a thousand of them.
func _draw_dot(at: Vector2, col: Color) -> void:
	draw_rect(Rect2(at.round() - Vector2.ONE, Vector2(2.0, 2.0)), col)


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
	var labelled: Dictionary = {}
	var label_slots: Dictionary = {}
	var friendly_glyphs := PackedVector2Array()
	var hostile_glyphs := PackedVector2Array()
	var trail_points := PackedVector2Array()
	var trail_colors := PackedColorArray()
	var visible_chart := Rect2(Vector2(-20, -20), size + Vector2(40, 40))
	var dense := weapon_manager.in_flight.size() > 200
	for w: Weapon in weapon_manager.in_flight:
		if w.phase == Weapon.Phase.DEAD:
			continue
		var own := w.faction == player_faction
		var detected := not own and ref != null and threat_manager != null and threat_manager.visible_to(ref, w)
		if not own and not detected and not Debug.enabled:
			continue  # an undetected round is invisible, which is the whole problem
		var sp := world_to_screen(w.position)
		if not visible_chart.has_point(sp):
			continue
		var col := COL_FRIENDLY if own else COL_HOSTILE
		# Detailed guidance lines belong to the hooked engagement. Drawing one long dashed
		# solution for every round in a massed salvo obscures the fleet and dominates redraws.
		var hooked := selected.has(w.shooter)
		if w.is_interceptor() and w.intercept_target != null and (hooked or selected.has(w.intercept_target.acquired)):
			draw_line(sp, world_to_screen(w.intercept_target.position), Color(col, 0.3), 1.0, true)
		elif own and hooked and w.target_track != null and w.phase == Weapon.Phase.CRUISE:
			draw_dashed_line(sp, world_to_screen(w.aim_point), Color(col, 0.3), 1.0, 5.0)
		if _weapon_trails.has(w.id):
			var arr: PackedVector2Array = _weapon_trails[w.id]
			var points := PackedVector2Array()
			var colors := PackedColorArray()
			for i in arr.size():
				var point := world_to_screen(arr[i])
				if not points.is_empty() and point.distance_squared_to(points[-1]) < (64.0 if dense and not hooked else 4.0) and i < arr.size() - 1:
					continue
				points.append(point)
				colors.append(Color(col, 0.05 + 0.35 * float(i + 1) / float(arr.size())))
			if points.size() >= 2:
				for i in range(1, points.size()):
					trail_points.append(points[i - 1])
					trail_points.append(points[i])
					trail_colors.append(colors[i])
		if own:
			friendly_glyphs.append_array(MapSymbols.ordnance_segments(sp, w.heading_deg, w.spec))
		else:
			hostile_glyphs.append_array(MapSymbols.ordnance_segments(sp, w.heading_deg, w.spec))
		if own and hooked and labelled.size() < 10:
			var label_key := "%d:%s" % [w.shooter.id if w.shooter != null else -1, w.spec.id]
			if not labelled.has(label_key):
				labelled[label_key] = true
				var cell := Vector2i(sp / 24.0)
				var slot := int(label_slots.get(cell, 0))
				label_slots[cell] = slot + 1
				_shadow_text(sp + Vector2(20, 25 + 13 * slot), w.spec.compact_name(), 10, WeaponPresentation.color(w.spec))
		if Debug.enabled:
			draw_dashed_line(sp, world_to_screen(w.aim_point), Color(col, 0.4), 1.0, 5.0)

	if not trail_points.is_empty():
		draw_multiline_colors(trail_points, trail_colors, 1.0, true)
	if not friendly_glyphs.is_empty():
		draw_multiline(friendly_glyphs, COL_FRIENDLY, 1.0, true)
	if not hostile_glyphs.is_empty():
		draw_multiline(hostile_glyphs, COL_HOSTILE, 1.0, true)


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
	if not _mouse_inside or _drag_mode != DragMode.NONE or menu_open or interaction_mode != InteractionMode.SELECT:
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
		lines.append("Click to command · Right-click for orders")
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
	lines.append(contact_hint(default_contact_verb(t) if _has_controllable_selection() else ""))
	_draw_card(lines)


## The hover card's last line says what a right-click on this contact will do now.
static func contact_hint(verb: String) -> String:
	match verb:
		"attack":
			return "Click to inspect · Right-click to attack · Shift for menu"
		"investigate":
			return "Click to inspect · Right-click to investigate · Shift for menu"
	return "Click to inspect · Right-click for the contact menu"


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
