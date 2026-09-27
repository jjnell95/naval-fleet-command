class_name ChartLand
extends ChartLayer
## The scenario's own coastline polygons, the land the simulation grounds ships on and masks radar
## with, filled with the chart's hypsometric tint and hill shading (chart_land.gdshader). Drawn just
## above ChartFloor and below the map's own `_draw()`, which strokes the crisp coastline on top.
##
## The triangulated meshes are shared by every ChartLand (tactical and regional map) and rebuilt only
## when Terrain changes.

const SHADER := preload("res://scripts/ui/chart_land.gdshader")

static var _meshes: Dictionary = {}  # Landmass -> ArrayMesh, world nm with y negated
static var _mesh_generation := -1


func _shader() -> Shader:
	return SHADER


## Triangulated fills for the current coastline, built once per Terrain generation.
static func land_meshes() -> Dictionary:
	if _mesh_generation != Terrain.generation:
		_meshes.clear()
		for l: Landmass in Terrain.landmasses:
			_meshes[l] = ChartMesh.build(l.points)
		_mesh_generation = Terrain.generation
	return _meshes


func _draw() -> void:
	if Terrain.is_empty() or not _update_material(false):
		return
	var view := Rect2(local_to_world(Vector2.ZERO), Vector2.ZERO).expand(local_to_world(size))
	var meshes := land_meshes()
	var xform := Transform2D(Vector2(px_per_nm, 0.0), Vector2(0.0, px_per_nm), world_to_local(Vector2.ZERO))
	for l: Landmass in Terrain.landmasses:
		if not l.bounds.intersects(view):
			continue
		var mesh: ArrayMesh = meshes.get(l)
		if mesh != null:
			draw_mesh(mesh, null, xform)
