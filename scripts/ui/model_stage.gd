class_name ModelStage
extends Control
## A self-contained inspection stage. Only the visible library runs a 3D viewport.
## Public catalogue models never reveal scenario contact identity.
var _viewport: SubViewport
var _container: SubViewportContainer
var _pivot: Node3D
var _model: Node3D
var _camera: Camera3D
var _id := ""
var _yaw := 0.0
var _pitch := 0.38
var _zoom := 13.5
var _dragging := false
var _spin := false
var _weapon := false
var _fallback: Texture2D
var _model_bounds := AABB()

func _ready() -> void:
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	_container = SubViewportContainer.new()
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_container.add_child(_viewport)
	var world := Node3D.new()
	_viewport.add_child(world)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0b1723")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("adc5dc")
	env.ambient_light_energy = 0.18
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("142535")
	sky_material.sky_horizon_color = Color("7296ae")
	sky_material.ground_bottom_color = Color("08111a")
	sky_material.ground_horizon_color = Color("39556b")
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env_node.environment = env
	world.add_child(env_node)
	for light_data in [[Vector3(-40, -35, 0), Color("ffecd4"), 0.38], [Vector3(-20, 145, 0), Color("83bbef"), 0.14], [Vector3(20, 25, 0), Color("d3e8fc"), 0.06]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = light_data[0]
		light.light_color = light_data[1]
		light.light_energy = light_data[2]
		light.shadow_enabled = light_data[2] > 0.3
		light.directional_shadow_max_distance = 50
		world.add_child(light)
	_pivot = Node3D.new()
	world.add_child(_pivot)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.1
	_camera.far = 100
	world.add_child(_camera)
	resized.connect(_resize_view)
	visibility_changed.connect(_sync_visibility)
	_resize_view()
	_camera_pose()
	if not _id.is_empty():
		_load_model()
	_sync_visibility()

func show_asset(asset_id: String, weapon := false) -> void:
	if _id == asset_id and _weapon == weapon:
		return
	_id = asset_id
	_weapon = weapon
	_fallback = PlatformArt.beauty(asset_id, weapon)
	reset_view()
	if is_node_ready():
		_load_model()
	queue_redraw()

func _load_model() -> void:
	_model_bounds = AABB()
	if _model != null:
		_pivot.remove_child(_model)
		_model.queue_free()
		_model = null
	var path := "res://assets/models/%s.glb" % _id
	if not _id.is_empty() and ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		if scene != null:
			_model = scene.instantiate() as Node3D
			_pivot.add_child(_model)
			var first := true
			for node: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
				var bounds := node.global_transform * node.get_aabb()
				_model_bounds = bounds if first else _model_bounds.merge(bounds)
				first = false
	_container.visible = _model != null
	_camera_pose()
	_sync_visibility()
	queue_redraw()

func reset_view() -> void:
	_yaw = 0.0
	_pitch = 0.38
	_zoom = 13.5
	_spin = false
	_camera_pose()

func set_view(preset: String) -> void:
	_spin = false
	match preset:
		"profile":
			_yaw = -0.5
			_pitch = 0.03
			_camera_pose()
		"plan":
			_yaw = -0.5
			_pitch = 1.54
			_camera_pose()
		_:
			reset_view()

func set_spin(enabled: bool) -> void:
	_spin = enabled

func _sync_visibility() -> void:
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() and _model != null else SubViewport.UPDATE_DISABLED
	if not is_visible_in_tree():
		_dragging = false

func _resize_view() -> void:
	_camera_pose()
	queue_redraw()

func _camera_pose(straight := false) -> void:
	if _camera == null:
		return
	var a := _yaw + (0.0 if straight else 0.5)
	_camera.position = Vector3(sin(a) * cos(_pitch), sin(_pitch), cos(a) * cos(_pitch)) * 25.0
	_camera.look_at(Vector3.ZERO)
	# Project the bounds into this camera's axes. A tall gun mount and a long ship must
	# both fit the stage, including after orbiting or changing to a plan/profile view.
	var aspect := maxf(size.x / maxf(size.y, 1.0), .1)
	if _model_bounds.size == Vector3.ZERO:
		_camera.size = _zoom / maxf(aspect, 1.0)
		return
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var rotation := _camera.global_basis.inverse()
	for i in 8:
		var point := rotation * _model_bounds.get_endpoint(i)
		minimum = minimum.min(Vector2(point.x, point.y))
		maximum = maximum.max(Vector2(point.x, point.y))
	var extent := maximum - minimum
	_camera.size = maxf(extent.y, extent.x / aspect) * 1.18 * (_zoom / 13.5)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			if event.double_click:
				reset_view()
			accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom = clampf(_zoom * (0.90 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.10), 7.5, 24.0)
			_camera_pose()
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x * 0.008
		_pitch = clampf(_pitch + event.relative.y * 0.006, -0.65, 1.54)
		_spin = false
		_camera_pose()
		accept_event()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_dragging = false
	if _spin and not _dragging:
		_yaw += delta * 0.18
		_camera_pose()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0b1723"))
	# A quiet studio graticule, with no animated sweep to suggest sensor truth.
	for x in range(0, int(size.x), 48):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color("142738"), 1)
	for y in range(0, int(size.y), 48):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color("142738"), 1)
	if _model == null and _fallback != null:
		var s := minf(size.x / _fallback.get_width(), size.y / _fallback.get_height())
		var wh := _fallback.get_size() * s
		draw_texture_rect(_fallback, Rect2((size - wh) / 2, wh), false)
