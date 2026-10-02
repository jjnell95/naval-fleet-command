class_name OperationDirector
extends Node
## The operation's script: the scenario's events, each fired at most once when its moment comes.
##
## An event can wait for a time (`at_s`), for other events or objectives (`after`), and for a
## condition on the battle itself (`when`, a MissionObjective predicate): a convoy passing a point,
## a side's own plot holding a ship, a base with aircraft ready, a ship hit or radiating, any or all
## of several. `latest_s` fires it anyway once that time comes; `unless` cancels it if its own
## condition comes true first; `expires_s` cancels it if it has not fired by then. Conditions are
## watched from the start and latch, so one met before the event's time still counts. Some of its
## shape is drawn once per engagement from the director's own random stream: a window instead of a
## time (`at_s_window`, `latest_s_window`), a `chance` that it happens at all, or one of several
## weighted `variants` merged into it. So a replay has to be read off the plot, not remembered.
##
## What an event does, in this order: `reinforcements` enter through the scenario loader, `intel`
## puts an imprecise contact report on a side's plot, `ai` gives the event's own side's units a
## new posture or route, `ready` brings a base's reserve airframes forward, `objectives` changes
## the tasking, and `message` is sent. An event belongs to a `side` (the player's unless it says
## otherwise) and acts only on that side's units; its message goes to its `audience` (the side by
## default) and only a message for the player's side is ever sent, so the opposing side's
## decisions are never announced. Nothing an event does hands anyone a firing solution.
##
## The draws use a stream of their own, seeded from the engagement's seed with a salt, so the
## sensor, weapon and damage streams, and every seeded outcome already pinned, are untouched.

## A message for the player's side, already composed (coordinates filled in).
signal message(text: String)
## Units entered the battle; the simulation gives any new side its commander.
signal reinforced()
## One of a side's own units was given a new standing route or posture by the scenario.
signal retasked(u: Unit)

const RNG_SALT := 0x0E7E
## A report's error when the event does not say. GAMEPLAY_ESTIMATE.
const DEFAULT_REPORT_ERROR_NM := 10.0

var unit_manager: UnitManager
var track_manager: TrackManager
var mission_manager: MissionManager
var player_faction := "BLUE"
## The chart's anchor (latitude, longitude), for the coordinates a contact report reads out.
var anchor := Vector2.ZERO
## The scenario's events as this engagement drew them: windows resolved to times, variants merged.
var events: Array = []
## Event id -> the sim time it fired, in the order they fired.
var fired: Dictionary = {}
## Event id -> why it never will: "chance", "unless", "expired", or "unreported" when the contact
## its message places is no longer there to report on.
var skipped: Dictionary = {}
## Event id -> what was drawn for it ("variant", "at_s", "latest_s", "happens"), for the record.
var variant: Dictionary = {}
var rng := RandomNumberGenerator.new()
var _conditions: Dictionary = {}  # event id -> MissionObjective built from "when"
var _vetoes: Dictionary = {}  # event id -> MissionObjective built from "unless"


func clear() -> void:
	events.clear()
	fired.clear()
	skipped.clear()
	variant.clear()
	_conditions.clear()
	_vetoes.clear()


## Empties the record and takes the scenario's side and chart. A restored engagement stops here and
## puts back its saved events; a new one goes on to draw them (configure).
func install(scenario: Dictionary) -> void:
	clear()
	player_faction = str(scenario.get("player_faction", "BLUE"))
	var m: Dictionary = scenario.get("map", {})
	anchor = Vector2(float(m.get("anchor_lat", 0.0)), float(m.get("anchor_lon", 0.0)))


## Draws this engagement's version of the scenario's events. Draws are made in event order, and
## within an event: the variant, then the windows, then the chance.
func configure(scenario: Dictionary, base_seed: int) -> void:
	install(scenario)
	rng.seed = base_seed ^ RNG_SALT
	var raw: Array = scenario.get("events", [])
	for i in raw.size():
		if typeof(raw[i]) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = (raw[i] as Dictionary).duplicate(true)
		var id := str(e.get("id", str(i)))
		e["id"] = id
		var drawn := {}
		if e.has("variants"):
			var choice := _pick(e["variants"])
			for key: String in choice:
				if key != "id" and key != "weight":
					e[key] = choice[key]
			drawn["variant"] = str(choice.get("id", ""))
			e.erase("variants")
		for key: String in ["at_s", "latest_s"]:
			if e.has(key + "_window"):
				var w: Array = e[key + "_window"]
				var at := snappedf(lerpf(float(w[0]), float(w[1]), rng.randf()), 1.0)
				e[key] = at
				drawn[key] = at
				e.erase(key + "_window")
		if e.has("chance"):
			var happens := rng.randf() < float(e["chance"])
			drawn["happens"] = happens
			if not happens:
				skipped[id] = "chance"
		if not drawn.is_empty():
			variant[id] = drawn
		events.append(e)
	rebuild()


func _pick(options: Array) -> Dictionary:
	var total := 0.0
	for o: Dictionary in options:
		total += maxf(float(o.get("weight", 1.0)), 0.0)
	var roll := rng.randf() * total
	for o: Dictionary in options:
		roll -= maxf(float(o.get("weight", 1.0)), 0.0)
		if roll < 0.0:
			return o.duplicate(true)
	return (options.back() as Dictionary).duplicate(true)


## The conditions, from the resolved events. A restored engagement calls this after putting its
## events back, then restores their progress.
func rebuild() -> void:
	_conditions.clear()
	_vetoes.clear()
	for e: Dictionary in events:
		if e.has("when"):
			_conditions[e["id"]] = MissionObjective.from_dict(e["when"])
		if e.has("unless"):
			_vetoes[e["id"]] = MissionObjective.from_dict(e["unless"])


func event(id: String) -> Dictionary:
	for e: Dictionary in events:
		if e["id"] == id:
			return e
	return {}


## Runs first in the tick, before anything moves, so an event that waits on an objective fires one
## tick after the objective completes (the mission is judged last).
func tick(now: float) -> void:
	if mission_manager == null or mission_manager.result != MissionManager.Result.RUNNING:
		return
	for e: Dictionary in events:
		var id: String = e["id"]
		if fired.has(id) or skipped.has(id):
			continue
		if e.has("expires_s") and now >= float(e["expires_s"]):
			skipped[id] = "expired"
			continue
		# Both conditions are watched from the start and latch, like every objective: the enemy
		# having located the carrier before a raid's window opens still sends the raid when it does.
		var veto: MissionObjective = _vetoes.get(id)
		var vetoed := veto != null and veto.evaluate(unit_manager, now, track_manager)
		var condition: MissionObjective = _conditions.get(id)
		var due := condition == null or condition.evaluate(unit_manager, now, track_manager)
		if now < float(e.get("at_s", 0.0)) or not _after_met(e.get("after", [])):
			continue
		if vetoed:
			skipped[id] = "unless"
			continue
		if not due and e.has("latest_s") and now >= float(e["latest_s"]):
			due = true
		if not due:
			continue
		if _reportable(e):
			_fire(e, now)
		else:
			skipped[id] = "unreported"


## Whether every contact report the event's message reads a position from can be made: its target
## is still afloat, or enters with this event. An event that cannot say where its contact is does
## nothing at all, so a tasking change is never made without the order that explains it (a box
## moved away from a battery that has since been destroyed, say).
func _reportable(e: Dictionary) -> bool:
	var text := str(e.get("message", "")).replace("{pos}", "{pos0}")
	if not text.contains("{pos"):
		return true
	var arriving := {}
	for u in e.get("reinforcements", []):
		arriving[str(u.get("callsign", ""))] = true
	var items: Array = e.get("intel", [])
	for i in items.size():
		if not text.contains("{pos%d}" % i):
			continue
		var name := str((items[i] as Dictionary).get("target", ""))
		var target := _unit(name)
		if not arriving.has(name) and (target == null or not target.is_engageable()):
			return false
	return true


## Events that have fired, and objectives (victory or loss) that are complete.
func _after_met(ids: Array) -> bool:
	for id in ids:
		var key := str(id)
		if fired.has(key):
			continue
		var o := mission_manager.objective(key)
		if o == null or not o.complete:
			return false
	return true


func _fire(e: Dictionary, now: float) -> void:
	var id: String = e["id"]
	fired[id] = now
	var side := str(e.get("side", player_faction))
	var arriving: Array = e.get("reinforcements", [])
	if not arriving.is_empty():
		# They enter through the same loader as the opening force, with no tracks: an enemy
		# reinforcement still has to be found by the other side's sensors.
		ScenarioLoader.populate(unit_manager, {"units": arriving})
		reinforced.emit()
	var reports: Array = []
	for item: Dictionary in e.get("intel", []):
		reports.append(_report(item, side, now))
	for item: Dictionary in e.get("ai", []):
		_retask(item, side)
	for item: Dictionary in e.get("ready", []):
		_bring_forward(item, side)
	var text := _compose(str(e.get("message", "")), reports)
	# Only a message for the player's side is heard, and only that is kept with the briefing's
	# tasking updates: the other side's orders are never read out, on the radio or in F1.
	var heard := text != "" and str(e.get("audience", side)) == player_faction
	if e.has("objectives") and mission_manager != null:
		mission_manager.apply_update(e["objectives"], now, text if heard else "")
	if heard:
		message.emit(text)


## A contact report on a named unit: its position now, moved by a draw within the report's error,
## put on the receiving side's plot as a datum (TrackManager.report_intel). Returns the reported
## position, or null when there is nothing on the board to report.
func _report(item: Dictionary, side: String, now: float) -> Variant:
	var target := _unit(str(item.get("target", "")))
	if target == null or not target.is_engageable():
		return null
	var error := float(item.get("error_nm", DEFAULT_REPORT_ERROR_NM))
	# Anywhere in the error circle, evenly: a report is near the contact, not usually on it.
	var offset := Geo.heading_to_vector(rng.randf() * 360.0) * error * sqrt(rng.randf())
	var at := target.position + offset
	if track_manager != null:
		track_manager.report_intel(str(item.get("to", side)), target, at, error, now, str(item.get("source", "")))
	return at


## "{pos}" (or "{pos0}", "{pos1}" ...) is the reported position of the event's first (or nth)
## contact report, as the chart's latitude and longitude read it. A message whose report could not
## be made is not sent at all rather than sent with a hole in it.
func _compose(text: String, reports: Array) -> String:
	if text == "" or not text.contains("{pos"):
		return text
	text = text.replace("{pos}", "{pos0}")
	for i in reports.size():
		var key := "{pos%d}" % i
		if text.contains(key):
			if reports[i] == null:
				return ""
			text = text.replace(key, chart_position(reports[i]))
	return "" if text.contains("{pos") else text


## A world position as the chart labels it: "68°41.2′N 07°12.9′E".
func chart_position(p: Vector2) -> String:
	var ll := Geo.world_to_latlon(p, anchor.x, anchor.y)
	return "%s %s" % [Geo.format_latlon(ll.x), Geo.format_latlon(ll.y, false)]


func _retask(item: Dictionary, side: String) -> void:
	for name in item.get("units", []):
		var u := _unit(str(name))
		if u == null or not u.alive or u.faction != side:
			continue
		if item.has("ai_posture"):
			u.ai_posture = str(item["ai_posture"])
		if item.has("patrol_nm"):
			var route: Array[Vector2] = []
			for leg in item["patrol_nm"]:
				route.append(Vector2(float(leg[0]), float(leg[1])))
			u.patrol_route = route
		retasked.emit(u)


## Shortens the preparation of a base's reserve airframes: never lengthens it, never touches one
## already flying, in turnaround or lost with its base, and never adds an airframe.
func _bring_forward(item: Dictionary, side: String) -> void:
	var host := _unit(str(item.get("host", "")))
	if host == null or not host.alive or host.faction != side:
		return
	var platform := str(item.get("platform", ""))
	var left := int(item.get("count", host.embarked.size()))
	var after_s := maxf(float(item.get("ready_after_s", 0.0)), 0.0)
	for a: Unit in host.embarked:
		if left <= 0:
			break
		if not a.alive or a.flight_state != Unit.FlightState.RESERVE:
			continue
		if platform != "" and not a.spec.id.contains(platform):
			continue
		a.state_timer_s = minf(a.state_timer_s, after_s)
		left -= 1


func _unit(callsign: String) -> Unit:
	for u in unit_manager.units:
		if u.callsign == callsign:
			return u
	return null


# --- Saved engagements -----------------------------------------------------------------------

## The tasking changes the fired events made, made again in the order they were made, so a
## restored engagement's objectives line up with their saved progress. Nothing is announced and
## no update is logged twice: the briefing's list of updates is saved with the mission manager.
func replay_updates() -> void:
	for id: String in fired:
		var e := event(id)
		if e.has("objectives") and mission_manager != null:
			mission_manager.apply_update(e["objectives"], float(fired[id]), "", false)


func condition_progress() -> Dictionary:
	var out := {}
	for id: String in _conditions:
		out["when:" + id] = (_conditions[id] as MissionObjective).progress_state()
	for id: String in _vetoes:
		out["unless:" + id] = (_vetoes[id] as MissionObjective).progress_state()
	return out


func restore_condition_progress(saved: Dictionary) -> void:
	for id: String in _conditions:
		(_conditions[id] as MissionObjective).restore_progress(saved.get("when:" + id, {}))
	for id: String in _vetoes:
		(_vetoes[id] as MissionObjective).restore_progress(saved.get("unless:" + id, {}))


# --- Authoring checks ------------------------------------------------------------------------

## The first thing wrong with a scenario's events, or "". A mission is refused rather than run with
## an event that names a unit nobody placed, waits on an id nobody defines, or orders another
## side's units about.
static func event_problem(sc: Dictionary) -> String:
	var raw = sc.get("events", [])
	if typeof(raw) != TYPE_ARRAY:
		return "events must be an array"
	var factions := {}  # callsign -> faction, for the opening force and every reinforcement
	var sides := {}
	for u in sc.get("units", []):
		factions[str(u.get("callsign", ""))] = str(u.get("faction", "BLUE"))
		_wing_callsigns(u, factions)
	for e in raw:
		if typeof(e) != TYPE_DICTIONARY:
			return "An event needs to be an object"
		var groups: Array = [e.get("reinforcements", [])]
		for v in e.get("variants", []):
			if typeof(v) == TYPE_DICTIONARY:
				groups.append(v.get("reinforcements", []))
		for group in groups:
			for u in group:
				if typeof(u) == TYPE_DICTIONARY:
					factions[str(u.get("callsign", ""))] = str(u.get("faction", "BLUE"))
					_wing_callsigns(u, factions)
	for f in factions.values():
		sides[f] = true
	var objective_ids := {}
	var objectives: Dictionary = sc.get("objectives", {})
	for d in objectives.get("victory", []) + objectives.get("loss", []):
		objective_ids[str(d.get("id", ""))] = true
	var event_ids := {}
	for i in raw.size():
		var e: Dictionary = raw[i]
		var id := str(e.get("id", str(i)))
		if event_ids.has(id) or objective_ids.has(id):
			return "Event id '%s' is used twice" % id
		event_ids[id] = true
		var shapes: Array = [e]
		for v in e.get("variants", []):
			if typeof(v) != TYPE_DICTIONARY or str(v.get("id", "")) == "":
				return "Event '%s' needs each variant to be an object with an id" % id
			var merged := e.duplicate(true)
			merged.erase("variants")
			for key: String in v:
				merged[key] = v[key]
			shapes.append(merged)
		for shape: Dictionary in shapes:
			for d in (shape.get("objectives", {}) as Dictionary).get("add", []) + (shape.get("objectives", {}) as Dictionary).get("add_loss", []):
				if typeof(d) == TYPE_DICTIONARY:
					objective_ids[str(d.get("id", ""))] = true
	for i in raw.size():
		var e: Dictionary = raw[i]
		var id := str(e.get("id", str(i)))
		var shapes: Array = []
		if e.has("variants"):
			for v: Dictionary in e["variants"]:
				var merged := e.duplicate(true)
				merged.erase("variants")
				for key: String in v:
					merged[key] = v[key]
				shapes.append(merged)
		else:
			shapes.append(e)
		for shape: Dictionary in shapes:
			var why := _shape_problem(shape, factions, sides, event_ids, objective_ids, str(sc.get("player_faction", "BLUE")))
			if why != "":
				return "Event '%s': %s" % [id, why]
	return ""


## The airframes a host's authored air wing names, as ScenarioLoader names them ("Fullback 21"):
## an event may retask a base's strike element or make its drones a task. A wing entry without a
## callsign or squadron is named after its host only when loaded, so it cannot be named here.
static func _wing_callsigns(host: Dictionary, factions: Dictionary) -> void:
	for entry in host.get("air_wing", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var base := str(entry.get("callsign", ""))
		if base == "":
			base = str(entry.get("squadron", ""))
		if base == "":
			continue
		var first := int(entry.get("first_modex", 1))
		for i in maxi(int(entry.get("count", 1)), 0):
			factions["%s %d" % [base, first + i]] = str(host.get("faction", "BLUE"))


static func _shape_problem(e: Dictionary, factions: Dictionary, sides: Dictionary, event_ids: Dictionary, objective_ids: Dictionary, player: String) -> String:
	var side := str(e.get("side", player))
	if not sides.has(side):
		return "no side '%s' in the scenario" % side
	for key in ["at_s", "latest_s", "expires_s"]:
		if e.has(key) and (typeof(e[key]) not in [TYPE_INT, TYPE_FLOAT] or float(e[key]) < 0.0):
			return "%s must be a time of zero or more" % key
	for key in ["at_s_window", "latest_s_window"]:
		if e.has(key):
			var w = e[key]
			if typeof(w) != TYPE_ARRAY or w.size() != 2 or float(w[0]) < 0.0 or float(w[1]) < float(w[0]):
				return "%s needs [earliest, latest]" % key
	if e.has("chance") and (float(e["chance"]) < 0.0 or float(e["chance"]) > 1.0):
		return "chance must be between 0 and 1"
	for prerequisite in e.get("after", []):
		if not event_ids.has(str(prerequisite)) and not objective_ids.has(str(prerequisite)):
			return "waits on '%s', which no event or objective defines" % prerequisite
	for key in ["when", "unless"]:
		if e.has(key):
			var why := MissionObjective.problem(e[key])
			if why != "":
				return "%s: %s" % [key, why]
			for name in MissionObjective.named_units(e[key]):
				if not factions.has(name):
					return "%s names '%s', which is not in the scenario" % [key, name]
	for item in e.get("intel", []):
		if typeof(item) != TYPE_DICTIONARY or not factions.has(str(item.get("target", ""))):
			return "a contact report needs a target in the scenario"
		if not sides.has(str(item.get("to", side))):
			return "a contact report goes to a side in the scenario"
		if float(item.get("error_nm", DEFAULT_REPORT_ERROR_NM)) <= 0.0:
			return "a contact report needs a positive error"
	for item in e.get("ai", []):
		for name in item.get("units", []):
			if str(factions.get(str(name), "")) != side:
				return "'%s' is not one of the %s side's units" % [name, side]
		for leg in item.get("patrol_nm", []):
			if typeof(leg) != TYPE_ARRAY or leg.size() != 2:
				return "a route leg needs two numbers"
	for item in e.get("ready", []):
		if str(factions.get(str(item.get("host", "")), "")) != side:
			return "'%s' is not one of the %s side's bases" % [item.get("host", ""), side]
	var update: Dictionary = e.get("objectives", {})
	for d in update.get("add", []) + update.get("add_loss", []):
		var why := MissionObjective.problem(d)
		if why != "" or str(d.get("id", "")) == "":
			return "an added objective needs an id and a known type (%s)" % why
		for name in MissionObjective.named_units(d):
			if not factions.has(name):
				return "an added objective names '%s', which is not in the scenario" % name
	for id in update.get("complete", []) + update.get("remove", []) + (update.get("update", {}) as Dictionary).keys():
		if not objective_ids.has(str(id)):
			return "no objective '%s' to change" % id
	if typeof(e.get("message", "")) != TYPE_STRING:
		return "the message must be text"
	if str(e.get("message", "")).contains("{pos") and (e.get("intel", []) as Array).is_empty():
		return "the message gives a reported position but the event makes no report"
	return ""
