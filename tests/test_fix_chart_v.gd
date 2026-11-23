extends TestCase
## The chart's labels survive captions that come and go between placements, the player can lay
## marks, fixed range circles and corridors of their own, and the radio band hides nothing.


func _map(size := Vector2(1200, 600)) -> TacticalMap:
	var map := TacticalMap.new()
	map.size = size
	return map


func _start_frame(map: TacticalMap) -> void:
	map._chart_captions.clear()
	map._label_queue.clear()


# --- Caption places -----------------------------------------------------------------------------

func test_a_caption_never_inherits_another_captions_alternative_place() -> void:
	var map := _map()
	# A track number sits on the CPA caption's own place, so the caption takes an alternative.
	map._queue_label("t:T1028", Vector2(400, 400), MapSymbols.RADIUS, "1028", "", 1.0, false)
	var number := ChartLabels.slot_box(map._label_queue[0], 0)
	var cpa := "CPA 10.4 nm / 10m"
	map._queue_caption(number.position + Vector2(0, map._readout_font().get_ascent(11)), cpa, 11, TacticalMap.COL_READOUT, false, Vector2.INF, map._corner_alts(cpa, 11, 4.0))
	map._place_labels()
	assert_true(map._labels.slot(0) > 0, "the CPA caption is moved off the number")
	# The next frame, within the same quarter second, a caption with no alternatives takes that
	# index: a place name that happens to sit where the CPA was.
	_start_frame(map)
	map._queue_label("t:T1028", Vector2(400, 400), MapSymbols.RADIUS, "1028", "", 1.0, false)
	map._queue_caption(number.position + Vector2(0, map._readout_font().get_ascent(11)), "QESHM", 11, TacticalMap.COL_LAND_LABEL)
	map._place_labels()
	var caption: Dictionary = map._chart_captions[0]
	var k := map._labels.slot(caption.key)
	assert_true(k == ChartLabels.HIDDEN or k <= (caption.alts as Array).size(), "the place name is given one of its own places, not slot %d" % k)
	if k != ChartLabels.HIDDEN:
		var rect := ChartLabels.caption_rect(caption, k)
		assert_true(not rect.intersects(ChartLabels.slot_box(map._label_queue[0], map._labels.slot("t:T1028"))), "and it does not print over the number")
	map.free()


func test_a_caption_slot_past_its_alternatives_reads_as_its_own_place() -> void:
	var caption := {"rect": Rect2(10, 10, 40, 12), "alts": []}
	assert_eq(ChartLabels.caption_rect(caption, 2), Rect2(10, 10, 40, 12), "a stale slot cannot reach past the alternatives")
