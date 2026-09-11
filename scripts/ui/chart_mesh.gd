class_name ChartMesh
## Triangulate a coastline once in world space. Do not simplify the fill in screen space:
## deleting vertices independently can make concave islands self-intersect while zooming.

static func build(points: PackedVector2Array) -> ArrayMesh:
	var indices := Geometry2D.triangulate_polygon(points)
	if indices.is_empty():
		return null
	var vertices := PackedVector3Array()
	for p in points:
		vertices.append(Vector3(p.x, -p.y, 0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
