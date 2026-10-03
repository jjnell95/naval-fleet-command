extends TestCase


func _boat() -> Unit:
	Terrain.clear()
	Bathymetry.clear()
	var u := Unit.new()
	u.spec = DataDB.platform("usn_ssn_virginia")
	u.faction = "BLUE"
	u.callsign = "Test boat"
	u.depth_m = 120.0
	u.ordered_depth_m = 120.0
	u.heading_deg = 90.0
	u.ordered_heading_deg = 90.0
	u.speed_kn = 8.0
	u.ordered_speed_kn = 8.0
	for id in u.spec.sensor_ids:
		u.sensors.append(DataDB.sensor(id))
	return u


func _manager(u: Unit) -> UnitManager:
	var um := UnitManager.new()
	um.add_unit(u)
	um.configure_submarine_comms("BLUE", true)
	return um


func test_deep_player_orders_queue_and_crew_task_continues_without_live_position_report() -> void:
	var u := _boat()
	var um := _manager(u)
	var destination := Vector2(20, 5)
	var order := Order.move(destination)
	assert_true(um.issue_order(u, order))
	assert_true(order.receipt.contains("Queued"))
	assert_eq(u.comms_pending.size(), 1)
	assert_true(u.waypoints.is_empty(), "shore order has not yet reached the boat")
	var crew := Order.set_speed(10.0)
	crew.origin = "crew"
	assert_true(um.issue_order(u, crew))
	assert_eq(u.ordered_speed_kn, 10.0, "crew remains autonomous")
	um.tick(15.0)
	assert_true(u.position != Vector2.ZERO, "existing motion continues")
	assert_eq(SubmarineComms.reported_position(u), Vector2.ZERO, "plot stays at last report")
	assert_true(not u.datalink_connected())
	u.depth_m = SubmarineComms.DEPTH_M
	um.tick(0.0)
	assert_eq(u.comms_pending.size(), 0)
	assert_eq(u.waypoints[0], destination)
	assert_true(u.datalink_connected())
	assert_eq(SubmarineComms.reported_position(u), u.position)
	um.free()


func test_scheduled_checkin_ascends_reports_then_returns_to_old_depth_and_keeps_station() -> void:
	var u := _boat()
	u.waypoints.assign([Vector2(20, 5), Vector2(20, 10), Vector2(5, 10)])
	u.patrol_active = true
	var original := u.waypoints.duplicate()
	var um := _manager(u)
	u.comms_next_check_s = 5.0
	um.tick(5.0)
	assert_eq(u.comms_phase, "ascending")
	assert_eq(u.ordered_depth_m, SubmarineComms.DEPTH_M)
	assert_eq(u.waypoints, original)
	for i in 300:
		um.tick(0.5)
		if u.comms_phase == "reporting": break
	assert_eq(u.comms_phase, "reporting")
	assert_true(u.comms_last_report_s > 5.0)
	assert_true(u.comms_window_until_s > um.now_s)
	um.tick(SubmarineComms.WINDOW_S)
	assert_eq(u.comms_phase, "submerged")
	assert_eq(u.ordered_depth_m, 120.0)
	assert_true(u.patrol_active, "check-in does not replace a standing mission")
	assert_eq(u.waypoints, original)
	um.free()


func test_on_demand_summons_does_not_deliver_full_orders_until_communication_depth() -> void:
	var u := _boat()
	var um := _manager(u)
	u.comms_interval_s = 0.0
	u.comms_next_check_s = -1.0
	assert_true(um.issue_order(u, Order.set_speed(12.0)))
	um.tick(100.0)
	assert_eq(u.comms_phase, "submerged")
	assert_eq(u.comms_pending.size(), 1)
	assert_true(um.issue_order(u, Order.request_sub_checkin()))
	assert_eq(u.comms_phase, "ascending")
	assert_eq(u.ordered_speed_kn, 8.0)
	u.depth_m = SubmarineComms.DEPTH_M
	um.tick(0.0)
	assert_eq(u.ordered_speed_kn, 12.0)
	assert_eq(u.comms_pending.size(), 0)
	um.free()


func test_queued_depth_and_interval_orders_wait_for_window_then_override_old_depth() -> void:
	var u := _boat()
	var um := _manager(u)
	assert_true(um.issue_order(u, Order.set_depth(200.0)))
	assert_true(um.issue_order(u, Order.set_sub_comms_interval(3600.0)))
	assert_eq(u.comms_interval_s, 7200.0)
	assert_true(um.issue_order(u, Order.request_sub_checkin()))
	u.depth_m = SubmarineComms.DEPTH_M
	um.tick(0.0)
	assert_eq(u.comms_interval_s, 3600.0)
	assert_eq(u.ordered_depth_m, SubmarineComms.DEPTH_M, "hold full window before diving")
	assert_eq(u.comms_return_depth_m, 200.0)
	um.tick(SubmarineComms.WINDOW_S)
	assert_eq(u.ordered_depth_m, 200.0, "new depth wins over the pre-window depth")
	um.free()


func test_disabling_windows_delivers_pending_orders_and_legacy_options_keep_convenience() -> void:
	var u := _boat()
	var um := _manager(u)
	assert_true(um.issue_order(u, Order.set_speed(15.0)))
	um.configure_submarine_comms("BLUE", false)
	assert_eq(u.comms_pending.size(), 0)
	assert_eq(u.ordered_speed_kn, 15.0)
	assert_true(SubmarineComms.connected(u))
	assert_true(not GameOptions.normal().submarine_comms)
	assert_true(GameOptions.classic().submarine_comms)
	var legacy := GameOptions.classic().to_dict()
	legacy.erase("submarine_comms")
	assert_true(not GameOptions.from_dict(legacy).submarine_comms)
	assert_eq(GameOptions.from_dict(legacy).preset(), GameOptions.CUSTOM)
	um.free()


func test_queue_copies_circuits_and_survives_snapshot_encoding_with_reference_identity() -> void:
	var u := _boat()
	var um := _manager(u)
	var route: Array[Vector2] = [Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)]
	var o := Order.patrol(route)
	assert_true(um.issue_order(u, o))
	o.route.clear()
	assert_eq(u.comms_pending[0]["route"].size(), 3, "submitted orders cannot be mutated through their caller")
	var refs := SimSnapshot.Refs.new()
	var data := SimSnapshot.fields_of(u, SimSnapshot.UNIT_SKIP, refs)
	assert_true(refs.errors.is_empty(), "no unsupported Order object in snapshot")
	var saved: Dictionary = bytes_to_var(var_to_bytes(data))
	var back := _boat()
	# Exercise exactly the field decoding and default-preservation behavior used by restore.
	var decoder := SimSnapshot.Refs.new()
	for key in saved:
		var current: Variant = back.get(key)
		var value: Variant = decoder.dec(saved[key])
		if current is Array and value is Array: current.assign(value)
		else: back.set(key, value)
	assert_true(decoder.errors.is_empty())
	assert_eq(back.comms_pending.size(), 1)
	assert_eq(back.comms_next_check_s, u.comms_next_check_s)
	var restored_um := UnitManager.new()
	restored_um.add_unit(back)
	back.depth_m = SubmarineComms.DEPTH_M
	restored_um.tick(0.0)
	assert_eq(back.waypoints, route)
	assert_true(back.patrol_active)
	restored_um.free()
	um.free()


func test_checkin_orders_refuse_non_submarines_and_invalid_intervals() -> void:
	var u := _boat()
	var um := _manager(u)
	assert_true(not um.issue_order(u, Order.set_sub_comms_interval(50.0)))
	var ship := Unit.new()
	ship.spec = DataDB.platform("usn_ddg_burke_iii")
	assert_true(not um.issue_order(ship, Order.request_sub_checkin()))
	assert_true(not um.issue_order(ship, Order.set_sub_comms_interval(7200.0)))
	um.free()


func test_order_that_becomes_invalid_before_delivery_is_reported_without_replacing_task() -> void:
	var u := _boat()
	var um := _manager(u)
	var track := Track.new()
	track.owner_faction = "BLUE"
	track.domain = "surface"
	track.position = Vector2(20, 20)
	assert_true(um.issue_order(u, Order.investigate(track)))
	assert_eq(u.comms_pending.size(), 1)
	track.status = Track.Status.LOST
	u.depth_m = SubmarineComms.DEPTH_M
	um.tick(0.0)
	assert_eq(u.comms_pending.size(), 0)
	assert_eq(u.investigation_track, null)
	assert_true(u.comms_note.contains("1 no longer executable"))
	um.free()


func test_saved_ascent_and_pending_orders_continue_identically_after_actual_restore() -> void:
	SimClock.set_paused(true)
	var sim := Simulation.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	assert_true(sim.load_scenario("res://data/scenarios/carrier_qualification.json"))
	# Isolate the command cycle in open water; the embedded scenario still exercises normal
	# save validation, catalogue references and the two-phase object restoration.
	sim.unit_manager.clear()
	sim.scenario["map"]["open_water"] = true
	sim.scenario["terrain"] = {}
	var u := _boat()
	Terrain.load_from(sim.scenario)
	Bathymetry.load_for(sim.scenario)
	u.position = Vector2(50, 50)
	sim.unit_manager.add_unit(u)
	sim.unit_manager.configure_submarine_comms("BLUE", true)
	assert_true(sim.unit_manager.issue_order(u, Order.move(Vector2(60, 60))))
	assert_true(sim.unit_manager.issue_order(u, Order.set_depth(180.0)))
	assert_true(sim.unit_manager.issue_order(u, Order.request_sub_checkin()))
	sim.unit_manager.tick(10.0)
	var saved := SimSnapshot.capture(sim)
	assert_eq(SimSnapshot.validate(saved), "")
	for i in 250: sim.unit_manager.tick(1.0)
	var expected := SimSnapshot.fields_of(u, SimSnapshot.UNIT_SKIP, SimSnapshot.Refs.new())
	assert_eq(sim.restore_snapshot(saved), "")
	u = sim.unit_manager.units[0]
	assert_eq(u.comms_pending.size(), 2)
	assert_eq(u.comms_phase, "ascending")
	for i in 250: sim.unit_manager.tick(1.0)
	var got := SimSnapshot.fields_of(u, SimSnapshot.UNIT_SKIP, SimSnapshot.Refs.new())
	# bottom_generation is already excluded by the same reflective snapshot field policy.
	for key in expected:
		assert_true(var_to_bytes(got[key]) == var_to_bytes(expected[key]), "restored field %s differs: %s vs %s" % [key, got[key], expected[key]])
	sim.unit_manager.clear()
	sim.free()


func test_new_group_attack_cannot_bypass_submarine_communication_through_surface_lead() -> void:
	var submarine := _boat()
	var um := _manager(submarine)
	var lead := Unit.new()
	lead.spec = DataDB.platform("usn_ddg_burke_iii")
	lead.faction = "BLUE"
	lead.callsign = "Surface lead"
	var manager := GroupAttackManager.new()
	manager.unit_manager = um
	var target := Track.new()
	target.owner_faction = "BLUE"
	var order := Order.group_attack([lead, submarine], [target], 4)
	assert_eq(manager.request(lead, order), null)
	assert_true(not order.execution_accepted)
	assert_true(order.receipt.contains("communication window") and order.receipt.contains(submarine.callsign))
	assert_true(manager.groups.is_empty(), "no internal crew ENGAGE may bypass the pending authorization")
	manager.free()
	um.free()


func test_reapplying_options_preserves_checkin_and_reenabling_starts_from_known_live_report() -> void:
	var u := _boat()
	var um := _manager(u)
	assert_true(um.issue_order(u, Order.set_speed(12.0)))
	assert_true(um.issue_order(u, Order.request_sub_checkin()))
	var deadline := u.comms_next_check_s
	var last_report := u.comms_last_report_s
	um.tick(5.0)
	um.configure_submarine_comms("BLUE", true)
	assert_eq(u.comms_next_check_s, deadline)
	assert_eq(u.comms_last_report_s, last_report)
	assert_eq(u.comms_phase, "ascending")
	assert_eq(u.comms_pending.size(), 1)
	u.depth_m = SubmarineComms.DEPTH_M
	um.tick(0.0)
	var window := u.comms_window_until_s
	um.configure_submarine_comms("BLUE", true)
	assert_eq(u.comms_window_until_s, window)
	um.configure_submarine_comms("BLUE", false)
	u.position = Vector2(30, 40)
	u.depth_m = 120.0
	um.now_s = 100.0
	um.configure_submarine_comms("BLUE", true)
	assert_eq(SubmarineComms.reported_position(u), Vector2(30, 40))
	assert_eq(u.comms_next_check_s, 7300.0)
	assert_eq(u.comms_last_report_s, 100.0)
	um.free()


func test_queued_commands_emit_no_execution_signal_and_nullified_target_is_rechecked() -> void:
	var u := _boat()
	var um := _manager(u)
	var received: Array = []
	um.order_issued.connect(func(_u: Unit, order: Order) -> void: received.append(order))
	var contact := Track.new()
	contact.owner_faction = "BLUE"
	assert_true(um.issue_order(u, Order.investigate(contact)))
	assert_true(received.is_empty(), "specialist managers and training receive no command yet")
	u.comms_pending[0]["track"] = null
	u.depth_m = SubmarineComms.DEPTH_M
	um.tick(0.0)
	assert_true(received.is_empty(), "a now-invalid order never reaches the execution signal")
	assert_true(u.comms_note.contains("1 no longer executable"))
	um.free()


func test_deep_standing_investigation_uses_own_contact_and_does_not_follow_unheard_shared_updates() -> void:
	var u := _boat()
	var um := _manager(u)
	var wm := WeaponManager.new()
	var tm := TrackManager.new()
	wm.track_manager = tm
	um.weapon_manager = wm
	var shared := Track.new()
	shared.id = "BLUE-1001"
	shared.owner_faction = "BLUE"
	shared.domain = "surface"
	shared.position = Vector2(10, 10)
	shared.networked = true
	var local := Track.new()
	local.id = shared.id
	local.owner_faction = "BLUE"
	local.domain = "surface"
	local.position = Vector2(8, 8)
	local.networked = false
	local.contributors[u] = 0.0
	tm._local_keys[u] = "local:test"
	tm._tracks["local:test"] = [local]
	u.depth_m = SubmarineComms.DEPTH_M
	assert_true(um.issue_order(u, Order.investigate(shared)))
	u.depth_m = 120.0
	um.tick(0.0)
	assert_true(u.investigation_track == local)
	shared.position = Vector2(100, 100)
	um.tick(0.0)
	assert_eq(u.waypoints[0], local.position, "crew follows its own held report")
	local.status = Track.Status.LOST
	um.tick(0.0)
	assert_eq(u.investigation_track, null)
	assert_eq(u.investigation_result, "Contact lost")
	um.weapon_manager = null
	wm.free()
	tm.clear()
	tm.free()
	um.free()


func test_deep_investigation_without_local_contact_does_not_use_shared_future_picture() -> void:
	var u := _boat()
	var um := _manager(u)
	var wm := WeaponManager.new()
	var tm := TrackManager.new()
	wm.track_manager = tm
	um.weapon_manager = wm
	var shared := Track.new()
	shared.owner_faction = "BLUE"
	shared.position = Vector2(10, 10)
	u.depth_m = SubmarineComms.DEPTH_M
	assert_true(um.issue_order(u, Order.investigate(shared)))
	u.depth_m = 120.0
	shared.position = Vector2(100, 100)
	um.tick(0.0)
	assert_eq(u.investigation_track, null)
	assert_eq(u.investigation_result, "Contact is not available to this unit")
	um.weapon_manager = null
	wm.free()
	tm.free()
	um.free()


func test_new_engagement_starts_communication_schedule_at_zero_not_previous_watch_time() -> void:
	var first := _boat()
	var um := _manager(first)
	um.tick(500.0)
	assert_eq(um.now_s, 500.0)
	um.clear()
	assert_eq(um.now_s, 0.0)
	var next := _boat()
	um.add_unit(next)
	# The shell's unit_added hook uses this manager clock during scenario population;
	# SimClock may still hold the previous engagement until load_scenario finishes.
	SubmarineComms.configure(next, true, um.now_s)
	assert_eq(next.comms_last_report_s, 0.0)
	assert_eq(next.comms_next_check_s, 7200.0)
	um.configure_submarine_comms("BLUE", true)
	assert_eq(next.comms_next_check_s, 7200.0, "applying doctrine after population keeps the new schedule")
	um.free()
