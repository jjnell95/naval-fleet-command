class_name ChartLand
extends ChartLayer
## The scenario's own coastline polygons, the land the simulation grounds ships on and masks radar
## with, filled with the chart's hypsometric tint and hill shading (chart_land.gdshader). Drawn just
## above ChartFloor and below the map's own `_draw()`, which strokes the crisp coastline on top.
##
## Every landmass is triangulated into one mesh, shared by every ChartLand (tactical and regional
## map) and rebuilt only when Terrain changes, so the whole coastline is one draw call however many
## islands a scenario has. The GPU clips what lies outside the view.

const SHADER := preload("res://scripts/ui/chart_land.gdshader")

static var _mesh: ArrayMesh  # world nm with y negated; null when there is no land
static var _mesh_generation := -1


func _shader() -> Shader:
	return SHADER


## The triangulated fill of the current coastline, built once per Terrain generation.
static func land_mesh() -> ArrayMesh:
	if _mesh_generation != Terrain.generation:
		_mesh = _build(Terrain.landmasses)
		_mesh_generation = Terrain.generation
	return _mesh


## Every landmass's triangulation in one surface. Triangulated in world space, one polygon at a
## time, never simplified (see ChartMesh); a polygon that will not triangulate is left out.
static func _build(landmasses: Array[Landmass]) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for l: Landmass in landmasses:
		var tri := Geometry2D.triangulate_polygon(l.points)
		if tri.is_empty():
			continue
		var base := vertices.size()
		for p in l.points:
			vertices.append(Vector3(p.x, -p.y, 0.0))
		for i in tri:
			indices.append(base + i)
	if indices.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _draw() -> void:
	if Terrain.is_empty() or not _update_material(false):
		return
	var view := Rect2(local_to_world(Vector2.ZERO), Vector2.ZERO).expand(local_to_world(size))
	var mesh := land_mesh()
	if mesh == null or not Terrain.bounds.intersects(view):
		return
	draw_mesh(mesh, null, Transform2D(Vector2(px_per_nm, 0.0), Vector2(0.0, px_per_nm), world_to_local(Vector2.ZERO)))
