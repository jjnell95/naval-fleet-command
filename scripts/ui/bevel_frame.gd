class_name BevelFrame
extends PanelContainer
## A pane of the command screen, framed the way late-1990s Windows software framed things: a
## three-pixel raised bevel, light on the top and left, shadowed on the bottom and right. The
## content sits inside it with no padding, so a map or a 3D view runs right up to the frame.

const WIDTH := 3.0
const COL_HIGHLIGHT := Color("edf3f1")
const COL_MID := Color("c9ccdb")
const COL_SHADOW := Color("6b678c")

## Draw only the bottom edge, for the map, which runs to the window's other three edges.
@export var bottom_only := false
## Background painted under the content, visible only while the content is loading or absent.
@export var fill := Color("05080f")


func _ready() -> void:
	var box := StyleBoxEmpty.new()
	var w := 0.0 if bottom_only else WIDTH
	box.content_margin_left = w
	box.content_margin_top = w
	box.content_margin_right = w
	box.content_margin_bottom = WIDTH
	add_theme_stylebox_override("panel", box)
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(queue_redraw)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), fill)
	var r := Rect2(Vector2.ZERO, size)
	if bottom_only:
		_hline(r.end.y - 3.0, r.position.x, r.end.x, COL_HIGHLIGHT)
		_hline(r.end.y - 2.0, r.position.x, r.end.x, COL_MID)
		_hline(r.end.y - 1.0, r.position.x, r.end.x, COL_SHADOW)
		return
	# Outer ring: highlight top-left, shadow bottom-right; then a mid-grey ring; then the inner
	# ring inverted, which is what makes a 1999 frame read as a raised rim around a sunken pane.
	var rings := [[COL_HIGHLIGHT, COL_SHADOW], [COL_MID, COL_MID], [COL_SHADOW, COL_HIGHLIGHT]]
	for i in rings.size():
		var inset := r.grow(-float(i))
		var lit: Color = rings[i][0]
		var dark: Color = rings[i][1]
		_hline(inset.position.y, inset.position.x, inset.end.x, lit)
		_vline(inset.position.x, inset.position.y, inset.end.y, lit)
		_hline(inset.end.y - 1.0, inset.position.x, inset.end.x, dark)
		_vline(inset.end.x - 1.0, inset.position.y, inset.end.y, dark)


func _hline(y: float, x0: float, x1: float, c: Color) -> void:
	draw_rect(Rect2(x0, y, x1 - x0, 1.0), c)


func _vline(x: float, y0: float, y1: float, c: Color) -> void:
	draw_rect(Rect2(x, y0, 1.0, y1 - y0), c)
