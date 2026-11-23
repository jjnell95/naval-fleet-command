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
## The tallest landmass on the raster: no cell a sight line samples can be higher.
static var _grid_top := 0.0
## Whether a sight line that clears the tallest ground on the chart all along its land span is
## answered without walking it. Off only in the test that proves the answer is the same.
static var height_shortcut := true

## Landmasses by area, so a sight line or a sound path looks only at the coast near it rather
## than every island on the chart (406 in the Taiwan Strait). Each landmass is listed in every
## bucket within one bucket of its grown bounds, and a query samples its line at half a bucket,
## so every landmass the exhaustive loop would find is still found: tests compare the two.
const INDEX_BUCKETS := 48
const INDEX_MIN_LANDMASSES := 64  # below this, testing every landmass is cheaper (measured)
static var _index: Array[PackedInt32Array] = []
static var _index_origin := Vector2.ZERO
static var _index_size := 1.0
static var _index_cols := 0
static var _index_rows := 0
static var _seen := PackedInt32Array()
static var _seen_mark := 0

## The sea grid: every cell of the chart sorted once into open sea, solid land, or coast. A point
## in the first two is answered without looking at a polygon, and one on the coast is tested
## against only the landmasses that pass through its cell, so the questions asked for every hull
## on every tick (is this ashore, what did this step run into, is this line clear of the coast)
## cost the same on a chart of four hundred islands as on one of four. The same grid is what the
## sea router searches. Built on first use after the coastline changes, because the scenario
## editor rewrites the coast far more often than anything asks about it.
const SEA_GRID_MAX_AXIS := 512
## Every cell within this much of a coastline is a coast cell (or half a cell on a chart so wide
## that its cells are larger): open-sea cells are what the router sails through, so this is also
## the least water a routed leg keeps between a hull and the beach.
const SEA_CLEARANCE_NM := 0.5
## How far from where it lies a hull may be picked up by, or set down from, the routing grid.
const SEA_SNAP_RINGS := 8
const SEA_SNAP_TRIES := 24
const SEA_ROUTE_CACHE := 128
const SEA_OPEN := -1  # a cell value; -2 and below is solid land, 0 and above indexes _sea_lists
static var _sea_generation := -1
static var _sea_cell := CELL_NM
static var _sea_margin := SEA_CLEARANCE_NM
static var _sea_origin := Vector2.ZERO
static var _sea_rect := Rect2()
static var _sea_cols := 0
static var _sea_rows := 0
static var _sea_ref := PackedInt32Array()
static var _sea_lists: Array[PackedInt32Array] = []
## The stretches of coastline within the margin of each coast cell, as landmass * SEA_EDGE_BASE +
## edge, so a line is tested against the coast beside it and not against the whole of a mainland.
const SEA_EDGE_BASE := 65536
static var _sea_edges: Dictionary = {}
static var _sea_spans := PackedInt32Array()  # row, first column, last column of each run of solid land
static var _sea_coast_cells := PackedInt32Array()
static var _sea_astar: AStarGrid2D
static var _sea_routes: Dictionary = {}
## How many searches of the grid the router has run since the coastline last changed, and how
## long the last one took, for the tests and the profiler: a route is planned when an order is
## given, never on a tick, and this is how that is checked.
static var sea_route_searches := 0
static var sea_route_last_usec := 0


# --- Scenario state ---------------------------------------------------------------------

static func clear() -> void:
	landmasses.clear()
	generation += 1
	bounds = Rect2()
	_grid = PackedFloat32Array()
	_grid_top = 0.0
	_cols = 0
	_rows = 0
	_origin = Vector2.ZERO
	_index = []
	_index_cols = 0
	_index_rows = 0
	_grid_rect = Rect2()
	_drop_sea_grid()


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
	_build_index()


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
	if landmasses.is_empty() or not bounds.has_point(p):
		return false
	if _sea_generation != generation:
		_build_sea_grid()
	var ref := _sea_ref[int((p.y - _sea_origin.y) / _sea_cell) * _sea_cols + int((p.x - _sea_origin.x) / _sea_cell)]
	if ref < 0:
		return ref != SEA_OPEN
	for i: int in _sea_lists[ref]:
		if landmasses[i].contains(p):
			return true
	return false


## The landmass a point is on, the first in the scenario's order where two overlap, or null at sea.
static func land_at(p: Vector2) -> Landmass:
	if landmasses.is_empty() or not bounds.has_point(p):
		return null
	if _sea_generation != generation:
		_build_sea_grid()
	var ref := _sea_ref[int((p.y - _sea_origin.y) / _sea_cell) * _sea_cols + int((p.x - _sea_origin.x) / _sea_cell)]
	if ref < 0:
		return null if ref == SEA_OPEN else landmasses[-ref - 2]
	for i: int in _sea_lists[ref]:
		if landmasses[i].contains(p):
			return landmasses[i]
	return null


## The same two answers from every polygon in turn: what the sea grid must always agree with.
static func is_land_exhaustive(p: Vector2) -> bool:
	return land_at_exhaustive(p) != null


static func land_at_exhaustive(p: Vector2) -> Landmass:
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

## The highest ground anywhere on the stretch from `a` to `b`, endpoints included, walked at half
## the raster spacing so that no cell the stretch crosses is stepped over. Zero over open sea.
static func highest_ground_along(a: Vector2, b: Vector2) -> float:
	if _grid.is_empty():
		return 0.0
	var top := maxf(elevation_at(a), elevation_at(b))
	var d := a.distance_to(b)
	if d < 1e-4:
		return top
	var span := _land_span(a, b)
	if span.x > span.y:
		return top
	var steps := maxi(int(ceilf(d * (span.y - span.x) / (_cell_nm * 0.5))), 1)
	for i in steps + 1:
		top = maxf(top, elevation_at(a.lerp(b, lerpf(span.x, span.y, float(i) / float(steps)))))
	return top


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
	if height_shortcut and _clears_every_hill(d, span, from_h_m, to_h_m):
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


## True when the sight line, less the earth's bulge, stays above the tallest ground on the chart
## over the whole stretch the walk below would sample, so no sample could mask it. Along the line
## that height is a parabola opening upward in the fraction travelled, so its lowest point on the
## stretch is the vertex clamped into it, and one evaluation there settles every sample. Late in
## the Taiwan Strait air battle that settles six in seven of the lines that reach land. The metre
## of margin is many orders of magnitude more than the rounding in the walk's own sums, so the
## answer is always the walk's answer.
static func _clears_every_hill(d: float, span: Vector2, from_h_m: float, to_h_m: float) -> bool:
	var bulge_k := d * d / Geo.EARTH_BULGE_K2
	var t := clampf(0.5 - (to_h_m - from_h_m) / (2.0 * bulge_k), span.x, span.y)
	return _grid_top < lerpf(from_h_m, to_h_m, t) - Geo.earth_bulge_m(t * d, (1.0 - t) * d) - 1.0


static func _steps_for(length_nm: float) -> int:
	return clampi(int(ceilf(length_nm / (_cell_nm * 0.75))), 2, MAX_LOS_STEPS)


## Where a course from `a` to `b` first crosses a coastline, as a fraction of the leg, or -1.0
## if it stays in open water the whole way. Exact against the drawn polygons, because this is
## what decides whether a ship may be ordered somewhere, whether a round has a line of fire and
## whether it then flies into a headland. Only the landmasses whose coast lies along the line are
## tested: the line is walked through the sea grid, and a leg over open water touches no polygon.
static func first_land_contact(a: Vector2, b: Vector2) -> float:
	if landmasses.is_empty() or a.distance_squared_to(b) < 1e-12:
		return -1.0
	if _sea_generation != generation:
		_build_sea_grid()
	var span := _clip_to_rect(a, b, _sea_rect)
	if span.x > span.y:
		return -1.0
	var seg := Rect2(a, Vector2.ZERO).expand(b)
	var length := a.distance_to(b)
	var best := -1.0
	# A coast cell is every cell within the margin of a coastline, so samples no further apart
	# than twice the margin cannot step over one that the line crosses.
	var steps := int(ceilf(length * (span.y - span.x) / (_sea_margin * 1.8))) + 1
	var from := a.lerp(b, span.x)
	var stride := (a.lerp(b, span.y) - from) / float(steps)
	var inv := 1.0 / _sea_cell
	var last := -1
	for k in steps + 1:
		var q := from + stride * float(k)
		var cell := clampi(int((q.y - _sea_origin.y) * inv), 0, _sea_rows - 1) * _sea_cols + clampi(int((q.x - _sea_origin.x) * inv), 0, _sea_cols - 1)
		if cell == last or _sea_ref[cell] < 0:
			continue
		last = cell
		for code: int in _sea_edges[cell]:
			var l := landmasses[code / SEA_EDGE_BASE]
			if not l.bounds.intersects(seg):
				continue
			var e := code % SEA_EDGE_BASE
			var hit = Geometry2D.segment_intersects_segment(a, b, l.points[e], l.points[(e + 1) % l.points.size()])
			if hit == null:
				continue
			var t: float = a.distance_to(hit) / length
			if best < 0.0 or t < best:
				best = t
	return best


## Whether a hull can sail straight from `a` to `b`. As first_land_contact, except that a hull
## lying against a beach, or a point picked at the water's edge, is not shut in by the few metres
## of coastline it is touching: the land test that stops a hull's steps is good to a few metres,
## and one stopped by it can lie a hair over the drawn line. The leg is clear if it is clear from
## a ship's length out, and the water there is water.
const SEA_HAIR_NM := 0.01


static func sea_leg_clear(a: Vector2, b: Vector2) -> bool:
	if first_land_contact(a, b) < 0.0:
		return true
	var length := a.distance_to(b)
	if length <= SEA_HAIR_NM * 3.0:
		return false
	var hair := (b - a) / length * SEA_HAIR_NM
	if is_land(a + hair) or is_land(b - hair):
		return false
	return first_land_contact(a + hair, b - hair) < 0.0


## The same crossing from every landmass in turn: what the walk through the sea grid must always
## agree with.
static func first_land_contact_exhaustive(a: Vector2, b: Vector2) -> float:
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


## Whether a hull at `from` can get to `to` by sea: in one straight leg, or round the coast by the
## route the sea router finds. Asked when an order is given or a firing point chosen, not on a tick.
static func reachable_by_sea(from: Vector2, to: Vector2) -> bool:
	if landmasses.is_empty():
		return true
	return not sea_route(from, to).is_empty()


## The stretch of a segment that could possibly touch land, as a pair of fractions along it.
## Most sight lines in a scenario never go near a coast, and the ones that do usually only clip
## the end of a long leg, so narrowing the walk before it starts is what keeps the sensor cycle
## affordable: the whole sensor layer asks this thousands of times a second at 60x compression.
## Returns x > y when the segment cannot reach any land at all.
static func _land_span(a: Vector2, b: Vector2) -> Vector2:
	if _index_cols == 0:
		return _land_span_exhaustive(a, b)
	var box := Rect2(a, Vector2.ZERO).expand(b)
	if not _grid_rect.intersects(box):
		return Vector2(1.0, 0.0)
	var lo := INF
	var hi := -INF
	for i: int in _candidates(a, b):
		var l := landmasses[i]
		if not l.bounds.intersects(box):
			continue
		var span := _clip_to_rect(a, b, l.bounds.grow(_cell_nm))
		if span.x > span.y:
			continue
		lo = minf(lo, span.x)
		hi = maxf(hi, span.y)
	return Vector2(1.0, 0.0) if lo > hi else Vector2(lo, hi)


## The same span from every landmass, without the index: what small charts use, and what the
## index must always agree with.
static func _land_span_exhaustive(a: Vector2, b: Vector2) -> Vector2:
	var box := Rect2(a, Vector2.ZERO).expand(b)
	if not _grid_rect.intersects(box):
		return Vector2(1.0, 0.0)
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
	return Vector2(1.0, 0.0) if lo > hi else Vector2(lo, hi)


## `force` builds it on a small chart too, so the test can compare it there.
static func _build_index(force := false) -> void:
	_index = []
	_index_cols = 0
	_index_rows = 0
	if landmasses.is_empty() or (landmasses.size() < INDEX_MIN_LANDMASSES and not force):
		return
	var area := bounds.grow(_cell_nm)
	_index_size = maxf(maxf(area.size.x, area.size.y) / float(INDEX_BUCKETS), _cell_nm)
	_index_origin = area.position
	_index_cols = int(ceilf(area.size.x / _index_size)) + 1
	_index_rows = int(ceilf(area.size.y / _index_size)) + 1
	var lists: Array = []
	lists.resize(_index_cols * _index_rows)
	for k in lists.size():
		lists[k] = []
	for i in landmasses.size():
		var g := landmasses[i].bounds.grow(_cell_nm)
		var c0 := clampi(int(floorf((g.position.x - _index_origin.x) / _index_size)) - 1, 0, _index_cols - 1)
		var c1 := clampi(int(floorf((g.end.x - _index_origin.x) / _index_size)) + 1, 0, _index_cols - 1)
		var r0 := clampi(int(floorf((g.position.y - _index_origin.y) / _index_size)) - 1, 0, _index_rows - 1)
		var r1 := clampi(int(floorf((g.end.y - _index_origin.y) / _index_size)) + 1, 0, _index_rows - 1)
		for r in range(r0, r1 + 1):
			for c in range(c0, c1 + 1):
				lists[r * _index_cols + c].append(i)
	_index.resize(lists.size())
	for k in lists.size():
		_index[k] = PackedInt32Array(lists[k])
	_seen = PackedInt32Array()
	_seen.resize(landmasses.size())
	_seen.fill(0)
	_seen_mark = 0


## Every landmass listed in a bucket the line passes within half a bucket of, each once.
static func _candidates(a: Vector2, b: Vector2) -> PackedInt32Array:
	var out := PackedInt32Array()
	_seen_mark += 1
	if _seen_mark >= 2147483647:
		_seen.fill(0)
		_seen_mark = 1
	var samples := int(ceilf(a.distance_to(b) / (_index_size * 0.5))) + 1
	var inv := 1.0 / _index_size
	var last := -1
	for k in samples + 1:
		var p := a.lerp(b, float(k) / float(samples))
		var c := int(floorf((p.x - _index_origin.x) * inv))
		var r := int(floorf((p.y - _index_origin.y) * inv))
		# A sample more than a bucket off the grid is more than a quarter-bucket from any land.
		if c < -1 or r < -1 or c > _index_cols or r > _index_rows:
			continue
		var bucket := clampi(r, 0, _index_rows - 1) * _index_cols + clampi(c, 0, _index_cols - 1)
		if bucket == last:
			continue
		last = bucket
		for i: int in _index[bucket]:
			if _seen[i] != _seen_mark:
				_seen[i] = _seen_mark
				out.append(i)
	return out


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
	_grid_top = 0.0
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
	_grid_top = maxf(_grid_top, l.elevation_m)
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


# --- The sea grid ------------------------------------------------------------------------

static func _drop_sea_grid() -> void:
	_sea_generation = -1
	_sea_cols = 0
	_sea_rows = 0
	_sea_ref = PackedInt32Array()
	_sea_lists = []
	_sea_edges = {}
	_sea_spans = PackedInt32Array()
	_sea_coast_cells = PackedInt32Array()
	_sea_astar = null
	_sea_routes.clear()
	sea_route_searches = 0


## Sorts every cell into open sea, solid land or coast. A coast cell is one within the margin of
## any stretch of coastline, and carries the landmasses that could hold a point in it: those with
## coast there, and the first one that covers it whole. Every other cell is all sea or all land,
## which its centre decides. One pass along the coastlines and one scanline fill; nothing here is
## proportional to the number of cells but the two arrays that are filled.
static func _build_sea_grid() -> void:
	_drop_sea_grid()
	_sea_generation = generation
	if landmasses.is_empty():
		return
	_sea_cell = maxf(CELL_NM, maxf(bounds.size.x, bounds.size.y) / float(SEA_GRID_MAX_AXIS))
	_sea_margin = maxf(SEA_CLEARANCE_NM, _sea_cell * 0.25)
	# Three cells of margin, of which the coast cells can take at most the innermost: the outer
	# two rings are always open sea, so a route can always get round the outside of the land.
	var area := bounds.grow(_sea_cell * 3.0)
	_sea_origin = area.position
	_sea_cols = int(ceilf(area.size.x / _sea_cell))
	_sea_rows = int(ceilf(area.size.y / _sea_cell))
	_sea_rect = Rect2(_sea_origin, Vector2(float(_sea_cols), float(_sea_rows)) * _sea_cell)
	var count := _sea_cols * _sea_rows
	_sea_ref.resize(count)
	_sea_ref.fill(SEA_OPEN)
	var stamp := PackedInt32Array()
	stamp.resize(count)
	stamp.fill(-1)
	var coast := PackedByteArray()
	coast.resize(count)
	coast.fill(0)
	var pair_cell := PackedInt32Array()
	var pair_land := PackedInt32Array()
	var edge_stamp := PackedInt32Array()
	edge_stamp.resize(count)
	edge_stamp.fill(-1)
	var edge_cell := PackedInt32Array()
	var edge_code := PackedInt32Array()
	var edge_id := 0
	var inv := 1.0 / _sea_cell
	var sample_nm := _sea_cell * 0.25
	# A point of the coast is within half a sample of a sampled one, so marking this far round
	# each sample marks every cell within the margin of the coast itself.
	var reach := _sea_margin + sample_nm * 0.5
	var crossings := PackedFloat64Array()
	for k in landmasses.size():
		var l := landmasses[k]
		var n := l.points.size()
		crossings.clear()
		for e in n:
			var a := l.points[e]
			var b := l.points[(e + 1) % n]
			var last_c0 := -1
			var last_r0 := -1
			var last_c1 := -1
			var last_r1 := -1
			edge_id += 1
			var code := k * SEA_EDGE_BASE + e
			var pieces := maxi(int(ceilf(a.distance_to(b) / sample_nm)), 1)
			for i in pieces + 1:
				var p := a.lerp(b, float(i) / float(pieces))
				var c0 := int((p.x - reach - _sea_origin.x) * inv)
				var c1 := int((p.x + reach - _sea_origin.x) * inv)
				var r0 := int((p.y - reach - _sea_origin.y) * inv)
				var r1 := int((p.y + reach - _sea_origin.y) * inv)
				if c0 == last_c0 and c1 == last_c1 and r0 == last_r0 and r1 == last_r1:
					continue
				last_c0 = c0
				last_c1 = c1
				last_r0 = r0
				last_r1 = r1
				for r in range(r0, r1 + 1):
					var base := r * _sea_cols
					for c in range(c0, c1 + 1):
						if edge_stamp[base + c] == edge_id:
							continue
						edge_stamp[base + c] = edge_id
						edge_cell.append(base + c)
						edge_code.append(code)
						if stamp[base + c] != k:
							stamp[base + c] = k
							pair_cell.append(base + c)
							pair_land.append(k)
							if coast[base + c] == 0:
								coast[base + c] = 1
								_sea_coast_cells.append(base + c)
			# Where this edge crosses the centre line of each row it spans, keyed so that one sort
			# puts the crossings of every row in order.
			if a.y == b.y:
				continue
			var low := minf(a.y, b.y)
			var high := maxf(a.y, b.y)
			var first_row := maxi(int(ceilf((low - _sea_origin.y) * inv - 0.5)), 0)
			var last_row := mini(int(ceilf((high - _sea_origin.y) * inv - 0.5)) - 1, _sea_rows - 1)
			for r in range(first_row, last_row + 1):
				var y := _sea_origin.y + (float(r) + 0.5) * _sea_cell
				if (a.y > y) == (b.y > y):
					continue
				crossings.append(float(r) * 1.0e7 + (a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y) - _sea_origin.x))
		crossings.sort()
		var solid := -k - 2
		var j := 0
		while j + 1 < crossings.size():
			var row := int(crossings[j] / 1.0e7)
			if int(crossings[j + 1] / 1.0e7) != row:
				j += 1
				continue
			var start := maxi(int(ceilf((crossings[j] - float(row) * 1.0e7) * inv - 0.5)), 0)
			var stop := mini(int(floorf((crossings[j + 1] - float(row) * 1.0e7) * inv - 0.5)), _sea_cols - 1)
			j += 2
			if stop < start:
				continue
			var base := row * _sea_cols
			var run := -1
			for c in range(start, stop + 1):
				# Its own coast cells already list it; the rest it covers whole, and the first
				# landmass to cover a cell is the one a point there is on.
				if stamp[base + c] != k and _sea_ref[base + c] == SEA_OPEN:
					_sea_ref[base + c] = solid
					if run < 0:
						run = c
				elif run >= 0:
					_sea_spans.append(row)
					_sea_spans.append(run)
					_sea_spans.append(c - 1)
					run = -1
			if run >= 0:
				_sea_spans.append(row)
				_sea_spans.append(run)
				_sea_spans.append(stop)
	# The coast cells' lists, in the scenario's order, shared between cells that hold the same ones.
	var lists := {}
	for i in pair_cell.size():
		var cell := pair_cell[i]
		if not lists.has(cell):
			lists[cell] = [-_sea_ref[cell] - 2] if _sea_ref[cell] <= -2 else []
		(lists[cell] as Array).append(pair_land[i])
	var shared := {}
	for cell: int in lists:
		var list := PackedInt32Array(lists[cell] as Array)
		list.sort()
		var key := str(list)
		if not shared.has(key):
			shared[key] = _sea_lists.size()
			_sea_lists.append(list)
		_sea_ref[cell] = shared[key]
	var edges := {}
	for i in edge_cell.size():
		var cell := edge_cell[i]
		if not edges.has(cell):
			edges[cell] = []
		(edges[cell] as Array).append(edge_code[i])
	for cell: int in edges:
		_sea_edges[cell] = PackedInt32Array(edges[cell] as Array)


# --- The sea router ----------------------------------------------------------------------

## The way by sea from `from` to `to`: the points to steer for in turn, ending at `to`. One point
## when a straight course is clear of every coast. Otherwise the shortest way round on the sea
## grid, through open-sea cells only and never cutting a corner between two of them, then pulled
## taut: a leg is kept only while it stays in cells clear of the coast, and the first and last,
## which start and end wherever the hull and its destination happen to lie, are tested against
## the coastline itself. Empty when there is no way: the destination is ashore, or shut in.
##
## Planned when an order is given or a task changes its mind about where it is going, never on a
## tick: a search of a large chart costs milliseconds (sea_route_last_usec). Answers are kept
## until the coastline changes, so asking whether there is a way and then taking it costs one search.
static func sea_route(from: Vector2, to: Vector2) -> PackedVector2Array:
	var direct := PackedVector2Array([to])
	if landmasses.is_empty():
		return direct
	if is_land(to):
		return PackedVector2Array()
	# A hull that is somehow ashore already is let go, as its steps are: better than trapped.
	if is_land(from) or sea_leg_clear(from, to):
		return direct
	var key := Vector4(from.x, from.y, to.x, to.y)
	if _sea_routes.has(key):
		return _sea_routes[key]
	var started := Time.get_ticks_usec()
	var route := _search_sea_route(from, to)
	sea_route_searches += 1
	sea_route_last_usec = Time.get_ticks_usec() - started
	if _sea_routes.size() >= SEA_ROUTE_CACHE:
		_sea_routes.clear()
	_sea_routes[key] = route
	return route


## How far a hull at `from` sails to follow a route to its end.
static func route_length_nm(from: Vector2, route: PackedVector2Array) -> float:
	var total := 0.0
	var at := from
	for p in route:
		total += at.distance_to(p)
		at = p
	return total


static func _search_sea_route(from: Vector2, to: Vector2) -> PackedVector2Array:
	var none := PackedVector2Array()
	var start := _nearest_open_cell(from)
	var goal := _nearest_open_cell(to)
	if start.x < 0 or goal.x < 0:
		return none
	if _sea_astar == null:
		_build_sea_astar()
	var cells := _sea_astar.get_id_path(start, goal)
	if cells.is_empty():
		return none
	var points := PackedVector2Array([from])
	for id: Vector2i in cells:
		points.append(_sea_cell_centre(id))
	points.append(to)
	# How far along a first or last leg the coast itself is tested rather than the grid: as far as
	# the cell the hull was picked up from, and a cell and a half more.
	var first_slack := from.distance_to(points[1]) + _sea_cell * 1.5
	var last_slack := to.distance_to(points[points.size() - 2]) + _sea_cell * 1.5
	var out := PackedVector2Array()
	var last := points.size() - 1
	var i := 0
	while i < last:
		# The furthest point still in plain sight of this one: doubling strides while the leg
		# stays clear, then halving back. The next point along is always in sight.
		var best := i + 1
		var stride := 2
		while i + stride <= last and _sea_leg_clear(points, i, i + stride, last, first_slack, last_slack):
			best = i + stride
			stride *= 2
		var low := best
		var high := mini(i + stride, last + 1)
		while high - low > 1:
			var mid := (low + high) / 2
			if _sea_leg_clear(points, i, mid, last, first_slack, last_slack):
				low = mid
			else:
				high = mid
		out.append(points[low])
		i = low
	return out


## Whether the leg between two points of a route under construction is clear. Between cell
## centres that is a walk through the grid; the stretch next to the hull's own position, or next
## to the destination, is asked of the coastline, because either may lie in a coast cell.
static func _sea_leg_clear(points: PackedVector2Array, i: int, j: int, last: int, first_slack: float, last_slack: float) -> bool:
	var a := points[i]
	var b := points[j]
	var length := a.distance_to(b)
	var lead := first_slack if i == 0 else 0.0
	var tail := last_slack if j == last else 0.0
	if lead + tail >= length:
		return sea_leg_clear(a, b)
	var along := (b - a) / length
	var inner_a := a + along * lead
	var inner_b := b - along * tail
	if lead > 0.0 and not sea_leg_clear(a, inner_a):
		return false
	if tail > 0.0 and not sea_leg_clear(inner_b, b):
		return false
	return _open_sea_between(inner_a, inner_b)


## Every sample of the line, half a margin apart, lies in an open-sea cell: so no point of it is
## nearer the coast than half the margin.
static func _open_sea_between(a: Vector2, b: Vector2) -> bool:
	var steps := int(ceilf(a.distance_to(b) / (_sea_margin * 0.9))) + 1
	var stride := (b - a) / float(steps)
	var inv := 1.0 / _sea_cell
	for k in steps + 1:
		var q := a + stride * float(k)
		var c := int(floorf((q.x - _sea_origin.x) * inv))
		var r := int(floorf((q.y - _sea_origin.y) * inv))
		if c < 0 or r < 0 or c >= _sea_cols or r >= _sea_rows:
			continue
		if _sea_ref[r * _sea_cols + c] != SEA_OPEN:
			return false
	return true


static func _sea_cell_centre(id: Vector2i) -> Vector2:
	return _sea_origin + (Vector2(id) + Vector2(0.5, 0.5)) * _sea_cell


## The open-sea cell a point is picked up from: its own when that is one, the edge of the grid
## for a point out beyond all the land, and otherwise the nearest it can reach in a straight line
## without crossing a coast. (-1, -1) when it is shut in.
static func _nearest_open_cell(p: Vector2) -> Vector2i:
	var inv := 1.0 / _sea_cell
	var raw := Vector2i(int(floorf((p.x - _sea_origin.x) * inv)), int(floorf((p.y - _sea_origin.y) * inv)))
	var home := Vector2i(clampi(raw.x, 0, _sea_cols - 1), clampi(raw.y, 0, _sea_rows - 1))
	if home != raw or _sea_ref[home.y * _sea_cols + home.x] == SEA_OPEN:
		return home
	var found: Array = []
	for r in range(maxi(home.y - SEA_SNAP_RINGS, 0), mini(home.y + SEA_SNAP_RINGS, _sea_rows - 1) + 1):
		for c in range(maxi(home.x - SEA_SNAP_RINGS, 0), mini(home.x + SEA_SNAP_RINGS, _sea_cols - 1) + 1):
			if _sea_ref[r * _sea_cols + c] == SEA_OPEN:
				var id := Vector2i(c, r)
				found.append([p.distance_squared_to(_sea_cell_centre(id)), r * _sea_cols + c, id])
	found.sort()
	for k in mini(found.size(), SEA_SNAP_TRIES):
		var id: Vector2i = found[k][2]
		if sea_leg_clear(p, _sea_cell_centre(id)):
			return id
	return Vector2i(-1, -1)


## The grid the router searches: open-sea cells, eight ways, a diagonal only between two open
## neighbours so that no route cuts the corner of a coast cell.
static func _build_sea_astar() -> void:
	_sea_astar = AStarGrid2D.new()
	_sea_astar.region = Rect2i(0, 0, _sea_cols, _sea_rows)
	_sea_astar.cell_size = Vector2(_sea_cell, _sea_cell)
	_sea_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_sea_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_sea_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_sea_astar.update()
	var k := 0
	while k + 2 < _sea_spans.size():
		_sea_astar.fill_solid_region(Rect2i(_sea_spans[k + 1], _sea_spans[k], _sea_spans[k + 2] - _sea_spans[k + 1] + 1, 1))
		k += 3
	for cell: int in _sea_coast_cells:
		_sea_astar.set_point_solid(Vector2i(cell % _sea_cols, cell / _sea_cols))
