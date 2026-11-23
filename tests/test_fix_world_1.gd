extends TestCase
## The 3D pane at the scale of a large fleet, its right-click, and the panels beside it that
## redraw only when what they show changes.

const ENV := {"visibility_nm": 10.0}


func _unit(pid: String, faction: String, pos: Vector2, callsign := "") -> Unit:
	var spec := DataDB.platform(pid)
	var u := Unit.new()
	u.spec = spec
	u.faction = faction
	u.callsign = callsign if callsign != "" else "%s %s" % [faction, pid]
	u.position = pos
	u.health = spec.health
	return u


func _hold(tm: TrackManager, id: String, truth: Unit, position: Vector2) -> Track:
	var t := Track.new()
	t.id = id
	t.owner_faction = "BLUE"
	t.truth = truth
	t.position = position
	t.status = Track.Status.ACTIVE
	t.classification = Track.Classification.SURFACE
	t.domain = "surface"
	t.identity = "HOSTILE"
	var list: Array = tm._tracks.get("BLUE", [])
	list.append(t)
	tm._tracks["BLUE"] = list
	return t


func _keys(entries: Array) -> Array:
	var out: Array = []
	for e: Dictionary in entries:
		out.append(e["key"])
	out.sort()
	return out


## 100 own ships, 60 of them massed round the middle, and 200 others spread over a theatre
## several times the pane's reach, half of the others held as contacts a little off where they
## really are.
func _fleet(um: UnitManager, tm: TrackManager) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in 100:
		var spread := 25.0 if i < 60 else 120.0
		um.add_unit(_unit("cw90_ticonderoga", "BLUE", Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread)), "BLUE %d" % i))
	for i in 200:
		var red := _unit("cw90_slava", "RED", Vector2(rng.randf_range(-150.0, 150.0), rng.randf_range(-150.0, 150.0)))
		um.add_unit(red)
		if i % 2 == 0:
			_hold(tm, "T%04d" % (1000 + i), red, red.position + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5)))


func test_a_300_unit_fleet_builds_no_more_entries_than_the_view_keeps() -> void:
	var um := UnitManager.new()
	var tm := TrackManager.new()
	_fleet(um, tm)
	assert_eq(um.units.size(), 300)
	for centre: Vector2 in [Vector2.ZERO, Vector2(60, -40), Vector2(-110, 95)]:
		var built := WorldPresentation.unit_entries(um, tm, "BLUE", ENV, PackedStringArray(), centre, WorldPresentation.MAX_RANGE_NM, WorldPresentation.MAX_ENTITIES)
		var kept := WorldPresentation.cull(built, centre)
		if centre == Vector2.ZERO:
			assert_eq(kept.size(), WorldPresentation.MAX_ENTITIES, "the massed force fills the view's budget")
		assert_true(built.size() <= kept.size(), "round %s the view builds %d entries and keeps %d" % [centre, built.size(), kept.size()])
		var everything := WorldPresentation.unit_entries(um, tm, "BLUE", ENV)
		assert_true(everything.size() > 3 * kept.size(), "the theatre holds far more than the view shows")
		assert_eq(_keys(kept), _keys(WorldPresentation.cull(everything, centre)), "and it shows exactly what building everything and culling would have shown, round %s" % centre)
	um.free()
	tm.free()


func test_the_hook_and_the_action_subject_are_built_however_far_off() -> void:
	var um := UnitManager.new()
	var tm := TrackManager.new()
	_fleet(um, tm)
	var far_own := _unit("cw90_ticonderoga", "BLUE", Vector2(400, 0), "FAR")
	um.add_unit(far_own)
	var far_red := _unit("cw90_slava", "RED", Vector2(-400, 0))
	um.add_unit(far_red)
	_hold(tm, "T9999", far_red, Vector2(-399, 1))
	var keep := PackedStringArray(["u:%d" % far_own.id, "t:T9999"])
	var built := WorldPresentation.unit_entries(um, tm, "BLUE", ENV, PackedStringArray(), Vector2.ZERO, WorldPresentation.MAX_RANGE_NM, WorldPresentation.MAX_ENTITIES, keep)
	var kept := WorldPresentation.cull(built, Vector2.ZERO, "u:%d" % far_own.id, WorldPresentation.MAX_RANGE_NM, WorldPresentation.MAX_ENTITIES, "t:T9999")
	assert_eq(kept[0]["key"], "u:%d" % far_own.id, "the hooked ship 400 nm off is still the subject")
	assert_eq(kept[1]["key"], "t:T9999", "and the contact Action follows is still drawn")
	assert_eq(kept[0]["label"], "FAR", "with its label")
	var alone := WorldPresentation.unit_entries(um, tm, "BLUE", ENV, PackedStringArray(), Vector2.ZERO, -1.0, 0, PackedStringArray(["t:T9999"]))
	assert_eq(_keys(alone), ["t:T9999"], "asked for one subject alone, only that is built")
	um.free()
	tm.free()


func test_a_contact_seen_beyond_the_view_is_not_drawn_as_its_plot_inside_it() -> void:
	var um := UnitManager.new()
	var tm := TrackManager.new()
	var own := _unit("cw90_ticonderoga", "BLUE", Vector2(36, 0))
	var red := _unit("cw90_slava", "RED", Vector2(42, 0))
	um.add_unit(own)
	um.add_unit(red)
	_hold(tm, "T1001", red, Vector2(39, 0))
	var built := WorldPresentation.unit_entries(um, tm, "BLUE", ENV, PackedStringArray(), Vector2.ZERO, WorldPresentation.MAX_RANGE_NM, WorldPresentation.MAX_ENTITIES)
	assert_eq(_keys(WorldPresentation.cull(built, Vector2.ZERO)), _keys(WorldPresentation.cull(WorldPresentation.unit_entries(um, tm, "BLUE", ENV), Vector2.ZERO)), "a sighted unit is shown once, as itself, even when that is past the edge")
	assert_true(_keys(built).find("t:T1001") < 0, "so its plot does not stand in for it")
	um.free()
	tm.free()


# --- Panels that redraw on change --------------------------------------------------------

func test_readiness_bars_redraw_only_when_a_value_they_show_changes() -> void:
	var bars := ReadinessBars.new()
	var ship := _unit("cw90_ticonderoga", "BLUE", Vector2.ZERO)
	bars.unit = ship
	assert_true(not bars.refresh(), "setting the unit has already asked for its first drawing")
	for i in 5:
		assert_true(not bars.refresh(), "a frame in which nothing changed draws nothing")
	ship.health = ship.spec.health * 0.6
	assert_true(bars.refresh(), "a hit is drawn")
	assert_true(not bars.refresh(), "once")
	ship.components["sensors"] = 0.4
	assert_true(bars.refresh(), "so is a damaged subsystem")
	bars.unit = null
	assert_true(not bars.refresh(), "clearing the unit asked for its own redraw")
	bars.free()


func test_the_portrait_redraws_only_when_the_platform_or_its_framing_changes() -> void:
	var card := PlatformPortrait.new()
	assert_true(card.refresh(), "the first frame draws the empty card")
	for i in 5:
		assert_true(not card.refresh(), "and nothing more while nothing changes")
	card.spec_override = DataDB.platform("cw90_slava")
	assert_true(not card.refresh(), "choosing a platform asked for its drawing as it was chosen")
	assert_eq(card.shown_spec().id, "cw90_slava")
	card.framed = true
	assert_true(not card.refresh(), "so did framing it")
	card.spec_override = DataDB.platform("cw90_slava")
	assert_true(not card.refresh(), "the same platform again is no change")
	card.free()


# --- Right-click in the 3D pane ----------------------------------------------------------

func _boot_view() -> Main:
	var main: Main = preload("res://scenes/main/Main.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.start_scenario("res://data/scenarios/training_missile_defence.json")
	main._on_briefing_start()
	SimClock.set_paused(true)
	var view := main._world_view
	main._swap_views()
	main._toggle_world_full()
	# The synchronous suite does not yield a frame for the parent containers' layout.
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(640, 360)
	return main


func _right_click(view: WorldView, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = true
	e.position = at
	view._gui_input(e)
	var up := e.duplicate() as InputEventMouseButton
	up.pressed = false
	view._gui_input(up)


func _restore_after(main: Main) -> void:
	main._cds_menus.close()
	main.free()
	SimClock.set_speed_index(0)
	SimClock.set_paused(true)


func test_right_click_on_the_3d_pane_opens_the_hooked_platforms_menu() -> void:
	var main := _boot_view()
	var view := main._world_view
	var ship: Unit = main.simulation.unit_manager.get_faction_units(main.simulation.player_faction).filter(func(u: Unit) -> bool: return not u.is_aircraft() and u.is_engageable())[0]
	main.map.clear_selection()
	view._process(0.016)
	_right_click(view, Vector2(20, 300))
	assert_true(not main._cds_menus.is_open(), "with nothing hooked there is no platform menu to open")
	main.map.select_units([ship])
	view._process(0.016)
	_right_click(view, Vector2(20, 300))
	assert_true(main._cds_menus.is_open(), "with a ship hooked, a right-click in the 3D window opens its orders menu")
	assert_eq(main.map.selected, [ship], "for the hooked ship")
	_restore_after(main)


func test_right_click_on_an_own_ship_in_the_3d_pane_hooks_it_first() -> void:
	var main := _boot_view()
	var view := main._world_view
	var ship: Unit = main.simulation.unit_manager.get_faction_units(main.simulation.player_faction).filter(func(u: Unit) -> bool: return not u.is_aircraft() and u.is_engageable())[0]
	main.map.select_units([ship])
	view._process(0.016)
	view._process(0.016)
	var cam := view._scene.camera
	var at := cam.unproject_position(WorldPresentation.to_world(ship.position, view._origin_nm, 0.0))
	var picked := view._scene.pick_entry(at)
	assert_eq(picked.get("key", ""), "u:%d" % ship.id, "the hooked ship is under the cursor at %s" % at)
	main.map.clear_selection()
	_right_click(view, at)
	assert_eq(main.map.selected, [ship], "right-clicking a ship of ours hooks it, as on the chart")
	assert_true(main._cds_menus.is_open(), "and opens its menu")
	_restore_after(main)


# --- An installation on its site ---------------------------------------------------------

func test_a_plotted_shore_battery_stands_on_its_site_as_an_emplacement() -> void:
	Terrain.load_from({"terrain": {"land": [{"id": "test_island", "name": "Test Island", "elevation_m": 300.0, "points_nm": [[-5, -5], [5, -5], [5, 5], [-5, 5]]}]}})
	var scene := WorldScene.new()
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(scene)
	scene.build()
	var um := UnitManager.new()
	var tm := TrackManager.new()
	var battery := _unit("irn_battery_qader", "RED", Vector2(0.5, 0.0))
	um.add_unit(battery)
	var t := _hold(tm, "T1", battery, Vector2(0.6, 0.1))
	t.domain = "land"
	t.classification = Track.Classification.CLASS_KNOWN
	t.known_class = battery.spec.short_name
	t.known_category = battery.spec.category
	t.position_error_nm = 0.5
	var entry := WorldPresentation.plotted_entry(t)
	assert_eq(entry["model"], "irn_battery_qader", "the plot knows the class, so the class model is drawn")
	scene.update(0.016, [entry], entry["key"])
	var rec: Dictionary = scene._records[entry["key"]]
	assert_eq(rec["tint"], "", "an installation keeps its earthworks, hardstand and vehicles instead of a pale wash")
	var model: Node3D = rec["root"]
	var bounds: AABB = rec["bounds"]
	var ground := scene.ground_at(model.position)
	assert_true(ground > 10.0, "the island stands well above the sea (%.1f m)" % ground)
	var foot := model.position.y + bounds.position.y * model.scale.y
	assert_true(foot >= ground - 0.01, "the site is not sunk into the ground under it (foot %.1f, ground %.1f)" % [foot, ground])
	var plinth := model.get_node_or_null("Plinth") as MeshInstance3D
	assert_true(plinth != null and plinth.visible, "it stands on a graded platform of earth")
	var plinth_bottom := model.position.y + (plinth.position.y - plinth.scale.y) * model.scale.y
	assert_true(plinth_bottom < ground - 2.0, "which reaches down into the hillside round it")
	var ring: MeshInstance3D = rec["ring"]
	assert_true(ring != null and ring.visible, "the plot's uncertainty ring is still drawn")
	assert_true(ring.position.y >= ground, "on the ground, not on the sea beneath it (ring at %.1f m)" % ring.position.y)
	# The fix improves and the plot moves: the model stands on the ground where it now is.
	t.position = Vector2(-3.5, 2.0)
	entry = WorldPresentation.plotted_entry(t)
	scene.update(0.016, [entry], entry["key"])
	assert_near(model.position.y + bounds.position.y * model.scale.y, scene._ground_under(entry["key"], t.position, WorldScene._footprint_m(bounds, model.scale.y)), 0.01, "the moved plot is grounded afresh")
	root.remove_child(scene)
	scene.free()
	um.free()
	tm.free()
	Terrain.clear()
