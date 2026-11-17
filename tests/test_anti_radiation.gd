extends TestCase
## An anti-radiation missile homes on a radar's own transmission. These pin the bargain that makes
## emission control a decision: it needs only a bearing to a radar that is on, and it is beaten by
## switching that radar off, which is its own kind of success.


func _radar() -> SensorSpec:
	var s := SensorSpec.new()
	s.kind = "radar"
	s.range_surface_nm = 40.0
	s.range_air_nm = 200.0
	s.antenna_height_m = 20.0
	return s


func _esm() -> SensorSpec:
	var s := SensorSpec.new()
	s.kind = "esm"
	s.esm_gain = 2.0
	s.antenna_height_m = 20.0
	return s


func _emitter(faction := "RED", position := Vector2(0, 20), speed := 0.0) -> Unit:
	var u := Unit.new()
	u.spec = PlatformSpec.new()
	u.spec.max_speed_kn = 30.0
	u.spec.fire_control_channels = 4
	u.faction = faction
	u.callsign = "%s-RADAR" % faction
	u.position = position
	u.speed_kn = speed
	u.ordered_speed_kn = speed
	u.health = 100.0
	u.sensors.append(_radar())
	return u


func _arm_spec(pk := 1.0) -> WeaponSpec:
	var s := WeaponSpec.new()
	s.id = "test_arm"
	s.type = "asm"
	s.guidance = "passive_radar_homing"
	s.profile = "high"
	s.target_types = PackedStringArray(["surface", "land"])
	s.max_range_nm = 60.0
	s.min_range_nm = 1.0
	s.speed_kn = 1200.0
	s.turn_rate_deg_s = 20.0
	s.seeker_range_nm = 25.0
	s.seeker_half_angle_deg = 45.0
	s.base_pk = pk
	s.damage = 15.0
	s.altitude_m = 9000.0
	return s


func _round(aim: Vector2, pk := 1.0) -> Weapon:
	var w := Weapon.new()
	w.id = 5
	w.spec = _arm_spec(pk)
	w.faction = "BLUE"
	w.aim_point = aim
	return w


func _manager(units: Array, w: Weapon, seed_value := 7) -> WeaponManager:
	Terrain.clear()
	Detection.set_environment({})
	var wm := WeaponManager.new()
	wm.rng.seed = seed_value
	wm.unit_manager = UnitManager.new()
	wm.track_manager = TrackManager.new()
	for u: Unit in units:
		wm.unit_manager.add_unit(u)
	if w != null:
		wm.in_flight.append(w)
	return wm


func _fly(wm: WeaponManager, w: Weapon, seconds := 400.0, each: Callable = Callable()) -> void:
	var t := 0.0
	while t < seconds and w.phase != Weapon.Phase.DEAD:
		t += 0.25
		if each.is_valid():
			each.call(t)
		wm.tick(0.25, t)


func _cleanup(wm: WeaponManager) -> void:
	wm.clear()
	wm.track_manager.free()
	wm.unit_manager.free()
	wm.free()


func test_it_rides_a_radar_in_and_wrecks_the_antennas() -> void:
	var ship := _emitter()
	# Aimed well short and off to one side: a bearing, not a position.
	var w := _round(Vector2(2, 8))
	var wm := _manager([ship], w)
	_fly(wm, w)
	assert_eq(w.dead_reason, "HIT", "homes on the transmission from wherever the bearing put it")
	assert_near(ship.health, 85.0, 0.01, "a small warhead")
	assert_true(ship.component("sensors") <= 0.26, "but the sensors are wrecked: %.2f" % ship.component("sensors"))
	_cleanup(wm)


func test_a_silent_ship_gives_it_nothing_to_find() -> void:
	var ship := _emitter()
	ship.radar_on = false
	var w := _round(ship.position)
	var wm := _manager([ship], w)
	_fly(wm, w)
	assert_eq(w.dead_reason, "NO ACQUISITION", "it flew through the ship's own position and heard nothing")
	assert_near(ship.health, 100.0, 0.01, "untouched")
	assert_true(w.distance_flown_nm >= w.spec.max_range_nm - 0.01, "and searched on down the bearing until its fuel ran out")
	_cleanup(wm)


func test_an_ordinary_missile_still_finds_a_silent_ship() -> void:
	var ship := _emitter()
	ship.radar_on = false
	var w := _round(ship.position)
	w.spec.guidance = "inertial_active"
	var wm := _manager([ship], w)
	_fly(wm, w)
	assert_eq(w.dead_reason, "HIT", "the emitter rule is the anti-radiation seeker's alone")
	_cleanup(wm)


func test_shutting_down_leaves_it_a_memory_and_a_poorer_chance() -> void:
	var hits := 0
	for trial in 200:
		var site := _emitter()
		var w := _round(site.position)
		var wm := _manager([site], w, 100 + trial)
		_fly(wm, w, 400.0, func(_t: float) -> void:
			if w.phase == Weapon.Phase.TERMINAL and w.position.distance_to(site.position) < 10.0:
				site.radar_on = false)
		if w.dead_reason == "HIT":
			hits += 1
		else:
			assert_eq(w.dead_reason, "MISS", "it still reaches the spot")
		_cleanup(wm)
	assert_true(hits > 55 and hits < 105, "about %d%% of a certain hit against a stationary emitter that went quiet: %d of 200" % [int(WeaponManager.ARM_MEMORY_PK * 100.0), hits])


func test_a_ship_that_goes_quiet_and_keeps_moving_is_not_where_it_remembers() -> void:
	var ship := _emitter("RED", Vector2(0, 40), 30.0)
	ship.heading_deg = 90.0
	ship.ordered_heading_deg = 90.0
	var w := _round(ship.position)
	var wm := _manager([ship], w)
	_fly(wm, w, 400.0, func(_t: float) -> void:
		Movement.step(ship, 0.25)
		if w.phase == Weapon.Phase.TERMINAL and w.position.distance_to(ship.position) < 20.0:
			ship.radar_on = false)
	assert_eq(w.dead_reason, "TARGET LOST", "a minute at thirty knots is half a mile from the last transmission")
	assert_near(ship.health, 100.0, 0.01, "untouched")
	_cleanup(wm)


func test_switching_back_on_gives_it_the_ship_again() -> void:
	var ship := _emitter("RED", Vector2(0, 40), 30.0)
	ship.heading_deg = 90.0
	ship.ordered_heading_deg = 90.0
	var w := _round(ship.position)
	var wm := _manager([ship], w)
	_fly(wm, w, 400.0, func(_t: float) -> void:
		Movement.step(ship, 0.25)
		var d := w.position.distance_to(ship.position)
		if w.phase == Weapon.Phase.TERMINAL:
			ship.radar_on = d >= 20.0 or d < 8.0)
	assert_eq(w.dead_reason, "HIT", "a radar that comes back on is a target again")
	_cleanup(wm)


func test_it_ignores_its_own_side_and_neutrals() -> void:
	var friend := _emitter("BLUE", Vector2(0, 10))
	var merchant := _emitter("CIV", Vector2(1, 15))
	var enemy := _emitter("RED", Vector2(0, 30))
	var w := _round(enemy.position)
	var wm := _manager([friend, merchant, enemy], w)
	wm.track_manager.neutral_factions = PackedStringArray(["CIV"])
	_fly(wm, w)
	assert_eq(w.dead_reason, "HIT", "reaches the enemy radar")
	assert_near(friend.health, 100.0, 0.01, "past a friendly radar on the same line")
	assert_near(merchant.health, 100.0, 0.01, "and a neutral's")
	assert_near(enemy.health, 85.0, 0.01, "to the one it was fired at")
	_cleanup(wm)


func _shooter(spec: WeaponSpec) -> Unit:
	var u := _emitter("BLUE", Vector2.ZERO)
	u.sensors.append(_esm())
	u.weapons.append(spec)
	u.magazines[spec.id] = 2
	return u


func test_it_can_be_fired_down_an_esm_bearing_and_nothing_else_can() -> void:
	var arm := _arm_spec()
	var shooter := _shooter(arm)
	var asm := _arm_spec()
	asm.id = "test_asm"
	asm.guidance = "inertial_active"
	shooter.weapons.append(asm)
	shooter.magazines[asm.id] = 2
	var t := Track.new()
	t.owner_faction = "BLUE"
	t.position = Vector2(0, 40)
	t.bearing_only = true
	t.tma_quality = 0.1
	t.source = "esm"
	t.last_seen_time = 100.0
	t.last_esm_time = 100.0
	assert_true(t.radiating(), "heard transmitting")
	assert_true(bool(Combat.check_engagement(shooter, arm, t)["ok"]), "an anti-radiation shot down a bearing: %s" % Combat.check_engagement(shooter, arm, t)["reason"])
	t.domain = "surface"
	assert_eq(Combat.check_engagement(shooter, asm, t)["reason"], "BEARING ONLY / NO RANGE SOLUTION", "an ordinary missile still needs a range")
	# Held by radar now, and no longer heard: a fix, but nothing to home on.
	t.bearing_only = false
	t.tma_quality = 1.0
	t.last_seen_time = 400.0
	assert_true(not t.radiating(), "silent for five minutes")
	assert_eq(Combat.check_engagement(shooter, arm, t)["reason"], "CONTACT NOT RADIATING", "refused, with the reason")
	assert_true(not shooter.weapons_for_track(t).has(arm), "and not offered as a weapon for the contact")
	t.last_esm_time = 390.0
	assert_true(shooter.weapons_for_track(t).has(arm), "offered again once it is heard")
	t.domain = "air"
	assert_true(not Combat.suits_track(arm, t), "never at an aircraft")


func test_the_plot_learns_a_contact_radiates_from_its_own_esm_only() -> void:
	var tm := TrackManager.new()
	var listener := _shooter(_arm_spec())
	var target := _emitter()
	tm.observe("BLUE", target, target.position, 0.8, 1.0, 10.0, 1.0, 20.0)
	var t := tm.find_track("BLUE", target)
	assert_true(not t.radiating(), "a radar plot says nothing about the contact's own emissions")
	var c := SensorContact.make(target, target.position, 5.0, 0.5, 1.0, 20.0, "esm", listener)
	c.bearing_only = true
	tm.observe_contact("BLUE", c, 11.0, 1.0)
	assert_true(t.radiating(), "an intercept does")
	target.radar_on = false
	tm.observe("BLUE", target, target.position, 0.8, 1.0, 11.0 + Track.EMITTER_MEMORY_S + 5.0, 1.0, 20.0)
	assert_true(not t.radiating(), "and the knowledge lapses when the intercepts stop, whatever the truth")
	tm.free()


func test_the_catalogue_carries_three_and_aircraft_to_fire_them() -> void:
	var carried := {}
	for p: PlatformSpec in DataDB.all_platforms():
		for wid: String in p.weapon_loadout:
			var w := DataDB.weapon(wid)
			if w != null and w.is_anti_radiation():
				carried[wid] = p.id
				assert_eq(p.domain, "air", "%s is air-launched" % wid)
	assert_eq(carried.size(), 3, "three anti-radiation weapons in service: %s" % str(carried))
	for w: WeaponSpec in DataDB.all_weapons():
		if not w.is_anti_radiation():
			continue
		assert_true(carried.has(w.id), "%s is carried by something" % w.id)
		assert_eq(w.seeker_band(), "none", "%s: chaff gives a passive seeker nothing" % w.id)
		assert_true(w.seeker_range_nm >= 20.0 and w.damage < 25.0, "%s: a long-eared seeker and a small warhead" % w.id)
		assert_true(w.source_status.contains("GAMEPLAY_ESTIMATE"), "%s labels its estimates" % w.id)


class Harness:
	extends RefCounted
	var um: UnitManager
	var tm: TrackManager
	var threats: ThreatManager
	var wm: WeaponManager
	var ai: AIController

	func free_all() -> void:
		ai.free()
		wm.free()
		threats.free()
		tm.free()
		um.free()


func _harness(units: Array) -> Harness:
	Terrain.clear()
	Detection.set_environment({})
	var h := Harness.new()
	h.um = UnitManager.new()
	for u: Unit in units:
		h.um.add_unit(u)
	h.tm = TrackManager.new()
	h.threats = ThreatManager.new()
	h.wm = WeaponManager.new()
	h.wm.unit_manager = h.um
	h.wm.track_manager = h.tm
	h.ai = AIController.new()
	h.ai.faction = "RED"
	h.ai.unit_manager = h.um
	h.ai.track_manager = h.tm
	h.ai.threat_manager = h.threats
	h.ai.weapon_manager = h.wm
	return h


func test_an_unarmed_radar_shuts_down_under_one_and_an_armed_ship_fights_it() -> void:
	var site := _emitter("RED", Vector2(0, 20))
	site.sensors.append(_esm())
	var w := _round(site.position)
	w.position = Vector2(0, 0)
	w.heading_deg = 0.0
	var h := _harness([site])
	h.wm.in_flight.append(w)
	h.threats.mark_detected("RED", w, 1.0, site)
	h.ai._manage_emissions(site, true)
	assert_true(not site.radar_on, "a radar with nothing to shoot back with goes silent under an anti-radiation round")
	# The same radar with a SAM aboard keeps its picture.
	site.radar_on = true
	var sam := WeaponSpec.new()
	sam.id = "test_sam"
	sam.type = "sam"
	sam.target_types = PackedStringArray(["air"])
	sam.max_range_nm = 20.0
	site.weapons.append(sam)
	site.magazines[sam.id] = 4
	h.ai._manage_emissions(site, true)
	assert_true(site.radar_on, "a ship that can engage the round keeps radiating")
	# And an ordinary missile is no reason to go blind.
	site.weapons.clear()
	w.spec.guidance = "inertial_active"
	h.ai._manage_emissions(site, true)
	assert_true(site.radar_on, "chaff and guns want the radar on against an ordinary missile")
	# One flying away is no threat either.
	w.spec.guidance = "passive_radar_homing"
	w.heading_deg = 180.0
	h.ai._manage_emissions(site, true)
	assert_true(site.radar_on, "a round going the other way is not coming for this radar")
	h.wm.in_flight.clear()
	h.free_all()
