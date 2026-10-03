class_name SensorCoverage
## What the commander's own sensors cover right now, as discs for the chart to light: everything
## outside them is drawn dark, so turning a radar off, or a contact sitting beyond reach, is
## something you can see at a glance rather than something you have to infer.
##
## Presentation only. It reads the commander's own units (their real positions, as the chart
## already shows them) and the same Detection figures the sensor rings use. It never reads an
## enemy unit or a track's truth.

## How each disc lights the chart. The shader (chart_palette.gdshaderinc) uses the same numbers.
const RADAR_SURFACE := 0.0  # a radar's reach against a ship on the surface: fully lit
const RADAR_AIR := 1.0  # air search beyond the surface horizon: aircraft are seen, ships are not
const SONAR := 2.0  # under water only: lit with a sea-green tint
## The shader holds this many discs. Surface radar is kept first, then sonar, then air search.
const MAX_DISCS := 48


## Discs, Vector4(centre x, centre y, radius nm, kind), for every sensor the faction has working.
## Each unit contributes at most one disc of each kind. A boat that has not checked in is left out:
## the commander does not know where it is listening from.
static func discs(units: Array) -> Array[Vector4]:
	var surface: Array[Vector4] = []
	var sonar: Array[Vector4] = []
	var air: Array[Vector4] = []
	for u: Unit in units:
		if u == null or not u.alive or (u.is_aircraft() and not u.in_flight()):
			continue
		if not SubmarineComms.connected(u):
			continue
		var at := SubmarineComms.reported_position(u)
		if u.radar_emitting():
			var efficiency := u.sensor_efficiency()
			var r := Detection.nominal_radar_ring_nm(u) * efficiency
			if r > 0.0:
				surface.append(Vector4(at.x, at.y, r, RADAR_SURFACE))
			var reach := 0.0
			for s: SensorSpec in u.sensors:
				if s.kind == "radar":
					reach = maxf(reach, s.range_air_nm)
			reach *= efficiency
			if reach > r + 1.0:
				air.append(Vector4(at.x, at.y, reach, RADAR_AIR))
		var listening := maxf(Detection.nominal_passive_ring_nm(u), Detection.best_active_sonar_nm(u))
		if listening > 0.0:
			sonar.append(Vector4(at.x, at.y, listening, SONAR))
	var out: Array[Vector4] = []
	for group: Array[Vector4] in [surface, sonar, air]:
		group.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.z > b.z)
		for d in group:
			if out.size() >= MAX_DISCS:
				return out
			out.append(d)
	return out


## Whether a world point is inside the lit part of the chart for these discs, and how: "radar",
## "air", "sonar" or "" for dark. For the hover readout and the tests.
static func cover_at(list: Array[Vector4], w: Vector2) -> String:
	var best := ""
	for d in list:
		if w.distance_to(Vector2(d.x, d.y)) > d.z:
			continue
		if d.w == RADAR_SURFACE:
			return "radar"
		if d.w == RADAR_AIR and best != "sonar":
			best = "air"
		elif d.w == SONAR and best == "":
			best = "sonar"
		elif d.w == SONAR and best == "air":
			best = "air + sonar"
	return best
