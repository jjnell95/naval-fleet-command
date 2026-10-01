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

# Escort arrival without a kill, and the escorted ship's loss overriding arrival, are covered by
# test_northern_passage. A passage watch resolved by kill, watch or breakout is covered by the
# 1990 barrier in test_cold_war. M35 cut the missions these tests used to load.

func test_named_target_victory_ignores_the_rest_of_the_enemy_force() -> void:
	var um := UnitManager.new()
	for pair in [["Boat", 10.0], ["Flanker 11", 30.0]]:
		var spec := PlatformSpec.new()
		spec.health = pair[1]
		var u := Unit.new()
		u.spec = spec
		u.faction = "RED"
		u.callsign = pair[0]
		u.health = pair[1]
		um.add_unit(u)
	var hunt := MissionObjective.from_dict({"type": "all_units_lost", "callsigns": ["Boat"]})
	assert_true(not hunt.evaluate(um, 1), "the boat is still afloat")
	Damage.apply(_find(um, "Boat"), 10000)
	assert_true(hunt.evaluate(um, 2), "sinking the named boat is the task")
	assert_true(_find(um, "Flanker 11").alive, "its supporting aircraft never had to die")
	um.free()

func test_hormuz_needs_two_tankers_through_and_only_own_fire_on_neutrals_fails_it() -> void:
	var h := _mission("gulf_01_hormuz")
	h[1].tick(0)
	h[1].tick(300)
	var transit: MissionObjective = h[1].victory_objectives[1]
	_find(h[0], "MT Gulf Horizon").position = transit.center
	h[1].tick(301)
	assert_true(not transit.complete, "one tanker is not the convoy")
	_find(h[0], "MT Ras Laffan Pride").position = transit.center
	h[1].tick(302)
	assert_true(transit.complete, "two of the three tankers clear the strait")
	assert_eq(h[1].result, MissionManager.Result.RUNNING, "then hold the box")
	h[1].tick(603)
	assert_eq(h[1].result, MissionManager.Result.VICTORY)
	_cleanup(h)
	h = _mission("gulf_01_hormuz")
	Damage.apply(_find(h[0], "Dhow Al Noor"), 10000, "gun", "RED")
	h[1].tick(1)
	assert_eq(h[1].result, MissionManager.Result.RUNNING, "an enemy sinking a dhow is not the player's incident")
	Damage.apply(_find(h[0], "MV Khor Fakkan Trader"), 10000, "gun", "BLUE")
	h[1].tick(2)
	assert_eq(h[1].result, MissionManager.Result.DEFEAT, "own fire on a neutral fails the operation")
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
