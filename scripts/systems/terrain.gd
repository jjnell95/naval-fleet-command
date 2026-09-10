class_name Terrain
## Land on the chart, and what it does to the fight.
##
## A scenario may declare landmasses as closed polygons in world nautical miles; everything not
## inside one is water. Terrain is static, loaded once per scenario the same way
## `Detection.set_environment` loads the weather, so any system can ask about it without a
## reference being plumbed through the managers. A scenario with no `terrain` block leaves this
## empty, every query short-circuits, and the game behaves exactly as it did before land existed.
##
## Land does three things:
##   * it stops ships and submarines — they run out of water before they run out of ocean;
##   * it masks line of sight — radar and ESM are blocked when the ground rises above the sight
##     line, allowing for the same 4/3-earth curvature the radar horizon already uses, so a
##     corvette hiding behind an island is invisible while an aircraft over it is not;
##   * it stops sound — an acoustic path does not go through rock at any depth.
##
## Two representations, for two very different call rates. The polygons are exact and answer
## "is this point ashore" and "where does this course hit the beach", which are asked a few dozen
## times a tick. A rasterised elevation grid, built once at load, answers "how high is the ground
## along this line", which the sensor cycle asks for every observer/target pair that passes its
## range test. The grid is coarse on purpose: terrain masking at this scale is not a knife edge.
##
## GAMEPLAY_ESTIMATE: all of it. Coastlines are stylised fictional shapes, elevations are one
## number standing in for a whole landmass, and the masking model is a straight line over a
## plateau, not a diffraction calculation.

const CELL_NM := 1.0  # chart resolution of the elevation grid
const MAX_GRID_AXIS := 420  # cap the raster so a very wide scenario cannot allocate a huge grid
const MAX_LOS_STEPS := 128  # bound the cost of one sight line however long it is
const AGROUND_CLEARANCE_NM := 0.05  # how far off the beach a refused move order is set down
const NEAREST_WATER_STEPS := 24

static var landmasses: Array[Landmass] = []
## Bumped whenever the coastline changes, so the map and the editor can drop cached geometry
## without comparing polygons. The scenario editor rewrites terrain while a chart is on screen.
static var generation := 0
static var bounds := Rect2()  # union of every landmass, for culling; empty when there is no land

static var _grid := PackedFloat32Array()
static var _cols := 0
static var _rows := 0
static var _cell_nm := CELL_NM
static var _origin := Vector2.ZERO
static var _grid_rect := Rect2()


# --- Scenario state ---------------------------------------------------------------------

static func clear() -> void:
	landmasses.clear()
	generation += 1
	bounds = Rect2()
	_grid = PackedFloat32Array()
	_cols = 0
	_rows = 0
	_origin = Vector2.ZERO
	_grid_rect = Rect2()


## Reads the scenario's `terrain` block. Absent or malformed means open ocean, which is what
## every scenario written before this existed gets.
static func load_from(scenario: Dictionary) -> void:
	clear()
	var block = scenario.get("terrain", {})
	if typeof(block) != TYPE_DICTIONARY:
		return
	var list = block.get("land", [])
	if typeof(list) != TYPE_ARRAY:
		return
	var built: Array[Landmass] = []
	for entry in list:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var l := Landmass.from_dict(entry)
		if not l.valid():
			push_warning("Terrain: landmass '%s' has fewer than three points; ignored" % l.name)
			continue
		built.append(l)
	set_landmasses(built)


## Shared by the loader and the scenario editor, so a coastline drawn in the editor behaves
## exactly like a shipped one the moment it is placed.
static func set_landmasses(list: Array[Landmass]) -> void:
	landmasses = list
	generation += 1
	_recompute_bounds()
	_build_grid()


static func to_dict() -> Dictionary:
	var out: Array = []
	for l in landmasses:
		out.append(l.to_dict())
	return {"land": out}


static func is_empty() -> bool:
	return landmasses.is_empty()


static func _recompute_bounds() -> void:
	bounds = Rect2()
	var first := true
	for l in landmasses:
		l.recompute()
		if first:
			bounds = l.bounds
			first = false
		else:
			bounds = bounds.merge(l.bounds)


# --- Point queries ----------------------------------------------------------------------

static func is_land(p: Vector2) -> bool:
	if landmasses.is_empty():
		return false
	for l in landmasses:
		if l.contains(p):
			return true
	return false


static func land_at(p: Vector2) -> Landmass:
	for l in landmasses:
		if l.contains(p):
			return l
	return null


## Distance to the nearest coastline in nautical miles: 0 ashore, INF when the scenario has no
## land at all. The AI uses it to keep off a lee shore.
static func distance_to_land_nm(p: Vector2) -> float:
	if landmasses.is_empty():
		return INF
	var best := INF
	for l in landmasses:
		if l.contains(p):
			return 0.0
		best = minf(best, l.distance_to_shore_nm(p))
	return best


## Ground height at a point, from the raster. Zero at sea.
static func elevation_at(p: Vector2) -> float:
	if _grid.is_empty():
		return 0.0
	var col := int(floorf((p.x - _origin.x) / _cell_nm))
	var row := int(floorf((p.y - _origin.y) / _cell_nm))
	if col < 0 or row < 0 or col >= _cols or row >= _rows:
		return 0.0
	return _grid[row * _cols + col]


# --- Line queries -----------------------------------------------------------------------

## True when the ground between two points rises above the line joining them. Heights are metres
## above sea level: a mast height for a ship, altitude for an aircraft, zero for anything on the
## surface. Endpoints are excluded, so a radar sited ashore is not blinded by its own hill.
static func masks_line_of_sight(from: Vector2, from_h_m: float, to: Vector2, to_h_m: float) -> bool:
	if _grid.is_empty():
		return false
	var d := from.distance_to(to)
	if d < 1e-4:
		return false
	var span := _land_span(from, to)
	if span.x > span.y:
		return false
	# The grid lookup is written out rather than calling elevation_at, because this loop is the
	# single hottest piece of terrain code in the game: the sensor cycle walks it thousands of
	# times a second at full time compression.
	var steps := _steps_for(d * (span.y - span.x))
	var dt := (span.y - span.x) / float(steps)
	var inv := 1.0 / _cell_nm
	var leg := to - from
	var p := from + leg * span.x
	var dp := leg * dt
	var t := span.x
	for i in steps + 1:
		if t > 0.0 and t < 1.0:
			var fx := (p.x - _origin.x) * inv
			var fy := (p.y - _origin.y) * inv
			if fx >= 0.0 and fy >= 0.0:
				var col := int(fx)
				var row := int(fy)
				if col < _cols and row < _rows:
					var ground := _grid[row * _cols + col]
					if ground > 0.0 and ground >= lerpf(from_h_m, to_h_m, t) - Geo.earth_bulge_m(t * d, (1.0 - t) * d):
						return true
		p += dp
		t += dt
	return false


## True when any land lies strictly between two points. This is the test for anything that
## cannot go over a hill at all: sound in water, and a hull on the surface.
static func blocks_path(a: Vector2, b: Vector2) -> bool:
	if _grid.is_empty():
		return false
	var d := a.distance_to(b)
	if d < 1e-4:
		return false
	var span := _land_span(a, b)
	if span.x > span.y:
		return false
	var steps := _steps_for(d * (span.y - span.x))
	var dt := (span.y - span.x) / float(steps)
	var inv := 1.0 / _cell_nm
	var leg := b - a
	var p := a + leg * span.x
	var dp := leg * dt
	var t := span.x
	for i in steps + 1:
		if t > 0.0 and t < 1.0:
			var fx := (p.x - _origin.x) * inv
			var fy := (p.y - _origin.y) * inv
			if fx >= 0.0 and fy >= 0.0:
				var col := int(fx)
				var row := int(fy)
				if col < _cols and row < _rows and _grid[row * _cols + col] > 0.0:
					return true
		p += dp
		t += dt
	return false


static func _steps_for(length_nm: float) -> int:
	return clampi(int(ceilf(length_nm / (_cell_nm * 0.75))), 2, MAX_LOS_STEPS)


## Where a course from `a` to `b` first crosses a coastline, as a fraction of the leg, or -1.0
## if it stays in open water the whole way. Exact against the drawn polygons, because this is
## what decides whether a ship may be ordered somewhere.
static func first_land_contact(a: Vector2, b: Vector2) -> float:
	if landmasses.is_empty() or a.distance_squared_to(b) < 1e-12:
		return -1.0
	var seg := Rect2(a, Vector2.ZERO).expand(b)
	var length := a.distance_to(b)
	var best := -1.0
	for l in landmasses:
		if not l.bounds.intersects(seg):
			continue
		var n := l.points.size()
		for i in n:
			var hit = Geometry2D.segment_intersects_segment(a, b, l.points[i], l.points[(i + 1) % n])
			if hit == null:
				continue
			var t: float = a.distance_to(hit) / length
			if best < 0.0 or t < best:
				best = t
	return best


## The stretch of a segment that could possibly touch land, as a pair of fractions along it.
## Most sight lines in a scenario never go near a coast, and the ones that do usually only clip
## the end of a long leg, so narrowing the walk before it starts is what keeps the sensor cycle
## affordable: the whole sensor layer asks this thousands of times a second at 60x compression.
## Returns x > y when the segment cannot reach any land at all.
static func _land_span(a: Vector2, b: Vector2) -> Vector2:
	var empty := Vector2(1.0, 0.0)
	var box := Rect2(a, Vector2.ZERO).expand(b)
	if not _grid_rect.intersects(box):
		return empty
	var lo := INF
	var hi := -INF
	for l in landmasses:
		if not l.bounds.intersects(box):
			continue
		var span := _clip_to_rect(a, b, l.bounds.grow(_cell_nm))
		if span.x > span.y:
			continue
		lo = minf(lo, span.x)
		hi = maxf(hi, span.y)
	return empty if lo > hi else Vector2(lo, hi)


## Slab clip of the segment a→b against a rectangle, in fractions along the segment.
static func _clip_to_rect(a: Vector2, b: Vector2, r: Rect2) -> Vector2:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for axis in 2:
		var step: float = d[axis]
		var low: float = r.position[axis]
		var high: float = r.end[axis]
		if absf(step) < 1e-9:
			var here: float = a[axis]
			if here < low or here > high:
				return Vector2(1.0, 0.0)
			continue
		var ta := (low - a[axis]) / step
		var tb := (high - a[axis]) / step
		if ta > tb:
			var swap := ta
			ta = tb
			tb = swap
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return Vector2(1.0, 0.0)
	return Vector2(t0, t1)


# --- Keeping hulls in the water ----------------------------------------------------------

## The position a hull actually reaches when it tries to move from `from` to `to`. In open water
## that is `to`. Against a coast the step is projected along the shore, so a ship ordered into a
## bay follows the beach instead of stopping dead on it; when even that is blocked it stays put.
static func constrain_step(from: Vector2, to: Vector2) -> Vector2:
	if landmasses.is_empty():
		return to
	var blocker := land_at(to)
	if blocker == null:
		return to
	if blocker.contains(from):
		# Already ashore — a scenario placed it there, or the coast moved under it. Let it go
		# wherever it was going rather than trapping it forever.
		return to
	var step := to - from
	var normal := blocker.shore_normal(to)
	var slide := step - normal * minf(step.dot(normal), 0.0)
	var candidate := from + slide
	if not is_land(candidate):
		return candidate
	return from


## The heading closest to the one wanted that has open water ahead of it. A ship running from
## something would rather turn along a coast than onto it, and the two orders that can beach a
## ship at full speed — turn away from an inbound salvo, and withdraw — name a bearing and no
## destination, so this is the only place the coast can reach them.
const BEARING_PROBE_DEG: Array[float] = [15.0, 30.0, 45.0, 60.0, 80.0, 100.0, 125.0, 155.0]


static func open_bearing_deg(from: Vector2, wanted_deg: float, lookahead_nm: float) -> float:
	if landmasses.is_empty():
		return wanted_deg
	if not blocks_path(from, from + Geo.heading_to_vector(wanted_deg) * lookahead_nm):
		return wanted_deg
	for offset: float in BEARING_PROBE_DEG:
		for side: float in [1.0, -1.0]:
			var candidate := wanted_deg + offset * side
			if not blocks_path(from, from + Geo.heading_to_vector(candidate) * lookahead_nm):
				return fposmod(candidate, 360.0)
	return wanted_deg


## Nearest open water to a point that is ashore, searched back along the bearing it was reached
## from and then straight out to sea. Used to make a refused move order land somewhere sensible
## rather than nowhere.
static func nearest_water(p: Vector2, approach_from := Vector2.INF) -> Vector2:
	if not is_land(p):
		return p
	var l := land_at(p)
	var reach := maxf(l.bounds.size.x, l.bounds.size.y) if l != null else 20.0
	if approach_from != Vector2.INF and not is_land(approach_from):
		for i in range(1, NEAREST_WATER_STEPS + 1):
			var q := p.lerp(approach_from, float(i) / float(NEAREST_WATER_STEPS))
			if not is_land(q):
				return q + (approach_from - p).normalized() * AGROUND_CLEARANCE_NM
	if l != null:
		var out := l.shore_normal(p)
		for i in range(1, NEAREST_WATER_STEPS + 1):
			var q := p + out * (reach * float(i) / float(NEAREST_WATER_STEPS))
			if not is_land(q):
				return q + out * AGROUND_CLEARANCE_NM
	return p


# --- Raster ------------------------------------------------------------------------------

## One scanline fill per landmass. Cheap enough to do at scenario load and at every edit in the
## scenario editor, which is what lets a coastline drawn by hand mask radar immediately.
static func _build_grid() -> void:
	_grid = PackedFloat32Array()
	_cols = 0
	_rows = 0
	_grid_rect = Rect2()
	if landmasses.is_empty():
		return
	var area := bounds.grow(CELL_NM * 2.0)
	_cell_nm = maxf(CELL_NM, maxf(area.size.x, area.size.y) / float(MAX_GRID_AXIS))
	_origin = area.position
	_cols = maxi(int(ceilf(area.size.x / _cell_nm)) + 1, 1)
	_rows = maxi(int(ceilf(area.size.y / _cell_nm)) + 1, 1)
	_grid_rect = Rect2(_origin, Vector2(float(_cols) * _cell_nm, float(_rows) * _cell_nm))
	_grid.resize(_cols * _rows)
	_grid.fill(0.0)
	for l in landmasses:
		_rasterise(l)


static func _rasterise(l: Landmass) -> void:
	var n := l.points.size()
	if n < 3:
		return
	var first_row := clampi(int(floorf((l.bounds.position.y - _origin.y) / _cell_nm)), 0, _rows - 1)
	var last_row := clampi(int(ceilf((l.bounds.end.y - _origin.y) / _cell_nm)), 0, _rows - 1)
	for row in range(first_row, last_row + 1):
		var y := _origin.y + (float(row) + 0.5) * _cell_nm
		var xs: Array[float] = []
		for i in n:
			var a := l.points[i]
			var b := l.points[(i + 1) % n]
			if (a.y > y) == (b.y > y):
				continue
			xs.append(a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y))
		if xs.size() < 2:
			continue
		xs.sort()
		var k := 0
		while k + 1 < xs.size():
			_fill_span(row, xs[k], xs[k + 1], l.elevation_m)
			k += 2


static func _fill_span(row: int, x0: float, x1: float, elevation: float) -> void:
	var start := int(ceilf((x0 - _origin.x) / _cell_nm - 0.5))
	var stop := int(floorf((x1 - _origin.x) / _cell_nm - 0.5))
	start = maxi(start, 0)
	stop = mini(stop, _cols - 1)
	var base := row * _cols
	for col in range(start, stop + 1):
		if elevation > _grid[base + col]:
			_grid[base + col] = elevation
