extends TestCase
## Installations ashore: a coastal battery that shoots from its hill, a missile site that defends
## a coast, and the strike weapons that can reach them across the beach.

const ISLAND := {"id": "test_island", "name": "Test Island", "elevation_m": 300.0,
	"points_nm": [[-5, -5], [5, -5], [5, 5], [-5, 5]]}
const DT := 0.25


func _land(list: Array) -> void:
	Terrain.load_from({"terrain": {"land": list}})


func _hull(hp := 100.0) -> PlatformSpec:
	var p := PlatformSpec.new()
	p.id = "test_ffg"
	p.short_name = "FFG Test"
	p.max_speed_kn = 28.0
	p.cruise_speed_kn = 14.0
	p.health = hp
	p.mast_height_m = 25.0
	p.fire_control_channels = 4
	return p


func _site(hp := 60.0) -> PlatformSpec:
	var p := PlatformSpec.new()
	p.id = "test_battery"
	p.short_name = "Battery Test"
	p.domain = "land"
	p.category = "coastal missile battery"
	p.max_speed_kn = 0.0
	p.health = hp
	p.mast_height_m = 30.0
	p.signature_factor = 1.2
	return p


func _radar(surface_nm := 60.0) -> SensorSpec:
	var s := SensorSpec.new()
	s.kind = "radar"
	s.range_surface_nm = surface_nm
	s.range_air_nm = 120.0
	s.antenna_height_m = 20.0
	return s


func _asm(targets: PackedStringArray, reach := 90.0) -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = "test_asm_" + "_".join(targets)
	w.display_name = "Test round"
	w.type = "asm"
	w.profile = "sea_skimming"
	w.target_types = targets
	w.max_range_nm = reach
	w.min_range_nm = 1.0
	w.speed_kn = 480.0
	w.seeker_range_nm = 6.0
	w.damage = 40.0
	w.base_pk = 1.0
	w.turn_rate_deg_s = 15.0
	return w


func _sam() -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = "test_sam"
	w.display_name = "Test SAM"
	w.type = "sam"
	w.profile = "high"
	w.target_types = PackedStringArray(["missile", "air"])
	w.max_range_nm = 40.0
	w.min_range_nm = 1.0
	w.speed_kn = 2200.0
	w.damage = 40.0
	w.base_pk = 1.0
	w.turn_rate_deg_s = 60.0
	return w


func _unit(spec: PlatformSpec, faction: String, pos: Vector2, weapon: WeaponSpec = null, rounds := 8, radar: SensorSpec = null) -> Unit:
	var u := Unit.new()
	u.spec = spec
	u.faction = faction
	u.callsign = "%s %s" % [faction, spec.short_name]
	u.position = pos
	u.health = spec.health
	u.decoys = 0
	if radar != null:
		u.sensors.append(radar)
	if weapon != null:
		u.weapons.append(weapon)
		u.magazines[weapon.id] = rounds
	return u


func _track(faction: String, truth: Unit, domain: String) -> Track:
	var t := Track.new()
	t.id = "T1"
	t.owner_faction = faction
	t.truth = truth
	t.position = truth.position
	t.domain = domain
	t.identity = "HOSTILE"
	t.classification = Track.Classification.CLASS_KNOWN
	t.status = Track.Status.ACTIVE
	t.known_class = truth.spec.short_name
	t.networked = true
	return t


class World:
	extends RefCounted
	var um: UnitManager
	var tm: TrackManager
	var wm: WeaponManager
	var thm: ThreatManager

	func _init() -> void:
		um = UnitManager.new()
		tm = TrackManager.new()
		thm = ThreatManager.new()
		wm = WeaponManager.new()
		wm.unit_manager = um
		wm.track_manager = tm
		wm.rng.seed = 3

	func fly(seconds: float) -> void:
		var t := 0.0
		while t < seconds:
			wm.tick(DT, t)
			t += DT

	func free_all() -> void:
		wm.free()
		thm.free()
		tm.free()
		um.free()


func _fire_and_fly(w: World, shooter: Unit, spec: WeaponSpec, t: Track) -> Weapon:
	assert_true(w.wm.launch(shooter, spec, t, 1, 0.0), "%s accepts the shot" % shooter.callsign)
	if w.wm.in_flight.is_empty():
		return null
	var round: Weapon = w.wm.in_flight[0]
	w.fly(1200.0)
	return round


func test_a_land_attack_round_crosses_the_beach_to_a_battery() -> void:
	_land([ISLAND])
	var w := World.new()
	var battery := _unit(_site(), "RED", Vector2(3.0, 0.0))
	var ship := _unit(_hull(), "BLUE", Vector2(-30.0, 0.0), _asm(PackedStringArray(["surface", "land"])))
	w.um.add_unit(battery)
	w.um.add_unit(ship)
	var t := _track("BLUE", battery, "land")
	var check := Combat.check_engagement(ship, ship.weapons[0], t)
	assert_true(check["ok"], "the coast is not a line-of-fire problem for a target ashore: %s" % check["reason"])
	var round := _fire_and_fly(w, ship, ship.weapons[0], t)
	assert_true(round != null and round.dead_reason == "HIT", "the round reached the battery: %s" % (round.dead_reason if round else "no round"))
	assert_true(not battery.alive or battery.health < battery.spec.health, "the battery was hit")
	w.free_all()
	Terrain.clear()


func test_an_anti_ship_round_still_dies_on_the_headland() -> void:
	_land([ISLAND])
	var w := World.new()
	var target := _unit(_hull(), "RED", Vector2(30.0, 0.0))
	var ship := _unit(_hull(), "BLUE", Vector2(-30.0, 0.0), _asm(PackedStringArray(["surface"])))
	w.um.add_unit(target)
	w.um.add_unit(ship)
	var t := _track("BLUE", target, "surface")
	assert_eq(Combat.check_engagement(ship, ship.weapons[0], t)["reason"], "NO LINE OF FIRE", "an island between two ships blocks the shot")
	# Fired anyway through the manager's own gate it would be refused; force the round to see the rule in flight.
	ship.weapons[0].profile = "high"
	assert_true(w.wm.launch(ship, ship.weapons[0], t, 1, 0.0), "a high flyer may be fired")
	var round: Weapon = w.wm.in_flight[0]
	round.spec.profile = "sea_skimming"
	w.fly(1200.0)
	assert_eq(round.dead_reason, "TERRAIN", "the sea-skimmer ends on the island")
	w.free_all()
	Terrain.clear()


func test_a_battery_ashore_shoots_out_over_its_own_coast() -> void:
	_land([ISLAND])
	var w := World.new()
	var battery := _unit(_site(), "RED", Vector2(4.0, 0.0), _asm(PackedStringArray(["surface"])), 8, _radar())
	var ship := _unit(_hull(), "BLUE", Vector2(-40.0, 0.0))
	w.um.add_unit(battery)
	w.um.add_unit(ship)
	var t := _track("RED", ship, "surface")
	var check := Combat.check_engagement(battery, battery.weapons[0], t)
	assert_true(check["ok"], "the battery has a line of fire from its hill: %s" % check["reason"])
	var round := _fire_and_fly(w, battery, battery.weapons[0], t)
	assert_true(round != null, "a round was fired")
	if round != null:
		assert_true(round.dead_reason != "TERRAIN", "the round cleared the coast rather than dying on it")
		assert_eq(round.dead_reason, "HIT", "and reached the ship")
	w.free_all()
	Terrain.clear()


func test_a_battery_round_that_turns_back_ashore_still_hits_the_ground() -> void:
	_land([ISLAND])
	var w := World.new()
	var battery := _unit(_site(), "RED", Vector2(4.0, 0.0), _asm(PackedStringArray(["surface"])), 8, _radar())
	var ship := _unit(_hull(), "BLUE", Vector2(20.0, 0.0))
	w.um.add_unit(battery)
	w.um.add_unit(ship)
	var t := _track("RED", ship, "surface")
	assert_true(w.wm.launch(battery, battery.weapons[0], t, 1, 0.0))
	var round: Weapon = w.wm.in_flight[0]
	w.fly(20.0)
	assert_true(not Terrain.is_land(round.position), "the round is over water")
	assert_true(not round.launched_ashore, "and the launch exemption has lapsed")
	round.position = Vector2(-2.0, 0.0)  # steer it back over the island
	round.aim_point = Vector2(-40.0, 0.0)
	w.fly(2.0)
	assert_eq(round.dead_reason, "TERRAIN", "the exemption does not outlast the coast")
	w.free_all()
	Terrain.clear()


func test_the_ai_battery_fires_on_the_networked_picture_and_never_moves() -> void:
	_land([ISLAND])
	var w := World.new()
	var battery := _unit(_site(), "RED", Vector2(4.0, 0.0), _asm(PackedStringArray(["surface"])), 8)
	var ship := _unit(_hull(), "BLUE", Vector2(-40.0, 0.0))
	w.um.add_unit(battery)
	w.um.add_unit(ship)
	var t := _track("RED", ship, "surface")
	w.tm._tracks["RED"] = [t]
	var ai := AIController.new()
	ai.faction = "RED"
	ai.unit_manager = w.um
	ai.track_manager = w.tm
	ai.threat_manager = w.thm
	ai.weapon_manager = w.wm
	var moves := [0]
	# The simulation node normally routes ENGAGE to the weapon layer; stand in for it here.
	w.um.order_issued.connect(func(u: Unit, o: Order) -> void:
		if o.type == Order.Type.ENGAGE:
			w.wm.launch(u, u.get_weapon(o.weapon_id), o.track, o.salvo, 10.0)
		elif o.type in [Order.Type.MOVE, Order.Type.SET_COURSE, Order.Type.SET_SPEED]:
			moves[0] += 1)
	ai.tick(10.0)
	assert_true(not w.wm.in_flight.is_empty(), "the battery fired on the picture it was handed")
	assert_eq(moves[0], 0, "and issued itself no movement orders")
	assert_eq(ai.state_name(battery), "ENGAGE")
	assert_eq(battery.position, Vector2(4.0, 0.0), "a battery stays where it was dug in")
	ai.free()
	w.free_all()
	Terrain.clear()


func test_a_missile_site_defends_the_coast_like_a_ship() -> void:
	_land([ISLAND])
	var w := World.new()
	var sam_site := _unit(_site(), "RED", Vector2(3.0, 0.0), _sam(), 8, _radar())
	var ship := _unit(_hull(), "BLUE", Vector2(-30.0, 0.0), _asm(PackedStringArray(["surface", "land"])))
	w.um.add_unit(sam_site)
	w.um.add_unit(ship)
	var t := _track("BLUE", sam_site, "land")
	assert_true(w.wm.launch(ship, ship.weapons[0], t, 1, 0.0))
	var inbound: Weapon = w.wm.in_flight[0]
	w.fly(120.0)
	w.thm.begin_cycle()
	w.thm.mark_detected("RED", inbound, 120.0, sam_site)
	var fired := AirDefence.run_cycle(w.um, w.thm, w.wm, 120.0)
	assert_true(fired > 0, "the site engaged the round closing on it")
	w.free_all()
	Terrain.clear()


func test_installations_stand_on_their_ground() -> void:
	_land([ISLAND])
	var site := _unit(_site(), "RED", Vector2(0.0, 0.0), null, 0, _radar())
	assert_near(Detection.mast_or_altitude_m(site), 330.0, 1e-6, "plateau plus mast")
	assert_near(Detection.observer_height_m(site, site.sensors[0]), 320.0, 1e-6, "the radar looks out from the hill")
	assert_true(Detection.emitter_height_m(site) >= 320.0, "and is heard from that height")
	# Sited a mile behind the eastern beach, it looks out over the water to the east; the five
	# miles of plateau to its west hide a ship on that side, as a cliff would.
	var headland := _unit(_site(), "RED", Vector2(4.0, 0.0), null, 0, _radar())
	var east := _unit(_hull(), "BLUE", Vector2(40.0, 0.0), null, 0, _radar())
	var west := _unit(_hull(), "BLUE", Vector2(-40.0, 0.0), null, 0, _radar())
	assert_true(not Detection.terrain_masks(east, headland), "a headland site is seen from the sea it faces")
	assert_true(Detection.radar_quality(east, headland) > 0.0, "and painted by the ship's radar")
	assert_true(Detection.terrain_masks(west, headland), "the plateau behind it hides it from the other side")
	Terrain.clear()


func test_track_wording_names_an_installation() -> void:
	var t := Track.new()
	t.id = "T9"
	t.domain = "land"
	t.classification = Track.Classification.SURFACE
	assert_eq(t.description(), "SHORE INSTALLATION")
	assert_eq(t.class_short(), "SHORE")
	assert_eq(t.label(), "T9 SHORE")
	assert_eq(MapSymbols.category_glyph("coastal missile battery", "land"), "CB")
	assert_eq(MapSymbols.category_glyph("surface-to-air missile site", "land"), "SA")
	assert_eq(MapSymbols.category_glyph("ballistic missile battery", "land"), "BM")
	assert_eq(MapSymbols.category_glyph("drone launch site", "land"), "DR")
	assert_eq(MapSymbols.category_glyph("shore base", "land"), "AB")


func test_catalogue_strike_rounds_and_decks_carry_their_new_roles() -> void:
	for wid in ["tomahawk_block_v", "nsm_strike_missile", "jsm_missile", "pla_cj10"]:
		assert_true(DataDB.weapon(wid).target_types.has("land"), "%s can be fired at a target ashore" % wid)
	for wid in ["kalibr_asm", "agm_158c_lrasm", "rgm_84_harpoon", "pla_yj18"]:
		assert_true(not DataDB.weapon(wid).target_types.has("land"), "%s stays an anti-ship round" % wid)
	var shandong := DataDB.platform("pla_cv_shandong")
	assert_eq(shandong.flight_facility(), "stobar")
	assert_true(shandong.can_operate(DataDB.platform("pla_fighter_j15")), "a ski-jump deck flies its own fighters")
	assert_true(shandong.can_operate(DataDB.platform("jasdf_fighter_f35b")), "and jump jets")
	assert_true(not shandong.can_operate(DataDB.platform("usn_fighter_fa18e")), "but no catapult aircraft")
	assert_true(DataDB.platform("usn_cvn_nimitz").can_operate(DataDB.platform("pla_fighter_j15")), "a catapult deck recovers a ski-jump aircraft into its wires")
	assert_true(not DataDB.platform("jmsdf_ddh_izumo").can_operate(DataDB.platform("pla_fighter_j15")), "a STOVL deck has no wires")
	assert_eq(shandong.recovery_capacity(), 1, "one angled deck, one at a time")
	for sid in ["pla_battery_yj12b", "irn_battery_qader", "rfn_battery_bastion", "pla_asbm_df21d"]:
		var p := DataDB.platform(sid)
		assert_eq(p.domain, "land", sid)
		assert_true(not p.weapon_loadout.is_empty(), "%s is armed" % sid)
		assert_eq(p.max_speed_kn, 0.0, "%s does not move" % sid)


## The single-altitude ballistic profile must never fall between the terminal interceptors'
## ceiling and the exo-atmospheric interceptor's floor: a round nobody in the catalogue can meet
## is a scenario the player cannot influence, not a hard one.
func test_every_ballistic_round_has_an_interceptor_whose_window_covers_it() -> void:
	var interceptors: Array = []
	for w in DataDB.all_weapons():
		if w.type == "sam" and w.target_types.has("ballistic"):
			interceptors.append(w)
	assert_true(interceptors.size() >= 3, "SM-3, SM-6 and Aster 30 at least")
	var rounds := 0
	for w in DataDB.all_weapons():
		if w.profile != "ballistic" or w.type != "asm":
			continue
		rounds += 1
		var covered: Array = []
		for sam in interceptors:
			if w.altitude_m >= sam.intercept_min_altitude_m and w.altitude_m <= sam.intercept_max_altitude_m:
				covered.append(sam.id)
		assert_true(not covered.is_empty(), "%s at %.0f m can be met by someone" % [w.id, w.altitude_m])
	assert_true(rounds >= 4, "Kinzhal, Khalij Fars, YJ-21 and DF-21D are all in the catalogue")
	var df21d := DataDB.weapon("pla_df21d")
	var sm3 := DataDB.weapon("sm3_family")
	var sm6 := DataDB.weapon("sm6_family")
	assert_true(df21d.altitude_m >= sm3.intercept_min_altitude_m, "the DF-21D is SM-3's problem")
	assert_true(df21d.altitude_m > sm6.intercept_max_altitude_m, "and beyond a terminal interceptor")
	var aster := DataDB.weapon("aster30_family")
	var khalij := DataDB.weapon("irn_khalij_fars")
	assert_true(khalij.altitude_m <= aster.intercept_max_altitude_m, "a Type 45 can meet a Khalij Fars")



## An AI ship with a long-range round, and one hostile track at `range_nm` of the given domain.
func _long_shot(domain: String, range_nm: float, moving_kn := 0.0) -> Array:
	var w := World.new()
	var strike := _asm(PackedStringArray(["surface", "land"]), 540.0)
	var shooter := _unit(_hull(), "BLUE", Vector2.ZERO, strike, 8)
	shooter.roe = Unit.Roe.FREE
	var target := _unit(_site() if domain == "land" else _hull(), "RED", Vector2(range_nm, 0.0))
	w.um.add_unit(shooter)
	w.um.add_unit(target)
	var t := _track("BLUE", target, domain)
	if moving_kn > 0.0:
		t.has_kinematics = true
		t.speed_kn = moving_kn
	w.tm._tracks["BLUE"] = [t]
	var ai := AIController.new()
	ai.faction = "BLUE"
	ai.unit_manager = w.um
	ai.track_manager = w.tm
	ai.threat_manager = w.thm
	ai.weapon_manager = w.wm
	var engaged: Array = [false]
	w.um.order_issued.connect(func(_u: Unit, o: Order) -> void:
		if o.type == Order.Type.ENGAGE:
			engaged[0] = true)
	ai.tick(10.0)
	var result: bool = engaged[0]
	ai.free()
	w.free_all()
	return [result, Combat.time_of_flight_s(strike, range_nm)]


func test_the_ai_strikes_a_fixed_installation_whatever_the_flight_time() -> void:
	var near := _long_shot("land", 40.0)
	assert_true(near[1] < AIController.MAX_TIME_OF_FLIGHT_S and near[0], "inside the limit, as before")
	var far := _long_shot("land", 200.0)
	assert_true(far[1] > AIController.MAX_TIME_OF_FLIGHT_S, "a %.0f s flight is past the limit" % far[1])
	assert_true(far[0], "and a battery dug in ashore is still there when the round arrives")


func test_the_flight_time_limit_still_holds_for_anything_that_moves() -> void:
	assert_true(not _long_shot("surface", 200.0)[0], "a ship 200 nm off will have moved by then")
	assert_true(not _long_shot("land", 200.0, 20.0)[0], "and so will a launcher the picture shows driving")
	assert_true(_long_shot("land", 200.0, 0.5)[0], "a site the picture puts at a crawl is standing still")
