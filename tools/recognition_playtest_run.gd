extends "res://tools/fleet_command_playtest_run.gd"
## Library selection, three viewing angles, frame containment and visible geometry.

func run(scene_tree: SceneTree) -> void:
	tree = scene_tree
	capture = OS.get_cmdline_user_args().has("--capture")
	output_dir = "res://work/model-review/native"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output-dir="): output_dir = arg.trim_prefix("--output-dir=")
	DirAccess.make_dir_recursive_absolute(output_dir)
	CommanderLog.path_override = output_dir.path_join("commander_log.json")
	errors = load("res://tests/test_error_log.gd").new()
	OS.add_logger(errors)
	main = load("res://scenes/main/Main.tscn").instantiate()
	tree.root.add_child(main)
	await _frames()
	main._toggle_library()
	var ids: Array[String] = []
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://tools/art/render_manifest.json"))
	for id: String in manifest:
		if manifest[id].get("recognition_revision", "") == "2026-10-02": ids.append(id)
	checks["all 36 revised models are exercised"] = ids.size() == 36
	for id in ids:
		main._library.inspect(id)
		await _frames()
		var stage: ModelStage = main._library._stage
		checks[id + " loads live geometry"] = stage._id == id and stage._model != null and stage._container.visible
		for preset: String in ["default", "profile", "plan"]:
			stage.set_view(preset)
			await _frames()
			var fits := Rect2(Vector2.ZERO, stage._viewport.size).grow(1.0)
			var contained := stage._model_bounds.has_volume()
			for i in 8:
				contained = contained and fits.has_point(stage._camera.unproject_position(stage._model_bounds.get_endpoint(i)))
			checks[id + " fits " + preset] = contained
		stage.reset_view()
		if id in ["usn_fighter_f35c", "cw90_f14a", "rn_ssn_astute", "fra_ssn_suffren", "usn_mpa_p8a", "cw90_s3a"]:
			await _shot(id)
	checks["reference controls fit the window"] = _fits(main._library._stage) and _fits(main._library._list) and _fits(main._library._search)
	main._close_library()
	await _frames()
	checks["hidden reference stops its renderer"] = main._library._stage._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED
	facts["models"] = ids
	_finish()
