class_name RegionalMap
extends Control
## The regional display: the whole battle space in one square pane, drawn from the same rasters and
## coastline as the tactical chart but darker and less saturated, so the eye reads it as context.
## Own units and held contacts are 4 px dots, the tactical chart's view is a magenta rectangle, and
## each own radiating radar's horizon is a translucent disc.
##
## Mouse: drag inside the rectangle pans the tactical chart, a click elsewhere recentres it there,
## the wheel zooms it, and a right-click sends the hooked platforms there as on the chart (Shift
## adds a leg). Friendly dots use their reported positions, and contact dots follow the tactical
## chart's identity filters.

## A line for the radio net's advice, when a right-click could not send the hook anywhere.
signal advice(text: String)

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
var _layer_view: Array = []
var _points := PackedVector2Array()
var _colors := PackedColorArray()
var _hooked := PackedByteArray()
var _view_box := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	tooltip_text = "Regional display. Drag the rectangle to pan the chart, click to recentre it, wheel to zoom, right-click to send the hooked platforms there."
	accessibility_name = "Regional display"
	_floor = ChartFloor.new()
	_floor.name = "RegionalFloor"
	_land = ChartLand.new()
	_land.name = "RegionalLand"
	for layer: ChartLayer in [_floor, _land]:
		layer.brightness = BRIGHTNESS
		layer.saturation = SATURATION
		add_child(layer)
		layer.set_process(false)  # the overview updates both rasters when their inputs change
	visibility_changed.connect(_sync_visibility)
	_sync_visibility()


func _sync_visibility() -> void:
	set_process(is_visible_in_tree())
	if is_processing():
		_process(0.0)


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var wanted := wanted_extent_nm()
	_extent = wanted if _extent <= 0.0 or wanted > _extent else lerpf(_extent, wanted, clampf(delta * 3.0, 0.0, 1.0))
	var own: Array[Unit] = []
	if map != null:
		own = map._own_units()
	_update_layers(own)
	_update_dots(own)
	Debug.time_add("regional", Time.get_ticks_usec() - t0)


func _update_layers(own: Array[Unit]) -> void:
	if _floor == null:
		return
	var center := _chart_center()
	var scale_px := _scale()
	var relief := map.show_terrain if map != null else true
	var sim := map.simulation if map != null else null
	var view := [size, center, scale_px, relief, sim, Terrain.generation, Bathymetry.generation]
	var discs: Array[Vector3] = []
	if show_radar_coverage:
		discs = _radar_coverage_for(own)
	if _layer_view == view and _floor.coverage == discs:
		return
	_layer_view = view
	for layer: ChartLayer in [_floor, _land]:
		layer.view_center_nm = center
		layer.px_per_nm = scale_px
		layer.relief_on = relief
		layer.coverage = discs
	_floor.simulation = sim
	_floor._process(0.0)  # refresh the charted box before drawing a newly loaded coast
	_land.queue_redraw()


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


func _world_to_pane() -> Transform2D:
	var scale_px := _scale()
	var origin := size * 0.5 - _chart_center() * Vector2(scale_px, -scale_px)
	return Transform2D(Vector2(scale_px, 0.0), Vector2(0.0, -scale_px), origin)


func world_to_regional(world: Vector2) -> Vector2:
	return _world_to_pane() * world


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
## Only connected friendly units can contribute current coverage.
func radar_coverage() -> Array[Vector3]:
	if map == null:
		return []
	return _radar_coverage_for(map._own_units())


func _radar_coverage_for(own: Array[Unit]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for u: Unit in own:
		if not u.alive or not SubmarineComms.connected(u) or not u.radar_emitting():
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
			MOUSE_BUTTON_RIGHT:
				if mouse.pressed:
					right_click(mouse.position, mouse.shift_pressed)
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


## A right-click at a pane point: a transit there for the hooked platforms, through the chart's
## own move request, or a word of advice saying why the hook cannot go there.
func right_click(point: Vector2, append: bool) -> void:
	if map == null:
		return
	if map.request_move(regional_to_world(point), append):
		return
	advice.emit("Hook a platform before you send it from the regional display" if map.selected.is_empty() else "No hooked platform can be sent there")


# --- Drawing ----------------------------------------------------------------------------

## Compare the actual plotted picture each frame. Paused orders, a newly selected reporting
## unit or a filter change can all change the overview without advancing the simulation clock.
func _update_dots(own: Array[Unit]) -> void:
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var hooked := PackedByteArray()
	var pane := Rect2(Vector2.ZERO, size)
	var projection := _world_to_pane()
	var tracks: Array = map._plotted_tracks() if map != null else []
	for t: Track in tracks:
		var p := projection * t.position
		if pane.has_point(p):
			points.append(p)
			var col := map.track_color(t)
			if t.status == Track.Status.STALE:
				col.a = 0.55
			colors.append(col)
			hooked.append(int(t == map.selected_track))
	for u: Unit in own:
		var p := projection * SubmarineComms.reported_position(u)
		if pane.has_point(p):
			points.append(p)
			colors.append(TacticalMap.COL_FRIENDLY)
			hooked.append(int(map.selected.has(u)))
	var view := view_rect()
	if view.has_area():
		view = Rect2(view.position.round() + Vector2(0.5, 0.5), view.size.round())
	else:
		view = Rect2()
	if points == _points and colors == _colors and hooked == _hooked and view == _view_box:
		return
	_points = points
	_colors = colors
	_hooked = hooked
	_view_box = view
	queue_redraw()


func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	for i in _points.size():
		draw_circle(_points[i], DOT_RADIUS, _colors[i])
		if _hooked[i]:
			draw_arc(_points[i], DOT_RADIUS + 2.5, 0.0, TAU, 16, COL_HOOK, 1.0, true)
	if _view_box != Rect2():
		draw_rect(_view_box, COL_VIEW, false, 1.0)
	Debug.time_add("regional", Time.get_ticks_usec() - t0)
