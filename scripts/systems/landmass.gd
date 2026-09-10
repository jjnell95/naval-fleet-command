class_name Landmass
extends RefCounted
## One closed piece of land on the chart, in world nautical miles.
##
## The polygon is the coastline: it is what gets drawn, what a ship runs aground on and what a
## sight line has to clear. `elevation_m` is the height a sensor must see over — an abstraction of
## the whole landmass as one plateau, not a height field. Islands are separate landmasses; a
## scenario's `land` list is simply all of them.
##
## GAMEPLAY_ESTIMATE: every coastline shipped with this project is a stylised fictional shape
## drawn to evoke the water a scenario names. None of it is survey data, and no elevation here is
## a claim about real ground.

const DEFAULT_ELEVATION_M := 180.0

var id := ""
var name := ""
var points := PackedVector2Array()
var elevation_m := DEFAULT_ELEVATION_M
var bounds := Rect2()
var centroid := Vector2.ZERO


static func from_dict(d: Dictionary) -> Landmass:
	var l := Landmass.new()
	l.id = str(d.get("id", ""))
	l.name = str(d.get("name", ""))
	l.elevation_m = maxf(float(d.get("elevation_m", DEFAULT_ELEVATION_M)), 0.0)
	for p in d.get("points_nm", []):
		if typeof(p) == TYPE_ARRAY and p.size() >= 2:
			l.points.append(Vector2(float(p[0]), float(p[1])))
	l.recompute()
	return l


func to_dict() -> Dictionary:
	var pts: Array = []
	for p in points:
		pts.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
	return {"id": id, "name": name, "elevation_m": elevation_m, "points_nm": pts}


## A polygon needs at least a triangle to enclose anything.
func valid() -> bool:
	return points.size() >= 3


func recompute() -> void:
	if points.is_empty():
		bounds = Rect2()
		centroid = Vector2.ZERO
		return
	bounds = Rect2(points[0], Vector2.ZERO)
	var sum := Vector2.ZERO
	for p in points:
		bounds = bounds.expand(p)
		sum += p
	centroid = sum / float(points.size())


func contains(p: Vector2) -> bool:
	if not bounds.has_point(p):
		return false
	return Geometry2D.is_point_in_polygon(p, points)


## Shortest distance from a point to the coastline, in nautical miles. Zero on the beach; this
## does not say which side of it the point is on.
func distance_to_shore_nm(p: Vector2) -> float:
	var best := INF
	var n := points.size()
	for i in n:
		var a := points[i]
		var b := points[(i + 1) % n]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best


## Outward unit normal of the nearest stretch of coast: the direction that leads to open water.
## Used to slide a ship along a shore instead of stopping it dead against one.
func shore_normal(p: Vector2) -> Vector2:
	var best := INF
	var best_a := Vector2.ZERO
	var best_b := Vector2.ZERO
	var n := points.size()
	for i in n:
		var a := points[i]
		var b := points[(i + 1) % n]
		var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
		if d < best:
			best = d
			best_a = a
			best_b = b
	var edge := best_b - best_a
	if edge.length_squared() < 1e-12:
		var away := p - centroid
		return away.normalized() if away.length_squared() > 1e-12 else Vector2.UP
	var normal := edge.orthogonal().normalized()
	# Two candidates; keep the one pointing away from the middle of the landmass.
	var mid := (best_a + best_b) * 0.5
	if normal.dot(mid - centroid) < 0.0:
		normal = -normal
	return normal
