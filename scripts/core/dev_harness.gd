class_name DevHarness
extends RefCounted
## Command-line scaffolding for driving the game without a person at the keyboard: scripted
## engagements, scenario sweeps, state dumps and screenshots. None of this is gameplay. It lives
## apart from Main so the wiring file stays readable, and it is the only place that should ever
## read OS.get_cmdline_user_args().
##
## Flags, all passed after a bare `--`:
##   --scenario=res://path       load this scenario instead of the default
##   --seed=N                    pin every generator, so runs repeat exactly
##   --autopilot                 let the opposing-force AI command the player's side as well
##   --fastforward=S             advance S seconds of simulation immediately
##   --autoplay=S                crude stand-in player: engage, advance, repeat, for S seconds
##   --combat / --defence        scripted engagement sequences from Milestones 3 and 4
##   --defence-once / --engage-once   fire one salvo and stop with rounds still in the air
##   --ping                      player surface ships go active on sonar at the start
##   --select / --form           select the player's ships, optionally in a screen formation
##   --move-mode                 leave Plot Move armed, for UI screenshots and interaction smoke
##   --open-palette              open the searchable Actions palette
##   --pick=CALLSIGN             select one own unit and hook the first track, for screenshots
##   --open-editor               open the scenario editor on the loaded scenario, for screenshots
##   --brief                     open the briefing board
##   --no-ai                     disable every AI controller
##   --reload-check              fight a while, restart, and report that state was cleared
##   --debug                     turn on the truth overlay
##   --dump                      print a full state report and quit, without touching the renderer
##   --hold=S --screenshot=PATH  wait S seconds, save a PNG, dump state and quit (windowed only)

var main: Main


func _init(owner: Main) -> void:
	main = owner


## Reads a numeric flag such as --seed=7. Static so Main can use it during startup.
static func arg(args: PackedStringArray, prefix: String, fallback: float) -> float:
	for a in args:
		if a.begins_with(prefix):
			return float(a.get_slice("=", 1))
	return fallback

func handle_flags() -> void:
	var args := OS.get_cmdline_user_args()
	var shot := ""
	var fast_forward := 0.0
	for a in args:
		if a.begins_with("--screenshot="):
			shot = a.get_slice("=", 1)
		elif a.begins_with("--fastforward="):
			fast_forward = float(a.get_slice("=", 1))
	if args.has("--debug"):
		Debug.enabled = true
	if args.has("--autopilot"):
		print("[Dev] the AI is commanding both sides")
	if args.has("--no-ai"):
		main.simulation.ai_enabled = false
		print("[Dev] AI disabled")
	if args.has("--ping"):
		for u in main.simulation.unit_manager.get_faction_units(main.simulation.player_faction):
			if u.has_sonar() and not u.is_submarine():
				main.simulation.unit_manager.issue_order(u, Order.active_sonar())
		print("[Dev] player surface units are pinging")
	if fast_forward > 0.0:
		SimClock.advance(fast_forward)
		print("[Dev] fast-forwarded %.0f s" % fast_forward)
	if args.has("--select"):
		var own: Array = []
		for u in main.simulation.unit_manager.get_faction_units(main.simulation.player_faction):
			if not u.is_aircraft() and u.spec.max_speed_kn > 0.0:
				own.append(u)
		main.map.select_units(own)
		if args.has("--form"):
			main._apply_formation("screen")
			main.map.select_units([own[0]] if not own.is_empty() else [])
	for a in args:
		if a.begins_with("--pick="):
			var wanted := a.get_slice("=", 1)
			for u in main.simulation.unit_manager.get_faction_units(main.simulation.player_faction):
				if u.callsign == wanted:
					main.map.select_units([u])
					var tracks: Array = main.simulation.track_manager.get_tracks(main.simulation.player_faction)
					if not tracks.is_empty():
						main.map.select_track(tracks[0])
					print("[Dev] picked %s" % wanted)
	if args.has("--open-editor"):
		main._editor.load_dict(main.simulation.scenario)
		main._show_editor()
		print("[Dev] editor opened")
	if args.has("--reload-check"):
		_run_reload_check()
	if args.has("--combat"):
		_run_scripted_engagement()
	var autoplay := arg(args, "--autoplay=", 0.0)
	if autoplay > 0.0:
		_run_autoplay(autoplay)
	if args.has("--defence"):
		_run_scripted_defence()
	if args.has("--defence-once"):
		var closing := 0.0
		while main.simulation.track_manager.get_tracks("RED").is_empty() and closing < 20000.0:
			SimClock.advance(60.0)
			closing += 60.0
		_auto_engage_faction("RED")
		SimClock.advance(float(arg(args, "--advance=", 75.0)))  # rounds and interceptors both airborne
		main.map.select_units(main.simulation.unit_manager.get_faction_units(main.simulation.player_faction))
	if args.has("--engage-once"):
		var closing := 0.0
		while main.simulation.track_manager.get_tracks(main.simulation.player_faction).is_empty() and closing < 20000.0:
			SimClock.advance(60.0)
			closing += 60.0
		var blue := main.simulation.unit_manager.get_faction_units(main.simulation.player_faction)
		main.map.select_units(blue)
		var tracks := main.simulation.track_manager.get_tracks(main.simulation.player_faction)
		if not tracks.is_empty():
			main.map.select_track(tracks[0])
		_auto_engage()
		SimClock.advance(90.0)  # leave rounds in flight for the screenshot
	if args.has("--smoke"):
		var blue := main.simulation.unit_manager.get_faction_units(main.simulation.player_faction)
		main.map.select_units(blue)
		main._apply_order_to_selection(Order.move(Vector2(0.0, 20.0)))
		SimClock.set_speed_index(5)
		SimClock.set_paused(false)
	if args.has("--move-mode"):
		main.map.set_move_mode(true)
	if args.has("--open-palette"):
		main._toggle_command_palette()
	if args.has("--open-library"):
		main._toggle_library()
		main._library._search.text = "F-35"
		main._library._filter("F-35")
	for a in args:
		if a.begins_with("--inspect="):
			main._inspect_asset(a.get_slice("=", 1), args.has("--weapon"))
		elif a.begins_with("--view="):
			main._library._stage.set_view(a.get_slice("=", 1))
		elif a.begins_with("--zoom="):
			_zoom_after_layout(float(a.get_slice("=", 1)))
	if args.has("--visual-smoke"):
		_visual_smoke()
		return
	if args.has("--dump"):
		_dump_state()
		main.get_tree().quit()
		return
	if shot != "":
		_screenshot_after(shot, arg(args, "--hold=", 3.0))


func _zoom_after_layout(value: float) -> void:
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	main.map.ppn = clampf(value, TacticalMap.MIN_PPN, TacticalMap.MAX_PPN)
	main.map.center_on_selection()


## Dev helper: drives the whole Milestone 3 loop headlessly and deterministically — close until
## radar contact, engage every track in envelope, let the rounds fly, repeat until the mission
## resolves. Used to verify search -> detect -> classify -> engage -> damage -> victory.
func _run_scripted_engagement() -> void:
	var elapsed := 0.0
	while main.simulation.track_manager.get_tracks(main.simulation.player_faction).is_empty() and elapsed < 20000.0:
		SimClock.advance(60.0)
		elapsed += 60.0
	print("[Dev] first contact after %.0f s of closing" % elapsed)
	for round_i in 8:
		if main.simulation.mission_manager.result != MissionManager.Result.RUNNING:
			break
		_auto_engage()
		SimClock.advance(300.0)


## Dev helper: lets the opposing force shoot so that automatic air defence can be observed.
## This is test scaffolding on the shared order path, not the Milestone 5 AI.
func _run_scripted_defence() -> void:
	var elapsed := 0.0
	while main.simulation.track_manager.get_tracks("RED").is_empty() and elapsed < 20000.0:
		SimClock.advance(60.0)
		elapsed += 60.0
	print("[Dev] RED holds contact after %.0f s" % elapsed)
	for wave in 3:
		_auto_engage_faction("RED")
		SimClock.advance(400.0)
	print("[Dev] defence tally: %d interceptors fired, %d intercepted, %d decoyed, %d rounds reached a ship (%d hits)" % [main._stats["launched"], main._stats["intercepted"], main._stats["decoyed"], main._stats["leaked"], main._stats["hits"]])


## Dev helper: proves restart clears every manager. Fights a while, restarts, and reports the
## state that must be back to its opening values.
func _run_reload_check() -> void:
	_run_autoplay(6000.0)
	print("[Dev] before restart: units=%d tracks=%d in_flight=%d sim_time=%.0f mission=%d" % [
		main.simulation.unit_manager.units.size(),
		main.simulation.track_manager.get_tracks(main.simulation.player_faction).size(),
		main.simulation.weapon_manager.in_flight.size(), SimClock.sim_time, main.simulation.mission_manager.result])
	main.restart_scenario()
	var hp := 0.0
	var mags := 0
	for u in main.simulation.unit_manager.units:
		hp += u.health
		for wid in u.magazines:
			mags += u.magazine_count(wid)
	print("[Dev] after restart: units=%d tracks=%d in_flight=%d sim_time=%.0f mission=%d hp_total=%.0f rounds=%d objectives_open=%d" % [
		main.simulation.unit_manager.units.size(),
		main.simulation.track_manager.get_tracks(main.simulation.player_faction).size(),
		main.simulation.weapon_manager.in_flight.size(), SimClock.sim_time, main.simulation.mission_manager.result,
		hp, mags, main.simulation.mission_manager.victory_objectives.filter(func(o: MissionObjective) -> bool: return not o.complete).size()])
	main.get_tree().quit()


## Dev helper: a crude stand-in for a player. Engages whatever is in envelope every 5 minutes and
## keeps the clock running, so a scenario can be checked for winnability end to end.
func _run_autoplay(budget_s: float) -> void:
	var spent := 0.0
	while spent < budget_s and main.simulation.mission_manager.result == MissionManager.Result.RUNNING:
		_auto_engage()
		SimClock.advance(60.0)
		spent += 60.0
	print("[Dev] autoplay ran %.0f s, mission=%s" % [spent, main.simulation.mission_manager.result])


func _auto_engage() -> void:
	_auto_engage_faction(main.simulation.player_faction)


func _auto_engage_faction(faction: String) -> void:
	for u in main.simulation.unit_manager.get_faction_units(faction):
		var best_track: Track = null
		var best_d := INF
		for t: Track in main.simulation.track_manager.get_tracks(faction):
			# Minimum discipline a real commander would apply: confirmed hostiles only.
			if t.identity != "HOSTILE" or t.status != Track.Status.ACTIVE:
				continue
			var d := u.position.distance_to(t.position)
			if d < best_d:
				best_d = d
				best_track = t
		if best_track == null:
			continue
		for spec in u.offensive_weapons():
			if Combat.check_engagement(u, spec, best_track)["ok"]:
				main.simulation.unit_manager.issue_order(u, Order.engage(best_track, spec.id, 4))
				break


func _dump_state() -> void:
	for u in main.simulation.unit_manager.units:
		print("[Dev] %s hp=%.0f/%.0f %s decoys=%d mags=%s" % [u.callsign, u.health, u.spec.health, Damage.condition_text(u), u.decoys, u.magazines])
	for t: Track in main.simulation.track_manager.get_tracks(main.simulation.player_faction):
		print("[Dev] track %s cls=%s id=%s pos=%s err=%.2f cse=%.0f spd=%.1f %s" % [t.id, t.classification, t.identity, t.position, t.position_error_nm, t.course_deg, t.speed_kn, t.status_text(SimClock.sim_time)])
	for w: Weapon in main.simulation.weapon_manager.in_flight:
		print("[Dev] round %d %s %s phase=%d pos=%s seen_by_player=%s interceptor=%s" % [w.id, w.faction, w.spec.display_name, w.phase, w.position, main.simulation.threat_manager.is_detected(main.simulation.player_faction, w), w.intercept_target != null])
	for u in main.simulation.unit_manager.units:
		if u.faction != main.simulation.player_faction and u.alive:
			print("[Dev] ai %s: %s" % [u.callsign, main.simulation.ai_state_for(u)])
	var mm := main.simulation.mission_manager
	for o in mm.victory_objectives:
		print("[Dev] victory '%s': %s (%s)" % [o.text, "DONE" if o.complete else "open", o.progress(main.simulation.unit_manager, SimClock.sim_time)])
	for o in mm.loss_objectives:
		print("[Dev] loss '%s': %s" % [o.text, "TRIGGERED" if o.complete else "clear"])
	for u in main.simulation.unit_manager.units:
		if u.is_aircraft() and u.faction == main.simulation.player_faction:
			print("[Dev] air %s state=%d alt=%.0f fuel=%.0f%% buoys=%d alive=%s" % [u.callsign, u.flight_state, u.altitude_m, u.fuel_fraction() * 100.0, u.sonobuoys, u.alive])
	print("[Dev] sonobuoys in the water=%d" % main.simulation.aviation_manager.sonobuoys.size())
	if not Terrain.is_empty():
		var aground := PackedStringArray()
		for u in main.simulation.unit_manager.units:
			if u.alive and u.needs_sea_room() and Terrain.is_land(u.position):
				aground.append(u.callsign)
		print("[Dev] terrain: %d landmasses, %d aground%s" % [Terrain.landmasses.size(), aground.size(), " (%s)" % ", ".join(aground) if not aground.is_empty() else ""])
	print("[Dev] defence stats=%s" % main._stats)
	print("[Dev] weapons in flight=%d  mission=%s  sim_time=%.1f s" % [main.simulation.weapon_manager.in_flight.size(), main.simulation.mission_manager.result, SimClock.sim_time])


## Screenshots need a rendered frame, so this path is for windowed runs only. Headless
## diagnostics use --dump, which never waits on the renderer.
func _screenshot_after(path: String, seconds: float) -> void:
	await main.get_tree().create_timer(seconds).timeout
	await RenderingServer.frame_post_draw
	var img := main.get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("[Dev] screenshot %s -> %s" % [path, error_string(err)])
	_dump_state()
	main.get_tree().quit()


## UI integration smoke in the actual application tree, including the live 3D stage.
func _visual_smoke() -> void:
	var checks: Dictionary = {}
	main._hide_screens()
	if main._library.visible:
		main._close_library()
	SimClock.set_paused(false)
	main._toggle_library()
	await main.get_tree().process_frame
	checks["gallery pauses a running mission"] = SimClock.paused
	var library := main._library
	library._filter("")
	checks["empty query restores complete catalogue"] = library._specs.size() == DataDB.all_platforms().size()
	library._search.text = "F-35"
	library._filter("F-35")
	var matched_ids: Array = library._specs.map(func(p: PlatformSpec) -> String: return p.id)
	checks["search finds both Lightning variants"] = matched_ids.has("usn_fighter_f35c") and matched_ids.has("rn_fighter_f35b") and library._specs.size() < DataDB.all_platforms().size()
	library._filter("no-such-platform")
	checks["empty results clear the model"] = library._specs.is_empty() and library._stage._model == null
	library.inspect("usn_ddg_burke_iii")
	await main.get_tree().process_frame
	checks["ship model and fitted weapons appear"] = library._stage._model != null and library._loadout.get_child_count() > 0
	checks["visible stage renders"] = library._stage._viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS
	var button := library._loadout.get_child(0) as Button
	button.pressed.emit()
	await main.get_tree().process_frame
	checks["loadout card opens weapon inspection"] = library._weapons and library._stage._model != null
	checks["weapon has linked platforms"] = library._loadout.get_child_count() > 0
	(library._loadout.get_child(0) as Button).pressed.emit()
	checks["carrier card returns to platform inspection"] = not library._weapons
	var stage := library._stage
	stage.set_view("profile")
	checks["profile preset"] = absf(stage._pitch - .03) < .001
	stage.set_view("plan")
	checks["plan preset"] = absf(stage._pitch - 1.54) < .001
	stage.reset_view()
	var yaw := stage._yaw
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	stage._gui_input(down)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(60, 20)
	stage._gui_input(motion)
	checks["drag orbits the model"] = stage._yaw != yaw
	down.pressed = false
	stage._gui_input(down)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	for i in 80:
		stage._gui_input(wheel)
	checks["zoom clamps safely"] = stage._zoom >= 7.5 and stage._zoom <= 24
	stage.reset_view()
	checks["reset restores framing"] = stage._zoom == 13.5 and stage._yaw == 0
	library.inspect("phalanx_ciws", true)
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	var fits := true
	var screen := Rect2(Vector2.ZERO, Vector2(stage._viewport.size))
	for i in 8:
		fits = fits and screen.has_point(stage._camera.unproject_position(stage._model_bounds.get_endpoint(i)))
	checks["tall gun mount fits inside the viewport"] = fits
	main._close_library()
	checks["closing restores a running mission"] = not SimClock.paused
	checks["hidden gallery stops rendering"] = stage._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED
	SimClock.set_paused(true)
	main._toggle_library()
	main._close_library()
	checks["closing preserves an existing pause"] = SimClock.paused
	SimClock.set_paused(false)
	main._toggle_command_palette()
	await main.get_tree().process_frame
	checks["command palette pauses a running mission"] = main._command_palette.visible and SimClock.paused
	checks["command palette exposes searchable actions"] = main._command_palette._actions.size() >= 20 and main._command_palette._search.has_focus()
	main._command_palette.close_palette()
	checks["closing command palette restores a running mission"] = not SimClock.paused
	main._show_briefing()
	checks["briefing pauses a running mission"] = main._briefing.visible and SimClock.paused
	main._hide_screens()
	checks["dismissing briefing restores a running mission"] = not SimClock.paused
	main._show_menu()
	await main.get_tree().process_frame
	main._toggle_library()
	await main.get_tree().process_frame
	var menu_was_isolated := main._library.visible and not main._menu.visible
	main._close_library()
	await main.get_tree().process_frame
	checks["gallery isolates and restores the mission menu"] = menu_was_isolated \
		and main._menu.visible and not main._library.visible and SimClock.paused \
		and main.get_viewport().gui_get_focus_owner() == main._menu._list
	main._hide_screens()
	var failed := 0
	for label in checks:
		print("[Visual smoke] %s %s" % ["PASS" if checks[label] else "FAIL", label])
		if not checks[label]:
			failed += 1
	print("[Visual smoke] %d checks, %d failed" % [checks.size(), failed])
	main.get_tree().quit(1 if failed else 0)
