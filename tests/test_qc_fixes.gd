extends TestCase

class AltitudeRound extends Weapon:
	var measured_altitude := 0.0
	func flight_altitude_m() -> float:
		return measured_altitude

func _scenario() -> Dictionary:
	return {"name": "QC mission", "player_faction": "BLUE", "map": {"center_nm": [0, 0], "extent_nm": 80}, "units": [{"platform": "cw90_perry", "callsign": "Perry", "position_nm": [0, 0], "faction": "BLUE", "air_wing": []}], "objectives": {"victory": [{"id": "wait", "type": "time_elapsed", "seconds": 100}]}}

func _ship(id := "cw90_perry", side := "BLUE") -> Unit:
	var u := Unit.new()
	u.spec = DataDB.platform(id)
	u.faction = side
	u.health = u.spec.health
	for sid in u.spec.sensor_ids:
		u.sensors.append(DataDB.sensor(sid))
	for wid in u.spec.weapon_loadout:
		u.weapons.append(DataDB.weapon(wid))
		u.magazines[wid] = u.spec.weapon_loadout[wid]
	return u

func _track(domain := "air", position := Vector2(0, 10)) -> Track:
	var t := Track.new()
	t.owner_faction = "BLUE"
	t.identity = "HOSTILE"
	t.domain = domain
	t.position = position
	t.altitude_m = 1000
	return t

func test_import_rejects_malformed_nested_labels_before_loading() -> void:
	for labels in ["bad", ["bad"], [{"text": {}, "position_nm": [0, 0]}], [{"text": "Bad", "position_nm": "bad"}], [{"text": "Bad", "position_nm": [INF, 0]}]]:
		var sc := _scenario()
		sc.map.labels = labels
		assert_true(ScenarioWorkshop.validate(sc) != "", "malformed label rejected")
	var valid := _scenario()
	valid.map.labels = [{"text": "Area", "position_nm": [0, 5]}]
	assert_eq(ScenarioWorkshop.validate(valid), "")

func test_import_rejects_objective_scalar_types_and_map_extent_fields() -> void:
	for key: String in ["id", "type", "text", "faction", "facility"]:
		var sc := _scenario()
		sc.objectives.victory[0][key] = {}
		assert_true(ScenarioWorkshop.validate(sc) != "", key + " rejected")
	for pair in [["phase_only", "yes"], ["center_nm", [0, NAN]], ["seconds", INF]]:
		var sc := _scenario()
		sc.objectives.victory[0][pair[0]] = pair[1]
		assert_true(ScenarioWorkshop.validate(sc) != "")
	for pair in [["anchor_lat", {}], ["charted_nm", [0, 0, 1]], ["open_water", "yes"], ["chart_region", []], ["focus_center_nm", "bad"]]:
		var sc := _scenario()
		sc.map[pair[0]] = pair[1]
		assert_true(ScenarioWorkshop.validate(sc) != "")

func test_open_water_recipes_disable_regional_land_and_legacy_saves_are_repaired() -> void:
	var sc := ScenarioWorkshop.generate({"region": 1, "seed": 2901, "coastlines": false})
	Terrain.load_from(sc)
	Bathymetry.load_for(sc)
	assert_true(Terrain.is_empty())
	assert_true(not Bathymetry.active, "regional raster disabled in playable chart")
	assert_near(Bathymetry.uniform_m, 2000)
	sc.map.erase("open_water")
	Bathymetry.load_for(sc)
	assert_true(not Bathymetry.active, "pre-fix saved recipe gets the same ocean")
	sc.recipe.coastlines = true
	Bathymetry.load_for(sc)
	assert_true(Bathymetry.active, "charted exercises retain raster geography")
	Bathymetry.clear()
	Terrain.clear()

func test_shared_rail_serializes_manual_and_automatic_rounds_and_refunds_queue() -> void:
	Terrain.clear()
	var ship := _ship()
	var wm := WeaponManager.new()
	var sam := DataDB.weapon("cw90_sm1mr")
	var asm := DataDB.weapon("cw90_harpoon")
	var air := _track()
	var surface := _track("surface")
	assert_eq(WeaponManager.launcher_key(ship, sam), WeaponManager.launcher_key(ship, asm))
	assert_true(wm.launch(ship, sam, air, 1, 0))
	assert_true(wm.launch(ship, asm, surface, 1, 0), "second family queues on rail")
	assert_eq(wm.in_flight.size(), 1, "one physical rail cannot launch both together")
	var threat := Weapon.new()
	threat.spec = DataDB.weapon("kalibr_asm")
	threat.position = Vector2(0, 5)
	threat.faction = "RED"
	assert_eq(wm.launch_interceptor(ship, sam, threat, 1, 0), 0, "automatic shot shares occupied rail")
	wm.tick(0, 7.9)
	assert_eq(wm.in_flight.size(), 1)
	wm.tick(0, 8)
	assert_eq(wm.in_flight.size(), 2)
	assert_true(wm.launch(ship, asm, surface, 1, 8))
	var left := ship.magazine_count(asm.id)
	assert_eq(wm.cancel_salvo(ship, surface), 1)
	assert_eq(ship.magazine_count(asm.id), left + 1)
	wm.free()

func test_manual_guidance_uses_held_height_not_hidden_truth_and_checks_terrain() -> void:
	Terrain.clear()
	var ship := _ship("usn_cg_ticonderoga")
	var wm := WeaponManager.new()
	var spec := DataDB.weapon("sm2_family")
	var t := _track("air", Vector2(40, 0))
	t.altitude_m = 20
	var hidden := _ship("usn_fighter_fa18e", "RED")
	hidden.altitude_m = 10000
	t.truth = hidden
	assert_true(not wm.engagement_check(ship, spec, t, 0).ok, "remote cue cannot illuminate low target")
	t.altitude_m = 1000
	assert_true(wm.engagement_check(ship, spec, t, 0).ok, "held high altitude opens horizon")
	assert_true(wm.launch(ship, spec, t, 1, 0))
	t.altitude_m = 20
	wm.tick(0.1, 0.1)
	assert_eq(wm.in_flight.size(), 0, "guidance geometry loss ends round")
	t.position = Vector2(10, 0)
	Terrain.load_from({"terrain": {"land": [{"name": "Ridge", "elevation_m": 2000, "points_nm": [[4, -2], [6, -2], [6, 2], [4, 2]]}]}})
	assert_true(not wm.engagement_check(ship, spec, t, 1).ok, "local terrain illumination gate")
	Terrain.clear()
	wm.free()

func test_radar_height_is_observed_into_local_and_network_tracks() -> void:
	var observer := _ship("usn_cg_ticonderoga")
	var target := _ship("usn_fighter_fa18e", "RED")
	target.flight_state = Unit.FlightState.AIRBORNE
	target.altitude_m = 1200
	var tm := TrackManager.new()
	tm.observe_contact("BLUE", SensorContact.make(target, Vector2(20, 0), 1, 1, 1, 20, "radar", observer), 1, 1)
	assert_near((tm.tracks_for(observer)[0] as Track).altitude_m, 1200)
	target.altitude_m = 25
	assert_near((tm.tracks_for(observer)[0] as Track).altitude_m, 1200, 0.01, "unobserved truth change does not update height")
	tm.free()

func test_cycle_channel_cache_matches_allocations_and_updates_after_each_shot() -> void:
	Terrain.clear()
	var ship := _ship("usn_cg_ticonderoga")
	ship.spec = ship.spec.duplicate()
	ship.spec.fire_control_channels = 1
	var wm := WeaponManager.new()
	var a := Weapon.new()
	a.spec = DataDB.weapon("kalibr_asm")
	a.position = Vector2(0, 5)
	a.faction = "RED"
	var b := Weapon.new()
	b.spec = a.spec
	b.position = Vector2(5, 0)
	b.faction = "RED"
	wm.begin_channel_batch()
	assert_eq(wm.launch_interceptor(ship, DataDB.weapon("sm2_family"), a, 1, 0), 1)
	assert_true(not wm.channel_available(ship, b), "first shot reserves cycle channel")
	assert_eq(wm.channel_loads().get(ship), 1)
	a.phase = Weapon.Phase.DEAD
	assert_true(wm.channel_available(ship, b), "defeated threat releases channel")
	wm.end_channel_batch()
	assert_eq(wm.channel_targets(ship).size(), 0)
	wm.free()

func test_sensor_range_cache_keeps_specs_altitudes_and_observers_separate() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var observer := _ship("usn_cg_ticonderoga")
	observer.spec = observer.spec.duplicate()
	observer.spec.has_datalink = false
	um.add_unit(observer)
	var remote := _ship("usn_cg_ticonderoga")
	remote.spec = observer.spec
	remote.position = Vector2(200, 0)
	um.add_unit(remote)
	var wm := WeaponManager.new()
	var tm := ThreatManager.new()
	var sm := SensorManager.new()
	sm.unit_manager = um
	sm.weapon_manager = wm
	sm.threat_manager = tm
	var spec := DataDB.weapon("kalibr_asm").duplicate() as WeaponSpec
	spec.signature_factor = 1
	for i in 3:
		var w := AltitudeRound.new()
		w.id = i + 1
		w.spec = spec if i < 2 else spec.duplicate()
		w.measured_altitude = 10 if i == 0 else 1000
		w.faction = "RED"
		w.position = Vector2(40, 0)
		wm.in_flight.append(w)
	sm._detect_weapons(0)
	assert_true(not tm.visible_to(observer, wm.in_flight[0]), "low round remains below horizon")
	assert_true(tm.visible_to(observer, wm.in_flight[1]), "high round visible")
	assert_true(tm.visible_to(observer, wm.in_flight[2]), "different resource retains its reach")
	assert_true(not tm.visible_to(remote, wm.in_flight[1]), "private observation cannot cue remote defence")
	sm.free()
	wm.free()
	tm.free()
	um.free()

func test_track_index_expires_associations_and_reacquires_without_leaking_old_tracks() -> void:
	var manager := TrackManager.new()
	var target := _ship("cw90_perry", "RED")
	manager.observe("BLUE", target, Vector2(10, 0), 1, 1, 0, 1, 10)
	var original := manager.find_track("BLUE", target)
	assert_true(original != null)
	manager.tick(Track.LOST_AFTER_S + 1, 1)
	assert_true(manager.find_track("BLUE", target) == null)
	manager.observe("BLUE", target, Vector2(20, 0), 1, 1, 2000, 1, 20)
	assert_true(manager.find_track("BLUE", target) != original, "expired geometry is not revived")
	manager.clear()
	assert_true(manager._by_target.is_empty())
	manager.free()

func test_jammer_batch_preserves_direction_and_clears_between_cycles() -> void:
	var observer := _ship("usn_cg_ticonderoga")
	var jammer := _ship("usn_ea_ea18g", "RED")
	jammer.flight_state = Unit.FlightState.AIRBORNE
	jammer.position = Vector2(10, 0)
	Detection.refresh_jammers([jammer])
	var clean := Detection.jam_penalty(observer, Vector2(0, 20))
	var jammed := Detection.jam_penalty(observer, Vector2(20, 0))
	assert_near(clean, 1)
	assert_true(jammed < 1)
	Detection.begin_jamming_batch()
	assert_near(Detection.jam_penalty(observer, Vector2(20, 0)), jammed, 0.00001)
	assert_near(Detection.jam_penalty(observer, Vector2(0, 20)), clean)
	Detection.end_jamming_batch()
	jammer.position = Vector2(0, 10)
	Detection.begin_jamming_batch()
	assert_near(Detection.jam_penalty(observer, Vector2(20, 0)), 1)
	assert_true(Detection.jam_penalty(observer, Vector2(0, 20)) < 1)
	Detection.end_jamming_batch()
	Detection.refresh_jammers([])

func test_ai_cycle_commit_counts_update_when_launches_fire_and_queued_rounds_leave() -> void:
	Terrain.clear()
	var brain := AIController.new()
	var wm := WeaponManager.new()
	brain.weapon_manager = wm
	brain.faction = "BLUE"
	brain._in_decision_cycle = true
	wm.round_fired.connect(brain._on_cycle_round_fired)
	var ship := _ship("usn_cg_ticonderoga")
	var t := _track()
	assert_true(wm.launch(ship, DataDB.weapon("sm2_family"), t, 2, 0))
	assert_eq(brain._rounds_already_committed(t), 1)
	wm.tick(0, 8)
	assert_eq(brain._rounds_already_committed(t), 2, "next decision sees the new commitment")
	wm.round_fired.disconnect(brain._on_cycle_round_fired)
	brain._in_decision_cycle = false
	assert_eq(brain._rounds_already_committed(t), 2)
	brain.free()
	wm.free()
