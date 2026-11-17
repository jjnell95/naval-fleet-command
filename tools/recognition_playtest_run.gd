extends "res://tools/fleet_command_playtest_run.gd"
## Contextual Reference via chart clicks and F7, then library selection and model framing.

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
	await _library_key(KEY_F7)
	checks["F7 on the operations desk opens a rotating Reference model"] = main._library.visible and not main._menu.visible and main._library._stage._spin and main._library._spin_button.button_pressed
	await _library_key(KEY_F7)
	var focus := main.get_viewport().gui_get_focus_owner()
	checks["closing Reference returns keyboard control to the desk"] = main._menu.visible and not main._library.visible and focus != null and main._menu.is_ancestor_of(focus)
	await _reference_from_chart()
	if OS.get_cmdline_user_args().has("--context-only"):
		_finish()
		return
	main._toggle_library()
	var ids: Array[String] = []
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://tools/art/render_manifest.json"))
	for id: String in manifest:
		var revision := str(manifest[id].get("recognition_revision", ""))
		if revision.is_empty() or DataDB.platform(id) == null:
			continue
		ids.append(id)
	var revised := ["civ_fishing_trawler", "rnon_aux_maud", "rfn_mpa_tu142", "usn_helo_mh60r"]
	checks["at least 36 prior revisions and four additional platforms are exercised"] = ids.size() >= 36 + revised.size()
	for id: String in revised:
		checks[id + " is included in the recognition playtest"] = ids.has(id)
	for id in ids:
		main._library.inspect(id)
		await _frames()
		var stage: ModelStage = main._library._stage
		checks[id + " loads live geometry"] = stage._id == id and stage._model != null and stage._container.visible
		for preset: String in ["default", "profile", "plan", "front"]:
			stage.set_view(preset)
			await _frames()
			var fits := Rect2(Vector2.ZERO, stage._viewport.size).grow(1.0)
			var contained := stage._model_bounds.has_volume()
			for i in 8:
				contained = contained and fits.has_point(stage._camera.unproject_position(stage._model_bounds.get_endpoint(i)))
			checks[id + " fits " + preset] = contained
			if revised.has(id) and preset != "default":
				await _shot(id + "-" + preset)
			if id == ids[0] and preset != "default":
				var axes := {"front": Vector3.RIGHT, "plan": Vector3.UP, "profile": Vector3.BACK}
				checks[preset + " looks squarely along its orthographic axis"] = stage._camera.projection == Camera3D.PROJECTION_ORTHOGONAL and stage._camera.global_basis.z.dot(axes[preset]) > 0.9999
		stage.reset_view()
		if revised.has(id) or id in ["usn_fighter_f35c", "cw90_f14a", "rn_ssn_astute", "fra_ssn_suffren", "usn_mpa_p8a", "cw90_s3a"]:
			await _shot(id)
	checks["reference controls fit the window"] = _fits(main._library._stage) and _fits(main._library._list) and _fits(main._library._search)
	main._close_library()
	await _frames()
	checks["hidden reference stops its renderer"] = main._library._stage._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED
	facts["models"] = ids
	_finish()


## A paused fixture isolates the library's response to a held report. The plot first
## knows no class, then knows the class shared by both operators. Its hidden aircraft is
## Japanese in both cases. Only the player chooses a particular catalogue entry.
func _reference_from_chart() -> void:
	main.start_scenario("res://data/scenarios/training_missile_defence.json")
	main._on_briefing_start()
	SimClock.set_paused(true)
	var sim := main.simulation
	var ship := sim.unit_manager.get_faction_units("BLUE")[0]
	ScenarioLoader.populate(sim.unit_manager, {"units": [
		{"platform": "usn_helo_mh60r", "faction": "BLUE", "callsign": "Reference flight", "position_nm": [10, 5]},
		{"platform": "jasdf_fighter_f35b", "faction": "RED", "callsign": "Unreported airframe", "position_nm": [5, -6]},
	]})
	var aircraft: Unit = sim.unit_manager.units[-2]
	var subject: Unit = sim.unit_manager.units[-1]
	var contact := sim.track_manager.report_intel("BLUE", subject, Vector2(5, -6), 2, SimClock.sim_time, "Exercise report")
	main.map.set_follow_selection(false)
	main.map.center_on(Vector2.ZERO)
	main.map.ppn = 14.0
	await _frames()
	await _chart_click(ship.position)
	await _chart_click(contact.position)
	await _library_key(KEY_F7)
	var library := main._library
	checks["F7 on an unknown opens an unselected catalogue"] = library.visible and library._title.text == "CLASS UNREPORTED" and library._list.get_selected_items().is_empty() and library._specs.size() == DataDB.all_platforms().size()
	checks["an unreported class reveals no identity or model"] = library._stage._id == "" and library._stage._model == null and library._detail.text == "" and library._loadout.get_child_count() == 0
	await _library_key(KEY_F7)
	await _chart_click(ship.position)
	await _library_key(KEY_F7)
	checks["F7 on the friendly ship follows the inspected ship, with contact still hooked"] = main.map.selected_track == contact and main.map.inspection_track() == null and library.visible and library._stage._id == ship.spec.id
	await _library_key(KEY_F7)
	contact.classification = Track.Classification.CLASS_KNOWN
	contact.known_class = "F-35B"
	await _chart_click(contact.position)
	await _library_key(KEY_F7)
	var variants := PackedStringArray()
	for spec: PlatformSpec in library._specs:
		variants.append(spec.id)
	variants.sort()
	checks["a shared class opens both operator variants without preselecting one"] = library.visible and variants == PackedStringArray(["jasdf_fighter_f35b", "rn_fighter_f35b"]) and library._list.get_selected_items().is_empty() and library._stage._id == "" and library._stage._model == null
	if library._list.item_count == 2:
		checks["the two operator choices have distinct row labels"] = library._list.get_item_text(0) != library._list.get_item_text(1)
		await _shot("reference-ambiguous-class")
		var choice := -1
		for i in library._specs.size():
			if library._specs[i].id == "rn_fighter_f35b":
				choice = i
		if choice >= 0:
			var row := library._list.get_item_rect(choice)
			await _click(library._list.get_global_transform_with_canvas() * row.get_center())
		checks["clicking an operator opens that model regardless of the contact's hidden identity"] = library._stage._id == "rn_fighter_f35b"
	await _click_control(library._search)
	library._search.select_all()
	for ch in "f-35b lightning japan":
		var key := InputEventKey.new()
		key.keycode = ch.to_upper().unicode_at(0) as Key
		key.unicode = ch.unicode_at(0)
		key.pressed = true
		main.get_viewport().push_input(key, true)
		key.pressed = false
		main.get_viewport().push_input(key, true)
	await _frames()
	checks["keyboard search matches the reported class, display name and chosen operator"] = library._specs.size() == 1 and library._specs[0].id == "jasdf_fighter_f35b" and library._stage._id == "jasdf_fighter_f35b"
	await _library_key(KEY_F7)
	await _chart_click(aircraft.position)
	await _library_key(KEY_F7)
	checks["F7 on the friendly aircraft follows the aircraft after inspecting a contact"] = main.map.selected_track == contact and main.map.inspection_track() == null and library.visible and library._stage._id == aircraft.spec.id
	await _library_key(KEY_F7)
	checks["closing contextual Reference restores the paused chart"] = not library.visible and SimClock.paused and main.map.keyboard_navigation_enabled


func _library_key(code: Key) -> void:
	for down: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = code
		key.pressed = down
		main.get_viewport().push_input(key, true)
		await tree.process_frame
	await _frames()
