class_name ChartRelief
## The chart's presentation rasters, loaded once per region and shared by every chart layer: the
## sea floor's depth and relief, a water mask for the raster's own coast, and the land height and
## hill-shade built from GMTED2010 (data/bathymetry/<region>_land.png and _land_relief.png).
##
## Every raster of a region shares the bounds, cell size and north-first row order of the depth
## raster that Bathymetry loads, so Bathymetry.world_rect() places them all. The land height is
## presentation only: the simulation's masking heights stay in Terrain, and nothing here feeds back
## into it. height_at() serves the chart's cursor readout.

const HEIGHT_SCALE_M := 6000.0
const SEA_RELIEF := 0.35  # colour *= 1 + shade * SEA_RELIEF over water
const UNKNOWN := -1.0

## Loaded rasters by region: textures for the shaders, and separately the land heights on the CPU
## for height_at(), read back only when the readout first asks.
static var _regions: Dictionary = {}
static var _heights: Dictionary = {}
static var _decode := PackedFloat32Array()  # byte value -> metres


static func land_path(region: String) -> String:
	return "res://data/bathymetry/%s_land.png" % region


static func land_relief_path(region: String) -> String:
	return "res://data/bathymetry/%s_land_relief.png" % region


## Everything this region has, loading it on first use. Missing files leave their entries null.
static func region_rasters(region: String) -> Dictionary:
	if _regions.has(region):
		return _regions[region]
	var out := {}
	out["depth"] = _load_texture(Bathymetry.chart_path(region))
	out["sea_relief"] = _load_texture(Bathymetry.relief_path(region))
	out["water"] = _water_mask(region)
	out["land"] = _load_texture(land_path(region))
	out["land_relief"] = _load_texture(land_relief_path(region))
	_regions[region] = out
	return out


## The land height codes on the CPU: {data, w, h}, or empty with no land raster. The raster is
## imported as a texture for the shaders, so this reads it back once (on the web, a render-target
## copy; about 50 ms for the largest region).
static func land_heights(region: String) -> Dictionary:
	if _heights.has(region):
		return _heights[region]
	var out := {}
	var land: Texture2D = region_rasters(region).get("land")
	var img := land.get_image() if land != null else null
	if img != null and not img.is_empty():
		if img.get_format() != Image.FORMAT_L8:
			img.convert(Image.FORMAT_L8)
		out = {"data": img.get_data(), "w": img.get_width(), "h": img.get_height()}
	_heights[region] = out
	return out


static func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## The raster's own land and water at full resolution: white where the depth raster holds water,
## black where it holds land (depth 0). The chart samples it smoothly for a crisp coast beyond the
## scenario's polygons. Built natively: brightness x255 lifts every non-zero byte to at least 1.0
## and a steep contrast about 0.5 then clips land to 0 and water to 1, with no per-pixel script loop.
static func _water_mask(region: String) -> Texture2D:
	var img := Bathymetry.source_image(region)
	if img == null or img.is_empty():
		return null
	img.adjust_bcs(255.0, 1000.0, 1.0)
	return ImageTexture.create_from_image(img)


## Land height in metres at a world position under the active chart: 0 at or below sea level,
## UNKNOWN where there is no raster. Bilinear, like Bathymetry.depth_at.
static func height_at(p: Vector2) -> float:
	if not Bathymetry.active:
		return UNKNOWN
	var r := land_heights(Bathymetry.region)
	if r.is_empty():
		return UNKNOWN
	return sample_heights(r["data"], int(r["w"]), int(r["h"]), Bathymetry.world_rect(), p)


## Bilinear lookup into a height-code raster covering `world`, in metres. Split out for the tests.
static func sample_heights(data: PackedByteArray, w: int, h: int, world: Rect2, p: Vector2) -> float:
	if w <= 0 or h <= 0 or world.size.x <= 0.0 or world.size.y <= 0.0:
		return UNKNOWN
	var fx := (p.x - world.position.x) / world.size.x * w - 0.5
	var fy := (world.end.y - p.y) / world.size.y * h - 0.5
	if fx < -0.5 or fy < -0.5 or fx > w - 0.5 or fy > h - 0.5:
		return UNKNOWN
	if _decode.is_empty():
		_decode.resize(256)
		for v in 256:
			_decode[v] = decode(v)
	var x0 := clampi(int(floor(fx)), 0, w - 1)
	var y0 := clampi(int(floor(fy)), 0, h - 1)
	var x1 := mini(x0 + 1, w - 1)
	var y1 := mini(y0 + 1, h - 1)
	var tx := clampf(fx - x0, 0.0, 1.0)
	var ty := clampf(fy - y0, 0.0, 1.0)
	var a := _decode[data[y0 * w + x0]]
	var b := _decode[data[y0 * w + x1]]
	var c := _decode[data[y1 * w + x0]]
	var d := _decode[data[y1 * w + x1]]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


## Height code to metres: 6000 * (v / 255)^2, as data/bathymetry/<region>_land.json documents.
static func decode(v: int) -> float:
	return HEIGHT_SCALE_M * pow(v / 255.0, 2.0)


## Binds the active region's rasters, and the uniforms every chart layer shares, to a material
## built from chart_floor.gdshader or chart_land.gdshader. `with_sea` adds the floor's own rasters.
static func bind(material: ShaderMaterial, with_sea: bool) -> void:
	var active := Bathymetry.active
	var r := region_rasters(Bathymetry.region) if active else {}
	var world := Bathymetry.world_rect()
	material.set_shader_parameter("world_rect", Vector4(world.position.x, world.position.y, maxf(world.size.x, 0.001), maxf(world.size.y, 0.001)))
	var land: Texture2D = r.get("land")
	var land_relief: Texture2D = r.get("land_relief")
	var has_land := land != null and land_relief != null
	material.set_shader_parameter("land_tex", land)
	material.set_shader_parameter("land_relief_tex", land_relief)
	material.set_shader_parameter("land_texel", _texel(land))
	material.set_shader_parameter("land_raster", 1.0 if has_land else 0.0)
	if not with_sea:
		return
	var depth: Texture2D = r.get("depth")
	var water: Texture2D = r.get("water")
	var sea_relief: Texture2D = r.get("sea_relief")
	material.set_shader_parameter("depth_tex", depth)
	material.set_shader_parameter("depth_texel", _texel(depth))
	material.set_shader_parameter("water_tex", water)
	material.set_shader_parameter("water_texel", _texel(water))
	material.set_shader_parameter("depth_raster", 1.0 if depth != null and water != null else 0.0)
	material.set_shader_parameter("sea_relief_tex", sea_relief)
	material.set_shader_parameter("sea_relief_texel", _texel(sea_relief))
	material.set_shader_parameter("sea_relief", SEA_RELIEF if sea_relief != null else 0.0)
	material.set_shader_parameter("uniform_depth_m", Bathymetry.uniform_m if not active and Bathymetry.uniform_m >= 0.0 else 2000.0)


static func _texel(tex: Texture2D) -> Vector2:
	if tex == null:
		return Vector2(0.001, 0.001)
	return Vector2(1.0 / maxf(tex.get_width(), 1.0), 1.0 / maxf(tex.get_height(), 1.0))
