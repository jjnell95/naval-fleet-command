extends TestCase
## Integration round R7: a scouting aircraft watching a carrier keeps out of the known air-defence
## cover of the escort beside it, so it is not shot down there and the strike it scouts for goes in.

const FIXTURE := "res://tests/fixtures/ai_plan_carrier.json"


func _run(seed: int) -> Dictionary:
	SimClock.set_paused(true)
	var sim := Simulation.new()
	sim.seed_override = seed
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	assert_true(sim.load_scenario(FIXTURE), FIXTURE)
	var carrier_shots := [0]
	var record := func(u: Unit, o: Order) -> void:
		if u.faction == "RED" and o.type == Order.Type.ENGAGE and o.track != null and str(o.track.known_category).contains("carrier"):
			carrier_shots[0] += 1
	sim.unit_manager.order_issued.connect(record)
	var frigate: Unit = null
	var scout: Unit = null
	for u in sim.unit_manager.units:
		if u.callsign == "Picket":
			frigate = u
		elif u.callsign == "Backfire Scout":
			scout = u
	var closest := INF
	var elapsed := 0.0
	while elapsed < 3600.0:
		SimClock.advance(10.0)
		elapsed += 10.0
		if scout.alive:
			closest = minf(closest, scout.position.distance_to(frigate.position))
	var out := {"alive": scout.alive, "closest": closest, "carrier_shots": carrier_shots[0]}
	sim.unit_manager.order_issued.disconnect(record)
	sim.unit_manager.clear()
	sim.queue_free()
	sim.free()
	return out


func test_a_scout_watching_a_carrier_keeps_out_of_the_escorts_missile_cover() -> void:
	# Seeds 5 and 7 are the ones where the scout used to hold its distance from the carrier over the
	# Perry beside it, inside her SM-1 reach, and was shot down; the strike then never went in.
	for seed in [5, 7]:
		var r := _run(seed)
		assert_true(r["alive"], "seed %d: the scout survives the hour" % seed)
		assert_true(float(r["closest"]) > 23.0, "seed %d: the scout stays outside the Perry's 23 nm SM-1 (closest %.1f nm)" % [seed, r["closest"]])
		assert_true(int(r["carrier_shots"]) > 0, "seed %d: the raid gets its missiles away at the carrier" % seed)
