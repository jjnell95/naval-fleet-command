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


# --- Weapons Free against aircraft: one round in the air at a track, then a look ------------------

## Two ships with a missile that takes aircraft, and a hostile aircraft held on their picture.
## Returns [harness, track manager, track, aircraft].
func _air_raid(speed_kn: float, pk := 0.0) -> Array:
	var ships: Array = []
	for x: float in [0.0, 1.0]:
		var sam := _sam("essm", 25.0, pk)
		sam.target_types = PackedStringArray(["missile", "air"])
		sam.guidance = "inertial_active"
		sam.seeker_range_nm = 4.0
		ships.append(_ship("BLUE", Vector2(x, 0.0), [sam], 20))
	var plane := Unit.new()
	plane.spec = _platform()
	plane.spec.domain = "air"
	plane.faction = "RED"
	plane.position = Vector2(0.0, 18.0)
	plane.altitude_m = 300.0
	plane.flight_state = Unit.FlightState.AIRBORNE
	var h := _harness(ships + [plane])
	var t := Track.new()
	t.id = "T1200"
	t.owner_faction = "BLUE"
	t.truth = plane
	t.position = plane.position
	t.position_error_nm = 0.1
	t.status = Track.Status.ACTIVE
	t.domain = "air"
	t.altitude_m = plane.altitude_m
	t.speed_kn = speed_kn
	t.course_deg = 180.0
	t.identity = "HOSTILE"
	t.classification = Track.Classification.CLASS_KNOWN
	var trk := TrackManager.new()
	trk._tracks["BLUE"] = [t]
	return [h, trk, t, plane]


## Steps the weapons and the weapons-free cycle each second. Returns [launched, most in the air].
func _fight_aircraft(c: Array, seconds: float) -> Array:
	var h: Array = c[0]
	var wm: WeaponManager = h[2]
	var now := 0.0
	var launched := 0
	var most := 0
	for i in int(seconds / DT):
		now += DT
		wm.tick(DT, now)
		if is_zero_approx(fmod(now, 1.0)):
			launched += AirDefence.engage_hostile_aircraft(h[0], c[1], wm, now, ["BLUE"])
		most = maxi(most, wm.faction_commitment("BLUE", c[2]))
	return [launched, most]


func test_a_slow_drone_gets_one_round_at_a_time_from_the_whole_force() -> void:
	var c := _air_raid(90.0)
	var result := _fight_aircraft(c, 60.0)
	assert_eq(int(result[1]), 1, "two ships on weapons free keep one round in the air at the drone")
	assert_true(int(result[0]) >= 2, "and after a miss they shoot again")
	assert_true(int(result[0]) <= 4, "one round per look, not a stream: %d" % int(result[0]))
	c[1].free()
	_cleanup(c[0])


func test_no_round_leaves_for_an_aircraft_while_one_is_still_flying_at_it() -> void:
	var c := _air_raid(90.0)
	var h: Array = c[0]
	var wm: WeaponManager = h[2]
	assert_eq(AirDefence.engage_hostile_aircraft(h[0], c[1], wm, 0.0, ["BLUE"]), 1)
	var now := 0.0
	for i in 12:
		now += DT
		wm.tick(DT, now)
	assert_eq(AirDefence.engage_hostile_aircraft(h[0], c[1], wm, now, ["BLUE"]), 0, "the round is still on its way")
	c[1].free()
	_cleanup(c[0])


func test_a_fast_closing_aircraft_gets_a_pair_and_then_a_look() -> void:
	var c := _air_raid(550.0)
	var h: Array = c[0]
	assert_eq(AirDefence.engage_hostile_aircraft(h[0], c[1], h[2], 0.0, ["BLUE"]), 2, "two together at a fast jet coming in")
	assert_eq(AirDefence.engage_hostile_aircraft(h[0], c[1], h[2], 1.0, ["BLUE"]), 0, "and nothing more while they fly")
	(c[2] as Track).course_deg = 0.0
	assert_eq(AirDefence.aircraft_salvo(h[0].units[0], c[2]), 1, "one at a fast aircraft going away")
	c[1].free()
	_cleanup(c[0])


# --- A detected round with no lock yet threatens what its seeker will find ------------------------

func _unlocked(wm: WeaponManager, ship: Unit, abeam_nm: float) -> Weapon:
	var w := _incoming(wm, _asm(), Vector2(abeam_nm, 30.0), ship)
	w.acquired = null
	w.phase = Weapon.Phase.CRUISE
	w.heading_deg = 180.0
	return w


func test_a_round_aimed_a_few_miles_abeam_is_engaged_as_soon_as_it_is_seen() -> void:
	var ship := _ship("BLUE", Vector2.ZERO, [_sam("area", 60.0, 1.0)])
	var h := _harness([ship])
	var w := _unlocked(h[2], ship, 3.6)
	assert_eq(AirDefence.threatened_unit(h[0], "BLUE", w), ship, "its seeker opens with the hull inside the basket")
	h[1].mark_detected("BLUE", w, 0.0, ship)
	assert_eq(AirDefence.run_cycle(h[0], h[1], h[2], 0.0), 1, "the first missile goes on detection, not when the seeker locks")
	_cleanup(h)


func test_a_round_whose_seeker_will_never_see_the_ship_is_not_charged_to_it() -> void:
	var ship := _ship("BLUE", Vector2.ZERO)
	var h := _harness([ship])
	var w := _unlocked(h[2], ship, 12.0)
	assert_true(AirDefence.threatened_unit(h[0], "BLUE", w) == null, "passing 12 nm clear with an 8 nm seeker")
	_cleanup(h)


# --- An escort with its radar off lights it to defend herself, unless ordered silent -------------

## A thin-skinned ship and an escort beside it with its radar switched off and a missile layer
## guided by that radar; the round is coming at the escort, the one case in which her crew may
## light a radar the commander put out. Returns [harness, ship, escort, round, emcon log].
func _dark_escort() -> Array:
	var sam := _sam("sm1", 25.0, 1.0)
	sam.guidance = "semi_active_radar"
	var ship := _ship("BLUE", Vector2.ZERO)
	var escort := _ship("BLUE", Vector2(1.0, 0.0), [sam])
	escort.radar_on = false
	var h := _harness([ship, escort])
	var round := _incoming(h[2], _asm(), Vector2(1.0, 16), escort)
	var log: Array = []
	(h[2] as WeaponManager).self_defence_emcon.connect(func(u: Unit, lit: bool) -> void: log.append([u, lit]))
	return [h, ship, escort, round, log]


func test_an_escort_with_its_radar_off_lights_it_to_defend_herself() -> void:
	var c := _dark_escort()
	var h: Array = c[0]
	var shots := _watch(h[2])
	_run(h, 120.0)
	var escort: Unit = c[2]
	assert_true(_count(shots, "sm1") > 0, "the crew switched the radar on to fight, and fired")
	assert_true(not escort.radar_on, "and put it out again once the threat had passed")
	assert_eq((c[3] as Weapon).dead_reason, "INTERCEPTED")
	assert_near(escort.health, 100.0, 1e-3)
	assert_eq(c[4], [[escort, true]], "the commander is told once")
	_cleanup(h)


func test_an_escort_ordered_radar_silent_holds_fire_and_says_so_once() -> void:
	var c := _dark_escort()
	var h: Array = c[0]
	var escort: Unit = c[2]
	assert_true(h[0].issue_order(escort, Order.set_emcon(true)))
	var shots := _watch(h[2])
	_run(h, 120.0)
	assert_true(not escort.radar_on, "the silent order stands")
	assert_eq(_count(shots, "sm1"), 0)
	assert_eq(c[4], [[escort, false]], "one report that it holds fire, not one a cycle")
	_cleanup(h)


# --- A missile fired at an aircraft rides out a moment's break in its guidance --------------------

## A semi-active missile in flight from `ship` at a hostile aircraft held on a track.
func _sam_at_aircraft(h: Array, ship: Unit) -> Weapon:
	var plane := Unit.new()
	plane.spec = _platform()
	plane.spec.domain = "air"
	plane.faction = "RED"
	plane.position = Vector2(0.0, 20.0)
	plane.altitude_m = 3000.0
	plane.flight_state = Unit.FlightState.AIRBORNE
	(h[0] as UnitManager).add_unit(plane)
	var t := Track.new()
	t.id = "T1300"
	t.owner_faction = "BLUE"
	t.truth = plane
	t.position = plane.position
	t.status = Track.Status.ACTIVE
	t.domain = "air"
	t.altitude_m = plane.altitude_m
	var spec := _sam("sm1", 25.0, 1.0)
	spec.target_types = PackedStringArray(["air"])
	spec.guidance = "semi_active_radar"
	var w := Weapon.new()
	w.id = 950
	w.spec = spec
	w.faction = "BLUE"
	w.shooter = ship
	w.target_track = t
	w.position = ship.position
	w.aim_point = plane.position
	w.heading_deg = 0.0
	w.phase = Weapon.Phase.CRUISE
	(h[2] as WeaponManager).in_flight.append(w)
	return w


func _tick(wm: WeaponManager, seconds: float, from := 0.0) -> float:
	var now := from
	for i in int(seconds / DT):
		now += DT
		wm.tick(DT, now)
	return now


func test_a_missile_at_an_aircraft_coasts_through_a_short_break_in_its_guidance() -> void:
	var ship := _ship("BLUE", Vector2.ZERO)
	var h := _harness([ship])
	var w := _sam_at_aircraft(h, ship)
	ship.radar_on = false
	var now := _tick(h[2], 1.5)
	assert_true(w.phase != Weapon.Phase.DEAD, "a missed look does not lose the missile: %s" % w.dead_reason)
	ship.radar_on = true
	now = _tick(h[2], 1.0, now)
	ship.radar_on = false
	_tick(h[2], 2.5, now)
	assert_true(w.phase != Weapon.Phase.DEAD, "the coast starts again once guidance has come back")
	_tick(h[2], 2.0, now + 2.5)
	assert_eq(w.dead_reason, "GUIDANCE LOST", "a lasting loss still costs the missile")
	_cleanup(h)


# --- A round whose target is gone searches a little way on, not to the end of its fuel ------------

func test_a_round_whose_target_sinks_under_it_does_not_take_a_merchant_far_down_range() -> void:
	var target := _ship("BLUE", Vector2.ZERO)
	var merchant := _ship("GREEN", Vector2(0.0, -60.0))
	var h := _harness([target, merchant])
	var round := _incoming(h[2], _asm(), Vector2(0.0, 10.0), target)
	target.alive = false
	_tick(h[2], 600.0)
	assert_eq(round.dead_reason, "TARGET LOST")
	assert_true(round.distance_flown_nm <= 10.0 + WeaponManager.SEARCH_ON_SEEKER_RADII * round.spec.acquisition_radius_nm() + 0.5,
		"it gave up a few seeker radii past the wreck, not %0.1f nm on" % round.distance_flown_nm)
	assert_near(merchant.health, 100.0, 1e-3, "the merchant 60 nm down range is left alone")
	_cleanup(h)


func test_a_round_searching_on_still_takes_the_next_ship_of_the_group() -> void:
	var target := _ship("BLUE", Vector2.ZERO)
	var consort := _ship("BLUE", Vector2(0.0, -6.0))
	var h := _harness([target, consort])
	var round := _incoming(h[2], _asm(), Vector2(0.0, 10.0), target)
	target.alive = false
	_tick(h[2], 300.0)
	assert_true(consort.health < 100.0, "the rest of the group, close past the wreck, is still found")
	_cleanup(h)
