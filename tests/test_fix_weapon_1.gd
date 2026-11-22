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
	var rounds: Array[Weapon] = []
	wm.weapon_fired.connect(func(w: Weapon) -> void: rounds.append(w))
	rounds.append(wm.in_flight[0])
	_fly(wm, 90.0)
	assert_eq(rounds.size(), 2)
	for w: Weapon in rounds:
		assert_true(w.acquired == ordered, "round %d locked %s" % [w.id, w.acquired.callsign if w.acquired != null else "nothing"])
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
