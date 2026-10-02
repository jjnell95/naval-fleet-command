class_name MissionObjective
extends RefCounted
## One scenario condition, built from scenario JSON. An objective is a predicate that becomes
## true and stays true. The scenario lists them under `victory` and `loss`, so the same predicate
## means opposite things depending on which list it sits in: RED reaching the Atlantic is a loss
## for a NATO picket, while BLUE reaching a rendezvous is a victory for an escort.
##
## The same predicates are the triggers of an operation's events (OperationDirector), which adds a
## few that only make sense there: what a side's own plot holds, what a base has ready to fly,
## whether a ship has been hit or is radiating, and any or all of several. The referee evaluates
## them at truth; what an event then does with the answer is what has to respect the fog.

enum Kind { FORCE_DESTROYED, UNIT_LOST, ALL_UNITS_LOST, REACH_AREA, TIME_ELAPSED, UNKNOWN, AIRCRAFT_RECOVERED, HOLD_AREA, TRACK_HELD, AIRCRAFT_READY, UNIT_DAMAGED, EMITTING, ANY, ALL }

const KIND_NAMES := {
	"force_destroyed": Kind.FORCE_DESTROYED,
	"unit_lost": Kind.UNIT_LOST,
	"all_units_lost": Kind.ALL_UNITS_LOST,
	"reach_area": Kind.REACH_AREA,
	"time_elapsed": Kind.TIME_ELAPSED,
	"aircraft_recovered": Kind.AIRCRAFT_RECOVERED,
	"hold_area": Kind.HOLD_AREA,
	"track_held": Kind.TRACK_HELD,
	"aircraft_ready": Kind.AIRCRAFT_READY,
	"unit_damaged": Kind.UNIT_DAMAGED,
	"emitting": Kind.EMITTING,
	"any": Kind.ANY,
	"all": Kind.ALL,
}
## How well a side's plot must know a contact for TRACK_HELD: Track.Classification by name.
const CLASSIFICATION_NAMES := {"UNKNOWN": 0, "SURFACE": 1, "CLASS_KNOWN": 2, "IDENTIFIED": 3}
## What a saved engagement keeps of an objective's progress; the rest is rebuilt from its dict.
const PROGRESS_FIELDS := ["complete", "unlocked", "held_since", "held_seconds"]

var id := ""
var kind: Kind = Kind.UNKNOWN
var text := ""
var faction := ""
## Optional responsibility filter on UNIT_LOST. Empty retains the original any-cause behavior.
## Damage preserves the firing faction through a later fire/flooding loss.
var caused_by := ""
var callsigns := PackedStringArray()
var center := Vector2.ZERO
var radius_nm := 15.0
var count := 1
var max_alive := 0
var seconds := 0.0
var complete := false
var facility := ""  # optional airfield or deck filter for aviation training
var after := PackedStringArray()
var unlocked := true
var held_since := -1.0
var held_seconds := 0.0
var phase_only := false  # enables later tasks but cannot itself end an any-mode mission
## A bonus task: credited by the assessment when done, never needed to win, never blocks a win.
var optional := false
## TRACK_HELD: whose plot (`faction`) must hold the named units, and how well. A stale track does
## not count unless allowed, and neither does a contact report nobody has seen for themselves.
var min_classification := 0
var allow_stale := false
var include_reports := false
## TRACK_HELD with a `center_nm`: the plot must also put the contact inside the area, where the
## side's own track says it is. A side reacting to an enemy's progress reacts to what it can see.
var plotted_in_area := false
## UNIT_DAMAGED: a named unit below this share of its health, or lost.
var health_below := 1.0
## AIRCRAFT_READY: the airframe type at the named bases, by catalogue id or part of one.
var platform := ""
## ANY and ALL: the predicates combined.
var children: Array[MissionObjective] = []


static func from_dict(d: Dictionary) -> MissionObjective:
	var o := MissionObjective.new()
	o.id = d.get("id", "")
	o.kind = KIND_NAMES.get(d.get("type", ""), Kind.UNKNOWN)
	if o.kind == Kind.UNKNOWN:
		push_error("MissionObjective: unknown type '%s'" % d.get("type", ""))
	o.text = d.get("text", "")
	o.faction = d.get("faction", "")
	o.caused_by = str(d.get("caused_by", ""))
	for c in d.get("callsigns", []):
		o.callsigns.append(str(c))
	var c: Array = d.get("center_nm", [0, 0])
	o.center = Vector2(c[0], c[1])
	o.radius_nm = float(d.get("radius_nm", 15.0))
	o.count = int(d.get("count", 1))
	o.max_alive = int(d.get("max_alive", 0))
	o.seconds = float(d.get("seconds", 0.0))
	o.facility = str(d.get("facility", ""))
	for prerequisite in d.get("after", []):
		o.after.append(str(prerequisite))
	o.unlocked = o.after.is_empty()
	o.phase_only = bool(d.get("phase_only", false))
	o.optional = bool(d.get("optional", false))
	o.min_classification = int(CLASSIFICATION_NAMES.get(str(d.get("min_classification", "UNKNOWN")), 0))
	o.allow_stale = bool(d.get("allow_stale", false))
	o.include_reports = bool(d.get("include_reports", false))
	o.plotted_in_area = o.kind == Kind.TRACK_HELD and d.has("center_nm")
	o.health_below = float(d.get("health_below", 1.0))
	o.platform = str(d.get("platform", ""))
	for child in d.get("of", []):
		if typeof(child) == TYPE_DICTIONARY:
			o.children.append(from_dict(child))
	return o


## Why this objective or trigger cannot be built as written, or "". The authoring checks use it
## without raising engine errors, so a bad mission is refused rather than half run.
static func problem(d: Variant) -> String:
	if typeof(d) != TYPE_DICTIONARY:
		return "a condition must be an object"
	var kind: Kind = KIND_NAMES.get(str(d.get("type", "")), Kind.UNKNOWN)
	if kind == Kind.UNKNOWN:
		return "unknown condition type '%s'" % d.get("type", "")
	if kind in [Kind.ANY, Kind.ALL]:
		if typeof(d.get("of", [])) != TYPE_ARRAY or (d.get("of", []) as Array).is_empty():
			return "'%s' needs a list of conditions under 'of'" % d["type"]
		for child in d["of"]:
			var why := problem(child)
			if why != "":
				return why
	if d.has("min_classification") and not CLASSIFICATION_NAMES.has(str(d["min_classification"])):
		return "unknown classification '%s'" % d["min_classification"]
	if kind in [Kind.TRACK_HELD, Kind.AIRCRAFT_READY, Kind.UNIT_DAMAGED, Kind.EMITTING] and (d.get("callsigns", []) as Array).is_empty():
		return "'%s' needs named units" % d["type"]
	if kind == Kind.TRACK_HELD and str(d.get("faction", "")) == "":
		return "'track_held' needs the faction whose plot is asked"
	return ""


## Every unit callsign a condition names, through any and all, for the authoring checks.
static func named_units(d: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for c in d.get("callsigns", []):
		out.append(str(c))
	for child in d.get("of", []):
		if typeof(child) == TYPE_DICTIONARY:
			out.append_array(named_units(child))
	return out


## Progress as plain data, including the parts of a combined condition.
func progress_state() -> Dictionary:
	var d := {}
	for name: String in PROGRESS_FIELDS:
		d[name] = get(name)
	if not children.is_empty():
		var parts := []
		for c in children:
			parts.append(c.progress_state())
		d["children"] = parts
	return d


func restore_progress(d: Dictionary) -> void:
	for name: String in PROGRESS_FIELDS:
		if d.has(name):
			set(name, d[name])
	var parts: Array = d.get("children", [])
	for i in mini(parts.size(), children.size()):
		children[i].restore_progress(parts[i])


## Latches once true: a sunk ship does not come back, and a rendezvous once made is made. The
## track manager is needed only to ask what a side's plot holds.
func evaluate(um: UnitManager, now: float, tm: TrackManager = null) -> bool:
	if complete:
		return true
	if not unlocked:
		return false
	complete = _test(um, now, tm)
	return complete


func _test(um: UnitManager, now: float, tm: TrackManager = null) -> bool:
	match kind:
		Kind.FORCE_DESTROYED:
			return um.get_engageable_units(faction).size() <= max_alive
		Kind.UNIT_LOST:
			for name in callsigns:
				var u := _find(um, name)
				if u != null and _lost(u) and (caused_by == "" or u.last_attacker == caused_by):
					return true
			return false
		Kind.ALL_UNITS_LOST:
			for name in callsigns:
				var u := _find(um, name)
				if u == null or not _lost(u):
					return false
			return not callsigns.is_empty()
		Kind.REACH_AREA:
			var n := 0
			for u in _scope(um):
				# A whole-force count means ships and flying aircraft, not airframes riding in a
				# hangar that happens to be inside the box.
				var present: bool = u.alive if not callsigns.is_empty() else u.is_engageable()
				if present and u.position.distance_to(center) <= radius_nm:
					n += 1
			return n >= count
		Kind.TIME_ELAPSED:
			return now >= seconds
		Kind.HOLD_AREA:
			var n := 0
			for u in _scope(um):
				if u.is_engageable() and u.position.distance_to(center) <= radius_nm:
					n += 1
			if n < count:
				held_since = -1.0
				held_seconds = 0.0
				return false
			if held_since < 0.0:
				held_since = now
			held_seconds = maxf(now - held_since, 0.0)
			return held_seconds >= seconds
		Kind.AIRCRAFT_RECOVERED:
			return _recovered_count(um) >= maxi(count, 1)
		Kind.TRACK_HELD:
			return _held_count(um, tm) >= maxi(count, 1)
		Kind.AIRCRAFT_READY:
			return _ready_count(um) >= maxi(count, 1)
		Kind.UNIT_DAMAGED:
			for name in callsigns:
				var u := _find(um, name)
				if u != null and (_lost(u) or Damage.health_fraction(u) < health_below):
					return true
			return false
		Kind.EMITTING:
			for name in callsigns:
				var u := _find(um, name)
				if u != null and u.alive and u.radar_emitting():
					return true
			return false
		Kind.ANY:
			# Every part is asked every time, so a hold inside an "any" keeps its own clock.
			var any_done := false
			for c in children:
				if c.evaluate(um, now, tm):
					any_done = true
			return any_done
		Kind.ALL:
			var all_done := not children.is_empty()
			for c in children:
				if not c.evaluate(um, now, tm):
					all_done = false
			return all_done
	return false


## Named units this side's own plot holds well enough (and, given an area, puts inside it). The
## plot is the faction's networked one, the picture its commander would be acting on.
func _held_count(um: UnitManager, tm: TrackManager) -> int:
	if tm == null:
		return 0
	var held := 0
	for name in callsigns:
		var u := _find(um, name)
		if u == null:
			continue
		var t := tm.find_track(faction, u)
		if t == null or t.status == Track.Status.LOST:
			continue
		if t.status == Track.Status.STALE and not allow_stale:
			continue
		if t.reported and not include_reports:
			continue
		if plotted_in_area and t.position.distance_to(center) > radius_nm:
			continue
		if int(t.classification) >= min_classification:
			held += 1
	return held


## Airframes of the type at the named bases that could be sent now or are already up.
func _ready_count(um: UnitManager) -> int:
	var n := 0
	for name in callsigns:
		var host := _find(um, name)
		if host == null or not host.alive:
			continue
		for a: Unit in host.embarked:
			if a.alive and (platform == "" or a.spec.id.contains(platform)) and (a.ready_to_launch() or a.in_flight()):
				n += 1
	return n


## Short status line for the objectives panel.
func progress(um: UnitManager, now: float) -> String:
	if complete:
		return "done"
	if not unlocked:
		return "awaiting previous task"
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
			if caused_by != "":
				return "no attributed losses"
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
		Kind.AIRCRAFT_RECOVERED:
			return "%d / %d aircraft recovered" % [_recovered_count(um), maxi(count, 1)]
		Kind.HOLD_AREA:
			return "%.0f / %.0f min continuously on station" % [held_seconds / 60.0, seconds / 60.0]
		Kind.TRACK_HELD:
			return "not yet located"
		Kind.UNIT_DAMAGED:
			# The referee knows the ship's condition; the panel says only that it has not happened,
			# so a strike task never reads out an enemy's damage before the hit is confirmed.
			return "no hit yet"
	return ""


func _recovered_count(um: UnitManager) -> int:
	var recovered := 0
	# A recovery is historical. A later aircraft loss does not erase a completed landing.
	for a: Unit in um.units:
		if (callsigns.is_empty() and a.faction != faction) or (not callsigns.is_empty() and not callsigns.has(a.callsign)):
			continue
		if not a.is_aircraft() or a.completed_sorties <= 0:
			continue
		var matching := facility == "" or int(a.completed_sorties_by_facility.get(facility, 0)) > 0
		if facility == "deck":
			for kind in ["catobar", "stobar", "stovl", "helicopter"]:
				matching = matching or int(a.completed_sorties_by_facility.get(kind, 0)) > 0
		if matching:
			recovered += 1
	return recovered


## Sunk, shot down or foundered. An aircraft that flew home off the chart has not been lost.
static func _lost(u: Unit) -> bool:
	return not u.alive and not u.departed


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
