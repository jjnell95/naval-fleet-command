class_name ScenarioLoader
## Loads scenario JSON from data/scenarios and populates a UnitManager.
##
## Aviation is expanded here rather than listed airframe by airframe. A scenario names a ship and
## the loader gives it the aircraft it sails with, because a destroyer with an empty hangar is a
## scenario-authoring mistake, not a tactical choice. Three ways to say it, in priority order:
##   * an explicit `air_wing` on the unit: a list of {platform, count, squadron, callsign} entries;
##   * nothing at all, in which case the platform's own `default_air_wing` is embarked;
##   * `"air_wing": []`, which sails the ship with an empty hangar on purpose.
## A separately listed aircraft unit naming this ship as its `home` still works and is counted
## against the same capacity, so hand-placed airframes and detachments do not double up.


static func load_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("ScenarioLoader: cannot open %s" % path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ScenarioLoader: %s is not a JSON object" % path)
		return {}
	return parsed


static func populate(um: UnitManager, scenario: Dictionary) -> void:
	var hosts: Array[Dictionary] = []
	for ud in scenario.get("units", []):
		var spec := DataDB.platform(ud.get("platform", ""))
		if spec == null:
			push_error("ScenarioLoader: unknown platform '%s'" % ud.get("platform", ""))
			continue
		var u := Unit.new()
		u.spec = spec
		u.callsign = ud.get("callsign", spec.short_name)
		u.faction = ud.get("faction", "BLUE")
		var p: Array = ud.get("position_nm", [0, 0])
		u.position = Vector2(p[0], p[1])
		u.heading_deg = fposmod(float(ud.get("heading_deg", 0.0)), 360.0)
		u.ordered_heading_deg = u.heading_deg
		u.speed_kn = clampf(float(ud.get("speed_kn", 0.0)), 0.0, spec.max_speed_kn)
		u.ordered_speed_kn = u.speed_kn
		for sid in spec.sensor_ids:
			var sensor := DataDB.sensor(sid)
			if sensor == null:
				push_warning("ScenarioLoader: unknown sensor '%s' on %s" % [sid, spec.id])
			else:
				u.sensors.append(sensor)
		u.radar_on = bool(ud.get("radar_on", true))
		u.health = spec.health
		u.decoys = int(ud.get("decoys", spec.decoy_count))
		u.torpedo_decoys = int(ud.get("torpedo_decoys", spec.torpedo_decoy_count))
		u.depth_m = clampf(float(ud.get("depth_m", 0.0)), 0.0, spec.max_depth_m)
		u.ordered_depth_m = u.depth_m
		u.ai_posture = ud.get("ai_posture", "standard")
		u.ai_plan_id = str(ud.get("ai_plan", ""))
		u.ai_role = str(ud.get("ai_role", ""))
		u.auto_countermeasures = bool(ud.get("auto_countermeasures", true))
		u.defence_policy = str(ud.get("defence_policy", "balanced"))
		if u.defence_policy not in ["balanced", "conserve", "saturation"]:
			u.defence_policy = "balanced"
		u.defence_priority = int(ud.get("defence_priority", 2 if spec.category.contains("carrier") else 0))
		u.points = maxi(int(ud.get("points", 0)), 0)
		u.home_callsign = ud.get("home", "")
		if spec.domain == "air":
			u.flight_state = Unit.FlightState.STOWED
			u.fuel_s = spec.endurance_s
			u.sonobuoys = spec.sonobuoy_count
			u.tanker_offload_s = spec.tanker_offload_s
			u.ordered_altitude_m = spec.cruise_altitude_m
		for leg in ud.get("patrol_nm", []):
			u.patrol_route.append(Vector2(leg[0], leg[1]))
		# Opening convoy orders use the editor's route data without handing the player to AI.
		if bool(ud.get("follow_route", false)):
			for i in u.patrol_route.size():
				u.apply_order(Order.move(u.patrol_route[i], i > 0))
		u.squadron = str(ud.get("squadron", ""))
		var loadout: Dictionary = ud.get("loadout", spec.weapon_loadout)
		for wid in loadout:
			var wspec := DataDB.weapon(wid)
			if wspec == null:
				push_warning("ScenarioLoader: unknown weapon '%s' on %s" % [wid, spec.id])
				continue
			u.weapons.append(wspec)
			u.magazines[wid] = int(loadout[wid])
		if u.is_aircraft():
			u.sortie_loadout = u.magazines.duplicate()
		um.add_unit(u)
		hosts.append({"unit": u, "data": ud})
	_link_aircraft(um)
	_link_formations(um, hosts)
	for host: Dictionary in hosts:
		_embark_air_wing(um, host["unit"], host["data"])
	for host: Dictionary in hosts:
		_stock_aviation(host["unit"], host["data"])
	_launch_off_map_aircraft(um)
	_check_sea_room(um)
	var sensor_count := 0
	for u in um.units: sensor_count += u.sensors.size()
	Debug.event("[Scenario] %d actors / %d sensor installations" % [um.units.size(), sensor_count])


static func _link_formations(um: UnitManager, hosts: Array[Dictionary]) -> void:
	for entry in hosts:
		var name := str(entry["data"].get("formation_leader", ""))
		if name == "":
			continue
		var u: Unit = entry["unit"]
		for leader in um.units:
			if leader.callsign != name or not Formation.can_join(u, leader):
				continue
			var offset: Array = entry["data"].get("formation_offset_nm", [3, -3])
			if offset.size() >= 2:
				u.apply_order(Order.form_up(leader, Vector2(offset[0], offset[1])))
			break


## A hull placed ashore, or sent to a patrol leg ashore, is the first thing a scenario author gets
## wrong once coastlines exist: the ship never arrives and the route never advances. The AI stands
## such a leg off into open water at run time, but saying so at load is what makes it findable.
static func _check_sea_room(um: UnitManager) -> void:
	if Terrain.is_empty():
		return
	for u in um.units:
		if not u.needs_sea_room():
			continue
		if Terrain.is_land(u.position):
			push_warning("ScenarioLoader: %s starts ashore at %s" % [u.callsign, u.position])
		for leg in u.patrol_route:
			if Terrain.is_land(leg):
				push_warning("ScenarioLoader: %s has a patrol leg ashore at %s" % [u.callsign, leg])


## Aircraft name their parent by callsign, so the link is resolved once every unit exists.
static func _link_aircraft(um: UnitManager) -> void:
	for a in um.units:
		if not a.alive or not a.is_aircraft() or a.home_callsign == "" or a.home != null:
			continue
		for candidate in um.units:
			if candidate.callsign == a.home_callsign and candidate.faction == a.faction and candidate.spec.can_operate(a.spec) and candidate.embarked.size() < candidate.spec.aircraft_capacity:
				a.home = candidate
				candidate.embarked.append(a)
				break
		if a.home == null:
			push_warning("ScenarioLoader: %s has no home '%s'" % [a.callsign, a.home_callsign])
		else:
			a.position = a.home.position


## Puts a ship's aircraft in its hangar. This is where "a destroyer carries a helicopter" stops
## being a property of the data model and becomes something the player actually has.
static func _embark_air_wing(um: UnitManager, host: Unit, data: Dictionary) -> void:
	if host.spec.aircraft_capacity <= 0:
		return
	var authored: bool = data.has("air_wing")
	var wing: Array = data.get("air_wing", _default_wing(host.spec))
	if wing.is_empty():
		return
	for entry in wing:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var spec := DataDB.platform(str(entry.get("platform", "")))
		if spec == null:
			push_warning("ScenarioLoader: unknown aircraft '%s' in %s air wing" % [entry.get("platform", ""), host.callsign])
			continue
		if not host.spec.can_operate(spec):
			push_warning("ScenarioLoader: %s cannot operate %s" % [host.callsign, spec.id])
			continue
		var squadron := str(entry.get("squadron", ""))
		var base_call := str(entry.get("callsign", ""))
		if base_call == "":
			base_call = squadron if squadron != "" else _det_callsign(host)
		var first := int(entry.get("first_modex", 1 if entry.has("callsign") or squadron != "" else 60))
		for i in maxi(int(entry.get("count", 1)), 0):
			if host.embarked.size() >= host.spec.aircraft_capacity:
				# An authored wing that does not fit is an error worth seeing. A default
				# detachment simply takes whatever room a scenario's own airframes left it.
				if authored:
					push_warning("ScenarioLoader: %s air wing exceeds capacity %d" % [host.callsign, host.spec.aircraft_capacity])
				return
			var a := _spawn_aircraft(spec, host, "%s %d" % [base_call, first + i], squadron)
			if entry.has("loadout"):
				a.weapons.clear()
				a.magazines.clear()
				for wid: String in entry["loadout"]:
					var weapon := DataDB.weapon(wid)
					if weapon != null and spec.weapon_loadout.has(wid):
						a.weapons.append(weapon)
						a.magazines[wid] = maxi(int(entry["loadout"][wid]), 0)
			a.sortie_loadout = a.magazines.duplicate()
			if float(entry.get("ready_after_s", 0.0)) > 0.0:
				a.flight_state = Unit.FlightState.RESERVE
				a.state_timer_s = float(entry["ready_after_s"])
			for leg in entry.get("patrol_nm", []):
				a.patrol_route.append(Vector2(leg[0], leg[1]))
			# An element of a raid can be tagged into a plan by itself, without its whole airfield.
			a.ai_plan_id = str(entry.get("ai_plan", ""))
			a.ai_role = str(entry.get("ai_role", ""))
			um.add_unit(a)


## What a platform sails with when the scenario does not say. Ships list this on the spec, so a
## Burke picks up its helicopter detachment in every scenario without an author remembering to.
static func _default_wing(spec: PlatformSpec) -> Array:
	var out: Array = []
	var modex := 60
	for pid in spec.default_air_wing:
		var n := int(spec.default_air_wing[pid])
		out.append({"platform": pid, "count": n, "first_modex": modex})
		modex += 10  # each type in the det gets its own block, the way a ship numbers its flight
	return out


## What to call a ship's own detachment when the scenario does not name it. An embarked flight
## is known by the ship it flies off, so "USS Truxtun (DDG 103)" puts up "Truxtun 60" rather than
## a second airframe called MH-60R. Pennant numbers and service prefixes are stripped; what is
## left is the name people actually say on the radio.
static func _det_callsign(host: Unit) -> String:
	var name := host.callsign
	var bracket := name.find(" (")
	if bracket > 0:
		name = name.substr(0, bracket)
	var words := name.split(" ", false)
	if words.is_empty():
		return host.spec.short_name
	return words[words.size() - 1]


static func _spawn_aircraft(spec: PlatformSpec, host: Unit, callsign: String, squadron: String) -> Unit:
	var a := Unit.new()
	a.spec = spec
	a.faction = host.faction
	a.callsign = callsign
	a.squadron = squadron
	a.position = host.position
	a.heading_deg = host.heading_deg
	a.ordered_heading_deg = host.heading_deg
	a.health = spec.health
	a.decoys = spec.decoy_count
	a.torpedo_decoys = spec.torpedo_decoy_count
	a.flight_state = Unit.FlightState.STOWED
	a.fuel_s = spec.endurance_s
	a.sonobuoys = spec.sonobuoy_count
	a.tanker_offload_s = spec.tanker_offload_s
	a.ordered_altitude_m = spec.cruise_altitude_m
	a.home = host
	a.home_callsign = host.callsign
	host.embarked.append(a)
	for sid in spec.sensor_ids:
		var sensor := DataDB.sensor(sid)
		if sensor != null:
			a.sensors.append(sensor)
	for wid in spec.weapon_loadout:
		var w := DataDB.weapon(wid)
		if w == null:
			push_warning("ScenarioLoader: unknown weapon '%s' on %s" % [wid, spec.id])
			continue
		a.weapons.append(w)
		a.magazines[wid] = int(spec.weapon_loadout[wid])
	a.sortie_loadout = a.magazines.duplicate()
	return a


## An aircraft a scenario places with no deck on the chart flew from a field beyond it, so it is
## already up: it has no hangar to wait in. Left stowed it would sit at its start position for the
## whole scenario, invisible and useless, which is the failure mode this exists to prevent.
static func _launch_off_map_aircraft(um: UnitManager) -> void:
	for a in um.units:
		if not a.alive or not a.is_aircraft() or a.home != null or a.flight_state != Unit.FlightState.STOWED:
			continue
		a.flight_state = Unit.FlightState.AIRBORNE
		a.altitude_m = a.spec.cruise_altitude_m
		a.ordered_altitude_m = a.spec.cruise_altitude_m
		if a.ordered_speed_kn <= 0.0:
			a.ordered_speed_kn = a.spec.cruise_speed_kn
			a.speed_kn = a.spec.cruise_speed_kn


## Two extra full wing reloads by default, in addition to weapons already on the aircraft.
## Scenario authors may provide exact limited stocks. These are game endurance budgets,
## never a claim about real carrier magazine capacities.
static func _stock_aviation(host: Unit, data: Dictionary) -> void:
	if host.spec.aircraft_capacity <= 0:
		return
	host.aviation_stores.clear()
	host.aviation_buoys = 0
	var reloads := maxi(int(data.get("aviation_reload_cycles", 2)), 0)
	for a in host.embarked:
		for wid: String in a.magazines:
			host.aviation_stores[wid] = int(host.aviation_stores.get(wid, 0)) + int(a.magazines[wid]) * reloads
		host.aviation_buoys += a.spec.sonobuoy_count * reloads
	if data.has("aviation_stores"):
		host.aviation_stores.clear()
		for wid: String in data["aviation_stores"]:
			host.aviation_stores[wid] = maxi(int(data["aviation_stores"][wid]), 0)
	host.aviation_buoys = maxi(int(data.get("aviation_buoys", host.aviation_buoys)), 0)


static func start_unix_time(scenario: Dictionary) -> int:
	var s: String = scenario.get("start_time_utc", "")
	return Time.get_unix_time_from_datetime_string(s) if s != "" else 0
