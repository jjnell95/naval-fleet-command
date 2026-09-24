class_name Bathymetry
## The sea floor under the chart.
##
## One regional raster, built offline from Natural Earth 1:10m bathymetry by
## `tools/scenarios/import_bathymetry.py`, covers every mission area. A scenario reaches it through
## its map anchor: the game's local projection is equirectangular about that point, so world
## nautical miles map onto latitude and longitude by a plain scale and offset, and one raster can
## serve any chart without being cut or reprojected per mission.
##
## Static, like Terrain, so the movement, sensor and rendering code can all ask without a reference
## being plumbed through. A scenario with no anchor, or an anchor outside the raster, leaves the
## floor unknown: `depth_at` returns UNKNOWN and every consumer treats unknown as "no effect", which
## is what keeps hand-built test worlds and the older open-ocean scenarios exactly as they were.
## `environment.bottom_m` sets a uniform floor instead, for a synthetic chart or a test.
##
## The raster honours Natural Earth's 0/200/1000/2000/3000/4000/5000 m contours and interpolates
## between them. It is a 1:10 million chart: good for shelf against basin and ridge against trough,
## silent about shoals, channels and under-keel clearance. It is never a navigation chart.

const SOURCE := "res://data/bathymetry/north_atlantic_depth.png"
## Must match data/bathymetry/north_atlantic_depth.json; a test holds them together.
const LON_MIN := -46.0
const LAT_MAX := 81.0
const CELL_LON_DEG := 1.0 / 30.0
const CELL_LAT_DEG := 1.0 / 60.0
const DEPTH_SCALE_M := 6000.0
const CONTOURS_M: Array[float] = [200.0, 1000.0, 2000.0, 3000.0, 4000.0, 5000.0]
const UNKNOWN := -1.0

static var _data := PackedByteArray()
static var _w := 0
static var _h := 0
static var _loaded_source := false
static var _decode := PackedFloat32Array()  # byte value -> metres

## Per-scenario state.
static var active := false
static var uniform_m := UNKNOWN
static var anchor_lat := 0.0
static var anchor_lon := 0.0
static var _nm_per_deg_lon := 60.0
## Bumped whenever the floor changes, so the renderer can rebuild its texture and transform.
static var generation := 0


static func clear() -> void:
	active = false
	uniform_m = UNKNOWN
	generation += 1


## Reads the scenario's map anchor and environment. Absent or out of range means an unknown floor.
static func load_for(scenario: Dictionary) -> void:
	clear()
	var env = scenario.get("environment", {})
	if typeof(env) == TYPE_DICTIONARY and env.has("bottom_m"):
		uniform_m = maxf(float(env["bottom_m"]), 0.0)
		return
	var m = scenario.get("map", {})
	if typeof(m) != TYPE_DICTIONARY or not m.has("anchor_lat") or not m.has("anchor_lon"):
		return
	set_anchor(float(m["anchor_lat"]), float(m["anchor_lon"]))


static func set_anchor(lat: float, lon: float) -> void:
	clear()
	if not _ensure_source():
		return
	if lon < LON_MIN or lon > LON_MIN + _w * CELL_LON_DEG or lat > LAT_MAX or lat < LAT_MAX - _h * CELL_LAT_DEG:
		return
	anchor_lat = lat
	anchor_lon = lon
	_nm_per_deg_lon = 60.0 * maxf(cos(deg_to_rad(lat)), 0.001)
	active = true


static func is_empty() -> bool:
	return not active and uniform_m < 0.0


static func _ensure_source() -> bool:
	if _loaded_source:
		return _w > 0
	_loaded_source = true
	if not ResourceLoader.exists(SOURCE):
		push_warning("Bathymetry: %s is missing; the sea floor is unknown" % SOURCE)
		return false
	var img := load(SOURCE) as Image
	if img == null or img.is_empty():
		return false
	if img.get_format() != Image.FORMAT_L8:
		img = img.duplicate() as Image
		img.convert(Image.FORMAT_L8)
	_data = img.get_data()
	_w = img.get_width()
	_h = img.get_height()
	_decode.resize(256)
	for v in 256:
		_decode[v] = DEPTH_SCALE_M * pow(v / 255.0, 2.0)
	return true


## The raster as an Image, for the chart renderer. Null when there is none.
static func source_image() -> Image:
	if not _ensure_source():
		return null
	var img := Image.create_from_data(_w, _h, false, Image.FORMAT_L8, _data)
	return img


## World rectangle, in nautical miles, that the whole raster covers under the current anchor.
static func world_rect() -> Rect2:
	if not active:
		return Rect2()
	var x0 := (LON_MIN - anchor_lon) * _nm_per_deg_lon
	var x1 := (LON_MIN + _w * CELL_LON_DEG - anchor_lon) * _nm_per_deg_lon
	var y1 := (LAT_MAX - anchor_lat) * 60.0
	var y0 := (LAT_MAX - _h * CELL_LAT_DEG - anchor_lat) * 60.0
	return Rect2(x0, y0, x1 - x0, y1 - y0)


## Water depth in metres at a world position, 0 ashore, UNKNOWN where there is no chart.
## Bilinear across the four nearest cells, so the floor is continuous under a moving hull.
static func depth_at(p: Vector2) -> float:
	if not active:
		return uniform_m
	var lon := anchor_lon + p.x / _nm_per_deg_lon
	var lat := anchor_lat + p.y / 60.0
	var fx := (lon - LON_MIN) / CELL_LON_DEG - 0.5
	var fy := (LAT_MAX - lat) / CELL_LAT_DEG - 0.5
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
