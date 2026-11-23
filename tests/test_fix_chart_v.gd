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


# --- Plotting aids --------------------------------------------------------------------------------

const HORMUZ := "res://data/scenarios/gulf_01_hormuz.json"

var _save_root := ""
var _clock_speeds: Array[float] = []


func _open() -> Main:
	_save_root = SaveGame.root_override
	_clock_speeds = SimClock.speeds()
	SaveGame.root_override = "user://test-chart-marks-%d" % Time.get_ticks_usec()
	var main: Main = preload("res://scenes/main/Main.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main._apply_options(GameOptions.normal(), false, false)
	main.simulation.seed_override = 2
	main.start_scenario(HORMUZ)
	main._on_briefing_start()
	SimClock.set_paused(true)
	# Headless, nothing lays the screen out: give the chart the size a window would.
	main.map.size = Vector2(1200, 600)
	main.map.fit_to(main.map.center_nm, 60.0)
	return main


func _close(main: Main) -> void:
	main.free()
	var dir := DirAccess.open(SaveGame.root_override)
	if dir != null:
		for file in dir.get_files():
			dir.remove(file)
		DirAccess.remove_absolute(SaveGame.root_override)
	SaveGame.root_override = _save_root
	SimClock.set_speeds(_clock_speeds)
	SimClock.set_speed_index(0)
	SimClock.set_paused(true)


## Open water on the chart, away from every symbol: a point and three more within 100 px of it.
func _water(main: Main) -> Array:
	var spots: Array = []
	for fx in [0.2, 0.35, 0.5, 0.65, 0.8]:
		for fy in [0.3, 0.5, 0.7]:
			var p: Vector2 = main.map.size * Vector2(fx, fy)
			var around: Array = [p]
			for d: Vector2 in [Vector2(60, 0), Vector2(0, 80), Vector2(-60, 40), Vector2(100, 0), Vector2(0, -80), Vector2(-60, -40)]:
				around.append(p + d)
			var open := around.filter(func(q: Vector2) -> bool: return str(main.map.context_at(q)["kind"]) == "water" and main.map.annotations.nearest(main.map.screen_to_world(q), 30.0 / main.map.ppn) < 0)
			if open.size() >= 4 and open[0] == p:
				return open
	return []


## Right-clicks `p` on the chart with nothing hooked and chooses `path` (menu texts, outermost first)
## the way a click on each would. Returns false when an entry is missing or disabled.
func _choose(main: Main, p: Vector2, path: Array) -> bool:
	main.map.select_units([])
	main._on_map_context(p, main.map.context_at(p))
	var menu: PopupMenu = main._cds_menus._root
	for i in path.size():
		var found := -1
		for k in menu.item_count:
			if menu.get_item_text(k) == str(path[i]):
				found = k
		if found < 0 or menu.is_item_disabled(found):
			main._cds_menus.close()
			return false
		if i < path.size() - 1:
			menu = menu.get_item_submenu_node(found)
		else:
			menu.id_pressed.emit(menu.get_item_id(found))
	main._cds_menus.close()
	return true


func _captions(main: Main) -> PackedStringArray:
	main.map._chart_captions.clear()
	main.map._queue_annotation_captions()
	var out := PackedStringArray()
	for c: Dictionary in main.map._chart_captions:
		out.append(c.text)
	main.map._chart_captions.clear()
	return out


func test_the_commander_lays_marks_fixed_range_circles_and_corridors_from_the_chart_menu() -> void:
	var main := _open()
	var map := main.map
	var spots := _water(main)
	assert_eq(spots.size() >= 4, true, "open water to click on")
	var p: Vector2 = spots[0]
	var world := map.screen_to_world(p)
	assert_true(_choose(main, p, ["Chart marks", "Mark this position"]), "the chart menu offers a mark")
	assert_eq(map.annotations.items.size(), 1)
	assert_true((map.annotations.items[0].at as Vector2).distance_to(world) < 0.01, "at the point clicked")
	assert_true(main.radio.last_advice.begins_with("Mark M1 laid"), "the radio confirms it: %s" % main.radio.last_advice)
	# A range circle fixed on a point with nothing hooked: B alone cannot do that.
	var q: Vector2 = spots[1]
	assert_true(_choose(main, q, ["Chart marks", "Range circle here", "10 nm"]))
	var circle: Dictionary = map.annotations.items[1]
	assert_eq(circle.kind, ChartAnnotations.CIRCLE)
	assert_near(float(circle.radius_nm), 10.0, 0.001)
	assert_true((circle.at as Vector2).distance_to(map.screen_to_world(q)) < 0.01, "centred where it was asked for, not on a hook")
	# A corridor in two clicks.
	var r: Vector2 = spots[2]
	assert_true(_choose(main, p, ["Chart marks", "Start a corridor here"]))
	assert_true(_choose(main, r, ["Chart marks", "End corridor here", "5 nm wide"]))
	var lane: Dictionary = map.annotations.items[2]
	assert_eq(lane.kind, ChartAnnotations.CORRIDOR)
	assert_true((lane.to as Vector2).distance_to(map.screen_to_world(r)) < 0.01)
	assert_true(not map.annotations.corridor_from.is_finite(), "the corridor is finished")
	var shown := _captions(main)
	for text in ["M1", "R1  10 nm", "C1  5 nm"]:
		assert_true(shown.has(text), "%s is labelled on the chart: %s" % [text, shown])
	# The marks are part of the saved picture.
	var saved: Variant = bytes_to_var(var_to_bytes(main._capture_presentation()))
	map.annotations.clear()
	var view := map.chart_view()
	main._restore_presentation(saved)
	map.size = Vector2(1200, 600)  # the restore lays the views out again
	map.restore_chart_view(view)
	assert_eq(map.annotations.items.size(), 3, "a load puts the marks back")
	assert_true(_choose(main, spots[3], ["Chart marks", "Mark this position"]))
	assert_eq(map.annotations.items[3].label, "M2", "and numbering carries on after them")
	# Right-click on a mark to take it off.
	assert_true(_choose(main, p, ["Chart marks", "Remove M1"]), "the mark under the click can be removed")
	assert_eq(map.annotations.items.size(), 3)
	assert_true(_choose(main, p, ["Chart marks", "Clear all marks"]))
	assert_true(map.annotations.is_empty())
	_close(main)


func test_an_older_save_without_marks_loads_with_a_clear_chart() -> void:
	var aids := ChartAnnotations.new()
	aids.add_mark(Vector2(1, 2))
	aids.restore(null)
	assert_true(aids.is_empty())
	aids.restore({"items": [{"kind": "mark", "label": "M7", "at": Vector2(3, 4)}, {"kind": "corridor", "at": Vector2.ZERO}]})
	assert_eq(aids.items.size(), 1, "a malformed aid is dropped, a good one kept")
	assert_eq(aids.add_mark(Vector2.ONE), "M8", "no new mark repeats a label on the chart")


func test_the_allied_filter_is_in_the_menu() -> void:
	var map := _map()
	var items := CdsMenus.filter_items(CommandBar.filter_state(map))
	var texts: Array = items.map(func(it: Dictionary) -> String: return str(it.get("text", "")))
	assert_true(texts.has("Allied contacts"), "the allied layer can be filtered: %s" % [texts])
	for it: Dictionary in items:
		if it.get("text", "") == "Allied contacts":
			assert_eq(it.action.name, "allied")
			assert_eq(it.checked, 1, "shown to start with")
	assert_true(not map.toggle_layer("allied") and not map.identity_shown("ALLIED"), "and turning it off hides allied contacts")
	map.free()


# --- Chart captions ---------------------------------------------------------------------------------

func test_a_boat_awaiting_check_in_is_captioned_clear_of_track_numbers() -> void:
	var map := _map()
	var units := UnitManager.new()
	map.unit_manager = units
	var sub := Unit.new()
	sub.spec = DataDB.platform("cw90_los_angeles")
	sub.faction = "BLUE"
	sub.health = sub.spec.health
	sub.comms_enabled = true
	sub.depth_m = 200.0
	sub.position = map.screen_to_world(Vector2(500, 300))
	sub.comms_report = {"position": sub.position, "heading_deg": 0.0, "speed_kn": 5.0, "depth_m": 200.0, "health": sub.spec.health}
	map.selected = [sub]
	map._own_cache = [sub]
	map._own_in_draw = true
	var sp := map.world_to_screen(sub.position)
	# A contact's number right where the caption would first print.
	map._queue_label("t:T1040", sp + Vector2(30, -30), MapSymbols.RADIUS, "1040", "", 1.0, false)
	map._draw_sensor_rings()
	map._own_in_draw = false
	var texts: Array = map._chart_captions.map(func(c: Dictionary) -> String: return c.text)
	assert_true(texts.has("SENSOR STATUS · AWAITING CHECK-IN"), "the boat's caption is placed with the other chart text: %s" % [texts])
	map._place_labels()
	if not map._chart_captions.is_empty():
		var caption: Dictionary = map._chart_captions[0]
		var k := map._labels.slot(caption.key)
		var number := ChartLabels.slot_box(map._label_queue[0], map._labels.slot("t:T1040"))
		assert_true(k == ChartLabels.HIDDEN or not ChartLabels.caption_rect(caption, k).intersects(number), "and never prints over a track number")
		assert_true(map._labels.slot("t:T1040") != ChartLabels.HIDDEN, "the number keeps its place")
	map.free()
	units.free()


# --- Radio band and fixed sites -------------------------------------------------------------------

static func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func test_an_own_ship_under_the_radio_band_stays_readable_and_keeps_its_number() -> void:
	var map := _map()
	map.post_message("HMS Duncan (D 37): Hit — critical · FIRE · FLOODING", "alert")
	var plate: Rect2 = map.radio_layout()["plate"]
	# The ship's symbol seen through the plate keeps more than half its contrast with the sea.
	var wash := TacticalMap.COL_RADIO_PLATE
	var symbol := TacticalMap.COL_FRIENDLY.lerp(Color(wash, 1.0), wash.a)
	var sea := TacticalMap.COL_OCEAN.lerp(Color(wash, 1.0), wash.a)
	var open := absf(_luma(TacticalMap.COL_FRIENDLY) - _luma(TacticalMap.COL_OCEAN))
	assert_true(absf(_luma(symbol) - _luma(sea)) > 0.5 * open, "the symbol under the band is still plainly drawn")
	# Its number stands clear of the band on a leader rather than being dropped.
	var at := plate.get_center()
	map._queue_label("u:7", at, MapSymbols.RADIUS, "0007", "", 1.0, false)
	map._place_labels()
	var k := map._labels.slot("u:7")
	assert_true(k != ChartLabels.HIDDEN, "the ship under the band keeps its number")
	if k != ChartLabels.HIDDEN:
		assert_true(not ChartLabels.slot_box(map._label_queue[0], k).intersects(plate), "printed clear of the radio rows")
	map.free()


func _site() -> Track:
	var t := Track.new()
	t.id = "T1050"
	t.identity = "HOSTILE"
	t.domain = "land"
	t.has_kinematics = false
	t.status = Track.Status.ACTIVE
	return t


func test_a_fixed_land_site_does_not_read_as_if_it_might_move() -> void:
	var map := _map()
	var card := "\n".join(map.track_hover_lines(_site()))
	assert_true(card.contains("Fixed site"), "the hover card names a fixed site: %s" % card)
	assert_true(not card.contains("estimating"), "and does not say its motion is being estimated")
	var ship := _site()
	ship.domain = "surface"
	assert_true("\n".join(map.track_hover_lines(ship)).contains("Kinematics estimating"), "a ship with no solution yet is still estimating")
	map.free()
	var panel := ContactPanel.new()
	var detail := panel._detail_text(_site(), null, 0.0)
	assert_true(detail.contains("fixed site") and not detail.contains("estimating"), "the contact panel says the same: %s" % detail)
	panel.free()
