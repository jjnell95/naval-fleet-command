class_name PlatformArt
## Original procedural fleet art: colour beauty/plan renders, lightweight thumbnails, and
## monochrome fallback profiles. The 3D gallery uses the matching models under assets/models.
## See assets/README.md and tools/blender/build_presentation_assets.py for the pipeline.

const WATERLINE := 0.80  # fraction of the profile height at which a ship's waterline lies
const PLAN_MARGIN := 1.10  # the plan render frames the hull with this much slack
## The plan views serve only the chart's graphic symbols, drawn at most 56 px long, so they are
## imported no larger than this (process/size_limit in every *_plan.png.import). A symbol is then
## made from a small texture, and the web build downloads and uploads a fraction of the render.
const PLAN_IMPORT_LIMIT := 384

static var _cache: Dictionary = {}
## Plan views loaded so far, so a test can tell a lookup that loads art from one that does not.
static var plans_loaded := 0

static func beauty(asset_id: String, weapon := false) -> Texture2D:
	var key := ("weapon:" if weapon else "beauty:") + asset_id
	if not _cache.has(key):
		var path := "res://assets/%s/%s_beauty.png" % ["weapons" if weapon else "platforms", asset_id]
		_cache[key] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _cache[key]

static func thumbnail(asset_id: String, weapon := false) -> Texture2D:
	var key := ("weapon-thumb:" if weapon else "thumb:") + asset_id
	if not _cache.has(key):
		var path := "res://assets/%s/%s_thumb.png" % ["weapons" if weapon else "platforms", asset_id]
		_cache[key] = load(path) as Texture2D if ResourceLoader.exists(path) else beauty(asset_id, weapon)
	return _cache[key]


static func profile(platform_id: String) -> Texture2D:
	return _load(platform_id, "profile")


## The plan view, loaded when asked and not kept here: the chart makes its small symbol from it
## once (MapSymbols.graphic_texture) and lets it go, so no plan view stays resident.
static func plan(platform_id: String) -> Texture2D:
	var path := plan_path(platform_id)
	if not ResourceLoader.exists(path):
		return null
	plans_loaded += 1
	return load(path) as Texture2D


## Whether the platform has a plan view, without loading it.
static func has_plan(platform_id: String) -> bool:
	return ResourceLoader.exists(plan_path(platform_id))


static func plan_path(platform_id: String) -> String:
	return "res://assets/platforms/%s_plan.png" % platform_id


static func _load(platform_id: String, kind: String) -> Texture2D:
	var key := platform_id + ":" + kind
	if _cache.has(key):
		return _cache[key]
	var path := "res://assets/platforms/%s_%s.png" % [platform_id, kind]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_cache[key] = tex
	return tex
