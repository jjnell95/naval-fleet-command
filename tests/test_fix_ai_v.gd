extends TestCase
## The grade reads how the mission was played: a switch flipped is not command, and a screen
## left with a hole in it costs the commander who opened it.


func _unit(faction: String, callsign: String, pos: Vector2, category: String) -> Unit:
	var spec := PlatformSpec.new()
	spec.short_name = callsign
	spec.category = category
	spec.domain = "surface"
	spec.max_speed_kn = 28.0
	spec.cruise_speed_kn = 14.0
	spec.health = 100.0
	var u := Unit.new()
	u.spec = spec
	u.faction = faction
	u.callsign = callsign
	u.position = pos
	u.heading_deg = 90.0
	u.health = 100.0
	return u


## [unit manager, mission manager, weapon manager]: a merchant with one escort on a formation
## station a mile and a half off her bow, against one raider, won by holding on for an hour.
func _convoy() -> Array:
	var um := UnitManager.new()
	var maud := _unit("BLUE", "Maud", Vector2.ZERO, "merchant")
	var escort := _unit("BLUE", "Escort", Vector2(1.0, 1.0), "frigate")
	for u: Unit in [escort, maud, _unit("RED", "Raider", Vector2(0.0, 20.0), "corvette")]:
		um.add_unit(u)
	escort.set_station("formation", "SCREEN STATION")
	escort.station_leader = maud
	escort.station_offset = Vector2(-1.0, 1.0)
	escort.formation_leader = maud
	escort.formation_offset = escort.station_offset
	escort.position = escort.station_point()
	var mm := MissionManager.new()
	mm.unit_manager = um
	mm.player_faction = "BLUE"
	mm.configure({"id": "test", "objectives": {
		"victory": [{"type": "time_elapsed", "seconds": 3600.0, "text": "Hold the passage"}],
		"loss": [{"type": "unit_lost", "callsigns": ["Maud"], "text": "Maud lost"}]}})
	var wm := WeaponManager.new()
	mm.listen(wm)
	return [um, mm, wm]


func _free(h: Array) -> void:
	h[2].free()
	h[1].free()
	h[0].free()


func _called(um: UnitManager, callsign: String) -> Unit:
	for u: Unit in um.units:
		if u.callsign == callsign:
			return u
	return null


func _give(um: UnitManager, u: Unit, o: Order) -> void:
	um.order_issued.emit(u, o)


## Runs the hour in minute steps. From `away_from` to `away_until` the escort stands 8 nm off.
func _play(h: Array, away_from := INF, away_until := INF) -> Dictionary:
	var um: UnitManager = h[0]
	var mm: MissionManager = h[1]
	var escort := _called(um, "Escort")
	var t := 0.0
	while mm.result == MissionManager.Result.RUNNING and t < 3700.0:
		escort.position = escort.station_point() + (Vector2(0.0, 8.0) if t >= away_from and t < away_until else Vector2.ZERO)
		mm.tick(t)
		t += 60.0
	return mm.assessment()


# --- Command ----------------------------------------------------------------------------------

func test_an_emission_or_radar_switch_alone_is_not_command() -> void:
	var switches: Array[Order] = [Order.set_emcon(false)]
	var radar := Order.new()
	radar.type = Order.Type.ACTIVATE_RADAR
	switches.append(radar)
	var roe := Order.new()
	roe.type = Order.Type.SET_ROE
	switches.append(roe)
	for o: Order in switches:
		var h := _convoy()
		_give(h[0], _called(h[0], "Escort"), o)
		var a := _play(h)
		assert_eq(int((h[1] as MissionManager).result), int(MissionManager.Result.VICTORY), "the passage was held")
		assert_true(not bool(a["commanded"]), "%s alone is not taking command" % Order.Type.keys()[o.type])
		assert_true(int(a["percent"]) < 40, "a victory with only %s given grades under 40, not %d" % [Order.Type.keys()[o.type], int(a["percent"])])
		_free(h)


func test_an_order_that_puts_the_force_to_work_is_command() -> void:
	var h := _convoy()
	var um: UnitManager = h[0]
	var raider := _called(um, "Raider")
	var t := Track.new()
	t.truth = raider
	t.position = raider.position
	_give(um, _called(um, "Escort"), Order.attack(t))
	var a := _play(h)
	assert_true(bool(a["commanded"]), "an attack order is command")
	assert_true(int(a["percent"]) >= 60, "and the victory grades as a commanded one: %d" % int(a["percent"]))
	_free(h)


# --- Screen discipline ------------------------------------------------------------------------

func test_an_escort_that_leaves_the_screen_for_most_of_the_passage_grades_well_below_one_that_keeps_it() -> void:
	var h := _convoy()
	_give(h[0], _called(h[0], "Escort"), Order.set_speed(18.0))
	var kept := _play(h)
	_free(h)
	h = _convoy()
	_give(h[0], _called(h[0], "Escort"), Order.set_speed(18.0))
	var broken := _play(h, 360.0, INF)
	_free(h)
	assert_near(float(kept["screen"]), 0.0, 0.001, "a screen kept costs nothing")
	assert_true(float(broken["screen_short"]) > 0.85, "the screen was short from six minutes on: %.2f" % float(broken["screen_short"]))
	assert_true(int(kept["percent"]) - int(broken["percent"]) >= 10, "a broken screen grades clearly lower: %d against %d" % [int(broken["percent"]), int(kept["percent"])])
	assert_true(MissionManager.assessment_text(broken).contains("Screen −"), "the debrief says why: %s" % MissionManager.assessment_text(broken))
	assert_true(not MissionManager.assessment_text(kept).contains("Screen"), "and says nothing of a screen that held: %s" % MissionManager.assessment_text(kept))


func test_a_short_detachment_costs_in_proportion() -> void:
	var h := _convoy()
	_give(h[0], _called(h[0], "Escort"), Order.set_speed(18.0))
	var a := _play(h, 600.0, 960.0)
	_free(h)
	assert_near(float(a["screen_short"]), 0.1, 0.03, "six minutes off station in an hour is a tenth of it")
	assert_true(float(a["screen"]) < 3.0, "and costs a little, not the whole term: %.1f" % float(a["screen"]))


func test_an_escort_the_commander_releases_is_not_held_to_the_screen() -> void:
	var h := _convoy()
	var um: UnitManager = h[0]
	var escort := _called(um, "Escort")
	_give(um, escort, Order.break_formation())
	escort.clear_station()
	escort.formation_leader = null
	var mm: MissionManager = h[1]
	var t := 0.0
	while mm.result == MissionManager.Result.RUNNING and t < 3700.0:
		escort.position = Vector2(0.0, 12.0)
		mm.tick(t)
		t += 60.0
	assert_near(float(mm.assessment()["screen"]), 0.0, 0.001, "a released escort has no station to be off")
	_free(h)


func test_the_screen_record_survives_a_save() -> void:
	var sim := Simulation.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	assert_true(sim.load_scenario("res://data/scenarios/northern_passage.json"))
	SimClock.set_paused(true)
	var mm := sim.mission_manager
	mm.screen_s = 600.0
	mm.screen_short_s = 240.0
	mm.screen_last_s = 600.0
	var before := mm.assessment()
	var snap := sim.capture_snapshot()
	mm.configure(sim.scenario)
	assert_near(mm.screen_short_s, 0.0, 0.001, "a fresh start forgets the record")
	assert_eq(sim.restore_snapshot(snap), "")
	var after := sim.mission_manager.assessment()
	assert_near(float(after["screen_short"]), 0.4, 0.001)
	assert_eq(after["percent"], before["percent"])
	assert_near(sim.mission_manager.screen_last_s, 600.0, 0.001, "the next tick counts from where the save left off")
	sim.free()


## The opening of Northern Passage through the real simulation: the frigate keeps her station
## until she is ordered, and the attack that sends her after the raider opens the screen.
func test_northern_passage_charges_the_frigate_that_chases_the_raider() -> void:
	var sim := Simulation.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	assert_true(sim.load_scenario("res://data/scenarios/northern_passage.json"))
	SimClock.set_paused(true)
	var frigate: Unit = null
	for u: Unit in sim.unit_manager.units:
		if u.spec.id == "rnon_ffg_fridtjof_nansen":
			frigate = u
	var ordered := false
	while SimClock.sim_time < 1100.0 and sim.mission_manager.result == MissionManager.Result.RUNNING:
		SimClock.advance(1.0)
		if not ordered and SimClock.sim_time >= 186.0:
			for t: Track in sim.track_manager.tracks_for(frigate):
				if t.identity == "HOSTILE" and t.domain == "surface":
					ordered = sim.unit_manager.issue_order(frigate, Order.attack(t))
					break
	assert_true(ordered, "the frigate was sent after the raider")
	var mm := sim.mission_manager
	assert_true(mm.screen_s > 1090.0, "the screen was counted from the start: %.0f s" % mm.screen_s)
	assert_true(mm.screen_short_s > 120.0, "and was short once she drew away: %.0f s" % mm.screen_short_s)
	assert_true(mm.screen_short_s < mm.screen_s - 180.0, "but not before the order: %.0f of %.0f s" % [mm.screen_short_s, mm.screen_s])
	sim.free()
