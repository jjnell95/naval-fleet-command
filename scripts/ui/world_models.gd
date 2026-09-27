class_name WorldModels
extends RefCounted
## The world view's model pool: GLB instances by id, generic contact markers and the sonobuoy
## float, with each model's bounds measured once. A node comes out of the pool shown and goes
## back hidden with its transform reset, so a busy picture does not churn the scene tree.

static var _scene_cache: Dictionary = {}
static var _bounds_cache: Dictionary = {}
var _pool: Dictionary = {}  # model id -> Array[Node3D]


## An instance of a model under `parent`, from the pool when one is free. Returns {node, bounds, meshes}.
func acquire(model_id: String, parent: Node3D) -> Dictionary:
	var free: Array = _pool.get(model_id, [])
	var node: Node3D
	if not free.is_empty():
		node = free.pop_back()
		_pool[model_id] = free
	else:
		node = _instantiate(model_id)
		parent.add_child(node)
	node.visible = true
	var meshes: Array = node.find_children("*", "MeshInstance3D", true, false)
	if not _bounds_cache.has(model_id):
		var bounds := AABB()
		var first := true
		var inverse := node.global_transform.affine_inverse()
		for mi: MeshInstance3D in meshes:
			var b := (inverse * mi.global_transform) * mi.get_aabb()
			bounds = b if first else bounds.merge(b)
			first = false
		if first:
			bounds = AABB(Vector3(-5, -1, -1), Vector3(10, 2, 2))
		_bounds_cache[model_id] = bounds
	return {"node": node, "bounds": _bounds_cache[model_id], "meshes": meshes}


func _instantiate(model_id: String) -> Node3D:
	if model_id.begins_with("marker:"):
		return _marker(model_id.get_slice(":", 1))
	if not _scene_cache.has(model_id):
		var path := "res://assets/models/%s.glb" % model_id
		_scene_cache[model_id] = load(path) if ResourceLoader.exists(path) else null
	var scene: PackedScene = _scene_cache[model_id]
	if scene == null:
		return _marker("surface")
	var node := scene.instantiate() as Node3D
	if node == null:
		return _marker("surface")
	return node


## Generic contact shapes and the sonobuoy float, all normalised to 10 units along +X like the
## GLBs, so one scale rule serves everything.
static func _marker(kind: String) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match kind:
		"air":
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 1.1
			cone.height = 10.0
			cone.radial_segments = 16
			mi.mesh = cone
			mi.rotation.z = deg_to_rad(-90.0)
		"weapon":
			var dart := CylinderMesh.new()
			dart.top_radius = 0.0
			dart.bottom_radius = 0.5
			dart.height = 10.0
			dart.radial_segments = 10
			mi.mesh = dart
			mi.rotation.z = deg_to_rad(-90.0)
		"buoy":
			var can := CylinderMesh.new()
			can.top_radius = 1.6
			can.bottom_radius = 1.6
			can.height = 5.0
			can.radial_segments = 12
			mi.mesh = can
			mi.position.y = -1.5
			var paint := StandardMaterial3D.new()
			paint.albedo_color = Color(0.95, 0.5, 0.12)
			paint.emission_enabled = true
			paint.emission = Color(0.95, 0.5, 0.12)
			paint.emission_energy_multiplier = 0.4
			mi.material_override = paint
			var mast := MeshInstance3D.new()
			var pole := CylinderMesh.new()
			pole.top_radius = 0.12
			pole.bottom_radius = 0.12
			pole.height = 5.0
			pole.radial_segments = 6
			mast.mesh = pole
			mast.position.y = 2.5
			mast.material_override = paint
			mast.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mast)
		_:
			var hull := CapsuleMesh.new()
			hull.radius = 0.7 if kind == "subsurface" else 0.55
			hull.height = 10.0
			hull.radial_segments = 14
			mi.mesh = hull
			mi.rotation.z = deg_to_rad(90.0)
	root.add_child(mi)
	return root


## Returns a node to the pool.
func release(model_id: String, node: Node3D) -> void:
	node.visible = false
	node.transform = Transform3D.IDENTITY
	var free: Array = _pool.get(model_id, [])
	free.append(node)
	_pool[model_id] = free
