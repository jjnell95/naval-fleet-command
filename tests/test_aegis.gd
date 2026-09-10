extends TestCase

func test_aegis_scenario_resolves_every_loadout_and_aircraft_home() -> void:
	var um := UnitManager.new()
	var sc := ScenarioLoader.load_file("res://data/scenarios/aegis_bastion.json")
	ScenarioLoader.populate(um, sc)
	assert_eq(um.units.size(), 19, "all scenario actors spawn")
	for u in um.units:
		assert_eq(u.sensors.size(), u.spec.sensor_ids.size(), u.callsign + " sensors resolve")
		assert_eq(u.weapons.size(), u.spec.weapon_loadout.size(), u.callsign + " weapons resolve")
		if u.is_aircraft():
			assert_true(u.home != null, u.callsign + " has a flight deck")
			if u.home != null:
				assert_true(u.home.embarked.size() <= u.home.spec.aircraft_capacity, "deck capacity respected")
	um.free()

func test_amraam_engages_air_tracks_but_rejects_surface() -> void:
	var fighter := Unit.new()
	fighter.spec = DataDB.platform("usn_fighter_fa18e")
	fighter.health = fighter.spec.health
	fighter.faction = "BLUE"
	var aam := DataDB.weapon("aim120_family")
	fighter.weapons.append(aam)
	fighter.magazines[aam.id] = 6
	var t := Track.new()
	t.position = Vector2(10, 0)
	t.domain = "air"
	t.status = Track.Status.ACTIVE
	assert_true(Combat.check_engagement(fighter, aam, t).ok, "fighter has a valid air shot")
	t.domain = "surface"
	assert_true(not Combat.check_engagement(fighter, aam, t).ok, "AMRAAM cannot attack a ship")
	t.domain = "air"
	fighter.roe = Unit.Roe.HOLD
	assert_true(not Combat.check_engagement(fighter, aam, t).ok, "weapons hold blocks fighter shot")

func test_aam_launch_consumes_round_and_can_damage_aircraft() -> void:
	var um := UnitManager.new()
	var sc := ScenarioLoader.load_file("res://data/scenarios/aegis_bastion.json")
	ScenarioLoader.populate(um, sc)
	var fighter: Unit = um.units[7]
	var target: Unit = um.units[15]
	fighter.position = Vector2.ZERO
	target.position = Vector2(5,0)
	fighter.flight_state = Unit.FlightState.AIRBORNE
	target.flight_state = Unit.FlightState.AIRBORNE
	fighter.altitude_m = 8000
	target.altitude_m = 8000
	var t := Track.new()
	t.position = target.position
	t.domain = "air"
	t.status = Track.Status.ACTIVE
	t.truth = target
	var w: WeaponSpec = DataDB.weapon("aim120_family").duplicate()
	w.base_pk = 1.0
	var wm := WeaponManager.new()
	wm.unit_manager = um
	wm.rng.seed = 7
	var before := fighter.magazine_count(w.id)
	assert_true(wm.launch(fighter,w,t,2,0), "air-to-air salvo launches")
	assert_eq(fighter.magazine_count(w.id),before-2,"rounds spent")
	for i in 160: wm.tick(0.25,float(i)*0.25)
	assert_true(target.health < target.spec.health,"aircraft receives damage from aircraft weapon")
	wm.free()
	um.free()
