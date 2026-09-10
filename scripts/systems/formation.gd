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
	if not u.in_formation():
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
static func assign(units: Array, pattern: String) -> Array:
	var offsets: Array = PATTERNS.get(pattern, PATTERNS["column"])
	var out: Array = []
	if units.size() < 2:
		return out
	var leader: Unit = units[0]
	for i in range(1, units.size()):
		var offset: Vector2 = offsets[(i - 1) % offsets.size()]
		out.append({"unit": units[i], "order": Order.form_up(leader, offset)})
	return out
