extends TestCase
## The chart's sensor coverage shading: lit where the commander's own radars and sonars reach and
## dark beyond them. Switching a sensor must change what is lit, at once.


func _radar(air := 160.0) -> SensorSpec:
	var s := SensorSpec.new()
	s.kind = "radar"
	s.range_surface_nm = 40.0
	s.range_air_nm = air
	s.antenna_height_m = 20.0
	return s


func _sonar(passive := 12.0, active := 8.0) -> SensorSpec:
	var s := SensorSpec.new()
	s.kind = "sonar"
	s.passive_sensitivity_nm = passive
	s.active_range_nm = active
	s.self_noise_tolerance = 1.0
	return s


func _ship(pos: Vector2, sensors: Array) -> Unit:
	var u := Unit.new()
	u.spec = PlatformSpec.new()
	u.spec.domain = "surface"
	u.spec.max_speed_kn = 30.0
	u.spec.mast_height_m = 25.0
	u.faction = "BLUE"
	u.position = pos
	u.health = 100.0
	for s: SensorSpec in sensors:
		u.sensors.append(s)
	return u


func _kinds(discs: Array[Vector4]) -> Array:
	return discs.map(func(d: Vector4) -> float: return d.w)


func test_a_radiating_radar_lights_its_surface_reach_and_its_air_search_beyond() -> void:
	var ship := _ship(Vector2(10, 5), [_radar()])
	var discs := SensorCoverage.discs([ship])
	assert_eq(_kinds(discs), [SensorCoverage.RADAR_SURFACE, SensorCoverage.RADAR_AIR])
	assert_near(discs[0].z, Detection.nominal_radar_ring_nm(ship), 0.001, "surface reach is the radar's horizon")
	assert_near(discs[1].z, 160.0, 0.001, "air search reaches its stated range")
	assert_eq(SensorCoverage.cover_at(discs, ship.position), "radar")
	assert_eq(SensorCoverage.cover_at(discs, ship.position + Vector2(100, 0)), "air")
	assert_eq(SensorCoverage.cover_at(discs, ship.position + Vector2(200, 0)), "", "dark beyond every sensor")


func test_switching_the_radar_off_takes_its_light_away_at_once() -> void:
	var ship := _ship(Vector2.ZERO, [_radar(), _sonar()])
	assert_true(SensorCoverage.discs([ship]).size() == 3)
	ship.apply_order(Order.silence_radar())
	var discs := SensorCoverage.discs([ship])
	assert_eq(_kinds(discs), [SensorCoverage.SONAR], "only the sonar is still listening")
	assert_eq(SensorCoverage.cover_at(discs, Vector2(20, 0)), "", "what the radar covered is dark")
	ship.apply_order(Order.activate_radar())
	assert_eq(SensorCoverage.discs([ship]).size(), 3, "and it comes back when the radar does")


func test_going_active_on_sonar_widens_the_lit_water_when_it_reaches_further() -> void:
	var ship := _ship(Vector2.ZERO, [_sonar(6.0, 15.0)])
	var passive := SensorCoverage.discs([ship])
	assert_near(passive[0].z, Detection.nominal_passive_ring_nm(ship), 0.001)
	ship.apply_order(Order.active_sonar())
	var active := SensorCoverage.discs([ship])
	assert_true(active[0].z > passive[0].z, "an active set reaching further lights more water")


func test_aircraft_on_deck_light_nothing_and_aircraft_flying_do() -> void:
	var plane := _ship(Vector2(50, 0), [_radar(250.0)])
	plane.spec.domain = "air"
	plane.flight_state = Unit.FlightState.STOWED
	assert_true(SensorCoverage.discs([plane]).is_empty(), "a radar in the hangar covers nothing")
	plane.flight_state = Unit.FlightState.AIRBORNE
	plane.altitude_m = 8000.0
	assert_true(not SensorCoverage.discs([plane]).is_empty())


func test_a_damaged_radar_lights_less() -> void:
	var ship := _ship(Vector2.ZERO, [_radar()])
	var whole := SensorCoverage.discs([ship])[0].z
	ship.components["sensors"] = 0.5
	assert_true(SensorCoverage.discs([ship])[0].z < whole)


func test_surface_radar_is_kept_first_when_there_are_more_discs_than_the_chart_holds() -> void:
	var units: Array = []
	for i in SensorCoverage.MAX_DISCS:
		units.append(_ship(Vector2(i * 10.0, 0), [_radar(), _sonar()]))
	var discs := SensorCoverage.discs(units)
	assert_eq(discs.size(), SensorCoverage.MAX_DISCS)
	assert_true(discs.all(func(d: Vector4) -> bool: return d.w == SensorCoverage.RADAR_SURFACE), "every ship's radar reach survives the cap")


func test_the_chart_layer_is_on_by_default_and_toggles() -> void:
	var map := TacticalMap.new()
	assert_true(map.show_coverage)
	assert_true(not map.toggle_layer("coverage"))
	assert_true(map.toggle_layer("coverage"))
	map.free()


func test_a_stale_contact_fades_as_it_ages() -> void:
	var t := Track.new()
	t.last_seen_time = 0.0
	t.status = Track.Status.STALE
	var fresh := TacticalMap.stale_alpha(t, Track.STALE_AFTER_S + 1.0)
	var old := TacticalMap.stale_alpha(t, Track.STALE_AFTER_S + TacticalMap.STALE_FADE_S * 2.0)
	assert_near(fresh, TacticalMap.STALE_ALPHA, 0.01, "just gone stale: the usual fade")
	assert_near(old, TacticalMap.STALE_FLOOR_ALPHA, 0.001, "long unseen: faint")
