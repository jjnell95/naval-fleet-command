class_name AirMissionManager
extends Node
## Air tasking: aircraft launched to a mission rather than an airframe launched to nowhere.
##
## The commander asks a deck for a combat air patrol over a point, a reconnaissance sweep of an
## area, an ASW search, or a strike on a held contact, with an aircraft type and a number. The
## mission launches real airframes as the deck can send them (queueing the rest when the catapults
## are busy), gives each a station or a target through ordinary crew orders, and narrates what each
## is doing. Everything it does goes through UnitManager.issue_order, so ROE, track quality, fuel,
## magazines, deck spots and recovery reservations are checked exactly as for the commander's own
## orders. It reads only the faction's own track picture. It never creates an aircraft or a round.
##
## Fuel outranks the mission: AviationManager sends an airframe to the tanker or the deck at bingo
## as it always has. With relief on, the mission launches a ready reserve airframe early enough to
## reach the station as the one there turns for home.

signal mission_report(mission: AirMission, message: String, good: bool)
signal mission_ended(mission: AirMission, reason: String)

const CYCLE_DT := 1.0
## A CAP commits on air contacts this far beyond its station. GAMEPLAY_ESTIMATE.
const COMMIT_MARGIN_NM := 25.0
## A reconnaissance or ASW aircraft looks at contacts this far beyond its search area.
const SEARCH_MARGIN_NM := 5.0
## Interceptors sent at one hostile contact; unknown contacts get one look each.
const INTERCEPTORS_PER_TRACK := 2
## An airframe within this of its station centre plus radius counts as on station.
const STATION_ARRIVAL_MARGIN_NM := 3.0
const MIN_RADIUS_NM := 3.0
const MAX_RADIUS_NM := 80.0
## ASW search: sonobuoys laid this far apart, no more often than this. GAMEPLAY_ESTIMATE.
const BUOY_SPACING_NM := 5.0
const BUOY_INTERVAL_S := 90.0
const ASW_ALTITUDE_M := 150.0
## A helicopter with a dipping set searches by stopping low in the area to lower it, listening for
## a while, then moving on along the search circuit. GAMEPLAY_ESTIMATE timings.
const DIP_S := 180.0
const DIP_INTERVAL_S := 240.0
## A held radar altitude above this marks an unclassified contact as probably airborne.
const AIRBORNE_ALTITUDE_M := 30.0

var unit_manager: UnitManager
var aviation_manager: AviationManager
var track_manager: TrackManager
var missions: Array[AirMission] = []
var now_s := 0.0
var _next_id := 1
var _accum := 0.0


func clear() -> void:
	missions.clear()
	_next_id = 1
	_accum = 0.0


func active_missions(faction: String) -> Array[AirMission]:
	var out: Array[AirMission] = []
	for m in missions:
		if m.active and m.faction == faction:
			out.append(m)
	return out


func mission_by_id(mission_id: int) -> AirMission:
	for m in missions:
		if m.id == mission_id:
			return m
	return null


## The mission an airframe is flying, or null.
func mission_for(a: Unit) -> AirMission:
	for m in missions:
		if m.active and m.aircraft.has(a):
			return m
	return null


# --- What a type can fly -----------------------------------------------------------------

## Whether an aircraft type is equipped for a kind of mission at all, magazines aside.
static func type_suits(spec: PlatformSpec, kind: int) -> bool:
	if spec == null or spec.domain != "air":
		return false
	match kind:
		AirMission.Kind.CAP:
			return _loadout_engages(spec, "air")
		AirMission.Kind.RECON:
			return not spec.sensor_ids.is_empty()
		AirMission.Kind.ASW:
			if spec.sonobuoy_count > 0 and spec.sonobuoy_sensitivity_nm > 0.0:
				return true
			for sid in spec.sensor_ids:
				var s := DataDB.sensor(sid)
				if s != null and s.kind == "sonar":
					return true
			return _loadout_engages(spec, "subsurface")
		AirMission.Kind.STRIKE:
			return _loadout_engages(spec, "surface") or _loadout_engages(spec, "land")
	return false


static func _loadout_engages(spec: PlatformSpec, domain: String) -> bool:
	for wid: String in spec.weapon_loadout:
		var w := DataDB.weapon(wid)
		if w != null and w.target_types.has(domain) and int(spec.weapon_loadout[wid]) > 0:
			return true
	return false


## This airframe, as it sits on deck now, can do its part: rounds for a CAP or strike, buoys or a
## weapon for ASW. A deck whose stores have run dry does not send empty fighters to a CAP.
static func airframe_fit(a: Unit, kind: int, target: Track = null) -> bool:
	match kind:
		AirMission.Kind.CAP:
			return _rounds_for(a, "air") > 0
		AirMission.Kind.ASW:
			return a.sonobuoys > 0 or a.has_sonar() or _rounds_for(a, "subsurface") > 0
		AirMission.Kind.STRIKE:
			if target == null:
				return _rounds_for(a, "surface") > 0
			for spec: WeaponSpec in a.weapons:
				if a.magazine_count(spec.id) > 0 and Combat.suits_track(spec, target):
					return true
			return false
	return true


## Fit now, or still on the deck's cycle with the deck's stores able to make up its fit when the
## turnaround finishes. A ready airframe is armed as it stands: it launches with what it carries.
static func _rearmable(a: Unit, kind: int, target: Track = null) -> bool:
	if airframe_fit(a, kind, target):
		return true
	if a.flight_state == Unit.FlightState.STOWED or a.home == null:
		return false
	if kind == AirMission.Kind.ASW and a.spec.sonobuoy_count > 0 and a.home.aviation_buoys > 0:
		return true
	for wid: String in a.sortie_loadout:
		if int(a.home.aviation_stores.get(wid, 0)) <= 0:
			continue
		var w := DataDB.weapon(wid)
		if w == null:
			continue
		match kind:
			AirMission.Kind.CAP:
				if w.target_types.has("air"):
					return true
			AirMission.Kind.ASW:
				if w.target_types.has("subsurface"):
					return true
			AirMission.Kind.STRIKE:
				if (target == null and w.target_types.has("surface")) or (target != null and Combat.suits_track(w, target)):
					return true
	return false


static func _rounds_for(a: Unit, domain: String) -> int:
	var n := 0
	for spec: WeaponSpec in a.weapons:
		if spec.target_types.has(domain):
			n += a.magazine_count(spec.id)
	return n


## Airframes of the type that belong to this deck and are still alive, wherever they are.
static func airframes_of(base: Unit, platform_id: String) -> Array[Unit]:
	var out: Array[Unit] = []
	if base == null:
		return out
	for a in base.embarked:
		if a.alive and a.spec.id == platform_id:
			out.append(a)
	return out


## Seconds an airframe of this type could spend on a station `distance_nm` from its deck, after
## the transit out and the fuel the trip home will need. Negative means it cannot get there.
static func station_time_s(spec: PlatformSpec, distance_nm: float) -> float:
	var cruise := Geo.knots_to_nm_per_s(maxf(spec.cruise_speed_kn, 1.0))
	var transit := distance_nm / cruise
	var home_reserve := maxf(spec.endurance_s * AviationManager.BINGO_FRACTION, transit + spec.recovery_time_s + spec.endurance_s * AviationManager.LANDING_RESERVE_FRACTION)
	return spec.endurance_s - transit - home_reserve


## Why a deck cannot fly this mission, or "" when it can (perhaps only in part; see request()).
func mission_rejection(base: Unit, kind: int, platform_id: String, station: Vector2, target: Track = null) -> String:
	if base == null or not base.alive:
		return "Base lost"
	if base.spec.aircraft_capacity <= 0:
		return "No flight deck"
	if base.fire >= 0.35 or base.component("weapons") <= 0.15:
		return "Flight operations suspended by damage"
	var spec := DataDB.platform(platform_id)
	if spec == null or airframes_of(base, platform_id).is_empty():
		return "No aircraft of that type aboard"
	if not base.spec.can_operate(spec):
		return "Incompatible flight deck"
	if not type_suits(spec, kind):
		match kind:
			AirMission.Kind.CAP:
				return "%s carries no air-to-air weapons" % spec.short_name
			AirMission.Kind.ASW:
				return "%s has no sonobuoys, sonar or ASW weapons" % spec.short_name
			AirMission.Kind.STRIKE:
				return "%s carries no strike weapons" % spec.short_name
			_:
				return "%s has no sensors for reconnaissance" % spec.short_name
	if kind == AirMission.Kind.STRIKE:
		var why := _strike_target_rejection(base, target)
		if why != "":
			return why
		station = target.position
	elif not station.is_finite():
		return "Choose a station on the chart"
	var reach_nm := base.position.distance_to(station)
	if kind == AirMission.Kind.STRIKE:
		reach_nm = maxf(reach_nm - _best_reach(spec, target), 0.0)
	if station_time_s(spec, reach_nm) <= 0.0:
		return "Beyond the %s's radius (%.0f nm)" % [spec.short_name, reach_nm]
	return ""


static func _best_reach(spec: PlatformSpec, target: Track) -> float:
	var best := 0.0
	for wid: String in spec.weapon_loadout:
		var w := DataDB.weapon(wid)
		if w != null and (target == null or Combat.suits_track(w, target)):
			best = maxf(best, w.max_range_nm * 0.8)
	return best


## A strike is ordered on the faction's held plot and only on a contact the commander may attack:
## not neutral or friendly, identified when weapons are tight, never under weapons hold.
func _strike_target_rejection(base: Unit, target: Track) -> String:
	if target == null:
		return "Choose a held contact to strike"
	if target.owner_faction != "" and target.owner_faction != base.faction:
		return "Contact is not held by this force"
	if target.status == Track.Status.LOST:
		return "Contact lost"
	if target.damage_estimate >= 100.0:
		return "Contact already destroyed"
	if target.identity in ["NEUTRAL", "FRIENDLY"]:
		return "Protected identity"
	if target.is_bearing_only() or not target.position.is_finite():
		return "Contact range unresolved"
	if target.domain == "":
		return "Identify contact first"
	if not target.domain in ["surface", "land"]:
		return "Strike missions attack ships and installations"
	if base.roe == Unit.Roe.HOLD:
		return "Weapons hold"
	if base.roe == Unit.Roe.TIGHT and target.identity != "HOSTILE":
		return "Identify contact first (weapons tight)"
	return ""


# --- Requests and cancellation -----------------------------------------------------------

## Airframes of the type on this deck that a new mission could have: ready, in turnaround or in
## reserve, not already flying for another mission and not owed to another mission's queued
## launches, and able to carry what this kind of mission needs.
func available_for(base: Unit, platform_id: String, kind: int = -1, target: Track = null) -> int:
	var n := 0
	for a in airframes_of(base, platform_id):
		if a.flight_state in [Unit.FlightState.STOWED, Unit.FlightState.TURNAROUND, Unit.FlightState.RESERVE] and mission_for(a) == null:
			if kind < 0 or _rearmable(a, kind, target):
				n += 1
	for m in missions:
		if m.active and not m.cancelled and m.base == base and m.platform_id == platform_id:
			n -= m.pending_launches
	return maxi(n, 0)


## Routed here by Simulation for an AIR_MISSION order on a deck. Accepts what the deck can do and
## says what it cannot: fewer airframes than asked for, launches queued behind a busy deck.
func request(base: Unit, order: Order) -> AirMission:
	var kind := order.mission_kind
	var why := mission_rejection(base, kind, order.aircraft_id, order.target_pos, order.track)
	if why != "":
		order.execution_accepted = false
		order.receipt = why
		return null
	var spec := DataDB.platform(order.aircraft_id)
	# Airframes already flying on another task, or owed to another mission's queue, are not this
	# mission's to take; nor is a ready airframe whose stores cannot be made up for this mission.
	var available := available_for(base, order.aircraft_id, kind, order.track)
	var wanted := maxi(order.aircraft_count, 1)
	var accepted := mini(wanted, available)
	if accepted <= 0:
		order.execution_accepted = false
		order.receipt = _unavailable_reason(base, spec, kind, order.track)
		return null
	var m := AirMission.new()
	m.id = _next_id
	_next_id += 1
	m.kind = kind as AirMission.Kind
	m.faction = base.faction
	m.base = base
	m.base_callsign = base.callsign
	m.platform_id = order.aircraft_id
	m.requested = accepted
	m.pending_launches = accepted
	m.relief = order.relief
	m.auto_return = order.automatic
	m.created_at_s = now_s
	if kind == AirMission.Kind.STRIKE:
		m.target = order.track
		m.target_id = order.track.id
		m.station = order.track.position
		m.radius_nm = 0.0
	else:
		m.station = order.target_pos
		m.radius_nm = clampf(order.radius_nm if order.radius_nm > 0.0 else default_radius(kind), MIN_RADIUS_NM, MAX_RADIUS_NM)
	missions.append(m)
	var launched := _launch_owed(m)
	var parts := PackedStringArray()
	parts.append("%s from %s: %d × %s" % [m.label(), base.callsign, accepted, spec.short_name])
	if accepted < wanted:
		parts.append("%d of %d accepted, only %d available" % [accepted, wanted, available])
	if launched > 0:
		parts.append("%d launching" % launched)
	if m.pending_launches > 0:
		parts.append("%d queued: %s" % [m.pending_launches, _queue_reason(m).to_lower()])
	if m.relief:
		parts.append("relief from ready reserve")
	order.receipt = " · ".join(parts)
	order.execution_accepted = true
	m.note = order.receipt
	return m


## Why a deck has no airframe of the type for a new mission.
func _unavailable_reason(base: Unit, spec: PlatformSpec, kind: int, target: Track) -> String:
	var unfit := 0
	var booked := 0
	for a in airframes_of(base, spec.id):
		if a.flight_state in [Unit.FlightState.STOWED, Unit.FlightState.TURNAROUND, Unit.FlightState.RESERVE] and mission_for(a) == null and not _rearmable(a, kind, target):
			unfit += 1
	for m in missions:
		if m.active and not m.cancelled and m.base == base and m.platform_id == spec.id:
			booked += m.pending_launches
	if booked > 0:
		return "Every free %s is already queued for another mission" % spec.short_name
	if unfit > 0:
		return "No %s can be armed for this mission: stores exhausted" % spec.short_name
	return "Every %s is already flying" % spec.short_name


static func default_radius(kind: int) -> float:
	match kind:
		AirMission.Kind.CAP:
			return 12.0
		AirMission.Kind.RECON:
			return 25.0
		AirMission.Kind.ASW:
			return 10.0
	return 0.0


## Ends a mission: queued launches are struck off and its airborne airframes come home. Airframes
## still on the catapults cannot be stopped; the mission waits for them to get airborne and sends
## them straight back, rather than leave them flying with no orders.
func cancel(mission_id: int, base: Unit) -> bool:
	var m := mission_by_id(mission_id)
	if m == null or not m.active or (base != null and m.base != base):
		return false
	if m.cancelled:
		return true
	m.cancelled = true
	m.pending_launches = 0
	m.note = "Cancelled"
	_step_cancelled(m)
	return true


func _step_cancelled(m: AirMission) -> void:
	for a in m.aircraft.duplicate():
		if not a.alive or a.departed or a.flight_state in [Unit.FlightState.TURNAROUND, Unit.FlightState.STOWED, Unit.FlightState.RECOVERING]:
			_drop(m, a, "")
		elif a.flight_state != Unit.FlightState.LAUNCHING and a.airborne():
			if not a.returning:
				_crew(a, Order.return_to_base())
			_drop(m, a, "")
	if m.aircraft.is_empty():
		_end(m, "Cancelled")


func _end(m: AirMission, reason: String) -> void:
	if not m.active:
		return
	m.active = false
	m.pending_launches = 0
	m.ended_reason = reason
	for a in m.aircraft:
		if a.station_mission_id == m.id:
			a.station_mission_id = -1
	m.aircraft.clear()
	m.tasks.clear()
	mission_ended.emit(m, reason)


# --- The mission cycle -------------------------------------------------------------------

func tick(dt: float, now: float) -> void:
	now_s = now
	_accum += dt
	while _accum >= CYCLE_DT - 1e-6:
		_accum -= CYCLE_DT
		for m in missions:
			if m.active:
				_step(m)


func _step(m: AirMission) -> void:
	if m.cancelled:
		_step_cancelled(m)
		return
	if m.base == null or not m.base.alive:
		_end(m, "Base lost")
		return
	for a in m.aircraft.duplicate():
		_track_airframe(m, a)
	if not m.active:
		return
	if m.kind == AirMission.Kind.STRIKE and m.pending_launches > 0:
		var why := _strike_target_rejection(m.base, m.target)
		if why != "":
			_report(m, "%s: %d strike launch%s cancelled — %s" % [m.label(), m.pending_launches, "" if m.pending_launches == 1 else "es", why.to_lower()], false)
			m.pending_launches = 0
	_launch_owed(m)
	if m.aircraft.is_empty() and m.pending_launches <= 0:
		_end(m, "Strike complete" if m.kind == AirMission.Kind.STRIKE else "All aircraft recovered")
		return
	if m.pending_launches > 0 and m.aircraft.is_empty() and _launch_candidates(m).is_empty() and not _any_coming_ready(m):
		_report(m, "%s: no %s left to launch" % [m.label(), DataDB.platform(m.platform_id).short_name], false)
		_end(m, "No aircraft left")


## Launches as many of the owed airframes as the deck will take this second. A deck holding an
## aircraft overhead for recovery lands it first: a queue that kept the catapults busy would leave
## it circling the ship on its last fuel.
func _launch_owed(m: AirMission) -> int:
	var launched := 0
	if _recovery_waiting(m.base):
		return 0
	while m.pending_launches > 0:
		var candidates := _launch_candidates(m)
		if candidates.is_empty():
			break
		var a: Unit = candidates[0]
		if aviation_manager.launch_rejection_reason(m.base, a.callsign) != "":
			break
		if aviation_manager.launch(m.base, a.callsign) == null:
			break
		m.pending_launches -= 1
		m.launched_total += 1
		a.roe = _mission_roe(m)
		m.aircraft.append(a)
		a.auto_return = m.auto_return
		m.tasks[a] = {"state": AirMission.LAUNCHING, "assigned": false, "generation": a.order_generation, "player_generation": a.player_order_generation, "relieved": false, "buoy_at": -INF, "attacked": false}
		launched += 1
	return launched


## The rules an airframe launches under: the deck's, or, if the commander has since tightened the
## rules on an airframe already flying the mission, the tightest of those, so a relief never comes
## up freer than the airframe it relieves.
func _mission_roe(m: AirMission) -> Unit.Roe:
	var roe := m.base.roe
	for other in m.aircraft:
		if other.alive and other.roe < roe:
			roe = other.roe
	return roe


## Ready airframes of the type, fit for this mission, in deck order.
func _launch_candidates(m: AirMission) -> Array[Unit]:
	var out: Array[Unit] = []
	for a in m.base.stowed_aircraft():
		if a.spec.id == m.platform_id and airframe_fit(a, m.kind, m.target):
			out.append(a)
	return out


func _any_coming_ready(m: AirMission) -> bool:
	for a in airframes_of(m.base, m.platform_id):
		if a.flight_state in [Unit.FlightState.TURNAROUND, Unit.FlightState.RESERVE, Unit.FlightState.LAUNCHING]:
			return true
		if a.in_flight() and mission_for(a) == null:
			return true  # flying something else; it may come back to the deck
	return false


## An airframe back over this deck and waiting for it to stop launching.
static func _recovery_waiting(base: Unit) -> bool:
	if base.spec.flight_facility() == "airfield":
		return false  # a field launches and recovers on separate runways
	for a in base.inbound_aircraft:
		if a.alive and a.airborne() and a.returning and a.position.distance_to(base.position) <= AviationManager.RECOVERY_RANGE_NM + 1.0:
			return true
	for a in base.embarked:
		if a.alive and a.airborne() and a.returning and (a.recovery_base == null or a.recovery_base == base) and a.position.distance_to(base.position) <= AviationManager.RECOVERY_RANGE_NM + 1.0:
			return true
	return false


func _queue_reason(m: AirMission) -> String:
	if _recovery_waiting(m.base):
		return "deck recovering"
	if _launch_candidates(m).is_empty():
		return "awaiting ready aircraft"
	var why := aviation_manager.launch_rejection_reason(m.base, m.platform_id)
	return why.capitalize() if why != "" else "next launch cycle"


## What one airframe on the mission is doing, and the next thing the mission tells it.
func _track_airframe(m: AirMission, a: Unit) -> void:
	var task: Dictionary = m.tasks[a]
	if not a.alive or a.departed:
		_drop(m, a, "lost" if not a.departed else "left the area")
		if m.relief and not bool(task["relieved"]) and m.kind != AirMission.Kind.STRIKE:
			m.pending_launches += 1
		return
	if a.flight_state in [Unit.FlightState.TURNAROUND, Unit.FlightState.STOWED]:
		m.completed_sorties += 1
		_drop(m, a, "")
		return
	# A replacement order from the commander releases the airframe; a temporary task does not.
	if a.player_order_generation != int(task["player_generation"]):
		task["player_generation"] = a.player_order_generation
		var still_tasked := a.attack_track != null or a.investigation_track != null
		var kept_station := a.station_mission_id == m.id
		if not still_tasked and not kept_station and not a.returning:
			_release(m, a)
			return
	match a.flight_state:
		Unit.FlightState.LAUNCHING:
			task["state"] = AirMission.LAUNCHING
			return
		Unit.FlightState.RECOVERING:
			task["state"] = AirMission.RECOVERING
			return
	if a.returning:
		if task["state"] != AirMission.RETURNING:
			task["state"] = AirMission.RETURNING
			_call_relief(m, a, task, "%s heading home" % a.callsign)
		return
	if a.tanking_on != null:
		task["state"] = AirMission.REFUELLING
		if bool(task["relieved"]):
			task["tanked_after_relief"] = true
		return
	if bool(task.get("tanked_after_relief", false)):
		task["tanked_after_relief"] = false
		if _hand_over_after_tanking(m, a, task):
			return
	if m.kind != AirMission.Kind.STRIKE:
		_relief_due(m, a, task)
	if a.attack_track != null:
		task["state"] = AirMission.ENGAGING
		task["attacked"] = true
		return
	if a.investigation_track != null:
		task["state"] = AirMission.INVESTIGATING
		return
	if m.kind == AirMission.Kind.STRIKE:
		_step_strike(m, a, task)
	else:
		_step_station(m, a, task)


func _drop(m: AirMission, a: Unit, why: String) -> void:
	m.aircraft.erase(a)
	m.tasks.erase(a)
	if a.station_mission_id == m.id:
		a.station_mission_id = -1
	if why != "":
		_report(m, "%s: %s %s" % [m.label(), a.callsign, why], false)


func _release(m: AirMission, a: Unit) -> void:
	_drop(m, a, "")
	m.requested = maxi(m.requested - 1, 0)
	if m.pending_launches > m.requested:
		m.pending_launches = m.requested
	_report(m, "%s: %s released by your order" % [m.label(), a.callsign], true)


## An airframe whose relief was called topped up from a tanker instead of going home, and the
## refuelling sent it back to the station. Two would then hold a one-airframe station: strike the
## relief off if it is still queued, otherwise send this one home. Returns true when it goes home.
func _hand_over_after_tanking(m: AirMission, a: Unit, task: Dictionary) -> bool:
	if m.pending_launches > 0:
		m.pending_launches -= 1
		task["relieved"] = false
		_report(m, "%s: %s refuelled and kept the station; relief stood down" % [m.label(), a.callsign], true)
		return false
	var holding := 0
	for other in m.aircraft:
		if other != a and not bool(m.tasks[other]["relieved"]):
			holding += 1
	if holding < m.requested:
		task["relieved"] = false  # the relief never came: it keeps the station
		return false
	task["state"] = AirMission.RETURNING
	_report(m, "%s: %s refuelled, relief on station, returning" % [m.label(), a.callsign], true)
	_crew(a, Order.return_to_base())
	return true


## With relief on, launch a ready reserve airframe early enough to reach the station as this one
## turns for home: its own launch time plus the transit out, ahead of the fuel it needs to get back.
func _relief_due(m: AirMission, a: Unit, task: Dictionary) -> void:
	if bool(task["relieved"]) or not bool(task["assigned"]):
		return
	# Out of the rounds the mission needs it for: home, with a relief when relief is on.
	if m.kind == AirMission.Kind.CAP and _rounds_for(a, "air") <= 0:
		var message := "%s out of air-to-air rounds, returning" % a.callsign
		if not m.relief:
			_report(m, "%s: %s" % [m.label(), message], false)
		_call_relief(m, a, task, message)
		_crew(a, Order.return_to_base())
		return
	if not m.relief:
		return
	var cruise := Geo.knots_to_nm_per_s(maxf(a.spec.cruise_speed_kn, 1.0))
	var lead_s := a.spec.launch_time_s + m.base.position.distance_to(m.station) / cruise
	if a.fuel_s - aviation_manager.return_fuel_required(a, m.base) <= lead_s:
		_call_relief(m, a, task, "relief launching for %s" % a.callsign)


func _call_relief(m: AirMission, a: Unit, task: Dictionary, message: String) -> void:
	if bool(task["relieved"]):
		return
	task["relieved"] = true
	if not m.relief or m.kind == AirMission.Kind.STRIKE:
		return
	var holding := 0
	for other in m.aircraft:
		if not bool(m.tasks[other]["relieved"]):
			holding += 1
	if holding + m.pending_launches < m.requested:
		m.pending_launches += 1
		_report(m, "%s: %s" % [m.label(), message], true)


func _step_station(m: AirMission, a: Unit, task: Dictionary) -> void:
	if not bool(task["assigned"]):
		_assign_station(m, a, task)
		return
	if a.station_mission_id != m.id:
		_release(m, a)
		return
	# Legacy saves used STOP plus an absolute dip_until time, with no physical array state.
	# Restore their standing route before starting a deliberate cycle; otherwise on_station()
	# stays false forever. Do this on a tick, so snapshot restoration itself emits no orders.
	var legacy_until := float(task.get("dip_until", -1.0))
	if legacy_until > 0.0:
		task.erase("dip_until")
		task["next_dip_at"] = now_s + DIP_INTERVAL_S
		if _crew(a, Order.return_to_station()) and legacy_until > now_s:
			task["dip_cycle"] = _crew(a, Order.deploy_dipping_sonar(legacy_until - now_s))
		return
	if bool(task.get("dip_cycle", false)):
		if a.dip_phase != DippingSonar.Phase.STOWED:
			task["state"] = AirMission.DIPPING
			return
		task["dip_cycle"] = false
		task["next_dip_at"] = now_s + DIP_INTERVAL_S
		return
	if not a.on_station():
		# A task ended with auto-return off: the airframe holds until told to go back (S).
		task["state"] = AirMission.HOLDING
		return
	var half := float(task.get("half", m.radius_nm)) + STATION_ARRIVAL_MARGIN_NM
	var offset := a.position - m.station
	task["state"] = AirMission.ON_STATION if absf(offset.x) <= half and absf(offset.y) <= half else AirMission.TRANSITING
	match m.kind:
		AirMission.Kind.CAP:
			_cap_look(m, a, task)
		AirMission.Kind.RECON:
			_recon_look(m, a, task)
		AirMission.Kind.ASW:
			_asw_look(m, a, task)


## The station is a circuit round the chosen point, flown by the existing patrol: fuel, recovery,
## evasion and refuelling all already know how to interrupt and resume one.
func _assign_station(m: AirMission, a: Unit, task: Dictionary) -> void:
	var half := maxf(station_half_nm(m.kind, m.radius_nm), (UnitManager.patrol_min_leg_nm(a) + 0.2) * 0.5)
	task["half"] = half
	var circuit := Order.patrol_box(m.station - Vector2(half, half), m.station + Vector2(half, half))
	circuit.station_label = m.station_label()
	circuit.mission_id = m.id
	# Reconnaissance never fires: not on its own looks, nor on one the commander adds while it
	# holds the station (engagement after identification is skipped for it).
	circuit.identify_only = m.kind == AirMission.Kind.RECON
	if not _crew(a, circuit):
		_report(m, "%s: %s cannot take the station: %s" % [m.label(), a.callsign, UnitManager.patrol_rejection(a, circuit.route).to_lower()], false)
		_crew(a, Order.return_to_base())
		task["assigned"] = true
		return
	task["assigned"] = true
	task["state"] = AirMission.TRANSITING
	if m.kind == AirMission.Kind.ASW and a.spec.max_altitude_m > 0.0:
		_crew(a, Order.set_altitude(ASW_ALTITUDE_M))


## Half the side of the square circuit flown on station. A CAP orbits on the circle's edge; a
## search flies a box inside its area so that what it lays and sees falls in the area.
static func station_half_nm(kind: int, radius_nm: float) -> float:
	return radius_nm if kind == AirMission.Kind.CAP else radius_nm * 0.6


## Air contacts near the CAP: hostiles are intercepted under the ROE, unknowns are identified.
## Identification never authorises fire: only a contact the plot already calls HOSTILE is attacked.
func _cap_look(m: AirMission, a: Unit, task: Dictionary) -> void:
	var best: Track = null
	var best_d := INF
	var attack := false
	for t: Track in _nearby(m, a, m.radius_nm + COMMIT_MARGIN_NM):
		if not _probably_air(t):
			continue
		var d := a.position.distance_squared_to(t.position)
		if t.identity == "HOSTILE":
			if _committed(m.faction, t, true) >= INTERCEPTORS_PER_TRACK:
				continue
			if UnitManager.attack_rejection(a, t) != "":
				continue
			if not attack or d < best_d:
				best = t
				best_d = d
				attack = true
		elif not attack and t.identity == "UNKNOWN" and t.classification < Track.Classification.CLASS_KNOWN:
			if _committed(m.faction, t, false) > 0 or UnitManager.investigation_rejection(a, t) != "":
				continue
			if d < best_d:
				best = t
				best_d = d
	if best == null:
		return
	if attack:
		if _crew(a, Order.attack(best)):
			task["state"] = AirMission.ENGAGING
			task["attacked"] = true
			_report(m, "%s intercepting track %s" % [a.callsign, best.id], true)
	elif _crew(a, Order.investigate(best, true)):
		task["state"] = AirMission.INVESTIGATING
		_report(m, "%s identifying track %s" % [a.callsign, best.id], true)


## Reconnaissance identifies what is in its area. It never fires: its looks are identify-only, so
## not even engagement after identification can turn one into an attack.
func _recon_look(m: AirMission, a: Unit, task: Dictionary) -> void:
	var best: Track = null
	var best_d := INF
	for t: Track in _nearby(m, a, m.radius_nm + SEARCH_MARGIN_NM):
		if t.classification >= Track.Classification.CLASS_KNOWN or _committed(m.faction, t, false) > 0:
			continue
		if UnitManager.investigation_rejection(a, t) != "":
			continue
		var d := a.position.distance_squared_to(t.position)
		if d < best_d:
			best = t
			best_d = d
	if best != null and _crew(a, Order.investigate(best, true)):
		task["state"] = AirMission.INVESTIGATING
		_report(m, "%s identifying track %s" % [a.callsign, best.id], true)


## ASW search: a pattern of sonobuoys across the area, a look at what they find, and a torpedo for
## a submarine the plot holds as hostile, under the ROE.
func _asw_look(m: AirMission, a: Unit, task: Dictionary) -> void:
	for t: Track in _nearby(m, a, m.radius_nm + SEARCH_MARGIN_NM):
		if t.domain != "subsurface":
			continue
		if t.identity == "HOSTILE" and _committed(m.faction, t, true) < INTERCEPTORS_PER_TRACK and UnitManager.attack_rejection(a, t) == "":
			if _crew(a, Order.attack(t)):
				task["state"] = AirMission.ENGAGING
				task["attacked"] = true
				_report(m, "%s attacking submarine track %s" % [a.callsign, t.id], true)
				return
		elif t.classification < Track.Classification.CLASS_KNOWN and _committed(m.faction, t, false) == 0 and UnitManager.investigation_rejection(a, t) == "":
			if _crew(a, Order.investigate(t, true)):
				task["state"] = AirMission.INVESTIGATING
				_report(m, "%s prosecuting track %s" % [a.callsign, t.id], true)
				return
	if _dips(a) and a.position.distance_to(m.station) <= m.radius_nm and now_s >= float(task.get("next_dip_at", 0.0)) and not Terrain.is_land(a.position):
		if _crew(a, Order.deploy_dipping_sonar(DIP_S)):
			task["dip_cycle"] = true
			return
	if a.sonobuoys <= 0 or a.spec.sonobuoy_sensitivity_nm <= 0.0:
		return
	if a.position.distance_to(m.station) > m.radius_nm or now_s - float(task["buoy_at"]) < BUOY_INTERVAL_S:
		return
	for b: Sonobuoy in aviation_manager.sonobuoys:
		if b.faction == a.faction and b.position.distance_to(a.position) < BUOY_SPACING_NM:
			return
	if _crew(a, Order.deploy_sonobuoy()):
		task["buoy_at"] = now_s


## A helicopter carrying a sonar that only works in the water: a dipping set.
static func _dips(a: Unit) -> bool:
	if not a.spec.can_hover:
		return false
	for s in a.sensors:
		if s.kind == "sonar" and s.requires_hover:
			return true
	return false


## A strike flies straight at its target on the attack task, and comes home once it is over.
func _step_strike(m: AirMission, a: Unit, task: Dictionary) -> void:
	if bool(task["attacked"]):
		# The attack ended: destroyed, lost, or the magazines are empty.
		task["state"] = AirMission.RETURNING
		_crew(a, Order.return_to_base())
		return
	var why := _strike_target_rejection(m.base, m.target)
	if why == "":
		why = UnitManager.attack_rejection(a, m.target)
	if why != "":
		_report(m, "%s: %s returning — %s" % [m.label(), a.callsign, why.to_lower()], false)
		task["attacked"] = true
		_crew(a, Order.return_to_base())
		return
	if _crew(a, Order.attack(m.target)):
		task["state"] = AirMission.ENGAGING
		task["attacked"] = true


## The faction's held contacts this airframe may act on, near the mission's station.
func _nearby(m: AirMission, a: Unit, reach_nm: float) -> Array:
	var out: Array = []
	if track_manager == null:
		return out
	for t: Track in track_manager.get_tracks(m.faction):
		if t.status != Track.Status.ACTIVE or not t.visible_to(a) or t.is_bearing_only():
			continue
		if t.position.distance_to(m.station) <= reach_nm:
			out.append(t)
	return out


static func _probably_air(t: Track) -> bool:
	if t.domain != "":
		return t.domain == "air"
	return t.altitude_m > AIRBORNE_ALTITUDE_M


## Own platforms already attacking (or investigating) this contact.
func _committed(faction: String, t: Track, attacking: bool) -> int:
	var n := 0
	for u in unit_manager.units:
		if not u.alive or u.faction != faction:
			continue
		if (attacking and u.attack_track == t) or (not attacking and u.investigation_track == t):
			n += 1
	return n


## An order from the mission is the crew's: it never ends the commander's standing assignment.
## Every look a mission orders is identify-only: a CAP or ASW mission attacks what it has
## identified through its own look, with its own limit on how many airframes go after one contact.
func _crew(a: Unit, order: Order) -> bool:
	order.origin = "crew"
	var ok := unit_manager.issue_order(a, order)
	var m := mission_for(a)
	if ok and m != null and m.tasks.has(a):
		m.tasks[a]["generation"] = a.order_generation
	return ok


func _report(m: AirMission, message: String, good: bool) -> void:
	m.note = message
	mission_report.emit(m, message, good)
