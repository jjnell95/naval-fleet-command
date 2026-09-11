extends TestCase

func _scenario(id: String) -> Dictionary:
	return ScenarioLoader.load_file("res://data/scenarios/%s.json" % id)

func _mission(id: String) -> Array:
	var sc := _scenario(id)
	var um := UnitManager.new()
	ScenarioLoader.populate(um, sc)
	var mm := MissionManager.new()
	mm.unit_manager = um
	mm.configure(sc)
	return [um, mm]

func _find(um: UnitManager, callsign: String) -> Unit:
	for u in um.units:
		if u.callsign == callsign: return u
	return null

func _cleanup(h: Array) -> void:
	h[1].free()
	h[0].free()

func test_escort_arrival_wins_without_destroying_the_enemy() -> void:
	var h := _mission("northern_shield")
	var maud := _find(h[0], "HNoMS Maud (A 530)")
	h[1].tick(0)
	assert_eq(h[1].result, MissionManager.Result.RUNNING)
	maud.position = h[1].victory_objectives[0].center
	h[1].tick(1)
	assert_eq(h[1].result, MissionManager.Result.VICTORY)
	assert_true(h[0].get_engageable_units("RED").size() > 0, "escorting is enough")
	_cleanup(h)

func test_maud_loss_overrides_arrival() -> void:
	var h := _mission("northern_shield")
	var maud := _find(h[0], "HNoMS Maud (A 530)")
	maud.position = h[1].victory_objectives[0].center
	Damage.apply(maud, 10000)
	h[1].tick(1)
	assert_eq(h[1].result, MissionManager.Result.DEFEAT)
	_cleanup(h)

func test_asw_hunt_does_not_require_destroying_supporting_aircraft() -> void:
	var h := _mission("northern_sentry")
	Damage.apply(_find(h[0], "Magnitogorsk (B-471)"), 10000)
	h[1].tick(1)
	assert_eq(h[1].result, MissionManager.Result.VICTORY)
	assert_true(_find(h[0], "Flanker 11").alive)
	_cleanup(h)

func test_passage_denial_accepts_either_victory_but_exit_takes_precedence() -> void:
	for outcome in ["time", "sink", "exit"]:
		var h := _mission("giuk_passage")
		var boat := _find(h[0], "Vladikavkaz (B-459)")
		if outcome == "sink": Damage.apply(boat, 10000)
		if outcome == "exit": boat.position = h[1].loss_objectives[-1].center
		h[1].tick(1 if outcome == "sink" else 21600)
		assert_eq(h[1].result, MissionManager.Result.DEFEAT if outcome == "exit" else MissionManager.Result.VICTORY, outcome)
		_cleanup(h)

func test_baltic_requires_both_merchants_and_protects_neutral_traffic() -> void:
	var h := _mission("baltic_sentinel")
	_find(h[0], "MV Baltic Trader").position = h[1].victory_objectives[0].center
	h[1].tick(1)
	assert_eq(h[1].result, MissionManager.Result.RUNNING)
	_find(h[0], "MV Gotland Star").position = h[1].victory_objectives[1].center
	h[1].tick(2)
	assert_eq(h[1].result, MissionManager.Result.VICTORY)
	_cleanup(h)
	h = _mission("baltic_sentinel")
	Damage.apply(_find(h[0], "FV Stormfagel"), 10000)
	h[1].tick(1)
	assert_eq(h[1].result, MissionManager.Result.DEFEAT)
	_cleanup(h)

func test_missing_named_target_cannot_count_as_destroyed() -> void:
	var um := UnitManager.new()
	var o := MissionObjective.from_dict({"type":"all_units_lost", "callsigns":["Typo"]})
	assert_true(not o.evaluate(um, 1))
	um.free()

func test_local_geographic_inverse_and_minute_carry() -> void:
	var ll := Geo.world_to_latlon(Vector2(30, 60), 60, 10)
	assert_near(ll.x, 61)
	assert_near(ll.y, 11)
	assert_eq(Geo.format_latlon(59.99999), "60°00.0′N")
	assert_eq(Geo.format_latlon(-7.25, false), "07°15.0′W")

func test_class_fits_do_not_mix_incompatible_systems() -> void:
	var burke := DataDB.platform("usn_ddg_arleigh_burke_iia")
	assert_true(not burke.weapon_loadout.has("rgm_84_harpoon"))
	assert_eq(burke.default_air_wing, {"usn_helo_mh60r":2})
	var type45 := DataDB.platform("rn_ddg_type45")
	assert_true(type45.weapon_loadout.has("aster15_family") and type45.weapon_loadout.has("mk8_114mm_gun"))
	assert_true(not type45.weapon_loadout.has("essm_family"))
	assert_eq(type45.occupied_vls_cells(), 48)
	assert_true(DataDB.platform("rnon_ffg_fridtjof_nansen").default_air_wing.is_empty())
	var udaloy := DataDB.platform("rfn_ddg_udaloy")
	assert_true(udaloy.weapon_loadout.has("kinzhal_naval_sam"))
	assert_true(not udaloy.weapon_loadout.has("redut_family"))
	assert_true(DataDB.weapon("kinzhal_naval_sam").profile != "ballistic")

func test_hull_length_limits_turning_circle() -> void:
	Terrain.clear()
	var ship := Unit.new()
	ship.spec = DataDB.platform("usn_cvn_ford")
	ship.speed_kn = 18
	ship.ordered_speed_kn = 18
	ship.ordered_heading_deg = 90
	Movement.step(ship, 10)
	assert_true(ship.heading_deg > 0 and ship.heading_deg < 8, "carrier turns over distance, not about its centre")
	ship.speed_kn = 0
	ship.ordered_speed_kn = 0
	var before := ship.heading_deg
	Movement.step(ship, 1)
	assert_near(ship.heading_deg, before, 0.001, "rudder cannot pivot a stopped hull")

func test_all_authored_charts_have_valid_land_sea_positions_and_routes() -> void:
	for entry in ScenarioIndex.list_all():
		if entry["custom"]: continue
		var sc := ScenarioLoader.load_file(entry["path"])
		Terrain.load_from(sc)
		assert_true(sc["terrain"].has("source"), sc["id"] + " names its geography source")
		for l: Landmass in Terrain.landmasses:
			assert_true(not Geometry2D.triangulate_polygon(l.points).is_empty(), sc["id"] + "/" + l.id + " triangulates")
		var names := []
		for ud in sc["units"]:
			names.append(ud["callsign"])
			var spec := DataDB.platform(ud["platform"])
			assert_true(spec != null, ud["platform"])
			if spec == null: continue
			var p: Array = ud["position_nm"]
			var at := Vector2(p[0], p[1])
			if spec.domain == "land": assert_true(Terrain.is_land(at), ud["callsign"] + " is ashore")
			if spec.domain not in ["surface", "subsurface"]: continue
			assert_true(not Terrain.is_land(at), ud["callsign"] + " starts in water")
			for leg in ud.get("patrol_nm", []):
				var next := Vector2(leg[0], leg[1])
				assert_true(Terrain.first_land_contact(at, next) < 0, sc["id"] + ": " + ud["callsign"] + " patrol clears coast")
				at = next
		for obj in sc["objectives"]["victory"] + sc["objectives"]["loss"]:
			for name in obj.get("callsigns", []): assert_true(name in names, name + " objective resolves")
			if obj["type"] == "reach_area":
				var p: Array = obj["center_nm"]
				assert_true(not Terrain.is_land(Vector2(p[0], p[1])), sc["id"] + " objective in water")
	Terrain.clear()
