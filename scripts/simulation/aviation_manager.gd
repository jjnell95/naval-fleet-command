class_name AviationManager
extends Node
## Deck cycle, fuel, tanking and sonobuoys.
##
## An aircraft exists from scenario load but sits in its hangar until launched, so the player can
## see what is available without those airframes being detectable or shootable. Fuel is the real
## constraint: an airframe is only over the contact for as long as its tanks allow, and it has to
## get home afterwards.
##
## The deck is a cycle, not a door. A carrier works several catapults at once and recovers down a
## single angled deck, and everything that lands has to be fuelled, rearmed and respotted before
## it counts as a sortie again. That is what makes a big deck worth having and what stops one
## frigate hangar from flying an unlimited war. A tanker extends the whole thing: an aircraft that
## can reach a basket does not have to go home when it hits bingo.

signal aircraft_launched(aircraft: Unit, parent: Unit)
signal aircraft_recovered(aircraft: Unit, parent: Unit)
signal aircraft_lost(aircraft: Unit, reason: String)
signal aircraft_bingo(aircraft: Unit)
signal launch_rejected(parent: Unit, reason: String)
signal sonobuoy_deployed(buoy: Sonobuoy, aircraft: Unit)
signal aircraft_ready(aircraft: Unit, parent: Unit)
signal aircraft_tanking(aircraft: Unit, tanker: Unit)
signal aircraft_departed(aircraft: Unit)

const CYCLE_DT := 1.0
const RECOVERY_RANGE_NM := 2.5
const BINGO_FRACTION := 0.28  # head home at this much fuel left
const IDLE_BURN := 0.7  # fraction of cruise burn when barely moving
const DASH_BURN := 0.3  # added quadratically with speed
## Tanking. A receiver at bingo looks for a basket before it looks for the deck, and takes it if
## the tanker is closer than the trip home would cost. GAMEPLAY_ESTIMATE throughout: one transfer
## rate stands in for the whole business of joining, plugging and taking a load.
const REFUEL_RANGE_NM := 3.0  # close enough to be on the basket
const REFUEL_RATE := 8.0  # receiver endurance-seconds gained per simulated second
const TANKER_SEARCH_NM := 180.0  # how far a thirsty aircraft will go looking for give
const TANKER_TOPPED_OFF := 0.92  # unplug at this fraction rather than chasing the last drop
const TANKER_RESERVE := 0.30  # a tanker keeps this much of its own fuel to get home on
## Off-map basing. A 200-mile chart does not contain every airfield an aircraft over it flew from,
## and a scenario that has to place every base on the plot cannot show a raid arriving from an air
## complex 400 miles away. An airframe with no deck of its own heads for the edge it can reach and
## is taken off the board when it crosses: it went home, and it is not coming back this scenario.
const OFF_MAP_MARGIN_NM := 12.0

var unit_manager: UnitManager
var sonobuoys: Array[Sonobuoy] = []
## The chart, for deciding when an aircraft with no deck has flown off it. Zero extent means no
## chart was set and nothing is ever considered off-map.
var map_center := Vector2.ZERO
var map_extent_nm := 0.0

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
	if not parent.spec.can_operate(chosen.spec):
		launch_rejected.emit(parent, "INCOMPATIBLE FLIGHT DECK")
		return null
	# Catapults and the groove are separate constraints. A deck with four cats gets four airframes
	# off at once; the same deck still cannot launch while it is taking someone aboard, because on
	# a real ship that is the same run of deck.
	if parent.launch_spots_busy() >= parent.spec.launch_capacity():
		launch_rejected.emit(parent, "CATAPULTS COMMITTED")
		return null
	if parent.recovery_spots_busy() > 0 and parent.spec.flight_facility() != "airfield":
		launch_rejected.emit(parent, "DECK RECOVERING")
		return null
	chosen.flight_state = Unit.FlightState.LAUNCHING
	chosen.state_timer_s = chosen.spec.launch_time_s
	chosen.position = parent.position
	chosen.heading_deg = parent.heading_deg
	chosen.returning = false
	return chosen


## Sends a section off one deck. A strike is not flown by single aircraft trickling off a
## catapult, and a deck that can work several spots should be allowed to use them. Returns the
## airframes actually launched, which may be fewer than asked for.
func launch_flight(parent: Unit, count: int, platform_id := "") -> Array[Unit]:
	var out: Array[Unit] = []
	for i in maxi(count, 1):
		var pick := ""
		if platform_id != "":
			var match_found := false
			for a in parent.stowed_aircraft():
				if a.spec.id == platform_id:
					pick = a.callsign
					match_found = true
					break
			if not match_found:
				break
		var a2 := launch(parent, pick)
		if a2 == null:
			break
		out.append(a2)
	return out


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
			Unit.FlightState.TURNAROUND:
				_step_turnaround(u, dt)
	_run_tanking(dt)


func _step_launch(a: Unit, dt: float) -> void:
	a.state_timer_s -= dt
	if a.state_timer_s > 0.0:
		return
	a.flight_state = Unit.FlightState.AIRBORNE
	a.fuel_s = a.spec.endurance_s
	a.ordered_altitude_m = a.spec.cruise_altitude_m
	a.ordered_speed_kn = a.spec.cruise_speed_kn
	a.sonobuoys = a.spec.sonobuoy_count
	a.tanker_offload_s = a.spec.tanker_offload_s
	a.tanking_on = null
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
		# Look for give before looking for the deck. A basket within reach is what turns a
		# two-hour sortie into a day on station, and it is the whole reason a tanker is up.
		var tanker := _find_tanker(a)
		if tanker != null:
			a.tanking_on = tanker
			aircraft_tanking.emit(a, tanker)
		else:
			a.returning = true
			aircraft_bingo.emit(a)
	if a.tanking_on != null and _step_tanking_receiver(a):
		return
	if not a.returning:
		return
	# Steer for home and land when close enough. Home moves, so this is refreshed every cycle.
	var base := a.home
	if base == null or not base.alive or not base.spec.can_operate(a.spec):
		base = _nearest_deck(a)
	if base == null:
		_step_off_map_return(a)
		return
	if a.home != base:
		if a.home != null:
			a.home.embarked.erase(a)
		a.home = base
		if not base.embarked.has(a):
			base.embarked.append(a)
	a.waypoints.clear()
	a.waypoints.append(base.position)
	a.ordered_speed_kn = a.spec.cruise_speed_kn
	if a.position.distance_to(base.position) <= RECOVERY_RANGE_NM:
		# Wait for the groove. Aircraft stack overhead rather than landing on top of each other,
		# and a deck in the middle of a launch is not taking anyone aboard.
		if base.recovery_spots_busy() >= base.spec.recovery_capacity():
			return
		if base.launch_spots_busy() > 0 and base.spec.flight_facility() != "airfield":
			return
		a.flight_state = Unit.FlightState.RECOVERING
		a.state_timer_s = a.spec.recovery_time_s
		a.waypoints.clear()
		a.ordered_speed_kn = 0.0


func _step_recovery(a: Unit, dt: float) -> void:
	a.state_timer_s -= dt
	if a.state_timer_s > 0.0:
		return
	a.flight_state = Unit.FlightState.TURNAROUND
	a.state_timer_s = a.home.spec.turnaround_time_s() if a.home != null else a.spec.turnaround_time_s()
	a.returning = false
	a.tanking_on = null
	a.altitude_m = 0.0
	a.speed_kn = 0.0
	a.ordered_speed_kn = 0.0
	a.waypoints.clear()
	aircraft_recovered.emit(a, a.home)


## Fuel, ordnance and a spot on the deck. Until this finishes the airframe is aboard but is not a
## sortie anyone can fly, which is the constraint that makes deck size mean something.
func _step_turnaround(a: Unit, dt: float) -> void:
	a.state_timer_s -= dt
	if a.state_timer_s > 0.0:
		return
	a.flight_state = Unit.FlightState.STOWED
	a.state_timer_s = 0.0
	a.fuel_s = a.spec.endurance_s
	a.sonobuoys = a.spec.sonobuoy_count
	a.tanker_offload_s = a.spec.tanker_offload_s
	# Rearmed from the ship's magazines. Deep strike stocks are not tracked separately; what a
	# deck can keep flying is bounded by turnaround time, not by a ship-side ordnance count.
	for wid in a.spec.weapon_loadout:
		a.magazines[wid] = int(a.spec.weapon_loadout[wid])
	aircraft_ready.emit(a, a.home)


## Any friendly deck or field that can take this aircraft. Losing the ship an aircraft came from
## should cost you the sortie, not automatically the airframe.
func _nearest_deck(a: Unit) -> Unit:
	var best: Unit = null
	var best_d := INF
	for u in unit_manager.units:
		if not u.alive or u.faction != a.faction or u.spec.aircraft_capacity <= 0 or u == a:
			continue
		if not u.spec.can_operate(a.spec) or (not u.embarked.has(a) and u.embarked.filter(func(other: Unit) -> bool: return other.alive).size() >= u.spec.aircraft_capacity):
			continue
		var d := a.position.distance_to(u.position)
		if d < best_d:
			best_d = d
			best = u
	return best


# --- Air-to-air refuelling -------------------------------------------------------------------

## A tanker with give left, close enough to be worth the detour. The trip has to cost less than
## the fuel the receiver still has, or it trades a landing for a swim.
func _find_tanker(a: Unit) -> Unit:
	if not a.spec.can_refuel or a.is_tanker():
		return null
	var best: Unit = null
	var best_d := INF
	for u in unit_manager.units:
		if u == a or not u.alive or not u.airborne() or u.faction != a.faction or not u.is_tanker():
			continue
		var d := a.position.distance_to(u.position)
		if d > TANKER_SEARCH_NM or d >= best_d:
			continue
		# Reaching the basket has to be inside what is left in the tanks, with something spare.
		var reach_nm := Geo.knots_to_nm_per_s(a.spec.cruise_speed_kn) * a.fuel_s
		if d > reach_nm * 0.7:
			continue
		best_d = d
		best = u
	return best


## Steers a thirsty receiver onto its tanker. Returns true while the join is the aircraft's job,
## so the normal return-to-deck logic stays out of the way.
func _step_tanking_receiver(a: Unit) -> bool:
	var t := a.tanking_on
	if a.fuel_fraction() >= TANKER_TOPPED_OFF:
		a.tanking_on = null  # full: unplug and go back to work
		a.returning = false
		a.waypoints.clear()
		return false
	if t == null or not t.alive or not t.airborne() or not t.is_tanker():
		# The tanker is gone — shot down, or it gave away everything it had. The receiver is
		# below bingo and has just spent fuel joining on it, so it goes home now rather than
		# carrying on as though nothing happened.
		a.tanking_on = null
		a.returning = true
		a.waypoints.clear()
		return false
	a.waypoints.clear()
	a.waypoints.append(t.position)
	a.ordered_altitude_m = t.altitude_m
	a.ordered_speed_kn = a.spec.cruise_speed_kn
	return true


## Moves fuel from tankers to whoever is plugged in. A tanker keeps a reserve for its own trip
## home; an aircraft cannot drain the last of someone else's tanks and strand them both.
func _run_tanking(dt: float) -> void:
	for a in unit_manager.units:
		if not a.alive or not a.airborne() or a.tanking_on == null:
			continue
		var t: Unit = a.tanking_on
		if not t.alive or not t.airborne() or not t.is_tanker():
			a.tanking_on = null
			a.returning = true
			continue
		if a.position.distance_to(t.position) > REFUEL_RANGE_NM:
			continue
		var spare := maxf(t.fuel_s - t.spec.endurance_s * TANKER_RESERVE, 0.0)
		var give := minf(REFUEL_RATE * dt, minf(t.tanker_offload_s, spare))
		var room := maxf(a.spec.endurance_s - a.fuel_s, 0.0)
		give = minf(give, room)
		if give <= 0.0:
			a.tanking_on = null
			a.returning = true
			continue
		a.fuel_s += give
		t.tanker_offload_s -= give
		t.fuel_s -= give


# --- Off-map basing --------------------------------------------------------------------------

## Flies an aircraft with nowhere on the chart to land towards the nearest edge, and takes it off
## the board once it is past. A Backfire that came from a field four hundred miles inland leaves
## the same way; it is not lost, it is simply no longer this scenario's problem.
func _step_off_map_return(a: Unit) -> void:
	if map_extent_nm <= 0.0:
		return  # no chart: it will fly until the tanks run dry, as before
	var half := map_extent_nm * 0.5
	var local := a.position - map_center
	if absf(local.x) > half + OFF_MAP_MARGIN_NM or absf(local.y) > half + OFF_MAP_MARGIN_NM:
		a.alive = false
		a.flight_state = Unit.FlightState.STOWED
		aircraft_departed.emit(a)
		return
	# Head for whichever edge is closest; that is the way back to wherever it came from.
	var exit_point := a.position
	if half - absf(local.x) <= half - absf(local.y):
		exit_point.x = map_center.x + (half + OFF_MAP_MARGIN_NM * 2.0) * signf(local.x if local.x != 0.0 else 1.0)
	else:
		exit_point.y = map_center.y + (half + OFF_MAP_MARGIN_NM * 2.0) * signf(local.y if local.y != 0.0 else 1.0)
	a.waypoints.clear()
	a.waypoints.append(exit_point)
	a.ordered_speed_kn = a.spec.cruise_speed_kn
