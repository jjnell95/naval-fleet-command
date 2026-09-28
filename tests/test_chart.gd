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


func test_land_fill_is_one_mesh_for_every_landmass() -> void:
	# Regression: ChartLand drew one mesh per landmass, 689 draw calls a frame in the regional pane
	# for northern_vigil. The whole coastline is one mesh now: one draw call, the same triangles.
	var sc = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/northern_vigil.json"))
	Terrain.load_from(sc)
	assert_true(Terrain.landmasses.size() > 600, "a coastline of many islands")
	var mesh := ChartLand.land_mesh()
	assert_true(mesh != null and mesh.get_surface_count() == 1, "one mesh of one surface for %d landmasses" % Terrain.landmasses.size())
	var verts := 0
	var indices := 0
	for l: Landmass in Terrain.landmasses:
		var tri := Geometry2D.triangulate_polygon(l.points)
		if not tri.is_empty():
			verts += l.points.size()
			indices += tri.size()
	if mesh != null:
		assert_eq(mesh.surface_get_array_len(0), verts, "every landmass's vertices")
		assert_eq(mesh.surface_get_array_index_len(0), indices, "and every landmass's own triangulation")
		var box := mesh.get_aabb()
		var b := Terrain.bounds
		assert_true(Vector2(box.position.x, box.position.y).is_equal_approx(Vector2(b.position.x, -b.end.y)) and Vector2(box.size.x, box.size.y).is_equal_approx(b.size), "in world nm with y negated, as the land shader reads it")
	assert_eq(ChartLand.land_mesh(), mesh, "built once per coastline")
	Terrain.load_from({"terrain": {"land": [ISLAND]}})
	var island := ChartLand.land_mesh()
	assert_true(island != null and island != mesh and island.surface_get_array_len(0) == 4, "rebuilt when the coastline changes")
	Terrain.clear()
	assert_eq(ChartLand.land_mesh(), null, "no land, no mesh")


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
	assert_near(view.size.x, 1000.0 / 4.0 * 288.0 / regional.wanted_extent_nm(), 0.01, "and as wide as the chart's view")
	assert_near(regional.wanted_extent_nm(), 200.0 * RegionalMap.THEATRE_MARGIN, 0.01, "the pane shows the theatre with a margin")
	map.ppn = 8.0
	assert_near(regional.view_rect().size.x, view.size.x * 0.5, 0.01, "zooming the chart shrinks it")
	_free(f)


func test_regional_click_recentres_drag_pans_and_wheel_zooms_the_chart() -> void:
	var f := _regional_fixture()
	var map: TacticalMap = f["map"]
	var regional: RegionalMap = f["regional"]
	map.ppn = 8.0
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(12, 12)  # well outside the rectangle, which sits round the centre
	assert_true(not regional.view_rect().has_point(click.position))
	var expected := regional.regional_to_world(click.position)
	regional._gui_input(click)
	assert_near(map.center_nm.x, expected.x, 0.01, "a click outside the rectangle recentres the chart there")
	assert_near(map.center_nm.y, expected.y, 0.01)
	var scale := regional.size.x / regional.wanted_extent_nm()  # pane px per nm, now the chart has moved
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(14.4, 0.0)
	regional._gui_input(drag)
	assert_near(map.center_nm.x, expected.x + 14.4 / scale, 0.01, "dragging pans the chart by the pane's scale")
	click.pressed = false
	regional._gui_input(click)
	regional._gui_input(drag)
	assert_near(map.center_nm.x, expected.x + 14.4 / scale, 0.01, "a released drag no longer pans")
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


# --- Symbology --------------------------------------------------------------------------

func test_identity_colours_are_the_classic_displays() -> void:
	assert_eq(TacticalMap.COL_FRIENDLY, Color8(64, 200, 255), "ownside light cyan-blue")
	assert_eq(TacticalMap.COL_ALLIED, Color8(255, 150, 40), "allied orange")
	assert_eq(TacticalMap.COL_HOSTILE, Color8(235, 30, 30), "hostile red")
	assert_eq(TacticalMap.COL_UNKNOWN, Color8(245, 235, 30), "unknown yellow")
	assert_eq(TacticalMap.COL_NEUTRAL, Color8(40, 220, 60), "neutral green")
	var map := TacticalMap.new()
	var t := Track.new()
	for pair in [["HOSTILE", TacticalMap.COL_HOSTILE], ["NEUTRAL", TacticalMap.COL_NEUTRAL], ["ALLIED", TacticalMap.COL_ALLIED], ["UNKNOWN", TacticalMap.COL_UNKNOWN]]:
		t.identity = pair[0]
		assert_eq(map.track_color(t), pair[1], "%s track colour" % pair[0])
	map.free()


func test_ntds_frames_carry_identity_and_domain_in_a_16_px_box() -> void:
	assert_eq(MapSymbols.frame_for_identity("HOSTILE"), MapSymbols.Frame.HOSTILE)
	assert_eq(MapSymbols.frame_for_identity("NEUTRAL"), MapSymbols.Frame.NEUTRAL)
	assert_eq(MapSymbols.frame_for_identity("ALLIED"), MapSymbols.Frame.ALLIED)
	assert_eq(MapSymbols.frame_for_identity("UNKNOWN"), MapSymbols.Frame.UNKNOWN)
	assert_eq(MapSymbols.frame_for_identity(""), MapSymbols.Frame.UNKNOWN, "no identity yet is unknown")
	for frame in MapSymbols.Frame.values():
		for domain in ["air", "surface", "subsurface", ""]:
			for p: Vector2 in MapSymbols.frame_stroke(frame, domain):
				assert_true(absf(p.x) <= MapSymbols.RADIUS + 0.5 and absf(p.y) <= MapSymbols.RADIUS + 0.5, "frame %d %s stays in the 16 px box" % [frame, domain])
	var surface := MapSymbols.frame_stroke(MapSymbols.Frame.FRIENDLY, "surface")
	assert_eq(surface[0], surface[surface.size() - 1], "a surface frame is closed")
	var air := MapSymbols.frame_stroke(MapSymbols.Frame.FRIENDLY, "air")
	assert_true(air[0] != air[air.size() - 1], "an air frame is open at the bottom")
	assert_true(_top(air) < -3.0 and _bottom(air) <= 3.6, "the friendly air arc is the upper semicircle")
	var sub := MapSymbols.frame_stroke(MapSymbols.Frame.FRIENDLY, "subsurface")
	assert_true(_bottom(sub) > 3.0 and _top(sub) >= -3.6, "the friendly subsurface arc is the lower one")
	assert_eq(MapSymbols.frame_stroke(MapSymbols.Frame.HOSTILE, "surface").size(), 5, "hostile surface is a closed diamond")
	assert_eq(MapSymbols.frame_stroke(MapSymbols.Frame.HOSTILE, "air")[1], Vector2(0.0, -6.0), "hostile air is a chevron pointing up")
	assert_eq(MapSymbols.frame_stroke(MapSymbols.Frame.HOSTILE, "subsurface")[1], Vector2(0.0, 6.0), "hostile subsurface points down")
	var square := MapSymbols.frame_stroke(MapSymbols.Frame.UNKNOWN, "surface")
	assert_eq(square.size(), 5, "unknown surface is a closed square")
	assert_true(is_equal_approx(absf(square[0].x), absf(square[0].y)), "with square corners")
	assert_eq(MapSymbols.frame_stroke(MapSymbols.Frame.UNKNOWN, "air").size(), 4, "unknown air is an open upper half-square")
	assert_eq(MapSymbols.frame_stroke(MapSymbols.Frame.NEUTRAL, "surface"), surface, "neutral shares the friendly frames")
	assert_eq(MapSymbols.frame_stroke(MapSymbols.Frame.ALLIED, "air"), air, "and so does allied")
	assert_true(MapSymbols.is_rotary("ASW helicopter") and MapSymbols.is_rotary("shipboard rotary-wing drone"), "rotorcraft get the helicopter bar")
	assert_true(not MapSymbols.is_rotary("fighter"))


func _top(pts: PackedVector2Array) -> float:
	var y := INF
	for p in pts:
		y = minf(y, p.y)
	return y


func _bottom(pts: PackedVector2Array) -> float:
	var y := -INF
	for p in pts:
		y = maxf(y, p.y)
	return y


func test_track_numbers_are_four_digits_and_own_numbers_follow_the_roster() -> void:
	assert_eq(MapSymbols.track_number("T1001"), "1001", "a contact's number comes from its track id")
	assert_eq(MapSymbols.track_number("T7"), "0007", "zero-padded")
	assert_eq(MapSymbols.track_number("T12345"), "2345", "the last four digits")
	assert_eq(MapSymbols.track_number("TX"), "", "no digits, no number")
	assert_eq(MapSymbols.own_track_number(1), "0001")
	assert_eq(MapSymbols.own_track_number(0), "", "an unnumbered unit prints nothing")
	var manager := UnitManager.new()
	var first := _unit("BLUE", Vector2.ZERO, "First")
	var hostile := _unit("RED", Vector2.ZERO, "Hostile")
	var second := _unit("BLUE", Vector2.ZERO, "Second")
	for u in [first, hostile, second]:
		manager.add_unit(u)
	var map := TacticalMap.new()
	map.unit_manager = manager
	assert_eq(map.own_track_number(second), 2, "roster order, own units only")
	assert_eq(map.track_number_text(first), "0001")
	first.alive = false
	var third := _unit("BLUE", Vector2.ZERO, "Third")
	manager.add_unit(third)
	assert_eq(map.own_track_number(third), 3, "a unit added later takes the next number")
	assert_eq(map.track_number_text(second), "0002", "a loss renumbers nobody")
	var t := Track.new()
	t.id = "T1042"
	assert_eq(map.track_number_text(t), "1042")
	map.reset_presentation()
	assert_eq(map.own_track_number(third), 3, "a restart numbers the roster afresh, in order")
	map.free()
	manager.free()


func test_velocity_leader_is_six_minutes_of_travel_clamped_to_6_48_px() -> void:
	assert_eq(MapSymbols.leader_px(0.2, 10.0), 0.0, "a stopped platform has no leader")
	assert_near(MapSymbols.leader_px(20.0, 10.0), 20.0, 0.001, "20 kts covers 2 nm in 6 minutes: 20 px at 10 px/nm")
	assert_near(MapSymbols.leader_px(20.0, 1.0), MapSymbols.LEADER_MIN_PX, 0.001, "never shorter than 6 px")
	assert_near(MapSymbols.leader_px(480.0, 10.0), MapSymbols.LEADER_MAX_PX, 0.001, "never longer than 48 px")
	assert_true(MapSymbols.leader_px(30.0, 10.0) > MapSymbols.leader_px(15.0, 10.0), "faster is longer")


func test_graphic_symbols_only_for_a_contact_whose_class_is_known() -> void:
	var map := TacticalMap.new()
	var spec := DataDB.platform("usn_ddg_burke_iii")
	var t := Track.new()
	t.id = "T1001"
	t.classification = Track.Classification.CLASS_KNOWN
	t.known_class = spec.short_name
	t.known_category = spec.category
	assert_eq(map._track_platform(t), "", "NTDS mode draws frames")
	map.set_symbol_mode(TacticalMap.SymbolMode.MEDIUM)
	var id := map._track_platform(t)
	assert_true(id != "" and PlatformArt.plan(id) != null, "a known class finds its plan view")
	assert_eq(DataDB.platform(id).short_name, spec.short_name, "of the reported class")
	t.classification = Track.Classification.SURFACE
	assert_eq(map._track_platform(t), "", "an unclassified contact stays NTDS")
	assert_eq(MapSymbols.platform_for_class("", ""), "", "no class, no art")
	var tex := MapSymbols.graphic_texture(spec.id, 40.0)
	assert_true(tex != null, "the plan view is prepared for the symbol size")
	assert_eq(tex.get_width(), int(roundf(40.0 * PlatformArt.PLAN_MARGIN * 2.0)), "at twice the drawn length, for mipmapped drawing")
	assert_eq(MapSymbols.graphic_texture(spec.id, 40.0), tex, "and cached")
	assert_eq(MapSymbols.graphic_texture("no_such_platform", 40.0), null)
	map.free()


func _resident_plans() -> int:
	var n := 0
	for spec: PlatformSpec in DataDB.all_platforms():
		if ResourceLoader.has_cached(PlatformArt.plan_path(spec.id)):
			n += 1
	return n


func test_graphic_symbols_load_only_the_plan_art_they_draw_and_keep_none_of_it() -> void:
	# Regression: the class lookup loaded every platform's plan view (139 textures, ~185 MB, most of
	# a second) on the first graphic-mode frame, only to learn which platforms had one.
	MapSymbols._class_platforms.clear()
	var loaded := PlatformArt.plans_loaded
	var spec := DataDB.platform("usn_fighter_f35c")
	var id := MapSymbols.platform_for_class(spec.short_name, spec.category)
	assert_true(id != "" and DataDB.platform(id).short_name == spec.short_name, "the reported class still finds its plan view")
	assert_eq(PlatformArt.plans_loaded - loaded, 0, "without loading any plan art")
	assert_eq(_resident_plans(), 0, "none is resident")
	MapSymbols._graphics.erase(MapSymbols._graphic_key(id, 28.0))
	assert_true(MapSymbols.graphic_texture(id, 28.0) != null, "the symbol drawn is made")
	assert_eq(PlatformArt.plans_loaded - loaded, 1, "from its own plan view alone")
	assert_eq(_resident_plans(), 0, "which is let go once the symbol is made: only the small symbol stays")


func test_graphic_symbols_are_made_within_a_per_frame_budget() -> void:
	# Switching a busy plot to a graphic mode spreads the new symbols over frames; a frame that has
	# spent its budget draws the rest as NTDS frames.
	var id := "usn_ddg_burke_iii"
	var key := MapSymbols._graphic_key(id, 28.0)
	MapSymbols._graphics.erase(key)
	MapSymbols._prep_frame = Engine.get_process_frames()
	MapSymbols._prep_usec = MapSymbols.GRAPHIC_PREP_BUDGET_USEC
	assert_eq(MapSymbols.graphic_texture_in_budget(id, 28.0), null, "a frame that has spent its budget makes no more symbols")
	assert_true(not MapSymbols._graphics.has(key), "and loads nothing")
	MapSymbols._prep_frame = -1  # the next frame
	var tex := MapSymbols.graphic_texture_in_budget(id, 28.0)
	assert_true(tex != null, "the next frame makes it")
	MapSymbols._prep_usec = MapSymbols.GRAPHIC_PREP_BUDGET_USEC * 10
	assert_eq(MapSymbols.graphic_texture_in_budget(id, 28.0), tex, "a symbol already made draws whatever the budget")
	MapSymbols._prep_frame = -1
	MapSymbols._prep_usec = 0


func test_graphic_symbol_cache_is_capped() -> void:
	for i in MapSymbols.GRAPHIC_CACHE_MAX + 16:
		MapSymbols.graphic_texture("no_such_platform", 1000.0 + i)
	assert_true(MapSymbols._graphics.size() <= MapSymbols.GRAPHIC_CACHE_MAX, "the prepared symbols never outgrow the cap: %d" % MapSymbols._graphics.size())
	MapSymbols._graphics.clear()


func test_quick_range_circle_arms_on_the_hook_fixes_and_clears() -> void:
	var map := TacticalMap.new()
	map.size = Vector2(800, 600)
	map.ppn = 4.0
	assert_eq(map.toggle_range_circle(), TacticalMap.RangeCircle.OFF, "nothing hooked: no circle")
	var ship := _unit("BLUE", Vector2(10, 0))
	map.select_units([ship])
	map._mouse = map.world_to_screen(Vector2(20, 0))
	assert_eq(map.toggle_range_circle(), TacticalMap.RangeCircle.ARMED, "first B arms it")
	assert_near(map.range_circle_nm(), 10.0, 0.001, "through the cursor")
	map._mouse = map.world_to_screen(Vector2(10, 25))
	assert_near(map.range_circle_nm(), 25.0, 0.001, "and follows it while armed")
	assert_eq(map.toggle_range_circle(), TacticalMap.RangeCircle.FIXED, "second B fixes it")
	map._mouse = map.world_to_screen(Vector2(0, 0))
	assert_near(map.range_circle_nm(), 25.0, 0.001, "a fixed circle ignores the cursor")
	ship.position = Vector2(30, 0)
	assert_eq(map._range_centre(), Vector2(30, 0), "and stays centred on its unit")
	assert_eq(map.toggle_range_circle(), TacticalMap.RangeCircle.OFF, "third B clears it")
	assert_near(map.range_circle_nm(), 0.0)
	assert_eq(ChartReadout.format_range_nmi(7.44), "7.4 nmi")
	assert_eq(ChartReadout.format_range_nmi(23.4), "23 nmi")
	map.free()


func test_identity_filters_hide_contacts_from_the_plot_only() -> void:
	var manager := TrackManager.new()
	var ship := _unit()
	var hostile := Track.new()
	hostile.id = "T1001"
	hostile.identity = "HOSTILE"
	hostile.owner_faction = "BLUE"
	var unknown := Track.new()
	unknown.id = "T1002"
	unknown.owner_faction = "BLUE"
	manager._tracks["BLUE"] = [hostile, unknown]
	var map := TacticalMap.new()
	map.track_manager = manager
	map.selected = [ship]
	assert_eq(map._plotted_tracks().size(), 2)
	map.toggle_layer("unknowns")
	assert_eq(map._plotted_tracks(), [hostile], "the unknown is filtered off the plot")
	assert_eq(map.priority_tracks().size(), 2, "but the track file behind N still holds it")
	map.free()
	manager.free()


func test_lost_own_platforms_stay_on_the_plot_in_grey_and_hostile_losses_do_not() -> void:
	var manager := UnitManager.new()
	var own := _unit("BLUE", Vector2(5, 5))
	var hostile := _unit("RED", Vector2(9, 9))
	manager.add_unit(own)
	manager.add_unit(hostile)
	var map := TacticalMap.new()
	map.unit_manager = manager
	map._record_wrecks()
	own.alive = false
	hostile.alive = false
	map._record_wrecks()
	assert_true(map._wrecks.has(own), "an own loss is remembered where it went down")
	assert_eq(map._wrecks[own]["pos"], Vector2(5, 5))
	assert_true(not map._wrecks.has(hostile), "an opposing loss is never shown from truth")
	map.reset_presentation()
	assert_true(map._wrecks.is_empty(), "a restart clears the wrecks")
	map.free()
	manager.free()


func test_regional_pane_always_contains_the_chart_view() -> void:
	var f := _regional_fixture()
	var map: TacticalMap = f["map"]
	var regional: RegionalMap = f["regional"]
	var pane := Rect2(Vector2.ZERO, regional.size).grow(0.5)
	for ppn in [8.0, 2.0, 0.6]:
		map.ppn = ppn
		for centre in [Vector2.ZERO, Vector2(150, -90)]:
			map.center_nm = centre
			regional._extent = 0.0  # settle at once rather than easing
			assert_true(pane.encloses(regional.view_rect()), "the chart's view fits the regional pane at %.1f px/nm off %s" % [ppn, centre])
	_free(f)

