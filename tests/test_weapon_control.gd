extends TestCase


func _weapon(id := "one", vls := false) -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = id
	w.max_range_nm = 60
	w.min_range_nm = 0.1
	w.launch_interval_s = 4
	w.vls_pack = 1 if vls else 0
	return w


func _unit(weapons: Array) -> Unit:
	var u := Unit.new()
	u.spec = PlatformSpec.new()
	u.spec.vls_cells = 32
	u.spec.fire_control_channels = 4
	u.spec.has_datalink = true
	u.faction = "BLUE"
	u.health = 100
	for w: WeaponSpec in weapons:
		u.weapons.append(w)
		u.magazines[w.id] = 8
	return u


func _track() -> Track:
	var t := Track.new()
	t.id = "T1901"
	t.owner_faction = "BLUE"
	t.identity = "HOSTILE"
	t.domain = "surface"
	t.position = Vector2(0, 20)
	return t


func _manager(u: Unit) -> WeaponManager:
	Terrain.clear()
	var wm := WeaponManager.new()
	wm.unit_manager = UnitManager.new()
	wm.unit_manager.add_unit(u)
	return wm


func _clean(wm: WeaponManager) -> void:
	wm.clear()
	wm.unit_manager.free()
	wm.free()


func test_repeated_manual_orders_respect_the_existing_launcher_queue() -> void:
	var spec := _weapon()
	var u := _unit([spec])
	var wm := _manager(u)
	var t := _track()
	assert_true(wm.launch(u, spec, t, 3, 0))
	assert_true(wm.launch(u, spec, t, 2, 0))
	assert_eq(wm.in_flight.size(), 1, "paused repeat orders cannot fire a whole magazine instantly")
	assert_eq(wm.committed_rounds(u, spec, t, true), 4)
	assert_eq(u.magazine_count(spec.id), 3)
	for now in range(1, 18):
		wm.tick(1, now)
	assert_eq(wm.in_flight.size(), 5)
	assert_eq(wm.committed_rounds(u, spec, t, true), 0)
	_clean(wm)


func test_vls_shares_service_but_an_independent_mount_can_fire() -> void:
	var a := _weapon("vls_a", true)
	var b := _weapon("vls_b", true)
	var c := _weapon("deck")
	var u := _unit([a, b, c])
	var wm := _manager(u)
	var t := _track()
	wm.launch(u, a, t, 2, 0)
	wm.launch(u, b, t, 1, 0)
	wm.launch(u, c, t, 1, 0)
	assert_eq(wm.in_flight.size(), 2, "one VLS round and the independent deck weapon")
	assert_eq(wm.committed_rounds(u, b, t, true), 1)
	assert_true(wm.ready_in_s(u, b, 0) >= 12)
	_clean(wm)


func test_hold_refunds_only_unfired_rounds() -> void:
	var spec := _weapon()
	var u := _unit([spec])
	var wm := _manager(u)
	wm.launch(u, spec, _track(), 4, 0)
	u.roe = Unit.Roe.HOLD
	wm.tick(0.25, 0.25)
	assert_eq(u.magazine_count(spec.id), 7)
	assert_eq(wm.in_flight.size(), 1, "an already launched missile is not recalled")
	assert_eq(wm.committed_rounds(u, spec, null, true), 0)
	_clean(wm)


func test_a_changed_identity_cancels_pending_shots() -> void:
	var spec := _weapon()
	var u := _unit([spec])
	var wm := _manager(u)
	var t := _track()
	wm.launch(u, spec, t, 3, 0)
	t.identity = "NEUTRAL"
	wm.tick(0.25, 0.25)
	assert_eq(u.magazine_count(spec.id), 7)
	assert_eq(wm.committed_rounds(u, spec, t, true), 0)
	_clean(wm)


func test_off_link_queued_shots_cannot_use_the_faction_picture() -> void:
	var spec := _weapon()
	var u := _unit([spec])
	var wm := _manager(u)
	var t := _track()
	wm.launch(u, spec, t, 3, 0)
	t.networked = false
	t.contributors.clear()
	wm.tick(0.25, 0.25)
	assert_eq(u.magazine_count(spec.id), 7)
	assert_eq(wm.in_flight.size(), 1)
	_clean(wm)


func test_cancel_is_scoped_to_the_selected_contact() -> void:
	var spec := _weapon()
	var u := _unit([spec])
	var wm := _manager(u)
	var one := _track()
	var two := _track()
	two.id = "T1902"
	wm.launch(u, spec, one, 2, 0)
	wm.launch(u, spec, two, 2, 0)
	assert_eq(wm.cancel_salvo(u, one), 1)
	assert_eq(wm.committed_rounds(u, spec, two, true), 2)
	assert_eq(u.magazine_count(spec.id), 5)
	_clean(wm)


func test_all_reserved_ammunition_can_leave_an_empty_available_magazine() -> void:
	var spec := _weapon()
	var u := _unit([spec])
	var wm := _manager(u)
	wm.launch(u, spec, _track(), 8, 0)
	assert_eq(u.magazine_count(spec.id), 0)
	for now in range(1, 30):
		wm.tick(1, now)
	assert_eq(wm.in_flight.size(), 8)
	_clean(wm)


func test_gross_tick_does_not_compress_a_salvo_into_one_instant() -> void:
	var spec := _weapon()
	var u := _unit([spec])
	var wm := _manager(u)
	wm.launch(u, spec, _track(), 4, 0)
	wm.tick(0, 30)
	assert_eq(wm.in_flight.size(), 2, "late processing launches one ready round, preserving spacing")
	_clean(wm)


func test_intercept_distance_not_current_range_limits_a_shot() -> void:
	var spec := _weapon()
	var u := _unit([spec])
	var t := _track()
	t.position = Vector2(0, 59)
	t.has_kinematics = true
	t.course_deg = 0
	t.speed_kn = 40
	var check := Combat.check_engagement(u, spec, t)
	assert_true(not check.ok)
	assert_eq(check.reason, "INTERCEPT BEYOND WEAPON RANGE")


func test_faster_receding_target_has_no_solution_but_closing_target_does() -> void:
	assert_true(not Combat.intercept_point(Vector2.ZERO, 100, Vector2(0, 10), 0, 200, true).is_finite())
	var aim := Combat.intercept_point(Vector2.ZERO, 100, Vector2(0, 10), 180, 200, true)
	assert_true(aim.is_finite())
	assert_near(aim.y, 10.0 / 3.0, 0.001)


func test_bearing_only_is_a_search_shot_for_torpedoes_not_a_missile_solution() -> void:
	var spec := _weapon()
	var u := _unit([spec])
	var t := _track()
	t.bearing_only = true
	t.tma_quality = 0.1
	assert_true(not Combat.check_engagement(u, spec, t).ok)
	spec.type = "torpedo"
	assert_true(Combat.check_engagement(u, spec, t).ok)
	assert_true(WeaponPresentation.track_quality(t, 0).contains("BEARING ONLY"))


func test_solution_does_not_consult_hidden_enemy_truth() -> void:
	var spec := _weapon()
	var u := _unit([spec])
	var t := _track()
	var hidden := _unit([])
	hidden.faction = "RED"
	hidden.position = Vector2(1000, 1000)
	t.truth = hidden
	var before := Combat.check_engagement(u, spec, t)
	hidden.alive = false
	hidden.position = Vector2.ZERO
	assert_eq(Combat.check_engagement(u, spec, t), before)


func test_asroc_flies_then_hands_off_to_an_independent_torpedo() -> void:
	var rocket := DataDB.weapon("rgm_139_vla")
	var u := _unit([rocket])
	var wm := _manager(u)
	var t := _track()
	t.domain = "subsurface"
	t.position = Vector2(0, 2)
	assert_true(wm.launch(u, rocket, t, 1, 0))
	var w: Weapon = wm.in_flight[0]
	assert_eq(w.threat_class(), "missile")
	for now in range(1, 33):
		wm.tick(1, now)
	assert_eq(w.spec.id, "mk54_lwt")
	assert_eq(w.threat_class(), "torpedo")
	assert_true(w.speed_nm_per_s() < Geo.knots_to_nm_per_s(50))
	assert_true(w.distance_flown_nm < 0.1, "the torpedo gets its own run budget")
	assert_true(w.delivery_spec == rocket)
	var goal := w.aim_point
	t.position = Vector2(100, 100)
	wm.tick(1, 33)
	assert_eq(w.aim_point, goal, "waterborne payload does not receive magic track steering")
	assert_eq(wm.committed_rounds(u, rocket, t), 1, "the board still accounts for the delivered payload")
	_clean(wm)


func test_sam_cannot_follow_asroc_underwater_after_delivery() -> void:
	var sam := DataDB.weapon("sm6_family")
	var w := Weapon.new()
	w.spec = DataDB.weapon("rgm_139_vla")
	assert_true(AirDefence._can_intercept(sam, w))
	w.spec = DataDB.weapon("mk54_lwt")
	assert_true(not AirDefence._can_intercept(sam, w))


func test_air_launch_height_agrees_between_detection_and_presentation() -> void:
	var w := Weapon.new()
	w.spec = DataDB.weapon("aim9x_air")
	w.launch_altitude_m = 9000
	assert_near(WorldPresentation.weapon_height_m(w), 9000, 0.01)
	var sensor := SensorSpec.new()
	sensor.range_air_nm = 10000
	assert_true(Detection.weapon_detection_range_nm(sensor, w.spec, 20, w.flight_altitude_m()) > Detection.weapon_detection_range_nm(sensor, w.spec, 20, 10))


func test_unpowered_bomb_needs_height_and_descends() -> void:
	var spec := DataDB.weapon("paveway_iv")
	var u := _unit([spec])
	u.altitude_m = 500
	assert_near(Combat.effective_range_nm(u, spec), 0.5, 0.001)
	u.altitude_m = 10000
	assert_near(Combat.effective_range_nm(u, spec), 8.0, 0.001)
	var w := Weapon.new()
	w.spec = spec
	w.launch_altitude_m = 8000
	w.launch_range_nm = 8
	w.distance_flown_nm = 4
	assert_near(w.flight_altitude_m(), 4000, 0.01)


func test_corrected_roles_and_aircraft_fits() -> void:
	assert_eq(Array(DataDB.weapon("agm_158b_jassm_er").target_types), ["land"])
	assert_eq(DataDB.weapon("aim9x_air").type, "aam")
	assert_eq(Array(DataDB.weapon("mk54_lwt").target_types), ["subsurface"])
	var uk := DataDB.platform("rn_fighter_f35b")
	assert_true(uk.weapon_loadout.has("paveway_iv") and uk.weapon_loadout.has("asraam_aam"))
	assert_true(not uk.weapon_loadout.has("jsm_missile"))
	assert_true(not DataDB.platform("jasdf_fighter_f35b").weapon_loadout.has("jsm_missile"))
	assert_true(DataDB.platform("rn_ssn_astute").weapon_loadout.has("tomahawk_tlam_v"))
	assert_eq(Array(DataDB.weapon("tomahawk_tlam_v").target_types), ["land"])
	assert_eq(DataDB.weapon("jmsdf_type07_vla").delivery_payload_id, "jmsdf_type97_torpedo")
	assert_true(DataDB.platform("rfn_uav_orion").weapon_loadout.has("orion_guided_bomb"))
	for id in ["rfn_mpa_il38n", "rfn_mpa_tu142"]:
		assert_true(not DataDB.platform(id).weapon_loadout.has("ugst_torpedo"))


func test_role_filters_cover_dual_role_weapons_without_losing_aam_or_bombs() -> void:
	assert_true(WeaponPresentation.matches(DataDB.weapon("tomahawk_block_v"), "land"))
	assert_true(WeaponPresentation.matches(DataDB.weapon("tomahawk_block_v"), "surface"))
	assert_true(WeaponPresentation.matches(DataDB.weapon("aim9x_air"), "air"))
	assert_true(WeaponPresentation.matches(DataDB.weapon("paveway_iv"), "land"))
	assert_true(WeaponPresentation.matches(DataDB.weapon("rgm_139_vla"), "subsurface"))


func test_every_platform_fit_and_payload_resolves_and_vls_fits() -> void:
	for platform: PlatformSpec in DataDB.all_platforms():
		if platform.vls_cells > 0:
			assert_true(platform.occupied_vls_cells() <= platform.vls_cells, platform.id + " VLS fit")
		for id: String in platform.weapon_loadout:
			assert_true(DataDB.weapon(id) != null, platform.id + " resolves " + id)
			assert_true(int(platform.weapon_loadout[id]) > 0, platform.id + " has positive stores")
	for spec: WeaponSpec in DataDB.all_weapons():
		assert_true(spec.min_range_nm >= 0 and spec.max_range_nm > spec.min_range_nm, spec.id + " range band")
		assert_true(spec.speed_kn > 0 and spec.launch_interval_s > 0, spec.id + " kinematics")
		assert_true(spec.target_types.size() > 0, spec.id + " has a role")
		if spec.delivery_payload_id != "":
			var payload := DataDB.weapon(spec.delivery_payload_id)
			assert_true(payload != null and payload.is_torpedo(), spec.id + " torpedo payload")
