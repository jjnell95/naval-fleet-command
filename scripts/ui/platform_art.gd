class_name PlatformArt
## Recognition art rendered from the original Blender models built by
## tools/blender/build_platform_art.py. Every image is greyscale on alpha: faces carry a
## mid-grey shade and the outline is white, so a draw call tints the whole thing with the
## identity or damage colour and it still reads as a command display, not a photograph.
##
## Two views exist per platform under assets/platforms:
##   <id>_profile.png  an elevated side view, bow to the right, waterline at WATERLINE (ships)
##                     or a three-quarter view from ahead and above (aircraft, the air station)
##   <id>_plan.png     straight down, bow to the right, the hull spanning 1 / PLAN_MARGIN of
##                     the width so the map can scale it to the real length
## Anything without a file falls back to the code-drawn shapes, so a new data file never breaks
## the display; it just looks plainer until the art is built.

const WATERLINE := 0.80  # fraction of the profile height at which a ship's waterline lies
const PLAN_MARGIN := 1.10  # the plan render frames the hull with this much slack

static var _cache: Dictionary = {}


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
