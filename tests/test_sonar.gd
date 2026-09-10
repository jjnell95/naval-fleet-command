extends TestCase
## Sonar is a second, independent way of being wrong about where the enemy is. These tests pin
## the parts that matter: noise rises with speed, quiet boats are nearly invisible, passive
## contact gives a bearing rather than a position, and a torpedo is not a missile.

const DT := 0.25


func _boat_spec(signature: float, max_speed := 20.0, max_depth := 240.0) -> PlatformSpec:
	var p := PlatformSpec.new()
	p.short_name = "SSK Test"
	p.domain = "subsurface"
	p.max_speed_kn = max_speed
	p.cruise_speed_kn = 6.0
	p.acoustic_signature = signature
	p.max_depth_m = max_depth
	p.patrol_depth_m = 90.0
	p.depth_rate_m_s = 2.0
	p.health = 45.0
	return p


func _ship_spec(signature := 1.0) -> PlatformSpec:
	var p := PlatformSpec.new()
	p.short_name = "DDG Test"
	p.domain = "surface"
	p.max_speed_kn = 30.0
	p.cruise_speed_kn = 16.0
	p.acoustic_signature = signature
	p.health = 110.0
	p.signature_factor = 1.0
	p.mast_height_m = 30.0
	return p


func _sonar(passive: float, active := 10.0, tolerance := 0.6, bearing := 1.0) -> SensorSpec:
	var s := SensorSpec.new()
	s.id = "test_sonar"
	s.kind = "sonar"
	s.passive_sensitivity_nm = passive
	s.active_range_nm = active
	s.self_noise_tolerance = tolerance
	s.bearing_accuracy_deg = bearing
	s.classify_rate = 1.0
	return s


func _radar() -> SensorSpec:
	var s := SensorSpec.new()
	s.kind = "radar"
	s.range_surface_nm = 40.0
	s.range_air_nm = 200.0
	s.antenna_height_m = 20.0
	return s


func _unit(spec: PlatformSpec, faction: String, pos: Vector2, speed := 0.0, depth := 0.0) -> Unit:
	var u := Unit.new()
	u.spec = spec
	u.faction = faction
	u.callsign = "%s-1" % faction
	u.position = pos
	u.speed_kn = speed
	u.ordered_speed_kn = speed
	u.health = spec.health
	u.depth_m = depth
	u.ordered_depth_m = depth
	return u


# --- Acoustics ---------------------------------------------------------------------------

func test_noise_rises_steeply_with_speed() -> void:
	var boat := _unit(_boat_spec(0.05), "RED", Vector2.ZERO, 0.0, 100.0)
	var at_rest := Detection.acoustic_noise(boat)
	boat.speed_kn = 6.0
	var at_creep := Detection.acoustic_noise(boat)
	boat.speed_kn = 12.0
	var at_speed := Detection.acoustic_noise(boat)
	assert_true(at_creep > at_rest, "moving is louder than sitting")
	assert_true(at_speed > at_creep * 1.8, "noise climbs faster than speed does")


func test_cavitation_starts_sooner_in_shallow_water() -> void:
	var shallow := _unit(_boat_spec(0.05), "RED", Vector2.ZERO, 9.0, 10.0)
	var deep := _unit(_boat_spec(0.05), "RED", Vector2.ZERO, 9.0, 220.0)
	assert_true(Detection.is_cavitating(shallow), "45 percent speed near the surface cavitates")
	assert_true(not Detection.is_cavitating(deep), "the same speed deep does not")
	assert_true(Detection.acoustic_noise(shallow) > Detection.acoustic_noise(deep) * 2.0, "cavitation is a large jump, not a nudge")


func test_a_quiet_boat_is_far_harder_to_hear_than_a_warship() -> void:
	var listener := _unit(_ship_spec(), "BLUE", Vector2.ZERO, 0.0)
	listener.sensors.append(_sonar(40.0))
	var boat := _unit(_boat_spec(0.05), "RED", Vector2(0.0, 5.0), 6.0, 90.0)
	var ship := _unit(_ship_spec(1.0), "RED", Vector2(0.0, 5.0), 16.0)
	var boat_range: float = Detection.best_passive_sonar(listener, boat)["range_nm"]
	var ship_range: float = Detection.best_passive_sonar(listener, ship)["range_nm"]
	assert_true(boat_range > 0.0, "the boat is audible at some range")
	assert_true(ship_range > boat_range * 4.0, "a surface combatant is heard far, far further off")


func test_slowing_down_to_listen_works() -> void:
	var fast := _unit(_ship_spec(), "BLUE", Vector2.ZERO, 27.0)
	var slow := _unit(_ship_spec(), "BLUE", Vector2.ZERO, 4.0)
	var array := _sonar(40.0, 10.0, 0.3)
	fast.sensors.append(array)
	slow.sensors.append(array)
	var target := _unit(_boat_spec(0.05), "RED", Vector2(0.0, 5.0), 6.0, 90.0)
	var fast_range := Detection.passive_sonar_range_nm(fast, array, target)
	var slow_range := Detection.passive_sonar_range_nm(slow, array, target)
	assert_true(slow_range > fast_range * 1.4, "own speed is the listener's biggest problem")


func test_a_towed_array_tolerates_own_speed_better_than_a_hull_set() -> void:
	var ship := _unit(_ship_spec(), "BLUE", Vector2.ZERO, 20.0)
	var hull := _sonar(40.0, 12.0, 0.3)
	var towed := _sonar(40.0, 9.0, 0.75)
	assert_true(Detection.self_noise_factor(ship, towed) > Detection.self_noise_factor(ship, hull), "streamed astern, away from the ship's own noise")


# --- Radar cannot see under water --------------------------------------------------------

func test_radar_cannot_see_a_submerged_boat() -> void:
	var ship := _unit(_ship_spec(), "BLUE", Vector2.ZERO)
	ship.sensors.append(_radar())
	var boat := _unit(_boat_spec(0.05), "RED", Vector2(0.0, 6.0), 6.0, 90.0)
	assert_near(Detection.radar_quality(ship, boat), 0.0, 1e-6, "nothing above the surface to see")
	boat.depth_m = 18.0
	assert_true(Detection.radar_signature_of(boat) > 0.0, "a raised mast is a target")
	assert_true(Detection.radar_signature_of(boat) < boat.spec.signature_factor * 0.2, "but a tiny one")
	boat.depth_m = 0.0
	assert_true(Detection.radar_quality(ship, boat) > 0.0, "surfaced, it is an ordinary contact")


# --- Passive contact is a bearing, not a position ----------------------------------------

func _sonar_harness(observer: Unit, target: Unit) -> Array:
	var um := UnitManager.new()
	um.add_unit(observer)
	um.add_unit(target)
	var tm := TrackManager.new()
	var sm := SensorManager.new()
	sm.unit_manager = um
	sm.track_manager = tm
	sm.rng.seed = 3
	return [um, tm, sm]


func _run_cycles(h: Array, seconds: float, turn_per_cycle := 0.0) -> void:
	var sm: SensorManager = h[2]
	var observer: Unit = sm.unit_manager.units[0]
	for i in int(seconds):
		if turn_per_cycle != 0.0:
			observer.heading_deg = fposmod(observer.heading_deg + turn_per_cycle, 360.0)
		sm.run_cycle(float(i + 1))


func _cleanup(h: Array) -> void:
	h[2].free()
	h[1].free()
	h[0].free()


func test_passive_contact_is_a_long_thin_ellipse_along_the_bearing() -> void:
	var listener := _unit(_ship_spec(), "BLUE", Vector2.ZERO, 4.0)
	listener.sensors.append(_sonar(40.0, 0.0))
	var target := _unit(_ship_spec(1.0), "RED", Vector2(0.0, 12.0), 16.0)
	var h := _sonar_harness(listener, target)
	_run_cycles(h, 5.0)
	var t: Track = h[1].get_tracks("BLUE")[0]
	assert_true(t.bearing_only, "held on sound alone")
	assert_true(t.is_bearing_only(), "and with no solution worth shooting at yet")
	assert_true(t.error_major_nm > t.error_minor_nm * 3.0, "uncertainty runs along the bearing line")
	assert_near(absf(Geo.heading_delta(t.error_axis_deg, 0.0)), 0.0, 6.0, "the bearing itself is good")
	assert_eq(t.source, "sonar_passive")
	_cleanup(h)


func test_manoeuvring_resolves_the_range() -> void:
	var still := _unit(_ship_spec(), "BLUE", Vector2.ZERO, 4.0)
	still.sensors.append(_sonar(40.0, 0.0))
	var target_a := _unit(_ship_spec(1.0), "RED", Vector2(0.0, 12.0), 16.0)
	var ha := _sonar_harness(still, target_a)
	_run_cycles(ha, 200.0)
	var steady: float = ha[1].get_tracks("BLUE")[0].tma_quality

	var turning := _unit(_ship_spec(), "BLUE", Vector2.ZERO, 4.0)
	turning.sensors.append(_sonar(40.0, 0.0))
	var target_b := _unit(_ship_spec(1.0), "RED", Vector2(0.0, 12.0), 16.0)
	var hb := _sonar_harness(turning, target_b)
	_run_cycles(hb, 200.0, 4.0)
	var manoeuvred: float = hb[1].get_tracks("BLUE")[0].tma_quality

	assert_true(manoeuvred > steady * 1.5, "turning against the bearing is how you get a range")
	assert_true(manoeuvred > 0.6, "a few minutes of manoeuvring gives a usable solution")
	_cleanup(ha)
	_cleanup(hb)


func test_active_sonar_gives_a_firm_position_immediately() -> void:
	var listener := _unit(_ship_spec(), "BLUE", Vector2.ZERO, 4.0)
	listener.sensors.append(_sonar(0.5, 12.0))
	listener.active_sonar_on = true
	var target := _unit(_boat_spec(0.05), "RED", Vector2(0.0, 6.0), 6.0, 90.0)
	var h := _sonar_harness(listener, target)
	_run_cycles(h, 3.0)
	var t: Track = h[1].get_tracks("BLUE")[0]
	assert_true(not t.bearing_only, "a ping returns a range")
	assert_eq(t.source, "sonar_active")
	assert_near(t.tma_quality, 1.0, 1e-6)
	assert_true(t.position.distance_to(target.position) < 1.0, "and it is close to the truth")
	_cleanup(h)


func test_pinging_is_heard_much_further_than_it_reaches() -> void:
	var emitter := _unit(_ship_spec(), "RED", Vector2.ZERO, 4.0)
	emitter.sensors.append(_sonar(20.0, 12.0))
	emitter.active_sonar_on = true
	var listener := _unit(_boat_spec(0.05), "BLUE", Vector2(0.0, 25.0), 4.0, 100.0)
	listener.sensors.append(_sonar(20.0, 10.0))
	var heard := Detection.active_sonar_detection_nm(listener, emitter)
	assert_true(heard > 12.0, "the transmission carries beyond the sonar's own reach")
	emitter.active_sonar_on = false
	assert_near(Detection.active_sonar_detection_nm(listener, emitter), 0.0, 1e-6, "silent once it stops")


# --- Depth -------------------------------------------------------------------------------

func test_depth_changes_at_the_stated_rate() -> void:
	var boat := _unit(_boat_spec(0.05), "RED", Vector2.ZERO, 6.0, 0.0)
	boat.apply_order(Order.set_depth(100.0))
	assert_near(boat.ordered_depth_m, 100.0, 1e-6)
	for i in int(20.0 / DT):
		Movement.step(boat, DT)
	assert_near(boat.depth_m, 40.0, 0.2, "2 m/s for 20 s")
	assert_true(boat.submerged())


func test_depth_orders_are_clamped_to_the_hull() -> void:
	var boat := _unit(_boat_spec(0.05, 20.0, 240.0), "RED", Vector2.ZERO)
	boat.apply_order(Order.set_depth(5000.0))
	assert_near(boat.ordered_depth_m, 240.0, 1e-6, "no deeper than the boat can go")


func test_a_surface_ship_never_leaves_the_surface() -> void:
	var ship := _unit(_ship_spec(), "BLUE", Vector2.ZERO, 10.0)
	ship.apply_order(Order.set_depth(100.0))
	Movement.step(ship, DT)
	assert_near(ship.depth_m, 0.0, 1e-6)
	assert_true(not ship.submerged())


# --- Torpedoes ---------------------------------------------------------------------------

func _torpedo(run_to_enable := 1.0, seeker := 2.5, damage := 90.0, pk := 1.0) -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = "test_torp"
	w.display_name = "Test torpedo"
	w.type = "torpedo"
	w.target_types = PackedStringArray(["surface", "subsurface"])
	w.max_range_nm = 25.0
	w.min_range_nm = 0.4
	w.speed_kn = 55.0
	w.turn_rate_deg_s = 12.0
	w.seeker_range_nm = seeker
	w.damage = damage
	w.base_pk = pk
	w.run_to_enable_nm = run_to_enable
	return w


func _weapon_harness(units: Array) -> WeaponManager:
	var um := UnitManager.new()
	for u: Unit in units:
		um.add_unit(u)
	var wm := WeaponManager.new()
	wm.unit_manager = um
	wm.rng.seed = 9
	return wm


func _advance(wm: WeaponManager, seconds: float) -> void:
	var now := 0.0
	for i in int(seconds / DT):
		now += DT
		wm.unit_manager.tick(DT)
		wm.tick(DT, now)


func _track_for(target: Unit, pos: Vector2) -> Track:
	var t := Track.new()
	t.id = "T1"
	t.truth = target
	t.position = pos
	t.status = Track.Status.ACTIVE
	t.domain = target.spec.domain
	return t


func test_torpedo_kills_a_submerged_boat() -> void:
	var shooter := _unit(_ship_spec(), "BLUE", Vector2.ZERO)
	var torp := _torpedo()
	shooter.weapons.append(torp)
	shooter.magazines[torp.id] = 4
	# Stopped, so the evasion term is out of the way and this tests the kill, not the dodge.
	var boat := _unit(_boat_spec(0.05), "RED", Vector2(0.0, 6.0), 0.0, 90.0)
	var wm := _weapon_harness([shooter, boat])
	assert_true(wm.launch(shooter, torp, _track_for(boat, Vector2(0.0, 6.0)), 1, 0.0), "shot accepted")
	_advance(wm, 700.0)
	assert_true(not boat.alive, "90 damage against a 45 point hull")
	_cleanup_wm(wm)


func test_an_anti_ship_missile_cannot_touch_a_submerged_boat() -> void:
	var asm := WeaponSpec.new()
	asm.id = "test_asm"
	asm.type = "asm"
	asm.target_types = PackedStringArray(["surface"])
	asm.max_range_nm = 60.0
	asm.speed_kn = 480.0
	asm.seeker_range_nm = 8.0
	asm.damage = 40.0
	asm.base_pk = 1.0
	var boat := _unit(_boat_spec(0.05), "RED", Vector2(0.0, 10.0), 6.0, 90.0)
	assert_true(not WeaponManager.can_target(asm, boat), "no seeker for that medium")
	boat.depth_m = 0.0
	assert_true(WeaponManager.can_target(asm, boat), "surfaced, it is fair game")
	var t := _track_for(boat, Vector2(0.0, 10.0))
	t.domain = "subsurface"
	assert_true(not Combat.suits_track(asm, t), "and the envelope check refuses the order up front")


func test_a_torpedo_will_not_bite_before_it_has_run_out() -> void:
	var shooter := _unit(_ship_spec(), "BLUE", Vector2.ZERO)
	var torp := _torpedo(4.0, 2.5)  # seeker stays off for the first 4 nm
	shooter.weapons.append(torp)
	shooter.magazines[torp.id] = 4
	# Target sits well inside the enable run, so the torpedo should pass it by.
	var boat := _unit(_boat_spec(0.05), "RED", Vector2(0.0, 1.2), 0.0, 90.0)
	var wm := _weapon_harness([shooter, boat])
	wm.launch(shooter, torp, _track_for(boat, Vector2(0.0, 1.2)), 1, 0.0)
	_advance(wm, 200.0)
	assert_true(boat.alive, "it ran past before the seeker came on")
	_cleanup_wm(wm)


func test_torpedoes_cannot_be_shot_down() -> void:
	var essm := WeaponSpec.new()
	essm.id = "essm"
	essm.type = "sam"
	essm.target_types = PackedStringArray(["missile"])
	essm.max_range_nm = 25.0
	essm.base_pk = 1.0
	var torpedo_round := Weapon.new()
	torpedo_round.spec = _torpedo()
	var missile_round := Weapon.new()
	missile_round.spec = WeaponSpec.new()
	missile_round.spec.type = "asm"
	assert_true(not AirDefence._can_intercept(essm, torpedo_round), "a surface-to-air missile is no use against a torpedo")
	assert_true(AirDefence._can_intercept(essm, missile_round), "but it is exactly right against a missile")


func _cleanup_wm(wm: WeaponManager) -> void:
	wm.unit_manager.free()
	wm.free()


# --- Shipped data ------------------------------------------------------------------------

func test_shipped_submarine_and_sonar_data_loads() -> void:
	for pid in ["usn_ssn_virginia", "rfn_ssk_kilo"]:
		var p := DataDB.platform(pid)
		assert_true(p != null, "%s loads" % pid)
		if p != null:
			assert_eq(p.domain, "subsurface")
			assert_true(p.max_depth_m > 0.0 and p.depth_rate_m_s > 0.0, "%s can dive" % pid)
			assert_true(p.acoustic_signature > 0.0 and p.acoustic_signature < 0.2, "%s is quiet" % pid)
			for sid in p.sensor_ids:
				var s := DataDB.sensor(sid)
				assert_true(s != null and s.kind == "sonar", "%s carries a real sonar" % pid)
			for wid in p.weapon_loadout:
				var w := DataDB.weapon(wid)
				assert_true(w != null and w.is_torpedo(), "%s carries torpedoes" % pid)
	for wid in ["mk48_adcap", "ugst_torpedo", "mk54_lwt", "rgm_139_vla"]:
		var w := DataDB.weapon(wid)
		assert_true(w != null, "%s loads" % wid)
		if w != null:
			assert_true(w.is_torpedo() and w.target_types.has("subsurface"), "%s can engage a boat" % wid)
			assert_true(w.run_to_enable_nm > 0.0, "%s has an enable run" % wid)


func test_asw_ships_can_actually_hunt() -> void:
	for pid in ["usn_ddg_arleigh_burke_iia", "rnon_ffg_fridtjof_nansen"]:
		var p := DataDB.platform(pid)
		assert_true(p != null)
		if p == null:
			continue
		var has_sonar := false
		for sid in p.sensor_ids:
			var s := DataDB.sensor(sid)
			if s != null and s.kind == "sonar":
				has_sonar = true
		assert_true(has_sonar, "%s has a sonar" % pid)
		var has_asw_weapon := false
		for wid in p.weapon_loadout:
			var w := DataDB.weapon(wid)
			if w != null and w.target_types.has("subsurface"):
				has_asw_weapon = true
		assert_true(has_asw_weapon, "%s has something to drop on a submarine" % pid)


func test_running_from_a_torpedo_helps() -> void:
	var torp := _torpedo(1.0, 2.5, 90.0, 0.9)
	var stopped := _unit(_ship_spec(), "BLUE", Vector2.ZERO, 0.0)
	var running := _unit(_ship_spec(), "BLUE", Vector2.ZERO, 30.0)
	assert_true(Combat.hit_probability(torp, running) < Combat.hit_probability(torp, stopped) * 0.7,
		"a ship at flank speed is a much harder problem for a torpedo")
