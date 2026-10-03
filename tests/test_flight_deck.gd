extends TestCase
## Flight operations that behave like flight operations: a jet never stops in the air, an aircraft
## launched without orders holds where it can be seen, aircraft back at a busy or burning deck hold
## in a marshal stack astern instead of circling the ship at transit speed, and a helicopter is
## not turned round like a strike fighter.


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


func _jet_spec() -> PlatformSpec:
	var p := _helo_spec(9000.0)
	p.short_name = "Jet Test"
	p.can_hover = false
	p.max_speed_kn = 1000.0
	p.cruise_speed_kn = 480.0
	p.turn_rate_deg_s = 7.0
	p.accel_kn_s = 20.0
	p.cruise_altitude_m = 9000.0
	p.max_altitude_m = 15000.0
	p.altitude_rate_m_s = 35.0
	p.launch_time_s = 45.0
	p.recovery_time_s = 60.0
	p.launch_requirement = "helicopter"  # lets the test deck operate it
	return p


func _airborne(spec: PlatformSpec, pos: Vector2) -> Unit:
	var a := _unit(spec, "BLUE", pos, spec.flight_speed("transit"))
	a.flight_state = Unit.FlightState.AIRBORNE
	a.altitude_m = spec.cruise_altitude_m
	a.fuel_s = spec.endurance_s
	return a


func test_a_jet_arriving_with_nowhere_to_go_holds_instead_of_stopping() -> void:
	var jet := _airborne(_jet_spec(), Vector2.ZERO)
	jet.waypoints.assign([Vector2(0, 0.05)])
	Movement.step(jet, DT)
	assert_true(jet.ordered_speed_kn >= jet.spec.flight_speed("patrol") - 0.01, "still flying")
	assert_eq(jet.waypoints.size(), 4, "a racetrack")
	assert_true(jet.waypoints.back().distance_to(Vector2(0, 0.05)) < 1e-4, "through the point it was sent to")
	for i in 400:
		Movement.step(jet, DT)
	assert_true(jet.speed_kn > 100.0, "it never slows to a stop")
	assert_true(jet.position.distance_to(Vector2(0, 0.05)) < Movement.HOLD_LEG_NM + Movement.HOLD_WIDTH_NM + 1.0, "and stays at the point")


func test_a_stop_order_puts_a_jet_into_a_hold_where_it_is() -> void:
	var jet := _airborne(_jet_spec(), Vector2(3, 4))
	jet.apply_order(Order.stop())
	Movement.step(jet, DT)
	assert_eq(jet.waypoints.size(), 4)
	assert_true(jet.ordered_speed_kn > 0.0)


func test_a_helicopter_still_stops_at_its_point() -> void:
	var helo := _airborne(_helo_spec(), Vector2.ZERO)
	helo.waypoints.assign([Vector2(0, 0.05)])
	Movement.step(helo, DT)
	assert_true(helo.waypoints.is_empty())
	assert_eq(helo.ordered_speed_kn, 0.0, "a helicopter can hover")


func test_an_aircraft_launched_without_orders_holds_ahead_of_its_ship() -> void:
	var ship := _unit(_ship_spec(), "BLUE", Vector2.ZERO)
	ship.heading_deg = 90.0
	var jet := _unit(_jet_spec(), "BLUE", Vector2.ZERO)
	_embark(ship, jet)
	var h := _harness([ship, jet])
	assert_true(h.av.launch(ship) == jet)
	_run(h, jet.spec.launch_time_s + 2.0)
	assert_true(jet.airborne())
	var departure := ship.position + Geo.heading_to_vector(90.0) * AviationManager.DEPARTURE_HOLD_NM
	assert_true(not jet.waypoints.is_empty(), "it has somewhere to be")
	assert_true(jet.waypoints.back().distance_to(departure) < 1.0, "a hold ahead of the ship")
	_run(h, 1800.0, jet.spec.launch_time_s + 2.0)
	assert_true(jet.position.distance_to(departure) < Movement.HOLD_LEG_NM + Movement.HOLD_WIDTH_NM + 2.0, "still there half an hour later, not flown off the chart")
	h.free_all()


func test_an_aircraft_back_at_a_busy_deck_holds_in_the_marshal_stack_astern() -> void:
	var ship := _unit(_ship_spec(2), "BLUE", Vector2.ZERO, 15.0)
	var first := _airborne(_helo_spec(), Vector2(0, -1.5))
	var second := _airborne(_jet_spec(), Vector2(0, -20))
	_embark(ship, first)
	_embark(ship, second)
	var h := _harness([ship, first, second])
	assert_true(h.av.request_return(first))
	assert_true(h.av.request_return(second))
	_run(h, 3.0)
	assert_eq(first.flight_state, Unit.FlightState.RECOVERING, "the first is on the deck's one recovery spot")
	_run(h, 120.0, 3.0)
	assert_true(AviationManager.in_marshal(second), "the second is waiting in marshal")
	var marshal := AviationManager.marshal_point(ship)
	assert_true(second.position.distance_to(marshal) < Movement.HOLD_LEG_NM + Movement.HOLD_WIDTH_NM + 2.0, "astern of the ship, not over it")
	assert_true(second.ordered_speed_kn <= second.spec.flight_speed("patrol") + 0.01, "at economical speed")
	assert_true(second.position.distance_to(ship.position) > AviationManager.RECOVERY_RANGE_NM, "clear of the deck")
	var recovered := false
	var now := 123.0
	for i in 40:
		now = _run(h, 30.0, now)
		if second.flight_state in [Unit.FlightState.RECOVERING, Unit.FlightState.TURNAROUND]:
			recovered = true
			break
	assert_true(recovered, "called down once the deck is clear")
	h.free_all()


func test_a_burning_deck_takes_nobody_aboard() -> void:
	var ship := _unit(_ship_spec(), "BLUE", Vector2.ZERO)
	ship.fire = 0.5
	var helo := _airborne(_helo_spec(), Vector2(0, -1.0))
	_embark(ship, helo)
	var h := _harness([ship, helo])
	assert_true(h.av.request_return(helo))
	_run(h, 60.0)
	assert_eq(helo.flight_state, Unit.FlightState.AIRBORNE, "flight operations suspended")
	assert_true(AviationManager.in_marshal(helo))
	ship.fire = 0.0
	_run(h, 120.0, 60.0)
	assert_true(helo.flight_state in [Unit.FlightState.RECOVERING, Unit.FlightState.TURNAROUND], "taken aboard once the fire is out")
	h.free_all()


func test_a_helicopter_aboard_a_carrier_is_not_turned_round_like_a_strike_fighter() -> void:
	var carrier := _unit(_ship_spec(40), "BLUE", Vector2.ZERO)
	carrier.spec.turnaround_s = 2700.0
	var helo := _unit(_helo_spec(), "BLUE", Vector2.ZERO)
	var jet := _unit(_jet_spec(), "BLUE", Vector2.ZERO)
	assert_eq(AviationManager.turnaround_for(helo, carrier), AviationManager.HELICOPTER_TURNAROUND_S)
	assert_eq(AviationManager.turnaround_for(jet, carrier), 2700.0)


func test_a_hold_laid_for_want_of_orders_is_not_a_route() -> void:
	# The AI and the stalled-task checks ask whether a unit has a route; a jet holding because it
	# had nowhere to go must still read as idle, or it would hold for ever.
	var jet := _airborne(_jet_spec(), Vector2.ZERO)
	jet.waypoints.assign([Vector2(0, 0.05)])
	Movement.step(jet, DT)
	assert_true(jet.holding())
	assert_true(not jet.has_route(), "a hold is not a route")
	jet.apply_order(Order.move(Vector2(20, 20)))
	assert_true(not jet.holding(), "a new destination ends the hold")
	assert_true(jet.has_route())
