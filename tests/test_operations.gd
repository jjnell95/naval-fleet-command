extends TestCase


func _air_harness(loadout: Dictionary = {"aim120_family": 2}) -> Array:
	Terrain.clear()
	var um := UnitManager.new()
	ScenarioLoader.populate(um, {"units": [{"platform": "usn_cvn_nimitz", "callsign": "Carrier", "faction": "BLUE",
		"aviation_stores": {"aim120_family": 3}, "aviation_buoys": 0,
		"air_wing": [{"platform": "usn_fighter_fa18e", "count": 2, "callsign": "CAP", "loadout": loadout}]}]})
	var av := AviationManager.new()
	av.unit_manager = um
	return [um, av, um.units[0], um.units[1], um.units[2]]


func test_rearming_conserves_shared_stocks_and_keeps_authored_fit() -> void:
	var h := _air_harness()
	var a: Unit = h[3]
	var b: Unit = h[4]
	a.magazines["aim120_family"] = 0
	b.magazines["aim120_family"] = 0
	h[1]._step_turnaround(a, 1)
	h[1]._step_turnaround(b, 1)
	assert_eq(a.magazine_count("aim120_family"), 2)
	assert_eq(b.magazine_count("aim120_family"), 1, "second section shares remaining stock")
	assert_eq(h[2].aviation_stores["aim120_family"], 0)
	assert_eq(a.magazine_count("agm_158c_lrasm"), 0, "CAP does not turn into a strike fit")
	assert_eq(a.weapons.size(), 1)
	a.magazines["aim120_family"] = 0
	h[1]._step_turnaround(a, 1)
	assert_eq(a.magazine_count("aim120_family"), 0, "an empty base cannot rearm again")
	h[1].free()
	h[0].free()


func test_empty_authored_fit_stays_unarmed_and_diversion_cannot_conjure_stock() -> void:
	var h := _air_harness({})
	h[1]._step_turnaround(h[3], 1)
	assert_true(h[3].magazines.is_empty())
	assert_true(h[3].weapons.is_empty())
	var other := Unit.new()
	other.spec = h[2].spec
	h[4].home = other
	h[4].sortie_loadout = {"aim120_family": 2}
	h[1]._step_turnaround(h[4], 1)
	assert_eq(h[4].magazine_count("aim120_family"), 0)
	h[1].free()
	h[0].free()


func test_reserve_aircraft_prepare_once_without_reloading_or_taking_deck_slots() -> void:
	var h := _air_harness()
	var a: Unit = h[3]
	a.flight_state = Unit.FlightState.RESERVE
	a.state_timer_s = 2
	a.magazines["aim120_family"] = 1
	assert_eq(h[2].launch_spots_busy(), 0)
	assert_true(h[1].launch(h[2], a.callsign) == null)
	h[1]._run_cycle(1, 1)
	assert_true(not a.ready_to_launch())
	h[1]._run_cycle(1, 2)
	assert_true(a.ready_to_launch())
	assert_eq(a.magazine_count("aim120_family"), 1)
	assert_eq(h[2].aviation_stores["aim120_family"], 3)
	h[1].free()
	h[0].free()


func test_reserves_share_host_loss_and_damaged_deck_cannot_launch() -> void:
	var h := _air_harness()
	h[2].fire = 0.5
	assert_true(h[1].launch(h[2], h[3].callsign) == null)
	h[3].flight_state = Unit.FlightState.RESERVE
	h[3].state_timer_s = 10
	h[2].alive = false
	h[1]._run_cycle(1, 1)
	assert_true(not h[3].alive)
	assert_true(not h[4].alive)
	h[1].free()
	h[0].free()


func test_hold_station_requires_continuous_presence_and_excludes_stowed_aircraft() -> void:
	var h := _air_harness()
	var um: UnitManager = h[0]
	var o := MissionObjective.from_dict({"type": "hold_area", "callsigns": ["Carrier"], "radius_nm": 5, "seconds": 300})
	assert_true(not o.evaluate(um, 0))
	assert_true(not o.evaluate(um, 299))
	h[2].position = Vector2(6, 0)
	assert_true(not o.evaluate(um, 300))
	h[2].position = Vector2.ZERO
	assert_true(not o.evaluate(um, 301))
	assert_true(not o.evaluate(um, 600))
	assert_true(o.evaluate(um, 601))
	var aircraft := MissionObjective.from_dict({"type": "hold_area", "callsigns": [h[3].callsign], "seconds": 1})
	assert_true(not aircraft.evaluate(um, 0))
	assert_true(not aircraft.evaluate(um, 10), "embarked airframe cannot fly a patrol")
	h[1].free()
	h[0].free()


func test_phase_prerequisite_cannot_end_any_mode_mission_and_loss_still_wins() -> void:
	var h := _air_harness()
	var mm := MissionManager.new()
	mm.unit_manager = h[0]
	mm.configure({"victory_mode": "any", "objectives": {"victory": [
		{"id": "prepare", "type": "time_elapsed", "seconds": 10, "phase_only": true},
		{"id": "finish", "type": "time_elapsed", "seconds": 20, "after": ["prepare"]}],
		"loss": [{"id": "lost", "type": "unit_lost", "callsigns": ["Carrier"]}]}})
	mm.tick(10)
	assert_eq(mm.result, MissionManager.Result.RUNNING)
	assert_true(mm.victory_objectives[0].complete)
	h[2].alive = false
	mm.tick(20)
	assert_eq(mm.result, MissionManager.Result.DEFEAT)
	mm.free()
	h[1].free()
	h[0].free()


func test_mission_restart_resets_hold_and_dependencies() -> void:
	var h := _air_harness()
	var mm := MissionManager.new()
	mm.unit_manager = h[0]
	var sc := {"objectives": {"victory": [{"id": "station", "type": "hold_area", "faction": "BLUE", "seconds": 5}]}}
	mm.configure(sc)
	mm.tick(0)
	mm.tick(5)
	assert_eq(mm.result, MissionManager.Result.VICTORY)
	mm.configure(sc)
	mm.tick(0)
	assert_eq(mm.result, MissionManager.Result.RUNNING)
	assert_eq(mm.victory_objectives[0].held_seconds, 0.0)
	mm.free()
	h[1].free()
	h[0].free()


func test_follow_on_force_does_not_reset_existing_airframes_or_duplicate_homes() -> void:
	var h := _air_harness()
	var a: Unit = h[3]
	a.flight_state = Unit.FlightState.AIRBORNE
	a.position = Vector2(50, 50)
	a.fuel_s = 99
	a.magazines["aim120_family"] = 0
	ScenarioLoader.populate(h[0], {"units": [{"platform": "cw90_tu22m3", "callsign": "Raid", "faction": "RED", "position_nm": [100, 100]}]})
	assert_eq(h[2].embarked.size(), 2)
	assert_eq(a.position, Vector2(50, 50))
	assert_eq(a.fuel_s, 99.0)
	assert_eq(a.magazine_count("aim120_family"), 0)
	assert_eq(h[2].aviation_stores["aim120_family"], 3)
	assert_true(h[0].units.back().airborne())
	h[1].free()
	h[0].free()


func test_all_operations_have_valid_dependencies_wings_and_finite_stores() -> void:
	var operations := 0
	var exercises := 0
	for entry: Dictionary in ScenarioIndex.list_all():
		if entry.custom:
			continue
		var sc := ScenarioLoader.load_file(entry.path)
		if entry.collection == "exercises":
			exercises += 1
			assert_eq(ScenarioMenu._shelf_of(entry), "exercises")
			continue
		operations += 1
		assert_eq(sc.operation_plan.size(), 3)
		var ids := {}
		for o: Dictionary in sc.objectives.victory:
			for previous: String in o.get("after", []):
				assert_true(ids.has(previous), "%s prerequisite defined before use: %s" % [entry.id, previous])
			assert_true(not ids.has(o.id), "unique objective id")
			ids[o.id] = true
		var um := UnitManager.new()
		Terrain.clear()
		ScenarioLoader.populate(um, sc)
		var names := {}
		for u in um.units:
			assert_true(not names.has(u.callsign), "%s unique callsign: %s" % [entry.id, u.callsign])
			names[u.callsign] = true
			if u.spec.id in ["usn_cvn_nimitz", "usn_cvn_ford"]:
				assert_eq(u.embarked.size(), 59, "%s has the larger air wing" % entry.id)
				assert_true(u.stowed_aircraft().size() < u.embarked.size(), "reserve remains aboard")
			assert_true(u.embarked.size() <= u.spec.aircraft_capacity)
			for wid: String in u.aviation_stores:
				assert_true(DataDB.weapon(wid) != null and int(u.aviation_stores[wid]) >= 0)
			for wid: String in u.sortie_loadout:
				assert_true(u.spec.weapon_loadout.has(wid), "authored aircraft weapon is supported")
		# An event waits on objectives or on events listed before it. Every variant's arrivals are
		# new identities: whichever is drawn, no callsign aliases the opening force.
		for o: Dictionary in sc.objectives.loss:
			ids[o.id] = true
		for event: Dictionary in sc.get("events", []):
			for previous: String in event.get("after", []):
				assert_true(ids.has(previous), "%s event %s waits on %s" % [entry.id, event.id, previous])
			ids[event.id] = true
			var arrivals := {}
			for shape: Dictionary in [event] + event.get("variants", []):
				for ud: Dictionary in shape.get("reinforcements", []):
					assert_true(not names.has(ud.callsign), "reinforcement identity does not alias opening force")
					arrivals[ud.callsign] = true
					assert_true(DataDB.platform(ud.platform) != null)
					if int(sc.year) == 1990:
						assert_true(str(ud.platform).begins_with("cw90_"))
			names.merge(arrivals)
		assert_eq(ScenarioWorkshop.validate(sc), "", "%s passes the authoring checks, events included" % entry.id)
		um.free()
	assert_eq(operations, 7, "one 2027 operation per chart region and three from 1990")
	assert_eq(exercises, 2, "Northern Passage and Carrier Qualification")


## Replaying an operation means reading the plot again. Every operation draws part of its shape
## per engagement (a raid's window and axis, how many come, where a ship waits, whether a report or
## a second force comes at all); the same seed draws the same operation, and two seeds draw two.
func test_each_operation_draws_its_shape_from_the_engagement_seed() -> void:
	var operations := 0
	for entry: Dictionary in ScenarioIndex.list_all():
		if entry.custom or entry.collection != "operations":
			continue
		operations += 1
		var sc := ScenarioLoader.load_file(entry.path)
		assert_true(sc.has("seed"), "%s has its own seed, so the menu replays one engagement" % entry.id)
		var draws := {}
		for seed in [2, 13, 2]:
			var director := OperationDirector.new()
			director.configure(sc, seed)
			if draws.has(seed):
				assert_eq(director.variant, draws[seed], "%s: the same seed draws the same operation" % entry.id)
			draws[seed] = director.variant.duplicate(true)
			director.free()
		assert_true(not draws[2].is_empty(), "%s draws part of its shape per engagement" % entry.id)
		assert_true(draws[2] != draws[13], "%s: seeds 2 and 13 draw different operations: %s / %s" % [entry.id, draws[2], draws[13]])
	assert_eq(operations, 7)


## Every operation gives the opposing force a mission of its own (an AIPlan) instead of leaving it to
## shoot at the nearest contact: the plan's members are the enemy's own units and the wing elements
## tagged for it, a raid or swarm that enters later is tagged to join on arrival, and nothing in a
## plan names a unit of the player's side. Plans act only on the enemy's own picture (test_ai_plans).
func test_each_operation_gives_the_enemy_a_mission_plan() -> void:
	SimClock.set_paused(true)
	var operations := 0
	for entry: Dictionary in ScenarioIndex.list_all():
		if entry.custom or entry.collection != "operations":
			continue
		operations += 1
		var sc := ScenarioLoader.load_file(entry.path)
		var defs: Array = sc.get("ai_plans", [])
		assert_true(not defs.is_empty(), "%s gives the enemy a plan" % entry.id)
		assert_eq(ScenarioWorkshop.validate(sc), "", entry.id)
		var player_units := {}
		for u: Dictionary in sc["units"]:
			if u["faction"] == sc.get("player_faction", "BLUE"):
				player_units[u["callsign"]] = true
		for d: Dictionary in defs:
			for key: String in ["units", "protect", "recon"]:
				for name in d.get(key, []):
					assert_true(typeof(name) != TYPE_STRING or not player_units.has(name), "%s: a plan never names %s" % [entry.id, name])
		var sim := Simulation.new()
		sim.seed_override = 2
		(Engine.get_main_loop() as SceneTree).root.add_child(sim)
		assert_true(sim.load_scenario(entry.path))
		SimClock.advance(2.0)  # the first decision cycle adopts the members
		var c: AIController = sim.ai_controllers.get("RED")
		assert_true(c != null and c.plans.size() == defs.size(), entry.id)
		for p: AIPlan in c.plans:
			assert_true(not p.members.is_empty(), "%s: plan %s has members from the start" % [entry.id, p.id])
			for m: Unit in p.members:
				assert_eq(m.faction, "RED", "%s: %s" % [p.id, m.callsign])
		# Units that enter later join the plan their tag names.
		for e: Dictionary in sc.get("events", []):
			for shape: Dictionary in [e] + e.get("variants", []):
				for r: Dictionary in shape.get("reinforcements", []):
					if r.has("ai_plan"):
						assert_true(defs.any(func(d: Dictionary) -> bool: return d["id"] == r["ai_plan"]), "%s: %s joins a plan that exists" % [entry.id, r["callsign"]])
		sim.unit_manager.clear()
		sim.free()
	assert_eq(operations, 7)


## The acceptance case in a shipped operation: in Carrier Watch the Soviet force is after the
## carrier. Slava and the Backfire hold their first rounds until their own picture has classified
## her, then fire at her together, past the cruiser and the destroyer nearer them.
func test_carrier_watch_raid_pursues_the_carrier_not_the_nearest_escort() -> void:
	SimClock.set_paused(true)
	var sim := Simulation.new()
	sim.seed_override = 13
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	assert_true(sim.load_scenario("res://data/scenarios/cold_war_03_carrier.json"))
	var shots: Array = []
	var record := func(u: Unit, o: Order) -> void:
		if u.faction == "RED" and o.type == Order.Type.ENGAGE and o.track != null:
			shots.append({"t": SimClock.sim_time, "unit": u.callsign, "category": o.track.known_category, "truth": o.track.truth})
	sim.unit_manager.order_issued.connect(record)
	while shots.is_empty() and SimClock.sim_time < 2400.0:
		SimClock.advance(10.0)
	sim.unit_manager.order_issued.disconnect(record)
	assert_true(not shots.is_empty(), "the raid fires within forty minutes")
	var carrier: Unit = null
	for u in sim.unit_manager.units:
		if u.callsign == "USS Dwight D. Eisenhower (CVN 69)":
			carrier = u
	var first: Dictionary = shots[0]
	assert_true(str(first["category"]).contains("carrier"), "the first round goes at a contact classified as a carrier: %s" % first)
	assert_eq(first["truth"], carrier)
	var plan: AIPlan = sim.ai_controllers["RED"].plans[0]
	assert_eq(plan.kind, AIPlan.Kind.THREATEN_CARRIER)
	for shot: Dictionary in shots:
		assert_true(shot["t"] == first["t"] and shot["truth"] == carrier, "one volley, at the carrier: %s" % shot)
	var nearer := 0
	for name: String in ["USS Bunker Hill (CG 52)", "USS Spruance (DD 963)"]:
		for u in sim.unit_manager.units:
			if u.callsign == name and u.position.distance_to(_unit_by_name(sim, "Slava").position) < carrier.position.distance_to(_unit_by_name(sim, "Slava").position):
				nearer += 1
	assert_true(nearer > 0, "an escort stood nearer Slava than the carrier did")
	sim.unit_manager.clear()
	sim.free()


func _unit_by_name(sim: Simulation, callsign: String) -> Unit:
	for u in sim.unit_manager.units:
		if u.callsign == callsign:
			return u
	return null


## A player's start of an operation draws its events from a fresh variation seed; the engagement's
## own streams (sensors, weapons, damage) keep the scenario seed, and a save keeps the variation.
func test_a_fresh_variation_changes_the_draw_and_nothing_else() -> void:
	var path := "res://data/scenarios/cold_war_03_carrier.json"
	var sc := ScenarioLoader.load_file(path)
	var expected := OperationDirector.new()
	expected.configure(sc, 5)
	var sim := Simulation.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	sim.variation_seed = 5
	assert_true(sim.load_scenario(path))
	assert_eq(sim.base_seed, int(sc.seed), "the engagement keeps the scenario's seed")
	assert_eq(sim.sensor_manager.rng.seed, int(sc.seed), "and its sensor stream")
	assert_eq(sim.director.variant, expected.variant, "the events are drawn from the variation")
	var snap := SimSnapshot.capture(sim)
	sim.variation_seed = -1
	assert_eq(sim.restore_snapshot(snap), "")
	assert_eq(sim.variation_seed, 5, "a saved engagement keeps its variation for a restart")
	expected.free()
	sim.unit_manager.clear()
	sim.free()


## The second Backfire element keeps no timetable: its window and its latest moment are drawn per
## engagement, and it goes sooner only when RED's own plot holds the carrier (or Slava is hit). It
## arrives once, on nobody's plot, and a reload draws the same operation again.
func test_scheduled_raid_fires_once_preserves_fog_and_resets_on_reload() -> void:
	var sim := Simulation.new()
	sim.seed_override = 13
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	assert_true(sim.load_scenario("res://data/scenarios/cold_war_03_carrier.json"))
	var raid := sim.director.event("follow_on_raid")
	var latest := float(raid["latest_s"])
	var arriving: Array = raid["reinforcements"]
	assert_true(latest >= 2700.0 and latest <= 3600.0, "the latest moment is drawn from its window: %s" % latest)
	assert_true(not arriving.is_empty())
	sim._tick_operation_events(0.25)  # the opening draws (Slava's station, the first raid's axis) act at once
	var initial := sim.unit_manager.units.size()
	sim._tick_operation_events(latest - 1.0)
	assert_eq(sim.unit_manager.units.size(), initial, "RED's plot holds nothing, so the raid waits for its latest moment")
	sim._tick_operation_events(latest)
	assert_eq(sim.unit_manager.units.size(), initial + arriving.size())
	var raider: Unit = sim.unit_manager.units.back()
	assert_eq(raider.callsign, str(arriving.back()["callsign"]))
	assert_true(raider.airborne())
	assert_true(sim.track_manager.find_track("BLUE", raider) == null, "a new raid is not an automatic contact report")
	sim._tick_operation_events(latest + 1.0)
	assert_eq(sim.unit_manager.units.size(), initial + arriving.size())
	assert_true(sim.reload())
	assert_true(sim.completed_events.is_empty())
	assert_eq(float(sim.director.event("follow_on_raid")["latest_s"]), latest, "the same seed draws the same operation")
	sim._tick_operation_events(0.25)
	assert_eq(sim.unit_manager.units.size(), initial)
	sim.free()
