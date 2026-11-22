class_name UnitManager
extends Node
## Owns all ground-truth Units and advances them on simulation ticks.

signal unit_added(unit: Unit)
signal order_issued(unit: Unit, order: Order)
signal investigation_ended(unit: Unit, track: Track, reason: String)
## An attack task finished on its own: "Target destroyed", "Contact lost", "Magazines empty",
## "Weapons hold", "Launchers damaged" or an availability reason. Replacing it with another order
## is silent, as it is for an investigation.
signal attack_ended(unit: Unit, track: Track, reason: String)
## The platform went back to its standing assignment by itself: after a task ("Contact classified",
## "Target destroyed") or after refuelling. A return the commander ordered is an ordinary order.
signal station_resumed(unit: Unit, reason: String)
## A return to station could not be made: the guide was lost, the circuit is blocked, the airframe
## is committed to recovery. The platform keeps its present orders.
signal station_unavailable(unit: Unit, reason: String)
## A task ended and the platform took up the route it had interrupted, by itself. Not raised for a
## return to station (station_resumed), nor when there was no route to go back to.
signal route_resumed(unit: Unit, reason: String)
## A hull ran out of water: held against a coast without headway, it has stopped and given up the
## leg it was on. Raised once, and not when a task was steering it: the task then ends with the
## reason "Blocked by coast" and reports through its own signal.
signal blocked_by_coast(unit: Unit)

## How far inside a weapon's reach an attacking platform settles: on the edge of the envelope a
## target that opens a few knots is out of range again before the salvo is away. GAMEPLAY.
const ATTACK_STANDOFF_FRACTION := 0.8
## A pause between salvos at the same contact, to let the plot show what the last one did.
const ATTACK_ASSESS_S := 20.0
## An attack held this long without being able to fire or close ends with the reason, rather
## than parking the platform indefinitely. GAMEPLAY.
## A standing attack closes on a stale plot for this long before giving it back. GAMEPLAY_ESTIMATE.
const ATTACK_STALE_S := 240.0
const ATTACK_STALL_S := 180.0
## A ship that has to close for an attack does so at this much of what her plant will give now,
## unless she was already ordered faster. GAMEPLAY.
const ATTACK_CLOSING_FRACTION := 0.85
## Settled inside the standoff, a platform holds the band until the range has opened this far past
## it. The weapon reaches 1.25 standoffs, so it is still in range when it turns to close again.
const ATTACK_HOLD_RELEASE := 1.12
## A fixed-wing aircraft attacking a ship or a shore target stays outside this much of the weapon's
## reach once it is in range, rather than flying on over the defences it has just woken. GAMEPLAY.
const ATTACK_HOLD_OFF_FRACTION := 0.7
## A contact making less than this is circled at the standoff; a faster one is paralleled.
const ATTACK_PARALLEL_MIN_KN := 3.0
## A boat holds her firing range no faster than this, to keep her own sonar. GAMEPLAY_ESTIMATE.
const ATTACK_QUIET_KN := 6.0
## A hull closing on its firing point counts as making way when it gains this much of the distance
## its speed should cover; pressed against a coast it gains nothing however fast the screws turn.
const ATTACK_PROGRESS_FRACTION := 0.1
## How long a helicopter stays in the dip trying to turn its own bearing into a range before it
## raises the dome and runs down the bearing instead. GAMEPLAY_ESTIMATE.
const ATTACK_LOCALISE_S := 300.0
const NO_SEA_ROUTE_TO_CONTACT := "No sea route to the contact"
const NO_SEA_ROUTE_TO_FIRE := "No sea route to a firing position"

var units: Array[Unit] = []
## The attack task fires through here. Simulation sets it; a unit manager without one can still
## steer an attack but never shoots.
var weapon_manager: WeaponManager:
	set(value):
		if weapon_manager != null and weapon_manager.unit_destroyed.is_connected(_on_unit_destroyed):
			weapon_manager.unit_destroyed.disconnect(_on_unit_destroyed)
		weapon_manager = value
		if weapon_manager != null:
			weapon_manager.unit_destroyed.connect(_on_unit_destroyed)
## Simulation time as of the last tick, for the attack task's firing checks and salvo pacing.
var now_s := 0.0
## Sides whose platforms attack a contact their own investigation has just identified as hostile,
## within the rules of engagement (the Classic option): faction -> true. Plain data the shell
## sets; a side not listed only reports what it found. Not cleared with the units: it is how the
## commander plays, not part of the scenario.
var engage_on_hostile_id: Dictionary = {}
var _next_id := 1


func add_unit(u: Unit) -> void:
	u.id = _next_id
	_next_id += 1
	units.append(u)
	unit_added.emit(u)


## `now` is the simulation clock; a caller without one (the tests) lets the manager keep its own.
func tick(dt: float, now := -1.0) -> void:
	now_s = now if now >= 0.0 else now_s + dt
	Formation.update_speed_caps(units)
	for u in units:
		if not u.alive:
			continue
		_deliver_submarine_orders(u, SubmarineComms.step(u, now_s))
		DefensiveResponse.tick(u, dt)
		_handoff_submarine_tasks(u)
		_step_investigation(u, dt)
		_step_attack(u, dt)
		# A task ended by an order rather than by its own step (fire cancelled) still hands the
		# platform back to what it was doing.
		if u.plan_kept and u.attack_track == null and u.investigation_track == null:
			_finish_task(u, u.task_generation, u.attack_result if u.attack_result != "" else u.investigation_result)
		Formation.step(u)
		var was_blocked := u.coast_blocked
		Movement.step(u, dt)
		if u.coast_blocked and not was_blocked:
			_report_blocked_by_coast(u)
		# Detach before the next sensor cycle can update the shared picture after diving.
		_handoff_submarine_tasks(u)


## A task received over the link continues on the boat's own sensor picture once it dives.
## Contact keys associate held reports; neither the shared track's new position nor hidden
## target truth is copied. Without a local report, ordinary task checks report contact loss.
func _handoff_submarine_tasks(u: Unit) -> void:
	if not SubmarineComms.restricted(u) or SubmarineComms.connected(u) or weapon_manager == null or weapon_manager.track_manager == null:
		return
	var own_picture := weapon_manager.track_manager.tracks_for(u)
	for field: String in ["attack_track", "investigation_track"]:
		var old: Track = u.get(field)
		if old == null or not old.networked:
			continue
		var key := WeaponManager.contact_key(old)
		for local: Track in own_picture:
			if WeaponManager.contact_key(local) == key:
				u.set(field, local)
				break


## A hull that Movement has just stopped against a coast. A task that was steering it ends, so it
## is not sent at the same beach on the next tick, and hands back to what it interrupted; anything
## else simply stays stopped until it is given somewhere to go.
func _report_blocked_by_coast(u: Unit) -> void:
	if u.attack_track != null:
		_end_attack(u, u.attack_track, "Blocked by coast")
	elif u.investigation_track != null:
		_end_investigation(u, u.investigation_track, "Blocked by coast")
	else:
		blocked_by_coast.emit(u)


## Why a hull cannot be sent to this point, or "". Anything that flies goes where it is told. A
## boat out of touch is judged from where it last reported, which is all the commander knows.
static func move_rejection(u: Unit, order: Order) -> String:
	if u == null or order == null or not u.needs_sea_room() or Terrain.is_empty():
		return ""
	if Terrain.is_land(order.target_pos):
		return "Destination is ashore"
	var from := u.position
	if SubmarineComms.should_queue(u, order):
		if order.append:
			return ""  # added to a route the boat has yet to be given; checked when it is delivered
		from = SubmarineComms.reported_position(u)
	elif order.append and not u.waypoints.is_empty():
		from = u.waypoints.back()
	return "" if Terrain.reachable_by_sea(from, order.target_pos) else "No sea route"


## Returns false when this platform cannot carry out the order, so group-order receipts count
## actual capability rather than merely counting living selections. Dynamic subsystem checks
## (deck spots and fire-control channels) remain with their specialist managers.
func issue_order(u: Unit, order: Order) -> bool:
	if not can_accept_order(u, order):
		# A refused shot says why, so the console can tell the commander rather than just
		# counting refusals. Each pair on a firing board carries its own Order.
		if order != null and order.type == Order.Type.ENGAGE:
			order.receipt = engage_rejection(u, order)
		elif order != null and order.type == Order.Type.SET_SPEED and u != null and u.alive and u.in_formation():
			order.receipt = station_keeping_rejection(u)
		return false
	if order.type == Order.Type.MOVE:
		var why := move_rejection(u, order)
		if why != "":
			order.receipt = why
			return false
	order.execution_accepted = true
	if SubmarineComms.should_queue(u, order):
		SubmarineComms.initialize(u, now_s)
		return SubmarineComms.queue_order(u, order)
	if not SubmarineComms.on_order(u, order, now_s):
		u.apply_order(order)
	order_issued.emit(u, order)
	return order.execution_accepted


## Apply the commander's communication rules without changing another side's behavior.
func configure_submarine_comms(faction: String, enabled: bool) -> void:
	for u in units:
		if u.faction == faction and u.is_submarine():
			_deliver_submarine_orders(u, SubmarineComms.configure(u, enabled, now_s))


func _deliver_submarine_orders(u: Unit, orders: Array[Order]) -> void:
	if orders.is_empty(): return
	var accepted := 0
	for order in orders:
		if issue_order(u, order): accepted += 1
	u.comms_note = "%d orders delivered%s" % [accepted, " · %d no longer executable" % (orders.size() - accepted) if accepted < orders.size() else ""]


## Why this platform cannot fire this ENGAGE order now, or "". The same checks the order is
## accepted on, worded for the radio line.
static func engage_rejection(u: Unit, order: Order) -> String:
	if u == null or not u.is_engageable():
		return "platform not deployed"
	var spec := u.get_weapon(order.weapon_id)
	if spec == null:
		return "%s not aboard" % order.weapon_id
	if order.track == null:
		return "no contact named"
	var check := Combat.check_engagement(u, spec, order.track)
	return "" if bool(check.get("ok", false)) else str(check.get("reason", "no firing solution")).to_lower()


static func can_accept_order(u: Unit, order: Order) -> bool:
	if u == null or order == null or not u.alive:
		return false
	# A disconnected crew cannot yet assess a newly transmitted firing or investigation
	# solution. Accept coherent instructions into the queue, then run the full checks when
	# the communication window delivers them; a lost contact is never attacked blindly.
	if SubmarineComms.should_queue(u, order) and order.type in [Order.Type.ENGAGE, Order.Type.ATTACK, Order.Type.INVESTIGATE]:
		if order.track == null or order.track.confirmed_destroyed or (order.track.owner_faction != "" and order.track.owner_faction != u.faction):
			return false
		if order.type == Order.Type.ENGAGE:
			return u.get_weapon(order.weapon_id) != null
		return u.spec.max_speed_kn > 0.0
	match order.type:
		Order.Type.SET_SUB_COMMS_INTERVAL:
			return SubmarineComms.restricted(u) and order.comms_interval_s in SubmarineComms.INTERVALS
		Order.Type.REQUEST_SUB_CHECKIN:
			return SubmarineComms.restricted(u) and u.spec.max_depth_m > 0.0
		Order.Type.ASW_SEARCH:
			return TowedArray.rejection(u) == ""
		Order.Type.RECOVER_TOWED_ARRAY:
			return TowedArray.capable(u) and (u.array_search_active or u.array_phase != TowedArray.Phase.STOWED)
		Order.Type.SNORKEL:
			return SubmarinePower.snorkel_rejection(u, order.automatic) == ""
		Order.Type.INVESTIGATE:
			return investigation_rejection(u, order.track) == ""
		Order.Type.ATTACK:
			return attack_rejection(u, order.track, order.weapon_id) == ""
		Order.Type.PATROL:
			return patrol_rejection(u, order.route) == ""
		Order.Type.RETURN_TO_STATION:
			return station_rejection(u) == ""
		Order.Type.SET_AUTO_RETURN:
			return u.is_engageable() and u.spec.max_speed_kn > 0.0
		Order.Type.SET_READY_ALERT:
			return AirMissionManager.ready_alert_rejection(u, order.aircraft_count) == ""
		Order.Type.DEPLOY_COUNTERMEASURES:
			return DefensiveResponse.can_deploy(u, order.countermeasure_kind)
		Order.Type.EVADE:
			return u.is_engageable() and u.spec.max_speed_kn > 0 and (not u.is_aircraft() or u.airborne())
		Order.Type.RESUME_PLAN, Order.Type.SET_AUTO_COUNTERMEASURES:
			return u.is_engageable()
		Order.Type.SET_AIR_DEFENCE_MODE:
			# Doctrine, not a task: an airframe in the hangar takes it too, so it holds once aloft.
			return u.alive
		Order.Type.INTERCEPT:
			# The round itself is checked by Simulation, which holds the threat picture.
			return AirDefence.intercept_rejection(u) == ""
		Order.Type.SET_DEFENCE_POLICY:
			return u.is_engageable() and order.defence_policy in ["balanced", "conserve", "saturation"]
		Order.Type.SET_SPEED:
			# Station keeping sets a consort's speed every tick; a speed of her own would be
			# overwritten at once. The group's speed is the guide's to order.
			if u.in_formation():
				return false
			# The circuit as ordered, not the points still ahead: those may include the way
			# round a coast to its first corner, which is no part of it.
			if u.patrol_active and patrol_rejection(u, u.station_route if not u.station_route.is_empty() else u.waypoints, order.speed_kn, false) != "":
				return false
			return _steerable(u)
		Order.Type.MOVE, Order.Type.SET_COURSE, Order.Type.STOP, Order.Type.CLEAR_WAYPOINTS:
			return _steerable(u)
		Order.Type.ACTIVATE_RADAR, Order.Type.SILENCE_RADAR:
			return u.is_engageable() and u.has_radar()
		Order.Type.DEPLOY_DIPPING_SONAR:
			return DippingSonar.rejection(u) == ""
		Order.Type.RECOVER_DIPPING_SONAR:
			return DippingSonar.capable(u) and u.dip_phase not in [DippingSonar.Phase.STOWED, DippingSonar.Phase.RAISING]
		Order.Type.ACTIVE_SONAR, Order.Type.PASSIVE_SONAR:
			return u.is_engageable() and u.has_sonar()
		Order.Type.CANCEL_FIRE:
			return u.alive
		Order.Type.ENGAGE:
			return engage_rejection(u, order) == ""
		Order.Type.SET_DEPTH:
			return u.is_engageable() and u.is_submarine() and u.spec.max_depth_m > 0.0
		Order.Type.SET_ALTITUDE:
			return u.airborne() and u.spec.max_altitude_m > 0.0
		Order.Type.LAUNCH_AIRCRAFT:
			return not u.stowed_aircraft().is_empty()
		Order.Type.AIR_MISSION:
			# The deck's own checks, and the reasons, are AirMissionManager's.
			return u.is_engageable() and u.spec.aircraft_capacity > 0
		Order.Type.CANCEL_AIR_MISSION:
			return u.alive
		Order.Type.GROUP_ATTACK:
			# Given to one member, the lead. The shooters' own checks, and the reasons, are
			# GroupAttackManager's.
			return u.is_engageable() and order.group_members.has(u) and not order.group_targets.is_empty()
		Order.Type.CANCEL_GROUP_ATTACK:
			return u.alive
		Order.Type.RETURN_TO_BASE:
			# Checked here, before the order is applied, so a landing that cannot be made leaves the
			# station and the order generation as they were.
			return u.airborne() and (order.recovery_base == null or AviationManager.recovery_rejection_reason(u, order.recovery_base) == "")
		Order.Type.DEPLOY_SONOBUOY:
			return u.airborne() and u.sonobuoys > 0 and u.spec.sonobuoy_sensitivity_nm > 0.0 and not Terrain.is_land(u.position)
		Order.Type.SET_EMCON:
			return u.is_engageable() and (u.has_radar() or u.has_sonar() or u.has_jammer())
		Order.Type.FORM_UP:
			return Formation.can_join(u, order.leader)
		Order.Type.BREAK_FORMATION, Order.Type.SET_ROE:
			return u.is_engageable()
	return false


## Why a consort in formation refuses a speed of her own.
static func station_keeping_rejection(u: Unit) -> String:
	return "Keeping station on %s: order the guide's speed" % u.formation_leader.callsign


## Steering a platform can take now. An aircraft on its way to the deck or the tanker is the aviation
## layer's: a course or speed given to it would be overwritten within the second, so it is refused.
static func _steerable(u: Unit) -> bool:
	if not u.is_engageable() or u.spec.max_speed_kn <= 0.0:
		return false
	return not u.is_aircraft() or (u.airborne() and not u.returning and u.tanking_on == null)


## Why this platform cannot go back to its standing assignment now, or "" when it can. The circuit
## is checked again from where the platform is now; a formation station needs a guide still afloat.
static func station_rejection(u: Unit) -> String:
	if u == null or not u.alive or not u.is_engageable() or u.spec.max_speed_kn <= 0.0:
		return "Select a deployed mobile platform"
	if u.is_aircraft() and (not u.airborne() or u.returning or u.tanking_on != null):
		return "Aircraft committed to fuel or recovery"
	match u.station_kind:
		"patrol":
			var reason := patrol_rejection(u, u.station_circuit_from_here(), u.station_speed())
			return "" if reason == "" else "Station unavailable: " + reason.to_lower()
		"formation":
			if u.station_leader == null or not u.station_leader.alive:
				return "Formation guide lost"
			if not Formation.can_join(u, u.station_leader):
				return "Formation guide not available"
			return ""
	return "No station assigned"


## Hands a platform back to its standing assignment as the crew's own order, so the receipt, the
## log and the specialist managers see it like any other. False, with the reason reported, when the
## station cannot be taken up; the platform then keeps what it was doing.
func resume_station(u: Unit, reason: String) -> bool:
	var why := station_rejection(u)
	if why != "":
		u.station_note = why
		station_unavailable.emit(u, why)
		return false
	var order := Order.return_to_station()
	order.origin = "crew"
	if not issue_order(u, order):
		return false
	station_resumed.emit(u, reason)
	return true


## After a task ends, for whatever reason: the platform goes back to what the task interrupted,
## unless a newer order arrived while it ran. `started` is the generation the task began under.
## The station first, when the platform is told to return to it by itself; otherwise the route it
## was on; with neither, a hull keeps her way on and an aircraft holds (Unit.resume_plan). A task
## that never took the steering interrupted nothing, and the platform is still on its own orders.
func _finish_task(u: Unit, started: int, reason: String) -> void:
	if not u.alive or u.order_generation != started:
		u.forget_plan()
		return
	if u.auto_return and u.has_station() and not u.on_station() and resume_station(u, reason):
		return
	if u.plan_kept:
		u.resume_plan()
		if u.has_route():
			route_resumed.emit(u, reason)
	elif Movement.must_keep_flying(u) and u.waypoints.is_empty():
		# On a bare course with nowhere to go: hold here rather than fly it to the end of the fuel.
		Movement.enter_hold(u, u.position)


## Uses only information held by this unit's faction, including datalink visibility. An
## investigation never obtains a hidden position or an early classification from Track.truth.
## `planning` is the question asked when the order is given: it also looks for the way by sea. The
## task's own step asks without it every tick and finds the way as it steers.
static func investigation_rejection(u: Unit, track: Track, planning := true) -> String:
	if u == null or not u.alive or not u.is_engageable() or u.spec.max_speed_kn <= 0.0:
		return "Select a deployed mobile platform"
	if u.is_aircraft() and (not u.airborne() or u.returning or u.tanking_on != null):
		return "Aircraft must be airborne and available for tasking"
	if track == null or (track.owner_faction != "" and track.owner_faction != u.faction):
		return "Contact is not available to this unit"
	if track.confirmed_destroyed:
		return "Target destroyed"
	if track.status == Track.Status.LOST:
		return "Contact lost"
	if not track.visible_to(u):
		return "Contact is not available to this unit"
	if track.is_bearing_only():
		return "Contact range unresolved"
	# A probable class from an emitter or a sound is not an identity: a contact still UNKNOWN is
	# worth closing to look at whatever the library made of it.
	if track.classification >= Track.Classification.CLASS_KNOWN and track.identity != "UNKNOWN":
		return "Contact classified"
	if not track.position.is_finite():
		return "Contact position unavailable"
	if u.needs_sea_room() and Terrain.is_land(track.position):
		return "Land blocks investigation — choose another course"
	if planning and u.needs_sea_room() and not Terrain.reachable_by_sea(u.position, track.position):
		return NO_SEA_ROUTE_TO_CONTACT
	return ""


func _step_investigation(u: Unit, dt: float) -> void:
	var track := u.investigation_track
	if track == null:
		return
	# Aviation may take over automatically for fuel. Do not overwrite its return/tanker route.
	if u.is_aircraft() and (not u.airborne() or u.returning or u.tanking_on != null):
		u.clear_investigation()
		return
	var reason := investigation_rejection(u, track, false)
	if reason != "":
		_end_investigation(u, track, reason)
		return
	if u.evasion_remaining_s > 0.0:
		return
	# A task may wait at the last plot and then follow a later update. Keep the player's chosen
	# transit speed separately because ordinary waypoint arrival commands zero speed.
	var arrive := maxf(Movement.ARRIVAL_MIN_NM, Geo.knots_to_nm_per_s(u.speed_kn) * dt * 2.0)
	if u.position.distance_to(track.position) <= arrive:
		_hold_investigation_position(u)
		if track.domain == "subsurface" and TowedArray.rejection(u) == "":
			var search := Order.asw_search()
			search.origin = "crew"
			issue_order(u, search)
		if track.domain == "subsurface" and DippingSonar.rejection(u) == "":
			var dip := Order.deploy_dipping_sonar(180.0)
			dip.origin = "crew"
			issue_order(u, dip)
	elif u.steer_for(track.position):
		u.ordered_speed_kn = u.investigation_speed_kn
	else:
		_end_investigation(u, track, NO_SEA_ROUTE_TO_CONTACT)


func _end_investigation(u: Unit, track: Track, reason: String) -> void:
	var started := u.task_generation
	var identify_only := u.investigation_identify_only
	u.investigation_track = null
	u.investigation_result = reason
	investigation_ended.emit(u, track, reason)
	if reason == "Contact classified" and not identify_only and _engage_identified(u, track, started):
		return  # the attack inherits the interrupted plan and hands back to it when it ends
	_finish_task(u, started, reason)


func set_engage_on_hostile_id(faction: String, on: bool) -> void:
	if on:
		engage_on_hostile_id[faction] = true
	else:
		engage_on_hostile_id.erase(faction)


## Engagement after identification: when the side has chosen it, a platform whose investigation
## has just classified its contact as hostile attacks it, as the crew's own order. Only a contact
## the plot calls HOSTILE, never an unknown or a neutral; only when the rules of engagement and a
## suitable weapon allow it (attack_rejection, the same test a commander's attack order meets);
## never over an order that arrived while the investigation ran. An identify-only look (an air
## mission's) never gets here, and an airframe on a reconnaissance station never fires this way,
## even after a look the commander ordered.
func _engage_identified(u: Unit, track: Track, started: int) -> bool:
	if not bool(engage_on_hostile_id.get(u.faction, false)) or u.station_identify_only:
		return false
	if track.identity != "HOSTILE" or u.order_generation != started:
		return false
	if attack_rejection(u, track) != "":
		return false
	var order := Order.attack(track)
	order.origin = "crew"
	return issue_order(u, order)


static func _hold_investigation_position(u: Unit) -> void:
	u.waypoints.clear()
	u.ordered_heading_deg = u.heading_deg
	# A fixed-wing aircraft cannot hover at a contact plot. It holds where it is: a racetrack
	# through its present position, instead of flying on along its heading until it ran out of
	# fuel; while the task remains active, later ticks bring it back toward the held plot.
	if Movement.must_keep_flying(u):
		Movement.enter_hold(u, u.position)
	else:
		u.ordered_speed_kn = 0.0


# --- The attack task ---------------------------------------------------------------------

## Why this platform cannot take an attack order on this contact, or "" when it can. Uses only
## what the unit's faction holds: the plot's position, identity and classification. A named
## weapon must be aboard, loaded and suited to the contact; otherwise the best one is chosen later.
static func attack_rejection(u: Unit, track: Track, weapon_id := "") -> String:
	if u == null or not u.alive or not u.is_engageable():
		return "Select a deployed platform"
	if u.weapons.is_empty():
		return "No weapons aboard"
	if u.is_aircraft() and (not u.airborne() or u.returning or u.tanking_on != null):
		return "Aircraft must be airborne and available for tasking"
	if track == null or (track.owner_faction != "" and track.owner_faction != u.faction):
		return "Contact is not available to this unit"
	if track.confirmed_destroyed:
		return "Target destroyed"
	if track.status == Track.Status.LOST:
		return "Contact lost"
	if not track.visible_to(u):
		return "Contact is not available to this unit"
	if track.identity in ["NEUTRAL", "FRIENDLY"]:
		return "Protected identity"
	if u.roe == Unit.Roe.HOLD:
		return "Weapons hold"
	if u.roe == Unit.Roe.TIGHT and track.identity != "HOSTILE":
		return "Identify contact first (weapons tight)"
	if not track.position.is_finite():
		return "Contact position unavailable"
	if track.domain == "":
		return "Identify contact first"
	if weapon_id != "":
		var spec := u.get_weapon(weapon_id)
		if spec == null:
			return "Weapon not aboard"
		if not Combat.suits_track(spec, track):
			return "Wrong weapon for contact"
		if u.magazine_count(weapon_id) <= 0:
			return "Magazine empty"
		if track.is_bearing_only() and not spec.is_torpedo():
			return "Contact range unresolved"
		return ""
	var suitable := u.weapons_for_track(track)
	if suitable.is_empty():
		var any_fit := false
		for spec: WeaponSpec in u.weapons:
			if Combat.suits_track(spec, track):
				any_fit = true
				break
		return "Magazines empty" if any_fit else "No suitable weapon aboard"
	if track.is_bearing_only():
		for spec: WeaponSpec in suitable:
			if spec.is_torpedo():
				return ""
		return "Contact range unresolved"
	return ""


## One step of the standing attack. Rounds in flight are left to arrive; then the shot is checked
## again, the best weapon chosen and fired when the envelope allows. The platform is steered only
## when it has to be: in reach it fires from wherever its own orders have it, in its screen station
## or along its route, and the task takes the steering only to close, open, unmask or clear the
## line of fire. The contact's position is the held plot.
func _step_attack(u: Unit, dt: float) -> void:
	var track := u.attack_track
	if track == null:
		return
	# Aviation may take over automatically for fuel. Do not overwrite its return/tanker route.
	if u.is_aircraft() and (not u.airborne() or u.returning or u.tanking_on != null):
		u.clear_attack()
		return
	var away := _rounds_away(u, track)
	var reason := attack_rejection(u, track, u.attack_weapon_id)
	# Empty racks do not end support for the final salvo. All other refusals (ROE, lost
	# contact, a reported kill) still end the task immediately.
	if reason != "" and not (away > 0 and reason in ["Magazine empty", "Magazines empty"]):
		_end_attack(u, track, reason)
		return
	u.attack_stale_s = u.attack_stale_s + dt if track.status != Track.Status.ACTIVE else 0.0
	if u.attack_stale_s >= ATTACK_STALE_S:
		_end_attack(u, track, "Contact stale: no fresh plot to fire on")
		return
	if u.evasion_remaining_s > 0.0:
		return  # evasion outranks the task and hands back to it afterwards
	if _localise_from_the_dip(u, track, dt):
		return
	if away > 0:
		u.attack_phase = "Engaging track · %d round%s away" % [away, "" if away == 1 else "s"]
		u.attack_assess_until_s = -1.0
		_keep_geometry(u, track, u.attack_standoff_nm, dt)
		return
	if u.attack_rounds_fired > 0:
		# The salvo has arrived. Read the plot for a moment before spending more.
		if u.attack_assess_until_s < 0.0:
			u.attack_assess_until_s = now_s + ATTACK_ASSESS_S
		if now_s < u.attack_assess_until_s:
			u.attack_phase = "Engaging track · assessing"
			_keep_geometry(u, track, u.attack_standoff_nm, dt)
			return
	var solution := _attack_solution(u, track)
	var spec: WeaponSpec = solution["spec"]
	if spec == null:
		_end_attack(u, track, "Magazines empty")
		return
	var standoff := u.attack_reach_nm(track, spec.id)
	if track.status != Track.Status.ACTIVE:
		# Seeking a fresh report is bounded independently of weapon range, guidance or
		# movement. A launcher refusal must not turn stale-contact pursuit into an endless task.
		u.attack_phase = "Intercept track · contact stale"
		_steer_attack(u, track, standoff, dt)
		return
	var check: Dictionary = solution["check"]
	if bool(check["ok"]):
		var salvo := mini(maxi(spec.salvo_default, 1), u.magazine_count(spec.id))
		if weapon_manager != null and weapon_manager.launch(u, spec, track, salvo, now_s):
			u.attack_rounds_fired += salvo
			u.attack_assess_until_s = -1.0
			u.attack_stall_s = 0.0
			u.attack_standoff_nm = standoff
			u.attack_phase = "Engaging track"
			_keep_geometry(u, track, u.attack_standoff_nm, dt)
		else:
			u.attack_phase = "Engaging track · awaiting launcher"
		return
	var why := str(check["reason"])
	var range_nm := u.position.distance_to(track.position)
	# Where the platform is steering to get its shot, when it is steering for one.
	var goal := Vector2.INF
	match why:
		"MOUNT MASKED / ATTACK TO UNMASK":
			u.attack_phase = "Turning to engage"
			u.take_steering()
			u.waypoints.clear()
			u.ordered_heading_deg = float(check.get("unmask_heading_deg", u.heading_deg))
			u.ordered_speed_kn = minf(u.spec.cruise_speed_kn, maxf(u.attack_speed_kn, 5.0))
			u.attack_stall_s = 0.0
			u.attack_progress_pos = u.position
			return
		"OUT OF RANGE", "BEARING ONLY / NO RANGE SOLUTION", "NO INTERCEPT SOLUTION", "TARGET CAN OUTRUN THE SHOT", "NO RADAR FIX ON AIRCRAFT":
			u.attack_phase = "Intercept track"
			goal = _steer_attack(u, track, standoff, dt)
		"INTERCEPT BEYOND WEAPON RANGE":
			# In reach of the plot but not of where the contact will be: it is opening. Keep
			# closing on it rather than holding at a standoff the lead point never enters.
			u.attack_phase = "Intercept track"
			goal = _steer_attack(u, track, maxf(range_nm * 0.5, spec.min_range_nm * 1.5 + 0.5), dt)
		"NO LINE OF FIRE":
			# Land between the shooter and the round's path: move to water with an open line.
			goal = _clearing_point(u, track, standoff)
			if not goal.is_finite() or u.spec.max_speed_kn <= 0.0:
				_end_attack(u, track, "No line of fire")
				return
			u.attack_phase = "Intercept track · clearing the line of fire"
			u.take_steering()
			u.attack_holding = false
			if not u.steer_for(goal):
				_end_attack(u, track, NO_SEA_ROUTE_TO_FIRE)
				return
			u.ordered_speed_kn = _closing_speed(u, track)
		"TOO CLOSE":
			u.attack_phase = "Opening to range"
			goal = _steer_attack(u, track, maxf(spec.min_range_nm * 1.5, 1.0), dt, true)
		"MAGAZINE EMPTY":
			_end_attack(u, track, "Magazines empty")
			return
		"LAUNCHERS DAMAGED":
			_end_attack(u, track, "Launchers damaged")
			return
		"WEAPONS HOLD":
			_end_attack(u, track, "Weapons hold")
			return
		"TRACK LOST":
			_end_attack(u, track, "Contact lost")
			return
		_:
			# Fire control saturated, guidance unavailable: hold the geometry and try again.
			u.attack_phase = "Attack track · " + why.to_lower()
			_keep_geometry(u, track, standoff, dt)
	_count_stall(u, track, goal, why, dt)


## Unable to fire and getting no nearer to being able to: after a while, say why and stop. With
## somewhere to steer for, what counts is the platform's own way toward it, measured from where it
## was a tick ago, so a hull held against a coast stalls although its engines are turning and it
## still has a route, and a long stern chase of a contact that is opening does not. A hull still
## coming round onto the bearing is given the time to do it.
func _count_stall(u: Unit, track: Track, goal: Vector2, why: String, dt: float) -> void:
	if u.attack_track != track:
		return  # the step that chose the goal has already ended the task
	var before := u.attack_progress_pos
	u.attack_progress_pos = u.position
	if goal.is_finite():
		if not before.is_finite():
			return
		# Rounding a headland the hull may be opening from its firing point for a while: on a sea
		# route, the way it is making is measured to the point it is steering for.
		var mark: Vector2 = u.waypoints[0] if u.on_sea_route() else goal
		var gained := before.distance_to(mark) - u.position.distance_to(mark)
		if gained >= Geo.knots_to_nm_per_s(maxf(u.speed_kn, 1.0)) * dt * ATTACK_PROGRESS_FRACTION:
			u.attack_stall_s = 0.0
			return
		if u.speed_kn >= 2.0 and absf(Geo.heading_delta(u.heading_deg, Geo.bearing_deg(u.position, mark))) > 60.0:
			return
	u.attack_stall_s += dt
	if u.attack_stall_s >= ATTACK_STALL_S:
		_end_attack(u, track, "Cannot engage: " + why.to_lower())


## A helicopter in the dip, ordered to attack a contact its own set holds as a bearing with no
## range: it stays where it is and pings for the range (unless emissions are silenced, when it
## keeps listening), and fires from the hover once the plot is worth a torpedo. True while it does.
## The plotted position of such a contact is a guess along the line, often miles beyond a boat
## that is close aboard; leaving the dip to fly there gives up the contact for nothing.
func _localise_from_the_dip(u: Unit, track: Track, dt: float) -> bool:
	if not DippingSonar.holds_bearing(u, track):
		if u.attack_phase.begins_with("Attack track · localising"):
			u.attack_stall_s = 0.0
			u.attack_phase = "Intercept track"
		return false
	u.attack_stall_s += dt
	if u.attack_stall_s >= ATTACK_LOCALISE_S:
		# No range to be had from here: up dome, and run down the bearing as any other platform would.
		u.attack_stall_s = 0.0
		u.attack_phase = "Intercept track"
		DippingSonar.recover(u)
		return false
	if not u.active_sonar_on and u.emcon != Unit.Emcon.SILENT:
		var ping := Order.active_sonar()
		ping.origin = "crew"
		issue_order(u, ping)
	u.attack_phase = "Attack track · localising, sonar %s" % ("active" if u.active_sonar_on else "passive")
	return true


## The weapon the attack would fire now: the named one, else the first that can be fired in the
## order weapons_for_track ranks them (longest reach first, guns last). When none can, the most
## preferred one's refusal decides what the platform does about it.
func _attack_solution(u: Unit, track: Track) -> Dictionary:
	var candidates: Array[WeaponSpec] = []
	if u.attack_weapon_id != "":
		var named := u.get_weapon(u.attack_weapon_id)
		if named != null and u.magazine_count(named.id) > 0:
			candidates.append(named)
	else:
		candidates = u.weapons_for_track(track)
		if track.is_bearing_only():
			# Only a torpedo can run down a bearing; preferring a longer-reach rocket would park the
			# platform outside torpedo range waiting for a range it does not have.
			candidates = candidates.filter(func(spec: WeaponSpec) -> bool: return spec.is_torpedo())
	var first: WeaponSpec = null
	var first_check := {}
	for spec: WeaponSpec in candidates:
		var check := weapon_manager.engagement_check(u, spec, track, now_s) if weapon_manager != null else Combat.check_engagement(u, spec, track)
		if bool(check["ok"]):
			return {"spec": spec, "check": check}
		if first == null:
			first = spec
			first_check = check
	return {"spec": first, "check": first_check}


## Own rounds queued or flying at this contact.
func _rounds_away(u: Unit, track: Track) -> int:
	if weapon_manager == null:
		return 0
	var count := 0
	for spec: WeaponSpec in u.weapons:
		count += weapon_manager.committed_rounds(u, spec, track)
	return count


## Whether this platform stands off from this contact rather than closing over it: a fixed-wing
## aircraft against a ship or a shore target, whose defences reach up.
static func _stands_off(u: Unit, track: Track) -> bool:
	return u.is_aircraft() and not u.spec.can_hover and track.domain in ["surface", "land"]


## The speed of a leg flown or sailed to get a shot.
static func _closing_speed(u: Unit, track: Track) -> float:
	if u.is_aircraft() and not u.spec.can_hover:
		# An intercept is flown fast; no attack is flown below the cruise.
		return u.spec.flight_speed("dash") if track.domain == "air" else maxf(u.attack_speed_kn, u.spec.cruise_speed_kn)
	return u.attack_speed_kn


## The point the platform steers for when land masks its shot. The one it is already making for
## stands while it still serves, so the search runs when the picture changes and not every tick.
func _clearing_point(u: Unit, track: Track, standoff_nm: float) -> Vector2:
	var by_sea := u.needs_sea_room()
	if u.attack_phase.ends_with("clearing the line of fire") and (u.on_sea_route() or u.waypoints.size() == 1):
		# The point at the end of the way already laid, whether that is one leg or several.
		var current: Vector2 = u.waypoints.back()
		var in_reach := current.distance_to(track.position) <= standoff_nm / ATTACK_STANDOFF_FRACTION
		if in_reach and Terrain.first_land_contact(current, track.position) < 0.0 and (not by_sea or u.on_sea_route() or Terrain.sea_leg_clear(u.position, current)):
			return current
	return Combat.clear_standoff_point(u.position, track.position, standoff_nm, by_sea)


## With rounds away, a salvo being assessed or the fire control busy, there is nothing to close
## for. A platform the attack is already steering keeps its range; one that is not carries on with
## its own orders, except that a fixed-wing aircraft which has released is turned away before
## those orders carry it in over the target.
func _keep_geometry(u: Unit, track: Track, standoff_nm: float, dt: float) -> void:
	if u.plan_kept:
		_steer_attack(u, track, standoff_nm, dt)
	elif u.attack_rounds_fired > 0 and _stands_off(u, track):
		var floor_nm := _hold_off_floor_nm(standoff_nm)
		if u.position.distance_to(track.position) <= floor_nm + _turn_room_nm(u):
			u.take_steering()
			u.attack_holding = true
			_hold_off(u, track, floor_nm)


## Steer to the standoff distance along the bearing to the plot, or keep it once there. Returns
## the point being steered for, or Vector2.INF when the platform is in the band. A platform that
## is already in reach and that the attack is not steering is left to its own orders. `opening`
## steers out to the standoff from inside it, for a weapon's minimum range.
func _steer_attack(u: Unit, track: Track, standoff_nm: float, dt: float, opening := false) -> Vector2:
	if u.spec.max_speed_kn <= 0.0:
		return Vector2.INF  # an installation ashore attacks from where it stands
	var range_nm := u.position.distance_to(track.position)
	var arrive := maxf(Movement.ARRIVAL_MIN_NM, Geo.knots_to_nm_per_s(u.speed_kn) * dt * 2.0)
	if opening and range_nm < standoff_nm:
		u.take_steering()
		u.attack_holding = false
		var out := Combat.standoff_point(u.position, track.position, standoff_nm + arrive)
		if not u.steer_for(out):
			u.waypoints.assign([out])  # a short leg outward: the stall guard ends it if the coast does
		u.ordered_speed_kn = maxf(u.attack_speed_kn, u.spec.cruise_speed_kn)
		return out
	var band := standoff_nm * (ATTACK_HOLD_RELEASE if u.attack_holding else 1.0) + arrive
	if standoff_nm <= 0.0 or range_nm <= band:
		if u.plan_kept:
			u.attack_holding = true
			_hold_band(u, track, standoff_nm)
		return Vector2.INF
	u.take_steering()
	u.attack_holding = false
	var goal := Combat.standoff_point(u.position, track.position, standoff_nm)
	if not u.steer_for(goal):
		_end_attack(u, track, NO_SEA_ROUTE_TO_FIRE)
		return Vector2.INF
	u.ordered_speed_kn = _closing_speed(u, track)
	return goal


## Inside the standoff with the steering: keep the range without stopping. A helicopter hovers. A
## fixed-wing aircraft holds off a ship or a shore target and otherwise flies on and comes round
## again. A hull keeps way on: alongside a contact that is moving, round one that is not, turning
## in or out as the range drifts, so she can still answer her helm, is not a sitting target, and
## neither creeps in on the contact nor hunts back and forth across the edge of the band.
func _hold_band(u: Unit, track: Track, standoff_nm: float) -> void:
	if u.is_aircraft():
		if _stands_off(u, track):
			_hold_off(u, track, _hold_off_floor_nm(standoff_nm))
			return
		u.waypoints.clear()
		u.ordered_heading_deg = u.heading_deg
		u.ordered_speed_kn = 0.0 if u.spec.can_hover else maxf(u.attack_speed_kn, u.spec.cruise_speed_kn)
		return
	var toward := Geo.bearing_deg(u.position, track.position)
	var range_nm := u.position.distance_to(track.position)
	# How far outside the standoff, as a fraction of a tenth of it. Inside it there is nothing to
	# correct: the weapon reaches, and opening out to the edge of its range would gain nothing.
	var error := clampf((range_nm - standoff_nm) / maxf(standoff_nm * 0.1, 0.5), 0.0, 1.0) if standoff_nm > 0.0 else 0.0
	var speed := u.attack_speed_kn
	if not u.attack_speed_ordered:
		speed = minf(u.spec.cruise_speed_kn, ATTACK_QUIET_KN if u.is_submarine() else u.attack_speed_kn)
	var course := 0.0
	if track.domain == "air":
		# Nothing a hull does keeps station on an aircraft: she holds the course she is on.
		course = u.ordered_heading_deg
		error = 0.0
	elif track.has_kinematics and track.speed_kn >= ATTACK_PARALLEL_MIN_KN:
		course = track.course_deg
		if not u.attack_speed_ordered:
			var ceiling := u.spec.cruise_speed_kn if u.is_submarine() else u.attack_speed_kn
			speed = clampf(track.speed_kn + error * 5.0, minf(ATTACK_PARALLEL_MIN_KN, ceiling), ceiling)
	else:
		# Abeam of the contact, on the side that is the smaller turn from the course already ordered.
		var to_starboard := absf(Geo.heading_delta(u.ordered_heading_deg, toward + 90.0))
		var to_port := absf(Geo.heading_delta(u.ordered_heading_deg, toward - 90.0))
		course = toward + (90.0 if to_starboard <= to_port else -90.0)
	# Which way, and how far, the contact lies from that course: turn in toward it when too far out.
	var off := Geo.heading_delta(course, toward)
	course += signf(off) * minf(absf(off), 60.0 * error)
	course = Terrain.open_bearing_deg(u.position, fposmod(course, 360.0), maxf(2.0, speed * 0.1))
	u.waypoints.clear()
	u.ordered_heading_deg = course
	u.ordered_speed_kn = speed


## How close a fixed-wing aircraft lets itself come to a ship or shore target it is attacking.
static func _hold_off_floor_nm(standoff_nm: float) -> float:
	return ATTACK_HOLD_OFF_FRACTION * standoff_nm / ATTACK_STANDOFF_FRACTION


## The radius of the turn this aircraft is flying, which is the room it needs to turn away in.
static func _turn_room_nm(u: Unit) -> float:
	return Geo.knots_to_nm_per_s(u.speed_kn) / deg_to_rad(maxf(u.spec.turn_rate_deg_s, 0.1))


## A racetrack on the aircraft's own side of the contact, its long legs across the bearing and the
## pattern laid away from the contact, no nearer to it than `floor_nm`. An aircraft already inside
## that opens out to it. The pattern is laid again when the contact has moved in on it, or when
## Movement has re-laid it along whatever heading the aircraft arrived on.
func _hold_off(u: Unit, track: Track, floor_nm: float) -> void:
	if u.holding():
		var clear := true
		for p: Vector2 in u.waypoints:
			if p.distance_to(track.position) < floor_nm:
				clear = false
				break
		if clear:
			return
	var range_nm := u.position.distance_to(track.position)
	var outward := Geo.bearing_deg(track.position, u.position) if range_nm > 0.001 else fposmod(u.heading_deg + 180.0, 360.0)
	var centre := track.position + Geo.heading_to_vector(outward) * maxf(range_nm, floor_nm + _turn_room_nm(u))
	Movement.enter_hold(u, centre, fposmod(outward - 90.0, 360.0))


func _end_attack(u: Unit, track: Track, reason: String) -> void:
	var started := u.task_generation
	u.attack_track = null
	u.attack_phase = ""
	u.attack_result = reason
	u.attack_assess_until_s = -1.0
	u.attack_holding = false
	attack_ended.emit(u, track, reason)
	_finish_task(u, started, reason)


## The plot does not expire a track just because the ship under it sank, so the attack is ended
## here, by the manager that owns the ground truth, for every platform attacking that unit. The
## task's own steps never read the association; this is the one place it is consulted.
func _on_unit_destroyed(target: Unit, _killer_faction: String) -> void:
	for u in units:
		if u.alive and u.attack_track != null and u.attack_track.truth == target:
			_end_attack(u, u.attack_track, "Target destroyed")


## Validate the entire circuit before changing any standing order. No partial patrol over land.
## `approach` also asks for a way by sea from where the platform is to the first corner.
static func patrol_rejection(u: Unit, points: Array[Vector2], speed_kn := -1.0, approach := true) -> String:
	if u == null or not u.alive or not u.is_engageable() or u.spec.max_speed_kn <= 0.0:
		return "Select a deployed mobile platform"
	if u.is_aircraft() and (not u.airborne() or u.returning or u.tanking_on != null):
		return "Aircraft must be airborne and available for tasking"
	if points.size() < 3 or points.size() > 16:
		return "A patrol needs 3 to 16 corners"
	for p: Vector2 in points:
		if not p.is_finite():
			return "Invalid patrol position"
	var minimum_leg := patrol_min_leg_nm(u, speed_kn)
	for i in points.size():
		var p := points[i]
		var next := points[(i + 1) % points.size()]
		if p.distance_to(next) + 0.001 < minimum_leg:
			return "Patrol legs need %.1f NM for this platform's turning room" % minimum_leg
		if u.needs_sea_room() and (Terrain.is_land(p) or Terrain.first_land_contact(p, next) >= 0.0):
			return "Patrol crosses land — choose open water"
	if approach and u.needs_sea_room() and not Terrain.reachable_by_sea(u.position, points[0]):
		return "No sea route to this patrol"
	return ""


static func patrol_min_leg_nm(u: Unit, speed_kn := -1.0) -> float:
	var speed := maxf(u.spec.cruise_speed_kn, minf(u.ordered_speed_kn if speed_kn < 0.0 else speed_kn, u.effective_max_speed()))
	var radius := Geo.knots_to_nm_per_s(speed) / deg_to_rad(maxf(u.spec.turn_rate_deg_s, 0.1))
	if u.needs_sea_room():
		radius = maxf(radius, u.spec.length_m * (1.5 if u.is_submarine() else 2.5) / 1852.0)
	# An aircraft must be able to reverse between successive sides without circling a corner
	# forever. Include the arrival tolerance on both ends and round the displayed limit up.
	return maxf(1.0, ceilf((2.0 * radius + 2.0 * Movement.ARRIVAL_MIN_NM) * 10.0) / 10.0)


func get_faction_units(faction: String) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if u.faction == faction and u.alive:
			out.append(u)
	return out


## Units a sensor could find or a weapon could reach. Aircraft in a hangar are neither.
func get_engageable_units(faction: String) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if u.faction == faction and u.is_engageable():
			out.append(u)
	return out


func clear() -> void:
	# Units are RefCounted. A carrier owns its air wing, and each airframe owns a
	# reference to its carrier; dropping the array alone leaks both on every restart.
	for u in units:
		u.clear_investigation()
		u.clear_attack()
		u.home = null
		u.recovery_base = null
		u.embarked.clear()
		u.inbound_aircraft.clear()
		u.formation_leader = null
		u.station_leader = null
		u.tanking_on = null
		u.comms_pending.clear()
		Detection.jammers.erase(u)
	units.clear()
	_next_id = 1
	now_s = 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		clear()
