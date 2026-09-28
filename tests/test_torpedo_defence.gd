extends TestCase
## Torpedo defence: acoustic decoys and anti-torpedo rounds, and chaff doing nothing to a torpedo.
## Each test builds its own geometry and forces the dice where it tests a mechanism.


func _hull(towed := false, expendables := 0, effectiveness := 0.3) -> PlatformSpec:
	var p := PlatformSpec.new()
	p.id = "test_hull"
	p.short_name = "DDG Test"
	p.max_speed_kn = 30.0
	p.health = 100.0
	p.decoy_count = 12
	p.decoy_effectiveness = 1.0  # chaff that would always work, if chaff worked on torpedoes
	p.torpedo_decoy = "Test decoy" if towed or expendables > 0 else ""
	p.towed_torpedo_decoy = towed
	p.torpedo_decoy_count = expendables
	p.torpedo_decoy_effectiveness = effectiveness
	return p


func _ship(spec: PlatformSpec, pos := Vector2.ZERO, speed_kn := 15.0, faction := "BLUE") -> Unit:
	var u := Unit.new()
	u.spec = spec
	u.faction = faction
	u.callsign = "Test %d" % randi()
	u.position = pos
	u.health = spec.health
	u.speed_kn = speed_kn
	u.decoys = spec.decoy_count
	u.torpedo_decoys = spec.torpedo_decoy_count
	return u


func _torpedo_spec() -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = "test_torpedo"
	w.display_name = "Test torpedo"
	w.type = "torpedo"
	w.profile = "subsurface"
	w.target_types = PackedStringArray(["surface", "subsurface"])
	w.speed_kn = 50.0
	w.max_range_nm = 20.0
	w.seeker_range_nm = 2.2
	w.soft_kill_resistance = 0.7
	return w


func _harness(units: Array, seed_value := 11) -> Array:
	var um := UnitManager.new()
	for u: Unit in units:
		um.add_unit(u)
	var tm := ThreatManager.new()
	var wm := WeaponManager.new()
	wm.unit_manager = um
	wm.rng.seed = seed_value
	return [um, tm, wm]


func _cleanup(h: Array) -> void:
	for node: Node in h:
		node.free()


## A torpedo already homing on `target` from `pos`, heard by `target`'s side.
func _homing(h: Array, target: Unit, pos: Vector2, wid := 700) -> Weapon:
	var w := Weapon.new()
	w.id = wid
	w.spec = _torpedo_spec()
	w.faction = "RED"
	w.position = pos
	w.acquired = target
	w.aim_point = target.position
	w.heading_deg = Geo.bearing_deg(pos, target.position)
	w.phase = Weapon.Phase.TERMINAL
	(h[2] as WeaponManager).in_flight.append(w)
	(h[1] as ThreatManager).mark_detected(target.faction, w, 0.0, target)
	return w


## A seed whose first draw is under one half, so a test that forces the odds high knows the dice agree.
func _lucky_seed() -> int:
	var probe := RandomNumberGenerator.new()
	for seed_value in range(1, 200):
		probe.seed = seed_value
		if probe.randf() < 0.5:
			return seed_value
	return 1


func test_chaff_does_nothing_to_a_torpedo() -> void:
	var ship := _ship(_hull())
	var h := _harness([ship])
	var torp := _homing(h, ship, Vector2(0.0, 1.0))
	AirDefence._try_decoy(ship, torp, h[2])
	assert_eq(ship.decoys, 12, "no chaff is spent on a torpedo")
	assert_eq(torp.phase, Weapon.Phase.TERMINAL, "and the torpedo keeps its lock")
	_cleanup(h)


func test_a_hull_with_no_countermeasures_has_only_its_speed() -> void:
	var ship := _ship(_hull(false, 0))
	var h := _harness([ship])
	var torp := _homing(h, ship, Vector2(0.0, 1.0))
	assert_eq(TorpedoDefence.run_cycle(h[0], h[1], h[2], 0.0), 0)
	assert_eq(torp.acquired, ship)
	_cleanup(h)


func test_a_towed_decoy_can_pull_a_torpedo_off_and_never_runs_out() -> void:
	var ship := _ship(_hull(true, 0, 10.0))  # the chance caps at MAX_DECOY_CHANCE
	var h := _harness([ship], _lucky_seed())
	var torp := _homing(h, ship, Vector2(0.0, 1.5))
	TorpedoDefence.run_cycle(h[0], h[1], h[2], 0.0)
	assert_eq(torp.phase, Weapon.Phase.DEAD, "decoyed, with no other ship in its cone to find")
	assert_eq(torp.dead_reason, "DECOYED")
	assert_eq(ship.torpedo_decoys, 0, "a towed body is not a store that runs down")
	_cleanup(h)


func test_the_towed_decoy_needs_way_on_and_waits_for_the_torpedo_to_close() -> void:
	var ship := _ship(_hull(true, 0, 10.0), Vector2.ZERO, 0.0)
	var h := _harness([ship])
	var torp := _homing(h, ship, Vector2(0.0, 1.0))
	TorpedoDefence.run_cycle(h[0], h[1], h[2], 0.0)
	assert_eq(torp.acquired, ship, "a ship lying stopped trails nothing useful")
	ship.speed_kn = 12.0
	torp.position = Vector2(0.0, TorpedoDefence.DECOY_RANGE_NM + 1.0)
	TorpedoDefence.run_cycle(h[0], h[1], h[2], 0.0)
	assert_true(not torp.acoustic_decoy_tried.has(ship.id), "outside decoy range nothing is tried yet")
	_cleanup(h)


func test_an_expendable_is_spent_only_when_the_towed_decoy_fails_and_each_ship_tries_once() -> void:
	var ship := _ship(_hull(true, 4, 0.0))  # every try fails
	var h := _harness([ship])
	var torp := _homing(h, ship, Vector2(0.0, 1.0))
	assert_eq(TorpedoDefence.run_cycle(h[0], h[1], h[2], 0.0), 1, "towed decoy first, then one expendable")
	assert_eq(ship.torpedo_decoys, 3)
	TorpedoDefence.run_cycle(h[0], h[1], h[2], 0.0)
	assert_eq(ship.torpedo_decoys, 3, "a failed try is not repeated against the same torpedo")
	assert_eq(torp.acquired, ship)
	_cleanup(h)


func test_a_torpedo_decoyed_onto_a_consort_meets_the_consorts_own_countermeasures() -> void:
	var first := _ship(_hull(false, 2, 10.0), Vector2.ZERO)
	var second := _ship(_hull(false, 2, 10.0), Vector2(0.0, -0.6))
	var h := _harness([first, second], _lucky_seed())
	var torp := _homing(h, first, Vector2(0.0, 1.2))
	torp.acoustic_decoy_tried[first.id] = true  # the first ship has had its try
	torp.acquired = second
	(h[1] as ThreatManager).mark_detected("BLUE", torp, 0.0, second)
	TorpedoDefence.run_cycle(h[0], h[1], h[2], 0.0)
	assert_true(torp.acoustic_decoy_tried.has(second.id), "the new target gets its own try")
	assert_eq(first.torpedo_decoys, 2, "and the first ship spends nothing more on it")
	_cleanup(h)


func test_a_torpedo_nobody_hears_gets_no_answer() -> void:
	var ship := _ship(_hull(true, 4, 10.0))
	var h := _harness([ship])
	var torp := _homing(h, ship, Vector2(0.0, 1.0))
	(h[1] as ThreatManager).begin_cycle()  # heard last cycle, not this one
	TorpedoDefence.run_cycle(h[0], h[1], h[2], 0.0)
	assert_true(torp.acoustic_decoy_tried.is_empty(), "countermeasures are cued by sonar, not by truth")
	_cleanup(h)


func test_paket_nk_fires_at_a_torpedo_homing_on_the_ship_inside_its_reach() -> void:
	var paket := DataDB.weapon("paket_nk")
	assert_true(paket != null and paket.target_types.has("torpedo"), "Paket-NK lists torpedoes among its targets")
	var ship := _ship(_hull())
	ship.weapons.append(paket)
	ship.magazines[paket.id] = 8
	var h := _harness([ship])
	var torp := _homing(h, ship, Vector2(0.0, 3.0))
	TorpedoDefence.run_cycle(h[0], h[1], h[2], 0.0)
	assert_eq(ship.magazine_count(paket.id), 8, "not yet: it is launched only once the torpedo is close")
	torp.position = Vector2(0.0, 1.2)
	TorpedoDefence.run_cycle(h[0], h[1], h[2], 0.0)
	assert_eq(ship.magazine_count(paket.id), 7, "one anti-torpedo round")
	var round_out: Weapon = null
	for w in (h[2] as WeaponManager).in_flight:
		if w.intercept_target == torp:
			round_out = w
	assert_true(round_out != null and round_out.spec.is_torpedo(), "it runs out through the water to the torpedo")
	_cleanup(h)


func test_paket_nk_is_not_fired_at_a_missile() -> void:
	var paket := DataDB.weapon("paket_nk")
	var missile := Weapon.new()
	missile.spec = DataDB.weapon("rgm_84_harpoon")
	assert_true(not AirDefence._can_intercept(paket, missile), "an anti-torpedo round is no use in the air")
	var torpedo := Weapon.new()
	torpedo.spec = _torpedo_spec()
	assert_true(AirDefence._can_intercept(paket, torpedo))


func test_the_decoy_odds_follow_the_torpedos_resistance() -> void:
	var hull := _hull(true, 0, 0.3)
	var torp := _torpedo_spec()
	assert_near(TorpedoDefence.decoy_chance(hull, torp), 0.3 / 0.7, 1e-6)
	torp.soft_kill_resistance = 1.5
	assert_near(TorpedoDefence.decoy_chance(hull, torp), 0.2, 1e-6, "a torpedo with better counter-countermeasures is harder to fool")


func test_which_navies_fit_what() -> void:
	for id in ["usn_ddg_arleigh_burke_iia", "usn_ddg_burke_iii", "usn_cg_ticonderoga", "usn_cvn_nimitz", "usn_cvn_ford", "usn_lha_america", "cw90_perry", "cw90_spruance", "cw90_ticonderoga", "cw90_nimitz"]:
		var p := DataDB.platform(id)
		assert_true(p != null and p.torpedo_decoy == "AN/SLQ-25 Nixie" and p.towed_torpedo_decoy, "%s streams Nixie" % id)
	for id in ["rn_ddg_type45", "rn_ffg_type26"]:
		var p := DataDB.platform(id)
		assert_true(p.towed_torpedo_decoy and p.torpedo_decoy_count == 16, "%s: Sonar 2170, a towed body and sixteen expendables" % id)
	assert_eq(DataDB.platform("fra_ffg_fremm").torpedo_decoy, "CANTO")
	for id in ["rfn_ffg_admiral_gorshkov", "rfn_fsg_steregushchiy"]:
		assert_true(DataDB.platform(id).weapon_loadout.has("paket_nk"), "%s carries Paket-NK" % id)
	# A submarine's countermeasures are acoustic; it carries no chaff that matters under water.
	for p: PlatformSpec in DataDB.all_platforms():
		if p.domain != "subsurface":
			continue
		assert_eq(p.decoy_count, 0, "%s carries no chaff" % p.id)
		if p.id != "irn_ssm_ghadir":
			assert_true(p.torpedo_decoy_count > 0 and p.torpedo_decoy_effectiveness > 0.0, "%s has countermeasure canisters" % p.id)


func test_the_defence_board_says_what_a_ship_has_against_a_torpedo() -> void:
	assert_eq(DefenceBoard.torpedo_answer(_ship(_hull(false, 0))), "EVADE", "nothing but her speed")
	assert_eq(DefenceBoard.torpedo_answer(_ship(_hull(true, 0))), "DECOY")
	var ship := _ship(_hull(false, 0))
	var paket := DataDB.weapon("paket_nk")
	ship.weapons.append(paket)
	ship.magazines[paket.id] = 8
	assert_eq(DefenceBoard.torpedo_answer(ship), "ATT")
	ship.magazines[paket.id] = 0
	assert_eq(DefenceBoard.torpedo_answer(ship), "EVADE", "an empty magazine is no answer")
