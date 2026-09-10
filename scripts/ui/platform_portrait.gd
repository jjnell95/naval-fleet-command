class_name PlatformPortrait
extends Control
## Original vector recognition illustration, never an exact platform blueprint.
var panel: UnitPanel

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var ink := Color("70e2d3")
	var dim := Color("294552")
	draw_rect(Rect2(Vector2.ZERO, size), Color("091722"))
	for x in range(0, int(size.x), 24):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(dim, 0.25))
	for y in range(0, int(size.y), 24):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(dim, 0.25))
	var unit: Unit = null
	if panel != null and not panel._units.is_empty(): unit = panel._units[0]
	var domain := unit.spec.domain if unit != null else "surface"
	var x := (size.x - minf(size.x * 0.76, 620.0)) * 0.5
	var y := size.y * 0.68
	var w := minf(size.x * 0.76, 620.0)
	if domain == "air":
		var c := Vector2(size.x * 0.5, size.y * 0.48)
		var pts := PackedVector2Array([Vector2(0,-35),Vector2(5,-8),Vector2(53,14),Vector2(50,20),Vector2(5,10),Vector2(4,27),Vector2(17,33),Vector2(17,38),Vector2(0,34),Vector2(-17,38),Vector2(-17,33),Vector2(-4,27),Vector2(-5,10),Vector2(-50,20),Vector2(-53,14),Vector2(-5,-8),Vector2(0,-35)])
		for i in pts.size(): pts[i] += c
		draw_colored_polygon(pts, Color(ink,0.12))
		draw_polyline(pts, ink, 1.5, true)
	elif domain == "subsurface":
		draw_style_box(_hull_style(ink), Rect2(x,y-28,w,26))
		draw_rect(Rect2(x+w*0.35,y-44,w*0.1,18),ink,false,1.5)
		draw_line(Vector2(x+w*0.39,y-44),Vector2(x+w*0.39,y-56),ink,1.5)
	else:
		var pts := PackedVector2Array([Vector2(x,y-12),Vector2(x+w,y-12),Vector2(x+w*0.91,y+6),Vector2(x+w*0.09,y+6),Vector2(x,y-12)])
		draw_colored_polygon(pts,Color(ink,0.13));draw_polyline(pts,ink,1.5,true)
		var superstructure := PackedVector2Array([Vector2(x+w*0.27,y-12),Vector2(x+w*0.31,y-38),Vector2(x+w*0.47,y-38),Vector2(x+w*0.51,y-28),Vector2(x+w*0.72,y-28),Vector2(x+w*0.77,y-12)])
		draw_polyline(superstructure,ink,1.5,true)
		draw_line(Vector2(x+w*0.41,y-38),Vector2(x+w*0.41,y-67),ink,1.5)
		draw_line(Vector2(x+w*0.35,y-53),Vector2(x+w*0.49,y-53),ink,1.5)
		draw_rect(Rect2(x+w*0.15,y-19,w*0.06,7),ink,false,1.5)
		draw_line(Vector2(x+w*0.16,y-19),Vector2(x+w*0.10,y-26),ink,2)
		for i in 4: draw_rect(Rect2(x+w*(0.34+i*0.027),y-33,3,4),ink)
		draw_line(Vector2(x-12,y+14),Vector2(x+w+12,y+14),dim,1)
	var font := get_theme_default_font()
	var caption := "AEGIS / MULTI-DOMAIN COMMAND" if unit == null else unit.spec.short_name.to_upper()
	draw_string(font,Vector2(12,18),caption,HORIZONTAL_ALIGNMENT_LEFT,int(size.x-24),11,ink)
	draw_string(font,Vector2(12,size.y-7),"RECOGNITION PROFILE / SCHEMATIC",HORIZONTAL_ALIGNMENT_LEFT,-1,9,Color("7d96a7"))

func _hull_style(ink: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(ink,0.12);s.border_color=ink
	s.set_border_width_all(1);s.set_corner_radius_all(13)
	return s
