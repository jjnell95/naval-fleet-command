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

## How far inside a weapon's reach an attacking platform settles: on the edge of the envelope a
## target that opens a few knots is out of range again before the salvo is away. GAMEPLAY.
const ATTACK_STANDOFF_FRACTION := 0.8
## A pause between salvos at the same contact, to let the plot show what the last one did.
const ATTACK_ASSESS_S := 20.0
## An attack held this long without being able to fire or close ends with the reason, rather
## than parking the platform indefinitely. GAMEPLAY.
const ATTACK_STALL_S := 180.0

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
		Formation.step(u)
		Movement.step(u, dt)
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


## Returns false when this platform cannot carry out the order, so group-order receipts count
## actual capability rather than merely counting living selections. Dynamic subsystem checks
## (deck spots and fire-control channels) remain with their specialist managers.
func issue_order(u: Unit, order: Order) -> bool:
	if not can_accept_order(u, order):
		return false
	if order.type == Order.Type.MOVE and u.needs_sea_room() and Terrain.is_land(order.target_pos):
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


static func can_accept_order(u: Unit, order: Order) -> bool:
	if u == null or order == null or not u.alive:
		return false
	# A disconnected crew cannot yet assess a newly transmitted firing or investigation
	# solution. Accept coherent instructions into the queue, then run the full checks when
	# the communication window delivers them; a lost contact is never attacked blindly.
	if SubmarineComms.should_queue(u, order) and order.type in [Order.Type.ENGAGE, Order.Type.ATTACK, Order.Type.INVESTIGATE]:
		if order.track == null or (order.track.owner_faction != "" and order.track.owner_faction != u.faction):
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
			if u.patrol_active and patrol_rejection(u, u.waypoints, order.speed_kn) != "":
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
			var spec := u.get_weapon(order.weapon_id)
			return u.is_engageable() and spec != null and order.track != null and bool(Combat.check_engagement(u, spec, order.track).get("ok", false))
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


## After a task ends on its own: back to station when the platform is told to, and only when no
## newer order arrived while the task ran. `started` is the generation the task began under.
func _return_after_task(u: Unit, started: int, reason: String) -> void:
	if not u.alive or not u.auto_return or not u.has_station() or u.on_station():
		return
	if u.order_generation != started:
		return
	resume_station(u, reason)


## Uses only information held by this unit's faction, including datalink visibility. An
## investigation never obtains a hidden position or an early classification from Track.truth.
static func investigation_rejection(u: Unit, track: Track) -> String:
	if u == null or not u.alive or not u.is_engageable() or u.spec.max_speed_kn <= 0.0:
		return "Select a deployed mobile platform"
	if u.is_aircraft() and (not u.airborne() or u.returning or u.tanking_on != null):
		return "Aircraft must be airborne and available for tasking"
	if track == null or (track.owner_faction != "" and track.owner_faction != u.faction):
		return "Contact is not available to this unit"
	if track.status == Track.Status.LOST:
		return "Contact lost"
	if not track.visible_to(u):
		return "Contact is not available to this unit"
	if track.is_bearing_only():
		return "Contact range unresolved"
	if track.classification >= Track.Classification.CLASS_KNOWN:
		return "Contact classified"
	if not track.position.is_finite():
		return "Contact position unavailable"
	if u.needs_sea_room() and (Terrain.is_land(track.position) or Terrain.first_land_contact(u.position, track.position) >= 0.0):
		return "Land blocks investigation — choose another course"
	return ""


func _step_investigation(u: Unit, dt: float) -> void:
	var track := u.investigation_track
	if track == null:
		return
	# Aviation may take over automatically for fuel. Do not overwrite its return/tanker route.
	if u.is_aircraft() and (not u.airborne() or u.returning or u.tanking_on != null):
		u.clear_investigation()
		return
	var reason := investigation_rejection(u, track)
	if reason != "":
		var started := u.task_generation
		var identify_only := u.investigation_identify_only
		u.investigation_track = null
		u.investigation_result = reason
		_hold_investigation_position(u)
		investigation_ended.emit(u, track, reason)
		if reason == "Contact classified" and not identify_only and _engage_identified(u, track, started):
			return  # the attack's own end hands back to the station
		_return_after_task(u, started, reason)
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
	else:
		u.waypoints.assign([track.position])
		u.ordered_speed_kn = u.investigation_speed_kn


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
	# A fixed-wing aircraft cannot hover at a contact plot. Keep it flying on its present course;
	# while the task remains active, later ticks bring it back toward the held plot as it turns.
	u.ordered_speed_kn = maxf(u.investigation_speed_kn, u.spec.cruise_speed_kn) if u.is_aircraft() and not u.spec.can_hover else 0.0


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
## again, the best weapon chosen, fired when the envelope allows, and the platform steered to a
## standoff inside that envelope when it does not. The contact's position is the held plot.
func _step_attack(u: Unit, dt: float) -> void:
	var track := u.attack_track
	if track == null:
		return
	# Aviation may take over automatically for fuel. Do not overwrite its return/tanker route.
	if u.is_aircraft() and (not u.airborne() or u.returning or u.tanking_on != null):
		u.clear_attack()
		return
	var reason := attack_rejection(u, track, u.attack_weapon_id)
	if reason != "":
		_end_attack(u, track, reason)
		return
	if u.evasion_remaining_s > 0.0:
		return  # evasion outranks the task and hands back to it afterwards
	var away := _rounds_away(u, track)
	if away > 0:
		u.attack_phase = "Engaging track · %d round%s away" % [away, "" if away == 1 else "s"]
		u.attack_assess_until_s = -1.0
		_steer_attack(u, track, u.attack_standoff_nm, dt)
		return
	if u.attack_rounds_fired > 0:
		# The salvo has arrived. Read the plot for a moment before spending more.
		if u.attack_assess_until_s < 0.0:
			u.attack_assess_until_s = now_s + ATTACK_ASSESS_S
		if now_s < u.attack_assess_until_s:
			u.attack_phase = "Engaging track · assessing"
			_steer_attack(u, track, u.attack_standoff_nm, dt)
			return
	var solution := _attack_solution(u, track)
	var spec: WeaponSpec = solution["spec"]
	if spec == null:
		_end_attack(u, track, "Magazines empty")
		return
	var check: Dictionary = solution["check"]
	if bool(check["ok"]):
		if track.status != Track.Status.ACTIVE:
			# Never shoot at a stale plot: the aim point would be old. Close on it instead.
			u.attack_phase = "Intercept track · contact stale"
			_steer_attack(u, track, ATTACK_STANDOFF_FRACTION * Combat.effective_range_nm(u, spec), dt)
			return
		var salvo := mini(maxi(spec.salvo_default, 1), u.magazine_count(spec.id))
		if weapon_manager != null and weapon_manager.launch(u, spec, track, salvo, now_s):
			u.attack_rounds_fired += salvo
			u.attack_assess_until_s = -1.0
			u.attack_stall_s = 0.0
			u.attack_standoff_nm = ATTACK_STANDOFF_FRACTION * Combat.effective_range_nm(u, spec)
			u.attack_phase = "Engaging track"
			_steer_attack(u, track, u.attack_standoff_nm, dt)
		else:
			u.attack_phase = "Engaging track · awaiting launcher"
		return
	var why := str(check["reason"])
	var reach := Combat.effective_range_nm(u, spec)
	var range_nm := u.position.distance_to(track.position)
	match why:
		"MOUNT MASKED / ATTACK TO UNMASK":
			u.attack_phase = "Turning to engage"
			u.waypoints.clear()
			u.ordered_heading_deg = float(check.get("unmask_heading_deg", u.heading_deg))
			u.ordered_speed_kn = minf(u.spec.cruise_speed_kn, maxf(u.attack_speed_kn, 5.0))
			u.attack_stall_s = 0.0
			return
		"OUT OF RANGE", "BEARING ONLY / NO RANGE SOLUTION", "NO INTERCEPT SOLUTION":
			u.attack_phase = "Intercept track"
			_steer_attack(u, track, ATTACK_STANDOFF_FRACTION * reach, dt)
		"INTERCEPT BEYOND WEAPON RANGE":
			# In reach of the plot but not of where the contact will be: it is opening. Keep
			# closing on it rather than holding at a standoff the lead point never enters.
			u.attack_phase = "Intercept track"
			_steer_attack(u, track, maxf(range_nm * 0.5, spec.min_range_nm * 1.5 + 0.5), dt)
		"NO LINE OF FIRE":
			# Land between the shooter and the round's path: move to water with an open line.
			var clear := Combat.clear_standoff_point(u.position, track.position, ATTACK_STANDOFF_FRACTION * reach)
			if not clear.is_finite() or u.spec.max_speed_kn <= 0.0:
				_end_attack(u, track, "No line of fire")
				return
			u.attack_phase = "Intercept track · clearing the line of fire"
			u.waypoints.assign([clear])
			u.ordered_speed_kn = maxf(u.attack_speed_kn, u.spec.cruise_speed_kn) if u.is_aircraft() and not u.spec.can_hover else u.attack_speed_kn
		"TOO CLOSE":
			u.attack_phase = "Opening to range"
			_steer_attack(u, track, maxf(spec.min_range_nm * 1.5, 1.0), dt, true)
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
			_steer_attack(u, track, ATTACK_STANDOFF_FRACTION * reach, dt)
	# Unable to fire and going nowhere: after a while, say why and stop, rather than park.
	if u.waypoints.is_empty():
		u.attack_stall_s += dt
		if u.attack_stall_s >= ATTACK_STALL_S:
			_end_attack(u, track, "Cannot engage: " + why.to_lower())
	else:
		u.attack_stall_s = 0.0


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


## Steer to the standoff distance along the bearing to the plot, or hold there. A fixed-wing
## aircraft cannot hold a point, so it keeps flying and comes round again on later ticks.
## `opening` steers out to the standoff from inside it, for a weapon's minimum range.
func _steer_attack(u: Unit, track: Track, standoff_nm: float, dt: float, opening := false) -> void:
	if u.spec.max_speed_kn <= 0.0:
		return  # an installation ashore attacks from where it stands
	var range_nm := u.position.distance_to(track.position)
	var fixed_wing := u.is_aircraft() and not u.spec.can_hover
	var arrive := maxf(Movement.ARRIVAL_MIN_NM, Geo.knots_to_nm_per_s(u.speed_kn) * dt * 2.0)
	if opening and range_nm < standoff_nm:
		u.waypoints.assign([Combat.standoff_point(u.position, track.position, standoff_nm + arrive)])
		u.ordered_speed_kn = maxf(u.attack_speed_kn, u.spec.cruise_speed_kn)
		return
	if standoff_nm <= 0.0 or range_nm <= standoff_nm + arrive:
		# Inside the envelope: hold here, as an investigating ship holds at the plot. A
		# fixed-wing aircraft cannot, so it flies on and comes round again.
		u.waypoints.clear()
		u.ordered_heading_deg = u.heading_deg
		u.ordered_speed_kn = maxf(u.attack_speed_kn, u.spec.cruise_speed_kn) if fixed_wing else 0.0
		return
	var goal := Combat.standoff_point(u.position, track.position, standoff_nm)
	u.waypoints.assign([goal])
	u.ordered_speed_kn = maxf(u.attack_speed_kn, u.spec.cruise_speed_kn) if fixed_wing else u.attack_speed_kn


func _end_attack(u: Unit, track: Track, reason: String) -> void:
	var started := u.task_generation
	u.attack_track = null
	u.attack_phase = ""
	u.attack_result = reason
	u.attack_assess_until_s = -1.0
	u.waypoints.clear()
	u.ordered_heading_deg = u.heading_deg
	if u.is_aircraft() and not u.spec.can_hover:
		u.ordered_speed_kn = maxf(u.attack_speed_kn, u.spec.cruise_speed_kn)
	attack_ended.emit(u, track, reason)
	_return_after_task(u, started, reason)


## The plot does not expire a track just because the ship under it sank, so the attack is ended
## here, by the manager that owns the ground truth, for every platform attacking that unit. The
## task's own steps never read the association; this is the one place it is consulted.
func _on_unit_destroyed(target: Unit, _killer_faction: String) -> void:
	for u in units:
		if u.alive and u.attack_track != null and u.attack_track.truth == target:
			_end_attack(u, u.attack_track, "Target destroyed")


## Validate the entire circuit before changing any standing order. No partial patrol over land.
static func patrol_rejection(u: Unit, points: Array[Vector2], speed_kn := -1.0) -> String:
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
	if u.needs_sea_room() and Terrain.first_land_contact(u.position, points[0]) >= 0.0:
		return "Land blocks the approach to this patrol"
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
