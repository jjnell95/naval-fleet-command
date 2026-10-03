class_name WorldFittings
extends RefCounted
## Current operating state, only on owned or directly sighted platforms. Never consult a track's
## hidden truth. Stations below are conservative recognition fits, not certified load diagrams.
## Models face +X; station positions are metres from the airframe centre (+Z starboard).
const EXTERNAL_STATIONS := {
	"cw90_f14a": [
		["cw90_aim54a", Vector3(1.8, -2.2, -0.48), 4.0],
		["cw90_aim54a", Vector3(1.8, -2.2, 0.48), 4.0],
		["cw90_aim54a", Vector3(-2.4, -2.2, -0.48), 4.0],
		["cw90_aim54a", Vector3(-2.4, -2.2, 0.48), 4.0],
		["cw90_aim9m", Vector3(1.1, -1.7, -2.6), 2.87],
		["cw90_aim9m", Vector3(1.1, -1.7, 2.6), 2.87],
	],
	"usn_helo_mh60r": [
		["mk54_lwt", Vector3(2.15, -2.0, -2.15), 2.72],
		["mk54_lwt", Vector3(2.15, -2.0, 2.15), 2.72],
	],
	"cw90_sh60b": [
		["cw90_mk46", Vector3(2.15, -2.0, -2.15), 2.59],
		["cw90_mk46", Vector3(2.15, -2.0, 2.15), 2.59],
	],
}
static var _store_scenes: Dictionary = {}


static func dip_fraction(u: Unit) -> float:
	if u == null or not u.alive or not u.airborne(): return 0.0
	match u.dip_phase:
		DippingSonar.Phase.LOWERING: return clampf(1.0 - u.dip_timer_s / DippingSonar.LOWER_S, 0.0, 1.0)
		DippingSonar.Phase.LISTENING: return 1.0
		DippingSonar.Phase.RAISING: return clampf(u.dip_timer_s / DippingSonar.RAISE_S, 0.0, 1.0)
	return 0.0


## Select only rounds actually carried and only explicitly authored external stations. No generic
## fallback: bomb bays and stealth internal carriage must never grow decorative wing missiles.
static func visible_stations(u: Unit) -> Array:
	var out: Array = []
	if u == null or not u.alive or not u.is_aircraft() or not u.in_flight(): return out
	var used: Dictionary = {}
	var stations: Array = EXTERNAL_STATIONS.get(u.spec.id, [])
	for i in stations.size():
		var station: Array = stations[i]
		var id: String = station[0]
		var n := int(used.get(id, 0))
		used[id] = n + 1
		if n < u.magazine_count(id):
			out.append({"index": i, "weapon": id, "position_m": station[1], "length_m": station[2]})
	return out


static func apply(root: Node3D, entry: Dictionary, bounds: AABB, model_scale: float) -> void:
	var rig := root.get_node_or_null("OperationalFittings") as Node3D
	var u: Unit = entry.get("unit")
	var observed: bool = entry.get("kind", "") in ["own", "visual"] and u != null and u.alive
	if not observed or model_scale <= 0.0:
		if rig != null: rig.visible = false
		return
	var fraction := dip_fraction(u)
	var mast_up := u.is_submarine() and u.at_periscope_depth()
	var stations := visible_stations(u)
	if not (fraction > 0.0 or mast_up or not stations.is_empty()):
		if rig != null: rig.visible = false
		return
	if rig == null:
		rig = Node3D.new()
		rig.name = "OperationalFittings"
		root.add_child(rig)
	rig.visible = true
	var cable := _cylinder(rig, "SonarCable", Color("747d82"))
	var body := _cylinder(rig, "SonarBody", Color("343b40"))
	cable.visible = fraction > 0.0
	body.visible = cable.visible
	if cable.visible:
		var depth := 30.0
		for s: SensorSpec in u.sensors:
			if s.requires_hover:
				depth = Acoustics.sensor_depth_m(u, s)
				break
		var length := maxf((u.altitude_m + depth) * fraction, 0.1) / model_scale
		var attach := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
		cable.position = attach - Vector3(0, length * 0.5, 0)
		cable.scale = Vector3(0.025 / model_scale, length, 0.025 / model_scale)
		body.position = attach - Vector3(0, length, 0)
		body.scale = Vector3(0.24, 0.75, 0.24) / model_scale
	var mast := _cylinder(rig, "Periscope", Color("545e62"))
	mast.visible = mast_up
	if mast_up:
		var attach := _mast_attachment(root, bounds)
		var length := maxf(u.depth_m + WorldPresentation.PERISCOPE_MAST_M - attach.y * model_scale, 0.5) / model_scale
		mast.position = attach + Vector3(0, length * 0.5, 0)
		mast.scale = Vector3(0.09 / model_scale, length, 0.09 / model_scale)
	var stores := rig.get_node_or_null("Stores") as Node3D
	if stores == null:
		stores = Node3D.new()
		stores.name = "Stores"
		rig.add_child(stores)
	for node: Node3D in stores.get_children(): node.visible = false
	stores.visible = not stations.is_empty()
	for station: Dictionary in stations:
		var node := _store(stores, str(station["weapon"]), int(station["index"]))
		if node == null: continue
		node.visible = true
		node.position = (station["position_m"] as Vector3) / model_scale
		node.scale = Vector3.ONE * float(station["length_m"]) / WorldPresentation.MODEL_UNITS / model_scale


static func _store(parent: Node3D, weapon_id: String, station: int) -> Node3D:
	var name := "Station%d_%s" % [station, weapon_id]
	var node := parent.get_node_or_null(name) as Node3D
	if node != null: return node
	if not _store_scenes.has(weapon_id):
		var path := "res://assets/models/%s.glb" % weapon_id
		_store_scenes[weapon_id] = load(path) if ResourceLoader.exists(path) else null
	var scene: PackedScene = _store_scenes[weapon_id]
	if scene == null: return null
	node = scene.instantiate() as Node3D
	node.name = name
	node.set_meta("weapon_id", weapon_id)
	# These are separate scene instances; no geometry or material on the aircraft is modified.
	WorldMaterials.dress(node, weapon_id)
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.has_meta("finish"): WorldMaterials.set_way(mi, WorldMaterials.ALOFT)
	# Small support shoes join the visible stores to the authored airframe. The imported weapons
	# span ten units; convert conservative metre dimensions into that local frame, leaving the GLB
	# mesh/material resources untouched. Empty stations disappear together with their support shoe.
	var torpedo := weapon_id in ["mk54_lwt", "cw90_mk46"]
	var phoenix := weapon_id == "cw90_aim54a"
	var length_m := 4.0 if phoenix else (2.72 if weapon_id == "mk54_lwt" else 2.59 if torpedo else 2.87)
	var scale_m := length_m / WorldPresentation.MODEL_UNITS
	var support := MeshInstance3D.new()
	support.name = "Mount"
	var shoe := BoxMesh.new()
	var height := 0.65 if torpedo else 0.2 if phoenix else 0.35
	shoe.size = Vector3(0.8 if phoenix else 0.35, height, 0.12) / scale_m
	support.mesh = shoe
	support.position.y = ((0.16 if torpedo else 0.19 if phoenix else 0.065) + height * 0.5) / scale_m
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("747e88")
	paint.roughness = 0.8
	support.material_override = paint
	node.add_child(support)
	parent.add_child(node)
	return node


## The revised boats have their retracted mast heads on the sail crown. Measure that upper band
## once from the base GLB, before fittings, rather than placing a pole in the middle of the hull.
static func _mast_attachment(root: Node3D, bounds: AABB) -> Vector3:
	if root.has_meta("mast_attachment"): return root.get_meta("mast_attachment")
	var sum := Vector3.ZERO
	var count := 0
	var inverse := root.global_transform.affine_inverse()
	var meshes: Array = root.get_meta("model_meshes", [])
	for mi: MeshInstance3D in meshes:
		var transform := inverse * mi.global_transform
		for surface in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p: Vector3 = transform * v
				if p.y >= bounds.end.y - bounds.size.y * 0.03:
					sum += p
					count += 1
	var attach := sum / float(count) if count > 0 else Vector3(bounds.get_center().x + bounds.size.x * 0.13, bounds.end.y, bounds.get_center().z)
	attach.y = bounds.end.y
	root.set_meta("mast_attachment", attach)
	return attach


static func _cylinder(parent: Node3D, name: String, color: Color) -> MeshInstance3D:
	var node := parent.get_node_or_null(name) as MeshInstance3D
	if node != null: return node
	node = MeshInstance3D.new()
	node.name = name
	var mesh := CylinderMesh.new()
	mesh.height = 1.0
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.radial_segments = 12
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.75
	node.material_override = material
	parent.add_child(node)
	return node
