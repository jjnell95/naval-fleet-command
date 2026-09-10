extends TestCase
## Milestone 11 systems: ballistic missile defence, electronic attack, sea state, damage control.


func _unit(platform: String, faction: String, pos: Vector2) -> Unit:
	var u := Unit.new()
	u.spec = DataDB.platform(platform)
	u.faction = faction
	u.position = pos
	u.health = u.spec.health
	for sid in u.spec.sensor_ids:
		u.sensors.append(DataDB.sensor(sid))
	if u.is_aircraft():
		u.flight_state = Unit.FlightState.AIRBORNE
		u.altitude_m = u.spec.cruise_altitude_m
		u.fuel_s = u.spec.endurance_s
	return u


func _round(weapon_id: String, faction: String) -> Weapon:
	var w := Weapon.new()
	w.spec = DataDB.weapon(weapon_id)
	w.faction = faction
	return w


func test_ballistic_round_needs_a_bmd_interceptor() -> void:
	var kinzhal := _round("kinzhal_family", "RED")
	var kalibr := _round("kalibr_asm", "RED")
	assert_eq(kinzhal.threat_class(), "ballistic", "Kinzhal flies a ballistic profile")
	assert_eq(kalibr.threat_class(), "missile", "Kalibr is an ordinary missile threat")
	var sm2 := DataDB.weapon("sm2_family")
	var sm3 := DataDB.weapon("sm3_family")
	var sm6 := DataDB.weapon("sm6_family")
	assert_true(not AirDefence._can_intercept(sm2, kinzhal), "SM-2 cannot meet a ballistic round")
	assert_true(AirDefence._can_intercept(sm3, kinzhal), "SM-3 can")
	assert_true(not AirDefence._can_intercept(sm3, kalibr), "SM-3 is useless against a sea-skimmer")
	assert_true(Combat.intercept_probability(sm3, kinzhal.spec) > Combat.intercept_probability(sm6, kinzhal.spec), "the exoatmospheric interceptor has the better shot")


func test_bmd_cruiser_engages_ballistic_threat_with_sm3_first() -> void:
	var um := UnitManager.new()
	var cg := _unit("usn_cg_ticonderoga", "BLUE", Vector2.ZERO)
	for wid in cg.spec.weapon_loadout:
		cg.weapons.append(DataDB.weapon(wid))
		cg.magazines[wid] = int(cg.spec.weapon_loadout[wid])
	um.add_unit(cg)
	var wm := WeaponManager.new()
	wm.unit_manager = um
	var tm := ThreatManager.new()
	var threat := _round("kinzhal_family", "RED")
	threat.id = 999
	threat.position = Vector2(0.0, 120.0)
	threat.heading_deg = 180.0
	threat.aim_point = Vector2.ZERO
	threat.acquired = cg
	wm.in_flight.append(threat)
	tm.begin_cycle()
	tm.mark_detected("BLUE", threat, 0.0)
	var fired := AirDefence.run_cycle(um, tm, wm, 0.0)
	assert_true(fired > 0, "the cruiser shoots at a detected ballistic round")
	var sm3_used := int(cg.spec.weapon_loadout["sm3_family"]) - cg.magazine_count("sm3_family")
	assert_true(sm3_used > 0, "the shot came from the SM-3 magazine")
	wm.free()
	tm.free()
	um.free()


func test_jammer_degrades_radar_only_toward_the_jammer() -> void:
	var ddg := _unit("usn_ddg_burke_iii", "BLUE", Vector2.ZERO)
	var bandit := _unit("rfn_strike_su30sm", "RED", Vector2(60.0, 0.0))
	var flanker := _unit("rfn_strike_su30sm", "RED", Vector2(0.0, 60.0))
	var growler := _unit("usn_ea_ea18g", "RED", Vector2(40.0, 0.0))  # flown by the other side for the test
	Detection.refresh_jammers([])
	var clean := Detection.radar_quality(ddg, bandit)
	assert_true(clean > 0.5, "clear picture before jamming")
	assert_true(growler.jamming(), "an airborne Growler with its emitters on is jamming")
	Detection.refresh_jammers([ddg, bandit, flanker, growler])
	var jammed := Detection.radar_quality(ddg, bandit)
	assert_true(jammed < clean * 0.5, "the target behind the jammer is much harder to see (%.2f vs %.2f)" % [jammed, clean])
	assert_near(Detection.radar_quality(ddg, flanker), clean, 1e-3, "a target off the jammer's bearing is untouched")
	assert_true(Detection.emitted_radar_power(growler) > 0.0, "ESM hears the jammer")
	growler.radar_on = false
	assert_true(not growler.jamming(), "silent means the jammer is silent too")
	Detection.refresh_jammers([])


func test_sea_state_shortens_sonar_and_hides_skimmers() -> void:
	var ffg := _unit("usn_ffg_constellation", "BLUE", Vector2.ZERO)
	var kilo := _unit("rfn_ssk_kilo", "RED", Vector2(5.0, 0.0))
	kilo.speed_kn = 8.0
	Detection.set_environment({})
	var calm: float = Detection.best_passive_sonar(ffg, kilo)["range_nm"]
	var kh35 := DataDB.weapon("kh35_uran")
	var clear_skimmer := Detection.best_weapon_detection_nm(ffg, kh35) * Detection.weapon_clutter_factor(kh35)
	Detection.set_environment({"sea_state": 5})
	assert_eq(Detection.sea_state, 5, "sea state read from the scenario")
	assert_eq(Detection.sea_state_name(), "very rough", "sea state named")
	var rough: float = Detection.best_passive_sonar(ffg, kilo)["range_nm"]
	assert_true(rough < calm * 0.75, "a rough sea shortens passive sonar (%.1f vs %.1f)" % [rough, calm])
	var rough_skimmer := Detection.best_weapon_detection_nm(ffg, kh35) * Detection.weapon_clutter_factor(kh35)
	assert_true(rough_skimmer < clear_skimmer, "clutter hides a sea-skimmer")
	assert_near(Detection.weapon_clutter_factor(DataDB.weapon("kh32_family")), 1.0, 1e-6, "a high-flying round is above the clutter")
	Detection.set_environment({})
	assert_eq(Detection.sea_state, 0, "environment resets")


func test_damage_control_restores_subsystems_to_a_cap() -> void:
	var ddg := _unit("usn_ddg_arleigh_burke_iia", "BLUE", Vector2.ZERO)
	ddg.components["propulsion"] = 0.2
	assert_true(Damage.repairing(ddg), "a damaged plant is being worked on")
	Damage.tick([ddg], 300.0)
	var after := ddg.component("propulsion")
	assert_true(after > 0.2 and after < Damage.REPAIR_CAP, "repair is gradual (%.2f)" % after)
	Damage.tick([ddg], 30000.0)
	assert_near(ddg.component("propulsion"), Damage.REPAIR_CAP, 1e-6, "a repair at sea stops at the cap")
	assert_true(not Damage.repairing(ddg), "nothing left to repair")
	var jet := _unit("usn_fighter_fa18e", "BLUE", Vector2.ZERO)
	jet.components["sensors"] = 0.3
	Damage.tick([jet], 30000.0)
	assert_near(jet.component("sensors"), 0.3, 1e-6, "aircraft carry no repair party")


func test_arctic_shield_scenario_resolves_every_actor() -> void:
	var um := UnitManager.new()
	var sc := ScenarioLoader.load_file("res://data/scenarios/arctic_shield.json")
	ScenarioLoader.populate(um, sc)
	assert_eq(um.units.size(), 29, "all scenario actors spawn")
	var jammers := 0
	var bmd := 0
	for u in um.units:
		assert_eq(u.sensors.size(), u.spec.sensor_ids.size(), u.callsign + " sensors resolve")
		assert_eq(u.weapons.size(), u.spec.weapon_loadout.size(), u.callsign + " weapons resolve")
		if u.has_jammer():
			jammers += 1
		if u.magazine_count("sm3_family") > 0:
			bmd += 1
		if u.is_aircraft():
			assert_true(u.home != null, u.callsign + " has a flight deck")
			if u.home != null:
				assert_true(u.home.embarked.size() <= u.home.spec.aircraft_capacity, u.home.callsign + " deck capacity respected")
	assert_eq(jammers, 1, "one Growler")
	assert_eq(bmd, 1, "one BMD shooter")
	assert_eq(int(sc["environment"]["sea_state"]), 4, "rough sea declared")
	um.free()
