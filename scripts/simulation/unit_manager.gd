class_name UnitManager
extends Node
## Owns all ground-truth Units and advances them on simulation ticks.

signal unit_added(unit: Unit)
signal order_issued(unit: Unit, order: Order)

var units: Array[Unit] = []
var _next_id := 1


func add_unit(u: Unit) -> void:
	u.id = _next_id
	_next_id += 1
	units.append(u)
	unit_added.emit(u)


func tick(dt: float) -> void:
	Formation.update_speed_caps(units)
	for u in units:
		if not u.alive:
			continue
		DefensiveResponse.tick(u, dt)
		Formation.step(u)
		Movement.step(u, dt)


## Returns false when this platform cannot carry out the order, so group-order receipts count
## actual capability rather than merely counting living selections. Dynamic subsystem checks
## (deck spots and fire-control channels) remain with their specialist managers.
func issue_order(u: Unit, order: Order) -> bool:
	if not can_accept_order(u, order):
		return false
	if order.type == Order.Type.MOVE and u.needs_sea_room() and Terrain.is_land(order.target_pos):
		return false
	order.execution_accepted = true
	u.apply_order(order)
	order_issued.emit(u, order)
	return order.execution_accepted


static func can_accept_order(u: Unit, order: Order) -> bool:
	if u == null or order == null or not u.alive:
		return false
	match order.type:
		Order.Type.PATROL:
			return patrol_rejection(u, order.route) == ""
		Order.Type.DEPLOY_COUNTERMEASURES:
			return DefensiveResponse.can_deploy(u, order.countermeasure_kind)
		Order.Type.EVADE:
			return u.is_engageable() and u.spec.max_speed_kn > 0 and (not u.is_aircraft() or u.airborne())
		Order.Type.RESUME_PLAN, Order.Type.SET_AUTO_COUNTERMEASURES:
			return u.is_engageable()
		Order.Type.SET_DEFENCE_POLICY:
			return u.is_engageable() and order.defence_policy in ["balanced", "conserve", "saturation"]
		Order.Type.SET_SPEED:
			if u.patrol_active and patrol_rejection(u, u.waypoints, order.speed_kn) != "":
				return false
			return (not u.is_aircraft() or u.airborne()) and u.is_engageable() and u.spec.max_speed_kn > 0.0
		Order.Type.MOVE, Order.Type.SET_COURSE, Order.Type.STOP, Order.Type.CLEAR_WAYPOINTS:
			return (not u.is_aircraft() or u.airborne()) and u.is_engageable() and u.spec.max_speed_kn > 0.0
		Order.Type.ACTIVATE_RADAR, Order.Type.SILENCE_RADAR:
			return u.is_engageable() and u.has_radar()
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
		Order.Type.RETURN_TO_BASE:
			return u.airborne()
		Order.Type.DEPLOY_SONOBUOY:
			return u.airborne() and u.sonobuoys > 0 and u.spec.sonobuoy_sensitivity_nm > 0.0 and not Terrain.is_land(u.position)
		Order.Type.SET_EMCON:
			return u.is_engageable() and (u.has_radar() or u.has_sonar() or u.has_jammer())
		Order.Type.FORM_UP:
			return Formation.can_join(u, order.leader)
		Order.Type.BREAK_FORMATION, Order.Type.SET_ROE:
			return u.is_engageable()
	return false


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
		u.home = null
		u.recovery_base = null
		u.embarked.clear()
		u.inbound_aircraft.clear()
		u.formation_leader = null
		u.tanking_on = null
		Detection.jammers.erase(u)
	units.clear()
	_next_id = 1


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		clear()
