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
	for u in units:
		if not u.alive:
			continue
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
		Order.Type.MOVE, Order.Type.SET_COURSE, Order.Type.SET_SPEED, Order.Type.STOP, Order.Type.CLEAR_WAYPOINTS:
			return u.is_engageable() and u.spec.max_speed_kn > 0.0
		Order.Type.ACTIVATE_RADAR, Order.Type.SILENCE_RADAR:
			return u.is_engageable() and u.has_radar()
		Order.Type.ACTIVE_SONAR, Order.Type.PASSIVE_SONAR:
			return u.is_engageable() and u.has_sonar()
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
			return u.is_engageable() and u.spec.max_speed_kn > 0.0 and order.leader != null and order.leader.alive
		Order.Type.BREAK_FORMATION, Order.Type.SET_ROE:
			return u.is_engageable()
	return false


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
	units.clear()
	_next_id = 1
