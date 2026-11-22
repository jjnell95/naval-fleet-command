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


# --- Captions -----------------------------------------------------------------------------------

const CARRIER_WATCH := "res://data/scenarios/cold_war_03_carrier.json"
const IKE := "USS Dwight D. Eisenhower (CVN 69)"


func test_an_airframe_on_a_mission_station_leaves_the_naming_to_the_ring() -> void:
	SimClock.set_paused(true)
	var sim := Simulation.new()
	sim.seed_override = 7
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	assert_true(sim.load_scenario(CARRIER_WATCH))
	sim.ai_enabled = false
	var cv: Unit = null
	var escort: Unit = null
	for u: Unit in sim.unit_manager.units:
		if u.callsign == IKE:
			cv = u
		elif escort == null and u.faction == "BLUE" and u != cv and not u.is_aircraft() and u.spec.max_speed_kn > 0.0:
			escort = u
	var air := sim.air_mission_manager
	assert_true(sim.unit_manager.issue_order(cv, air.quick_order(cv, AirMission.Kind.CAP, cv.position + Vector2(0, 25))))
	var corner := escort.position + Vector2(-6, 6)
	assert_true(sim.unit_manager.issue_order(escort, Order.patrol_box(corner, corner + Vector2(12, 12))))
	SimClock.advance(900.0)
	var map := TacticalMap.new()
	map.simulation = sim
	map.unit_manager = sim.unit_manager
	map.player_faction = "BLUE"
	var on_station := 0
	for u: Unit in sim.unit_manager.units:
		if u.is_aircraft() and u.patrol_active and u.station_mission_id >= 0:
			on_station += 1
			assert_eq(map.patrol_caption(u), "", "%s's circuit is named by the CAP ring, not again at its corner" % u.callsign)
	assert_true(on_station > 0, "the CAP is on station")
	assert_eq(map.patrol_caption(escort), "PATROL", "a ship's own patrol box is still named")
	map.free()
	sim.unit_manager.clear()
	sim.queue_free()
	sim.free()


func test_ring_titles_circuit_names_and_cpa_captions_are_placed_not_stacked() -> void:
	var map := _map()
	map._queue_ring_title(Vector2(600, 300), 60.0, "CAP 1 · 12 nm · Hold area")
	var title := _caption_rect_queued(map, 0)
	# A circuit's corner name exactly where the ring's title prints.
	map._queue_caption(title.position + Vector2(title.size.x * 0.5, map._readout_font().get_ascent(11)), "PATROL", 11, TacticalMap.COL_ROUTE, false, Vector2.INF, map._corner_alts("PATROL", 11, 8.0))
	# A CPA caption and a track number on one spot.
	map._queue_label("t:T1028", Vector2(400, 400), MapSymbols.RADIUS, "1028", "", 1.0, false)
	var number := ChartLabels.slot_box(map._label_queue[0], 0)
	var cpa := "CPA 10.4 nm / 10m"
	map._queue_caption(number.position + Vector2(0, map._readout_font().get_ascent(11)), cpa, 11, TacticalMap.COL_READOUT, false, Vector2.INF, map._corner_alts(cpa, 11, 4.0))
	map._place_labels()
	assert_true(_shown(map, 0) and _shown(map, 1), "the ring's title and the circuit's name both print")
	assert_true(not _caption_at(map, 0).grow(ChartLabels.GAP_PX).intersects(_caption_at(map, 1)), "and neither prints over the other")
	assert_true(_shown(map, "t:T1028"), "the track number keeps its place")
	assert_true(_shown(map, 2), "the CPA finds a place of its own beside the number")
	assert_true(not _caption_at(map, 2).intersects(ChartLabels.slot_box(map._label_queue[0], map._labels.slot("t:T1028"))), "clear of the number")
	map.free()


func test_a_caption_whose_own_place_is_off_the_chart_takes_another() -> void:
	var map := _map(Vector2(400, 300))
	# A ring near the top edge: no room for its title above, so it goes under the ring.
	map._queue_ring_title(Vector2(200, 30), 20.0, "OBJECTIVE AREA")
	assert_eq(map._chart_captions.size(), 1, "the title is not dropped for want of room above")
	map._place_labels()
	assert_true(_shown(map, 0))
	assert_true(_caption_at(map, 0).position.y > 30.0, "it prints under the ring")
	map.free()


func _caption_rect_queued(map: TacticalMap, index: int) -> Rect2:
	return map._chart_captions[index].rect
