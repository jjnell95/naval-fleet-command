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


# --- Naval guns ---------------------------------------------------------------------------------

## A destroyer with the gun under test fitted, a target of `platform` at `range_nm` dead ahead, and
## the director's track on it.
func _gun_range(gun_id: String, platform: String, domain: String, range_nm: float, hover := true) -> Dictionary:
	var um := UnitManager.new()
	var target_def := {"platform": platform, "callsign": "Target", "faction": "RED", "position_nm": [0, range_nm], "heading_deg": 90.0, "speed_kn": 0.0}
	ScenarioLoader.populate(um, {"units": [
		{"platform": "usn_ddg_arleigh_burke_iia", "callsign": "Shooter", "faction": "BLUE", "position_nm": [0, 0], "heading_deg": 0.0, "speed_kn": 0.0},
		target_def]})
	var ship: Unit = um.units[0]
	var target: Unit = um.units[1]
	if domain == "air":
		target.flight_state = Unit.FlightState.AIRBORNE
		target.altitude_m = 150.0
		target.fuel_s = 99999.0
		if hover:
			# In the hover, as a dipping helicopter is.
			target.speed_kn = 0.0
			target.ordered_speed_kn = 0.0
			target.waypoints.clear()
	var spec := DataDB.weapon(gun_id)
	if ship.get_weapon(gun_id) == null:
		ship.weapons.append(spec)
	ship.magazines[spec.id] = 600
	var wm := WeaponManager.new()
	wm.unit_manager = um
	wm.rng.seed = 7
	Damage.rng.seed = 7
	var t := Track.new()
	t.id = "G1"
	t.owner_faction = "BLUE"
	t.truth = target
	t.position = target.position
	t.status = Track.Status.ACTIVE
	t.domain = domain
	t.identity = "HOSTILE"
	t.has_kinematics = true
	t.altitude_m = target.altitude_m
	return {"um": um, "wm": wm, "ship": ship, "target": target, "track": t, "spec": spec}


func _free_range(r: Dictionary) -> void:
	(r["um"] as UnitManager).free()
	(r["wm"] as WeaponManager).free()


## Every naval gun listed only ships, and the 76 mm and 57 mm mounts not even a contact ashore, so
## a destroyer could not put a round into a hovering helicopter four miles off or a coastal battery
## five miles inland: WRONG WEAPON FOR CONTACT. Every mount in the catalogue is dual-purpose.
func test_a_naval_gun_can_be_laid_on_a_helicopter_and_a_shore_battery() -> void:
	var guns := DataDB.all_weapons().filter(func(w: WeaponSpec) -> bool: return w.is_gun())
	assert_true(guns.size() >= 15, "the catalogue's guns are found")
	for spec: WeaponSpec in guns:
		var reach := minf(4.0, spec.max_range_nm - 1.0)
		var air := _gun_range(spec.id, "rn_helo_wildcat", "air", reach)
		var check: Dictionary = (air["wm"] as WeaponManager).engagement_check(air["ship"], spec, air["track"], 0.0)
		assert_true(check["ok"], "%s may be laid on a helicopter %.0f nm off (%s)" % [spec.id, reach, check.get("reason", "")])
		_free_range(air)
		var ashore := _gun_range(spec.id, "irn_battery_qader", "land", reach)
		check = (ashore["wm"] as WeaponManager).engagement_check(ashore["ship"], spec, ashore["track"], 0.0)
		assert_true(check["ok"], "%s may be laid on a coastal battery %.0f nm off (%s)" % [spec.id, reach, check.get("reason", "")])
		_free_range(ashore)


## The rounds a 76 mm mount fires at a helicopter fly, arrive and are resolved like any other
## gunfire: in the hover some hit and it is hurt; flying, each round still bursts or goes by where
## it passes, rather than circling the helicopter until it runs out of range.
func test_rounds_fired_at_a_helicopter_arrive_and_some_hit() -> void:
	for hover: bool in [true, false]:
		var r := _gun_range("oto_76mm_gun", "rn_helo_wildcat", "air", 3.0, hover)
		var wm: WeaponManager = r["wm"]
		var um: UnitManager = r["um"]
		var helicopter: Unit = r["target"]
		var tally := {"hit": 0, "resolved": 0, "ran_out": 0}
		wm.weapon_impact.connect(func(_f: String, _s: WeaponSpec, _u: Unit, hit: bool) -> void:
			tally["resolved"] += 1
			if hit:
				tally["hit"] += 1)
		wm.weapon_resolved.connect(func(w: Weapon) -> void:
			if w.dead_reason == "RANGE EXHAUSTED":
				tally["ran_out"] += 1)
		var before := helicopter.health
		var rounds := 20 if hover else 6
		wm.launch(r["ship"], r["spec"], r["track"], rounds, 0.0)
		var now := 0.0
		while now < float(rounds) * (r["spec"] as WeaponSpec).launch_interval_s + 60.0:
			now += SimClock.TICK_DT
			um.tick(SimClock.TICK_DT)
			wm.tick(SimClock.TICK_DT, now)
		var how := "in the hover" if hover else "flying"
		assert_true(int(tally["resolved"]) > 0, "%s: the rounds reach the helicopter and are resolved (%d)" % [how, int(tally["resolved"])])
		assert_eq(int(tally["ran_out"]), 0, "%s: no round circles it until it runs out of range" % how)
		if hover:
			assert_true(int(tally["hit"]) > 0 and helicopter.health < before, "some of twenty hit (%d), and it is hurt (%.1f of %.1f)" % [int(tally["hit"]), helicopter.health, before])
		_free_range(r)


## At its full reach a gun used to keep half its rated chance, 0.28 a round against a stopped
## destroyer: long-range gunnery that sank ships. It now falls to under one in five against
## anything, however large and however still, while close in the rating stands.
func test_a_gun_at_its_full_reach_hits_fewer_than_one_round_in_five() -> void:
	var big := Unit.new()
	big.spec = DataDB.platform("civ_tanker_vlcc")
	big.speed_kn = 0.0
	var burke := Unit.new()
	burke.spec = DataDB.platform("usn_ddg_arleigh_burke_iia")
	burke.speed_kn = 0.0
	for spec: WeaponSpec in DataDB.all_weapons():
		if not spec.is_gun():
			continue
		var at_limit := Combat.hit_probability(spec, big, spec.max_range_nm)
		assert_true(at_limit < 0.2, "%s at %.0f nm against a stopped tanker: %.2f a round" % [spec.id, spec.max_range_nm, at_limit])
		var close := Combat.hit_probability(spec, burke, 1.0)
		assert_true(close > 0.35, "%s at a mile against a stopped destroyer keeps its rating: %.2f" % [spec.id, close])
		# The fire control sizes its salvo on the same fall with range.
		var plotted := Track.new()
		plotted.has_kinematics = true
		plotted.speed_kn = 0.0
		var judged := burke.expected_hit_chance(spec, plotted, spec.max_range_nm)
		assert_true(judged < 0.2, "%s: the fire control expects under one in five at full reach too (%.2f)" % [spec.id, judged])


# --- Installations ashore -----------------------------------------------------------------------

## Every installation had no length, so the 3D view drew each at its 150 m fallback: an air base's
## runway 150 m long. Each now has the footprint of its kind: a runway for an air station, a few
## hundred metres to a kilometre for a battery or a missile site.
func test_every_installation_ashore_has_the_footprint_of_its_kind() -> void:
	var seen := 0
	for p: PlatformSpec in DataDB.all_platforms():
		if p.domain != "land":
			continue
		seen += 1
		var drawn := WorldPresentation.length_of(p)
		assert_true(p.length_m > 0.0, "%s has a footprint length of its own" % p.id)
		if p.flight_facility() == "airfield":
			assert_true(drawn >= 2000.0, "%s is drawn with a runway's length (%.0f m)" % [p.id, drawn])
		else:
			assert_true(drawn >= 200.0 and drawn <= 1500.0, "%s is drawn the size of a battery or a missile site (%.0f m)" % [p.id, drawn])
	assert_true(seen >= 12, "the catalogue's installations are found (%d)" % seen)
