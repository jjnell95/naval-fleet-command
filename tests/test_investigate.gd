extends TestCase


func _unit(air := false) -> Unit:
	var u := Unit.new()
	u.spec = DataDB.platform("usn_helo_mh60r" if air else "usn_ddg_arleigh_burke_iia")
	for sid in u.spec.sensor_ids:
		u.sensors.append(DataDB.sensor(sid))
	u.faction = "BLUE"
	u.flight_state = Unit.FlightState.AIRBORNE if air else Unit.FlightState.STOWED
	u.fuel_s = u.spec.endurance_s
	u.health = u.spec.health
	return u


func _track() -> Track:
	var t := Track.new()
	t.id = "0101"
	t.owner_faction = "BLUE"
	t.position = Vector2(0, 10)
	return t


func test_paused_order_records_task_and_follows_only_reported_position() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var u := _unit()
	var t := _track()
	t.truth = _unit()
	t.truth.position = Vector2(500, 500)
	um.add_unit(u)
	assert_true(um.issue_order(u, Order.investigate(t)))
	assert_eq(u.investigation_track, t, "task is recorded without a simulation tick")
	assert_eq(u.position, Vector2.ZERO, "issuing while paused never advances the platform")
	assert_eq(u.waypoints, [t.position], "reported plot, not underlying enemy truth")
	t.position = Vector2(10, 10)
	um.tick(0.25)
	assert_eq(u.waypoints, [t.position], "new sensor reports update the destination")
	assert_eq(t.classification, Track.Classification.UNKNOWN, "investigation does not grant free identification")
	um.free()


func test_domain_classification_continues_but_known_class_completes_once() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var u := _unit()
	var t := _track()
	var receipts: Array = []
	um.investigation_ended.connect(func(unit: Unit, track: Track, reason: String) -> void: receipts.append([unit, track, reason]))
	um.add_unit(u)
	um.issue_order(u, Order.investigate(t))
	t.classification = Track.Classification.SURFACE
	um.tick(0.25)
	assert_eq(u.investigation_track, t)
	t.classification = Track.Classification.CLASS_KNOWN
	t.known_class = "Merchant"
	um.tick(0.25)
	assert_eq(u.investigation_track, null)
	assert_eq(u.investigation_result, "Contact classified")
	assert_eq(u.investigation_track_id, t.id)
	assert_true(u.waypoints.is_empty())
	assert_eq(u.ordered_speed_kn, 0.0, "classification ends pursuit")
	t.position = Vector2(30, 30)
	um.tick(0.25)
	assert_eq(receipts.size(), 1, "one completion receipt per task")
	assert_eq(receipts[0], [u, t, "Contact classified"])
	um.free()


func test_lost_hidden_and_bearing_only_updates_end_task_and_hold() -> void:
	Terrain.clear()
	for change: String in ["lost", "hidden", "bearing"]:
		var um := UnitManager.new()
		var u := _unit()
		var t := _track()
		um.add_unit(u)
		assert_true(um.issue_order(u, Order.investigate(t)))
		match change:
			"lost": t.status = Track.Status.LOST
			"hidden": t.networked = false
			"bearing": t.bearing_only = true
		um.tick(0.25)
		assert_eq(u.investigation_track, null, change)
		assert_true(not u.investigation_result.is_empty(), change)
		assert_true(u.waypoints.is_empty(), change)
		assert_eq(u.ordered_speed_kn, 0.0, change)
		um.free()


func test_invalid_contact_is_rejected_without_replacing_current_navigation() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var u := _unit()
	um.add_unit(u)
	var course := Vector2(5, 5)
	um.issue_order(u, Order.move(course))
	for change: String in ["foreign", "lost", "hidden", "bearing", "classified", "invalid"]:
		var t := _track()
		match change:
			"foreign": t.owner_faction = "RED"
			"lost": t.status = Track.Status.LOST
			"hidden": t.networked = false
			"bearing": t.bearing_only = true
			"classified": t.classification = Track.Classification.CLASS_KNOWN
			"invalid": t.position = Vector2(NAN, 0)
		assert_true(not um.issue_order(u, Order.investigate(t)), change)
		assert_eq(u.waypoints, [course], change)
		assert_eq(u.investigation_track, null, change)
	assert_true(not um.issue_order(u, Order.investigate(null)))
	um.free()


func test_local_contact_requires_contribution_when_not_networked() -> void:
	Terrain.clear()
	var u := _unit()
	var t := _track()
	t.networked = false
	assert_true(UnitManager.investigation_rejection(u, t) != "")
	t.contributors[u] = true
	assert_eq(UnitManager.investigation_rejection(u, t), "")
	t.owner_faction = "RED"
	assert_true(UnitManager.investigation_rejection(u, t) != "", "a contributor cannot cross faction ownership")
	t.contributors.clear()


func test_evasion_suspends_investigation_then_resumes_the_latest_plot() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var u := _unit()
	var t := _track()
	um.add_unit(u)
	um.issue_order(u, Order.investigate(t))
	u.evasion_remaining_s = 30
	u.evasion_course_deg = 180
	t.position = Vector2(10, 0)
	um.tick(0.25)
	assert_eq(u.investigation_track, t)
	assert_eq(u.waypoints, [Vector2(0, 10)], "evasion suspends the investigation route")
	um.issue_order(u, Order.resume_plan())
	um.tick(0.25)
	assert_eq(u.waypoints, [t.position], "resuming reads the latest held contact position")
	um.free()


func test_navigation_supersedes_investigation_and_support_orders_preserve_it() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var u := _unit()
	var t := _track()
	var leader := _unit()
	um.add_unit(u)
	um.add_unit(leader)
	for o: Order in [Order.set_speed(10), Order.set_emcon(true), Order.set_roe(Unit.Roe.HOLD)]:
		um.issue_order(u, Order.investigate(t))
		assert_true(um.issue_order(u, o), o.describe())
		assert_eq(u.investigation_track, t, o.describe())
	for o: Order in [Order.move(Vector2(5, 0)), Order.move(Vector2(5, 0), true), Order.set_course(90), Order.stop(), Order.clear_waypoints(), Order.patrol_box(Vector2(5, 5), Vector2(10, 10)), Order.form_up(leader, Vector2(0, -2)), Order.break_formation()]:
		assert_true(um.issue_order(u, Order.investigate(t)))
		assert_true(um.issue_order(u, o), o.describe())
		assert_eq(u.investigation_track, null, o.describe())
		assert_eq(u.investigation_result, "")
		if o.type == Order.Type.MOVE:
			assert_eq(u.waypoints, [Vector2(5, 0)], "old investigation plot is not appended to the manual route")
	um.free()


func test_waiting_at_plot_can_follow_new_reports_and_preserves_selected_speed() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var u := _unit()
	var t := _track()
	t.position = u.position
	um.add_unit(u)
	assert_true(um.issue_order(u, Order.investigate(t)))
	um.tick(0.25)
	assert_eq(u.investigation_track, t)
	assert_true(u.waypoints.is_empty())
	assert_eq(u.ordered_speed_kn, 0.0)
	um.issue_order(u, Order.set_speed(12))
	t.position = Vector2(0, 10)
	um.tick(0.25)
	assert_eq(u.waypoints, [t.position])
	assert_eq(u.ordered_speed_kn, 12.0)
	um.issue_order(u, Order.set_speed(0))
	um.tick(0.25)
	assert_eq(u.ordered_speed_kn, 0.0, "a manual speed hold is not silently undone")
	um.free()


func test_land_blocks_surface_investigation_but_aircraft_can_overfly() -> void:
	Terrain.load_from({"terrain": {"land": [{"points_nm": [[-2, -2], [2, -2], [2, 2], [-2, 2]], "name": "Island", "elevation_m": 50}]}})
	var um := UnitManager.new()
	var u := _unit()
	u.position = Vector2(-5, 0)
	var t := _track()
	t.position = Vector2(5, 0)
	um.add_unit(u)
	assert_true(not um.issue_order(u, Order.investigate(t)), "initial route cannot cross land")
	assert_eq(UnitManager.investigation_rejection(_unit(true), t), "")
	t.position = Vector2(-5, 10)
	assert_true(um.issue_order(u, Order.investigate(t)))
	t.position = Vector2(5, 0)
	um.tick(0.25)
	assert_eq(u.investigation_track, null, "a fresh plot cannot send a hull across an island")
	assert_true(u.investigation_result.contains("Land blocks"))
	assert_eq(u.ordered_speed_kn, 0.0)
	um.free()
	Terrain.clear()


func test_unavailable_aircraft_and_immobile_units_cannot_investigate() -> void:
	Terrain.clear()
	var t := _track()
	var a := _unit(true)
	for state: int in [Unit.FlightState.STOWED, Unit.FlightState.LAUNCHING, Unit.FlightState.RECOVERING]:
		a.flight_state = state as Unit.FlightState
		assert_true(not UnitManager.can_accept_order(a, Order.investigate(t)))
	a.flight_state = Unit.FlightState.AIRBORNE
	a.returning = true
	assert_true(not UnitManager.can_accept_order(a, Order.investigate(t)))
	a.returning = false
	a.alive = false
	assert_true(not UnitManager.can_accept_order(a, Order.investigate(t)))
	var shore := Unit.new()
	shore.spec = PlatformSpec.new()
	shore.spec.max_speed_kn = 0
	assert_true(not UnitManager.can_accept_order(shore, Order.investigate(t)))


func test_fixed_wing_keeps_flying_at_plot_and_after_classification() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var a := _unit(true)
	a.spec = DataDB.platform("usn_fighter_fa18e")
	a.speed_kn = a.spec.cruise_speed_kn
	a.ordered_speed_kn = a.spec.cruise_speed_kn
	var t := _track()
	t.position = a.position
	um.add_unit(a)
	assert_true(um.issue_order(a, Order.investigate(t)))
	um.tick(0.25)
	assert_true(a.ordered_speed_kn > 0, "arrival must not make a fixed-wing aircraft hover")
	t.classification = Track.Classification.CLASS_KNOWN
	um.tick(0.25)
	assert_eq(a.investigation_track, null)
	assert_true(a.ordered_speed_kn >= a.spec.flight_speed("patrol") - 0.01, "completed aircraft maintains forward flight")
	# It holds where it finished, a racetrack through its own position, rather than flying on along
	# its heading until bingo or continuing to pursue the classified contact.
	assert_eq(a.waypoints.size(), 4, "a holding pattern")
	assert_true(a.waypoints.back().distance_to(a.position) < 0.5, "the hold is laid where the aircraft is")
	um.free()


func test_accepted_return_and_bingo_replace_investigation_without_stealing_recovery_route() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var av := AviationManager.new()
	av.unit_manager = um
	var base := _unit()
	var a := _unit(true)
	a.position = Vector2(0, 10)
	a.home = base
	base.embarked.append(a)
	um.add_unit(base)
	um.add_unit(a)
	var t := _track()
	t.position = Vector2(0, 20)
	assert_true(um.issue_order(a, Order.investigate(t)))
	var hostile_base := _unit()
	hostile_base.faction = "RED"
	assert_true(not av.request_return(a, hostile_base))
	assert_eq(a.investigation_track, t, "rejected recovery cannot silently cancel investigation")
	a.fuel_s = av.return_fuel_required(a, base) - 1
	av.tick(1.0, 1.0)
	assert_true(a.returning)
	assert_eq(a.investigation_track, null, "bingo return supersedes pursuit immediately")
	var recovery_route := a.waypoints.duplicate()
	um.tick(0.25)
	assert_eq(a.waypoints, recovery_route, "investigation must not override aviation's chosen route")
	av.free()
	um.free()
