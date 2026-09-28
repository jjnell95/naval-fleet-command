class_name ChartLayer
extends Control
## Base of the chart's shader-drawn layers, ChartFloor (sea floor and the raster's land) and
## ChartLand (the scenario's coastline polygons). A canvas item carries one material, and the
## tactical map draws everything else in one `_draw()`, so each layer is its own child with
## `show_behind_parent`: it paints under the map's coastline, marks and symbols.
##
## A layer either follows a TacticalMap's view (`map`), or its owner sets the view directly, as the
## regional map does. Presentation only: it reads Bathymetry, Terrain and ChartRelief and never
## touches simulation state.

## The map whose view this layer follows each frame. Null when the owner drives the view.
var map: TacticalMap
## World point at the layer's centre, and the scale. Copied from `map` when there is one.
var view_center_nm := Vector2.ZERO
var px_per_nm := 4.0
## Hill shading on land and sea (the chart's relief toggle).
var relief_on := true
## The regional map's darker, less saturated treatment.
var brightness := 1.0
var saturation := 1.0
## Radar-coverage discs, Vector3(centre x, centre y, radius) in world nm, at most 16.
var coverage: Array[Vector3] = []

var _material: ShaderMaterial
var _bound_generation := -1


func _init() -> void:
	show_behind_parent = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_material = ShaderMaterial.new()
	_material.shader = _shader()
	material = _material


## The layer's shader. Subclasses override.
func _shader() -> Shader:
	return null


func _process(_delta: float) -> void:
	if map != null:
		view_center_nm = map.center_nm
		px_per_nm = map.ppn
		relief_on = map.show_terrain
	queue_redraw()


## World nautical miles to this layer's local pixels, north up.
func world_to_local(w: Vector2) -> Vector2:
	var d := w - view_center_nm
	return Vector2(size.x * 0.5 + d.x * px_per_nm, size.y * 0.5 - d.y * px_per_nm)


func local_to_world(p: Vector2) -> Vector2:
	var ppn := maxf(px_per_nm, 0.0001)
	return Vector2(view_center_nm.x + (p.x - size.x * 0.5) / ppn, view_center_nm.y - (p.y - size.y * 0.5) / ppn)


## Pushes the per-frame uniforms, rebinding the region's rasters when the chart changes. False
## when there is no material yet (the layer is not in the tree).
func _update_material(with_sea: bool) -> bool:
	if _material == null:
		return false
	if _bound_generation != Bathymetry.generation:
		_bound_generation = Bathymetry.generation
		ChartRelief.bind(_material, with_sea)
	_material.set_shader_parameter("px_per_nm", px_per_nm)
	_material.set_shader_parameter("relief", 1.0 if relief_on else 0.0)
	_material.set_shader_parameter("tone_brightness", brightness)
	_material.set_shader_parameter("tone_saturation", saturation)
	var discs: Array[Vector4] = []
	for c in coverage:
		if discs.size() >= 16:
			break
		discs.append(Vector4(c.x, c.y, c.z, 0.0))
	var count := discs.size()
	while discs.size() < 16:
		discs.append(Vector4.ZERO)
	_material.set_shader_parameter("coverage", discs)
	_material.set_shader_parameter("coverage_count", count)
	return true
