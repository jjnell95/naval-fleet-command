class_name ChartCoast
extends Control
## The scenario's coastline stroked on the tactical chart: a crisp thin edge over ChartLand's fill,
## in a canvas item of its own just above it and behind the map's own drawing. The map redraws its
## plot on every simulation tick and at the idle rate; the coast changes only when the view or the
## land does, and re-emitting hundreds of anti-aliased polylines with every plot draw was the
## largest part of the chart's cost on a coast like Taiwan's. TacticalMap holds the projection and
## draws the strokes (`draw_coast`); this item only says when.

var map: TacticalMap
var _drawn_key := PackedFloat64Array()


func _init() -> void:
	show_behind_parent = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if map == null:
		return
	var key := map.coast_view_key()
	if key != _drawn_key:
		_drawn_key = key
		queue_redraw()


func _draw() -> void:
	if map != null:
		map.draw_coast(self)
