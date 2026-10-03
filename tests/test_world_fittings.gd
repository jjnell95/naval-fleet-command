extends TestCase

func _unit(id: String) -> Unit:
	var u := Unit.new()
	u.spec = DataDB.platform(id)
	u.faction = "BLUE"
	u.magazines = u.spec.weapon_loadout.duplicate()
	u.flight_state = Unit.FlightState.AIRBORNE
	for sid in u.spec.sensor_ids: u.sensors.append(DataDB.sensor(sid))
	return u


func _stage(u: Unit) -> Dictionary:
	var parent := Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(parent)
	var models := WorldModels.new()
	var record := models.acquire(u.spec.id, parent)
	record["parent"] = parent
	record["models"] = models
	return record


func _apply(record: Dictionary, u: Unit, kind := "own") -> void:
	WorldFittings.apply(record["node"], {"kind": kind, "unit": u}, record["bounds"], WorldPresentation.model_scale(u.spec.length_m))


func test_tomcat_carries_real_phoenix_and_sidewinder_models_on_distinct_stations() -> void:
	var u := _unit("cw90_f14a")
	var r := _stage(u)
	_apply(r, u)
	var stations := WorldFittings.visible_stations(u)
	assert_eq(stations.size(), 6)
	var stores: Node3D = r["node"].get_node("OperationalFittings/Stores")
	for station: Dictionary in stations:
		var node := stores.get_node("Station%d_%s" % [station["index"], station["weapon"]]) as Node3D
		assert_true(node.scene_file_path.ends_with(str(station["weapon"]) + ".glb"), "actual weapon GLB instanced")
		assert_true(node.visible)
		assert_true(node.find_children("*", "MeshInstance3D", true, false).size() > 0)
		var pos: Vector3 = station["position_m"]
		assert_true(absf(pos.z) < 0.6 if station["weapon"] == "cw90_aim54a" else absf(pos.z) > 2.5, "Phoenix belly; Sidewinder glove")
	u.magazines["cw90_aim54a"] = 1
	_apply(r, u)
	assert_eq(WorldFittings.visible_stations(u).size(), 3)
	assert_eq(stores.get_children().filter(func(n: Node3D) -> bool: return n.visible).size(), 3)
	u.magazines["cw90_aim54a"] = 0
	u.magazines["cw90_aim9m"] = 0
	_apply(r, u)
	assert_true(not (r["node"].get_node("OperationalFittings") as Node3D).visible)
	r["parent"].free()


func test_helicopter_torpedoes_and_dipping_cable_follow_current_rounds_and_phase() -> void:
	var u := _unit("usn_helo_mh60r")
	var r := _stage(u)
	u.altitude_m = 20.0
	u.dip_phase = DippingSonar.Phase.LOWERING
	u.dip_timer_s = DippingSonar.LOWER_S * 0.5
	_apply(r, u)
	assert_near(WorldFittings.dip_fraction(u), 0.5)
	var cable: MeshInstance3D = r["node"].get_node("OperationalFittings/SonarCable")
	var half_length := cable.scale.y
	assert_true(cable.visible)
	assert_eq(WorldFittings.visible_stations(u).size(), 2)
	u.dip_phase = DippingSonar.Phase.LISTENING
	_apply(r, u)
	assert_near(cable.scale.y, half_length * 2.0)
	u.dip_phase = DippingSonar.Phase.RAISING
	u.dip_timer_s = DippingSonar.RAISE_S * 0.25
	_apply(r, u)
	assert_near(cable.scale.y, half_length * 0.5)
	u.dip_phase = DippingSonar.Phase.STOWED
	u.magazines["mk54_lwt"] = 1
	_apply(r, u)
	assert_true(not cable.visible)
	assert_eq(WorldFittings.visible_stations(u).size(), 1)
	r["parent"].free()


func test_estimates_and_unsupported_internal_fits_never_show_operational_details() -> void:
	var u := _unit("cw90_f14a")
	var r := _stage(u)
	_apply(r, u)
	var rig: Node3D = r["node"].get_node("OperationalFittings")
	_apply(r, u, "plotted")
	assert_true(not rig.visible, "even an accidental unit reference on an estimate reveals nothing")
	_apply(r, u, "visual")
	assert_true(rig.visible, "direct sighting may show external carriage")
	WorldFittings.apply(r["node"], {"kind": "own", "unit": null}, r["bounds"], 1.0)
	assert_true(not rig.visible, "disconnected own-unit last report reveals no current equipment state")
	for id: String in ["usn_fighter_f35c", "rfn_bomber_tu22m3", "usn_mpa_p8a"]:
		assert_true(WorldFittings.visible_stations(_unit(id)).is_empty(), "unsupported or internal carriage is omitted")
	r["parent"].free()


func test_pooled_models_keep_original_meshes_bounds_and_materials() -> void:
	var u := _unit("cw90_f14a")
	var r := _stage(u)
	var original_meshes: Array = r["meshes"].duplicate()
	var materials: Array = original_meshes.map(func(mi: MeshInstance3D) -> Material: return mi.get_active_material(0))
	_apply(r, u)
	var root: Node3D = r["node"]
	var models: WorldModels = r["models"]
	models.release(u.spec.id, root)
	assert_true(not (root.get_node("OperationalFittings") as Node3D).visible)
	var again := models.acquire(u.spec.id, r["parent"])
	assert_eq(again["node"], root)
	assert_eq(again["bounds"], r["bounds"])
	assert_eq(again["meshes"], original_meshes, "stores/cable/rotors excluded from aircraft material and geometry lists")
	for i in original_meshes.size(): assert_eq(original_meshes[i].get_active_material(0), materials[i])
	_apply(r, u, "plotted")
	assert_true(not (root.get_node("OperationalFittings") as Node3D).visible)
	r["parent"].free()


func test_mast_rises_from_the_sail_only_at_observed_periscope_depth() -> void:
	var u := _unit("cw90_los_angeles")
	var r := _stage(u)
	u.depth_m = 15.0
	_apply(r, u)
	var mast: MeshInstance3D = r["node"].get_node("OperationalFittings/Periscope")
	assert_true(mast.visible)
	var attach: Vector3 = r["node"].get_meta("mast_attachment")
	assert_true(attach.x > 0.8 and attach.x < 2.0, "anchor is on forward sail crown")
	assert_near(mast.position.y - mast.scale.y * 0.5, attach.y)
	var mast_top_m := (mast.position.y + mast.scale.y * 0.5) * WorldPresentation.model_scale(u.spec.length_m) - u.depth_m
	assert_near(mast_top_m, WorldPresentation.PERISCOPE_MAST_M)
	u.depth_m = 100.0
	_apply(r, u)
	assert_true(not (r["node"].get_node("OperationalFittings") as Node3D).visible)
	r["parent"].free()
