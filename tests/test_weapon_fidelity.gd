extends TestCase
## Commander decisions must obey the same geometry as the flight and held-picture advisory.


func _shooter() -> Unit:
	var u := Unit.new()
	u.spec = PlatformSpec.new()
	u.callsign = "Shooter"
	u.faction = "BLUE"
	u.roe = Unit.Roe.FREE
	return u


func _track(position: Vector2, identity := "HOSTILE") -> Track:
	var t := Track.new()
	t.id = "T1001"
	t.owner_faction = "BLUE"
	t.position = position
	t.position_error_nm = 0.0
	t.identity = identity
	t.domain = "surface"
	return t


func _weapon() -> WeaponSpec:
	var spec := WeaponSpec.new()
	spec.id = "test"
	spec.min_range_nm = 0.0
	spec.speed_kn = 3600.0
	spec.seeker_range_nm = 2.0
	return spec


func test_swept_forward_cone_rejects_astern_and_abeam_baskets() -> void:
	assert_true(not is_finite(WeaponManager.first_seeker_contact_fraction(Vector2.ZERO, Vector2(0, 5), Vector2(0, -1), 2.0, 0.0, 35.0)))
	assert_true(not is_finite(WeaponManager.first_seeker_contact_fraction(Vector2.ZERO, Vector2(0, 5), Vector2(1, 0.1), 2.0, 0.0, 35.0)))
	assert_near(WeaponManager.first_seeker_contact_fraction(Vector2.ZERO, Vector2(0, 5), Vector2(0, 3), 0.1, 0.0, 35.0), 0.58, 0.001, "a narrow forward basket crossed entirely in one tick is found")
	assert_true(is_finite(WeaponManager.first_seeker_contact_fraction(Vector2.ZERO, Vector2.ZERO, Vector2(0, 1), 2.0, 0.0, 35.0)), "stationary seeker and reacquisition share the same geometry")


func test_initial_acquisition_can_find_neutral_and_friendly_traffic() -> void:
	for faction: String in ["NEUTRAL", "BLUE"]:
		var wm := WeaponManager.new()
		wm.unit_manager = UnitManager.new()
		var civilian := _shooter()
		civilian.faction = faction
		civilian.position = Vector2(0, 1)
		wm.unit_manager.add_unit(civilian)
		var w := Weapon.new()
		w.spec = _weapon()
		w.spec.base_pk = 0.0
		w.faction = "BLUE"
		w.position = Vector2(0, 0.5)
		w.aim_point = Vector2(0, 2)
		wm._try_acquire(w, Vector2.ZERO)
		assert_true(w.acquired == civilian, "the seeker cannot read faction or a protected plot identity")
		wm.unit_manager.free()
		wm.free()


func test_only_supported_weapons_accept_live_midcourse_updates() -> void:
	Terrain.clear()
	for supported: bool in [false, true]:
		var wm := WeaponManager.new()
		wm.unit_manager = UnitManager.new()
		var shooter := _shooter()
		var spec := _weapon()
		spec.midcourse_updates = supported
		shooter.weapons.append(spec)
		shooter.magazines[spec.id] = 2
		var track := _track(Vector2(0, 20))
		assert_true(wm.launch(shooter, spec, track, 1, 0.0))
		var round: Weapon = wm.in_flight[0]
		track.position = Vector2(10, 20)
		wm.tick(0.25, 0.25)
		assert_near(round.aim_point.x, 10.0 if supported else 0.0, 0.001)
		shooter.alive = false
		track.position = Vector2(15, 20)
		wm.tick(0.25, 0.5)
		assert_near(round.aim_point.x, 10.0 if supported else 0.0, 0.001, "lost shooter cannot transmit a new solution")
		wm.clear()
		wm.unit_manager.free()
		wm.free()
	assert_true(not DataDB.weapon("cw90_harpoon").supports_midcourse_updates())
	assert_true(not DataDB.weapon("nsm_strike_missile").supports_midcourse_updates())
	assert_true(DataDB.weapon("aim120_family").supports_midcourse_updates())
	assert_true(DataDB.weapon("sm2_family").supports_midcourse_updates())


func test_semi_active_guidance_still_requires_illumination() -> void:
	var shooter := _shooter()
	var spec := _weapon()
	spec.type = "sam"
	spec.guidance = "semi_active_abstract"
	assert_true(spec.requires_radar_support())
	shooter.radar_on = false
	assert_true(not WeaponManager.radar_support_available(shooter, spec))
	shooter.radar_on = true
	shooter.emcon = Unit.Emcon.FREE
	assert_true(WeaponManager.radar_support_available(shooter, spec))
	var wm := WeaponManager.new()
	var round := Weapon.new()
	round.spec = spec
	round.shooter = shooter
	shooter.radar_on = false
	wm._step(round, 0.25)
	assert_eq(round.dead_reason, "GUIDANCE LOST")
	wm.free()


func test_mount_arcs_union_and_vls_exception() -> void:
	var shooter := _shooter()
	var spec := _weapon()
	shooter.spec.weapon_mount_arcs = {spec.id: [Vector2(0, 140)]}
	var aft := Vector2(0, -10)
	var check := Combat.firing_arc_check(shooter, spec, aft)
	assert_true(not check.ok)
	shooter.heading_deg = check.heading_deg
	assert_true(Combat.firing_arc_check(shooter, spec, aft).ok)
	shooter.heading_deg = 0.0
	shooter.spec.weapon_mount_arcs[spec.id].append(Vector2(180, 140))
	assert_true(Combat.firing_arc_check(shooter, spec, aft).ok, "paired fore/aft mounts cover each other's masked sector")
	shooter.spec.weapon_mount_arcs[spec.id] = [Vector2(0, 20)]
	spec.vls_pack = 1
	shooter.spec.vls_cells = 32
	assert_true(Combat.firing_arc_check(shooter, spec, aft).ok, "VLS does not need hull unmasking")


func test_attack_crew_turns_before_expending_a_masked_mount() -> void:
	Terrain.clear()
	var shooter := _shooter()
	var spec := _weapon()
	shooter.weapons.append(spec)
	shooter.magazines[spec.id] = 2
	shooter.spec.weapon_mount_arcs = {spec.id: [Vector2(0, 140)]}
	var track := _track(Vector2(0, -10))
	var um := UnitManager.new()
	var wm := WeaponManager.new()
	wm.unit_manager = um
	um.weapon_manager = wm
	um.add_unit(shooter)
	assert_true(um.issue_order(shooter, Order.attack(track, spec.id)))
	um.tick(0.25)
	assert_eq(shooter.attack_phase, "Turning to engage")
	assert_true(wm.in_flight.is_empty())
	assert_eq(shooter.magazine_count(spec.id), 2)
	shooter.heading_deg = shooter.ordered_heading_deg
	um.tick(0.25)
	assert_true(not wm.in_flight.is_empty(), "the standing task fires once the mount is unmasked")
	um.weapon_manager = null
	wm.clear()
	wm.free()
	um.free()


func test_traffic_advisory_reads_only_held_protected_reports() -> void:
	var shooter := _shooter()
	var spec := _weapon()
	var target := _track(Vector2(0, 20))
	var civilian := _track(Vector2(1, 20), "NEUTRAL")
	civilian.id = "CIV1"
	civilian.truth = _shooter()
	civilian.truth.position = Vector2(1000, 1000)
	var hidden := _track(Vector2(0, 20), "FRIENDLY")
	hidden.networked = false
	var far := _track(Vector2(20, 20), "NEUTRAL")
	var risks := WeaponPresentation.protected_contacts_at_risk(shooter, spec, target, [civilian, hidden, far])
	assert_eq(risks.size(), 1)
	assert_true(risks.has(civilian), "held report warns even when debug truth differs")
	assert_true(WeaponPresentation.protected_contact_warning(shooter, spec, target, [civilian]).contains("CIV1"))
	civilian.status = Track.Status.LOST
	assert_true(WeaponPresentation.protected_contacts_at_risk(shooter, spec, target, [civilian]).is_empty())


func _armed(spec: WeaponSpec, domain: String, faction := "BLUE") -> Unit:
	var u := _shooter()
	u.spec.domain = domain
	u.spec.vls_cells = 32
	u.spec.fire_control_channels = 4
	u.spec.has_datalink = true
	u.faction = faction
	u.health = 100
	u.radar_on = true
	if domain == "air":
		u.flight_state = Unit.FlightState.AIRBORNE
		u.altitude_m = 6000
	if spec != null:
		u.weapons.append(spec)
		u.magazines[spec.id] = 8
	return u


func test_rocket_delivered_torpedo_searches_around_its_water_entry() -> void:
	# The payload swims on along the rocket's line before its seeker comes on. A boat on or
	# just short of the held datum is then astern of it, and must still be found.
	for offset: Vector2 in [Vector2.ZERO, Vector2(0, 0.3), Vector2(0, -0.3), Vector2(0.4, 0)]:
		Terrain.clear()
		var rocket := DataDB.weapon("rgm_139_vla")
		var ship := _armed(rocket, "surface")
		var boat := _armed(null, "subsurface", "RED")
		boat.position = Vector2(0, 5) + offset
		boat.depth_m = 100
		boat.ordered_depth_m = 100
		var wm := WeaponManager.new()
		wm.unit_manager = UnitManager.new()
		wm.unit_manager.add_unit(ship)
		wm.unit_manager.add_unit(boat)
		var datum := _track(Vector2(0, 5))
		datum.domain = "subsurface"
		assert_true(wm.launch(ship, rocket, datum, 1, 0))
		var round: Weapon = wm.in_flight[0]
		var now := 0.0
		while round.phase != Weapon.Phase.DEAD and round.acquired == null and now < 600.0:
			now += 0.5
			wm.tick(0.5, now)
		assert_true(round.acquired == boat, "payload finds a boat %s from its datum" % offset)
		wm.clear()
		wm.unit_manager.free()
		wm.free()


func test_seeker_separating_from_its_launcher_ignores_the_wingman_alongside() -> void:
	# A short shot opens its seeker at launch with the bandit and the shooter's own section
	# already in the basket. A round still separating takes nothing alongside its launcher.
	for ahead: float in [0.0, 0.3]:
		Terrain.clear()
		var aam := DataDB.weapon("cw90_aim9m")
		var lead := _armed(aam, "air")
		var wing := _armed(null, "air")
		wing.position = Geo.heading_to_vector(0) * ahead
		var bandit := _armed(null, "air", "RED")
		bandit.position = Geo.heading_to_vector(0) * 3.0
		var wm := WeaponManager.new()
		wm.unit_manager = UnitManager.new()
		for u: Unit in [lead, wing, bandit]:
			wm.unit_manager.add_unit(u)
		var target := _track(bandit.position)
		target.domain = "air"
		target.altitude_m = 6000
		assert_true(wm.launch(lead, aam, target, 1, 0))
		var round: Weapon = wm.in_flight[0]
		var first: Unit = null
		var now := 0.0
		while round.phase != Weapon.Phase.DEAD and now < 60.0:
			now += 0.25
			wm.tick(0.25, now)
			if first == null and round.acquired != null:
				first = round.acquired
		assert_true(first == bandit, "wingman %.1f nm ahead is not the first lock" % ahead)
		assert_near(wing.health, 100.0, 0.001, "the section's wingman is not hit")
		wm.clear()
		wm.unit_manager.free()
		wm.free()


func test_traffic_ahead_beyond_safe_separation_is_still_in_the_line_of_fire() -> void:
	# The seeker cannot read identities: a merchant between the shooter and its target is the
	# first return the seeker meets, even while the round is still separating from its launcher.
	var wm := WeaponManager.new()
	wm.unit_manager = UnitManager.new()
	var shooter := _armed(null, "surface")
	var merchant := _armed(null, "surface", "NEUTRAL")
	merchant.position = Vector2(0, 1.5)
	var target := _armed(null, "surface", "RED")
	target.position = Vector2(0, 2.5)
	for u: Unit in [shooter, merchant, target]:
		wm.unit_manager.add_unit(u)
	var w := Weapon.new()
	w.spec = _weapon()
	w.shooter = shooter
	w.faction = "BLUE"
	w.position = Vector2(0, 0.3)
	w.distance_flown_nm = 0.3
	w.aim_point = target.position
	wm._try_acquire(w, Vector2(0, 0.1))
	assert_true(w.acquired == merchant, "safe separation does not clear the line of fire")
	wm.unit_manager.free()
	wm.free()


func test_a_close_shot_the_weapon_allows_still_finds_its_target() -> void:
	# Separation follows the round's own minimum range: a short-range missile cleared to fire at
	# 0.4 nm is armed against the bandit it was fired at.
	Terrain.clear()
	var aam := DataDB.weapon("aim9x_air")
	assert_true(aam.min_range_nm < 0.4, "the fixture needs a weapon that may fire inside half a mile")
	var lead := _armed(aam, "air")
	var bandit := _armed(null, "air", "RED")
	bandit.position = Geo.heading_to_vector(0) * 0.4
	var wm := WeaponManager.new()
	wm.unit_manager = UnitManager.new()
	for u: Unit in [lead, bandit]:
		wm.unit_manager.add_unit(u)
	var target := _track(bandit.position)
	target.domain = "air"
	target.altitude_m = 6000
	assert_true(wm.launch(lead, aam, target, 1, 0))
	var round: Weapon = wm.in_flight[0]
	var now := 0.0
	while round.phase != Weapon.Phase.DEAD and round.acquired == null and now < 30.0:
		now += 0.25
		wm.tick(0.25, now)
	assert_true(round.acquired == bandit)
	wm.clear()
	wm.unit_manager.free()
	wm.free()
