class_name TacticalOverview
extends Control
## Clickable theatre overview for recovering context after zooming into the tactical picture.
## It deliberately uses only own units and the console's visible Tracks; it never reads hostile
## Unit truth. The bright rectangle is the current main-map viewport.

const PAD := 9.0
const TITLE_H := 22.0
const COL_BG := Color("08131d", 0.94)
const COL_WATER := Color("0b2635")
const COL_LAND := Color("3b5149")
const COL_COAST := Color("9bb6aa", 0.8)
const COL_VIEW := Color("72dbc9")
const REDRAW_INTERVAL_S := 1.0 / 20.0

var map: TacticalMap
var _dragging := false
var _font: Font
var _redraw_accum := 0.0
var _terrain_generation := -1
var _terrain_size := Vector2.ZERO
var _terrain_center := Vector2(INF, INF)
var _terrain_extent := -1.0
var _terrain_cache: Array[Dictionary] = []
var _floor_texture: ImageTexture  # depth tint for the plot, rebuilt with the terrain cache
var _floor_generation := -1


func _ready() -> void:
	custom_minimum_size = Vector2(208, 142)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	tooltip_text = "Theatre overview. Click or drag to recenter; use the wheel to zoom the tactical picture."
	accessibility_name = "Tactical overview"
	accessibility_description = "Overview of friendly units, visible contacts, and the current map viewport. Click or use arrow keys to recenter."
	_font = UITheme.body_font()
	resized.connect(_invalidate_terrain_cache)


func _process(delta: float) -> void:
	_redraw_accum += delta
	if _redraw_accum >= REDRAW_INTERVAL_S:
		_redraw_accum = 0.0
		queue_redraw()


func _invalidate_terrain_cache() -> void:
	_terrain_generation = -1
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if map == null:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mouse.pressed
			if mouse.pressed:
				grab_focus()
				_recenter(mouse.position)
			accept_event()
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
			map.zoom_at_center(TacticalMap.ZOOM_STEP)
			accept_event()
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			map.zoom_at_center(1.0 / TacticalMap.ZOOM_STEP)
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_recenter((event as InputEventMouseMotion).position)
		accept_event()
	elif event is InputEventKey and (event as InputEventKey).pressed:
		var key := event as InputEventKey
		var step := _extent_nm() * 0.08
		var handled := true
		match key.keycode:
			KEY_LEFT:
				map.center_on(map.center_nm + Vector2(-step, 0))
			KEY_RIGHT:
				map.center_on(map.center_nm + Vector2(step, 0))
			KEY_UP:
				map.center_on(map.center_nm + Vector2(0, step))
			KEY_DOWN:
				map.center_on(map.center_nm + Vector2(0, -step))
			KEY_EQUAL, KEY_KP_ADD:
				map.zoom_at_center(TacticalMap.ZOOM_STEP)
			KEY_MINUS, KEY_KP_SUBTRACT:
				map.zoom_at_center(1.0 / TacticalMap.ZOOM_STEP)
			_:
				handled = false
		if not handled:
			return
		if key.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
			map.set_follow_selection(false)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
		queue_redraw()


func _plot_rect() -> Rect2:
	return Rect2(PAD, TITLE_H, maxf(size.x - PAD * 2.0, 1.0), maxf(size.y - TITLE_H - PAD, 1.0))


func _chart_center() -> Vector2:
	return map.simulation.map_center if map != null and map.simulation != null else Vector2.ZERO


func _extent_nm() -> float:
	return maxf(map.simulation.map_extent_nm if map != null and map.simulation != null else 200.0, 1.0)


func world_to_overview(world: Vector2) -> Vector2:
	var plot := _plot_rect()
	var scale := minf(plot.size.x, plot.size.y) / _extent_nm()
	var d := world - _chart_center()
	return plot.get_center() + Vector2(d.x, -d.y) * scale


func overview_to_world(point: Vector2) -> Vector2:
	var plot := _plot_rect()
	var scale := minf(plot.size.x, plot.size.y) / _extent_nm()
	var d := (point - plot.get_center()) / maxf(scale, 0.0001)
	return _chart_center() + Vector2(d.x, -d.y)


func _recenter(point: Vector2) -> void:
	var plot := _plot_rect()
	var clamped := Vector2(
		clampf(point.x, plot.position.x, plot.end.x),
		clampf(point.y, plot.position.y, plot.end.y))
	map.set_follow_selection(false)
	map.center_on(overview_to_world(clamped))


func _ensure_terrain_cache() -> void:
	var center := _chart_center()
	var extent := _extent_nm()
	if _terrain_generation == Terrain.generation and _floor_generation == Bathymetry.generation and _terrain_size == size and _terrain_center == center and is_equal_approx(_terrain_extent, extent):
		return
	_terrain_generation = Terrain.generation
	_terrain_size = size
	_terrain_center = center
	_terrain_extent = extent
	_terrain_cache.clear()
	_floor_generation = Bathymetry.generation
	_build_floor()
	for land: Landmass in Terrain.landmasses:
		if land.points.size() < 3:
			continue
		var fill := PackedVector2Array()
		for point in land.points:
			fill.append(world_to_overview(point))
		var outline := fill.duplicate()
		outline.append(fill[0])
		_terrain_cache.append({"fill": fill, "outline": outline})


## The same depth tint as the main chart, sampled once into a small image. Where the scenario's
## coastline polygons end, the raster's own coast carries on, so the inset has no clip line either.
func _build_floor() -> void:
	_floor_texture = null
	if not Bathymetry.active:
		return
	var plot := _plot_rect()
	var w := int(plot.size.x)
	var h := int(plot.size.y)
	if w < 4 or h < 4:
		return
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var d := Bathymetry.depth_at(overview_to_world(plot.position + Vector2(x + 0.5, y + 0.5)))
			img.set_pixel(x, y, depth_color(d))
	_floor_texture = ImageTexture.create_from_image(img)


## Chart tint for a depth, matching chart_floor.gdshader. Presentation only.
static func depth_color(d: float) -> Color:
	if d < 0.0:
		return COL_WATER
	if d < 0.5:
		return COL_LAND.darkened(0.25)
	var shoal := Color(0.118, 0.262, 0.302)
	var shelf := Color(0.086, 0.215, 0.270)
	var slope := Color(0.063, 0.170, 0.232)
	var basin := Color(0.045, 0.132, 0.192)
	var abyss := Color(0.032, 0.100, 0.155)
	var c := shoal.lerp(shelf, smoothstep(0.0, 200.0, d))
	c = c.lerp(slope, smoothstep(200.0, 1200.0, d))
	c = c.lerp(basin, smoothstep(1200.0, 2800.0, d))
	return c.lerp(abyss, smoothstep(2800.0, 4500.0, d))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	draw_rect(Rect2(Vector2.ZERO, size), UITheme.COL_BORDER_LIGHT, false, 1.0)
	draw_string(UITheme.heading_font(), Vector2(PAD, 16), "TACTICAL OVERVIEW", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.COL_ACCENT)
	var scale_text := "%s NM" % Geo.format_nm(_extent_nm())
	var sw := _font.get_string_size(scale_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	draw_string(_font, Vector2(size.x - sw - PAD, 16), scale_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.COL_DIM)
	var plot := _plot_rect()
	draw_rect(plot, COL_WATER)
	if map == null:
		return
	if map.show_terrain:
		_ensure_terrain_cache()
		if _floor_texture != null:
			draw_texture_rect(_floor_texture, plot, false)
		for geometry: Dictionary in _terrain_cache:
			draw_colored_polygon(geometry["fill"], COL_LAND)
			draw_polyline(geometry["outline"], COL_COAST, 1.0, true)
	for u: Unit in map._own_units():
		var p := world_to_overview(u.position)
		if plot.has_point(p):
			draw_circle(p, 3.0 if map.selected.has(u) else 2.0, TacticalMap.COL_FRIENDLY)
	for track: Track in map._visible_tracks():
		var p := world_to_overview(track.position)
		if plot.has_point(p):
			var col := map.track_color(track)
			draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), col, track == map.selected_track, 1.0)
	var chart := map.unobstructed_chart_rect()
	var a := world_to_overview(map.screen_to_world(chart.position))
	var b := world_to_overview(map.screen_to_world(chart.end))
	var viewport := Rect2(a, b - a).abs().intersection(plot)
	if viewport.size.x > 0.0 and viewport.size.y > 0.0:
		draw_rect(viewport, Color(COL_VIEW, 0.08))
		draw_rect(viewport, COL_VIEW, false, 1.5)
	if has_focus():
		draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), UITheme.COL_ACCENT, false, 2.0)
