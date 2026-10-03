extends RefCounted
## End-to-end Northern Passage: instantiate the real scene and issue ordinary player orders.
## No artificial observations, damage, ammunition, target positions or mission-result changes.
## godot --headless --path . --script tools/passage_playtest.gd -- --policy=escort --seed=31
## Use xvfb-run, --resolution WIDTHxHEIGHT, and --capture for native screenshots and layout checks.

var tree: SceneTree
var main: Main
var clock: Node
var checks: Dictionary = {}
var commands: Array = []
var facts := {"first_blue_shot_s": -1.0, "first_defensive_shot_s": -1.0, "held_fire_for_civilians": false, "first_red_shot_s": -1.0, "blue_rounds": 0, "red_rounds": 0, "defensive_rounds": 0, "helicopter_observations": false, "unknown_seen": false, "classified_seen": false}
var policy := "escort"
var capture := false
var host: Unit
var frigate: Unit
var cargo: Unit
var helo: Unit
var helo_routed := false
var helo_returned := false
var fired_at: Dictionary = {}
var observed_names: Dictionary = {}
var shot_taken := false
var errors: Logger

func run(scene_tree: SceneTree) -> void:
	tree = scene_tree
	await _run()

func _option(prefix: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return fallback

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://work/m31")
	clock = tree.root.get_node("SimClock")
	policy = _option("--policy=", "escort")
	# A validation run keeps its own commander's log, never the developer's.
	var out_arg := _option("--out=", "")
	CommanderLog.path_override = (out_arg.get_basename() + "-commander_log.json") if out_arg != "" else "res://work/m31/%s-%s-%d-commander_log.json" % [policy, _option("--seed=", "31"), DisplayServer.window_get_size().x]
	CommanderLog.clear()
	capture = OS.get_cmdline_user_args().has("--capture")
	errors = load("res://tests/test_error_log.gd").new()
	OS.add_logger(errors)
	main = load("res://scenes/main/Main.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame
	checks["intro accessible on the operations desk"] = main._menu.visible and not main._menu._intro.disabled
	if capture:
		checks["intro button fits viewport"] = _fits(main._menu._intro)
		await _shot("desk")
	main._menu._intro.pressed.emit()
	await tree.process_frame
	checks["intro opens paused briefing"] = main._briefing.visible and clock.paused and main.simulation.scenario_path == ScenarioMenu.INTRO_PATH
	checks["briefing explains deadline and civilian condition"] = main._briefing._body.text.contains("45-minute") and main._briefing._body.text.contains("neutral")
	if capture:
		checks["take-command button fits viewport"] = _fits(main._briefing._start)
		await _shot("briefing")
	main._briefing._start.pressed.emit()
	checks["take command runs at real time"] = not clock.paused and clock.multiplier() == 1
	clock.set_paused(true)
	tree.root.get_node("Debug").log_events = false
	for u: Unit in main.simulation.unit_manager.get_faction_units("BLUE"):
		if u.spec.id == "usn_ddg_arleigh_burke_iia": host = u
		if u.spec.id == "rnon_ffg_fridtjof_nansen": frigate = u
		if u.spec.category == "merchant": cargo = u
		if u.is_aircraft(): helo = u
	checks["expected controllable force present"] = host != null and frigate != null and cargo != null and helo != null
	if not checks["expected controllable force present"]:
		_finish()
		return
	var wm := main.simulation.weapon_manager
	wm.round_fired.connect(func(u: Unit, _spec: WeaponSpec, _t: Track) -> void:
		var side := "blue" if u.faction == "BLUE" else "red"
		facts[side + "_rounds"] += 1
		if facts["first_" + side + "_shot_s"] < 0:
			facts["first_" + side + "_shot_s"] = clock.sim_time)
	wm.interceptor_launched.connect(func(u: Unit, _spec: WeaponSpec, _w: Weapon, rounds: int) -> void:
		if u.faction == "BLUE":
			facts.defensive_rounds += rounds
			if facts.first_defensive_shot_s < 0: facts.first_defensive_shot_s = clock.sim_time)
	main.simulation.track_manager.track_added.connect(func(faction: String, t: Track) -> void:
		if faction == "BLUE" and t.identity == "UNKNOWN": facts.unknown_seen = true)
	main.simulation.track_manager.track_classified.connect(func(faction: String, t: Track) -> void:
		if faction == "BLUE" and t.identity in ["HOSTILE", "NEUTRAL"]: facts.classified_seen = true)
	if policy == "escort":
		_order(host, Order.launch_aircraft())
	elif policy == "abandon":
		for u: Unit in [host, frigate]:
			_order(u, Order.break_formation())
			_order(u, Order.set_roe(Unit.Roe.HOLD))
			_order(u, Order.set_emcon(true))
			_order(u, Order.set_speed(u.spec.max_speed_kn))
			_order(u, Order.move(Vector2(-35, -10)))
	elif policy == "deadline":
		_order(cargo, Order.stop())
	elif policy == "civilian":
		main.map.select_units([host])
		main._apply_order_to_selection(Order.set_roe(Unit.Roe.FREE))
		checks["free-fire order warns about civilians"] = main.radio.journal.back().contains("Neutral sinkings")
	else:
		checks["known policy"] = false
		_finish()
		return
	checks["opening commands preserve paused simulation time"] = clock.sim_time == 0
	if capture:
		main.map.select_units([host])
		main.map.fit_to(Vector2(14, 3), 55)
		await _shot("command")
	var last_frame := 0.0
	while main.simulation.mission_manager.result == MissionManager.Result.RUNNING and clock.sim_time < 2800:
		_drive_orders()
		clock.advance(1.0)
		for t: Track in main.simulation.track_manager.get_tracks("BLUE"):
			if t.contributors.has(helo): facts.helicopter_observations = true
			if t.known_callsign != "": observed_names[t.known_callsign] = true
		var engagement_at := float(facts.first_blue_shot_s) if facts.first_blue_shot_s >= 0 else float(facts.first_defensive_shot_s)
		if capture and not shot_taken and engagement_at >= 0 and clock.sim_time >= engagement_at + 5 and not wm.in_flight.is_empty():
			main.map.select_units([frigate])
			await _shot("engagement")
			shot_taken = true
		if clock.sim_time - last_frame >= 120:
			last_frame = clock.sim_time
			await tree.process_frame
	checks["mission reached a terminal outcome"] = main.simulation.mission_manager.result != MissionManager.Result.RUNNING
	checks["expected policy outcome"] = main.simulation.mission_manager.result == (MissionManager.Result.VICTORY if policy == "escort" else MissionManager.Result.DEFEAT)
	if policy == "abandon":
		checks["abandonment ends through freighter loss"] = main.simulation.mission_manager.loss_objectives[0].complete
	if policy == "deadline":
		checks["stationary convoy ends through deadline expiry"] = main.simulation.mission_manager.loss_objectives[1].complete and cargo.alive
	checks["debrief is visible and pauses the clock"] = main._report.visible and clock.paused
	var graded: Dictionary = CommanderLog.best("northern_passage")
	var won := main.simulation.mission_manager.result == MissionManager.Result.VICTORY
	checks["debrief leads with a graded effectiveness"] = main._report._body.text.contains("MISSION EFFECTIVENESS") and main._report._tiles["effectiveness"]["value"].text.ends_with("%")
	checks["the commander's log records the commanded result"] = graded.get("result", "") == ("VICTORY" if won else "DEFEAT") and int(graded.get("attempts", 0)) == 1
	checks["a victory grades 60 to 100 and a defeat 0 to 40"] = (int(graded.get("best_percent", -1)) >= 60) if won else (int(graded.get("best_percent", 101)) <= 40)
	checks["debrief includes civilians and observed timeline"] = main._report._body.text.contains("CIVILIAN INCIDENTS") and main._report._body.text.contains("OBSERVED EVENT TIMELINE")
	if policy == "escort":
		checks["investigation precedes incoming fire"] = facts.first_red_shot_s > 120
		checks["real defensive exchange occurred"] = facts.defensive_rounds > 0 and facts.red_rounds > 0
		checks["escort withheld unsafe shots near held civilians"] = facts.held_fire_for_civilians
		checks["reconnaissance updated the shared picture"] = facts.helicopter_observations
		checks["reconnaissance airframe returned alive"] = helo.alive and helo.completed_sorties == 1
		checks["detection and classification both occurred"] = facts.unknown_seen and facts.classified_seen
		checks["no player-caused civilian sinking"] = main._civilian_incidents.is_empty()
	if policy == "civilian":
		checks["civilian condition caused the defeat"] = main.simulation.mission_manager.loss_objectives[2].complete
		checks["civilian sinking is not an enemy kill"] = not main._civilian_incidents.is_empty() and main._kills.is_empty()
	var names_observed := true
	for name: String in ["Stoikiy", "MV Skerry Trader", "MV Coastal Star"]:
		if main._report._body.text.contains(name) and not observed_names.has(name): names_observed = false
	checks["debrief names only observed contacts"] = names_observed
	if capture:
		checks["report review button fits viewport"] = _fits(main._report._review)
		checks["tactical panes fit viewport"] = _fits(main.map) and _fits(main._bottom_strip)
		checks["real engagement captured"] = shot_taken
		await _shot("debrief")
	_finish()

func _drive_orders() -> void:
	if policy == "escort" and helo.alive:
		if helo.airborne() and not helo_routed:
			helo_routed = _order(helo, Order.move(Vector2(7, 2)))
		if helo.airborne() and clock.sim_time >= 240 and not helo_returned:
			helo_returned = _order(helo, Order.return_to_base())
	if policy not in ["escort", "civilian"]:
		return
	var shooter := host if policy == "civilian" else frigate
	for t: Track in main.simulation.track_manager.tracks_for(shooter):
		if t.identity != ("UNKNOWN" if policy == "civilian" else "HOSTILE") or t.domain != "surface":
			continue
		# This policy deliberately fires at a probable merchant without establishing affiliation.
		# Waiting for the held class avoids spending the whole magazine on the first unknown
		# warship; it uses only the commander's picture, never the contact's hidden faction.
		if policy == "civilian" and (t.classification < Track.Classification.CLASS_KNOWN or not t.known_category.contains("merchant")):
			continue
		if clock.sim_time - float(fired_at.get(t.id, -1000)) < (30.0 if policy == "civilian" else 240.0):
			continue
		for w: WeaponSpec in shooter.weapons:
			if w.type != ("gun" if policy == "civilian" else "asm") or not Combat.check_engagement(shooter, w, t).ok:
				continue
			if policy == "escort" and not _clear_civilian_corridor(t, w):
				facts.held_fire_for_civilians = true
				continue
			if _order(shooter, Order.engage(t, w.id, mini(8 if policy == "civilian" else 4, shooter.magazine_count(w.id)))):
				fired_at[t.id] = clock.sim_time
				return

## A protective escort does not fire a searching missile through charted civilian traffic.
## Use held reports and their error bounds only; a hostile label is not a precise range fix.
## The separate civilian policy deliberately ignores this precaution and must still lose.
func _clear_civilian_corridor(target: Track, weapon: WeaponSpec) -> bool:
	var aim := Combat.intercept_point(frigate.position, weapon.speed_kn, target.position, target.course_deg, target.speed_kn, target.has_kinematics)
	for held: Track in main.simulation.track_manager.tracks_for(frigate):
		if held.identity != "NEUTRAL" or held.status == Track.Status.LOST: continue
		var closest := Geometry2D.get_closest_point_to_segment(held.position, frigate.position, aim)
		var margin := weapon.acquisition_radius_nm() + target.position_error_nm + held.position_error_nm
		if held.position.distance_to(closest) <= margin: return false
	return true

func _order(u: Unit, order: Order) -> bool:
	var accepted := main.simulation.unit_manager.issue_order(u, order)
	commands.append({"time_s": clock.sim_time, "unit": u.callsign, "order": order.describe(), "accepted": accepted})
	return accepted

func _fits(control: Control) -> bool:
	return control.is_visible_in_tree() and main.get_viewport_rect().encloses(control.get_global_rect())

func _shot(label: String) -> void:
	await tree.process_frame
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var frame := main.get_viewport().get_texture().get_image()
	var path := "res://work/m31/%s-%s-%d.png" % [policy, label, frame.get_width()]
	checks["screenshot " + label] = frame.save_png(path) == OK

func _finish() -> void:
	var logged: Array[String] = errors.take_errors()
	checks["no unexpected engine errors"] = logged.is_empty()
	var units: Array = []
	var aground := 0
	for u: Unit in main.simulation.unit_manager.units:
		units.append({"name": u.callsign, "position": [u.position.x, u.position.y], "heading": u.heading_deg, "health": u.health, "alive": u.alive, "fuel_s": u.fuel_s, "magazines": u.magazines.duplicate(), "flight_state": u.flight_state, "last_attacker": u.last_attacker})
		if u.alive and u.needs_sea_room() and Terrain.is_land(u.position): aground += 1
	checks["surviving hulls remain afloat"] = aground == 0
	var report := {"policy": policy, "seed": main.simulation.seed_override, "sim_time_s": clock.sim_time, "window_size": [tree.root.size.x, tree.root.size.y], "logical_viewport": [main.size.x, main.size.y], "result": main.simulation.mission_manager.result, "checks": checks, "facts": facts, "commands": commands, "observed_names": observed_names.keys(), "units": units, "errors": logged}
	var out := _option("--out=", "res://work/m31/trial-%s-%s.json" % [policy, _option("--seed=", "31")])
	var file := FileAccess.open(out, FileAccess.WRITE)
	if file == null:
		checks["result file written"] = false
	else:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	var failed := 0
	for key: String in checks:
		if not checks[key]:
			failed += 1
			print("FAIL: " + key)
	print("[Northern Passage] %d checks, %d failed; policy=%s result=%s time=%.1fs facts=%s" % [checks.size(), failed, policy, main.simulation.mission_manager.result, clock.sim_time, JSON.stringify(facts)])
	OS.remove_logger(errors)
	tree.quit(1 if failed else 0)
