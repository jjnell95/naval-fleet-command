extends SceneTree
## Blender-free presentation renders for the fleet models.
##
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --script tools/art/render_assets.gd -- --all-new
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --script tools/art/render_assets.gd -- pla_ddg_type055 pla_yj18
##
## Every id is instantiated from assets/models/<id>.glb into a transparent SubViewport that carries
## the ModelStage environment and lights, so the pictures match what the inspection stage shows.
## The raw passes are rendered at twice the final size and handed to tools/art/compose_renders.py,
## which keys out the sea plane, draws the recognition outline on the profile and writes:
##   assets/platforms/<id>_beauty.png (1200x640), _thumb.png (240x128), _profile.png (768x224),
##   _plan.png (768 wide for a hull, span-proportioned for an aircraft), and for a weapon only
##   assets/weapons/<id>_beauty.png and _thumb.png.
## Options: --raw-dir=<dir> (default user://art_raw), --out=<dir> (default res://assets),
## --keep-raw, --no-compose.

const SUPERSAMPLE := 2
const BEAUTY_SIZE := Vector2i(1200, 640)
const PROFILE_SIZE := Vector2i(768, 224)
const PLAN_WIDTH := 768
const FIT_MARGIN := 1.16  # the beauty framing used by the earlier Blender pipeline
const PLAN_MARGIN := 1.10  # PlatformArt.PLAN_MARGIN
const WATERLINE := 0.80  # PlatformArt.WATERLINE
const KEY_COLOR := Color(0.0, 1.0, 0.0, 1.0)  # unshaded sea plane, keyed out afterwards
const CAMERA_DISTANCE := 60.0
const STAGE_LIGHT_SCALE := 0.12  # ModelStage's own lights, kept as a soft top light
const LAND_TOP_LIGHT := 4.0  # multiplier on those lights for a flat installation
const ART_LIGHTS := [
	[Vector3(-0.3, 1.5, 0.7), Color(1.0, 0.88, 0.73), 0.52],
	[Vector3(0.3, 1.0, -0.8), Color(0.58, 0.78, 1.0), 0.40],
	[Vector3(1.0, 0.5, -0.2), Color(0.84, 0.95, 1.0), 0.15],
]
const ART_AMBIENT := Color(0.24, 0.34, 0.46)
const ART_AMBIENT_ENERGY := 0.34
const SIDECAR := "res://tools/art/render_manifest.json"
const NEW_RECORDS := "res://data/theatres_2027_manifest.json"

var _viewport: SubViewport
var _world: Node3D
var _env_node: WorldEnvironment
var _stage_env: Environment
var _profile_env: Environment
var _stage_lights: Array[DirectionalLight3D] = []
var _top_lights: Array[DirectionalLight3D] = []  # ModelStage's own, lifted for flat land sites
var _profile_light: DirectionalLight3D
var _camera: Camera3D
var _pivot: Node3D
var _model: Node3D
var _sea: MeshInstance3D
var _meshes: Array[MeshInstance3D] = []
var _points := PackedVector3Array()
var _bounds := AABB()
var _sidecar: Dictionary = {}
var _ids: Array[String] = []
var _raw_dir := "user://art_raw"
var _out_dir := ""
var _keep_raw := false
var _compose := true
var _grey_material: StandardMaterial3D
var _normal_material: ShaderMaterial
var _depth_material: ShaderMaterial
var _jobs: Array = []


func _initialize() -> void:
	if not _parse_args():
		quit(1)
		return
	_build_stage()
	call_deferred("_run")


func _parse_args() -> bool:
	var all_new := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--all-new":
			all_new = true
		elif arg.begins_with("--raw-dir="):
			_raw_dir = arg.trim_prefix("--raw-dir=")
		elif arg.begins_with("--out="):
			_out_dir = ProjectSettings.globalize_path(arg.trim_prefix("--out="))
		elif arg == "--keep-raw":
			_keep_raw = true
		elif arg == "--no-compose":
			_compose = false
			_keep_raw = true
		elif arg.begins_with("--"):
			push_error("unknown option " + arg)
			return false
		else:
			_ids.append(arg)
	if FileAccess.file_exists(SIDECAR):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(SIDECAR))
		if parsed is Dictionary:
			_sidecar = parsed
	if all_new:
		var manifest = JSON.parse_string(FileAccess.get_file_as_string(NEW_RECORDS))
		if not manifest is Dictionary:
			push_error("cannot read " + NEW_RECORDS)
			return false
		for key in ["platforms", "weapons"]:
			for id in manifest.get(key, []):
				var entry: Dictionary = _sidecar.get(id, {})
				if entry.has("copy_of"):
					continue  # build_models.py copied the donor's renders along with its GLB
				if not _ids.has(id):
					_ids.append(id)
	if _ids.is_empty():
		push_error("nothing to render: pass ids or --all-new")
		return false
	return true


## The same environment and lights as ModelStage, so a render matches the inspection stage.
func _build_stage() -> void:
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.use_debanding = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.size = BEAUTY_SIZE * SUPERSAMPLE
	root.add_child(_viewport)
	_world = Node3D.new()
	_viewport.add_child(_world)
	_env_node = WorldEnvironment.new()
	_stage_env = Environment.new()
	_stage_env.background_mode = Environment.BG_COLOR
	_stage_env.background_color = Color("0b1723")
	_stage_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_stage_env.ambient_light_color = ART_AMBIENT
	_stage_env.ambient_light_energy = ART_AMBIENT_ENERGY
	_stage_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("142535")
	sky_material.sky_horizon_color = Color("7296ae")
	sky_material.ground_bottom_color = Color("08111a")
	sky_material.ground_horizon_color = Color("39556b")
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	_stage_env.sky = sky
	_stage_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env_node.environment = _stage_env
	_world.add_child(_env_node)
	for light_data in [[Vector3(-40, -35, 0), Color("ffecd4"), 0.38], [Vector3(-20, 145, 0), Color("83bbef"), 0.14], [Vector3(20, 25, 0), Color("d3e8fc"), 0.06]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = light_data[0]
		light.light_color = light_data[1]
		light.light_energy = light_data[2] * STAGE_LIGHT_SCALE
		light.set_meta("base_energy", light.light_energy)
		light.shadow_enabled = light_data[2] > 0.3
		light.directional_shadow_max_distance = 50
		_world.add_child(light)
		_stage_lights.append(light)
		_top_lights.append(light)
	# The committed Blender renders were lit by three suns that travel upwards and sideways (a
	# warm key under the hull, a cool fill on the starboard side, a faint rim from ahead) under a
	# blue-grey world. These directional lights reproduce that rig in Y-up terms so a new model
	# sits beside an old one without a visible change of studio.
	for light_data in ART_LIGHTS:
		var light := DirectionalLight3D.new()
		light.look_at_from_position(Vector3.ZERO, light_data[0], Vector3.UP)
		light.light_color = light_data[1]
		light.light_energy = light_data[2]
		light.shadow_enabled = false
		_world.add_child(light)
		_stage_lights.append(light)
	# The recognition profile is a flat grey drawing: neutral ambient, one soft key, no sky.
	_profile_env = Environment.new()
	_profile_env.background_mode = Environment.BG_COLOR
	_profile_env.background_color = Color(0, 0, 0, 0)
	_profile_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_profile_env.ambient_light_color = Color(1, 1, 1)
	_profile_env.ambient_light_energy = 0.14
	_profile_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_profile_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_profile_light = DirectionalLight3D.new()
	_profile_light.light_color = Color(1, 1, 1)
	_profile_light.light_energy = 0.12
	_profile_light.shadow_enabled = false
	_profile_light.visible = false
	_world.add_child(_profile_light)
	_pivot = Node3D.new()
	_world.add_child(_pivot)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.near = 0.05
	_camera.far = CAMERA_DISTANCE * 3.0
	_world.add_child(_camera)
	_camera.make_current()
	var sea_mesh := BoxMesh.new()
	sea_mesh.size = Vector3(80, 0.02, 80)
	_sea = MeshInstance3D.new()
	_sea.mesh = sea_mesh
	var sea_material := StandardMaterial3D.new()
	sea_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sea_material.albedo_color = KEY_COLOR
	_sea.material_override = sea_material
	_sea.visible = false
	_world.add_child(_sea)
	_grey_material = StandardMaterial3D.new()
	_grey_material.albedo_color = Color(0.5, 0.5, 0.5)
	_grey_material.roughness = 0.85
	_grey_material.metallic = 0.0
	_normal_material = ShaderMaterial.new()
	var normal_shader := Shader.new()
	normal_shader.code = "shader_type spatial;\nrender_mode unshaded, cull_back;\nvoid fragment() {\n\tALBEDO = normalize(NORMAL) * 0.5 + 0.5;\n}\n"
	_normal_material.shader = normal_shader
	_depth_material = ShaderMaterial.new()
	var depth_shader := Shader.new()
	depth_shader.code = "shader_type spatial;\nrender_mode unshaded, cull_back;\nuniform float depth_min = 0.0;\nuniform float depth_range = 1.0;\nvoid fragment() {\n\tfloat d = clamp((-VERTEX.z - depth_min) / depth_range, 0.0, 1.0);\n\tALBEDO = vec3(0.2 + 0.8 * d);\n}\n"
	_depth_material.shader = depth_shader


func _run() -> void:
	var raw_global := ProjectSettings.globalize_path(_raw_dir)
	DirAccess.make_dir_recursive_absolute(raw_global)
	var failures := 0
	for id in _ids:
		var ok := await _render_asset(id, raw_global)
		if not ok:
			failures += 1
	if _compose and not _jobs.is_empty():
		var job_file := raw_global.path_join("jobs.json")
		var f := FileAccess.open(job_file, FileAccess.WRITE)
		f.store_string(JSON.stringify(_jobs, "  "))
		f.close()
		var script := ProjectSettings.globalize_path("res://tools/art/compose_renders.py")
		var output := []
		var args := [script, job_file]
		if not _keep_raw:
			args.append("--clean")
		var code := OS.execute("python3", args, output, true)
		for line in output:
			print(line.strip_edges())
		if code != 0:
			push_error("compose_renders.py failed with exit code %d" % code)
			failures += 1
	print("RENDER COMPLETE %d assets, %d failures" % [_ids.size() - failures, failures])
	quit(1 if failures > 0 else 0)


func _asset_info(id: String) -> Dictionary:
	var info: Dictionary = _sidecar.get(id, {}).duplicate()
	if not info.has("kind"):
		info["kind"] = "weapon" if ResourceLoader.exists("res://data/weapons/%s.tres" % id) else "platform"
	if info["kind"] == "platform" and not info.has("domain"):
		var spec_path := _find_platform_spec(id, "res://data/platforms")
		if not spec_path.is_empty():
			var spec = load(spec_path)
			if spec != null and "domain" in spec:
				info["domain"] = spec.domain
	if not info.has("domain"):
		info["domain"] = "surface"
	return info


func _find_platform_spec(id: String, dir_path: String) -> String:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var path := dir_path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				var found := _find_platform_spec(id, path)
				if not found.is_empty():
					return found
		elif name == id + ".tres":
			return path
		name = dir.get_next()
	return ""


func _load_model(id: String) -> bool:
	if _model != null:
		_pivot.remove_child(_model)
		_model.queue_free()
		_model = null
	_meshes.clear()
	_points = PackedVector3Array()
	var path := "res://assets/models/%s.glb" % id
	if not ResourceLoader.exists(path):
		push_error("no model at " + path)
		return false
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("cannot load " + path)
		return false
	_model = scene.instantiate() as Node3D
	_pivot.add_child(_model)
	var first := true
	for node: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(node)
		var xform := node.global_transform
		var box := xform * node.get_aabb()
		_bounds = box if first else _bounds.merge(box)
		first = false
		for s in node.mesh.get_surface_count():
			var arrays := node.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				_points.append(xform * v)
	if _points.is_empty():
		push_error(id + " has no geometry")
		return false
	return true


func _set_override(material: Material) -> void:
	for mesh in _meshes:
		mesh.material_override = material


func _use_stage(stage: bool) -> void:
	_env_node.environment = _stage_env if stage else _profile_env
	for light in _stage_lights:
		light.visible = stage
	_profile_light.visible = not stage


## Aim the orthographic camera along `direction` (from the target towards the camera), then
## slide it so the projected points are centred and scale it so they fit with `margin`.
func _fit_camera(direction: Vector3, up: Vector3, aspect: float, margin: float) -> Dictionary:
	var center := _bounds.get_center()
	var d := direction.normalized()
	_camera.position = center + d * CAMERA_DISTANCE
	_camera.look_at(center, up)
	var right := _camera.global_basis.x
	var cam_up := _camera.global_basis.y
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in _points:
		var rel := p - _camera.position
		var q := Vector2(rel.dot(right), rel.dot(cam_up))
		lo = lo.min(q)
		hi = hi.max(q)
	var mid := (lo + hi) * 0.5
	_camera.position += right * mid.x + cam_up * mid.y
	var view_w := maxf(hi.x - lo.x, (hi.y - lo.y) * aspect) * margin
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.size = view_w
	return {"width": view_w, "height": view_w / aspect, "extent": hi - lo}


## Side elevation from starboard, slightly above: the hull's waterline sits at WATERLINE of the
## image height and the picture widens until the tallest mast fits, as the Blender build did.
func _fit_profile(waterline_y: float, aspect: float) -> void:
	var direction := Vector3(0.0, 0.22, 1.0).normalized()
	var center := _bounds.get_center()
	var target := Vector3(center.x, waterline_y, center.z)
	_camera.position = target + direction * CAMERA_DISTANCE
	_camera.look_at(target, Vector3.UP)
	var right := _camera.global_basis.x
	var cam_up := _camera.global_basis.y
	var length := _bounds.size.x
	var extent := length * PLAN_MARGIN
	var top := -INF
	for p in _points:
		top = maxf(top, (p - target).dot(cam_up))
	var view_h := extent / aspect
	while top * 1.06 > view_h * WATERLINE:
		extent *= 1.08
		view_h = extent / aspect
	# Centre the frame on the hull's midpoint along the length; the waterline sits 30% of the
	# view below the image centre.
	var x_lo := INF
	var x_hi := -INF
	for p in _points:
		var s := (p - target).dot(right)
		x_lo = minf(x_lo, s)
		x_hi = maxf(x_hi, s)
	_camera.position = target + direction * CAMERA_DISTANCE + right * (x_lo + x_hi) * 0.5 + cam_up * (view_h * (WATERLINE - 0.5))
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.size = extent


func _depth_window() -> Vector2:
	var fwd := -_camera.global_basis.z
	var lo := INF
	var hi := -INF
	for p in _points:
		var depth := (p - _camera.position).dot(fwd)
		lo = minf(lo, depth)
		hi = maxf(hi, depth)
	return Vector2(lo, maxf(hi - lo, 0.001))


func _snapshot(size: Vector2i, path: String) -> void:
	_viewport.size = size
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	image.save_png(path)


func _render_asset(id: String, raw_global: String) -> bool:
	if not _load_model(id):
		return false
	var info := _asset_info(id)
	var weapon: bool = info["kind"] == "weapon"
	var domain: String = info.get("domain", "surface")
	var hull := domain == "surface" or domain == "subsurface"
	var job := {"id": id, "kind": info["kind"], "domain": domain, "raw": raw_global, "out": _out_dir}
	# A site is one flat horizontal surface; the low studio suns barely touch it, so the top
	# lights come up for land while ships keep the tone of the earlier renders.
	for light in _top_lights:
		light.light_energy = light.get_meta("base_energy", light.light_energy) * (LAND_TOP_LIGHT if domain == "land" else 1.0)
	_use_stage(true)
	_set_override(null)
	_sea.visible = false
	# Beauty: an elevated three-quarter from the bow-starboard side; aircraft are seen a little
	# more from above, ordnance more from the side (the Blender camera directions, in Y-up terms).
	var direction := Vector3(0.63, 0.66, 1.0)
	if weapon:
		direction = Vector3(0.18, 0.52, 1.0)
	elif domain == "air":
		direction = Vector3(0.62, 0.88, 1.0)
	_fit_camera(direction, Vector3.UP, float(BEAUTY_SIZE.x) / BEAUTY_SIZE.y, FIT_MARGIN)
	await _snapshot(BEAUTY_SIZE * SUPERSAMPLE, raw_global.path_join(id + "_beauty.png"))
	if not weapon:
		# Plan: straight down with the bow to the right and port at the top of the picture. The
		# texture is cut to the model's proportions so the chart can scale it from its width.
		var length := _bounds.size.x
		var span := _bounds.size.z
		var plan_size: Vector2i
		if length >= span:
			plan_size = Vector2i(PLAN_WIDTH, maxi(8, roundi(PLAN_WIDTH * span / length)))
		else:
			plan_size = Vector2i(maxi(8, roundi(PLAN_WIDTH * length / span)), PLAN_WIDTH)
		var center := _bounds.get_center()
		_camera.position = center + Vector3(0.0, CAMERA_DISTANCE, 0.0)
		_camera.look_at(center, Vector3(0.0, 0.0, -1.0))
		if length >= span:
			_camera.keep_aspect = Camera3D.KEEP_WIDTH
			_camera.size = length * PLAN_MARGIN
		else:
			_camera.keep_aspect = Camera3D.KEEP_HEIGHT
			_camera.size = span * PLAN_MARGIN
		job["plan_size"] = [plan_size.x, plan_size.y]
		await _snapshot(plan_size * SUPERSAMPLE, raw_global.path_join(id + "_plan.png"))
		# Profile passes: flat grey shading, then normals and depth for the outline pass.
		_use_stage(false)
		var aspect := float(PROFILE_SIZE.x) / PROFILE_SIZE.y
		if hull:
			var waterline_y: float = info.get("waterline_y", _bounds.get_center().y)
			_fit_profile(waterline_y, aspect)
			_profile_light.rotation_degrees = Vector3.ZERO
			_profile_light.look_at_from_position(Vector3.ZERO, Vector3(0.5, -1.4, -1.0), Vector3.UP)
			if domain == "surface":
				_sea.position = Vector3(_bounds.get_center().x, waterline_y - 0.01, _bounds.get_center().z)
				_sea.visible = true
		else:
			var view_dir := Vector3(0.55, 0.75, 1.0) if domain == "air" else Vector3(-0.35, 0.75, 0.8)
			_fit_camera(view_dir, Vector3.UP, aspect, 1.06)
			_profile_light.look_at_from_position(Vector3.ZERO, Vector3(-0.4, -1.2, -1.0), Vector3.UP)
		var window := _depth_window()
		_depth_material.set_shader_parameter("depth_min", window.x)
		_depth_material.set_shader_parameter("depth_range", window.y)
		_set_override(_grey_material)
		await _snapshot(PROFILE_SIZE * SUPERSAMPLE, raw_global.path_join(id + "_pgrey.png"))
		_set_override(_normal_material)
		await _snapshot(PROFILE_SIZE * SUPERSAMPLE, raw_global.path_join(id + "_pnormal.png"))
		_set_override(_depth_material)
		await _snapshot(PROFILE_SIZE * SUPERSAMPLE, raw_global.path_join(id + "_pdepth.png"))
		_sea.visible = false
		_set_override(null)
		_use_stage(true)
	_jobs.append(job)
	print("RENDERED " + id)
	return true
