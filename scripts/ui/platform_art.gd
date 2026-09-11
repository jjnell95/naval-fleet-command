class_name PlatformArt
## Original procedural fleet art: colour beauty/plan renders, lightweight thumbnails, and
## monochrome fallback profiles. The 3D gallery uses the matching models under assets/models.
## See assets/README.md and tools/blender/build_presentation_assets.py for the pipeline.

const WATERLINE := 0.80  # fraction of the profile height at which a ship's waterline lies
const PLAN_MARGIN := 1.10  # the plan render frames the hull with this much slack

static var _cache: Dictionary = {}

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


static func plan(platform_id: String) -> Texture2D:
	return _load(platform_id, "plan")


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
