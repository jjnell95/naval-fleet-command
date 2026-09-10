class_name MapSymbols
## Original vector symbology, NATO-inspired: friendly surface = circle, hostile = diamond,
## unknown = square. Sizes are in screen pixels and independent of zoom.

const RADIUS := 9.0
const HEADING_TICK := 8.0


static func draw_surface(ci: CanvasItem, pos: Vector2, color: Color, hostile: bool, heading_deg: float) -> void:
	if hostile:
		var r := RADIUS + 2.0
		var pts := PackedVector2Array([pos + Vector2(0, -r), pos + Vector2(r, 0), pos + Vector2(0, r), pos + Vector2(-r, 0), pos + Vector2(0, -r)])
		ci.draw_polyline(pts, color, 2.0)
	else:
		ci.draw_arc(pos, RADIUS, 0.0, TAU, 24, color, 2.0)
	var h := Vector2(sin(deg_to_rad(heading_deg)), -cos(deg_to_rad(heading_deg)))
	ci.draw_line(pos + h * RADIUS, pos + h * (RADIUS + HEADING_TICK), color, 2.0)


## A small arc under the symbol means the contact is below the surface.
static func draw_subsurface_mark(ci: CanvasItem, pos: Vector2, color: Color) -> void:
	ci.draw_arc(pos + Vector2(0.0, RADIUS + 3.0), 5.0, 0.0, PI, 12, color, 2.0)


## A small arc above the symbol means the contact is in the air.
static func draw_air_mark(ci: CanvasItem, pos: Vector2, color: Color) -> void:
	ci.draw_arc(pos + Vector2(0.0, -RADIUS - 3.0), 5.0, PI, TAU, 12, color, 2.0)


static func draw_selection(ci: CanvasItem, pos: Vector2, color: Color) -> void:
	ci.draw_arc(pos, RADIUS + 6.0, 0.0, TAU, 32, color, 1.5)


## Track symbol: hostile = diamond, unknown = square. Course tick only when kinematics are known.
static func draw_track(ci: CanvasItem, pos: Vector2, color: Color, hostile: bool, has_course: bool, course_deg: float) -> void:
	if hostile:
		var r := RADIUS + 2.0
		var pts := PackedVector2Array([pos + Vector2(0, -r), pos + Vector2(r, 0), pos + Vector2(0, r), pos + Vector2(-r, 0), pos + Vector2(0, -r)])
		ci.draw_polyline(pts, color, 2.0)
	else:
		ci.draw_rect(Rect2(pos - Vector2(RADIUS, RADIUS), Vector2(RADIUS * 2.0, RADIUS * 2.0)), color, false, 2.0)
	if has_course:
		var h := Vector2(sin(deg_to_rad(course_deg)), -cos(deg_to_rad(course_deg)))
		ci.draw_line(pos + h * RADIUS, pos + h * (RADIUS + HEADING_TICK), color, 2.0)
