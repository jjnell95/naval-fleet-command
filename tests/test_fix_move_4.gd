extends TestCase
## The weapon a captain would choose. The standing attack picks the round and the salvo from the
## plot: the gun at small craft inside its reach, else the cheapest round meant for the target that
## reaches with margin, and as many rounds as it takes to finish what the plot says is left.

const DT := 0.25


## A catalogue platform fitted as a scenario fits it.
func _ship(platform_id: String, faction: String, pos: Vector2) -> Unit:
	var spec := DataDB.platform(platform_id)
	var u := Unit.new()
	u.spec = spec
	u.faction = faction
	u.callsign = "%s %s" % [faction, platform_id]
	u.position = pos
	u.health = spec.health
	for wid: String in spec.weapon_loadout:
		var w := DataDB.weapon(wid)
		if w != null:
			u.weapons.append(w)
			u.magazines[wid] = int(spec.weapon_loadout[wid])
	return u


## The shooter's plot of a target: what is reported of it, never its true state.
func _track(target: Unit, classified := true) -> Track:
	var t := Track.new()
	t.id = "T2001"
	t.owner_faction = "BLUE"
	t.truth = target
	t.position = target.position
	t.position_error_nm = 0.3
	t.status = Track.Status.ACTIVE
	t.domain = "surface"
	t.identity = "HOSTILE"
	t.classification = Track.Classification.CLASS_KNOWN if classified else Track.Classification.SURFACE
	t.known_class = target.spec.short_name if classified else ""
	return t


class Harness:
	extends RefCounted
	var um: UnitManager
	var wm: WeaponManager
	var now := 0.0

	func advance(seconds: float) -> void:
		for i in int(round(seconds / 0.25)):
			now += 0.25
			um.tick(0.25, now)
			wm.tick(0.25, now)

	func free_all() -> void:
		um.free()
		wm.free()


func _harness(units: Array) -> Harness:
	Terrain.clear()
	var h := Harness.new()
	h.um = UnitManager.new()
	for u: Unit in units:
		h.um.add_unit(u)
	h.wm = WeaponManager.new()
	h.wm.unit_manager = h.um
	h.wm.rng.seed = 11
	h.um.weapon_manager = h.wm
	return h


## Rounds of each weapon the shooter has spent or committed since `before` was taken.
func _spent(u: Unit, before: Dictionary) -> Dictionary:
	var out := {}
	for wid: String in before:
		var used := int(before[wid]) - u.magazine_count(wid)
		if used > 0:
			out[wid] = used
	return out


func _attack(shooter: Unit, target: Unit, t: Track, seconds := 30.0) -> Dictionary:
	var h := _harness([shooter, target])
	var before := shooter.magazines.duplicate()
	h.um.issue_order(shooter, Order.attack(t))
	h.advance(seconds)
	var out := {"spent": _spent(shooter, before), "fired": shooter.attack_rounds_fired}
	h.free_all()
	return out


func test_a_speedboat_inside_gun_range_draws_the_gun() -> void:
	var shooter := _ship("rn_ddg_type45", "BLUE", Vector2.ZERO)
	var boat := _ship("irn_fac_peykaap3", "RED", Vector2(0, 5))
	var t := _track(boat)
	assert_eq(shooter.weapons_for_track(t)[0].id, "mk8_114mm_gun", "the gun leads against an eight-point boat at five miles")
	var result := _attack(shooter, boat, t)
	var spent: Dictionary = result["spent"]
	assert_true(spent.has("mk8_114mm_gun"), "the gun fires: %s" % str(spent))
	assert_true(not spent.has("rgm_84_harpoon"), "no Harpoon at a speedboat inside gun range: %s" % str(spent))


func test_a_speedboat_beyond_gun_range_draws_one_missile_not_a_salvo() -> void:
	var shooter := _ship("rn_ddg_type45", "BLUE", Vector2.ZERO)
	var boat := _ship("irn_fac_peykaap3", "RED", Vector2(0, 30))
	var t := _track(boat)
	assert_eq(shooter.weapons_for_track(t)[0].id, "rgm_84_harpoon", "beyond the gun the ship-killer that reaches")
	assert_eq(shooter.salvo_for_track(DataDB.weapon("rgm_84_harpoon"), t), 1, "one round finishes an eight-point boat")
	var result := _attack(shooter, boat, t, 10.0)
	assert_eq(int(result["fired"]), 1, "one Harpoon, not four")


func test_a_destroyer_at_sixty_miles_draws_the_anti_ship_missile_not_the_land_attack_one() -> void:
	var shooter := _ship("usn_cg_ticonderoga", "BLUE", Vector2.ZERO)
	var destroyer := _ship("pla_ddg_type052d", "RED", Vector2(0, 60))
	var t := _track(destroyer)
	var first := shooter.weapons_for_track(t)[0]
	assert_eq(first.id, "rgm_84_harpoon", "the anti-ship missile leads")
	var result := _attack(shooter, destroyer, t, 30.0)
	var spent: Dictionary = result["spent"]
	assert_true(spent.has("rgm_84_harpoon"), "Harpoons go: %s" % str(spent))
	assert_true(not spent.has("tomahawk_block_v"), "the Tomahawks are kept: %s" % str(spent))
	assert_eq(int(spent.get("rgm_84_harpoon", 0)), 4, "a fresh destroyer gets the full salvo")


func test_a_contact_assessed_three_quarters_destroyed_draws_a_one_round_reattack() -> void:
	var shooter := _ship("rn_ddg_type45", "BLUE", Vector2.ZERO)
	var frigate := _ship("irn_ffg_alvand", "RED", Vector2(0, 30))
	var t := _track(frigate)
	var harpoon := DataDB.weapon("rgm_84_harpoon")
	assert_eq(shooter.salvo_for_track(harpoon, t), 2, "a fresh 55-point frigate is worth two")
	t.damage_estimate = 76.0
	assert_eq(shooter.salvo_for_track(harpoon, t), 1, "one more round for what is left")
	var result := _attack(shooter, frigate, t, 10.0)
	assert_eq(int(result["fired"]), 1, "the re-attack is one round, not four")


func test_an_unclassified_contact_is_assumed_a_medium_hull() -> void:
	var shooter := _ship("rn_ddg_type45", "BLUE", Vector2.ZERO)
	var boat := _ship("irn_fac_peykaap3", "RED", Vector2(0, 30))
	var t := _track(boat, false)
	assert_eq(shooter.salvo_for_track(DataDB.weapon("rgm_84_harpoon"), t), 4, "the plot does not know it is a boat")


func test_an_anti_surface_weapon_comes_before_an_anti_submarine_torpedo() -> void:
	var shooter := _ship("fra_ffg_fremm", "BLUE", Vector2.ZERO)
	shooter.magazines["mm40_exocet"] = 0
	var frigate := _ship("irn_ffg_moudge", "RED", Vector2(0, 5))
	var t := _track(frigate)
	var ranked := shooter.weapons_for_track(t).map(func(w: WeaponSpec) -> String: return w.id)
	assert_eq(ranked[0], "oto_76mm_gun", "the gun before a lightweight torpedo at a ship: %s" % str(ranked))
	shooter.magazines["mm40_exocet"] = 8
	ranked = shooter.weapons_for_track(t).map(func(w: WeaponSpec) -> String: return w.id)
	assert_eq(ranked[0], "mm40_exocet", "and the ship-killer before both: %s" % str(ranked))


func test_a_named_weapon_fires_its_own_salvo_whatever_the_target() -> void:
	var shooter := _ship("usn_cg_ticonderoga", "BLUE", Vector2.ZERO)
	var boat := _ship("irn_fac_peykaap3", "RED", Vector2(0, 30))
	var t := _track(boat)
	var h := _harness([shooter, boat])
	h.um.issue_order(shooter, Order.attack(t, "tomahawk_block_v"))
	h.advance(10.0)
	assert_eq(shooter.attack_rounds_fired, DataDB.weapon("tomahawk_block_v").salvo_default, "the commander's choice is not second-guessed")
	h.free_all()


# --- CAP pursuit -------------------------------------------------------------------------

func _load_carrier() -> Simulation:
	SimClock.set_paused(true)
	var sim := Simulation.new()
	sim.seed_override = 7
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	assert_true(sim.load_scenario("res://data/scenarios/cold_war_03_carrier.json"))
	sim.ai_enabled = false
	return sim


func _free_sim(sim: Simulation) -> void:
	sim.unit_manager.clear()
	sim.queue_free()
	sim.free()


func test_a_cap_ordered_without_a_pursuit_may_chase_the_standard_sixty_miles() -> void:
	var sim := _load_carrier()
	var cv: Unit = null
	for u in sim.unit_manager.units:
		if u.callsign == "USS Dwight D. Eisenhower (CVN 69)":
			cv = u
	assert_true(sim.unit_manager.issue_order(cv, Order.air_mission(AirMission.Kind.CAP, "cw90_f14a", 2, cv.position + Vector2(0, 20), 10.0)))
	var m: AirMission = sim.air_mission_manager.active_missions("BLUE")[0]
	assert_eq(m.pursuit_nm, AirMissionManager.COMMIT_MARGIN_NM, "the CAP chases as far as the dialog's default")
	assert_true(sim.unit_manager.issue_order(cv, Order.revise_air_mission(m, m.station, 10.0, 2, false, true, "hold", null, 40.0)))
	assert_eq(m.pursuit_nm, 40.0)
	assert_true(sim.unit_manager.issue_order(cv, Order.revise_air_mission(m, m.station + Vector2(5, 0), 10.0, 2, false, true)))
	assert_eq(m.pursuit_nm, 40.0, "a revision that names no pursuit keeps the mission's own")
	_free_sim(sim)


# --- A torpedo shot opens beyond the enable run -----------------------------------------------

func _test_hull(domain := "surface") -> PlatformSpec:
	var p := PlatformSpec.new()
	p.short_name = "Test"
	p.domain = domain
	p.max_speed_kn = 28.0
	p.cruise_speed_kn = 14.0
	p.turn_rate_deg_s = 6.0
	p.accel_kn_s = 1.0
	p.health = 100.0
	p.length_m = 120.0
	if domain == "subsurface":
		p.max_depth_m = 300.0
		p.depth_rate_m_s = 1.0
	return p


func test_a_torpedo_attack_from_too_close_opens_beyond_the_enable_run_and_fires() -> void:
	var fish := WeaponSpec.new()
	fish.id = "test_long_enable_torpedo"
	fish.display_name = "Test torpedo"
	fish.type = "torpedo"
	fish.target_types = PackedStringArray(["subsurface"])
	fish.max_range_nm = 12.0
	fish.min_range_nm = 0.5
	fish.run_to_enable_nm = 2.0
	fish.speed_kn = 45.0
	fish.damage = 60.0
	fish.base_pk = 1.0
	fish.salvo_default = 1
	var ship := Unit.new()
	ship.spec = _test_hull()
	ship.faction = "BLUE"
	ship.callsign = "BLUE ship"
	ship.health = 100.0
	ship.weapons.append(fish)
	ship.magazines[fish.id] = 4
	var boat := Unit.new()
	boat.spec = _test_hull("subsurface")
	boat.faction = "RED"
	boat.callsign = "RED boat"
	boat.health = 100.0
	boat.position = Vector2(0, 1.6)
	boat.depth_m = 100.0
	var t := Track.new()
	t.id = "T2002"
	t.owner_faction = "BLUE"
	t.truth = boat
	t.position = boat.position
	t.position_error_nm = 0.2
	t.status = Track.Status.ACTIVE
	t.domain = "subsurface"
	t.identity = "HOSTILE"
	t.classification = Track.Classification.SURFACE
	var h := _harness([ship, boat])
	var ended: Array = []
	h.um.attack_ended.connect(func(_u: Unit, _t: Track, reason: String) -> void: ended.append(reason))
	assert_true(h.um.issue_order(ship, Order.attack(t)))
	var fired_at := [-1.0]
	for i in int(600.0 / DT):
		h.advance(DT)
		t.last_seen_time = h.now
		if ship.attack_rounds_fired > 0:
			fired_at[0] = ship.position.distance_to(boat.position)
			break
	assert_true(fired_at[0] > 0.0, "the ship opens and fires (ended: %s, phase '%s')" % [str(ended), ship.attack_phase])
	assert_true(fired_at[0] >= Combat.minimum_range_nm(fish), "from beyond the enable run and its margin (%.2f nm)" % fired_at[0])
	h.free_all()
