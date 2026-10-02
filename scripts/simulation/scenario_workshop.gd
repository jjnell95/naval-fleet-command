class_name ScenarioWorkshop
## Reproducible custom fleets and shared authoring validation. Recipes choose a force, not a
## scripted battle. Geography can be reused without inheriting a template's story or enemies.

const REGIONS := ["north_atlantic", "west_pacific", "arabian_sea", "mediterranean"]
## Geography only: each region borrows a shipped mission's coastline, never its forces or story.
## The Norwegian Sea comes from the 1990 carrier watch, whose open-water origin sits at 68°N 4°E.
const CHARTS := ["cold_war_03_carrier", "pacific_02_taiwan_strait", "gulf_01_hormuz", "med_01_tartus"]


static func generate(recipe: Dictionary) -> Dictionary:
	var seed_value := int(recipe.get("seed", 29))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var cold := int(recipe.get("year", 2027)) == 1990
	var region := clampi(int(recipe.get("region", 0)), 0, REGIONS.size() - 1)
	var geography := ScenarioLoader.load_file("res://data/scenarios/%s.json" % CHARTS[region])
	var map_data: Dictionary = geography.get("map", {}).duplicate(true)
	map_data.erase("focus_center_nm")
	map_data.erase("focus_extent_nm")
	map_data["center_nm"] = [0, 0]
	map_data["extent_nm"] = clampf(float(recipe.get("extent_nm", 220)), 100, 1200)
	map_data["chart_region"] = REGIONS[region]
	var terrain: Dictionary = geography.get("terrain", {"land": []}).duplicate(true) if bool(recipe.get("coastlines", false)) else {"land": []}
	if not bool(recipe.get("coastlines", false)):
		map_data["labels"] = []
		map_data["open_water"] = true
	var name := str(recipe.get("name", "Fleet exercise %d" % seed_value))
	var sc := {
		"id": "custom_fleet_%d" % seed_value, "name": name, "seed": seed_value,
		"year": 1990 if cold else 2027, "era": "Cold War" if cold else "Modern",
		"start_time_utc": "%d-06-01T06:00:00" % (1990 if cold else 2027),
		"player_faction": "BLUE", "neutral_factions": ["NEUTRAL"],
		"theatre": REGIONS[region].replace("_", " ").capitalize(),
		"description": "A custom fleet exercise. You set the forces, plan and victory conditions. All combat performance is a game estimate.",
		"commander_intent": "Keep the force coherent, build the contact picture and protect the flagship.",
		"first_orders": ["Review the force in Fleet Operations (J).", "Set emissions and defensive policy before accelerating time.", "Save selection groups with Ctrl+1 to 9; recall with Alt+1 to 9."],
		"environment": {"sea_state": clampi(int(recipe.get("sea_state", 2)), 0, 6)},
		"map": map_data, "terrain": terrain, "victory_mode": "all", "units": [],
		"objectives": {"text": "Protect the flagship and defeat the opposing fleet.", "victory": [{"id": "defeat_red", "type": "force_destroyed", "faction": "RED", "text": "Defeat the opposing fleet"}], "loss": []},
		"recipe": recipe.duplicate(true),
	}
	var land: Array[Landmass] = []
	var occupied: Array[Vector2] = []
	for entry in terrain.get("land", []):
		land.append(Landmass.from_dict(entry))
	for faction: String in ["BLUE", "RED"]:
		var prefix := faction.to_lower()
		var count := clampi(int(recipe.get(prefix + "_ships", 6)), 1, 48)
		var carriers := clampi(int(recipe.get(prefix + "_carriers", 1 if faction == "BLUE" else 0)), 0, mini(count, 2))
		var choices: Array = ["cw90_ticonderoga", "cw90_spruance", "cw90_perry"] if cold else ["usn_ddg_arleigh_burke_iia", "usn_cg_ticonderoga", "usn_ffg_constellation"]
		if faction == "RED":
			choices = ["cw90_slava", "cw90_sovremenny", "cw90_udaloy"] if cold else (["pla_ddg_type055", "pla_ddg_type052d"] if region == 1 else ["rfn_ffg_admiral_gorshkov", "rfn_cg_slava", "rfn_ddg_udaloy"])
		var carrier_id := "cw90_nimitz" if cold else "usn_cvn_nimitz"
		if faction == "RED":
			# The 1990 recipe keeps the period boundary; a second Nimitz is a fictional opposing
			# force, rather than silently borrowing a modern STOBAR air wing.
			carrier_id = "cw90_nimitz" if cold else "pla_cv_shandong"
		var origin := Vector2(-38, -6) if faction == "BLUE" else Vector2(38, 6)
		origin = _water_point(origin, land)
		var heading := 90.0 if faction == "BLUE" else 270.0
		var leader_name := "%s 01" % faction
		for i in count:
			var pid: String = carrier_id if i < carriers else choices[rng.randi_range(0, choices.size() - 1)]
			var spec := DataDB.platform(pid)
			if spec == null:
				continue
			var offset := Vector2.ZERO if i == 0 else Formation.offset_for(i - 1, str(recipe.get("formation", "screen")))
			var world := _water_point(origin + Geo.heading_to_vector(heading) * offset.y + Geo.heading_to_vector(heading + 90) * offset.x, land, occupied)
			occupied.append(world)
			var unit := {"platform": pid, "callsign": "%s %02d" % [faction, i + 1], "faction": faction,
				"position_nm": [world.x, world.y], "heading_deg": heading, "speed_kn": minf(spec.cruise_speed_kn, 16),
				"radar_on": true, "defence_policy": str(recipe.get("defence_policy", "balanced")),
				"defence_priority": 2 if i < carriers else 0}
			if i > 0:
				unit["formation_leader"] = leader_name
				unit["formation_offset_nm"] = [offset.x, offset.y]
			if i < carriers:
				unit["air_wing"] = scaled_wing(spec, clampi(int(recipe.get("aircraft_per_carrier", 24)), 0, spec.aircraft_capacity), unit["callsign"])
			sc["units"].append(unit)
		if faction == "BLUE":
			sc["objectives"]["loss"].append({"id": "flagship_lost", "type": "unit_lost", "callsigns": [leader_name], "text": "Keep the flagship afloat"})
		var boats := clampi(int(recipe.get(prefix + "_subs", 1)), 0, 12)
		for i in boats:
			var pid := "cw90_los_angeles" if cold else "usn_ssn_virginia"
			if faction == "RED":
				pid = "cw90_victor3" if cold else ("pla_ssn_type093b" if region == 1 else "rfn_ssk_kilo")
			var spec := DataDB.platform(pid)
			var world := _water_point(origin + Vector2(rng.randf_range(-12, 12), 22 + i * 7), land, occupied)
			occupied.append(world)
			sc["units"].append({"platform": pid, "callsign": "%s SUB %02d" % [faction, i + 1], "faction": faction,
				"position_nm": [world.x, world.y], "heading_deg": heading, "speed_kn": 8, "depth_m": spec.patrol_depth_m, "radar_on": false})
	return sc


static func scaled_wing(host: PlatformSpec, total: int, callsign: String) -> Array:
	var out: Array = []
	var original := 0
	for pid in host.default_air_wing:
		original += int(host.default_air_wing[pid])
	var remaining := mini(total, host.aircraft_capacity)
	for pid: String in host.default_air_wing:
		if remaining <= 0:
			break
		var n := mini(remaining, maxi(1, roundi(float(host.default_air_wing[pid]) / maxf(original, 1) * total)))
		out.append({"platform": pid, "count": n, "callsign": "%s %s" % [callsign, DataDB.platform(pid).short_name]})
		remaining -= n
	if remaining > 0 and not out.is_empty():
		out[0]["count"] += remaining
	return out


static func _water_point(start: Vector2, land: Array[Landmass], occupied: Array[Vector2] = []) -> Vector2:
	if not _on_land(start, land) and _clear_point(start, occupied):
		return start
	for ring in range(1, 81):
		for sector in 24:
			var p := start + Geo.heading_to_vector(sector * 15.0) * ring * 2.0
			if not _on_land(p, land) and _clear_point(p, occupied):
				return p
	return start


static func _clear_point(point: Vector2, occupied: Array[Vector2]) -> bool:
	for other in occupied:
		if point.distance_squared_to(other) < 0.64:
			return false
	return true


static func _on_land(point: Vector2, land: Array[Landmass]) -> bool:
	for l in land:
		if l.contains(point):
			return true
	return false


static func structural_problem(sc: Dictionary) -> String:
	for key: String in ["map", "environment", "objectives", "terrain"]:
		if sc.has(key) and typeof(sc[key]) != TYPE_DICTIONARY:
			return "%s must be an object" % key
	for key: String in ["id", "name", "player_faction", "victory_mode"]:
		if sc.has(key) and typeof(sc[key]) != TYPE_STRING:
			return "%s must be text" % key
	if sc.has("victory_mode") and sc["victory_mode"] not in ["all", "any"]:
		return "Choose all or any for victory mode"
	if not _valid_number(sc.get("map", {}).get("extent_nm", 220)) or float(sc.get("map", {}).get("extent_nm", 220)) <= 0:
		return "map.extent_nm needs a positive finite number"
	var map_data: Dictionary = sc.get("map", {})
	for key: String in ["anchor_lat", "anchor_lon", "focus_extent_nm"]:
		if map_data.has(key) and not _valid_number(map_data[key]):
			return "map.%s needs a finite number" % key
	for key: String in ["center_nm", "focus_center_nm"]:
		if map_data.has(key) and not _valid_pair(map_data[key]):
			return "map.%s needs two finite numbers" % key
	if map_data.has("chart_region") and typeof(map_data.chart_region) != TYPE_STRING:
		return "map.chart_region must be text"
	if map_data.has("open_water") and typeof(map_data.open_water) != TYPE_BOOL:
		return "map.open_water must be true or false"
	if map_data.has("charted_nm"):
		if typeof(map_data.charted_nm) != TYPE_ARRAY or map_data.charted_nm.size() != 4:
			return "map.charted_nm needs four finite numbers"
		for number in map_data.charted_nm:
			if not _valid_number(number):
				return "map.charted_nm needs four finite numbers"
	if typeof(map_data.get("labels", [])) != TYPE_ARRAY:
		return "map.labels must be an array"
	for label in map_data.get("labels", []):
		if typeof(label) != TYPE_DICTIONARY or typeof(label.get("text", "")) != TYPE_STRING or not _valid_pair(label.get("position_nm", null)):
			return "A map label needs text and a position with two finite numbers"
	for key: String in ["text"]:
		if sc.get("objectives", {}).has(key) and typeof(sc.objectives[key]) != TYPE_STRING:
			return "objectives.%s must be text" % key
	if typeof(sc.get("units", [])) != TYPE_ARRAY:
		return "units must be an array"
	for key: String in ["victory", "loss"]:
		if typeof(sc.get("objectives", {}).get(key, [])) != TYPE_ARRAY:
			return "objectives.%s must be an array" % key
		for objective in sc.get("objectives", {}).get(key, []):
			if typeof(objective) != TYPE_DICTIONARY:
				return "Every objective must be an object"
			for text_key: String in ["id", "type", "text", "faction", "facility", "caused_by"]:
				if objective.has(text_key) and typeof(objective[text_key]) != TYPE_STRING:
					return "Objective %s must be text" % text_key
			if objective.has("phase_only") and typeof(objective.phase_only) != TYPE_BOOL:
				return "Objective phase_only must be true or false"
			for array_key: String in ["callsigns", "after"]:
				if typeof(objective.get(array_key, [])) != TYPE_ARRAY:
					return "Objective %s must be an array" % array_key
				for name in objective.get(array_key, []):
					if typeof(name) != TYPE_STRING:
						return "Objective %s entries must be text" % array_key
			for number_key: String in ["seconds", "radius_nm", "count", "max_alive"]:
				if objective.has(number_key) and (not _valid_number(objective[number_key]) or float(objective[number_key]) < 0):
					return "Objective %s needs a non-negative finite number" % number_key
			if objective.has("center_nm") and not _valid_pair(objective["center_nm"]):
				return "An objective center needs two finite numbers"
	for unit in sc.get("units", []):
		if typeof(unit) != TYPE_DICTIONARY:
			return "Every unit must be an object"
		if unit.has("follow_route") and typeof(unit["follow_route"]) != TYPE_BOOL:
			return "Unit follow_route must be true or false"
		for key: String in ["callsign", "platform", "faction", "home", "formation_leader", "defence_policy", "ai_plan", "ai_role"]:
			if unit.has(key) and typeof(unit[key]) != TYPE_STRING:
				return "Unit %s must be text" % key
		for key: String in ["heading_deg", "speed_kn", "depth_m", "editor_arrival_s", "decoys", "torpedo_decoys"]:
			if unit.has(key) and not _valid_number(unit[key]):
				return "Unit %s needs a finite number" % key
			if key != "heading_deg" and float(unit.get(key, 0)) < 0:
				return "Unit %s cannot be negative" % key
		for key: String in ["position_nm", "formation_offset_nm"]:
			if unit.has(key) and not _valid_pair(unit[key]):
				return "%s.%s needs two finite numbers" % [unit.get("callsign", "Unit"), key]
		for key: String in ["loadout", "aviation_stores"]:
			if unit.has(key) and typeof(unit[key]) != TYPE_DICTIONARY:
				return "%s.%s must be an object" % [unit.get("callsign", "Unit"), key]
			for wid in unit.get(key, {}):
				var rounds = unit[key][wid]
				if typeof(wid) != TYPE_STRING or not _valid_number(rounds) or float(rounds) < 0 or float(rounds) != floor(float(rounds)):
					return "%s.%s needs whole non-negative round counts" % [unit.get("callsign", "Unit"), key]
		if unit.has("air_wing") and typeof(unit["air_wing"]) != TYPE_ARRAY:
			return "air_wing must be an array"
		for wing in unit.get("air_wing", []):
			if typeof(wing) != TYPE_DICTIONARY or not _valid_number(wing.get("count", 0)):
				return "An air-wing entry needs a platform and numeric count"
			if typeof(wing.get("platform", "")) != TYPE_STRING or float(wing.get("count", 0)) < 0 or float(wing.get("count", 0)) != floor(float(wing.get("count", 0))):
				return "An air-wing entry needs a platform and whole non-negative count"
			var problem := structural_problem({"units": [{"callsign": "Air wing", "loadout": wing.get("loadout", {}), "patrol_nm": wing.get("patrol_nm", []), "ai_plan": wing.get("ai_plan", ""), "ai_role": wing.get("ai_role", "")}]})
			if problem != "":
				return problem
		if typeof(unit.get("patrol_nm", [])) != TYPE_ARRAY:
			return "patrol_nm must be an array"
		for leg in unit.get("patrol_nm", []):
			if not _valid_pair(leg):
				return "A patrol leg needs two finite numbers"
	if not _valid_pair(sc.get("map", {}).get("center_nm", [0, 0])):
		return "map.center_nm needs two finite numbers"
	if typeof(sc.get("events", [])) != TYPE_ARRAY:
		return "events must be an array"
	for event in sc.get("events", []):
		if typeof(event) != TYPE_DICTIONARY or typeof(event.get("reinforcements", [])) != TYPE_ARRAY:
			return "A wave needs an object with a reinforcements array"
		if not _valid_number(event.get("at_s", 0)) or float(event.get("at_s", 0)) < 0:
			return "A reinforcement wave needs a non-negative arrival time"
		var problem := structural_problem({"units": event.get("reinforcements", [])})
		if problem != "":
			return problem
	# Opposing-force mission plans (AIPlan). The loader skips a malformed one with a warning; the
	# editor refuses it, so an author finds out before the plan silently does nothing.
	if typeof(sc.get("ai_plans", [])) != TYPE_ARRAY:
		return "ai_plans must be an array"
	for plan in sc.get("ai_plans", []):
		if typeof(plan) != TYPE_DICTIONARY:
			return "Every AI plan must be an object"
		var problem := AIPlan.definition_problem(plan)
		if problem != "":
			return problem
	if typeof(sc.get("terrain", {}).get("land", [])) != TYPE_ARRAY:
		return "terrain.land must be an array"
	for island in sc.get("terrain", {}).get("land", []):
		if typeof(island) != TYPE_DICTIONARY or typeof(island.get("points_nm", [])) != TYPE_ARRAY:
			return "A coastline needs an object with points_nm vertices"
		for point in island.get("points_nm", []):
			if not _valid_pair(point):
				return "A coastline vertex needs two finite numbers"
		if not _valid_number(island.get("elevation_m", 150)):
			return "A coastline elevation needs a finite number"
	return ""


static func _valid_pair(value) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != 2:
		return false
	for number in value:
		if typeof(number) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(number)):
			return false
	return true


static func _valid_number(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func validate(sc: Dictionary) -> String:
	var problem := structural_problem(sc)
	if problem != "":
		return problem
	if str(sc.get("name", "")).strip_edges() == "":
		return "Give the mission a name"
	var units: Array = sc.get("units", []).duplicate(true)
	var arrivals: Dictionary = {}
	var player_count := 0
	for u: Dictionary in sc.get("units", []):
		arrivals[str(u.get("callsign", ""))] = float(u.get("editor_arrival_s", 0))
		if u.get("faction", "BLUE") == sc.get("player_faction", "BLUE") and float(u.get("editor_arrival_s", 0)) == 0:
			player_count += 1
	for event in sc.get("events", []):
		units.append_array(event.get("reinforcements", []))
		for u: Dictionary in event.get("reinforcements", []):
			arrivals[str(u.get("callsign", ""))] = float(event.get("at_s", 0))
	if units.size() > 300:
		return "Keep the authored fleet below 300 units"
	var names: Dictionary = {}
	var land: Array[Landmass] = []
	for entry in sc.get("terrain", {}).get("land", []):
		var island := Landmass.from_dict(entry)
		if not island.valid():
			return "A coastline needs at least three vertices"
		land.append(island)
	for u: Dictionary in units:
		var name := str(u.get("callsign", "")).strip_edges()
		if name == "" or names.has(name):
			return "Every unit needs a unique callsign: %s" % name
		names[name] = u
		var spec := DataDB.platform(str(u.get("platform", "")))
		if spec == null:
			return "Unknown platform on %s" % name
		if spec.domain != "air" and not u.has("position_nm"):
			return "%s needs a chart position" % name
		if float(u.get("speed_kn", 0)) < 0 or float(u.get("speed_kn", 0)) > spec.max_speed_kn:
			return "%s speed exceeds its platform limit" % name
		var cells := 0
		for wid: String in u.get("loadout", spec.weapon_loadout):
			var weapon := DataDB.weapon(wid)
			var rounds := int(u.get("loadout", spec.weapon_loadout)[wid])
			if weapon == null or not spec.weapon_loadout.has(wid) or rounds < 0:
				return "%s has an incompatible weapon fit: %s" % [name, wid]
			if weapon.vls_pack > 0:
				cells += ceili(float(rounds) / weapon.vls_pack)
			if (weapon.vls_pack <= 0 or spec.vls_cells <= 0) and rounds > int(spec.weapon_loadout[wid]):
				return "%s exceeds the installed %s magazine" % [name, wid]
		if spec.vls_cells > 0 and cells > spec.vls_cells:
			return "%s needs %d VLS cells, but has %d" % [name, cells, spec.vls_cells]
		if spec.domain in ["surface", "subsurface"]:
			var point: Array = u.get("position_nm", [0, 0])
			if _on_land(Vector2(point[0], point[1]), land):
				return "%s starts ashore" % name
			for leg in u.get("patrol_nm", []):
				if _on_land(Vector2(leg[0], leg[1]), land):
					return "%s patrol waypoint is ashore" % name
	if player_count == 0:
		return "Place a player unit at the start of the mission"
	for u: Dictionary in units:
		var leader_name := str(u.get("formation_leader", ""))
		if leader_name == "":
			continue
		if not names.has(leader_name) or leader_name == u["callsign"]:
			return "%s needs a different existing formation leader" % u["callsign"]
		var leader: Dictionary = names[leader_name]
		if leader.get("faction", "BLUE") != u.get("faction", "BLUE") or DataDB.platform(str(leader["platform"])).domain != DataDB.platform(str(u["platform"])).domain:
			return "%s needs a friendly formation leader in the same domain" % u["callsign"]
		if float(arrivals[leader_name]) > float(arrivals[u["callsign"]]):
			return "%s arrives before its formation leader" % u["callsign"]
		var visited: Dictionary = {u["callsign"]: true}
		var next := leader_name
		while next != "" and names.has(next):
			if visited.has(next):
				return "Formation leaders form a cycle"
			visited[next] = true
			next = str(names[next].get("formation_leader", ""))
	for u: Dictionary in units:
		var spec := DataDB.platform(str(u["platform"]))
		var embarked := 0
		for entry in u.get("air_wing", []):
			if typeof(entry) != TYPE_DICTIONARY:
				return "Every air-wing entry needs a platform and count"
			var aircraft := DataDB.platform(str(entry.get("platform", "")))
			if not spec.can_operate(aircraft) or int(entry.get("count", 0)) < 0:
				return "%s cannot operate that air-wing entry" % u["callsign"]
			for wid: String in entry.get("loadout", {}):
				if not aircraft.weapon_loadout.has(wid) or int(entry["loadout"][wid]) > int(aircraft.weapon_loadout[wid]):
					return "%s air wing has an incompatible weapon fit" % u["callsign"]
			embarked += int(entry.get("count", 0))
		for a: Dictionary in units:
			if a.get("home", "") == u["callsign"]:
				embarked += 1
		if embarked > spec.aircraft_capacity:
			return "%s air wing exceeds %d aircraft" % [u["callsign"], spec.aircraft_capacity]
		var home_name := str(u.get("home", ""))
		if home_name != "":
			if not names.has(home_name):
				return "%s has no home %s" % [u["callsign"], home_name]
			var host: Dictionary = names[home_name]
			if host.get("faction", "BLUE") != u.get("faction", "BLUE") or not DataDB.platform(str(host["platform"])).can_operate(spec):
				return "%s needs a compatible friendly deck" % u["callsign"]
			if float(arrivals[home_name]) > float(arrivals[u["callsign"]]):
				return "%s arrives before its home base" % u["callsign"]
	var objectives: Dictionary = sc.get("objectives", {})
	if objectives.get("victory", []).is_empty():
		return "Add a victory task"
	var ids: Dictionary = {}
	for o: Dictionary in objectives.get("victory", []):
		var id := str(o.get("id", ""))
		if id == "" or ids.has(id):
			return "Victory tasks need unique IDs"
		ids[id] = o
	for key: String in ["victory", "loss"]:
		for o: Dictionary in objectives.get(key, []):
			if not MissionObjective.KIND_NAMES.has(str(o.get("type", ""))):
				return "Unknown objective type: %s" % o.get("type", "")
			if str(o.get("caused_by", "")) != "":
				if o.get("type", "") != "unit_lost":
					return "A caused_by filter is only supported on a unit-lost task"
				if o.get("callsigns", []).is_empty():
					return "An attributed-loss task needs named units"
				if not units.any(func(u: Dictionary) -> bool: return u.get("faction", "BLUE") == o["caused_by"]):
					return "An attributed-loss task needs an existing responsible faction"
			if o.get("type", "") == "force_destroyed" and not units.any(func(u: Dictionary) -> bool: return u.get("faction", "BLUE") == o.get("faction", "RED")):
				return "A destroy-force task needs an opposing force"
			for callsign in o.get("callsigns", []):
				if not names.has(callsign):
					return "An objective names missing unit %s" % callsign
			if o.has("center_nm") and not _valid_pair(o["center_nm"]):
				return "An objective area needs two finite coordinates"
			if o.has("radius_nm") and float(o["radius_nm"]) <= 0:
				return "An objective area needs a positive radius"
			for prerequisite in o.get("after", []):
				if not ids.has(prerequisite):
					return "Unknown task prerequisite %s" % prerequisite
	for id: String in ids:
		if _cycle(id, ids, {}):
			return "Task prerequisites form a cycle"
	return _plans_problem(sc, names, units)


## Every opposing-force plan names units that exist and are on its side and has what its kind needs;
## every unit or air-wing entry tagged for a plan names one that exists for its own side. Plan
## callsigns are scenario units and reinforcements: an embarked aircraft joins a plan with its deck,
## or by a tag on its air-wing entry.
static func _plans_problem(sc: Dictionary, names: Dictionary, units: Array) -> String:
	var plans: Dictionary = {}
	for plan: Dictionary in sc.get("ai_plans", []):
		var pid := str(plan["id"])
		if plans.has(pid):
			return "AI plan IDs must be unique: %s" % pid
		plans[pid] = plan
		var side := str(plan["faction"])
		if sc.get("neutral_factions", []).has(side):
			return "AI plan %s cannot belong to a neutral side" % pid
		var named: Array = []
		named.append_array(plan.get("units", []))
		named.append_array(plan.get("protect", []))
		for entry in plan.get("recon", []):
			if typeof(entry) == TYPE_STRING:
				named.append(entry)
				continue
			named.append(entry["base"])
			if DataDB.platform(str(entry["platform"])) == null:
				return "AI plan %s asks for reconnaissance by unknown aircraft %s" % [pid, entry["platform"]]
			if not plan.has("objective_nm"):
				return "AI plan %s needs an objective for its air reconnaissance" % pid
		for callsign in named:
			if not names.has(callsign):
				return "AI plan %s names missing unit %s" % [pid, callsign]
			if str(names[callsign].get("faction", "BLUE")) != side:
				return "AI plan %s names %s, which is not on its side" % [pid, callsign]
		match str(plan["kind"]):
			"protect_breakout":
				if plan.get("protect", []).is_empty():
					return "AI plan %s needs the units it protects" % pid
			"defend_installation":
				if not plan.has("objective_nm") and plan.get("protect", []).is_empty():
					return "AI plan %s needs an objective or an installation to defend" % pid
	for u: Dictionary in units:
		var tagged: Array = [u]
		for entry in u.get("air_wing", []):
			if typeof(entry) == TYPE_DICTIONARY:
				tagged.append(entry)
		for entry: Dictionary in tagged:
			var pid := str(entry.get("ai_plan", ""))
			if pid != "" and (not plans.has(pid) or str(plans[pid]["faction"]) != str(u.get("faction", "BLUE"))):
				return "%s is tagged for missing AI plan %s" % [u.get("callsign", "A unit"), pid]
			var role := str(entry.get("ai_role", ""))
			if role != "" and not AIPlan.ROLES.has(role):
				return "%s has unknown AI role %s" % [u.get("callsign", "A unit"), role]
	return ""


static func _cycle(id: String, ids: Dictionary, visited: Dictionary) -> bool:
	if visited.has(id):
		return true
	var next := visited.duplicate()
	next[id] = true
	for parent: String in ids[id].get("after", []):
		if _cycle(parent, ids, next):
			return true
	return false


## Wave units remain editable on the chart. Export turns their arrival times into runtime events
## and gates destroy-force tasks until that faction's final scheduled wave has arrived.
static func export_scenario(sc: Dictionary) -> Dictionary:
	var out := sc.duplicate(true)
	var opening: Array = []
	var waves: Dictionary = {}
	var latest: Dictionary = {}
	var events: Array = out.get("events", []).duplicate(true)
	for u: Dictionary in out.get("units", []):
		var arrival := maxf(float(u.get("editor_arrival_s", 0)), 0)
		u.erase("editor_arrival_s")
		if arrival <= 0:
			opening.append(u)
		else:
			var key := str(int(arrival))
			if not waves.has(key):
				waves[key] = []
			waves[key].append(u)
			var faction := str(u.get("faction", "RED"))
			latest[faction] = maxf(float(latest.get(faction, 0)), arrival)
	for key: String in waves:
		events.append({"id": "editor_wave_%s" % key, "editor_wave": true, "at_s": int(key), "reinforcements": waves[key]})
	for event: Dictionary in events:
		for u: Dictionary in event.get("reinforcements", []):
			var faction := str(u.get("faction", "RED"))
			latest[faction] = maxf(float(latest.get(faction, 0)), float(event.get("at_s", 0)))
	var gates: Array = []
	for o: Dictionary in out.get("objectives", {}).get("victory", []):
		var faction := str(o.get("faction", "RED"))
		if o.get("type", "") == "force_destroyed" and float(latest.get(faction, 0)) > 0:
			var gate := "waves_arrived_%s" % faction.to_lower()
			var after: Array = o.get("after", []).duplicate()
			if not after.has(gate):
				after.append(gate)
			o["after"] = after
			var exists := false
			for existing in gates:
				exists = exists or existing["id"] == gate
			for existing in out["objectives"]["victory"]:
				exists = exists or existing.get("id", "") == gate
			if not exists:
				gates.append({"id": gate, "type": "time_elapsed", "seconds": latest[faction], "phase_only": true, "text": "All %s reinforcement waves have arrived" % faction})
	if not gates.is_empty():
		out["objectives"]["victory"].append_array(gates)
	out["units"] = opening
	out["events"] = events
	return out
