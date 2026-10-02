class_name SimSnapshot
extends RefCounted
## A saved engagement: everything the simulation needs to carry on from the tick it was taken
## exactly as it would have without stopping. Plain data only (Variant types, no Objects), so it
## can be written with store_var, which keeps 64-bit RNG states, infinities, integer keys and
## dictionary order exactly; JSON keeps none of those.
##
## Every object reference (a unit, a track, a weapon, a catalogue entry, an air mission) is written
## as a small marker holding a stable id, and restore is two-phase: every object is allocated first,
## then every field is filled with the markers resolved, so each saved reference comes back as the
## one object it was. Several systems compare objects by identity, so a deep copy per field would
## quietly break them. Restore writes fields directly and emits no signals: nothing is "detected",
## "launched" or "added" a second time, and the observed journal is not replayed.
##
## Units, tracks, weapons, air missions, buoys, group attacks and the opposing force's mission
## plans are saved by reflection over their script variables, less the few each class lists below
## with the reason. tests/test_save.gd fails when a class gains a variable that is neither saved nor
## listed, so new state cannot silently fall out of a save. Managers list the fields they save
## explicitly, under the same test.
##
## Scenario-editor files are mission definitions; this is a running engagement, and embeds the
## scenario it was started from, so an edited or deleted mission file cannot break a continuation.

const FORMAT := "naval-fleet-command.engagement"
const VERSION := 1

## Variables kept out of the reflective copy, by class.
const UNIT_SKIP := {
	"bottom_generation": "a validity flag is saved instead; the chart's generation is new after a load",
}
const TRACK_SKIP := {}
const WEAPON_SKIP := {}
const MISSION_SKIP := {}
const BUOY_SKIP := {}
## An AI mission plan (AIPlan), saved whole: what the author wrote and how far its commander has got.
const PLAN_SKIP := {}
const GROUP_SKIP := {}

## Manager state saved by name. Anything else a manager holds is wiring (manager references set
## once in Simulation._ready), catalogue data, or recomputed within a single tick.
const MANAGER_FIELDS := {
	"UnitManager": ["now_s", "_next_id", "engage_on_hostile_id"],
	"TrackManager": ["_tracks", "_by_target", "_local_keys", "_track_ids", "_next_number"],
	"SensorManager": ["_accum", "_last_heading", "_manoeuvre"],
	"ThreatManager": ["_observers", "_detected", "_first_seen"],
	"WeaponManager": ["in_flight", "_next_id", "_launcher_ready_at", "now_s", "_pending", "_pending_dirty"],
	"AviationManager": ["_accum", "_next_buoy_id"],
	"AirMissionManager": ["now_s", "_next_id", "_accum"],
	"GroupAttackManager": ["now_s", "_next_id", "_accum"],
	"MissionManager": ["result"],
	"AIController": ["enabled", "_bb", "_plan_checked"],
}
## Manager variables that are deliberately not saved, and why. SensorManager.reference_path is a
## development switch between two cycles that produce the same tracks, not engagement state.
const MANAGER_TRANSIENT := {
	"UnitManager": ["units", "weapon_manager"],
	"TrackManager": ["neutral_factions"],
	"SensorManager": ["unit_manager", "track_manager", "threat_manager", "weapon_manager", "aviation_manager", "rng", "reference_path"],
	"ThreatManager": ["revision"],
	"WeaponManager": ["unit_manager", "track_manager", "rng", "revision", "_channel_batch", "_channel_cache"],
	"AviationManager": ["unit_manager", "sonobuoys", "map_center", "map_extent_nm"],
	"AirMissionManager": ["unit_manager", "aviation_manager", "track_manager", "missions"],
	# The group attack records are saved on their own, below; their rounds' tags are on the
	# queued shots and the weapons themselves.
	"GroupAttackManager": ["unit_manager", "track_manager", "weapon_manager", "groups"],
	"MissionManager": ["unit_manager", "player_faction", "briefing", "situation", "victory_objectives", "loss_objectives", "victory_mode", "neutral_factions"],
	# `plans` is rebuilt from the embedded scenario when the controller is, then each plan is filled
	# from its saved record (capture, restore): plans are records, not plain manager data.
	"AIController": ["faction", "unit_manager", "track_manager", "threat_manager", "weapon_manager", "air_mission_manager", "plans", "_cycle_inbound", "_cycle_committed", "_cycle_torpedoes", "_in_decision_cycle"],
}
## A mission objective's progress; the rest of it is rebuilt from the embedded scenario.
const OBJECTIVE_FIELDS := ["complete", "unlocked", "held_since", "held_seconds"]


## Converts object references to markers on the way out and back on the way in.
class Refs:
	extends RefCounted
	var errors: PackedStringArray = []
	var tracks: Array = []  # capture: index is the ref
	var track_index: Dictionary = {}
	var weapons: Array = []
	var weapon_index: Dictionary = {}
	var units_by_id: Dictionary = {}
	var tracks_by_ref: Array = []
	var weapons_by_id: Dictionary = {}
	var missions_by_id: Dictionary = {}

	func track_ref(t: Track) -> int:
		if not track_index.has(t):
			track_index[t] = tracks.size()
			tracks.append(t)
		return int(track_index[t])

	func weapon_ref(w: Weapon) -> int:
		if not weapon_index.has(w):
			weapon_index[w] = true
			weapons.append(w)
		return w.id

	func enc(v: Variant) -> Variant:
		match typeof(v):
			TYPE_OBJECT:
				if v == null:
					return null
				if v is Unit:
					return {"$u": (v as Unit).id}
				if v is Track:
					return {"$t": track_ref(v)}
				if v is Weapon:
					return {"$w": weapon_ref(v)}
				if v is PlatformSpec:
					return {"$p": (v as PlatformSpec).id}
				if v is WeaponSpec:
					return {"$ws": (v as WeaponSpec).id}
				if v is SensorSpec:
					return {"$s": (v as SensorSpec).id}
				if v is AirMission:
					return {"$m": (v as AirMission).id}
				errors.append("cannot save a reference to %s" % v)
				return null
			TYPE_ARRAY:
				var out := []
				for x in v:
					out.append(enc(x))
				return out
			TYPE_DICTIONARY:
				var object_keys := false
				for k in v:
					if typeof(k) == TYPE_OBJECT:
						object_keys = true
						break
				if object_keys:
					var pairs := []
					for k in v:
						pairs.append([enc(k), enc(v[k])])
					return {"$pairs": pairs}
				var d := {}
				for k in v:
					d[k] = enc(v[k])
				return d
		return _copy_packed(v)

	func dec(v: Variant) -> Variant:
		match typeof(v):
			TYPE_ARRAY:
				var out := []
				for x in v:
					out.append(dec(x))
				return out
			TYPE_DICTIONARY:
				if v.size() == 1:
					var key = v.keys()[0]
					if typeof(key) == TYPE_STRING and (key as String).begins_with("$"):
						return _marker(key, v[key])
				var d := {}
				for k in v:
					d[k] = dec(v[k])
				return d
		return _copy_packed(v)

	## Packed arrays are shared by reference: without a copy a snapshot would keep growing with
	## the live track it was taken from, and a restored track would share the save's buffer.
	static func _copy_packed(v: Variant) -> Variant:
		if typeof(v) >= TYPE_PACKED_BYTE_ARRAY and typeof(v) <= TYPE_PACKED_VECTOR4_ARRAY:
			return v.duplicate()
		return v

	func _marker(kind: String, value: Variant) -> Variant:
		match kind:
			"$u":
				if not units_by_id.has(int(value)):
					errors.append("unit %s missing" % value)
				return units_by_id.get(int(value))
			"$t":
				var i := int(value)
				if i < 0 or i >= tracks_by_ref.size():
					errors.append("track %s missing" % value)
					return null
				return tracks_by_ref[i]
			"$w":
				if not weapons_by_id.has(int(value)):
					errors.append("weapon %s missing" % value)
				return weapons_by_id.get(int(value))
			"$m":
				return missions_by_id.get(int(value))
			"$p":
				return DataDB.platform(str(value))
			"$ws":
				return DataDB.weapon(str(value))
			"$s":
				return DataDB.sensor(str(value))
			"$pairs":
				var d := {}
				for pair: Array in value:
					d[dec(pair[0])] = dec(pair[1])
				return d
		errors.append("unknown marker %s" % kind)
		return null


# --- Capture -------------------------------------------------------------------------------

## Everything the simulation holds, as plain data. The caller adds presentation (the journal, the
## after-action counters) and writes it out.
static func capture(sim: Simulation) -> Dictionary:
	var refs := Refs.new()
	var um := sim.unit_manager
	var units := []
	for u in um.units:
		var d := fields_of(u, UNIT_SKIP, refs)
		d["bottom_cache_valid"] = u.bottom_generation == Bathymetry.generation
		units.append(d)
	var managers := {}
	for node: Node in [um, sim.track_manager, sim.sensor_manager, sim.threat_manager, sim.weapon_manager, sim.aviation_manager, sim.air_mission_manager, sim.group_attack_manager, sim.mission_manager]:
		managers[_manager_name(node)] = manager_fields(node, refs)
	var ai := []
	for faction: String in sim.ai_controllers:
		var c: AIController = sim.ai_controllers[faction]
		var plans := []
		for p in c.plans:
			plans.append(fields_of(p, PLAN_SKIP, refs))
		ai.append([faction, manager_fields(c, refs), plans])
	var missions := []
	for m in sim.air_mission_manager.missions:
		missions.append(fields_of(m, MISSION_SKIP, refs))
	var buoys := []
	for b in sim.aviation_manager.sonobuoys:
		buoys.append(fields_of(b, BUOY_SKIP, refs))
	# Group attacks, ended ones too, in the order they were ordered: members by unit id, contacts as
	# track references (a contact already lost from every picture is saved with them). What each
	# has queued and in the air is not stored here; it is counted from the tags on the saved queue
	# and weapons.
	var groups := []
	for g in sim.group_attack_manager.groups:
		groups.append(fields_of(g, GROUP_SKIP, refs))
	var objectives := {"victory": _objective_state(sim.mission_manager.victory_objectives), "loss": _objective_state(sim.mission_manager.loss_objectives)}
	# Weapons may name other weapons (an interceptor's target that has already left the plot), and
	# tracks are found wherever they are referenced; both lists grow while they are written.
	var weapons := []
	var i := 0
	while i < refs.weapons.size():
		weapons.append(fields_of(refs.weapons[i], WEAPON_SKIP, refs))
		i += 1
	var tracks := []
	i = 0
	while i < refs.tracks.size():
		tracks.append(fields_of(refs.tracks[i], TRACK_SKIP, refs))
		i += 1
	return {
		"format": FORMAT,
		"version": VERSION,
		"scenario": sim.scenario.duplicate(true),
		"scenario_path": sim.scenario_path,
		"scenario_digest": scenario_digest(sim.scenario),
		"base_seed": sim.base_seed,
		"clock": {"sim_time": SimClock.sim_time, "start_unix_time": SimClock.start_unix_time},
		"rng": {
			"sensor": [sim.sensor_manager.rng.seed, sim.sensor_manager.rng.state],
			"weapon": [sim.weapon_manager.rng.seed, sim.weapon_manager.rng.state],
			"damage": [Damage.rng.seed, Damage.rng.state],
		},
		"simulation": {
			"defence_accum": sim._defence_accum,
			"ai_accum": sim._ai_accum,
			"completed_events": sim.completed_events.keys(),
			"ai_enabled": sim.ai_enabled,
			"ai_plays_player": sim.ai_plays_player,
		},
		"units": units,
		"tracks": tracks,
		"weapons": weapons,
		"air_missions": missions,
		"sonobuoys": buoys,
		"group_attacks": groups,
		"managers": managers,
		"ai": ai,
		"objectives": objectives,
		"errors": refs.errors,
	}


## Every script variable of an entity, less the listed ones, with references as markers.
static func fields_of(obj: Object, skip: Dictionary, refs: Refs) -> Dictionary:
	var out := {}
	for name: String in script_variables(obj):
		if not skip.has(name):
			out[name] = refs.enc(obj.get(name))
	return out


static func manager_fields(node: Object, refs: Refs) -> Dictionary:
	var out := {}
	for name: String in MANAGER_FIELDS[_manager_name(node)]:
		out[name] = refs.enc(node.get(name))
	return out


## Script variables in declaration order.
static func script_variables(obj: Object) -> PackedStringArray:
	var out := PackedStringArray()
	for p: Dictionary in obj.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.append(str(p["name"]))
	return out


static func _manager_name(node: Object) -> String:
	var script: Script = node.get_script()
	return script.get_global_name() if script != null else node.get_class()


static func _objective_state(list: Array) -> Array:
	var out := []
	for o: MissionObjective in list:
		var d := {}
		for name: String in OBJECTIVE_FIELDS:
			d[name] = o.get(name)
		out.append(d)
	return out


static func scenario_digest(scenario: Dictionary) -> String:
	if scenario.is_empty():
		return ""
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes(scenario))
	return hashing.finish().hex_encode()


# --- Validation ----------------------------------------------------------------------------

## Why this snapshot cannot be restored, or "". Checked before the running engagement is touched.
static func validate(snap: Variant) -> String:
	if typeof(snap) != TYPE_DICTIONARY:
		return "Not a saved engagement"
	if str(snap.get("format", "")) != FORMAT:
		return "Not a saved engagement (unknown format)"
	var version := int(snap.get("version", 0))
	if version > VERSION:
		return "Saved by a newer version of the game (format %d; this build reads up to %d)" % [version, VERSION]
	if version < 1:
		return "Saved engagement is from an unsupported early format"
	for key in ["scenario", "clock", "rng", "simulation", "units", "tracks", "weapons", "managers", "objectives"]:
		if not snap.has(key):
			return "Saved engagement is incomplete (%s missing)" % key
	if typeof(snap["scenario"]) != TYPE_DICTIONARY or (snap["scenario"] as Dictionary).is_empty():
		return "Saved engagement has no scenario"
	if scenario_digest(snap["scenario"]) != str(snap.get("scenario_digest", "")):
		return "Saved engagement is damaged (scenario does not match its checksum)"
	if not (snap.get("errors", []) as Array).is_empty():
		return "Saved engagement was written with errors: %s" % ", ".join(snap["errors"])
	var damaged := _shape_problem(snap)
	if damaged != "":
		return "Saved engagement is damaged (%s)" % damaged
	if int(snap["managers"].get("MissionManager", {}).get("result", MissionManager.Result.RUNNING)) != MissionManager.Result.RUNNING:
		return "That engagement had already ended"
	var missing := _missing_catalogue(snap)
	if missing != "":
		return "Saved engagement uses %s, which this build does not have" % missing
	return ""


## The first thing wrong with the snapshot's structure, or "": every record where a record should
## be, ids where ids should be, and every reference pointing at something the snapshot holds. A
## restore replaces the running engagement before it finishes, so a save that would fail half-way
## has to be caught here.
static func _shape_problem(snap: Dictionary) -> String:
	for key in ["units", "tracks", "weapons"]:
		if typeof(snap[key]) != TYPE_ARRAY:
			return "%s" % key
	for key in ["air_missions", "sonobuoys", "group_attacks", "ai"]:
		if snap.has(key) and typeof(snap[key]) != TYPE_ARRAY:
			return "%s" % key
	for key in ["clock", "rng", "simulation", "managers", "objectives"]:
		if typeof(snap[key]) != TYPE_DICTIONARY:
			return "%s" % key
	var ids := {"$u": {}, "$w": {}, "$m": {}}
	for pair in [["units", "$u"], ["weapons", "$w"], ["air_missions", "$m"]]:
		for d in snap.get(pair[0], []):
			if typeof(d) != TYPE_DICTIONARY or typeof(d.get("id")) != TYPE_INT:
				return "a record in %s" % pair[0]
			if ids[pair[1]].has(d["id"]):
				return "two %s with id %d" % [pair[0], d["id"]]
			ids[pair[1]][d["id"]] = true
	for key in ["tracks", "sonobuoys", "group_attacks"]:
		for d in snap.get(key, []):
			if typeof(d) != TYPE_DICTIONARY:
				return "a record in %s" % key
	for node in snap["managers"].values():
		if typeof(node) != TYPE_DICTIONARY:
			return "managers"
	for entry in snap.get("ai", []):
		# [faction, controller fields] and, since enemy mission plans, [..., plan records].
		if typeof(entry) != TYPE_ARRAY or not entry.size() in [2, 3] or typeof(entry[0]) != TYPE_STRING or typeof(entry[1]) != TYPE_DICTIONARY:
			return "ai"
		if entry.size() == 3 and typeof(entry[2]) != TYPE_ARRAY:
			return "ai"
	for stream in ["sensor", "weapon", "damage"]:
		var pair: Variant = snap["rng"].get(stream)
		if typeof(pair) != TYPE_ARRAY or pair.size() != 2 or typeof(pair[0]) != TYPE_INT or typeof(pair[1]) != TYPE_INT:
			return "random stream %s" % stream
	if not typeof(snap["clock"].get("sim_time")) in [TYPE_FLOAT, TYPE_INT] or typeof(snap["clock"].get("start_unix_time")) != TYPE_INT:
		return "clock"
	for key in ["defence_accum", "ai_accum"]:
		if not typeof(snap["simulation"].get(key)) in [TYPE_FLOAT, TYPE_INT]:
			return "simulation"
	for key in ["victory", "loss"]:
		var list: Variant = snap["objectives"].get(key, [])
		if typeof(list) != TYPE_ARRAY:
			return "objectives"
		for d in list:
			if typeof(d) != TYPE_DICTIONARY:
				return "objectives"
	for key in snap:
		if key != "scenario":
			var bad := _reference_problem(snap[key], ids, (snap["tracks"] as Array).size())
			if bad != "":
				return bad
	return ""


## A marker naming a unit, weapon, track or mission the snapshot does not hold, or a malformed one.
static func _reference_problem(v: Variant, ids: Dictionary, track_count: int) -> String:
	match typeof(v):
		TYPE_DICTIONARY:
			if v.size() == 1:
				var key = v.keys()[0]
				if key is String and (key as String).begins_with("$"):
					var value: Variant = v[key]
					match key:
						"$u", "$w", "$m":
							if typeof(value) != TYPE_INT or not ids[key].has(value):
								return "%s %s missing" % [{"$u": "unit", "$w": "weapon", "$m": "air mission"}[key], value]
							return ""
						"$t":
							if typeof(value) != TYPE_INT or value < 0 or value >= track_count:
								return "track %s missing" % value
							return ""
						"$p", "$ws", "$s":
							return "" if typeof(value) == TYPE_STRING else "catalogue reference"
						"$pairs":
							if typeof(value) != TYPE_ARRAY:
								return "paired record"
							for pair in value:
								if typeof(pair) != TYPE_ARRAY or pair.size() != 2:
									return "paired record"
								for x in pair:
									var bad := _reference_problem(x, ids, track_count)
									if bad != "":
										return bad
							return ""
					return "unknown reference %s" % key
			for k in v:
				var bad := _reference_problem(v[k], ids, track_count)
				if bad != "":
					return bad
		TYPE_ARRAY:
			for x in v:
				var bad := _reference_problem(x, ids, track_count)
				if bad != "":
					return bad
	return ""


## The first catalogue id the snapshot names that DataDB does not know, or "".
static func _missing_catalogue(v: Variant) -> String:
	match typeof(v):
		TYPE_DICTIONARY:
			if v.size() == 1:
				var key = v.keys()[0]
				if key is String:
					match key:
						"$p":
							return "" if DataDB.platform(str(v[key])) != null else "platform '%s'" % v[key]
						"$ws":
							return "" if DataDB.weapon(str(v[key])) != null else "weapon '%s'" % v[key]
						"$s":
							return "" if DataDB.sensor(str(v[key])) != null else "sensor '%s'" % v[key]
			for k in v:
				if typeof(k) == TYPE_OBJECT:
					return "an object reference"
				var found := _missing_catalogue(v[k])
				if found != "":
					return found
		TYPE_ARRAY:
			for x in v:
				var found := _missing_catalogue(x)
				if found != "":
					return found
		TYPE_OBJECT:
			return "an object reference"
	return ""


## Older formats are upgraded here, one version at a time, only where the meaning is certain.
## Version 1 is the first.
static func migrate(snap: Dictionary) -> Dictionary:
	return snap


# --- Restore -------------------------------------------------------------------------------

## Puts a validated snapshot back into a Simulation whose world (chart, environment, objectives)
## has just been installed from the embedded scenario. Returns "" or what went wrong.
static func restore(sim: Simulation, snap: Dictionary) -> String:
	var refs := Refs.new()
	var um := sim.unit_manager
	# Phase one: an empty object for every saved one, so references can be resolved in any order.
	for d: Dictionary in snap["units"]:
		var u := Unit.new()
		u.id = int(d["id"])
		refs.units_by_id[u.id] = u
		um.units.append(u)
	for _d in snap["tracks"]:
		refs.tracks_by_ref.append(Track.new())
	for d: Dictionary in snap["weapons"]:
		var w := Weapon.new()
		w.id = int(d["id"])
		refs.weapons_by_id[w.id] = w
	for d: Dictionary in snap.get("air_missions", []):
		var m := AirMission.new()
		m.id = int(d["id"])
		refs.missions_by_id[m.id] = m
		sim.air_mission_manager.missions.append(m)
	# Phase two: fill them.
	for d: Dictionary in snap["units"]:
		var u: Unit = refs.units_by_id[int(d["id"])]
		_fill(u, d, refs)
		u.bottom_generation = Bathymetry.generation if bool(d.get("bottom_cache_valid", false)) else -1
	for i in snap["tracks"].size():
		_fill(refs.tracks_by_ref[i], snap["tracks"][i], refs)
	for d: Dictionary in snap["weapons"]:
		_fill(refs.weapons_by_id[int(d["id"])], d, refs)
	for d: Dictionary in snap.get("air_missions", []):
		_fill(refs.missions_by_id[int(d["id"])], d, refs)
	for d: Dictionary in snap.get("sonobuoys", []):
		var b := Sonobuoy.new()
		_fill(b, d, refs)
		sim.aviation_manager.sonobuoys.append(b)
	for d: Dictionary in snap.get("group_attacks", []):
		var g := GroupAttack.new()
		_fill(g, d, refs)
		sim.group_attack_manager.groups.append(g)
	var managers: Dictionary = snap["managers"]
	# Which sides engage what they identify is kept across a new mission, so it is not emptied with
	# the units; a save from before the option existed was played with no side doing so.
	um.engage_on_hostile_id = {}
	for node: Node in [um, sim.track_manager, sim.sensor_manager, sim.threat_manager, sim.weapon_manager, sim.aviation_manager, sim.air_mission_manager, sim.group_attack_manager, sim.mission_manager]:
		_fill_manager(node, managers.get(_manager_name(node), {}), refs)
	_restore_objectives(sim.mission_manager.victory_objectives, snap["objectives"].get("victory", []))
	_restore_objectives(sim.mission_manager.loss_objectives, snap["objectives"].get("loss", []))
	# The AI: one controller per saved faction, in the saved order, which is the order they think.
	# Whether the AI flies the player's side decides which controllers exist, so it comes first.
	var s: Dictionary = snap["simulation"]
	sim.ai_enabled = bool(s.get("ai_enabled", true))
	sim.ai_plays_player = bool(s.get("ai_plays_player", false))
	sim._build_ai(true)
	var ordered := {}
	for entry: Array in snap.get("ai", []):
		var faction := str(entry[0])
		var c: AIController = sim.ai_controllers.get(faction)
		if c == null:
			refs.errors.append("no AI for %s" % faction)
			continue
		_fill_manager(c, entry[1], refs)
		_restore_plans(c, entry[2] if entry.size() > 2 else [], refs)
		ordered[faction] = c
	for faction: String in sim.ai_controllers:
		if not ordered.has(faction):
			ordered[faction] = sim.ai_controllers[faction]
	sim.ai_controllers = ordered
	sim._defence_accum = float(s["defence_accum"])
	sim._ai_accum = float(s["ai_accum"])
	sim.completed_events.clear()
	for key in s.get("completed_events", []):
		sim.completed_events[key] = true
	sim.base_seed = int(snap.get("base_seed", 0))
	# Seed first: setting a seed resets the state.
	var rng: Dictionary = snap["rng"]
	sim.sensor_manager.rng.seed = int(rng["sensor"][0])
	sim.sensor_manager.rng.state = int(rng["sensor"][1])
	sim.weapon_manager.rng.seed = int(rng["weapon"][0])
	sim.weapon_manager.rng.state = int(rng["weapon"][1])
	Damage.rng.seed = int(rng["damage"][0])
	Damage.rng.state = int(rng["damage"][1])
	Detection.refresh_jammers(um.units)
	sim.weapon_manager.revision += 1
	sim.threat_manager.revision += 1
	var clock: Dictionary = snap["clock"]
	SimClock.reset(int(clock["start_unix_time"]))
	SimClock.sim_time = float(clock["sim_time"])
	return "" if refs.errors.is_empty() else "Saved engagement could not be restored: " + ", ".join(refs.errors)


## A controller's plans were just rebuilt from the embedded scenario (allocation); each is filled
## from the record saved under its id. A save written before plans were saved has no records and
## leaves them as the scenario sets them up.
static func _restore_plans(c: AIController, saved: Array, refs: Refs) -> void:
	for d: Dictionary in saved:
		var plan: AIPlan = null
		for p in c.plans:
			if p.id == str(d.get("id", "")):
				plan = p
				break
		if plan == null:
			refs.errors.append("no AI plan %s for %s" % [d.get("id", "?"), c.faction])
			continue
		_fill(plan, d, refs)


static func _fill(obj: Object, data: Dictionary, refs: Refs) -> void:
	for name in data:
		if name != "bottom_cache_valid":
			_assign(obj, name, refs.dec(data[name]))


static func _fill_manager(node: Object, data: Dictionary, refs: Refs) -> void:
	for name in data:
		_assign(node, name, refs.dec(data[name]))


## Writes into a typed array in place, so an Array[Unit] stays one.
static func _assign(obj: Object, name: String, value: Variant) -> void:
	var current: Variant = obj.get(name)
	if typeof(current) == TYPE_ARRAY and typeof(value) == TYPE_ARRAY:
		(current as Array).assign(value)
	else:
		obj.set(name, value)


static func _restore_objectives(list: Array, saved: Array) -> void:
	for i in mini(list.size(), saved.size()):
		for name in saved[i]:
			list[i].set(name, saved[i][name])
