class_name WorldLand
## Land for the world view, built from Terrain's coastline polygons: a low coastal shelf and
## three terraces whose height follows the landmass's charted elevation, so a headland has a
## silhouette against the sky without pretending to be a height field. GAMEPLAY_ESTIMATE, like
## the elevations it draws from.

const SHELF_M := 3.0
## Land colours are vertex colours read as linear values, hence the low numbers.
const COL_SHELF := Color(0.150, 0.160, 0.125)
const COL_SLOPE := Color(0.115, 0.135, 0.100)
const COL_TOP := Color(0.100, 0.125, 0.092)
const COL_WALL := Color(0.070, 0.080, 0.066)


## The mesh for one landmass, in metres about `origin_nm`.
static func build(l: Landmass, origin_nm: Vector2) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var height := clampf(l.elevation_m, 10.0, 450.0) * 0.25
	var inset_m := clampf(height * 3.0, 220.0, 900.0)
	_add_plateau(origin_nm, l.points, SHELF_M, 0.0, COL_SHELF, COL_WALL, vertices, normals, colors, indices)
	var clockwise := Geometry2D.is_polygon_clockwise(l.points)
	var below := SHELF_M
	for step in range(1, 4):
		var top := height * float(step) / 3.0
		for ring in Geometry2D.offset_polygon(l.points, -float(step) * inset_m / WorldPresentation.NM_TO_M, Geometry2D.JOIN_ROUND):
			if ring.size() >= 3 and Geometry2D.is_polygon_clockwise(ring) == clockwise:
				_add_plateau(origin_nm, ring, top, below, COL_TOP if step == 3 else COL_SLOPE, COL_WALL, vertices, normals, colors, indices)
		below = top
	if indices.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A flat top at `top_m` over a polygon in chart nm, with walls down to `base_m`.
static func _add_plateau(origin_nm: Vector2, poly: PackedVector2Array, top_m: float, base_m: float, top_color: Color, wall_color: Color, vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array) -> void:
	var tri := Geometry2D.triangulate_polygon(poly)
	if tri.is_empty():
		return
	var base := vertices.size()
	for p in poly:
		vertices.append(_point(p, top_m, origin_nm))
		normals.append(Vector3.UP)
		colors.append(top_color)
	# A double-sided material flips the normal on back faces, so every top triangle must wind
	# the same way when seen from above, whatever the coastline's own orientation.
	for k in range(0, tri.size() - 2, 3):
		var i0 := base + tri[k]
		var i1 := base + tri[k + 1]
		var i2 := base + tri[k + 2]
		var face := (vertices[i1] - vertices[i0]).cross(vertices[i2] - vertices[i0])
		if face.y < 0.0:
			var swap := i1
			i1 = i2
			i2 = swap
		indices.append_array(PackedInt32Array([i0, i1, i2]))
	if top_m <= base_m:
		return
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var edge := b - a
		if edge.length_squared() < 1e-9:
			continue
		var out := edge.orthogonal().normalized()
		var probe := (a + b) * 0.5 + out * 0.02
		if Geometry2D.is_point_in_polygon(probe, poly):
			out = -out
		var normal := Vector3(out.x, 1.1, -out.y).normalized()  # shaded as a slope, not a cliff
		var start := vertices.size()
		for v in [_point(a, top_m, origin_nm), _point(b, top_m, origin_nm), _point(b, base_m, origin_nm), _point(a, base_m, origin_nm)]:
			vertices.append(v)
			normals.append(normal)
			colors.append(wall_color)
		var face := (vertices[start + 1] - vertices[start]).cross(vertices[start + 2] - vertices[start])
		if face.dot(normal) >= 0.0:
			indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))
		else:
			indices.append_array(PackedInt32Array([start, start + 2, start + 1, start, start + 3, start + 2]))


static func _point(p: Vector2, y: float, origin_nm: Vector2) -> Vector3:
	return WorldPresentation.to_world(p, origin_nm, y)
