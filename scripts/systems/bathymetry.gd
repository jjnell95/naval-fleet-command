class_name Bathymetry
## The sea floor under the chart.
##
## Regional rasters, built offline from Natural Earth 1:10m bathymetry by
## `tools/scenarios/import_bathymetry.py`, cover every theatre the game plays in. A scenario reaches
## its region through its map anchor: the game's local projection is equirectangular about that
## point, so world nautical miles map onto latitude and longitude by a plain scale and offset, and
## one raster per region serves any chart in it without being cut or reprojected per mission.
##
## Static, like Terrain, so the movement, sensor and rendering code can all ask without a reference
## being plumbed through. A scenario with no anchor, or an anchor outside every region, leaves the
## floor unknown: `depth_at` returns UNKNOWN and every consumer treats unknown as "no effect", which
## is what keeps hand-built test worlds and the older open-ocean scenarios exactly as they were.
## `environment.bottom_m` sets a uniform floor instead, for a synthetic chart or a test.
##
## Each raster honours Natural Earth's 0/200/1000/2000/3000/4000/5000 m contours and interpolates
## between them. It is a 1:10 million chart: good for shelf against basin and ridge against trough,
## silent about shoals, channels and under-keel clearance. It is never a navigation chart.

## The chart regions, in step with tools/scenarios/regions.py and the metadata written beside each
## raster (data/bathymetry/<region>_depth.json); tests/test_ocean.gd holds them together.
const REGIONS := {
	"north_atlantic": {"lon_min": -46.0, "lat_min": 52.0, "lon_max": 55.0, "lat_max": 81.0, "cell_lon": 1.0 / 30.0, "cell_lat": 1.0 / 60.0,
		"title": "North Atlantic, Norwegian Sea, Barents Sea and Baltic"},
	"west_pacific": {"lon_min": 99.0, "lat_min": -2.0, "lon_max": 152.0, "lat_max": 52.0, "cell_lon": 1.0 / 24.0, "cell_lat": 1.0 / 48.0,
		"title": "Western Pacific: East and South China Seas, Philippine Sea, Sea of Japan"},
	"arabian_sea": {"lon_min": 30.0, "lat_min": 8.0, "lon_max": 76.0, "lat_max": 32.0, "cell_lon": 1.0 / 24.0, "cell_lat": 1.0 / 48.0,
		"title": "Persian Gulf, Gulf of Oman, Arabian Sea and Red Sea"},
	"mediterranean": {"lon_min": -7.0, "lat_min": 29.0, "lon_max": 43.0, "lat_max": 47.0, "cell_lon": 1.0 / 30.0, "cell_lat": 1.0 / 60.0,
		"title": "Mediterranean and Black Sea approaches"},
}
const DEFAULT_REGION := "north_atlantic"
const DEPTH_SCALE_M := 6000.0
const CONTOURS_M: Array[float] = [200.0, 1000.0, 2000.0, 3000.0, 4000.0, 5000.0]
const UNKNOWN := -1.0

## Loaded rasters, by region: {data: PackedByteArray, w: int, h: int}.
static var _rasters: Dictionary = {}
static var _missing: Dictionary = {}
static var _decode := PackedFloat32Array()  # byte value -> metres

## Per-scenario state.
static var active := false
static var region := DEFAULT_REGION
static var uniform_m := UNKNOWN
static var anchor_lat := 0.0
static var anchor_lon := 0.0
static var _nm_per_deg_lon := 60.0
static var _lon_min := -46.0
static var _lat_max := 81.0
static var _cell_lon := 1.0 / 30.0
static var _cell_lat := 1.0 / 60.0
static var _data := PackedByteArray()
static var _w := 0
static var _h := 0
## Bumped whenever the floor changes, so the renderer can rebuild its texture and transform.
static var generation := 0


static func clear() -> void:
	active = false
	uniform_m = UNKNOWN
	generation += 1


## Reads the scenario's map anchor and environment. Absent or out of range means an unknown floor.
static func load_for(scenario: Dictionary) -> void:
	clear()
	var m = scenario.get("map", {})
	var recipe = scenario.get("recipe", {})
	# Explicit exercise mode also repairs missions saved by the original fleet builder.
	if (typeof(m) == TYPE_DICTIONARY and m.get("open_water", false) == true) or (typeof(recipe) == TYPE_DICTIONARY and recipe.has("coastlines") and recipe["coastlines"] == false):
		uniform_m = 2000.0
		return
	var env = scenario.get("environment", {})
	if typeof(env) == TYPE_DICTIONARY and env.has("bottom_m"):
		uniform_m = maxf(float(env["bottom_m"]), 0.0)
		return
	if typeof(m) != TYPE_DICTIONARY or not m.has("anchor_lat") or not m.has("anchor_lon"):
		return
	set_anchor(float(m["anchor_lat"]), float(m["anchor_lon"]), str(m.get("chart_region", "")))


## The region whose bounds hold the point with the most margin to an edge, or "" for none.
static func region_for(lat: float, lon: float) -> String:
	var best := ""
	var best_margin := -1.0
	for name: String in REGIONS:
		var r: Dictionary = REGIONS[name]
		var margin := minf(minf(lon - float(r["lon_min"]), float(r["lon_max"]) - lon), minf(lat - float(r["lat_min"]), float(r["lat_max"]) - lat))
		if margin >= 0.0 and margin > best_margin:
			best = name
			best_margin = margin
	return best


static func set_anchor(lat: float, lon: float, preferred := "") -> void:
	clear()
	var name := preferred if REGIONS.has(preferred) else region_for(lat, lon)
	if name == "" or not _ensure_source(name):
		return
	var r: Dictionary = REGIONS[name]
	if lon < float(r["lon_min"]) or lon > float(r["lon_max"]) or lat > float(r["lat_max"]) or lat < float(r["lat_min"]):
		return
	region = name
	_lon_min = float(r["lon_min"])
	_lat_max = float(r["lat_max"])
	_cell_lon = float(r["cell_lon"])
	_cell_lat = float(r["cell_lat"])
	var raster: Dictionary = _rasters[name]
	_data = raster["data"]
	_w = int(raster["w"])
	_h = int(raster["h"])
	anchor_lat = lat
	anchor_lon = lon
	_nm_per_deg_lon = 60.0 * maxf(cos(deg_to_rad(lat)), 0.001)
	active = true


static func is_empty() -> bool:
	return not active and uniform_m < 0.0


static func depth_path(name: String) -> String:
	return "res://data/bathymetry/%s_depth.png" % name


static func chart_path(name: String) -> String:
	return "res://data/bathymetry/%s_chart.exr" % name


static func relief_path(name: String) -> String:
	return "res://data/bathymetry/%s_relief.png" % name


static func _ensure_source(name: String) -> bool:
	if _rasters.has(name):
		return true
	if _missing.has(name):
		return false
	var path := depth_path(name)
	if not ResourceLoader.exists(path):
		push_warning("Bathymetry: %s is missing; the %s sea floor is unknown" % [path, name])
		_missing[name] = true
		return false
	var img := load(path) as Image
	if img == null or img.is_empty():
		_missing[name] = true
		return false
	if img.get_format() != Image.FORMAT_L8:
		img = img.duplicate() as Image
		img.convert(Image.FORMAT_L8)
	_rasters[name] = {"data": img.get_data(), "w": img.get_width(), "h": img.get_height()}
	if _decode.is_empty():
		_decode.resize(256)
		for v in 256:
			_decode[v] = DEPTH_SCALE_M * pow(v / 255.0, 2.0)
	return true


## A region's raster as an Image, for the chart renderer and tests. Null when there is none.
static func source_image(name := "") -> Image:
	var which := name if name != "" else region
	if not _ensure_source(which):
		return null
	var raster: Dictionary = _rasters[which]
	return Image.create_from_data(int(raster["w"]), int(raster["h"]), false, Image.FORMAT_L8, raster["data"])


## World rectangle, in nautical miles, that the active raster covers under the current anchor.
static func world_rect() -> Rect2:
	if not active:
		return Rect2()
	var x0 := (_lon_min - anchor_lon) * _nm_per_deg_lon
	var x1 := (_lon_min + _w * _cell_lon - anchor_lon) * _nm_per_deg_lon
	var y1 := (_lat_max - anchor_lat) * 60.0
	var y0 := (_lat_max - _h * _cell_lat - anchor_lat) * 60.0
	return Rect2(x0, y0, x1 - x0, y1 - y0)


## Water depth in metres at a world position, 0 ashore, UNKNOWN where there is no chart.
## Bilinear across the four nearest cells, so the floor is continuous under a moving hull.
static func depth_at(p: Vector2) -> float:
	if not active:
		return uniform_m
	var lon := anchor_lon + p.x / _nm_per_deg_lon
	var lat := anchor_lat + p.y / 60.0
	var fx := (lon - _lon_min) / _cell_lon - 0.5
	var fy := (_lat_max - lat) / _cell_lat - 0.5
	if fx < -0.5 or fy < -0.5 or fx > _w - 0.5 or fy > _h - 0.5:
		return UNKNOWN
	var x0 := clampi(int(floor(fx)), 0, _w - 1)
	var y0 := clampi(int(floor(fy)), 0, _h - 1)
	var x1 := mini(x0 + 1, _w - 1)
	var y1 := mini(y0 + 1, _h - 1)
	var tx := clampf(fx - x0, 0.0, 1.0)
	var ty := clampf(fy - y0, 0.0, 1.0)
	var a := _decode[_data[y0 * _w + x0]]
	var b := _decode[_data[y0 * _w + x1]]
	var c := _decode[_data[y1 * _w + x0]]
	var d := _decode[_data[y1 * _w + x1]]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


## The shallowest water along a path, sampled every few miles. Deep-water propagation needs deep
## water the whole way, not just at the two ends.
static func min_depth_along(a: Vector2, b: Vector2, step_nm := 4.0) -> float:
	if is_empty():
		return UNKNOWN
	var length := a.distance_to(b)
	var steps := clampi(int(ceil(length / step_nm)), 1, 64)
	var shallowest := INF
	for i in steps + 1:
		var d := depth_at(a.lerp(b, float(i) / steps))
		if d < 0.0:
			return UNKNOWN
		shallowest = minf(shallowest, d)
	return shallowest


## Chart annotation: "2,850 m", "shelf 140 m", or an empty string with no chart.
static func format_depth(d: float) -> String:
	if d < 0.0:
		return ""
	if d < 1.0:
		return "ashore"
	var metres := int(round(d / 10.0)) * 10 if d >= 100.0 else int(round(d))
	var s := str(metres)
	if metres >= 1000:
		@warning_ignore("integer_division")
		s = "%d,%03d" % [metres / 1000, metres % 1000]
	return s + " m"
