class_name ThreatManager
extends Node
## Per-faction picture of detected incoming weapons. Rebuilt every sensor cycle: a weapon that
## drops below the radar horizon simply disappears from the picture again.
##
## Detection is shared across a faction, which stands in for a task-force air picture. The
## quality of that sharing (datalinks, EMCON) is refined in Milestone 9. A faction whose ships
## are all radar-silent still sees nothing at all.

signal threat_detected(faction: String, weapon: Weapon)

var _observers: Dictionary = {}
var _detected: Dictionary = {}  # faction -> Dictionary[int weapon_id, Weapon]
var _first_seen: Dictionary = {}  # faction -> Dictionary[int weapon_id, float]


func begin_cycle() -> void:
	_observers.clear()
	for faction in _detected.keys():
		_detected[faction] = {}


func mark_detected(faction: String, w: Weapon, now: float, observer: Unit = null) -> void:
	if not _observers.has(w.id):
		_observers[w.id] = []
	_observers[w.id].append(observer)
	if not _detected.has(faction):
		_detected[faction] = {}
	if not _first_seen.has(faction):
		_first_seen[faction] = {}
	_detected[faction][w.id] = w
	if not _first_seen[faction].has(w.id):
		_first_seen[faction][w.id] = now
		threat_detected.emit(faction, w)


func get_threats(faction: String) -> Array[Weapon]:
	var out: Array[Weapon] = []
	for w in _detected.get(faction, {}).values():
		if w.phase != Weapon.Phase.DEAD:
			out.append(w)
	return out


func is_detected(faction: String, w: Weapon) -> bool:
	return _detected.get(faction, {}).has(w.id)


func visible_to(u: Unit, w: Weapon) -> bool:
	if not is_detected(u.faction, w):
		return false
	for observer: Unit in _observers.get(w.id, []):
		if observer == u:
			return true
		if u.datalink_connected() and (observer == null or (observer.faction == u.faction and observer.datalink_connected())):
			return true
	return false


func forget(w: Weapon) -> void:
	_observers.erase(w.id)
	for faction in _detected.keys():
		_detected[faction].erase(w.id)
	for faction in _first_seen.keys():
		_first_seen[faction].erase(w.id)


func clear() -> void:
	_observers.clear()
	_detected.clear()
	_first_seen.clear()
