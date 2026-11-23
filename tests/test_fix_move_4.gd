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

