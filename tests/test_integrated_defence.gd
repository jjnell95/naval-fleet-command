extends TestCase
## The task force's air defence as one system: one allocation across the raid, each ship's own
## inner layer, networked fire control between fitted ships, Weapons Free against aircraft, and the
## weapon-path fixes that came with them (refusal reasons, kills cancelling queued rounds, stale
## attacks giving up, air-to-air rounds over land, anti-air salvo sizes).


func _platform(hp := 100.0) -> PlatformSpec:
	var p := PlatformSpec.new()
	p.short_name = "Test"
	p.max_speed_kn = 30.0
	p.cruise_speed_kn = 15.0
	p.turn_rate_deg_s = 6.0
	p.accel_kn_s = 1.0
	p.health = hp
	p.decoy_count = 0
	p.fire_control_channels = 4
	return p


func _radar() -> SensorSpec:
	var s := SensorSpec.new()
	s.kind = "radar"
	s.range_surface_nm = 40.0
	s.range_air_nm = 200.0
	s.antenna_height_m = 20.0
	return s


func _asm() -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = "test_asm"
	w.display_name = "Test ASM"
	w.type = "asm"
	w.max_range_nm = 70.0
	w.min_range_nm = 2.0
	w.speed_kn = 480.0
	w.turn_rate_deg_s = 15.0
	w.seeker_range_nm = 8.0
	w.damage = 40.0
	w.base_pk = 1.0
	w.salvo_default = 4
	w.launch_interval_s = 4.0
	w.altitude_m = 10.0
	w.signature_factor = 0.15
	return w


func _sam(id: String, max_range: float, pk: float, interval := 1.0) -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = id
	w.display_name = id
	w.type = "sam"
	w.target_types = PackedStringArray(["missile", "air"])
	w.max_range_nm = max_range
	w.min_range_nm = 0.05
	w.speed_kn = 2400.0
	w.turn_rate_deg_s = 120.0
	w.base_pk = pk
	w.salvo_default = 2
	w.launch_interval_s = interval
	return w


func _ship(faction: String, pos: Vector2, weapons: Array = [], rounds := 32) -> Unit:
	var u := Unit.new()
	u.spec = _platform()
	u.faction = faction
	u.callsign = "%s-%d" % [faction, int(pos.x * 10.0 + pos.y)]
	u.position = pos
	u.health = 100.0
	u.decoys = 0
	u.sensors.append(_radar())
	for spec: WeaponSpec in weapons:
		u.weapons.append(spec)
		u.magazines[spec.id] = rounds
	return u


func _harness(units: Array) -> Array:
	Terrain.clear()
	var um := UnitManager.new()
	for u: Unit in units:
		um.add_unit(u)
	var tm := ThreatManager.new()
	var wm := WeaponManager.new()
	wm.unit_manager = um
	wm.rng.seed = 5
	um.weapon_manager = wm
	return [um, tm, wm]


func _incoming(wm: WeaponManager, faction: String, pos: Vector2, target: Unit, wid := 900) -> Weapon:
	var w := Weapon.new()
	w.id = wid
	w.spec = _asm()
	w.faction = faction
	w.position = pos
	w.acquired = target
	w.aim_point = target.position
	w.heading_deg = Geo.bearing_deg(pos, target.position)
	w.phase = Weapon.Phase.TERMINAL
	wm.in_flight.append(w)
	return w


func _cleanup(h: Array) -> void:
	h[1].free()
	h[2].free()
	h[0].free()


# --- One allocation for the force -------------------------------------------------------------

func test_a_raid_gets_one_interceptor_per_round_before_any_round_gets_a_second() -> void:
	# Each ship can put one missile up per cycle. Two rounds arrive together. Answering them one at
	# a time sent both ships' missiles at the first round and none at the second.
	var a := _ship("BLUE", Vector2(0, 0), [_sam("area", 50.0, 0.0, 30.0)])
	var b := _ship("BLUE", Vector2(1, 0), [_sam("area", 50.0, 0.0, 30.0)])
	var h := _harness([a, b])
	var first := _incoming(h[2], "RED", Vector2(0, 20), a, 901)
	var second := _incoming(h[2], "RED", Vector2(1, 20.2), b, 902)
	h[1].mark_detected("BLUE", first, 0.0)
	h[1].mark_detected("BLUE", second, 0.0)
	assert_eq(AirDefence.run_cycle(h[0], h[1], h[2], 0.0), 2)
	assert_eq(first.guided_interceptors_committed, 1, "the first round has one interceptor")
	assert_eq(second.guided_interceptors_committed, 1, "and so does the second, from the other ship")
	_cleanup(h)


func test_a_ship_with_a_free_channel_is_asked_before_a_nearer_saturated_one() -> void:
	var near := _ship("BLUE", Vector2(0, 5), [_sam("area", 50.0, 0.0)])
	near.spec.fire_control_channels = 1
	var far := _ship("BLUE", Vector2(0, 0), [_sam("area", 50.0, 0.0)])
	var h := _harness([near, far])
	var busy := _incoming(h[2], "RED", Vector2(30, 30), near, 903)
	assert_eq(h[2].launch_interceptor(near, near.weapons[0], busy, 1, 0.0), 1, "the near ship's one channel is taken")
	var round := _incoming(h[2], "RED", Vector2(0, 25), far, 904)
	h[1].mark_detected("BLUE", round, 0.0)
	AirDefence.run_cycle(h[0], h[1], h[2], 5.0)
	assert_eq(AirDefence.engaging_units(h[2], round), [far] as Array[Unit], "the ship with a channel took it")
	_cleanup(h)


func test_each_ship_keeps_its_own_inner_layer_allowance() -> void:
	var point_escort := _sam("point", 12.0, 0.0)
	var point_own := _sam("point", 12.0, 1.0)
	var escort := _ship("BLUE", Vector2(1, 0), [point_escort])
	var victim := _ship("BLUE", Vector2(0, 0), [point_own])
	var h := _harness([escort, victim])
	var round := _incoming(h[2], "RED", Vector2(0, 8), victim)
	# The escort has already spent its point-layer allowance on this round.
	round.defence_commitments[AirDefence.layer_key(point_escort, escort)] = 2
	assert_eq(AirDefence._engage_threat(escort, round, h[2], true, 0.0), 0, "the escort is out of shots at it")
	assert_eq(AirDefence._engage_threat(victim, round, h[2], true, 0.0), 1, "the ship it is aimed at still has its own")
	_cleanup(h)


# --- Networked fire control -------------------------------------------------------------------

func _networked_case(shooter_flag: bool, consort_flag: bool) -> Array:
	var sam := _sam("supported", 80.0, 0.0)
	sam.guidance = "fire_control_directed"
	var shooter := _ship("BLUE", Vector2(0, 0), [sam])
	shooter.spec.cooperative_engagement = shooter_flag
	var consort := _ship("BLUE", Vector2(0, 32), [])
	consort.spec.cooperative_engagement = consort_flag
	var h := _harness([shooter, consort])
	# A sea-skimmer forty miles out: below the shooter's horizon, ten miles from the consort.
	var round := _incoming(h[2], "RED", Vector2(0, 40), shooter)
	h[1].mark_detected("BLUE", round, 0.0)
	return [h, shooter, consort, sam, round]


func test_an_unfitted_consort_cues_but_cannot_guide_below_the_shooters_horizon() -> void:
	var c := _networked_case(true, false)
	assert_eq(AirDefence.run_cycle(c[0][0], c[0][1], c[0][2], 0.0), 0, "a cue is not guidance")
	assert_true(c[0][2].network_guide(c[1], c[3], c[4]) == null)
	_cleanup(c[0])


func test_fitted_ships_on_the_link_guide_each_others_shots() -> void:
	var c := _networked_case(true, true)
	var h: Array = c[0]
	var shooter: Unit = c[1]
	var consort: Unit = c[2]
	assert_eq(h[2].network_guide(shooter, c[3], c[4]), consort, "the consort's radar carries the shot")
	assert_eq(AirDefence.run_cycle(h[0], h[1], h[2], 0.0), 1, "the shooter fires beyond its own horizon")
	var interceptor: Weapon = h[2].in_flight.back()
	h[2].tick(0.25, 0.25)
	assert_true(interceptor.phase != Weapon.Phase.DEAD, "guidance holds while the consort has the round")
	consort.radar_on = false
	h[2].tick(0.25, 0.5)
	assert_eq(interceptor.dead_reason, "GUIDANCE LOST", "the guide's radar went off")
	_cleanup(h)


func test_networked_fire_control_needs_the_link_at_both_ends() -> void:
	var c := _networked_case(true, true)
	var h: Array = c[0]
	(c[1] as Unit).spec.has_datalink = false
	assert_true(h[2].network_guide(c[1], c[3], c[4]) == null, "the shooter is off the link")
	(c[1] as Unit).spec.has_datalink = true
	(c[2] as Unit).spec.has_datalink = false
	assert_true(h[2].network_guide(c[1], c[3], c[4]) == null, "the consort is off the link")
	_cleanup(h)


func test_a_self_guided_interceptor_needs_no_network() -> void:
	var c := _networked_case(false, false)
	var active := _sam("active", 80.0, 0.0)
	assert_true(c[0][2].guidance_available(c[1], active, c[4]), "an active seeker guides itself")
	_cleanup(c[0])


func test_shipped_aegis_hulls_are_fitted_and_the_1990_cruiser_is_not() -> void:
	for id: String in ["usn_ddg_arleigh_burke_iia", "usn_ddg_burke_iii", "usn_cg_ticonderoga", "jmsdf_ddg_maya"]:
		assert_true(DataDB.platform(id).cooperative_engagement, "%s fights on the network" % id)
	assert_true(not DataDB.platform("cw90_ticonderoga").cooperative_engagement, "not in the 1990 fleet")


# --- Weapons Free against aircraft ------------------------------------------------------------

func _air_case(identity := "HOSTILE") -> Array:
	var sam := _sam("area", 40.0, 0.0)
	var ship := _ship("BLUE", Vector2.ZERO, [sam], 20)
	var plane := Unit.new()
	plane.spec = _platform()
	plane.spec.domain = "air"
	plane.faction = "RED"
	plane.position = Vector2(0, 20)
	plane.altitude_m = 3000.0
	var h := _harness([ship, plane])
	var t := Track.new()
	t.id = "T1100"
	t.owner_faction = "BLUE"
	t.truth = plane
	t.position = plane.position
	t.status = Track.Status.ACTIVE
	t.domain = "air"
	t.altitude_m = 3000.0
	t.identity = identity
	t.classification = Track.Classification.CLASS_KNOWN
	var tm := TrackManager.new()
	tm._tracks["BLUE"] = [t]
	return [h, ship, t, tm]


func test_a_ship_on_weapons_free_engages_a_hostile_aircraft_in_its_envelope() -> void:
	var c := _air_case()
	var h: Array = c[0]
	assert_eq(AirDefence.engage_hostile_aircraft(h[0], c[3], h[2], 0.0, ["BLUE"]), 1)
	assert_eq(h[2].faction_commitment("BLUE", c[2]), 1, "one round: shoot, look, shoot")
	AirDefence.engage_hostile_aircraft(h[0], c[3], h[2], 1.0, ["BLUE"])
	AirDefence.engage_hostile_aircraft(h[0], c[3], h[2], 2.0, ["BLUE"])
	assert_eq(h[2].faction_commitment("BLUE", c[2]), AirDefence.AIRCRAFT_ROUNDS_IN_FLIGHT, "and no more than the side's limit")
	c[3].free()
	_cleanup(h)


func test_weapons_tight_manual_defence_and_unidentified_aircraft_are_left_to_the_commander() -> void:
	var c := _air_case()
	(c[1] as Unit).roe = Unit.Roe.TIGHT
	assert_eq(AirDefence.engage_hostile_aircraft(c[0][0], c[3], c[0][2], 0.0, ["BLUE"]), 0, "tight")
	(c[1] as Unit).roe = Unit.Roe.FREE
	(c[1] as Unit).auto_air_defence = false
	assert_eq(AirDefence.engage_hostile_aircraft(c[0][0], c[3], c[0][2], 0.0, ["BLUE"]), 0, "manual defence")
	(c[1] as Unit).auto_air_defence = true
	(c[2] as Track).identity = "UNKNOWN"
	assert_eq(AirDefence.engage_hostile_aircraft(c[0][0], c[3], c[0][2], 0.0, ["BLUE"]), 0, "not identified")
	assert_eq(AirDefence.engage_hostile_aircraft(c[0][0], c[3], c[0][2], 0.0, []), 0, "an AI side is not stepped here")
	c[3].free()
	_cleanup(c[0])


func test_missiles_are_kept_back_for_missiles() -> void:
	var c := _air_case()
	(c[1] as Unit).magazines["area"] = AirDefence.SAM_RESERVE_FOR_MISSILES
	assert_eq(AirDefence.engage_hostile_aircraft(c[0][0], c[3], c[0][2], 0.0, ["BLUE"]), 0)
	c[3].free()
	_cleanup(c[0])


# --- The weapon path --------------------------------------------------------------------------

func test_a_refused_shot_says_why() -> void:
	var c := _air_case()
	var ship: Unit = c[1]
	ship.roe = Unit.Roe.HOLD
	var order := Order.engage(c[2], "area", 1)
	assert_true(not c[0][0].issue_order(ship, order))
	assert_eq(order.receipt, "weapons hold")
	assert_eq(UnitManager.engage_rejection(ship, Order.engage(c[2], "nothing_aboard", 1)), "nothing_aboard not aboard")
	c[3].free()
	_cleanup(c[0])


func test_rounds_still_queued_are_returned_once_the_plot_records_the_kill() -> void:
	var c := _air_case()
	var ship: Unit = c[1]
	var sam: WeaponSpec = ship.weapons[0]
	sam.launch_interval_s = 10.0
	assert_true(c[0][2].launch(ship, sam, c[2], 3, 0.0))
	assert_eq(ship.magazine_count("area"), 17)
	assert_eq(c[0][2].committed_rounds(ship, sam, c[2], true), 2, "two still on the rail")
	(c[2] as Track).damage_estimate = 100.0
	c[0][2].tick(0.25, 0.25)
	assert_eq(c[0][2].committed_rounds(ship, sam, c[2], true), 0)
	assert_eq(ship.magazine_count("area"), 19, "both queued rounds are back in the magazine")
	c[3].free()
	_cleanup(c[0])


func test_an_air_to_air_or_anti_air_round_is_not_a_sea_skimmer() -> void:
	var aam := WeaponSpec.new()
	aam.type = "aam"
	aam.profile = "direct"
	assert_true(not Combat.profile_is_surface_bound(aam), "a dogfight missile flies at height")
	var hellfire := WeaponSpec.new()
	hellfire.type = "asm"
	hellfire.profile = "direct"
	assert_true(Combat.profile_is_surface_bound(hellfire), "an air-to-surface direct round still meets the ground")


func test_the_ai_fires_a_weapons_own_salvo_at_an_aircraft_not_an_anti_ship_volley() -> void:
	var ai := AIController.new()
	var sam := _sam("area", 100.0, 0.5)
	var ship := _ship("RED", Vector2.ZERO, [sam, _asm()], 24)
	var air := Track.new()
	air.domain = "air"
	var surface := Track.new()
	surface.domain = "surface"
	assert_eq(ai._salvo_for(ship, sam, air), 2, "two SAMs at one aircraft")
	assert_eq(ai._salvo_for(ship, ship.weapons[1], surface), AIController.ASM_SALVO, "a full volley at a ship")
	ai.free()
