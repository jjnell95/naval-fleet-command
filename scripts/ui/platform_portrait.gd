class_name PlatformPortrait
extends Control
## Original vector recognition illustration, never an exact platform blueprint. The silhouette
## follows the platform category so a carrier, a cruiser, a boat and a jet read differently.
var panel: UnitPanel
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var ink := UITheme.COL_ACCENT
	var dim := Color("294552")
	draw_rect(Rect2(Vector2.ZERO, size), Color("091420"))
	draw_rect(Rect2(Vector2.ZERO, size), UITheme.COL_BORDER, false, 1.0)
	for x in range(0, int(size.x), 24):
		draw_line(Vector2(x, 0), Vector2(size.x - size.x + x, size.y), Color(dim, 0.22))
	for y in range(0, int(size.y), 24):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(dim, 0.22))
	var unit: Unit = null
	if panel != null and not panel._units.is_empty():
		unit = panel._units[0]
	var domain := unit.spec.domain if unit != null else "surface"
	var category := unit.spec.category.to_lower() if unit != null else "destroyer"
	var w := minf(size.x * 0.78, 620.0)
	var x := (size.x - w) * 0.5
	var y := size.y * 0.66
	if domain == "air":
		_draw_aircraft(Vector2(size.x * 0.5, size.y * 0.5), category, ink)
	elif domain == "subsurface":
		_draw_submarine(x, y, w, ink)
	elif domain == "land":
		_draw_base(x, y, w, ink)
	elif category.contains("carrier"):
		_draw_carrier(x, y, w, ink)
	elif category.contains("merchant") or category.contains("replenish") or category.contains("auxiliar"):
		_draw_merchant(x, y, w, ink)
	else:
		_draw_combatant(x, y, w, ink, category.contains("cruiser"))
	if domain != "air":
		draw_line(Vector2(x - 12, y + 12), Vector2(x + w + 12, y + 12), Color(ink, 0.35), 1)
	var caption := "AEGIS / MULTI-DOMAIN COMMAND" if unit == null else unit.spec.short_name.to_upper()
	draw_string(_font, Vector2(10, 15), caption, HORIZONTAL_ALIGNMENT_LEFT, int(size.x - 20), 10, ink)
	var tag := "RECOGNITION PROFILE" if unit == null else "%s · %s" % [unit.spec.category.to_upper(), unit.spec.nation.to_upper()]
	draw_string(_font, Vector2(10, size.y - 6), tag, HORIZONTAL_ALIGNMENT_LEFT, int(size.x - 20), 9, UITheme.COL_DIM)


func _hull(x: float, y: float, w: float, ink: Color, bow_sharp := true) -> void:
	var pts := PackedVector2Array([Vector2(x, y - 12), Vector2(x + w, y - 12 if not bow_sharp else y - 15), Vector2(x + w * 0.92, y + 5), Vector2(x + w * 0.08, y + 5)])
	draw_colored_polygon(pts, Color(ink, 0.13))
	pts.append(pts[0])
	draw_polyline(pts, ink, 1.5, true)


func _draw_combatant(x: float, y: float, w: float, ink: Color, cruiser: bool) -> void:
	_hull(x, y, w, ink)
	var s := PackedVector2Array([Vector2(x + w * 0.27, y - 12), Vector2(x + w * 0.30, y - 34), Vector2(x + w * 0.46, y - 34), Vector2(x + w * 0.50, y - 26), Vector2(x + w * 0.70, y - 26), Vector2(x + w * 0.74, y - 12)])
	draw_polyline(s, ink, 1.5, true)
	draw_line(Vector2(x + w * 0.40, y - 34), Vector2(x + w * 0.40, y - 60), ink, 1.5)
	draw_line(Vector2(x + w * 0.35, y - 48), Vector2(x + w * 0.47, y - 48), ink, 1.5)
	# Phased-array face on the deckhouse: the shape of an Aegis ship.
	draw_rect(Rect2(x + w * 0.33, y - 31, w * 0.05, 7), ink, false, 1.0)
	draw_rect(Rect2(x + w * 0.15, y - 19, w * 0.06, 7), ink, false, 1.5)
	draw_line(Vector2(x + w * 0.16, y - 19), Vector2(x + w * 0.10, y - 26), ink, 2)
	var cells := 6 if cruiser else 4
	for i in cells:
		draw_rect(Rect2(x + w * (0.52 + i * 0.026), y - 24, 3, 4), ink)
	if cruiser:
		draw_line(Vector2(x + w * 0.62, y - 26), Vector2(x + w * 0.62, y - 44), ink, 1.5)


func _draw_carrier(x: float, y: float, w: float, ink: Color) -> void:
	var deck := PackedVector2Array([Vector2(x - 6, y - 22), Vector2(x + w + 6, y - 22), Vector2(x + w + 6, y - 14), Vector2(x - 6, y - 14)])
	draw_colored_polygon(deck, Color(ink, 0.18))
	deck.append(deck[0])
	draw_polyline(deck, ink, 1.5, true)
	var hull := PackedVector2Array([Vector2(x + 4, y - 14), Vector2(x + w - 4, y - 14), Vector2(x + w * 0.9, y + 6), Vector2(x + w * 0.1, y + 6)])
	draw_colored_polygon(hull, Color(ink, 0.10))
	hull.append(hull[0])
	draw_polyline(hull, ink, 1.5, true)
	draw_rect(Rect2(x + w * 0.62, y - 44, w * 0.10, 22), ink, false, 1.5)
	draw_line(Vector2(x + w * 0.67, y - 44), Vector2(x + w * 0.67, y - 66), ink, 1.5)
	for i in 5:
		draw_line(Vector2(x + w * (0.15 + i * 0.09), y - 22), Vector2(x + w * (0.15 + i * 0.09) + 6, y - 22), Color(ink, 0.6), 3)


func _draw_merchant(x: float, y: float, w: float, ink: Color) -> void:
	_hull(x, y, w, ink, false)
	draw_rect(Rect2(x + w * 0.08, y - 36, w * 0.14, 24), ink, false, 1.5)
	draw_line(Vector2(x + w * 0.15, y - 36), Vector2(x + w * 0.15, y - 50), ink, 1.5)
	for i in 3:
		draw_line(Vector2(x + w * (0.35 + i * 0.18), y - 12), Vector2(x + w * (0.35 + i * 0.18), y - 30), ink, 1.5)


func _draw_submarine(x: float, y: float, w: float, ink: Color) -> void:
	var pts := PackedVector2Array()
	for i in 41:
		var a := lerpf(-PI * 0.5, PI * 0.5, i / 40.0)
		pts.append(Vector2(x + w * 0.5 + sin(a) * w * 0.5, y - 12 - cos(a) * 14))
	for i in 41:
		var a := lerpf(PI * 0.5, PI * 1.5, i / 40.0)
		pts.append(Vector2(x + w * 0.5 + sin(a) * w * 0.5, y - 12 - cos(a) * 14))
	draw_colored_polygon(pts, Color(ink, 0.13))
	pts.append(pts[0])
	draw_polyline(pts, ink, 1.5, true)
	draw_rect(Rect2(x + w * 0.40, y - 44, w * 0.10, 18), ink, false, 1.5)
	draw_line(Vector2(x + w * 0.44, y - 44), Vector2(x + w * 0.44, y - 58), ink, 1.5)
	draw_line(Vector2(x + w * 0.85, y - 32), Vector2(x + w * 0.85, y + 6), ink, 1.5)


func _draw_base(x: float, y: float, w: float, ink: Color) -> void:
	draw_rect(Rect2(x, y - 6, w, 6), Color(ink, 0.3))
	draw_rect(Rect2(x, y - 6, w, 6), ink, false, 1.0)
	draw_rect(Rect2(x + w * 0.1, y - 30, w * 0.18, 24), ink, false, 1.5)
	draw_line(Vector2(x + w * 0.3, y - 6), Vector2(x + w * 0.3, y - 40), ink, 1.5)


func _draw_aircraft(c: Vector2, category: String, ink: Color) -> void:
	var pts: PackedVector2Array
	if category.contains("helicopter") or category.contains("helo"):
		pts = PackedVector2Array([Vector2(0, -22), Vector2(10, -16), Vector2(12, 4), Vector2(6, 16), Vector2(24, 36), Vector2(20, 38), Vector2(3, 22), Vector2(-3, 22), Vector2(-20, 38), Vector2(-24, 36), Vector2(-6, 16), Vector2(-12, 4), Vector2(-10, -16)])
		draw_line(c + Vector2(-46, -4), c + Vector2(46, -4), Color(ink, 0.6), 1.5)
		draw_line(c + Vector2(-4, -46), c + Vector2(4, 38), Color(ink, 0.6), 1.5)
	elif category.contains("patrol") or category.contains("early") or category.contains("bomber") or category.contains("aew"):
		pts = PackedVector2Array([Vector2(0, -42), Vector2(5, -20), Vector2(64, 2), Vector2(64, 8), Vector2(6, 2), Vector2(4, 28), Vector2(20, 38), Vector2(20, 42), Vector2(0, 38), Vector2(-20, 42), Vector2(-20, 38), Vector2(-4, 28), Vector2(-6, 2), Vector2(-64, 8), Vector2(-64, 2), Vector2(-5, -20)])
		if category.contains("early") or category.contains("aew"):
			draw_arc(c + Vector2(0, 6), 22.0, 0.0, TAU, 32, ink, 1.5, true)
	else:
		pts = PackedVector2Array([Vector2(0, -38), Vector2(5, -8), Vector2(53, 14), Vector2(50, 20), Vector2(5, 10), Vector2(4, 27), Vector2(17, 33), Vector2(17, 38), Vector2(0, 34), Vector2(-17, 38), Vector2(-17, 33), Vector2(-4, 27), Vector2(-5, 10), Vector2(-50, 20), Vector2(-53, 14), Vector2(-5, -8)])
	for i in pts.size():
		pts[i] += c
	draw_colored_polygon(pts, Color(ink, 0.12))
	pts.append(pts[0])
	draw_polyline(pts, ink, 1.5, true)
	if category.contains("electronic"):
		draw_arc(c + Vector2(0, 8), 30.0, PI * 1.15, PI * 1.85, 16, Color("f08cf0"), 1.5, true)
		draw_arc(c + Vector2(0, 8), 40.0, PI * 1.2, PI * 1.8, 16, Color("f08cf0", 0.5), 1.0, true)
