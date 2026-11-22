extends TestCase
## The catalogue as a naval reader would check it: shells on the missiles' damage scale, torpedoes
## that swim at torpedo speeds and arm before their minimum range, rocket-thrown weapons that fly,
## ships that carry the sonars they are built with and sound like what they are, and sonar ranges
## long enough for an anti-submarine fight to start outside gun range.


func _weapons(type: String) -> Array:
	return DataDB.all_weapons().filter(func(w: WeaponSpec) -> bool: return w.type == type)


func _unit(platform_id: String, faction := "RED") -> Unit:
	var u := Unit.new()
	u.spec = DataDB.platform(platform_id)
	u.faction = faction
	u.callsign = u.spec.short_name
	u.health = u.spec.health
	u.id = 1
	return u


# --- Guns -------------------------------------------------------------------------------------

## Calibre in millimetres of every gun in the catalogue. A new gun has to be entered here, which
## is the point: its damage is then checked against its calibre.
const GUN_CALIBRE_MM := {
	"mk45_mod4_gun": 127, "cw90_mk45": 127, "a192_130mm_gun": 130, "ak130_gun": 130, "cw90_ak130": 130,
	"pla_hpj45_130mm": 130, "mk8_114mm_gun": 114, "a190_100mm_gun": 100, "ak100_gun": 100, "cw90_ak100": 100,
	"oto_76mm_gun": 76, "cw90_mk75": 76, "cw90_ak176": 76, "pla_hpj26_76mm": 76, "mk110_57mm_gun": 57,
}


func test_gun_damage_is_on_the_missile_scale_by_calibre() -> void:
	var guns := _weapons("gun")
	assert_true(guns.size() >= 15, "the catalogue's guns are found")
	for w: WeaponSpec in guns:
		assert_true(GUN_CALIBRE_MM.has(w.id), "%s has a calibre entered for the damage check" % w.id)
		var mm := int(GUN_CALIBRE_MM.get(w.id, 0))
		if mm >= 127:
			assert_true(w.damage >= 2.0 and w.damage <= 3.0, "%s: a 127-130 mm shell does 2 to 3, not %.1f" % [w.id, w.damage])
		elif mm >= 76:
			assert_true(w.damage >= 1.0 and w.damage <= 2.2, "%s: a 76-114 mm shell does 1 to about 2, not %.1f" % [w.id, w.damage])
		else:
			assert_true(w.damage > 0.0 and w.damage < 1.0, "%s: a shell under 76 mm does less than 1, not %.1f" % [w.id, w.damage])
	# The scale is the anti-ship missiles': a 5-inch shell is a small fraction of a Harpoon.
	assert_true(DataDB.weapon("mk45_mod4_gun").damage * 12.0 <= DataDB.weapon("rgm_84_harpoon").damage, "twelve 5-inch hits do no more than one Harpoon")


func test_twenty_shell_hits_leave_a_destroyer_afloat() -> void:
	var gun := DataDB.weapon("mk45_mod4_gun")
	for trial in 40:
		Damage.rng.seed = 2000 + trial
		var burke := _unit("usn_ddg_arleigh_burke_iia")
		for hit in 20:
			Damage.apply(burke, gun.damage, gun.type, "BLUE")
		assert_true(burke.alive, "twenty 5-inch hits do not sink a Burke outright (seed %d)" % (2000 + trial))
		assert_true(Damage.health_fraction(burke) >= 0.5, "and leave it at least half its hull (%.2f)" % Damage.health_fraction(burke))
	Damage.rng.seed = 2100
	var six := _unit("usn_ddg_arleigh_burke_iia")
	for hit in 6:
		Damage.apply(six, gun.damage, gun.type, "BLUE")
	assert_true(Damage.health_fraction(six) >= 0.85, "six shells used to leave a Burke at 40 percent; now %.2f" % Damage.health_fraction(six))


func test_guns_that_bombard_may_be_laid_on_a_contact_ashore() -> void:
	var ashore := Track.new()
	ashore.domain = "land"
	for w: WeaponSpec in _weapons("gun"):
		var mm := int(GUN_CALIBRE_MM.get(w.id, 0))
		assert_true(w.target_types.has("surface"), "%s still engages ships" % w.id)
		assert_eq(Combat.suits_track(w, ashore), mm >= 100, "%s (%d mm) %s a contact ashore" % [w.id, mm, "suits" if mm >= 100 else "does not suit"])


# --- Torpedoes --------------------------------------------------------------------------------

func test_torpedo_decoy_resistance_follows_the_seeker_generation() -> void:
	var torpedoes := _weapons("torpedo")
	assert_true(torpedoes.size() >= 20, "the catalogue's torpedoes are found")
	for w: WeaponSpec in torpedoes:
		if w.seeker_band() != "acoustic":
			# A wake-homer follows the ship's wake; a noisemaker has almost nothing to offer it.
			assert_true(w.soft_kill_resistance >= 3.0, "%s does not listen, so a decoy barely touches it (%.2f)" % [w.id, w.soft_kill_resistance])
			continue
		assert_true(w.soft_kill_resistance >= 0.8, "%s: no seeker is easier to decoy than the scale's floor (%.2f)" % [w.id, w.soft_kill_resistance])
		var period := w.id.begins_with(DataDB.COLD_WAR_PREFIX) or w.id == "irn_test71me"
		if period:
			assert_true(w.soft_kill_resistance < 1.0, "%s is a 1980s seeker, below a current one (%.2f)" % [w.id, w.soft_kill_resistance])
		else:
			assert_true(w.soft_kill_resistance >= 1.0, "%s is a current seeker: 1.0 or more, not %.2f" % [w.id, w.soft_kill_resistance])
	for id: String in ["mk48_adcap", "spearfish", "f21_torpedo", "jmsdf_type18_torpedo"]:
		assert_true(DataDB.weapon(id).soft_kill_resistance > DataDB.weapon("cw90_mk48").soft_kill_resistance, "%s resists a decoy better than a 1980 Mk 48" % id)
	# What it means at sea: a towed decoy rated 0.30 used to pull a current heavyweight off 43
	# times in a hundred, and a wake-homer as often.
	var burke := DataDB.platform("usn_ddg_arleigh_burke_iia")
	assert_true(burke.towed_torpedo_decoy and burke.torpedo_decoy_effectiveness > 0.0, "the Burke tows a decoy")
	assert_true(TorpedoDefence.decoy_chance(burke, DataDB.weapon("ugst_torpedo")) <= burke.torpedo_decoy_effectiveness, "a current torpedo is seduced no more often than the decoy's own rating")
	assert_true(TorpedoDefence.decoy_chance(DataDB.platform("cw90_perry"), DataDB.weapon("cw90_53_65")) < 0.1, "a towed noisemaker hardly ever takes a wake-homer")
	assert_true(TorpedoDefence.decoy_chance(burke, DataDB.weapon("irn_53_65ke")) < 0.1, "nor the export wake-homer")


func test_no_torpedo_swims_faster_than_seventy_knots() -> void:
	for w: WeaponSpec in _weapons("torpedo"):
		assert_true(w.speed_kn <= 70.0, "%s swims at %.0f kn" % [w.id, w.speed_kn])
		assert_eq(w.profile, "subsurface", "%s runs under water" % w.id)
		assert_eq(w.delivery_payload_id, "", "%s is not also a rocket" % w.id)


func test_rocket_thrown_torpedoes_fly_out_and_drop_a_real_torpedo() -> void:
	var rockets := _weapons("asw_rocket")
	var ids := rockets.map(func(w: WeaponSpec) -> String: return w.id)
	for id: String in ["rastrub_asw", "cw90_rastrub", "pla_yu8", "rgm_139_vla", "jmsdf_type07_vla"]:
		assert_true(ids.has(id), "%s is a rocket-thrown weapon, not a swimming torpedo" % id)
	for w: WeaponSpec in rockets:
		assert_true(w.speed_kn >= 500.0 and w.speed_kn <= 700.0, "%s flies at about the speed of sound (%.0f kn)" % [w.id, w.speed_kn])
		assert_eq(w.profile, "high", "%s flies" % w.id)
		assert_true(w.altitude_m > 0.0, "%s flies above the sea" % w.id)
		assert_eq(Array(w.target_types), ["subsurface"], "%s is an anti-submarine weapon" % w.id)
		var payload := DataDB.weapon(w.delivery_payload_id)
		assert_true(payload != null and payload.is_torpedo(), "%s carries a torpedo the catalogue holds" % w.id)
		if payload == null:
			continue
		assert_eq(payload.seeker_band(), "acoustic", "%s's torpedo listens, so a decoy has its chance" % w.id)
		assert_true(payload.target_types.has("subsurface"), "%s's torpedo hunts submarines" % w.id)
		assert_eq(w.id.begins_with(DataDB.COLD_WAR_PREFIX), payload.id.begins_with(DataDB.COLD_WAR_PREFIX), "%s carries a torpedo of its own period" % w.id)


func _shooter(weapon: WeaponSpec) -> Unit:
	var u := Unit.new()
	u.spec = PlatformSpec.new()
	u.spec.vls_cells = 32
	u.spec.has_datalink = true
	u.faction = "RED"
	u.health = 100.0
	u.weapons.append(weapon)
	u.magazines[weapon.id] = 8
	return u


func test_a_rastrub_reaches_fifteen_miles_through_the_air_in_under_two_minutes() -> void:
	for id: String in ["cw90_rastrub", "rastrub_asw", "pla_yu8"]:
		Terrain.clear()
		var rocket := DataDB.weapon(id)
		var u := _shooter(rocket)
		var wm := WeaponManager.new()
		wm.unit_manager = UnitManager.new()
		wm.unit_manager.add_unit(u)
		var t := Track.new()
		t.id = "T1"
		t.owner_faction = "RED"
		t.identity = "HOSTILE"
		t.domain = "subsurface"
		t.position = Vector2(0, 15)
		assert_true(wm.launch(u, rocket, t, 1, 0.0), "%s fires on a submarine plot at 15 nm" % id)
		var w: Weapon = wm.in_flight[0]
		assert_eq(w.threat_class(), "missile", "%s leaves as a missile in the air" % id)
		assert_true(w.flight_altitude_m() > 0.0, "%s is above the sea on the way out" % id)
		var entered := -1.0
		var now := 0.0
		while now < 200.0 and entered < 0.0:
			now += 0.25
			wm.tick(0.25, now)
			if w.delivery_spec != null:
				entered = now
		assert_true(entered > 0.0 and entered < 120.0, "%s is over the datum in under two minutes (%.0f s); swimming there took a quarter of an hour" % [id, entered])
		assert_true(w.position.distance_to(Vector2(0, 15)) < 0.5, "%s puts its torpedo in the water at the datum" % id)
		assert_eq(w.spec.id, rocket.delivery_payload_id, "what swims from there is the carried torpedo")
		assert_true(w.speed_nm_per_s() <= Geo.knots_to_nm_per_s(70.0), "at a torpedo's speed")
		wm.clear()
		wm.unit_manager.free()
		wm.free()


# --- Definitions nothing uses -----------------------------------------------------------------

## Every "loadout" a mission gives a unit or an embarked aircraft, wherever it sits in the file.
func _collect_loadouts(node: Variant, used: Dictionary) -> void:
	if node is Dictionary:
		for key in node:
			if key == "loadout" and node[key] is Dictionary:
				for wid in node[key]:
					used[wid] = true
			else:
				_collect_loadouts(node[key], used)
	elif node is Array:
		for item in node:
			_collect_loadouts(item, used)


func test_every_weapon_and_sensor_definition_is_carried_by_something() -> void:
	var used := {}
	for p: PlatformSpec in DataDB.all_platforms():
		for wid in p.weapon_loadout:
			used[wid] = true
		for sid in p.sensor_ids:
			used[sid] = true
	for name in ResourceLoader.list_directory("res://data/scenarios"):
		if not name.ends_with(".json"):
			continue
		_collect_loadouts(ScenarioLoader.load_file("res://data/scenarios/" + name), used)
	for w: WeaponSpec in DataDB.all_weapons():
		if w.delivery_payload_id != "":
			used[w.delivery_payload_id] = true
	for w: WeaponSpec in DataDB.all_weapons():
		assert_true(used.has(w.id), "%s is carried by a platform, loaded in a mission or delivered by a rocket" % w.id)
	for name in ResourceLoader.list_directory("res://data/sensors"):
		var id := name.get_basename()
		assert_true(used.has(id), "sensor %s is fitted to a platform" % id)
	for gone: String in ["agm_158b_jassm_er", "jsm_missile", "kh38_family", "aim9x_family"]:
		assert_true(DataDB.weapon(gone) == null, "%s is no longer defined" % gone)
	assert_eq(int(DataDB.platform("usaf_fighter_f16c").weapon_loadout.get("aim9x_air", 0)), 2, "the F-16C carries the same Sidewinder as the Navy's jets")


# --- Minimum range and the enable run ---------------------------------------------------------

func test_no_torpedo_may_be_fired_inside_its_enable_run() -> void:
	for w: WeaponSpec in _weapons("torpedo"):
		assert_true(w.run_to_enable_nm > 0.0, "%s has an enable run" % w.id)
		if w.target_types.has("torpedo"):
			# An anti-torpedo round is fired at something a few hundred yards off and closing.
			assert_true(w.min_range_nm >= w.run_to_enable_nm, "%s: minimum range %.1f is not inside its %.1f nm enable run" % [w.id, w.min_range_nm, w.run_to_enable_nm])
			continue
		assert_true(w.min_range_nm >= w.run_to_enable_nm + 0.25, "%s: minimum range %.1f leaves the seeker a look after its %.1f nm enable run" % [w.id, w.min_range_nm, w.run_to_enable_nm])
		assert_true(w.max_range_nm > w.min_range_nm * 3.0, "%s keeps a usable envelope" % w.id)


func _target(domain: String, at: Vector2) -> Unit:
	var u := Unit.new()
	u.spec = PlatformSpec.new()
	u.spec.domain = domain
	u.spec.health = 100.0
	u.spec.max_speed_kn = 20.0
	u.spec.max_depth_m = 300.0
	u.faction = "RED"
	u.health = 100.0
	u.position = at
	u.depth_m = 100.0 if domain == "subsurface" else 0.0
	return u


## The shot the audit made: a Mk 48 fired at a boat seven cables off ran blind past it and on
## for its whole range. The shortest shot the fire control now accepts finds its target.
func test_the_shortest_accepted_torpedo_shot_acquires_its_target() -> void:
	var old_shot := Track.new()
	old_shot.domain = "subsurface"
	old_shot.position = Vector2(0, 0.7)
	for id: String in ["cw90_mk48", "mk48_adcap", "spearfish", "pla_yu6", "ugst_torpedo", "jmsdf_type18_torpedo"]:
		var blue := _shooter(DataDB.weapon(id))
		blue.faction = "BLUE"
		assert_eq(Combat.check_engagement(blue, DataDB.weapon(id), old_shot)["reason"], "TOO CLOSE", "%s is refused at 0.7 nm, inside its enable run" % id)
	for w: WeaponSpec in _weapons("torpedo"):
		if w.target_types.has("torpedo"):
			continue
		Terrain.clear()
		var domain := "subsurface" if w.target_types.has("subsurface") else "surface"
		var u := _shooter(w)
		u.faction = "BLUE"
		var boat := _target(domain, Vector2(0, w.min_range_nm + 0.01))  # clear of the rounding at the limit itself
		var wm := WeaponManager.new()
		wm.unit_manager = UnitManager.new()
		wm.unit_manager.add_unit(u)
		wm.unit_manager.add_unit(boat)
		var t := Track.new()
		t.id = "T1"
		t.owner_faction = "BLUE"
		t.identity = "HOSTILE"
		t.domain = domain
		t.position = boat.position
		assert_true(wm.launch(u, w, t, 1, 0.0), "%s fires at its minimum range of %.1f nm" % [w.id, w.min_range_nm])
		if wm.in_flight.is_empty():
			wm.unit_manager.free()
			wm.free()
			continue
		var round: Weapon = wm.in_flight[0]
		var acquired := false
		var now := 0.0
		while now < 240.0 and round.phase != Weapon.Phase.DEAD and not acquired:
			now += 0.25
			wm.tick(0.25, now)
			acquired = round.acquired == boat
		assert_true(acquired, "%s fired at %.1f nm has its seeker on before it reaches the target" % [w.id, w.min_range_nm])
		wm.clear()
		wm.unit_manager.free()
		wm.free()
