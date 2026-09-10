class_name AviationManager
extends Node
## Deck cycle, fuel and sonobuoys.
##
## An aircraft exists from scenario load but sits in its hangar until launched, so the player can
## see what is available without those airframes being detectable or shootable. Fuel is the real
## constraint: an airframe is only over the contact for as long as its tanks allow, and it has to
## get home afterwards.

signal aircraft_launched(aircraft: Unit, parent: Unit)
signal aircraft_recovered(aircraft: Unit, parent: Unit)
signal aircraft_lost(aircraft: Unit, reason: String)
signal aircraft_bingo(aircraft: Unit)
signal launch_rejected(parent: Unit, reason: String)
signal sonobuoy_deployed(buoy: Sonobuoy, aircraft: Unit)

const CYCLE_DT := 1.0
const RECOVERY_RANGE_NM := 2.5
const BINGO_FRACTION := 0.28  # head home at this much fuel left
const IDLE_BURN := 0.7  # fraction of cruise burn when barely moving
const DASH_BURN := 0.3  # added quadratically with speed

var unit_manager: UnitManager
var sonobuoys: Array[Sonobuoy] = []

var _accum := 0.0
var _next_buoy_id := 1


func clear() -> void:
	sonobuoys.clear()
	_next_buoy_id = 1
	_accum = 0.0


## Sends one airframe off the deck. Returns the aircraft, or null with a reason emitted.
func launch(parent: Unit, which := "") -> Unit:
	if not parent.alive:
		launch_rejected.emit(parent, "SHIP LOST")
		return null
	var available := parent.stowed_aircraft()
	if available.is_empty():
		launch_rejected.emit(parent, "NO AIRCRAFT AVAILABLE")
		return null
	var chosen: Unit = available[0]
	if which != "":
		for a in available:
			if a.callsign == which or a.spec.id == which:
				chosen = a
	chosen.flight_state = Unit.FlightState.LAUNCHING
	chosen.state_timer_s = chosen.spec.launch_time_s
	chosen.position = parent.position
	chosen.heading_deg = parent.heading_deg
	chosen.returning = false
	return chosen


## Orders an airframe home under its own steam.
func request_return(a: Unit) -> void:
	if a.airborne():
		a.returning = true


func deploy_sonobuoy(a: Unit, now: float) -> Sonobuoy:
	if not a.airborne() or a.sonobuoys <= 0 or a.spec.sonobuoy_sensitivity_nm <= 0.0:
		return null
	if Terrain.is_land(a.position):
		return null  # a hydrophone in a field hears nothing, and the buoy is not spent
	a.sonobuoys -= 1
	var b := Sonobuoy.new()
	b.id = _next_buoy_id
	_next_buoy_id += 1
	b.faction = a.faction
	b.position = a.position
	b.sensitivity_nm = a.spec.sonobuoy_sensitivity_nm
	b.expires_at = now + a.spec.sonobuoy_life_s
	sonobuoys.append(b)
	sonobuoy_deployed.emit(b, a)
	return b


func tick(dt: float, now: float) -> void:
	_accum += dt
	while _accum >= CYCLE_DT - 1e-6:
		_accum -= CYCLE_DT
		_run_cycle(CYCLE_DT, now)


func _run_cycle(dt: float, now: float) -> void:
	for i in range(sonobuoys.size() - 1, -1, -1):
		if not sonobuoys[i].alive_at(now):
			sonobuoys.remove_at(i)
	for u in unit_manager.units:
		if not u.is_aircraft() or not u.alive:
			continue
		match u.flight_state:
			Unit.FlightState.LAUNCHING:
				_step_launch(u, dt)
			Unit.FlightState.AIRBORNE:
				_step_airborne(u, dt)
			Unit.FlightState.RECOVERING:
				_step_recovery(u, dt)


func _step_launch(a: Unit, dt: float) -> void:
	a.state_timer_s -= dt
	if a.state_timer_s > 0.0:
		return
	a.flight_state = Unit.FlightState.AIRBORNE
	a.fuel_s = a.spec.endurance_s
	a.ordered_altitude_m = a.spec.cruise_altitude_m
	a.ordered_speed_kn = a.spec.cruise_speed_kn
	a.sonobuoys = a.spec.sonobuoy_count
	aircraft_launched.emit(a, a.home)


func _step_airborne(a: Unit, dt: float) -> void:
	var cruise := maxf(a.spec.cruise_speed_kn, 1.0)
	var rate := IDLE_BURN + DASH_BURN * pow(a.speed_kn / cruise, 2.0)
	var was_above_bingo := a.fuel_fraction() > BINGO_FRACTION
	a.fuel_s -= dt * rate
	if a.fuel_s <= 0.0:
		a.fuel_s = 0.0
		a.alive = false
		a.flight_state = Unit.FlightState.STOWED
		aircraft_lost.emit(a, "OUT OF FUEL")
		return
	if was_above_bingo and a.fuel_fraction() <= BINGO_FRACTION and not a.returning:
		a.returning = true
		aircraft_bingo.emit(a)
	if not a.returning:
		return
	# Steer for home and land when close enough. Home moves, so this is refreshed every cycle.
	var base := a.home
	if base == null or not base.alive:
		base = _nearest_deck(a)
	if base == null:
		return  # nowhere at all to go; it will fly until the tanks run dry
	a.home = base
	a.waypoints.clear()
	a.waypoints.append(base.position)
	a.ordered_speed_kn = a.spec.cruise_speed_kn
	if a.position.distance_to(base.position) <= RECOVERY_RANGE_NM:
		a.flight_state = Unit.FlightState.RECOVERING
		a.state_timer_s = a.spec.recovery_time_s
		a.waypoints.clear()
		a.ordered_speed_kn = 0.0


func _step_recovery(a: Unit, dt: float) -> void:
	a.state_timer_s -= dt
	if a.state_timer_s > 0.0:
		return
	a.flight_state = Unit.FlightState.STOWED
	a.returning = false
	a.fuel_s = a.spec.endurance_s
	a.altitude_m = 0.0
	a.speed_kn = 0.0
	a.ordered_speed_kn = 0.0
	aircraft_recovered.emit(a, a.home)


## Any friendly deck or field that can take this aircraft. Losing the ship an aircraft came from
## should cost you the sortie, not automatically the airframe.
func _nearest_deck(a: Unit) -> Unit:
	var best: Unit = null
	var best_d := INF
	for u in unit_manager.units:
		if not u.alive or u.faction != a.faction or u.spec.aircraft_capacity <= 0 or u == a:
			continue
		var d := a.position.distance_to(u.position)
		if d < best_d:
			best_d = d
			best = u
	return best

