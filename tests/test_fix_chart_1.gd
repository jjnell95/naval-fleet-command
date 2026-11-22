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
	# The CAP is laid on the far side of the carrier from the Backfire raid: one between them goes
	# for the raid once it closes (p-air#2), and an airframe that is engaging is off its station.
	assert_true(sim.unit_manager.issue_order(cv, air.quick_order(cv, AirMission.Kind.CAP, cv.position + Vector2(0, -25))))
	var corner := escort.position + Vector2(-6, 6)
	assert_true(sim.unit_manager.issue_order(escort, Order.patrol_box(corner, corner + Vector2(12, 12))))
	SimClock.advance(600.0)
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


# --- Regional display right-click -------------------------------------------------------------

func _ship(position: Vector2) -> Unit:
	var u := Unit.new()
	u.spec = DataDB.platform("usn_ddg_burke_iii")
	u.faction = "BLUE"
	u.position = position
	u.callsign = "USS Test"
	u.health = u.spec.health
	return u


func _right_click_at(regional: RegionalMap, at: Vector2, shift := false) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	click.shift_pressed = shift
	click.position = at
	regional._gui_input(click)
	click.pressed = false
	regional._gui_input(click)


func test_a_right_click_on_the_regional_display_sends_the_hook_there() -> void:
	var sim := Simulation.new()
	sim.map_center = Vector2.ZERO
	sim.map_extent_nm = 200.0
	var map := TacticalMap.new()
	map.simulation = sim
	map.size = Vector2(1000, 600)
	map.ppn = 4.0
	var regional := RegionalMap.new()
	regional.map = map
	regional.size = Vector2(288, 288)
	var moves: Array = []
	var advice: Array = []
	map.move_order_requested.connect(func(at: Vector2, append: bool) -> void: moves.append([at, append]))
	regional.advice.connect(func(text: String) -> void: advice.append(text))
	_right_click_at(regional, Vector2(40, 60))
	assert_true(moves.is_empty(), "nothing hooked, nothing sent")
	assert_eq(advice.size(), 1, "the player is told to hook a platform first")
	map.select_units([_ship(Vector2(5, 5))])
	_right_click_at(regional, Vector2(40, 60))
	assert_eq(moves.size(), 1, "one transit ordered for the hooked ship")
	var expected := regional.regional_to_world(Vector2(40, 60))
	assert_near((moves[0][0] as Vector2).distance_to(expected), 0.0, 0.01, "to the point under the cursor")
	assert_eq(moves[0][1], false, "a plain right-click sets the course")
	_right_click_at(regional, Vector2(200, 30), true)
	assert_eq(moves.size(), 2)
	assert_eq(moves[1][1], true, "Shift adds a leg")
	assert_true(map.center_nm.is_equal_approx(Vector2.ZERO), "a right-click does not recentre the chart")
	regional.free()
	map.free()
	sim.free()


# --- Contacts on one spot ---------------------------------------------------------------------

func test_two_contacts_on_one_spot_share_a_label_instead_of_losing_both() -> void:
	var map := _map()
	# Two emitters heard from one place: their bearing lines end on the same pixel.
	map._queue_label("t:T1003", Vector2(500.4, 200.2), TacticalMap.BEARING_END_PX, "1003", "", 1.0, false)
	map._queue_label("t:T1004", Vector2(500.0, 200.0), TacticalMap.BEARING_END_PX, "1004", "", 1.0, false)
	map._queue_label("t:T1002", Vector2(560.0, 260.0), TacticalMap.BEARING_END_PX, "1002", "", 1.0, false)
	map._place_labels()
	var numbers: Array = map._label_queue.map(func(l: Dictionary) -> String: return l.number)
	assert_true(numbers.has("1003/1004"), "the pair is labelled together: %s" % [numbers])
	assert_true(numbers.has("1002"), "a contact on its own keeps its own number")
	for l: Dictionary in map._label_queue:
		assert_true(_shown(map, l.key), "%s is printed" % l.number)
	map.free()


func test_the_hooked_contact_heads_its_shared_label() -> void:
	var map := _map()
	for i in 4:
		map._queue_label("t:T10%02d" % i, Vector2(300, 300), MapSymbols.RADIUS, "10%02d" % i, "tag", 1.0, i == 2)
	map._place_labels()
	assert_eq(map._label_queue.size(), 1)
	var l: Dictionary = map._label_queue[0]
	assert_eq(l.number, "1002 +3", "the hook first, then how many more share the spot")
	assert_true(l.priority, "and the pile keeps the hook's precedence")
	assert_true(_shown(map, l.key))
	map.free()


# --- Hook brackets ------------------------------------------------------------------------------

func test_the_hooked_number_prints_clear_of_its_brackets_on_the_same_line() -> void:
	var map := _map()
	var at := Vector2(300, 300)
	map._queue_label("u:1", at, MapSymbols.RADIUS, "0001", "", 1.0, true)
	map._queue_label("u:2", Vector2(500, 300), MapSymbols.RADIUS, "0002", "", 1.0, false)
	map._place_labels()
	var hooked: Dictionary = map._label_queue[0]
	var plain: Dictionary = map._label_queue[1]
	var rect := ChartLabels.slot_box(hooked, map._labels.slot("u:1"))
	var half := roundf(TacticalMap._bracket_box(MapSymbols.RADIUS) * 0.5) + MapSymbols.STROKE * 0.5
	var brackets := Rect2(at - Vector2.ONE * half, Vector2.ONE * 2.0 * half)
	assert_true(not rect.intersects(brackets), "the number %s does not touch the brackets %s" % [rect, brackets])
	var unhooked := ChartLabels.slot_box(plain, map._labels.slot("u:2"))
	assert_near(rect.position.y - at.y, unhooked.position.y - 300.0, 0.01, "it keeps the classic height beside the symbol")
	assert_eq(ChartLabels.baseline(unhooked, plain.ascent) - Vector2(500, 300), Vector2(7, 17), "an unhooked number keeps the classic place")
	map.free()
