class_name Main
extends Control
## Main entry point. Wires the simulation layer to the presentation layer and handles
## global hotkeys. Dev flags (after `--`) are handled by DevHarness.

const GAME_TITLE := "NAVAL FLEET COMMAND"
const BUILD_MILESTONE := "M14 — Fleet Presentation"
const DEFAULT_SCENARIO := "res://data/scenarios/aegis_bastion.json"
## Flags that mean the session is being driven programmatically, so the menu and briefing are
## skipped and the simulation is left ready to be advanced.
const SCRIPTED_FLAGS := ["--combat", "--defence", "--defence-once", "--engage-once", "--smoke", "--dump", "--autoplay", "--reload-check", "--ping", "--autopilot", "--select"]

@onready var simulation: Simulation = %Simulation
@onready var map: TacticalMap = %TacticalMap
@onready var top_bar: TopBar = %TopBar
@onready var unit_panel: UnitPanel = %UnitPanel
@onready var orders_panel: OrdersPanel = %OrdersPanel
@onready var contact_panel: ContactPanel = %ContactPanel

var _library: PlatformLibrary
var _library_was_paused := true
var _report: AfterAction
var _editor: ScenarioEditor
var _menu: ScenarioMenu
var _briefing: BriefingPanel
var _objective_accum := 0.0
var _dev: DevHarness
var _stats := {}
var _losses: PackedStringArray = []
var _kills: PackedStringArray = []


func _ready() -> void:
	theme = UITheme.build()
	unit_panel.roster.map = map
	unit_panel.inspect_requested.connect(_inspect_asset)
	orders_panel.inspect_requested.connect(func(id: String) -> void: _inspect_asset(id, true))
	top_bar.library_pressed.connect(_toggle_library)
	var overview := CommandOverview.new()
	overview.map = map
	overview.custom_minimum_size.y = 90
	$Layout.add_child(overview)
	$Layout.move_child(overview, 1)
	orders_panel.weapon_manager = simulation.weapon_manager
	map.unit_manager = simulation.unit_manager
	map.track_manager = simulation.track_manager
	map.weapon_manager = simulation.weapon_manager
	map.threat_manager = simulation.threat_manager
	map.aviation_manager = simulation.aviation_manager
	map.simulation = simulation
	map.player_faction = simulation.player_faction
	contact_panel.track_manager = simulation.track_manager
	contact_panel.player_faction = simulation.player_faction
	contact_panel.map = map

	map.selection_changed.connect(_on_selection_changed)
	map.move_order_requested.connect(_on_move_order_requested)
	map.engage_requested.connect(_on_engage_requested)
	map.waypoint_delete_requested.connect(_on_waypoint_delete_requested)
	orders_panel.order_requested.connect(_apply_order_to_selection)
	orders_panel.formation_requested.connect(_apply_formation)
	contact_panel.track_chosen.connect(map.select_track)
	map.track_selected.connect(_on_track_selected)
	orders_panel.weapon_selection_changed.connect(func(spec: WeaponSpec) -> void: map.weapon_ring = spec)
	top_bar.logged.connect(unit_panel.add_event)
	simulation.weapon_manager.weapon_launched.connect(_on_weapon_launched)
	simulation.weapon_manager.weapon_impact.connect(_on_weapon_impact)
	simulation.weapon_manager.unit_destroyed.connect(_on_unit_destroyed)
	simulation.weapon_manager.engagement_rejected.connect(_on_engagement_rejected)
	simulation.weapon_manager.interceptor_launched.connect(_on_interceptor_launched)
	simulation.weapon_manager.weapon_defeated.connect(_on_weapon_defeated)
	simulation.threat_manager.threat_detected.connect(_on_threat_detected)
	simulation.aviation_manager.aircraft_launched.connect(func(a: Unit, parent: Unit) -> void:
		if a.faction == simulation.player_faction:
			_stats["sorties"] = int(_stats.get("sorties", 0)) + 1
			top_bar.flash("%s airborne from %s" % [a.callsign, parent.callsign if parent != null else "base"], "good")
			SoundFx.play("click")
		print("[Air] %s launched" % a.callsign))
	simulation.aviation_manager.aircraft_recovered.connect(func(a: Unit, _p: Unit) -> void:
		if a.faction == simulation.player_faction:
			top_bar.flash("%s recovered" % a.callsign))
	simulation.aviation_manager.aircraft_bingo.connect(func(a: Unit) -> void:
		if a.faction == simulation.player_faction:
			SimClock.drop_to_realtime()
			top_bar.flash("%s at bingo fuel, returning" % a.callsign, "warn"))
	simulation.aviation_manager.aircraft_lost.connect(func(a: Unit, reason: String) -> void:
		if a.faction == simulation.player_faction:
			SimClock.drop_to_realtime()
			_losses.append(a.callsign)
			top_bar.flash("%s LOST — %s" % [a.callsign, reason], "alert")
		print("[Air] %s lost: %s" % [a.callsign, reason]))
	simulation.aviation_manager.launch_rejected.connect(func(parent: Unit, reason: String) -> void:
		if parent.faction == simulation.player_faction:
			top_bar.flash("%s cannot launch: %s" % [parent.callsign, reason], "warn"))
	simulation.mission_manager.mission_ended.connect(_on_mission_ended)
	simulation.mission_manager.objective_completed.connect(func(o: MissionObjective, is_loss: bool) -> void:
		if not is_loss:
			top_bar.flash("OBJECTIVE COMPLETE — %s" % o.text, "good")
		print("[Mission] objective %s: %s" % ["failed" if is_loss else "complete", o.text]))
	_build_screens()
	top_bar.briefing_pressed.connect(_show_briefing)
	top_bar.restart_pressed.connect(restart_scenario)
	top_bar.menu_pressed.connect(_show_menu)
	simulation.track_manager.track_added.connect(_on_track_added)
	simulation.track_manager.track_classified.connect(_on_track_classified)
	simulation.track_manager.track_lost.connect(_on_track_lost)
	simulation.unit_manager.order_issued.connect(func(u: Unit, o: Order) -> void: print("[Order] %s: %s" % [u.callsign, o.describe()]))

	move_child(_library, get_child_count() - 1)
	var args := OS.get_cmdline_user_args()
	var scripted := false
	for f in SCRIPTED_FLAGS:
		if args.has(f):
			scripted = true
	var start_path := DEFAULT_SCENARIO
	for a in args:
		if a.begins_with("--scenario="):
			start_path = a.get_slice("=", 1)
		elif a.begins_with("--fastforward="):
			scripted = true
	if args.has("--autopilot"):
		simulation.ai_plays_player = true
	# Must be set before the scenario loads, since that is when the generators are seeded.
	var seed_value := int(DevHarness.arg(args, "--seed=", -1.0))
	if seed_value >= 0:
		simulation.seed_override = seed_value
		print("[Dev] seed pinned to %d" % seed_value)
	if scripted:
		SoundFx.enabled = false
	start_scenario(start_path)
	if args.has("--brief"):
		_show_briefing()
	elif scripted:
		_hide_screens()
	else:
		_show_menu()
	print("[Main] %s booted (%s) — %d units, Godot %s" % [GAME_TITLE, BUILD_MILESTONE, simulation.unit_manager.units.size(), Engine.get_version_info()["string"]])
	_dev = DevHarness.new(self)
	_dev.handle_flags()


func _process(delta: float) -> void:
	_objective_accum += delta
	if _objective_accum < 0.5:
		return
	_objective_accum = 0.0
	top_bar.set_objective_text(_objective_summary())
	var threats := AirDefence.inbound_threats(simulation.unit_manager, simulation.threat_manager, simulation.player_faction, map.reference_unit())
	if threats.is_empty():
		top_bar.set_alert("")
	else:
		var torpedo := false
		var ballistic := false
		for entry: Dictionary in threats:
			var w: Weapon = entry["weapon"]
			if w.spec.is_torpedo():
				torpedo = true
			elif w.threat_class() == "ballistic":
				ballistic = true
		var label := "TORPEDO IN THE WATER" if torpedo else ("BALLISTIC INBOUND" if ballistic else "MISSILE INBOUND")
		top_bar.set_alert("%s  ·  %d" % [label, threats.size()])


func _objective_summary() -> String:
	var mm := simulation.mission_manager
	for o in mm.victory_objectives:
		if not o.complete:
			return "%s  (%s)" % [o.text, o.progress(simulation.unit_manager, SimClock.sim_time)]
	return "objectives complete" if not mm.victory_objectives.is_empty() else ""


# --- Scenario lifecycle -------------------------------------------------------------------

func start_scenario(path: String) -> void:
	if not simulation.load_scenario(path):
		push_error("Main: failed to load scenario %s" % path)
		return
	SimClock.set_paused(true)
	SimClock.set_speed_index(0)
	map.clear_selection()
	map.weapon_ring = null
	map.reset_presentation()
	map.fit_to(simulation.map_center, simulation.map_extent_nm)
	top_bar.set_scenario_name(simulation.scenario_name)
	top_bar.set_objective_text("")
	top_bar.set_alert("")
	unit_panel.set_units([])
	unit_panel.clear_events()
	orders_panel.set_units([], false)
	orders_panel.set_target_track(null)
	var own := simulation.unit_manager.get_faction_units(simulation.player_faction)
	if not own.is_empty():
		map.select_units([own[0]])
	contact_panel.refresh()
	_stats = {"launched": 0, "intercepted": 0, "decoyed": 0, "hits": 0, "leaked": 0, "hostile_rounds": 0, "hits_taken": 0, "own_rounds": 0, "hits_scored": 0, "decoys_used": 0, "contacts": 0, "classified": 0, "sorties": 0}
	_losses = PackedStringArray()
	_kills = PackedStringArray()
	_report.hide()
	_briefing.configure(simulation.scenario_name, simulation.scenario.get("forces", ""), simulation.scenario.get("description", ""), simulation.scenario.get("environment", {}))
	_briefing.set_mode(true)
	var coast := "" if Terrain.is_empty() else ", %d landmass%s charted" % [Terrain.landmasses.size(), "" if Terrain.landmasses.size() == 1 else "es"]
	top_bar.flash("%s loaded — sea state %d, %s%s" % [simulation.scenario_name, Detection.sea_state, Detection.sea_state_name(), coast])


func restart_scenario() -> void:
	start_scenario(simulation.scenario_path)
	_show_briefing()


func _build_screens() -> void:
	_library = PlatformLibrary.new()
	_library.closed.connect(_close_library)
	add_child(_library)
	_library.hide()
	_menu = ScenarioMenu.new()
	_menu.name = "ScenarioMenu"
	_menu.scenario_chosen.connect(func(path: String) -> void:
		start_scenario(path)
		_show_briefing())
	_menu.dismissed.connect(_hide_screens)
	_menu.editor_requested.connect(_show_editor)
	_menu.library_requested.connect(_toggle_library)
	add_child(_menu)
	_menu.hide()

	_editor = ScenarioEditor.new()
	_editor.name = "ScenarioEditor"
	_editor.play_requested.connect(func(path: String) -> void:
		start_scenario(path)
		_show_briefing())
	_editor.closed.connect(_show_menu)
	add_child(_editor)
	_editor.hide()

	_briefing = BriefingPanel.new()
	_briefing.name = "BriefingPanel"
	_briefing.mission_manager = simulation.mission_manager
	_briefing.unit_manager = simulation.unit_manager
	_briefing.start_pressed.connect(_hide_screens)
	_briefing.restart_pressed.connect(restart_scenario)
	_briefing.menu_pressed.connect(_show_menu)
	add_child(_briefing)
	_briefing.hide()

	_report = AfterAction.new()
	_report.name = "AfterAction"
	_report.review_pressed.connect(func() -> void: _report.hide())
	_report.restart_pressed.connect(restart_scenario)
	_report.menu_pressed.connect(_show_menu)
	add_child(_report)


func _show_editor() -> void:
	_menu.hide()
	_briefing.hide()
	_report.hide()
	_editor.show()
	SimClock.set_paused(true)


func _show_menu() -> void:
	_briefing.hide()
	_report.hide()
	_editor.hide()
	_menu.allow_back(simulation.scenario_path != "")
	_menu.refresh(simulation.scenario_path)
	_menu.show()
	SimClock.set_paused(true)


func _show_briefing() -> void:
	_menu.hide()
	_report.hide()
	_editor.hide()
	_briefing.set_mode(SimClock.sim_time <= 0.0)
	_briefing.refresh()
	_briefing.show()
	SimClock.set_paused(true)


func _hide_screens() -> void:
	_menu.hide()
	_briefing.hide()
	_editor.hide()


func _toggle_library() -> void:
	if _library.visible:
		_close_library()
	else:
		_library_was_paused = SimClock.paused
		_library.show()
		SimClock.set_paused(true)


func _close_library() -> void:
	_library.hide()
	SimClock.set_paused(_library_was_paused)


func _inspect_asset(id: String, weapon := false) -> void:
	if not _library.visible:
		_toggle_library()
	_library.inspect(id, weapon)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if _library.visible and k.keycode not in [KEY_F7, KEY_ESCAPE]:
		return
	if _editor.visible and k.keycode != KEY_F8 and k.keycode != KEY_F9:
		return  # the editor owns the keyboard while it is open
	match k.keycode:
		KEY_F7:
			_toggle_library()
		KEY_SPACE:
			SimClock.toggle_pause()
		KEY_ESCAPE:
			if _library.visible:
				_close_library()
			elif _report.visible:
				_report.hide()
			else:
				map.clear_selection()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			SimClock.set_speed_index(k.keycode - KEY_1)
		KEY_F2:
			map.show_key = not map.show_key
		KEY_F4:
			map.show_rings = not map.show_rings
		KEY_F5:
			map.show_trails = not map.show_trails
		KEY_F6:
			map.show_terrain = not map.show_terrain
			if Terrain.is_empty():
				top_bar.flash("No charted land in this area")
		KEY_F3:
			Debug.toggle()
		KEY_M:
			top_bar.flash("Sound %s" % ("on" if SoundFx.toggle() else "off"))
		KEY_R:
			_toggle_radar_on_selection()
		KEY_P:
			_toggle_sonar_on_selection()
		KEY_E:
			_toggle_emcon_on_selection()
		KEY_F1:
			if _briefing.visible:
				_hide_screens()
			else:
				_show_briefing()
		KEY_F9:
			_show_menu()
		KEY_F8:
			_show_editor()
		KEY_F10:
			restart_scenario()
		KEY_HOME:
			map.fit_to_fleet()
		KEY_C:
			map.center_on_selection()
		_:
			return
	get_viewport().set_input_as_handled()


func _on_selection_changed(units: Array) -> void:
	if map.selected_track != null and not map.selected_track.visible_to(map.reference_unit()):
		map.select_track(null)
	unit_panel.set_units(units)
	orders_panel.set_units(units, _all_controllable(units))
	orders_panel.set_target_track(map.selected_track)


func _on_track_selected(t: Track) -> void:
	contact_panel.refresh()
	orders_panel.set_target_track(t)


func _on_weapon_launched(shooter: Unit, spec: WeaponSpec, t: Track, rounds: int) -> void:
	SimClock.drop_to_realtime()
	var own := shooter.faction == simulation.player_faction
	if own:
		_stats["own_rounds"] += rounds
		map.add_effect(shooter.position, "launch")
		SoundFx.play("launch")
		top_bar.flash("%s — %d x %s at %s" % [shooter.callsign, rounds, spec.display_name, t.id], "good")

	print("[Combat] %s launches %d x %s at %s (%.1f nm)" % [shooter.callsign, rounds, spec.display_name, t.id, shooter.position.distance_to(t.position)])


func _on_threat_detected(faction: String, w: Weapon) -> void:
	if faction != simulation.player_faction or (map.reference_unit() != null and not simulation.threat_manager.visible_to(map.reference_unit(), w)):
		return
	SimClock.drop_to_realtime()
	_stats["hostile_rounds"] += 1
	var seconds := int(w.time_to_reach_s(_nearest_own_unit_pos(w)))
	var label := "TORPEDO IN THE WATER" if w.spec.is_torpedo() else ("BALLISTIC INBOUND" if w.threat_class() == "ballistic" else "INCOMING")
	top_bar.flash("%s — %s, impact in ~%d s" % [label, w.spec.display_name, seconds], "alert")
	SoundFx.play("torpedo" if w.spec.is_torpedo() else "alarm", 1.0)
	print("[Defence] inbound %s detected at %.1f nm" % [w.spec.display_name, w.position.distance_to(_nearest_own_unit_pos(w))])


func _nearest_own_distance(pos: Vector2) -> float:
	var best := INF
	for u in simulation.unit_manager.get_faction_units(simulation.player_faction):
		best = minf(best, pos.distance_to(u.position))
	return 0.0 if best == INF else best


func _nearest_own_unit_pos(w: Weapon) -> Vector2:
	var best := w.position
	var best_d := INF
	for u in simulation.unit_manager.get_faction_units(simulation.player_faction):
		var d := w.position.distance_to(u.position)
		if d < best_d:
			best_d = d
			best = u.position
	return best


func _on_interceptor_launched(shooter: Unit, spec: WeaponSpec, threat: Weapon, rounds: int) -> void:
	if shooter.faction == simulation.player_faction:
		_stats["launched"] += rounds
		map.add_effect(shooter.position, "launch")
		SoundFx.play("launch", 0.4)
	print("[Defence] %s fires %d x %s at inbound %s (%.1f nm)" % [shooter.callsign, rounds, spec.display_name, threat.spec.display_name, shooter.position.distance_to(threat.position)])


func _on_weapon_defeated(threat: Weapon, reason: String, by_unit: Unit) -> void:
	var own_defence := by_unit != null and by_unit.faction == simulation.player_faction
	if own_defence:
		if reason == "INTERCEPTED":
			_stats["intercepted"] += 1
		elif reason == "DECOYED":
			_stats["decoyed"] += 1
			_stats["decoys_used"] += 1
		map.add_effect(threat.position, "intercept" if reason == "INTERCEPTED" else "decoy")
		SoundFx.play("intercept", 0.3)
		top_bar.flash("%s %s by %s" % [threat.spec.display_name, reason, by_unit.callsign], "good")
	print("[Defence] %s %s by %s" % [threat.spec.display_name, reason, by_unit.callsign if by_unit != null else "?"])


func _on_weapon_impact(faction: String, spec: WeaponSpec, target: Unit, hit: bool) -> void:
	var own_target := target.faction == simulation.player_faction
	if hit:
		_stats["hits"] += 1
		if own_target:
			_stats["hits_taken"] += 1
		elif faction == simulation.player_faction:
			_stats["hits_scored"] += 1
	_stats["leaked"] += 1
	if not hit:
		map.add_effect(target.position, "miss")
		print("[Combat] %s miss on %s" % [spec.display_name, target.callsign])
		return
	SimClock.drop_to_realtime()
	map.add_effect(target.position, "hit", own_target)
	SoundFx.play("impact", 0.2)
	if own_target:
		top_bar.flash("%s HIT — %s" % [target.callsign, Damage.condition_text(target)], "alert")
	else:
		top_bar.flash("HIT on %s — %.0f%% remaining" % [target.callsign, Damage.health_fraction(target) * 100.0], "good")
	print("[Combat] %s hit %s (%s, %.0f%%)" % [spec.display_name, target.callsign, Damage.condition_text(target), Damage.health_fraction(target) * 100.0])


func _on_unit_destroyed(u: Unit, killer_faction: String) -> void:
	SimClock.drop_to_realtime()
	map.add_effect(u.position, "destroyed", u.faction == simulation.player_faction)
	SoundFx.play("impact", 0.0)
	if u.faction == simulation.player_faction:
		_losses.append(u.callsign)
		top_bar.flash("%s DESTROYED" % u.callsign, "alert")
	else:
		if killer_faction == simulation.player_faction:
			_kills.append(u.callsign)
		top_bar.flash("%s DESTROYED" % u.callsign, "good")
	print("[Combat] %s destroyed by %s" % [u.callsign, killer_faction])


func _on_engagement_rejected(shooter: Unit, spec: WeaponSpec, reason: String) -> void:
	if shooter.faction == simulation.player_faction:
		top_bar.flash("%s cannot fire %s: %s" % [shooter.callsign, spec.display_name, reason], "warn")


func _on_mission_ended(result: String, summary: String) -> void:
	SimClock.set_paused(true)
	var mm := simulation.mission_manager
	var objectives: Array = []
	objectives.append_array(mm.victory_objectives)
	_report.show_report(result, summary, _stats, objectives, _losses, _kills, SimClock.sim_time)
	top_bar.flash(result, "good" if result == "VICTORY" else "alert")
	SoundFx.play("victory" if result == "VICTORY" else "defeat")
	print("[Mission] %s — %s" % [result, summary])
	_briefing.set_mode(false)


func _on_move_order_requested(world_pos: Vector2, append: bool) -> void:
	_apply_order_to_selection(Order.move(world_pos, append))


## Ctrl/cmd + right-click on a contact: select it as the target and, if a shooter and a legal
## weapon are already lined up in the orders panel, fire immediately. Tells the player why nothing
## happened when it can't, rather than firing silently into nothing.
func _on_engage_requested(t: Track) -> void:
	map.select_track(t)
	if orders_panel.try_engage():
		return
	if map.selected.is_empty():
		top_bar.flash("Select a shooter before you engage", "warn")
	else:
		top_bar.flash("No weapon in envelope for %s" % t.id, "warn")


## Right-click on a waypoint marker drops just that leg. Order objects only carry "set a new
## route" or "append one more leg", so the remaining route is rebuilt as a fresh sequence of
## those two rather than needing a new order type.
func _on_waypoint_delete_requested(u: Unit, index: int) -> void:
	if u.faction != simulation.player_faction or index < 0 or index >= u.waypoints.size():
		return
	var remaining := u.waypoints.duplicate()
	remaining.remove_at(index)
	if remaining.is_empty():
		simulation.unit_manager.issue_order(u, Order.clear_waypoints())
	else:
		simulation.unit_manager.issue_order(u, Order.move(remaining[0], false))
		for i in range(1, remaining.size()):
			simulation.unit_manager.issue_order(u, Order.move(remaining[i], true))
	SoundFx.play("click", 0.05)


## One order goes to every selected unit, so a mixed selection can have it accepted by the
## helicopter and refused by the destroyer. The flash reports the refusal only when nothing at all
## could take it; otherwise the order simply went to the units it suited.
func _apply_order_to_selection(order: Order) -> void:
	var any := false
	var refused := 0
	for u in map.selected:
		if u.faction == simulation.player_faction:
			if simulation.unit_manager.issue_order(u, order):
				any = true
			else:
				refused += 1
	if any:
		SoundFx.play("click", 0.05)
		if order.type == Order.Type.MOVE and not Terrain.is_empty():
			for u in map.selected:
				if u.faction == simulation.player_faction and u.needs_sea_room() and Terrain.first_land_contact(u.position, order.target_pos) >= 0.0:
					top_bar.flash("%s: land on that course — it will follow the coast" % u.callsign, "warn")
					break
	elif refused > 0:
		top_bar.flash("That is land — pick a point in the water", "warn")
		if order.type == Order.Type.MOVE:
			map.add_effect(order.target_pos, "refused")


func _toggle_radar_on_selection() -> void:
	var any_on := false
	for u in map.selected:
		if u.radar_on:
			any_on = true
	_apply_order_to_selection(Order.silence_radar() if any_on else Order.activate_radar())


## Formation orders are per-unit, so they cannot go through the broadcast path.
func _apply_formation(pattern: String) -> void:
	var own: Array = []
	for u in map.selected:
		if u.faction == simulation.player_faction and not u.is_aircraft():
			own.append(u)
	if own.size() < 2:
		top_bar.flash("Select a leader and at least one consort to form up", "warn")
		return
	for entry: Dictionary in Formation.assign(own, pattern):
		simulation.unit_manager.issue_order(entry["unit"], entry["order"])
	top_bar.flash("%s formed on %s" % [pattern.to_upper(), own[0].callsign], "good")


func _toggle_emcon_on_selection() -> void:
	var any_radiating := false
	for u in map.selected:
		if u.radar_on or u.active_sonar_on:
			any_radiating = true
	_apply_order_to_selection(Order.set_emcon(any_radiating))


func _toggle_sonar_on_selection() -> void:
	var any_on := false
	for u in map.selected:
		if u.active_sonar_on:
			any_on = true
	_apply_order_to_selection(Order.passive_sonar() if any_on else Order.active_sonar())
	for u in map.selected:
		if u.active_sonar_on:
			SoundFx.play("ping", 0.5)
			break


func _on_track_added(faction: String, t: Track) -> void:
	if faction != simulation.player_faction or (map.reference_unit() != null and not t.visible_to(map.reference_unit())):
		return
	SimClock.drop_to_realtime()
	_stats["contacts"] += 1
	top_bar.flash("NEW CONTACT %s (%s)" % [t.id, t.source.to_upper().replace("_", " ")], "warn")
	SoundFx.play("contact", 0.5)
	contact_panel.refresh()
	print("[Contact] %s gained on %s at %.1f nm from the nearest of ours" % [t.id, t.source, _nearest_own_distance(t.position)])


func _on_track_classified(faction: String, t: Track) -> void:
	if faction != simulation.player_faction:
		return
	if t.classification == Track.Classification.CLASS_KNOWN:
		SimClock.drop_to_realtime()
		if t.identity == "HOSTILE":
			_stats["classified"] += 1
		top_bar.flash("%s CLASSIFIED %s — %s" % [t.id, t.known_class, t.identity], "alert" if t.identity == "HOSTILE" else "info")
		SoundFx.play("classified", 0.5)
		print("[Contact] %s classified as %s (%s)" % [t.id, t.known_class, t.identity])
	elif t.classification == Track.Classification.IDENTIFIED:
		top_bar.flash("%s IDENTIFIED AS %s" % [t.id, t.known_callsign])


func _on_track_lost(faction: String, t: Track) -> void:
	if faction == simulation.player_faction:
		top_bar.flash("TRACK %s LOST" % t.id, "warn")


func _all_controllable(units: Array) -> bool:
	if units.is_empty():
		return false
	for u in units:
		if u.faction != simulation.player_faction:
			return false
	return true
