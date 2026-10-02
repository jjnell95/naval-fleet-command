extends TestCase

func _helo() -> Unit:
	Terrain.clear()
	var u := Unit.new()
	u.spec = DataDB.platform("usn_helo_mh60r")
	for id in u.spec.sensor_ids:
		u.sensors.append(DataDB.sensor(id))
	u.flight_state = Unit.FlightState.AIRBORNE
	u.faction = "BLUE"
	u.altitude_m = 20.0
	u.ordered_altitude_m = u.spec.cruise_altitude_m
	u.ordered_speed_kn = u.spec.cruise_speed_kn
	return u


func _lower(u: Unit, um: UnitManager, duration := 0.0) -> void:
	assert_true(um.issue_order(u, Order.deploy_dipping_sonar(duration)))
	Movement.step(u, 0.25)
	assert_eq(u.dip_phase, DippingSonar.Phase.LOWERING)
	Movement.step(u, DippingSonar.LOWER_S)
	assert_true(DippingSonar.listening(u))


func test_deployment_requires_a_hover_then_full_lowering_before_active_or_passive_sensing() -> void:
	var u := _helo()
	var um := UnitManager.new()
	u.speed_kn = 100.0
	u.altitude_m = 400.0
	assert_true(um.issue_order(u, Order.active_sonar()))
	assert_true(not u.active_sonar_emitting(), "active posture does not put a stowed sonar in the water")
	assert_true(um.issue_order(u, Order.deploy_dipping_sonar(60.0)))
	Movement.step(u, 1.0)
	assert_eq(u.dip_phase, DippingSonar.Phase.POSITIONING)
	assert_true(not u.active_sonar_emitting())
	for step in 1000:
		Movement.step(u, 0.25)
		if u.dip_phase == DippingSonar.Phase.LOWERING: break
	assert_eq(u.dip_phase, DippingSonar.Phase.LOWERING)
	assert_near(u.dip_timer_s, DippingSonar.LOWER_S)
	Movement.step(u, DippingSonar.LOWER_S - 0.25)
	assert_true(not DippingSonar.listening(u) and not u.active_sonar_emitting())
	assert_near(Detection.best_active_sonar_nm(u), 0.0)
	assert_near(Detection.nominal_passive_ring_nm(u), 0.0)
	Movement.step(u, 0.25)
	assert_true(DippingSonar.listening(u) and u.active_sonar_emitting())
	assert_near(u.dip_timer_s, 60.0, 0.001, "listening duration starts after lowering")
	assert_true(Detection.best_active_sonar_nm(u) > 0.0 and Detection.nominal_passive_ring_nm(u) > 0.0)
	um.free()


func test_new_navigation_waits_for_retraction_and_keeps_the_newest_destination() -> void:
	var u := _helo()
	var um := UnitManager.new()
	_lower(u, um)
	var start := u.position
	assert_true(um.issue_order(u, Order.move(Vector2(0, 10))))
	assert_eq(u.dip_phase, DippingSonar.Phase.RAISING)
	assert_true(not DippingSonar.listening(u))
	assert_true(um.issue_order(u, Order.move(Vector2(10, 0))))
	assert_true(um.issue_order(u, Order.set_speed(80.0)))
	Movement.step(u, DippingSonar.RAISE_S - 0.25)
	assert_eq(u.position, start, "movement stays held until the wire is aboard")
	assert_eq(u.waypoints[0], Vector2(10, 0))
	assert_near(u.ordered_speed_kn, 80.0)
	Movement.step(u, 0.25)
	assert_eq(u.dip_phase, DippingSonar.Phase.STOWED)
	Movement.step(u, 1.0)
	assert_true(u.position != start and u.speed_kn > 0.0)
	assert_eq(u.waypoints[0], Vector2(10, 0), "no stale route restored after the new order")
	um.free()


func test_timed_cycle_preserves_station_and_resumes_only_after_raising() -> void:
	var u := _helo()
	var um := UnitManager.new()
	var route: Array[Vector2] = [Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)]
	u.waypoints.assign(route)
	u.patrol_active = true
	_lower(u, um, 60.0)
	Movement.step(u, 59.75)
	assert_true(DippingSonar.listening(u))
	Movement.step(u, 0.25)
	assert_eq(u.dip_phase, DippingSonar.Phase.RAISING)
	Movement.step(u, DippingSonar.RAISE_S)
	assert_eq(u.dip_phase, DippingSonar.Phase.STOWED)
	assert_eq(u.waypoints, route)
	assert_true(u.patrol_active)
	Movement.step(u, 1.0)
	assert_true(u.speed_kn > 0.0 and u.altitude_m > DippingSonar.HOVER_M)
	um.free()


func test_cancel_before_lowering_resumes_immediately_but_lowering_requires_raising() -> void:
	var u := _helo()
	var um := UnitManager.new()
	assert_true(um.issue_order(u, Order.deploy_dipping_sonar()))
	assert_true(not um.issue_order(u, Order.deploy_dipping_sonar()), "a repeat request cannot reset the clock")
	assert_true(um.issue_order(u, Order.recover_dipping_sonar()))
	assert_eq(u.dip_phase, DippingSonar.Phase.STOWED)
	assert_true(um.issue_order(u, Order.deploy_dipping_sonar()))
	Movement.step(u, 0.25)
	assert_true(um.issue_order(u, Order.recover_dipping_sonar()))
	assert_eq(u.dip_phase, DippingSonar.Phase.RAISING)
	assert_true(not um.issue_order(u, Order.recover_dipping_sonar()))
	um.free()


func test_availability_and_sensor_damage_prevent_deployment() -> void:
	var u := _helo()
	var um := UnitManager.new()
	u.flight_state = Unit.FlightState.STOWED
	assert_true(not um.issue_order(u, Order.deploy_dipping_sonar()))
	u.flight_state = Unit.FlightState.AIRBORNE
	u.returning = true
	assert_true(not um.issue_order(u, Order.deploy_dipping_sonar()))
	u.returning = false
	u.components["sensors"] = 0.0
	assert_true(not um.issue_order(u, Order.deploy_dipping_sonar()))
	u.components["sensors"] = 1.0
	_lower(u, um)
	u.components["sensors"] = 0.0
	assert_true(not DippingSonar.listening(u))
	Movement.step(u, 0.25)
	assert_eq(u.dip_phase, DippingSonar.Phase.RAISING)
	var jet := Unit.new()
	jet.spec = DataDB.platform("usn_fighter_fa18e")
	jet.flight_state = Unit.FlightState.AIRBORNE
	assert_true(not um.issue_order(jet, Order.deploy_dipping_sonar()))
	um.free()


func test_automatic_fuel_return_raises_before_final_approach() -> void:
	var u := _helo()
	var um := UnitManager.new()
	var av := AviationManager.new()
	av.unit_manager = um
	var base := Unit.new()
	base.spec = DataDB.platform("usn_ddg_arleigh_burke_iia")
	base.faction = u.faction
	u.home = base
	base.embarked.append(u)
	um.add_unit(base)
	um.add_unit(u)
	_lower(u, um)
	u.fuel_s = av.return_fuel_required(u, base) - 1.0
	av._step_airborne(u, 0.25)
	assert_true(u.returning)
	assert_eq(u.dip_phase, DippingSonar.Phase.RAISING)
	assert_eq(u.flight_state, Unit.FlightState.AIRBORNE, "a nearby deck cannot skip retraction")
	Movement.step(u, DippingSonar.RAISE_S)
	av._step_airborne(u, 0.25)
	assert_eq(u.flight_state, Unit.FlightState.RECOVERING)
	base.embarked.clear()
	av.free()
	um.free()


func test_land_and_loss_of_hover_cannot_produce_a_wet_array() -> void:
	var u := _helo()
	var um := UnitManager.new()
	Terrain.load_from({"terrain": {"land": [{"name": "Test island", "points_nm": [[-5, -5], [5, -5], [5, 5], [-5, 5]]}]}})
	assert_true(not um.issue_order(u, Order.deploy_dipping_sonar()))
	Terrain.clear()
	_lower(u, um)
	u.altitude_m = 100.0
	assert_true(not DippingSonar.listening(u))
	Movement.step(u, 0.25)
	assert_eq(u.dip_phase, DippingSonar.Phase.RAISING)
	um.free()
