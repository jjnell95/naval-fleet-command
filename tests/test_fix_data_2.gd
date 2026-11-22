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


## The briefing and the P-3C's report put the North Cape Kilo inside the screen; she started 47 nm
## east of the pickets and spent the watch outside them. She now opens between the pickets and the
## carrier, nearer the carrier than any picket is.
func test_the_north_cape_kilo_starts_inside_the_screen() -> void:
	var sim := _open("res://data/scenarios/aegis_bastion.json", 2)
	var kilo := _named(sim, "Kaluga (B-800)")
	var carrier := _named(sim, "USS Dwight D. Eisenhower (CVN 69)")
	var to_carrier := kilo.position.distance_to(carrier.position)
	for picket: String in ["USS Jack H. Lucas (DDG 125)", "USS Gettysburg (CG 64)"]:
		var p := _named(sim, picket)
		assert_true(kilo.position.x < p.position.x, "the Kilo is west of %s, on the group's side of the line" % picket)
		assert_true(to_carrier < p.position.distance_to(carrier.position), "and nearer the carrier than %s is" % picket)
	for leg: Vector2 in kilo.patrol_route:
		assert_true(leg.x < _named(sim, "USS Gettysburg (CG 64)").position.x, "her patrol stays inside the screen")
	_close(sim)


## Hormuz opened on its 267 nm theatre with the force as one pile of rings. The chart fits the
## commander's ships when a scenario authors no focus; an operation whose force moves (all of them)
## authors none, so the opening and Fit force (Home) are one frame. Every operation's opening view
## holds all of its ships, and at command scale rather than the theatre's.
func test_each_operation_opens_its_chart_on_the_force() -> void:
	for id: String in OPERATIONS:
		var sim := _open("res://data/scenarios/%s.json" % id, 7)
		var m: Dictionary = sim.scenario["map"]
		var view := CommanderPicture.force_view(sim.unit_manager, sim.player_faction)
		if m.has("focus_center_nm"):
			view = Vector3(float(m["focus_center_nm"][0]), float(m["focus_center_nm"][1]), float(m["focus_extent_nm"]))
		var half := view.z / 2.0
		for u: Unit in sim.unit_manager.get_faction_units(sim.player_faction):
			if u.spec.domain in ["surface", "subsurface"] and u.spec.max_speed_kn > 0.0:
				assert_true(absf(u.position.x - view.x) <= half and absf(u.position.y - view.y) <= half, "%s: %s is on the opening chart" % [id, u.callsign])
		assert_true(view.z <= sim.map_extent_nm * 0.6, "%s opens on the force (%d nm), not the theatre's %d" % [id, int(view.z), int(sim.map_extent_nm)])
		_close(sim)
