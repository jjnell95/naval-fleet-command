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


func test_tactical_overview_transform_round_trips_with_offset_theatre() -> void:
	var simulation := Simulation.new()
	simulation.map_center = Vector2(320, -175)
	simulation.map_extent_nm = 480.0
	var map := TacticalMap.new()
	map.simulation = simulation
	var overview := TacticalOverview.new()
	overview.map = map
	overview.size = Vector2(236, 158)
	for world in [Vector2(320, -175), Vector2(410, -80), Vector2(210, -290)]:
		var recovered := overview.overview_to_world(overview.world_to_overview(world))
		assert_near(recovered.x, world.x, 0.001, "overview preserves world x")
		assert_near(recovered.y, world.y, 0.001, "overview preserves world y")
	overview.free()
	map.free()
	simulation.free()


func test_tactical_map_layer_toggles_return_and_store_the_new_state() -> void:
	var map := TacticalMap.new()
	assert_true(map.toggle_layer("sensors"), "sensor rings turn on")
	assert_true(map.show_rings)
	assert_true(not map.toggle_layer("sensors"), "sensor rings turn back off")
	assert_true(not map.show_rings)
	assert_true(map.toggle_layer("vectors"), "vectors turn on")
	assert_true(map.show_vectors)
	assert_true(not map.toggle_layer("trails"), "trails start on and turn off")
	assert_true(not map.show_trails)
	assert_true(not map.toggle_layer("terrain"), "terrain starts on and turns off")
	assert_true(map.toggle_layer("range_grid"), "range grid turns on")
	assert_true(map.toggle_layer("key"), "symbol key turns on")
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
	var visual_center := map.world_to_screen(Vector2(10, 10))
	assert_near(visual_center.x, chart.get_center().x, 0.001, "group centre lands in the unobstructed chart centre")
	assert_near(visual_center.y, chart.get_center().y, 0.001, "group centre clears header and command overlays")
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


func test_drag_release_over_header_clears_the_input_latch() -> void:
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
	release.position = Vector2(400, 4)
	map._gui_input(release)
	assert_eq(map._drag_mode, TacticalMap.DragMode.NONE, "release over the header still ends the owned drag")
	map.free()


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
