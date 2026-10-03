class_name Main
extends Control
## Main entry point. Wires the simulation layer to the presentation layer and handles
## global hotkeys. Dev flags (after `--`) are handled by DevHarness.

const GAME_TITLE := "NAVAL FLEET COMMAND"
const BUILD_MILESTONE := "M33 / Command Intent"
const DEFAULT_SCENARIO := "res://data/scenarios/northern_passage.json"
## Flags that mean the session is being driven programmatically, so the menu and briefing are
## skipped and the simulation is left ready to be advanced.
const SCRIPTED_FLAGS := ["--weapon-control-smoke", "--fleet-workshop-smoke", "--cold-war-smoke", "--aviation-smoke", "--open-air-ops", "--combat", "--defence", "--defence-once", "--engage-once", "--smoke", "--dump", "--autoplay", "--reload-check", "--ping", "--autopilot", "--select", "--move-mode", "--open-palette"]

@onready var simulation: Simulation = %Simulation
@onready var map: TacticalMap = %TacticalMap
@onready var unit_panel: UnitPanel = %UnitPanel
@onready var orders_panel: OrdersPanel = %OrdersPanel
@onready var contact_panel: ContactPanel = %ContactPanel
@onready var data_display: DataDisplay = %DataDisplay
@onready var status_boards: StatusBoards = %StatusBoards
@onready var _upper: Control = %Upper
@onready var _bottom_strip: HBoxContainer = %BottomStrip
@onready var _regional_frame: BevelFrame = %RegionalFrame
@onready var _view_frame: BevelFrame = %ViewFrame

## The message traffic: the radio line on the chart, the data display's lamp and the comms board.
var radio := RadioNet.new()
## The crew you can hear: spoken phrases for command-screen events, never the radio text itself.
var voice: CrewVoice
var _control_groups: Dictionary = {}
var regional: RegionalMap

var _library: PlatformLibrary
var _report: AfterAction
var _editor: ScenarioEditor
var _menu: ScenarioMenu
var _briefing: BriefingPanel
var _command_guide: CommandGuide
var _command_palette: CommandPalette
var _air_operations: AirOperations
## The Air Operations dialog has handed the chart over to pick a station or a strike target.
var _air_picking := false
var _saves: SavedEngagements
## Simulated time of the last autosave in this engagement.
var _autosaved_at := 0.0
## Autosave in play only. Any run with command-line arguments (the test suites, the validation
## tools, the dev harness) leaves the player's saves alone, as it does their settings.
var _autosave_enabled := OS.get_cmdline_user_args().is_empty()
var _fleet_operations: FleetOperations
var _weapon_control: WeaponControl
var _modal_pause_captured := false
var _modal_was_paused := true
var _background_focus_modes: Dictionary = {}
var _library_previous_focus: Control
var _library_returns_to_menu := false
var _objective_accum := 0.0
## G swaps the chart and the 3D view between the top area and the bottom-centre pane; F10 gives
## the 3D view the whole window.
var _views_swapped := false
var _world_full := false
var _cds_menus: CdsMenus
var _key_help: KeyCommands
var _command_taken := false  # the player has taken command of the loaded operation
var _scripted_session := false  # a dev-harness run: graded on the debrief, never logged
## A player's session (no command-line arguments): each start of an operation draws its events
## afresh. A driven run or a pinned --seed keeps the scenario's own draw, so it repeats exactly.
var _fresh_draws := false
var _restart_armed_ms := -100000
const RESTART_CONFIRM_MS := 4000
var _world_view: WorldView
var command_bar: CommandBar
var _dev: DevHarness
var _stats := {}
var _losses: PackedStringArray = []
var _kills: PackedStringArray = []
var _civilian_incidents: PackedStringArray = []
## Inbound rounds the side has detected but the commander's picture does not hold yet (seen only by
## a consort off the link). Each is announced once, when it reaches the picture.
var _unannounced: Array[Weapon] = []
var _foundered: Dictionary = {}  # Unit -> true, lost to fire or flooding rather than outright
## The gameplay options in effect (time ladder, missile defence, engagement after identification,
## voice and ambient). Usually the player's stored preference; a restored engagement plays under
## its own until the next operation starts (apply_engagement_options).
var options := GameOptions.normal()
## The player's preference: what the desk, a new operation and a restart use. A driven run (any
## command-line argument) plays Normal, or the --preset= it names, and never reads or saves it.
var _preferred := GameOptions.normal()
var _options_from_engagement := false
## A smoke, a probe, a sweep or a screenshot: the sound devices and the stored settings are left alone.
var _driven_run := false


func _ready() -> void:
	theme = UITheme.build()
	# Behind the command screen's panes; it shows only while a pane is loading.
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color.BLACK
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	move_child(backdrop, 0)
	unit_panel.roster.map = map
	unit_panel.inspect_requested.connect(_inspect_asset)
	orders_panel.inspect_requested.connect(func(id: String) -> void: _inspect_asset(id, true))
	# The old command dock lives on the status boards now; the chart has the top of the screen.
	status_boards.host(orders_panel, StatusBoards.BOARD_ORDERS, false)
	status_boards.host(unit_panel, StatusBoards.BOARD_TASK_GROUP)
	status_boards.host(contact_panel, StatusBoards.BOARD_TRACKS)
	status_boards.finish_boards()
	status_boards.hide()
	status_boards.closed.connect(_focus_map_if_clear)
	status_boards.visibility_changed.connect(_sync_overlay)
	radio.map = map
	radio.display = data_display
	radio.boards = status_boards
	radio.logged.connect(unit_panel.add_event)
	voice = CrewVoice.new()
	voice.name = "CrewVoice"
	voice.muted = func() -> bool: return not SoundFx.enabled
	add_child(voice)
	data_display.map = map
	data_display.simulation = simulation
	data_display.pause_requested.connect(SimClock.toggle_pause)
	data_display.scale_step_requested.connect(func(step: int) -> void: _set_time_scale(SimClock.speed_index + step))
	data_display.messages_requested.connect(_on_message_lamp)
	status_boards.comms_shown.connect(func() -> void: data_display.unread_alerts = 0)
	data_display.threat_requested.connect(_focus_urgent_threat)
	regional = RegionalMap.new()
	regional.name = "RegionalMap"
	regional.map = map
	_regional_frame.add_child(regional)
	_bottom_strip.resized.connect(_fit_bottom_strip)
	_cds_menus = CdsMenus.new()
	_cds_menus.name = "CdsMenus"
	_cds_menus.theme_source = theme
	_cds_menus.action_chosen.connect(_run_cds_action)
	_cds_menus.menu_closed.connect(func() -> void: map.menu_open = false)
	add_child(_cds_menus)
	orders_panel.weapon_manager = simulation.weapon_manager
	orders_panel.threat_manager = simulation.threat_manager
	map.unit_manager = simulation.unit_manager
	map.track_manager = simulation.track_manager
	map.weapon_manager = simulation.weapon_manager
	map.threat_manager = simulation.threat_manager
	map.aviation_manager = simulation.aviation_manager
	map.simulation = simulation
	map.player_faction = simulation.player_faction
	_world_view = WorldView.new()
	_world_view.name = "WorldView"
	_world_view.map = map
	_world_view.simulation = simulation
	_world_view.swap_requested.connect(_swap_views)
	_world_view.fullscreen_requested.connect(_toggle_world_full)
	_view_frame.add_child(_world_view)
	map.context_menu_requested.connect(_on_map_context)
	contact_panel.track_manager = simulation.track_manager
	contact_panel.player_faction = simulation.player_faction
	contact_panel.map = map

	map.selection_changed.connect(_on_selection_changed)
	map.move_order_requested.connect(_on_move_order_requested)
	map.patrol_order_requested.connect(_apply_order_to_selection)
	map.mission_station_move_requested.connect(func(m: AirMission, at: Vector2) -> void: _revise_chart_mission(m, at, m.radius_nm))
	map.mission_radius_change_requested.connect(func(m: AirMission, radius: float) -> void: _revise_chart_mission(m, m.station, radius))
	map.escort_station_move_requested.connect(_move_escort_station)
	map.engage_requested.connect(_on_engage_requested)
	map.attack_requested.connect(func(t: Track) -> void: _apply_order_to_selection(Order.attack(t)))
	map.intercept_requested.connect(func(w: Weapon) -> void: _apply_order_to_selection(Order.intercept(w)))
	map.investigate_requested.connect(func(t: Track) -> void: _apply_order_to_selection(Order.investigate(t)))
	map.waypoint_delete_requested.connect(_on_waypoint_delete_requested)
	map.interaction_mode_changed.connect(orders_panel.set_move_mode)
	orders_panel.order_requested.connect(_apply_order_to_selection)
	command_bar = CommandBar.new()
	command_bar.name = "CommandBar"
	command_bar.map = map
	command_bar.action_requested.connect(_run_palette_action)
	$Layout.add_child(command_bar)
	$Layout.move_child(command_bar, 1)
	orders_panel.unit_orders_requested.connect(_apply_unit_orders)
	orders_panel.formation_requested.connect(_apply_formation)
	orders_panel.move_mode_requested.connect(map.set_move_mode)
	orders_panel.emcon_toggle_requested.connect(_toggle_emcon_on_selection)
	orders_panel.air_operations_requested.connect(_toggle_air_operations)
	contact_panel.track_chosen.connect(map.select_track)
	map.track_selected.connect(_on_track_selected)
	orders_panel.weapon_selection_changed.connect(func(spec: WeaponSpec) -> void: map.weapon_ring = spec)
	simulation.weapon_manager.weapon_launched.connect(_on_weapon_launched)
	simulation.weapon_manager.round_fired.connect(_on_round_fired)
	simulation.weapon_manager.weapon_impact.connect(_on_weapon_impact)
	simulation.weapon_manager.unit_destroyed.connect(_on_unit_destroyed)
	simulation.weapon_manager.engagement_rejected.connect(_on_engagement_rejected)
	simulation.weapon_manager.interceptor_launched.connect(_on_interceptor_launched)
	simulation.weapon_manager.weapon_defeated.connect(_on_weapon_defeated)
	simulation.weapon_manager.weapon_seduced.connect(_on_weapon_seduced)
	simulation.weapon_manager.decoys_spent.connect(_on_decoys_spent)
	simulation.casualty_event.connect(_on_casualty_event)
	simulation.operation_message.connect(func(message: String) -> void:
		radio.flash(message, "info")
		Debug.event("[Operation] %s" % message))
	# New tasking: the order itself is the event's message above. Time drops to real time so it is
	# read, and the objective line and an open briefing read the objectives again.
	simulation.mission_manager.objectives_changed.connect(func() -> void:
		SimClock.drop_to_realtime()
		radio.set_objective_text(_objective_summary())
		if _briefing != null and _briefing.visible:
			_briefing.refresh())
	simulation.threat_manager.threat_detected.connect(_on_threat_detected)
	simulation.aviation_manager.aircraft_launched.connect(func(a: Unit, parent: Unit) -> void:
		if a.faction == simulation.player_faction:
			_stats["sorties"] = int(_stats.get("sorties", 0)) + 1
			radio.flash("Airborne from %s" % (parent.callsign if parent != null else "base"), "good", a)
			SoundFx.play("click")
		Debug.event("[Air] %s launched" % a.callsign))
	simulation.aviation_manager.aircraft_recovered.connect(func(a: Unit, _p: Unit) -> void:
		if a.faction == simulation.player_faction:
			radio.flash("Recovered", "info", a))
	simulation.aviation_manager.aircraft_bingo.connect(func(a: Unit) -> void:
		if a.faction == simulation.player_faction:
			SimClock.drop_to_realtime()
			radio.flash("Bingo fuel, returning", "warn", a)
			voice.say("aircraft_rtb", a))
	simulation.air_mission_manager.mission_report.connect(func(m: AirMission, message: String, good: bool) -> void:
		if m.faction == simulation.player_faction and not simulation.ai_plays_player:
			radio.flash(message, "info" if good else "warn", m.base))
	simulation.air_mission_manager.mission_ended.connect(func(m: AirMission, reason: String) -> void:
		if m.faction == simulation.player_faction and not simulation.ai_plays_player:
			radio.flash("%s %d ended: %s" % [m.label(), m.id, reason.to_lower()], "info", m.base))
	simulation.group_attack_manager.group_report.connect(func(g: GroupAttack, message: String, good: bool) -> void:
		if g.faction == simulation.player_faction and not simulation.ai_plays_player and g.members.all(func(u: Unit) -> bool: return _receives_report(u)):
			radio.flash(message, "info" if good else "warn", g.lead if g.lead != null and g.lead.alive else null))
	simulation.group_attack_manager.group_ended.connect(func(g: GroupAttack, reason: String) -> void:
		if g.faction == simulation.player_faction and not simulation.ai_plays_player and g.members.all(func(u: Unit) -> bool: return _receives_report(u)):
			radio.flash(g.note, "good" if reason in ["Target destroyed", "Targets destroyed"] else "info", g.lead if g.lead != null and g.lead.alive else null)
		Debug.event("[Combat] group attack %d on %s ended: %s, %d of %d rounds fired" % [g.id, g.target_label(), reason, g.fired_total, g.budget]))
	simulation.aviation_manager.aircraft_tanking.connect(func(a: Unit, tanker: Unit) -> void:
		if a.faction == simulation.player_faction and not simulation.ai_plays_player:
			radio.flash("Low fuel, joining %s to refuel" % tanker.callsign, "info", a))
	simulation.aviation_manager.aircraft_lost.connect(func(a: Unit, reason: String) -> void:
		if a.faction == simulation.player_faction:
			SimClock.drop_to_realtime()
			_losses.append(a.callsign)
			radio.flash("%s LOST — %s" % [a.callsign, reason], "alert", a)
			voice.say("unit_lost", null, {"name": a.callsign})
		Debug.event("[Air] %s lost: %s" % [a.callsign, reason]))
	simulation.aviation_manager.launch_rejected.connect(func(parent: Unit, reason: String) -> void:
		if parent.faction == simulation.player_faction:
			radio.flash("Cannot launch: %s" % reason, "warn", parent)
			voice.say("order_refused", parent))
	simulation.mission_manager.mission_ended.connect(_on_mission_ended)
	simulation.mission_manager.objective_completed.connect(func(o: MissionObjective, is_loss: bool) -> void:
		if not is_loss:
			radio.flash("OBJECTIVE COMPLETE — %s" % o.text, "good")
		Debug.event("[Mission] objective %s: %s" % ["failed" if is_loss else "complete", o.text]))
	_command_guide = CommandGuide.new()
	_command_guide.name = "CommandGuide"
	_command_guide.action_requested.connect(_run_palette_action)
	_command_guide.dismissed.connect(func() -> void: _briefing._guide.set_pressed_no_signal(false))
	add_child(_command_guide)
	_build_screens()
	# Reinforcements and every airframe take the side's missile-defence doctrine as they arrive.
	simulation.unit_manager.unit_added.connect(func(u: Unit) -> void:
		if u.faction == simulation.player_faction:
			if u.is_submarine():
				SubmarineComms.configure(u, options.submarine_comms and not simulation.ai_plays_player, simulation.unit_manager.now_s)
			_set_air_defence(u))
	simulation.track_manager.track_added.connect(_on_track_added)
	simulation.track_manager.track_classified.connect(_on_track_classified)
	simulation.track_manager.track_lost.connect(_on_track_lost)
	simulation.unit_manager.order_issued.connect(func(u: Unit, o: Order) -> void:
		if u.faction == simulation.player_faction and not simulation.ai_plays_player:
			_command_guide.record_order(u, o)
			Debug.event("[Order] %s: %s" % [u.callsign, o.describe()]))
	simulation.unit_manager.investigation_ended.connect(func(u: Unit, t: Track, reason: String) -> void:
		if u.faction != simulation.player_faction or not _receives_report(u):
			return
		_command_guide.record_classification(u, t, reason)
		var report := "Track %s: %s" % [DataDisplay.track_number_for_track(t), reason.to_lower()]
		if reason == "Contact classified":
			report += " — " + t.description()
		radio.flash(report, "good" if reason == "Contact classified" else "warn", u))
	simulation.unit_manager.station_resumed.connect(func(u: Unit, reason: String) -> void:
		if u.faction != simulation.player_faction or simulation.ai_plays_player or not _receives_report(u):
			return
		radio.flash("%s: %s — resuming %s" % [u.callsign, reason, DataDisplay.station_name(u.station_label, false) if u.station_label != "" else "station"], "good", u))
	simulation.unit_manager.station_unavailable.connect(func(u: Unit, reason: String) -> void:
		if u.faction != simulation.player_faction or simulation.ai_plays_player or not _receives_report(u):
			return
		radio.flash("%s cannot return to station: %s" % [u.callsign, reason.to_lower()], "warn", u))
	simulation.unit_manager.attack_ended.connect(func(u: Unit, t: Track, reason: String) -> void:
		if u.faction != simulation.player_faction or simulation.ai_plays_player or not _receives_report(u):
			return
		var number := DataDisplay.track_number_for_track(t)
		if reason == "Target destroyed":
			radio.flash("Attack on track %s complete — target destroyed, %d rounds fired" % [number, u.attack_rounds_fired], "good", u)
		else:
			# The kill itself is already spoken when the unit is destroyed; only a broken-off attack is said here.
			radio.flash("Attack on track %s ended: %s" % [number, reason.to_lower()], "warn", u)
			voice.say("attack_broken_off", u, {"track": t}))

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
		elif a.begins_with("--fastforward=") or a.begins_with("--perf="):
			scripted = true
	_scripted_session = scripted
	if args.has("--autopilot"):
		simulation.ai_plays_player = true
	# Must be set before the scenario loads, since that is when the generators are seeded.
	var seed_value := int(DevHarness.arg(args, "--seed=", -1.0))
	if seed_value >= 0:
		simulation.seed_override = seed_value
		print("[Dev] seed pinned to %d" % seed_value)
	if scripted:
		SoundFx.enabled = false
	# A player launches with no arguments, in the browser or on the desktop. Anything else is a
	# driven run (a smoke, a probe, a screenshot), which never saves preferences and never reaches
	# the operating system's speech.
	_driven_run = scripted or CrewVoice.automated_run() or not args.is_empty()
	InterfaceScale.initialize(get_window(), _driven_run, args)
	if _driven_run:
		UserSettings.writable = false
		# Smokes and sweeps play Normal whatever the player chose, so their outcomes never depend on
		# someone's preference; --preset=classic asks for the Classic rules (sound is left alone).
		_preferred = GameOptions.classic() if args.has("--preset=classic") else GameOptions.normal(voice.enabled, SoundFx.ambient_enabled)
	else:
		_fresh_draws = true
		var silent := voice.configure_from_settings()
		if silent != "" and voice.enabled:
			Debug.event("[Voice] %s" % silent)
		_preferred = GameOptions.load_preferred()
	_apply_options(_preferred, false, not _driven_run)
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
	var t0 := Time.get_ticks_usec()
	var hooked: Unit = map.selected[0] if not map.selected.is_empty() else null
	SoundFx.set_ambient(_command_taken and not _menu.visible and not _editor.visible and not _report.visible, Detection.sea_state, SoundFx.hum_for(hooked))
	radio.set_objective_text(_objective_summary())
	_autosave_if_due()
	_announce_unannounced_threats()
	var threats := _commander_inbound()
	_command_guide.refresh(simulation.unit_manager, options, not threats.is_empty(), map.selected_track, not threats.is_empty() and (threats[0]["weapon"] as Weapon).spec.is_torpedo(), simulation.mission_manager)
	_command_guide.visible = _command_taken and _command_guide.enabled and not _has_visible_modal() and not status_boards.visible and not _views_swapped and not _world_full
	_command_guide.position = map.global_position - global_position + Vector2(14, 14)
	if threats.is_empty():
		radio.set_alert("")
	else:
		# The banner, countdown, and click-to-focus all describe the same highest-priority threat.
		var primary: Dictionary = threats[0]
		var weapon: Weapon = primary["weapon"]
		var label := "TORPEDO IN THE WATER" if weapon.spec.is_torpedo() else ("BALLISTIC INBOUND" if weapon.threat_class() == "ballistic" else "MISSILE INBOUND")
		# On manual missile defence the SAMs wait for the commander: say which key sends them.
		var cue := " - X ENGAGES" if options.manual_missile_defence() and not weapon.spec.is_torpedo() and weapon.intercept_cleared.is_empty() else ""
		radio.set_alert("%s - %d - %d s%s" % [label, threats.size(), maxi(int(primary["time_s"]), 0), cue])
	Debug.time_add("shell", Time.get_ticks_usec() - t0)


func _objective_summary() -> String:
	var mm := simulation.mission_manager
	for o in mm.victory_objectives:
		if not o.complete:
			return "%s  (%s)" % [o.text, o.progress(simulation.unit_manager, SimClock.sim_time)]
	return "objectives complete" if not mm.victory_objectives.is_empty() else ""


# --- Scenario lifecycle -------------------------------------------------------------------

func start_scenario(path: String) -> void:
	_close_engagement_dialogs()
	# A new operation (from the desk, a restart, the editor) is played under the player's own
	# options, even after a restored engagement brought its own.
	if _options_from_engagement:
		_options_from_engagement = false
		_apply_options(_preferred, false, not _driven_run)
	# A player's start draws the operation's events afresh. A driven run or a pinned --seed plays the
	# scenario's own draw, even after a restored engagement brought its own variation with it.
	simulation.variation_seed = randi() % 1000000 if _fresh_draws and simulation.seed_override < 0 else -1
	if not simulation.load_scenario(path):
		push_error("Main: failed to load scenario %s" % path)
		return
	_reset_command_screen()
	_briefing.configure(simulation.scenario_name, simulation.scenario.get("forces", ""), simulation.scenario.get("description", ""), simulation.scenario.get("environment", {}), simulation.scenario)
	_briefing.set_mode(true)
	var coast := "" if Terrain.is_empty() else ", %d landmass%s charted" % [Terrain.landmasses.size(), "" if Terrain.landmasses.size() == 1 else "es"]
	radio.flash("%s loaded — sea state %d, %s%s" % [simulation.scenario_name, Detection.sea_state, Detection.sea_state_name(), coast])


func _close_engagement_dialogs() -> void:
	_control_groups.clear()
	if data_display != null:
		data_display.close_details()
	if _weapon_control != null:
		_weapon_control.hide()
	if _fleet_operations != null:
		_fleet_operations.hide()
	if _air_operations != null:
		_air_operations.hide()
		_air_operations.clear_selection()
	if _air_picking:
		# Cleared first, so the map's cancellation does not reopen Air Operations.
		_air_picking = false
		map.cancel_interaction_mode()


## The command screen as a fresh engagement finds it: panels closed and empty, the chart fitted, the
## radio and the after-action counters cleared. A new mission and a loaded one both start here.
func _reset_command_screen() -> void:
	SimClock.set_paused(true)
	SimClock.set_speed_index(0)
	_apply_doctrine()
	_command_taken = false
	_command_guide.reset(str(simulation.scenario.get("id", "")), simulation.player_faction)
	# A replacement scenario starts behind its own briefing. Rebase any older modal snapshot so
	# dismissing that briefing can never inherit a running state from the previous mission.
	_modal_pause_captured = true
	_modal_was_paused = true
	_set_background_input_enabled(false)
	map.clear_selection()
	map.weapon_ring = null
	map.reset_presentation()
	if _world_view != null:
		_world_view.reset_presentation()
	# A new operation opens on the command screen's own layout, and its chart is fitted once the
	# top area has been laid out again (bringing the bottom strip back only queues that).
	if _views_swapped or _world_full:
		_views_swapped = false
		_world_full = false
		_arrange_views()
	var chart: Dictionary = simulation.scenario.get("map", {})
	var focus: Array = chart.get("focus_center_nm", [simulation.map_center.x, simulation.map_center.y])
	map.fit_to(Vector2(focus[0], focus[1]), float(chart.get("focus_extent_nm", simulation.map_extent_nm)))
	map.call_deferred("fit_to", Vector2(focus[0], focus[1]), float(chart.get("focus_extent_nm", simulation.map_extent_nm)))
	radio.clear()
	voice.stop()
	radio.set_scenario_name(simulation.scenario_name)
	status_boards.close_boards()
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
	_civilian_incidents = PackedStringArray()
	_foundered.clear()
	_unannounced.clear()
	_report.hide()
	_autosaved_at = SimClock.sim_time


# --- Saved engagements -----------------------------------------------------------------------

## Whether the running engagement can be saved now, or the reason it cannot.
func save_refusal() -> String:
	if not _command_taken:
		return "Take command of an operation first"
	if simulation.mission_manager.result != MissionManager.Result.RUNNING:
		return "The engagement has ended"
	if simulation._in_tick:
		return "Wait for the simulation step to finish"
	return ""


## Writes the running engagement to a slot. `kind` is quick, auto or manual. Returns "" or why not.
func save_engagement(slot: String, kind: String, label: String) -> String:
	var why := save_refusal()
	if why != "":
		return why
	var snapshot := simulation.capture_snapshot()
	if snapshot.is_empty() or not (snapshot.get("errors", []) as Array).is_empty():
		return "The engagement could not be captured: %s" % ", ".join(snapshot.get("errors", ["mid-step"]))
	var header := {
		"serial": SaveGame.next_serial(),
		"label": label,
		"kind": kind,
		"scenario_name": simulation.scenario_name,
		"scenario_id": str(simulation.scenario.get("id", "")),
		"sim_time": SimClock.sim_time,
		"clock_text": SimClock.datetime_string(),
		"elapsed_text": Geo.format_duration(SimClock.sim_time),
		"created_unix": int(Time.get_unix_time_from_system()),
		"version": SimSnapshot.VERSION,
		"build": BUILD_MILESTONE,
		"note": _objective_summary(),
		"gameplay": options.label(),
	}
	return SaveGame.write(SaveGame.slot_path(slot), header, {"simulation": snapshot, "presentation": _capture_presentation()})


func quicksave() -> void:
	var why := save_engagement(SaveGame.QUICKSAVE, "quick", "Quicksave")
	if why == "":
		radio.advise("Quicksaved at %s. Ctrl+Shift+L returns here." % SimClock.datetime_string())
	else:
		radio.advise("Cannot save: " + why)


func quickload() -> void:
	var path := SaveGame.slot_path(SaveGame.QUICKSAVE)
	if not FileAccess.file_exists(path):
		radio.advise("No quicksave yet. Ctrl+Shift+S saves the engagement.")
		return
	var why := load_engagement(path)
	if why != "":
		radio.advise("Cannot load: " + why)


## Replaces the running engagement with a saved one. The simulation refuses a damaged, foreign or
## newer save before anything changes; the screen then takes up the saved record: the journal,
## the after-action counters, the track numbers, the hooked platforms and the view.
func load_engagement(path: String) -> String:
	var file := SaveGame.read(path)
	if str(file.get("error", "")) != "":
		return str(file["error"])
	var payload: Dictionary = file["payload"]
	var validation := SimSnapshot.validate(payload.get("simulation"))
	if validation != "":
		return validation
	# Validation checks the save's shape and every reference before anything changes, but the
	# restore still replaces the running engagement before it finishes. Keep a copy to put back.
	var kept := {}
	if save_refusal() == "":
		kept = {"simulation": simulation.capture_snapshot(), "presentation": _capture_presentation()}
	var why := _install_engagement(payload)
	if why == "":
		var own_rules := " under its own gameplay options, %s," % options.label() if _options_from_engagement else ""
		radio.advise("Engagement restored at %s,%s paused. Space resumes." % [SimClock.datetime_string(), own_rules])
		return ""
	if not kept.is_empty() and _install_engagement(kept) == "":
		return why + ". The running engagement was kept"
	# Nothing to go back to: start the operation over rather than leave a half-built one.
	start_scenario(simulation.scenario_path)
	return why


func _install_engagement(payload: Dictionary) -> String:
	_close_engagement_dialogs()
	_hide_screens()
	var why := simulation.restore_snapshot(payload["simulation"])
	if why != "":
		return why
	# The engagement goes on under the gameplay options it was saved with, put in place before the
	# screen is reset: the doctrine the simulation restored already agrees with them, so the reset
	# issues no order, and the clock, chip and menus show the saved ladder from the first frame.
	var presentation: Variant = payload.get("presentation", {})
	var saved_options: Variant = presentation.get("options", {}) if typeof(presentation) == TYPE_DICTIONARY else {}
	apply_engagement_options(saved_options if typeof(saved_options) == TYPE_DICTIONARY else {}, false)
	_reset_command_screen()
	_briefing.configure(simulation.scenario_name, simulation.scenario.get("forces", ""), simulation.scenario.get("description", ""), simulation.scenario.get("environment", {}), simulation.scenario)
	_briefing.set_mode(false)
	_restore_presentation(payload.get("presentation", {}))
	_command_taken = true
	_modal_pause_captured = false
	_set_background_input_enabled(true)
	SimClock.set_paused(true)
	return ""


func _autosave_if_due() -> void:
	if not _autosave_enabled or _scripted_session or SimClock.paused or SimClock.sim_time - _autosaved_at < SaveGame.AUTOSAVE_INTERVAL_S:
		return
	if save_refusal() != "":
		return
	_autosaved_at = SimClock.sim_time
	var slot := SaveGame.next_autosave_slot()
	if save_engagement(slot, "auto", "Autosave %s" % Geo.format_duration(SimClock.sim_time)) == "":
		SaveGame.prune_autosaves()


## What the screen itself has recorded that the simulation does not hold: the observed journal and
## comms, the after-action counters, the commander's groups, own track numbers and the view.
func _capture_presentation() -> Dictionary:
	var numbers := []
	for u: Unit in map._own_numbers:
		numbers.append([u.id, map._own_numbers[u]])
	var foundered := []
	for u: Unit in _foundered:
		foundered.append(u.id)
	var selected := []
	for u: Unit in map.selected:
		selected.append(u.id)
	return {
		"journal": radio.journal.duplicate(),
		"journal_omitted": radio.journal_omitted,
		"history": radio.history.duplicate(),
		"board_messages": status_boards._messages.duplicate(),
		"stats": _stats.duplicate(),
		"losses": _losses,
		"kills": _kills,
		"civilian_incidents": _civilian_incidents,
		"foundered": foundered,
		"control_groups": _control_groups.duplicate(true),
		"own_numbers": numbers,
		"selected": selected,
		"view": {"center": map.center_nm, "ppn": map.ppn},
		"autosaved_at": _autosaved_at,
		# The rules the engagement is fought under; a load continues under them (_install_engagement).
		"options": engagement_options(),
		"command_guide": _command_guide.to_dict(),
	}


func _restore_presentation(d: Dictionary) -> void:
	var by_id := {}
	for u in simulation.unit_manager.units:
		by_id[u.id] = u
	radio.journal.assign(d.get("journal", []))
	radio.journal_omitted = int(d.get("journal_omitted", 0))
	radio.history.assign(d.get("history", []))
	status_boards._messages.assign(d.get("board_messages", []))
	_stats = d.get("stats", _stats).duplicate()
	_losses = PackedStringArray(d.get("losses", []))
	_kills = PackedStringArray(d.get("kills", []))
	_civilian_incidents = PackedStringArray(d.get("civilian_incidents", []))
	_foundered.clear()
	for id in d.get("foundered", []):
		if by_id.has(int(id)):
			_foundered[by_id[int(id)]] = true
	_control_groups = d.get("control_groups", {}).duplicate(true)
	map._own_numbers.clear()
	for pair: Array in d.get("own_numbers", []):
		if by_id.has(int(pair[0])):
			map._own_numbers[by_id[int(pair[0])]] = int(pair[1])
	var selected: Array = []
	for id in d.get("selected", []):
		if by_id.has(int(id)) and (by_id[int(id)] as Unit).alive:
			selected.append(by_id[int(id)])
	map.select_units(selected)
	var view: Dictionary = d.get("view", {})
	if view.has("center"):
		map.center_nm = view["center"]
		map.ppn = float(view.get("ppn", map.ppn))
		map.queue_redraw()
	_autosaved_at = float(d.get("autosaved_at", SimClock.sim_time))
	_command_guide.restore(d.get("command_guide", {}))


func _toggle_saved_engagements() -> void:
	if _saves.visible:
		_close_saved_engagements()
		return
	if _has_visible_modal() and not _menu.visible:
		return
	_begin_modal_pause()
	_saves.open(save_refusal() == "")


func _close_saved_engagements() -> void:
	_saves.hide()
	_restore_modal_pause_if_clear()
	call_deferred("_focus_map_if_clear")


## Restarting throws away the whole mission, so from the command deck it takes a second press.
## The briefing and the after-action report restart directly; there it is the deliberate choice.
func _request_restart() -> void:
	var now := Time.get_ticks_msec()
	if now - _restart_armed_ms <= RESTART_CONFIRM_MS:
		_restart_armed_ms = -RESTART_CONFIRM_MS
		restart_scenario()
		return
	_restart_armed_ms = now
	radio.advise("Restart this operation? Press Ctrl+F10 again to confirm")


func restart_scenario() -> void:
	start_scenario(simulation.scenario_path)
	_show_briefing()


## The bottom strip holds a square regional map; the 3D view and the data display share the rest.
func _fit_bottom_strip() -> void:
	var side := _bottom_strip.size.y
	if side > 0.0 and not is_equal_approx(_regional_frame.custom_minimum_size.x, side):
		_regional_frame.custom_minimum_size.x = side


## Puts the chart and the 3D view where the current layout wants them. The top area normally
## holds the chart and the bottom-centre pane the 3D view; G swaps them, and F10 gives the 3D view
## the whole window by collapsing the bottom strip under it. Both keep running throughout.
func _arrange_views() -> void:
	# A control that leaves the tree mid-drag never hears the release that would end the drag.
	map.cancel_drag()
	regional.cancel_drag()
	var top: Control = _world_view if (_views_swapped or _world_full) else map
	var pane: Control = map if top == _world_view else _world_view
	for pair: Array in [[top, _upper], [pane, _view_frame]]:
		var node: Control = pair[0]
		var slot: Control = pair[1]
		if node.get_parent() != slot:
			node.reparent(slot, false)
		node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_upper.move_child(status_boards, _upper.get_child_count() - 1)
	_bottom_strip.visible = not _world_full
	$Layout/MapEdge.visible = not _world_full
	command_bar.visible = not _world_full
	map.visible = not _world_full
	_world_view.set_layout_state(_views_swapped, _world_full)
	_world_view.rig.cut()
	_sync_overlay()
	call_deferred("_focus_map_if_clear")


## The status boards sit over the top area; while they are up the chart there draws no readouts
## under them. A chart in the bottom pane (G) is not covered.
func _sync_overlay() -> void:
	map.overlay_covered = status_boards.visible and map.get_parent() == _upper


func _swap_views() -> void:
	_world_full = false
	_views_swapped = not _views_swapped
	_arrange_views()


func _toggle_world_full() -> void:
	_world_full = not _world_full
	_arrange_views()


## The status boards (ASTABs). A board number opens that board, or closes it if it is already up.
## Opening the comms board by any route clears the message lamp (StatusBoards.comms_shown).
func _toggle_boards(board := -1) -> void:
	status_boards.toggle(board)
	if not status_boards.visible:
		_focus_map_if_clear()


## The lamp on the data display: it opens the comms board, and closes it only when it is already
## what is on screen, so a click on a lit lamp always shows the messages it is lit for.
func _on_message_lamp() -> void:
	if status_boards.showing_comms():
		_toggle_boards(StatusBoards.BOARD_COMMS)
	else:
		status_boards.open_board(StatusBoards.BOARD_COMMS)


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
	_menu.options_requested.connect(_choose_options)
	add_child(_menu)
	_menu.hide()

	_editor = ScenarioEditor.new()
	_editor.name = "ScenarioEditor"
	_editor.play_requested.connect(func(path: String) -> void:
		start_scenario(path)
		_show_briefing())
	_editor.closed.connect(func() -> void:
		_show_menu()
		var saved := _editor.opened_path()
		if saved != "" and saved.begins_with(ScenarioIndex.user_root()):
			_menu.show_saved(saved))
	add_child(_editor)
	_editor.hide()

	_briefing = BriefingPanel.new()
	_briefing.name = "BriefingPanel"
	_briefing.mission_manager = simulation.mission_manager
	_briefing.unit_manager = simulation.unit_manager
	_briefing.start_pressed.connect(_on_briefing_start)
	_briefing.restart_pressed.connect(restart_scenario)
	_briefing.menu_pressed.connect(_show_menu)
	_briefing.guide_toggled.connect(func(on: bool) -> void:
		_command_guide.enabled = on and _command_guide.available)
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
	_air_operations.chart_pick_requested.connect(_begin_air_pick)
	map.point_picked.connect(func(pos: Vector2) -> void:
		if _air_picking:
			_air_operations.apply_station(pos)
			_end_air_pick())
	map.contact_picked.connect(func(t: Track) -> void:
		if _air_picking:
			_air_operations.apply_target(t)
			_end_air_pick())
	map.pick_cancelled.connect(func() -> void:
		if _air_picking:
			_end_air_pick())
	_air_operations.aircraft_selected.connect(func(a: Unit) -> void:
		_close_air_operations()
		map.select_units([a])
		map.center_on_selection())
	add_child(_air_operations)
	_air_operations.hide()
	_key_help = KeyCommands.new()
	_fleet_operations = FleetOperations.new()
	_fleet_operations.simulation = simulation
	_fleet_operations.closed.connect(_close_fleet_operations)
	_fleet_operations.selection_requested.connect(func(units: Array) -> void: map.select_units(units))
	_fleet_operations.order_requested.connect(func(order: Order) -> void:
		_apply_order_to_selection(order)
		_fleet_operations.refresh())
	_fleet_operations.formation_requested.connect(_apply_formation)
	add_child(_fleet_operations)
	_fleet_operations.hide()
	_weapon_control = WeaponControl.new()
	_weapon_control.simulation = simulation
	_weapon_control.closed.connect(_close_weapon_control)
	_weapon_control.unit_orders_requested.connect(_apply_unit_orders)
	_weapon_control.group_order_requested.connect(_issue_group_order)
	_weapon_control.target_selected.connect(func(t: Track) -> void: map.select_track(t))
	_weapon_control.weapon_selected.connect(func(spec: WeaponSpec) -> void: orders_panel.select_weapon(spec))
	_weapon_control.range_role_selected.connect(func(role: String) -> void: map.weapon_range_role = role; map.show_weapon_ranges = true)
	add_child(_weapon_control)
	_weapon_control.hide()
	orders_panel.weapon_control_requested.connect(_toggle_weapon_control)
	_key_help.name = "KeyCommands"
	_key_help.closed.connect(_restore_modal_pause_if_clear)
	add_child(_key_help)
	_key_help.hide()
	_saves = SavedEngagements.new()
	_saves.name = "SavedEngagements"
	_saves.closed.connect(_close_saved_engagements)
	_saves.save_requested.connect(func() -> void:
		var why := save_engagement("save-%d" % SaveGame.next_serial(), "manual", "Saved %s" % SimClock.datetime_string())
		_saves.refresh()
		_saves.show_message("Saved." if why == "" else "Cannot save: " + why, why == ""))
	_saves.delete_requested.connect(func(path: String) -> void:
		SaveGame.remove(path)
		_saves.refresh())
	_saves.load_requested.connect(func(path: String) -> void:
		var why := load_engagement(path)
		if why != "":
			_saves.show_message("Cannot load: " + why, false)
		else:
			_saves.hide())
	add_child(_saves)
	_saves.hide()


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
	# Returning to the chart only makes sense once the player has taken command; before that it
	# would skip the briefing.
	_menu.allow_back(_command_taken)
	_menu.refresh(simulation.scenario_path, _command_taken)
	_menu.show()
	_menu.call_deferred("focus_default")


func _show_briefing() -> void:
	_begin_modal_pause()
	_menu.hide()
	_report.hide()
	_editor.hide()
	_briefing.set_mode(SimClock.sim_time <= 0.0)
	_briefing._select_section("orders")
	_briefing.refresh()
	_briefing._guide.set_pressed_no_signal(_command_guide.enabled)
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
	_command_taken = true
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
	# The 3D pane stops rendering behind a full-screen surface; nobody can see it there.
	if _world_view != null:
		_world_view.set_suspended(not enabled)
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
	return _air_picking \
		or (_menu != null and _menu.visible) \
		or (_briefing != null and _briefing.visible) \
		or (_editor != null and _editor.visible) \
		or (_library != null and _library.visible) \
		or (_command_palette != null and _command_palette.visible) \
		or (_air_operations != null and _air_operations.visible) \
		or (_weapon_control != null and _weapon_control.visible) \
		or (_fleet_operations != null and _fleet_operations.visible) \
		or (_key_help != null and _key_help.visible) \
		or (_saves != null and _saves.visible) \
		or (_report != null and _report.visible)


func _restore_modal_pause_if_clear() -> void:
	if not _modal_pause_captured or _has_visible_modal():
		return
	var restore := _modal_was_paused
	_modal_pause_captured = false
	SimClock.set_paused(restore)
	_set_background_input_enabled(true)


func _toggle_air_operations() -> void:
	if _air_picking:
		map.cancel_interaction_mode()  # back to the dialog the pick came from
		return
	if _air_operations.visible:
		_close_air_operations()
		return
	if _has_visible_modal():
		return
	_begin_modal_pause()
	_air_operations.open_for(map.selected)
	_air_operations.set_clock_context(_modal_was_paused)


func _toggle_weapon_control() -> void:
	if _weapon_control.visible:
		_close_weapon_control()
		return
	if _has_visible_modal():
		return
	_begin_modal_pause()
	_weapon_control.open_for(map.selected, map.selected_track)


func _close_weapon_control() -> void:
	_weapon_control.hide()
	_restore_modal_pause_if_clear()


## "Group attack (N rounds)..." from a contact's menu: the firing board on that contact, with the
## group budget set, so the allocation can be read before it is committed.
func _open_group_attack(t: Track, budget: int) -> void:
	if _weapon_control.visible or _has_visible_modal():
		return
	if map.selected_track != t:
		map.select_track(t)
	_begin_modal_pause()
	_weapon_control.open_for(map.selected, t, budget)


## A group attack, or its cancellation, goes to one member: one order makes one group, where the
## same order given to each hooked platform would make one group apiece. The receipt is the
## group manager's, which says who fires what and who cannot.
func _issue_group_order(lead: Unit, order: Order) -> void:
	if lead == null or not lead.alive or lead.faction != simulation.player_faction or not simulation.unit_manager.units.has(lead):
		order.receipt = "Hook your own platforms first."
		radio.advise(order.receipt)
		return
	var accepted := simulation.unit_manager.issue_order(lead, order)
	if order.receipt == "":
		order.receipt = "Group attack refused" if order.type == Order.Type.GROUP_ATTACK else "That group attack has already ended."
	elif not accepted and order.type == Order.Type.GROUP_ATTACK:
		order.receipt = "Group attack refused: " + order.receipt
	radio.flash(order.receipt, "good" if accepted else "warn", lead)
	if accepted:
		SoundFx.play("click", 0.05)
	voice.say(("attack_ack" if order.type == Order.Type.GROUP_ATTACK else "order_ack") if accepted else "order_refused", lead, {"track": order.track})
	call_deferred("_focus_map_if_clear")


func _toggle_fleet_operations() -> void:
	if _fleet_operations.visible:
		_close_fleet_operations()
		return
	if _has_visible_modal():
		return
	_begin_modal_pause()
	_fleet_operations.open_for(map.selected)


func _close_fleet_operations() -> void:
	_fleet_operations.hide()
	_restore_modal_pause_if_clear()


## The dialog steps aside while the commander picks on the chart; the clock stays where the dialog
## left it, and the dialog comes back with the pick (or without, on a right-click or Escape).
func _begin_air_pick(contact: bool) -> void:
	var context := _air_operations.pick_context()
	_air_picking = true
	_air_operations.hide()
	_set_background_input_enabled(true)
	map.set_pick_mode(contact, str(context["prompt"]), context["origin"], float(context["radius_nm"]))
	map.grab_focus()
	radio.advise(str(context["prompt"]) + ". Right-click or Escape returns to Air Operations.")


func _end_air_pick() -> void:
	_air_picking = false
	if not _modal_pause_captured:
		# Nothing should have released Air Operations' pause while the chart was picking, but if
		# it was, closing the dialog must still hand back the keyboard and a paused clock.
		_modal_pause_captured = true
		_modal_was_paused = true
	SimClock.set_paused(true)
	_set_background_input_enabled(false)
	_air_operations.show()
	_air_operations.refresh()


## "Air strike..." from a contact's menu: Air Operations, set to strike that contact.
func _open_air_strike(t: Track) -> void:
	if _air_operations.visible or _has_visible_modal():
		return
	_begin_modal_pause()
	_air_operations.open_strike(map.selected, t)
	_air_operations.set_clock_context(_modal_was_paused)


func _close_air_operations() -> void:
	_air_operations.hide()
	_restore_modal_pause_if_clear()
	call_deferred("_focus_map_if_clear")


func _issue_air_order(u: Unit, order: Order) -> void:
	if u == null or not u.alive or u.faction != simulation.player_faction or not simulation.unit_manager.units.has(u):
		_air_operations.show_receipt("That airframe or host is no longer under your command.", false)
		return
	var before := u.launch_spots_busy()
	var accepted := simulation.unit_manager.issue_order(u, order)
	var message := ""
	if order.type == Order.Type.AIR_MISSION:
		message = order.receipt if order.receipt != "" else ("Mission assigned" if accepted else "Mission refused")
		if not accepted:
			message = "Mission refused: " + message
	elif order.type == Order.Type.CANCEL_AIR_MISSION:
		message = "Mission %d cancelled: queued launches struck off, its aircraft returning." % order.mission_id if accepted else "That mission has already ended."
	elif order.type == Order.Type.LAUNCH_AIRCRAFT:
		var launched := u.launch_spots_busy() - before
		var spec := DataDB.platform(order.aircraft_id)
		message = "%s: launching %d of %d × %s. Resume time to fly the sortie." % [u.callsign, launched, order.aircraft_count, spec.short_name if spec != null else order.aircraft_id] if accepted else simulation.aviation_manager.launch_rejection_reason(u, order.aircraft_id)
	else:
		message = "%s: return and land at %s. Recovery includes approach, landing, refuelling and rearming." % [u.callsign, order.recovery_base.callsign] if accepted and order.recovery_base != null else "Return order rejected: " + simulation.aviation_manager.recovery_rejection_reason(u, order.recovery_base)
	_air_operations.show_receipt(message, accepted)
	radio.flash(message, "good" if accepted else "warn")
	voice.say("order_ack" if accepted else "order_refused", u)


func _revise_chart_mission(m: AirMission, at: Vector2, radius: float) -> void:
	if m == null or not m.active or m.base == null: return
	_issue_air_order(m.base, Order.revise_air_mission(m, at, radius, m.requested, m.relief, m.auto_return, m.cap_intent, m.protected_unit, m.pursuit_nm))


func _move_escort_station(u: Unit, at: Vector2) -> void:
	if u == null or u.faction != simulation.player_faction or u.station_leader == null: return
	var leader := u.station_leader
	var axis := u.station_axis_deg if u.station_axis_deg >= 0.0 else SubmarineComms.reported_heading(leader)
	var delta := at - SubmarineComms.reported_position(leader)
	var order := Order.form_up(leader, Vector2(delta.dot(Geo.heading_to_vector(axis + 90.0)), delta.dot(Geo.heading_to_vector(axis))), u.station_axis_deg)
	order.station_label = u.station_label
	var accepted := simulation.unit_manager.issue_order(u, order)
	var receipt := order.receipt if order.receipt != "" else ("escort station revised" if accepted else "station order refused")
	radio.flash("%s: %s" % [u.callsign, receipt], "good" if accepted else "warn")
	if _receives_report(u): voice.say("order_ack" if accepted else "order_refused", u)


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
	if not _has_visible_modal() and map.focus_mode != Control.FOCUS_NONE and map.is_visible_in_tree():
		map.grab_focus()


## F7: with a class-known contact hooked or inspected, the reference opens on that class's
## entry; otherwise it opens on the last entry shown, as before. The class is the track's
## reported one, looked up by short name in the catalogue, never the unit under the track.
func _open_reference() -> void:
	var spec := PlatformLibrary.entry_for_track(_reference_contact(), _catalogue_hint())
	if spec != null and not _library.visible:
		_inspect_asset(spec.id)
		return
	_toggle_library()


## The contact F7 refers to: the one being inspected, else the hooked one.
func _reference_contact() -> Track:
	var t := map.inspection_track()
	if t == null:
		t = map.selected_track
	return t if t != null and t.status != Track.Status.LOST else null


## An own platform id, so a class name shared by both catalogues resolves in this mission's era.
func _catalogue_hint() -> String:
	var ref := map.reference_unit()
	return ref.spec.id if ref != null and ref.spec != null else ""


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
	var layers := _cds_state()
	var actions: Array[Dictionary] = [
		{"id": "fleet_operations", "label": "Fleet Operations", "description": "Task-group readiness, stations and fleet orders.", "shortcut": "J", "enabled": true},
		{"id": "deploy_radar_decoys", "label": "Deploy chaff / radar countermeasures", "description": "Use one RF pack on each capable selected platform. Timing, stores and seeker type matter.", "shortcut": "D", "enabled": controllable},
		{"id": "evade", "label": "Evade detected inbound weapons", "description": "Temporary emergency maneuver, then resume the route or formation station.", "shortcut": "V", "enabled": movable},
		{"id": "resume_plan", "label": "Resume route / station", "description": "End the emergency maneuver without erasing the standing plan.", "shortcut": "", "enabled": movable},
		{"id": "swap_views", "label": "Swap chart and 3D view", "description": "Put the 3D view in the top area and the chart in the bottom-centre pane, or back.", "shortcut": "G", "enabled": true, "state": "3D on top" if _views_swapped else "chart on top"},
		{"id": "world_full", "label": "3D view full screen", "description": "Give the 3D view the whole window; press again or Escape to return.", "shortcut": "F10", "enabled": true, "state": "on" if _world_full else "off"},
		{"id": "camera_cycle", "label": "Cycle 3D camera", "description": "Tether, fly-by, action and detached cameras in turn.", "shortcut": "T", "enabled": true, "state": _world_view.camera_mode_name()},
		{"id": "camera_tether", "label": "Tether camera", "description": "Follow the hooked platform from behind and above.", "shortcut": "F9", "enabled": true},
		{"id": "camera_flyby", "label": "Fly-by camera", "description": "Hold a point ahead of the hooked platform and let it pass.", "shortcut": "F11", "enabled": true},
		{"id": "camera_action", "label": "Action camera", "description": "Cut to launches, hits and deck events you can see, then back.", "shortcut": "F12", "enabled": true},
		{"id": "camera_detached", "label": "Detached camera", "description": "Stop the camera where it is and watch the platform move away.", "shortcut": "F8", "enabled": true},
		{"id": "status_boards", "label": "Status boards", "description": "Orders, task group, track file and comms boards over the chart.", "shortcut": "A", "enabled": true, "state": "open" if status_boards.visible else "closed"},
		{"id": "plot_move", "label": "Plot route", "description": "Arm a left-click route; Shift chains waypoints. Right-click water moves the hooked platform at once.", "shortcut": "W", "enabled": movable, "state": "armed" if map.interaction_mode == TacticalMap.InteractionMode.MOVE else "off", "reason": "Hook a deployed mobile platform first."},
		{"id": "return_to_station", "label": "Return to station", "description": "Resume the patrol, screen or air station that an investigation, attack or refuelling interrupted.", "shortcut": "S", "enabled": movable and map.selected.any(func(u: Unit) -> bool: return u.has_station()), "reason": "The hooked platforms hold no station."},
		{"id": "auto_return", "label": "Auto-return to station", "description": "Go back to station by itself once an identification, interception or attack ends. A newer order always stands.", "shortcut": "", "enabled": movable, "state": _auto_return_state(), "reason": "Hook a deployed mobile platform first."},
		{"id": "plot_patrol", "label": "Assign patrol area", "description": "Click two opposite corners of a repeating patrol circuit. Fuel and recovery still apply.", "shortcut": "Shift+W", "enabled": movable, "reason": "Hook a deployed mobile platform first."},
		{"id": "weapon_control", "label": "Weapon control", "description": "Commit mixed weapons, inspect target quality and cancel queued rounds.", "shortcut": "Shift+E", "enabled": controllable},
		{"id": "open_defence", "label": "Defence commands", "description": "Countermeasures, evasion and interceptor policy for the hooked platforms.", "shortcut": "", "enabled": controllable},
		{"id": "open_engagement", "label": "Engagement board", "description": "Weapon, salvo, range and time of flight for the hooked contact.", "shortcut": "", "enabled": controllable and has_target, "state": map.selected_track.id if has_target else "no target", "reason": "Hook a shooter and a contact first."},
		{"id": "next_contact", "label": "Next priority contact", "description": "Cycle hostile, unknown, fresh, and nearby contacts first.", "shortcut": "N", "enabled": contacts > 0, "state": "%d held" % contacts, "reason": "No contacts are held."},
		{"id": "previous_contact", "label": "Previous priority contact", "description": "Cycle backward through the priority contact stack.", "shortcut": "Shift+N", "enabled": contacts > 0, "state": "%d held" % contacts, "reason": "No contacts are held."},
		{"id": "next_platform", "label": "Next own platform", "description": "Hook the next platform of the task group.", "shortcut": ".", "enabled": true},
		{"id": "focus_selection", "label": "Centre on selection and target", "description": "Center one item or fit the complete shooter-target problem.", "shortcut": "C", "enabled": not map.selected.is_empty() or has_target, "reason": "Hook a platform or contact first."},
		{"id": "follow_selection", "label": "Follow selection or target", "description": "Keep the hooked contact or single hooked platform centered.", "shortcut": "F", "enabled": map.selected.size() == 1 or has_target, "state": "on" if map.follow_selection else "off", "reason": "Hook one platform or a contact first."},
		{"id": "fit_fleet", "label": "Fit friendly force", "description": "Frame every deployed friendly unit.", "shortcut": "Home", "enabled": true},
		{"id": "fit_theatre", "label": "Fit operation area", "description": "Return to the scenario's full chart extent.", "shortcut": "", "enabled": true},
		{"id": "toggle_radar", "label": "Toggle radar", "description": "Mixed or silent selections converge active; all-active selections go silent.", "shortcut": "R", "enabled": controllable and radar_state >= 0, "state": _state_name(radar_state, "off", "on"), "reason": "The selection has no controllable radar."},
		{"id": "toggle_sonar", "label": "Toggle active sonar", "description": "Mixed or passive selections converge active; all-active selections go passive.", "shortcut": "P", "enabled": controllable and sonar_state >= 0, "state": _state_name(sonar_state, "passive", "active"), "reason": "The selection has no controllable sonar."},
		{"id": "toggle_emcon", "label": "Toggle emission control", "description": "Switch the selection between silent and free emissions.", "shortcut": "E", "enabled": controllable, "state": _state_name(emcon_state, "free", "silent"), "reason": "Hook a controllable platform first."},
		{"id": "symbols", "label": "NTDS or graphic symbols", "description": "Cycle NTDS symbols and small, medium and large graphic symbols.", "shortcut": "Tab", "enabled": true, "state": ["NTDS", "small", "medium", "large"][clampi(int(layers.get("symbol_mode", 0)), 0, 3)]},
		{"id": "toggle_leaders", "label": "Velocity leaders", "description": "Speed-scaled course lines on every symbol.", "shortcut": "Shift+V", "enabled": true, "state": _on_off(layers, "leaders")},
		{"id": "toggle_track_numbers", "label": "Track numbers", "description": "Four-digit track numbers beside the symbols.", "shortcut": "Shift+K", "enabled": true, "state": _on_off(layers, "track_numbers")},
		{"id": "toggle_tags", "label": "Tags", "description": "Names and classifications under the track numbers.", "shortcut": "Shift+I", "enabled": true, "state": _on_off(layers, "tags")},
		{"id": "toggle_sensors", "label": "Sensor rings", "description": "Detection ranges for the current selection.", "shortcut": "F4", "enabled": true, "state": _on_off(layers, "sensors")},
		{"id": "toggle_trails", "label": "Track trails", "description": "Recent movement history.", "shortcut": "F5", "enabled": true, "state": _on_off(layers, "trails")},
		{"id": "toggle_relief", "label": "Relief shading", "description": "Hill-shading on land and sea floor.", "shortcut": "F6", "enabled": true, "state": _on_off(layers, "relief")},
		{"id": "toggle_latlon", "label": "Lat/long readout", "description": "Cursor position at the bottom left of the chart.", "shortcut": "Ctrl+L", "enabled": true, "state": _on_off(layers, "latlon")},
		{"id": "toggle_scale", "label": "Scale bar", "description": "Nautical-mile scale at the bottom left of the chart.", "shortcut": "Ctrl+S", "enabled": true, "state": _on_off(layers, "scale")},
		{"id": "radar_coverage", "label": "Radar coverage on the regional map", "description": "Shade what your radiating radars cover.", "shortcut": "Ctrl+W", "enabled": true, "state": _on_off(layers, "radar_coverage")},
		{"id": "toggle_graticule", "label": "Graticule", "description": "Latitude and longitude lines on the chart.", "shortcut": "", "enabled": true, "state": _on_off(layers, "graticule")},
		{"id": "toggle_key", "label": "Symbol key", "description": "The NTDS symbol key.", "shortcut": "F2", "enabled": true, "state": _on_off(layers, "key")},
		{"id": "range_circle", "label": "Range circle", "description": "A range ring from the hooked platform through the cursor; B again fixes it, then clears it.", "shortcut": "B", "enabled": true},
		{"id": "toggle_pause", "label": "Pause or resume time", "description": "Stop or resume simulation time without changing acceleration.", "shortcut": "Space", "enabled": true, "state": "paused" if SimClock.paused else "running"},
		{"id": "briefing", "label": "Orders and briefing", "description": "Objectives, failure conditions, environment and controls.", "shortcut": "F1", "enabled": true},
		{"id": "library", "label": "Reference", "description": "Platforms and weapons, with models; opens on a hooked contact's class once it is classified.", "shortcut": "F7", "enabled": true},
		{"id": "air_operations", "label": "Air operations: launch and recover", "description": "Select aircraft types, manage sorties, and choose a carrier or airfield for landing.", "shortcut": "F3", "enabled": true},
		{"id": "quicksave", "label": "Quicksave", "description": "Save the engagement to the quicksave slot.", "shortcut": "Ctrl+Shift+S", "enabled": save_refusal() == "", "reason": save_refusal()},
		{"id": "quickload", "label": "Quickload", "description": "Return to the quicksave.", "shortcut": "Ctrl+Shift+L", "enabled": FileAccess.file_exists(SaveGame.slot_path(SaveGame.QUICKSAVE)), "reason": "No quicksave yet."},
		{"id": "saved_engagements", "label": "Saved engagements", "description": "Save, load or delete engagements, including the autosave history.", "shortcut": "Ctrl+Shift+O", "enabled": true},
		{"id": "key_commands", "label": "Key commands", "description": "Every keyboard command on one board.", "shortcut": "H", "enabled": true},
		{"id": "missions", "label": "Missions", "description": "The operations desk.", "shortcut": "M", "enabled": true},
		{"id": "editor", "label": "Scenario editor", "description": "Build or change an operation.", "shortcut": "Ctrl+E", "enabled": true},
		{"id": "restart", "label": "Restart mission", "description": "Start this operation again; press twice to confirm.", "shortcut": "Ctrl+F10", "enabled": true},
		{"id": "sound", "label": "Sound on or off", "description": "Mute or restore the game's sounds.", "shortcut": "Ctrl+M", "enabled": true, "state": "on" if SoundFx.enabled else "off"},
		{"id": "voice", "label": "Crew voice", "description": "Spoken crew reports through the system's text-to-speech.", "shortcut": "", "enabled": true, "state": "on" if voice.enabled else "off"},
		{"id": "ambient", "label": "Ambient sea and machinery", "description": "Sea wash by sea state and the hooked platform's engine or rotor.", "shortcut": "", "enabled": true, "state": "on" if SoundFx.ambient_enabled else "off"},
		{"id": "intercept_inbound", "label": "Engage inbound weapons", "description": "Fire interceptors from the hooked ships at the inbound rounds they hold. With manual missile defence the SAMs fire only on this order; close-in guns answer by themselves.", "shortcut": "X", "enabled": controllable, "reason": "Hook your ships first."},
		{"id": "preset_normal", "label": "Gameplay: Normal", "description": GameOptions.preset_description(GameOptions.NORMAL) + ".", "shortcut": "", "enabled": true, "state": "selected" if options.preset() == GameOptions.NORMAL else ""},
		{"id": "preset_classic", "label": "Gameplay: Classic", "description": GameOptions.preset_description(GameOptions.CLASSIC) + ".", "shortcut": "", "enabled": true, "state": "selected" if options.preset() == GameOptions.CLASSIC else ""},
	]
	for key: String in ["ceiling", "manual_defence", "engage_on_id"]:
		actions.append({"id": "option_" + key, "label": GameOptions.option_text(key), "description": GameOptions.option_tooltip(key), "shortcut": "", "enabled": true, "state": "on" if options.option_on(key) else "off"})
	for percent: int in InterfaceScale.PERCENTAGES:
		actions.append({"id": "ui_scale_%d" % percent, "label": "Interface size: %d%%" % percent, "description": "Scale text, chart labels and controls together.", "shortcut": "", "enabled": true, "state": "selected" if InterfaceScale.percent == percent else ""})
	var ladder := SimClock.speeds()
	for i in ladder.size():
		actions.append({"id": "speed_%d" % i, "label": "Set time to %d×" % int(ladder[i]), "description": "Set simulation acceleration; time remains paused until resumed." + (" The ceiling." if i == ladder.size() - 1 and ladder.size() < SimClock.SPEEDS.size() else ""), "shortcut": str(i + 1), "enabled": true, "state": "selected" if SimClock.speed_index == i else ""})
	return actions


## "on", "off" or "mixed" across the hooked own platforms.
func _auto_return_state() -> String:
	var on := 0
	var total := 0
	for u: Unit in map.selected:
		if u.faction == simulation.player_faction and u.alive:
			total += 1
			if u.auto_return:
				on += 1
	return "off" if on == 0 else "on" if on == total else "mixed"


static func _on_off(state: Dictionary, key: String) -> String:
	return "on" if bool(state.get(key, false)) else "off"


## What the chart and the regional map are currently showing, for the menus' check marks.
func _cds_state() -> Dictionary:
	var state := {"symbol_mode": map.symbol_mode, "radar_coverage": regional.show_radar_coverage, "sound": SoundFx.enabled, "voice": voice.enabled, "ambient": SoundFx.ambient_enabled,
		"options": options}
	for layer in ["leaders", "track_numbers", "tags", "trails", "relief", "latlon", "scale", "sensors", "graticule", "key"]:
		state[layer] = map.has_layer(layer)
	return state


func _state_name(state: int, off_name: String, on_name: String) -> String:
	if state < 0:
		return "unavailable"
	if state == 2:
		return "mixed"
	return on_name if state == 1 else off_name


func _run_palette_action(id: String) -> void:
	if id.begins_with("ui_scale_"):
		InterfaceScale.apply(get_window(), int(id.trim_prefix("ui_scale_")))
		return
	match id:
		"guide_aircraft":
			var aircraft := _command_guide.aircraft(simulation.unit_manager)
			if aircraft != null:
				map.select_units([aircraft])
				map.center_on_selection()
		"orders_menu":
			var button: Button = command_bar.buttons[id]
			var items := CdsMenus.orders_items(map.selected, map.selected_track, _all_controllable(map.selected), _all_movable(map.selected), simulation.weapon_manager)
			_cds_menus.open(items, button.get_global_rect().position + Vector2(0, button.size.y))
			map.menu_open = true
		"chart_menu", "time_menu", "options_menu":
			var button: Button = command_bar.buttons[id]
			var items := CommandBar.chart_items(map) if id == "chart_menu" else (CommandBar.time_items() if id == "time_menu" else CdsMenus.options_items(_cds_state()))
			_cds_menus.open(items, button.get_global_rect().position + Vector2(0, button.size.y))
			map.menu_open = true
		"preset_normal", "preset_classic":
			_choose_options(GameOptions.preset_named(id.trim_prefix("preset_"), options.voice, options.ambient))
		"option_ceiling", "option_manual_defence", "option_engage_on_id", "option_submarine_comms":
			_choose_options(options.toggled(id.trim_prefix("option_")))
		"intercept_inbound":
			_apply_order_to_selection(Order.intercept())
		"chart_zoom_in", "chart_zoom_out":
			map._zoom_at(map.size * 0.5, TacticalMap.ZOOM_STEP if id == "chart_zoom_in" else 1.0 / TacticalMap.ZOOM_STEP)
		"fleet_operations":
			_toggle_fleet_operations()
		"deploy_radar_decoys":
			_apply_order_to_selection(Order.deploy_countermeasures("radar"))
		"evade":
			_apply_order_to_selection(Order.evade())
		"resume_plan":
			_apply_order_to_selection(Order.resume_plan())
		"swap_views":
			_swap_views()
		"world_full":
			_toggle_world_full()
		"camera_cycle":
			_world_view.cycle_camera_mode()
		"camera_tether":
			_world_view.set_camera_mode(WorldView.CAM_TETHER)
		"camera_flyby":
			_world_view.set_camera_mode(WorldView.CAM_FLYBY)
		"camera_action":
			_world_view.set_camera_mode(WorldView.CAM_ACTION)
		"camera_detached":
			_world_view.set_camera_mode(WorldView.CAM_DETACHED)
		"status_boards":
			_toggle_boards()
		"plot_move":
			map.set_move_mode(map.interaction_mode != TacticalMap.InteractionMode.MOVE)
			map.grab_focus()
		"plot_patrol":
			map.set_patrol_mode(map.interaction_mode != TacticalMap.InteractionMode.PATROL)
			map.grab_focus()
		"return_to_station":
			_apply_order_to_selection(Order.return_to_station())
		"quicksave":
			quicksave()
		"quickload":
			quickload()
		"saved_engagements":
			_toggle_saved_engagements()
		"auto_return":
			_apply_order_to_selection(Order.set_auto_return(_auto_return_state() != "on"))
		"weapon_control":
			_toggle_weapon_control()
		"open_engagement":
			status_boards.open_board(StatusBoards.BOARD_ORDERS)
			orders_panel.open_engagement(true)
		"open_defence":
			status_boards.open_board(StatusBoards.BOARD_ORDERS)
			orders_panel._tabs.current_tab = 4
		"next_contact":
			_cycle_priority_track(1)
		"previous_contact":
			_cycle_priority_track(-1)
		"next_platform":
			_hook_next_platform()
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
		"symbols":
			map.cycle_symbol_mode()
		"toggle_leaders":
			map.toggle_layer("leaders")
		"toggle_track_numbers":
			map.toggle_layer("track_numbers")
		"toggle_tags":
			map.toggle_layer("tags")
		"toggle_sensors":
			map.toggle_layer("sensors")
		"toggle_trails":
			map.toggle_layer("trails")
		"toggle_relief":
			map.toggle_layer("relief")
		"toggle_latlon":
			map.toggle_layer("latlon")
		"toggle_scale":
			map.toggle_layer("scale")
		"toggle_graticule":
			map.toggle_layer("graticule")
		"toggle_key":
			map.toggle_layer("key")
		"radar_coverage":
			regional.toggle_radar_coverage()
		"range_circle":
			map.toggle_range_circle()
		"toggle_pause":
			SimClock.toggle_pause()
		"briefing":
			_show_briefing()
		"library":
			_open_reference()
		"air_operations":
			_toggle_air_operations()
		"key_commands":
			_show_key_commands()
		"missions":
			_show_menu()
		"editor":
			_show_editor()
		"restart":
			_request_restart()
		"sound":
			var sound_on: bool = SoundFx.toggle()
			if not sound_on:
				voice.stop()
			radio.advise("Sound %s" % ("on" if sound_on else "off"))
		"voice", "ambient":
			# Both are gameplay options too: a change goes through the options, so the preset chip
			# says CUSTOM when Classic's crew and sea are turned off. The voice flips from what the
			# menus show, the crew as heard: a system that cannot speak says why when asked again.
			var o := options.duplicate_options()
			if id == "voice":
				o.voice = not voice.enabled
			else:
				o.ambient = not options.ambient
			_choose_options(o)
		"actions":
			_toggle_command_palette()
		_:
			if id.begins_with("speed_"):
				_set_time_scale(int(id.trim_prefix("speed_")))


## Space is the pause key on the command deck. It is taken here, before the GUI sees it, because a
## focused button also answers Space: pausing just after clicking ENGAGE would fire again. Tab is
## taken here too (NTDS or graphic symbols), before the GUI spends it on focus navigation.
## Text fields and the full-screen surfaces keep both keys.
func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	# Actions opens from anywhere, including from inside a search field.
	if k.keycode == KEY_K and (k.meta_pressed or k.ctrl_pressed) and not _editor.visible:
		_toggle_command_palette()
		get_viewport().set_input_as_handled()
		return
	# The library focuses its search field on opening, and a focused field swallows Escape.
	if k.keycode == KEY_ESCAPE and _library.visible and not _command_palette.visible:
		_close_library()
		get_viewport().set_input_as_handled()
		return
	if (k.keycode != KEY_SPACE and k.keycode != KEY_TAB) or _has_visible_modal():
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	if k.keycode == KEY_SPACE:
		SimClock.toggle_pause()
	elif map.is_visible_in_tree() and not map.menu_open and (focus == null or focus == map) and not (k.ctrl_pressed or k.meta_pressed or k.alt_pressed or k.shift_pressed):
		# Only from the chart: on the status boards Tab still walks the controls.
		map.cycle_symbol_mode()
	else:
		return
	get_viewport().set_input_as_handled()


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
	if _key_help.visible:
		_key_help.close()
		get_viewport().set_input_as_handled()
		return
	if _saves.visible:
		if k.keycode == KEY_ESCAPE or (k.keycode == KEY_O and k.shift_pressed and (k.ctrl_pressed or k.meta_pressed)):
			_close_saved_engagements()
			get_viewport().set_input_as_handled()
		return
	if _weapon_control.visible:
		if k.keycode == KEY_ESCAPE or (k.keycode == KEY_E and k.shift_pressed):
			_close_weapon_control()
			get_viewport().set_input_as_handled()
		return
	if _fleet_operations.visible:
		if k.keycode in [KEY_J, KEY_ESCAPE]:
			_close_fleet_operations()
			get_viewport().set_input_as_handled()
		return
	if _air_operations.visible:
		if k.keycode in [KEY_F3, KEY_ESCAPE]:
			_close_air_operations()
			get_viewport().set_input_as_handled()
		return
	if _library.visible:
		if k.keycode in [KEY_F7, KEY_ESCAPE]:
			_close_library()
			get_viewport().set_input_as_handled()
		return
	if _editor.visible:
		if k.keycode == KEY_ESCAPE or (k.keycode == KEY_E and (k.ctrl_pressed or k.meta_pressed)):
			_show_menu()
			get_viewport().set_input_as_handled()
		return
	if _menu.visible:
		if k.keycode in [KEY_M, KEY_ESCAPE] and _command_taken:
			_hide_screens()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_E and (k.ctrl_pressed or k.meta_pressed):
			_show_editor()
			get_viewport().set_input_as_handled()
		elif (k.ctrl_pressed or k.meta_pressed) and k.shift_pressed and k.keycode in [KEY_L, KEY_O]:
			# The desk is where a reloaded browser tab or a fresh start lands, so the saves open
			# from here too. The radio is hidden behind the desk: with no quicksave to load, show
			# the list, which says so.
			if k.keycode == KEY_L and FileAccess.file_exists(SaveGame.slot_path(SaveGame.QUICKSAVE)):
				quickload()
			else:
				_toggle_saved_engagements()
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
		elif k.keycode == KEY_F10 and (k.ctrl_pressed or k.meta_pressed):
			restart_scenario()
		elif k.keycode == KEY_M:
			_show_menu()
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if (k.ctrl_pressed or k.meta_pressed) and k.shift_pressed and k.keycode in [KEY_S, KEY_L, KEY_O]:
		# Checked before the Ctrl table: Ctrl+S alone is the scale bar, Ctrl+L the lat-long readout.
		if not (_menu.visible or _editor.visible or _briefing.visible or _report.visible):
			match k.keycode:
				KEY_S: quicksave()
				KEY_L: quickload()
				KEY_O: _toggle_saved_engagements()
			get_viewport().set_input_as_handled()
			return
	if k.ctrl_pressed or k.meta_pressed:
		if k.keycode >= KEY_1 and k.keycode <= KEY_9:
			_store_control_group(k.keycode - KEY_0)
			get_viewport().set_input_as_handled()
			return
		match k.keycode:
			KEY_L:
				_run_palette_action("toggle_latlon")
			KEY_S:
				_run_palette_action("toggle_scale")
			KEY_W:
				_run_palette_action("radar_coverage")
			KEY_M:
				_run_palette_action("sound")
			KEY_E:
				_show_editor()
			KEY_F10:
				_request_restart()
			_:
				return
		get_viewport().set_input_as_handled()
		return
	if k.alt_pressed and k.keycode >= KEY_1 and k.keycode <= KEY_9:
		_recall_control_group(k.keycode - KEY_0)
		get_viewport().set_input_as_handled()
		return
	if k.shift_pressed:
		match k.keycode:
			KEY_W:
				_run_palette_action("plot_patrol")
			KEY_E:
				_toggle_weapon_control()
			KEY_R:
				map.toggle_layer("weapon_ranges")
			KEY_V:
				map.toggle_layer("leaders")
			KEY_K:
				map.toggle_layer("track_numbers")
			KEY_I:
				map.toggle_layer("tags")
			KEY_N:
				_cycle_priority_track(-1)
			_:
				return
		get_viewport().set_input_as_handled()
		return
	match k.keycode:
		KEY_J:
			_toggle_fleet_operations()
		KEY_D:
			_run_palette_action("deploy_radar_decoys")
		KEY_V:
			_run_palette_action("evade")
		KEY_G:
			_swap_views()
		KEY_W:
			_run_palette_action("plot_move")
		KEY_T:
			_world_view.cycle_camera_mode()
		KEY_F8:
			_world_view.set_camera_mode(WorldView.CAM_DETACHED)
		KEY_F9:
			_world_view.set_camera_mode(WorldView.CAM_TETHER)
		KEY_F11:
			_world_view.set_camera_mode(WorldView.CAM_FLYBY)
		KEY_F12:
			_world_view.set_camera_mode(WorldView.CAM_ACTION)
		KEY_F10:
			_toggle_world_full()
		KEY_A:
			_toggle_boards()
		KEY_H:
			_show_key_commands()
		KEY_M:
			_show_menu()
		KEY_B:
			map.toggle_range_circle()
		KEY_PERIOD:
			_hook_next_platform()
		KEY_F3:
			_toggle_air_operations()
		KEY_F7:
			_open_reference()
		KEY_SPACE:
			SimClock.toggle_pause()
		KEY_ESCAPE:
			if _world_full:
				_toggle_world_full()
			elif status_boards.visible:
				status_boards.close_boards()
			elif not map.cancel_interaction_mode():
				map.clear_selection()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			_set_time_scale(k.keycode - KEY_1)
		KEY_F2:
			map.toggle_layer("key")
		KEY_F4:
			map.toggle_layer("sensors")
		KEY_F5:
			map.toggle_layer("trails")
		KEY_F6:
			map.toggle_layer("relief")
		KEY_R:
			_toggle_radar_on_selection()
		KEY_P:
			_toggle_sonar_on_selection()
		KEY_E:
			_toggle_emcon_on_selection()
		KEY_F:
			map.set_follow_selection(not map.follow_selection)
		KEY_N:
			_cycle_priority_track(1)
		KEY_S:
			_run_palette_action("return_to_station")
		KEY_X:
			_run_palette_action("intercept_inbound")
		KEY_F1:
			_show_briefing()
		KEY_HOME:
			map.fit_to_fleet()
		KEY_C:
			map.center_on_selection()
		_:
			return
	get_viewport().set_input_as_handled()


## A time scale by its step on the ladder in use (the number keys, SCALE, the time menu). A step
## past the ceiling is refused with advice rather than quietly taken as the ceiling, so the keys
## never seem to do something they did not.
func _set_time_scale(index: int) -> void:
	var ladder := SimClock.speeds()
	if index >= ladder.size():
		radio.advise("%d× is the ceiling: %s" % [int(SimClock.ceiling()), "keys 1 to %d set the time scale" % ladder.size() if ladder.size() > 1 else "time runs at real time only"])
		return
	SimClock.set_speed_index(maxi(index, 0))


# --- Gameplay options ----------------------------------------------------------------------

## The commander chose options (the desk, the chip, the palette, the CDS menu): they become the
## preference, saved, and take effect at once, also mid-mission.
func _choose_options(o: GameOptions) -> void:
	var was := options.preset()
	_preferred = o.duplicate_options()
	_options_from_engagement = false
	_apply_options(_preferred, true, true)
	if options.preset() != was:
		radio.advise("Gameplay %s: %s" % [options.label(), options.summary()])


## Puts a set of gameplay options into effect: the clock's ladder, the player's ships' missile
## defence (as orders), engagement after identification (plain data on the unit manager), the crew
## voice and ambient sound, and every place the preset is shown. `persist` saves them as the
## player's preference; a restored engagement's options are applied without it. `sound` switches
## the voice and ambient bed to match: always for the commander's own choice, never on its own in a
## driven run, which must not reach the system's speech unasked.
func _apply_options(o: GameOptions, persist: bool, sound: bool) -> void:
	options = o.duplicate_options()
	SimClock.set_speeds(options.time_scales)
	# Under the Classic ceiling the watch is slow enough to listen to, so routine reports are spoken.
	voice.routine_ceiling = options.ceiling() if options.ceiling() <= GameOptions.CLASSIC_CEILING else 1.0
	_apply_doctrine()
	if sound:
		_apply_sound(options, persist)
	if persist:
		GameOptions.save_preferred(options)
	_show_options()


## The simulation's share of the options, for the side the player commands: engagement after
## identification as plain data, and each unit's missile-defence mode by order. The AI's sides keep
## automatic defence, and so does the player's when the AI flies it (a dev sweep).
func _apply_doctrine() -> void:
	var um := simulation.unit_manager
	um.configure_submarine_comms(simulation.player_faction, options.submarine_comms and not simulation.ai_plays_player)
	um.engage_on_hostile_id.clear()
	um.set_engage_on_hostile_id(simulation.player_faction, options.engage_on_hostile_id and not simulation.ai_plays_player)
	for u in um.units:
		if u.faction == simulation.player_faction and u.alive:
			_set_air_defence(u)


func _set_air_defence(u: Unit) -> void:
	var automatic := not options.manual_missile_defence() or simulation.ai_plays_player
	var pending_value := u.auto_air_defence
	for pending: Dictionary in u.comms_pending:
		if int(pending.get("type", -1)) == Order.Type.SET_AIR_DEFENCE_MODE:
			pending_value = bool(pending.get("automatic", pending_value))
	if pending_value != automatic:
		simulation.unit_manager.issue_order(u, Order.set_air_defence_mode(automatic))


func _apply_sound(o: GameOptions, persist: bool) -> void:
	if o.voice != voice.enabled:
		var note := voice.toggle(persist)
		if _command_taken or voice.enabled != o.voice:
			radio.advise(note)
	if o.ambient != SoundFx.ambient_enabled:
		SoundFx.set_ambient_enabled(o.ambient, persist)


func _show_options() -> void:
	if command_bar != null:
		command_bar.options_label = options.label()
		command_bar.options_tooltip = "\n".join(options.summary_lines())
		command_bar.refresh()
	# The desk chooses what a new operation is played under, so it shows the player's own choice,
	# even while a restored engagement goes on under the options it was saved with.
	if _menu != null:
		_menu.set_options(_preferred)
	if _briefing != null:
		_briefing.options_label = options.label()
		_briefing.options_lines = options.summary_lines()
		if _briefing.visible:
			_briefing.refresh()


## The options this engagement is being played under, for a save file.
func engagement_options() -> Dictionary:
	return options.to_dict()


## A restored engagement continues under the options it was saved with (its time ladder, missile
## defence and engagement rules, its sound) without overwriting the player's preference; the next
## operation started goes back to the preference. A save from before there were options was played
## under Normal's rules, and leaves the sound as the player has it. Returns whether the engagement
## brought options of its own, different from the preference.
func apply_engagement_options(d: Dictionary, announce := true) -> bool:
	var saved := d.duplicate()
	if not saved.has("voice"):
		saved["voice"] = voice.enabled
	if not saved.has("ambient"):
		saved["ambient"] = SoundFx.ambient_enabled
	var o := GameOptions.from_dict(saved)
	_options_from_engagement = not o.equals(_preferred)
	_apply_options(o, false, not _driven_run)
	if _options_from_engagement and announce:
		radio.advise("This engagement continues under its own gameplay options: %s" % options.label())
	return _options_from_engagement


## Hooks the next platform of the task group, in roster order ("." in the old games).
func _hook_next_platform() -> void:
	var own: Array = map._own_units()
	if own.is_empty():
		return
	var at := own.find(map.selected[0]) if map.selected.size() == 1 else -1
	var next: Unit = own[(at + 1) % own.size()]
	map.select_units([next])
	if not Rect2(Vector2.ZERO, map.size).has_point(map.world_to_screen(next.position)):
		map.center_on_selection()


func _show_key_commands() -> void:
	if _has_visible_modal():
		return
	_begin_modal_pause()
	_key_help.open()


func _on_selection_changed(units: Array) -> void:
	if map.selected_track != null and not _commander_sees_track(map.selected_track):
		map.select_track(null)
	unit_panel.set_units(units)
	# The dock retains ownership/capability permission, then recalculates whether the
	# selection is actively commandable as aircraft launch, recover, or are stowed.
	orders_panel.set_units(units, _all_command_authorized(units), _all_mobile_command_authorized(units))
	orders_panel.set_target_track(map.selected_track)
	if _world_view != null:
		_world_view.refocus()


func _on_track_selected(t: Track) -> void:
	CommandTraining.record_inspection(simulation, t)
	if _command_guide != null:
		_command_guide.record_inspection(t)
	contact_panel.refresh()
	orders_panel.set_target_track(t)
	if _world_view != null:
		_world_view.refocus()
	if t != null:
		orders_panel.open_engagement()


func _cycle_priority_track(step: int) -> void:
	var next := contact_panel.cycle_visible_track(step)
	if next == null:
		radio.advise("No contacts held on this picture")
		return
	radio.flash("TARGET %s · %s %s" % [next.id, next.identity, next.domain.to_upper()], "alert" if next.identity == "HOSTILE" else "info")


func _focus_urgent_threat() -> void:
	var threats := _commander_inbound()
	if threats.is_empty():
		radio.advise("No inbound weapon is held on this picture")
		return
	var entry: Dictionary = threats[0]
	var weapon: Weapon = entry["weapon"]
	var target: Unit = entry["target"]
	map.set_follow_selection(false)
	var target_plot := SubmarineComms.reported_position(target)
	map.fit_to((weapon.position + target_plot) * 0.5, maxf(weapon.position.distance_to(target_plot) * 1.55 + 4.0, 12.0))
	radio.flash("FOCUS · %s inbound to %s · impact in ~%d s" % [weapon.spec.display_name, target.callsign, maxi(int(entry["time_s"]), 0)], "alert")


func _on_round_fired(shooter: Unit, spec: WeaponSpec, _track: Track) -> void:
	if shooter.faction != simulation.player_faction:
		return
	_stats["own_rounds"] += 1
	if not _receives_report(shooter): return
	map.add_effect(shooter.position, "launch", true)
	_world_view.add_effect(shooter.position, "launch", true)
	SoundFx.play("launch")
	# Deferred a frame: a ready launcher fires inside issue_order, before the order's own
	# acknowledgement is said, and the acknowledgement should come first.
	if spec.is_torpedo():
		voice.say.call_deferred("torpedo_away", shooter)
	elif not spec.is_gun() and spec.type not in ["bomb", "ciws"]:
		voice.say.call_deferred("missile_away", shooter)


func _on_weapon_launched(shooter: Unit, spec: WeaponSpec, t: Track, rounds: int) -> void:
	if _combat_observed(shooter, shooter.faction == simulation.player_faction):
		SimClock.drop_to_realtime()
	if shooter.faction == simulation.player_faction and _receives_report(shooter):
		radio.flash("%d x %s committed to track %s; %d queued" % [rounds, spec.display_name, DataDisplay.track_number_for_track(t), simulation.weapon_manager.committed_rounds(shooter, spec, t, true)], "good", shooter)
	Debug.event("[Combat] %s commits %d x %s at %s (%.1f nm)" % [shooter.callsign, rounds, spec.display_name, t.id, shooter.position.distance_to(t.position)])


func _on_threat_detected(faction: String, w: Weapon) -> void:
	if w.is_interceptor():
		return  # the other side's SAM or anti-torpedo round, after one of ours: not inbound on us
	if faction != simulation.player_faction:
		return
	if not _commander_sees_threat(w):
		# The side's first sight of it came from a platform the commander does not hear from. Detection
		# fires once, so remember it and announce it when it reaches the commander's own picture.
		if not _unannounced.has(w):
			_unannounced.append(w)
		return
	_announce_threat(w)


func _announce_unannounced_threats() -> void:
	for w in _unannounced.duplicate():
		if w.phase == Weapon.Phase.DEAD:
			_unannounced.erase(w)
		elif _commander_sees_threat(w):
			_unannounced.erase(w)
			_announce_threat(w)


func _announce_threat(w: Weapon) -> void:
	SimClock.drop_to_realtime()
	_stats["hostile_rounds"] += 1
	var seconds := int(w.time_to_reach_s(_nearest_own_unit_pos(w)))
	var label := "TORPEDO IN THE WATER" if w.spec.is_torpedo() else ("BALLISTIC INBOUND" if w.threat_class() == "ballistic" else "INCOMING")
	radio.flash("%s — %s, impact in ~%d s" % [label, w.spec.display_name, seconds], "alert")
	SoundFx.play("torpedo" if w.spec.is_torpedo() else "alarm", 1.0)
	voice.say("torpedo_inbound" if w.spec.is_torpedo() else "inbound_missile", _nearest_own_unit(w))
	Debug.event("[Defence] inbound %s detected at %.1f nm" % [w.spec.display_name, w.position.distance_to(_nearest_own_unit_pos(w))])


func _nearest_own_distance(pos: Vector2) -> float:
	var best := INF
	for u in simulation.unit_manager.get_faction_units(simulation.player_faction):
		best = minf(best, pos.distance_to(SubmarineComms.reported_position(u)))
	return 0.0 if best == INF else best


## The own unit nearest an inbound round: the one whose watch calls it.
func _nearest_own_unit(w: Weapon) -> Unit:
	var best: Unit = null
	var best_d := INF
	for u in simulation.unit_manager.get_faction_units(simulation.player_faction):
		if not _receives_report(u): continue
		var d := w.position.distance_to(SubmarineComms.reported_position(u))
		if d < best_d:
			best_d = d
			best = u
	return best


func _nearest_own_unit_pos(w: Weapon) -> Vector2:
	var best := w.position
	var best_d := INF
	for u in simulation.unit_manager.get_faction_units(simulation.player_faction):
		if not _receives_report(u): continue
		var d := w.position.distance_to(SubmarineComms.reported_position(u))
		if d < best_d:
			best_d = d
			best = SubmarineComms.reported_position(u)
	return best


func _on_interceptor_launched(shooter: Unit, spec: WeaponSpec, threat: Weapon, rounds: int) -> void:
	if shooter.faction == simulation.player_faction:
		_stats["launched"] += rounds
		if not _receives_report(shooter): return
		map.add_effect(shooter.position, "launch", true)
		_world_view.add_effect(shooter.position, "launch", true)
		SoundFx.play("launch", 0.4)
	Debug.event("[Defence] %s fires %d x %s at inbound %s (%.1f nm)" % [shooter.callsign, rounds, spec.display_name, threat.spec.display_name, shooter.position.distance_to(threat.position)])


func _on_weapon_defeated(threat: Weapon, reason: String, by_unit: Unit) -> void:
	var own_defence := by_unit != null and by_unit.faction == simulation.player_faction
	if own_defence:
		if reason == "INTERCEPTED":
			_stats["intercepted"] += 1
		elif reason == "DECOYED":
			_stats["decoyed"] += 1
		if not _receives_report(by_unit): return
		map.add_effect(threat.position, "intercept" if reason == "INTERCEPTED" else "decoy", true)
		_world_view.add_effect(threat.position, "intercept" if reason == "INTERCEPTED" else "decoy", true, _effect_height(threat))
		SoundFx.play("intercept", 0.3)
		radio.flash("%s %s" % [threat.spec.display_name, reason.to_lower()], "good", by_unit)
		if reason == "INTERCEPTED":
			voice.say("interceptor_kill", by_unit)
	Debug.event("[Defence] %s %s by %s" % [threat.spec.display_name, reason, by_unit.callsign if by_unit != null else "?"])


## Where the 3D view draws what happened to a round: at its height, or on the sea over a torpedo.
static func _effect_height(threat: Weapon) -> float:
	return 0.0 if threat.spec.is_torpedo() else threat.spec.altitude_m


func _on_decoys_spent(u: Unit, count: int) -> void:
	if u.faction == simulation.player_faction:
		_stats["decoys_used"] += count
		if not _receives_report(u): return
		map.add_effect(u.position, "decoy", true)
		_world_view.add_effect(u.position, "decoy", true, u.altitude_m if u.is_aircraft() else 10.0)


## Decoys pulled a round off one ship and it found another. Worth saying out loud: the escort's
## chaff has just handed the missile to whoever was behind it.
func _on_weapon_seduced(threat: Weapon, from_unit: Unit, to_unit: Unit) -> void:
	var from_reports := from_unit.faction == simulation.player_faction and _receives_report(from_unit)
	var to_reports := to_unit.faction == simulation.player_faction and _receives_report(to_unit)
	if not from_reports and not to_reports and not _commander_sees_threat(threat): return
	var own := to_reports
	map.add_effect(threat.position, "decoy", own)
	_world_view.add_effect(threat.position, "decoy", own, _effect_height(threat))
	if from_reports or to_reports:
		radio.flash("%s decoyed off %s — re-acquired %s" % [threat.spec.display_name, _radio_name(from_unit), _radio_name(to_unit)], "alert" if own else "warn")
	Debug.event("[Defence] %s decoyed off %s, re-acquired %s" % [threat.spec.display_name, from_unit.callsign, to_unit.callsign])


## Fire and flooding aboard. Only our own ships report; an enemy's fight for its ship is not ours
## to see, and its loss already arrives as a destruction.
func _on_casualty_event(u: Unit, event: String) -> void:
	if event == "lost":
		_foundered[u] = true
	Debug.event("[Damage] %s %s" % [u.callsign, event])
	if u.faction != simulation.player_faction or not _receives_report(u):
		return
	match event:
		"fire_out":
			radio.flash("Fire out", "good", u)
			voice.say("fire_out", u)
		"flooding_controlled":
			radio.flash("Flooding under control", "good", u)


func _on_weapon_impact(faction: String, spec: WeaponSpec, target: Unit, hit: bool) -> void:
	var own_target := target.faction == simulation.player_faction
	if hit:
		_stats["hits"] += 1
		if own_target:
			_stats["hits_taken"] += 1
		elif faction == simulation.player_faction:
			_stats["hits_scored"] += 1
	_stats["leaked"] += 1
	# Internal after-action counts keep the result. The live watch receives only reports or
	# independently witnessed effects; faction ownership alone cannot report a silent hit.
	var observed := _combat_observed(target, own_target)
	if not observed: return
	if not hit:
		map.add_effect(target.position, "miss", false, target)
		_world_view.add_effect(target.position, "miss", false, -1.0, target)
		Debug.event("[Combat] %s miss on %s" % [spec.display_name, target.callsign])
		return
	# The chart and the 3D view show only a hit someone could witness; the clock and the speaker
	# keep to the same rule.
	if observed:
		SimClock.drop_to_realtime()
		SoundFx.play("impact", 0.2)
	map.add_effect(target.position, "hit", own_target, target)
	_world_view.add_effect(target.position, "hit", own_target, -1.0, target)
	if own_target and _receives_report(target):
		var casualties := ""
		if target.fire > 0.0:
			casualties += " · FIRE"
		if target.flooding > 0.0:
			casualties += " · FLOODING"
		radio.flash("Hit — %s%s" % [Damage.condition_text(target).to_lower(), casualties], "alert", target)
		voice.say("own_ship_hit", target)
	else:
		# Only what the plot holds: the contact's track label, never its true name or health.
		var t := _held_track(target)
		if t != null:
			radio.flash("Hit", "good", t)
		elif faction == simulation.player_faction:
			radio.flash("Weapon hit", "good")
	Debug.event("[Combat] %s hit %s (%s, %.0f%%)" % [spec.display_name, target.callsign, Damage.condition_text(target), Damage.health_fraction(target) * 100.0])


func _on_unit_destroyed(u: Unit, killer_faction: String) -> void:
	var own := u.faction == simulation.player_faction
	var neutral := simulation.track_manager.neutral_factions.has(u.faction)
	# These are after-action facts; live radio/effects below still require a report or witness.
	if own:
		_losses.append(u.callsign)
	elif killer_faction == simulation.player_faction:
		if neutral: _civilian_incidents.append(_radio_name(u))
		else: _kills.append(_radio_name(u))
	if not _combat_observed(u, own): return
	SimClock.drop_to_realtime()
	SoundFx.play("impact", 0.0)
	map.add_effect(u.position, "destroyed", own and _receives_report(u), u)
	_world_view.add_effect(u.position, "destroyed", own and _receives_report(u), -1.0, u)
	if own:
		radio.flash("%s %s" % [u.callsign, "LOST TO FIRE AND FLOODING" if _foundered.has(u) else "DESTROYED"], "alert")
		voice.say("unit_lost", null, {"name": u.callsign})
	else:
		if killer_faction == simulation.player_faction:
			if neutral:
				radio.flash("CIVILIAN LOSS — your force sank a neutral vessel", "alert")
			else:
				voice.say("target_destroyed", null, {"track": _held_track(u)})
		var t := _held_track(u)
		if t != null:
			radio.flash("Neutral vessel lost" if neutral else "Destroyed", "alert" if neutral else "good", t)
		elif killer_faction == simulation.player_faction and not neutral:
			radio.flash("Target destroyed", "good")
	Debug.event("[Combat] %s destroyed by %s" % [u.callsign, killer_faction])


## Combat hands the watch back at real time, and sounds, only for what the player's side could
## know: its own shot, hit or loss, or one a lookout could see or the plot holds (the 3D view's own
## witness rule). An enemy salvo nobody has detected must not announce itself by slowing the clock;
## when its rounds are detected, _on_threat_detected drops it then.
func _combat_observed(subject: Unit, own_involved: bool) -> bool:
	var own := simulation.unit_manager.get_faction_units(simulation.player_faction)
	own = own.filter(func(u: Unit) -> bool: return _receives_report(u))
	if subject != null and subject.faction == simulation.player_faction and not _receives_report(subject): own_involved = false
	return WorldPresentation.combat_observed(subject, own_involved, own, simulation.track_manager.get_tracks(simulation.player_faction), Detection.environment)


static func _receives_report(u: Unit) -> bool:
	return u != null and (not SubmarineComms.restricted(u) or SubmarineComms.connected(u))


func _commander_sees_track(t: Track) -> bool:
	if t == null or t.owner_faction != simulation.player_faction: return false
	var ref := map.reference_unit()
	if ref == null or not _receives_report(ref): return t.networked
	return t.visible_to(ref)


func _commander_sees_threat(w: Weapon) -> bool:
	var ref := map.reference_unit()
	if ref != null and _receives_report(ref): return simulation.threat_manager.visible_to(ref, w)
	for u: Unit in simulation.unit_manager.get_faction_units(simulation.player_faction):
		if u.datalink_connected() and simulation.threat_manager.visible_to(u, w): return true
	return false


func _commander_inbound() -> Array:
	var ref := map.reference_unit()
	if ref != null and not _receives_report(ref): ref = null
	return AirDefence.inbound_threats(simulation.unit_manager, simulation.threat_manager, simulation.player_faction, ref).filter(func(e: Dictionary) -> bool: return _commander_sees_threat(e["weapon"]))


## The player's own track on another side's unit, if the plot holds it (association is the one
## sanctioned use of a track's truth link).
func _held_track(u: Unit) -> Track:
	var t := simulation.track_manager.find_track(simulation.player_faction, u)
	return t if t != null and t.status != Track.Status.LOST else null


## How the radio names a unit: an own unit by its callsign, anything else by the track the plot
## holds on it, or not at all.
func _radio_name(u: Unit) -> String:
	if u.faction == simulation.player_faction:
		return u.callsign if _receives_report(u) else "an unreported contact"
	var t := _held_track(u)
	return t.label() if t != null else "another contact"


func _on_engagement_rejected(shooter: Unit, spec: WeaponSpec, reason: String) -> void:
	if shooter.faction == simulation.player_faction and _receives_report(shooter):
		radio.flash("Cannot fire %s: %s" % [spec.display_name, reason], "warn", shooter)
		# A queued round the weapon system cancels was never an order the crew refused.
		if not reason.begins_with("QUEUED ROUND CANCELLED"):
			voice.say("order_refused", shooter)


func _on_mission_ended(result: String, summary: String) -> void:
	if data_display != null:
		data_display.close_details()
	SimClock.set_paused(true)
	_set_background_input_enabled(false)
	var mm := simulation.mission_manager
	var objectives: Array = []
	objectives.append_array(mm.victory_objectives)
	radio.flash(result, "good" if result == "VICTORY" else "alert")
	voice.say("mission_won" if result == "VICTORY" else "mission_lost")
	var assessment := mm.assessment()
	# The log is the commander's record: a mission the AI fought for the player, or one ended
	# before anyone took command (a harness), is graded on the debrief but not entered.
	# The log records when the commander set the score, as the 1999 log did, not the operation's date.
	var logged := CommanderLog.record(str(simulation.scenario.get("id", "")), result, int(assessment["percent"]), Time.get_datetime_string_from_system(false, true)) if _command_taken and not simulation.ai_plays_player and not _scripted_session else {}
	radio.flash("Mission effectiveness %d%%%s" % [int(assessment["percent"]), " — a new best" if bool(logged.get("improved", false)) and int(logged.get("attempts", 1)) > 1 else ""], "good" if int(assessment["percent"]) >= 50 else "warn")
	_report.show_report(result, summary, _stats, objectives, _losses, _kills, SimClock.sim_time, radio.journal, _civilian_incidents, mm.loss_objectives, radio.journal_omitted, assessment, logged, str(simulation.scenario.get("id", "")))
	SoundFx.play("victory" if result == "VICTORY" else "defeat")
	Debug.event("[Mission] %s — %s" % [result, summary])
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
		radio.advise("Select a shooter before you engage")
	else:
		radio.advise("Engagement refused for %s — check weapon solution and weapons posture" % t.id)


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
	elif u.patrol_active and remaining.size() >= 3:
		if not simulation.unit_manager.issue_order(u, Order.patrol(remaining)):
			radio.flash(UnitManager.patrol_rejection(u, remaining), "warn", u)
			if _receives_report(u): voice.say("order_refused", u)
	else:
		simulation.unit_manager.issue_order(u, Order.move(remaining[0], false))
		for i in range(1, remaining.size()):
			simulation.unit_manager.issue_order(u, Order.move(remaining[i], true))
	SoundFx.play("click", 0.05)


## Right-click on the chart, when it is not a direct transit order: the Orders menu on your own
## platform, Engage With on a contact, the route menu on a waypoint, the CDS menu otherwise.
func _on_map_context(screen_pos: Vector2, context: Dictionary) -> void:
	var items: Array = []
	match str(context.get("kind", "")):
		"own_unit":
			var u: Unit = context.get("unit")
			if u != null and not map.selected.has(u):
				map.select_units([u])
			items = CdsMenus.orders_items(map.selected, map.selected_track, _all_controllable(map.selected), _all_movable(map.selected), simulation.weapon_manager)
		"weapon":
			var w: Weapon = context.get("weapon")
			if w == null:
				return
			items = CdsMenus.weapon_items(w, map.selected, _all_controllable(map.selected), _all_movable(map.selected))
		"track":
			var t: Track = context.get("track")
			if t == null:
				return
			var shooters: Array = map.selected if _all_controllable(map.selected) else []
			items = CdsMenus.engage_items(shooters, t, not shooters.is_empty(), simulation.weapon_manager)
		"waypoint":
			var owner: Unit = context.get("waypoint_unit")
			if owner == null or owner.faction != simulation.player_faction:
				return
			items = CdsMenus.waypoint_items(owner, int(context.get("waypoint_index", 0)))
		_:
			items = CdsMenus.cds_items(_cds_state())
	map.menu_open = true
	_cds_menus.open(items, context.get("viewport_pos", map.get_global_transform_with_canvas() * screen_pos))


func _run_cds_action(action: Dictionary) -> void:
	match str(action.get("kind", "")):
		"order":
			_apply_order_to_selection(action["order"])
		"unit_orders":
			_apply_unit_orders(action["pairs"])
		"altitude":
			_apply_unit_orders(_altitude_orders(float(action["metres"])))
		"depth":
			var pairs := _depth_orders(float(action["metres"]))
			if pairs.is_empty():
				radio.advise("No boat can get under the layer here" if float(action["metres"]) == -2.0 else "No hooked platform can dive")
			else:
				_apply_unit_orders(pairs)
		"formation":
			_apply_formation(str(action["pattern"]))
		"engage":
			var t: Track = action["track"]
			if map.selected_track != t:
				map.select_track(t)
			_apply_order_to_selection(Order.engage(t, str(action["weapon"]), int(action["rounds"])))
		"attack":
			var t: Track = action["track"]
			if map.selected_track != t:
				map.select_track(t)
			_apply_order_to_selection(Order.attack(t, str(action.get("weapon", ""))))
		"investigate":
			_apply_order_to_selection(Order.investigate(action["track"]))
		"air_strike":
			_open_air_strike(action["track"])
		"group_attack":
			_open_group_attack(action["track"], int(action.get("budget", 0)))
		"waypoint_delete":
			_on_waypoint_delete_requested(action["unit"], int(action["index"]))
		"layer":
			map.toggle_layer(str(action["name"]))
		"symbols":
			map.set_symbol_mode(int(action["mode"]))
		"board":
			status_boards.open_board(int(action["board"]))
			if action.has("tab"):
				orders_panel._tabs.current_tab = int(action["tab"])
		"inspect":
			_inspect_asset(str(action["id"]))
		"palette":
			_run_palette_action(str(action["id"]))


## Altitude presets: a negative value means each airframe's own cruise altitude, or its ceiling.
func _altitude_orders(metres: float) -> Array:
	var pairs: Array = []
	for u: Unit in map.selected:
		if not u.is_aircraft():
			continue
		var wanted := metres
		if metres == -1.0:
			wanted = u.spec.cruise_altitude_m
		elif metres == -2.0:
			wanted = u.spec.max_altitude_m
		pairs.append([u, Order.set_altitude(clampf(wanted, 0.0, u.spec.max_altitude_m))])
	return pairs


## Depth presets: -1 is each boat's patrol depth, -2 under the layer where there is one.
func _depth_orders(metres: float) -> Array:
	var pairs: Array = []
	for u: Unit in map.selected:
		if u.spec.max_depth_m <= 0.0:
			continue
		var wanted := u.spec.patrol_depth_m if metres < 0.0 else metres
		if metres == -2.0:
			wanted = Acoustics.below_layer_depth_m(u, true)
			if wanted < 0.0:
				continue
		pairs.append([u, Order.set_depth(clampf(wanted, 0.0, u.spec.max_depth_m))])
	return pairs


## One order goes to every selected unit. The acknowledgement makes group commands legible: a
## mixed force may accept an order only on the platforms that support it, and that is never silent.
func _apply_order_to_selection(order: Order) -> void:
	var accepted := 0
	var refused := 0
	var queued := 0
	var rounds_committed := 0
	var interceptors_before := int(_stats.get("launched", 0))
	var refusal := ""
	for u in map.selected:
		if u.faction == simulation.player_faction:
			var before := _committed_for_order(u, order)
			order.receipt = ""  # each platform's delivery or refusal, if it has one
			if simulation.unit_manager.issue_order(u, order):
				accepted += 1
				if order.receipt.begins_with("Queued for submarine"): queued += 1
				if order.type == Order.Type.ENGAGE:
					rounds_committed += maxi(_committed_for_order(u, order) - before, 0)
			else:
				refused += 1
				if order.type == Order.Type.INTERCEPT and refusal == "":
					refusal = order.receipt if order.receipt != "" else AirDefence.intercept_rejection(u)
	var receipt := _order_acknowledgement(Order.engage(order.track, order.weapon_id, rounds_committed)) if order.type == Order.Type.ENGAGE and accepted > 0 else ""
	if receipt != "":
		receipt += " · %d rounds committed" % rounds_committed
	if order.type == Order.Type.INTERCEPT:
		order.receipt = refusal
		if accepted > 0:
			var away := int(_stats.get("launched", 0)) - interceptors_before
			receipt = _order_acknowledgement(order) + (" · %d interceptor%s away" % [away, "" if away == 1 else "s"] if away > 0 else " · cleared to fire as it closes")
	if queued > 0:
		receipt = "Queued for submarine check-in · %d orders" % queued if queued == accepted else "%d orders sent · %d queued for submarine check-in" % [accepted - queued, queued]
	_report_orders(order, accepted, refused, receipt)


## Orders that carry a different value for each platform, such as each airframe's cruise altitude.
func _apply_unit_orders(pairs: Array) -> void:
	var accepted := 0
	var refused := 0
	var queued := 0
	var sample: Order = null
	var volleys := {}
	var rounds_committed := 0
	for pair: Array in pairs:
		var u: Unit = pair[0]
		if u.faction != simulation.player_faction or not map.selected.has(u):
			continue
		sample = pair[1]
		var before := _committed_for_order(u, sample)
		pair[1].execution_accepted = simulation.unit_manager.issue_order(u, pair[1])
		if pair[1].execution_accepted:
			accepted += 1
			if sample.receipt.begins_with("Queued for submarine"): queued += 1
			if sample.type == Order.Type.ENGAGE:
				var key := "%s|%s" % [sample.track.id, sample.weapon_id]
				if not volleys.has(key):
					volleys[key] = {"track": sample.track, "weapon": sample.weapon_id, "rounds": 0}
				var committed := maxi(_committed_for_order(u, sample) - before, 0)
				volleys[key]["rounds"] += committed
				rounds_committed += committed
		else:
			refused += 1
	if sample != null:
		var receipts := PackedStringArray()
		for volley: Dictionary in volleys.values():
			receipts.append(_order_acknowledgement(Order.engage(volley["track"], volley["weapon"], volley["rounds"])))
		var receipt := "; ".join(receipts)
		if not receipts.is_empty():
			receipt += " · %d rounds committed" % rounds_committed
		if queued > 0:
			receipt = "Queued for submarine check-in · %d orders" % queued if queued == accepted else "%d orders sent · %d queued for submarine check-in" % [accepted - queued, queued]
		_report_orders(sample, accepted, refused, receipt)


func _committed_for_order(u: Unit, order: Order) -> int:
	if order.type != Order.Type.ENGAGE:
		return 0
	var spec := u.get_weapon(order.weapon_id)
	return simulation.weapon_manager.committed_rounds(u, spec, order.track) if spec != null else 0


func _report_orders(order: Order, accepted: int, refused: int, receipt_override := "") -> void:
	var attempted := accepted + refused
	if accepted > 0:
		SoundFx.play("click", 0.05)
		var receipt := receipt_override if receipt_override != "" else _order_acknowledgement(order)
		var speaker: Unit = map.selected[0] if map.selected.size() == 1 else null
		if not _receives_report(speaker): speaker = null
		if speaker == null or accepted > 1:
			receipt += " · %d orders accepted" % accepted
		if refused > 0:
			receipt += " / %d refused" % refused
		radio.flash(receipt, "warn" if refused > 0 else "good", speaker)
		var reporter := speaker if speaker != null else _first_own(map.selected)
		if not receipt.begins_with("Queued for submarine") and reporter != null:
			voice.say(_ack_event(order), reporter, {"track": order.track})
		if order.type == Order.Type.SET_ROE and order.roe == Unit.Roe.FREE:
			radio.flash("Weapons free permits firing on unidentified contacts. Neutral sinkings can fail the mission.", "warn")
		if order.type == Order.Type.MOVE and not Terrain.is_empty() and not receipt.begins_with("Queued for submarine"):
			for u in map.selected:
				if u.faction == simulation.player_faction and u.needs_sea_room() and Terrain.first_land_contact(SubmarineComms.reported_position(u), order.target_pos) >= 0.0:
					radio.flash("Land on that course — following the coast", "warn", u)
					break
	elif attempted > 0:
		# The platform says it cannot; the console says why.
		var reporter := _first_own(map.selected)
		if reporter != null: voice.say("order_refused", reporter)
		if order.type == Order.Type.INVESTIGATE and not map.selected.is_empty():
			radio.advise(UnitManager.investigation_rejection(map.selected[0], order.track))
			return
		if order.type == Order.Type.ATTACK and not map.selected.is_empty():
			radio.advise("Cannot attack track %s: %s" % [DataDisplay.track_number_for_track(order.track), UnitManager.attack_rejection(map.selected[0], order.track, order.weapon_id).to_lower()])
			return
		if order.type == Order.Type.SET_SPEED and map.selected.any(func(u: Unit) -> bool: return u.patrol_active):
			radio.advise("Speed refused: allow more turning room in the patrol area, or assign a transit route")
			return
		if order.type == Order.Type.PATROL and not map.selected.is_empty():
			radio.advise(UnitManager.patrol_rejection(map.selected[0], order.route))
			return
		if order.type == Order.Type.RETURN_TO_STATION and not map.selected.is_empty():
			radio.advise("Cannot return to station: " + UnitManager.station_rejection(map.selected[0]).to_lower())
			return
		if order.type == Order.Type.INTERCEPT:
			radio.advise("Cannot intercept: " + (order.receipt if order.receipt != "" else "no hooked ship can engage").to_lower())
			return
		radio.advise("Order refused by %d selected platform%s%s" % [refused, "" if refused == 1 else "s", " — pick a point in the water" if order.type == Order.Type.MOVE else ""])
		if order.type == Order.Type.MOVE:
			map.add_effect(order.target_pos, "refused")
			_world_view.add_effect(order.target_pos, "refused")
	else:
		radio.advise("Select a controllable platform first")


## Which spoken acknowledgement an accepted order earns: attack and investigate name the track.
static func _ack_event(order: Order) -> String:
	if order.type == Order.Type.ENGAGE or order.type == Order.Type.ATTACK:
		return "attack_ack"
	if order.type == Order.Type.INVESTIGATE:
		return "investigate_ack"
	return "order_ack"


## The first communicating own unit: a disconnected crew cannot acknowledge a group order.
func _first_own(units: Array) -> Unit:
	for u: Unit in units:
		if u.faction == simulation.player_faction and u.alive and _receives_report(u):
			return u
	return null


## A short crew response ties the command to the platform and the plotted target.
static func _order_acknowledgement(order: Order) -> String:
	if order.receipt != "": return order.receipt
	match order.type:
		Order.Type.MOVE:
			return "Waypoint added, aye" if order.append else "Making for the ordered position, aye"
		Order.Type.PATROL:
			return "Establishing patrol, aye"
		Order.Type.RETURN_TO_STATION:
			return "Returning to station, aye"
		Order.Type.SET_AUTO_RETURN:
			return "Auto-return to station %s, aye" % ("on" if order.automatic else "off")
		Order.Type.INVESTIGATE:
			return "Investigating track %s" % DataDisplay.track_number_for_track(order.track)
		Order.Type.ATTACK:
			var chosen := DataDB.weapon(order.weapon_id) if order.weapon_id != "" else null
			return "Attacking track %s%s" % [DataDisplay.track_number_for_track(order.track), " with %s" % chosen.compact_name() if chosen != null else ""]
		Order.Type.ENGAGE:
			var weapon := DataDB.weapon(order.weapon_id)
			return "Engaging track %s, %d × %s" % [DataDisplay.track_number_for_track(order.track), order.salvo, weapon.compact_name() if weapon != null else order.weapon_id]
		Order.Type.STOP:
			return "All stop, aye"
		Order.Type.RETURN_TO_BASE:
			return "Returning to %s" % (order.recovery_base.callsign if order.recovery_base != null else "base")
		Order.Type.INTERCEPT:
			return "Engaging inbound #%d" % order.threat.id if order.threat != null else "Engaging inbound weapons"
	return order.describe().capitalize() + ", aye"


func _toggle_radar_on_selection() -> void:
	var capable := 0
	var active := 0
	for u in map.selected:
		if u.has_radar():
			capable += 1
			if u.radar_on:
				active += 1
	if capable == 0:
		radio.advise("The selection has no radar")
		return
	_apply_order_to_selection(Order.silence_radar() if active == capable else Order.activate_radar())


## Formation orders are per-unit, so they cannot go through the broadcast path.
func _apply_formation(pattern: String) -> void:
	var own: Array = []
	for u in map.selected:
		if u.faction == simulation.player_faction and not u.is_aircraft():
			own.append(u)
	if own.size() < 2:
		radio.advise("Select a leader and at least one consort to form up")
		return
	if own[0].in_formation():
		simulation.unit_manager.issue_order(own[0], Order.break_formation())
	var accepted := 0
	var queued := 0
	var axis := -1.0
	if pattern in ["aaw_screen", "asw_screen"]:
		var nearest := INF
		for t: Track in simulation.track_manager.get_tracks(simulation.player_faction):
			if t.status != Track.Status.ACTIVE or t.identity != "HOSTILE" or t.is_bearing_only(): continue
			if pattern == "aaw_screen" and t.domain != "air": continue
			if pattern == "asw_screen" and t.domain != "subsurface": continue
			var distance: float = SubmarineComms.reported_position(own[0]).distance_squared_to(t.position)
			if distance < nearest:
				nearest = distance
				axis = Geo.bearing_deg(SubmarineComms.reported_position(own[0]), t.position)
	for entry: Dictionary in Formation.assign(own, pattern, 1.0, axis):
		var consort: Unit = entry["unit"]
		if simulation.unit_manager.issue_order(consort, entry["order"]):
			accepted += 1
			if entry["order"].receipt.begins_with("Queued for submarine"): queued += 1
			if pattern == "asw_screen" and TowedArray.rejection(consort) == "":
				simulation.unit_manager.issue_order(consort, Order.asw_search())
	radio.flash("%s: %d consorts assigned on %s%s" % [pattern.to_upper(), accepted - queued, own[0].callsign, " · %d queued for submarine check-in" % queued if queued > 0 else ""], "good")
	var reporter := _first_own(own)
	if reporter != null and accepted > queued: voice.say("order_ack", reporter)


func _store_control_group(number: int) -> void:
	var ids: Array = []
	for u: Unit in map.selected:
		if u.alive and u.faction == simulation.player_faction:
			ids.append(u.id)
	if ids.is_empty():
		radio.advise("Select friendly platforms before saving a group")
		return
	_control_groups[number] = ids
	radio.advise("Group %d saved: %d platforms. Alt+%d recalls it." % [number, ids.size(), number])


func _recall_control_group(number: int) -> void:
	var own: Array = []
	for u in simulation.unit_manager.units:
		if u.is_engageable() and u.faction == simulation.player_faction and _control_groups.get(number, []).has(u.id):
			own.append(u)
	if own.is_empty():
		radio.advise("Group %d has no available platforms" % number)
		return
	map.select_units(own)
	map.center_on_selection()


func _toggle_emcon_on_selection() -> void:
	var state := orders_panel._selection_state("emcon")
	if state < 0:
		radio.advise("Select a controllable platform first")
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
		radio.advise("The selection has no sonar")
		return
	_apply_order_to_selection(Order.passive_sonar() if active == capable else Order.active_sonar())
	for u in map.selected:
		if u.active_sonar_on and _receives_report(u):
			SoundFx.play("ping", 0.5)
			break


func _on_track_added(faction: String, t: Track) -> void:
	if faction != simulation.player_faction or not _commander_sees_track(t):
		return
	SimClock.drop_to_realtime()
	_stats["contacts"] += 1
	radio.flash("New contact, track %s (%s)" % [DataDisplay.track_number_for_track(t), DataDisplay.source_text(t.source)], "warn")
	SoundFx.play("contact", 0.5)
	voice.say("new_contact", null, {"track": t})
	contact_panel.refresh()
	Debug.event("[Contact] %s gained on %s at %.1f nm from the nearest of ours" % [t.id, t.source, _nearest_own_distance(t.position)])


func _on_track_classified(faction: String, t: Track) -> void:
	if faction != simulation.player_faction or not _commander_sees_track(t):
		return
	if t.classification == Track.Classification.CLASS_KNOWN:
		SimClock.drop_to_realtime()
		if t.identity == "HOSTILE":
			_stats["classified"] += 1
		radio.flash("Track %s classified %s, %s" % [DataDisplay.track_number_for_track(t), t.known_class, t.identity.to_lower()], "alert" if t.identity == "HOSTILE" else "info")
		SoundFx.play("classified", 0.5)
		if t.identity == "HOSTILE":
			voice.say("contact_hostile", null, {"track": t})
		Debug.event("[Contact] %s classified as %s (%s)" % [t.id, t.known_class, t.identity])
	elif t.classification == Track.Classification.IDENTIFIED:
		radio.flash("Track %s identified as %s" % [DataDisplay.track_number_for_track(t), t.known_callsign])


func _on_track_lost(faction: String, t: Track) -> void:
	if faction == simulation.player_faction and _commander_sees_track(t):
		radio.flash("Track %s lost" % DataDisplay.track_number_for_track(t), "warn")


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
