class_name ScenarioLoader
## Loads scenario JSON from data/scenarios and populates a UnitManager.
## Full objective/victory handling arrives in Milestone 6; this is the minimal spawn path.


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
		u.depth_m = clampf(float(ud.get("depth_m", 0.0)), 0.0, spec.max_depth_m)
		u.ordered_depth_m = u.depth_m
		u.ai_posture = ud.get("ai_posture", "standard")
		u.home_callsign = ud.get("home", "")
		if spec.domain == "air":
			u.flight_state = Unit.FlightState.STOWED
			u.fuel_s = spec.endurance_s
			u.sonobuoys = spec.sonobuoy_count
			u.ordered_altitude_m = spec.cruise_altitude_m
		for leg in ud.get("patrol_nm", []):
			u.patrol_route.append(Vector2(leg[0], leg[1]))
		var loadout: Dictionary = ud.get("loadout", spec.weapon_loadout)
		for wid in loadout:
			var wspec := DataDB.weapon(wid)
			if wspec == null:
				push_warning("ScenarioLoader: unknown weapon '%s' on %s" % [wid, spec.id])
				continue
			u.weapons.append(wspec)
			u.magazines[wid] = int(loadout[wid])
		um.add_unit(u)
	_link_aircraft(um)
	_check_sea_room(um)
	var sensor_count := 0
	for u in um.units: sensor_count += u.sensors.size()
	print("[Scenario] %d actors / %d sensor installations" % [um.units.size(), sensor_count])


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
		if not a.is_aircraft() or a.home_callsign == "":
			continue
		for candidate in um.units:
			if candidate.callsign == a.home_callsign:
				a.home = candidate
				candidate.embarked.append(a)
				break
		if a.home == null:
			push_warning("ScenarioLoader: %s has no home '%s'" % [a.callsign, a.home_callsign])
		else:
			a.position = a.home.position


static func start_unix_time(scenario: Dictionary) -> int:
	var s: String = scenario.get("start_time_utc", "")
	return Time.get_unix_time_from_datetime_string(s) if s != "" else 0
