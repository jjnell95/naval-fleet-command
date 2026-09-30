extends TestCase

func _unit(air := false) -> Unit:
	var u := Unit.new()
	u.spec = DataDB.platform("usn_helo_mh60r" if air else "usn_ddg_arleigh_burke_iia")
	u.faction = "BLUE"
	u.health = u.spec.health
	u.flight_state = Unit.FlightState.AIRBORNE if air else Unit.FlightState.STOWED
	u.fuel_s = u.spec.endurance_s
	u.position = Vector2(-5, -5)
	return u

func _box() -> Order:
	return Order.patrol_box(Vector2(-5, -5), Vector2(-1, -1))

func test_patrol_completes_multiple_circuits_without_stopping() -> void:
	Terrain.clear()
	var u := _unit(true)
	var um := UnitManager.new()
	um.add_unit(u)
	assert_true(um.issue_order(u, _box()))
	for i in 10000:
		um.tick(0.25)
	assert_true(u.patrol_legs_completed >= 8, "aircraft completes at least two circuits")
	assert_eq(u.waypoints.size(), 4, "completed corners return to the back of the queue")
	assert_true(u.speed_kn > 0.0, "does not stop at the last corner")
	assert_true(Rect2(-6, -6, 6, 6).has_point(u.position), "remains within turning room of the box")
	um.free()

func test_fast_aircraft_can_complete_the_minimum_patrol_box() -> void:
	Terrain.clear()
	var u := _unit(true)
	u.spec = DataDB.platform("usn_fighter_fa18e")
	assert_true(not UnitManager.can_accept_order(u, Order.patrol_box(Vector2(-5, -5), Vector2(-4, -4))), "a fighter cannot turn inside a helicopter's one-mile box")
	var leg := UnitManager.patrol_min_leg_nm(u)
	var order := Order.patrol_box(Vector2(-5, -5), Vector2(-5 + leg, -5 + leg))
	assert_true(UnitManager.can_accept_order(u, order))
	u.apply_order(order)
	for i in 16000:
		Movement.step(u, .25)
	assert_true(u.patrol_legs_completed >= 8, "fighter makes progress around the smallest assignable circuit")


func test_patrol_orders_copy_points_and_do_not_share_rotating_queues() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var a := _unit()
	var b := _unit()
	var order := _box()
	um.add_unit(a)
	um.add_unit(b)
	assert_true(um.issue_order(a, order))
	assert_true(um.issue_order(b, order))
	Movement.step(a, .25)
	assert_near(b.waypoints[0].x, -5)
	assert_near(order.route[0].x, -5, 0.001, "shared order remains immutable after one unit turns")
	assert_true(a.waypoints[0] != b.waypoints[0])
	um.free()

func test_speed_order_cannot_make_an_existing_patrol_impossible_to_turn() -> void:
	Terrain.clear()
	var u := _unit(true)
	u.spec = DataDB.platform("usn_fighter_fa18e")
	var um := UnitManager.new()
	um.add_unit(u)
	assert_true(um.issue_order(u, _box()))
	var cruise := u.ordered_speed_kn
	assert_true(not um.issue_order(u, Order.set_speed(999)), "flank speed exceeds the box's turning room")
	assert_eq(u.ordered_speed_kn, cruise, "refused speed does not mutate the standing plan")
	assert_true(um.issue_order(u, Order.set_speed(300)))
	assert_true(u.patrol_active)
	um.free()

func test_manual_navigation_cancels_patrol_but_sensor_and_speed_orders_preserve_it() -> void:
	Terrain.clear()
	var u := _unit()
	for command: Order in [Order.set_speed(12), Order.activate_radar(), Order.set_emcon(true), Order.set_roe(Unit.Roe.HOLD)]:
		u.apply_order(_box())
		u.apply_order(command)
		assert_true(u.patrol_active)
	for command: Order in [Order.move(Vector2.ZERO), Order.move(Vector2.ZERO, true), Order.set_course(90), Order.stop(), Order.clear_waypoints(), Order.break_formation()]:
		u.apply_order(_box())
		u.apply_order(command)
		assert_true(not u.patrol_active, command.describe())

func test_evasion_preserves_circuit_and_resumes_it() -> void:
	Terrain.clear()
	var u := _unit()
	u.apply_order(_box())
	u.evasion_remaining_s = 30
	u.evasion_course_deg = 180
	Movement.step(u, .25)
	assert_eq(u.patrol_legs_completed, 0, "evasion does not consume a corner")
	u.apply_order(Order.resume_plan())
	Movement.step(u, .25)
	assert_eq(u.patrol_legs_completed, 1)
	assert_true(u.patrol_active)

func test_invalid_circuit_is_rejected_atomically() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var u := _unit()
	um.add_unit(u)
	um.issue_order(u, Order.move(Vector2(-20, 0)))
	for bad: Order in [Order.patrol_box(Vector2.ZERO, Vector2(.1, 5)), Order.patrol([Vector2.ZERO]), Order.patrol([Vector2.ZERO, Vector2(0, NAN), Vector2(5, 5)])]:
		assert_true(not um.issue_order(u, bad))
		assert_eq(u.waypoints, [Vector2(-20, 0)], "rejected area leaves the standing route untouched")
		assert_true(not u.patrol_active)
	um.free()

func test_land_crossing_and_blocked_approach_are_rejected_but_aircraft_can_overfly() -> void:
	Terrain.load_from({"terrain": {"land": [{"points_nm": [[-2, -2], [2, -2], [2, 2], [-2, 2]], "name": "Island", "elevation_m": 50}]}})
	var ship := _unit()
	ship.position = Vector2(-5, 0)
	var crossed := Order.patrol_box(Vector2(-4, 0), Vector2(4, 5))
	assert_true(UnitManager.patrol_rejection(ship, crossed.route).contains("crosses land"))
	var blocked := Order.patrol_box(Vector2(4, 0), Vector2(8, 5))
	assert_true(UnitManager.patrol_rejection(ship, blocked.route).contains("approach"))
	assert_eq(UnitManager.patrol_rejection(_unit(true), crossed.route), "")
	Terrain.clear()

func test_bingo_fuel_breaks_patrol_and_prevents_retasking_the_returning_aircraft() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var av := AviationManager.new()
	av.unit_manager = um
	var ship := _unit()
	var a := _unit(true)
	a.home = ship
	ship.embarked.append(a)
	um.add_unit(ship)
	um.add_unit(a)
	assert_true(um.issue_order(a, _box()))
	var fuel := a.fuel_s
	av.tick(10, 10)
	assert_true(a.fuel_s < fuel, "patrolling consumes real endurance")
	a.fuel_s = av.return_fuel_required(a, ship) - 1
	av.tick(1.0, 11.0)
	assert_true(a.returning and not a.patrol_active, "bingo cancels the circuit")
	assert_true(not um.issue_order(a, _box()), "cannot override bingo with a patrol")
	assert_eq(a.recovery_base, ship)
	av.free()
	um.free()

func test_patrol_unavailable_on_deck_or_during_recovery() -> void:
	var u := _unit(true)
	for state: int in [Unit.FlightState.STOWED, Unit.FlightState.LAUNCHING, Unit.FlightState.RECOVERING]:
		u.flight_state = state as Unit.FlightState
		assert_true(not UnitManager.can_accept_order(u, _box()))

func test_patrol_leaves_formation_and_display_distinguishes_it_from_transit() -> void:
	Terrain.clear()
	var ship := _unit()
	var leader := _unit()
	ship.formation_leader = leader
	ship.apply_order(_box())
	assert_true(not ship.in_formation())
	assert_true(DataDisplay.orders_text(ship).contains("Patrol circuit"))
	ship.apply_order(Order.move(Vector2(-9, -9)))
	assert_true(DataDisplay.orders_text(ship).contains("Transit"))

func test_patrol_tool_cancels_cleanly_when_selection_changes() -> void:
	var map := TacticalMap.new()
	map.select_units([_unit()])
	map.set_patrol_mode(true)
	assert_eq(map.interaction_mode, TacticalMap.InteractionMode.PATROL)
	map._patrol_started = true
	map.select_units([])
	assert_eq(map.interaction_mode, TacticalMap.InteractionMode.SELECT)
	assert_true(not map._patrol_started)
	map.select_units([_unit()])
	map.set_patrol_mode(true)
	assert_true(map.cancel_interaction_mode())
	assert_eq(map.interaction_mode, TacticalMap.InteractionMode.SELECT)
	map.free()
