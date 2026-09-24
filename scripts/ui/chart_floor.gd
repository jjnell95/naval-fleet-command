class_name ChartFloor
extends Control
## The sea floor, drawn behind the tactical plot.
##
## TacticalMap draws everything in one `_draw()`, and a canvas item carries one material, so the
## bathymetry lives on this child instead: `show_behind_parent` puts it under the map's own land,
## grid and symbols, and its shader tints depth, shades relief and draws Natural Earth's contours
## per pixel. The raster is uploaded once; each frame only the source rectangle and a few uniforms
## change, so panning and zooming cost nothing but the fill.
##
## Presentation only. It reads Bathymetry and the map's transform and never touches simulation state.

const SHADER := preload("res://scripts/ui/chart_floor.gdshader")
const RELIEF := "res://data/bathymetry/north_atlantic_relief.png"
## Half-float metres at half resolution, for smooth contours. Same bounds as the simulation raster.
const CHART := "res://data/bathymetry/north_atlantic_chart.exr"

var map: TacticalMap
var _texture: Texture2D
var _generation := -1
var _charted := Rect2()  # world rect covered by the scenario's coastline polygons
var _material: ShaderMaterial


func _ready() -> void:
	show_behind_parent = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	material = _material
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


## True when there is a floor to draw. The map falls back to its plain ocean otherwise.
func active() -> bool:
	return map != null and map.show_terrain and Bathymetry.active and _ensure_texture()


func _ensure_texture() -> bool:
	if _texture != null:
		return true
	if not ResourceLoader.exists(CHART):
		return false
	_texture = load(CHART)
	if _texture == null:
		return false
	if ResourceLoader.exists(RELIEF):
		_material.set_shader_parameter("relief_tex", load(RELIEF))
	return true


func _process(_delta: float) -> void:
	if _generation != Bathymetry.generation:
		_generation = Bathymetry.generation
		_charted = _read_charted()
	queue_redraw()


func _read_charted() -> Rect2:
	if map == null or map.simulation == null:
		return Rect2()
	var box = map.simulation.scenario.get("map", {}).get("charted_nm", [])
	if typeof(box) != TYPE_ARRAY or box.size() != 4 or Terrain.is_empty():
		return Rect2()
	return Rect2(float(box[0]), float(box[1]), float(box[2]) - float(box[0]), float(box[3]) - float(box[1]))


func _draw() -> void:
	if not active():
		return
	var world := Bathymetry.world_rect()
	if world.size.x <= 0.0 or world.size.y <= 0.0:
		return
	var tex_size := Vector2(_texture.get_width(), _texture.get_height())
	# Viewport corners in raster pixels. The region may run past the raster's edge; the shader
	# sees UV outside [0, 1] there and paints open ocean.
	var tl := _to_raster(map.screen_to_world(Vector2.ZERO), world, tex_size)
	var br := _to_raster(map.screen_to_world(size), world, tex_size)
	draw_texture_rect_region(_texture, Rect2(Vector2.ZERO, size), Rect2(tl, br - tl))
	_material.set_shader_parameter("texel", Vector2(1.0 / tex_size.x, 1.0 / tex_size.y))
	_material.set_shader_parameter("texel_px", size.x / maxf(br.x - tl.x, 0.001))
	var everywhere := Vector4(-10.0, -10.0, 10.0, 10.0)
	if _charted.size.x > 0.0:
		var a := _to_raster(Vector2(_charted.position.x, _charted.end.y), world, tex_size) / tex_size
		var b := _to_raster(Vector2(_charted.end.x, _charted.position.y), world, tex_size) / tex_size
		_material.set_shader_parameter("coast_uv", Vector4(a.x, a.y, b.x, b.y))
		_material.set_shader_parameter("chart_uv", Vector4(a.x, a.y, b.x, b.y))
	elif Terrain.is_empty():
		# No coastline polygons at all: the raster's coast is the only one, and nothing is dimmed.
		_material.set_shader_parameter("coast_uv", Vector4(-10.0, -10.0, -9.0, -9.0))
		_material.set_shader_parameter("chart_uv", everywhere)
	else:
		_material.set_shader_parameter("coast_uv", everywhere)
		_material.set_shader_parameter("chart_uv", everywhere)


static func _to_raster(w: Vector2, world: Rect2, tex_size: Vector2) -> Vector2:
	return Vector2((w.x - world.position.x) / world.size.x * tex_size.x, (world.end.y - w.y) / world.size.y * tex_size.y)


## World rectangle whose coastline comes from polygons, for the map's neatline.
func charted_rect() -> Rect2:
	return _charted
