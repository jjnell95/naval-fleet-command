extends TestCase
## Rounds go for what they were fired at, and launchers do not block each other.

const DT := 0.25


func _hull(domain := "surface", hp := 100.0) -> PlatformSpec:
	var p := PlatformSpec.new()
	p.short_name = "Test hull"
	p.domain = domain
	p.max_speed_kn = 30.0
	p.cruise_speed_kn = 15.0
	p.health = hp
	return p


func _unit(faction: String, pos: Vector2, callsign: String, domain := "surface", hp := 100.0) -> Unit:
	var u := Unit.new()
	u.spec = _hull(domain, hp)
	u.faction = faction
	u.callsign = callsign
	u.position = pos
	u.health = hp
	u.roe = Unit.Roe.FREE
	u.decoys = 0
	if domain == "air":
		u.flight_state = Unit.FlightState.AIRBORNE
		u.altitude_m = 3000.0
		u.ordered_altitude_m = 3000.0
		u.fuel_s = 99999.0
	return u


func _radar() -> SensorSpec:
	var s := SensorSpec.new()
	s.kind = "radar"
	s.range_surface_nm = 40.0
	s.range_air_nm = 200.0
	s.antenna_height_m = 20.0
	return s


func _missile(id: String, type := "asm", targets: Array = ["surface"]) -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = id
	w.display_name = id
	w.type = type
	w.guidance = "active_radar_homing"
	w.profile = "high"
	w.target_types = PackedStringArray(targets)
	w.max_range_nm = 80.0
	w.min_range_nm = 0.5
	w.speed_kn = 1800.0
	w.turn_rate_deg_s = 40.0
	w.seeker_range_nm = 8.0
	w.damage = 40.0
	w.base_pk = 1.0
	w.launch_interval_s = 2.0
	return w


func _arm(u: Unit, spec: WeaponSpec, rounds := 16) -> void:
	u.weapons.append(spec)
	u.magazines[spec.id] = rounds


func _track(owner: String, truth: Unit, id := "T1", identity := "HOSTILE") -> Track:
	var t := Track.new()
	t.id = id
	t.owner_faction = owner
	t.truth = truth
	t.position = truth.position
	t.position_error_nm = 0.1
	t.status = Track.Status.ACTIVE
	t.domain = "air" if truth.spec.domain == "air" else truth.spec.domain
	t.altitude_m = truth.altitude_m if truth.spec.domain == "air" else -1.0
	t.identity = identity
	t.classification = Track.Classification.CLASS_KNOWN
	return t


## [UnitManager, WeaponManager, TrackManager]. The managers are not in the tree: tests step them.
func _world(units: Array) -> Array:
	var um := UnitManager.new()
	for u: Unit in units:
		um.add_unit(u)
	var tm := TrackManager.new()
	var wm := WeaponManager.new()
	wm.unit_manager = um
	wm.track_manager = tm
	wm.rng.seed = 11
	um.weapon_manager = wm
	return [um, wm, tm]


func _hold(tm: TrackManager, t: Track) -> void:
	var held: Array = tm._tracks.get(t.owner_faction, [])
	held.append(t)
	tm._tracks[t.owner_faction] = held


func _free_world(h: Array) -> void:
	h[1].free()
	h[2].free()
	h[0].free()


## Steps only the weapons, so the geometry stays where the test put it.
func _fly(wm: WeaponManager, seconds: float, from := 0.0) -> float:
	var now := from
	for i in int(seconds / DT):
		now += DT
		wm.tick(DT, now)
	return now


# --- Designation: the round takes what it was fired at ------------------------------------------

func test_a_datalinked_round_takes_the_contact_it_was_fired_at_not_the_first_in_its_cone() -> void:
	var shooter := _unit("BLUE", Vector2.ZERO, "Shooter")
	var spec := _missile("linked", "aam", ["air"])
	spec.midcourse_updates = true
	_arm(shooter, spec)
	var near := _unit("RED", Vector2(0.2, 26.5), "Near", "air")
	var ordered := _unit("RED", Vector2(0.0, 30.0), "Ordered", "air")
	var h := _world([shooter, near, ordered])
	var wm: WeaponManager = h[1]
	var t := _track("BLUE", ordered)
	assert_true(wm.launch(shooter, spec, t, 2, 0.0), str(wm.engagement_check(shooter, spec, t, 0.0).reason))
	var locks := {}
	var now := 0.0
	while now < 90.0:
		now += DT
		wm.tick(DT, now)
		for w: Weapon in wm.in_flight:
			if w.acquired != null:
				locks[w.acquired.callsign] = true
	assert_eq(locks.keys(), ["Ordered"], "every lock was on the contact the rounds were fired at")
	assert_true(near.alive and is_equal_approx(near.health, 100.0), "the aircraft short of the target is untouched")
	assert_true(not ordered.alive, "the ordered aircraft is hit")
	_free_world(h)


func test_a_launch_and_leave_round_takes_the_ship_nearest_its_aim_point() -> void:
	var shooter := _unit("BLUE", Vector2.ZERO, "Shooter")
	var spec := _missile("leave")
	_arm(shooter, spec)
	var short := _unit("RED", Vector2(1.0, 25.0), "Short")
	var ordered := _unit("RED", Vector2(0.0, 30.0), "Ordered")
	var h := _world([shooter, short, ordered])
	var wm: WeaponManager = h[1]
	var t := _track("BLUE", ordered)
	assert_true(wm.launch(shooter, spec, t, 1, 0.0), str(wm.engagement_check(shooter, spec, t, 0.0).reason))
	var w: Weapon = wm.in_flight[0]
	_fly(wm, 90.0)
	assert_true(w.acquired == ordered, "locked %s" % (w.acquired.callsign if w.acquired != null else "nothing"))
	assert_true(is_equal_approx(short.health, 100.0), "the ship short of the aim point is untouched")
	_free_world(h)


func test_no_round_locks_a_unit_of_its_own_side() -> void:
	var shooter := _unit("BLUE", Vector2.ZERO, "Shooter")
	var spec := _missile("heat", "aam", ["air"])
	spec.guidance = "infrared_homing"
	_arm(shooter, spec)
	var wingman := _unit("BLUE", Vector2(0.3, 27.0), "Wingman", "air")
	var bandit := _unit("RED", Vector2(0.0, 30.0), "Bandit", "air")
	var h := _world([shooter, wingman, bandit])
	var wm: WeaponManager = h[1]
	var t := _track("BLUE", bandit)
	assert_true(wm.launch(shooter, spec, t, 1, 0.0), str(wm.engagement_check(shooter, spec, t, 0.0).reason))
	var w: Weapon = wm.in_flight[0]
	_fly(wm, 90.0)
	assert_true(w.acquired == bandit, "locked %s" % (w.acquired.callsign if w.acquired != null else "nothing"))
	assert_true(wingman.alive and is_equal_approx(wingman.health, 100.0), "the wingman is untouched")
	# With the bandit gone, a second round finds only the wingman at its aim point and takes nothing.
	assert_true(not bandit.alive)
	bandit.alive = true
	bandit.health = 100.0
	bandit.position = Vector2(60.0, 0.0)
	assert_true(wm.launch(shooter, spec, t, 1, 100.0), "the plot still shows the contact where it was")
	var second: Weapon = wm.in_flight[0]
	_fly(wm, 200.0, 100.0)
	assert_true(second.phase == Weapon.Phase.DEAD and second.acquired == null, "nothing of its own side is ever acquired: %s" % second.dead_reason)
	assert_true(wingman.alive and is_equal_approx(wingman.health, 100.0))
	_free_world(h)


func test_decoyed_rounds_do_not_turn_on_their_own_side() -> void:
	var shooter := _unit("BLUE", Vector2.ZERO, "Shooter")
	var spec := _missile("leave")
	var own := _unit("BLUE", Vector2(0.0, 31.0), "Own ship")
	var target := _unit("RED", Vector2(0.0, 30.0), "Target")
	var h := _world([shooter, own, target])
	var wm: WeaponManager = h[1]
	for seed_value in 12:
		wm.rng.seed = seed_value
		var w := Weapon.new()
		w.spec = spec
		w.faction = "BLUE"
		w.shooter = shooter
		w.position = Vector2(0.0, 28.0)
		w.heading_deg = Geo.bearing_deg(w.position, target.position)
		w.acquired = target
		w.phase = Weapon.Phase.TERMINAL
		wm.in_flight.append(w)
		assert_true(wm.seduce(w, target) == null, "a seduced round finds nothing but its own side and is spent")
	_free_world(h)


func test_automatic_anti_air_fire_holds_while_an_own_aircraft_is_in_the_basket() -> void:
	var ship := _unit("BLUE", Vector2.ZERO, "Ship")
	ship.sensors.append(_radar())
	var sam := _missile("area", "sam", ["air", "missile"])
	sam.guidance = "inertial_active"
	sam.seeker_range_nm = 4.0
	_arm(ship, sam, 20)
	var drone := _unit("RED", Vector2(0.0, 22.0), "Drone", "air")
	var helo := _unit("BLUE", Vector2(0.0, 19.5), "Helo", "air")
	helo.altitude_m = 150.0
	var h := _world([ship, drone, helo])
	var wm: WeaponManager = h[1]
	var t := _track("BLUE", drone)
	_hold(h[2], t)
	assert_eq(AirDefence.engage_hostile_aircraft(h[0], h[2], wm, 0.0, ["BLUE"]), 0, "own helicopter 2.5 nm short of the contact")
	assert_true(wm.in_flight.is_empty())
	assert_true(bool(wm.engagement_check(ship, sam, t, 0.0).ok), "the commander may still order the shot")
	helo.position = Vector2(8.0, 19.5)
	assert_eq(AirDefence.engage_hostile_aircraft(h[0], h[2], wm, 1.0, ["BLUE"]), 1, "clear of the basket, the ship fires")
	_free_world(h)


# --- Neutrals: the discipline is at launch -------------------------------------------------------

func test_a_shot_is_refused_while_a_held_neutral_lies_in_the_basket() -> void:
	var shooter := _unit("BLUE", Vector2.ZERO, "Shooter")
	var asm := _missile("leave")
	var sam := _missile("area", "sam", ["air"])
	_arm(shooter, asm)
	var warship := _unit("RED", Vector2(0.0, 30.0), "Warship")
	var merchant := _unit("NEUTRAL", Vector2(3.0, 28.0), "Merchant")
	var h := _world([shooter, warship, merchant])
	var wm: WeaponManager = h[1]
	var target := _track("BLUE", warship, "T1")
	var traffic := _track("BLUE", merchant, "T2", "UNKNOWN")
	_hold(h[2], target)
	_hold(h[2], traffic)
	assert_true(bool(Combat.check_engagement(shooter, asm, target).ok), "a contact nobody has identified does not stop the shot")
	traffic.identity = "NEUTRAL"
	assert_eq(str(Combat.check_engagement(shooter, asm, target).reason), "NEUTRAL IN THE LINE OF FIRE", "the check every caller reaches")
	assert_eq(str(wm.engagement_check(shooter, asm, target, 0.0).reason), "NEUTRAL IN THE LINE OF FIRE")
	var refusals: Array[String] = []
	wm.engagement_rejected.connect(func(_u: Unit, _s: WeaponSpec, reason: String) -> void: refusals.append(reason))
	assert_true(not wm.launch(shooter, asm, target, 2, 0.0), "no round leaves")
	assert_eq(refusals, ["NEUTRAL IN THE LINE OF FIRE"] as Array[String])
	assert_eq(shooter.magazine_count(asm.id), 16, "and none is spent")
	traffic.identity = "FRIENDLY"
	assert_true(not bool(Combat.check_engagement(shooter, asm, target).ok), "an ally in the basket is protected the same way")
	# A missile that cannot lock a ship is not held back by one.
	target.domain = "air"
	assert_true(str(Combat.check_engagement(shooter, sam, target, true).reason) != "NEUTRAL IN THE LINE OF FIRE")
	target.domain = "surface"
	traffic.identity = "NEUTRAL"
	traffic.position = Vector2(20.0, 28.0)
	assert_true(bool(Combat.check_engagement(shooter, asm, target).ok), "clear of the basket, the shot is good")
	assert_true(wm.launch(shooter, asm, target, 2, 0.0))
	# A neutral that wanders into the basket stops the rounds still on the launcher.
	traffic.position = Vector2(1.0, 30.0)
	wm.tick(DT, DT)
	assert_eq(wm.committed_rounds(shooter, asm, target, true), 0, "the queued round is withdrawn")
	assert_eq(shooter.magazine_count(asm.id), 15, "and goes back aboard")
	_free_world(h)


func test_the_other_side_holds_fire_on_its_own_picture_of_a_neutral() -> void:
	var raider := _unit("RED", Vector2.ZERO, "Raider")
	var asm := _missile("leave")
	_arm(raider, asm)
	var escort := _unit("BLUE", Vector2(0.0, 30.0), "Escort")
	var merchant := _unit("NEUTRAL", Vector2(1.0, 31.0), "Merchant")
	var h := _world([raider, escort, merchant])
	var target := _track("RED", escort, "R1")
	var traffic := _track("RED", merchant, "R2", "NEUTRAL")
	_hold(h[2], target)
	_hold(h[2], traffic)
	assert_eq(str(Combat.check_engagement(raider, asm, target).reason), "NEUTRAL IN THE LINE OF FIRE")
	# What BLUE holds about the same merchant is BLUE's business.
	traffic.owner_faction = "BLUE"
	h[2]._tracks["RED"] = [target]
	h[2]._tracks["BLUE"] = [traffic]
	assert_true(bool(Combat.check_engagement(raider, asm, target).ok), "the check reads the shooter's own plot, never the truth")
	_free_world(h)


func test_a_torpedo_is_not_fired_past_a_held_neutral() -> void:
	var boat := _unit("BLUE", Vector2.ZERO, "Boat")
	var fish := _missile("fish", "torpedo", ["surface", "subsurface"])
	fish.guidance = "acoustic_homing"
	fish.profile = "subsurface"
	fish.speed_kn = 50.0
	fish.max_range_nm = 20.0
	fish.seeker_range_nm = 2.0
	fish.run_to_enable_nm = 1.0
	_arm(boat, fish)
	var warship := _unit("RED", Vector2(0.0, 10.0), "Warship")
	var merchant := _unit("NEUTRAL", Vector2(1.0, 5.0), "Merchant")
	var h := _world([boat, warship, merchant])
	var target := _track("BLUE", warship, "T1")
	var traffic := _track("BLUE", merchant, "T2", "NEUTRAL")
	_hold(h[2], target)
	_hold(h[2], traffic)
	assert_eq(str(Combat.check_engagement(boat, fish, target).reason), "NEUTRAL IN THE LINE OF FIRE", "a torpedo searches the whole run in")
	traffic.position = Vector2(0.5, -2.5)
	assert_true(bool(Combat.check_engagement(boat, fish, target).ok), "astern of the boat, behind where the seeker comes on, it is not at risk")
	_free_world(h)


func test_standing_attack_in_northern_passage_hits_no_neutral() -> void:
	var sim := Simulation.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	assert_true(sim.load_scenario("res://data/scenarios/northern_passage.json"))
	SimClock.set_paused(true)
	var frigate: Unit = null
	for u: Unit in sim.unit_manager.get_faction_units("BLUE"):
		if u.spec.id == "rnon_ffg_fridtjof_nansen":
			frigate = u
	assert_true(frigate != null, "the escort frigate is in the scenario")
	var neutral_hits: Array[String] = []
	var blue_hits := [0]
	sim.weapon_manager.weapon_impact.connect(func(faction: String, spec: WeaponSpec, target: Unit, hit: bool) -> void:
		if faction != "BLUE":
			return
		if sim.track_manager.neutral_factions.has(target.faction):
			neutral_hits.append("%s on %s at %.0f s (%s)" % [spec.id, target.callsign, SimClock.sim_time, "hit" if hit else "miss"])
		elif hit:
			blue_hits[0] += 1)
	var ordered := false
	while SimClock.sim_time < 1300.0 and frigate != null:
		SimClock.advance(1.0)
		if not ordered and SimClock.sim_time >= 186.0:
			for t: Track in sim.track_manager.tracks_for(frigate):
				if t.identity == "HOSTILE" and t.domain == "surface":
					ordered = sim.unit_manager.issue_order(frigate, Order.attack(t))
					break
	assert_true(ordered, "the frigate was ordered to attack the hostile it holds")
	assert_true(blue_hits[0] > 0, "the attack reached its target")
	assert_eq(neutral_hits, [] as Array[String], "no BLUE round lands on or is rolled against a neutral")
	sim.free()


# --- A salvo outlives its first kill -------------------------------------------------------------

func test_the_rest_of_a_salvo_takes_the_next_ship_when_the_first_round_sinks_the_target() -> void:
	var shooter := _unit("BLUE", Vector2.ZERO, "Shooter")
	var spec := _missile("leave")
	spec.damage = 100.0
	_arm(shooter, spec)
	var first := _unit("RED", Vector2(0.0, 30.0), "First")
	var second := _unit("RED", Vector2(0.3, 31.0), "Second")
	var h := _world([shooter, first, second])
	var wm: WeaponManager = h[1]
	var t := _track("BLUE", first)
	var rounds: Array[Weapon] = []
	wm.weapon_fired.connect(func(w: Weapon) -> void: rounds.append(w))
	assert_true(wm.launch(shooter, spec, t, 4, 0.0), str(wm.engagement_check(shooter, spec, t, 0.0).reason))
	var now := 0.0
	var flying_after_first_kill := -1
	while now < 300.0 and (now < 10.0 or not wm.in_flight.is_empty()):
		now += DT
		wm.tick(DT, now)
		if not first.alive and flying_after_first_kill < 0:
			flying_after_first_kill = wm.in_flight.size()
	assert_eq(rounds.size(), 4)
	assert_true(not first.alive, "the first round sinks the target")
	assert_eq(flying_after_first_kill, 3, "the three rounds behind it are still flying")
	assert_true(not second.alive, "one of them takes the ship beside it")
	var lost := 0
	for w: Weapon in rounds:
		if w.dead_reason == "TARGET LOST":
			lost += 1
			assert_true(w.distance_flown_nm >= spec.max_range_nm - 0.01, "a round is lost only when its range runs out (flew %.1f nm)" % w.distance_flown_nm)
			assert_true(w.position.y > 40.0, "having searched on down its heading, not circled the wreck")
	assert_eq(lost, 2, "the two with nothing left to find")
	_free_world(h)
