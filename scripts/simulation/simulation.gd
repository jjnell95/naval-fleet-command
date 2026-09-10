class_name Simulation
extends Node
## Root of the simulation layer. Hosts managers and forwards SimClock ticks to them.
## Contains no UI references.

var unit_manager: UnitManager
var track_manager: TrackManager
var sensor_manager: SensorManager
var weapon_manager: WeaponManager
var threat_manager: ThreatManager
var aviation_manager: AviationManager
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
	sensor_manager.weapon_manager = weapon_manager
	weapon_manager.weapon_defeated.connect(func(w: Weapon, _r: String, _u: Unit) -> void: threat_manager.forget(w))
	aviation_manager = AviationManager.new()
	aviation_manager.name = "AviationManager"
	aviation_manager.unit_manager = unit_manager
	add_child(aviation_manager)
	sensor_manager.aviation_manager = aviation_manager
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
	scenario_path = path
	scenario_name = scenario.get("name", "UNNAMED")
	player_faction = scenario.get("player_faction", "BLUE")
	var m: Dictionary = scenario.get("map", {})
	var c: Array = m.get("center_nm", [0, 0])
	map_center = Vector2(c[0], c[1])
	map_extent_nm = float(m.get("extent_nm", 200.0))
	track_manager.neutral_factions = PackedStringArray()
	for f in scenario.get("neutral_factions", []):
		track_manager.neutral_factions.append(str(f))
	unit_manager.clear()
	track_manager.clear()
	threat_manager.clear()
	weapon_manager.clear()
	aviation_manager.clear()
	var base_seed := _resolve_seed(scenario)
	sensor_manager.rng.seed = base_seed
	weapon_manager.rng.seed = base_seed ^ 0x5EED
	Damage.rng.seed = base_seed ^ 0xDA46
	ScenarioLoader.populate(unit_manager, scenario)
	mission_manager.player_faction = player_faction
	mission_manager.configure(scenario)
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
func _build_ai() -> void:
	for c in ai_controllers.values():
		c.queue_free()
	ai_controllers.clear()
	var seen: Dictionary = {}
	for u in unit_manager.units:
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
		add_child(c)
		ai_controllers[u.faction] = c


func ai_state_for(u: Unit) -> String:
	var c: AIController = ai_controllers.get(u.faction)
	return c.describe(u) if c != null else ""


## ENGAGE orders are not unit state changes; they are routed to the weapon layer here so that
## the player and (from Milestone 5) the AI use one command path.
func _on_order_issued(u: Unit, o: Order) -> void:
	match o.type:
		Order.Type.ENGAGE:
			var spec := u.get_weapon(o.weapon_id)
			if spec != null:
				weapon_manager.launch(u, spec, o.track, o.salvo, SimClock.sim_time)
		Order.Type.LAUNCH_AIRCRAFT:
			aviation_manager.launch(u, o.aircraft_id)
		Order.Type.RETURN_TO_BASE:
			aviation_manager.request_return(u)
		Order.Type.DEPLOY_SONOBUOY:
			aviation_manager.deploy_sonobuoy(u, SimClock.sim_time)


func _on_tick(dt: float) -> void:
	unit_manager.tick(dt)
	sensor_manager.tick(dt)
	weapon_manager.tick(dt, SimClock.sim_time)
	aviation_manager.tick(dt, SimClock.sim_time)
	_defence_accum += dt
	while _defence_accum >= DEFENCE_DT - 1e-6:
		_defence_accum -= DEFENCE_DT
		AirDefence.run_cycle(unit_manager, threat_manager, weapon_manager, SimClock.sim_time)
	if ai_enabled:
		_ai_accum += dt
		while _ai_accum >= AI_DT - 1e-6:
			_ai_accum -= AI_DT
			for c in ai_controllers.values():
				c.tick(SimClock.sim_time)
	mission_manager.tick(SimClock.sim_time)
