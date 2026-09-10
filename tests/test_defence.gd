extends TestCase

const DT := 0.25


func _platform(hp := 100.0) -> PlatformSpec:
	var p := PlatformSpec.new()
	p.short_name = "FFG Test"
	p.max_speed_kn = 30.0
	p.cruise_speed_kn = 15.0
	p.health = hp
	p.decoy_count = 12
	p.decoy_effectiveness = 0.35
	return p


func _radar(air_nm := 200.0, antenna_m := 20.0) -> SensorSpec:
	var s := SensorSpec.new()
	s.kind = "radar"
	s.range_surface_nm = 40.0
	s.range_air_nm = air_nm
	s.antenna_height_m = antenna_m
	return s


func _asm(difficulty := 1.0, altitude := 10.0, soft := 1.0) -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = "test_asm"
	w.display_name = "Test ASM"
	w.type = "asm"
	w.max_range_nm = 70.0
	w.speed_kn = 480.0
	w.turn_rate_deg_s = 15.0
	w.seeker_range_nm = 8.0
	w.damage = 40.0
	w.base_pk = 1.0
	w.defensive_difficulty = difficulty
	w.altitude_m = altitude
	w.soft_kill_resistance = soft
	w.signature_factor = 0.15
	return w


func _sam(id: String, max_range: float, pk: float, salvo := 2, kind := "sam") -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = id
	w.display_name = id
	w.type = kind
	w.target_types = PackedStringArray(["missile"])
	w.max_range_nm = max_range
	w.min_range_nm = 0.05
	w.speed_kn = 2400.0
	w.turn_rate_deg_s = 120.0
	w.damage = 0.0
	w.base_pk = pk
	w.salvo_default = salvo
	w.launch_interval_s = 1.0
	return w


func _ship(faction: String, pos: Vector2, hp := 100.0, defensive: Array = [], rounds := 32) -> Unit:
	var u := Unit.new()
	u.spec = _platform(hp)
	u.faction = faction
	u.callsign = "%s-1" % faction
	u.position = pos
	u.health = hp
	u.decoys = 0
	u.sensors.append(_radar())
	for spec: WeaponSpec in defensive:
		u.weapons.append(spec)
		u.magazines[spec.id] = rounds
	return u


func _harness(units: Array) -> Array:
	var um := UnitManager.new()
	for u: Unit in units:
		um.add_unit(u)
	var tm := ThreatManager.new()
	var wm := WeaponManager.new()
	wm.unit_manager = um
	wm.rng.seed = 11
	return [um, tm, wm]


## Hand-built inbound round, already locked onto `target`, so tests control the geometry exactly.
func _incoming(wm: WeaponManager, spec: WeaponSpec, faction: String, pos: Vector2, target: Unit, wid := 900) -> Weapon:
	var w := Weapon.new()
	w.id = wid
	w.spec = spec
	w.faction = faction
	w.position = pos
	w.acquired = target
	w.aim_point = target.position
	w.heading_deg = Geo.bearing_deg(pos, target.position)
	w.phase = Weapon.Phase.TERMINAL
	wm.in_flight.append(w)
	return w


func _run(h: Array, seconds: float, defend := true) -> void:
	var um: UnitManager = h[0]
	var tm: ThreatManager = h[1]
	var wm: WeaponManager = h[2]
	var now := 0.0
	var defence_accum := 0.0
	for i in int(seconds / DT):
		now += DT
		um.tick(DT)
		wm.tick(DT, now)
		defence_accum += DT
		if defence_accum >= 1.0:
			defence_accum -= 1.0
			# Stand in for the sensor cycle: everything in flight is seen by the other side.
			tm.begin_cycle()
			for w: Weapon in wm.in_flight:
				if w.intercept_target == null:
					for u in um.units:
						if u.faction != w.faction:
							tm.mark_detected(u.faction, w, now)
			if defend:
				AirDefence.run_cycle(um, tm, wm, now)


func _cleanup(h: Array) -> void:
	h[1].free()
	h[2].free()
	h[0].free()


# --- Detection ---------------------------------------------------------------------------

func test_sea_skimmer_is_detected_far_later_than_a_high_flier() -> void:
	var sensor := _radar(200.0, 20.0)
	var skimmer := Detection.weapon_detection_range_nm(sensor, _asm(1.0, 10.0))
	var high := Detection.weapon_detection_range_nm(sensor, _asm(1.0, 3000.0))
	assert_near(skimmer, 2.23 * (sqrt(20.0) + sqrt(10.0)), 0.05, "sea skimmer is horizon-limited")
	assert_near(high, 30.0, 0.05, "high flier is limited by radar power, not the horizon")
	assert_true(high > skimmer * 1.5, "altitude buys warning time")


func test_silent_ship_detects_no_incoming() -> void:
	var u := _ship("BLUE", Vector2.ZERO)
	assert_true(Detection.best_weapon_detection_nm(u, _asm()) > 0.0)
	u.radar_on = false
	assert_near(Detection.best_weapon_detection_nm(u, _asm()), 0.0, 1e-6, "no emissions, no warning")


# --- Threat geometry ---------------------------------------------------------------------

func test_closest_approach_distinguishes_inbound_from_passing() -> void:
	var u := _ship("BLUE", Vector2.ZERO)
	var h := _harness([u])
	var inbound := _incoming(h[2], _asm(), "RED", Vector2(0.0, 10.0), u)
	var cpa := AirDefence.closest_approach(u, inbound)
	assert_near(cpa["cpa_nm"], 0.0, 0.01, "a round aimed at the ship closes to zero")
	assert_true(cpa["time_s"] > 0.0)
	assert_true(AirDefence.is_inbound(u, inbound))

	var passing := Weapon.new()
	passing.id = 901
	passing.spec = _asm()
	passing.faction = "RED"
	passing.position = Vector2(20.0, 10.0)
	passing.heading_deg = 0.0  # heading north, 20 nm to the east
	assert_true(not AirDefence.is_inbound(u, passing), "a round passing 20 nm clear is not my problem")
	_cleanup(h)


func test_interceptors_are_not_treated_as_threats() -> void:
	var u := _ship("BLUE", Vector2.ZERO)
	var h := _harness([u])
	var sam := Weapon.new()
	sam.id = 902
	sam.spec = _sam("essm", 25.0, 0.8)
	sam.faction = "RED"
	sam.position = Vector2(0.0, 5.0)
	sam.intercept_target = _incoming(h[2], _asm(), "RED", Vector2(0.0, 10.0), u)
	assert_true(not AirDefence.is_inbound(u, sam), "SAMs are not anti-ship rounds")
	_cleanup(h)


# --- Interception ------------------------------------------------------------------------

func test_intercept_probability_scales_with_difficulty() -> void:
	var essm := _sam("essm", 25.0, 0.8)
	assert_near(Combat.intercept_probability(essm, _asm(1.0)), 0.8, 1e-4)
	assert_near(Combat.intercept_probability(essm, _asm(1.5)), 0.5333, 1e-3, "a harder round is harder to stop")
	assert_true(Combat.intercept_probability(essm, _asm(10.0)) >= 0.05, "probability stays clamped above zero")


func test_air_defence_stops_an_inbound_round() -> void:
	var ship := _ship("BLUE", Vector2.ZERO, 100.0, [_sam("essm", 25.0, 1.0)])
	var h := _harness([ship])
	var inbound := _incoming(h[2], _asm(), "RED", Vector2(0.0, 12.0), ship)
	_run(h, 120.0)
	assert_eq(inbound.phase, Weapon.Phase.DEAD)
	assert_eq(inbound.dead_reason, "INTERCEPTED")
	assert_near(ship.health, 100.0, 1e-3, "ship undamaged")
	assert_true(ship.magazine_count("essm") < 32, "interceptors were expended")
	_cleanup(h)


func test_round_gets_through_when_interception_fails() -> void:
	var ship := _ship("BLUE", Vector2.ZERO, 100.0, [_sam("essm", 25.0, 0.0)])
	var h := _harness([ship])
	var inbound := _incoming(h[2], _asm(), "RED", Vector2(0.0, 12.0), ship)
	_run(h, 120.0)
	assert_eq(inbound.phase, Weapon.Phase.DEAD)
	assert_near(ship.health, 60.0, 1e-3, "a leaker still does its damage")
	_cleanup(h)


func test_defence_is_automatic_without_any_order() -> void:
	var ship := _ship("BLUE", Vector2.ZERO, 100.0, [_sam("essm", 25.0, 1.0)])
	var h := _harness([ship])
	_incoming(h[2], _asm(), "RED", Vector2(0.0, 15.0), ship)
	# No Order is ever issued in this test.
	_run(h, 60.0)
	assert_true(ship.magazine_count("essm") < 32, "the ship defended itself unprompted")
	_cleanup(h)


func test_undefended_ship_takes_the_hit() -> void:
	var ship := _ship("BLUE", Vector2.ZERO, 100.0, [])
	var h := _harness([ship])
	_incoming(h[2], _asm(), "RED", Vector2(0.0, 12.0), ship)
	_run(h, 120.0)
	assert_near(ship.health, 60.0, 1e-3, "no interceptors, no defence")
	_cleanup(h)


func test_empty_defensive_magazine_cannot_engage() -> void:
	var ship := _ship("BLUE", Vector2.ZERO, 100.0, [_sam("essm", 25.0, 1.0)], 0)
	var h := _harness([ship])
	_incoming(h[2], _asm(), "RED", Vector2(0.0, 12.0), ship)
	_run(h, 120.0)
	assert_near(ship.health, 60.0, 1e-3, "an empty launcher defends nothing")
	assert_eq(ship.magazine_count("essm"), 0)
	_cleanup(h)


func test_outer_layer_shoots_first() -> void:
	var long_sam := _sam("long", 25.0, 0.0)  # always misses, so the inner layer still gets a turn
	var ciws := _sam("ciws", 1.2, 1.0, 3, "ciws")
	var ship := _ship("BLUE", Vector2.ZERO, 100.0, [long_sam, ciws])
	var h := _harness([ship])
	var inbound := _incoming(h[2], _asm(), "RED", Vector2(0.0, 20.0), ship)
	# One cycle at 20 nm: only the long-range layer is in range.
	var tm: ThreatManager = h[1]
	tm.mark_detected("BLUE", inbound, 0.0)
	AirDefence.run_cycle(h[0], tm, h[2], 0.0)
	assert_true(ship.magazine_count("long") < 32, "outer layer engaged")
	assert_eq(ship.magazine_count("ciws"), 32, "close-in layer held its fire at 20 nm")
	# Let it run in: the outer layer misses and the close-in layer finishes the job.
	_run(h, 200.0)
	assert_eq(inbound.dead_reason, "INTERCEPTED")
	assert_true(ship.magazine_count("ciws") < 32, "close-in layer engaged once the round closed")
	assert_near(ship.health, 100.0, 1e-3)
	_cleanup(h)


func test_decoy_can_defeat_a_seeker() -> void:
	var ship := _ship("BLUE", Vector2.ZERO, 100.0, [])
	ship.decoys = 4
	ship.spec.decoy_effectiveness = 1.0  # forced success, to test the mechanism not the dice
	var h := _harness([ship])
	var inbound := _incoming(h[2], _asm(1.0, 10.0, 1.0), "RED", Vector2(0.0, 2.0), ship)
	_run(h, 60.0)
	assert_eq(inbound.dead_reason, "DECOYED")
	assert_eq(ship.decoys, 3, "one decoy salvo consumed")
	assert_near(ship.health, 100.0, 1e-3)
	_cleanup(h)


func test_decoy_only_attempted_once_per_round() -> void:
	var ship := _ship("BLUE", Vector2.ZERO, 100.0, [])
	ship.decoys = 4
	ship.spec.decoy_effectiveness = 0.0  # always fails
	var h := _harness([ship])
	_incoming(h[2], _asm(), "RED", Vector2(0.0, 2.0), ship)
	_run(h, 60.0)
	assert_eq(ship.decoys, 3, "a failed decoy is not retried against the same round")
	assert_near(ship.health, 60.0, 1e-3)
	_cleanup(h)


# --- Data --------------------------------------------------------------------------------

func test_shipped_defensive_data_loads() -> void:
	for wid in ["sm2_family", "essm_family", "phalanx_ciws", "redut_family", "ak630_ciws"]:
		var w := DataDB.weapon(wid)
		assert_true(w != null, "%s loads" % wid)
		if w != null:
			assert_true(w.is_interceptor(), "%s is an interceptor" % wid)
			assert_true(w.target_types.has("missile"), "%s engages missiles" % wid)
			assert_true(w.max_range_nm > 0.0 and w.base_pk > 0.0)
	var burke := DataDB.platform("usn_ddg_arleigh_burke_iia")
	assert_true(burke != null)
	if burke != null:
		assert_true(burke.weapon_loadout.has("essm_family"), "Burke carries a medium layer")
		assert_true(burke.weapon_loadout.has("phalanx_ciws"), "Burke carries a close-in layer")
		assert_true(burke.decoy_count > 0)
	var nansen := DataDB.platform("rnon_ffg_fridtjof_nansen")
	if nansen != null:
		assert_true(not nansen.weapon_loadout.has("phalanx_ciws"), "Nansen deliberately has no close-in layer")


func test_defensive_weapons_are_ordered_outermost_first() -> void:
	var ship := _ship("BLUE", Vector2.ZERO, 100.0, [_sam("ciws", 1.2, 0.5, 3, "ciws"), _sam("long", 45.0, 0.7), _sam("medium", 25.0, 0.78)])
	var order := ship.defensive_weapons()
	assert_eq(order.size(), 3)
	assert_eq(order[0].id, "long")
	assert_eq(order[1].id, "medium")
	assert_eq(order[2].id, "ciws")
	assert_true(ship.offensive_weapons().is_empty(), "interceptors never appear as strike options")


func test_escort_defends_a_consort() -> void:
	# A well-armed escort in company with a thin-skinned ship that has no interceptors at all.
	var escort := _ship("BLUE", Vector2(2.0, 0.0), 110.0, [_sam("essm", 25.0, 1.0)])
	var consort := _ship("BLUE", Vector2.ZERO, 85.0, [])
	var h := _harness([escort, consort])
	var inbound := _incoming(h[2], _asm(), "RED", Vector2(0.0, 14.0), consort)
	_run(h, 140.0)
	assert_eq(inbound.dead_reason, "INTERCEPTED", "the escort shot down a round aimed at its consort")
	assert_true(escort.magazine_count("essm") < 32, "the escort spent the interceptors")
	assert_near(consort.health, 85.0, 1e-3, "consort undamaged")
	_cleanup(h)


func test_rounds_threatening_nobody_are_ignored() -> void:
	var ship := _ship("BLUE", Vector2.ZERO, 100.0, [_sam("essm", 25.0, 1.0)])
	var h := _harness([ship])
	var passing := Weapon.new()
	passing.id = 950
	passing.spec = _asm()
	passing.faction = "RED"
	passing.position = Vector2(15.0, 0.0)
	passing.heading_deg = 90.0  # heading due east, straight away from the ship
	passing.aim_point = Vector2(70.0, 0.0)
	h[2].in_flight.append(passing)
	_run(h, 60.0)
	assert_eq(ship.magazine_count("essm"), 32, "no interceptors wasted on a round going elsewhere")
	_cleanup(h)
