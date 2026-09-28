class_name RegionalMap
extends Control
## The regional display: the whole battle space in one square pane, drawn from the same rasters and
## coastline as the tactical chart but darker and less saturated, so the eye reads it as context.
## Own units and held contacts are 4 px dots, the tactical chart's view is a magenta rectangle, and
## each own radiating radar's horizon is a translucent disc.
##
## Mouse: drag inside the rectangle pans the tactical chart, a click elsewhere recentres it there,
## the wheel zooms it. Information rules as the chart: own units from `map._own_units()` and contacts
## from `map._visible_tracks()` only, never hostile truth.

const COL_VIEW := Color("c040c0")
const COL_HOOK := Color.WHITE
const DOT_RADIUS := 2.0
const BRIGHTNESS := 0.55
const SATURATION := 0.85  # the reference pane keeps most of its colour; 0.7 read grey
const MAX_COVERAGE := 16
## The pane shows the theatre with this much margin, and never less than the chart's whole view,
## so the magenta rectangle always sits inside it: the regional display is the wider picture.
const THEATRE_MARGIN := 1.8
const VIEW_MARGIN := 1.15
const MIN_EXTENT_NM := 240.0
const MAX_EXTENT_NM := 2400.0

var map: TacticalMap
## Radar-coverage discs (on by default).
var show_radar_coverage := true

var _floor: ChartFloor
var _land: ChartLand
var _dragging := false
var _extent := 0.0  # eased toward wanted_extent_nm(), so zooming the chart does not jolt the pane


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	tooltip_text = "Regional display. Drag the rectangle to pan the chart, click to recentre it, wheel to zoom."
	accessibility_name = "Regional display"
	_floor = ChartFloor.new()
	_floor.name = "RegionalFloor"
	_land = ChartLand.new()
	_land.name = "RegionalLand"
	for layer: ChartLayer in [_floor, _land]:
		layer.brightness = BRIGHTNESS
		layer.saturation = SATURATION
		add_child(layer)


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var wanted := wanted_extent_nm()
	_extent = wanted if _extent <= 0.0 or wanted > _extent else lerpf(_extent, wanted, clampf(delta * 3.0, 0.0, 1.0))
	var discs: Array[Vector3] = []
	if show_radar_coverage:
		discs = radar_coverage()
	for layer: ChartLayer in [_floor, _land]:
		if layer == null:
			continue
		layer.view_center_nm = _chart_center()
		layer.px_per_nm = _scale()
		layer.relief_on = map.show_terrain if map != null else true
		layer.coverage = discs
	if _floor != null:
		_floor.simulation = map.simulation if map != null else null
	queue_redraw()
	Debug.time_add("regional", Time.get_ticks_usec() - t0)


## Drops a drag in progress, for when the pane is hidden or moved under the pointer (F10).
func cancel_drag() -> void:
	_dragging = false


func toggle_radar_coverage() -> bool:
	show_radar_coverage = not show_radar_coverage
	return show_radar_coverage


# --- Transform --------------------------------------------------------------------------

## The theatre: the scenario's map centre and extent, the same frame the old overview used.
func _chart_center() -> Vector2:
	return map.simulation.map_center if map != null and map.simulation != null else Vector2.ZERO


func _extent_nm() -> float:
	return _extent if _extent > 0.0 else wanted_extent_nm()


## Side of the square the pane covers, in nm: the theatre with a margin, grown to hold the whole
## tactical chart view around the theatre centre, within sane limits.
func wanted_extent_nm() -> float:
	var theatre: float = map.simulation.map_extent_nm if map != null and map.simulation != null else 200.0
	var extent := theatre * THEATRE_MARGIN
	if map != null and map.size.x > 0.0:
		var centre := _chart_center()
		for corner in [Vector2.ZERO, Vector2(map.size.x, 0.0), map.size, Vector2(0.0, map.size.y)]:
			var d: Vector2 = (map.screen_to_world(corner) - centre).abs()
			extent = maxf(extent, 2.0 * maxf(d.x, d.y) * VIEW_MARGIN)
	return clampf(extent, MIN_EXTENT_NM, MAX_EXTENT_NM)


func _scale() -> float:
	return minf(size.x, size.y) / _extent_nm()


func world_to_regional(world: Vector2) -> Vector2:
	var d := world - _chart_center()
	return size * 0.5 + Vector2(d.x, -d.y) * _scale()


func regional_to_world(point: Vector2) -> Vector2:
	var d := (point - size * 0.5) / maxf(_scale(), 0.0001)
	return _chart_center() + Vector2(d.x, -d.y)


## The tactical chart's view, in pane pixels.
func view_rect() -> Rect2:
	if map == null:
		return Rect2()
	var a := world_to_regional(map.screen_to_world(Vector2.ZERO))
	var b := world_to_regional(map.screen_to_world(map.size))
	return Rect2(a, b - a).abs()


## Discs for the player's radiating radars: centre and horizon range in world nm, largest first.
## Own units only, and only while their radar is actually on the air.
func radar_coverage() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if map == null:
		return out
	for u: Unit in map._own_units():
		if not u.alive or not u.radar_emitting():
			continue
		var r := Detection.nominal_radar_ring_nm(u)
		if r > 0.0:
			out.append(Vector3(u.position.x, u.position.y, r))
	out.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z > b.z)
	if out.size() > MAX_COVERAGE:
		out.resize(MAX_COVERAGE)
	return out


# --- Input ------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if map == null:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		match mouse.button_index:
			MOUSE_BUTTON_LEFT:
				if mouse.pressed:
					# Inside the rectangle the press grabs it; anywhere else it recentres first.
					if not view_rect().has_point(mouse.position):
						map.center_on(regional_to_world(mouse.position))
					_dragging = true
				else:
					_dragging = false
				accept_event()
			MOUSE_BUTTON_WHEEL_UP:
				if mouse.pressed:
					map.zoom_at_center(TacticalMap.ZOOM_STEP)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mouse.pressed:
					map.zoom_at_center(1.0 / TacticalMap.ZOOM_STEP)
				accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		map.set_follow_selection(false)
		map.center_nm += Vector2(motion.relative.x, -motion.relative.y) / maxf(_scale(), 0.0001)
		accept_event()


# --- Drawing ----------------------------------------------------------------------------

func _draw() -> void:
	if map == null:
		return
	var t0 := Time.get_ticks_usec()
	var pane := Rect2(Vector2.ZERO, size)
	for t: Track in map._visible_tracks():
		var p := world_to_regional(t.position)
		if pane.has_point(p):
			var col := map.track_color(t)
			if t.status == Track.Status.STALE:
				col.a = 0.55
			draw_circle(p, DOT_RADIUS, col)
			if t == map.selected_track:
				draw_arc(p, DOT_RADIUS + 2.5, 0.0, TAU, 16, COL_HOOK, 1.0, true)
	for u: Unit in map._own_units():
		var p := world_to_regional(u.position)
		if pane.has_point(p):
			draw_circle(p, DOT_RADIUS, TacticalMap.COL_FRIENDLY)
			if map.selected.has(u):
				draw_arc(p, DOT_RADIUS + 2.5, 0.0, TAU, 16, COL_HOOK, 1.0, true)
	var view := view_rect()
	if view.size.x > 0.0 and view.size.y > 0.0:
		draw_rect(Rect2(view.position.round() + Vector2(0.5, 0.5), view.size.round()), COL_VIEW, false, 1.0)
	Debug.time_add("regional", Time.get_ticks_usec() - t0)
