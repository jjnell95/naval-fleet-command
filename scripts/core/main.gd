class_name Main
extends Control
## Main entry point. Wires the simulation layer to the presentation layer and handles
## global hotkeys. Dev flags (after `--`): --smoke (auto-order + run) and --screenshot=PATH.

const GAME_TITLE := "NAVAL FLEET COMMAND"
const BUILD_MILESTONE := "M9 — Operational Depth"
const DEFAULT_SCENARIO := "res://data/scenarios/north_atlantic_shadow_line.json"
## Flags that mean the session is being driven programmatically, so the menu and briefing are
## skipped and the simulation is left ready to be advanced.
const SCRIPTED_FLAGS := ["--combat", "--defence", "--defence-once", "--engage-once", "--smoke", "--dump", "--autoplay", "--reload-check", "--ping", "--autopilot", "--select"]

@onready var simulation: Simulation = %Simulation
@onready var map: TacticalMap = %TacticalMap
@onready var top_bar: TopBar = %TopBar
@onready var unit_panel: UnitPanel = %UnitPanel
@onready var orders_panel: OrdersPanel = %OrdersPanel
@onready var contact_panel: ContactPanel = %ContactPanel

var _banner: Label
var _menu: ScenarioMenu
var _briefing: BriefingPanel
var _objective_accum := 0.0
var _dev: DevHarness
var _stats := {"launched": 0, "intercepted": 0, "decoyed": 0, "hits": 0, "leaked": 0}


func _ready() -> void:
	theme = UITheme.build()
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
	orders_panel.order_requested.connect(_apply_order_to_selection)
	orders_panel.formation_requested.connect(_apply_formation)
	contact_panel.track_chosen.connect(map.select_track)
	map.track_selected.connect(_on_track_selected)
	orders_panel.weapon_selection_changed.connect(func(spec: WeaponSpec) -> void: map.weapon_ring = spec)
	simulation.weapon_manager.weapon_launched.connect(_on_weapon_launched)
	simulation.weapon_manager.weapon_impact.connect(_on_weapon_impact)
	simulation.weapon_manager.unit_destroyed.connect(_on_unit_destroyed)
	simulation.weapon_manager.engagement_rejected.connect(_on_engagement_rejected)
	simulation.weapon_manager.interceptor_launched.connect(_on_interceptor_launched)
	simulation.weapon_manager.weapon_defeated.connect(_on_weapon_defeated)
	simulation.threat_manager.threat_detected.connect(_on_threat_detected)
	simulation.aviation_manager.aircraft_launched.connect(func(a: Unit, parent: Unit) -> void:
		if a.faction == simulation.player_faction:
			top_bar.flash("%s airborne from %s" % [a.callsign, parent.callsign if parent != null else "base"])
		print("[Air] %s launched" % a.callsign))
	simulation.aviation_manager.aircraft_recovered.connect(func(a: Unit, _p: Unit) -> void:
		if a.faction == simulation.player_faction:
			top_bar.flash("%s recovered" % a.callsign))
	simulation.aviation_manager.aircraft_bingo.connect(func(a: Unit) -> void:
		if a.faction == simulation.player_faction:
			SimClock.drop_to_realtime()
			top_bar.flash("%s at bingo fuel, returning" % a.callsign))
	simulation.aviation_manager.aircraft_lost.connect(func(a: Unit, reason: String) -> void:
		if a.faction == simulation.player_faction:
			SimClock.drop_to_realtime()
			top_bar.flash("%s LOST — %s" % [a.callsign, reason])
		print("[Air] %s lost: %s" % [a.callsign, reason]))
	simulation.aviation_manager.launch_rejected.connect(func(parent: Unit, reason: String) -> void:
		if parent.faction == simulation.player_faction:
			top_bar.flash("%s cannot launch: %s" % [parent.callsign, reason]))
	simulation.mission_manager.mission_ended.connect(_on_mission_ended)
	simulation.mission_manager.objective_completed.connect(func(o: MissionObjective, is_loss: bool) -> void:
		if not is_loss:
			top_bar.flash("OBJECTIVE COMPLETE — %s" % o.text)
		print("[Mission] objective %s: %s" % ["failed" if is_loss else "complete", o.text]))
	_build_banner()
	_build_screens()
	top_bar.briefing_pressed.connect(_show_briefing)
	top_bar.restart_pressed.connect(restart_scenario)
	top_bar.menu_pressed.connect(_show_menu)
	simulation.track_manager.track_added.connect(_on_track_added)
	simulation.track_manager.track_classified.connect(_on_track_classified)
	simulation.track_manager.track_lost.connect(_on_track_lost)
	simulation.unit_manager.order_issued.connect(func(u: Unit, o: Order) -> void: print("[Order] %s: %s" % [u.callsign, o.describe()]))

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
	map.fit_to(simulation.map_center, simulation.map_extent_nm)
	top_bar.set_scenario_name(simulation.scenario_name)
	top_bar.set_objective_text("")
	unit_panel.set_units([])
	orders_panel.set_units([], false)
	orders_panel.set_target_track(null)
	contact_panel.refresh()
	_stats = {"launched": 0, "intercepted": 0, "decoyed": 0, "hits": 0, "leaked": 0}
	_banner.hide()
	_briefing.configure(simulation.scenario_name, simulation.scenario.get("forces", ""), simulation.scenario.get("description", ""))
	_briefing.set_mode(true)


func restart_scenario() -> void:
	start_scenario(simulation.scenario_path)
	_show_briefing()


func _build_screens() -> void:
	_menu = ScenarioMenu.new()
	_menu.name = "ScenarioMenu"
	_menu.scenario_chosen.connect(func(path: String) -> void:
		start_scenario(path)
		_show_briefing())
	_menu.dismissed.connect(_hide_screens)
	add_child(_menu)
	_menu.hide()

	_briefing = BriefingPanel.new()
	_briefing.name = "BriefingPanel"
	_briefing.mission_manager = simulation.mission_manager
	_briefing.unit_manager = simulation.unit_manager
	_briefing.start_pressed.connect(_hide_screens)
	_briefing.restart_pressed.connect(restart_scenario)
	_briefing.menu_pressed.connect(_show_menu)
	add_child(_briefing)
	_briefing.hide()


func _show_menu() -> void:
	_briefing.hide()
	_menu.allow_back(simulation.scenario_path != "")
	_menu.refresh(simulation.scenario_path)
	_menu.show()
	SimClock.set_paused(true)


func _show_briefing() -> void:
	_menu.hide()
	_briefing.set_mode(SimClock.sim_time <= 0.0)
	_briefing.refresh()
	_briefing.show()
	SimClock.set_paused(true)


func _hide_screens() -> void:
	_menu.hide()
	_briefing.hide()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_SPACE:
			SimClock.toggle_pause()
		KEY_ESCAPE:
			map.clear_selection()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			SimClock.set_speed_index(k.keycode - KEY_1)
		KEY_F3:
			Debug.toggle()
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
		KEY_F10:
			restart_scenario()
		_:
			return
	get_viewport().set_input_as_handled()


func _build_banner() -> void:
	_banner = Label.new()
	_banner.name = "MissionBanner"
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.offset_left = -420.0
	_banner.offset_right = 420.0
	_banner.offset_top = 120.0
	_banner.offset_bottom = 200.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 26)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.hide()
	add_child(_banner)


func _on_selection_changed(units: Array) -> void:
	unit_panel.set_units(units)
	orders_panel.set_units(units, _all_controllable(units))
	orders_panel.set_target_track(map.selected_track)


func _on_track_selected(t: Track) -> void:
	contact_panel.refresh()
	orders_panel.set_target_track(t)


func _on_weapon_launched(shooter: Unit, spec: WeaponSpec, t: Track, rounds: int) -> void:
	SimClock.drop_to_realtime()
	var own := shooter.faction == simulation.player_faction
	top_bar.flash("%s %s — %d x %s at %s" % ["LAUNCH" if own else "HOSTILE LAUNCH", shooter.callsign if own else "unknown", rounds, spec.display_name, t.id])
	print("[Combat] %s launches %d x %s at %s (%.1f nm)" % [shooter.callsign, rounds, spec.display_name, t.id, shooter.position.distance_to(t.position)])


func _on_threat_detected(faction: String, w: Weapon) -> void:
	if faction != simulation.player_faction:
		return
	SimClock.drop_to_realtime()
	var seconds := int(w.time_to_reach_s(_nearest_own_unit_pos(w)))
	var label := "TORPEDO IN THE WATER" if w.spec.is_torpedo() else "INCOMING"
	top_bar.flash("%s — %s, impact in ~%d s" % [label, w.spec.display_name, seconds])
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
	_stats["launched"] += rounds
	print("[Defence] %s fires %d x %s at inbound %s (%.1f nm)" % [shooter.callsign, rounds, spec.display_name, threat.spec.display_name, shooter.position.distance_to(threat.position)])


func _on_weapon_defeated(threat: Weapon, reason: String, by_unit: Unit) -> void:
	if reason == "INTERCEPTED":
		_stats["intercepted"] += 1
	elif reason == "DECOYED":
		_stats["decoyed"] += 1
	var defender := by_unit.callsign if by_unit != null else "?"
	if by_unit != null and by_unit.faction == simulation.player_faction:
		top_bar.flash("%s %s by %s" % [threat.spec.display_name, reason, defender])
	print("[Defence] %s %s by %s" % [threat.spec.display_name, reason, defender])


func _on_weapon_impact(faction: String, spec: WeaponSpec, target: Unit, hit: bool) -> void:
	if hit:
		_stats["hits"] += 1
	_stats["leaked"] += 1
	if not hit:
		print("[Combat] %s miss on %s" % [spec.display_name, target.callsign])
		return
	SimClock.drop_to_realtime()
	if target.faction == simulation.player_faction:
		top_bar.flash("%s HIT — %s" % [target.callsign, Damage.condition_text(target)])
	else:
		top_bar.flash("HIT on %s — %.0f%% remaining" % [target.callsign, Damage.health_fraction(target) * 100.0])
	print("[Combat] %s hit %s (%s, %.0f%%)" % [spec.display_name, target.callsign, Damage.condition_text(target), Damage.health_fraction(target) * 100.0])


func _on_unit_destroyed(u: Unit, killer_faction: String) -> void:
	SimClock.drop_to_realtime()
	top_bar.flash("%s DESTROYED" % u.callsign)
	print("[Combat] %s destroyed by %s" % [u.callsign, killer_faction])


func _on_engagement_rejected(shooter: Unit, spec: WeaponSpec, reason: String) -> void:
	if shooter.faction == simulation.player_faction:
		top_bar.flash("%s cannot fire %s: %s" % [shooter.callsign, spec.display_name, reason])


func _on_mission_ended(result: String, summary: String) -> void:
	SimClock.set_paused(true)
	_banner.text = "%s\n%s\n\nF10 restart     F9 scenarios" % [result, summary]
	_banner.modulate = Color(0.5, 1.0, 0.6) if result == "VICTORY" else Color(1.0, 0.5, 0.45)
	_banner.show()
	top_bar.flash(result)
	print("[Mission] %s — %s" % [result, summary])
	_briefing.set_mode(false)


func _on_move_order_requested(world_pos: Vector2, append: bool) -> void:
	_apply_order_to_selection(Order.move(world_pos, append))


func _apply_order_to_selection(order: Order) -> void:
	for u in map.selected:
		if u.faction == simulation.player_faction:
			simulation.unit_manager.issue_order(u, order)


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
		top_bar.flash("Select a leader and at least one consort to form up")
		return
	for entry: Dictionary in Formation.assign(own, pattern):
		simulation.unit_manager.issue_order(entry["unit"], entry["order"])
	top_bar.flash("%s formed on %s" % [pattern.to_upper(), own[0].callsign])


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


func _on_track_added(faction: String, t: Track) -> void:
	if faction != simulation.player_faction:
		return
	SimClock.drop_to_realtime()
	top_bar.flash("NEW CONTACT %s" % t.id)
	contact_panel.refresh()
	print("[Contact] %s gained on %s at %.1f nm from the nearest of ours" % [t.id, t.source, _nearest_own_distance(t.position)])


func _on_track_classified(faction: String, t: Track) -> void:
	if faction != simulation.player_faction:
		return
	if t.classification == Track.Classification.CLASS_KNOWN:
		SimClock.drop_to_realtime()
		top_bar.flash("%s CLASSIFIED %s — %s" % [t.id, t.known_class, t.identity])
		print("[Contact] %s classified as %s (%s)" % [t.id, t.known_class, t.identity])
	elif t.classification == Track.Classification.IDENTIFIED:
		top_bar.flash("%s IDENTIFIED AS %s" % [t.id, t.known_callsign])


func _on_track_lost(faction: String, t: Track) -> void:
	if faction == simulation.player_faction:
		top_bar.flash("TRACK %s LOST" % t.id)


func _all_controllable(units: Array) -> bool:
	if units.is_empty():
		return false
	for u in units:
		if u.faction != simulation.player_faction:
			return false
	return true
