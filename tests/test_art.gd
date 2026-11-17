extends TestCase
## The rendered recognition art is built from data/platforms by tools/blender; these tests keep
## the two in step so a new platform cannot ship without a picture, and check the loader's
## contract that the display code relies on.


func test_every_platform_has_profile_and_plan_art() -> void:
	var specs := DataDB.all_platforms()
	assert_true(specs.size() >= 30, "platform catalogue loads")
	for spec: PlatformSpec in specs:
		var profile := PlatformArt.profile(spec.id)
		var plan := PlatformArt.plan(spec.id)
		assert_true(profile != null, spec.id + " has a profile render")
		assert_true(plan != null, spec.id + " has a plan render")
		if plan != null:
			assert_true(plan.get_width() >= 8 and plan.get_height() >= 8, spec.id + " plan has a usable size")
		if profile != null:
			assert_true(profile.get_width() > profile.get_height(), spec.id + " profile is landscape")


func test_plan_art_is_landscape_for_hulls_and_scaled_from_width() -> void:
	# A ship's plan is far longer than it is wide; the map divides the real length by the
	# texture width times the frame margin, so that ratio must hold for every hull.
	for spec: PlatformSpec in DataDB.all_platforms():
		if spec.domain != "surface" and spec.domain != "subsurface":
			continue
		var plan := PlatformArt.plan(spec.id)
		if plan == null:
			continue
		assert_true(plan.get_width() > plan.get_height() * 2, spec.id + " plan is a long hull")
	assert_near(PlatformArt.PLAN_MARGIN, 1.10, 1e-6, "frame margin matches the Blender build")


func test_plan_art_is_imported_small_but_enough_for_the_largest_symbol() -> void:
	# The plans serve only the chart's graphic symbols, at most 56 px long and made at twice that,
	# so they are imported no larger than PLAN_IMPORT_LIMIT (size_limit in each .import): a symbol
	# is made from a small texture and a small read-back, never the full 768 px render.
	var need := int(ceilf(float(TacticalMap.GRAPHIC_SYMBOL_PX.max()) * PlatformArt.PLAN_MARGIN * 2.0))
	for spec: PlatformSpec in DataDB.all_platforms():
		var plan := PlatformArt.plan(spec.id)
		if plan == null:
			continue
		assert_true(maxi(plan.get_width(), plan.get_height()) <= PlatformArt.PLAN_IMPORT_LIMIT, spec.id + " plan is imported small: %s" % plan.get_size())
		assert_true(plan.get_width() >= need, spec.id + " plan is wide enough for the largest graphic symbol: %s" % plan.get_size())


func test_missing_art_returns_null_and_is_cached() -> void:
	assert_true(PlatformArt.profile("no_such_platform") == null, "unknown id has no profile")
	assert_true(PlatformArt.plan("no_such_platform") == null, "unknown id has no plan")
	assert_true(PlatformArt.profile("no_such_platform") == null, "second lookup is still null")


func test_presentation_catalogue_is_complete_and_importable() -> void:
	var records := DataDB.all_platforms() + DataDB.all_weapons()
	for spec in records:
		var weapon := spec is WeaponSpec
		assert_true(PlatformArt.beauty(spec.id, weapon) != null, spec.id + " has a beauty render")
		var thumb := PlatformArt.thumbnail(spec.id, weapon)
		assert_true(thumb != null and thumb.get_width() <= 240, spec.id + " has a lightweight thumbnail")
		var path := "res://assets/models/%s.glb" % spec.id
		assert_true(ResourceLoader.exists(path), spec.id + " has an imported runtime model")
		if ResourceLoader.exists(path):
			var scene := load(path) as PackedScene
			assert_true(scene != null, spec.id + " imports as a scene")
			if scene != null:
				var instance := scene.instantiate()
				var meshes := instance.find_children("*", "MeshInstance3D", true, false)
				assert_true(not meshes.is_empty(), spec.id + " has drawable geometry")
				var surfaces := 0
				for mesh_node: MeshInstance3D in meshes:
					surfaces += mesh_node.mesh.get_surface_count()
					var extent := mesh_node.get_aabb().size
					assert_true(extent.is_finite(), spec.id + " has finite bounds")
					assert_true(maxf(extent.x, maxf(extent.y, extent.z)) <= 10.01, spec.id + " fits the normalized inspection stage")
				assert_true(surfaces <= 20, spec.id + " respects the material draw-call budget")
				instance.free()


func test_missing_presentation_assets_fall_back_cleanly() -> void:
	assert_true(PlatformArt.beauty("missing-platform") == null, "missing platform returns null")
	assert_true(PlatformArt.beauty("missing-weapon", true) == null, "missing weapon returns null")
	assert_true(PlatformArt.beauty("missing-platform") == null, "missing lookup is cached")


func test_surface_and_aircraft_plans_keep_distinct_proportions() -> void:
	var ship := PlatformArt.plan("usn_ddg_burke_iii")
	var jet := PlatformArt.plan("usn_fighter_f35c")
	assert_true(ship != null and jet != null, "ship and jet plans are available")
	if ship != null and jet != null:
		assert_true(float(ship.get_width()) / ship.get_height() > 5, "destroyer plan is slender")
		assert_true(float(jet.get_width()) / jet.get_height() < 2, "carrier fighter shows its broad wing")


func test_trawler_has_a_forward_wheelhouse_and_a_separate_aft_working_rig() -> void:
	var trawler := preload("res://assets/models/civ_fishing_trawler.glb").instantiate()
	var windows := _material_bounds(trawler, "glazing")
	var rig := _material_bounds(trawler, "marking_yellow")
	assert_true(windows.position.x > 0.0 and windows.size.z > 1.0, "wheelhouse windows span the forward deck")
	assert_true(rig.end.x < 0.0 and rig.size.y > 1.0 and rig.size.z > 1.0, "raised trawl gantry spans the stern")
	trawler.free()


func test_maud_has_a_marked_landing_deck_behind_the_bridge() -> void:
	var maud := preload("res://assets/models/rnon_aux_maud.glb").instantiate()
	var pad := _material_bounds(maud, "flight_deck")
	var markings := _material_bounds(maud, "marking_white")
	var windows := _material_bounds(maud, "glazing")
	assert_true(pad.size.x > 2.0 and pad.end.x < windows.position.x, "stern deck lies aft of the accommodation")
	assert_true(markings.size.z > 0.8 and pad.position.x < markings.position.x and markings.end.x < pad.end.x
			and markings.position.y >= pad.end.y, "visible landing markings lie above the aft deck")
	maud.free()


func _material_bounds(model: Node, material_name: String) -> AABB:
	var bounds := AABB()
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in part.mesh.get_surface_count():
			var finish := part.mesh.surface_get_material(surface)
			if finish == null or finish.resource_name != material_name:
				continue
			var points: PackedVector3Array = part.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for point: Vector3 in points:
				bounds = AABB(point, Vector3.ZERO) if bounds == AABB() else bounds.expand(point)
	return bounds


func test_close_scale_plot_uses_legible_metric_steps() -> void:
	var map := TacticalMap.new()
	map.ppn = TacticalMap.MAX_PPN
	var step := map._nice_step(80)
	assert_true(step * map.ppn >= 80 and step * map.ppn <= 200, "scale bar remains inside the plot")
	assert_true(map._chart_axis(.014, "E", "W") != map._chart_axis(.034, "E", "W"), "close coordinates do not collapse to the same label")
	map.free()


func test_seahawk_and_tu142_cockpit_glazing_spans_both_sides_forward() -> void:
	for id: String in ["usn_helo_mh60r", "rfn_mpa_tu142"]:
		var scene := load("res://assets/models/%s.glb" % id) as PackedScene
		var model := scene.instantiate()
		var glass := _material_bounds(model, "glazing")
		assert_true(glass.end.x > 3.0 and glass.position.z < 0.0 and glass.end.z > 0.0,
				"%s has a glazed forward cockpit across both sides of the normalized model" % id)
		model.free()
