extends TestCase
## Deliberate ship sonar handling, role screens, and aircraft endurance decisions.


func _ship(id := "rn_ffg_type26") -> Unit:
	Terrain.clear()
	Bathymetry.clear()
	Detection.set_environment({})
	var u := Unit.new()
	u.spec = DataDB.platform(id)
	u.faction = "BLUE"
	for sensor in u.spec.sensor_ids: u.sensors.append(DataDB.sensor(sensor))
	u.magazines = u.spec.weapon_loadout.duplicate()
	u.ordered_speed_kn = u.spec.cruise_speed_kn
	return u


func test_ship_array_must_slow_and_stream_before_it_can_hear_or_ping() -> void:
	var u := _ship()
	var um := UnitManager.new()
	u.speed_kn = 20.0
	assert_true(um.issue_order(u, Order.active_sonar()))
	assert_near(Detection.nominal_passive_ring_nm(u), 0.0)
	assert_true(not u.active_sonar_emitting())
	assert_true(um.issue_order(u, Order.asw_search()))
	Movement.step(u, 1.0)
	assert_near(u.array_timer_s, TowedArray.STREAM_S, 0.01, "cable waits for safe speed")
	for i in 400: Movement.step(u, 0.25)
	assert_eq(u.array_phase, TowedArray.Phase.STREAMING)
	assert_true(u.speed_kn <= TowedArray.QUIET_SPEED_KN + 0.1)
	for i in 400: Movement.step(u, 0.25)
	assert_eq(u.array_phase, TowedArray.Phase.LISTENING)
	assert_true(Detection.nominal_passive_ring_nm(u) > 0.0 and u.active_sonar_emitting())
	assert_near(u.ordered_speed_kn, u.spec.cruise_speed_kn, 0.001, "commanded intent is preserved")
	um.free()


func test_ship_navigation_recovers_before_accelerating_and_keeps_latest_route() -> void:
	var u := _ship()
	var um := UnitManager.new()
	assert_true(um.issue_order(u, Order.asw_search()))
	Movement.step(u, TowedArray.STREAM_S)
	assert_true(um.issue_order(u, Order.move(Vector2(0, 80))))
	assert_true(um.issue_order(u, Order.move(Vector2(80, 0))))
	assert_eq(u.array_phase, TowedArray.Phase.RECOVERING)
	assert_true(not u.array_search_active)
	Movement.step(u, TowedArray.RECOVER_S - 0.25)
	assert_true(u.speed_kn <= TowedArray.QUIET_SPEED_KN + 0.1)
	assert_near(Detection.nominal_passive_ring_nm(u), 0.0)
	Movement.step(u, 0.25)
	Movement.step(u, 10.0)
	assert_eq(u.array_phase, TowedArray.Phase.STOWED)
	assert_true(u.speed_kn > TowedArray.QUIET_SPEED_KN)
	assert_eq(u.waypoints[0], Vector2(80, 0))
	um.free()


func test_shallow_water_and_damage_recover_arrays_without_blinding_hull_sonar() -> void:
	var u := _ship()
	var hull := SensorSpec.new()
	hull.kind = "sonar"
	hull.passive_sensitivity_nm = 5.0
	u.sensors.append(hull)
	assert_true(Detection.nominal_passive_ring_nm(u) > 0.0, "hull sonar stays available with array stowed")
	TowedArray.search(u)
	TowedArray.step(u, TowedArray.STREAM_S)
	Bathymetry.load_for({"environment": {"bottom_m": 15.0}})
	TowedArray.step(u, 0.25)
	assert_eq(u.array_phase, TowedArray.Phase.RECOVERING)
	assert_true(not TowedArray.sensor_ready(u, u.sensors[1]))
	Bathymetry.clear()
	u.array_phase = TowedArray.Phase.LISTENING
	u.components["sensors"] = 0.0
	TowedArray.step(u, 0.25)
	assert_eq(u.array_phase, TowedArray.Phase.RECOVERING)


func test_array_save_fields_resume_identically_and_legacy_units_start_stowed() -> void:
	for phase in [TowedArray.Phase.STREAMING, TowedArray.Phase.LISTENING, TowedArray.Phase.RECOVERING]:
		var u := _ship()
		u.array_phase = phase
		u.array_timer_s = 31.75
		u.array_search_active = phase != TowedArray.Phase.RECOVERING
		var refs := SimSnapshot.Refs.new()
		var saved := SimSnapshot.fields_of(u, SimSnapshot.UNIT_SKIP, refs)
		var restored := Unit.new()
		SimSnapshot._fill(restored, bytes_to_var(var_to_bytes(saved)), SimSnapshot.Refs.new())
		assert_eq(refs.errors.size(), 0)
		for i in 200:
			Movement.step(u, 0.25)
			Movement.step(restored, 0.25)
		assert_eq(u.array_phase, restored.array_phase)
		assert_eq(u.position, restored.position)
		assert_eq(u.array_timer_s, restored.array_timer_s)
		for key in ["array_phase", "array_timer_s", "array_search_active"]: saved.erase(key)
		var legacy := Unit.new()
		SimSnapshot._fill(legacy, saved, SimSnapshot.Refs.new())
		assert_eq(legacy.array_phase, TowedArray.Phase.STOWED)
		assert_true(not legacy.array_search_active)


func test_role_screens_put_capable_escort_on_threat_axis_independent_of_selection_order() -> void:
	var guide := _ship("usn_cvn_nimitz")
	var asw := _ship()
	var aaw := _ship("usn_ddg_arleigh_burke_iia")
	guide.id = 1
	asw.id = 2
	aaw.id = 3
	var screen := Formation.assign([guide, asw, aaw], "aaw_screen", 1.0, 90.0)
	assert_eq(screen[0]["unit"], aaw)
	aaw.apply_order(screen[0]["order"])
	var east := Formation.station_for(aaw)
	assert_true(east.x > guide.position.x + 7.0)
	guide.heading_deg = 180.0
	assert_eq(Formation.station_for(aaw), east, "guide turn does not rotate the threat-facing station")
	var sub_screen := Formation.assign([guide, aaw, asw], "asw_screen")
	assert_eq(sub_screen[0]["unit"], asw)
	var transit := Formation.assign([guide, asw, aaw], "transit")
	assert_eq(transit[0]["unit"], asw, "transit keeps selection order")
	assert_true((transit[0]["order"] as Order).offset_nm.y < 0.0)
	guide.embarked.clear()


func test_quiet_array_consort_paces_the_group_then_releases_it_after_recovery() -> void:
	var guide := _ship()
	var consort := _ship()
	consort.apply_order(Order.form_up(guide, Vector2(0, 6)))
	TowedArray.search(consort)
	Formation.update_speed_caps([guide, consort])
	assert_near(guide.formation_speed_cap_kn, TowedArray.QUIET_SPEED_KN)
	TowedArray.recover(consort)
	TowedArray.step(consort, TowedArray.RECOVER_S)
	Formation.update_speed_caps([guide, consort])
	assert_true(guide.formation_speed_cap_kn > TowedArray.QUIET_SPEED_KN)


func test_tomcat_patrol_transit_dash_are_distinct_with_disproportionate_dash_fuel_cost() -> void:
	var spec := DataDB.platform("cw90_f14a")
	assert_near(spec.flight_speed("patrol"), 390.0)
	assert_near(spec.flight_speed("transit"), 480.0)
	assert_near(spec.flight_speed("dash"), 700.0)
	assert_true(spec.fuel_burn_rate(390.0) < spec.fuel_burn_rate(480.0))
	assert_true(spec.fuel_burn_rate(700.0) > spec.fuel_burn_rate(480.0) * 1.8)
	var patrol := Unit.new()
	patrol.spec = spec
	patrol.speed_kn = spec.flight_speed("patrol")
	patrol.fuel_s = spec.endurance_s
	var dash := Unit.new()
	dash.spec = spec
	dash.speed_kn = spec.flight_speed("dash")
	dash.fuel_s = spec.endurance_s
	var av := AviationManager.new()
	av._burn_fuel(patrol, 600.0)
	av._burn_fuel(dash, 600.0)
	assert_true(patrol.fuel_s - dash.fuel_s > 500.0, "a ten-minute dash materially reduces station time")
	av.free()


func test_hover_burn_exceeds_economical_helicopter_forward_flight() -> void:
	var spec := DataDB.platform("usn_helo_mh60r")
	assert_true(spec.fuel_burn_rate(0.0) > spec.fuel_burn_rate(spec.flight_speed("patrol")))
	assert_true(spec.flight_speed("dash") <= spec.max_speed_kn)


func test_enemy_ship_works_only_a_nearby_held_submarine_datum_and_recovers_for_transit() -> void:
	var ship := _ship("pla_ffg_type054a")
	ship.faction = "RED"
	ship.health = ship.spec.health
	var transit := _ship("pla_ffg_type054a")
	transit.faction = "RED"
	transit.health = transit.spec.health
	transit.ai_posture = "breakout"
	transit.patrol_route.assign([Vector2(0, 30), Vector2(30, 30)])
	var um := UnitManager.new()
	um.add_unit(ship)
	um.add_unit(transit)
	var tm := TrackManager.new()
	var t := Track.new()
	t.id = "R-01"
	t.owner_faction = "RED"
	t.domain = "subsurface"
	t.identity = "UNKNOWN"
	t.position = Vector2(1.5, 0)
	t.status = Track.Status.ACTIVE
	tm._tracks["RED"] = [t]
	var ai := AIController.new()
	ai.faction = "RED"
	ai.unit_manager = um
	ai.track_manager = tm
	var orders: Array[int] = []
	um.order_issued.connect(func(u: Unit, o: Order) -> void:
		if u == ship: orders.append(o.type))
	ai.tick(0.0)
	assert_eq(ai.state_name(ship), "INVESTIGATE")
	assert_eq(ship.array_phase, TowedArray.Phase.STREAMING, "enemy crew explicitly streams on its held submarine datum")
	assert_true(orders.has(Order.Type.ASW_SEARCH))
	assert_eq(transit.array_phase, TowedArray.Phase.STOWED, "a breakout ship keeps transit priorities")
	assert_true(transit.ordered_speed_kn > TowedArray.QUIET_SPEED_KN)
	for i in 800:
		um.tick(0.25)
		if i % 8 == 0: ai.tick(float(i + 1) * 0.25)
	assert_eq(ship.array_phase, TowedArray.Phase.LISTENING, "routine AI course refresh cannot restart the handling clock")
	assert_true(Detection.sonar_sensor_ready(ship, DataDB.sensor("pla_hsjg206")))
	assert_true(ship.speed_kn <= TowedArray.QUIET_SPEED_KN + 0.1)
	t.position = Vector2(40, 0)
	ai.tick(202.0)
	assert_eq(ship.array_phase, TowedArray.Phase.RECOVERING, "a distant datum requires recovery before transit")
	assert_true(ship.ordered_speed_kn > TowedArray.QUIET_SPEED_KN)
	for i in 400: um.tick(0.25)
	assert_eq(ship.array_phase, TowedArray.Phase.STOWED)
	assert_true(ship.speed_kn > TowedArray.QUIET_SPEED_KN)
	# A fresh nearby look starts another cycle; losing it returns the crew to normal patrol.
	t.position = ship.position + Vector2(1, 0)
	ai.tick(305.0)
	assert_true(ship.array_search_active)
	t.status = Track.Status.LOST
	ai.tick(307.0)
	assert_eq(ship.array_phase, TowedArray.Phase.RECOVERING)
	assert_true(not ship.array_search_active)
	ai.free()
	tm.free()
	um.free()
