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


## Returns false when the order could not be carried out, so the caller can tell the player why.
## The only order terrain can refuse is a MOVE: everything else either names no destination or
## belongs to something that overflies a coast.
func issue_order(u: Unit, order: Order) -> bool:
	if not u.alive:
		return false
	if order.type == Order.Type.MOVE and u.needs_sea_room() and Terrain.is_land(order.target_pos):
		return false
	u.apply_order(order)
	order_issued.emit(u, order)
	return true


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
