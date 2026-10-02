extends TestCase
## Regression coverage for the M17 command-deck UX. These tests intentionally exercise the
## small public/stateful seams behind the controls so they stay useful in headless CI.


func _unit(platform_id := "usn_ddg_burke_iii", faction := "BLUE", position := Vector2.ZERO) -> Unit:
	var u := Unit.new()
	u.spec = DataDB.platform(platform_id)
	u.faction = faction
	u.position = position
	u.health = u.spec.health
	for sensor_id in u.spec.sensor_ids:
		u.sensors.append(DataDB.sensor(sensor_id))
	return u


func _track(id: String, identity: String, position: Vector2, status := Track.Status.ACTIVE) -> Track:
	var t := Track.new()
	t.id = id
	t.owner_faction = "BLUE"
	t.identity = identity
	t.position = position
	t.status = status
	return t


func test_command_guide_records_accepted_player_orders_and_preserves_progress() -> void:
	Terrain.clear()
	var guide := CommandGuide.new()
	guide.reset("northern_passage", "BLUE")
	var um := UnitManager.new()
	var air := _unit("usn_helo_mh60r")
	air.flight_state = Unit.FlightState.AIRBORNE
	um.add_unit(air)
	um.order_issued.connect(guide.record_order)
	guide.observe(um)
	assert_eq(guide.step(), 1, "an actual airborne aircraft completes launch")
	var route := Order.patrol_box(Vector2(1, 1), Vector2(3, 3))
	route.execution_accepted = false
	guide.record_order(air, route)
	assert_true(not guide.done.has("patrol"), "an unaccepted order earns no progress")
	var crew := Order.patrol_box(Vector2(1, 1), Vector2(3, 3))
	crew.origin = "crew"
	assert_true(um.issue_order(air, crew))
	assert_true(not guide.done.has("patrol"), "autonomous crew movement is not a practiced command")
	assert_true(um.issue_order(air, route))
	assert_eq(guide.step(), 2)
	guide.record_inspection(_track("T1", "UNKNOWN", Vector2(4, 4)))
	assert_eq(guide.step(), 3)
	guide.skip_step()
	var restored := CommandGuide.new()
	restored.reset("northern_passage", "BLUE")
	restored.restore(guide.to_dict())
	assert_eq(restored.to_dict(), guide.to_dict(), "save restores steps, skips and aircraft association")
	assert_eq(restored.step(), 4)
	assert_true(not restored.done.has("investigate"), "skipping never claims the command was practiced")
	restored.restore({})
	assert_true(not restored.enabled, "old saves do not introduce a guide mid-engagement")
	restored.reset("cold_war_03_carrier", "BLUE")
	restored.restore(guide.to_dict())
	assert_true(not restored.enabled, "other operations cannot enable an unrelated lesson")
	guide.free()
	restored.free()
	um.free()


func test_command_guide_only_completes_return_after_its_investigation_is_classified() -> void:
	Terrain.clear()
	var guide := CommandGuide.new()
	guide.reset("northern_passage", "BLUE")
	var um := UnitManager.new()
	var air := _unit("usn_helo_mh60r")
	air.flight_state = Unit.FlightState.AIRBORNE
	um.add_unit(air)
	guide.aircraft_id = air.id
	guide.target_id = "T1"
	assert_true(um.issue_order(air, Order.patrol_box(Vector2(1, 1), Vector2(3, 3))))
	guide.observe(um)
	assert_true(not guide.done.has("return"), "already being on patrol is not a completed investigation")
	guide.record_classification(air, _track("T2", "NEUTRAL", Vector2(2, 2)), "Contact classified")
	guide.observe(um)
	assert_true(not guide.done.has("return"), "another report does not complete the task")
	guide.record_classification(air, _track("T1", "NEUTRAL", Vector2(2, 2)), "Contact classified")
	guide.observe(um)
	assert_true(guide.done.has("return"), "classification plus resumed station closes the command loop")
	guide.free()
	um.free()


func test_command_guide_handles_unresolved_reports_recovery_and_torpedoes() -> void:
	var guide := CommandGuide.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(guide)
	guide.reset("northern_passage", "BLUE")
	var um := UnitManager.new()
	var air := _unit("usn_helo_mh60r")
	air.flight_state = Unit.FlightState.AIRBORNE
	um.add_unit(air)
	guide.aircraft_id = air.id
	guide.done.assign(["launch", "patrol", "inspect"])
	var report := _track("T1", "UNKNOWN", Vector2(20, 1))
	report.bearing_only = true
	guide.refresh(um, GameOptions.classic(), false, report)
	assert_true(guide._body.text.contains("range unresolved") and guide._body.text.contains("skip"), "no demand to investigate a bearing-only report")
	assert_eq(TacticalMap.default_contact_verb(report), "", "cursor opens the explanatory menu instead of promising an impossible order")
	guide.refresh(um, GameOptions.classic(), true, report, true)
	assert_true(guide._body.text.contains("Torpedo") and not guide._body.text.contains("press X"), "missile intercept guidance is not given for torpedoes")
	guide.skip_step()
	var recovery := Order.return_to_base()
	guide.record_order(air, recovery)
	guide.observe(um)
	assert_true(not guide.done.has("return"), "ordering recovery does not claim a safe landing")
	air.flight_state = Unit.FlightState.TURNAROUND
	guide.observe(um)
	assert_true(guide.done.has("return"), "actual deck recovery closes the alternate lesson")
	guide.free()
	um.free()


func test_priority_tracks_rank_identity_freshness_distance_and_id() -> void:
	var reference := _unit()
	var unknown_near := _track("T1001", "UNKNOWN", Vector2(1, 0))
	var hostile_stale := _track("T1002", "HOSTILE", Vector2(2, 0), Track.Status.STALE)
	var hostile_far := _track("T1004", "HOSTILE", Vector2(40, 0))
	var hostile_near_b := _track("T1003", "HOSTILE", Vector2(5, 0))
	var hostile_near_a := _track("T1000", "HOSTILE", Vector2(-5, 0))
	var tracks := [unknown_near, hostile_stale, hostile_far, hostile_near_b, hostile_near_a]
	tracks.sort_custom(func(a: Track, b: Track) -> bool: return TacticalMap._track_precedes(a, b, reference))
	assert_eq(tracks, [hostile_near_a, hostile_near_b, hostile_far, hostile_stale, unknown_near], "priority is hostile, fresh, near, then stable id")


func test_priority_track_cycle_selects_centers_and_wraps() -> void:
	var reference := _unit()
	var manager := TrackManager.new()
	var first := _track("T1001", "HOSTILE", Vector2(4, 1))
	var second := _track("T1002", "UNKNOWN", Vector2(8, 2))
	manager._tracks["BLUE"] = [second, first]
	var map := TacticalMap.new()
	map.track_manager = manager
	map.selected = [reference]
	assert_eq(map.cycle_priority_track(), first, "first cycle chooses the highest-priority contact")
	assert_eq(map.selected_track, first)
	assert_eq(map.center_nm, first.position, "cycling also recovers the contact on the plot")
	assert_eq(map.cycle_priority_track(), second, "next cycle advances through the sorted picture")
	assert_eq(map.cycle_priority_track(), first, "cycling wraps at the end")
	assert_eq(map.cycle_priority_track(-1), second, "reverse cycling wraps in the other direction")
	map.free()
	manager.free()


func test_regional_map_transform_round_trips_with_offset_theatre() -> void:
	var simulation := Simulation.new()
	simulation.map_center = Vector2(320, -175)
	simulation.map_extent_nm = 480.0
	var map := TacticalMap.new()
	map.simulation = simulation
	var regional := RegionalMap.new()
	regional.map = map
	regional.size = Vector2(288, 288)
	for world in [Vector2(320, -175), Vector2(410, -80), Vector2(210, -290)]:
		var recovered := regional.regional_to_world(regional.world_to_regional(world))
		assert_near(recovered.x, world.x, 0.001, "regional map preserves world x")
		assert_near(recovered.y, world.y, 0.001, "regional map preserves world y")
	assert_eq(regional.world_to_regional(Vector2(320, -175)), Vector2(144, 144), "the theatre centre is the pane centre")
	var half := regional.wanted_extent_nm() * 0.5
	assert_near(regional.world_to_regional(Vector2(320, -175 + half)).y, 0.0, 0.001, "the pane's extent spans the square pane, north up")
	assert_true(regional.wanted_extent_nm() >= 480.0, "and holds the whole theatre")
	regional.free()
	map.free()
	simulation.free()


func test_tactical_map_layer_toggles_return_and_store_the_new_state() -> void:
	var map := TacticalMap.new()
	assert_true(map.toggle_layer("sensors"), "sensor rings turn on")
	assert_true(map.show_rings)
	assert_true(not map.toggle_layer("sensors"), "sensor rings turn back off")
	assert_true(not map.show_rings)
	assert_true(not map.toggle_layer("leaders"), "velocity leaders start on (Shift+V) and turn off")
	assert_true(not map.show_leaders)
	assert_true(map.toggle_layer("vectors"), "the old vectors name is the same switch")
	assert_true(map.show_leaders)
	assert_true(not map.toggle_layer("track_numbers"), "track numbers start on (Shift+K) and turn off")
	assert_true(not map.show_track_numbers)
	assert_true(map.toggle_layer("tags"), "tags start off (Shift+I) and turn on")
	assert_true(map.show_tags)
	assert_true(not map.toggle_layer("routes"), "PIM legs start on and turn off")
	assert_true(not map.toggle_layer("trails"), "trails start on and turn off")
	assert_true(not map.show_trails)
	assert_true(not map.toggle_layer("terrain"), "relief shading (F6) starts on and turns off")
	assert_true(not map.show_terrain)
	assert_true(map.toggle_layer("relief"), "relief is the same switch under its own name")
	assert_true(map.show_terrain)
	assert_true(map.toggle_layer("range_grid"), "range grid turns on")
	assert_true(map.toggle_layer("key"), "symbol key turns on")
	assert_true(map.toggle_layer("graticule"), "the graticule starts off and turns on")
	assert_true(map.show_graticule)
	assert_true(not map.toggle_layer("latlon"), "the lat/long readout starts on (Ctrl+L) and turns off")
	assert_true(not map.show_latlon)
	assert_true(not map.toggle_layer("scale"), "the scale bar starts on (Ctrl+S) and turns off")
	assert_true(not map.show_scale)
	for filter in ["hostiles", "allied", "neutrals", "unknowns"]:
		assert_true(map.has_layer(filter), "%s are shown by default" % filter)
	assert_true(not map.toggle_layer("threats"), "the CDS menu's Threats filter hides hostiles")
	assert_true(not map.has_layer("hostiles"))
	assert_true(map.has_layer("tags") and map.has_layer("leaders") and not map.has_layer("track_numbers"), "has_layer reports the state menus check")
	assert_true(not map.toggle_layer("no_such_layer") and not map.has_layer("no_such_layer"), "an unknown layer is off and stays off")
	map.free()


func test_symbol_mode_cycles_ntds_small_medium_large() -> void:
	var map := TacticalMap.new()
	assert_eq(map.symbol_mode, TacticalMap.SymbolMode.NTDS, "NTDS symbols by default")
	assert_eq(map.cycle_symbol_mode(), TacticalMap.SymbolMode.SMALL)
	assert_eq(map.symbol_mode_name(), "Small")
	assert_eq(map.cycle_symbol_mode(), TacticalMap.SymbolMode.MEDIUM)
	assert_eq(map.cycle_symbol_mode(), TacticalMap.SymbolMode.LARGE)
	assert_eq(map.cycle_symbol_mode(), TacticalMap.SymbolMode.NTDS, "Tab wraps back to NTDS")
	map.set_symbol_mode(2)
	assert_eq(map.symbol_mode_name(), "Medium", "the CDS menu can pick a mode directly")
	map.free()


func test_move_mode_requires_own_selection_and_cancel_is_idempotent() -> void:
	var map := TacticalMap.new()
	map.set_move_mode(true)
	assert_eq(map.interaction_mode, TacticalMap.InteractionMode.SELECT, "empty selection cannot arm a move")
	map.selected = [_unit("usn_ddg_burke_iii", "RED")]
	map.set_move_mode(true)
	assert_eq(map.interaction_mode, TacticalMap.InteractionMode.SELECT, "an opposing unit is not controllable")
	map.selected = [_unit()]
	map.set_move_mode(true)
	assert_eq(map.interaction_mode, TacticalMap.InteractionMode.MOVE, "own selection arms plot-move")
	assert_true(map.cancel_interaction_mode(), "first cancel exits an active interaction")
	assert_eq(map.interaction_mode, TacticalMap.InteractionMode.SELECT)
	assert_true(not map.cancel_interaction_mode(), "second cancel has nothing left to consume")
	map.free()


func test_multi_selection_focus_fits_the_group_with_margin() -> void:
	var map := TacticalMap.new()
	map.size = Vector2(1200, 800)
	map.selected = [
		_unit("usn_ddg_burke_iii", "BLUE", Vector2(-10, 0)),
		_unit("usn_ddg_burke_iii", "BLUE", Vector2(30, 20)),
	]
	map.center_on_selection()
	var chart := map.unobstructed_chart_rect()
	assert_eq(chart, Rect2(Vector2.ZERO, map.size), "the chart has no chrome: the whole control is chart")
	var visual_center := map.world_to_screen(Vector2(10, 10))
	assert_near(visual_center.x, chart.get_center().x, 0.001, "group centre lands in the unobstructed chart centre")
	assert_near(visual_center.y, chart.get_center().y, 0.001, "group centre lands in the chart centre")
	assert_near(map.ppn, minf(chart.size.x, chart.size.y) / 60.0, 0.001, "group focus includes the documented margin inside safe bounds")
	for u: Unit in map.selected:
		var screen := map.world_to_screen(u.position)
		assert_true(chart.has_point(screen), "every selected unit remains visible outside persistent controls")
	map.show_key = true
	map.center_on(Vector2(10, 10))
	var key_safe_focus := map.world_to_screen(Vector2(10, 10))
	assert_true(map.unobstructed_chart_rect().has_point(key_safe_focus), "focus remains inside safe bounds with the symbol key open")
	assert_true(not map._symbol_key_rect().has_point(key_safe_focus), "the symbol key cannot cover fitted content")
	map.free()


func test_selection_mutations_normalize_move_and_follow_state() -> void:
	var map := TacticalMap.new()
	var a := _unit()
	var b := _unit("usn_ddg_burke_iii", "BLUE", Vector2(5, 0))
	map.select_units([a])
	map.set_move_mode(true)
	map.set_follow_selection(true)
	assert_eq(map.interaction_mode, TacticalMap.InteractionMode.MOVE)
	assert_true(map.follow_selection)
	map.select_units([])
	assert_eq(map.interaction_mode, TacticalMap.InteractionMode.SELECT, "deselecting the last platform cancels Plot Move")
	assert_true(not map.follow_selection, "an empty selection cannot leave latent follow state")
	map.select_units([a])
	map.set_follow_selection(true)
	map.select_units([a, b])
	assert_true(not map.follow_selection, "a group without a target cannot retain single-platform follow")
	map.free()


func test_manual_recovery_clears_follow_and_uses_safe_chart_center() -> void:
	var map := TacticalMap.new()
	map.size = Vector2(1200, 800)
	var unit := _unit()
	map.select_units([unit])
	map.set_follow_selection(true)
	map.center_on(Vector2(25, -10))
	assert_true(not map.follow_selection, "manual recenter exits follow instead of snapping back")
	var focused := map.world_to_screen(Vector2(25, -10))
	assert_near(focused.x, map.unobstructed_chart_rect().get_center().x, 0.001)
	assert_near(focused.y, map.unobstructed_chart_rect().get_center().y, 0.001)
	map.free()


func test_drag_release_at_the_chart_edge_clears_the_input_latch() -> void:
	var map := TacticalMap.new()
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(map)
	map.size = Vector2(1000, 700)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = Vector2(400, 300)
	map._gui_input(press)
	assert_eq(map._drag_mode, TacticalMap.DragMode.PAN)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	release.position = Vector2(400, -12)
	map._gui_input(release)
	assert_eq(map._drag_mode, TacticalMap.DragMode.NONE, "release past the chart's top edge still ends the owned drag")
	map.free()


## A map in the tree with a ship at (-20, 0) nm, a hostile contact at (20, 0) nm and a waypoint
## at (0, 20) nm; 4 px/nm about the origin, so world (x, y) is at pixel (500 + 4x, 350 - 4y).
func _right_click_fixture() -> Dictionary:
	Terrain.clear()
	Bathymetry.clear()
	var manager := UnitManager.new()
	var ship := _unit("usn_ddg_burke_iii", "BLUE", Vector2(-20, 0))
	ship.waypoints.append(Vector2(0, 20))
	manager.add_unit(ship)
	var tracks := TrackManager.new()
	var hostile := _track("T1007", "HOSTILE", Vector2(20, 0))
	hostile.domain = "surface"
	hostile.classification = Track.Classification.CLASS_KNOWN
	var unknown := _track("T1008", "UNKNOWN", Vector2(20, 20))
	tracks._tracks["BLUE"] = [hostile, unknown]
	var map := TacticalMap.new()
	map.unit_manager = manager
	map.track_manager = tracks
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(map)
	map.size = Vector2(1000, 700)
	map.center_nm = Vector2.ZERO
	map.ppn = 4.0
	var events := {"move": [], "context": [], "engage": [], "delete": [], "attack": [], "investigate": []}
	map.move_order_requested.connect(func(w: Vector2, append: bool) -> void: events["move"].append([w, append]))
	map.context_menu_requested.connect(func(at: Vector2, ctx: Dictionary) -> void: events["context"].append([at, ctx]))
	map.engage_requested.connect(func(t: Track) -> void: events["engage"].append(t))
	map.attack_requested.connect(func(t: Track) -> void: events["attack"].append(t))
	map.investigate_requested.connect(func(t: Track) -> void: events["investigate"].append(t))
	map.waypoint_delete_requested.connect(func(u: Unit, i: int) -> void: events["delete"].append([u, i]))
	return {"map": map, "manager": manager, "tracks": tracks, "ship": ship, "hostile": hostile, "unknown": unknown, "events": events}


func _free_fixture(f: Dictionary) -> void:
	(f["map"] as Node).free()
	(f["manager"] as Node).free()
	(f["tracks"] as Node).free()
	Terrain.clear()


func _right_click(map: TacticalMap, at: Vector2, shift := false, ctrl := false, drag_to := Vector2.INF) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = at
	map._gui_input(press)
	if drag_to != Vector2.INF:
		var motion := InputEventMouseMotion.new()
		motion.position = drag_to
		motion.relative = drag_to - at
		map._gui_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	release.position = drag_to if drag_to != Vector2.INF else at
	release.shift_pressed = shift
	release.ctrl_pressed = ctrl
	map._gui_input(release)


func test_right_click_on_open_water_transits_the_hooked_unit_there() -> void:
	var f := _right_click_fixture()
	var map: TacticalMap = f["map"]
	var events: Dictionary = f["events"]
	map.select_units([f["ship"]])
	_right_click(map, Vector2(500, 450))
	assert_eq(events["move"].size(), 1, "a right-click on water is a MOVE order at once")
	assert_eq(events["move"][0][0], Vector2(0, -25), "to the world point under the cursor")
	assert_true(not events["move"][0][1], "a plain right-click replaces the route")
	_right_click(map, Vector2(520, 450), true)
	assert_true(events["move"][1][1], "Shift+right-click appends a leg")
	assert_true(events["context"].is_empty(), "no menu when the chart acted by itself")
	assert_eq(map._drag_mode, TacticalMap.DragMode.NONE, "the right press that began a pan is released")
	_right_click(map, Vector2(500, 450), false, false, Vector2(560, 470))
	assert_eq(events["move"].size(), 2, "a right-drag pans and orders nothing")
	assert_true(events["context"].is_empty(), "and asks for no menu")
	_free_fixture(f)


func test_right_click_on_a_hostile_attacks_and_shift_asks_for_the_menu() -> void:
	var f := _right_click_fixture()
	var map: TacticalMap = f["map"]
	var events: Dictionary = f["events"]
	map.select_units([f["ship"]])
	_right_click(map, Vector2(580, 352))
	assert_eq(map.selected_track, f["hostile"], "the contact is hooked as the order goes")
	assert_eq(events["attack"], [f["hostile"]], "a bare right-click on a hostile is the standing attack, the classic display's default")
	assert_true(events["context"].is_empty(), "with no menu to go through")
	assert_true(events["move"].is_empty(), "a contact is never a move destination")
	_right_click(map, Vector2(580, 352), true)
	assert_eq(events["attack"].size(), 1, "Shift does not attack")
	assert_eq(events["context"].size(), 1, "Shift+right-click asks for the contact menu")
	var ctx: Dictionary = events["context"][0][1]
	assert_eq(ctx["kind"], "track")
	assert_eq(ctx["track"], f["hostile"])
	assert_eq(events["context"][0][0], Vector2(580, 352), "the menu opens where the click was")
	assert_true(ctx.has("viewport_pos"), "with a position to place a popup in the viewport")
	_right_click(map, Vector2(580, 352), false, true)
	assert_eq(events["engage"], [f["hostile"]], "Ctrl/Cmd+right-click still fires the lined-up weapon at once")
	assert_eq(events["context"].size(), 1, "without a menu")
	assert_eq(events["attack"].size(), 1, "and without a standing attack")
	_free_fixture(f)


func test_right_click_on_an_unknown_investigates_and_needs_a_hooked_platform() -> void:
	var f := _right_click_fixture()
	var map: TacticalMap = f["map"]
	var events: Dictionary = f["events"]
	_right_click(map, Vector2(580, 352))
	assert_true(events["attack"].is_empty(), "nothing hooked: nothing to attack with")
	assert_eq(events["context"].size(), 1, "so the right-click asks for the menu")
	assert_eq(map.selected_track, f["hostile"], "and hooks the contact for it")
	map.select_units([f["ship"]])
	_right_click(map, Vector2(580, 270))
	assert_eq(events["investigate"], [f["unknown"]], "a bare right-click on an unidentified contact investigates it")
	assert_eq(events["context"].size(), 1, "with no menu")
	(f["unknown"] as Track).identity = "NEUTRAL"
	(f["unknown"] as Track).classification = Track.Classification.CLASS_KNOWN
	_right_click(map, Vector2(580, 270))
	assert_eq(events["investigate"].size(), 1, "a neutral is neither attacked nor investigated")
	assert_eq(events["context"].size(), 2, "it gets the menu")
	assert_eq(TacticalMap.default_contact_verb(null), "")
	var lost := _track("T1009", "HOSTILE", Vector2.ZERO, Track.Status.LOST)
	assert_eq(TacticalMap.default_contact_verb(lost), "", "a lost hostile is not attacked blind")
	_free_fixture(f)


func test_cursor_says_what_a_right_click_would_do() -> void:
	var f := _right_click_fixture()
	var map: TacticalMap = f["map"]
	assert_eq(map.hover_cursor_shape(Vector2(580, 352)), Control.CURSOR_ARROW, "nothing hooked: the arrow")
	map.select_units([f["ship"]])
	assert_eq(map.hover_cursor_shape(Vector2(580, 352)), Control.CURSOR_CROSS, "a cross over a hostile the hooked ship would attack")
	assert_eq(map.hover_cursor_shape(Vector2(580, 270)), Control.CURSOR_HELP, "a query over an unknown it would investigate")
	assert_eq(map.hover_cursor_shape(Vector2(700, 600)), Control.CURSOR_ARROW, "the arrow over water")
	assert_eq(map.hover_cursor_shape(Vector2(421, 349)), Control.CURSOR_ARROW, "and over your own platform")
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(580, 352)
	map._gui_input(motion)
	assert_eq(map.mouse_default_cursor_shape, Control.CURSOR_CROSS, "moving the mouse sets the chart's cursor")
	assert_true(TacticalMap.contact_hint("attack").contains("Right-click to attack"), "the hover card says the same thing")
	assert_true(TacticalMap.contact_hint("investigate").contains("Right-click to investigate"))
	assert_true(TacticalMap.contact_hint("").contains("contact menu"))
	_free_fixture(f)


func test_right_click_on_an_own_unit_hooks_it_for_the_orders_menu() -> void:
	var f := _right_click_fixture()
	var map: TacticalMap = f["map"]
	var events: Dictionary = f["events"]
	_right_click(map, Vector2(421, 349))
	assert_eq(map.selected, [f["ship"]], "the unit under the cursor is hooked")
	assert_eq(events["context"].size(), 1)
	assert_eq(events["context"][0][1]["kind"], "own_unit")
	assert_eq(events["context"][0][1]["unit"], f["ship"])
	assert_true(events["move"].is_empty(), "right-clicking the hooked unit is not a move onto itself")
	_free_fixture(f)


func test_right_click_on_a_waypoint_offers_the_leg_instead_of_deleting_it() -> void:
	var f := _right_click_fixture()
	var map: TacticalMap = f["map"]
	var events: Dictionary = f["events"]
	map.select_units([f["ship"]])
	_right_click(map, Vector2(502, 272))
	assert_true(events["delete"].is_empty(), "a bare right-click no longer drops the leg")
	assert_true(events["move"].is_empty(), "nor orders a move onto the waypoint")
	var ctx: Dictionary = events["context"][0][1]
	assert_eq(ctx["kind"], "waypoint")
	assert_eq(ctx["waypoint_unit"], f["ship"])
	assert_eq(ctx["waypoint_index"], 0)
	map.request_waypoint_delete(ctx["waypoint_unit"], ctx["waypoint_index"])
	assert_eq(events["delete"], [[f["ship"], 0]], "the shell's Delete leg goes out on the old signal")
	map.request_waypoint_delete(f["ship"], 3)
	assert_eq(events["delete"].size(), 1, "a leg that does not exist is not requested")
	_free_fixture(f)


func test_right_click_with_nothing_hooked_or_on_land_asks_for_a_menu() -> void:
	var f := _right_click_fixture()
	var map: TacticalMap = f["map"]
	var events: Dictionary = f["events"]
	_right_click(map, Vector2(500, 450))
	assert_eq(events["context"][0][1]["kind"], "water", "nothing hooked: the CDS menu, over water")
	assert_eq(events["context"][0][1]["world_pos"], Vector2(0, -25))
	assert_true(events["move"].is_empty())
	Terrain.load_from({"terrain": {"land": [{"id": "cape", "name": "Cape", "elevation_m": 50.0, "points_nm": [[-5, -40], [5, -40], [5, -30], [-5, -30]]}]}})
	map.select_units([f["ship"]])
	_right_click(map, Vector2(500, 490))
	assert_true(events["move"].is_empty(), "a hull is not ordered onto land")
	assert_eq(events["context"][1][1]["kind"], "empty", "land with nothing on it")
	var jet := _unit("usn_fighter_f35c", "BLUE", Vector2(-10, 10))
	jet.flight_state = Unit.FlightState.AIRBORNE
	(f["manager"] as UnitManager).add_unit(jet)
	map.select_units([jet])
	_right_click(map, Vector2(500, 490))
	assert_eq(events["move"].size(), 1, "an aircraft transits over land")
	_free_fixture(f)


func test_move_mode_right_click_still_cancels_the_tool() -> void:
	var f := _right_click_fixture()
	var map: TacticalMap = f["map"]
	var events: Dictionary = f["events"]
	map.select_units([f["ship"]])
	map.set_move_mode(true)
	_right_click(map, Vector2(500, 450))
	assert_eq(map.interaction_mode, TacticalMap.InteractionMode.SELECT, "right-click leaves Plot Move")
	assert_true(events["move"].is_empty() and events["context"].is_empty(), "and does nothing else")
	_free_fixture(f)


func test_context_classification_reads_the_chart_under_the_cursor() -> void:
	var f := _right_click_fixture()
	var map: TacticalMap = f["map"]
	assert_eq(map.context_at(Vector2(421, 349))["kind"], "own_unit")
	assert_eq(map.context_at(Vector2(580, 352))["kind"], "track")
	assert_eq(map.context_at(Vector2(502, 272))["kind"], "waypoint")
	assert_eq(map.context_at(Vector2(700, 600))["kind"], "water")
	var water := map.context_at(Vector2(700, 600))
	assert_true(water["unit"] == null and water["track"] == null and water["waypoint_unit"] == null and water["waypoint_index"] == -1, "unused fields are empty")
	map.toggle_layer("hostiles")
	assert_eq(map.context_at(Vector2(580, 352))["kind"], "water", "a filtered contact cannot be clicked")
	map.toggle_layer("hostiles")
	var near_both := map.context_at(Vector2(420, 350))
	(f["ship"] as Unit).position = Vector2(20, 1)
	assert_eq(map.context_at(Vector2(580, 350))["kind"], "own_unit", "an own unit wins over a contact under it")
	assert_eq(near_both["kind"], "own_unit")
	Terrain.load_from({"terrain": {"land": [{"id": "isle", "name": "Isle", "elevation_m": 50.0, "points_nm": [[40, 40], [60, 40], [60, 60], [40, 60]]}]}})
	assert_eq(map.context_at(map.world_to_screen(Vector2(50, 50)))["kind"], "empty", "land the chart shows")
	_free_fixture(f)


func test_stowed_aircraft_and_unsupported_system_orders_are_refused() -> void:
	var aircraft := _unit("usn_fighter_f35c")
	assert_true(not aircraft.is_engageable())
	var map := TacticalMap.new()
	map.select_units([aircraft])
	map.set_move_mode(true)
	assert_eq(map.interaction_mode, TacticalMap.InteractionMode.SELECT, "a deck-stowed aircraft cannot arm Plot Move")
	var manager := UnitManager.new()
	manager.add_unit(aircraft)
	assert_true(not manager.issue_order(aircraft, Order.move(Vector2(10, 5))), "the command layer also refuses a stowed route")
	assert_true(aircraft.waypoints.is_empty())
	var ship := _unit()
	ship.sensors.clear()
	manager.add_unit(ship)
	assert_true(not manager.issue_order(ship, Order.activate_radar()), "a platform without radar is not counted as accepting radar")
	assert_true(not manager.issue_order(ship, Order.active_sonar()), "a platform without sonar is not counted as accepting sonar")
	assert_true(not manager.issue_order(ship, Order.engage(_track("T2000", "HOSTILE", Vector2(5, 0)), "missing_weapon", 1)), "a platform without the selected weapon is not counted as accepting fire")
	map.free()
	manager.free()


func test_move_preview_distinguishes_ship_aircraft_and_partial_land_orders() -> void:
	Terrain.load_from({"terrain": {"land": [{"id": "island", "name": "Island", "elevation_m": 50.0, "points_nm": [[-2, -2], [2, -2], [2, 2], [-2, 2]]}]}})
	var ship := _unit("usn_ddg_burke_iii", "BLUE", Vector2(-10, 0))
	var aircraft := _unit("usn_fighter_f35c", "BLUE", Vector2(-10, 2))
	aircraft.flight_state = Unit.FlightState.AIRBORNE
	var map := TacticalMap.new()
	map.select_units([ship, aircraft])
	var partial := map._move_acceptance(Vector2.ZERO)
	assert_eq(partial["total"], 2)
	assert_eq(partial["accepted"], 1, "only the airborne platform accepts a land endpoint")
	map.select_units([aircraft])
	assert_eq(map._move_acceptance(Vector2.ZERO)["accepted"], 1, "aircraft may legally route over land")
	map.select_units([ship])
	assert_eq(map._move_acceptance(Vector2.ZERO)["accepted"], 0, "a ship must choose water")
	map.free()
	Terrain.clear()


func test_contact_cycle_uses_the_visible_filtered_track_file() -> void:
	var reference := _unit()
	var air := _track("T3001", "HOSTILE", Vector2(4, 0))
	air.domain = "air"
	var surface := _track("T3002", "HOSTILE", Vector2(3, 0))
	surface.domain = "surface"
	var manager := TrackManager.new()
	manager._tracks["BLUE"] = [surface, air]
	var map := TacticalMap.new()
	map.track_manager = manager
	map.select_units([reference])
	var panel := ContactPanel.new()
	panel.track_manager = manager
	panel.map = map
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(panel)
	panel._filter = "AIR"
	panel.refresh()
	assert_eq(panel.visible_track_count(), 1)
	assert_eq(panel.cycle_visible_track(1), air)
	assert_eq(map.selected_track, air, "shortcut/button cycling cannot select a row hidden by the active filter")
	panel.free()
	map.free()
	manager.free()


func test_orders_panel_selection_state_reports_none_off_on_and_mixed() -> void:
	var panel := OrdersPanel.new()
	assert_eq(panel._selection_state("radar"), -1, "no capable selection is unavailable")
	var a := _unit()
	var b := _unit()
	panel._units = [a, b]
	assert_eq(panel._selection_state("radar"), 1, "both radars begin on")
	b.radar_on = false
	assert_eq(panel._selection_state("radar"), 2, "different radar settings report mixed")
	a.radar_on = false
	assert_eq(panel._selection_state("radar"), 0, "both radars off is off")
	assert_eq(panel._selection_state("sonar"), 0, "both active sonars begin off")
	b.active_sonar_on = true
	assert_eq(panel._selection_state("sonar"), 2, "different sonar settings report mixed")
	a.active_sonar_on = true
	assert_eq(panel._selection_state("sonar"), 1, "both active sonars on is on")
	assert_eq(panel._selection_state("emcon"), 0, "both units begin emissions-free")
	b.emcon = Unit.Emcon.SILENT
	assert_eq(panel._selection_state("emcon"), 2, "different EMCON settings report mixed")
	a.emcon = Unit.Emcon.SILENT
	assert_eq(panel._selection_state("emcon"), 1, "both silent is on")
	panel.free()


func test_command_palette_filters_all_terms_and_only_activates_enabled_rows() -> void:
	var palette := CommandPalette.new()
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(palette)
	palette.set_actions([
		{"id": "radar", "label": "Activate radar", "description": "Radiate selected ships", "shortcut": "R", "enabled": true, "state": "silent"},
		{"id": "weapons", "label": "Weapons free", "description": "Change doctrine", "shortcut": "W", "enabled": false, "reason": "No platform selected"},
		{"id": "sonar", "label": "Active sonar", "description": "Ping selected escorts", "shortcut": "P", "enabled": true},
		{"id": "", "label": "Invalid command"},
	])
	palette._filter("radar silent")
	assert_eq(palette._filtered_actions.size(), 1, "every search term must match")
	assert_eq(palette._filtered_actions[0]["id"], "radar")
	palette._filter("no platform")
	assert_eq(palette._filtered_actions.size(), 1, "disabled reasons are searchable")
	assert_true(palette._list.is_item_disabled(0), "unavailable commands expose disabled semantics")
	assert_true(palette._list.get_item_text(0).contains("No platform selected"), "the unavailable reason remains readable without activating the row")
	var fired: Array[String] = []
	palette.action_requested.connect(func(id: String) -> void: fired.append(id))
	palette._activate_index(0)
	assert_true(fired.is_empty(), "disabled rows cannot run")
	palette._filter("active sonar")
	palette._activate_index(0)
	assert_eq(fired, ["sonar"], "enabled row emits its stable action id")
	palette.free()


func test_order_receipt_uses_the_synchronous_execution_result() -> void:
	var manager := UnitManager.new()
	var ship := _unit()
	manager.add_unit(ship)
	manager.order_issued.connect(func(_unit: Unit, routed: Order) -> void: routed.execution_accepted = false)
	assert_true(not manager.issue_order(ship, Order.set_roe(Unit.Roe.TIGHT)), "the caller sees a downstream refusal instead of a false accepted receipt")
	manager.free()


func test_stowed_aircraft_cannot_arm_the_persistent_move_action() -> void:
	var aircraft := _unit("usn_fighter_f35c")
	var panel := OrdersPanel.new()
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(panel)
	aircraft.flight_state = Unit.FlightState.AIRBORNE
	panel.set_units([aircraft], true, true)
	panel.set_move_mode(true)
	assert_true(not panel._move_btn.disabled, "Plot Move is available while the selected aircraft is airborne")
	assert_true(panel._move_btn.button_pressed)
	aircraft.flight_state = Unit.FlightState.STOWED
	panel._sync_live_eligibility()
	panel._sync_quick_actions()
	assert_true(panel._move_btn.disabled, "Plot Move is disabled for a deck-stowed aircraft")
	assert_true(not panel._move_btn.button_pressed, "landing clears the stale armed state without requiring reselection")
	var station := _unit("shore_air_station")
	panel.set_units([station], true, false)
	assert_true(not panel._heading.editable, "stationary installations cannot edit a course")
	for button: Button in panel._movement_buttons:
		assert_true(button.disabled, "stationary installations cannot issue detailed movement orders")
	var carrier := _unit("usn_cvn_ford")
	var deck_aircraft := _unit("usn_fighter_f35c")
	deck_aircraft.flight_state = Unit.FlightState.TURNAROUND
	carrier.embarked.append(deck_aircraft)
	panel.set_units([carrier], true, true)
	assert_true(not panel._launch_btn.visible, "launch stays hidden while the selected deck has no ready aircraft")
	deck_aircraft.flight_state = Unit.FlightState.STOWED
	panel._sync_live_eligibility()
	assert_true(panel._launch_btn.visible, "launch appears as soon as deck readiness changes, without reselection")
	panel.free()
