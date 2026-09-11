extends TestCase

func _unit(id: String, side := "BLUE") -> Unit:
	var u := Unit.new()
	u.spec = DataDB.platform(id)
	u.faction = side
	u.health = u.spec.health
	for wid in u.spec.weapon_loadout:
		u.weapons.append(DataDB.weapon(wid))
		u.magazines[wid] = u.spec.weapon_loadout[wid]
	return u

func _air_track(x: float) -> Track:
	var t := Track.new()
	t.owner_faction = "BLUE"
	t.domain = "air"
	t.identity = "HOSTILE"
	t.position = Vector2(x, 10)
	return t

func test_disconnected_unit_has_independent_track_history() -> void:
	var ship := _unit("usn_ddg_burke_iii")
	var boat := _unit("rn_ssn_astute")
	boat.depth_m = 120
	var enemy := _unit("rfn_ffg_admiral_gorshkov", "RED")
	var tm := TrackManager.new()
	tm.observe_contact("BLUE", SensorContact.make(enemy, Vector2(5, 5), 1, 1, 1, 7, "sonar", boat), 1, 1)
	assert_eq(tm.get_tracks("BLUE").size(), 0, "local detection is not published")
	var local: Track = tm.tracks_for(boat)[0]
	tm.observe_contact("BLUE", SensorContact.make(enemy, Vector2(80, 80), 1, 1, 1, 90, "radar", ship), 2, 1)
	assert_eq(tm.tracks_for(ship).size(), 1)
	assert_true(local != tm.tracks_for(ship)[0], "separate data objects")
	assert_near(local.position.x, 5, 0.01, "remote radar cannot refine a disconnected boat's track")
	assert_true(not (tm.tracks_for(ship)[0] as Track).visible_to(boat), "deep boat cannot use shared targeting")
	boat.depth_m = 0
	tm.observe_contact("BLUE", SensorContact.make(enemy, Vector2(6, 6), 1, 1, 1, 8, "sonar", boat), 3, 1)
	assert_eq(tm.tracks_for(boat), tm.get_tracks("BLUE"), "reconnection switches to network picture")
	tm.clear()
	assert_eq(tm._local_keys.size(), 0, "restart discards observer state")
	tm.free()

func test_off_link_shooter_cannot_fire_using_shared_track() -> void:
	var boat := _unit("rn_ssn_astute")
	boat.depth_m = 100
	var t := _air_track(5)
	t.domain = "subsurface"
	assert_eq(Combat.check_engagement(boat, DataDB.weapon("spearfish"), t).reason, "TRACK NOT HELD / OFF LINK")
	t.networked = false
	t.contributors[boat] = 1.0
	assert_true(Combat.check_engagement(boat, DataDB.weapon("spearfish"), t).ok, "local torpedo solution still works")

func test_private_weapon_detection_does_not_enable_remote_defence() -> void:
	var observer := _unit("usn_ddg_burke_iii")
	observer.spec = observer.spec.duplicate()
	observer.spec.has_datalink = false
	var consort := _unit("usn_ddg_burke_iii")
	var w := Weapon.new()
	w.id = 1
	w.spec = DataDB.weapon("kalibr_asm")
	w.faction = "RED"
	var tm := ThreatManager.new()
	tm.mark_detected("BLUE", w, 1, observer)
	assert_true(tm.visible_to(observer, w), "finder can defend locally")
	assert_true(not tm.visible_to(consort, w), "private radar cannot cue another ship")
	observer.spec.has_datalink = true
	assert_true(tm.visible_to(consort, w), "linked report is usable")
	tm.begin_cycle()
	assert_true(not tm.visible_to(consort, w), "fresh detection required each cycle")
	tm.free()

func test_manual_sam_salvo_reserves_shared_channel_budget() -> void:
	var ship := _unit("usn_ddg_burke_iii")
	ship.spec = ship.spec.duplicate()
	ship.spec.fire_control_channels = 1
	var wm := WeaponManager.new()
	var t1 := _air_track(20)
	var t2 := _air_track(25)
	var sm2 := DataDB.weapon("sm2_family")
	assert_true(wm.launch(ship, sm2, t1, 2, 0), "first SAM salvo launches")
	assert_eq(wm.channel_targets(ship).size(), 1, "two rounds at one track use one channel")
	var before := ship.magazine_count(sm2.id)
	assert_true(not wm.launch(ship, sm2, t2, 1, 0), "second target refused when saturated")
	assert_eq(ship.magazine_count(sm2.id), before, "rejected shot does not spend ammunition")
	wm.in_flight.clear()
	assert_eq(wm.channel_targets(ship).size(), 1, "queued second salvo round keeps reservation")
	wm.clear()
	assert_true(wm.channel_available(ship, t2), "channel released after engagement clears")
	wm.free()

func test_sam_and_point_defence_channels_are_distinct() -> void:
	var ship := _unit("usn_ddg_burke_iii")
	ship.spec = ship.spec.duplicate()
	ship.spec.fire_control_channels = 1
	var wm := WeaponManager.new()
	assert_true(wm.launch(ship, DataDB.weapon("sm2_family"), _air_track(20), 1, 0))
	var threat := Weapon.new()
	threat.spec = DataDB.weapon("kalibr_asm")
	threat.faction = "RED"
	threat.position = Vector2(1,0)
	assert_eq(wm.launch_interceptor(ship, DataDB.weapon("essm_family"), threat, 1, 0), 0, "manual SAM shot blocks new guided target")
	assert_true(wm.launch_interceptor(ship, DataDB.weapon("phalanx_ciws"), threat, 1, 0) > 0, "CIWS is self-contained")
	assert_eq(wm.channel_targets(ship).size(), 1, "CIWS does not consume guidance")
	wm.free()

func test_exoatmospheric_interceptor_requires_high_target() -> void:
	var w := Weapon.new()
	w.spec = DataDB.weapon("kinzhal_family").duplicate()
	var sm3 := DataDB.weapon("sm3_family")
	assert_true(not AirDefence._can_intercept(sm3, w), "40 km aero-ballistic profile is below SM-3 gate")
	w.spec.altitude_m = 150000
	assert_true(AirDefence._can_intercept(sm3, w), "synthetic exo target satisfies gate")
	assert_true(not AirDefence._can_intercept(DataDB.weapon("sm6_family"), w), "terminal interceptor is not exoatmospheric")

func test_neutral_identity_and_tight_roe_are_enforced() -> void:
	var ship := _unit("usn_ddg_burke_iii")
	var t := _air_track(10)
	t.identity = "NEUTRAL"
	assert_eq(Combat.check_engagement(ship, DataDB.weapon("sm2_family"), t).reason, "PROTECTED IDENTITY")
	t.identity = "UNKNOWN"
	ship.roe = Unit.Roe.TIGHT
	assert_true(not Combat.check_engagement(ship, DataDB.weapon("sm2_family"), t).ok)
	t.identity = "HOSTILE"
	assert_true(Combat.check_engagement(ship, DataDB.weapon("sm2_family"), t).ok)

func test_flight_deck_compatibility() -> void:
	var qe := DataDB.platform("rn_cvf_queen_elizabeth")
	var ford := DataDB.platform("usn_cvn_ford")
	var frigate := DataDB.platform("rn_ffg_type26")
	assert_true(qe.can_operate(DataDB.platform("rn_fighter_f35b")))
	assert_true(not qe.can_operate(DataDB.platform("usn_fighter_f35c")), "no catapult on STOVL deck")
	assert_true(not qe.can_operate(DataDB.platform("usn_aew_e2d")))
	assert_true(ford.can_operate(DataDB.platform("usn_aew_e2d")))
	assert_true(not ford.can_operate(DataDB.platform("usn_mpa_p8a")), "P-8 needs runway")
	assert_true(frigate.can_operate(DataDB.platform("rn_helo_merlin_hm2")))
	assert_true(not frigate.can_operate(DataDB.platform("fra_fighter_rafale_m")))

func test_deck_cycle_serializes_launches_and_rejects_wrong_aircraft() -> void:
	var parent := _unit("rn_cvf_queen_elizabeth")
	var a := _unit("rn_fighter_f35b")
	var b := _unit("rn_fighter_f35b")
	a.callsign = "First"
	b.callsign = "Second"
	parent.embarked.assign([a,b])
	var am := AviationManager.new()
	assert_true(am.launch(parent, "First") == a)
	assert_true(am.launch(parent, "Second") == null, "busy deck rejects second launch")
	a.flight_state = Unit.FlightState.AIRBORNE
	b.spec = DataDB.platform("usn_fighter_f35c")
	assert_true(am.launch(parent, "Second") == null, "wrong deck rejects even when free")
	am.free()

func test_all_catalogue_resources_resolve_and_cells_fit() -> void:
	assert_eq(DataDB.all_platforms().size(), 42)
	for p: PlatformSpec in DataDB.all_platforms():
		for sid in p.sensor_ids:
			assert_true(DataDB.sensor(sid) != null, p.id + " sensor " + sid)
		for wid in p.weapon_loadout:
			assert_true(DataDB.weapon(wid) != null, p.id + " weapon " + wid)
		if p.vls_cells > 0:
			assert_true(p.occupied_vls_cells() <= p.vls_cells, p.id + " magazine fits physical cells")
	assert_eq(DataDB.weapon("essm_family").vls_pack, 4, "ESSM is quad-packed")
	assert_true(DataDB.platform("usn_fighter_fa18e").sensor_ids.has("an_alr_67"))
	assert_true(not DataDB.platform("usn_fighter_fa18e").sensor_ids.has("an_alq_240"))
	assert_eq(DataDB.platform("usn_uav_mq4c").weapon_loadout.size(), 0)

func test_every_shipped_aircraft_has_compatible_home_and_capacity() -> void:
	for entry: Dictionary in ScenarioIndex.list_all():
		if entry.custom:
			continue
		var um := UnitManager.new()
		var sc := ScenarioLoader.load_file(entry.path)
		Terrain.load_from(sc)
		ScenarioLoader.populate(um, sc)
		for u in um.units:
			if u.is_aircraft():
				assert_true(u.home != null, entry.name + " / " + u.callsign + " valid home")
				if u.home != null:
					assert_true(u.home.spec.can_operate(u.spec))
					assert_true(u.home.embarked.size() <= u.home.spec.aircraft_capacity)
			elif u.spec.domain == "surface":
				assert_true(not Terrain.is_land(u.position), u.callsign + " afloat")
		um.free()
	Terrain.clear()
