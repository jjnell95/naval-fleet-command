extends TestCase

func test_aegis_scenario_resolves_every_loadout_and_aircraft_home() -> void:
	var um := UnitManager.new()
	var sc := ScenarioLoader.load_file("res://data/scenarios/aegis_bastion.json")
	ScenarioLoader.populate(um, sc)
	# Counting actors pins scenario authoring rather than behaviour, so what is checked here is
	# that everything the scenario does field resolves and fits on the deck it was given.
	assert_true(um.units.size() >= 19, "the scenario fields a full task group")
	var airframes := 0
	for u in um.units:
		assert_eq(u.sensors.size(), u.spec.sensor_ids.size(), u.callsign + " sensors resolve")
		assert_eq(u.weapons.size(), u.spec.weapon_loadout.size(), u.callsign + " weapons resolve")
		if u.is_aircraft():
			airframes += 1
			if u.home != null:
				assert_true(u.home.spec.can_operate(u.spec), u.callsign + " is on a deck that can work it")
				assert_true(u.home.embarked.size() <= u.home.spec.aircraft_capacity, "deck capacity respected")
	assert_true(airframes >= 8, "and a real air component, not a token one")
	um.free()

func test_amraam_engages_air_tracks_but_rejects_surface() -> void:
	var fighter := Unit.new()
	fighter.spec = DataDB.platform("usn_fighter_fa18e")
	fighter.health = fighter.spec.health
	fighter.faction = "BLUE"
	fighter.flight_state = Unit.FlightState.AIRBORNE
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

## Finds a scenario actor by what it is rather than where it landed in the spawn order. Indexing
## units by position breaks the moment a scenario gains or loses an actor, which it should be free
## to do.
func _find(um: UnitManager, platform_id: String, faction: String) -> Unit:
	for u in um.units:
		if u.spec.id == platform_id and u.faction == faction:
			return u
	return null


func test_aam_launch_consumes_round_and_can_damage_aircraft() -> void:
	var um := UnitManager.new()
	var sc := ScenarioLoader.load_file("res://data/scenarios/aegis_bastion.json")
	ScenarioLoader.populate(um, sc)
	var fighter: Unit = _find(um, "usn_fighter_fa18e", "BLUE")
	var target: Unit = _find(um, "rfn_fighter_su35s", "RED")
	assert_true(fighter != null and target != null, "the scenario fields both airframes")
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
