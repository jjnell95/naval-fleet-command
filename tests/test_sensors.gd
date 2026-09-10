extends TestCase


func _radar(surface_nm: float, antenna_m: float) -> SensorSpec:
	var s := SensorSpec.new()
	s.id = "test_radar"
	s.kind = "radar"
	s.range_surface_nm = surface_nm
	s.antenna_height_m = antenna_m
	return s


func _unit(faction: String, pos: Vector2, radar: SensorSpec = null) -> Unit:
	var spec := PlatformSpec.new()
	spec.short_name = "FFG Test"
	spec.max_speed_kn = 30.0
	spec.cruise_speed_kn = 15.0
	spec.signature_factor = 1.0
	spec.mast_height_m = 25.0
	var u := Unit.new()
	u.spec = spec
	u.faction = faction
	u.callsign = "%s-1" % faction
	u.position = pos
	if radar != null:
		u.sensors.append(radar)
	return u


func test_radar_horizon() -> void:
	assert_near(Detection.radar_horizon_nm(25.0, 25.0), 22.3, 0.05)
	assert_near(Detection.radar_horizon_nm(0.0, 0.0), 0.0)


func test_effective_range_is_horizon_limited() -> void:
	var r := _radar(40.0, 25.0)
	assert_near(Detection.radar_range_vs_surface_nm(r, 1.0, 25.0), 22.3, 0.05, "horizon caps 40 nm radar")
	assert_near(Detection.radar_range_vs_surface_nm(_radar(10.0, 25.0), 1.0, 25.0), 10.0, 1e-4, "short radar not capped")
	assert_near(Detection.radar_range_vs_surface_nm(_radar(10.0, 25.0), 0.5, 25.0), 5.0, 1e-4, "signature scales range")


func test_silent_radar_detects_nothing() -> void:
	var o := _unit("BLUE", Vector2.ZERO, _radar(40.0, 25.0))
	var t := _unit("RED", Vector2(10.0, 0.0))
	assert_true(Detection.radar_quality(o, t) > 0.0, "detected when radiating")
	o.radar_on = false
	assert_near(Detection.radar_quality(o, t), 0.0, 1e-6, "silent radar")
	o.radar_on = true
	t.position = Vector2(30.0, 0.0)
	assert_near(Detection.radar_quality(o, t), 0.0, 1e-6, "beyond horizon")


func test_track_classification_progression() -> void:
	var tm := TrackManager.new()
	var o := _unit("BLUE", Vector2.ZERO, _radar(40.0, 25.0))
	var t := _unit("RED", Vector2(10.0, 0.0))
	var now := 0.0
	for i in 20:
		now += 1.0
		tm.observe("BLUE", t, t.position, 0.5, 1.0, now, 1.0, 10.0)
		tm.tick(now, 1.0)
	var tracks: Array = tm.get_tracks("BLUE")
	assert_eq(tracks.size(), 1, "one track per target")
	var tr: Track = tracks[0]
	assert_eq(tr.classification, Track.Classification.UNKNOWN, "unknown early")
	assert_eq(tr.identity, "UNKNOWN")
	for i in 200:
		now += 1.0
		tm.observe("BLUE", t, t.position, 0.5, 1.0, now, 1.0, 10.0)
		tm.tick(now, 1.0)
	assert_eq(tr.classification, Track.Classification.CLASS_KNOWN, "class known after ~180 s obs")
	assert_eq(tr.identity, "HOSTILE")
	assert_eq(tr.known_class, "FFG Test")
	assert_eq(tm.find_track("BLUE", t), tr, "association stable")
	assert_eq(tm.get_tracks("RED").size(), 0, "no cross-faction leakage")
	tm.free()


func test_track_goes_stale_and_dead_reckons() -> void:
	var tm := TrackManager.new()
	var t := _unit("RED", Vector2(0.0, 0.0))
	var now := 0.0
	# Target moves north at 10 kn; observe without noise for 60 s.
	for i in 60:
		now += 1.0
		t.position = Vector2(0.0, 10.0 / 3600.0 * now)
		tm.observe("BLUE", t, t.position, 0.5, 1.0, now, 1.0, 5.0)
		tm.tick(now, 1.0)
	var tr: Track = tm.get_tracks("BLUE")[0]
	assert_true(tr.has_kinematics, "kinematics estimated after interval")
	assert_near(tr.speed_kn, 10.0, 1.0, "speed estimate")
	assert_near(tr.course_deg, 0.0, 2.0, "course estimate")
	assert_eq(tr.status, Track.Status.ACTIVE)
	var last_pos := tr.position
	var err := tr.position_error_nm
	# No observations for 120 s.
	for i in 120:
		now += 1.0
		tm.tick(now, 1.0)
	assert_eq(tr.status, Track.Status.STALE, "stale after 60 s unobserved")
	assert_true(tr.position.y > last_pos.y + 0.2, "dead-reckoned north")
	assert_true(tr.position_error_nm > err, "uncertainty grows")
	for i in 1800:
		now += 1.0
		tm.tick(now, 1.0)
	assert_eq(tm.get_tracks("BLUE").size(), 0, "dropped after LOST_AFTER_S")
	tm.free()


func test_kinematics_with_noise() -> void:
	var tm := TrackManager.new()
	var t := _unit("RED", Vector2.ZERO)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var now := 0.0
	for i in 300:
		now += 1.0
		t.position = Vector2.ZERO + Geo.heading_to_vector(245.0) * (12.0 / 3600.0 * now)
		var obs := t.position + Vector2(rng.randfn(0.0, 0.12), rng.randfn(0.0, 0.12))
		tm.observe("BLUE", t, obs, 0.5, 1.0, now, 1.0, 20.0)
		tm.tick(now, 1.0)
	var tr: Track = tm.get_tracks("BLUE")[0]
	assert_true(tr.has_kinematics)
	assert_near(tr.speed_kn, 12.0, 2.0, "speed within 2 kn despite 0.12 nm plot noise")
	assert_near(absf(Geo.heading_delta(tr.course_deg, 245.0)), 0.0, 10.0, "course within 10 deg")
	tm.free()
