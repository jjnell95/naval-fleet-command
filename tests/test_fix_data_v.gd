extends TestCase
## The data as a commander plays it: an anti-submarine barrier laid out at sea scale, so the hunt
## starts with a search and not a contact, and naval guns that can be laid on what a gun is for.

const BARRIER := "res://data/scenarios/cold_war_02_barrier.json"
const DALLAS := "USS Dallas (SSN 700)"
const SPRUANCE := "USS Spruance (DD 963)"
const VICTOR := "Soviet submarine (Victor III)"


func _open(path: String, seed_value: int) -> Simulation:
	SimClock.set_paused(true)
	var sim := Simulation.new()
	sim.seed_override = seed_value
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	assert_true(sim.load_scenario(path), path)
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


func _v(p: Array) -> Vector2:
	return Vector2(float(p[0]), float(p[1]))


func _unit_entry(sc: Dictionary, callsign: String) -> Dictionary:
	for u: Dictionary in sc["units"]:
		if u["callsign"] == callsign:
			return u
	return {}


func _objective(list: Array, id: String) -> Dictionary:
	for o: Dictionary in list:
		if o["id"] == id:
			return o
	return {}


## Miles a boat sailing `route` from `start` covers before it is inside the exit circle.
func _miles_to_exit(start: Vector2, route: Array, exit_at: Vector2, radius: float) -> float:
	var travelled := 0.0
	var here := start
	for p in route:
		var there := _v(p)
		var leg := here.distance_to(there)
		var steps := int(ceil(leg / 0.1))
		for i in steps:
			var at := here.lerp(there, float(i + 1) / float(steps))
			travelled += leg / float(steps)
			if at.distance_to(exit_at) <= radius:
				return travelled
		here = there
	return INF


## Whether the ship holds the boat on a track of her own sensors, not on an intelligence cue the
## plot shares with her.
func _heard(sim: Simulation, ship: Unit, boat: Unit) -> bool:
	var t := sim.track_manager.find_for(ship, boat)
	return t != null and not t.reported


# --- The Iceland-Faroe Barrier ---------------------------------------------------------------

## Dallas used to open 6.9 nm from the Victor III, inside her own passive reach of it, and held it
## from the first second: a single Attack order was the whole mission. The boat now opens far up
## its lane, so neither barrier ship has it on her own sonar in the first twenty minutes.
func test_the_barrier_opens_with_a_search_not_a_contact() -> void:
	for seed_value: int in [2, 7, 13]:
		var sim := _open(BARRIER, seed_value)
		var dallas := _named(sim, DALLAS)
		var spruance := _named(sim, SPRUANCE)
		var victor := _named(sim, VICTOR)
		assert_true(dallas != null and spruance != null and victor != null, "the barrier has its boat, its destroyer and the intruder")
		var opening := dallas.position.distance_to(victor.position)
		assert_true(opening > 20.0, "seed %d: the Victor opens beyond Dallas's hearing and a Mk 48's reach (%.1f nm)" % [seed_value, opening])
		var heard_at := -1.0
		for minute in 20:
			SimClock.advance(60.0)
			if heard_at < 0.0 and (_heard(sim, dallas, victor) or _heard(sim, spruance, victor)):
				heard_at = SimClock.sim_time
		assert_true(heard_at < 0.0, "seed %d: neither barrier ship holds the boat on her own sonar in the first twenty minutes (held at %.0f s)" % [seed_value, heard_at])
		var plotted := sim.track_manager.find_track(sim.player_faction, victor)
		assert_true(plotted == null or plotted.reported, "seed %d: the plot holds at most a wide intelligence cue, not a sonar track" % seed_value)
		_close(sim)


## The lanes cross the barrier line further apart than one listener covers, the breakout is not a
## point every lane meets, and a boat left alone on any lane still breaks out inside the watch at
## its quiet transit speed, so holding the watch is earned.
func test_every_lane_is_a_real_breakout_inside_the_watch() -> void:
	var sc := ScenarioLoader.load_file(BARRIER)
	var watch := float(_objective(sc["objectives"]["victory"], "watch").get("seconds", 0.0))
	var exit: Dictionary = _objective(sc["objectives"]["loss"], "breakout")
	assert_true(watch > 0.0 and not exit.is_empty(), "the barrier has a watch and a breakout")
	var exit_at := _v(exit["center_nm"])
	var radius := float(exit["radius_nm"])
	var boat: Dictionary = _unit_entry(sc, VICTOR)
	var start := _v(boat["position_nm"])
	var transit := DataDB.platform(str(boat["platform"])).cruise_speed_kn
	var dallas := _v(_unit_entry(sc, DALLAS)["position_nm"])
	var lane_event: Dictionary = {}
	for e: Dictionary in sc["events"]:
		if e["id"] == "transit_lane":
			lane_event = e
	assert_eq(lane_event.get("variants", []).size(), 3, "the boat has three lanes")
	var crossings: Array[Vector2] = []
	for variant: Dictionary in lane_event.get("variants", []):
		var route: Array = variant["ai"][0]["patrol_nm"]
		var miles := _miles_to_exit(start, route, exit_at, radius)
		var hours := miles / transit
		assert_true(miles > 25.0, "%s lane: tens of miles to the breakout (%.1f nm)" % [variant["id"], miles])
		assert_true(hours * 3600.0 < watch - 600.0, "%s lane: an unopposed boat at %.0f kn breaks out inside the watch (%.1f h of %.1f)" % [variant["id"], transit, hours, watch / 3600.0])
		if route.size() > 1:
			crossings.append(_v(route[0]))
	assert_eq(crossings.size(), 2, "two lanes leave the direct line")
	if crossings.size() == 2:
		assert_true(crossings[0].distance_to(crossings[1]) > 20.0, "the outer lanes cross the barrier %.1f nm apart, more than Dallas hears a quiet Victor across" % crossings[0].distance_to(crossings[1]))
	assert_true(dallas.distance_to(exit_at) > radius, "Dallas does not open inside the breakout")
	assert_true(radius >= 8.0, "the breakout is a broad exit south of the line (radius %.0f nm), not a point every lane converges on" % radius)
