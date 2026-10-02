class_name WorldMaterials
extends RefCounted
## The world view's finishes. The models carry flat PBR colours named for what each surface is
## (naval_paint, deck_non_skid, antifouling, rubber, airframe ...), which under the world view's sky
## looked like one pale plastic. At instancing, WorldModels hands every surface to `dress`, which
## swaps its material for a shared ShaderMaterial on world_hull.gdshader that knows how that finish
## ages and takes the light. Paint is the navy's own: a U.S. haze grey, the lighter greys of the Royal
## Navy and the European fleets, the blue-grey of Russian hulls, the PLA Navy's pale grey. Weathering
## follows the same lines. Surfaces the table does not name keep their own material.
##
## A hull in the water also wears its way: the waterline, wetness and bow spray are drawn at one of
## a few speeds (WAY_BANDS), each a shared variant of the finish, set with `set_way`. They are not
## instance uniforms because WebGL gives instance uniforms room for about 255 instances in all.
##
## The GLBs themselves are untouched: the reference gallery and the renders use them as authored.

const HULL_SHADER := "res://scripts/ui/world_hull.gdshader"

enum Finish { PAINT, DECK, BOTTOM, GLASS, AIRFRAME, ANECHOIC, METAL, MARKING, FITTING, ORDNANCE, GROUND }

## Material name -> [finish, colour (sRGB), roughness, metallic]. A colour of null means the navy's paint.
const TABLE := {
	"naval_paint": [Finish.PAINT, null, 0.62, 0.0],
	"hull_red": [Finish.PAINT, Color("6e2a1f"), 0.6, 0.0],
	"deck_non_skid": [Finish.DECK, Color("3c4247"), 0.93, 0.0],
	"flight_deck": [Finish.DECK, Color("363a3e"), 0.9, 0.0],
	"antifouling": [Finish.BOTTOM, Color("6a2a20"), 0.8, 0.0],
	"boot_topping": [Finish.BOTTOM, Color("222629"), 0.7, 0.0],
	"array_face": [Finish.FITTING, Color("8d9591"), 0.72, 0.0],
	"radome": [Finish.FITTING, Color("cdd0c8"), 0.55, 0.0],
	"glazing": [Finish.GLASS, Color("0b1a22"), 0.08, 0.0],
	"canopy_gold": [Finish.GLASS, Color("383a26"), 0.1, 0.2],
	"titanium": [Finish.METAL, Color("7b848c"), 0.38, 0.8],
	"bronze": [Finish.METAL, Color("a1733c"), 0.35, 0.75],
	"rubber": [Finish.ANECHOIC, Color("1b1c20"), 0.6, 0.0],
	"submarine_coating": [Finish.ANECHOIC, Color("293139"), 0.73, 0.0],
	"marking_white": [Finish.MARKING, Color("d2d6d0"), 0.7, 0.0],
	"marking_yellow": [Finish.MARKING, Color("c99c2a"), 0.7, 0.0],
	"hazard_red": [Finish.MARKING, Color("a32e1f"), 0.62, 0.0],
	"airframe": [Finish.AIRFRAME, Color("89939c"), 0.55, 0.0],  # the tactical ghost greys, lighter underneath
	"airframe_light": [Finish.AIRFRAME, Color("a2abb1"), 0.58, 0.0],
	"airframe_blue": [Finish.AIRFRAME, Color("47607a"), 0.6, 0.0],
	"missile_body": [Finish.ORDNANCE, Color("c3c8c4"), 0.5, 0.0],
	"seeker": [Finish.ORDNANCE, Color("3b4240"), 0.3, 0.3],
	"earth": [Finish.GROUND, Color("766c52"), 0.95, 0.0],
	"earth_dark": [Finish.GROUND, Color("4d4535"), 0.95, 0.0],
	"concrete": [Finish.GROUND, Color("a6a59b"), 0.85, 0.0],
	"drab": [Finish.GROUND, Color("4a5236"), 0.78, 0.0],
}

## Paint and weathering by navy, from the platform's `nation`. The greys are the services' own
## public colours, matched by eye, not specification values.
const NAVIES := {
	"USA": [Color("7c858b"), 0.45],
	"UK": [Color("939b9e"), 0.4],
	"France": [Color("8e969a"), 0.35],
	"Italy": [Color("8e969a"), 0.35],
	"Germany": [Color("8b9396"), 0.3],
	"Norway": [Color("8e979b"), 0.35],
	"Denmark": [Color("8e979b"), 0.35],
	"Sweden": [Color("7b857f"), 0.3],
	"Spain": [Color("8e969a"), 0.35],
	"Russia": [Color("6b7985"), 0.75],
	"USSR": [Color("6b7985"), 0.8],
	"China": [Color("8b97a1"), 0.3],
	"Japan": [Color("7b8389"), 0.25],
	"Iran": [Color("868b87"), 0.65],
	"Civil": [Color("c4c3bc"), 0.6],
	"Civilian": [Color("c4c3bc"), 0.6],
}
const DEFAULT_NAVY := [Color("80888d"), 0.45]

## Speeds through the water, in metres per second, that the finishes are drawn at: stopped, and
## about 5, 10, 16 and 23 knots. A way of -1 is aloft or ashore: no waterline at all.
const WAY_BANDS := [0.0, 2.5, 5.0, 8.0, 12.0]
const ALOFT := -1

static var _shader: Shader
static var _cache: Dictionary = {}  # "navy/material/way" -> ShaderMaterial


## Swaps every named surface under `root` for the world view's finish, and remembers the result on
## each MeshInstance3D (meta "finish") so a tint can be lifted again.
static func dress(root: Node, model_id: String) -> void:
	var navy := _navy_for(model_id)
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var dressed: Array = []
		for i in mi.mesh.get_surface_count():
			var original := mi.get_active_material(i)
			var finish := material_for(original.resource_name if original != null else "", navy)
			dressed.append(finish)
			mi.set_surface_override_material(i, finish)
		mi.set_meta("finish", dressed)


## Puts back the finish `dress` gave a mesh, after a tint.
static func restore(mi: MeshInstance3D) -> void:
	var dressed: Array = mi.get_meta("finish", [])
	for i in dressed.size():
		mi.set_surface_override_material(i, dressed[i])


## Moves a dressed mesh's finishes to a way (an index into WAY_BANDS, or ALOFT). They are put on
## the mesh only when `apply` is set: a mesh wearing a tint keeps it and gets them back on `restore`.
static func set_way(mi: MeshInstance3D, way: int, apply := true) -> void:
	var dressed: Array = mi.get_meta("finish", [])
	for i in dressed.size():
		var m: ShaderMaterial = dressed[i]
		if m != null:
			dressed[i] = material_for(m.resource_name, m.get_meta("navy", ""), way)
	mi.set_meta("finish", dressed)
	if apply:
		restore(mi)


## The band of WAY_BANDS nearest a speed through the water in metres per second.
static func way_for(speed_m_s: float) -> int:
	var best := 0
	for i in WAY_BANDS.size():
		if absf(speed_m_s - WAY_BANDS[i]) < absf(speed_m_s - WAY_BANDS[best]):
			best = i
	return best


## The shared material for a named surface in a navy's paint at a way, or null to keep the model's
## own.
static func material_for(material_name: String, navy: String, way := ALOFT) -> ShaderMaterial:
	var row: Array = TABLE.get(material_name, [])
	if row.is_empty():
		return null
	var key := "%s/%s/%d" % [navy, material_name, way]
	if _cache.has(key):
		return _cache[key]
	if _shader == null:
		_shader = load(HULL_SHADER)
	var paint: Array = NAVIES.get(navy, DEFAULT_NAVY)
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.resource_name = material_name
	m.set_meta("navy", navy)
	m.set_shader_parameter("finish", int(row[0]))
	m.set_shader_parameter("albedo", paint[0] if row[1] == null else row[1])
	m.set_shader_parameter("roughness", float(row[2]))
	m.set_shader_parameter("metallic", float(row[3]))
	m.set_shader_parameter("weathering", float(paint[1]))
	m.set_shader_parameter("at_sea", 0.0 if way == ALOFT else 1.0)
	m.set_shader_parameter("hull_speed", 0.0 if way == ALOFT else float(WAY_BANDS[way]))
	_cache[key] = m
	return m


static func _navy_for(model_id: String) -> String:
	var spec := DataDB.platform(model_id)
	return spec.nation if spec != null else ""
