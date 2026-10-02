class_name Simulation
extends Node
## Root of the simulation layer. Hosts managers and forwards SimClock ticks to them.
## Contains no UI references.

var unit_manager: UnitManager
var track_manager: TrackManager
var sensor_manager: SensorManager
var weapon_manager: WeaponManager
## Fire and flooding aboard a ship: `fire`, `fire_out`, `flooding_controlled`, `lost`.
signal casualty_event(unit: Unit, event: String)
signal operation_message(message: String)
var operation_events: Array = []
var completed_events: Dictionary = {}
var threat_manager: ThreatManager
var aviation_manager: AviationManager
var air_mission_manager: AirMissionManager
var group_attack_manager: GroupAttackManager
var mission_manager: MissionManager
var scenario: Dictionary = {}
var scenario_name := ""
var player_faction := "BLUE"
var map_center := Vector2.ZERO
var map_extent_nm := 200.0

const DEFENCE_DT := 1.0
const AI_DT := 2.0
var _defence_accum := 0.0
var _ai_accum := 0.0
var ai_controllers: Dictionary = {}  # faction -> AIController
var ai_enabled := true
## Dev only: let the opposing-force brain command the player's side too, so a scenario can be
## checked end to end by something that actually manoeuvres, launches aircraft and picks weapons.
var ai_plays_player := false
var scenario_path := ""
var seed_override := -1


func _ready() -> void:
	unit_manager = UnitManager.new()
	unit_manager.name = "UnitManager"
	add_child(unit_manager)
	track_manager = TrackManager.new()
	track_manager.name = "TrackManager"
	add_child(track_manager)
	threat_manager = ThreatManager.new()
	threat_manager.name = "ThreatManager"
	add_child(threat_manager)
	sensor_manager = SensorManager.new()
	sensor_manager.name = "SensorManager"
	sensor_manager.unit_manager = unit_manager
	sensor_manager.track_manager = track_manager
	sensor_manager.threat_manager = threat_manager
	add_child(sensor_manager)
	weapon_manager = WeaponManager.new()
	weapon_manager.name = "WeaponManager"
	weapon_manager.unit_manager = unit_manager
	weapon_manager.track_manager = track_manager
	add_child(weapon_manager)
	unit_manager.weapon_manager = weapon_manager
	sensor_manager.weapon_manager = weapon_manager
	weapon_manager.weapon_defeated.connect(func(w: Weapon, _r: String, _u: Unit) -> void: threat_manager.forget(w))
	weapon_manager.weapon_resolved.connect(threat_manager.forget)
	# Battle damage assessment: each side's plot learns from its own hits and the kills it sees.
	weapon_manager.weapon_impact.connect(track_manager.on_weapon_impact)
	weapon_manager.unit_destroyed.connect(track_manager.on_unit_destroyed)
	aviation_manager = AviationManager.new()
	aviation_manager.name = "AviationManager"
	aviation_manager.unit_manager = unit_manager
	add_child(aviation_manager)
	sensor_manager.aviation_manager = aviation_manager
	air_mission_manager = AirMissionManager.new()
	air_mission_manager.name = "AirMissionManager"
	air_mission_manager.unit_manager = unit_manager
	air_mission_manager.aviation_manager = aviation_manager
	air_mission_manager.track_manager = track_manager
	add_child(air_mission_manager)
	group_attack_manager = GroupAttackManager.new()
	group_attack_manager.name = "GroupAttackManager"
	group_attack_manager.unit_manager = unit_manager
	group_attack_manager.track_manager = track_manager
	group_attack_manager.weapon_manager = weapon_manager
	add_child(group_attack_manager)
	mission_manager = MissionManager.new()
	mission_manager.name = "MissionManager"
	mission_manager.unit_manager = unit_manager
	add_child(mission_manager)
	unit_manager.order_issued.connect(_on_order_issued)
	SimClock.tick.connect(_on_tick)


func load_scenario(path: String) -> bool:
	scenario = ScenarioLoader.load_file(path)
	if scenario.is_empty():
		return false
	# Keep full-rate sensors, defence and AI on different fixed ticks instead of one burst.
	_defence_accum = 0.5
	_ai_accum = 0.25
	sensor_manager._accum = 0.0
	sensor_manager._last_heading.clear()
	sensor_manager._manoeuvre.clear()
	scenario_path = path
	scenario_name = scenario.get("name", "UNNAMED")
	player_faction = scenario.get("player_faction", "BLUE")
	var m: Dictionary = scenario.get("map", {})
	var c: Array = m.get("center_nm", [0, 0])
	map_center = Vector2(c[0], c[1])
	map_extent_nm = float(m.get("extent_nm", 200.0))
	aviation_manager.map_center = map_center
	aviation_manager.map_extent_nm = map_extent_nm
	Detection.set_environment(scenario.get("environment", {}))
	Terrain.load_from(scenario)
	Bathymetry.load_for(scenario)
	track_manager.neutral_factions = PackedStringArray()
	for f in scenario.get("neutral_factions", []):
		track_manager.neutral_factions.append(str(f))
	unit_manager.clear()
	track_manager.clear()
	threat_manager.clear()
	weapon_manager.clear()
	aviation_manager.clear()
	air_mission_manager.clear()
	group_attack_manager.clear()
	var base_seed := _resolve_seed(scenario)
	sensor_manager.rng.seed = base_seed
	weapon_manager.rng.seed = base_seed ^ 0x5EED
	Damage.rng.seed = base_seed ^ 0xDA46
	ScenarioLoader.populate(unit_manager, scenario)
	mission_manager.player_faction = player_faction
	mission_manager.configure(scenario)
	operation_events = scenario.get("events", []).duplicate(true)
	completed_events.clear()
	_build_ai()
	SimClock.reset(ScenarioLoader.start_unix_time(scenario))
	return true


## Scenarios stay reproducible when they pin a seed or the session forces one; otherwise every
## run of the same scenario plays out differently.
func _resolve_seed(sc: Dictionary) -> int:
	if seed_override >= 0:
		return seed_override
	if sc.has("seed"):
		return int(sc["seed"])
	return randi()


func reload() -> bool:
	return load_scenario(scenario_path) if scenario_path != "" else false


## One controller per faction the player does not command. Each sees only its own picture.
func _build_ai(reset := true) -> void:
	if reset:
		for c in ai_controllers.values():
			c.queue_free()
		ai_controllers.clear()
	var seen: Dictionary = {}
	for u in unit_manager.units:
		if ai_controllers.has(u.faction):
			continue
		if seen.has(u.faction) or track_manager.neutral_factions.has(u.faction):
			continue
		if u.faction == player_faction and not ai_plays_player:
			continue
		seen[u.faction] = true
		var c := AIController.new()
		c.name = "AI_%s" % u.faction
		c.faction = u.faction
		c.unit_manager = unit_manager
		c.track_manager = track_manager
		c.threat_manager = threat_manager
		c.weapon_manager = weapon_manager
		c.air_mission_manager = air_mission_manager
		add_child(c)
		ai_controllers[u.faction] = c


func ai_state_for(u: Unit) -> String:
	var c: AIController = ai_controllers.get(u.faction)
	return c.describe(u) if c != null else ""


## ENGAGE orders are not unit state changes; they are routed to the weapon layer here so that
## the player and (from Milestone 5) the AI use one command path.
func _on_order_issued(u: Unit, o: Order) -> void:
	match o.type:
		Order.Type.DEPLOY_COUNTERMEASURES:
			o.execution_accepted = DefensiveResponse.deploy(u, o.countermeasure_kind, weapon_manager)
		Order.Type.EVADE:
			o.execution_accepted = DefensiveResponse.start_evasion(u, unit_manager, threat_manager, o.evasion_mode)
		Order.Type.SET_ROE:
			if u.roe == Unit.Roe.HOLD:
				weapon_manager.cancel_salvo(u)
		Order.Type.CANCEL_FIRE:
			# A member of a group attack leaves it first, so the group hears why its rounds came
			# back; the cancel then refunds whatever else the platform has queued.
			var withdrew := group_attack_manager.withdraw(u, o.track)
			o.execution_accepted = weapon_manager.cancel_salvo(u, o.track) > 0 or o.stopped_attack or withdrew
		Order.Type.ENGAGE:
			var spec := u.get_weapon(o.weapon_id)
			# Only the group manager's own crew orders spend from a group's budget; an ENGAGE from
			# the commander or the AI is always the platform's own fire.
			var group := o.group_id if o.origin == "crew" else -1
			o.execution_accepted = spec != null and weapon_manager.launch(u, spec, o.track, o.salvo, SimClock.sim_time, group)
		Order.Type.LAUNCH_AIRCRAFT:
			if o.aircraft_count > 1:
				# A section flies one type. The lead names it, so a mixed hangar does not put a
				# tanker off the catapult behind three fighters.
				var lead := aviation_manager.launch(u, o.aircraft_id)
				o.execution_accepted = lead != null
				if lead != null:
					aviation_manager.launch_flight(u, o.aircraft_count - 1, lead.spec.id)
			else:
				o.execution_accepted = aviation_manager.launch(u, o.aircraft_id) != null
		Order.Type.RETURN_TO_BASE:
			o.execution_accepted = aviation_manager.request_return(u, o.recovery_base)
		Order.Type.DEPLOY_SONOBUOY:
			o.execution_accepted = aviation_manager.deploy_sonobuoy(u, SimClock.sim_time) != null
		Order.Type.AIR_MISSION:
			air_mission_manager.now_s = SimClock.sim_time
			air_mission_manager.request(u, o)
		Order.Type.CANCEL_AIR_MISSION:
			o.execution_accepted = air_mission_manager.cancel(o.mission_id, u)
		Order.Type.GROUP_ATTACK:
			group_attack_manager.now_s = SimClock.sim_time
			group_attack_manager.request(u, o)
		Order.Type.CANCEL_GROUP_ATTACK:
			o.execution_accepted = group_attack_manager.cancel(o.group_id, u, o)


func _on_tick(dt: float) -> void:
	var profile_at := Time.get_ticks_usec()
	_tick_operation_events(SimClock.sim_time)
	unit_manager.tick(dt, SimClock.sim_time)
	for e: Dictionary in Damage.tick(unit_manager.units, dt):
		var u: Unit = e["unit"]
		casualty_event.emit(u, e["event"])
		if e["event"] == "lost":
			# Lost to fire or flooding after the fact: the same destruction every other system
			# already listens for, credited to whoever started it.
			weapon_manager.unit_destroyed.emit(u, u.last_attacker)
	Debug.time_add("sim/units", Time.get_ticks_usec() - profile_at)
	profile_at = Time.get_ticks_usec()
	sensor_manager.tick(dt)
	Debug.time_add("sim/sensors", Time.get_ticks_usec() - profile_at)
	profile_at = Time.get_ticks_usec()
	weapon_manager.tick(dt, SimClock.sim_time)
	Debug.time_add("sim/weapons", Time.get_ticks_usec() - profile_at)
	profile_at = Time.get_ticks_usec()
	aviation_manager.tick(dt, SimClock.sim_time)
	air_mission_manager.tick(dt, SimClock.sim_time)
	Debug.time_add("sim/aviation", Time.get_ticks_usec() - profile_at)
	# After the weapons have fired and resolved this tick, so a volley that has just arrived is
	# seen as arrived.
	group_attack_manager.tick(dt, SimClock.sim_time)
	profile_at = Time.get_ticks_usec()
	_defence_accum += dt
	while _defence_accum >= DEFENCE_DT - 1e-6:
		_defence_accum -= DEFENCE_DT
		DefensiveResponse.run_cycle(unit_manager, threat_manager, weapon_manager)
		AirDefence.run_cycle(unit_manager, threat_manager, weapon_manager, SimClock.sim_time)
		TorpedoDefence.run_cycle(unit_manager, threat_manager, weapon_manager, SimClock.sim_time)
	Debug.time_add("sim/defence", Time.get_ticks_usec() - profile_at)
	profile_at = Time.get_ticks_usec()
	if ai_enabled:
		_ai_accum += dt
		while _ai_accum >= AI_DT - 1e-6:
			_ai_accum -= AI_DT
			weapon_manager.begin_channel_batch()
			for c in ai_controllers.values():
				c.tick(SimClock.sim_time)
			weapon_manager.end_channel_batch()
	Debug.time_add("sim/ai", Time.get_ticks_usec() - profile_at)
	mission_manager.tick(SimClock.sim_time)


## Authored reinforcements enter once, through the same loader as the opening force.
## They receive no tracks or target truth. Only the authored command message is public;
## enemy reinforcements must still be detected by the player's sensors.
func _tick_operation_events(now: float) -> void:
	if mission_manager.result != MissionManager.Result.RUNNING:
		return
	for i in operation_events.size():
		var event: Dictionary = operation_events[i]
		var key := str(event.get("id", str(i)))
		if completed_events.has(key) or now < float(event.get("at_s", 0.0)):
			continue
		if not mission_manager.prerequisites_complete(PackedStringArray(event.get("after", []))):
			continue
		completed_events[key] = true
		if not event.get("reinforcements", []).is_empty():
			ScenarioLoader.populate(unit_manager, {"units": event["reinforcements"]})
			_build_ai(false)
		var message := str(event.get("message", ""))
		if message != "":
			operation_message.emit(message)
