extends TestCase
## Defects found in a read of the simulation core, each pinned by the case that showed it.


func _boat(depth: float) -> Unit:
	var u := Unit.new()
	u.spec = PlatformSpec.new()
	u.spec.domain = "subsurface"
	u.spec.max_speed_kn = 20.0
	u.spec.max_depth_m = 240.0
	u.spec.depth_rate_m_s = 2.0
	u.faction = "RED"
	u.health = 45.0
	u.depth_m = depth
	u.ordered_depth_m = depth
	return u


func _torpedo(types: Array) -> WeaponSpec:
	var s := WeaponSpec.new()
	s.id = "test_torpedo"
	s.type = "torpedo"
	s.guidance = "acoustic_homing"
	s.profile = "subsurface"
	s.target_types = PackedStringArray(types)
	s.max_range_nm = 25.0
	s.speed_kn = 50.0
	s.seeker_range_nm = 2.5
	s.seeker_half_angle_deg = 60.0
	s.turn_rate_deg_s = 15.0
	s.base_pk = 1.0
	s.damage = 90.0
	return s


func test_coming_up_to_periscope_depth_is_no_escape_from_an_asw_torpedo() -> void:
	var asw := _torpedo(["subsurface"])
	for depth: float in [100.0, 18.0, 0.0]:
		assert_true(WeaponManager.can_target(asw, _boat(depth)), "an ASW torpedo homes on a boat at %d m" % int(depth))
	var asm := WeaponSpec.new()
	asm.target_types = PackedStringArray(["surface"])
	assert_true(not WeaponManager.can_target(asm, _boat(100.0)), "a surface seeker still cannot see a submerged boat")
	assert_true(WeaponManager.can_target(asm, _boat(0.0)), "and still can see a surfaced one")


func test_a_torpedo_runs_on_down_the_bearing_past_a_short_range_guess() -> void:
	Terrain.clear()
	Detection.set_environment({})
	var boat := _boat(100.0)
	boat.position = Vector2(0, 13)
	var wm := WeaponManager.new()
	wm.rng.seed = 3
	wm.unit_manager = UnitManager.new()
	wm.unit_manager.add_unit(boat)
	var w := Weapon.new()
	w.id = 1
	w.spec = _torpedo(["subsurface", "surface"])
	w.faction = "BLUE"
	w.aim_point = Vector2(0, 8)  # the plot's guess, five miles short on a true bearing
	wm.in_flight.append(w)
	var t := 0.0
	while t < 2400.0 and w.phase != Weapon.Phase.DEAD:
		t += 0.5
		wm.tick(0.5, t)
	assert_eq(w.dead_reason, "HIT", "it kept searching past the guessed range")
	wm.clear()
	wm.unit_manager.free()
	wm.free()


func _aircraft() -> Unit:
	var u := Unit.new()
	u.spec = DataDB.platform("usn_fighter_fa18e")
	u.flight_state = Unit.FlightState.AIRBORNE
	u.altitude_m = 5000.0
	u.ordered_altitude_m = 5000.0
	u.fuel_s = 9000.0
	return u


func test_a_jet_cannot_be_ordered_below_flying_speed() -> void:
	Terrain.clear()
	var u := _aircraft()
	u.speed_kn = 480.0
	u.waypoints.assign([Vector2(0, 400)])
	u.ordered_speed_kn = 10.0
	for i in 2400:
		Movement.step(u, 0.25)
	var floor_kn := u.spec.flight_speed("patrol") * Movement.MIN_FLYING_FRACTION
	assert_near(u.speed_kn, floor_kn, 0.5, "held at the slowest it can fly, not the 10 knots ordered")


func test_a_waypoint_inside_the_turning_circle_is_passed_not_orbited() -> void:
	Terrain.clear()
	var u := _aircraft()
	u.speed_kn = 480.0
	u.ordered_speed_kn = 480.0
	u.waypoints.assign([Vector2(1.1, 0.3), Vector2(0, 60)])
	var t := 0.0
	while t < 900.0 and u.waypoints.size() > 1:
		Movement.step(u, 0.25)
		t += 0.25
	assert_eq(u.waypoints.size(), 1, "the unreachable point is given up and the route goes on")
	# A ship ordered to a point close astern is outside both circles: she comes round to it.
	var ship := Unit.new()
	ship.spec = DataDB.platform("usn_ddg_arleigh_burke_iia")
	ship.speed_kn = 30.0
	ship.ordered_speed_kn = 30.0
	ship.health = ship.spec.health
	ship.waypoints.assign([Vector2(0, -0.3), Vector2(0, -40)])
	Movement.step(ship, 0.25)
	assert_eq(ship.waypoints.size(), 2, "not written off at once")
	t = 0.0
	while t < 600.0 and ship.waypoints.size() > 1:
		Movement.step(ship, 0.25)
		t += 0.25
	assert_true(t > 30.0 and ship.waypoints.size() == 1, "reached by turning, after %.0f s" % t)


func test_wrecked_sensors_shorten_the_warning_of_incoming_weapons() -> void:
	var ship := Unit.new()
	ship.spec = PlatformSpec.new()
	var radar := SensorSpec.new()
	radar.kind = "radar"
	radar.range_air_nm = 200.0
	radar.antenna_height_m = 20.0
	var sonar := SensorSpec.new()
	sonar.kind = "sonar"
	sonar.passive_sensitivity_nm = 20.0
	ship.sensors.append(radar)
	ship.sensors.append(sonar)
	var missile := WeaponSpec.new()
	missile.altitude_m = 8000.0
	missile.signature_factor = 0.1
	var torpedo := _torpedo(["surface"])
	var radar_before := Detection.best_weapon_detection_nm(ship, missile)
	var sonar_before := Detection.torpedo_detection_nm(ship, torpedo)
	ship.components["sensors"] = 0.2
	assert_near(Detection.best_weapon_detection_nm(ship, missile) / radar_before, ship.sensor_efficiency(), 0.001, "radar warning shortened like every other radar range")
	assert_near(Detection.torpedo_detection_nm(ship, torpedo) / sonar_before, ship.sensor_efficiency(), 0.001, "and torpedo warning")


func test_a_coasting_air_track_is_assumed_to_be_on_the_deck_for_guidance() -> void:
	Terrain.clear()
	var ship := Unit.new()
	ship.spec = PlatformSpec.new()
	ship.spec.mast_height_m = 25.0
	var radar := SensorSpec.new()
	radar.kind = "radar"
	ship.sensors.append(radar)
	var sam := WeaponSpec.new()
	sam.type = "sam"
	sam.guidance = "semi_active_radar"
	var t := Track.new()
	t.domain = "air"
	t.position = Vector2(0, 60)
	t.altitude_m = 8000.0
	assert_true(WeaponManager.track_support_available(ship, sam, t), "plotted high: inside the illuminator's horizon")
	t.status = Track.Status.STALE
	assert_true(not WeaponManager.track_support_available(ship, sam, t), "no longer plotted: its old height is not evidence")
