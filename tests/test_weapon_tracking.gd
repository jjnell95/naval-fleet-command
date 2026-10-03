extends TestCase
## Flight geometry and the lifecycle of the detected weapon picture.


func _unit(faction := "BLUE", position := Vector2.ZERO, linked := true) -> Unit:
	var u := Unit.new()
	u.spec = PlatformSpec.new()
	u.spec.has_datalink = linked
	u.faction = faction
	u.position = position
	u.health = 100.0
	return u


func _round(target: Unit, terminal := true) -> Weapon:
	var w := Weapon.new()
	w.id = 71
	w.spec = WeaponSpec.new()
	w.spec.speed_kn = 7200.0  # two nautical miles per second: deliberately crosses a whole basket
	w.spec.max_range_nm = 10.0
	w.spec.turn_rate_deg_s = 0.0
	w.spec.seeker_range_nm = 0.1
	w.spec.base_pk = 1.0
	w.spec.damage = 20.0
	w.faction = "BLUE"
	w.aim_point = target.position
	if terminal:
		w.phase = Weapon.Phase.TERMINAL
		w.acquired = target
	return w


func _manager(target: Unit, w: Weapon) -> WeaponManager:
	Terrain.clear()
	var wm := WeaponManager.new()
	# Interception is capped at 95% (Combat.intercept_probability), so an unseeded manager made
	# the crossing-shot test fail about one run in twenty. A fixed seed keeps the geometry under test.
	wm.rng.seed = 7
	wm.unit_manager = UnitManager.new()
	wm.unit_manager.add_unit(target)
	wm.in_flight.append(w)
	return wm


func _cleanup(wm: WeaponManager) -> void:
	wm.clear()
	wm.unit_manager.free()
	wm.free()


func test_fast_round_acquires_and_hits_a_target_crossed_during_the_tick() -> void:
	var target := _unit("RED", Vector2(0, 1))
	var w := _round(target, false)
	var wm := _manager(target, w)
	wm.tick(1.0, 1.0)
	assert_eq(w.dead_reason, "HIT", "a whole seeker basket crossed between ticks still acquires")
	assert_near(target.health, 80.0)
	_cleanup(wm)


func test_fast_round_cannot_damage_a_ship_passed_abeam() -> void:
	var target := _unit("RED", Vector2(0.5, 1))
	var w := _round(target)
	var wm := _manager(target, w)
	wm.tick(1.0, 1.0)
	assert_eq(w.phase, Weapon.Phase.TERMINAL, "speed must not enlarge the impact radius")
	assert_near(target.health, 100.0)
	_cleanup(wm)


func test_valid_last_step_hit_precedes_range_exhaustion() -> void:
	var target := _unit("RED", Vector2(0, 2))
	var w := _round(target)
	w.position = Vector2(0, 1.8)
	w.distance_flown_nm = 1.8
	w.spec.max_range_nm = 2.0
	var wm := _manager(target, w)
	wm.tick(1.0, 1.0)
	assert_eq(w.dead_reason, "HIT", "a target at the permitted range remains reachable")
	assert_near(w.distance_flown_nm, 2.0)
	assert_near(w.position.y, 2.0)
	_cleanup(wm)


func test_travel_is_clipped_to_remaining_range() -> void:
	var target := _unit("RED", Vector2(0, 2.2))
	var w := _round(target)
	w.position = Vector2(0, 1.8)
	w.distance_flown_nm = 1.8
	w.spec.max_range_nm = 2.0
	var wm := _manager(target, w)
	wm.tick(1.0, 1.0)
	assert_eq(w.dead_reason, "RANGE EXHAUSTED")
	assert_near(w.position.y, 2.0, 0.001, "a coarse tick cannot grant another full step of range")
	assert_near(target.health, 100.0)
	_cleanup(wm)


func test_torpedo_cannot_acquire_before_its_seeker_enables() -> void:
	var target := _unit("RED", Vector2(0, 1))
	var w := _round(target, false)
	w.spec.type = "torpedo"
	w.spec.run_to_enable_nm = 1.5
	w.aim_point = Vector2(0, 10)
	var wm := _manager(target, w)
	wm.tick(1.0, 1.0)
	assert_true(w.acquired == null, "the part of the step before run-out is not searched")
	assert_near(target.health, 100.0)
	_cleanup(wm)


func test_fast_interceptor_cannot_defeat_a_threat_passed_abeam() -> void:
	var target := _unit("RED", Vector2(0.5, 1))
	var threat := _round(target, false)
	threat.faction = "RED"
	threat.position = target.position
	threat.spec.speed_kn = 0.0
	var interceptor := _round(target)
	interceptor.spec.type = "sam"
	interceptor.spec.target_types = PackedStringArray(["missile"])
	interceptor.intercept_target = threat
	var wm := _manager(target, interceptor)
	wm.tick(1.0, 1.0)
	assert_true(threat.phase != Weapon.Phase.DEAD)
	assert_true(interceptor.phase != Weapon.Phase.DEAD)
	_cleanup(wm)


func test_interceptor_leads_a_crossing_threat_into_its_actual_flight_path() -> void:
	var target := _unit("RED", Vector2(0, 1))
	var threat := _round(target, false)
	threat.faction = "RED"
	threat.position = Vector2(-1, 1)
	threat.heading_deg = 90.0
	threat.spec.speed_kn = 3600.0
	var interceptor := _round(target)
	interceptor.spec.type = "sam"
	interceptor.spec.target_types = PackedStringArray(["missile"])
	interceptor.spec.turn_rate_deg_s = 360.0
	interceptor.intercept_target = threat
	var wm := _manager(target, interceptor)
	wm.tick(1.0, 1.0)
	assert_eq(threat.dead_reason, "INTERCEPTED", "pure pursuit misses this crossing shot; lead guidance intersects it")
	assert_eq(interceptor.dead_reason, "INTERCEPT")
	_cleanup(wm)


func test_cruise_seeker_does_not_lock_a_ship_passed_before_activation() -> void:
	var target := _unit("RED", Vector2(0, 1))
	var w := _round(target, false)
	w.aim_point = Vector2(0, 2)
	var wm := _manager(target, w)
	wm.tick(1.0, 1.0)
	assert_true(w.acquired == null, "only travel inside the held aim-point basket can be searched")
	assert_near(target.health, 100.0)
	_cleanup(wm)


func test_acquisition_cannot_retroactively_hit_a_ship_already_passed() -> void:
	var target := _unit("RED", Vector2(0, 1.5))
	var w := _round(target, false)
	w.spec.seeker_range_nm = 0.2
	w.aim_point = Vector2(0, 1.8)
	var wm := _manager(target, w)
	wm.tick(1.0, 1.0)
	assert_true(w.acquired == null, "a ship already astern when search enables is outside the forward seeker cone")
	assert_near(target.health, 100.0, 0.001, "lock at y=1.6 cannot claim an earlier pass at y=1.5")
	_cleanup(wm)


func test_interceptor_cannot_hit_a_threat_after_its_range_expires() -> void:
	var target := _unit("RED", Vector2(0, 3))
	var threat := _round(target, false)
	threat.faction = "RED"
	threat.position = Vector2(0, 1.8)
	threat.spec.speed_kn = 3600.0
	threat.spec.max_range_nm = 2.0
	threat.distance_flown_nm = 1.8
	var interceptor := _round(target)
	interceptor.spec.type = "sam"
	interceptor.spec.target_types = PackedStringArray(["missile"])
	interceptor.intercept_target = threat
	var wm := _manager(target, interceptor)
	wm.tick(1.0, 1.0)
	assert_true(threat.phase != Weapon.Phase.DEAD, "an expiring inbound is not frozen in place for the remainder of the sweep")
	assert_true(interceptor.phase != Weapon.Phase.DEAD)
	_cleanup(wm)


func test_ordinary_impact_retires_detection_history_once() -> void:
	var target := _unit("RED", Vector2(0, 1))
	var w := _round(target)
	var wm := _manager(target, w)
	var tm := ThreatManager.new()
	tm.mark_detected("RED", w, 0.0)
	var resolved: Array[Weapon] = []
	wm.weapon_resolved.connect(func(round: Weapon) -> void:
		resolved.append(round)
		tm.forget(round))
	wm.tick(1.0, 1.0)
	wm.tick(1.0, 2.0)
	assert_eq(resolved.size(), 1)
	assert_true(not tm.is_detected("RED", w))
	assert_true(tm._first_seen["RED"].is_empty(), "ordinary losses must not accumulate historical weapon ids")
	assert_true(tm.get_threats("RED").is_empty())
	tm.free()
	_cleanup(wm)


func test_dead_weapons_are_never_detected_even_before_retirement() -> void:
	var w := _round(_unit("RED"))
	var tm := ThreatManager.new()
	tm.mark_detected("RED", w, 0.0)
	w.phase = Weapon.Phase.DEAD
	assert_true(not tm.is_detected("RED", w))
	tm.begin_cycle()
	tm.mark_detected("RED", w, 1.0)
	assert_true(tm._detected["RED"].is_empty())
	tm.free()


func test_observer_sharing_stays_within_its_faction() -> void:
	var recipient := _unit()
	var isolated := _unit("BLUE", Vector2.ZERO, false)
	var w := _round(_unit("RED"))
	var tm := ThreatManager.new()
	tm.mark_detected("RED", w, 0.0)  # faction-wide fixture observation for the other picture
	tm.mark_detected("BLUE", w, 0.0, isolated)
	tm.mark_detected("BLUE", w, 0.0, isolated)
	assert_true(tm.visible_to(isolated, w))
	assert_true(not tm.visible_to(recipient, w), "an opposing picture cannot supply a missing datalink")
	assert_eq(tm._observers["BLUE"][w.id].size(), 1)
	tm.free()


func test_indexed_lookup_selects_the_observers_actual_picture() -> void:
	var observer := _unit("BLUE", Vector2.ZERO, false)
	var target := _unit("RED", Vector2(0, 10))
	var tm := TrackManager.new()
	var c := SensorContact.make(target, target.position, 0.3, 0.5, 1.0, 10.0, "radar", observer)
	tm.observe_contact("BLUE", c, 1.0, 1.0)
	var local := tm.find_for(observer, target)
	assert_true(local != null)
	assert_true(not local.networked)
	assert_true(tm.find_track("BLUE", target) == null)
	observer.spec.has_datalink = true
	tm.observe_contact("BLUE", c, 2.0, 1.0)
	var shared := tm.find_for(observer, target)
	assert_true(shared == tm.find_track("BLUE", target))
	assert_true(shared != local, "the lookup must change pictures when the unit joins the link")
	tm.free()
