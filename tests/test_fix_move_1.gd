extends TestCase
## An attack order must not park the ship. In reach, a platform fires from where its own orders
## have it: in its screen station, along its route, on its circuit. When it has to close it does so
## briskly, keeps way on once in range, and goes back to what it was doing when the task ends,
## however it ends. Aircraft hold off a ship they have fired at and hold when the task is over.

const DT := 0.25


func _platform(air := false, sub := false) -> PlatformSpec:
	var p := PlatformSpec.new()
	p.short_name = "Test"
	p.max_speed_kn = 28.0
	p.cruise_speed_kn = 14.0
	p.turn_rate_deg_s = 6.0
	p.accel_kn_s = 1.0
	p.health = 100.0
	p.length_m = 150.0
	if sub:
		p.domain = "subsurface"
		p.max_depth_m = 300.0
		p.depth_rate_m_s = 1.0
	if air:
		p.domain = "air"
		p.max_speed_kn = 400.0
		p.cruise_speed_kn = 300.0
		p.cruise_altitude_m = 3000.0
		p.max_altitude_m = 9000.0
		p.altitude_rate_m_s = 20.0
		p.endurance_s = 36000.0
		p.turn_rate_deg_s = 3.0
		p.length_m = 18.0
	return p


func _asm(max_range := 60.0, damage := 40.0) -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = "test_asm"
	w.display_name = "Test ASM"
	w.short_name = "ASM"
	w.type = "asm"
	w.max_range_nm = max_range
	w.min_range_nm = 2.0
	w.speed_kn = 480.0
	w.turn_rate_deg_s = 30.0
	w.seeker_range_nm = 8.0
	w.damage = damage
	w.base_pk = 1.0
	w.salvo_default = 2
	w.launch_interval_s = 4.0
	return w


func _gun(damage := 15.0) -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = "test_gun"
	w.display_name = "Test gun"
	w.short_name = "GUN"
	w.type = "gun"
	w.max_range_nm = 10.0
	w.min_range_nm = 0.0
	w.speed_kn = 1500.0
	w.seeker_range_nm = 0.0
	w.damage = damage
	w.base_pk = 1.0
	w.salvo_default = 4
	w.launch_interval_s = 2.0
	return w


func _torpedo() -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = "test_torpedo"
	w.display_name = "Test torpedo"
	w.type = "torpedo"
	w.target_types = PackedStringArray(["subsurface", "surface"])
	w.max_range_nm = 12.0
	w.min_range_nm = 0.5
	w.speed_kn = 50.0
	w.damage = 30.0
	w.base_pk = 1.0
	w.salvo_default = 1
	return w


func _unit(faction: String, pos: Vector2, hp := 100.0, weapons: Array = [], rounds := 8, kind := "ship") -> Unit:
	var u := Unit.new()
	u.spec = _platform(kind == "air", kind == "sub")
	u.faction = faction
	u.callsign = "%s-%s" % [faction, kind]
	u.position = pos
	u.health = hp
	u.spec.health = hp
	if kind == "air":
		u.flight_state = Unit.FlightState.AIRBORNE
		u.fuel_s = u.spec.endurance_s
		u.altitude_m = u.spec.cruise_altitude_m
		u.ordered_altitude_m = u.spec.cruise_altitude_m
		u.speed_kn = u.spec.cruise_speed_kn
		u.ordered_speed_kn = u.spec.cruise_speed_kn
	for w: WeaponSpec in weapons:
		u.weapons.append(w)
		u.magazines[w.id] = rounds
	return u


func _track(target: Unit, identity := "HOSTILE") -> Track:
	var t := Track.new()
	t.id = "T1076"
	t.owner_faction = "BLUE"
	t.truth = target
	t.position = target.position
	t.status = Track.Status.ACTIVE
	t.domain = target.spec.domain
	t.identity = identity
	t.classification = Track.Classification.CLASS_KNOWN if identity != "UNKNOWN" else Track.Classification.SURFACE
	t.known_class = target.spec.short_name
	return t


class Harness:
	extends RefCounted
	var um: UnitManager
	var wm: WeaponManager
	var now := 0.0
	var ended: Array = []
	var resumed: Array = []
	var routes: Array = []
	## Tracks kept on their unit, as a sensor holding the contact would: position, course and speed.
	var plots: Array = []

	func step() -> void:
		now += 0.25
		for t: Track in plots:
			if t.truth != null and t.truth.alive:
				t.position = t.truth.position
				t.course_deg = t.truth.heading_deg
				t.speed_kn = t.truth.speed_kn
				t.has_kinematics = true
		um.tick(0.25, now)
		wm.tick(0.25, now)

	func advance(seconds: float, each := Callable()) -> void:
		for i in int(round(seconds / 0.25)):
			step()
			if each.is_valid():
				each.call()

	func until(predicate: Callable, limit_s: float, each := Callable()) -> bool:
		for i in int(round(limit_s / 0.25)):
			if predicate.call():
				return true
			step()
			if each.is_valid():
				each.call()
		return predicate.call()

	func free_all() -> void:
		um.free()
		wm.free()


func _harness(units: Array) -> Harness:
	Terrain.clear()
	var h := Harness.new()
	h.um = UnitManager.new()
	for u: Unit in units:
		h.um.add_unit(u)
	h.wm = WeaponManager.new()
	h.wm.unit_manager = h.um
	h.wm.rng.seed = 7
	h.um.weapon_manager = h.wm
	h.um.attack_ended.connect(func(u: Unit, t: Track, reason: String) -> void: h.ended.append([u, t, reason]))
	h.um.station_resumed.connect(func(u: Unit, reason: String) -> void: h.resumed.append([u, reason]))
	h.um.route_resumed.connect(func(u: Unit, reason: String) -> void: h.routes.append([u, reason]))
	return h


## A ship under way down a three-leg route at 13 kn.
func _transit(ship: Unit, um: UnitManager) -> Array[Vector2]:
	var route: Array[Vector2] = [Vector2(0, 40), Vector2(30, 80), Vector2(30, 160)]
	for i in route.size():
		assert_true(um.issue_order(ship, Order.move(route[i], i > 0)))
	assert_true(um.issue_order(ship, Order.set_speed(13.0)))
	ship.speed_kn = 13.0
	return route


# --- In reach: fire without touching the plan --------------------------------------------------

func test_an_escort_in_reach_fires_from_its_screen_station_and_never_slows() -> void:
	var guide := _unit("BLUE", Vector2.ZERO)
	var escort := _unit("BLUE", Vector2(4, 6), 100.0, [_asm(60.0)])
	var target := _unit("RED", Vector2(10, 45), 60.0)
	var h := _harness([guide, escort, target])
	assert_true(h.um.issue_order(guide, Order.move(Vector2(0, 300))))
	assert_true(h.um.issue_order(guide, Order.set_speed(15.0)))
	guide.speed_kn = 15.0
	escort.speed_kn = 15.0
	assert_true(h.um.issue_order(escort, Order.form_up(guide, Vector2(4, 6))))
	h.advance(180.0)
	assert_true(escort.on_station())
	var t := _track(target)
	h.plots.append(t)
	assert_true(h.um.issue_order(escort, Order.attack(t)))
	assert_eq(escort.formation_leader, guide, "an attack order on a contact in reach does not take her out of the screen")
	var slowest := [escort.speed_kn]
	var left_station := [false]
	var watch := func() -> void:
		slowest[0] = minf(slowest[0], escort.speed_kn)
		if escort.formation_leader != guide:
			left_station[0] = true
	assert_true(h.until(func() -> bool: return not h.ended.is_empty(), 1800.0, watch), "the attack runs to its end")
	assert_eq(h.ended[0][2], "Target destroyed")
	h.advance(900.0, watch)
	assert_true(slowest[0] >= 14.0, "she never slowed: slowest %.1f kn with the guide at 15" % slowest[0])
	assert_true(not left_station[0], "and never left her station")
	assert_true(escort.on_station(), "in the screen afterwards")
	assert_true(escort.position.distance_to(Formation.station_for(escort)) < 1.0, "on her station point, with the convoy")
	h.free_all()


func test_a_ship_in_reach_keeps_her_route_and_speed_through_the_attack_and_after_it() -> void:
	for ending: String in ["destroyed", "weapons hold", "cancel fire"]:
		var ship := _unit("BLUE", Vector2.ZERO, 100.0, [_asm(60.0)])
		var target := _unit("RED", Vector2(20, 30), 60.0 if ending == "destroyed" else 5000.0)
		var h := _harness([ship, target])
		var route := _transit(ship, h.um)
		var t := _track(target)
		assert_true(h.um.issue_order(ship, Order.attack(t)))
		assert_eq(ship.waypoints, route, "%s: the route stands" % ending)
		var slowest := [ship.speed_kn]
		var lowest_order := [ship.ordered_speed_kn]
		var watch := func() -> void:
			slowest[0] = minf(slowest[0], ship.speed_kn)
			lowest_order[0] = minf(lowest_order[0], ship.ordered_speed_kn)
		h.advance(30.0, watch)
		assert_true(ship.attack_rounds_fired > 0, "%s: she fires at once" % ending)
		assert_near(ship.ordered_speed_kn, 13.0, 0.01, "%s: thirty seconds in, still ordered 13 kn" % ending)
		match ending:
			"destroyed":
				assert_true(h.until(func() -> bool: return not h.ended.is_empty(), 1800.0, watch))
				assert_eq(h.ended[0][2], "Target destroyed")
			"weapons hold":
				assert_true(h.um.issue_order(ship, Order.set_roe(Unit.Roe.HOLD)))
				h.advance(1.0, watch)
				assert_eq(ship.attack_result, "Weapons hold")
			"cancel fire":
				assert_true(h.um.issue_order(ship, Order.cancel_fire(t)))
				h.advance(1.0, watch)
				assert_eq(ship.attack_result, "Fire cancelled")
		assert_eq(ship.attack_track, null, ending)
		h.advance(900.0, watch)
		assert_true(slowest[0] >= 12.9, "%s: never below her transit speed (slowest %.1f kn)" % [ending, slowest[0]])
		assert_near(lowest_order[0], 13.0, 0.01, "%s: nobody ordered her slower" % ending)
		assert_true(ship.waypoints.size() >= 2 and ship.waypoints.back() == route.back(), "%s: still on her route fifteen minutes later" % ending)
		h.free_all()


func test_a_ship_on_patrol_in_reach_stays_on_her_circuit() -> void:
	var picket := _unit("BLUE", Vector2.ZERO, 100.0, [_asm(60.0)])
	var target := _unit("RED", Vector2(0, 40), 60.0)
	var h := _harness([picket, target])
	assert_true(h.um.issue_order(picket, Order.patrol_box(Vector2(-8, -8), Vector2(8, 8))))
	h.advance(60.0)
	assert_true(h.um.issue_order(picket, Order.attack(_track(target))))
	assert_true(picket.patrol_active, "the circuit is not suspended for a contact she can already reach")
	assert_true(h.until(func() -> bool: return not h.ended.is_empty(), 1800.0))
	assert_true(picket.patrol_active and picket.on_station(), "and she is still flying it when the attack ends")
	assert_true(h.resumed.is_empty(), "there was no station to go back to: she never left it")
	h.free_all()


# --- Must close: remember the plan, close briskly, restore it ----------------------------------

func test_a_ship_that_must_close_does_so_fast_and_resumes_her_route_however_the_attack_ends() -> void:
	for ending: String in ["destroyed", "weapons hold", "cancel fire", "contact lost", "magazines empty"]:
		var ship := _unit("BLUE", Vector2.ZERO, 100.0, [_asm(60.0, 40.0)], 2 if ending == "magazines empty" else 8)
		var target := _unit("RED", Vector2(40, 70), 60.0 if ending == "destroyed" else 5000.0)
		var h := _harness([ship, target])
		var route := _transit(ship, h.um)
		h.advance(60.0)
		var t := _track(target)
		assert_true(h.um.issue_order(ship, Order.attack(t)))
		assert_eq(ship.waypoints.size(), 1, "%s: the intercept leg replaces the route" % ending)
		assert_near(ship.ordered_speed_kn, 0.85 * 28.0, 0.01, "%s: she closes at most of her speed, not at 13 kn" % ending)
		var slowest := [ship.speed_kn]
		var watch := func() -> void: slowest[0] = minf(slowest[0], ship.speed_kn)
		match ending:
			"destroyed", "magazines empty":
				assert_true(h.until(func() -> bool: return not h.ended.is_empty(), 7200.0, watch), ending)
				assert_eq(h.ended[0][2], "Target destroyed" if ending == "destroyed" else "Magazines empty")
			"weapons hold":
				h.advance(600.0, watch)
				assert_true(h.um.issue_order(ship, Order.set_roe(Unit.Roe.HOLD)))
				h.advance(1.0, watch)
			"cancel fire":
				h.advance(600.0, watch)
				assert_true(h.um.issue_order(ship, Order.cancel_fire(t)))
				h.advance(1.0, watch)
			"contact lost":
				h.advance(600.0, watch)
				t.status = Track.Status.LOST
				h.advance(1.0, watch)
		assert_eq(ship.attack_track, null, ending)
		assert_eq(ship.waypoints, route, "%s: the route she was on is hers again" % ending)
		assert_near(ship.ordered_speed_kn, 13.0, 0.01, "%s: at the speed she was sailing it" % ending)
		h.advance(900.0, watch)
		assert_true(slowest[0] >= 12.9, "%s: never dead in the water (slowest %.1f kn)" % [ending, slowest[0]])
		assert_near(ship.speed_kn, 13.0, 0.2, "%s: making her transit speed fifteen minutes later" % ending)
		assert_true(not ship.plan_kept, "%s: nothing left over to restore a second time" % ending)
		h.free_all()


func test_a_speed_order_during_the_attack_overrides_the_closing_speed() -> void:
	var ship := _unit("BLUE", Vector2.ZERO, 100.0, [_asm(60.0)])
	var target := _unit("RED", Vector2(0, 150), 5000.0)
	var h := _harness([ship, target])
	assert_true(h.um.issue_order(ship, Order.attack(_track(target))))
	assert_near(ship.ordered_speed_kn, 23.8, 0.01)
	assert_true(h.um.issue_order(ship, Order.set_speed(9.0)))
	h.advance(120.0)
	assert_near(ship.ordered_speed_kn, 9.0, 0.01, "the commander's speed stands for the closing leg")
	assert_true(ship.has_route(), "and she is still closing")
	h.free_all()


func test_a_newer_navigation_order_stands_and_the_old_plan_is_not_restored() -> void:
	var ship := _unit("BLUE", Vector2.ZERO, 100.0, [_asm(60.0)])
	var target := _unit("RED", Vector2(60, 90), 5000.0)
	var h := _harness([ship, target])
	_transit(ship, h.um)
	var t := _track(target)
	assert_true(h.um.issue_order(ship, Order.attack(t)))
	h.advance(120.0)
	assert_true(h.um.issue_order(ship, Order.move(Vector2(-50, 0))))
	assert_eq(ship.attack_track, null, "a new transit replaces the attack")
	h.advance(600.0)
	assert_eq(ship.waypoints, [Vector2(-50, 0)], "and it is the new transit she is on, not the old route")
	h.free_all()


func test_with_no_route_a_hull_keeps_her_course_and_her_speed_from_before_the_attack() -> void:
	var ship := _unit("BLUE", Vector2.ZERO, 100.0, [_asm(60.0)])
	var target := _unit("RED", Vector2(70, 70), 60.0)
	var h := _harness([ship, target])
	assert_true(h.um.issue_order(ship, Order.set_course(90.0)))
	assert_true(h.um.issue_order(ship, Order.set_speed(12.0)))
	h.advance(120.0)
	assert_true(h.um.issue_order(ship, Order.attack(_track(target))))
	assert_true(h.until(func() -> bool: return not h.ended.is_empty(), 7200.0))
	assert_eq(h.ended[0][2], "Target destroyed")
	assert_near(ship.ordered_speed_kn, 12.0, 0.01, "the speed she had before the attack")
	assert_near(ship.ordered_heading_deg, ship.heading_deg, 0.01, "on the course the attack left her on")
	h.advance(600.0)
	assert_near(ship.speed_kn, 12.0, 0.2, "ten minutes later she is still under way")
	h.free_all()


func test_a_consort_that_leaves_the_screen_to_close_rejoins_it_by_default() -> void:
	var guide := _unit("BLUE", Vector2.ZERO)
	var escort := _unit("BLUE", Vector2(4, 6), 100.0, [_gun(30.0)], 400)
	var target := _unit("RED", Vector2(20, 30), 60.0)
	var h := _harness([guide, escort, target])
	assert_true(h.um.issue_order(guide, Order.move(Vector2(0, 300))))
	assert_true(h.um.issue_order(guide, Order.set_speed(12.0)))
	assert_true(h.um.issue_order(escort, Order.form_up(guide, Vector2(4, 6))))
	h.advance(120.0)
	var t := _track(target)
	h.plots.append(t)
	assert_true(escort.auto_return, "returning to station is the default")
	assert_true(h.um.issue_order(escort, Order.attack(t)))
	assert_eq(escort.formation_leader, null, "out of gun range she has to leave the screen to close")
	assert_eq(escort.station_kind, "formation", "the station is kept for her")
	assert_true(h.until(func() -> bool: return not h.ended.is_empty(), 7200.0))
	assert_eq(h.ended[0][2], "Target destroyed")
	assert_eq(escort.formation_leader, guide, "the kill sends her back to her station without an order")
	assert_eq(h.resumed, [[escort, "Target destroyed"]])
	assert_true(h.until(func() -> bool: return escort.position.distance_to(Formation.station_for(escort)) < 0.5, 7200.0), "she catches the convoy up and takes her station")
	h.advance(300.0)
	assert_true(escort.on_station() and escort.speed_kn > 10.0, "and stays on it, under way with the guide")
	h.free_all()


func test_an_investigation_hands_back_the_route_it_interrupted() -> void:
	var ship := _unit("BLUE", Vector2.ZERO)
	var contact := _unit("RED", Vector2(25, 10))
	var h := _harness([ship, contact])
	var route := _transit(ship, h.um)
	var t := _track(contact, "UNKNOWN")
	assert_true(h.um.issue_order(ship, Order.investigate(t)))
	assert_eq(ship.waypoints, [t.position])
	h.advance(300.0)
	t.classification = Track.Classification.IDENTIFIED
	t.identity = "NEUTRAL"
	h.advance(DT)
	assert_eq(ship.investigation_track, null)
	assert_eq(ship.investigation_result, "Contact classified")
	assert_eq(ship.waypoints, route, "the look is over: back on the route")
	assert_eq(h.routes, [[ship, "Contact classified"]], "and the crew can be heard saying so")
	assert_near(ship.ordered_speed_kn, 13.0, 0.01, "at its speed")
	h.free_all()


func test_an_attack_that_follows_an_investigation_still_restores_the_first_plan() -> void:
	var ship := _unit("BLUE", Vector2.ZERO, 100.0, [_asm(60.0)])
	var contact := _unit("RED", Vector2(40, 70), 60.0)
	var h := _harness([ship, contact])
	var route := _transit(ship, h.um)
	var t := _track(contact, "UNKNOWN")
	assert_true(h.um.issue_order(ship, Order.investigate(t)))
	h.advance(120.0)
	assert_true(h.um.issue_order(ship, Order.attack(t)), "the look turns into an attack before it is finished")
	assert_eq(ship.investigation_track, null)
	assert_true(h.until(func() -> bool: return not h.ended.is_empty(), 7200.0))
	assert_eq(ship.waypoints, route, "the route the investigation interrupted, not the leg to the contact")
	assert_near(ship.ordered_speed_kn, 13.0, 0.01)
	h.free_all()


# --- In range after closing: keep way on, hold the band ------------------------------------------

## The range sampled once a minute for `minutes`, with the slowest speed seen on the way.
func _watch_range(h: Harness, ship: Unit, target: Unit, minutes: int) -> Dictionary:
	var ranges: Array[float] = []
	var slowest := [INF]
	for m in minutes:
		h.advance(60.0, func() -> void: slowest[0] = minf(slowest[0], ship.speed_kn))
		ranges.append(ship.position.distance_to(target.position))
	var turns := 0
	for i in range(2, ranges.size()):
		var before := ranges[i - 1] - ranges[i - 2]
		var after := ranges[i] - ranges[i - 1]
		if absf(before) > 0.05 and absf(after) > 0.05 and signf(before) != signf(after):
			turns += 1
	return {"ranges": ranges, "slowest": slowest[0], "turns": turns, "low": ranges.min(), "high": ranges.max()}


func test_a_ship_in_gun_range_keeps_way_on_and_a_steady_range_for_thirty_minutes() -> void:
	for moving: bool in [false, true]:
		var gun := _gun(0.001)
		var ship := _unit("BLUE", Vector2.ZERO, 100.0, [gun], 100000)
		var target := _unit("RED", Vector2(0, 30), 1.0e9)
		var h := _harness([ship, target])
		if moving:
			target.heading_deg = 70.0
			target.ordered_heading_deg = 70.0
			target.speed_kn = 10.0
			target.ordered_speed_kn = 10.0
		var t := _track(target)
		h.plots.append(t)
		assert_true(h.um.issue_order(ship, Order.attack(t)))
		assert_true(h.until(func() -> bool: return ship.attack_rounds_fired > 0, 7200.0), "she closes and opens fire")
		h.advance(300.0)  # settled
		var seen := _watch_range(h, ship, target, 30)
		var label := "moving contact" if moving else "stopped contact"
		assert_true(ship.attack_track != null and h.ended.is_empty(), "%s: the attack is still running" % label)
		assert_true(float(seen["slowest"]) >= 3.0, "%s: she never stops (slowest %.1f kn)" % [label, seen["slowest"]])
		assert_true(float(seen["high"]) <= 10.0, "%s: she stays in gun range (out to %.1f nm)" % [label, seen["high"]])
		assert_true(float(seen["low"]) >= 5.0, "%s: without creeping in on the contact (in to %.1f nm)" % [label, seen["low"]])
		assert_true(float(seen["high"]) - float(seen["low"]) <= 1.5, "%s: the range holds steady (%.1f to %.1f nm)" % [label, seen["low"], seen["high"]])
		assert_true(int(seen["turns"]) <= 2, "%s: and does not swing in and out (%d reversals: %s)" % [label, seen["turns"], seen["ranges"]])
		h.free_all()


func test_a_boat_that_has_fired_keeps_steerage_way_and_goes_back_to_her_patrol_speed() -> void:
	var boat := _unit("BLUE", Vector2.ZERO, 100.0, [_torpedo()], 4, "sub")
	var target := _unit("RED", Vector2(0, 30), 60.0, [], 0, "sub")
	target.heading_deg = 90.0
	target.ordered_heading_deg = 90.0
	target.speed_kn = 5.0
	target.ordered_speed_kn = 5.0
	var h := _harness([boat, target])
	assert_true(h.um.issue_order(boat, Order.set_course(0.0)))
	assert_true(h.um.issue_order(boat, Order.set_speed(7.0)))
	boat.speed_kn = 7.0
	var t := _track(target)
	h.plots.append(t)
	assert_true(h.um.issue_order(boat, Order.attack(t)))
	assert_near(boat.ordered_speed_kn, boat.spec.cruise_speed_kn, 0.01, "a boat closes at her cruise, not at a sprint that deafens her")
	var slowest := [boat.speed_kn]
	var watch := func() -> void: slowest[0] = minf(slowest[0], boat.speed_kn)
	assert_true(h.until(func() -> bool: return boat.attack_rounds_fired > 0, 14400.0, watch), "she closes and fires")
	assert_true(h.until(func() -> bool: return not h.ended.is_empty(), 7200.0, watch), "and the attack comes to an end")
	assert_true(slowest[0] >= 3.0, "with way on throughout, able to turn (slowest %.1f kn)" % slowest[0])
	assert_near(boat.ordered_speed_kn, 7.0, 0.01, "afterwards she is back at the speed she was ordered before")
	h.advance(600.0, watch)
	assert_true(slowest[0] >= 3.0, "and still under way ten minutes later")
	h.free_all()


# --- The remembered plan is part of a saved game ------------------------------------------------

func test_the_remembered_plan_survives_a_save() -> void:
	var ship := _unit("BLUE", Vector2.ZERO, 100.0, [_asm(60.0)])
	var target := _unit("RED", Vector2(60, 90), 5000.0)
	var h := _harness([ship, target])
	var route := _transit(ship, h.um)
	assert_true(h.um.issue_order(ship, Order.attack(_track(target))))
	h.advance(60.0)
	var names := SimSnapshot.script_variables(ship)
	var refs := SimSnapshot.Refs.new()
	var saved := {}
	for field: String in ["plan_kept", "plan_waypoints", "plan_speed_kn", "attack_holding", "attack_speed_ordered", "attack_progress_pos"]:
		assert_true(names.has(field) and not SimSnapshot.UNIT_SKIP.has(field), "%s is saved" % field)
		saved[field] = refs.enc(ship.get(field))
	var loaded := Unit.new()
	SimSnapshot._fill(loaded, bytes_to_var(var_to_bytes(saved)), refs)
	assert_true(loaded.plan_kept)
	assert_eq(loaded.plan_waypoints, route)
	assert_near(loaded.plan_speed_kn, 13.0, 0.01)
	var old_save := Unit.new()
	SimSnapshot._fill(old_save, {"auto_return": false}, refs)
	assert_true(not old_save.plan_kept and old_save.plan_waypoints.is_empty(), "a save from before the plan was remembered loads with none")
	h.free_all()


# --- Fixed-wing aircraft: stand off, then hold ---------------------------------------------------

func test_a_strike_aircraft_holds_off_the_ship_it_fired_at_and_holds_when_the_attack_ends() -> void:
	# Out of range and closing, in range on a bare course straight at the target, and in range on a
	# route that runs on over the target: none of them may fly in on the ship after release.
	for approach: String in ["closing from out of range", "on a course at the target", "on a route over the target"]:
		var strike := _unit("BLUE", Vector2(0, -150) if approach == "closing from out of range" else Vector2(0, -55), 100.0, [_asm(60.0)], 4, "air")
		var target := _unit("RED", Vector2.ZERO, 5000.0)
		var h := _harness([strike, target])
		if approach == "on a route over the target":
			assert_true(h.um.issue_order(strike, Order.move(Vector2(0, 200))))
		var t := _track(target)
		assert_true(h.um.issue_order(strike, Order.attack(t)), approach)
		var released_at := [-1.0]
		var closest := [INF]
		var slowest := [INF]
		var held := [false]
		var watch := func() -> void:
			slowest[0] = minf(slowest[0], strike.speed_kn)
			if strike.attack_rounds_fired > 0:
				if released_at[0] < 0.0:
					released_at[0] = strike.position.distance_to(target.position)
				closest[0] = minf(closest[0], strike.position.distance_to(target.position))
				if strike.attack_track != null and strike.holding():
					held[0] = true
		assert_true(h.until(func() -> bool: return not h.ended.is_empty(), 3600.0, watch), approach)
		assert_eq(h.ended[0][2], "Magazines empty", approach)
		assert_true(released_at[0] > 40.0, "%s: it releases from stand-off range (%.1f nm)" % [approach, released_at[0]])
		assert_true(closest[0] >= 0.7 * released_at[0], "%s: after release it comes no nearer than 0.7 of the firing range (closest %.1f, fired at %.1f nm)" % [approach, closest[0], released_at[0]])
		assert_true(held[0], "%s: it waits for the result in a hold on its own side of the target" % approach)
		assert_true(slowest[0] >= strike.spec.flight_speed("patrol") * Movement.MIN_FLYING_FRACTION, "%s: never below flying speed" % approach)
		if approach == "on a route over the target":
			assert_eq(strike.waypoints, [Vector2(0, 200)], "the route it was on is its own again once the attack is over")
		else:
			assert_true(strike.holding(), "%s: with nowhere to go back to, it holds where the attack ended" % approach)
			var ended_at := strike.position
			h.advance(2400.0)
			assert_true(strike.position.distance_to(ended_at) < 25.0, "%s: forty minutes later it is still there, not %.0f nm away on its last heading" % [approach, strike.position.distance_to(ended_at)])
		h.free_all()


func test_a_fighter_holds_where_its_intercept_ended_instead_of_flying_on_to_bingo() -> void:
	var aam := _asm(40.0, 200.0)
	aam.type = "aam"
	aam.target_types = PackedStringArray(["air"])
	aam.speed_kn = 2400.0
	var fighter := _unit("BLUE", Vector2.ZERO, 100.0, [aam], 4, "air")
	var bandit := _unit("RED", Vector2(0, 130), 100.0, [], 0, "air")
	bandit.heading_deg = 180.0
	bandit.ordered_heading_deg = 180.0
	var h := _harness([fighter, bandit])
	var t := _track(bandit)
	h.plots.append(t)
	assert_true(h.um.issue_order(fighter, Order.attack(t)))
	assert_true(h.until(func() -> bool: return not h.ended.is_empty(), 1800.0), "the intercept is flown and ends")
	assert_eq(h.ended[0][2], "Target destroyed")
	assert_true(fighter.holding(), "with the bandit down and no station to go back to, the fighter holds")
	var ended_at := fighter.position
	h.advance(2640.0)
	assert_true(fighter.position.distance_to(ended_at) < 25.0, "44 minutes later it is %.0f nm from where the intercept ended" % fighter.position.distance_to(ended_at))
	h.free_all()


# --- The read-out after the crew goes back to station ---------------------------------------------

func test_the_result_stays_on_the_read_out_after_the_crew_returns_to_station() -> void:
	var guide := _unit("BLUE", Vector2.ZERO)
	guide.callsign = "Guide"
	var escort := _unit("BLUE", Vector2(4, 6), 100.0, [_gun(30.0)], 400)
	var target := _unit("RED", Vector2(14, 22), 60.0)
	var h := _harness([guide, escort, target])
	assert_true(h.um.issue_order(guide, Order.move(Vector2(0, 300))))
	assert_true(h.um.issue_order(guide, Order.set_speed(12.0)))
	var form := Order.form_up(guide, Vector2(4, 6))
	form.station_label = "SCREEN STATION"
	assert_true(h.um.issue_order(escort, form))
	h.advance(60.0)
	var t := _track(target)
	assert_true(h.um.issue_order(escort, Order.attack(t)))
	assert_true(h.until(func() -> bool: return not h.ended.is_empty(), 7200.0))
	h.advance(DT)
	assert_true(escort.on_station(), "the crew has gone back to the screen")
	assert_eq(escort.attack_result, "Target destroyed", "and what the attack achieved is still on the read-out")
	assert_eq(escort.attack_track_id, t.id, "against the track it concerned")
	var line := DataDisplay.orders_text(escort)
	assert_true(line.begins_with("Returning to screen station"), "the line says what she is doing now first: %s" % line)
	assert_true(line.ends_with("Target destroyed"), "then what the task found: %s" % line)
	assert_true(h.until(func() -> bool: return escort.position.distance_to(escort.station_point()) < 0.5, 7200.0))
	assert_true(DataDisplay.orders_text(escort).begins_with("On screen station"), DataDisplay.orders_text(escort))
	assert_true(h.um.issue_order(escort, Order.break_formation()))
	assert_eq(escort.attack_result, "", "the commander's next navigation order clears it")
	h.free_all()


func test_an_aircraft_on_its_way_home_says_so_before_it_repeats_an_old_result() -> void:
	var jet := _unit("BLUE", Vector2.ZERO, 100.0, [_asm(60.0)], 4, "air")
	jet.attack_track_id = "T1001"
	jet.attack_result = "Target destroyed"
	assert_eq(DataDisplay.orders_text(jet), "Track 1001: Target destroyed")
	jet.returning = true
	assert_eq(DataDisplay.orders_text(jet), "Return to base · Track 1001: Target destroyed")


func test_the_identification_result_survives_the_return_to_a_patrol() -> void:
	var picket := _unit("BLUE", Vector2.ZERO)
	var contact := _unit("RED", Vector2(30, 5))
	var h := _harness([picket, contact])
	assert_true(h.um.issue_order(picket, Order.patrol_box(Vector2(-8, -8), Vector2(8, 8))))
	h.advance(30.0)
	var t := _track(contact, "UNKNOWN")
	assert_true(h.um.issue_order(picket, Order.investigate(t)))
	h.advance(60.0)
	t.classification = Track.Classification.IDENTIFIED
	t.identity = "NEUTRAL"
	h.advance(1.0)
	assert_true(picket.patrol_active, "the look is over and she is back on her circuit")
	assert_eq(picket.investigation_result, "Contact classified", "with what she found still readable")
	assert_eq(picket.investigation_track_id, t.id)
	h.free_all()


# --- Land in the way ---------------------------------------------------------------------------

func _skimmer() -> WeaponSpec:
	var asm := _asm(60.0)
	asm.profile = "sea_skimming"
	return asm


func _land(points: Array) -> void:
	Terrain.load_from({"terrain": {"land": [{"id": "isle", "name": "Isle", "elevation_m": 80.0, "points_nm": points}]}})


func test_land_in_the_line_of_fire_sends_the_ship_to_the_nearest_clear_water_she_can_reach() -> void:
	var ship := _unit("BLUE", Vector2.ZERO, 100.0, [_skimmer()])
	var target := _unit("RED", Vector2(0, 30), 800.0)
	var h := _harness([ship, target])
	_land([[-3, 12], [3, 12], [3, 18], [-3, 18]])
	assert_true(Terrain.blocks_path(ship.position, target.position), "the fixture puts an island in the way")
	assert_true(h.um.issue_order(ship, Order.attack(_track(target))))
	h.advance(DT)
	assert_eq(ship.attack_phase, "Intercept track · clearing the line of fire")
	assert_eq(ship.waypoints.size(), 1)
	var point: Vector2 = ship.waypoints[0]
	assert_true(not Terrain.blocks_path(point, target.position), "the point has an open line to the target")
	assert_true(Terrain.reachable_by_sea(ship.position, point), "and she can sail to it")
	assert_true(point.distance_to(ship.position) < 16.0, "a short move round the island, not the far edge of the weapon's reach (%.1f nm away)" % point.distance_to(ship.position))
	var before := ship.position
	assert_true(h.until(func() -> bool: return ship.attack_rounds_fired > 0, 3600.0), "and she fires from there")
	assert_true(ship.position.distance_to(before) < 16.0, "having moved %.1f nm" % ship.position.distance_to(before))
	Terrain.clear()
	h.free_all()


func test_an_attack_with_no_clear_water_in_reach_ends_instead_of_steering_at_the_coast() -> void:
	var ship := _unit("BLUE", Vector2.ZERO, 100.0, [_skimmer()])
	var target := _unit("RED", Vector2(0, 30), 800.0)
	var h := _harness([ship, target])
	# A long bar of land between them: every point with a line to the target is on its far side.
	_land([[-300, 10], [300, 10], [300, 12], [-300, 12]])
	assert_true(h.um.issue_order(ship, Order.attack(_track(target))))
	h.advance(5.0)
	assert_eq(h.ended.size(), 1, "the attack is given back at once")
	assert_eq(h.ended[0][2], "No line of fire")
	assert_true(ship.waypoints.is_empty(), "and she is not sent at the shore")
	h.advance(600.0)
	assert_true(Terrain.distance_to_land_nm(ship.position) > 5.0, "ten minutes later she is nowhere near it")
	Terrain.clear()
	h.free_all()


func test_a_hull_pressed_against_a_coast_on_its_way_to_fire_gives_the_attack_back() -> void:
	var ship := _unit("BLUE", Vector2.ZERO, 100.0, [_asm(60.0)])
	var target := _unit("RED", Vector2(0, 100), 800.0)
	var h := _harness([ship, target])
	_land([[-60, 8], [60, 8], [60, 10], [-60, 10]])
	assert_true(h.um.issue_order(ship, Order.attack(_track(target))))
	assert_true(ship.has_route(), "she sets off for her firing point")
	# She runs onto the bar that lies across the leg: engines turning, a route, and no way made.
	assert_true(h.until(func() -> bool: return not h.ended.is_empty(), 3600.0), "the attack does not stay open for ever with her aground")
	assert_true(str(h.ended[0][2]).begins_with("Cannot engage"), str(h.ended[0][2]))
	assert_true(h.now < 1800.0 + UnitManager.ATTACK_STALL_S, "within minutes of stopping (ended at %.0f s)" % h.now)
	assert_eq(ship.attack_rounds_fired, 0)
	Terrain.clear()
	h.free_all()


func test_a_long_stern_chase_is_not_mistaken_for_a_stall() -> void:
	var ship := _unit("BLUE", Vector2.ZERO, 100.0, [_asm(60.0)])
	var target := _unit("RED", Vector2(0, 100), 800.0)
	target.heading_deg = 0.0
	target.ordered_heading_deg = 0.0
	target.speed_kn = 26.0
	target.ordered_speed_kn = 26.0
	var h := _harness([ship, target])
	var t := _track(target)
	h.plots.append(t)
	assert_true(h.um.issue_order(ship, Order.attack(t)))
	h.advance(1800.0)
	assert_true(h.ended.is_empty(), "half an hour into a chase she is not winning, the attack still stands")
	assert_true(ship.speed_kn > 20.0, "and she is still chasing")
	h.free_all()


# --- Aircraft speed, and the helicopter in the dip ----------------------------------------------

func _helo() -> Unit:
	var u := Unit.new()
	u.spec = DataDB.platform("usn_helo_mh60r")
	for id: String in u.spec.sensor_ids:
		u.sensors.append(DataDB.sensor(id))
	var torpedo := DataDB.weapon("mk54_lwt")
	u.weapons.append(torpedo)
	u.magazines[torpedo.id] = 2
	u.flight_state = Unit.FlightState.AIRBORNE
	u.fuel_s = u.spec.endurance_s
	u.faction = "BLUE"
	u.callsign = "Helo"
	u.altitude_m = 20.0
	u.ordered_altitude_m = u.spec.cruise_altitude_m
	u.ordered_speed_kn = 1.0  # as the hover left it
	return u


func _boat_at(pos: Vector2) -> Unit:
	var boat := _unit("RED", pos, 100.0, [], 0, "sub")
	boat.depth_m = 60.0
	boat.ordered_depth_m = 60.0
	return boat


## The helicopter in the dip, holding the boat as a bearing: the plot is a guess far down the line.
func _dipping(h: Harness, helo: Unit, boat: Unit) -> Track:
	assert_true(h.um.issue_order(helo, Order.deploy_dipping_sonar(0.0)))
	assert_true(h.until(func() -> bool: return DippingSonar.listening(helo), 120.0), "the dome is down")
	var t := _track(boat)
	t.position = helo.position + (boat.position - helo.position).normalized() * 20.0
	t.bearing_only = true
	t.tma_quality = 0.0
	t.source = "sonar_passive"
	t.contributors[helo] = h.now
	return t


func test_a_dipping_helicopter_stays_in_the_dip_and_pings_for_a_range_on_its_own_contact() -> void:
	var helo := _helo()
	var boat := _boat_at(Vector2(0, 1.5))
	var h := _harness([helo, boat])
	var t := _dipping(h, helo, boat)
	var hover := helo.position
	assert_true(not helo.active_sonar_on)
	assert_true(h.um.issue_order(helo, Order.attack(t)), "a bearing is enough to order a torpedo attack")
	h.advance(60.0)
	assert_true(DippingSonar.listening(helo), "the dome stays down: it is the only thing holding the contact")
	assert_true(helo.position.distance_to(hover) < 0.05, "and the helicopter does not fly off to the plotted guess")
	assert_true(helo.active_sonar_on, "it goes active for a range")
	assert_eq(helo.attack_phase, "Attack track · localising, sonar active")
	assert_eq(helo.attack_rounds_fired, 0)
	# The ping returns a range: the boat is close aboard, well inside torpedo range.
	t.bearing_only = false
	t.position = boat.position
	assert_true(h.until(func() -> bool: return helo.attack_rounds_fired > 0, 60.0), "with a range it drops on the contact")
	assert_true(helo.position.distance_to(hover) < 0.05, "from the hover")
	assert_true(DippingSonar.listening(helo), "with the dome still down to watch the result")
	h.free_all()


func test_a_silenced_helicopter_keeps_listening_and_one_with_no_range_to_be_had_runs_down_the_bearing() -> void:
	var helo := _helo()
	var boat := _boat_at(Vector2(0, 1.5))
	var h := _harness([helo, boat])
	var t := _dipping(h, helo, boat)
	var hover := helo.position
	assert_true(h.um.issue_order(helo, Order.set_emcon(true)))
	assert_true(h.um.issue_order(helo, Order.attack(t)))
	h.advance(60.0)
	assert_true(not helo.active_sonar_on, "emissions are silenced: it does not ping")
	assert_eq(helo.attack_phase, "Attack track · localising, sonar passive")
	assert_true(DippingSonar.listening(helo))
	h.advance(UnitManager.ATTACK_LOCALISE_S)
	assert_true(not DippingSonar.listening(helo), "no range to be had from here: the dome comes up")
	assert_true(helo.attack_track == t, "and the attack goes on down the bearing")
	h.advance(180.0)
	assert_true(helo.speed_kn >= helo.spec.cruise_speed_kn - 1.0, "at cruise, not at the knot the hover left ordered (%.0f kn)" % helo.speed_kn)
	assert_true(helo.position.distance_to(hover) > 2.0, "it has moved off: %.1f nm" % helo.position.distance_to(hover))
	h.free_all()


func test_an_aircraft_never_flies_a_task_below_its_cruise() -> void:
	for task: String in ["attack", "investigate"]:
		var helo := _helo()
		var contact := _unit("RED", Vector2(0, 40), 800.0)
		var h := _harness([helo, contact])
		helo.weapons.append(_asm(10.0))
		helo.magazines["test_asm"] = 2
		var t := _track(contact, "HOSTILE" if task == "attack" else "UNKNOWN")
		assert_true(h.um.issue_order(helo, Order.attack(t) if task == "attack" else Order.investigate(t)), task)
		assert_true(helo.ordered_speed_kn >= helo.spec.cruise_speed_kn, "%s: ordered %.0f kn, cruise %.0f" % [task, helo.ordered_speed_kn, helo.spec.cruise_speed_kn])
		h.advance(120.0)
		assert_true(helo.speed_kn >= helo.spec.cruise_speed_kn - 1.0, "%s: flown at %.0f kn" % [task, helo.speed_kn])
		h.free_all()


# --- Identify a contact whose class is known and whose allegiance is not --------------------------

func test_a_contact_of_known_class_and_unknown_allegiance_can_still_be_closed_and_looked_at() -> void:
	var helo := _helo()
	var merchant := _unit("GREEN", Vector2(0, 20))
	var h := _harness([helo, merchant])
	var t := _track(merchant, "UNKNOWN")
	t.classification = Track.Classification.CLASS_KNOWN
	t.known_class = "Merchant"
	assert_eq(UnitManager.investigation_rejection(helo, t), "", "class from a library, allegiance unknown: worth a look")
	assert_true(h.um.issue_order(helo, Order.investigate(t)))
	assert_eq(helo.investigation_track, t)
	h.advance(120.0)
	assert_eq(helo.investigation_track, t, "the look goes on until the allegiance is known")
	assert_true(helo.position.y > 2.0, "and the helicopter is closing the contact")
	t.classification = Track.Classification.IDENTIFIED
	t.identity = "NEUTRAL"
	h.advance(DT)
	assert_eq(helo.investigation_track, null)
	assert_eq(helo.investigation_result, "Contact classified")
	assert_eq(UnitManager.investigation_rejection(helo, t), "Contact classified", "an identified contact needs no second look")
	h.free_all()


# --- A consort firing from its station that becomes the guide -------------------------------------

func test_a_consort_attacking_from_station_takes_over_the_lost_guides_route() -> void:
	var guide := _unit("BLUE", Vector2.ZERO)
	var escort := _unit("BLUE", Vector2(4, 6), 100.0, [_asm(60.0)])
	var target := _unit("RED", Vector2(10, 45), 5000.0)
	var h := _harness([guide, escort, target])
	assert_true(h.um.issue_order(guide, Order.move(Vector2(0, 300))))
	assert_true(h.um.issue_order(guide, Order.set_speed(15.0)))
	assert_true(h.um.issue_order(escort, Order.form_up(guide, Vector2(4, 6))))
	h.advance(60.0)
	assert_true(h.um.issue_order(escort, Order.attack(_track(target))))
	h.advance(30.0)
	assert_true(escort.attack_track != null and escort.on_station(), "firing from her station")
	guide.alive = false
	h.advance(DT)
	assert_eq(escort.waypoints, [Vector2(0, 300)], "the convoy's route is hers now, attack or no attack")
	assert_near(escort.ordered_speed_kn, 15.0, 0.01)
	assert_true(escort.attack_track != null, "and the attack goes on")
	h.free_all()
