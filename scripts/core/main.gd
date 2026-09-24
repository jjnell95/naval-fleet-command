class_name Main
extends Control
## Main entry point. Wires the simulation layer to the presentation layer and handles
## global hotkeys. Dev flags (after `--`) are handled by DevHarness.

const GAME_TITLE := "NAVAL FLEET COMMAND"
const BUILD_MILESTONE := "M20 — Air Operations"
const DEFAULT_SCENARIO := "res://data/scenarios/aegis_bastion.json"
## Flags that mean the session is being driven programmatically, so the menu and briefing are
## skipped and the simulation is left ready to be advanced.
const SCRIPTED_FLAGS := ["--aviation-smoke", "--open-air-ops", "--combat", "--defence", "--defence-once", "--engage-once", "--smoke", "--dump", "--autoplay", "--reload-check", "--ping", "--autopilot", "--select", "--move-mode", "--open-palette"]

@onready var simulation: Simulation = %Simulation
@onready var map: TacticalMap = %TacticalMap
@onready var top_bar: TopBar = %TopBar
@onready var unit_panel: UnitPanel = %UnitPanel
@onready var orders_panel: OrdersPanel = %OrdersPanel
@onready var contact_panel: ContactPanel = %ContactPanel

var _library: PlatformLibrary
var _report: AfterAction
var _editor: ScenarioEditor
var _menu: ScenarioMenu
var _briefing: BriefingPanel
var _command_palette: CommandPalette
var _air_operations: AirOperations
var _modal_pause_captured := false
var _modal_was_paused := true
var _background_focus_modes: Dictionary = {}
var _library_previous_focus: Control
var _library_returns_to_menu := false
var _objective_accum := 0.0
var _dev: DevHarness
var _stats := {}
var _losses: PackedStringArray = []
var _kills: PackedStringArray = []
var _foundered: Dictionary = {}  # Unit -> true, lost to fire or flooding rather than outright


func _ready() -> void:
	theme = UITheme.build()
	unit_panel.roster.map = map
	unit_panel.inspect_requested.connect(_inspect_asset)
	orders_panel.inspect_requested.connect(func(id: String) -> void: _inspect_asset(id, true))
	top_bar.library_pressed.connect(_toggle_library)
	top_bar.air_operations_pressed.connect(_toggle_air_operations)
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
	map.interaction_mode_changed.connect(orders_panel.set_move_mode)
	orders_panel.order_requested.connect(_apply_order_to_selection)
	orders_panel.formation_requested.connect(_apply_formation)
	orders_panel.move_mode_requested.connect(map.set_move_mode)
	orders_panel.emcon_toggle_requested.connect(_toggle_emcon_on_selection)
	orders_panel.air_operations_requested.connect(_toggle_air_operations)
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
	simulation.weapon_manager.weapon_seduced.connect(_on_weapon_seduced)
	simulation.casualty_event.connect(_on_casualty_event)
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
	top_bar.commands_pressed.connect(_toggle_command_palette)
	top_bar.alert_pressed.connect(_focus_urgent_threat)
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
		# The banner, countdown, and click-to-focus all describe the same highest-priority threat.
		var primary: Dictionary = threats[0]
		var weapon: Weapon = primary["weapon"]
		var label := "TORPEDO IN THE WATER" if weapon.spec.is_torpedo() else ("BALLISTIC INBOUND" if weapon.threat_class() == "ballistic" else "MISSILE INBOUND")
		top_bar.set_alert("%s  ·  %d  ·  %ds" % [label, threats.size(), maxi(int(primary["time_s"]), 0)])


func _objective_summary() -> String:
	var mm := simulation.mission_manager
	for o in mm.victory_objectives:
		if not o.complete:
			return "%s  (%s)" % [o.text, o.progress(simulation.unit_manager, SimClock.sim_time)]
	return "objectives complete" if not mm.victory_objectives.is_empty() else ""


# --- Scenario lifecycle -------------------------------------------------------------------

func start_scenario(path: String) -> void:
	if _air_operations != null:
		_air_operations.hide()
		_air_operations.clear_selection()
	if not simulation.load_scenario(path):
		push_error("Main: failed to load scenario %s" % path)
		return
	SimClock.set_paused(true)
	SimClock.set_speed_index(0)
	# A replacement scenario starts behind its own briefing. Rebase any older modal snapshot so
	# dismissing that briefing can never inherit a running state from the previous mission.
	_modal_pause_captured = true
	_modal_was_paused = true
	_set_background_input_enabled(false)
	map.clear_selection()
	map.weapon_ring = null
	map.reset_presentation()
	var chart: Dictionary = simulation.scenario.get("map", {})
	var focus: Array = chart.get("focus_center_nm", [simulation.map_center.x, simulation.map_center.y])
	map.fit_to(Vector2(focus[0], focus[1]), float(chart.get("focus_extent_nm", simulation.map_extent_nm)))
	top_bar.set_scenario_name(simulation.scenario_name)
	top_bar.set_objective_text("")
	top_bar.set_alert("")
	unit_panel.set_units([])
	unit_panel.clear_events()
	orders_panel.set_units([], false, false)
	orders_panel.set_target_track(null)
	var own := simulation.unit_manager.get_faction_units(simulation.player_faction)
	if not own.is_empty():
		map.select_units([own[0]])
	contact_panel.refresh()
	_stats = {"launched": 0, "intercepted": 0, "decoyed": 0, "hits": 0, "leaked": 0, "hostile_rounds": 0, "hits_taken": 0, "own_rounds": 0, "hits_scored": 0, "decoys_used": 0, "contacts": 0, "classified": 0, "sorties": 0}
	_losses = PackedStringArray()
	_kills = PackedStringArray()
	_foundered.clear()
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
	_briefing.start_pressed.connect(_on_briefing_start)
	_briefing.restart_pressed.connect(restart_scenario)
	_briefing.menu_pressed.connect(_show_menu)
	add_child(_briefing)
	_briefing.hide()

	_report = AfterAction.new()
	_report.name = "AfterAction"
	_report.review_pressed.connect(_close_report)
	_report.restart_pressed.connect(restart_scenario)
	_report.menu_pressed.connect(_show_menu)
	add_child(_report)

	_command_palette = CommandPalette.new()
	_command_palette.action_requested.connect(_run_palette_action)
	_command_palette.closed.connect(_restore_modal_pause_if_clear)
	add_child(_command_palette)
	_command_palette.hide()
	_air_operations = AirOperations.new()
	_air_operations.name = "AirOperations"
	_air_operations.simulation = simulation
	_air_operations.closed.connect(_close_air_operations)
	_air_operations.order_requested.connect(_issue_air_order)
	_air_operations.aircraft_selected.connect(func(a: Unit) -> void:
		_close_air_operations(false)
		map.select_units([a])
		map.center_on_selection())
	add_child(_air_operations)
	_air_operations.hide()


func _show_editor() -> void:
	_begin_modal_pause()
	_menu.hide()
	_briefing.hide()
	_report.hide()
	_editor.show()
	_editor.call_deferred("focus_default")


func _show_menu() -> void:
	_begin_modal_pause()
	_briefing.hide()
	_report.hide()
	_editor.hide()
	_menu.allow_back(simulation.scenario_path != "")
	_menu.refresh(simulation.scenario_path)
	_menu.show()
	_menu.call_deferred("focus_default")


func _show_briefing() -> void:
	_begin_modal_pause()
	_menu.hide()
	_report.hide()
	_editor.hide()
	_briefing.set_mode(SimClock.sim_time <= 0.0)
	_briefing.refresh()
	_briefing.show()
	_briefing.call_deferred("focus_default")


func _hide_screens(restore_pause := true) -> void:
	_menu.hide()
	_briefing.hide()
	_editor.hide()
	if restore_pause:
		_restore_modal_pause_if_clear()
	if not _has_visible_modal():
		call_deferred("_focus_map_if_clear")


func _on_briefing_start() -> void:
	# TAKE COMMAND / RESUME is explicit intent to run the clock, even when the board was opened
	# from an already-paused picture. Clear the modal snapshot before resuming.
	_hide_screens(false)
	_modal_pause_captured = false
	_set_background_input_enabled(true)
	SimClock.set_paused(false)
	call_deferred("_focus_map_if_clear")


func _begin_modal_pause() -> void:
	if not _modal_pause_captured:
		_modal_was_paused = SimClock.paused
		_modal_pause_captured = true
	SimClock.set_paused(true)
	_set_background_input_enabled(false)


func _set_background_input_enabled(enabled: bool) -> void:
	map.keyboard_navigation_enabled = enabled
	var layout := $Layout as Control
	if enabled:
		for node in _background_focus_modes:
			if is_instance_valid(node):
				(node as Control).focus_mode = int(_background_focus_modes[node]) as Control.FocusMode
		_background_focus_modes.clear()
		return
	if _background_focus_modes.is_empty():
		var controls: Array[Node] = [layout]
		controls.append_array(layout.find_children("*", "Control", true, false))
		for node: Node in controls:
			var control := node as Control
			if control == null:
				continue
			_background_focus_modes[control] = control.focus_mode
			control.focus_mode = Control.FOCUS_NONE
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null and (owner == layout or layout.is_ancestor_of(owner)):
		owner.release_focus()


func _has_visible_modal() -> bool:
	return (_menu != null and _menu.visible) \
		or (_briefing != null and _briefing.visible) \
		or (_editor != null and _editor.visible) \
		or (_library != null and _library.visible) \
		or (_command_palette != null and _command_palette.visible) \
		or (_air_operations != null and _air_operations.visible) \
		or (_report != null and _report.visible)


func _restore_modal_pause_if_clear() -> void:
	if not _modal_pause_captured or _has_visible_modal():
		return
	var restore := _modal_was_paused
	_modal_pause_captured = false
	SimClock.set_paused(restore)
	_set_background_input_enabled(true)


func _toggle_air_operations() -> void:
	if _air_operations.visible:
		_close_air_operations(false)
		return
	if _has_visible_modal():
		return
	_begin_modal_pause()
	_air_operations.open_for(map.selected)


func _close_air_operations(execute := false) -> void:
	_air_operations.hide()
	if execute:
		_modal_was_paused = false
		SimClock.set_speed_index(0)
	_restore_modal_pause_if_clear()
	call_deferred("_focus_map_if_clear")


func _issue_air_order(u: Unit, order: Order) -> void:
	if u == null or not u.alive or u.faction != simulation.player_faction or not simulation.unit_manager.units.has(u):
		_air_operations.show_receipt("That airframe or host is no longer under your command.", false)
		return
	var before := u.launch_spots_busy()
	var accepted := simulation.unit_manager.issue_order(u, order)
	var message := ""
	if order.type == Order.Type.LAUNCH_AIRCRAFT:
		var launched := u.launch_spots_busy() - before
		var spec := DataDB.platform(order.aircraft_id)
		message = "%s: launching %d of %d × %s. Resume time to fly the sortie." % [u.callsign, launched, order.aircraft_count, spec.short_name if spec != null else order.aircraft_id] if accepted else simulation.aviation_manager.launch_rejection_reason(u, order.aircraft_id)
	else:
		message = "%s: return and land at %s. Recovery includes approach, landing, refuelling and rearming." % [u.callsign, order.recovery_base.callsign] if accepted and order.recovery_base != null else "Return order rejected: " + simulation.aviation_manager.recovery_rejection_reason(u, order.recovery_base)
	_air_operations.show_receipt(message, accepted)
	top_bar.flash(message, "good" if accepted else "warn")


func _toggle_library() -> void:
	if _library.visible:
		_close_library()
	else:
		_library_previous_focus = get_viewport().gui_get_focus_owner()
		_library_returns_to_menu = _menu.visible
		_begin_modal_pause()
		if _library_returns_to_menu:
			# The gallery is a full-screen surface, so the mission menu must not remain in
			# the keyboard focus chain behind it.
			_menu.hide()
		_library.show()
		_library.call_deferred("focus_default")


func _close_library() -> void:
	_library.hide()
	if _library_returns_to_menu:
		_library_returns_to_menu = false
		_library_previous_focus = null
		_menu.show()
		_menu.call_deferred("focus_default")
		return
	_restore_modal_pause_if_clear()
	if is_instance_valid(_library_previous_focus) and _library_previous_focus.is_visible_in_tree():
		_library_previous_focus.call_deferred("grab_focus")
	_library_previous_focus = null


func _close_report() -> void:
	_report.hide()
	_set_background_input_enabled(true)
	call_deferred("_focus_map_if_clear")


func _focus_map_if_clear() -> void:
	if not _has_visible_modal() and map.focus_mode != Control.FOCUS_NONE:
		map.grab_focus()


func _inspect_asset(id: String, weapon := false) -> void:
	if not _library.visible:
		_toggle_library()
	_library.inspect(id, weapon)


func _toggle_command_palette() -> void:
	if _command_palette.visible:
		_command_palette.close_palette()
		return
	# Avoid stacking a second modal over the mission selector, briefing, editor, gallery, or report.
	if _has_visible_modal():
		return
	# Snapshot action state while the mission is still in its real running/paused state. The
	# palette's modal pause is presentation-only and must not make its Pause row lie.
	var actions := _palette_actions()
	_command_palette.set_actions(actions)
	_command_palette.open_palette()
	# Open first so the palette can remember the invoking control before modal isolation releases it.
	_begin_modal_pause()


func _palette_actions() -> Array[Dictionary]:
	var controllable := _all_controllable(map.selected)
	var movable := _all_movable(map.selected)
	var has_target := map.selected_track != null
	var contacts := contact_panel.visible_track_count()
	var radar_state := orders_panel._selection_state("radar")
	var sonar_state := orders_panel._selection_state("sonar")
	var emcon_state := orders_panel._selection_state("emcon")
	var actions: Array[Dictionary] = [
		{"id": "plot_move", "label": "Plot move", "description": "Arm a visible left-click route order; Shift chains waypoints.", "shortcut": "G", "enabled": movable, "state": "armed" if map.interaction_mode == TacticalMap.InteractionMode.MOVE else "off", "reason": "Select a deployed mobile platform first."},
		{"id": "open_engagement", "label": "Open engagement solution", "description": "Show weapon, range, time-of-flight, and fire controls for the hooked contact.", "shortcut": "", "enabled": controllable and has_target, "state": map.selected_track.id if has_target else "no target", "reason": "Select a shooter and a contact first."},
		{"id": "next_contact", "label": "Next priority contact", "description": "Cycle hostile, unknown, fresh, and nearby contacts first.", "shortcut": "N", "enabled": contacts > 0, "state": "%d held" % contacts, "reason": "No contacts are held."},
		{"id": "previous_contact", "label": "Previous priority contact", "description": "Cycle backward through the priority contact stack.", "shortcut": "Shift+N", "enabled": contacts > 0, "state": "%d held" % contacts, "reason": "No contacts are held."},
		{"id": "focus_selection", "label": "Focus selection and target", "description": "Center one item or fit the complete shooter-target problem.", "shortcut": "C", "enabled": not map.selected.is_empty() or has_target, "reason": "Select a platform or contact first."},
		{"id": "follow_selection", "label": "Follow selection or target", "description": "Keep the hooked contact or single selected platform centered.", "shortcut": "F", "enabled": map.selected.size() == 1 or has_target, "state": "on" if map.follow_selection else "off", "reason": "Select one platform or hook a contact first."},
		{"id": "fit_fleet", "label": "Fit friendly force", "description": "Recover the camera by framing every deployed friendly unit.", "shortcut": "Home", "enabled": true},
		{"id": "fit_theatre", "label": "Fit operation area", "description": "Return to the scenario's full chart extent.", "shortcut": "", "enabled": true},
		{"id": "toggle_radar", "label": "Toggle radar", "description": "Mixed or silent selections converge active; all-active selections go silent.", "shortcut": "R", "enabled": controllable and radar_state >= 0, "state": _state_name(radar_state, "off", "on"), "reason": "The selection has no controllable radar."},
		{"id": "toggle_sonar", "label": "Toggle active sonar", "description": "Mixed or passive selections converge active; all-active selections go passive.", "shortcut": "P", "enabled": controllable and sonar_state >= 0, "state": _state_name(sonar_state, "passive", "active"), "reason": "The selection has no controllable sonar."},
		{"id": "toggle_emcon", "label": "Toggle emission control", "description": "Switch the selection between silent and free emissions.", "shortcut": "E", "enabled": controllable, "state": _state_name(emcon_state, "free", "silent"), "reason": "Select a controllable platform first."},
		{"id": "toggle_sensors", "label": "Sensor coverage layer", "description": "Show detection ranges for the current selection.", "shortcut": "F4", "enabled": true, "state": "on" if map.show_rings else "off"},
		{"id": "toggle_vectors", "label": "Motion vectors layer", "description": "Show projected courses for units and tracks.", "shortcut": "V", "enabled": true, "state": "on" if map.show_vectors else "off"},
		{"id": "toggle_trails", "label": "Track trails layer", "description": "Show recent movement history.", "shortcut": "F5", "enabled": true, "state": "on" if map.show_trails else "off"},
		{"id": "toggle_terrain", "label": "Terrain detail layer", "description": "Show charted land fill and coastline detail.", "shortcut": "F6", "enabled": true, "state": "on" if map.show_terrain else "off"},
		{"id": "toggle_key", "label": "Map symbol key", "description": "Show identification and map-control guidance.", "shortcut": "F2", "enabled": true, "state": "on" if map.show_key else "off"},
		{"id": "toggle_range_grid", "label": "Reference range grid", "description": "Show concentric ranges around the picture reference.", "shortcut": "", "enabled": true, "state": "on" if map.show_range_grid else "off"},
		{"id": "toggle_pause", "label": "Pause or resume time", "description": "Stop or resume simulation time without changing acceleration.", "shortcut": "Space", "enabled": true, "state": "paused" if SimClock.paused else "running"},
		{"id": "briefing", "label": "Mission briefing and help", "description": "Review objectives, failure conditions, environment, and controls.", "shortcut": "F1", "enabled": true},
		{"id": "library", "label": "Fleet and ordnance gallery", "description": "Inspect platform and weapon capabilities.", "shortcut": "F7", "enabled": true},
		{"id": "air_operations", "label": "Air operations: launch and recover", "description": "Select aircraft types, manage sorties, and choose a carrier or airfield for landing.", "shortcut": "F3", "enabled": true},
	]
	for i in SimClock.SPEEDS.size():
		actions.append({"id": "speed_%d" % i, "label": "Set time to %d×" % int(SimClock.SPEEDS[i]), "description": "Set simulation acceleration; time remains paused until resumed.", "shortcut": str(i + 1), "enabled": true, "state": "selected" if SimClock.speed_index == i else ""})
	return actions


func _state_name(state: int, off_name: String, on_name: String) -> String:
	if state < 0:
		return "unavailable"
	if state == 2:
		return "mixed"
	return on_name if state == 1 else off_name


func _run_palette_action(id: String) -> void:
	match id:
		"plot_move":
			map.set_move_mode(map.interaction_mode != TacticalMap.InteractionMode.MOVE)
			map.grab_focus()
		"open_engagement":
			orders_panel.open_engagement()
		"next_contact":
			_cycle_priority_track(1)
		"previous_contact":
			_cycle_priority_track(-1)
		"focus_selection":
			map.center_on_selection()
		"follow_selection":
			map.set_follow_selection(not map.follow_selection)
		"fit_fleet":
			map.fit_to_fleet()
		"fit_theatre":
			map.fit_to(simulation.map_center, simulation.map_extent_nm)
		"toggle_radar":
			_toggle_radar_on_selection()
		"toggle_sonar":
			_toggle_sonar_on_selection()
		"toggle_emcon":
			_toggle_emcon_on_selection()
		"toggle_sensors":
			map.toggle_layer("sensors")
		"toggle_vectors":
			map.toggle_layer("vectors")
		"toggle_trails":
			map.toggle_layer("trails")
		"toggle_terrain":
			map.toggle_layer("terrain")
		"toggle_key":
			map.toggle_layer("key")
		"toggle_range_grid":
			map.toggle_layer("range_grid")
		"toggle_pause":
			SimClock.toggle_pause()
		"briefing":
			_show_briefing()
		"library":
			_toggle_library()
		"air_operations":
			_toggle_air_operations()
		_:
			if id.begins_with("speed_"):
				SimClock.set_speed_index(int(id.trim_prefix("speed_")))


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_K and (k.meta_pressed or k.ctrl_pressed):
		_toggle_command_palette()
		get_viewport().set_input_as_handled()
		return
	# Full-screen surfaces own the keyboard. Their close shortcuts are handled here, but map and
	# time hotkeys cannot leak through and change a mission behind a modal.
	if _command_palette.visible:
		return
	if _air_operations.visible:
		if k.keycode in [KEY_F3, KEY_ESCAPE]:
			_close_air_operations(false)
			get_viewport().set_input_as_handled()
		return
	if _library.visible:
		if k.keycode in [KEY_F7, KEY_ESCAPE]:
			_close_library()
			get_viewport().set_input_as_handled()
		return
	if _editor.visible:
		if k.keycode in [KEY_F8, KEY_F9, KEY_ESCAPE]:
			_show_menu()
			get_viewport().set_input_as_handled()
		return
	if _menu.visible:
		if k.keycode in [KEY_F9, KEY_ESCAPE] and simulation.scenario_path != "":
			_hide_screens()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_F8:
			_show_editor()
			get_viewport().set_input_as_handled()
		return
	if _briefing.visible:
		if k.keycode in [KEY_F1, KEY_ESCAPE]:
			_hide_screens()
			get_viewport().set_input_as_handled()
		return
	if _report.visible:
		if k.keycode == KEY_ESCAPE:
			_close_report()
		elif k.keycode == KEY_F10:
			restart_scenario()
		elif k.keycode == KEY_F9:
			_show_menu()
		else:
			return
		get_viewport().set_input_as_handled()
		return
	match k.keycode:
		KEY_F3:
			_toggle_air_operations()
		KEY_F7:
			_toggle_library()
		KEY_SPACE:
			SimClock.toggle_pause()
		KEY_ESCAPE:
			if not map.cancel_interaction_mode():
				map.clear_selection()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			SimClock.set_speed_index(k.keycode - KEY_1)
		KEY_F2:
			map.toggle_layer("key")
		KEY_F4:
			map.toggle_layer("sensors")
		KEY_F5:
			map.toggle_layer("trails")
		KEY_F6:
			map.toggle_layer("terrain")
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
		KEY_G:
			map.set_move_mode(map.interaction_mode != TacticalMap.InteractionMode.MOVE)
		KEY_F:
			map.set_follow_selection(not map.follow_selection)
		KEY_V:
			map.toggle_layer("vectors")
		KEY_N:
			_cycle_priority_track(-1 if k.shift_pressed else 1)
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
	# The dock retains ownership/capability permission, then recalculates whether the
	# selection is actively commandable as aircraft launch, recover, or are stowed.
	orders_panel.set_units(units, _all_command_authorized(units), _all_mobile_command_authorized(units))
	orders_panel.set_target_track(map.selected_track)


func _on_track_selected(t: Track) -> void:
	contact_panel.refresh()
	orders_panel.set_target_track(t)
	if t != null:
		orders_panel.open_engagement()


func _cycle_priority_track(step: int) -> void:
	var next := contact_panel.cycle_visible_track(step)
	if next == null:
		top_bar.flash("No contacts held on this picture", "warn")
		return
	top_bar.flash("TARGET %s · %s %s" % [next.id, next.identity, next.domain.to_upper()], "alert" if next.identity == "HOSTILE" else "info")


func _focus_urgent_threat() -> void:
	var threats := AirDefence.inbound_threats(simulation.unit_manager, simulation.threat_manager, simulation.player_faction, map.reference_unit())
	if threats.is_empty():
		top_bar.flash("No inbound weapon is held on this picture")
		return
	var entry: Dictionary = threats[0]
	var weapon: Weapon = entry["weapon"]
	var target: Unit = entry["target"]
	map.set_follow_selection(false)
	map.fit_to((weapon.position + target.position) * 0.5, maxf(weapon.position.distance_to(target.position) * 1.55 + 4.0, 12.0))
	top_bar.flash("FOCUS · %s inbound to %s · impact in ~%d s" % [weapon.spec.display_name, target.callsign, maxi(int(entry["time_s"]), 0)], "alert")


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


## Decoys pulled a round off one ship and it found another. Worth saying out loud: the escort's
## chaff has just handed the missile to whoever was behind it.
func _on_weapon_seduced(threat: Weapon, from_unit: Unit, to_unit: Unit) -> void:
	var own := to_unit.faction == simulation.player_faction
	map.add_effect(threat.position, "decoy")
	if own or from_unit.faction == simulation.player_faction:
		top_bar.flash("%s decoyed off %s — re-acquired %s" % [threat.spec.display_name, from_unit.callsign, to_unit.callsign], "alert" if own else "warn")
	print("[Defence] %s decoyed off %s, re-acquired %s" % [threat.spec.display_name, from_unit.callsign, to_unit.callsign])


## Fire and flooding aboard. Only our own ships report; an enemy's fight for its ship is not ours
## to see, and its loss already arrives as a destruction.
func _on_casualty_event(u: Unit, event: String) -> void:
	if event == "lost":
		_foundered[u] = true
	print("[Damage] %s %s" % [u.callsign, event])
	if u.faction != simulation.player_faction:
		return
	match event:
		"fire_out":
			top_bar.flash("%s: fire out" % u.callsign, "good")
		"flooding_controlled":
			top_bar.flash("%s: flooding under control" % u.callsign, "good")


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
		var casualties := ""
		if target.fire > 0.0:
			casualties += " · FIRE"
		if target.flooding > 0.0:
			casualties += " · FLOODING"
		top_bar.flash("%s HIT — %s%s" % [target.callsign, Damage.condition_text(target), casualties], "alert")
	else:
		top_bar.flash("HIT on %s — %.0f%% remaining" % [target.callsign, Damage.health_fraction(target) * 100.0], "good")
	print("[Combat] %s hit %s (%s, %.0f%%)" % [spec.display_name, target.callsign, Damage.condition_text(target), Damage.health_fraction(target) * 100.0])


func _on_unit_destroyed(u: Unit, killer_faction: String) -> void:
	SimClock.drop_to_realtime()
	map.add_effect(u.position, "destroyed", u.faction == simulation.player_faction)
	SoundFx.play("impact", 0.0)
	var how := "LOST TO FIRE AND FLOODING" if _foundered.has(u) else "DESTROYED"
	if u.faction == simulation.player_faction:
		_losses.append(u.callsign)
		top_bar.flash("%s %s" % [u.callsign, how], "alert")
	else:
		if killer_faction == simulation.player_faction:
			_kills.append(u.callsign)
		top_bar.flash("%s %s" % [u.callsign, how], "good")
	print("[Combat] %s destroyed by %s" % [u.callsign, killer_faction])


func _on_engagement_rejected(shooter: Unit, spec: WeaponSpec, reason: String) -> void:
	if shooter.faction == simulation.player_faction:
		top_bar.flash("%s cannot fire %s: %s" % [shooter.callsign, spec.display_name, reason], "warn")


func _on_mission_ended(result: String, summary: String) -> void:
	SimClock.set_paused(true)
	_set_background_input_enabled(false)
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


## One order goes to every selected unit. The acknowledgement makes group commands legible: a
## mixed force may accept an order only on the platforms that support it, and that is never silent.
func _apply_order_to_selection(order: Order) -> void:
	var accepted := 0
	var refused := 0
	for u in map.selected:
		if u.faction == simulation.player_faction:
			if simulation.unit_manager.issue_order(u, order):
				accepted += 1
			else:
				refused += 1
	var attempted := accepted + refused
	if accepted > 0:
		SoundFx.play("click", 0.05)
		var receipt := "✓ %s · %d accepted" % [order.describe(), accepted]
		if refused > 0:
			receipt += " / %d refused" % refused
		top_bar.flash(receipt, "warn" if refused > 0 else "good")
		if order.type == Order.Type.MOVE and not Terrain.is_empty():
			for u in map.selected:
				if u.faction == simulation.player_faction and u.needs_sea_room() and Terrain.first_land_contact(u.position, order.target_pos) >= 0.0:
					top_bar.flash("%s: land on that course — it will follow the coast" % u.callsign, "warn")
					break
	elif attempted > 0:
		top_bar.flash("Order refused by %d selected platform%s%s" % [refused, "" if refused == 1 else "s", " — pick a point in the water" if order.type == Order.Type.MOVE else ""], "warn")
		if order.type == Order.Type.MOVE:
			map.add_effect(order.target_pos, "refused")
	else:
		top_bar.flash("Select a controllable platform first", "warn")


func _toggle_radar_on_selection() -> void:
	var capable := 0
	var active := 0
	for u in map.selected:
		if u.has_radar():
			capable += 1
			if u.radar_on:
				active += 1
	if capable == 0:
		top_bar.flash("The selection has no radar", "warn")
		return
	_apply_order_to_selection(Order.silence_radar() if active == capable else Order.activate_radar())


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
	var state := orders_panel._selection_state("emcon")
	if state < 0:
		top_bar.flash("Select a controllable platform first", "warn")
		return
	# OFF/FREE and MIXED both converge to SILENT; only an all-silent selection returns FREE.
	_apply_order_to_selection(Order.set_emcon(state != 1))


func _toggle_sonar_on_selection() -> void:
	var capable := 0
	var active := 0
	for u in map.selected:
		if u.has_sonar():
			capable += 1
			if u.active_sonar_on:
				active += 1
	if capable == 0:
		top_bar.flash("The selection has no sonar", "warn")
		return
	_apply_order_to_selection(Order.passive_sonar() if active == capable else Order.active_sonar())
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
	if not _all_command_authorized(units):
		return false
	for u: Unit in units:
		# Hangar/deck aircraft remain inspectable in the roster, but they are not an active
		# command element until launch. Keeping this gate aligned with UnitManager avoids a
		# dock full of actions that will all be refused.
		if not u.is_engageable():
			return false
	return true


func _all_command_authorized(units: Array) -> bool:
	if units.is_empty():
		return false
	for u: Unit in units:
		if u.faction != simulation.player_faction or not u.alive:
			return false
	return true


func _all_mobile_command_authorized(units: Array) -> bool:
	if not _all_command_authorized(units):
		return false
	for u: Unit in units:
		if u.spec.max_speed_kn <= 0.0:
			return false
	return true


func _all_movable(units: Array) -> bool:
	if not _all_controllable(units):
		return false
	for u: Unit in units:
		if not u.is_engageable() or u.spec.max_speed_kn <= 0.0 or (u.is_aircraft() and not u.airborne()):
			return false
	return true
