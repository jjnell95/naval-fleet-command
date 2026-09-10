extends TestCase

const DT := 0.25


func _platform(hp: float, sig := 1.0) -> PlatformSpec:
	var p := PlatformSpec.new()
	p.short_name = "FFG Test"
	p.max_speed_kn = 30.0
	p.cruise_speed_kn = 15.0
	p.health = hp
	p.signature_factor = sig
	return p


func _asm(pk := 1.0, max_range := 60.0, seeker := 8.0, dmg := 40.0) -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = "test_asm"
	w.display_name = "Test ASM"
	w.type = "asm"
	w.max_range_nm = max_range
	w.min_range_nm = 2.0
	w.speed_kn = 480.0
	w.turn_rate_deg_s = 30.0
	w.seeker_range_nm = seeker
	w.damage = dmg
	w.base_pk = pk
	w.launch_interval_s = 4.0
	return w


func _unit(faction: String, pos: Vector2, hp := 100.0, weapon: WeaponSpec = null, rounds := 8) -> Unit:
	var u := Unit.new()
	u.spec = _platform(hp)
	u.faction = faction
	u.callsign = "%s-1" % faction
	u.position = pos
	u.health = hp
	if weapon != null:
		u.weapons.append(weapon)
		u.magazines[weapon.id] = rounds
	return u


func _track(target: Unit, pos: Vector2, status := Track.Status.ACTIVE) -> Track:
	var t := Track.new()
	t.id = "T1001"
	t.owner_faction = "BLUE"
	t.truth = target
	t.position = pos
	t.status = status
	t.domain = target.spec.domain
	return t


func _harness(units: Array) -> WeaponManager:
	var um := UnitManager.new()
	for u: Unit in units:
		um.add_unit(u)
	var wm := WeaponManager.new()
	wm.unit_manager = um
	wm.rng.seed = 7
	return wm


func _advance(wm: WeaponManager, seconds: float, start_now := 0.0) -> float:
	var now := start_now
	var steps := int(seconds / DT)
	for i in steps:
		now += DT
		wm.unit_manager.tick(DT)
		wm.tick(DT, now)
	return now


func _cleanup(wm: WeaponManager) -> void:
	wm.unit_manager.free()
	wm.free()


# --- Geometry and envelope ---------------------------------------------------------------

func test_intercept_point_stationary_target() -> void:
	var p := Combat.intercept_point(Vector2.ZERO, 480.0, Vector2(0.0, 20.0), 90.0, 0.0, true)
	assert_near(p.y, 20.0, 1e-4, "no lead against a stopped target")
	assert_near(p.x, 0.0, 1e-4)


func test_intercept_point_leads_moving_target() -> void:
	# Target 40 nm north running east at 30 kn; weapon at 480 kn takes ~5 min to arrive.
	var p := Combat.intercept_point(Vector2.ZERO, 480.0, Vector2(0.0, 40.0), 90.0, 30.0, true)
	assert_true(p.x > 2.0, "aim point leads east of the track")
	assert_near(p.x, 30.0 * (p.distance_to(Vector2.ZERO) / 480.0), 0.2, "lead consistent with time of flight")


func test_intercept_ignores_unknown_kinematics() -> void:
	var p := Combat.intercept_point(Vector2.ZERO, 480.0, Vector2(0.0, 40.0), 90.0, 30.0, false)
	assert_near(p.x, 0.0, 1e-4, "no lead until course/speed are estimated")


func test_envelope_checks() -> void:
	var w := _asm(1.0, 60.0)
	var shooter := _unit("BLUE", Vector2.ZERO, 100.0, w, 8)
	var target := _unit("RED", Vector2(0.0, 30.0))
	assert_true(Combat.check_engagement(shooter, w, _track(target, Vector2(0.0, 30.0)))["ok"], "30 nm is inside a 60 nm weapon")
	assert_eq(Combat.check_engagement(shooter, w, _track(target, Vector2(0.0, 80.0)))["reason"], "OUT OF RANGE")
	assert_eq(Combat.check_engagement(shooter, w, _track(target, Vector2(0.0, 1.0)))["reason"], "TOO CLOSE")
	assert_eq(Combat.check_engagement(shooter, w, _track(target, Vector2(0.0, 30.0), Track.Status.LOST))["reason"], "TRACK LOST")
	shooter.magazines[w.id] = 0
	assert_eq(Combat.check_engagement(shooter, w, _track(target, Vector2(0.0, 30.0)))["reason"], "MAGAZINE EMPTY")


# --- Weapon flight -----------------------------------------------------------------------

func test_salvo_consumes_magazine_and_spawns_rounds() -> void:
	var w := _asm()
	var shooter := _unit("BLUE", Vector2.ZERO, 100.0, w, 8)
	var target := _unit("RED", Vector2(0.0, 20.0))
	var wm := _harness([shooter, target])
	assert_true(wm.launch(shooter, w, _track(target, Vector2(0.0, 20.0)), 4, 0.0), "launch accepted")
	assert_eq(shooter.magazine_count(w.id), 4, "four rounds consumed at launch")
	assert_eq(wm.in_flight.size(), 1, "first round away immediately")
	_advance(wm, 13.0)
	assert_eq(wm.in_flight.size(), 4, "remaining rounds ripple off at the launch interval")
	_cleanup(wm)


func test_missile_hits_and_damages_target() -> void:
	var w := _asm(1.0, 60.0, 8.0, 40.0)
	var shooter := _unit("BLUE", Vector2.ZERO, 100.0, w, 8)
	var target := _unit("RED", Vector2(0.0, 20.0), 100.0)
	var wm := _harness([shooter, target])
	wm.launch(shooter, w, _track(target, Vector2(0.0, 20.0)), 1, 0.0)
	_advance(wm, 200.0)  # 20 nm at 480 kn is 150 s
	assert_true(wm.in_flight.is_empty(), "round resolved")
	assert_near(target.health, 60.0, 1e-3, "40 damage applied")
	assert_true(target.alive)
	_cleanup(wm)


func test_missile_misses_when_pk_fails() -> void:
	var w := _asm(0.0)
	var shooter := _unit("BLUE", Vector2.ZERO, 100.0, w, 8)
	var target := _unit("RED", Vector2(0.0, 20.0), 100.0)
	var wm := _harness([shooter, target])
	wm.launch(shooter, w, _track(target, Vector2(0.0, 20.0)), 1, 0.0)
	_advance(wm, 200.0)
	assert_near(target.health, 100.0, 1e-3, "zero pk never damages")
	assert_true(target.alive)
	_cleanup(wm)


func test_stale_track_sends_missile_to_empty_water() -> void:
	var w := _asm(1.0, 60.0, 8.0, 40.0)
	var shooter := _unit("BLUE", Vector2.ZERO, 100.0, w, 8)
	var target := _unit("RED", Vector2(0.0, 20.0), 100.0)
	# The track says the enemy is 25 nm east of where it actually is, and it is no longer
	# being observed, so no mid-course update can correct the aim point.
	var stale := _track(target, Vector2(25.0, 20.0), Track.Status.STALE)
	var wm := _harness([shooter, target])
	wm.launch(shooter, w, stale, 1, 0.0)
	_advance(wm, 400.0)
	assert_true(wm.in_flight.is_empty(), "round expended")
	assert_near(target.health, 100.0, 1e-3, "stale data means the seeker finds nothing")
	_cleanup(wm)


func test_mid_course_update_follows_an_active_track() -> void:
	var w := _asm(1.0, 60.0, 8.0, 40.0)
	var shooter := _unit("BLUE", Vector2.ZERO, 100.0, w, 8)
	var target := _unit("RED", Vector2(0.0, 25.0), 100.0)
	target.heading_deg = 90.0
	target.speed_kn = 25.0
	target.ordered_heading_deg = 90.0
	target.ordered_speed_kn = 25.0
	var live := _track(target, target.position)
	var wm := _harness([shooter, target])
	wm.launch(shooter, w, live, 1, 0.0)
	# Keep the track fed with truth, as a radar holding contact would.
	var now := 0.0
	for i in int(400.0 / DT):
		now += DT
		wm.unit_manager.tick(DT)
		live.position = target.position
		wm.tick(DT, now)
		if not wm.in_flight.is_empty():
			continue
		break
	assert_near(target.health, 60.0, 1e-3, "a maintained track still gets the hit on a manoeuvring target")
	_cleanup(wm)


func test_range_exhaustion() -> void:
	var w := _asm(1.0, 10.0, 8.0, 40.0)  # 10 nm weapon
	var shooter := _unit("BLUE", Vector2.ZERO, 100.0, w, 8)
	var target := _unit("RED", Vector2(0.0, 40.0), 100.0)
	var wm := _harness([shooter, target])
	# Envelope check blocks the shot; force a round into the air to prove the fuel cut-off works.
	assert_eq(Combat.check_engagement(shooter, w, _track(target, Vector2(0.0, 40.0)))["reason"], "OUT OF RANGE")
	wm.launch(shooter, w, _track(target, Vector2(0.0, 9.0)), 1, 0.0)
	_advance(wm, 400.0)
	assert_true(wm.in_flight.is_empty())
	assert_near(target.health, 100.0, 1e-3, "round ran out of range short of the real ship")
	_cleanup(wm)


# --- Damage ------------------------------------------------------------------------------

func test_damage_destroys_and_silences_unit() -> void:
	var u := _unit("RED", Vector2.ZERO, 50.0)
	u.radar_on = true
	u.speed_kn = 20.0
	assert_true(not Damage.apply(u, 12.0), "survives a light hit")
	assert_eq(Damage.condition_text(u), "LIGHT DAMAGE")
	assert_true(not Damage.apply(u, 13.0), "still afloat at half strength")
	assert_eq(Damage.condition_text(u), "HEAVY DAMAGE")
	assert_true(Damage.apply(u, 40.0), "destroyed by the second hit")
	assert_true(not u.alive)
	assert_near(u.speed_kn, 0.0, 1e-6, "wreck stops moving")
	assert_true(not u.radar_on, "wreck stops radiating")




# --- Data integrity ----------------------------------------------------------------------

func test_shipped_data_loads() -> void:
	for wid in ["rgm_84_harpoon", "nsm_strike_missile", "p800_oniks", "kh35_uran", "mk45_mod4_gun", "oto_76mm_gun", "a190_100mm_gun"]:
		var w := DataDB.weapon(wid)
		assert_true(w != null, "weapon %s loads" % wid)
		if w != null:
			assert_true(w.max_range_nm > 0.0 and w.damage > 0.0, "%s has usable values" % wid)
	for pid in ["usn_ddg_arleigh_burke_iia", "rnon_ffg_fridtjof_nansen", "rfn_ffg_admiral_gorshkov", "rfn_fsg_steregushchiy"]:
		var p := DataDB.platform(pid)
		assert_true(p != null, "platform %s loads" % pid)
		if p != null:
			assert_true(p.health > 0.0, "%s has a damage pool" % pid)
			assert_true(not p.weapon_loadout.is_empty(), "%s carries weapons" % pid)
			for wid in p.weapon_loadout:
				assert_true(DataDB.weapon(wid) != null, "%s loadout references real weapon %s" % [pid, wid])


func test_real_harpoon_flies_and_hits() -> void:
	var w := DataDB.weapon("rgm_84_harpoon")
	assert_true(w != null)
	if w == null:
		return
	var shooter := _unit("BLUE", Vector2.ZERO, 110.0, w, 8)
	var target := _unit("RED", Vector2(0.0, 18.0), 90.0)
	var wm := _harness([shooter, target])
	wm.rng.seed = 1  # deterministic pass of the 0.80 pk roll
	wm.launch(shooter, w, _track(target, Vector2(0.0, 18.0)), 2, 0.0)
	_advance(wm, 300.0)
	assert_true(wm.in_flight.is_empty(), "both rounds resolved")
	assert_true(target.health < 90.0, "shipped Harpoon data produces damage")
	_cleanup(wm)
