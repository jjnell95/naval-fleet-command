class_name WorldLand
extends Node3D
## Land for the world view: a height field around the focus, lifted from the region's
## presentation height raster (data/bathymetry/<region>_land.png) and cut to the chart's coast.
##
## The coast is the one the simulation uses. The scenario's coastline polygons are drawn once into
## three small masks that share one 2D world (a fine one near the focus, a wider one out to the
## edge of the grid, and a coarse one whose blur makes the hills rise a little way inland instead
## of from the waterline); outside the scenario's charted box the depth raster's own land carries
## on, as it does on the chart. One static grid, dense near its centre and sparse at its edge, is
## lifted in the vertex shader, so moving the focus costs a uniform update and, every few miles,
## one redraw of the masks. Presentation only, and GAMEPLAY_ESTIMATE like the rasters it reads.

const MESH_HALF_NM := 60.0
const MESH_CELLS := 192
const MESH_POWER := 1.7  # grid spacing grows with distance from the centre as t^power
const NEAR_HALF_NM := 12.0
const NEAR_PX := 1024
const FAR_PX := 1024
const RAMP_PX := 256
const RECENTRE_NM := 4.0
const JUMP_NM := NEAR_HALF_NM  # a recentre further than this is a jump, not the focus sliding on
const BASE_M := 1.4  # land at the waterline stands this far above still water
const SHELF_M := BASE_M
const FLAT_M := 40.0  # inland height where no raster covers the chart
const MIN_INLAND_M := 10.0
const HEIGHT_SCALE_M := 6000.0
const RAMP_TEXEL_M := 2.0 * MESH_HALF_NM * 1852.0 / RAMP_PX
## Ground colours by climate: beach, low, mid, high, rock, snow, and the snow line in metres.
const PALETTES := {
	"arid": [Color(0.84, 0.76, 0.58), Color(0.78, 0.66, 0.47), Color(0.70, 0.58, 0.42), Color(0.62, 0.52, 0.42), Color(0.55, 0.47, 0.40), Color(0.92, 0.92, 0.94), 3800.0],
	"mediterranean": [Color(0.82, 0.76, 0.60), Color(0.56, 0.54, 0.36), Color(0.52, 0.50, 0.36), Color(0.58, 0.53, 0.44), Color(0.56, 0.52, 0.46), Color(0.93, 0.94, 0.96), 2400.0],
	"boreal": [Color(0.56, 0.54, 0.48), Color(0.33, 0.38, 0.28), Color(0.38, 0.40, 0.32), Color(0.48, 0.48, 0.46), Color(0.42, 0.42, 0.42), Color(0.93, 0.95, 0.98), 620.0],
	"tropical": [Color(0.88, 0.82, 0.64), Color(0.26, 0.42, 0.20), Color(0.30, 0.42, 0.22), Color(0.40, 0.46, 0.31), Color(0.46, 0.44, 0.38), Color(0.93, 0.94, 0.96), 5000.0],
}

## The chart rectangle the coastline polygons are authoritative for; empty means everywhere.
var charted := Rect2()

var _origin_nm := Vector2.ZERO
var _centre := Vector2.INF
var _pending := Vector2.INF
var _pending_frames := 0
var _terrain_generation := -1
var _bathy_generation := -1
var _mesh: MeshInstance3D
var _material: ShaderMaterial
var _near: SubViewport
var _far: SubViewport
var _ramp: SubViewport
var _polygons: Node2D
var _region := ""
var _heights := PackedByteArray()
var _hw := 0
var _hh := 0
var _present := false

static var _grid: ArrayMesh
static var _height_textures: Dictionary = {}
static var _depth_textures: Dictionary = {}
static var _height_data: Dictionary = {}


func build() -> void:
	name = "Land"
	_near = _mask_viewport(NEAR_PX)
	_polygons = Node2D.new()
	_polygons.name = "Coast"
	_near.add_child(_polygons)
	_far = _mask_viewport(FAR_PX)
	_far.world_2d = _near.world_2d
	_ramp = _mask_viewport(RAMP_PX)
	_ramp.world_2d = _near.world_2d
	_material = ShaderMaterial.new()
	_material.shader = load("res://scripts/ui/world_land.gdshader")
	_material.set_shader_parameter("near_mask", _near.get_texture())
	_material.set_shader_parameter("far_mask", _far.get_texture())
	_material.set_shader_parameter("ramp_mask", _ramp.get_texture())
	_material.set_shader_parameter("near_half_m", NEAR_HALF_NM * WorldPresentation.NM_TO_M)
	_material.set_shader_parameter("far_half_m", MESH_HALF_NM * WorldPresentation.NM_TO_M)
	_material.set_shader_parameter("height_scale_m", HEIGHT_SCALE_M)
	_material.set_shader_parameter("base_m", BASE_M)
	_material.set_shader_parameter("flat_m", FLAT_M)
	_material.set_shader_parameter("min_inland_m", MIN_INLAND_M)
	_mesh = MeshInstance3D.new()
	_mesh.name = "Ground"
	_mesh.mesh = grid_mesh()
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.visible = false
	add_child(_mesh)


func _mask_viewport(px: int) -> SubViewport:
	var v := SubViewport.new()
	v.size = Vector2i(px, px)
	v.transparent_bg = true
	v.disable_3d = true
	v.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(v)
	return v


# --- Per frame -----------------------------------------------------------------------------

## Follows the floating origin. Rebuilds its sources when the chart changes, and recentres the
## grid when the focus has moved a few miles, one frame after asking for the masks to be redrawn
## so the grid never shows a coast drawn for somewhere else.
func update(origin_nm: Vector2) -> void:
	_origin_nm = origin_nm
	if _terrain_generation != Terrain.generation or _bathy_generation != Bathymetry.generation:
		_rebuild_sources()
	if _pending == Vector2.INF and (_centre == Vector2.INF or _centre.distance_to(origin_nm) > RECENTRE_NM):
		_begin_recentre(origin_nm)
	if _pending != Vector2.INF:
		_pending_frames -= 1
		if _pending_frames <= 0 or _centre == Vector2.INF:
			_apply_centre(_pending)
			_pending = Vector2.INF
	if _centre != Vector2.INF:
		_mesh.position = WorldPresentation.to_world(_centre, origin_nm, 0.0)


func reset() -> void:
	_terrain_generation = -1
	_bathy_generation = -1
	_centre = Vector2.INF
	_pending = Vector2.INF
	_mesh.visible = false


## Dims the ground's own glow with the light.
func set_daylight(daylight: float) -> void:
	if _material != null:
		_material.set_shader_parameter("ground_glow", 0.32 * daylight)


## The near mask and its window (x, z of its centre about the floating origin, half size in
## metres; a negative size means no coast), for the sea's surf line.
func coast_texture() -> Texture2D:
	return _near.get_texture() if _near != null else null


func coast_window() -> Vector3:
	if _centre == Vector2.INF or not _present or Terrain.landmasses.is_empty():
		return Vector3(0.0, 0.0, -1.0)
	var c := WorldPresentation.to_world(_centre, _origin_nm, 0.0)
	return Vector3(c.x, c.z, NEAR_HALF_NM * WorldPresentation.NM_TO_M)


# --- Sources -------------------------------------------------------------------------------

func _rebuild_sources() -> void:
	_terrain_generation = Terrain.generation
	_bathy_generation = Bathymetry.generation
	_centre = Vector2.INF
	_pending = Vector2.INF
	for child in _polygons.get_children():
		_polygons.remove_child(child)
		child.queue_free()
	for l: Landmass in Terrain.landmasses:
		if not l.valid():
			continue
		# Drawn with north up by flipping the points, not the canvas: a mirrored canvas transform
		# gets its items culled.
		var flipped := PackedVector2Array()
		flipped.resize(l.points.size())
		for i in l.points.size():
			flipped[i] = Vector2(l.points[i].x, -l.points[i].y)
		var poly := Polygon2D.new()
		poly.polygon = flipped
		poly.color = Color.WHITE
		poly.antialiased = true
		_polygons.add_child(poly)
	_region = Bathymetry.region if Bathymetry.active else ""
	var has_raster := _region != "" and _ensure_region(_region)
	_material.set_shader_parameter("use_raster", 1.0 if has_raster else 0.0)
	_material.set_shader_parameter("use_polygons", 0.0 if Terrain.landmasses.is_empty() else 1.0)
	if has_raster:
		var tex: Texture2D = _height_textures[_region]
		_material.set_shader_parameter("height_tex", tex)
		_material.set_shader_parameter("depth_tex", _depth_textures[_region])
		_material.set_shader_parameter("height_size", Vector2(tex.get_width(), tex.get_height()))
		var data: Dictionary = _height_data[_region]
		_heights = data["data"]
		_hw = int(data["w"])
		_hh = int(data["h"])
	else:
		_heights = PackedByteArray()
		_hw = 0
		_hh = 0


## Loads a region's height raster (as a texture, and as bytes for the few points the CPU needs)
## and its depth raster as a texture. False when the region has no height raster.
static func _ensure_region(region: String) -> bool:
	if _height_textures.has(region):
		return _height_textures[region] != null
	var path := "res://data/bathymetry/%s_land.png" % region
	var depth := Bathymetry.source_image(region)
	if not ResourceLoader.exists(path) or depth == null:
		_height_textures[region] = null
		return false
	var tex := load(path) as Texture2D
	var img := tex.get_image() if tex != null else null
	if img == null or img.is_empty():
		_height_textures[region] = null
		return false
	if img.get_format() != Image.FORMAT_L8:
		img = img.duplicate() as Image
		img.convert(Image.FORMAT_L8)
	_height_textures[region] = tex
	_depth_textures[region] = ImageTexture.create_from_image(depth)
	_height_data[region] = {"data": img.get_data(), "w": img.get_width(), "h": img.get_height()}
	return true


func _begin_recentre(centre: Vector2) -> void:
	_pending = centre
	_pending_frames = 2
	_present = _land_near(centre)
	if not _present:
		return
	# A jump (a new hook far off, or the Action camera going to an event): the masks about to be
	# drawn are for somewhere the grid is not yet, and would put a coast in the wrong place for
	# the frames until it moves. Show no land until it has; a slide of a few miles keeps it.
	if _centre != Vector2.INF and _centre.distance_to(centre) > JUMP_NM:
		_mesh.visible = false
	_draw_mask(_near, centre, NEAR_HALF_NM, NEAR_PX)
	_draw_mask(_far, centre, MESH_HALF_NM, FAR_PX)
	_draw_mask(_ramp, centre, MESH_HALF_NM, RAMP_PX)


func _draw_mask(v: SubViewport, centre: Vector2, half_nm: float, px: int) -> void:
	var s := float(px) / (2.0 * half_nm)
	v.canvas_transform = Transform2D(Vector2(s, 0.0), Vector2(0.0, s), Vector2(px * 0.5 - centre.x * s, px * 0.5 + centre.y * s))
	v.render_target_update_mode = SubViewport.UPDATE_ONCE


## Whether any land lies inside the grid around `centre`, so an open-ocean view draws no grid.
func _land_near(centre: Vector2) -> bool:
	var window := Rect2(centre - Vector2.ONE * MESH_HALF_NM, Vector2.ONE * MESH_HALF_NM * 2.0)
	if not Terrain.landmasses.is_empty():
		for l: Landmass in Terrain.landmasses:
			if l.valid() and l.bounds.intersects(window):
				return true
	var polygons_everywhere := not Terrain.landmasses.is_empty() and charted.size.x <= 0.0
	if polygons_everywhere or _hw <= 0 or not Bathymetry.active:
		return false
	var steps := 24
	for j in steps + 1:
		for i in steps + 1:
			var p := window.position + window.size * Vector2(float(i) / steps, float(j) / steps)
			if charted.size.x > 0.0 and charted.has_point(p) and not Terrain.landmasses.is_empty():
				continue
			if Bathymetry.depth_at(p) == 0.0:
				return true
	return false


func _apply_centre(centre: Vector2) -> void:
	_centre = centre
	_mesh.visible = _present
	if not _present:
		return
	var m := WorldPresentation.NM_TO_M
	if charted.size.x > 0.0:
		_material.set_shader_parameter("charted_m", Vector4((charted.position.x - centre.x) * m, -(charted.end.y - centre.y) * m, (charted.end.x - centre.x) * m, -(charted.position.y - centre.y) * m))
	else:
		_material.set_shader_parameter("charted_m", Vector4(-1.0e9, -1.0e9, 1.0e9, 1.0e9))
	if _hw > 0:
		var r: Dictionary = Bathymetry.REGIONS[_region]
		var lon_span := float(r["cell_lon"]) * _hw
		var lat_span := float(r["cell_lat"]) * _hh
		var nm_per_deg_lon := 60.0 * maxf(cos(deg_to_rad(Bathymetry.anchor_lat)), 0.001)
		_material.set_shader_parameter("uv_origin", raster_uv(centre))
		_material.set_shader_parameter("uv_per_m", Vector2(1.0 / (m * nm_per_deg_lon * lon_span), 1.0 / (m * 60.0 * lat_span)))
	var lat := Bathymetry.anchor_lat + centre.y / 60.0 if Bathymetry.active else 60.0
	var p: Array = PALETTES[climate(_region, lat)]
	var names := ["col_beach", "col_low", "col_mid", "col_high", "col_rock", "col_snow"]
	for i in names.size():
		_material.set_shader_parameter(names[i], p[i])
	_material.set_shader_parameter("snow_line_m", p[6])


# --- Queries -------------------------------------------------------------------------------

## The ground's climate, for its colours: the Gulf and the Red Sea are desert, the Norwegian Sea
## is boreal, the South China Sea tropical.
static func climate(region: String, lat_deg: float) -> String:
	match region:
		"arabian_sea":
			return "arid"
		"mediterranean":
			return "arid" if lat_deg < 36.5 else "mediterranean"
		"west_pacific":
			return "tropical" if lat_deg < 26.0 else "mediterranean"
	return "boreal" if absf(lat_deg) > 50.0 else "mediterranean"


## The raster's texture coordinate for a chart position, under the current anchor.
func raster_uv(p: Vector2) -> Vector2:
	if _hw <= 0:
		return Vector2.ZERO
	var r: Dictionary = Bathymetry.REGIONS[_region]
	var nm_per_deg_lon := 60.0 * maxf(cos(deg_to_rad(Bathymetry.anchor_lat)), 0.001)
	var lon := Bathymetry.anchor_lon + p.x / nm_per_deg_lon
	var lat := Bathymetry.anchor_lat + p.y / 60.0
	return Vector2((lon - float(r["lon_min"])) / (float(r["cell_lon"]) * _hw), (float(r["lat_max"]) - lat) / (float(r["cell_lat"]) * _hh))


## The raster's height at a chart position, B-spline filtered as the shader filters it.
func raster_height_m(p: Vector2) -> float:
	if _hw <= 0:
		return FLAT_M
	var uv := raster_uv(p)
	var fx := uv.x * _hw - 0.5
	var fy := uv.y * _hh - 0.5
	var ix := int(floorf(fx))
	var iy := int(floorf(fy))
	var tx := fx - ix
	var ty := fy - iy
	var v := 0.0
	for j in 4:
		var wy := bspline_weight(ty, j)
		var y := clampi(iy - 1 + j, 0, _hh - 1)
		for i in 4:
			var x := clampi(ix - 1 + i, 0, _hw - 1)
			v += wy * bspline_weight(tx, i) * _heights[y * _hw + x] / 255.0
	return HEIGHT_SCALE_M * v * v


## Cubic B-spline weight of tap `i` (0..3) at fraction `t` between taps 1 and 2.
static func bspline_weight(t: float, i: int) -> float:
	match i:
		0:
			return pow(1.0 - t, 3.0) / 6.0
		1:
			return (3.0 * t * t * t - 6.0 * t * t + 4.0) / 6.0
		2:
			return (-3.0 * t * t * t + 3.0 * t * t + 3.0 * t + 1.0) / 6.0
	return t * t * t / 6.0


## Whether a chart position is land by the same rule the shader draws: the polygons inside the
## charted box, the raster outside it.
func is_land(p: Vector2) -> bool:
	if not Terrain.landmasses.is_empty() and (charted.size.x <= 0.0 or charted.has_point(p)):
		return Terrain.is_land(p)
	return _hw > 0 and Bathymetry.active and Bathymetry.depth_at(p) == 0.0


## Ground height at a chart position, 0 at sea. `inland_m` is the distance from the coast when
## the caller knows it (an installation); without it the height is the full inland height, which
## errs high, as a camera clearance should.
func height_at(p: Vector2, inland_m := INF) -> float:
	if not is_land(p):
		return 0.0
	var ramp := 1.0
	if inland_m != INF:
		ramp = smoothstep(0.5, 1.0, clampf(0.5 + inland_m / RAMP_TEXEL_M, 0.0, 1.0))
	var h := maxf(raster_height_m(p), MIN_INLAND_M) if _hw > 0 else FLAT_M
	return BASE_M + h * ramp


# --- Grid ----------------------------------------------------------------------------------

## One square grid, (MESH_CELLS + 1)^2 vertices over the whole window, spaced finely at the
## centre and coarsely at the edge. Flat: the shader lifts it.
static func grid_mesh() -> ArrayMesh:
	if _grid != null:
		return _grid
	var n := MESH_CELLS + 1
	var half := MESH_HALF_NM * WorldPresentation.NM_TO_M
	var coords := PackedFloat32Array()
	coords.resize(n)
	for i in n:
		var t := 2.0 * float(i) / float(MESH_CELLS) - 1.0
		coords[i] = signf(t) * pow(absf(t), MESH_POWER) * half
	var vertices := PackedVector3Array()
	vertices.resize(n * n)
	var normals := PackedVector3Array()
	normals.resize(n * n)
	for j in n:
		for i in n:
			vertices[j * n + i] = Vector3(coords[i], 0.0, coords[j])
			normals[j * n + i] = Vector3.UP
	var indices := PackedInt32Array()
	indices.resize(MESH_CELLS * MESH_CELLS * 6)
	var k := 0
	for j in MESH_CELLS:
		for i in MESH_CELLS:
			var a := j * n + i
			indices[k] = a
			indices[k + 1] = a + 1
			indices[k + 2] = a + n
			indices[k + 3] = a + 1
			indices[k + 4] = a + n + 1
			indices[k + 5] = a + n
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-half, -50.0, -half), Vector3(half * 2.0, 7000.0, half * 2.0))
	_grid = mesh
	return mesh

