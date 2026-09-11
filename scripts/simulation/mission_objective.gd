class_name MissionObjective
extends RefCounted
## One scenario condition, built from scenario JSON. An objective is a predicate that becomes
## true and stays true. The scenario lists them under `victory` and `loss`, so the same predicate
## means opposite things depending on which list it sits in: RED reaching the Atlantic is a loss
## for a NATO picket, while BLUE reaching a rendezvous is a victory for an escort.

enum Kind { FORCE_DESTROYED, UNIT_LOST, ALL_UNITS_LOST, REACH_AREA, TIME_ELAPSED, UNKNOWN }

const KIND_NAMES := {
	"force_destroyed": Kind.FORCE_DESTROYED,
	"unit_lost": Kind.UNIT_LOST,
	"all_units_lost": Kind.ALL_UNITS_LOST,
	"reach_area": Kind.REACH_AREA,
	"time_elapsed": Kind.TIME_ELAPSED,
}

var id := ""
var kind: Kind = Kind.UNKNOWN
var text := ""
var faction := ""
var callsigns := PackedStringArray()
var center := Vector2.ZERO
var radius_nm := 15.0
var count := 1
var max_alive := 0
var seconds := 0.0
var complete := false


static func from_dict(d: Dictionary) -> MissionObjective:
	var o := MissionObjective.new()
	o.id = d.get("id", "")
	o.kind = KIND_NAMES.get(d.get("type", ""), Kind.UNKNOWN)
	if o.kind == Kind.UNKNOWN:
		push_error("MissionObjective: unknown type '%s'" % d.get("type", ""))
	o.text = d.get("text", "")
	o.faction = d.get("faction", "")
	for c in d.get("callsigns", []):
		o.callsigns.append(str(c))
	var c: Array = d.get("center_nm", [0, 0])
	o.center = Vector2(c[0], c[1])
	o.radius_nm = float(d.get("radius_nm", 15.0))
	o.count = int(d.get("count", 1))
	o.max_alive = int(d.get("max_alive", 0))
	o.seconds = float(d.get("seconds", 0.0))
	return o


## Latches once true: a sunk ship does not come back, and a rendezvous once made is made.
func evaluate(um: UnitManager, now: float) -> bool:
	if complete:
		return true
	complete = _test(um, now)
	return complete


func _test(um: UnitManager, now: float) -> bool:
	match kind:
		Kind.FORCE_DESTROYED:
			return um.get_engageable_units(faction).size() <= max_alive
		Kind.UNIT_LOST:
			for name in callsigns:
				var u := _find(um, name)
				if u != null and not u.alive:
					return true
			return false
		Kind.ALL_UNITS_LOST:
			for name in callsigns:
				var u := _find(um, name)
				if u == null or u.alive:
					return false
			return not callsigns.is_empty()
		Kind.REACH_AREA:
			var n := 0
			for u in _scope(um):
				if u.alive and u.position.distance_to(center) <= radius_nm:
					n += 1
			return n >= count
		Kind.TIME_ELAPSED:
			return now >= seconds
	return false


## Short status line for the objectives panel.
func progress(um: UnitManager, now: float) -> String:
	if complete:
		return "done"
	match kind:
		Kind.FORCE_DESTROYED:
			return "%d remaining" % um.get_engageable_units(faction).size()
		Kind.ALL_UNITS_LOST:
			var afloat := 0
			for name in callsigns:
				var u := _find(um, name)
				if u != null and u.alive:
					afloat += 1
			return "%d of %d still up" % [afloat, callsigns.size()]
		Kind.UNIT_LOST:
			var lines := PackedStringArray()
			for name in callsigns:
				var u := _find(um, name)
				if u != null:
					lines.append("%s %.0f%%" % [name, Damage.health_fraction(u) * 100.0])
			return ", ".join(lines)
		Kind.REACH_AREA:
			var best := INF
			for u in _scope(um):
				if u.alive:
					best = minf(best, u.position.distance_to(center) - radius_nm)
			return "---" if best == INF else "%.0f nm to go" % maxf(best, 0.0)
		Kind.TIME_ELAPSED:
			return "%s left" % Geo.format_duration(maxf(seconds - now, 0.0)).trim_prefix("D+0 ")
	return ""


## Units this objective is about: named ships if given, otherwise the whole faction.
func _scope(um: UnitManager) -> Array:
	if callsigns.is_empty():
		return um.get_faction_units(faction)
	var out: Array = []
	for name in callsigns:
		var u := _find(um, name)
		if u != null:
			out.append(u)
	return out


func _find(um: UnitManager, callsign: String) -> Unit:
	for u in um.units:
		if u.callsign == callsign:
			return u
	return null
