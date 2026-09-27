class_name JfcStyle
extends StyleBox
## The late-1990s command chrome drawn as vectors, so it stays crisp at any window scale:
## bevelled button faces, sunken fields and list boxes (optionally with the square arrow button
## a drop-down list carries at its right end), the three-line frame between the command
## screen's panes, and the glossy LED lamps of the in-mission dialogs.
##
## UITheme builds every instance; nothing else needs to know the fields.

enum Kind { BEVEL, FRAME, LED }

@export var kind := Kind.BEVEL
## Fill. Fully transparent draws no face.
@export var face := Color.TRANSPARENT
## When set, the face shades from this colour at the top to `face` at the bottom: a metal sheen.
@export var face_top := Color.TRANSPARENT
## The lit edge: top and left when raised, bottom and right when sunken.
@export var light := Color.TRANSPARENT
## The shaded edge: bottom and right when raised, top and left when sunken.
@export var dark := Color.TRANSPARENT
## A one-pixel line round the whole shape, outside the bevel.
@export var outline := Color.TRANSPARENT
## Bevel width in pixels.
@export var edge := 1.0
@export var radius := 0.0
@export var sunken := false
## Draw a square bevelled arrow button at the right end, as a JFC drop-down list does.
@export var dropdown := false
@export var arrow_color := Color.BLACK
## FRAME: one-pixel rings from the outside in.
@export var rings := PackedColorArray()
## LED: the lamp's lit colour, and whether a lamp sits at the left of a labelled button.
@export var lamp := Color.TRANSPARENT
@export var lamp_left := false
## LED: the lamp's diameter; zero fits the rect.
@export var lamp_size := 0.0


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	match kind:
		Kind.FRAME:
			_draw_frame(to_canvas_item, rect)
		Kind.LED:
			var d := lamp_size if lamp_size > 0.0 else minf(rect.size.x, rect.size.y) - 2.0
			var centre := rect.get_center()
			if lamp_left:
				centre.x = rect.position.x + d * 0.5 + 3.0
			draw_lamp(to_canvas_item, centre, d * 0.5, lamp)
		_:
			_draw_bevel(to_canvas_item, rect)


func _draw_frame(ci: RID, rect: Rect2) -> void:
	var r := Rect2(rect.position.round(), rect.size.round())
	if face.a > 0.0:
		RenderingServer.canvas_item_add_rect(ci, r.grow(-rings.size()), face)
	for i in rings.size():
		_ring(ci, r.grow(-i), rings[i], rings[i])


## A square one-pixel ring, top and left in `a`, bottom and right in `b`.
static func _ring(ci: RID, r: Rect2, a: Color, b: Color) -> void:
	if r.size.x < 1.0 or r.size.y < 1.0:
		return
	RenderingServer.canvas_item_add_rect(ci, Rect2(r.position, Vector2(r.size.x, 1.0)), a)
	RenderingServer.canvas_item_add_rect(ci, Rect2(r.position, Vector2(1.0, r.size.y)), a)
	RenderingServer.canvas_item_add_rect(ci, Rect2(r.position.x, r.end.y - 1.0, r.size.x, 1.0), b)
	RenderingServer.canvas_item_add_rect(ci, Rect2(r.end.x - 1.0, r.position.y, 1.0, r.size.y), b)


func _draw_bevel(ci: RID, rect: Rect2) -> void:
	var r := Rect2(rect.position.round(), rect.size.round())
	var lit := dark if sunken else light
	var shade := light if sunken else dark
	draw_face(ci, r, face, face_top, lit, shade, outline, radius, edge)
	if dropdown:
		var side := maxf(r.size.y - 4.0, 8.0)
		var button := Rect2(r.end.x - side - 2.0, r.position.y + 2.0, side, side)
		draw_face(ci, button, UITheme.JFC_FACE, Color.TRANSPARENT, UITheme.JFC_BEVEL_HI, UITheme.JFC_BEVEL_LO, UITheme.JFC_GREY_BORDER, 0.0, 1.0)
		draw_triangle(ci, button.get_center() + Vector2(0.0, 1.0), side * 0.3, arrow_color)


## A face with its bevel: `lit` along the top and left, `shade` along the bottom and right, and a
## one-pixel outline round it all. Square corners are drawn pixel-exact; rounded ones anti-aliased.
static func draw_face(ci: RID, r: Rect2, fill: Color, fill_top: Color, lit: Color, shade: Color, line: Color, rad_px: float, width: float) -> void:
	if rad_px <= 0.5:
		if fill.a > 0.0:
			if fill_top.a > 0.0:
				var quad := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
				RenderingServer.canvas_item_add_polygon(ci, quad, PackedColorArray([fill_top, fill_top, fill, fill]))
			else:
				RenderingServer.canvas_item_add_rect(ci, r, fill)
		var inner := r.grow(-1.0) if line.a > 0.0 else r
		for i in int(width):
			_ring(ci, inner.grow(-i), lit, shade)
		if line.a > 0.0:
			_ring(ci, r, line, line)
		return
	var rad := minf(rad_px, minf(r.size.x, r.size.y) * 0.5)
	if fill.a > 0.0:
		var outline_pts := _rounded(r, rad, 180.0, 540.0)
		var colors := PackedColorArray([fill])
		if fill_top.a > 0.0:
			colors.resize(outline_pts.size())
			for i in outline_pts.size():
				colors[i] = fill_top.lerp(fill, clampf((outline_pts[i].y - r.position.y) / maxf(r.size.y, 1.0), 0.0, 1.0))
		RenderingServer.canvas_item_add_polygon(ci, outline_pts, colors)
	var inset := (1.0 if line.a > 0.0 else 0.0) + width * 0.5
	if lit.a > 0.0:
		RenderingServer.canvas_item_add_polyline(ci, _rounded(r.grow(-inset), maxf(rad - inset, 0.5), 135.0, 315.0), PackedColorArray([lit]), width, true)
	if shade.a > 0.0:
		RenderingServer.canvas_item_add_polyline(ci, _rounded(r.grow(-inset), maxf(rad - inset, 0.5), 315.0, 495.0), PackedColorArray([shade]), width, true)
	if line.a > 0.0:
		var closed := _rounded(r.grow(-0.5), maxf(rad - 0.5, 0.5), 180.0, 540.0)
		closed.append(closed[0])
		RenderingServer.canvas_item_add_polyline(ci, closed, PackedColorArray([line]), 1.0, true)


## Points round a rounded rectangle from `from_deg` to `to_deg`, measured clockwise on screen
## from the +x axis about each corner's centre (180 is the left side, 270 the top). Past 360 the
## walk carries on round, so 315 → 495 runs down the right side and along the bottom.
static func _rounded(r: Rect2, rad: float, from_deg: float, to_deg: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var per_quarter := maxi(int(ceil(rad * 0.5)), 2)
	var q := floorf(from_deg / 90.0) * 90.0
	while q < to_deg - 0.001:
		var a0 := maxf(q, from_deg)
		var a1 := minf(q + 90.0, to_deg)
		var centre := _corner(r, rad, int(fposmod(q, 360.0)))
		var n := maxi(int(ceil(per_quarter * (a1 - a0) / 90.0)), 1)
		for i in n + 1:
			var a := deg_to_rad(lerpf(a0, a1, float(i) / n))
			pts.append(centre + Vector2(cos(a), sin(a)) * rad)
		q += 90.0
	return pts


## The centre of the corner whose arc starts at `quadrant` degrees.
static func _corner(r: Rect2, rad: float, quadrant: int) -> Vector2:
	match quadrant:
		180:
			return Vector2(r.position.x + rad, r.position.y + rad)
		270:
			return Vector2(r.end.x - rad, r.position.y + rad)
		0:
			return Vector2(r.end.x - rad, r.end.y - rad)
	return Vector2(r.position.x + rad, r.end.y - rad)


## A small filled triangle pointing down, the arrow of a drop-down list or a scroll button.
static func draw_triangle(ci: RID, centre: Vector2, half: float, color: Color, down := true) -> void:
	var s := 1.0 if down else -1.0
	var pts := PackedVector2Array([
		centre + Vector2(-half, -half * 0.55 * s),
		centre + Vector2(half, -half * 0.55 * s),
		centre + Vector2(0.0, half * 0.6 * s),
	])
	RenderingServer.canvas_item_add_polygon(ci, pts, PackedColorArray([color]))
	var outline_pts := pts.duplicate()
	outline_pts.append(pts[0])
	RenderingServer.canvas_item_add_polyline(ci, outline_pts, PackedColorArray([color]), 1.0, true)


## A glossy lamp: a dark rim, a body shaded from its lit colour at the top left to a deep tone at
## the bottom right, and a white specular dot. A lit lamp also throws a faint halo.
static func draw_lamp(ci: RID, centre: Vector2, radius_px: float, color: Color) -> void:
	if radius_px < 2.0:
		return
	var lit := color.v > 0.0 and color.s > 0.3
	var deep := color.darkened(0.62)
	var bright := color.lightened(0.35)
	if lit:
		RenderingServer.canvas_item_add_circle(ci, centre, radius_px + 2.5, Color(color, 0.18), true)
	RenderingServer.canvas_item_add_circle(ci, centre, radius_px, color.darkened(0.72), true)
	var body := radius_px - maxf(radius_px * 0.12, 1.0)
	var steps := 7
	for i in steps:
		var t := float(i) / float(steps - 1)
		var rr := body * (1.0 - t * 0.62)
		var offset := Vector2(-0.22, -0.26) * body * t
		RenderingServer.canvas_item_add_circle(ci, centre + offset, rr, deep.lerp(color, minf(t * 1.6, 1.0)).lerp(bright, maxf(t * 1.4 - 0.6, 0.0)), true)
	RenderingServer.canvas_item_add_circle(ci, centre + Vector2(-0.34, -0.38) * body, body * 0.24, Color(1, 1, 1, 0.9), true)
	RenderingServer.canvas_item_add_circle(ci, centre + Vector2(-0.3, -0.34) * body, body * 0.42, Color(1, 1, 1, 0.16), true)
