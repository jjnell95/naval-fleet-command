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
