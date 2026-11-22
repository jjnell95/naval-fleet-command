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


## Every operation used to open with each own ship "Steady on" her authored heading, no route and
## no station. The main body now sails its route from the first second and the escorts are formed
## on the guide, so Return to Station has somewhere to go; ten minutes on they are still on it.
func test_every_operation_opens_with_its_force_on_route_and_on_station() -> void:
	for id: String in OPERATIONS:
		var sim := _open("res://data/scenarios/%s.json" % id, 7)
		var ships: Array[Unit] = []
		for u: Unit in sim.unit_manager.get_faction_units(sim.player_faction):
			if u.spec.domain == "surface" and u.spec.max_speed_kn > 0.0:
				ships.append(u)
		assert_true(not ships.is_empty(), "%s has ships" % id)
		var formed := 0
		for u: Unit in ships:
			var orders := DataDisplay.orders_text(u)
			assert_true(not orders.begins_with("Steady on"), "%s: %s opens with orders, not '%s'" % [id, u.callsign, orders])
			assert_true(u.in_formation() or u.patrol_active or u.has_route(), "%s: %s has a route or a station" % [id, u.callsign])
			if u.in_formation():
				formed += 1
				assert_true(u.has_station(), "%s: %s can be sent back to her station" % [id, u.callsign])
				assert_true(u.position.distance_to(Formation.station_for(u)) < 0.5, "%s: %s starts on her station" % [id, u.callsign])
		SimClock.advance(600.0)
		for u: Unit in ships:
			if u.is_engageable() and u.in_formation() and u.attack_track == null and u.investigation_track == null:
				assert_true(u.position.distance_to(Formation.station_for(u)) < 2.0, "%s: %s keeps her station ten minutes in (%.1f nm off)" % [id, u.callsign, u.position.distance_to(Formation.station_for(u))])
		if id != "cold_war_02_barrier":
			assert_true(formed >= 2, "%s: the escorts are formed on the guide (%d)" % [id, formed])
		_close(sim)


## USS Nicholas opened the convoy radar-off with no reason in the briefing, so she never defended
## and Elrod took the hit with Nicholas's 32 Standards still aboard. Every escort formed on a guide
## now radiates from the start, except where the briefing gives the reason for silence (Provence
## off Tartus keeps the Bastion battery's picture empty).
func test_no_escort_opens_blind_without_a_reason() -> void:
	var silent_by_brief := ["FS Provence (D 652)"]
	for id: String in OPERATIONS:
		var sim := _open("res://data/scenarios/%s.json" % id, 7)
		for u: Unit in sim.unit_manager.get_faction_units(sim.player_faction):
			if u.in_formation() and u.has_radar() and not silent_by_brief.has(u.callsign):
				assert_true(u.radar_on, "%s: %s is formed on the guide and radiating" % [id, u.callsign])
		_close(sim)
	var convoy := _open("res://data/scenarios/cold_war_01_convoy.json", 2)
	var nicholas := _named(convoy, "USS Nicholas (FFG 47)")
	assert_true(nicholas.radar_on and nicholas.emcon != Unit.Emcon.SILENT, "Nicholas radiates and has no silent order")
	_close(convoy)

