class_name TestRosterM20
extends TestCase
## Catalogue integration checks: every new choice resolves to usable systems and safe basing.

const PLATFORMS := [
	"fra_cvn_charles_de_gaulle", "usn_lha_america", "esp_lhd_juan_carlos_i", "fra_lhd_mistral",
	"ita_ddg_horizon", "deu_ffg_sachsen", "swe_fsg_visby", "rfn_ffg_admiral_grigorovich",
	"fra_ssn_suffren", "swe_ssk_gotland", "usmc_fighter_av8b", "raf_fighter_typhoon",
	"swe_fighter_gripen_c", "usaf_fighter_f16c", "fra_mpa_atlantic2", "rfn_strike_su34",
	"fra_helo_panther", "fra_aew_e2c",
]
const WEAPONS := [
	"meteor_aam", "asraam_aam", "iris_t_aam", "agm65e_maverick", "rbs15f", "kh31a",
	"f21_torpedo", "torpedo62", "torpedo47", "mistral_naval", "otomat_mk2", "shtil1",
]


func test_new_platforms_are_discoverable_and_have_complete_system_references() -> void:
	var catalogue := DataDB.all_platforms()
	for id in PLATFORMS:
		var p := DataDB.platform(id)
		assert_true(p != null, "%s loads" % id)
		if p == null:
			continue
		assert_true(catalogue.has(p), "%s is in the editor/gallery catalogue" % id)
		assert_true(not p.role.is_empty() and not p.service_note.is_empty(), "%s explains its role and fit" % id)
		assert_true(p.source_status.contains("GAMEPLAY_ESTIMATE"), "%s labels estimated performance" % id)
		for sid in p.sensor_ids:
			assert_true(DataDB.sensor(sid) != null, "%s sensor %s resolves" % [id, sid])
		for wid in p.weapon_loadout:
			assert_true(DataDB.weapon(wid) != null, "%s weapon %s resolves" % [id, wid])
			assert_true(int(p.weapon_loadout[wid]) > 0, "%s magazine is usable" % id)


func test_new_weapons_are_usable_from_at_least_one_platform() -> void:
	var catalogue := DataDB.all_weapons()
	for id in WEAPONS:
		var w := DataDB.weapon(id)
		assert_true(w != null, "%s loads" % id)
		if w == null:
			continue
		assert_true(catalogue.has(w), "%s appears in the weapons catalogue" % id)
		assert_true(w.max_range_nm > w.min_range_nm and w.speed_kn > 0.0, "%s has a usable envelope" % id)
		assert_true(w.damage > 0.0 and not w.target_types.is_empty(), "%s can act on targets" % id)
		assert_true(w.source_status.contains("GAMEPLAY_ESTIMATE"), "%s labels combat estimates" % id)
		var fitted := false
		for p: PlatformSpec in DataDB.all_platforms():
			if int(p.weapon_loadout.get(id, 0)) > 0:
				fitted = true
		assert_true(fitted, "%s is fitted to a playable platform" % id)


func test_new_default_air_wings_fit_their_hosts() -> void:
	for id in PLATFORMS:
		var p := DataDB.platform(id)
		if p == null or p.default_air_wing.is_empty():
			continue
		var count := 0
		for aircraft_id in p.default_air_wing:
			var aircraft := DataDB.platform(aircraft_id)
			var quantity := int(p.default_air_wing[aircraft_id])
			assert_true(quantity > 0, "%s has positive airframe counts" % id)
			count += quantity
			assert_true(aircraft != null and p.can_operate(aircraft), "%s can operate %s" % [id, aircraft_id])
		assert_true(count <= p.aircraft_capacity, "%s wing fits its total capacity" % id)
		assert_true(p.launch_capacity() > 0 and p.recovery_capacity() > 0, "%s has a complete deck cycle" % id)


func test_expansion_keeps_catapult_stovl_and_runway_aircraft_distinct() -> void:
	var catobar := DataDB.platform("fra_cvn_charles_de_gaulle")
	var stovl := DataDB.platform("esp_lhd_juan_carlos_i")
	var helo_deck := DataDB.platform("fra_lhd_mistral")
	var runway := DataDB.platform("shore_air_station")
	var hawkeye := DataDB.platform("fra_aew_e2c")
	var harrier := DataDB.platform("usmc_fighter_av8b")
	var typhoon := DataDB.platform("raf_fighter_typhoon")
	var panther := DataDB.platform("fra_helo_panther")
	assert_true(catobar.can_operate(hawkeye), "E-2C has an appropriate catapult deck")
	assert_true(not stovl.can_operate(hawkeye), "a ski jump cannot launch the E-2C")
	assert_true(stovl.can_operate(harrier), "STOVL carrier can launch the Harrier")
	assert_true(not helo_deck.can_operate(harrier), "a helicopter carrier cannot become a jet carrier")
	assert_true(not catobar.can_operate(typhoon), "a catapult does not make a land fighter carrier-capable")
	assert_true(helo_deck.can_operate(panther), "Panther can use the helicopter carrier")
	for id in PLATFORMS:
		var p := DataDB.platform(id)
		if p.domain == "air":
			assert_true(runway.can_operate(p), "%s has a land recovery option" % id)
			assert_true(p.endurance_s > p.launch_time_s + p.recovery_time_s, "%s can complete a sortie" % id)
			assert_true(p.cruise_altitude_m > 0 and p.altitude_rate_m_s > 0, "%s can climb" % id)


func test_new_vls_fits_do_not_exceed_cells() -> void:
	for id in PLATFORMS:
		var p := DataDB.platform(id)
		if p != null and p.vls_cells > 0:
			assert_true(p.occupied_vls_cells() <= p.vls_cells, "%s VLS fit stays inside physical capacity" % id)
	assert_eq(DataDB.platform("deu_ffg_sachsen").occupied_vls_cells(), 32)
	assert_eq(DataDB.platform("ita_ddg_horizon").occupied_vls_cells(), 48)
	assert_eq(DataDB.platform("rfn_ffg_admiral_grigorovich").occupied_vls_cells(), 32)


func test_new_carriers_spawn_mixed_aircraft_through_real_scenario_loader() -> void:
	for id in ["fra_cvn_charles_de_gaulle", "usn_lha_america", "esp_lhd_juan_carlos_i", "fra_lhd_mistral"]:
		var um := UnitManager.new()
		ScenarioLoader.populate(um, {"units": [{"platform": id, "callsign": "Test Host", "faction": "BLUE", "position_nm": [0, 0]}]})
		var host: Unit = um.units[0]
		var types := {}
		for a: Unit in host.embarked:
			types[a.spec.id] = true
			assert_true(a.home == host, "%s aircraft retains a recoverable home" % id)
			assert_eq(a.flight_state, Unit.FlightState.STOWED, "default wing starts ready aboard")
		assert_true(types.size() >= 2, "%s offers a real aircraft-type choice" % id)
		assert_eq(host.embarked.size(), um.units.size() - 1, "%s loads every advertised airframe" % id)
		um.free()
