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
## A CAP commits on air contacts this far beyond its station, by default. However short the
## pursuit, the fighter's own leash is never less than its missiles' reach, and it goes for any
## raid it can get a shot at without flying beyond that leash: a raid closing on it is met further
## out than one crossing or running away. GAMEPLAY_ESTIMATE.
const COMMIT_MARGIN_NM := 60.0
## A fighter or a reconnaissance airframe keeps this much beyond the reach of a ship's air-defence
## missiles. GAMEPLAY_ESTIMATE.
const AIR_DEFENCE_MARGIN_NM := 5.0
## A fighter is sent only on a raid it can take inside its leash with this much to spare, and kept
## after one until it no longer can at all; one called back does not turn for the same raid again
## until it has regained its station and this long has passed. Without the gap it would be sent
## and recalled every few seconds on a raid at the edge. GAMEPLAY_ESTIMATE.
const COMMIT_HYSTERESIS_NM := 5.0
const BREAK_OFF_S := 120.0
## A fighter in a fight with one hostile coming in on it turns to another only if that one is this
## much nearer. GAMEPLAY_ESTIMATE.
const THREAT_SWITCH_NM := 10.0
## A held course within about 60 degrees of a point counts as closing on it. A fighter sent after
## a hostile closing on it stays on it until the hostile's course is opening the range: a plot that
## swings the course across the 60-degree line must not send and recall it by turns.
const CLOSING_COS := 0.5
const STILL_CLOSING_COS := 0.0
## A CAP fighter that sees a round coming at it breaks when the round is this close to arriving,
## as the other side's fighters do and the commander can order: soon enough that the turn is built
## up by the endgame, and the break is flown again while the round is still coming. GAMEPLAY_ESTIMATE.
const MISSILE_BREAK_S := 40.0
## A reconnaissance or ASW aircraft looks at contacts this far beyond its search area.
const SEARCH_MARGIN_NM := 5.0
## An unarmed sensor aircraft keeps at least this far from a ship it has not identified as
## harmless: it is the one aircraft on the plot that cannot answer a missile, and its radar and
## ESM do their work from here. GAMEPLAY_ESTIMATE, about a ship's area-defence missile reach.
const SENSOR_STANDOFF_NM := 40.0
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
## Ready alert. A deck holding fighters on alert scrambles them into a CAP between itself and a
## hostile air raid that comes within this distance, or that is closing on it within the wider
## one: a raid's stand-off missiles reach 200 nm and more, so the alert has to go while the raid is
## still outside that. The CAP is laid toward the raid at this fraction of its range, no further
## out than the cap, with a pursuit that reaches the raid. A CAP the deck already has up does not
## hold the alert back unless it is already going for that raid. GAMEPLAY_ESTIMATE throughout; the
## alert is spent by the scramble and set again by order.
const MAX_READY_ALERT := 4
const ALERT_TRIGGER_NM := 60.0
const ALERT_CLOSING_TRIGGER_NM := 220.0
const ALERT_STATION_FRACTION := 0.5
const ALERT_STATION_MAX_NM := 40.0
const ALERT_RADIUS_NM := 15.0

var unit_manager: UnitManager
var aviation_manager: AviationManager
var track_manager: TrackManager
var threat_manager: ThreatManager
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
	var cruise := Geo.knots_to_nm_per_s(maxf(spec.flight_speed("transit"), 1.0))
	var transit := distance_nm / cruise
	var home_reserve := maxf(spec.endurance_s * AviationManager.BINGO_FRACTION, transit + spec.recovery_time_s + spec.endurance_s * AviationManager.LANDING_RESERVE_FRACTION)
	return (spec.endurance_s - transit - home_reserve) / spec.fuel_burn_rate(spec.flight_speed("patrol"))


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
	if target.confirmed_destroyed:
		return "Contact already destroyed"
	if target.status == Track.Status.LOST:
		return "Contact lost"
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
	if order.mission_id >= 0:
		return revise(base, order)
	var intent_why := _intent_rejection(base, order)
	if intent_why != "":
		order.execution_accepted = false
		order.receipt = intent_why
		return null
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
	m.note_at_s = now_s
	m.cap_intent = order.cap_intent
	m.protected_unit = order.protected_unit if order.cap_intent == "protect" else null
	m.pursuit_nm = clampf(order.pursuit_nm, 0.0, MAX_RADIUS_NM)
	if kind == AirMission.Kind.STRIKE:
		m.target = order.track
		m.target_id = order.track.id
		m.station = order.track.position
		m.radius_nm = 0.0
	elif is_intercept_order(order):
		# Fighters sent at one raid chase that raid; a ring over where it was is empty sky by the
		# time they get there, and relief for it would only keep fighters circling nothing.
		m.intercept = true
		m.target = order.track
		m.target_id = order.track.id
		m.station = order.track.position
		m.radius_nm = MIN_RADIUS_NM
		m.relief = false
		m.cap_intent = "hold"
		m.protected_unit = null
	else:
		m.station = order.target_pos
		m.radius_nm = clampf(order.radius_nm if order.radius_nm > 0.0 else default_radius(kind), MIN_RADIUS_NM, MAX_RADIUS_NM)
	if m.protected_unit != null:
		m.anchor_offset = m.station - m.protected_unit.position
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


## A CAP order that names a hostile air contact is an intercept of that contact.
static func is_intercept_order(order: Order) -> bool:
	return order.mission_kind == AirMission.Kind.CAP and order.track != null and order.track.identity == "HOSTILE" and _probably_air(order.track)


## Why an intercept can no longer go for its contact, or "".
static func _intercept_target_rejection(m: AirMission) -> String:
	var t := m.target
	if t == null or t.confirmed_destroyed:
		return "Contact destroyed"
	if t.status == Track.Status.LOST or t.is_bearing_only() or not t.position.is_finite():
		return "Contact lost"
	if t.identity != "HOSTILE":
		return "Contact no longer hostile"
	return ""


func _intent_rejection(base: Unit, order: Order) -> String:
	if order.cap_intent not in ["hold", "protect"]:
		return "Choose Hold area or Protect group"
	if order.cap_intent == "protect":
		if order.mission_kind != AirMission.Kind.CAP:
			return "Only combat air patrols protect a group"
		if base == null or order.protected_unit == null or not order.protected_unit.alive or order.protected_unit.faction != base.faction:
			return "Choose a surviving friendly group to protect"
	return ""


## The same validation drives the editor and order execution. Retasking aircraft does not
## require a serviceable flight deck; additional launches still wait for deck recovery.
func revision_rejection(base: Unit, order: Order) -> String:
	var m := mission_by_id(order.mission_id)
	if m == null or not m.active or m.cancelled or m.base != base:
		return "That mission is no longer available to this deck"
	if base == null or not base.alive:
		return "Base lost"
	if m.kind == AirMission.Kind.STRIKE:
		return "Strike targets cannot be changed after assignment"
	if m.intercept:
		return "An intercept follows its contact; cancel it to send the fighters elsewhere"
	if order.mission_kind != m.kind or order.aircraft_id != m.platform_id:
		return "Keep the mission and aircraft type when editing"
	if not order.target_pos.is_finite():
		return "Choose a station on the chart"
	var spec := DataDB.platform(m.platform_id)
	var distance := base.position.distance_to(order.target_pos)
	if station_time_s(spec, distance) <= 0.0:
		return "Beyond the %s's radius (%.0f nm)" % [spec.short_name, distance]
	var why := _intent_rejection(base, order)
	if why != "":
		return why
	if order.aircraft_count < 1:
		return "Keep at least one aircraft, or cancel the mission"
	var maximum := working_aircraft(m).size() + m.pending_launches + available_for(base, m.platform_id, m.kind, m.target)
	if order.aircraft_count > maximum:
		return "Only %d aircraft available to this mission" % maximum
	return ""


static func working_aircraft(m: AirMission) -> Array[Unit]:
	var working: Array[Unit] = []
	for a in m.aircraft:
		if a.alive and not a.returning and not bool(m.tasks[a].get("relieved", false)):
			working.append(a)
	return working


## Edit the standing task in place. Existing aircraft, stores, sorties and task identity survive.
## An unachievable increase is refused atomically; the old task continues unchanged.
func revise(base: Unit, order: Order) -> AirMission:
	var why := revision_rejection(base, order)
	if why != "":
		order.execution_accepted = false
		order.receipt = why
		return null
	var m := mission_by_id(order.mission_id)
	var working := working_aircraft(m)
	m.station = order.target_pos
	m.radius_nm = clampf(order.radius_nm, MIN_RADIUS_NM, MAX_RADIUS_NM)
	m.requested = order.aircraft_count
	m.relief = order.relief
	m.auto_return = order.automatic
	m.cap_intent = order.cap_intent
	m.protected_unit = order.protected_unit if order.cap_intent == "protect" else null
	m.anchor_offset = m.station - m.protected_unit.position if m.protected_unit != null else Vector2.ZERO
	m.pursuit_nm = clampf(order.pursuit_nm, 0.0, MAX_RADIUS_NM)
	# Reductions strike off the queue first. Retain the first working section; excess aircraft
	# already airborne return, and excess launches return as soon as they clear the deck.
	m.pending_launches = maxi(m.requested - working.size(), 0)
	for i in working.size():
		var a := working[i]
		a.auto_return = m.auto_return
		if i >= m.requested:
			m.tasks[a]["retire"] = true
			m.tasks[a]["relieved"] = true
		elif bool(m.tasks[a].get("assigned", false)):
			_relocate_airframe(m, a, m.tasks[a])
	order.execution_accepted = true
	order.receipt = "%s %d updated · %d aircraft · %.0f nm radius · %s" % [m.kind_name(), m.id, m.requested, m.radius_nm, m.intent_label()]
	_report(m, order.receipt, true)
	return m


func _relocate_airframe(m: AirMission, a: Unit, task: Dictionary) -> void:
	var half := maxf(station_half_nm(m.kind, m.radius_nm), (UnitManager.patrol_min_leg_nm(a) + 0.2) * 0.5)
	task["half"] = half
	task["centre"] = m.station
	var own := m.station + _slot_offset(m, a, task)
	var circuit := Order.patrol_box(own - Vector2(half, half), own + Vector2(half, half))
	if a.on_station() and a.attack_track == null and a.investigation_track == null and a.tanking_on == null and a.evasion_remaining_s <= 0.0:
		_assign_station(m, a, task)
	else:
		# Update the return destination without ending an interception, investigation or recovery.
		a.station_route.assign(circuit.route)


func _follow_anchor(m: AirMission) -> void:
	if m.kind != AirMission.Kind.CAP or m.cap_intent != "protect":
		return
	if m.protected_unit == null or not m.protected_unit.alive:
		m.cap_intent = "hold"
		m.protected_unit = null
		_report(m, "%s %d: protected group lost; holding last area" % [m.kind_name(), m.id], false)
		return
	var next_station := m.protected_unit.position + m.anchor_offset
	# A two-mile movement is enough to move the circuit; do not reset its leg every second.
	if next_station.distance_to(m.station) < 2.0:
		return
	m.station = next_station
	for a in m.aircraft:
		if bool(m.tasks[a].get("assigned", false)) and not a.returning:
			_relocate_airframe(m, a, m.tasks[a])


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
	m.note_at_s = now_s
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

## Quick tasking: one gesture on the chart flies a sensible mission, without the Air Operations
## dialog. Defaults per kind: airframes asked for, station radius, relief. GAMEPLAY_ESTIMATE.
const QUICK_COUNT := {AirMission.Kind.CAP: 2, AirMission.Kind.RECON: 1, AirMission.Kind.ASW: 1, AirMission.Kind.STRIKE: 4}
const QUICK_RADIUS_NM := {AirMission.Kind.CAP: 15.0, AirMission.Kind.RECON: 20.0, AirMission.Kind.ASW: 12.0, AirMission.Kind.STRIKE: 0.0}
const QUICK_RELIEF := {AirMission.Kind.CAP: true, AirMission.Kind.RECON: false, AirMission.Kind.ASW: true, AirMission.Kind.STRIKE: false}
## A look at one contact searches a small area round it.
const QUICK_IDENTIFY_RADIUS_NM := 6.0


## The aircraft type this deck should send on a quick mission: the type with the most airframes it
## can have for the job. Reconnaissance prefers an unarmed sensor aircraft or a helicopter over a
## fighter, so a quick look does not spend a deck's strike or CAP airframes; but a look at a ship
## (`look`) is a job for a helicopter or an armed jet, never for an aircraft that cannot answer
## the ship's missiles. "" when none fits.
func quick_type(base: Unit, kind: int, target: Track = null, look: Track = null) -> String:
	if base == null:
		return ""
	var best := ""
	var best_score := -1.0
	var seen := {}
	for a: Unit in base.embarked:
		if not a.alive or seen.has(a.spec.id):
			continue
		seen[a.spec.id] = true
		if not type_suits(a.spec, kind):
			continue
		var n := available_for(base, a.spec.id, kind, target)
		if n <= 0:
			continue
		var score := float(n)
		if kind == AirMission.Kind.RECON and look != null and _ship_to_avoid(look):
			if a.spec.can_hover or not a.spec.weapon_loadout.is_empty():
				score += 1000.0
			elif a.is_sensor_aircraft():
				continue
		elif kind == AirMission.Kind.RECON and (a.is_sensor_aircraft() or a.spec.can_hover):
			score += 1000.0
		if kind == AirMission.Kind.ASW and (a.spec.sonobuoy_count > 0 or _dips(a)):
			score += 1000.0
		if score > best_score:
			best = a.spec.id
			best_score = score
	return best


## The order a quick mission flies, or null with the reason in `why` (index 0).
func quick_order(base: Unit, kind: int, at: Vector2, target: Track = null, why: Array = []) -> Order:
	# A strike and an intercept are laid on their contact. A look at a contact is a small search
	# area round it: the contact only sets where and how wide.
	var identify := target != null and kind == AirMission.Kind.RECON
	var look := target if identify else null
	var intercept := target != null and kind == AirMission.Kind.CAP and target.identity == "HOSTILE" and _probably_air(target)
	if kind != AirMission.Kind.STRIKE and not intercept:
		target = null
	var pid := quick_type(base, kind, target, look)
	if pid == "":
		why.append("No %s aircraft ready on %s" % [AirMission.KIND_NAMES[kind], base.callsign if base != null else "a deck"])
		return null
	var count := mini(int(QUICK_COUNT[kind]), available_for(base, pid, kind, target))
	var radius := QUICK_IDENTIFY_RADIUS_NM if identify else float(QUICK_RADIUS_NM[kind])
	var order := Order.air_mission(kind, pid, count, at, radius, target, bool(QUICK_RELIEF[kind]) and not intercept, true)
	order.pursuit_nm = COMMIT_MARGIN_NM
	var reason := mission_rejection(base, kind, pid, at, target)
	if reason != "":
		why.append(reason)
		return null
	return order


## The nearest of this side's decks that can fly a quick mission of this kind to `at`, or null.
func quick_deck(faction: String, kind: int, at: Vector2, target: Track = null) -> Unit:
	var look := target if kind == AirMission.Kind.RECON else null
	if kind != AirMission.Kind.STRIKE:
		target = null
	var best: Unit = null
	var best_d := INF
	for u: Unit in unit_manager.units:
		if u.faction != faction or not u.alive or u.is_aircraft() or u.spec.aircraft_capacity <= 0 or not u.is_engageable():
			continue
		var pid := quick_type(u, kind, target, look)
		if pid == "" or mission_rejection(u, kind, pid, at, target) != "":
			continue
		var d := u.position.distance_to(at)
		if d < best_d:
			best = u
			best_d = d
	return best


## Sends every airborne airframe of this deck home, mission or not. Returns how many were told.
func recall_all(base: Unit) -> int:
	if base == null:
		return 0
	var flying := 0
	for a: Unit in base.embarked:
		if a.alive and a.airborne():
			flying += 1
	for m in missions.duplicate():
		if m.active and m.base == base:
			cancel(m.id, base)
	for a: Unit in base.embarked:
		if a.alive and a.airborne() and not a.returning:
			unit_manager.issue_order(a, Order.return_to_base())
	return flying


## Why this deck cannot hold `count` fighters on alert, or "". Standing an alert down always works.
static func ready_alert_rejection(u: Unit, count: int) -> String:
	if u == null or not u.is_engageable() or u.spec.aircraft_capacity <= 0:
		return "No flight deck"
	if count <= 0:
		return ""
	if count > MAX_READY_ALERT:
		return "At most %d on alert" % MAX_READY_ALERT
	if alert_fighter_type(u) == "":
		return "No fighters aboard"
	return ""


## The fighter type a deck puts on alert: the one with most airframes aboard fit for a CAP.
static func alert_fighter_type(base: Unit) -> String:
	var counts := {}
	for a: Unit in base.embarked:
		if a.alive and type_suits(a.spec, AirMission.Kind.CAP):
			counts[a.spec.id] = int(counts.get(a.spec.id, 0)) + 1
	var best := ""
	for pid: String in counts:
		if best == "" or int(counts[pid]) > int(counts[best]):
			best = pid
	return best


## The nearest hostile air contact that should bring an alert deck's fighters up, or null. A raid
## the deck's own CAP is already going for needs no scramble.
func _alert_threat(base: Unit) -> Track:
	var best: Track = null
	var best_d := INF
	for t: Track in track_manager.tracks_for(base):
		if t.identity != "HOSTILE" or t.status != Track.Status.ACTIVE or not _probably_air(t) or t.is_bearing_only():
			continue
		if _cap_committed_to(base, t):
			continue
		var d := t.position.distance_to(base.position)
		var closing := false
		if t.has_kinematics and t.speed_kn > 0.0 and d > 0.01:
			closing = Geo.heading_to_vector(t.course_deg).dot((base.position - t.position).normalized()) > 0.3
		if (d <= ALERT_TRIGGER_NM or (closing and d <= ALERT_CLOSING_TRIGGER_NM)) and d < best_d:
			best = t
			best_d = d
	return best


## Whether a CAP from this deck has an airframe going for this raid.
func _cap_committed_to(base: Unit, t: Track) -> bool:
	for m in missions:
		if not m.active or m.base != base or m.kind != AirMission.Kind.CAP:
			continue
		if m.intercept and m.target == t:
			return true
		for a in m.aircraft:
			if a.alive and a.attack_track == t:
				return true
	return false


## Decks on alert with a raid coming: launch the alert as a CAP toward it. A deck already flying a
## CAP that is going for that raid keeps its alert for the next one.
func _scramble_alerts() -> void:
	if track_manager == null:
		return
	for base: Unit in unit_manager.units:
		if base.ready_alert <= 0 or not base.alive or not base.is_engageable():
			continue
		var threat := _alert_threat(base)
		if threat == null:
			continue
		var pid := alert_fighter_type(base)
		if pid == "":
			continue
		var available := available_for(base, pid, AirMission.Kind.CAP)
		if available <= 0:
			continue
		var count := mini(base.ready_alert, available)
		var bearing := (threat.position - base.position).normalized()
		var reach := minf(base.position.distance_to(threat.position) * ALERT_STATION_FRACTION, ALERT_STATION_MAX_NM)
		var station := base.position + bearing * reach
		var order := Order.air_mission(AirMission.Kind.CAP, pid, count, station, ALERT_RADIUS_NM)
		order.pursuit_nm = clampf(station.distance_to(threat.position) - ALERT_RADIUS_NM, COMMIT_MARGIN_NM, MAX_RADIUS_NM)
		order.origin = "crew"
		var m := request(base, order)
		if m == null:
			continue
		base.ready_alert = 0
		_report(m, "ALERT LAUNCH: %d × %s scrambled from %s toward track %s" % [count, DataDB.platform(pid).short_name, base.callsign, threat.id], true)


func tick(dt: float, now: float) -> void:
	now_s = now
	_accum += dt
	while _accum >= CYCLE_DT - 1e-6:
		_accum -= CYCLE_DT
		_break_from_missiles()
		for m in missions:
			if m.active:
				_step(m)
		_scramble_alerts()


## A CAP fighter with a round it can see coming at it breaks: the endgame is then flown against a
## turning target, as it is against the other side's fighters. The break interrupts the steering,
## not the mission, and the attack it was flying takes up again after it.
func _break_from_missiles() -> void:
	if threat_manager == null:
		return
	var factions: Array[String] = []
	for m in missions:
		if m.active and m.kind == AirMission.Kind.CAP and not factions.has(m.faction):
			factions.append(m.faction)
	for faction in factions:
		for entry: Dictionary in AirDefence.inbound_threats(unit_manager, threat_manager, faction):
			var a: Unit = entry["target"]
			if not a.is_aircraft() or a.spec.can_hover or not a.airborne() or a.evasion_remaining_s > 0.0:
				continue
			if float(entry["time_s"]) > MISSILE_BREAK_S or not threat_manager.visible_to(a, entry["weapon"]):
				continue
			var m := mission_for(a)
			if m == null or m.kind != AirMission.Kind.CAP:
				continue
			var order := Order.evade()
			if _crew(a, order) and order.execution_accepted:
				_report(m, "%s breaking: missile inbound" % a.callsign, true)


func _step(m: AirMission) -> void:
	if m.cancelled:
		_step_cancelled(m)
		return
	if m.base == null or not m.base.alive:
		_end(m, "Base lost")
		return
	_follow_anchor(m)
	if m.intercept and _intercept_target_rejection(m) == "":
		m.station = m.target.position
	for a in m.aircraft.duplicate():
		_track_airframe(m, a)
	if not m.active:
		return
	if (m.kind == AirMission.Kind.STRIKE or m.intercept) and m.pending_launches > 0:
		var why := _strike_target_rejection(m.base, m.target) if m.kind == AirMission.Kind.STRIKE else _intercept_target_rejection(m)
		if why != "":
			_report(m, "%s: %d launch%s cancelled — %s" % [m.label(), m.pending_launches, "" if m.pending_launches == 1 else "es", why.to_lower()], false)
			m.pending_launches = 0
	_launch_owed(m)
	if m.aircraft.is_empty() and m.pending_launches <= 0:
		if m.lost_total > 0 and m.completed_sorties == 0:
			_end(m, "All aircraft lost")
		elif m.kind == AirMission.Kind.STRIKE:
			# A strike whose launches were all struck off never flew: say so, not "complete".
			_end(m, "Strike complete" if m.launched_total > 0 else "Strike called off")
		elif m.lost_total > 0:
			_end(m, "%d recovered, %d lost" % [m.completed_sorties, m.lost_total])
		else:
			_end(m, "All aircraft recovered")
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


## An airframe back at this deck, in the marshal stack or on approach, waiting for it to stop
## launching: recoveries come first, or a busy launch queue would keep it holding on its last fuel.
static func _recovery_waiting(base: Unit) -> bool:
	if base.spec.flight_facility() == "airfield":
		return false  # a field launches and recovers on separate runways
	for a in base.inbound_aircraft:
		if a.alive and a.airborne() and a.returning and a.position.distance_to(base.position) <= AviationManager.MARSHAL_RANGE_NM + AviationManager.MARSHAL_SLACK_NM:
			return true
	for a in base.embarked:
		if a.alive and a.airborne() and a.returning and (a.recovery_base == null or a.recovery_base == base) and a.position.distance_to(base.position) <= AviationManager.MARSHAL_RANGE_NM + AviationManager.MARSHAL_SLACK_NM:
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
		if not a.departed:
			m.lost_total += 1
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
	if bool(task.get("retire", false)):
		if a.airborne() and not a.returning:
			_crew(a, Order.return_to_base())
		task["state"] = AirMission.RETURNING
		return
	if m.kind == AirMission.Kind.CAP and not m.intercept:
		_enforce_cap_boundary(m, a, task)
	if a.returning:
		if task["state"] != AirMission.RETURNING and task["state"] != AirMission.MARSHAL:
			_call_relief(m, a, task, "%s heading home" % a.callsign)
		task["state"] = AirMission.MARSHAL if AviationManager.in_marshal(a) else AirMission.RETURNING
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
	if m.kind != AirMission.Kind.STRIKE and not m.intercept:
		_relief_due(m, a, task)
	if m.kind == AirMission.Kind.CAP and (a.attack_track != null or a.investigation_track != null) and _answer_threat(m, a, task):
		return
	if a.attack_track != null:
		task["state"] = AirMission.ENGAGING
		task["attacked"] = true
		if m.kind == AirMission.Kind.STRIKE and a.attack_rounds_fired > 0 and not _guides_its_rounds(a):
			_report(m, "%s: %s salvo away, returning" % [m.label(), a.callsign], true)
			task["state"] = AirMission.RETURNING
			_crew(a, Order.return_to_base())
		return
	if a.investigation_track != null:
		task["state"] = AirMission.INVESTIGATING
		return
	if m.kind == AirMission.Kind.STRIKE:
		_step_strike(m, a, task)
	elif m.intercept:
		_step_intercept(m, a, task)
	else:
		_step_station(m, a, task)


## A CAP fighter busy with one contact on the mission's word turns on a hostile that comes in on it
## inside its own missile reach and nearer than the contact it is after: it does not fly on
## toward a raid while another shoots at it. An attack the commander ordered is left alone.
## Returns true when it turned.
func _answer_threat(m: AirMission, a: Unit, task: Dictionary) -> bool:
	if int(task.get("cap_player_generation", -1)) != a.player_order_generation:
		return false
	var busy_with := a.attack_track if a.attack_track != null else a.investigation_track
	var busy_nm := a.position.distance_to(busy_with.position) if a.attack_track != null else INF
	var best: Track = null
	var best_d := busy_nm
	# One already coming in on it is the fight it is in: it turns from that only for one a good
	# deal nearer, or it would hop between two and never settle on either long enough to shoot.
	if a.attack_track != null and threatens(a, a.attack_track):
		best_d -= THREAT_SWITCH_NM
	for t: Track in _nearby(m, a, INF):
		if t == a.attack_track or t.bearing_only or not threatens(a, t, COMMIT_HYSTERESIS_NM):
			continue
		var d := a.position.distance_to(t.position)
		if d < best_d and UnitManager.attack_rejection(a, t) == "":
			best = t
			best_d = d
	if best == null or not _crew(a, Order.attack(best)):
		return false
	_crew(a, Order.set_speed(a.spec.flight_speed("dash")))
	task["speed_for"] = AirMission.ENGAGING
	task["state"] = AirMission.ENGAGING
	task["cap_target"] = best
	task["cap_player_generation"] = a.player_order_generation
	if m.intercept:
		# Once this is dealt with it goes back for the raid it was sent at.
		task["answering"] = true
	else:
		task["attacked"] = true
	_report(m, "%s turning on track %s, closing on it" % [a.callsign, best.id], true)
	return true


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
		# A task ended with auto-return off: the airframe holds until told to go back (S). It is
		# still on the mission: a CAP that has just identified a hostile still intercepts it, from
		# where it is holding, instead of flying on with nothing to do until bingo.
		task["state"] = AirMission.HOLDING
		_look(m, a, task)
		return
	if _keep_standoff(m, a, task):
		return
	var half := float(task.get("half", m.radius_nm)) + STATION_ARRIVAL_MARGIN_NM
	var offset := a.position - (task.get("centre", m.station) as Vector2) - _slot_offset(m, a, task)
	task["state"] = AirMission.ON_STATION if absf(offset.x) <= half and absf(offset.y) <= half else AirMission.TRANSITING
	if task["state"] == AirMission.ON_STATION and now_s >= float(task.get("broke_off_until", -INF)):
		task.erase("broke_off")
		task.erase("broke_off_until")
	if task["state"] == AirMission.ON_STATION:
		task.erase("recalled_until")
	# The mission sets the speed when the airframe's state changes (out at transit, on station at
	# patrol), not every second: a dash the commander orders on station stands until the next change.
	if str(task.get("speed_for", "")) != str(task["state"]):
		task["speed_for"] = task["state"]
		var flight_speed := a.spec.flight_speed("patrol" if task["state"] == AirMission.ON_STATION else "transit")
		if absf(a.ordered_speed_kn - flight_speed) > 0.1:
			_crew(a, Order.set_speed(flight_speed))
	a.station_speed_kn = a.spec.flight_speed("patrol")
	_look(m, a, task)


func _look(m: AirMission, a: Unit, task: Dictionary) -> void:
	match m.kind:
		AirMission.Kind.CAP:
			_cap_look(m, a, task)
		AirMission.Kind.RECON:
			_recon_look(m, a, task)
		AirMission.Kind.ASW:
			_asw_look(m, a, task)


## The station is a circuit round the chosen point, flown by the existing patrol: fuel, recovery,
## evasion and refuelling all already know how to interrupt and resume one.
func _assign_station(m: AirMission, a: Unit, task: Dictionary, centre := Vector2.INF) -> void:
	if not centre.is_finite():
		centre = m.station
	var half := maxf(station_half_nm(m.kind, m.radius_nm), (UnitManager.patrol_min_leg_nm(a) + 0.2) * 0.5)
	task["half"] = half
	task["centre"] = centre
	var own := centre + _slot_offset(m, a, task)
	var circuit := Order.patrol_box(own - Vector2(half, half), own + Vector2(half, half))
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


## Each airframe holding a station flies its own copy of the circuit, moved out along the diagonal by
## its place in the mission: a section on one station would otherwise close up on the lead after
## the launch interval and fly as one symbol all sortie. The place is taken once, the lowest free.
const SECTION_SPACING_NM := 2.0


func _slot_offset(m: AirMission, a: Unit, task: Dictionary) -> Vector2:
	if not task.has("slot"):
		var taken := {}
		for other in m.aircraft:
			if other != a and other.alive and m.tasks.has(other) and m.tasks[other].has("slot") and not bool(m.tasks[other].get("relieved", false)):
				taken[int(m.tasks[other]["slot"])] = true
		var slot := 0
		while taken.has(slot):
			slot += 1
		task["slot"] = slot
	var k := int(task["slot"])
	if k <= 0:
		return Vector2.ZERO
	var step := ceilf(k / 2.0) * SECTION_SPACING_NM
	return Vector2(step, step) if k % 2 == 1 else Vector2(-step, -step)


## An unarmed sensor aircraft flies its circuit no nearer than the stand-off to any ship the plot
## does not call friendly or neutral, and any reconnaissance airframe, once its look has told the
## plot what a ship is, keeps outside that ship's missile cover: the circuit is moved out along the
## line from the ship, and back when the ship has gone. Returns true when it was moved this second.
func _keep_standoff(m: AirMission, a: Unit, task: Dictionary) -> bool:
	if not _unarmed_fixed_wing(a) and m.kind != AirMission.Kind.RECON:
		return false
	var half := float(task.get("half", m.radius_nm))
	var centre := m.station
	var from := ""
	var kept := 0.0
	for t: Track in _nearby(m, a, INF):
		var standoff := _standoff_nm(a, t)
		var clear := standoff + half * sqrt(2.0)
		if standoff <= 0.0 or t.position.distance_to(centre) >= clear:
			continue
		var away := centre - t.position
		if away.length() < 0.01:
			away = m.base.position - t.position
		if away.length() < 0.01:
			away = Vector2(0, -1)
		centre = t.position + away.normalized() * clear
		from = t.id
		kept = standoff
	var current: Vector2 = task.get("centre", m.station)
	if centre.distance_to(current) < 2.0:
		return false
	_assign_station(m, a, task, centre)
	if from != "" and from != str(task.get("standoff_from", "")):
		_report(m, "%s keeping %.0f nm off track %s" % [a.callsign, kept, from], true)
	task["standoff_from"] = from
	return true


## How far this airframe keeps its circuit from a held contact: an unarmed sensor aircraft at
## least SENSOR_STANDOFF_NM from any ship that might shoot, anything else beyond the cover of a ship
## the plot has a class or a hostile identity for. A ship nobody has looked at yet is still the
## look's to make.
static func _standoff_nm(a: Unit, t: Track) -> float:
	if not _ship_to_avoid(t):
		return 0.0
	var cover := air_defence_standoff_nm(t)
	if _unarmed_fixed_wing(a):
		return maxf(SENSOR_STANDOFF_NM, cover)
	return cover


## An aircraft that carries sensors and nothing to fight with, and has to keep moving to fly.
static func _unarmed_fixed_wing(a: Unit) -> bool:
	return a.is_sensor_aircraft() and not a.spec.can_hover


## A held ship or installation that might shoot: not one the plot calls friendly or neutral.
static func _ship_to_avoid(t: Track) -> bool:
	if t.identity in ["FRIENDLY", "NEUTRAL"] or t.confirmed_destroyed:
		return false
	if t.domain != "":
		return t.domain in ["surface", "land"]
	return not _probably_air(t)


## Half the side of the square circuit flown on station. A CAP flies a square inscribed in its
## ring, so the circuit is the ring the chart draws; a search flies a box well inside its area so
## that what it lays and sees falls in the area.
static func station_half_nm(kind: int, radius_nm: float) -> float:
	return radius_nm / sqrt(2.0) if kind == AirMission.Kind.CAP else radius_nm * 0.6


## Air contacts near the CAP: hostiles are intercepted under the ROE, unknowns are identified.
## Identification never authorises fire: only a contact the plot already calls HOSTILE is attacked.
func _cap_look(m: AirMission, a: Unit, task: Dictionary) -> void:
	var best: Track = null
	var best_d := INF
	var attack := false
	# Just called back to its station: nothing sends it out again until it is back or BREAK_OFF_S
	# has passed, except a hostile coming in on it.
	var recalled := now_s < float(task.get("recalled_until", -INF))
	for t: Track in _nearby(m, a, INF):
		if not _probably_air(t):
			continue
		var d := _cap_priority(m, a, t)
		if t.identity == "HOSTILE":
			# One coming in on the fighter itself comes first, however many are already on it.
			var threat := threatens(a, t)
			if threat:
				d = a.position.distance_to(t.position) - 1000.0
			elif recalled or t == task.get("broke_off") or _committed(m.faction, t, true) >= INTERCEPTORS_PER_TRACK:
				continue
			if not _cap_pursues(m, a, t, COMMIT_HYSTERESIS_NM):
				continue
			if UnitManager.attack_rejection(a, t) != "":
				continue
			if not attack or d < best_d:
				best = t
				best_d = d
				attack = true
		elif not attack and not recalled and t.identity == "UNKNOWN" and t.classification < Track.Classification.CLASS_KNOWN:
			# The look is called off at the ring and the pursuit; it is sent only inside them by the
			# same gap the intercept keeps, or one at the edge is sent and recalled by turns.
			if t.position.distance_to(m.station) > m.radius_nm + m.pursuit_nm - COMMIT_HYSTERESIS_NM:
				continue
			if _committed(m.faction, t, false) > 0 or UnitManager.investigation_rejection(a, t) != "":
				continue
			if d < best_d:
				best = t
				best_d = d
	if best == null:
		return
	if attack:
		if _crew(a, Order.attack(best)):
			# An intercept is flown fast: the attack takes its speed from the order after it.
			_crew(a, Order.set_speed(a.spec.flight_speed("dash")))
			task["speed_for"] = AirMission.ENGAGING
			task["state"] = AirMission.ENGAGING
			task["attacked"] = true
			task["cap_target"] = best
			task["cap_player_generation"] = a.player_order_generation
			_report(m, "%s intercepting track %s" % [a.callsign, best.id], true)
	elif _crew(a, Order.investigate(best, true)):
		task["state"] = AirMission.INVESTIGATING
		task["cap_target"] = best
		task["cap_player_generation"] = a.player_order_generation
		_report(m, "%s identifying track %s" % [a.callsign, best.id], true)


## Held course/speed only: a closing raid outranks a nearby contact departing the protected area.
static func _cap_priority(m: AirMission, a: Unit, t: Track) -> float:
	var center := m.protected_unit.position if m.cap_intent == "protect" and m.protected_unit != null else m.station
	var range_nm := t.position.distance_to(center)
	var score := range_nm + a.position.distance_to(t.position) * 0.1
	if t.has_kinematics and t.speed_kn > 0.0 and range_nm > 0.01:
		var velocity := Geo.heading_to_vector(t.course_deg) * Geo.knots_to_nm_per_s(t.speed_kn)
		var closing := velocity.dot((center - t.position).normalized())
		if closing > 0.0:
			var cpa_time := clampf((center - t.position).dot(velocity) / maxf(velocity.length_squared(), 0.000001), 0.0, 600.0)
			var cpa := (t.position + velocity * cpa_time).distance_to(center)
			score = cpa + range_nm * 0.1 - 100.0
	return score


## The best reach of the air-to-air weapons this airframe is fitted with, or 0. The fit, not the
## rounds left: a fighter that has just fired its long-range pair still supports them.
static func aam_reach_nm(a: Unit) -> float:
	var best := 0.0
	for spec: WeaponSpec in a.weapons:
		if spec.target_types.has("air"):
			best = maxf(best, spec.max_range_nm)
	return best


## How far from its station a CAP fighter goes after a raid, its leash: the ring and the pursuit
## the commander set, and never less than its own missiles reach.
static func cap_commit_nm(m: AirMission, a: Unit) -> float:
	return maxf(m.radius_nm + m.pursuit_nm, aam_reach_nm(a))


## Whether a CAP fighter goes after this hostile air contact, and whether it keeps after one it is
## already chasing: the one test for both, so a fighter is never sent after a raid it would be
## called back from the next second. A hostile inside its own missiles' reach and closing on it is
## answered wherever the fighter is. Otherwise it goes only if it can get its shot away without
## flying beyond its leash of the station or of the group it protects, meeting the raid on its held
## course and speed, and never on one further out than a missile shot beyond that leash. One with
## rounds away on its contact supports them a missile's flight further. A `margin` above zero is
## the test for sending: it is that much stricter than the one for keeping, so nothing sent at the
## edge is recalled by the next second's plot.
static func cap_commits(m: AirMission, a: Unit, t: Track, margin := 0.0) -> bool:
	# A position worked up from bearings alone is no fix on an aircraft: it can swing tens of miles
	# from one second to the next, and nothing can be fired on it. One is not gone out to.
	if margin > 0.0 and t.bearing_only:
		return false
	if threatens(a, t, margin, CLOSING_COS if margin > 0.0 else STILL_CLOSING_COS):
		return true
	var leash := cap_commit_nm(m, a) - margin
	var shot := aam_reach_nm(a)
	if a.attack_track == t and a.attack_rounds_fired > 0 and _from_guarded(m, a.position) <= leash + shot:
		return true
	# Nothing further out than one missile shot beyond the leash: a prediction that far ahead is a
	# guess at where the raid will turn.
	if _from_guarded(m, t.position) > leash + shot:
		return false
	var shot_at := cap_shot_point(a, t)
	if not shot_at.is_finite() or _from_guarded(m, shot_at) > leash:
		return false
	# A raid that would have its shot away first is not gone out to meet: the fighter is sent only
	# when the raid is coming for what the CAP holds and can be met over it. One already sent stays
	# on it, or it would turn its tail on a raid that is about to shoot.
	if margin > 0.0 and outshoots(a, t):
		return met_over_guarded(m, t, shot_at)
	return true


## Whether a raid that would shoot first is coming for what the CAP holds and would be met over it:
## the only way a fighter is sent at one.
static func met_over_guarded(m: AirMission, t: Track, shot_at: Vector2) -> bool:
	return _closing_on_guarded(m, t) and shot_at.is_finite() and _from_guarded(m, shot_at) <= m.radius_nm


## A hostile air contact inside this airframe's own missile reach and closing on it: one that has
## fired on it, or is about to. A fighter turns to answer it whatever else it is doing. A fighter is
## sent on one only `margin` inside that reach, and kept on it out to the reach itself.
static func threatens(a: Unit, t: Track, margin := 0.0, closing_cos := CLOSING_COS) -> bool:
	if t.identity != "HOSTILE" or not _probably_air(t) or not t.has_kinematics or t.speed_kn <= 0.0:
		return false
	var d := t.position.distance_to(a.position)
	if d > aam_reach_nm(a) - margin or d < 0.01:
		return false
	return Geo.heading_to_vector(t.course_deg).dot((a.position - t.position) / d) > closing_cos


## Whether this air contact, by the class the plot gives it, would have its shot away at the fighter
## first, the two closing head on with the fighter at dash: the no-escape range of its best
## air-to-air round against the fighter beats the fighter's own against it. Both sides fire at their
## no-escape range, so this is who shoots first. A contact of no known class is not judged.
static func outshoots(a: Unit, t: Track) -> bool:
	var known := Combat._reported_platform(t)
	if known == null or not t.position.is_finite() or t.position.distance_to(a.position) < 0.01:
		return false
	var own := 0.0
	for spec: WeaponSpec in a.weapons_for_track(t):
		own = maxf(own, Combat.air_no_escape_range_nm(spec, t, a.position, Combat.effective_range_nm(a, spec)))
	# The fighter as the contact would hold it: its own type, coming straight in at dash.
	var me := Track.new()
	me.domain = "air"
	me.position = a.position
	me.has_kinematics = true
	me.course_deg = Geo.bearing_deg(a.position, t.position)
	me.speed_kn = a.spec.flight_speed("dash")
	me.classification = Track.Classification.CLASS_KNOWN
	me.known_class = a.spec.short_name
	me.known_category = a.spec.category
	var theirs := 0.0
	for wid: String in known.weapon_loadout:
		var w := DataDB.weapon(wid)
		if w != null and w.target_types.has("air") and w.type in ["aam", "sam"]:
			theirs = maxf(theirs, Combat.air_no_escape_range_nm(w, me, t.position))
	return theirs > own


## Whether a contact's held course is bringing it in on the CAP's station or the group it protects.
static func _closing_on_guarded(m: AirMission, t: Track) -> bool:
	if not t.has_kinematics or t.speed_kn <= 0.0:
		return false
	var heading := Geo.heading_to_vector(t.course_deg)
	var centres: Array[Vector2] = [m.station]
	if m.cap_intent == "protect" and m.protected_unit != null and m.protected_unit.alive:
		centres.append(m.protected_unit.position)
	for c in centres:
		var to := c - t.position
		if to.length() < 0.01 or heading.dot(to.normalized()) > CLOSING_COS:
			return true
	return false


## Distance from the nearer of the CAP's station and the group it protects.
static func _from_guarded(m: AirMission, p: Vector2) -> float:
	var d := p.distance_to(m.station)
	if m.cap_intent == "protect" and m.protected_unit != null and m.protected_unit.alive:
		d = minf(d, p.distance_to(m.protected_unit.position))
	return d


## Where this fighter would be as it fires on the contact, flying straight at dash to meet it on
## its held course and speed to the stand-off its attack closes to: where it is, when it is already
## in range. INF when nothing aboard suits the contact or the fighter cannot close on it.
static func cap_shot_point(a: Unit, t: Track) -> Vector2:
	var fire_nm := a.attack_reach_nm(t)
	if fire_nm <= 0.0:
		return Vector2.INF
	var rel := t.position - a.position
	var dist := rel.length()
	if dist <= fire_nm:
		return a.position
	var v_t := Vector2.ZERO
	if t.has_kinematics:
		v_t = Geo.heading_to_vector(t.course_deg) * Geo.knots_to_nm_per_s(t.speed_kn)
	var v_a := Geo.knots_to_nm_per_s(maxf(a.spec.flight_speed("dash"), 1.0))
	# The first time s at which |rel + v_t s| = fire_nm + v_a s.
	var qa := v_t.length_squared() - v_a * v_a
	var qb := 2.0 * (rel.dot(v_t) - fire_nm * v_a)
	var qc := dist * dist - fire_nm * fire_nm
	var s := INF
	if absf(qa) < 1e-12:
		if qb < 0.0:
			s = -qc / qb
	else:
		var disc := qb * qb - 4.0 * qa * qc
		if disc >= 0.0:
			for root in [(-qb - sqrt(disc)) / (2.0 * qa), (-qb + sqrt(disc)) / (2.0 * qa)]:
				if root > 0.0 and root < s:
					s = root
	if not is_finite(s):
		return Vector2.INF
	var meet := t.position + v_t * s
	return a.position + (meet - a.position).normalized() * v_a * s


## The CAP test with the plot's air defences added: the fighter is not sent, nor kept, where it
## would have to fly deeper into a ship's missile cover to take its shot. A contact closing on it
## inside its own reach is answered all the same.
func _cap_pursues(m: AirMission, a: Unit, t: Track, margin := 0.0) -> bool:
	if not cap_commits(m, a, t, margin):
		return false
	if threatens(a, t, margin, CLOSING_COS if margin > 0.0 else STILL_CLOSING_COS):
		return true
	var shot_at := cap_shot_point(a, t)
	return not shot_at.is_finite() or _air_defence_over(m.faction, shot_at, a.position, margin) == null


## A held ship whose air-defence cover, widened by `margin`, `point` lies inside, nearer the ship
## than `from` is, or null.
func _air_defence_over(faction: String, point: Vector2, from: Vector2, margin := 0.0) -> Track:
	if track_manager == null:
		return null
	for t: Track in track_manager.get_tracks(faction):
		if t.status == Track.Status.LOST or t.is_bearing_only() or not t.position.is_finite():
			continue
		var cover := air_defence_standoff_nm(t)
		if cover <= 0.0:
			continue
		cover += margin
		var d := point.distance_to(t.position)
		if d < cover and d < from.distance_to(t.position) - 0.1:
			return t
	return null


## How far an aircraft that has no business over it keeps from a held ship: the reach of the air
## defences the plot says it carries, and a margin. A ship the plot calls hostile with no class yet
## is taken to have an area-defence missile. One not yet looked at, or that the plot calls friendly
## or neutral, gets none: an unarmed sensor aircraft adds its own floor (`_standoff_nm`).
static func air_defence_standoff_nm(t: Track) -> float:
	if not _ship_to_avoid(t):
		return 0.0
	var known := Combat._reported_platform(t)
	if known != null:
		var reach := 0.0
		for wid: String in known.weapon_loadout:
			var w := DataDB.weapon(wid)
			if w != null and w.target_types.has("air") and not w.is_gun():
				reach = maxf(reach, w.max_range_nm)
		return reach + AIR_DEFENCE_MARGIN_NM if reach > 0.0 else 0.0
	return SENSOR_STANDOFF_NM if t.identity == "HOSTILE" else 0.0


func _enforce_cap_boundary(m: AirMission, a: Unit, task: Dictionary) -> void:
	var assigned: Track = task.get("cap_target") as Track
	if assigned == null or (a.attack_track != assigned and a.investigation_track != assigned):
		return
	# The player may temporarily override the station. Only mission-issued pursuits are bounded.
	if a.player_order_generation != int(task.get("cap_player_generation", a.player_order_generation)):
		return
	if a.attack_track == assigned:
		if _cap_pursues(m, a, assigned):
			return
	elif assigned.position.distance_to(m.station) <= m.radius_nm + m.pursuit_nm:
		return
	if _crew(a, Order.return_to_station()):
		task.erase("cap_target")
		# It does not turn back for the same contact for a while (BREAK_OFF_S), unless that
		# contact comes in on it.
		task["broke_off"] = assigned
		task["broke_off_until"] = now_s + BREAK_OFF_S
		task["recalled_until"] = now_s + BREAK_OFF_S
		task["state"] = AirMission.TRANSITING
		_report(m, "%s returning: contact outside CAP pursuit boundary" % a.callsign, true)


## Reconnaissance identifies what is in its area. It never fires: its looks are identify-only, so
## not even engagement after identification can turn one into an attack.
func _recon_look(m: AirMission, a: Unit, task: Dictionary) -> void:
	var best: Track = null
	var best_d := INF
	for t: Track in _nearby(m, a, m.radius_nm + SEARCH_MARGIN_NM):
		if t.classification >= Track.Classification.CLASS_KNOWN or _committed(m.faction, t, false) > 0:
			continue
		# A contact already hostile needs no look, and a look at a ship is close enough to be shot
		# at: an unarmed sensor aircraft leaves ships to its radar and ESM from the stand-off.
		if t.identity == "HOSTILE" or (_unarmed_fixed_wing(a) and _ship_to_avoid(t)):
			continue
		# A look from the air identifies what can be seen. A submarine contact is the ASW
		# mission's: an early-warning aircraft sent to circle one would circle it until bingo.
		if t.domain == "subsurface" and not a.has_sonar() and a.spec.sonobuoy_count <= 0:
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


## Whether this airframe's strike rounds need it to stay and guide them in.
static func _guides_its_rounds(a: Unit) -> bool:
	for spec: WeaponSpec in a.weapons:
		if (spec.target_types.has("surface") or spec.target_types.has("land")) and spec.requires_radar_support():
			return true
	return false


## A strike flies at its target on the attack task, turns for home once its salvo is away (rounds
## that need no guidance from it), and comes home in any case once the attack is over.
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


## An intercept goes for its contact at dash as soon as it is airborne and comes home once the attack
## is over: the contact destroyed, lost or out of the rounds to reach it.
func _step_intercept(m: AirMission, a: Unit, task: Dictionary) -> void:
	if bool(task.get("answering", false)):
		task.erase("answering")
		task["attacked"] = false
	if bool(task["attacked"]):
		task["state"] = AirMission.RETURNING
		_crew(a, Order.return_to_base())
		return
	var why := _intercept_target_rejection(m)
	if why == "":
		why = UnitManager.attack_rejection(a, m.target)
	if why != "":
		_report(m, "%s: %s returning — %s" % [m.label(), a.callsign, why.to_lower()], false)
		task["attacked"] = true
		task["state"] = AirMission.RETURNING
		_crew(a, Order.return_to_base())
		return
	if _crew(a, Order.attack(m.target)):
		_crew(a, Order.set_speed(a.spec.flight_speed("dash")))
		task["speed_for"] = AirMission.ENGAGING
		task["state"] = AirMission.ENGAGING
		task["attacked"] = true
		task["cap_player_generation"] = a.player_order_generation
		_report(m, "%s intercepting track %s" % [a.callsign, m.target_id], true)


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
	m.note_at_s = now_s
	mission_report.emit(m, message, good)
