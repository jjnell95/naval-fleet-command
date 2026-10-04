extends TestCase
## Air combat that behaves like air combat: a missile is not fired where an aircraft can simply
## outrun it, a hit brings an aircraft down, an aircraft's countermeasures work against a ship's
## SAM, nobody keeps firing at an aircraft already seen to fall, and a fighter can recognise
## another aircraft on its own radar at close range.


func _aam(range_nm := 45.0, speed := 2100.0) -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = "test_aam"
	w.type = "aam"
	w.guidance = "active_radar"
	w.target_types = PackedStringArray(["air"])
	w.max_range_nm = range_nm
	w.min_range_nm = 0.5
	w.speed_kn = speed
	w.seeker_range_nm = 5.0
	w.base_pk = 0.6
	w.damage = 10.0
	w.salvo_default = 2
	return w


func _fighter(faction: String, pos: Vector2, weapons: Array = []) -> Unit:
	var u := Unit.new()
	u.spec = PlatformSpec.new()
	u.spec.domain = "air"
	u.spec.max_speed_kn = 1000.0
	u.spec.cruise_speed_kn = 480.0
	u.spec.health = 30.0
	u.faction = faction
	u.callsign = faction
	u.position = pos
	u.health = 30.0
	u.flight_state = Unit.FlightState.AIRBORNE
	u.altitude_m = 9000.0
	for w: WeaponSpec in weapons:
		u.weapons.append(w)
		u.magazines[w.id] = 4
	return u


func _air_track(target: Unit, speed := 0.0, course := 0.0) -> Track:
	var t := Track.new()
	t.id = "T2001"
	t.owner_faction = "BLUE"
	t.truth = target
	t.position = target.position
	t.status = Track.Status.ACTIVE
	t.domain = "air"
	t.identity = "HOSTILE"
	t.classification = Track.Classification.SURFACE
	t.altitude_m = 9000.0
	t.speed_kn = speed
	t.course_deg = course
	t.has_kinematics = speed > 0.0
	return t


func test_a_missile_is_not_fired_where_the_aircraft_can_outrun_it() -> void:
	var aam := _aam(45.0, 2100.0)
	var shooter := _fighter("BLUE", Vector2.ZERO, [aam])
	var bandit := _fighter("RED", Vector2(0, 40))
	# Running away at 900 kn for the whole 77 s flight: the usable reach is 45 - 19 ≈ 26 nm.
	var running := _air_track(bandit, 900.0, 0.0)
	var check := Combat.check_engagement(shooter, aam, running)
	assert_true(not check["ok"])
	assert_true(str(check["reason"]) in ["TARGET CAN OUTRUN THE SHOT", "INTERCEPT BEYOND WEAPON RANGE"], str(check["reason"]))
	bandit.position = Vector2(0, 20)
	assert_true(Combat.check_engagement(shooter, aam, _air_track(bandit, 900.0, 0.0))["ok"], "inside the no-escape reach it fires")
	assert_near(Combat.air_no_escape_range_nm(aam, _air_track(bandit, 2000.0), shooter.position), Combat.AIR_ESCAPE_FLOOR * 45.0, 1e-6, "never below the floor")
	assert_near(Combat.air_no_escape_range_nm(aam, _air_track(bandit, 0.0), shooter.position), 45.0, 1e-6, "a target with no known speed costs nothing")


func test_a_position_worked_up_from_bearings_is_no_solution_on_an_aircraft() -> void:
	var aam := _aam()
	var shooter := _fighter("BLUE", Vector2.ZERO, [aam])
	var t := _air_track(_fighter("RED", Vector2(0, 15)))
	t.bearing_only = true
	t.tma_quality = 0.9
	assert_eq(Combat.check_engagement(shooter, aam, t)["reason"], "NO RADAR FIX ON AIRCRAFT")


func test_a_hit_brings_an_aircraft_down_whatever_the_warhead_rating() -> void:
	var wm := WeaponManager.new()
	var um := UnitManager.new()
	wm.unit_manager = um
	var bandit := _fighter("RED", Vector2.ZERO)
	bandit.health = 40.0
	um.add_unit(bandit)
	var w := Weapon.new()
	w.spec = _aam()
	w.spec.base_pk = 1.0
	w.faction = "BLUE"
	w.acquired = bandit
	wm.rng.seed = 1
	wm._resolve_impact(w)
	assert_true(not bandit.alive, "a 10-point warhead still downs a 40-point aircraft")
	wm.free()
	um.free()


func test_an_aircraft_can_decoy_a_ships_command_guided_sam() -> void:
	var sam := WeaponSpec.new()
	sam.type = "sam"
	sam.guidance = "fire_control_directed"
	assert_eq(sam.seeker_band(), "radar")


func test_close_range_radar_gives_a_probable_type_on_an_aircraft_but_not_on_a_ship() -> void:
	var tm := TrackManager.new()
	tm.configure_recognition({"BLUE": {"test_fighter": "HOSTILE"}})
	var bandit := _fighter("RED", Vector2(0, 20))
	bandit.spec.id = "test_fighter"
	bandit.spec.short_name = "Test Fighter"
	for second in int(TrackManager.RADAR_RECOGNITION_S) + 2:
		tm.observe_contact("BLUE", SensorContact.make(bandit, bandit.position, 0.3, 1.0, 1.0, 20.0, "radar"), float(second), 1.0)
	var t := tm.find_track("BLUE", bandit)
	assert_eq(t.classification, Track.Classification.CLASS_KNOWN)
	assert_eq(t.class_evidence, "Radar recognition")
	assert_eq(t.identity, "HOSTILE", "the recognition brief names the type's side")
	var far := _fighter("RED", Vector2(0, 120))
	far.spec.id = "test_fighter"
	for second in int(TrackManager.RADAR_RECOGNITION_S) + 2:
		tm.observe_contact("BLUE", SensorContact.make(far, far.position, 0.3, 1.0, 1.0, 120.0, "radar"), float(second), 1.0)
	assert_true(tm.find_track("BLUE", far).classification < Track.Classification.CLASS_KNOWN, "too far for a type from the return")
	tm.free()


func test_the_ai_does_not_fire_at_an_aircraft_the_side_has_seen_go_down() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/systems/ai_controller.gd")
	assert_true(src.contains("t.damage_estimate >= 100.0"), "the engagement picker skips recorded kills")
	assert_eq(AIController.AIR_ROUNDS_IN_FLIGHT, 2)


func test_ships_do_not_spend_interceptors_on_a_missile_chasing_an_aircraft() -> void:
	var sam := WeaponSpec.new()
	sam.id = "area"
	sam.type = "sam"
	sam.target_types = PackedStringArray(["missile", "air"])
	sam.max_range_nm = 40.0
	sam.min_range_nm = 0.1
	sam.speed_kn = 2000.0
	sam.base_pk = 1.0
	sam.salvo_default = 2
	var ship := Unit.new()
	ship.spec = PlatformSpec.new()
	ship.spec.fire_control_channels = 4
	ship.faction = "BLUE"
	ship.position = Vector2.ZERO
	ship.health = 100.0
	ship.weapons.append(sam)
	ship.magazines["area"] = 10
	var fighter := _fighter("BLUE", Vector2(0, 5))
	var um := UnitManager.new()
	um.add_unit(ship)
	um.add_unit(fighter)
	var tm := ThreatManager.new()
	var wm := WeaponManager.new()
	wm.unit_manager = um
	var aam := Weapon.new()
	aam.id = 77
	aam.spec = _aam()
	aam.faction = "RED"
	aam.position = Vector2(0, 15)
	aam.acquired = fighter
	aam.heading_deg = 180.0
	aam.phase = Weapon.Phase.TERMINAL
	wm.in_flight.append(aam)
	tm.mark_detected("BLUE", aam, 0.0)
	AirDefence.run_cycle(um, tm, wm, 0.0)
	assert_eq(ship.magazine_count("area"), 10, "the fighter beats it with countermeasures, not the ship's SAMs")
	tm.free()
	wm.free()
	um.free()


func test_an_aircraft_coming_straight_in_is_shot_from_further_out_than_one_running() -> void:
	var aam := _aam(45.0, 2100.0)
	var shooter := _fighter("BLUE", Vector2.ZERO, [aam])
	var bandit := _fighter("RED", Vector2(0, 33))
	var inbound := _air_track(bandit, 900.0, 180.0)  # heading south, straight at the shooter
	assert_true(Combat.check_engagement(shooter, aam, inbound)["ok"], "a closing target has not turned away yet")
	assert_true(not Combat.check_engagement(shooter, aam, _air_track(bandit, 900.0, 0.0))["ok"], "the same range on one already running is too far")


func test_a_kill_the_side_has_seen_drops_out_of_the_ai_picture() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/systems/ai_controller.gd")
	assert_true(src.contains("if t.identity == \"HOSTILE\" and t.damage_estimate >= 100.0:"), "killed hostiles are not chased")


func test_a_closing_aircraft_gets_a_lighter_margin_not_none() -> void:
	var aam := _aam(45.0, 2100.0)
	var shooter := _fighter("BLUE", Vector2.ZERO, [aam])
	var edge := _fighter("RED", Vector2(0, 44))
	assert_true(not Combat.check_engagement(shooter, aam, _air_track(edge, 900.0, 180.0))["ok"], "not at the very edge: it will turn once it sees the shot")
	var inside := _fighter("RED", Vector2(0, 34))
	assert_true(Combat.check_engagement(shooter, aam, _air_track(inside, 900.0, 180.0))["ok"])


func _known_track(platform_id: String, pos: Vector2, speed: float, course: float) -> Track:
	var spec := DataDB.platform(platform_id)
	var t := _air_track(_fighter("RED", pos), speed, course)
	t.classification = Track.Classification.CLASS_KNOWN
	t.known_class = spec.short_name
	t.known_category = spec.category
	return t


func test_a_slow_turning_bomber_is_shot_from_further_out_than_a_fighter() -> void:
	# Both coming straight in at 500 kn. The Tu-22M3 needs a minute to turn round and cannot open
	# the range before an SM-2 arrives; the Su-35 turns in a third of the time and runs.
	var sm2 := DataDB.weapon("sm2_family")
	var bomber := Combat.air_no_escape_range_nm(sm2, _known_track("rfn_bomber_tu22m3", Vector2(0, 50), 500.0, 180.0), Vector2.ZERO)
	var fighter := Combat.air_no_escape_range_nm(sm2, _known_track("rfn_fighter_su35s", Vector2(0, 50), 500.0, 180.0), Vector2.ZERO)
	assert_true(bomber > 40.0, "a bomber coming straight in is shot from near the full reach: %.1f" % bomber)
	assert_true(fighter < bomber - 5.0, "a fighter that can turn and run is not: %.1f" % fighter)
	var running := Combat.air_no_escape_range_nm(sm2, _known_track("rfn_bomber_tu22m3", Vector2(0, 50), 500.0, 0.0), Vector2.ZERO)
	assert_true(running < bomber, "one already running away is shot from closer in")


func test_the_no_escape_range_reads_the_plot_not_the_aircraft() -> void:
	var aam := _aam(45.0, 2100.0)
	var t := _known_track("rfn_bomber_tu22m3", Vector2(0, 30), 500.0, 180.0)
	var before := Combat.air_no_escape_range_nm(aam, t, Vector2.ZERO)
	t.truth.spec.turn_rate_deg_s = 90.0  # the real airframe's figures are never consulted
	t.truth.spec.max_speed_kn = 2000.0
	assert_near(Combat.air_no_escape_range_nm(aam, t, Vector2.ZERO), before, 1e-6)


class AirHarness:
	extends RefCounted
	var um: UnitManager
	var wm: WeaponManager
	var ai: AIController
	var orders: Array = []

	func free_all() -> void:
		ai.free()
		wm.free()
		um.free()


func _air_harness(fighter: Unit, bandit: Unit) -> AirHarness:
	var h := AirHarness.new()
	h.um = UnitManager.new()
	h.um.add_unit(fighter)
	h.um.add_unit(bandit)
	h.wm = WeaponManager.new()
	h.wm.unit_manager = h.um
	h.ai = AIController.new()
	h.ai.faction = fighter.faction
	h.ai.unit_manager = h.um
	h.ai.weapon_manager = h.wm
	h.um.order_issued.connect(func(_u: Unit, o: Order) -> void: h.orders.append(o))
	return h


func _ordered(h: AirHarness, type: Order.Type) -> Order:
	for o: Order in h.orders:
		if o.type == type:
			return o
	return null


func test_a_fighter_closes_at_dash_until_it_has_a_shot() -> void:
	var aam := _aam(45.0, 2100.0)
	var fighter := _fighter("BLUE", Vector2.ZERO, [aam])
	var bandit := _fighter("RED", Vector2(0, 60))
	var h := _air_harness(fighter, bandit)
	var t := _air_track(bandit, 480.0, 180.0)
	h.ai._fight_air(fighter, h.ai._board(fighter), t, 60.0, 0.0)
	assert_true(_ordered(h, Order.Type.MOVE) != null, "it flies at the contact")
	var speed := _ordered(h, Order.Type.SET_SPEED)
	assert_true(speed != null and speed.speed_kn > fighter.spec.cruise_speed_kn, "at dash")
	h.free_all()


func test_a_fighter_with_rounds_on_the_way_cranks_instead_of_turning_tail() -> void:
	var aam := _aam(45.0, 2100.0)
	var fighter := _fighter("BLUE", Vector2.ZERO, [aam])
	fighter.heading_deg = 10.0
	var bandit := _fighter("RED", Vector2(0, 30))
	var h := _air_harness(fighter, bandit)
	var t := _air_track(bandit, 480.0, 180.0)
	var round := Weapon.new()
	round.spec = aam
	round.shooter = fighter
	round.target_track = t
	h.wm.in_flight.append(round)
	h.ai._fight_air(fighter, h.ai._board(fighter), t, 30.0, 0.0)
	var course := _ordered(h, Order.Type.SET_COURSE)
	assert_true(course != null)
	assert_near(absf(Geo.heading_delta(0.0, course.heading_deg)), AIController.AIR_CRANK_DEG, 0.01, "the contact held well off the nose, not astern")
	h.free_all()


func _round_at(track: Track, aim: Vector2, heading: float) -> Weapon:
	var w := Weapon.new()
	w.spec = _aam(45.0, 2100.0)
	w.spec.seeker_half_angle_deg = 30.0
	w.faction = "BLUE"
	w.target_track = track
	w.position = aim - Geo.heading_to_vector(heading) * 0.5
	w.heading_deg = heading
	w.aim_point = aim
	w.distance_flown_nm = 20.0
	return w


func test_a_round_at_an_aircraft_that_finds_nothing_at_its_aim_point_searches_on() -> void:
	var um := UnitManager.new()
	var wm := WeaponManager.new()
	wm.unit_manager = um
	# The bandit turned after the last update: it is twelve miles beyond the aim point, on the line.
	var bandit := _fighter("RED", Vector2(0, 32))
	um.add_unit(bandit)
	var w := _round_at(_air_track(bandit), Vector2(0, 20), 0.0)
	wm.in_flight.append(w)
	for i in 40:
		wm._step(w, 0.5)
		if w.phase != Weapon.Phase.CRUISE:
			break
	assert_true(w.searching_on, "it flew past the aim point still searching")
	assert_eq(w.phase, Weapon.Phase.TERMINAL, "and found the aircraft further on")
	assert_true(w.acquired == bandit)
	wm.free()
	um.free()


func test_a_round_searching_on_that_never_finds_anything_ends_as_no_acquisition() -> void:
	var um := UnitManager.new()
	var wm := WeaponManager.new()
	wm.unit_manager = um
	um.add_unit(_fighter("RED", Vector2(40, 0)))
	var w := _round_at(_air_track(_fighter("RED", Vector2(0, 20))), Vector2(0, 20), 0.0)
	wm.in_flight.append(w)
	for i in 200:
		wm._step(w, 0.5)
		if w.phase == Weapon.Phase.DEAD:
			break
	assert_eq(w.dead_reason, "NO ACQUISITION")
	assert_near(w.distance_flown_nm, w.spec.max_range_nm, 0.01, "it searched until its fuel ran out")
	wm.free()
	um.free()
