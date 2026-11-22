extends TestCase
## Air-defence doctrine: the force defends its ships, not an allowance of rounds.

const DT := 0.25


func _platform(hp := 100.0) -> PlatformSpec:
	var p := PlatformSpec.new()
	p.short_name = "FFG Test"
	p.max_speed_kn = 30.0
	p.cruise_speed_kn = 15.0
	p.health = hp
	p.decoy_count = 0
	return p


func _radar() -> SensorSpec:
	var s := SensorSpec.new()
	s.kind = "radar"
	s.range_surface_nm = 40.0
	s.range_air_nm = 200.0
	s.antenna_height_m = 20.0
	return s


func _asm(speed_kn := 480.0) -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = "test_asm"
	w.display_name = "Test ASM"
	w.type = "asm"
	w.max_range_nm = 120.0
	w.speed_kn = speed_kn
	w.turn_rate_deg_s = 15.0
	w.seeker_range_nm = 8.0
	w.damage = 40.0
	w.base_pk = 1.0
	w.altitude_m = 10.0
	return w


func _sam(id: String, max_range: float, pk: float, kind := "sam") -> WeaponSpec:
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
	w.salvo_default = 1
	w.launch_interval_s = 1.0
	return w


func _ship(faction: String, pos: Vector2, weapons: Array = [], rounds := 32) -> Unit:
	var u := Unit.new()
	u.spec = _platform()
	u.faction = faction
	u.callsign = "%s ship" % faction
	u.position = pos
	u.health = 100.0
	u.decoys = 0
	u.sensors.append(_radar())
	for spec: WeaponSpec in weapons:
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


func _cleanup(h: Array) -> void:
	h[1].free()
	h[2].free()
	h[0].free()


## An inbound round. Locked on `target` when one is given, else flying its heading unlocked.
func _incoming(wm: WeaponManager, spec: WeaponSpec, pos: Vector2, target: Unit, wid := 900, faction := "RED") -> Weapon:
	var w := Weapon.new()
	w.id = wid
	w.spec = spec
	w.faction = faction
	w.position = pos
	w.acquired = target
	w.aim_point = target.position
	w.launch_range_nm = pos.distance_to(target.position)
	w.heading_deg = Geo.bearing_deg(pos, target.position)
	w.phase = Weapon.Phase.TERMINAL
	wm.in_flight.append(w)
	return w


## What the defence did, read from the manager's own signal: one entry per launch.
func _watch(wm: WeaponManager) -> Array:
	var log: Array = []
	wm.interceptor_launched.connect(func(shooter: Unit, spec: WeaponSpec, threat: Weapon, rounds: int) -> void:
		log.append({"shooter": shooter, "spec": spec.id, "threat": threat, "rounds": rounds, "range": shooter.position.distance_to(threat.position), "t": wm.now_s}))
	return log


func _sams_up(wm: WeaponManager, threat: Weapon) -> int:
	var n := 0
	for w: Weapon in wm.in_flight:
		if w.phase != Weapon.Phase.DEAD and w.intercept_target == threat and w.spec.type == "sam":
			n += 1
	return n


## The simulation's own order of work, with the sensor cycle stood in for: every round in flight
## is seen by the other side. Returns the most missiles ever in the air at `watch`.
func _run(h: Array, seconds: float, watch: Weapon = null, start := 0.0) -> int:
	var um: UnitManager = h[0]
	var tm: ThreatManager = h[1]
	var wm: WeaponManager = h[2]
	var now := start
	var accum := 0.0
	var most := 0
	for i in int(seconds / DT):
		now += DT
		um.tick(DT)
		wm.tick(DT, now)
		accum += DT
		if accum >= 1.0:
			accum -= 1.0
			tm.begin_cycle()
			for w: Weapon in wm.in_flight:
				if w.intercept_target == null:
					for u in um.units:
						if u.faction != w.faction:
							tm.mark_detected(u.faction, w, now)
			DefensiveResponse.run_cycle(um, tm, wm)
			AirDefence.run_cycle(um, tm, wm, now)
		if watch != null:
			most = maxi(most, _sams_up(wm, watch))
	return most


func _count(log: Array, spec_id: String) -> int:
	var n := 0
	for e: Dictionary in log:
		if e["spec"] == spec_id:
			n += 1
	return n


# --- A leaker is engaged until it is dead or it hits ----------------------------------------------

func test_a_round_that_survives_its_interceptors_is_shot_at_again_all_the_way_in() -> void:
	var ship := _ship("BLUE", Vector2.ZERO, [_sam("point", 25.0, 0.0)])
	var h := _harness([ship])
	var log := _watch(h[2])
	var round := _incoming(h[2], _asm(), Vector2(0, 20), ship)
	var most := _run(h, 200.0, round)
	assert_eq(round.dead_reason, "HIT", "every interceptor was made to miss")
	assert_true(log.size() >= 6, "the ship kept shooting as each one missed (fired %d)" % log.size())
	assert_true(float(log.back()["range"]) < 4.0, "the last missile left with the round close in, not %.1f nm out" % float(log.back()["range"]))
	assert_true(most <= AirDefence.MAX_INTERCEPTORS_PER_THREAT, "and never more than the allowance in the air at once (%d)" % most)
	_cleanup(h)


func test_a_close_in_gun_fires_every_cycle_the_round_is_in_its_envelope() -> void:
	var gun := _sam("gun", 1.2, 0.0, "ciws")
	gun.salvo_default = 1
	var ship := _ship("BLUE", Vector2.ZERO, [gun], 60)
	var h := _harness([ship])
	var log := _watch(h[2])
	var round := _incoming(h[2], _asm(), Vector2(0, 3), ship)
	_run(h, 40.0)
	assert_eq(round.dead_reason, "HIT")
	# 1.2 nm at 480 knots is nine seconds, and the mount cycles once a second.
	assert_true(log.size() >= 6, "the gun fired the whole way across its envelope (bursts: %d)" % log.size())
	_cleanup(h)


func test_every_ship_whose_gun_bears_fires_it() -> void:
	var gun := _sam("gun", 2.0, 0.0, "ciws")
	var first := _ship("BLUE", Vector2.ZERO, [gun], 60)
	var second := _ship("BLUE", Vector2(0.1, 0), [gun], 60)
	var h := _harness([first, second])
	_incoming(h[2], _asm(), Vector2(0, 3), first)
	_run(h, 40.0)
	assert_true(first.magazine_count("gun") <= 55, "the ship under attack fired more than two bursts")
	assert_true(second.magazine_count("gun") <= 55, "and so did its consort alongside")
	assert_true(AirDefence._count_committed(h[2]).is_empty(), "gun bursts are not missiles in the air")
	_cleanup(h)


# --- Shoot, look, shoot ---------------------------------------------------------------------------

func test_one_missile_goes_up_while_there_is_time_to_look() -> void:
	var ship := _ship("BLUE", Vector2.ZERO, [_sam("point", 25.0, 1.0)])
	var h := _harness([ship])
	var round := _incoming(h[2], _asm(), Vector2(0, 20), ship)
	var most := _run(h, 120.0, round)
	assert_eq(round.dead_reason, "INTERCEPTED")
	assert_eq(most, 1, "one in the air: the second waits on the result of the first")
	assert_eq(ship.magazine_count("point"), 31, "and the first one did the job, so one round was spent")
	_cleanup(h)


func test_a_second_missile_goes_at_once_when_there_is_no_time_for_a_look() -> void:
	var ship := _ship("BLUE", Vector2.ZERO, [_sam("point", 25.0, 0.0)])
	var h := _harness([ship])
	var log := _watch(h[2])
	# 1,500 knots from six miles: fourteen seconds to run, and the first missile needs five of them.
	var round := _incoming(h[2], _asm(1500.0), Vector2(0, 6), ship)
	var most := _run(h, 4.0, round)
	assert_eq(most, 2, "a pair is in the air inside the first seconds")
	assert_true(log.size() >= 2 and float(log[1]["t"]) - float(log[0]["t"]) <= 2.0, "the second followed the first at the launcher's own interval")
	_cleanup(h)


func test_a_saturation_policy_keeps_a_pair_up_and_conserve_one() -> void:
	for policy: String in ["saturation", "conserve"]:
		var ship := _ship("BLUE", Vector2.ZERO, [_sam("point", 25.0, 0.0)])
		ship.defence_policy = policy
		var h := _harness([ship])
		var round := _incoming(h[2], _asm(), Vector2(0, 20), ship)
		var most := _run(h, 30.0, round)
		assert_eq(most, 2 if policy == "saturation" else 1, policy)
		_cleanup(h)


# --- One count for the whole force ----------------------------------------------------------------

func test_three_ships_put_one_missile_between_them_at_one_round() -> void:
	var ships: Array = []
	for i in 3:
		ships.append(_ship("BLUE", Vector2(float(i) * 0.5, 0), [_sam("point", 25.0, 1.0)]))
	var h := _harness(ships)
	var round := _incoming(h[2], _asm(), Vector2(0, 20), ships[0])
	var most := _run(h, 120.0, round)
	var spent := 0
	for u: Unit in ships:
		spent += 32 - u.magazine_count("point")
	assert_eq(round.dead_reason, "INTERCEPTED")
	assert_eq(most, 1, "the force counts what is in the air at the round as one")
	assert_eq(spent, 1, "so one missile was spent on it, not one or two from each ship")
	_cleanup(h)


func test_a_round_aimed_at_an_undefended_ship_is_answered_first() -> void:
	var escort := _ship("BLUE", Vector2.ZERO, [_sam("point", 25.0, 1.0)])
	var merchant := _ship("BLUE", Vector2(1.0, 0))
	var h := _harness([escort, merchant])
	var at_escort := _incoming(h[2], _asm(), Vector2(0, 12.0), escort, 900)
	var at_merchant := _incoming(h[2], _asm(), Vector2(1.0, 12.4), merchant, 901)
	var tm: ThreatManager = h[1]
	tm.mark_detected("BLUE", at_escort, 0.0)
	tm.mark_detected("BLUE", at_merchant, 0.0)
	var picture := AirDefence.inbound_threats(h[0], tm, "BLUE")
	assert_eq(picture[0]["weapon"], at_merchant, "the round at the ship with nothing to shoot back with ranks first")
	# One launcher, one missile a cycle: it goes to the round only this ship can stop.
	assert_eq(AirDefence.run_cycle(h[0], tm, h[2], 0.0), 1)
	assert_eq(_sams_up(h[2], at_merchant), 1, "the escort's first missile covers its consort")
	assert_eq(_sams_up(h[2], at_escort), 0)
	_cleanup(h)


# --- The cheapest layer that can still do it ------------------------------------------------------

func test_an_area_missile_holds_while_the_point_layer_will_have_the_round_in_time() -> void:
	var ship := _ship("BLUE", Vector2.ZERO, [_sam("area", 60.0, 1.0), _sam("point", 16.0, 1.0)])
	var h := _harness([ship])
	var round := _incoming(h[2], _asm(), Vector2(0, 40), ship)
	_run(h, 320.0)
	assert_eq(round.dead_reason, "INTERCEPTED")
	assert_eq(ship.magazine_count("area"), 32, "no area missile was spent on a round the point layer could take")
	assert_eq(ship.magazine_count("point"), 31)
	_cleanup(h)


func test_the_innermost_missile_that_leaves_time_for_a_look_takes_the_shot() -> void:
	var ship := _ship("BLUE", Vector2.ZERO, [_sam("medium", 25.0, 1.0), _sam("short", 6.0, 1.0)])
	var h := _harness([ship])
	var log := _watch(h[2])
	var far := _incoming(h[2], _asm(), Vector2(0, 15), ship, 900)
	(h[1] as ThreatManager).mark_detected("BLUE", far, 0.0)
	AirDefence.run_cycle(h[0], h[1], h[2], 0.0)
	assert_eq(log.size(), 1)
	assert_eq(log[0]["spec"], "medium", "out at fifteen miles the ship does not wait for its shortest layer: both are point defence")
	var near := _incoming(h[2], _asm(), Vector2(0, 5), ship, 901)
	(h[1] as ThreatManager).mark_detected("BLUE", near, 5.0)
	AirDefence.run_cycle(h[0], h[1], h[2], 5.0)
	assert_eq(log.size(), 2)
	assert_eq(log[1]["spec"], "short", "with both in reach and time in hand, the cheaper one goes")
	_cleanup(h)


func test_an_area_missile_covers_a_consort_the_point_layer_cannot_reach() -> void:
	var escort := _ship("BLUE", Vector2.ZERO, [_sam("area", 60.0, 1.0), _sam("point", 16.0, 1.0)])
	var consort := _ship("BLUE", Vector2(0, 30))
	var h := _harness([escort, consort])
	var round := _incoming(h[2], _asm(), Vector2(0, 50), consort)
	_run(h, 200.0)
	assert_eq(round.dead_reason, "INTERCEPTED", "the escort's area missile reached out to it")
	assert_eq(escort.magazine_count("point"), 32)
	assert_true(escort.magazine_count("area") < 32)
	assert_near(consort.health, 100.0, 1e-3)
	_cleanup(h)


func _bmd(rounds := 32) -> Array:
	var long := _sam("bmd", 60.0, 1.0)
	long.target_types = PackedStringArray(["missile", "ballistic"])
	var escort := _ship("BLUE", Vector2.ZERO, [long, _sam("point", 16.0, 1.0)])
	escort.magazines["bmd"] = rounds
	var consort := _ship("BLUE", Vector2(0, 30))
	return [escort, consort]


func test_ballistic_capable_missiles_are_kept_while_a_ballistic_round_is_held() -> void:
	var units := _bmd()
	var h := _harness(units)
	var cruise := _incoming(h[2], _asm(), Vector2(0, 50), units[1], 900)
	var ballistic := _asm(4000.0)
	ballistic.profile = "ballistic"
	ballistic.altitude_m = 30000.0
	ballistic.max_range_nm = 400.0
	var lofted := _incoming(h[2], ballistic, Vector2(0, -200), units[1], 901)
	var tm: ThreatManager = h[1]
	tm.mark_detected("BLUE", cruise, 0.0)
	tm.mark_detected("BLUE", lofted, 0.0)
	AirDefence.run_cycle(h[0], tm, h[2], 0.0)
	assert_eq(_sams_up(h[2], cruise), 0, "the rounds that can stop a ballistic missile are not spent on a cruise missile while one is coming")
	_cleanup(h)


func test_ballistic_capable_missiles_are_kept_when_the_magazine_is_low() -> void:
	for rounds: int in [AirDefence.BALLISTIC_RESERVE_ROUNDS, AirDefence.BALLISTIC_RESERVE_ROUNDS + 1]:
		var units := _bmd(rounds)
		var h := _harness(units)
		var cruise := _incoming(h[2], _asm(), Vector2(0, 50), units[1])
		(h[1] as ThreatManager).mark_detected("BLUE", cruise, 0.0)
		AirDefence.run_cycle(h[0], h[1], h[2], 0.0)
		assert_eq(_sams_up(h[2], cruise), 0 if rounds <= AirDefence.BALLISTIC_RESERVE_ROUNDS else 1, "%d rounds aboard" % rounds)
		_cleanup(h)


func test_a_ship_with_nothing_else_defends_itself_with_its_ballistic_capable_missiles() -> void:
	var long := _sam("bmd", 60.0, 1.0)
	long.target_types = PackedStringArray(["missile", "ballistic"])
	var ship := _ship("BLUE", Vector2.ZERO, [long], 4)
	var h := _harness([ship])
	var round := _incoming(h[2], _asm(), Vector2(0, 20), ship)
	_run(h, 120.0)
	assert_eq(round.dead_reason, "INTERCEPTED", "a reserve is not kept at the cost of the ship")
	_cleanup(h)


# --- Weapons hold stops attacks, not self-defence -------------------------------------------------

func test_a_ship_on_weapons_hold_still_shoots_down_a_round_coming_at_it() -> void:
	var ship := _ship("BLUE", Vector2.ZERO, [_sam("point", 25.0, 1.0), _sam("gun", 1.2, 1.0, "ciws")])
	var h := _harness([ship])
	assert_true(h[0].issue_order(ship, Order.set_roe(Unit.Roe.HOLD)))
	var round := _incoming(h[2], _asm(), Vector2(0, 20), ship)
	_run(h, 200.0)
	assert_eq(round.dead_reason, "INTERCEPTED", "hold is an order not to attack; the ship still defends itself")
	assert_near(ship.health, 100.0, 1e-3)
	_cleanup(h)


func test_the_guns_of_a_ship_on_weapons_hold_fire_at_a_leaker() -> void:
	var ship := _ship("BLUE", Vector2.ZERO, [_sam("gun", 1.2, 1.0, "ciws")], 60)
	var h := _harness([ship])
	ship.roe = Unit.Roe.HOLD
	var round := _incoming(h[2], _asm(), Vector2(0, 3), ship)
	_run(h, 40.0)
	assert_true(ship.magazine_count("gun") < 60, "the close-in gun fired")
	assert_eq(round.dead_reason, "INTERCEPTED")
	_cleanup(h)


func test_a_consort_on_weapons_hold_covers_the_ship_beside_it() -> void:
	var escort := _ship("BLUE", Vector2(1.0, 0), [_sam("point", 25.0, 1.0)])
	var merchant := _ship("BLUE", Vector2.ZERO)
	var h := _harness([escort, merchant])
	escort.roe = Unit.Roe.HOLD
	var round := _incoming(h[2], _asm(), Vector2(0, 20), merchant)
	_run(h, 200.0)
	assert_eq(round.dead_reason, "INTERCEPTED")
	assert_near(merchant.health, 100.0, 1e-3)
	_cleanup(h)


# --- Manual missile defence: self-defence weapons fire, area missiles wait for the commander ------

func _manual(ship: Unit, h: Array) -> void:
	assert_true(h[0].issue_order(ship, Order.set_air_defence_mode(false)))


func test_on_manual_defence_the_point_missiles_and_guns_fire_unordered() -> void:
	var ship := _ship("BLUE", Vector2.ZERO, [_sam("area", 60.0, 1.0), _sam("point", 10.0, 1.0), _sam("gun", 1.2, 1.0, "ciws")])
	var h := _harness([ship])
	_manual(ship, h)
	var log := _watch(h[2])
	var round := _incoming(h[2], _asm(), Vector2(0, 40), ship)
	_run(h, 400.0)
	assert_eq(_count(log, "area"), 0, "the area missile waits for the commander")
	assert_true(_count(log, "point") > 0, "the point-defence missile is the crew's to fire")
	assert_eq(round.dead_reason, "INTERCEPTED")
	assert_near(ship.health, 100.0, 1e-3, "an unordered ship still defends itself")
	_cleanup(h)


func test_on_manual_defence_a_gun_is_all_that_answers_for_a_ship_with_only_area_missiles() -> void:
	var ship := _ship("BLUE", Vector2.ZERO, [_sam("area", 60.0, 1.0), _sam("gun", 1.2, 0.0, "ciws")])
	var h := _harness([ship])
	_manual(ship, h)
	var log := _watch(h[2])
	_incoming(h[2], _asm(), Vector2(0, 40), ship)
	_run(h, 400.0)
	assert_eq(_count(log, "area"), 0, "no area missile leaves unordered")
	assert_true(_count(log, "gun") > 0, "the gun fires by itself")
	assert_true(ship.health < 100.0, "and with the gun missing, the round arrives")
	_cleanup(h)


func test_range_decides_which_missiles_are_self_defence() -> void:
	assert_true(_sam("gun", 1.2, 1.0, "ciws").is_self_defence())
	assert_true(_sam("point", 10.0, 1.0).is_self_defence())
	assert_true(not _sam("area", 60.0, 1.0).is_self_defence())
	var flagged := _sam("flagged", 60.0, 1.0)
	flagged.defence_layer = "point"
	assert_true(flagged.is_self_defence(), "the data can say so outright")
	assert_true(not _asm().is_self_defence(), "an attack weapon never is")


# --- Manual missile defence: the intercept order with no round named clears the raid --------------

## A ship on manual defence with only an area missile, a first round held, and the order given.
func _cleared_for_raid() -> Array:
	var ship := _ship("BLUE", Vector2.ZERO, [_sam("area", 60.0, 1.0)])
	var h := _harness([ship])
	_manual(ship, h)
	var first := _incoming(h[2], _asm(), Vector2(0, 50), ship, 900)
	_run(h, 1.0)
	var result := AirDefence.order_intercept(ship, null, h[0], h[1], h[2], 1.0)
	assert_eq(int(result["cleared"]), 1, str(result["reason"]))
	return [ship, h, first]


func test_one_intercept_order_covers_the_rounds_of_the_raid_that_arrive_later() -> void:
	var set := _cleared_for_raid()
	var ship: Unit = set[0]
	var h: Array = set[1]
	var log := _watch(h[2])
	_run(h, 24.0, null, 1.0)
	var second := _incoming(h[2], _asm(), Vector2(0, 50), ship, 901)
	_run(h, 25.0, null, 25.0)
	var third := _incoming(h[2], _asm(), Vector2(3, 50), ship, 902)
	_run(h, 500.0, null, 50.0)
	for round: Weapon in [set[2], second, third]:
		assert_eq(round.dead_reason, "INTERCEPTED", "round %d is engaged on the one order" % round.id)
	assert_true(log.any(func(e: Dictionary) -> bool: return e["threat"] == third and e["spec"] == "area"), "the area missile takes the last round too")
	assert_near(ship.health, 100.0, 1e-3)
	_cleanup(h)


func test_the_clearance_lapses_once_the_sky_has_been_quiet() -> void:
	var set := _cleared_for_raid()
	var ship: Unit = set[0]
	var h: Array = set[1]
	_run(h, 100.0, null, 1.0)
	assert_eq((set[2] as Weapon).dead_reason, "INTERCEPTED")
	assert_true(ship.cleared_for_raid(101.0), "the clearance outlasts the last round by a while")
	_run(h, AirDefence.RAID_QUIET_S, null, 101.0)
	var now := 101.0 + AirDefence.RAID_QUIET_S
	assert_true(not ship.cleared_for_raid(now), "a quiet sky ends it")
	var log := _watch(h[2])
	_incoming(h[2], _asm(), Vector2(0, 50), ship, 903)
	_run(h, 500.0, null, now)
	assert_eq(log.size(), 0, "the next raid waits for the commander again")
	assert_true(ship.health < 100.0)
	_cleanup(h)


func test_weapons_hold_withdraws_the_clearance() -> void:
	var set := _cleared_for_raid()
	var ship: Unit = set[0]
	var h: Array = set[1]
	var first: Weapon = set[2]
	# Out of reach yet: the order cleared the round and nothing has left.
	first.position = Vector2(0, 80)
	ship.roe = Unit.Roe.HOLD
	_run(h, 2.0, null, 1.0)
	assert_true(not ship.cleared_for_raid(3.0))
	assert_true(not first.intercept_cleared.has(ship.id), "the round named goes back to waiting as well")
	ship.roe = Unit.Roe.FREE
	var log := _watch(h[2])
	_run(h, 700.0, null, 3.0)
	assert_eq(log.size(), 0, "lifting the hold does not release missiles on the old order")
	_cleanup(h)


func test_the_rounds_waiting_on_the_commander_are_counted_until_he_clears_them() -> void:
	var ship := _ship("BLUE", Vector2.ZERO, [_sam("area", 60.0, 1.0), _sam("point", 10.0, 1.0)])
	var h := _harness([ship])
	_manual(ship, h)
	_incoming(h[2], _asm(), Vector2(0, 50), ship, 900)
	_incoming(h[2], _asm(), Vector2(1, 52), ship, 901)
	_run(h, 1.0)
	assert_eq(AirDefence.awaiting_clearance(h[0], h[1], "BLUE").size(), 2, "both rounds wait on the order")
	assert_eq(AirDefence.awaiting_clearance(h[0], h[1], "RED").size(), 0)
	AirDefence.order_intercept(ship, null, h[0], h[1], h[2], 1.0)
	assert_eq(AirDefence.awaiting_clearance(h[0], h[1], "BLUE").size(), 0, "cleared, the prompt goes")
	_incoming(h[2], _asm(), Vector2(-1, 55), ship, 902)
	_run(h, 1.0, null, 1.0)
	assert_eq(AirDefence.awaiting_clearance(h[0], h[1], "BLUE").size(), 0, "a later round of a cleared raid needs no new order")
	_cleanup(h)


func test_a_ship_on_automatic_defence_has_nothing_waiting_on_the_commander() -> void:
	var ship := _ship("BLUE", Vector2.ZERO, [_sam("area", 60.0, 1.0)])
	var h := _harness([ship])
	_incoming(h[2], _asm(), Vector2(0, 50), ship, 900)
	_run(h, 1.0)
	assert_eq(AirDefence.awaiting_clearance(h[0], h[1], "BLUE").size(), 0)
	_cleanup(h)


func test_the_raid_clearance_is_part_of_a_saved_game() -> void:
	assert_true(SimSnapshot.script_variables(Unit.new()).has("raid_clearance_until_s"))
	assert_true(not SimSnapshot.UNIT_SKIP.has("raid_clearance_until_s"))
