extends TestCase
## Aircraft exist to put a sensor somewhere other than where the ship is, and fuel is what that
## costs. These tests pin the deck cycle, the fuel clock, and the reach that altitude buys.

const DT := 0.25


func _ship_spec(capacity := 1) -> PlatformSpec:
	var p := PlatformSpec.new()
	p.short_name = "DDG Test"
	p.domain = "surface"
	p.max_speed_kn = 30.0
	p.cruise_speed_kn = 16.0
	p.health = 110.0
	p.signature_factor = 1.0
	p.mast_height_m = 30.0
	p.acoustic_signature = 1.0
	p.aircraft_capacity = capacity
	p.turnaround_s = 600.0  # short of a real deck cycle, long enough to observe
	return p


func _helo_spec(endurance := 3600.0) -> PlatformSpec:
	var p := PlatformSpec.new()
	p.short_name = "Helo Test"
	p.domain = "air"
	p.max_speed_kn = 145.0
	p.cruise_speed_kn = 110.0
	p.turn_rate_deg_s = 6.0
	p.accel_kn_s = 2.0
	p.health = 20.0
	p.signature_factor = 0.25
	p.cruise_altitude_m = 500.0
	p.max_altitude_m = 3500.0
	p.altitude_rate_m_s = 8.0
	p.endurance_s = endurance
	p.can_hover = true
	p.launch_time_s = 60.0
	p.recovery_time_s = 60.0
	p.sonobuoy_count = 4
	p.sonobuoy_sensitivity_nm = 24.0
	p.sonobuoy_life_s = 1800.0
	return p


func _boat_spec() -> PlatformSpec:
	var p := PlatformSpec.new()
	p.short_name = "SSK Test"
	p.domain = "subsurface"
	p.max_speed_kn = 20.0
	p.cruise_speed_kn = 6.0
	p.acoustic_signature = 0.05
	p.max_depth_m = 240.0
	p.patrol_depth_m = 90.0
	p.depth_rate_m_s = 2.0
	p.health = 45.0
	return p


func _unit(spec: PlatformSpec, faction: String, pos: Vector2, speed := 0.0) -> Unit:
	var u := Unit.new()
	u.spec = spec
	u.faction = faction
	u.callsign = "%s-%d" % [faction, randi() % 1000]
	u.position = pos
	u.speed_kn = speed
	u.ordered_speed_kn = speed
	u.health = spec.health
	return u


class Harness:
	extends RefCounted
	var um: UnitManager
	var av: AviationManager
	var tm: TrackManager
	var sm: SensorManager

	func free_all() -> void:
		if sm != null:
			sm.free()
		if tm != null:
			tm.free()
		av.free()
		um.free()


func _harness(units: Array, with_sensors := false) -> Harness:
	var h := Harness.new()
	h.um = UnitManager.new()
	for u: Unit in units:
		h.um.add_unit(u)
	h.av = AviationManager.new()
	h.av.unit_manager = h.um
	if with_sensors:
		h.tm = TrackManager.new()
		h.sm = SensorManager.new()
		h.sm.unit_manager = h.um
		h.sm.track_manager = h.tm
		h.sm.aviation_manager = h.av
		h.sm.rng.seed = 4
	return h


func _embark(parent: Unit, aircraft: Unit) -> void:
	aircraft.home = parent
	aircraft.home_callsign = parent.callsign
	aircraft.fuel_s = aircraft.spec.endurance_s
	aircraft.sonobuoys = aircraft.spec.sonobuoy_count
	parent.embarked.append(aircraft)


func _run(h: Harness, seconds: float, now_start := 0.0) -> float:
	var now := now_start
	for i in int(seconds / DT):
		now += DT
		h.um.tick(DT)
		h.av.tick(DT, now)
	return now


# --- Deck cycle --------------------------------------------------------------------------

func test_a_stowed_aircraft_is_not_on_the_board() -> void:
	var ship := _unit(_ship_spec(), "BLUE", Vector2.ZERO)
	var helo := _unit(_helo_spec(), "BLUE", Vector2.ZERO)
	_embark(ship, helo)
	assert_true(not helo.is_engageable(), "a helicopter in the hangar cannot be found or hit")
	assert_true(not helo.airborne())
	assert_eq(ship.stowed_aircraft().size(), 1, "but it is available")
	var h := _harness([ship, helo])
	assert_eq(h.um.get_engageable_units("BLUE").size(), 1, "only the ship counts")
	h.free_all()


func test_launch_takes_time_then_puts_the_aircraft_up() -> void:
	var ship := _unit(_ship_spec(), "BLUE", Vector2.ZERO)
	var helo := _unit(_helo_spec(), "BLUE", Vector2.ZERO)
	_embark(ship, helo)
	var h := _harness([ship, helo])
	assert_true(h.av.launch(ship) != null, "launch accepted")
	assert_eq(helo.flight_state, Unit.FlightState.LAUNCHING)
	_run(h, 30.0)
	assert_eq(helo.flight_state, Unit.FlightState.LAUNCHING, "still on the deck at 30 s")
	_run(h, 40.0, 30.0)
	assert_true(helo.airborne(), "airborne after the launch time")
	assert_true(helo.fuel_s > helo.spec.endurance_s - 30.0, "with full tanks")
	assert_eq(helo.sonobuoys, 4)
	h.free_all()


func test_launching_an_empty_hangar_is_refused() -> void:
	var ship := _unit(_ship_spec(0), "BLUE", Vector2.ZERO)
	var h := _harness([ship])
	var reasons: Array[String] = []
	h.av.launch_rejected.connect(func(_p: Unit, r: String) -> void: reasons.append(r))
	assert_true(h.av.launch(ship) == null)
	assert_eq(reasons.size(), 1)
	assert_eq(reasons[0], "NO AIRCRAFT AVAILABLE")
	h.free_all()


func test_fuel_burns_faster_at_speed() -> void:
	var ship := _unit(_ship_spec(), "BLUE", Vector2.ZERO)
	var slow := _unit(_helo_spec(), "BLUE", Vector2.ZERO)
	_embark(ship, slow)
	var h := _harness([ship, slow])
	h.av.launch(ship)
	var now := _run(h, 70.0)
	slow.ordered_speed_kn = 0.0
	slow.speed_kn = 0.0
	var before := slow.fuel_s
	now = _run(h, 200.0, now)
	var hover_burn := before - slow.fuel_s
	slow.speed_kn = slow.spec.max_speed_kn
	slow.ordered_speed_kn = slow.spec.max_speed_kn
	before = slow.fuel_s
	_run(h, 200.0, now)
	var dash_burn := before - slow.fuel_s
	assert_true(dash_burn > hover_burn * 1.3, "a dash costs more than the clock suggests")
	h.free_all()


func test_bingo_fuel_sends_it_home_and_it_recovers() -> void:
	var ship := _unit(_ship_spec(), "BLUE", Vector2.ZERO)
	var helo := _unit(_helo_spec(1800.0), "BLUE", Vector2.ZERO)
	_embark(ship, helo)
	var h := _harness([ship, helo])
	h.av.launch(ship)
	# GDScript lambdas capture locals by value, so a counter has to live in a reference type.
	var bingo_calls: Array[String] = []
	h.av.aircraft_bingo.connect(func(a: Unit) -> void: bingo_calls.append(a.callsign))
	var now := _run(h, 70.0)
	helo.position = Vector2(0.0, 8.0)  # out on task, six minutes from the deck
	helo.ordered_speed_kn = helo.spec.cruise_speed_kn
	# Wind the tanks down to just above bingo so the decision happens promptly.
	helo.fuel_s = helo.spec.endurance_s * 0.30
	now = _run(h, 60.0, now)
	assert_eq(bingo_calls.size(), 1, "warned once when the tanks got low")
	assert_true(helo.returning, "and turned for home")
	now = _run(h, 400.0, now)
	assert_eq(helo.flight_state, Unit.FlightState.TURNAROUND, "aboard, but being turned round")
	assert_true(helo.fuel_s < helo.spec.endurance_s, "not refuelled the instant the wheels touch")
	assert_true(ship.stowed_aircraft().is_empty(), "and not yet a sortie the ship has")
	_run(h, 700.0, now)
	assert_eq(helo.flight_state, Unit.FlightState.STOWED, "ready again once the deck has turned it")
	assert_near(helo.fuel_s, helo.spec.endurance_s, 1.0, "refuelled")
	assert_true(helo.alive)
	h.free_all()


func test_running_the_tanks_dry_loses_the_aircraft() -> void:
	var ship := _unit(_ship_spec(), "BLUE", Vector2.ZERO)
	var helo := _unit(_helo_spec(200.0), "BLUE", Vector2.ZERO)
	_embark(ship, helo)
	var h := _harness([ship, helo])
	h.av.launch(ship)
	var lost: Array[String] = []
	h.av.aircraft_lost.connect(func(_a: Unit, r: String) -> void: lost.append(r))
	var now := _run(h, 70.0)
	helo.position = Vector2(0.0, 400.0)  # far too far to get back
	helo.home = null  # and nowhere to divert to
	_run(h, 400.0, now)
	assert_eq(lost.size(), 1)
	assert_eq(lost[0], "OUT OF FUEL")
	assert_true(not helo.alive)
	h.free_all()


func test_a_stranded_aircraft_diverts_to_another_deck() -> void:
	var ship := _unit(_ship_spec(), "BLUE", Vector2.ZERO)
	var consort := _unit(_ship_spec(), "BLUE", Vector2(0.0, 4.0))
	consort.callsign = "Consort"
	var helo := _unit(_helo_spec(1800.0), "BLUE", Vector2.ZERO)
	_embark(ship, helo)
	var h := _harness([ship, consort, helo])
	h.av.launch(ship)
	var now := _run(h, 70.0)
	helo.position = Vector2(0.0, 6.0)
	helo.fuel_s = helo.spec.endurance_s * 0.30
	Damage.apply(ship, 500.0)  # the deck it came from is gone
	_run(h, 1400.0, now)
	assert_eq(helo.home, consort, "it found somewhere else to land")
	assert_eq(helo.flight_state, Unit.FlightState.STOWED)
	assert_true(helo.alive, "losing the ship should cost the sortie, not the airframe")
	h.free_all()


# --- What altitude buys ------------------------------------------------------------------

func _radar(surface := 40.0, air := 200.0, antenna := 20.0) -> SensorSpec:
	var s := SensorSpec.new()
	s.kind = "radar"
	s.range_surface_nm = surface
	s.range_air_nm = air
	s.antenna_height_m = antenna
	return s


func test_an_aircraft_at_altitude_is_seen_from_far_off() -> void:
	var ship := _unit(_ship_spec(), "BLUE", Vector2.ZERO)
	ship.sensors.append(_radar())
	var helo_spec := _helo_spec()
	var helo := _unit(helo_spec, "RED", Vector2(0.0, 40.0))
	helo.flight_state = Unit.FlightState.AIRBORNE
	helo.altitude_m = 500.0
	var reach := Detection.best_radar_air_range_nm(ship, helo.spec.signature_factor, helo.altitude_m)
	assert_true(reach > 40.0, "a helicopter at 500 m is well over the horizon of a ship's mast")
	assert_true(Detection.radar_quality(ship, helo) > 0.0, "so it is detected at 40 nm")
	helo.flight_state = Unit.FlightState.STOWED
	assert_near(Detection.radar_quality(ship, helo), 0.0, 1e-6, "in a hangar it is nothing at all")


func test_an_airborne_radar_sees_ships_far_past_a_ships_horizon() -> void:
	var mpa_spec := _helo_spec()
	mpa_spec.cruise_altitude_m = 8000.0
	mpa_spec.max_altitude_m = 12000.0
	var mpa := _unit(mpa_spec, "BLUE", Vector2.ZERO)
	mpa.flight_state = Unit.FlightState.AIRBORNE
	mpa.altitude_m = 8000.0
	mpa.sensors.append(_radar(120.0, 200.0, 3.0))
	var ship := _unit(_ship_spec(), "RED", Vector2(0.0, 60.0))
	var from_air := Detection.best_radar_range_nm(mpa, 1.0, ship.spec.mast_height_m)
	var surface_ship := _unit(_ship_spec(), "BLUE", Vector2.ZERO)
	surface_ship.sensors.append(_radar(120.0, 200.0, 20.0))
	var from_deck := Detection.best_radar_range_nm(surface_ship, 1.0, ship.spec.mast_height_m)
	assert_true(from_air > from_deck * 3.0, "height is the whole reason to put a radar in an aeroplane")
	assert_true(Detection.radar_quality(mpa, ship) > 0.0, "60 nm is nothing from eight kilometres up")


# --- Dipping sonar and buoys -------------------------------------------------------------

func _dipping_set() -> SensorSpec:
	var s := SensorSpec.new()
	s.kind = "sonar"
	s.passive_sensitivity_nm = 38.0
	s.active_range_nm = 11.0
	s.bearing_accuracy_deg = 1.0
	s.self_noise_tolerance = 0.95
	s.requires_hover = true
	return s


func test_a_dipping_set_only_works_stopped_and_low() -> void:
	var helo := _unit(_helo_spec(), "BLUE", Vector2.ZERO)
	helo.flight_state = Unit.FlightState.AIRBORNE
	helo.sensors.append(_dipping_set())
	var boat := _unit(_boat_spec(), "RED", Vector2(0.0, 3.0), 6.0)
	boat.depth_m = 90.0

	helo.speed_kn = 110.0
	helo.altitude_m = 500.0
	assert_true(not helo.is_hovering())
	assert_near(Detection.best_passive_sonar(helo, boat)["range_nm"], 0.0, 1e-6, "a set in the air hears nothing")

	helo.speed_kn = 0.0
	helo.altitude_m = 50.0
	assert_true(helo.is_hovering(), "stopped and low is what dipping means")
	assert_true(Detection.best_passive_sonar(helo, boat)["range_nm"] > 3.0, "and then it hears the boat")


func test_one_buoy_gives_a_circle_and_two_give_a_position() -> void:
	var boat := _unit(_boat_spec(), "RED", Vector2.ZERO, 6.0)
	boat.depth_m = 90.0
	var ship := _unit(_ship_spec(), "BLUE", Vector2(0.0, 200.0))  # far away, contributing nothing
	var h := _harness([ship, boat], true)

	var b1 := Sonobuoy.new()
	b1.id = 1
	b1.faction = "BLUE"
	b1.position = Vector2(1.0, 0.0)
	b1.sensitivity_nm = 24.0
	b1.expires_at = 9999.0
	h.av.sonobuoys.append(b1)
	h.sm.run_cycle(1.0)
	var t: Track = h.tm.get_tracks("BLUE")[0]
	assert_eq(t.source, "sonobuoy")
	var single_error := t.error_major_nm
	assert_true(single_error > 1.5, "one buoy says only that something noisy is inside its circle")

	var b2 := Sonobuoy.new()
	b2.id = 2
	b2.faction = "BLUE"
	b2.position = Vector2(-1.0, 0.5)
	b2.sensitivity_nm = 24.0
	b2.expires_at = 9999.0
	h.av.sonobuoys.append(b2)
	h.sm.run_cycle(2.0)
	assert_true(t.error_major_nm < single_error, "two overlapping circles cross, and that is a position")
	assert_true(t.position.distance_to(boat.position) < 2.0, "close to the truth")
	h.free_all()


func test_buoys_stop_listening_when_they_expire() -> void:
	var b := Sonobuoy.new()
	b.expires_at = 100.0
	assert_true(b.alive_at(50.0))
	assert_true(not b.alive_at(150.0))


func test_a_buoy_hears_a_fast_boat_further_than_a_slow_one() -> void:
	var b := Sonobuoy.new()
	b.sensitivity_nm = 24.0
	var slow := _unit(_boat_spec(), "RED", Vector2.ZERO, 4.0)
	slow.depth_m = 90.0
	var fast := _unit(_boat_spec(), "RED", Vector2.ZERO, 16.0)
	fast.depth_m = 90.0
	assert_true(b.reach_against(fast) > b.reach_against(slow) * 1.5, "the same acoustics as everything else")


# --- What can shoot what -----------------------------------------------------------------

func test_air_defence_can_engage_aircraft_but_torpedoes_cannot() -> void:
	var sam := DataDB.weapon("essm_family")
	var torp := DataDB.weapon("mk54_lwt")
	assert_true(sam != null and torp != null)
	if sam == null or torp == null:
		return
	var helo := _unit(_helo_spec(), "RED", Vector2.ZERO)
	helo.flight_state = Unit.FlightState.AIRBORNE
	helo.altitude_m = 500.0
	assert_true(WeaponManager.can_target(sam, helo), "a surface-to-air missile is for exactly this")
	assert_true(not WeaponManager.can_target(torp, helo), "a torpedo is not")
	assert_true(sam.damage > 0.0, "and it has to actually do damage, not just intercept")


func test_nothing_in_the_inventory_can_attack_a_shore_station() -> void:
	var base := DataDB.platform("shore_air_station")
	assert_true(base != null)
	if base == null:
		return
	assert_eq(base.domain, "land")
	var station := _unit(base, "RED", Vector2.ZERO)
	for wid in ["rgm_84_harpoon", "nsm_strike_missile", "mk48_adcap", "essm_family"]:
		var w := DataDB.weapon(wid)
		if w != null:
			assert_true(not WeaponManager.can_target(w, station), "%s cannot strike a land target" % wid)


# --- Movement ----------------------------------------------------------------------------

func test_altitude_changes_at_the_stated_rate() -> void:
	var helo := _unit(_helo_spec(), "BLUE", Vector2.ZERO)
	helo.flight_state = Unit.FlightState.AIRBORNE
	helo.apply_order(Order.set_altitude(800.0))
	for i in int(50.0 / DT):
		Movement.step(helo, DT)
	assert_near(helo.altitude_m, 400.0, 1.0, "8 m/s for 50 s")
	helo.apply_order(Order.set_altitude(99999.0))
	assert_near(helo.ordered_altitude_m, helo.spec.max_altitude_m, 1e-6, "clamped to the ceiling")


func test_a_stowed_aircraft_rides_with_its_ship() -> void:
	var ship := _unit(_ship_spec(), "BLUE", Vector2.ZERO)
	var helo := _unit(_helo_spec(), "BLUE", Vector2.ZERO)
	_embark(ship, helo)
	ship.position = Vector2(10.0, 5.0)
	Movement.step(helo, DT)
	assert_eq(helo.position, ship.position, "it goes where the ship goes")
	assert_near(helo.altitude_m, 0.0, 1e-6)


# --- Shipped data ------------------------------------------------------------------------

func test_shipped_aviation_data_loads() -> void:
	for pid in ["usn_helo_mh60r", "usn_mpa_p8a", "rfn_strike_su30sm"]:
		var p := DataDB.platform(pid)
		assert_true(p != null, "%s loads" % pid)
		if p == null:
			continue
		assert_eq(p.domain, "air")
		assert_true(p.endurance_s > 0.0, "%s has fuel" % pid)
		assert_true(p.cruise_altitude_m > 0.0 and p.altitude_rate_m_s > 0.0, "%s can climb" % pid)
		for sid in p.sensor_ids:
			assert_true(DataDB.sensor(sid) != null, "%s uses a real sensor" % pid)
		for wid in p.weapon_loadout:
			assert_true(DataDB.weapon(wid) != null, "%s carries a real weapon" % pid)
	var helo := DataDB.platform("usn_helo_mh60r")
	if helo != null:
		assert_true(helo.can_hover, "a helicopter can stop")
		assert_true(helo.sonobuoy_count > 0)
	var mpa := DataDB.platform("usn_mpa_p8a")
	if mpa != null:
		assert_true(not mpa.can_hover, "a Poseidon cannot")
		assert_true(mpa.sonobuoy_count > helo.sonobuoy_count, "but it carries far more buoys")
	var dipping := DataDB.sensor("an_aqs_22")
	assert_true(dipping != null and dipping.requires_hover, "the dipping set is flagged as such")


func test_ships_that_operate_helicopters_have_somewhere_to_put_them() -> void:
	for pid in ["usn_ddg_arleigh_burke_iia", "rnon_ffg_fridtjof_nansen"]:
		var p := DataDB.platform(pid)
		assert_true(p != null and p.aircraft_capacity > 0, "%s has a hangar" % pid)


# --- Tanking ------------------------------------------------------------------------------
## A tanker is what turns a strike radius into an operating radius. These pin the part that
## matters: a receiver at bingo takes fuel instead of the deck, and cannot drain a tanker dry.

## A deck that can work fixed-wing aircraft. A helicopter deck cannot, which is the rule these
## tests kept tripping over before the fixture admitted what it was.
func _carrier_spec(capacity := 8) -> PlatformSpec:
	var p := _ship_spec(capacity)
	p.short_name = "CVN Test"
	p.category = "carrier"
	p.aviation_facility = "catobar"
	p.launch_spots = 4
	p.recovery_spots = 1
	p.turnaround_s = 600.0
	return p


func _tanker_spec() -> PlatformSpec:
	var p := _helo_spec(20000.0)
	p.short_name = "Tanker Test"
	p.can_hover = false
	p.cruise_speed_kn = 280.0
	p.max_speed_kn = 320.0
	p.cruise_altitude_m = 8000.0
	p.tanker_offload_s = 6000.0
	p.launch_requirement = "catobar"
	return p


func _receiver_spec() -> PlatformSpec:
	var p := _helo_spec(3600.0)
	p.short_name = "Receiver Test"
	p.can_hover = false
	p.cruise_speed_kn = 400.0
	p.max_speed_kn = 900.0
	p.cruise_altitude_m = 9000.0
	p.can_refuel = true
	p.launch_requirement = "catobar"
	return p


func test_a_thirsty_aircraft_takes_the_basket_instead_of_the_deck() -> void:
	var ship := _unit(_carrier_spec(4), "BLUE", Vector2.ZERO)
	var jet := _unit(_receiver_spec(), "BLUE", Vector2(0.0, 40.0))
	var tanker := _unit(_tanker_spec(), "BLUE", Vector2(0.0, 42.0))
	_embark(ship, jet)
	_embark(ship, tanker)
	var h := _harness([ship, jet, tanker])
	h.av.launch(ship)
	h.av.launch(ship)
	var now := _run(h, 70.0)
	# Both airborne and well out on task; put the tanker where it belongs and run the jet down.
	jet.flight_state = Unit.FlightState.AIRBORNE
	tanker.flight_state = Unit.FlightState.AIRBORNE
	tanker.position = Vector2(0.0, 42.0)
	tanker.fuel_s = tanker.spec.endurance_s
	tanker.tanker_offload_s = tanker.spec.tanker_offload_s
	jet.position = Vector2(0.0, 40.0)
	jet.fuel_s = jet.spec.endurance_s * 0.29
	var joined: Array[String] = []
	h.av.aircraft_tanking.connect(func(a: Unit, _t: Unit) -> void: joined.append(a.callsign))
	now = _run(h, 120.0, now)
	assert_eq(joined.size(), 1, "it went looking for give before it went looking for the deck")
	assert_true(not jet.returning, "and did not turn for home")
	var before := jet.fuel_s
	_run(h, 240.0, now)
	assert_true(jet.fuel_s > before, "took fuel on the basket")
	assert_true(tanker.tanker_offload_s < tanker.spec.tanker_offload_s, "which came out of the tanker")
	h.free_all()


func test_a_receiver_with_no_tanker_still_goes_home() -> void:
	var ship := _unit(_carrier_spec(2), "BLUE", Vector2.ZERO)
	var jet := _unit(_receiver_spec(), "BLUE", Vector2.ZERO)
	_embark(ship, jet)
	var h := _harness([ship, jet])
	h.av.launch(ship)
	var now := _run(h, 70.0)
	jet.position = Vector2(0.0, 20.0)
	jet.fuel_s = jet.spec.endurance_s * 0.29
	_run(h, 120.0, now)
	assert_true(jet.returning, "no basket in the sky means the deck is the only option")
	h.free_all()


# --- Off-map basing -----------------------------------------------------------------------

func test_an_aircraft_with_no_deck_flies_off_the_chart_rather_than_running_dry() -> void:
	var raider := _unit(_receiver_spec(), "RED", Vector2(0.0, 60.0))
	raider.flight_state = Unit.FlightState.AIRBORNE
	raider.fuel_s = raider.spec.endurance_s * 0.29
	raider.ordered_speed_kn = raider.spec.cruise_speed_kn
	var h := _harness([raider])
	h.av.map_center = Vector2.ZERO
	h.av.map_extent_nm = 160.0
	var gone: Array[String] = []
	h.av.aircraft_departed.connect(func(a: Unit) -> void: gone.append(a.callsign))
	var now := _run(h, 120.0)
	assert_true(raider.returning, "it turned for home even though home is not on the plot")
	assert_true(not raider.waypoints.is_empty(), "and steered for an edge")
	_run(h, 700.0, now)
	assert_eq(gone.size(), 1, "it left the chart")
	assert_true(not raider.alive, "and is off the board")
	h.free_all()
