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
	var ahead := Geo.heading_to_vector(leader.heading_deg)
	var starboard := Geo.heading_to_vector(leader.heading_deg + 90.0)
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


## Assigns a named pattern to a selection. The first unit leads; the rest take stations in order.
## Returns the orders to issue, so the caller still goes through the normal command path.
static func assign(units: Array, pattern: String, spacing := 1.0) -> Array:
	var out: Array = []
	if units.size() < 2:
		return out
	var leader: Unit = units[0]
	var station_index := 0
	for i in range(1, units.size()):
		var u: Unit = units[i]
		if not can_join(u, leader):
			continue
		var offset := offset_for(station_index, pattern) * clampf(spacing, 0.5, 3.0)
		out.append({"unit": units[i], "order": Order.form_up(leader, offset)})
		station_index += 1
	return out


## Stations grow with the force. Modulo-five reuse put the sixth escort on the first escort.
static func offset_for(i: int, pattern: String) -> Vector2:
	match pattern:
		"column":
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
		var ahead := Geo.heading_to_vector(successor.heading_deg)
		var right := Geo.heading_to_vector(successor.heading_deg + 90.0)
		for i in range(1, survivors.size()):
			var member: Unit = survivors[i]
			var relative := member.position - successor.position
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
		for i in range(1, group.size()):
			(group[i] as Unit).station_leader = guide
	for u: Unit in units:
		if u.alive and u.in_formation() and u.evasion_remaining_s <= 0:
			var leader := u.formation_leader
			var seen: Dictionary = {}
			while leader != null and leader.alive and not seen.has(leader):
				seen[leader] = true
				leader.formation_speed_cap_kn = minf(leader.formation_speed_cap_kn, u.effective_max_speed())
				leader = leader.formation_leader


## A consort that inherits the guide has no station of its own any longer: the group forms on it.
static func _take_guide(successor: Unit, old: Unit) -> void:
	if successor.station_kind == "formation" and successor.station_leader == old:
		successor.clear_station()
		successor.station_note = "Formation guide lost: now guiding the group"
