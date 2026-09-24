class_name TestColdWar
extends TestCase
## The period boundary covers default detachments and scenario overrides, not just hull names.

func _manifest() -> Dictionary:
	return ScenarioLoader.load_file("res://data/cold_war_1990_manifest.json")


func _mission(id: String) -> Array:
	Terrain.clear()
	var sc := ScenarioLoader.load_file("res://data/scenarios/%s.json" % id)
	var um := UnitManager.new()
	ScenarioLoader.populate(um, sc)
	var mm := MissionManager.new()
	mm.unit_manager = um
	mm.player_faction = "BLUE"
	mm.configure(sc)
	return [um, mm, sc]


func _find(um: UnitManager, callsign: String) -> Unit:
	for unit: Unit in um.units:
		if unit.callsign == callsign:
			return unit
	return null


func _cleanup(h: Array) -> void:
	h[1].free()
	h[0].free()


func _check_platform(id: String, manifest: Dictionary, seen: Dictionary) -> void:
	if seen.has(id):
		return
	seen[id] = true
	assert_true(manifest["platforms"].has(id), "%s is on the explicit 1990 platform list" % id)
	var p := DataDB.platform(id)
	assert_true(p != null, "%s resolves" % id)
	if p == null:
		return
	assert_true(p.source_status.contains("GAMEPLAY_ESTIMATE"), "%s distinguishes identity from performance" % id)
	for sid in p.sensor_ids:
		assert_true(manifest["sensors"].has(sid), "%s cannot inherit a modern sensor: %s" % [id, sid])
		assert_true(DataDB.sensor(sid) != null, "%s sensor resolves" % sid)
	for wid in p.weapon_loadout:
		assert_true(manifest["weapons"].has(wid), "%s cannot inherit a modern weapon: %s" % [id, wid])
		assert_true(DataDB.weapon(wid) != null, "%s weapon resolves" % wid)
	var capacity := 0
	for aid in p.default_air_wing:
		_check_platform(aid, manifest, seen)
		capacity += int(p.default_air_wing[aid])
		assert_true(p.can_operate(DataDB.platform(aid)), "%s can launch and recover %s" % [id, aid])
	assert_true(capacity <= p.aircraft_capacity, "%s air wing fits" % id)


func test_period_inventory_resolves_recursively_and_does_not_inherit_modern_fits() -> void:
	var manifest := _manifest()
	assert_eq(manifest["year"], 1990)
	assert_true(manifest["platforms"].size() >= 20, "a distinct era catalogue ships")
	var seen := {}
	for id in manifest["platforms"]:
		_check_platform(id, manifest, seen)
	for id in manifest["weapons"]:
		var w := DataDB.weapon(id)
		assert_true(w != null, "%s loads" % id)
		if w != null:
			assert_true(w.max_range_nm > w.min_range_nm and w.damage > 0, "%s has a usable envelope" % id)
			assert_true(w.source_status.contains("GAMEPLAY_ESTIMATE"), "%s is a labeled approximation" % id)


func test_all_1990_missions_have_reviewable_metadata_and_only_period_actors() -> void:
	var manifest := _manifest()
	assert_eq(manifest["scenario_ids"].size(), 4)
	for id in manifest["scenario_ids"]:
		var h := _mission(id)
		var sc: Dictionary = h[2]
		assert_eq(sc["era"], "Cold War")
		assert_eq(sc["year"], 1990)
		assert_true(str(sc["start_time_utc"]).begins_with("1990-"))
		assert_true(int(sc["order"]) < 0, "%s is introduced before the modern missions" % id)
		for key in ["difficulty", "role", "learning", "commander_intent", "historical_note"]:
			assert_true(not str(sc.get(key, "")).is_empty(), "%s has %s" % [id,key])
		assert_true(int(sc["duration_minutes"]) >= 10 and int(sc["duration_minutes"]) <= 60)
		assert_true(sc.get("first_orders", []).size() >= 3)
		for u: Unit in h[0].units:
			_check_platform(u.spec.id, manifest, {})
			for wid in u.magazines:
				assert_true(manifest["weapons"].has(wid), "%s scenario override stays inside era" % u.callsign)
		h[1].tick(0)
		assert_eq(h[1].result, MissionManager.Result.RUNNING, "%s does not resolve at load" % id)
		_cleanup(h)


func test_period_shipboard_fits_respect_launcher_and_sensor_differences() -> void:
	var perry := DataDB.platform("cw90_perry")
	assert_eq(int(perry.weapon_loadout["cw90_sm1mr"]) + int(perry.weapon_loadout["cw90_harpoon"]), 40, "shared Mk 13 magazine")
	assert_eq(perry.vls_cells, 0)
	var spruance := DataDB.platform("cw90_spruance")
	assert_eq(spruance.vls_cells, 61, "DD-963 after the 1986-87 refit")
	assert_true(spruance.weapon_loadout.has("cw90_sea_sparrow"))
	assert_true(not spruance.weapon_loadout.has("cw90_sm2mr"), "ASW destroyer does not acquire Aegis area defence")
	var tico := DataDB.platform("cw90_ticonderoga")
	assert_eq(tico.vls_cells, 122)
	assert_true(tico.occupied_vls_cells() <= tico.vls_cells)
	assert_true(tico.sensor_ids.has("cw90_spy1a"), "CG-52 keeps its period radar")
	assert_true(DataDB.platform("cw90_slava").weapon_loadout.has("cw90_p500"), "Slava has Bazalt")
	assert_true(DataDB.platform("cw90_sovremenny").weapon_loadout.has("cw90_moskit"), "Sovremennyy is surface-strike specialized")
	assert_true(DataDB.platform("cw90_udaloy").weapon_loadout.has("cw90_rastrub"), "Udaloy retains its different ASW role")
	assert_true(not DataDB.weapon("cw90_rastrub").target_types.has("surface"), "unimplemented Rastrub surface mode is not quietly enabled")


func test_period_aircraft_do_not_gain_later_capabilities() -> void:
	var sh60 := DataDB.platform("cw90_sh60b")
	for sid in sh60.sensor_ids:
		assert_true(DataDB.sensor(sid).kind != "sonar", "SH-60B uses buoys, not an MH-60R dipping set")
	assert_true(sh60.sonobuoy_count > 0)
	assert_eq(DataDB.platform("cw90_p3c").flight_requirement(), "runway")
	assert_eq(DataDB.platform("cw90_f14a").flight_requirement(), "catobar")
	var tomcat := DataDB.platform("cw90_f14a")
	assert_eq(tomcat.weapon_loadout.size(), 2, "Phoenix and Sidewinder; Sparrow is intentionally omitted")
	assert_true(tomcat.weapon_loadout.has("cw90_aim54a") and tomcat.weapon_loadout.has("cw90_aim9m"))
	assert_true(not DataDB.platform("cw90_e2c").can_refuel)
	assert_true(not DataDB.platform("cw90_tu22m3").can_refuel)
	assert_true(DataDB.platform("cw90_tu22m3").weapon_loadout.has("cw90_kh22"))


func test_convoy_arrival_wins_with_enemy_afloat_and_loss_overrides_it() -> void:
	for sink in [false, true]:
		var h := _mission("cold_war_01_convoy")
		var cargo := _find(h[0], "MV North Star")
		cargo.position = h[1].victory_objectives[0].center
		if sink:
			Damage.apply(cargo, 10000)
		h[1].tick(1)
		assert_eq(h[1].result, MissionManager.Result.DEFEAT if sink else MissionManager.Result.VICTORY)
		assert_true(h[0].get_engageable_units("RED").size() > 0)
		_cleanup(h)


func test_barrier_can_resolve_by_kill_watch_or_breakout() -> void:
	for outcome in ["kill", "watch", "breakout"]:
		var h := _mission("cold_war_02_barrier")
		var boat := _find(h[0], "Soviet submarine (Victor III)")
		if outcome == "kill":
			Damage.apply(boat, 10000)
		if outcome == "breakout":
			boat.position = h[1].loss_objectives[1].center
		h[1].tick(1 if outcome == "kill" else 10800)
		assert_eq(h[1].result, MissionManager.Result.DEFEAT if outcome == "breakout" else MissionManager.Result.VICTORY)
		_cleanup(h)


func test_carrier_watch_and_baltic_neutral_have_meaningful_loss_conditions() -> void:
	var h := _mission("cold_war_03_carrier")
	h[1].tick(7200)
	assert_eq(h[1].result, MissionManager.Result.VICTORY)
	_cleanup(h)
	h = _mission("cold_war_03_carrier")
	Damage.apply(_find(h[0], "USS Bunker Hill (CG 52)"), 10000)
	h[1].tick(7200)
	assert_eq(h[1].result, MissionManager.Result.DEFEAT, "air-defence screen loss overrides the watch")
	_cleanup(h)
	h = _mission("cold_war_04_baltic")
	Damage.apply(_find(h[0], "MV Baltic Trader"), 10000)
	Damage.apply(_find(h[0], "Otlichnyy"), 10000)
	h[1].tick(1)
	assert_eq(h[1].result, MissionManager.Result.DEFEAT, "sinking the enemy does not erase a neutral loss")
	_cleanup(h)


func test_towed_array_cannot_project_the_hull_active_sonar_below_the_layer() -> void:
	var hull := DataDB.sensor("cw90_sqs53b")
	var towed := DataDB.sensor("cw90_sqr19")
	assert_eq(hull.array_depth_m, 0.0, "hull transmitter stays near the keel")
	assert_true(hull.active_range_nm > 0.0)
	assert_true(towed.array_depth_m > 0.0 and towed.passive_sensitivity_nm > 0.0)
	assert_eq(towed.active_range_nm, 0.0, "SQR-19 is passive only")
	for id in ["cw90_spruance", "cw90_ticonderoga"]:
		var p := DataDB.platform(id)
		assert_true(p.sensor_ids.has("cw90_sqs53b") and p.sensor_ids.has("cw90_sqr19"), "%s has separate sensor bodies" % id)
