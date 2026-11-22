extends TestCase
## A chart you can read: the radio line keeps a band of its own, chart captions are placed rather
## than stacked, and the regional display takes a right-click transit like the chart does.


func _map(size := Vector2(1200, 600)) -> TacticalMap:
	var map := TacticalMap.new()
	map.size = size
	return map


func _shown(map: TacticalMap, key: Variant) -> bool:
	return map._labels.slot(key) != ChartLabels.HIDDEN


## The rect a queued caption prints in, where it was placed.
func _caption_at(map: TacticalMap, index: int) -> Rect2:
	var caption: Dictionary = map._chart_captions[index]
	return ChartLabels.caption_rect(caption, map._labels.slot(caption.key))


# --- Radio band -------------------------------------------------------------------------------

func test_place_names_and_track_numbers_keep_out_of_the_radio_band() -> void:
	var map := _map()
	map.post_message("Khalij Fars anti-ship ballistic missile, impact in ~2 s", "alert")
	map.post_message("HMS Duncan (D 37): Hit — critical · FIRE · FLOODING", "alert")
	var layout := map.radio_layout()
	var plate: Rect2 = layout["plate"]
	assert_eq((layout["rows"] as Array).size(), 2)
	var font := map._readout_font()
	for row: Dictionary in layout["rows"]:
		var width := font.get_string_size(row["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, TacticalMap.READOUT_FONT_SIZE).x
		var text := Rect2((map.size.x - width) * 0.5, float(row["baseline"]) - font.get_ascent(TacticalMap.READOUT_FONT_SIZE), width, font.get_height(TacticalMap.READOUT_FONT_SIZE))
		assert_true(plate.encloses(text), "the plate is behind the whole of '%s'" % row["text"])
	# A coast name and a contact's number exactly where the bottom row prints, and one name well clear.
	var bottom: float = (layout["rows"] as Array)[0]["baseline"]
	map._queue_caption(Vector2(map.size.x * 0.5, bottom), "UNITED ARAB EMIRATES", 11, TacticalMap.COL_LAND_LABEL, true)
	map._queue_caption(Vector2(map.size.x * 0.5, 100.0), "GULF OF OMAN", 11, TacticalMap.COL_LAND_LABEL, true)
	map._queue_label("t:T1002", Vector2(map.size.x * 0.5 - 20.0, bottom - 22.0), MapSymbols.RADIUS, "1002", "", 1.0, false)
	map._place_labels()
	assert_true(not _shown(map, 0) or not _caption_at(map, 0).intersects(plate), "the place name does not print through the radio line")
	assert_true(_shown(map, 1), "a name away from the band still prints")
	if _shown(map, "t:T1002"):
		var label: Dictionary = map._label_queue[0]
		assert_true(not ChartLabels.slot_box(label, map._labels.slot("t:T1002")).intersects(plate), "the track number is placed clear of the radio line")
	map.free()


func test_the_band_is_released_when_the_radio_line_clears() -> void:
	var map := _map()
	map.post_message("New contact, track 1002 (Radar)")
	var bottom := map.size.y - TacticalMap.RADIO_BOTTOM_PX - 3.0
	map._queue_caption(Vector2(map.size.x * 0.5, bottom), "MUSANDAM", 11, TacticalMap.COL_LAND_LABEL, true)
	map._place_labels()
	assert_true(not _shown(map, 0), "under a message the name gives way")
	map._radio.clear()
	map._place_labels()
	assert_true(map.radio_layout().is_empty(), "nothing on the air")
	assert_true(_shown(map, 0), "the name returns at once when the band clears, not a beat later")
	map.free()


func test_a_board_over_the_chart_takes_the_radio_band_with_it() -> void:
	var map := _map()
	map.post_message("Splash one")
	map.overlay_covered = true
	var bottom := map.size.y - TacticalMap.RADIO_BOTTOM_PX - 3.0
	map._queue_caption(Vector2(map.size.x * 0.5, bottom), "QESHM", 11, TacticalMap.COL_LAND_LABEL, true)
	map._place_labels()
	assert_true(_shown(map, 0), "the radio line is not drawn under a board, so it reserves nothing")
	map.free()
