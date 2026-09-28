extends TestCase
## Ship weapon fits. Loadouts are catalogue data, so this checks them the way a reviewer would:
## a few things that must hold for every hull, the corrections made to specific classes, and the
## hulls that are thin in service and are deliberately left that way. A fit is only worth having
## if the hull can use it, so the last group fires the new rounds through the real engagement
## check.


func _platform(id: String) -> PlatformSpec:
	var p := DataDB.platform(id)
	assert_true(p != null, "%s loads" % id)
	return p


## The farthest reach among a hull's weapons of one type, 0 when it carries none.
func _reach(p: PlatformSpec, type: String) -> float:
	var best := 0.0
	for wid in p.weapon_loadout:
		var w := DataDB.weapon(wid)
		if w != null and w.type == type:
			best = maxf(best, w.max_range_nm)
	return best


func _carries_type(p: PlatformSpec, type: String) -> bool:
	for wid in p.weapon_loadout:
		var w := DataDB.weapon(wid)
		if w != null and w.type == type:
			return true
	return false


func _rounds(p: PlatformSpec, weapon_ids: Array) -> int:
	var n := 0
	for wid in weapon_ids:
		n += int(p.weapon_loadout.get(wid, 0))
	return n


# --- Holds for every hull -----------------------------------------------------------------

func test_a_ship_that_carries_guided_interceptors_can_guide_them() -> void:
	# Automatic defence only launches a guided round while the ship has a free fire-control
	# channel, so a hull with missiles and no channels carries dead weight.
	for p: PlatformSpec in DataDB.all_platforms():
		if p.domain != "surface":
			continue
		if _carries_type(p, "sam"):
			assert_true(p.fire_control_channels >= 1, "%s carries SAMs and must have a fire-control channel" % p.id)


func test_major_combatants_carry_an_interceptor() -> void:
	for p: PlatformSpec in DataDB.all_platforms():
		if p.domain != "surface" or not (p.category in ["cruiser", "destroyer", "frigate"]):
			continue
		var has := false
		for wid in p.weapon_loadout:
			var w := DataDB.weapon(wid)
			if w != null and w.is_interceptor():
				has = true
		assert_true(has, "%s is a major combatant and carries something that shoots at missiles" % p.id)


func test_every_loadout_round_resolves_and_is_positive() -> void:
	for p: PlatformSpec in DataDB.all_platforms():
		for wid in p.weapon_loadout:
			assert_true(DataDB.weapon(wid) != null, "%s carries a weapon that exists: %s" % [p.id, wid])
			assert_true(int(p.weapon_loadout[wid]) > 0, "%s magazine for %s is usable" % [p.id, wid])


# --- Corrections --------------------------------------------------------------------------

func test_burkes_have_reach_beyond_the_gun() -> void:
	# Two Burkes (one each in the Gulf and Spratly operations) used to have Tomahawk patched in by hand;
	# the other fourteen had nothing past 13 nm to strike with.
	for id in ["usn_ddg_arleigh_burke_iia", "usn_ddg_burke_iii"]:
		var p := _platform(id)
		if p == null:
			continue
		assert_true(p.weapon_loadout.has("tomahawk_block_v"), "%s carries Tomahawk" % id)
		assert_true(_reach(p, "asm") >= 200.0, "%s can strike far beyond its gun" % id)
		assert_true(not p.weapon_loadout.has("rgm_84_harpoon"), "%s still carries no Harpoon" % id)
		assert_true(p.occupied_vls_cells() <= p.vls_cells, "%s missile fit stays inside its cells" % id)


func test_american_and_british_attack_submarines_carry_cruise_missiles_and_torpedoes() -> void:
	var virginia := _platform("usn_ssn_virginia")
	if virginia != null:
		assert_true(_carries_type(virginia, "torpedo"), "Virginia keeps her torpedo room")
		assert_eq(int(virginia.weapon_loadout.get("tomahawk_block_v", 0)), 12, "twelve payload-tube Tomahawk")
		assert_eq(virginia.vls_cells, 12, "the payload tubes are the cells")
		assert_true(virginia.occupied_vls_cells() <= virginia.vls_cells)
	var astute := _platform("rn_ssn_astute")
	if astute != null:
		assert_true(astute.weapon_loadout.has("spearfish") and astute.weapon_loadout.has("tomahawk_block_v"))
		assert_true(_rounds(astute, ["spearfish", "tomahawk_block_v"]) <= 38, "inside the six-tube boat's 38-weapon stowage")


func test_only_the_improved_kilo_carries_kalibr() -> void:
	var improved := _platform("rfn_ssk_kilo")
	if improved != null:
		assert_eq(int(improved.weapon_loadout.get("kalibr_asm", 0)), 4, "four Kalibr through two of the six tubes")
		assert_true(_carries_type(improved, "torpedo"))
	for id in ["rfn_ssk_kilo_877", "irn_ssk_kilo_877ekm"]:
		var p := _platform(id)
		if p != null:
			assert_true(not _carries_type(p, "asm"), "%s is the Project 877 family and carries no cruise missile" % id)


func test_suffren_mixes_heavyweight_torpedoes_with_anti_ship_missiles() -> void:
	var p := _platform("fra_ssn_suffren")
	if p == null:
		return
	assert_true(p.weapon_loadout.has("f21_torpedo") and p.weapon_loadout.has("sm39_exocet"))
	assert_true(_rounds(p, ["f21_torpedo", "sm39_exocet"]) <= 20, "inside the twenty stowage racks")
	assert_true(not p.weapon_loadout.has("mm40_exocet"), "the surface-launched round is not what a boat fires")


func test_iver_huitfeldt_has_a_close_in_layer_and_her_torpedo_launchers() -> void:
	var p := _platform("dnk_ffg_iver_huitfeldt")
	if p == null:
		return
	assert_true(p.weapon_loadout.has("millennium_35mm"), "the 35 mm CIWS is a permanent fit")
	assert_true(p.weapon_loadout.has("mu90"), "the twin MU90 launchers are a permanent fit")
	assert_eq(int(p.weapon_loadout.get("rgm_84_harpoon", 0)), 16, "two eight-cell Harpoon modules")
	var layers := {}
	for wid in p.weapon_loadout:
		var w := DataDB.weapon(wid)
		if w != null and w.is_interceptor():
			layers[w.defensive_layer()] = true
	assert_true(layers.has("close_in") and layers.size() >= 2, "a close-in layer as well as her missile layers, not one")


func test_visby_carries_her_anti_ship_missiles() -> void:
	var p := _platform("swe_fsg_visby")
	if p != null:
		assert_eq(int(p.weapon_loadout.get("rbs15_mk3", 0)), 8, "two four-round launchers")
		assert_true(_reach(p, "asm") >= 60.0, "a corvette that can strike further than its gun")


# --- Thin in service, thin here ------------------------------------------------------------

func test_hulls_that_are_thin_in_service_are_not_given_hardware_they_lack() -> void:
	# Each of these was looked at and left alone on purpose. Public sources agree that they carry
	# what the data says, and inventing a missile for them would be a fiction, not a correction.
	var qe := _platform("rn_cvf_queen_elizabeth")
	if qe != null:
		assert_true(not _carries_type(qe, "sam"), "Queen Elizabeth has no missile defence of her own; her escorts provide it")
		assert_true(_carries_type(qe, "ciws"), "she carries Phalanx")
	var juan_carlos := _platform("esp_lhd_juan_carlos_i")
	if juan_carlos != null:
		assert_true(juan_carlos.weapon_loadout.is_empty(), "Juan Carlos I carries light guns only, which the game has no mount for")
	var type26 := _platform("rn_ffg_type26")
	if type26 != null:
		assert_true(not _carries_type(type26, "asm"), "no surface anti-ship missile is procured for the Type 26 yet")
	var nansen := _platform("rnon_ffg_fridtjof_nansen")
	if nansen != null:
		assert_true(not _carries_type(nansen, "ciws"), "Nansen has no close-in weapon")


# --- The hulls can use what they carry ------------------------------------------------------

func _shooter(id: String, at_depth_m := 0.0) -> Unit:
	var u := Unit.new()
	u.spec = DataDB.platform(id)
	u.faction = "BLUE"
	u.callsign = "Test"
	u.health = u.spec.health
	u.depth_m = at_depth_m
	for wid in u.spec.weapon_loadout:
		var w := DataDB.weapon(wid)
		u.weapons.append(w)
		u.magazines[wid] = int(u.spec.weapon_loadout[wid])
	return u


func _surface_track(distance_nm: float) -> Track:
	var t := Track.new()
	t.id = "T1001"
	t.owner_faction = "BLUE"
	t.position = Vector2(0.0, distance_nm)
	t.status = Track.Status.ACTIVE
	t.domain = "surface"
	t.identity = "HOSTILE"
	return t


func test_submarines_can_fire_their_missiles_at_a_surface_track_from_periscope_depth() -> void:
	Terrain.clear()
	for case: Array in [["fra_ssn_suffren", "sm39_exocet", 25.0], ["rfn_ssk_kilo", "kalibr_asm", 60.0], ["usn_ssn_virginia", "tomahawk_block_v", 150.0], ["rn_ssn_astute", "tomahawk_block_v", 150.0]]:
		var u := _shooter(case[0], 10.0)
		var w := DataDB.weapon(case[1])
		var check := Combat.check_engagement(u, w, _surface_track(case[2]))
		assert_true(check["ok"], "%s can fire %s at %d nm: %s" % [case[0], case[1], int(case[2]), check["reason"]])


func test_a_submarine_missile_is_not_offered_against_the_wrong_domain() -> void:
	Terrain.clear()
	var u := _shooter("fra_ssn_suffren", 10.0)
	var air := _surface_track(20.0)
	air.domain = "air"
	assert_true(not Combat.check_engagement(u, DataDB.weapon("sm39_exocet"), air)["ok"], "an anti-ship missile does not engage an aircraft")


func test_the_new_close_in_mount_engages_a_sea_skimmer_but_not_a_torpedo() -> void:
	var mount := DataDB.weapon("millennium_35mm")
	assert_true(mount != null and mount.is_interceptor() and mount.type == "ciws", "it is a close-in interceptor")
	assert_eq(mount.defensive_layer(), "close_in")
	var skimmer := Weapon.new()
	skimmer.spec = DataDB.weapon("rgm_84_harpoon")
	assert_true(AirDefence._can_intercept(mount, skimmer), "it engages an anti-ship missile")
	var torpedo := Weapon.new()
	torpedo.spec = DataDB.weapon("mu90")
	assert_true(not AirDefence._can_intercept(mount, torpedo), "a torpedo cannot be shot down")


func test_the_new_weapons_are_labelled_estimates_and_have_a_usable_envelope() -> void:
	for wid in ["millennium_35mm", "sm39_exocet"]:
		var w := DataDB.weapon(wid)
		assert_true(w != null, "%s loads" % wid)
		if w == null:
			continue
		assert_true(w.source_status.contains("GAMEPLAY_ESTIMATE"), "%s labels its numbers as estimates" % wid)
		assert_true(w.max_range_nm > w.min_range_nm and w.speed_kn > 0.0 and w.damage > 0.0, "%s has a usable envelope" % wid)
		var fitted := false
		for p: PlatformSpec in DataDB.all_platforms():
			if p.weapon_loadout.has(wid):
				fitted = true
		assert_true(fitted, "%s is fitted to a platform" % wid)
