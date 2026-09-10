extends TestCase
## Terrain geometry: what is ashore, what a sight line clears and what a hull may do about it.

const ISLAND := {
	"id": "test_island",
	"name": "Test Island",
	"elevation_m": 300.0,
	"points_nm": [[-5, -5], [5, -5], [5, 5], [-5, 5]],
}


func _load(land: Array) -> void:
	Terrain.load_from({"terrain": {"land": land}})


func test_open_ocean_is_untouched() -> void:
	Terrain.clear()
	assert_true(Terrain.is_empty(), "no scenario terrain")
	assert_true(not Terrain.is_land(Vector2(10, 10)), "nothing is ashore")
	assert_true(not Terrain.masks_line_of_sight(Vector2(-50, 0), 25.0, Vector2(50, 0), 25.0), "nothing masks")
	assert_true(not Terrain.blocks_path(Vector2(-50, 0), Vector2(50, 0)), "nothing blocks")
	assert_eq(Terrain.first_land_contact(Vector2(-50, 0), Vector2(50, 0)), -1.0, "no coast to hit")
	assert_eq(Terrain.constrain_step(Vector2.ZERO, Vector2(1, 1)), Vector2(1, 1), "step is free")
	assert_eq(Terrain.distance_to_land_nm(Vector2.ZERO), INF, "no land at any range")


func test_a_scenario_without_terrain_loads_as_open_ocean() -> void:
	_load([ISLAND])
	Terrain.load_from({"units": []})
	assert_true(Terrain.is_empty(), "the previous scenario's coast is gone")


func test_point_in_land() -> void:
	_load([ISLAND])
	assert_eq(Terrain.landmasses.size(), 1, "one landmass")
	assert_true(Terrain.is_land(Vector2.ZERO), "middle of the island")
	assert_true(Terrain.is_land(Vector2(4.9, 0)), "just inside the beach")
	assert_true(not Terrain.is_land(Vector2(5.1, 0)), "just off the beach")
	assert_true(not Terrain.is_land(Vector2(40, 40)), "open water")
	assert_near(Terrain.distance_to_land_nm(Vector2(9, 0)), 4.0, 0.01, "four miles off")
	assert_eq(Terrain.distance_to_land_nm(Vector2(1, 1)), 0.0, "ashore")


func test_a_bay_is_water() -> void:
	# A C-shaped landmass: the water inside the arms is still water.
	_load([{
		"name": "Cape Test",
		"elevation_m": 200.0,
		"points_nm": [[-10, -10], [10, -10], [10, -6], [-6, -6], [-6, 6], [10, 6], [10, 10], [-10, 10]],
	}])
	assert_true(Terrain.is_land(Vector2(-8, 0)), "the spine of the cape")
	assert_true(not Terrain.is_land(Vector2(5, 0)), "the bay between the arms")
	assert_true(Terrain.is_land(Vector2(0, 8)), "the northern arm")


func test_high_ground_masks_two_ships() -> void:
	_load([ISLAND])
	var west := Vector2(-20, 0)
	var east := Vector2(20, 0)
	assert_true(Terrain.masks_line_of_sight(west, 25.0, east, 25.0), "island between two mastheads")
	assert_true(not Terrain.masks_line_of_sight(west, 25.0, Vector2(-20, 40), 25.0), "clear water to the north")


func test_an_aircraft_sees_over_the_island() -> void:
	_load([ISLAND])
	assert_true(not Terrain.masks_line_of_sight(Vector2(-20, 0), 8000.0, Vector2(20, 0), 25.0), "8 km up, looking down")
	assert_true(Terrain.masks_line_of_sight(Vector2(-20, 0), 150.0, Vector2(20, 0), 25.0), "150 m is not enough")


func test_low_ground_does_not_mask() -> void:
	var sandbar := ISLAND.duplicate()
	sandbar["elevation_m"] = 5.0
	_load([sandbar])
	assert_true(not Terrain.masks_line_of_sight(Vector2(-8, 0), 25.0, Vector2(8, 0), 25.0), "a five metre sandbar hides nothing")


func test_sound_does_not_go_through_rock() -> void:
	_load([ISLAND])
	assert_true(Terrain.blocks_path(Vector2(-20, 0), Vector2(20, 0)), "across the island")
	assert_true(not Terrain.blocks_path(Vector2(-20, 20), Vector2(20, 20)), "around the north")
	# Height is irrelevant to sound: the same path masks nothing for a high flyer but still
	# stops an acoustic path.
	assert_true(not Terrain.masks_line_of_sight(Vector2(-20, 0), 9000.0, Vector2(20, 0), 9000.0), "two aircraft see each other")
	assert_true(Terrain.blocks_path(Vector2(-20, 0), Vector2(20, 0)), "sound still blocked")


func test_first_land_contact() -> void:
	_load([ISLAND])
	assert_near(Terrain.first_land_contact(Vector2(-20, 0), Vector2(20, 0)), 0.375, 0.001, "hits the west shore")
	assert_eq(Terrain.first_land_contact(Vector2(-20, 20), Vector2(20, 20)), -1.0, "passes north of it")


func test_a_hull_stops_at_the_beach() -> void:
	_load([ISLAND])
	assert_eq(Terrain.constrain_step(Vector2(-6, 0), Vector2(-4, 0)), Vector2(-6, 0), "straight at the shore, stopped")
	assert_eq(Terrain.constrain_step(Vector2(-6, 0), Vector2(-4, 2)), Vector2(-6, 2), "glancing, slides along the coast")
	assert_eq(Terrain.constrain_step(Vector2(-20, 0), Vector2(-19, 0)), Vector2(-19, 0), "open water is free")


func test_nearest_water() -> void:
	_load([ISLAND])
	var w := Terrain.nearest_water(Vector2(0, 0), Vector2(-30, 0))
	assert_true(not Terrain.is_land(w), "the fallback is wet")
	assert_true(w.x < -5.0, "it backed out the way it came")
	var out := Terrain.nearest_water(Vector2(2, 2))
	assert_true(not Terrain.is_land(out), "with no approach it heads out to sea")
	assert_eq(Terrain.nearest_water(Vector2(30, 30)), Vector2(30, 30), "open water is left alone")


func test_elevation_raster_matches_the_polygon() -> void:
	_load([ISLAND])
	assert_near(Terrain.elevation_at(Vector2.ZERO), 300.0, 0.5, "the middle is high ground")
	assert_eq(Terrain.elevation_at(Vector2(30, 30)), 0.0, "the sea is at sea level")


func test_round_trip_through_json() -> void:
	_load([ISLAND])
	var saved := Terrain.to_dict()
	Terrain.clear()
	assert_true(Terrain.is_empty(), "cleared")
	Terrain.load_from({"terrain": saved})
	assert_eq(Terrain.landmasses.size(), 1, "reloaded")
	assert_eq(Terrain.landmasses[0].name, "Test Island", "kept its name")
	assert_true(Terrain.masks_line_of_sight(Vector2(-20, 0), 25.0, Vector2(20, 0), 25.0), "still masks after a round trip")


func test_a_degenerate_polygon_is_ignored() -> void:
	_load([{"name": "Sliver", "points_nm": [[0, 0], [1, 1]]}])
	assert_true(Terrain.is_empty(), "two points do not enclose anything")


func test_earth_bulge_matches_the_radar_horizon() -> void:
	# A 25 m masthead's horizon is HORIZON_K * sqrt(25) nm; at exactly that range the sea has
	# risen to eye level, which is the same statement the bulge makes.
	var horizon := Detection.radar_horizon_nm(25.0, 0.0)
	assert_near(Geo.earth_bulge_m(horizon, 0.0001), 0.0, 0.01, "no drop at the observer")
	assert_near(Geo.earth_bulge_m(horizon * 0.5, horizon * 0.5) * 4.0, 25.0, 0.05, "the far end sits on the horizon")

# --- What land does to the fight ----------------------------------------------------------

func _radar(surface_nm: float, antenna_m: float) -> SensorSpec:
	var s := SensorSpec.new()
	s.id = "test_radar"
	s.kind = "radar"
	s.range_surface_nm = surface_nm
	s.range_air_nm = surface_nm * 2.0
	s.antenna_height_m = antenna_m
	return s


func _ship(faction: String, pos: Vector2, radar: SensorSpec = null) -> Unit:
	var spec := PlatformSpec.new()
	spec.short_name = "FFG Test"
	spec.domain = "surface"
	spec.max_speed_kn = 30.0
	spec.cruise_speed_kn = 15.0
	spec.turn_rate_deg_s = 6.0
	spec.accel_kn_s = 5.0
	spec.signature_factor = 1.0
	spec.mast_height_m = 25.0
	spec.health = 100.0
	var u := Unit.new()
	u.spec = spec
	u.faction = faction
	u.callsign = "%s-1" % faction
	u.position = pos
	u.health = 100.0
	if radar != null:
		u.sensors.append(radar)
	return u


func _flyer(faction: String, pos: Vector2, altitude_m: float) -> Unit:
	var u := _ship(faction, pos)
	u.spec.domain = "air"
	u.spec.max_speed_kn = 900.0
	u.spec.max_altitude_m = 12000.0
	u.spec.altitude_rate_m_s = 30.0
	u.flight_state = Unit.FlightState.AIRBORNE
	u.altitude_m = altitude_m
	u.ordered_altitude_m = altitude_m
	return u


func test_an_island_hides_a_ship_from_radar() -> void:
	# A radar with plenty of reach and a clear horizon: only the ground is in the way.
	var observer := _ship("BLUE", Vector2(-20, 0), _radar(200.0, 4000.0))
	observer.altitude_m = 0.0
	var target := _ship("RED", Vector2(20, 0))
	Terrain.clear()
	var open_water := Detection.radar_quality(observer, target)
	assert_true(open_water > 0.0, "seen across open water")
	_load([ISLAND])
	assert_near(Detection.radar_quality(observer, target), 0.0, 1e-6, "the island is in the way")
	target.position = Vector2(0, 30)
	assert_true(Detection.radar_quality(observer, target) > 0.0, "clear water north of it")


func test_an_aircraft_over_the_island_is_still_seen() -> void:
	_load([ISLAND])
	var observer := _ship("BLUE", Vector2(-20, 0), _radar(200.0, 4000.0))
	var high := _flyer("RED", Vector2(20, 0), 9000.0)
	assert_true(Detection.radar_quality(observer, high) > 0.0, "an aircraft is above the hill")


func test_sound_and_bearings_stop_at_the_coast() -> void:
	_load([ISLAND])
	var west := _ship("BLUE", Vector2(-20, 0))
	var east := _ship("RED", Vector2(20, 0))
	assert_true(Detection.acoustic_path_blocked(west, east), "no acoustic path through an island")
	assert_true(Detection.terrain_masks(west, east), "no radar or ESM path either")
	east.position = Vector2(-20, 30)
	assert_true(not Detection.acoustic_path_blocked(west, east), "clear water is clear")


func test_a_sea_skimmer_has_no_line_of_fire_over_land() -> void:
	var skimmer := WeaponSpec.new()
	skimmer.id = "test_asm"
	skimmer.type = "asm"
	skimmer.profile = "sea_skimming"
	skimmer.max_range_nm = 80.0
	skimmer.speed_kn = 480.0
	skimmer.target_types = PackedStringArray(["surface"])
	var shooter := _ship("BLUE", Vector2(-20, 0))
	shooter.weapons.append(skimmer)
	shooter.magazines[skimmer.id] = 8
	var target := _ship("RED", Vector2(20, 0))
	var t := Track.new()
	t.id = "T1001"
	t.owner_faction = "BLUE"
	t.truth = target
	t.position = target.position
	t.status = Track.Status.ACTIVE
	t.domain = "surface"
	Terrain.clear()
	assert_true(Combat.check_engagement(shooter, skimmer, t)["ok"], "clear shot over open water")
	_load([ISLAND])
	var blocked := Combat.check_engagement(shooter, skimmer, t)
	assert_true(not blocked["ok"], "the island is in the way")
	assert_eq(blocked["reason"], "NO LINE OF FIRE", "and it says so")
	# A round that flies over the weather does not care about a 300 m hill.
	skimmer.profile = "high"
	assert_true(Combat.check_engagement(shooter, skimmer, t)["ok"], "a high-flying round clears it")
	assert_true(Combat.profile_is_surface_bound(WeaponSpec.new()), "the default profile stays low")


func test_a_hull_cannot_be_ordered_onto_land() -> void:
	_load([ISLAND])
	var um := UnitManager.new()
	var ship := _ship("BLUE", Vector2(-20, 0))
	var jet := _flyer("BLUE", Vector2(-20, 0), 6000.0)
	um.add_unit(ship)
	um.add_unit(jet)
	assert_true(not um.issue_order(ship, Order.move(Vector2.ZERO)), "a ship is refused")
	assert_true(ship.waypoints.is_empty(), "and takes no waypoint from it")
	assert_true(um.issue_order(jet, Order.move(Vector2.ZERO)), "an aircraft overflies it")
	assert_true(um.issue_order(ship, Order.move(Vector2(-20, 30))), "open water is fine")
	um.free()


func test_a_ship_driven_at_a_coast_follows_it() -> void:
	_load([ISLAND])
	var ship := _ship("BLUE", Vector2(-6.0, 0.0))
	ship.heading_deg = 90.0  # due east, straight at the beach
	ship.ordered_heading_deg = 90.0
	ship.speed_kn = 30.0
	ship.ordered_speed_kn = 30.0
	for i in 400:
		Movement.step(ship, 0.25)
	assert_true(not Terrain.is_land(ship.position), "it is still in the water")
	assert_true(ship.position.x <= -4.9, "it did not cross the beach")
	var flyer := _flyer("BLUE", Vector2(-6.0, 0.0), 6000.0)
	flyer.heading_deg = 90.0
	flyer.ordered_heading_deg = 90.0
	flyer.speed_kn = 400.0
	flyer.ordered_speed_kn = 400.0
	for i in 400:
		Movement.step(flyer, 0.25)
	assert_true(flyer.position.x > 0.0, "an aircraft flies straight over")


func test_a_waypoint_ashore_is_dropped() -> void:
	_load([ISLAND])
	var ship := _ship("BLUE", Vector2(-20, 0))
	ship.waypoints.append(Vector2.ZERO)
	ship.ordered_speed_kn = 20.0
	Movement.step(ship, 0.25)
	assert_true(ship.waypoints.is_empty(), "an unreachable waypoint does not survive a tick")
	assert_near(ship.ordered_speed_kn, 0.0, 1e-6, "and the ship stops rather than steering at the beach")


func test_a_screen_station_ashore_is_moved_to_water() -> void:
	_load([ISLAND])
	var leader := _ship("BLUE", Vector2(-14, 0))
	var consort := _ship("BLUE", Vector2(-16, 4))
	consort.formation_leader = leader
	consort.formation_offset = Vector2(0.0, 16.0)  # sixteen miles ahead, i.e. on the island
	leader.heading_deg = 90.0
	var station := Formation.station_for(consort)
	assert_true(not Terrain.is_land(station), "the station is in the water")


func test_open_bearing_turns_along_a_coast() -> void:
	_load([ISLAND])
	var from := Vector2(-20, 0)
	assert_near(Terrain.open_bearing_deg(from, 0.0, 30.0), 0.0, 1e-6, "north is already clear")
	var away := Terrain.open_bearing_deg(from, 90.0, 40.0)
	assert_true(absf(Geo.heading_delta(90.0, away)) > 1.0, "due east is not")
	assert_true(not Terrain.blocks_path(from, from + Geo.heading_to_vector(away) * 40.0), "the chosen bearing is clear")


func test_terrain_state_does_not_leak_into_later_tests() -> void:
	# The whole suite runs in one process, so a coastline left loaded here would silently change
	# every sensor result in every file that runs after this one.
	Terrain.clear()
	assert_true(Terrain.is_empty(), "terrain resets")
	assert_eq(Terrain.elevation_at(Vector2.ZERO), 0.0, "and so does the raster")
