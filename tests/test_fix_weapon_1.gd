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
	var merchant := _unit("NEUTRAL", Vector2(1.0, 29.5), "Merchant")
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
	# Inside the seeker's reach but well clear of where the target is: the round passes it over
	# for what is nearer its aim point, so the shot is the commander's to take.
	traffic.position = Vector2(4.0, 27.0)
	assert_true(bool(Combat.check_engagement(shooter, asm, target).ok), "traffic that does not compete with the target does not stop the shot")
	# The older and vaguer the solution, the wider the margin.
	target.position_error_nm = 4.5
	assert_eq(str(Combat.check_engagement(shooter, asm, target).reason), "NEUTRAL IN THE LINE OF FIRE", "a poor plot of the target widens what is at risk")
	target.position_error_nm = 0.1
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
	var merchant := _unit("NEUTRAL", Vector2(0.5, 30.8), "Merchant")
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
	var fired := [0]
	sim.weapon_manager.round_fired.connect(func(u: Unit, _spec: WeaponSpec, _t: Track) -> void:
		if u == frigate:
			fired[0] += 1)
	var ordered := false
	while SimClock.sim_time < 1300.0 and frigate != null:
		SimClock.advance(1.0)
		if not ordered and SimClock.sim_time >= 186.0:
			for t: Track in sim.track_manager.tracks_for(frigate):
				if t.identity == "HOSTILE" and t.domain == "surface":
					ordered = sim.unit_manager.issue_order(frigate, Order.attack(t))
					break
	assert_true(ordered, "the frigate was ordered to attack the hostile it holds")
	# The Gorshkov answers the frigate's missiles with its own and then runs, so whether BLUE's
	# rounds get through is the fight's to decide; that the attack was carried out is not.
	assert_true(fired[0] > 0, "the frigate carried the attack out")
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
			# It searches a few seeker radii past the wreck, not to the end of its fuel.
			assert_true(w.distance_flown_nm <= 30.0 + WeaponManager.SEARCH_ON_SEEKER_RADII * spec.acquisition_radius_nm() + 1.0, "a round gives up a few seeker radii past the wreck (flew %.1f nm)" % w.distance_flown_nm)
			assert_true(w.position.y > 40.0, "having searched on down its heading, not circled the wreck")
	assert_eq(lost, 2, "the two with nothing left to find")
	_free_world(h)


# --- Launchers that do not block each other ------------------------------------------------------

## A real Flight IIA destroyer with an anti-ship missile inbound from 18 nm. Returns
## [UnitManager, WeaponManager, destroyer, inbound round].
func _destroyer_under_attack() -> Array:
	Terrain.clear()
	var um := UnitManager.new()
	ScenarioLoader.populate(um, {"units": [
		{"platform": "usn_ddg_arleigh_burke_iia", "callsign": "Destroyer", "faction": "BLUE", "position_nm": [0, 0], "heading_deg": 0.0, "speed_kn": 15.0},
		{"platform": "rfn_cg_slava", "callsign": "Raider", "faction": "RED", "position_nm": [0, 18], "heading_deg": 180.0, "speed_kn": 0.0},
		{"platform": "rfn_ssk_kilo", "callsign": "Boat", "faction": "RED", "position_nm": [6, -5], "heading_deg": 0.0, "speed_kn": 4.0, "depth_m": 100.0},
		{"platform": "shore_air_station", "callsign": "Field", "faction": "RED", "position_nm": [-120, 60]},
	]})
	var wm := WeaponManager.new()
	wm.unit_manager = um
	wm.rng.seed = 5
	var raider: Unit = um.units[1]
	var harpoon := DataDB.weapon("rgm_84_harpoon")
	raider.weapons.append(harpoon)
	raider.magazines[harpoon.id] = 4
	var red_track := _track("RED", um.units[0], "R1")
	assert_true(wm.launch(raider, harpoon, red_track, 1, 0.0), "the raider's missile is on its way")
	return [um, wm, um.units[0], wm.in_flight[0]]


## Steps the engagement, offering the destroyer's SM-2 and ESSM the inbound round every tick as
## the defence cycle would. Returns the time the first interceptor left, or -1.
func _first_interceptor_time(um: UnitManager, wm: WeaponManager, ship: Unit, threat: Weapon, seconds: float) -> float:
	var now := 0.0
	var first := -1.0
	while now < seconds:
		now += DT
		um.tick(DT)
		wm.tick(DT, now)
		if first < 0.0 and threat.phase != Weapon.Phase.DEAD:
			for id: String in ["sm2_family", "essm_family"]:
				if wm.launch_interceptor(ship, ship.get_weapon(id), threat, 1, now) > 0:
					first = now
					break
	return first


func test_a_queued_strike_salvo_does_not_hold_up_the_ships_own_missiles() -> void:
	var c := _destroyer_under_attack()
	var um: UnitManager = c[0]
	var wm: WeaponManager = c[1]
	var ship: Unit = c[2]
	var tomahawk := ship.get_weapon("tomahawk_block_v")
	var field := _track("BLUE", um.units[3], "B1")
	field.domain = "land"
	var fired: Array[float] = []
	wm.weapon_fired.connect(func(w: Weapon) -> void:
		if w.spec == tomahawk:
			fired.append(wm.now_s))
	assert_true(wm.launch(ship, tomahawk, field, 8, 0.0), str(wm.engagement_check(ship, tomahawk, field, 0.0).reason))
	assert_eq(wm.committed_rounds(ship, tomahawk, field, true), 7, "seven rounds wait behind the first")
	var first := _first_interceptor_time(um, wm, ship, c[3], 60.0)
	assert_true(first > 0.0 and first <= 2.0, "the first interceptor leaves within two seconds, not behind the salvo (left at %.2f s)" % first)
	assert_eq(fired.size(), 8, "every strike round still leaves: pushed back, not dropped")
	for i in range(1, fired.size()):
		assert_true(fired[i] - fired[i - 1] >= tomahawk.launch_interval_s - 0.01, "the salvo keeps its own spacing (%.2f s)" % (fired[i] - fired[i - 1]))
	wm.free()
	um.free()


func test_one_anti_submarine_rocket_does_not_hold_up_the_ships_own_missiles() -> void:
	var c := _destroyer_under_attack()
	var um: UnitManager = c[0]
	var wm: WeaponManager = c[1]
	var ship: Unit = c[2]
	var rocket := ship.get_weapon("rgm_139_vla")
	var boat := _track("BLUE", um.units[2], "B1")
	assert_true(wm.launch(ship, rocket, boat, 1, 0.0), str(wm.engagement_check(ship, rocket, boat, 0.0).reason))
	assert_true(wm.ready_in_s(ship, rocket, 0.0) >= rocket.launch_interval_s - 0.01, "the next rocket waits its own interval")
	var first := _first_interceptor_time(um, wm, ship, c[3], 30.0)
	assert_true(first > 0.0 and first <= 2.0, "the first interceptor leaves within two seconds (left at %.2f s)" % first)
	wm.free()
	um.free()


func test_an_interceptor_pushes_queued_strike_rounds_back_and_a_mechanical_launcher_stays_busy() -> void:
	var ship := _unit("BLUE", Vector2.ZERO, "Ship")
	ship.spec.vls_cells = 32
	ship.sensors.append(_radar())
	var strike := _missile("strike")
	strike.vls_pack = 1
	strike.launch_interval_s = 5.0
	var sam := _missile("sam", "sam", ["missile", "air"])
	sam.guidance = "inertial_active"
	sam.vls_pack = 1
	sam.launch_interval_s = 2.0
	sam.min_range_nm = 0.05
	_arm(ship, strike)
	_arm(ship, sam)
	var enemy := _unit("RED", Vector2(0.0, 40.0), "Enemy")
	var h := _world([ship, enemy])
	var wm: WeaponManager = h[1]
	var t := _track("BLUE", enemy)
	var inbound := Weapon.new()
	inbound.id = 900
	inbound.spec = _missile("inbound")
	inbound.faction = "RED"
	inbound.position = Vector2(0.0, 15.0)
	inbound.heading_deg = 180.0
	inbound.acquired = ship
	inbound.phase = Weapon.Phase.TERMINAL
	assert_true(wm.launch(ship, strike, t, 3, 0.0))
	# The second strike round is due at 5 s. An interceptor that leaves just before it goes first.
	assert_eq(wm.launch_interceptor(ship, sam, inbound, 1, 0.5), 0, "the cell group is still sequencing the strike round")
	assert_eq(wm.launch_interceptor(ship, sam, inbound, 1, 4.5), 1, "then it is free, with strike rounds still queued")
	wm.now_s = 5.0
	var queue_times: Array[float] = []
	for p: Dictionary in wm._pending:
		queue_times.append(float(p.time))
	assert_true(queue_times[0] >= 5.5 - 0.001, "the strike round that was due is pushed back behind the interceptor (now %.2f s)" % queue_times[0])
	assert_eq(wm.committed_rounds(ship, strike, t, true), 2, "and stays queued")
	assert_eq(wm.launch_interceptor(ship, sam, inbound, 1, 5.5), 0, "the same missile keeps its own salvo spacing")
	assert_eq(wm.launch_interceptor(ship, sam, inbound, 1, 6.5), 1)
	# A single-arm launcher is a different thing: whatever it fired, it is reloading.
	var frigate := _unit("BLUE", Vector2(0.0, 1.0), "Frigate")
	frigate.sensors.append(_radar())
	frigate.spec.launcher_groups = {"strike": "Arm", "sam": "Arm"}
	frigate.spec.launcher_service_s = {"Arm": 8.0}
	_arm(frigate, strike)
	_arm(frigate, sam)
	h[0].add_unit(frigate)
	assert_true(wm.launch(frigate, strike, t, 1, 10.0))
	assert_eq(wm.launch_interceptor(frigate, sam, inbound, 1, 12.0), 0, "the arm is still reloading")
	assert_eq(wm.launch_interceptor(frigate, sam, inbound, 1, 18.0), 1)
	_free_world(h)


# --- Ballistic missiles --------------------------------------------------------------------------

## Fires one real ballistic missile from a plain launcher at a real destroyer `range_nm` away,
## with the plot `offset` from the ship. Returns [UnitManager, WeaponManager, round, destroyer].
func _ballistic_shot(id: String, range_nm: float, offset: Vector2) -> Array:
	Terrain.clear()
	var spec := DataDB.weapon(id)
	var shooter := _unit("BLUE", Vector2.ZERO, "Battery")
	_arm(shooter, spec, 4)
	var um := UnitManager.new()
	um.add_unit(shooter)
	ScenarioLoader.populate(um, {"units": [{"platform": "usn_ddg_arleigh_burke_iia", "callsign": "Destroyer", "faction": "RED", "position_nm": [0, range_nm], "heading_deg": 90.0, "speed_kn": 0.0}]})
	var target: Unit = um.units[1]
	var wm := WeaponManager.new()
	wm.unit_manager = um
	wm.rng.seed = 11
	var t := _track("BLUE", target)
	t.position = target.position + offset
	assert_true(wm.launch(shooter, spec, t, 1, 0.0), "%s: %s" % [id, str(wm.engagement_check(shooter, spec, t, 0.0).reason)])
	return [um, wm, wm.in_flight[0] if not wm.in_flight.is_empty() else null, target]


func test_a_ballistic_missile_that_misses_does_not_circle_its_target() -> void:
	for id: String in ["pla_df21d", "pla_yj21", "irn_khalij_fars"]:
		var spec := DataDB.weapon(id)
		var range_nm := spec.max_range_nm * 0.6
		var c := _ballistic_shot(id, range_nm, Vector2(2.0, 0.0))
		var wm: WeaponManager = c[1]
		var w: Weapon = c[2]
		if w != null:
			var turned := 0.0
			var last := w.heading_deg
			var now := 0.0
			while w.phase != Weapon.Phase.DEAD and now < 3000.0:
				now += DT
				wm.tick(DT, now)
				turned += absf(Geo.heading_delta(last, w.heading_deg))
				last = w.heading_deg
			assert_true(w.dead_reason in ["MISS", "HIT"], "%s ended %s" % [id, w.dead_reason])
			assert_true(turned < 180.0, "%s turned %.0f degrees" % [id, turned])
			assert_true(w.distance_flown_nm < range_nm + 10.0, "%s flew %.0f nm for a %.0f nm shot" % [id, w.distance_flown_nm, range_nm])
		wm.free()
		c[0].free()


func test_a_ballistic_missile_comes_down_through_the_interceptors_height_bands() -> void:
	var exo := DataDB.weapon("sm3_family")
	var upper := DataDB.weapon("sm6_family")
	for range_nm: float in [480.0, 100.0]:
		var c := _ballistic_shot("pla_df21d", range_nm, Vector2.ZERO)
		var wm: WeaponManager = c[1]
		var w: Weapon = c[2]
		var top := w.spec.altitude_m
		assert_near(w.flight_altitude_m(), top, 1.0, "it leaves at its cruise height")
		assert_true(AirDefence._can_intercept(exo, w) and not AirDefence._can_intercept(upper, w), "outside the atmosphere it is the exoatmospheric interceptor's alone")
		var now := 0.0
		var upper_from_nm := -1.0
		var exo_below_floor := false
		var checked_last_ten := false
		while w.phase != Weapon.Phase.DEAD and now < 3000.0:
			now += DT
			wm.tick(DT, now)
			if w.phase == Weapon.Phase.DEAD:
				break
			var height := w.flight_altitude_m()
			if height < exo.intercept_min_altitude_m and AirDefence._can_intercept(exo, w):
				exo_below_floor = true
			if upper_from_nm < 0.0 and AirDefence._can_intercept(upper, w):
				upper_from_nm = w.distance_to_go_nm()
			if w.distance_to_go_nm() <= 10.0 and w.distance_to_go_nm() > 1.0:
				checked_last_ten = true
				assert_true(AirDefence._can_intercept(upper, w), "in its last ten miles the upper-atmosphere interceptor can engage it (%.0f m at %.1f nm)" % [height, w.distance_to_go_nm()])
				assert_true(not AirDefence._can_intercept(exo, w), "and the exoatmospheric one cannot")
		assert_true(checked_last_ten, "the round was watched through its dive")
		assert_true(not exo_below_floor, "the exoatmospheric interceptor never engages below its floor")
		assert_true(upper_from_nm >= 10.0, "the dive opens the upper band with at least ten miles to run (opened at %.1f nm)" % upper_from_nm)
		wm.free()
		c[0].free()
	# A round that never leaves the atmosphere is never the exoatmospheric interceptor's.
	var low := _ballistic_shot("irn_khalij_fars", 114.0, Vector2.ZERO)
	assert_true(not AirDefence._can_intercept(exo, low[2]) and AirDefence._can_intercept(upper, low[2]))
	low[1].free()
	low[0].free()


# --- Interceptors coast before they are lost -----------------------------------------------------

func _sam_case() -> Array:
	Terrain.clear()
	var ship := _unit("BLUE", Vector2.ZERO, "Ship")
	ship.sensors.append(_radar())
	var sam := _missile("directed", "sam", ["missile"])
	sam.guidance = "fire_control_directed"
	sam.speed_kn = 2400.0
	sam.turn_rate_deg_s = 120.0
	sam.seeker_range_nm = 4.0
	sam.min_range_nm = 0.05
	_arm(ship, sam)
	var h := _world([ship])
	var inbound := Weapon.new()
	inbound.id = 900
	inbound.spec = _missile("inbound")
	inbound.spec.speed_kn = 480.0
	inbound.spec.altitude_m = 10.0
	inbound.faction = "RED"
	inbound.position = Vector2(0.0, 14.0)
	inbound.heading_deg = 180.0
	inbound.acquired = ship
	inbound.phase = Weapon.Phase.TERMINAL
	(h[1] as WeaponManager).in_flight.append(inbound)
	return [h, ship, sam, inbound]


func test_an_interceptor_survives_one_missed_look_from_its_illuminator() -> void:
	var c := _sam_case()
	var h: Array = c[0]
	var wm: WeaponManager = h[1]
	var ship: Unit = c[1]
	var inbound: Weapon = c[3]
	assert_eq(wm.launch_interceptor(ship, c[2], inbound, 1, 0.0), 1)
	var sam: Weapon = wm.in_flight.back()
	wm.tick(DT, 0.25)
	ship.radar_on = false
	wm.tick(DT, 0.5)
	assert_true(sam.phase != Weapon.Phase.DEAD, "a quarter of a second without the beam does not destroy the round")
	ship.radar_on = true
	_fly(wm, 30.0, 0.5)
	assert_eq(sam.dead_reason, "INTERCEPT", "guided again, it goes on to its intercept")
	assert_eq(inbound.dead_reason, "INTERCEPTED")
	_free_world(h)


func test_a_semi_active_round_needs_the_beam_only_for_its_endgame() -> void:
	var c := _sam_case()
	var h: Array = c[0]
	var wm: WeaponManager = h[1]
	var ship: Unit = c[1]
	var inbound: Weapon = c[3]
	assert_eq(wm.launch_interceptor(ship, c[2], inbound, 1, 0.0), 1)
	var sam: Weapon = wm.in_flight.back()
	# The inbound round drops under the radar horizon for longer than any coast, while the
	# interceptor is still on its way out to it.
	inbound.position = Vector2(0.0, 40.0)
	assert_true(not wm.guidance_available(ship, c[2], inbound), "the illuminator cannot see it there")
	var now := _fly(wm, WeaponManager.INTERCEPT_COAST_S + 2.0)
	assert_true(sam.phase != Weapon.Phase.DEAD, "on the way out the round flies its last solution")
	inbound.position = Vector2(0.0, 12.0)
	_fly(wm, 30.0, now)
	assert_eq(sam.dead_reason, "INTERCEPT", "with the beam back for the endgame it homes")
	_free_world(h)


func test_an_interceptor_without_guidance_in_its_endgame_is_lost_after_a_short_coast() -> void:
	var c := _sam_case()
	var h: Array = c[0]
	var wm: WeaponManager = h[1]
	var ship: Unit = c[1]
	var inbound: Weapon = c[3]
	inbound.position = Vector2(0.0, 3.0)
	assert_eq(wm.launch_interceptor(ship, c[2], inbound, 1, 0.0), 1)
	var sam: Weapon = wm.in_flight.back()
	# Hold the inbound round still and out of the interceptor's path, so only guidance decides.
	inbound.spec.speed_kn = 0.0
	inbound.position = Vector2(3.0, 0.0)
	ship.radar_on = false
	var now := _fly(wm, WeaponManager.INTERCEPT_COAST_S - 0.5)
	assert_true(sam.phase != Weapon.Phase.DEAD, "it coasts first")
	_fly(wm, 1.0, now)
	assert_eq(sam.dead_reason, "GUIDANCE LOST")
	_free_world(h)


# --- Shells and gunnery --------------------------------------------------------------------------

func test_nothing_shoots_at_shells_and_chaff_ignores_them() -> void:
	var shell_spec := DataDB.weapon("oto_76mm_gun")
	var shell := Weapon.new()
	shell.spec = shell_spec
	assert_eq(shell.threat_class(), "shell")
	for spec: WeaponSpec in DataDB.all_weapons():
		assert_true(not AirDefence._can_intercept(spec, shell), "%s would engage a shell" % spec.id)
	# A ship with a missile and a gun layer and chaff aboard, under fire from a gun.
	var ship := _unit("RED", Vector2.ZERO, "Ship")
	ship.sensors.append(_radar())
	ship.decoys = 8
	ship.auto_countermeasures = true
	var sam := _missile("point", "sam", ["missile"])
	sam.guidance = "inertial_active"
	sam.min_range_nm = 0.05
	var gun := _missile("close", "ciws", ["missile"])
	gun.max_range_nm = 2.0
	gun.min_range_nm = 0.05
	_arm(ship, sam)
	_arm(ship, gun, 400)
	var h := _world([ship])
	var wm: WeaponManager = h[1]
	var threats := ThreatManager.new()
	shell.id = 901
	shell.faction = "BLUE"
	shell.position = Vector2(0.0, 2.0)
	shell.heading_deg = 180.0
	shell.acquired = ship
	shell.phase = Weapon.Phase.TERMINAL
	wm.in_flight.append(shell)
	threats.begin_cycle()
	threats.mark_detected("RED", shell, 0.0)
	assert_eq(AirDefence.run_cycle(h[0], threats, wm, 0.0), 0, "no interceptor leaves for a shell")
	DefensiveResponse.run_cycle(h[0], threats, wm)
	assert_eq(ship.decoys, 8, "and no chaff is spent on one")
	assert_eq(ship.magazine_count(sam.id), 16)
	assert_eq(ship.magazine_count(gun.id), 400)
	# The same ship still answers a missile.
	var missile := Weapon.new()
	missile.id = 902
	missile.spec = _missile("inbound")
	missile.faction = "BLUE"
	missile.position = Vector2(0.0, 10.0)
	missile.heading_deg = 180.0
	missile.acquired = ship
	missile.phase = Weapon.Phase.TERMINAL
	wm.in_flight.append(missile)
	threats.begin_cycle()
	threats.mark_detected("RED", missile, 0.0)
	assert_true(AirDefence.run_cycle(h[0], threats, wm, 0.0) > 0, "a missile is still engaged")
	threats.free()
	_free_world(h)


func test_gunfire_is_less_accurate_at_range_and_against_a_fast_target() -> void:
	var gun := DataDB.weapon("mk45_mod4_gun")
	var boat := _unit("RED", Vector2.ZERO, "Boat")
	boat.spec.signature_factor = 0.3
	boat.spec.max_speed_kn = 55.0
	boat.speed_kn = 52.0
	var at_limit := Combat.hit_probability(gun, boat, gun.max_range_nm)
	assert_true(at_limit < 0.2, "at maximum range against a fast boat the chance is under one in five (%.2f)" % at_limit)
	assert_true(at_limit > 0.0)
	var closer := Combat.hit_probability(gun, boat, 2.0)
	assert_true(closer > at_limit * 1.5, "closing the range helps (%.2f against %.2f)" % [closer, at_limit])
	boat.speed_kn = 0.0
	var stopped := Combat.hit_probability(gun, boat, 2.0)
	assert_true(stopped > closer * 1.5, "and so does a target that is not moving (%.2f against %.2f)" % [stopped, closer])
	assert_true(Combat.hit_probability(gun, boat, 0.0) <= gun.base_pk, "never better than the gun's rated figure")
	for spec: WeaponSpec in DataDB.all_weapons():
		if spec.is_gun():
			boat.speed_kn = 45.0
			var pk := Combat.hit_probability(spec, boat, spec.max_range_nm)
			assert_true(pk < 0.2, "%s at its limit against a fast boat: %.2f" % [spec.id, pk])


func test_a_gun_salvo_at_long_range_misses_as_often_as_it_hits() -> void:
	var ship := _unit("BLUE", Vector2.ZERO, "Ship")
	var gun := _missile("gun", "gun", ["surface"])
	gun.guidance = "unguided"
	gun.profile = "direct"
	gun.seeker_range_nm = 0.0
	gun.max_range_nm = 10.0
	gun.min_range_nm = 0.3
	gun.speed_kn = 1600.0
	gun.damage = 0.5
	gun.base_pk = 1.0
	gun.launch_interval_s = 1.0
	_arm(ship, gun, 60)
	var target := _unit("RED", Vector2(0.0, 9.8), "Target", "surface", 1000.0)
	target.spec.signature_factor = 1.0
	var h := _world([ship, target])
	var wm: WeaponManager = h[1]
	var t := _track("BLUE", target)
	var results := {"hit": 0, "miss": 0}
	wm.weapon_impact.connect(func(_f: String, _s: WeaponSpec, _u: Unit, hit: bool) -> void:
		results["hit" if hit else "miss"] += 1)
	assert_true(wm.launch(ship, gun, t, 40, 0.0), str(wm.engagement_check(ship, gun, t, 0.0).reason))
	_fly(wm, 90.0)
	assert_eq(int(results.hit) + int(results.miss), 40, "every shell arrives")
	assert_true(int(results.hit) >= 10 and int(results.hit) <= 30, "about half hit at the limit of the gun's reach (%d of 40)" % int(results.hit))
	_free_world(h)
