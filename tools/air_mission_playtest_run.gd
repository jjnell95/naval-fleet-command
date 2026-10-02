extends RefCounted
## The M36 command loop through viewport mouse and keyboard input on the real scene: a carrier
## hooked on the chart, Air Operations opened with F3, a combat air patrol chosen and its station
## clicked on the chart, the mission assigned and flown, the Missions tab read back; then an escort
## sent to investigate a real contact with a right-click and brought back to its screen station
## with S. Real sensors and the real deck cycle throughout: no invented contacts, fuel or rounds.

const CARRIER_WATCH := "res://data/scenarios/cold_war_03_carrier.json"
const PASSAGE := "res://data/scenarios/northern_passage.json"

var tree: SceneTree
var main: Main
var checks := {}
var facts := {}
var shots: Array[String] = []
var errors: Logger
var capture := false
var output_dir := "res://work/m36-air"


func run(scene_tree: SceneTree) -> void:
	tree = scene_tree
	capture = OS.get_cmdline_user_args().has("--capture")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			output_dir = argument.trim_prefix("--output-dir=").trim_suffix("/")
	DirAccess.make_dir_recursive_absolute(output_dir)
	CommanderLog.path_override = output_dir.path_join("commander_log.json")  # never the developer's own record
	SaveGame.root_override = output_dir.path_join("saves")  # nor their saved engagements
	for leftover in SaveGame.list_saves():
		DirAccess.remove_absolute(str(leftover["path"]))
	errors = load("res://tests/test_error_log.gd").new()
	OS.add_logger(errors)
	main = load("res://scenes/main/Main.tscn").instantiate()
	tree.root.add_child(main)
	await _frames()
	await _combat_air_patrol()
	await _escort_returns_to_station()
	_finish()


func _combat_air_patrol() -> void:
	main.start_scenario(CARRIER_WATCH)
	await _take_command()
	Debug.log_events = false
	var carrier := _find("USS Dwight D. Eisenhower (CVN 69)")
	if carrier == null:
		checks["1990 carrier operation loads"] = false
		return
	main.map.select_units([carrier])
	main.map.center_on_selection()
	main.map.clear_selection()
	await _frames()
	await _chart_click(carrier.position)
	checks["carrier hooked by a chart click"] = main.map.selected == [carrier]
	await _key(KEY_F3)
	var panel := main._air_operations
	checks["F3 opens Air Operations on the hooked carrier"] = panel.visible and panel._base == carrier and SimClock.paused
	await _click_control(panel._mission_picker)
	await _popup_click(panel._mission_picker.get_popup(), 1 + AirMission.Kind.CAP)
	checks["mission picker sets a combat air patrol"] = panel.mission_kind() == AirMission.Kind.CAP
	var tomcat := panel._type_ids.find("cw90_f14a")
	if tomcat >= 0 and panel._type_picker.selected != tomcat:
		await _click_control(panel._type_picker)
		await _popup_click(panel._type_picker.get_popup(), tomcat)
	checks["Tomcats chosen"] = panel._type_id == "cw90_f14a"
	checks["a section of two by default"] = int(panel._count.value) == 2
	checks["assignment waits for a station"] = panel._launch.disabled and panel._launch_hint.text.contains("station")
	await _click_control(panel._station_button)
	checks["PICK ON CHART hands the chart over"] = not panel.visible and main.map.interaction_mode == TacticalMap.InteractionMode.PICK and main._air_picking
	var station := carrier.position + Vector2(8.0, 30.0)
	await _chart_motion(station)
	await _shot("cap-pick")
	await _chart_click(station)
	var picked: Vector2 = panel._station
	checks["the clicked point becomes the station"] = panel.visible and picked.is_finite() and picked.distance_to(station) < 1.5 and main.map.interaction_mode == TacticalMap.InteractionMode.SELECT
	checks["the dialog states range, bearing and time on station"] = panel._station_label.text.contains("nm") and panel._station_label.text.contains("min on station")
	checks["the station reads in latitude and longitude"] = panel._station_label.text.contains(" N / ") and panel._station_label.text.contains(" E")
	checks["the hint says what launches now"] = not panel._launch.disabled and panel._launch_hint.text.contains("launch now")
	await _click_control(panel._launch)
	var missions := main.simulation.air_mission_manager.active_missions("BLUE")
	var m: AirMission = missions[0] if not missions.is_empty() else null
	checks["ASSIGN MISSION creates the CAP"] = m != null and m.kind == AirMission.Kind.CAP and m.requested == 2
	if m == null:
		return
	checks["two Tomcats on the catapults"] = m.count_in(AirMission.LAUNCHING) == 2
	checks["the Missions tab shows the new mission"] = panel._lower_tabs.current_tab == 1 and panel._missions.get_root() != null and panel._missions.get_root().get_child_count() == 1
	checks["the receipt names what launched"] = panel._receipt.text.contains("Combat air patrol") and panel._receipt.text.contains("launching")
	await _shot("cap-assigned")
	await _click_control(panel._ok)
	checks["Ok resumes at real time"] = not panel.visible and not SimClock.paused and SimClock.speed_index == 0
	checks["Ok after ASSIGN does not assign the mission twice"] = main.simulation.air_mission_manager.active_missions("BLUE").size() == 1 and m.launched_total == 2
	SimClock.set_paused(true)
	SimClock.advance(420.0)
	var on_station := m.count_in(AirMission.ON_STATION)
	facts["cap_summary_after_7_min"] = m.summary()
	checks["the section reaches its CAP station"] = on_station == 2
	for a in m.aircraft:
		checks["%s orders line names the CAP station" % a.callsign] = DataDisplay.orders_text(a, main.simulation.weapon_manager).begins_with("CAP station")
	main.map.select_units([m.aircraft[0]])
	main.map.center_on_selection()
	await _frames()
	await _shot("cap-on-station")
	await _key(KEY_F3)
	panel._lower_tabs.current_tab = 1
	await _frames()
	var rows := panel._missions.get_root().get_child(0).get_children() if panel._missions.get_root().get_child_count() > 0 else []
	var board_states := PackedStringArray()
	for row: TreeItem in rows:
		board_states.append(row.get_text(1))
	facts["board_states"] = board_states
	checks["the board reads ON STATION for each airframe"] = board_states.size() == 2 and Array(board_states).all(func(s: String) -> bool: return s == AirMission.ON_STATION)
	await _shot("cap-board")
	await _key(KEY_ESCAPE)
	checks["Escape closes Air Operations"] = not panel.visible
	await _save_and_reload(m)


## Ctrl+Shift+S, carry on, Ctrl+Shift+L: the battle, the air mission, the journal and the chart's
## own track numbers come back as they were at the save, and the saved engagements list shows it.
func _save_and_reload(m: AirMission) -> void:
	var saved_at := SimClock.sim_time
	var journal := main.radio.journal.size()
	var summary := m.summary()
	var tomcat: Unit = m.aircraft[0]
	var tomcat_at := tomcat.position
	var number := main.map.track_number_text(tomcat)
	await _key(KEY_S, true, true)
	checks["Ctrl+Shift+S writes the quicksave"] = FileAccess.file_exists(SaveGame.slot_path(SaveGame.QUICKSAVE))
	SimClock.advance(180.0)
	checks["the battle moved on after the save"] = SimClock.sim_time > saved_at and tomcat.position != tomcat_at
	await _key(KEY_L, true, true)
	var missions := main.simulation.air_mission_manager.active_missions("BLUE")
	var restored: AirMission = missions[0] if not missions.is_empty() else null
	checks["Ctrl+Shift+L returns to the saved tick"] = SimClock.sim_time == saved_at and SimClock.paused
	checks["the CAP comes back with its airframes"] = restored != null and restored.summary() == summary
	var tomcat_back: Unit = null
	for u in main.simulation.unit_manager.units:
		if u.id == tomcat.id:
			tomcat_back = u
	checks["an airframe is where it was at the save"] = tomcat_back != null and tomcat_back.position == tomcat_at and restored != null and restored.aircraft.has(tomcat_back)
	checks["the observed journal is the one at the save"] = main.radio.journal.size() == journal
	checks["own track numbers are kept"] = tomcat_back != null and main.map.track_number_text(tomcat_back) == number
	await _shot("after-quickload")
	await _key(KEY_O, true, true)
	checks["Ctrl+Shift+O lists the saved engagements"] = main._saves.visible and main._saves._list.get_root().get_child_count() >= 1
	await _shot("saved-engagements")
	await _key(KEY_ESCAPE)
	checks["Escape closes the list"] = not main._saves.visible


func _escort_returns_to_station() -> void:
	main.start_scenario(PASSAGE)
	await _take_command()
	var frigate: Unit
	for u: Unit in main.simulation.unit_manager.get_faction_units("BLUE"):
		if u.spec.id == "rnon_ffg_fridtjof_nansen":
			frigate = u
	if frigate == null:
		checks["Northern Passage escort found"] = false
		return
	var guide := frigate.formation_leader
	checks["the escort starts on its screen station"] = frigate.station_kind == "formation" and frigate.on_station()
	var unknown: Track
	for second in 240:
		SimClock.advance(1.0)
		for t: Track in main.simulation.track_manager.tracks_for(frigate):
			if t.identity == "UNKNOWN" and t.classification < Track.Classification.CLASS_KNOWN and UnitManager.investigation_rejection(frigate, t) == "":
				unknown = t
				break
		if unknown != null:
			break
	checks["real sensors produce a contact to investigate"] = unknown != null
	if unknown == null:
		return
	main.map.select_units([frigate])
	await _frames()
	await _chart_click(unknown.position, MOUSE_BUTTON_RIGHT)
	checks["right-click on the unknown sends the escort to look"] = frigate.investigation_track == unknown
	checks["the screen station is kept while it looks"] = frigate.station_kind == "formation" and frigate.station_leader == guide and not frigate.on_station()
	var ended := false
	for second in 900:
		SimClock.advance(1.0)
		if frigate.investigation_track == null:
			ended = true
			break
	facts["investigation_result"] = frigate.investigation_result
	checks["the investigation ends on its own"] = ended
	checks["the orders line offers the way back"] = DataDisplay.orders_text(frigate).contains("S returns to") or frigate.on_station()
	await _shot("escort-off-station")
	main.map.select_units([frigate])
	await _key(KEY_S)
	checks["S re-forms the escort on its guide"] = frigate.formation_leader == guide and frigate.on_station()
	SimClock.advance(120.0)
	checks["the escort steers back toward its station"] = frigate.position.distance_to(Formation.station_for(frigate)) < 12.0


## Take Command on the operation's briefing with the mouse, as a player does, and hold the clock
## on the same press so frame time cannot move the opening picture.
func _take_command() -> void:
	main._show_briefing()
	await _frames()
	main._briefing._start.pressed.connect(func() -> void: SimClock.set_paused(true), CONNECT_ONE_SHOT)
	await _click_control(main._briefing._start)
	SimClock.set_paused(true)
	checks["Take Command through the briefing (%s)" % main.simulation.scenario_name] = main._command_taken and not main._briefing.visible


func _find(callsign: String) -> Unit:
	for u in main.simulation.unit_manager.units:
		if u.callsign == callsign:
			return u
	return null


func _frames() -> void:
	await tree.process_frame
	await tree.process_frame


func _key(code: Key, shift := false, ctrl := false) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.shift_pressed = shift
		event.ctrl_pressed = ctrl
		event.pressed = pressed
		main.get_viewport().push_input(event, true)
		await tree.process_frame
	await _frames()


func _click_control(control: Control) -> void:
	await _click(control.get_global_rect().get_center())


func _chart_click(world: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	await _click(main.map.get_global_transform_with_canvas() * main.map.world_to_screen(world), button)


func _chart_motion(world: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = main.map.get_global_transform_with_canvas() * main.map.world_to_screen(world)
	main.get_viewport().push_input(event, true)
	await _frames()


func _click(point: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	main.get_viewport().push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.position = point
		event.pressed = pressed
		main.get_viewport().push_input(event, true)
		await tree.process_frame
	await _frames()


## Embedded popup hit testing reads the actual pointer: warp to the row, then press and release.
func _popup_click(menu: PopupMenu, index: int) -> void:
	await tree.create_timer(0.2).timeout
	var point := Vector2(-1, -1)
	for y in range(6, menu.size.y, 5):
		var candidate := Vector2(menu.size.x * 0.5, y)
		menu.warp_mouse(candidate)
		await _frames()
		if menu.get_focused_item() == index:
			point = candidate
			break
	if point.x < 0:
		checks["popup row hittable: %d" % index] = false
		menu.hide()
		await _frames()
		return
	var window_id := menu.get_window_id()
	var input_point := Vector2(DisplayServer.mouse_get_position() - DisplayServer.window_get_position(window_id))
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.window_id = window_id
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = input_point
		event.global_position = input_point
		event.pressed = pressed
		Input.parse_input_event(event)
		await tree.process_frame
	await _frames()


func _shot(label: String) -> void:
	if not capture:
		return
	await _frames()
	await RenderingServer.frame_post_draw
	var frame := main.get_viewport().get_texture().get_image()
	var path := output_dir.path_join("%s-%d.png" % [label, frame.get_width()])
	checks["screenshot: " + label] = frame.save_png(path) == OK
	shots.append(path)


func _finish() -> void:
	var logged: Array[String] = errors.take_errors()
	checks["no unexpected engine errors"] = logged.is_empty()
	var failures := 0
	for check: String in checks:
		if not checks[check]:
			print("FAIL: " + check)
			failures += 1
	var result := {"window": [tree.root.size.x, tree.root.size.y], "checks": checks, "facts": facts, "errors": logged, "screenshots": shots}
	var file := FileAccess.open(output_dir.path_join("air-missions-%d.json" % tree.root.size.x), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t") + "\n")
	file.close()
	print("[Air missions] %d checks, %d failed" % [checks.size(), failures])
	OS.remove_logger(errors)
	tree.quit(1 if failures else 0)
