class_name ChartMarks
extends Control
## The chart's moving marks, in a canvas item of their own above the plot: the pulsing ring round a
## ship with a round inbound, the impact and launch flashes, the red edge of a hit on one of ours,
## and the radio line as it fades. These change every display frame; the plot under them changes
## only on a simulation tick, a view change or the idle refresh, and redrawing the whole plot to
## move one ring cost several milliseconds a frame. TacticalMap decides when this item redraws
## and supplies what it draws.

var map: TacticalMap


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	if map != null:
		map.draw_marks(self)
