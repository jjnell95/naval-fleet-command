extends TestCase
## The sea floor and the water column: a real chart under every mission, a layer a boat can hide
## beneath, a shelf that muffles sound, convergence zones in deep water and a floor a submarine
## cannot go through.

const SCENARIO_DIR := "res://data/scenarios/"


func _boat_spec(signature := 0.05, max_depth := 300.0) -> PlatformSpec:
	var p := PlatformSpec.new()
	p.short_name = "SSN Test"
	p.domain = "subsurface"
	p.max_speed_kn = 28.0
	p.cruise_speed_kn = 8.0
	p.acoustic_signature = signature
	p.max_depth_m = max_depth
	p.patrol_depth_m = 120.0
	p.depth_rate_m_s = 2.0
	p.turn_rate_deg_s = 3.0
	p.health = 60.0
	return p


func _ship_spec(signature := 1.0) -> PlatformSpec:
	var p := PlatformSpec.new()
	p.short_name = "FFG Test"
	p.domain = "surface"
	p.max_speed_kn = 30.0
	p.cruise_speed_kn = 16.0
	p.acoustic_signature = signature
	p.signature_factor = 1.0
	p.mast_height_m = 30.0
	p.health = 100.0
	return p


func _sonar(passive: float, array_depth := 0.0, cz := false) -> SensorSpec:
	var s := SensorSpec.new()
	s.id = "test_sonar"
	s.kind = "sonar"
	s.passive_sensitivity_nm = passive
	s.active_range_nm = 8.0
	s.self_noise_tolerance = 0.7
	s.bearing_accuracy_deg = 1.0
	s.classify_rate = 1.0
	s.array_depth_m = array_depth
	s.cz_capable = cz
	return s


func _unit(spec: PlatformSpec, faction: String, pos: Vector2, speed := 0.0, depth := 0.0) -> Unit:
	var u := Unit.new()
	u.spec = spec
	u.faction = faction
	u.callsign = "%s-%d" % [faction, randi() % 1000]
	u.position = pos
	u.speed_kn = speed
	u.ordered_speed_kn = speed
	u.depth_m = depth
	u.ordered_depth_m = depth
	u.health = spec.health
	return u


func _water(bottom_m: float, layer_m := 0.0, strength := 1.0, cz := 0.0) -> void:
	var env := {"bottom_m": bottom_m, "layer_depth_m": layer_m, "layer_strength": strength, "cz_range_nm": cz}
	Detection.set_environment(env)
	Bathymetry.load_for({"environment": env})


func _reset() -> void:
	Detection.set_environment({})
	Bathymetry.clear()


# --- The chart --------------------------------------------------------------------------

func test_runtime_constants_match_the_built_rasters() -> void:
	for name: String in Bathymetry.REGIONS:
		var r: Dictionary = Bathymetry.REGIONS[name]
		var meta_path := "res://data/bathymetry/%s_depth.json" % name
		assert_true(FileAccess.file_exists(meta_path), "%s has raster metadata" % name)
		if not FileAccess.file_exists(meta_path):
			continue
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		assert_eq(str(meta.get("region", name)), name, "%s metadata names its region" % name)
		assert_near(float(meta["bounds_lon_lat"][0]), float(r["lon_min"]), 1e-6, "%s west edge" % name)
		assert_near(float(meta["bounds_lon_lat"][1]), float(r["lat_min"]), 1e-6, "%s south edge" % name)
		assert_near(float(meta["bounds_lon_lat"][2]), float(r["lon_max"]), 1e-6, "%s east edge" % name)
		assert_near(float(meta["bounds_lon_lat"][3]), float(r["lat_max"]), 1e-6, "%s north edge" % name)
		assert_near(float(meta["cell_deg"][0]), float(r["cell_lon"]), 1e-9, "%s longitude cell" % name)
		assert_near(float(meta["cell_deg"][1]), float(r["cell_lat"]), 1e-9, "%s latitude cell" % name)
		assert_near(float(meta["depth_scale_m"]), Bathymetry.DEPTH_SCALE_M, 1e-6, "%s encoding scale" % name)
		var img := Bathymetry.source_image(name)
		assert_true(img != null, "%s raster loads without a renderer" % name)
		if img != null:
			assert_eq(img.get_width(), int(meta["size_px"][0]), "%s raster width" % name)
			assert_eq(img.get_height(), int(meta["size_px"][1]), "%s raster height" % name)
		assert_true(ResourceLoader.exists(Bathymetry.chart_path(name)), "%s has a chart texture" % name)
		assert_true(ResourceLoader.exists(Bathymetry.relief_path(name)), "%s has a relief texture" % name)
		# The chart's land relief shares the sea floor's grid, so one transform samples both.
		var land_meta_path := "res://data/bathymetry/%s_land.json" % name
		assert_true(FileAccess.file_exists(land_meta_path), "%s has land relief metadata" % name)
		if FileAccess.file_exists(land_meta_path):
			var land: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(land_meta_path))
			assert_eq(land["bounds_lon_lat"], meta["bounds_lon_lat"], "%s land relief covers the sea floor's bounds" % name)
			assert_eq(land["size_px"], meta["size_px"], "%s land relief is on the sea floor's grid" % name)
		assert_true(ResourceLoader.exists("res://data/bathymetry/%s_land.png" % name), "%s has a land height texture" % name)
		assert_true(ResourceLoader.exists("res://data/bathymetry/%s_land_relief.png" % name), "%s has a land relief texture" % name)


func test_anchor_selects_the_region_with_the_most_margin() -> void:
	assert_eq(Bathymetry.region_for(68.0, 8.0), "north_atlantic")
	assert_eq(Bathymetry.region_for(56.8, 18.5), "north_atlantic", "the Baltic is on the Atlantic raster")
	assert_eq(Bathymetry.region_for(24.0, 122.0), "west_pacific")
	assert_eq(Bathymetry.region_for(40.0, 134.0), "west_pacific", "the Sea of Japan")
	assert_eq(Bathymetry.region_for(26.5, 56.5), "arabian_sea")
	assert_eq(Bathymetry.region_for(14.5, 42.8), "arabian_sea", "the Red Sea")
	assert_eq(Bathymetry.region_for(34.5, 33.0), "mediterranean")
	assert_eq(Bathymetry.region_for(-50.0, -100.0), "", "the Southern Ocean is uncharted")
	assert_eq(Bathymetry.region_for(31.3, 32.3), "mediterranean", "Port Said sits deeper inside the Mediterranean sheet than the Red Sea one")


func test_regional_rasters_know_shelf_from_trench() -> void:
	# A handful of features anyone can check against an atlas. Interpolated between Natural
	# Earth contours, so the test asks for the right band, not a sounding.
	var probes := [
		["west_pacific", 11.37, 142.59, 5000.0, INF, "Challenger Deep"],
		["west_pacific", 24.8, 119.7, 0.5, 200.0, "Taiwan Strait shelf"],
		["west_pacific", 42.0, 136.0, 3000.0, INF, "Japan Basin"],
		["west_pacific", 39.5, 134.5, 200.0, 2000.0, "Yamato Rise"],
		["west_pacific", 20.5, 121.0, 1000.0, INF, "Bashi Channel"],
		["arabian_sea", 26.6, 52.0, 0.5, 200.0, "Persian Gulf"],
		["arabian_sea", 24.0, 60.0, 2000.0, INF, "Gulf of Oman"],
		["arabian_sea", 14.0, 42.0, 0.5, 2000.0, "southern Red Sea"],
		["mediterranean", 36.5, 19.0, 3000.0, INF, "Ionian Basin"],
		["mediterranean", 33.5, 33.5, 1000.0, INF, "Levantine Basin"],
		["mediterranean", 45.0, 13.0, 0.5, 200.0, "northern Adriatic shelf"],
	]
	for probe in probes:
		var name: String = probe[0]
		Bathymetry.set_anchor(float(probe[1]), float(probe[2]))
		assert_eq(Bathymetry.region, name, "%s anchors on %s" % [probe[5], name])
		if not Bathymetry.active:
			continue
		var d := Bathymetry.depth_at(Vector2.ZERO)
		assert_true(d >= float(probe[3]) and d <= float(probe[4]), "%s: %.0f m in [%.0f, %.0f]" % [probe[5], d, probe[3], probe[4]])
	_reset()


func _world(lat: float, lon: float, lat0: float, lon0: float) -> Vector2:
	return Vector2((lon - lon0) * 60.0 * cos(deg_to_rad(lat0)), (lat - lat0) * 60.0)


func test_known_waters_have_the_right_kind_of_floor() -> void:
	Bathymetry.set_anchor(68.0, 8.0)
	assert_true(not Bathymetry.is_empty(), "anchored chart is live")
	assert_true(Bathymetry.depth_at(_world(70.0, 5.0, 68.0, 8.0)) > 2500.0, "Lofoten Basin is abyssal")
	assert_true(Bathymetry.depth_at(_world(66.0, 0.0, 68.0, 8.0)) > 2500.0, "so is the Norwegian Basin")
	var barents := Bathymetry.depth_at(_world(73.0, 35.0, 68.0, 8.0))
	assert_true(barents > 100.0 and barents < 500.0, "the Barents is a shelf sea: %.0f m" % barents)
	assert_near(Bathymetry.depth_at(_world(67.5, 20.0, 68.0, 8.0)), 0.0, 1.0, "inland Lapland is dry")
	Bathymetry.set_anchor(56.8, 18.5)
	var gotland := Bathymetry.depth_at(_world(57.3, 20.1, 56.8, 18.5))
	assert_true(gotland > 150.0 and gotland < 350.0, "the Gotland Deep: %.0f m" % gotland)
	_reset()


func test_no_anchor_means_an_unknown_floor_and_no_effect() -> void:
	_reset()
	Bathymetry.load_for({"map": {"center_nm": [0, 0]}})
	assert_true(Bathymetry.is_empty(), "nothing to read")
	assert_eq(Bathymetry.depth_at(Vector2(10, 10)), Bathymetry.UNKNOWN, "unknown, not zero")
	var boat := _unit(_boat_spec(), "RED", Vector2.ZERO, 5.0, 200.0)
	assert_near(Acoustics.max_operating_depth_m(boat), 300.0, 1e-6, "hull limit only")
	Bathymetry.set_anchor(-50.0, -100.0)
	assert_true(Bathymetry.is_empty(), "an anchor off every raster is no chart either")


func test_every_shipped_mission_has_a_floor_and_its_boats_start_in_water() -> void:
	for f in DirAccess.get_files_at(SCENARIO_DIR):
		if not f.ends_with(".json"):
			continue
		var sc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SCENARIO_DIR + f))
		Bathymetry.load_for(sc)
		assert_true(not Bathymetry.is_empty(), "%s is charted" % f)
		for ud in sc["units"]:
			if not str(ud["platform"]).contains("_ss"):
				continue
			var p := Vector2(ud["position_nm"][0], ud["position_nm"][1])
			var floor_m := Bathymetry.depth_at(p)
			assert_true(floor_m > float(ud.get("depth_m", 0.0)) + 10.0, "%s: %s starts above the floor (%.0f m)" % [f, ud["callsign"], floor_m])
	_reset()


# --- The floor under a boat ------------------------------------------------------------

func test_a_boat_cannot_go_deeper_than_the_water() -> void:
	_water(80.0)
	var boat := _unit(_boat_spec(), "RED", Vector2.ZERO, 5.0, 20.0)
	boat.ordered_depth_m = 250.0
	for i in 400:
		Movement.step(boat, 0.25)
	assert_near(boat.depth_m, 80.0 - Acoustics.KEEL_CLEARANCE_M, 0.5, "held off the bottom")
	_water(30.0)
	boat.bottom_generation = -1
	for i in 40:
		Movement.step(boat, 0.25)
	assert_true(boat.depth_m <= Unit.PERISCOPE_DEPTH_M, "no room to submerge at all")
	assert_true(not boat.submerged(), "so the mast is out of the water")
	_reset()


# --- The layer -------------------------------------------------------------------------

func test_a_hull_set_hears_a_boat_below_the_layer_badly_and_a_towed_body_does_not() -> void:
	_water(3000.0, 80.0, 1.0)
	var hull_ship := _unit(_ship_spec(), "BLUE", Vector2.ZERO, 5.0)
	hull_ship.sensors.append(_sonar(30.0))
	var vds_ship := _unit(_ship_spec(), "BLUE", Vector2(1, 0), 5.0)
	vds_ship.sensors.append(_sonar(30.0, 300.0))
	var deep := _unit(_boat_spec(0.3), "RED", Vector2(0, 8), 8.0, 150.0)
	var hull_range := Detection.passive_sonar_range_nm(hull_ship, hull_ship.sensors[0], deep)
	var vds_range := Detection.passive_sonar_range_nm(vds_ship, vds_ship.sensors[0], deep)
	assert_near(hull_range / vds_range, 1.0 - Acoustics.CROSS_LAYER_LOSS, 0.01, "cross-layer loss")
	assert_true(Acoustics.sensor_depth_m(vds_ship, vds_ship.sensors[0]) > 80.0, "the body goes through the layer")
	deep.depth_m = 40.0
	var shallow_range := Detection.passive_sonar_range_nm(hull_ship, hull_ship.sensors[0], deep)
	assert_true(shallow_range > hull_range * 1.5, "come above the layer and the hull set has you")
	_reset()


func test_no_layer_means_no_hiding() -> void:
	_water(3000.0, 0.0)
	var ship := _unit(_ship_spec(), "BLUE", Vector2.ZERO, 5.0)
	ship.sensors.append(_sonar(30.0))
	var deep := _unit(_boat_spec(0.3), "RED", Vector2(0, 8), 8.0, 250.0)
	var shallow := _unit(_boat_spec(0.3), "RED", Vector2(0, 8), 8.0, 40.0)
	assert_near(Detection.passive_sonar_range_nm(ship, ship.sensors[0], deep), Detection.passive_sonar_range_nm(ship, ship.sensors[0], shallow), 1e-4, "depth alone changes nothing")
	_reset()


func test_a_layer_below_the_floor_is_no_layer() -> void:
	_water(90.0, 120.0)
	assert_true(not Acoustics.layer_present_at(90.0), "the shelf is mixed to the bottom")
	var boat := _unit(_boat_spec(), "RED", Vector2.ZERO)
	assert_eq(Acoustics.below_layer_depth_m(boat), -1.0, "nowhere to hide")
	_water(3000.0, 120.0)
	boat.bottom_generation = -1
	assert_near(Acoustics.below_layer_depth_m(boat), 120.0 + Acoustics.BELOW_LAYER_MARGIN_M, 1e-4, "comfortably under it")
	_reset()


func test_buoys_are_set_under_the_layer_when_the_water_allows() -> void:
	_water(3000.0, 80.0)
	assert_eq(Acoustics.buoy_depth_m(3000.0), 120.0, "the shallowest setting that clears the layer")
	assert_eq(Acoustics.buoy_depth_m(60.0), 27.0, "shallow water gets the shallow setting")
	_water(3000.0, 0.0)
	assert_eq(Acoustics.buoy_depth_m(3000.0), 300.0, "no layer: as deep as it goes")
	_reset()


# --- Shallow water ---------------------------------------------------------------------

func test_the_shelf_muffles_sound() -> void:
	var ship := _unit(_ship_spec(), "BLUE", Vector2.ZERO, 5.0)
	ship.sensors.append(_sonar(30.0))
	var boat := _unit(_boat_spec(0.3), "RED", Vector2(0, 8), 8.0, 30.0)
	_water(3000.0)
	var deep_range := Detection.passive_sonar_range_nm(ship, ship.sensors[0], boat)
	_water(45.0)
	ship.bottom_generation = -1
	boat.bottom_generation = -1
	var shelf_range := Detection.passive_sonar_range_nm(ship, ship.sensors[0], boat)
	assert_true(shelf_range < deep_range * 0.8, "shallow water is harder")
	assert_true(shelf_range > deep_range * 0.5, "but not deaf")
	_reset()


# --- Convergence zones -----------------------------------------------------------------

func _harness(units: Array) -> Array:
	var um := UnitManager.new()
	for u in units:
		um.add_unit(u)
	var tm := TrackManager.new()
	var sm := SensorManager.new()
	sm.unit_manager = um
	sm.track_manager = tm
	sm.rng.seed = 11
	return [um, tm, sm]


func _free(h: Array) -> void:
	h[2].free()
	h[1].free()
	h[0].free()


func test_a_loud_ship_is_heard_in_the_convergence_zone_and_not_short_of_it() -> void:
	_water(3500.0, 0.0, 0.0, 30.0)
	var listener := _unit(_ship_spec(), "BLUE", Vector2.ZERO, 5.0)
	listener.sensors.append(_sonar(13.0, 0.0, true))
	var loud := _unit(_ship_spec(1.0), "RED", Vector2(0, 30), 16.0)
	var h := _harness([listener, loud])
	for i in 5:
		h[2].run_cycle(float(i + 1))
	var tracks: Array = h[1].get_tracks("BLUE")
	assert_eq(tracks.size(), 1, "the zone brings it in")
	if not tracks.is_empty():
		var t: Track = tracks[0]
		assert_eq(t.source, "sonar_cz", "labelled as a zone contact")
		assert_true(t.bearing_only, "still a bearing to work")
		assert_true(t.error_major_nm <= 30.0 * Acoustics.CZ_HALF_WIDTH_FRACTION + 0.01, "but the range is bracketed")
		assert_near(t.position.distance_to(Vector2.ZERO), 30.0, 4.0, "around the zone")
	_free(h)
	var gap := _unit(_ship_spec(1.0), "RED", Vector2(0, 25), 16.0)
	var listener2 := _unit(_ship_spec(), "BLUE", Vector2.ZERO, 5.0)
	listener2.sensors.append(_sonar(13.0, 0.0, true))
	h = _harness([listener2, gap])
	for i in 5:
		h[2].run_cycle(float(i + 1))
	assert_true(h[1].get_tracks("BLUE").is_empty(), "the shadow zone between is silent")
	_free(h)
	_reset()


func test_convergence_zones_need_deep_water_a_big_array_and_a_loud_source() -> void:
	var listener := _unit(_ship_spec(), "BLUE", Vector2.ZERO, 5.0)
	var small := _sonar(13.0, 0.0, false)
	var big := _sonar(13.0, 0.0, true)
	var loud := _unit(_ship_spec(1.0), "RED", Vector2(0, 30), 28.0)
	var quiet := _unit(_boat_spec(0.03), "RED", Vector2(0, 30), 4.0, 150.0)
	_water(3500.0, 0.0, 0.0, 30.0)
	var direct_loud := Detection.passive_sonar_range_nm(listener, big, loud, false)
	var direct_quiet := Detection.passive_sonar_range_nm(listener, big, quiet, false)
	assert_true(not Acoustics.cz_zone_for(big, 30.0, direct_loud).is_empty(), "loud source, big array")
	assert_true(Acoustics.cz_zone_for(small, 30.0, direct_loud).is_empty(), "a small set cannot use it")
	assert_true(Acoustics.cz_zone_for(big, 30.0, direct_quiet).is_empty(), "a quiet boat is lost in it")
	assert_true(Acoustics.deep_water_path(Vector2.ZERO, Vector2(0, 30)), "abyssal water carries it")
	_water(1200.0, 0.0, 0.0, 30.0)
	assert_true(not Acoustics.deep_water_path(Vector2.ZERO, Vector2(0, 30)), "the ray meets the floor first")
	_water(3500.0, 0.0, 0.0, 0.0)
	assert_true(Acoustics.zones().is_empty(), "an environment without zones has none")
	_reset()


# --- A fused track keeps its best measurement ------------------------------------------

func test_a_bearing_does_not_blur_a_firm_plot() -> void:
	var tm := TrackManager.new()
	var target := _unit(_ship_spec(), "RED", Vector2(0, 20), 15.0)
	var radar_ship := _unit(_ship_spec(), "BLUE", Vector2.ZERO)
	var sonar_ship := _unit(_ship_spec(), "BLUE", Vector2(5, 0))
	var firm := SensorContact.make(target, Vector2(0, 20), 0.3, 0.8, 1.0, 20.0, "radar", radar_ship)
	tm.observe_contact("BLUE", firm, 10.0, 1.0)
	var bearing := SensorContact.new()
	bearing.target = target
	bearing.observer = sonar_ship
	bearing.position = Vector2(3, 28)
	bearing.error_major_nm = 6.0
	bearing.error_minor_nm = 0.5
	bearing.bearing_only = true
	bearing.source = "sonar_cz"
	tm.observe_contact("BLUE", bearing, 10.0, 1.0)
	var t: Track = tm.get_tracks("BLUE")[0]
	assert_eq(t.source, "radar", "the radar plot stands")
	assert_true(not t.bearing_only, "still a firm track")
	assert_near(t.position.distance_to(Vector2(0, 20)), 0.0, 1e-4, "not dragged toward the guess")
	assert_true(t.contributors.has(sonar_ship), "the listener still counts as holding it")
	tm.free()
