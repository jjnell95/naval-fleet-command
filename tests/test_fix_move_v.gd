extends TestCase
## A standing attack is bounded by what the platform is for: an escort fires from her screen
## station and is never taken out of it to chase, a hull gives up a chase it cannot win, a patrol
## of two corners can be returned to, and a hull holding its range keeps clear of the coast.

const DT := 0.25


## A catalogue platform fitted as a scenario fits it.
func _ship(platform_id: String, faction: String, pos: Vector2) -> Unit:
	var spec := DataDB.platform(platform_id)
	var u := Unit.new()
	u.spec = spec
	u.faction = faction
	u.callsign = "%s %s" % [faction, platform_id]
	u.position = pos
	u.health = spec.health
	for wid: String in spec.weapon_loadout:
		var w := DataDB.weapon(wid)
		if w != null:
			u.weapons.append(w)
			u.magazines[wid] = int(spec.weapon_loadout[wid])
	return u


## The shooter's plot of a target, laid on it afresh each step with the motion the plot holds.
func _track(target: Unit) -> Track:
	var t := Track.new()
	t.id = "T2001"
	t.owner_faction = "BLUE"
	t.truth = target
	t.status = Track.Status.ACTIVE
	t.domain = "surface"
	t.identity = "HOSTILE"
	t.classification = Track.Classification.CLASS_KNOWN
	t.known_class = target.spec.short_name
	t.position_error_nm = 0.3
	_plot(t, target)
	return t


func _plot(t: Track, target: Unit) -> void:
	t.position = target.position
	t.course_deg = target.heading_deg
	t.speed_kn = target.speed_kn
	t.has_kinematics = true


func _managers(units: Array) -> Array:
	Terrain.clear()
	var um := UnitManager.new()
	for u: Unit in units:
		um.add_unit(u)
	var wm := WeaponManager.new()
	wm.unit_manager = um
	wm.rng.seed = 11
	um.weapon_manager = wm
	return [um, wm]


# --- An escort is not taken out of the screen to chase ------------------------------------------

func test_escort_attacking_in_northern_passage_fires_from_the_screen_and_never_leaves_it() -> void:
	Terrain.clear()
	Detection.set_environment({})
	var sim := Simulation.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	assert_true(sim.load_scenario("res://data/scenarios/northern_passage.json"))
	SimClock.set_paused(true)
	var frigate: Unit = null
	for u: Unit in sim.unit_manager.get_faction_units("BLUE"):
		if u.spec.id == "rnon_ffg_fridtjof_nansen":
			frigate = u
	assert_true(frigate != null, "the escort frigate is in the scenario")
	var fired := [0]
	sim.weapon_manager.round_fired.connect(func(u: Unit, _spec: WeaponSpec, _t: Track) -> void:
		if u == frigate:
			fired[0] += 1)
	var ordered := false
	var furthest := 0.0
	while SimClock.sim_time < 900.0 and frigate.alive:
		SimClock.advance(1.0)
		if not ordered and SimClock.sim_time >= 186.0:
			for t: Track in sim.track_manager.tracks_for(frigate):
				if t.identity == "HOSTILE" and t.domain == "surface":
					ordered = sim.unit_manager.issue_order(frigate, Order.attack(t))
					break
		if frigate.station_kind == "formation" and frigate.station_point().is_finite():
			furthest = maxf(furthest, frigate.position.distance_to(frigate.station_point()))
	assert_true(ordered, "the frigate was ordered to attack the hostile it holds")
	assert_true(fired[0] > 0, "she fired on it from the screen")
	assert_true(frigate.in_formation(), "she is back in the screen by 900 s (phase '%s', result '%s')" % [frigate.attack_phase, frigate.attack_result])
	assert_true(furthest <= 3.2, "she never strays more than about 3 NM from her station (%.1f NM)" % furthest)
	sim.free()


# --- A hull gives up a chase it cannot win ------------------------------------------------------

func test_a_ship_gives_up_a_stern_chase_of_a_faster_contact() -> void:
	var shooter := _ship("rnon_ffg_fridtjof_nansen", "BLUE", Vector2.ZERO)
	# Only the gun, so the contact has to be closed to be engaged.
	for wid: String in shooter.magazines.keys():
		if wid != "oto_76mm_gun":
			shooter.magazines[wid] = 0
	shooter.heading_deg = 0.0
	shooter.ordered_heading_deg = 0.0
	var runner := _ship("rnon_ffg_fridtjof_nansen", "RED", Vector2(0.0, 14.0))
	runner.heading_deg = 0.0
	runner.ordered_heading_deg = 0.0
	runner.speed_kn = runner.spec.max_speed_kn
	runner.ordered_speed_kn = runner.spec.max_speed_kn
	var m := _managers([shooter, runner])
	var um: UnitManager = m[0]
	var wm: WeaponManager = m[1]
	var t := _track(runner)
	assert_true(um.issue_order(shooter, Order.attack(t)), UnitManager.attack_rejection(shooter, t))
	var now := 0.0
	var start_range := shooter.position.distance_to(runner.position)
	while now < 1200.0 and shooter.attack_track != null:
		now += DT
		_plot(t, runner)
		um.tick(DT, now)
		wm.tick(DT, now)
	assert_true(shooter.attack_track == null, "the attack is given up rather than chased for ever (phase '%s', range %.1f from %.1f NM)" % [shooter.attack_phase, shooter.position.distance_to(runner.position), start_range])
	assert_true(shooter.attack_result.contains("opening"), "the commander is told why: '%s'" % shooter.attack_result)
	um.free()
	wm.free()


func test_a_ship_still_closes_on_a_slower_contact() -> void:
	var shooter := _ship("rnon_ffg_fridtjof_nansen", "BLUE", Vector2.ZERO)
	for wid: String in shooter.magazines.keys():
		if wid != "oto_76mm_gun":
			shooter.magazines[wid] = 0
	var slow := _ship("rnon_ffg_fridtjof_nansen", "RED", Vector2(0.0, 11.0))
	slow.heading_deg = 0.0
	slow.ordered_heading_deg = 0.0
	slow.speed_kn = 12.0
	slow.ordered_speed_kn = 12.0
	var m := _managers([shooter, slow])
	var um: UnitManager = m[0]
	var wm: WeaponManager = m[1]
	var t := _track(slow)
	assert_true(um.issue_order(shooter, Order.attack(t)))
	var fired := [0]
	wm.round_fired.connect(func(u: Unit, _spec: WeaponSpec, _t: Track) -> void:
		if u == shooter:
			fired[0] += 1)
	var now := 0.0
	while now < 1800.0 and fired[0] == 0 and shooter.attack_track != null:
		now += DT
		_plot(t, slow)
		um.tick(DT, now)
		wm.tick(DT, now)
	assert_true(fired[0] > 0, "a chase she gains on is carried through to the gun (phase '%s', result '%s', range %.1f NM)" % [shooter.attack_phase, shooter.attack_result, shooter.position.distance_to(slow.position)])
	um.free()
	wm.free()


func test_a_consort_whose_shot_lies_beyond_the_screen_keeps_station_and_says_why() -> void:
	var guide := _ship("rnon_ffg_fridtjof_nansen", "BLUE", Vector2.ZERO)
	var escort := _ship("rnon_ffg_fridtjof_nansen", "BLUE", Vector2(4, 6))
	for wid: String in escort.magazines.keys():
		if wid != "oto_76mm_gun":
			escort.magazines[wid] = 0
	var target := _ship("rnon_ffg_fridtjof_nansen", "RED", Vector2(24, 30))
	var m := _managers([guide, escort, target])
	var um: UnitManager = m[0]
	var wm: WeaponManager = m[1]
	assert_true(um.issue_order(guide, Order.move(Vector2(0, 300))))
	assert_true(um.issue_order(guide, Order.set_speed(12.0)))
	assert_true(um.issue_order(escort, Order.form_up(guide, Vector2(4, 6))))
	var now := 0.0
	for i in 480:
		now += DT
		um.tick(DT, now)
	var t := _track(target)
	var ended: Array = []
	um.attack_ended.connect(func(u: Unit, _t: Track, reason: String) -> void: ended.append([u, reason, guide.position.y]))
	assert_true(um.issue_order(escort, Order.attack(t)))
	var left_screen := false
	while now < 7200.0 and ended.is_empty():
		now += DT
		_plot(t, target)
		um.tick(DT, now)
		wm.tick(DT, now)
		left_screen = left_screen or not escort.in_formation()
	assert_true(not left_screen, "a contact out of the gun's reach from the screen is not chased out of it")
	assert_eq(ended.size(), 1, "the attack is given back")
	if not ended.is_empty():
		assert_eq(ended[0][1], "Cannot engage: " + UnitManager.SCREEN_HELD.to_lower(), "with the reason")
		# Abeam of it at 24 NM north; the screen closed it all the way up until shortly before.
		assert_true(float(ended[0][2]) > 20.0, "and not while the convoy was still closing it (guide at %.1f NM north)" % float(ended[0][2]))
	assert_true(escort.in_formation(), "she is in the screen")
	um.free()
	wm.free()


# --- Holding the range off a coast -------------------------------------------------------------

func test_a_destroyer_holding_her_range_off_musandam_is_never_put_on_the_shore() -> void:
	Detection.set_environment({})
	var ship := _ship("usn_ddg_arleigh_burke_iia", "BLUE", Vector2(-28.0, 10.2))
	ship.heading_deg = 100.0
	ship.ordered_heading_deg = 100.0
	ship.speed_kn = 13.0
	ship.ordered_speed_kn = 13.0
	var target := _ship("irn_ffg_moudge", "RED", Vector2(60.0, -50.0))
	target.health = 100000.0
	var um := UnitManager.new()
	um.add_unit(ship)
	um.add_unit(target)
	var wm := WeaponManager.new()
	wm.unit_manager = um
	wm.rng.seed = 7
	um.weapon_manager = wm
	Terrain.clear()
	Terrain.load_from(ScenarioLoader.load_file("res://data/scenarios/gulf_01_hormuz.json"))
	var t := _track(target)
	assert_true(um.issue_order(ship, Order.attack(t)))
	var now := 0.0
	var nearest := INF
	var crawling := 0.0
	var longest_crawl := 0.0
	while now < 9000.0 and ship.attack_track != null:
		now += DT
		um.tick(DT, now)
		wm.tick(DT, now)
		nearest = minf(nearest, Terrain.distance_to_land_nm(ship.position))
		crawling = crawling + DT if now > 600.0 and ship.speed_kn < 5.0 and ship.ordered_speed_kn > 20.0 else 0.0
		longest_crawl = maxf(longest_crawl, crawling)
	assert_true(nearest > 0.0, "she is never on the beach (nearest %.2f NM)" % nearest)
	assert_true(longest_crawl < 60.0, "and never creeps with full speed rung on (%.0f s at under 5 kn)" % longest_crawl)
	assert_true(ship.attack_rounds_fired > 0, "the attack is carried on")
	Terrain.clear()
	um.free()
	wm.free()


## A coast to the south: the short way round from south-west to east would take her through it.
func test_a_ship_with_the_shore_on_the_short_side_of_her_turn_comes_round_the_other_way() -> void:
	Terrain.clear()
	Terrain.load_from({"terrain": {"land": [{"id": "coast", "name": "Coast", "elevation_m": 40.0, "points_nm": [[-40, -30], [40, -30], [40, 0], [-40, 0]]}]}})
	var ship := _ship("usn_ddg_arleigh_burke_iia", "BLUE", Vector2(0.0, 0.35))
	ship.heading_deg = 219.0
	ship.ordered_heading_deg = 219.0
	ship.speed_kn = 18.0
	ship.ordered_speed_kn = 25.0
	ship.waypoints.assign([Vector2(10.0, 0.5)])
	var nearest := INF
	var first_turn := 0.0
	for i in 2400:
		Movement.step(ship, DT)
		if i == 8:
			first_turn = Geo.heading_delta(219.0, ship.heading_deg)
		nearest = minf(nearest, Terrain.distance_to_land_nm(ship.position))
	assert_true(first_turn > 0.0, "she comes round to starboard, away from the shore (%.1f deg)" % first_turn)
	assert_true(nearest > 0.05, "and keeps off it (nearest %.2f NM)" % nearest)
	assert_true(ship.position.x > 2.0, "and is on her way east (%.1f NM)" % ship.position.x)
	Terrain.clear()


func test_a_ship_with_open_water_on_both_sides_still_turns_the_short_way() -> void:
	Terrain.clear()
	Terrain.load_from({"terrain": {"land": [{"id": "coast", "name": "Coast", "elevation_m": 40.0, "points_nm": [[-40, -30], [40, -30], [40, -20], [-40, -20]]}]}})
	var ship := _ship("usn_ddg_arleigh_burke_iia", "BLUE", Vector2(0.0, 0.35))
	ship.heading_deg = 219.0
	ship.ordered_heading_deg = 219.0
	ship.speed_kn = 18.0
	ship.ordered_speed_kn = 25.0
	ship.waypoints.assign([Vector2(10.0, 0.5)])
	for i in 8:
		Movement.step(ship, DT)
	assert_true(Geo.heading_delta(219.0, ship.heading_deg) < 0.0, "with sea room she turns to port, the short way")
	Terrain.clear()


# --- A scenario's patrol line of two corners ---------------------------------------------------

func _on_two_corner_line(faction := "BLUE") -> Unit:
	var ship := _ship("rnon_ffg_fridtjof_nansen", faction, Vector2(0.0, 0.0))
	# As the scenario loader lays a `route_circuit` of two points: out and back along a line.
	var line: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(20.0, 0.0)]
	ship.apply_order(Order.patrol(line))
	return ship


func test_a_ship_on_a_two_corner_scenario_patrol_goes_back_to_it_after_a_task() -> void:
	var ship := _on_two_corner_line()
	var contact := _ship("rnon_ffg_fridtjof_nansen", "RED", Vector2(6.0, 12.0))
	var m := _managers([ship, contact])
	var um: UnitManager = m[0]
	var wm: WeaponManager = m[1]
	var unavailable: Array = []
	um.station_unavailable.connect(func(_u: Unit, why: String) -> void: unavailable.append(why))
	var resumed: Array = []
	um.station_resumed.connect(func(_u: Unit, why: String) -> void: resumed.append(why))
	assert_eq(UnitManager.station_rejection(ship), "", "the line she was given is a station she can go back to")
	var t := _track(contact)
	t.identity = "UNKNOWN"
	t.classification = Track.Classification.SURFACE
	t.known_class = ""
	assert_true(um.issue_order(ship, Order.investigate(t)))
	var now := 0.0
	for i in 1200:
		now += DT
		um.tick(DT, now)
	t.classification = Track.Classification.IDENTIFIED
	t.identity = "NEUTRAL"
	for i in 8:
		now += DT
		um.tick(DT, now)
	assert_eq(ship.investigation_track, null, "the look is over")
	assert_eq(unavailable, [], "she is not told her station is unavailable")
	assert_eq(resumed.size(), 1, "she goes back to it by herself")
	assert_true(ship.patrol_active and ship.on_station(), "and sails her line again")
	um.free()
	wm.free()


func test_a_two_corner_scenario_patrol_takes_a_new_speed_and_a_commanded_return() -> void:
	var ship := _on_two_corner_line()
	var m := _managers([ship])
	var um: UnitManager = m[0]
	var wm: WeaponManager = m[1]
	assert_true(um.issue_order(ship, Order.set_speed(20.0)), "the speed of the line she is sailing can be changed")
	var t := _track(_ship("rnon_ffg_fridtjof_nansen", "RED", Vector2(5, 5)))
	t.identity = "UNKNOWN"
	t.classification = Track.Classification.SURFACE
	assert_true(um.issue_order(ship, Order.investigate(t)), "she is sent to look at something")
	assert_true(um.issue_order(ship, Order.return_to_station()), "and the commander can send her back to it")
	assert_true(ship.patrol_active, "on her line")
	# A circuit the commander lays still needs three corners.
	var two: Array[Vector2] = [Vector2(0, 0), Vector2(20, 0)]
	assert_true(UnitManager.patrol_rejection(ship, two) != "")
	um.free()
	wm.free()
