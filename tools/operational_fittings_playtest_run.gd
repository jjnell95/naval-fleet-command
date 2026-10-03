extends RefCounted
var tree: SceneTree
## Native inspection of the same model pool and operating-state fittings used by WorldScene.
var stage: Node3D
var camera: Camera3D
var label: Label
var models := WorldModels.new()
var record: Dictionary = {}
var out := "res://work/credible-review/fittings"
var errors: RefCounted

func run(scene_tree: SceneTree) -> void:
	tree = scene_tree
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output-dir="): out = arg.trim_prefix("--output-dir=")
	DirAccess.make_dir_recursive_absolute(out)
	errors = load("res://tests/test_error_log.gd").new()
	OS.add_logger(errors)
	stage = Node3D.new()
	tree.root.add_child(stage)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("132330")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c2d5e3")
	env.ambient_light_energy = 0.7
	environment.environment = env
	stage.add_child(environment)
	for angles in [Vector3(-45, -45, 0), Vector3(25, 120, 0)]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = angles
		light.light_energy = 1.6
		stage.add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 2000.0
	stage.add_child(camera)
	label = Label.new()
	label.position = Vector2(30, 22)
	label.add_theme_font_size_override("font_size", 24)
	tree.root.add_child(label)
	var u := _show("cw90_f14a")
	_pose(Vector3(20, -12, 22), Vector3.ZERO, 17.0)
	await _shot("01-tomcat-loaded", "F-14A+  |  4 Phoenix belly stations + 2 Sidewinder glove stations", u)
	u.magazines["cw90_aim54a"] = 1
	u.magazines["cw90_aim9m"] = 1
	await _shot("02-tomcat-after-launch", "F-14A+  |  1 Phoenix + 1 Sidewinder remain", u)
	u = _show("usn_helo_mh60r")
	_pose(Vector3(22, -7, 24), Vector3.ZERO, 18.0)
	await _shot("03-seahawk-loaded", "MH-60R  |  Two external Mk 54 torpedoes", u)
	u.altitude_m = 20.0
	u.dip_phase = DippingSonar.Phase.LOWERING
	u.dip_timer_s = DippingSonar.LOWER_S * 0.75
	_pose(Vector3(30, 5, 35), Vector3(0, -8, 0), 33.0)
	await _shot("04-seahawk-lowering", "MH-60R  |  Sonar lowering: 25% cable deployed", u)
	u = _show("cw90_los_angeles")
	u.depth_m = 15.0
	_pose(Vector3(55, 30, 75), Vector3(8, 6, 0), 70.0)
	await _shot("05-submarine-mast", "Los Angeles class  |  Observation mast raised from sail", u)
	u.depth_m = 100.0
	await _shot("06-submarine-deep", "Los Angeles class  |  Deep running: observation mast stowed", u)
	var failures: Array = errors.take_errors()
	var file := FileAccess.open(out.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"captures": 6, "errors": failures}, "\t"))
	OS.remove_logger(errors)
	stage.free()
	label.free()
	tree.quit(0 if failures.is_empty() else 1)

func _show(id: String) -> Unit:
	if not record.is_empty(): models.release(record["id"], record["node"])
	var u := Unit.new()
	u.spec = DataDB.platform(id)
	u.faction = "BLUE"
	u.flight_state = Unit.FlightState.AIRBORNE
	u.magazines = u.spec.weapon_loadout.duplicate()
	for sid in u.spec.sensor_ids: u.sensors.append(DataDB.sensor(sid))
	record = models.acquire(id, stage)
	record["id"] = id
	var scale := WorldPresentation.model_scale(u.spec.length_m)
	(record["node"] as Node3D).scale = Vector3.ONE * scale
	for mi: MeshInstance3D in record["meshes"]:
		if mi.has_meta("finish"): WorldMaterials.set_way(mi, WorldMaterials.ALOFT)
	return u

func _pose(position: Vector3, aim: Vector3, size: float) -> void:
	camera.position = position
	camera.look_at(aim)
	camera.size = size

func _shot(name: String, title: String, u: Unit) -> void:
	label.text = title
	WorldFittings.apply(record["node"], {"kind": "own", "unit": u}, record["bounds"], WorldPresentation.model_scale(u.spec.length_m))
	for i in 5: await tree.process_frame
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png(out.path_join(name + ".png"))
