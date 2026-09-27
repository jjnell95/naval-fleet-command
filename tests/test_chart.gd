extends TestCase
## The chart's presentation: the readout's formats, the radio line's timing, the land rasters behind
## the relief and the height readout, the charted box, and the regional display's view and input.
## Everything here is presentation; none of it may show the player something the plot does not hold.

const ISLAND := {
	"id": "test_island",
	"name": "Test Island",
	"elevation_m": 300.0,
	"points_nm": [[-5, -5], [5, -5], [5, 5], [-5, 5]],
}


func _unit(faction := "BLUE", position := Vector2.ZERO, callsign := "") -> Unit:
	var u := Unit.new()
	u.spec = DataDB.platform("usn_ddg_burke_iii")
	u.faction = faction
	u.position = position
	u.callsign = callsign
	u.health = u.spec.health
	for sensor_id in u.spec.sensor_ids:
		u.sensors.append(DataDB.sensor(sensor_id))
	return u


func _world(lat: float, lon: float, lat0: float, lon0: float) -> Vector2:
	return Vector2((lon - lon0) * 60.0 * cos(deg_to_rad(lat0)), (lat - lat0) * 60.0)


# --- Readout ----------------------------------------------------------------------------

func test_position_reads_degrees_and_zero_padded_minutes() -> void:
	assert_eq(ChartReadout.format_position(30.8167, 15.7667), "30-49 N / 015-46 E")
	assert_eq(ChartReadout.format_position(12.4833, 43.9833), "12-29 N / 043-59 E")
	assert_eq(ChartReadout.format_position(-5.9999, -0.5), "06-00 S / 000-30 W", "south and west, rounded to the minute")
	assert_eq(ChartReadout.format_position(68.9999, 13.0), "69-00 N / 013-00 E", "59.99 minutes rounds up into the next degree")
	assert_eq(ChartReadout.format_position(0.0, 114.5), "00-00 N / 114-30 E")


func test_depth_and_height_read_in_feet_with_separators() -> void:
	assert_eq(ChartReadout.format_feet(309.07), "1,014 ft")
	assert_eq(ChartReadout.format_feet(102.7), "337 ft")
	assert_eq(ChartReadout.format_feet(0.0), "0 ft")
	assert_eq(ChartReadout.format_feet(400000.0), "1,312,336 ft")
	assert_eq(ChartReadout.depth_line(false, 0.0, 309.07), "Depth: 1,014 ft")
	assert_eq(ChartReadout.depth_line(true, 102.7, 0.0), "Height: 337 ft")
	assert_eq(ChartReadout.depth_line(false, 0.0, Bathymetry.UNKNOWN), "", "no chart, no depth line")


func test_scale_bar_is_a_round_length_between_60_and_160_pixels_at_every_zoom() -> void:
	var ppn := TacticalMap.MIN_PPN
	while ppn <= TacticalMap.MAX_PPN:
		var nm := ChartReadout.scale_step_nm(ppn)
		assert_true(ChartReadout.SCALE_STEPS_NM.has(nm), "a round step")
		assert_true(nm * ppn >= 60.0 and nm * ppn <= 160.0, "%.3f nm at %.2f px/nm is %.0f px" % [nm, ppn, nm * ppn])
		ppn *= 1.07
	assert_eq(ChartReadout.format_nmi(10.0), "10 nmi")
	assert_eq(ChartReadout.format_nmi(0.5), "0.5 nmi")
	assert_eq(ChartReadout.format_nmi(0.02), "0.02 nmi")


# --- Radio line -------------------------------------------------------------------------

func test_radio_line_holds_six_seconds_then_fades_over_one() -> void:
	assert_near(RadioLine.alpha_at(0.0), 1.0)
	assert_near(RadioLine.alpha_at(5.99), 1.0)
	assert_near(RadioLine.alpha_at(6.5), 0.5, 0.001)
	assert_near(RadioLine.alpha_at(7.0), 0.0)
	var radio := RadioLine.new()
	radio.post("Contact bearing 045", "info", null, 10.0)
	assert_eq(radio.visible(12.0).size(), 1, "showing during the hold")
	assert_eq(radio.visible(16.8).size(), 1, "still fading")
	assert_eq(radio.visible(17.1).size(), 0, "gone after hold plus fade")
	assert_true(radio.entries.is_empty(), "a faded line is dropped")


func test_radio_line_keeps_the_newest_three_with_the_latest_last() -> void:
	var radio := RadioLine.new()
	for i in 5:
		radio.post("line %d" % i, "alert" if i == 4 else "info", null, float(i))
	var shown := radio.visible(4.5)
	assert_eq(shown.size(), RadioLine.MAX_LINES)
	assert_eq(shown[0]["text"], "line 2", "the oldest two were dropped")
	assert_eq(shown[2]["text"], "line 4", "the latest is last (drawn at the bottom)")
	assert_eq(shown[2]["severity"], "alert")


func test_radio_line_names_its_speaker_and_rings_it_only_while_showing() -> void:
	var ship := _unit("BLUE", Vector2.ZERO, "USS Bulkeley (DDG 84)")
	assert_eq(RadioLine.format("Missile away", ship), "USS Bulkeley (DDG 84): Missile away")
	assert_eq(RadioLine.format("Mission time 08:00", null), "Mission time 08:00", "a system line is bare")
	var t := Track.new()
	t.id = "T1001"
	assert_eq(RadioLine.format("Splash", t), "T1001 UNK: Splash", "a contact goes by what the plot holds, not its true name")
	var map := TacticalMap.new()
	map.post_message("Missile away", "info", ship)
	assert_eq(map._radio.entries.size(), 1)
	assert_eq(map._radio.speakers(1.0), [ship], "the speaker is ringed while the line is up")
	assert_true(map._radio.speakers(RadioLine.HOLD_S + RadioLine.FADE_S + 0.1).is_empty(), "and not after")
	map.reset_presentation()
	assert_true(map._radio.entries.is_empty(), "a restart clears the radio line")
	map.free()


# --- Rasters ----------------------------------------------------------------------------

func test_every_region_has_land_rasters_on_the_depth_grid() -> void:
	for name: String in Bathymetry.REGIONS:
		assert_true(ResourceLoader.exists(ChartRelief.land_path(name)), "%s has a land height raster" % name)
		assert_true(ResourceLoader.exists(ChartRelief.land_relief_path(name)), "%s has a land relief raster" % name)
		var r := ChartRelief.region_rasters(name)
		var depth := Bathymetry.source_image(name)
		assert_true(r.get("land") != null and r.get("land_relief") != null and r.get("water") != null, "%s rasters load" % name)
		var heights := ChartRelief.land_heights(name)
		assert_eq(int(heights.get("w", 0)), depth.get_width(), "%s land raster shares the depth grid" % name)
		assert_eq(int(heights.get("h", 0)), depth.get_height(), "%s land raster shares the depth grid" % name)
		assert_eq((r["land_relief"] as Texture2D).get_size(), Vector2(depth.get_size()), "%s land relief shares it too" % name)


func test_water_mask_is_white_on_water_and_black_on_the_raster_land() -> void:
	var mask := (ChartRelief.region_rasters("arabian_sea")["water"] as Texture2D).get_image()
	var r: Dictionary = Bathymetry.REGIONS["arabian_sea"]
	var at := func(lat: float, lon: float) -> float:
		return mask.get_pixel(int((lon - float(r["lon_min"])) / float(r["cell_lon"])), int((float(r["lat_max"]) - lat) / float(r["cell_lat"]))).r
	assert_near(at.call(26.6, 52.0), 1.0, 0.001, "the Persian Gulf is water")
	assert_near(at.call(24.0, 60.0), 1.0, 0.001, "the Gulf of Oman is water")
	assert_near(at.call(29.0, 53.0), 0.0, 0.001, "the Zagros is land")
	assert_near(at.call(20.0, 50.0), 0.0, 0.001, "the Empty Quarter is land")


func test_height_decoding_and_bilinear_lookup() -> void:
	assert_near(ChartRelief.decode(0), 0.0)
	assert_near(ChartRelief.decode(255), 6000.0, 0.001)
	assert_near(ChartRelief.decode(128), 6000.0 * pow(128.0 / 255.0, 2.0), 0.001)
	# A 2x2 raster over a 2x2 nm box, north row first: cell centres at x 0.5/1.5, y 1.5 (north)/0.5.
	var data := PackedByteArray([0, 255, 0, 255])
	var world := Rect2(0, 0, 2, 2)
	assert_near(ChartRelief.sample_heights(data, 2, 2, world, Vector2(0.5, 1.5)), 0.0, 0.001, "west cell")
	assert_near(ChartRelief.sample_heights(data, 2, 2, world, Vector2(1.5, 0.5)), 6000.0, 0.001, "east cell")
	assert_near(ChartRelief.sample_heights(data, 2, 2, world, Vector2(1.0, 1.0)), 3000.0, 0.001, "halfway between")
	assert_eq(ChartRelief.sample_heights(data, 2, 2, world, Vector2(5.0, 1.0)), ChartRelief.UNKNOWN, "off the raster")


func test_height_readout_knows_mountains_from_the_gulf() -> void:
	Bathymetry.clear()
	assert_eq(ChartRelief.height_at(Vector2.ZERO), ChartRelief.UNKNOWN, "no chart, no height")
	Bathymetry.set_anchor(26.3, 56.6)
	assert_true(ChartRelief.height_at(_world(26.6, 52.0, 26.3, 56.6)) < 1.0, "the Persian Gulf is at sea level")
	var zagros := ChartRelief.height_at(_world(29.6, 52.5, 26.3, 56.6))
	assert_true(zagros > 1000.0 and zagros < 4500.0, "the Zagros near Shiraz is high ground: %.0f m" % zagros)
	var hajar := ChartRelief.height_at(_world(23.1, 57.5, 26.3, 56.6))
	assert_true(hajar > 400.0, "the Hajar range is high ground: %.0f m" % hajar)
	Bathymetry.clear()


func test_charted_box_hands_the_coast_to_the_polygons_only_where_there_are_polygons() -> void:
	Terrain.clear()
	var sim := Simulation.new()
	sim.scenario = {"map": {"charted_nm": [-50, -40, 60, 70]}}
	assert_eq(ChartFloor.charted_box(sim), Rect2(), "no polygons: the raster owns every coast")
	Terrain.load_from({"terrain": {"land": [ISLAND]}})
	assert_eq(ChartFloor.charted_box(sim), Rect2(-50, -40, 110, 110), "the scenario's stated charted box")
	sim.scenario = {}
	assert_eq(ChartFloor.charted_box(sim), Terrain.bounds, "no stated box: the polygons' own extent")
	Terrain.clear()
	sim.free()


# --- Regional map -----------------------------------------------------------------------

func _regional_fixture() -> Dictionary:
	var sim := Simulation.new()
	sim.map_center = Vector2.ZERO
	sim.map_extent_nm = 200.0
	var manager := UnitManager.new()
	var map := TacticalMap.new()
	map.simulation = sim
	map.unit_manager = manager
	map.size = Vector2(1000, 600)
	map.ppn = 4.0
	var regional := RegionalMap.new()
	regional.map = map
	regional.size = Vector2(288, 288)
	return {"sim": sim, "manager": manager, "map": map, "regional": regional}


func _free(f: Dictionary) -> void:
	(f["regional"] as Node).free()
	(f["map"] as Node).free()
	(f["manager"] as Node).free()
	(f["sim"] as Node).free()


func test_regional_view_rectangle_follows_the_chart() -> void:
	var f := _regional_fixture()
	var map: TacticalMap = f["map"]
	var regional: RegionalMap = f["regional"]
	var view := regional.view_rect()
	assert_near(view.get_center().x, 144.0, 0.01, "the rectangle is centred on the chart's centre")
	assert_near(view.size.x, 1000.0 / 4.0 * 288.0 / 200.0, 0.01, "and as wide as the chart's view")
	map.ppn = 8.0
	assert_near(regional.view_rect().size.x, view.size.x * 0.5, 0.01, "zooming the chart shrinks it")
	_free(f)


func test_regional_click_recentres_drag_pans_and_wheel_zooms_the_chart() -> void:
	var f := _regional_fixture()
	var map: TacticalMap = f["map"]
	var regional: RegionalMap = f["regional"]
	map.ppn = 8.0  # the rectangle spans x 54-234, y 90-198 of the pane
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(72, 72)
	regional._gui_input(click)
	assert_near(map.center_nm.x, -50.0, 0.01, "a click outside the rectangle recentres the chart there")
	assert_near(map.center_nm.y, 50.0, 0.01)
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(14.4, 0.0)
	regional._gui_input(drag)
	assert_near(map.center_nm.x, -40.0, 0.01, "dragging pans the chart by the pane's scale")
	click.pressed = false
	regional._gui_input(click)
	regional._gui_input(drag)
	assert_near(map.center_nm.x, -40.0, 0.01, "a released drag no longer pans")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	regional._gui_input(wheel)
	assert_near(map.ppn, 8.0 * TacticalMap.ZOOM_STEP, 0.001, "the wheel zooms the chart")
	_free(f)


func test_regional_radar_coverage_is_own_radiating_radars_only() -> void:
	var f := _regional_fixture()
	var manager: UnitManager = f["manager"]
	var regional: RegionalMap = f["regional"]
	var own := _unit("BLUE", Vector2(10, 5))
	var quiet := _unit("BLUE", Vector2(-20, 0))
	quiet.radar_on = false
	var hostile := _unit("RED", Vector2(40, 40))
	for u in [own, quiet, hostile]:
		manager.add_unit(u)
	var discs := regional.radar_coverage()
	assert_eq(discs.size(), 1, "one own radar on the air; a silent ship and every hostile are left out")
	assert_eq(Vector2(discs[0].x, discs[0].y), own.position)
	assert_near(discs[0].z, Detection.nominal_radar_ring_nm(own), 0.001, "the disc is the radar's horizon")
	assert_true(not regional.toggle_radar_coverage(), "the coverage layer starts on and turns off")
	_free(f)


# --- Coastline --------------------------------------------------------------------------

func test_coastline_skips_the_charted_box_clip_edges() -> void:
	var box := Rect2(0, 0, 100, 100)
	# An island in open water: one closed ring.
	var island := PackedVector2Array([Vector2(10, 10), Vector2(20, 10), Vector2(20, 20), Vector2(10, 20)])
	var runs := TacticalMap.coast_runs(island, box)
	assert_eq(runs.size(), 1)
	assert_eq(runs[0].size(), 5, "closed back to its first point")
	# A mainland clipped at the box's west and north edges: the two clip edges are not coast.
	var mainland := PackedVector2Array([Vector2(0, 60), Vector2(30, 70), Vector2(40, 100), Vector2(0, 100)])
	runs = TacticalMap.coast_runs(mainland, box)
	assert_eq(runs.size(), 1, "one run of real coast")
	assert_eq(runs[0], PackedVector2Array([Vector2(0, 60), Vector2(30, 70), Vector2(40, 100)]), "from the west edge to the north edge")
	# A land strip clipped at two opposite edges leaves two separate coasts.
	var strip := PackedVector2Array([Vector2(0, 40), Vector2(100, 45), Vector2(100, 55), Vector2(0, 50)])
	runs = TacticalMap.coast_runs(strip, box)
	assert_eq(runs.size(), 2, "the north and south shores")
	assert_eq(TacticalMap.coast_runs(mainland, Rect2()).size(), 1, "no charted box: the whole ring is coast")
	# Clipped a little inside the stated box and simplified: still a clip edge, within the margin.
	var inset := PackedVector2Array([Vector2(0.15, 60), Vector2(30, 70), Vector2(40, 98.5), Vector2(0, 98.5)])
	runs = TacticalMap.coast_runs(inset, box)
	assert_eq(runs.size(), 1, "near-edge clip segments are left out too")
	assert_eq(runs[0].size(), 3)
