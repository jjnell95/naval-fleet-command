class_name Formation
## Station keeping. FORM_UP is the order; this is the control law that carries it out, the same
## way Movement carries out a waypoint. A unit in formation surrenders its own steering until it
## is told to break.

const STATION_TOLERANCE_NM := 0.4
const CATCHUP_GAIN := 2.0

## Offsets are given in the leader's frame: x to starboard, y ahead, in nautical miles.
const PATTERNS := {
	"screen": [Vector2(-4.0, 6.0), Vector2(4.0, 6.0), Vector2(-7.0, 1.0), Vector2(7.0, 1.0), Vector2(0.0, 9.0)],
	"column": [Vector2(0.0, -1.5), Vector2(0.0, -3.0), Vector2(0.0, -4.5), Vector2(0.0, -6.0), Vector2(0.0, -7.5)],
	"abreast": [Vector2(2.5, 0.0), Vector2(-2.5, 0.0), Vector2(5.0, 0.0), Vector2(-5.0, 0.0), Vector2(7.5, 0.0)],
}


## Where this unit should be, given where its leader is and which way the leader is pointing.
static func station_for(u: Unit) -> Vector2:
	var leader := u.formation_leader
	var axis := leader.heading_deg if u.formation_axis_deg < 0.0 else u.formation_axis_deg
	var ahead := Geo.heading_to_vector(axis)
	var starboard := Geo.heading_to_vector(axis + 90.0)
	var station := leader.position + ahead * u.formation_offset.y + starboard * u.formation_offset.x
	if not u.needs_sea_room():
		return station
	# A screen station reaches seven miles abeam, so it falls ashore as soon as the group closes a
	# coast. A consort holding a degraded station is worth more than one steaming at a beach.
	return Terrain.nearest_water(station, leader.position)


## Steers one unit toward its station. Runs before Movement each tick.
static func step(u: Unit) -> void:
	if not u.in_formation() or u.evasion_remaining_s > 0:
		return
	var leader := u.formation_leader
	var station := station_for(u)
	var gap := u.position.distance_to(station)
	u.waypoints.clear()
	if gap <= STATION_TOLERANCE_NM:
		u.ordered_heading_deg = leader.heading_deg
		u.ordered_speed_kn = clampf(leader.speed_kn, 0.0, u.effective_max_speed())
		return
	u.ordered_heading_deg = Geo.bearing_deg(u.position, station)
	# Close the gap without overshooting: match the leader and add a little for the distance.
	u.ordered_speed_kn = clampf(leader.speed_kn + gap * CATCHUP_GAIN, 1.0, u.effective_max_speed())


## The first unit remains the commander's guide. Role screens rank eligible consorts by fitted
## weapons and sensors; geometric patterns retain selection order. A supplied threat bearing is
## held in world coordinates, so a course alteration does not turn the screen away from danger.
## Returns the orders to issue, so the caller still goes through the normal command path.
static func assign(units: Array, pattern: String, spacing := 1.0, threat_axis_deg := -1.0) -> Array:
	var out: Array = []
	if units.size() < 2:
		return out
	var leader: Unit = units[0]
	var consorts: Array = []
	for i in range(1, units.size()):
		if can_join(units[i], leader): consorts.append(units[i])
	if pattern in ["aaw_screen", "asw_screen"]:
		consorts.sort_custom(func(a: Unit, b: Unit) -> bool:
			var sa := role_score(a, pattern)
			var sb := role_score(b, pattern)
			return a.id < b.id if is_equal_approx(sa, sb) else sa > sb)
	var station_index := 0
	for u: Unit in consorts:
		var offset := offset_for(station_index, pattern) * clampf(spacing, 0.5, 3.0)
		var order := Order.form_up(leader, offset)
		if pattern in ["aaw_screen", "asw_screen"]:
			order.formation_axis_deg = fposmod(threat_axis_deg, 360.0) if threat_axis_deg >= 0.0 else -1.0
		out.append({"unit": u, "order": order})
		station_index += 1
	return out


static func role_score(u: Unit, pattern: String) -> float:
	var sensor_score := 0.0
	for sensor: SensorSpec in u.sensors:
		if pattern == "aaw_screen" and sensor.kind == "radar":
			sensor_score = maxf(sensor_score, sensor.range_air_nm * 0.1)
		elif pattern == "asw_screen" and sensor.kind == "sonar":
			sensor_score = maxf(sensor_score, 2.0 * (sensor.passive_sensitivity_nm + sensor.active_range_nm))
	var weapon_score := 0.0
	for id in u.spec.weapon_loadout:
		if int(u.magazines.get(id, 0)) <= 0: continue
		var weapon := DataDB.weapon(id)
		if weapon == null: continue
		if (pattern == "aaw_screen" and weapon.target_types.has("air")) or (pattern == "asw_screen" and weapon.target_types.has("subsurface")):
			weapon_score = maxf(weapon_score, weapon.max_range_nm)
	return sensor_score + weapon_score + (float(u.spec.fire_control_channels) if pattern == "aaw_screen" else float(u.spec.aircraft_capacity) * 2.0)


## Stations grow with the force. Modulo-five reuse put the sixth escort on the first escort.
static func offset_for(i: int, pattern: String) -> Vector2:
	match pattern:
		"aaw_screen":
			# Best area-defence unit covers the threat axis; subsequent ships overlap the flanks.
			return Vector2(0, 8) if i == 0 else Vector2((1 if i % 2 == 1 else -1) * (4.0 + floori((i - 1) / 2.0) * 3.0), 4.0)
		"asw_screen":
			# Best listening platform leads ahead; the rest cover both shoulders of the formation.
			return Vector2(0, 6) if i == 0 else Vector2((1 if i % 2 == 1 else -1) * (3.0 + floori((i - 1) / 2.0) * 3.0), 2.0)
		"transit", "column":
			return Vector2(0, -1.5 * (i + 1))
		"abreast":
			return Vector2((1 if i % 2 == 0 else -1) * 2.5 * (floori(i / 2.0) + 1), 0)
		"wedge":
			var rank := floori(i / 2.0) + 1
			return Vector2((1 if i % 2 == 0 else -1) * 3.0 * rank, -3.0 * rank)
		"dispersed":
			return Geo.heading_to_vector(i % 8 * 45.0 + floori(i / 8.0) * 22.5) * (10.0 + floori(i / 8.0) * 8.0)
		_:
			if i < PATTERNS["screen"].size():
				return PATTERNS["screen"][i]
			var n := i - PATTERNS["screen"].size()
			return Geo.heading_to_vector(n % 8 * 45.0 + floori(n / 8.0) * 22.5) * (13.0 + floori(n / 8.0) * 7.0)


static func can_join(u: Unit, leader: Unit) -> bool:
	if u == null or leader == null or u == leader or not u.is_engageable() or not leader.is_engageable():
		return false
	if u.faction != leader.faction or u.spec.domain != leader.spec.domain or u.spec.max_speed_kn <= 0:
		return false
	if u.is_aircraft() and (not u.airborne() or not leader.airborne()):
		return false
	var seen: Dictionary = {}
	var ancestor := leader
	while ancestor != null:
		if ancestor == u or seen.has(ancestor):
			return false
		seen[ancestor] = true
		ancestor = ancestor.formation_leader
	return true


## The flagship paces the slowest consort, including battle damage, while consorts retain speed
## in reserve to regain station. Dead flagships pass command to a surviving group member.
static func update_speed_caps(units: Array) -> void:
	var orphan_groups: Dictionary = {}
	# Consorts away on a task keep their station on the lost guide; they follow the succession too.
	var absent_members: Dictionary = {}
	for u: Unit in units:
		u.formation_speed_cap_kn = INF
		if u.alive and u.formation_leader != null and not u.formation_leader.alive:
			var old := u.formation_leader
			if not orphan_groups.has(old):
				orphan_groups[old] = []
			orphan_groups[old].append(u)
		elif u.alive and u.station_kind == "formation" and u.station_leader != null and not u.station_leader.alive:
			if not absent_members.has(u.station_leader):
				absent_members[u.station_leader] = []
			absent_members[u.station_leader].append(u)
	for old: Unit in orphan_groups:
		var survivors: Array = orphan_groups[old]
		survivors.sort_custom(func(a: Unit, b: Unit) -> bool: return a.id < b.id)
		var successor: Unit = survivors[0]
		successor.formation_leader = null
		_take_guide(successor, old)
		_inherit_plan(successor, old)
		var ahead := Geo.heading_to_vector(successor.heading_deg)
		var right := Geo.heading_to_vector(successor.heading_deg + 90.0)
		for i in range(1, survivors.size()):
			var member: Unit = survivors[i]
			var relative := member.position - successor.position
			if member.formation_axis_deg >= 0.0:
				ahead = Geo.heading_to_vector(member.formation_axis_deg)
				right = Geo.heading_to_vector(member.formation_axis_deg + 90.0)
			else:
				ahead = Geo.heading_to_vector(successor.heading_deg)
				right = Geo.heading_to_vector(successor.heading_deg + 90.0)
			member.formation_leader = successor
			member.formation_offset = Vector2(relative.dot(right), relative.dot(ahead))
			if member.station_kind == "formation" and member.station_leader == old:
				member.station_leader = successor
				member.station_offset = member.formation_offset
		for member: Unit in absent_members.get(old, []):
			member.station_leader = successor  # the same offset, on the new guide
		absent_members.erase(old)
	# Nobody was on station when the guide was lost: the lowest-numbered absent consort guides.
	for old: Unit in absent_members:
		var group: Array = absent_members[old]
		group.sort_custom(func(a: Unit, b: Unit) -> bool: return a.id < b.id)
		var guide: Unit = group[0]
		_take_guide(guide, old)
		if old.station_kind == "patrol" and not guide.has_station():
			guide.set_station("patrol", old.station_label)
			guide.station_route.assign(old.station_route)
			guide.station_speed_kn = old.station_speed_kn
		for i in range(1, group.size()):
			(group[i] as Unit).station_leader = guide
	for u: Unit in units:
		if u.alive and u.in_formation() and u.evasion_remaining_s <= 0:
			var leader := u.formation_leader
			var seen: Dictionary = {}
			while leader != null and leader.alive and not seen.has(leader):
				seen[leader] = true
				leader.formation_speed_cap_kn = minf(leader.formation_speed_cap_kn, minf(u.effective_max_speed(), TowedArray.speed_limit(u)))
				leader = leader.formation_leader


## The new guide carries on where the old one was going: its route, or its patrol circuit. A
## convoy whose lead ship is sunk keeps steaming for the gate instead of stopping where it was hit.
static func _inherit_plan(successor: Unit, old: Unit) -> void:
	if successor.attack_track != null or successor.investigation_track != null:
		return
	successor.waypoints.assign(old.waypoints)
	successor.patrol_active = old.patrol_active
	successor.patrol_legs_completed = 0
	if old.station_kind == "patrol" and not successor.has_station():
		successor.set_station("patrol", old.station_label)
		successor.station_route.assign(old.station_route)
		successor.station_speed_kn = old.station_speed_kn
	if not old.waypoints.is_empty() or old.ordered_speed_kn > 0.0:
		successor.ordered_speed_kn = minf(old.ordered_speed_kn, successor.effective_max_speed())
		successor.ordered_heading_deg = old.ordered_heading_deg


## A consort that inherits the guide has no station of its own any longer: the group forms on it.
static func _take_guide(successor: Unit, old: Unit) -> void:
	if successor.station_kind == "formation" and successor.station_leader == old:
		successor.clear_station()
		successor.station_note = "Formation guide lost: now guiding the group"
