extends TestCase
## Operations open the way an operation should: the force on its route and in formation, its
## escorts radiating, the enemy where the briefing puts him, and the chart on the force, with
## the commander given time to take the picture in before the shooting starts.

const HORMUZ := "res://data/scenarios/gulf_01_hormuz.json"
const OPERATIONS := ["aegis_bastion", "cold_war_01_convoy", "cold_war_02_barrier", "cold_war_03_carrier",
	"gulf_01_hormuz", "med_01_tartus", "pacific_02_taiwan_strait"]


func _open(path: String, seed_value: int, both_sides := false) -> Simulation:
	SimClock.set_paused(true)
	var sim := Simulation.new()
	sim.seed_override = seed_value
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	assert_true(sim.load_scenario(path), path)
	if both_sides:
		sim.ai_plays_player = true
		sim._build_ai()
	return sim


func _close(sim: Simulation) -> void:
	sim.unit_manager.clear()
	sim.get_parent().remove_child(sim)
	sim.free()


func _named(sim: Simulation, callsign: String) -> Unit:
	for u: Unit in sim.unit_manager.units:
		if u.callsign == callsign:
			return u
	return null


func _scenario(id: String) -> Dictionary:
	return ScenarioLoader.load_file("res://data/scenarios/%s.json" % id)


## Hormuz used to have sixteen missiles in the air by 95 s on every seed, from a battery 15 nm off
## the convoy, before an escort could be placed or the battery seen. The shore batteries now come
## out of their hides later, so the opening minutes are the commander's; they still come.
func test_hormuz_gives_the_commander_his_opening_before_the_shore_fires() -> void:
	for seed_value: int in [1, 2, 45]:
		var sim := _open(HORMUZ, seed_value)
		var first := {"at": INF, "what": ""}
		sim.weapon_manager.weapon_launched.connect(func(shooter: Unit, spec: WeaponSpec, _t: Track, _n: int) -> void:
			if shooter.faction == "RED" and spec.type != "sam" and SimClock.sim_time < float(first["at"]):
				first["at"] = SimClock.sim_time
				first["what"] = "%s fires %s" % [shooter.callsign, spec.display_name])
		SimClock.advance(480.0)
		assert_true(float(first["at"]) == INF, "seed %d: nothing is fired at the force in the first eight minutes (%s at %.0f s)" % [seed_value, first["what"], float(first["at"])])
		SimClock.advance(1200.0)
		var qeshm := _named(sim, "Qeshm coastal battery")
		assert_true(qeshm != null, "seed %d: the Qader battery has come out by 28 minutes" % seed_value)
		_close(sim)
