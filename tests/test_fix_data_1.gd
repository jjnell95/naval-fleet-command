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
	for gone: String in ["agm_158b_jassm_er", "jsm_missile", "kh38_family"]:
		assert_true(DataDB.weapon(gone) == null, "%s is no longer defined" % gone)
	assert_true(not DataDB.all_weapons().any(func(w: WeaponSpec) -> bool: return w.id == "aim9x_family"), "the second AIM-9X is no longer in the catalogue")
	# A fighter in an engagement saved before the fold still names the old id.
	assert_eq(DataDB.weapon("aim9x_family"), DataDB.weapon("aim9x_air"), "a saved reference to the old id finds the one Sidewinder")
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


# --- Sonars, signatures and what is heard at what range ---------------------------------------

## A catalogue unit under way, with its sensors fitted and nothing streamed or dipped.
func _afloat(platform_id: String, speed_kn: float) -> Unit:
	var u := _unit(platform_id, "BLUE")
	u.speed_kn = speed_kn
	u.depth_m = 100.0 if u.spec.domain == "subsurface" else 0.0
	for sid in u.spec.sensor_ids:
		u.sensors.append(DataDB.sensor(sid))
	return u


## The same unit listening on its best ears: towed array streamed and quiet, dipping set wet.
func _listening(platform_id: String, speed_kn: float) -> Unit:
	var u := _afloat(platform_id, speed_kn)
	u.array_phase = TowedArray.Phase.LISTENING
	if u.spec.can_hover:
		u.flight_state = Unit.FlightState.AIRBORNE
		u.altitude_m = 20.0
		u.dip_phase = DippingSonar.Phase.LISTENING
	return u


func _is_hull_sonar(s: SensorSpec) -> bool:
	return s != null and s.kind == "sonar" and not s.requires_hover and s.array_depth_m <= 0.0


func _surface_ships() -> Array:
	return DataDB.all_platforms().filter(func(p: PlatformSpec) -> bool: return p.domain == "surface")


## Direct-path passive range, the figure Detection gives before the water column has its say.
func _hears_at(listener: Unit, sensor_id: String, target_id: String, target_kn: float) -> float:
	var target := _afloat(target_id, target_kn)
	target.position = listener.position + Vector2(0, 5)
	return Detection.passive_sonar_range_nm(listener, DataDB.sensor(sensor_id), target, false)


## Escorts whose only sonar in service is a variable-depth or towed set, so they have no hull
## sonar to list. Any other destroyer, frigate or cruiser without one is a catalogue error.
const NO_HULL_SONAR_IN_SERVICE := ["usn_ffg_constellation", "jmsdf_ffm_mogami"]


func test_escorts_carry_the_hull_sonars_they_are_built_with() -> void:
	Detection.set_environment({})
	var torpedo := DataDB.weapon("irn_test71me")
	for id: String in ["rn_ddg_type45", "fra_ffg_fremm", "rfn_ffg_admiral_gorshkov", "rfn_fsg_steregushchiy", "dnk_ffg_iver_huitfeldt", "irn_ffg_alvand", "rn_ffg_type26", "rnon_ffg_fridtjof_nansen"]:
		var ship := _afloat(id, 12.0)
		assert_true(ship.sensors.any(_is_hull_sonar), "%s has a hull sonar" % id)
		# With nothing streamed, at a patrol speed: the warning a torpedo-defence drill starts from.
		assert_true(Detection.torpedo_detection_nm(ship, torpedo) >= 4.0, "%s hears a running torpedo at four miles or more (%.1f)" % [id, Detection.torpedo_detection_nm(ship, torpedo)])
	for p: PlatformSpec in _surface_ships():
		if not p.category in ["destroyer", "frigate", "cruiser"] or NO_HULL_SONAR_IN_SERVICE.has(p.id):
			continue
		var fitted := Array(p.sensor_ids).map(func(sid: String) -> SensorSpec: return DataDB.sensor(sid))
		assert_true(fitted.any(_is_hull_sonar), "%s (%s) has a hull sonar" % [p.id, p.category])
	# A surface ship carries a surface ship's sonar: the Kilo's suite used to be listed for a
	# cruiser and a destroyer.
	var submarine_suites := {}
	for p: PlatformSpec in DataDB.all_platforms():
		if p.domain == "subsurface":
			for sid in p.sensor_ids:
				submarine_suites[sid] = p.id
	for p: PlatformSpec in _surface_ships():
		for sid in p.sensor_ids:
			assert_true(not submarine_suites.has(sid), "%s does not carry %s, a submarine's sonar suite" % [p.id, sid])


func test_surface_ships_sound_like_what_they_are() -> void:
	var values := {}
	for p: PlatformSpec in _surface_ships():
		assert_true(p.acoustic_signature > 0.0 and p.acoustic_signature <= 0.5, "%s has its own radiated noise, not the default (%.2f)" % [p.id, p.acoustic_signature])
		values[p.acoustic_signature] = true
	assert_true(values.size() >= 12, "surface ships are spread over many noise levels, not one (%d)" % values.size())
	# Quiet by design, then ordinary warships, then the loud ones; small craft under them all.
	for chain: Array in [
		["rn_ffg_type26", "usn_ddg_arleigh_burke_iia", "rfn_cg_slava", "usn_cvn_nimitz"],
		["fra_ffg_fremm", "rn_ddg_type45", "rfn_ddg_udaloy", "rn_cvf_queen_elizabeth"],
		["cw90_spruance", "cw90_udaloy", "cw90_sovremenny", "cw90_nimitz"],
		["irn_fac_peykaap3", "pla_pgg_type022", "pla_fsg_type056a", "pla_ddg_type052d", "pla_cv_shandong"],
		["civ_fishing_trawler", "civ_merchant_bulk", "civ_tanker_vlcc"],
	]:
		for i in range(1, chain.size()):
			assert_true(DataDB.platform(chain[i - 1]).acoustic_signature < DataDB.platform(chain[i]).acoustic_signature, "%s is quieter than %s" % [chain[i - 1], chain[i]])
	# What a submarine makes of it, each at the speed it goes about its business.
	Detection.set_environment({})
	var boat := _listening("usn_ssn_virginia", 5.0)
	var trawler := _hears_at(boat, "an_bqq_10", "civ_fishing_trawler", 8.0)
	var frigate := _hears_at(boat, "an_bqq_10", "rn_ffg_type26", 12.0)
	var destroyer := _hears_at(boat, "an_bqq_10", "usn_ddg_arleigh_burke_iia", 16.0)
	var carrier := _hears_at(boat, "an_bqq_10", "usn_cvn_nimitz", 20.0)
	var tanker := _hears_at(boat, "an_bqq_10", "civ_tanker_vlcc", 13.0)
	assert_true(trawler < frigate and frigate < destroyer and destroyer < carrier and carrier < tanker, "trawler %.0f < quiet frigate %.0f < destroyer %.0f < carrier %.0f < tanker %.0f nm" % [trawler, frigate, destroyer, carrier, tanker])
	assert_true(_hears_at(boat, "an_bqq_10", "irn_fac_peykaap3", 40.0) < frigate, "a speedboat flat out is heard nearer than a frigate")
	assert_true(tanker > 2.5 * trawler, "a tanker is heard much further off than a trawler: they used to be the same")


func test_sonar_families_keep_their_order() -> void:
	var users := {}
	for p: PlatformSpec in DataDB.all_platforms():
		for sid in p.sensor_ids:
			users[sid] = p
	var quietest_suite := INF
	for sid: String in users:
		var s := DataDB.sensor(sid)
		var p: PlatformSpec = users[sid]
		if s.kind != "sonar":
			continue
		if p.domain == "subsurface" and p.category != "midget submarine":
			assert_true(s.passive_sensitivity_nm >= 36.0 and s.passive_sensitivity_nm <= 60.0, "%s: a submarine's suite is the long ears (%.0f)" % [sid, s.passive_sensitivity_nm])
			quietest_suite = minf(quietest_suite, s.passive_sensitivity_nm)
		elif s.requires_hover:
			assert_true(s.passive_sensitivity_nm <= 18.0, "%s: a dipping transducer is a small array (%.0f)" % [sid, s.passive_sensitivity_nm])
			assert_true(s.active_range_nm >= 9.0, "%s: its strength is its ping (%.0f)" % [sid, s.active_range_nm])
		elif p.domain == "surface" and s.array_depth_m > 0.0:
			assert_true(s.passive_sensitivity_nm >= 26.0 and s.passive_sensitivity_nm <= 46.0, "%s: a towed or variable-depth array hears far (%.0f)" % [sid, s.passive_sensitivity_nm])
		elif p.domain == "surface":
			assert_true(s.passive_sensitivity_nm >= 9.0 and s.passive_sensitivity_nm <= 15.0, "%s: a hull set stays short (%.0f)" % [sid, s.passive_sensitivity_nm])
	assert_true(DataDB.sensor("an_aqs_22").passive_sensitivity_nm < DataDB.sensor("an_bqq_10").passive_sensitivity_nm * 0.5, "a dipping set no longer out-ranges a submarine's bow array")
	assert_true(quietest_suite < INF, "submarine suites were found")


## The range table, direct path, calm sea: [listener, its speed, sensor, target, its speed, nm].
const RANGE_TABLE := [
	["cw90_los_angeles", 5.0, "cw90_bqq5", "cw90_victor3", 5.0, 13.2],
	["cw90_los_angeles", 5.0, "cw90_bqq5", "cw90_victor3", 10.0, 16.7],
	["cw90_los_angeles", 5.0, "cw90_bqq5", "cw90_victor3", 15.0, 21.3],
	["cw90_victor3", 5.0, "cw90_mgk400", "cw90_los_angeles", 5.0, 7.4],
	["cw90_spruance", 8.0, "cw90_sqr19", "cw90_victor3", 5.0, 11.1],
	["cw90_spruance", 10.0, "cw90_sqs53b", "cw90_victor3", 5.0, 3.2],
	["usn_ssn_virginia", 5.0, "an_bqq_10", "rfn_ssk_kilo", 4.0, 8.3],
	["usn_ssn_virginia", 5.0, "an_bqq_10", "rfn_ssn_yasen_m", 8.0, 11.4],
	["usn_ssn_virginia", 5.0, "an_bqq_10", "pla_ssn_type093b", 8.0, 17.3],
	["rfn_ssk_kilo", 4.0, "mgk_400em", "usn_ssn_virginia", 8.0, 8.2],
	["rn_ffg_type26", 8.0, "sonar_2087", "rfn_ssk_kilo", 4.0, 6.2],
	["usn_ddg_arleigh_burke_iia", 10.0, "an_sqs_53c", "rfn_ssk_kilo", 4.0, 1.6],
	["rn_ddg_type45", 12.0, "sonar_2091", "cw90_victor3", 5.0, 2.1],
	["usn_helo_mh60r", 0.0, "an_aqs_22", "rfn_ssk_kilo", 4.0, 2.6],
	["usn_ssn_virginia", 5.0, "an_bqq_10", "usn_ddg_arleigh_burke_iia", 16.0, 44.5],
	["usn_ssn_virginia", 5.0, "an_bqq_10", "civ_tanker_vlcc", 13.0, 88.7],
	["cw90_victor3", 5.0, "cw90_mgk400", "cw90_merchant", 14.0, 43.8],
]


func test_the_passive_range_table() -> void:
	Detection.set_environment({})
	for row: Array in RANGE_TABLE:
		var listener := _listening(row[0], row[1])
		var got := _hears_at(listener, row[2], row[3], row[4])
		assert_near(got, row[5], maxf(0.15, float(row[5]) * 0.02), "%s on %s at %d kn hears %s at %d kn" % [row[0], row[2], int(row[1]), row[3], int(row[4])])
	# What the table is for: a submarine holds a nuclear boat of the last generation at ten miles
	# and more, where it used to be five, and a hull set still has to be on top of one.
	var la := _listening("cw90_los_angeles", 5.0)
	assert_true(_hears_at(la, "cw90_bqq5", "cw90_victor3", 5.0) >= 10.0, "a Los Angeles holds a Victor III at patrol speed beyond ten miles")
	var spruance := _listening("cw90_spruance", 10.0)
	assert_true(_hears_at(spruance, "cw90_sqs53b", "cw90_victor3", 5.0) <= 4.0, "a hull sonar hears the same boat inside four")


func test_a_convergence_zone_can_be_heard() -> void:
	# The barrier mission's water: zones every 30 miles, sea state 4.
	Detection.set_environment({"sea_state": 4, "cz_range_nm": 30.0})
	var la := _listening("cw90_los_angeles", 5.0)
	var sensor := DataDB.sensor("cw90_bqq5")
	assert_true(sensor.cz_capable, "the BQQ-5 works the zones")
	var transiting := _hears_at(la, "cw90_bqq5", "cw90_victor3", 10.0)
	assert_true(not Acoustics.cz_zone_for(sensor, 30.0, transiting).is_empty(), "a Victor III transiting at 10 kn is heard in the first zone (direct reach %.1f nm)" % transiting)
	var creeping := _hears_at(la, "cw90_bqq5", "rfn_ssk_kilo", 3.0)
	assert_true(Acoustics.cz_zone_for(sensor, 30.0, creeping).is_empty(), "a creeping diesel boat is not (direct reach %.1f nm)" % creeping)
	var hull := DataDB.sensor("cw90_sqs56")
	assert_true(Acoustics.cz_zone_for(hull, 30.0, 40.0).is_empty(), "a small hull set never works the zones")
	Detection.set_environment({})


# --- Radar against small things ---------------------------------------------------------------

## How far a lookout recognises a ship or a boat (SensorManager._visual_pass), and a periscope.
const LOOKOUT_NM := 6.0


func _radar_reach_nm(observer: Unit, signature: float, target_height_m: float) -> float:
	return Detection.best_radar_range_nm(observer, signature, target_height_m) * Detection.clutter_factor(signature)


func test_a_warship_radar_sees_a_boat_further_than_its_lookouts() -> void:
	var boats := ["irn_fac_peykaap3", "irn_pgg_houdong", "pla_pgg_type022", "civ_fishing_trawler"]
	for sea_state in [0, 2, 4]:
		Detection.set_environment({"sea_state": sea_state})
		for p: PlatformSpec in _surface_ships():
			if p.weapon_loadout.is_empty() or p.displacement_t < 500.0 or p.category in ["merchant", "auxiliary"]:
				continue
			var ship := _afloat(p.id, 12.0)
			ship.radar_on = true
			for boat_id: String in boats:
				var boat := DataDB.platform(boat_id)
				var reach := _radar_reach_nm(ship, boat.signature_factor, boat.mast_height_m)
				assert_true(reach >= LOOKOUT_NM - 0.01, "%s radar holds a %s at %.1f nm in sea state %d; a lookout sees it at %.0f" % [p.id, boat_id, reach, sea_state, LOOKOUT_NM])
	Detection.set_environment({})
	var burke := _afloat("usn_ddg_arleigh_burke_iia", 12.0)
	burke.radar_on = true
	var peykaap := DataDB.platform("irn_fac_peykaap3")
	assert_true(_radar_reach_nm(burke, peykaap.signature_factor, peykaap.mast_height_m) >= 9.0, "an Aegis destroyer holds a speedboat at nine miles, not under five")


func test_the_seahawk_radar_finds_a_periscope_before_an_eye_does() -> void:
	for sea_state in [0, 3]:
		Detection.set_environment({"sea_state": sea_state})
		var helo := _afloat("usn_helo_mh60r", 100.0)
		helo.flight_state = Unit.FlightState.AIRBORNE
		helo.altitude_m = 300.0
		helo.radar_on = true
		var signature := DataDB.platform("rfn_ssk_kilo").signature_factor * Detection.RADAR_PERISCOPE_SIGNATURE
		var by_radar := _radar_reach_nm(helo, signature, SensorManager.PERISCOPE_HEIGHT_M)
		var by_eye := SensorManager.PERISCOPE_SIGHTING_NM * clampf(1.0 - 0.12 * sea_state, 0.25, 1.0)
		assert_true(by_radar >= by_eye, "sea state %d: the radar holds a periscope at %.2f nm, a lookout at %.2f" % [sea_state, by_radar, by_eye])
	Detection.set_environment({})
	assert_true(DataDB.sensor("an_aps_153").range_surface_nm >= DataDB.sensor("cw90_aps124").range_surface_nm, "the Romeo's radar is no worse than the Seahawk radar of 1990")
