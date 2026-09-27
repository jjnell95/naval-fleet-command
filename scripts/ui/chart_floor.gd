class_name ChartFloor
extends ChartLayer
## The sea floor, drawn behind the chart: stepped depth bands with the baked sea-floor relief, and,
## beyond the scenario's coastline polygons, the raster's own land in the same hypsometric tint, so
## the chart runs edge to edge with no clip line (chart_floor.gdshader). One rect, one material:
## panning and zooming change a few uniforms and nothing else. With no raster under the chart it
## paints the uniform floor (or deep water) with the same grain.
##
## Presentation only. It reads Bathymetry, ChartRelief and the scenario's charted box.

const SHADER := preload("res://scripts/ui/chart_floor.gdshader")

## The scenario whose charted box this floor honours. Taken from `map` when there is one.
var simulation: Simulation
var _charted_key := ""
var _charted := Rect2()  # world rect covered by the scenario's coastline polygons


func _shader() -> Shader:
	return SHADER


## True when a regional raster lies under the chart (rather than a uniform or unknown floor).
func active() -> bool:
	return Bathymetry.active and ChartRelief.region_rasters(Bathymetry.region).get("depth") != null


func _process(delta: float) -> void:
	if map != null:
		simulation = map.simulation
	var key := "%d:%d:%d" % [Bathymetry.generation, Terrain.generation, simulation.get_instance_id() if simulation != null else 0]
	if key != _charted_key:
		_charted_key = key
		_charted = charted_box(simulation)
	super(delta)


## The world rect whose coast the scenario's polygons own, or an empty rect when the raster owns
## the coast everywhere (no polygons at all).
static func charted_box(sim: Simulation) -> Rect2:
	if Terrain.is_empty():
		return Rect2()
	var box = sim.scenario.get("map", {}).get("charted_nm", []) if sim != null else []
	if typeof(box) != TYPE_ARRAY or box.size() != 4:
		# Polygons with no stated box own the coast wherever they reach.
		return Terrain.bounds
	return Rect2(float(box[0]), float(box[1]), float(box[2]) - float(box[0]), float(box[3]) - float(box[1]))


func _draw() -> void:
	if not _update_material(true):
		return
	_material.set_shader_parameter("view_origin_nm", local_to_world(Vector2.ZERO))
	_material.set_shader_parameter("nm_per_px", 1.0 / maxf(px_per_nm, 0.0001))
	var world := Bathymetry.world_rect()
	var box := Vector4(-10.0, -10.0, -9.0, -9.0)
	if _charted.size.x > 0.0 and world.size.x > 0.0:
		var a := _to_uv(Vector2(_charted.position.x, _charted.end.y), world)
		var b := _to_uv(Vector2(_charted.end.x, _charted.position.y), world)
		box = Vector4(a.x, a.y, b.x, b.y)
	_material.set_shader_parameter("charted_uv", box)
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)


static func _to_uv(w: Vector2, world: Rect2) -> Vector2:
	return Vector2((w.x - world.position.x) / world.size.x, (world.end.y - w.y) / world.size.y)


## World rectangle whose coastline comes from polygons.
func charted_rect() -> Rect2:
	return _charted
