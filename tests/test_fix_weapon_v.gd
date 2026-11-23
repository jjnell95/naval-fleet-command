extends TestCase
## Seekers that take what they were sent at, defensive fire that is not held for nothing, plots too
## old to shoot at, anti-radiation rounds that end, group budgets sized to the target, a radar the
## commander switched off, and ships that fight a torpedo for as long as it runs.

const DT := 0.25


func _platform(domain := "surface", max_speed := 30.0) -> PlatformSpec:
	var p := PlatformSpec.new()
	p.short_name = "Test %s" % domain
	p.domain = domain
	p.max_speed_kn = max_speed
	p.cruise_speed_kn = 15.0
	p.health = 100.0
	p.decoy_count = 0
	return p


func _unit(faction: String, pos: Vector2, domain := "surface", uid := 0) -> Unit:
	var u := Unit.new()
	u.spec = _platform(domain)
	u.faction = faction
	u.callsign = "%s %s %d" % [faction, domain, uid]
	u.position = pos
	u.health = 100.0
	u.id = uid
	if domain == "subsurface":
		u.depth_m = 100.0
	return u


func _track(owner: Unit, pos: Vector2, domain := "surface") -> Track:
	var t := Track.new()
	t.id = "T1"
	t.owner_faction = owner.faction
	t.identity = "HOSTILE"
	t.domain = domain
	t.status = Track.Status.ACTIVE
	t.has_kinematics = true
	t.position = pos
	t.networked = false
	t.contributors[owner] = true
	return t


func _harness(units: Array, seed_value := 11) -> WeaponManager:
	var um := UnitManager.new()
	for u: Unit in units:
		um.add_unit(u)
	var wm := WeaponManager.new()
	wm.unit_manager = um
	wm.rng.seed = seed_value
	return wm


func _cleanup(wm: WeaponManager) -> void:
	wm.clear()
	wm.unit_manager.free()
	wm.free()


## Northern Passage played headless: the frigate is given the bare attack order on the Gorshkov at
## `attack_at`, and the run goes on for `after_s`. Returns every BLUE impact as [time, callsign, hit].
func _northern_passage_attack(attack_at: float, after_s: float, seed_value := -1) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	SimClock.set_paused(true)
	Terrain.clear()
	Detection.set_environment({})
	var sim := Simulation.new()
	tree.root.add_child(sim)
	if seed_value >= 0:
		sim.seed_override = seed_value
	var out := {"impacts": [], "ordered": false, "neutral": null}
	if not sim.load_scenario("res://data/scenarios/northern_passage.json"):
		sim.free()
		return out
	var frigate: Unit = null
	for u: Unit in sim.unit_manager.units:
		if u.spec.id == "rnon_ffg_fridtjof_nansen":
			frigate = u
		if u.callsign == "MV Skerry Trader":
			out["neutral"] = u
	var impacts: Array = out["impacts"]
	var on_impact := func(faction: String, _spec: WeaponSpec, target: Unit, hit: bool) -> void:
		if faction == "BLUE" and target != null:
			impacts.append([SimClock.sim_time, target.callsign, hit])
	sim.weapon_manager.weapon_impact.connect(on_impact)
	var start := SimClock.sim_time
	while SimClock.sim_time - start < attack_at + after_s and sim.mission_manager.result == MissionManager.Result.RUNNING:
		SimClock.advance(1.0)
		if not out["ordered"] and SimClock.sim_time - start >= attack_at:
			for tr: Track in sim.track_manager.tracks_for(frigate):
				if tr.identity == "HOSTILE" and tr.domain == "surface":
					out["ordered"] = sim.unit_manager.issue_order(frigate, Order.attack(tr, ""))
					break
			for tr: Track in sim.track_manager.tracks_for(frigate):
				if tr.truth == out["neutral"]:
					out["held_as"] = tr.identity
	sim.weapon_manager.weapon_impact.disconnect(on_impact)
	sim.free()
	return out


# --- p-firsthour#2: a seeker opened on the rail does not take a neutral near the shooter --------

## Inside nine miles of the Gorshkov an NSM's seeker is open as it leaves the rail. The merchant two
## miles off the frigate's bow, held NEUTRAL from the start, crossed its cone first and took all
## three hits of every salvo. Nothing short of the aim point is the target.
func test_a_standing_attack_never_hits_the_neutral_merchant_beside_the_frigate() -> void:
	for attack_at: float in [500.0, 526.0]:
		for seed_value: int in [-1, 2]:
			var run := _northern_passage_attack(attack_at, 120.0, seed_value)
			assert_true(run["ordered"], "at %d s the attack order is taken" % int(attack_at))
			assert_eq(run.get("held_as", ""), "NEUTRAL", "the frigate holds Skerry Trader as neutral")
			for impact: Array in run["impacts"]:
				assert_true(impact[1] != "MV Skerry Trader", "attack at %d s, seed %d: no round lands on the neutral (%s)" % [int(attack_at), seed_value, str(impact)])


## The same geometry on the bench: a missile fired at a plot eight miles off with a nine-mile seeker,
## and a neutral two miles out on the shooter's bow inside the seeker's cone. The round flies past
## the neutral and takes the ship.
func test_a_seeker_open_at_launch_takes_the_target_not_the_hull_beside_the_shooter() -> void:
	Terrain.clear()
	var shooter := _unit("BLUE", Vector2.ZERO, "surface", 1)
	# The plot is half a mile short of the ship, which is just beyond the seeker's reach at launch.
	var target := _unit("RED", Vector2(7.6, 5.0), "surface", 2)
	var merchant := _unit("NEUTRAL", Vector2(1.8, 0.05), "surface", 3)
	var wm := _harness([shooter, target, merchant])
	var spec := DataDB.weapon("nsm_strike_missile")
	var plot := _track(shooter, Vector2(7.0, 4.6))
	plot.truth = target
	assert_true(spec.acquisition_radius_nm() > shooter.position.distance_to(plot.position), "the shot is inside the seeker's own range")
	wm._fire_round(shooter, spec, plot)
	var round: Weapon = wm.in_flight[0]
	var first := ""
	var now := 0.0
	while now < 200.0 and round.phase != Weapon.Phase.DEAD:
		now += DT
		wm.tick(DT, now)
		if first == "" and round.acquired != null:
			first = round.acquired.callsign
	assert_eq(first, target.callsign, "the first lock is the ship it was fired at")
	_cleanup(wm)


# --- c-defence#2: an own helicopter low under a drone at height is no merge --------------------

func _sam_world(helo_pos: Vector2, helo_altitude_m: float, plot_height := true) -> Dictionary:
	var ship := _unit("BLUE", Vector2.ZERO, "surface", 1)
	var radar := SensorSpec.new()
	radar.kind = "radar"
	radar.range_surface_nm = 40.0
	radar.range_air_nm = 200.0
	radar.antenna_height_m = 20.0
	ship.sensors.append(radar)
	ship.roe = Unit.Roe.FREE
	var sam := DataDB.weapon("sm2_family")
	ship.weapons.append(sam)
	ship.magazines[sam.id] = 20
	var drone := _unit("RED", Vector2(0.0, 22.0), "air", 2)
	var helo := _unit("BLUE", helo_pos, "air", 3)
	for a: Unit in [drone, helo]:
		a.flight_state = Unit.FlightState.AIRBORNE
		a.fuel_s = 99999.0
	drone.altitude_m = 4500.0
	helo.altitude_m = helo_altitude_m
	var um := UnitManager.new()
	for u: Unit in [ship, drone, helo]:
		um.add_unit(u)
	var tm := TrackManager.new()
	var wm := WeaponManager.new()
	wm.unit_manager = um
	wm.track_manager = tm
	um.weapon_manager = wm
	var t := _track(ship, drone.position, "air")
	t.truth = drone
	t.position_error_nm = 0.2
	t.speed_kn = 90.0
	t.course_deg = 90.0
	t.altitude_m = drone.altitude_m if plot_height else -1.0
	t.classification = Track.Classification.CLASS_KNOWN
	tm._tracks["BLUE"] = [t]
	return {"um": um, "tm": tm, "wm": wm, "ship": ship, "track": t}


func _free_sam_world(w: Dictionary) -> void:
	(w["wm"] as WeaponManager).clear()
	(w["wm"] as WeaponManager).free()
	(w["tm"] as TrackManager).free()
	(w["um"] as UnitManager).free()


## A Burke on Weapons Free holding a hostile drone at 4,500 m, 22 miles off; its own helicopter
## hovers at 150 m some four miles from the drone. The crew can see on the height-finder that the two
## are not one merge, and shoots. An own aircraft at the drone's height there is a merge, and the
## crew still holds.
func test_automatic_sam_fire_is_not_held_by_an_own_helicopter_far_below_the_drone() -> void:
	var cases := [
		[Vector2(3.0, 19.5), 150.0, true, 1, "helicopter low under the drone"],
		[Vector2(3.0, 19.5), 4200.0, true, 0, "own aircraft at the drone's height"],
		[Vector2(12.0, 19.5), 4500.0, true, 1, "own aircraft well clear in plan"],
	]
	for c: Array in cases:
		var w := _sam_world(c[0], c[1], c[2])
		var fired := AirDefence.engage_hostile_aircraft(w["um"], w["tm"], w["wm"], 0.0, ["BLUE"])
		assert_true(bool((w["wm"] as WeaponManager).engagement_check(w["ship"], DataDB.weapon("sm2_family"), w["track"], 0.0).ok), "%s: the shot is in the envelope" % c[4])
		assert_eq(fired, c[3], c[4])
		_free_sam_world(w)


# --- c-sensors#3: a stale plot is no fire-control solution ---------------------------------------

func _strike_spec(id: String, type: String, targets: Array, guidance := "active_radar_homing") -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = id
	w.display_name = id
	w.type = type
	w.guidance = guidance
	w.profile = "sea_skimming"
	w.target_types = PackedStringArray(targets)
	w.max_range_nm = 200.0
	w.min_range_nm = 1.0
	w.speed_kn = 500.0
	w.turn_rate_deg_s = 15.0
	w.seeker_range_nm = 8.0
	w.damage = 40.0
	w.base_pk = 1.0
	w.run_to_enable_nm = 1.0
	return w


## A Burke loses the frigate it held on radar. Five minutes on the plot is STALE, two miles out,
## and the Tomahawk check said IN ENVELOPE and launch() fired. The check now refuses it, and the
## refusal names why; a torpedo that searches about the datum, an anti-radiation round that listens
## for the emitter and a strike on a site ashore are still allowed.
func test_no_missile_or_shell_is_laid_on_a_stale_plot() -> void:
	Terrain.clear()
	var shooter := _unit("BLUE", Vector2.ZERO, "surface", 1)
	shooter.roe = Unit.Roe.FREE
	var ship := _unit("RED", Vector2(0.0, 6.0), "surface", 2)
	var missile := _strike_spec("strike", "asm", ["surface", "land"])
	var torpedo := _strike_spec("fish", "torpedo", ["surface", "subsurface"])
	torpedo.max_range_nm = 20.0
	var arm := _strike_spec("arm", "asm", ["surface", "land"], "passive_radar_homing")
	for spec: WeaponSpec in [missile, torpedo, arm]:
		shooter.weapons.append(spec)
		shooter.magazines[spec.id] = 8
	ship.radar_on = true
	var wm := _harness([shooter, ship])
	var t := _track(shooter, ship.position)
	t.truth = ship
	t.last_esm_time = 0.0
	assert_true(bool(Combat.check_engagement(shooter, missile, t).ok), "a current plot: %s" % Combat.check_engagement(shooter, missile, t).reason)
	t.status = Track.Status.STALE
	t.position_error_nm = 2.2
	assert_eq(str(Combat.check_engagement(shooter, missile, t).reason), "NO CURRENT FIX", "a missile at a stale ship plot")
	assert_true(not wm.launch(shooter, missile, t, 1, 0.0) and wm.in_flight.is_empty(), "nothing leaves the rail at a stale plot")
	assert_true(str(Combat.check_engagement(shooter, torpedo, t).reason) != "NO CURRENT FIX", "a torpedo searches about the datum")
	assert_true(str(Combat.check_engagement(shooter, arm, t).reason) != "NO CURRENT FIX", "an anti-radiation round listens for the emitter")
	t.domain = "land"
	assert_true(str(Combat.check_engagement(shooter, missile, t).reason) != "NO CURRENT FIX", "a site ashore stays where it was plotted")
	_cleanup(wm)


# --- c-weapons:new1: an anti-radiation round homing on silence ends at the end of its range -----

## Fired at a radar beyond its reach, an anti-radiation missile hears it, and then the radar goes
## quiet. The round flies on to the last place it heard it, runs out of fuel short of it and ends
## there. It used to hang at full range, in flight for the rest of the engagement.
func test_an_anti_radiation_round_homing_on_a_silent_emitter_ends_at_full_range() -> void:
	Terrain.clear()
	Detection.set_environment({})
	var site := _unit("RED", Vector2(0.0, 70.0), "surface", 2)
	var radar := SensorSpec.new()
	radar.kind = "radar"
	radar.range_surface_nm = 40.0
	radar.range_air_nm = 200.0
	radar.antenna_height_m = 20.0
	site.sensors.append(radar)
	site.radar_on = true
	var wm := _harness([site])
	var w := Weapon.new()
	w.id = 9
	w.spec = _strike_spec("arm", "asm", ["surface", "land"], "passive_radar_homing")
	w.spec.max_range_nm = 60.0
	w.spec.speed_kn = 1200.0
	w.spec.seeker_range_nm = 25.0
	w.spec.seeker_half_angle_deg = 45.0
	w.spec.profile = "high"
	w.spec.altitude_m = 9000.0
	w.faction = "BLUE"
	w.aim_point = site.position
	w.heading_deg = 0.0
	wm.in_flight.append(w)
	var heard := false
	var now := 0.0
	while now < 600.0 and w.phase != Weapon.Phase.DEAD:
		now += DT
		wm.tick(DT, now)
		if w.phase == Weapon.Phase.TERMINAL and w.acquired == site and not heard:
			heard = true
			site.radar_on = false
	assert_true(heard, "it heard the radar before it went quiet")
	assert_eq(w.phase, Weapon.Phase.DEAD, "the round has ended (flown %.1f of %.1f nm)" % [w.distance_flown_nm, w.spec.max_range_nm])
	assert_eq(w.dead_reason, "RANGE EXHAUSTED")
	assert_true(not wm.in_flight.has(w), "nothing is left in flight")
	assert_near(site.health, 100.0, 0.01, "the site is untouched")
	_cleanup(wm)


# --- hook:group-budget: a group's default budget is what the target needs ---------------------

func _catalogue_ship(sim: Simulation, platform: String, callsign: String, pos: Vector2) -> Unit:
	var u := Unit.new()
	u.spec = DataDB.platform(platform)
	u.faction = "BLUE"
	u.callsign = callsign
	u.health = u.spec.health
	u.position = pos
	u.roe = Unit.Roe.FREE
	for sid in u.spec.sensor_ids:
		u.sensors.append(DataDB.sensor(sid))
	for wid in u.spec.weapon_loadout:
		u.weapons.append(DataDB.weapon(wid))
		u.magazines[wid] = u.spec.weapon_loadout[wid]
	sim.unit_manager.add_unit(u)
	return u


## Three ships group-attack a surface contact. Fresh, it draws the volley its strength needs, no
## more than a salvo from each. Assessed 76% destroyed, the group's default is a round or two in
## all, and that is what the group fires, not a salvo per ship.
func test_a_group_attack_on_a_nearly_dead_target_fires_a_round_or_two_in_all() -> void:
	Terrain.clear()
	SimClock.set_paused(true)
	var sim := Simulation.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	sim.ai_enabled = false
	sim.weapon_manager.rng.seed = 7
	var members: Array = [
		_catalogue_ship(sim, "usn_ddg_arleigh_burke_iia", "Ignatius", Vector2(0, 0)),
		_catalogue_ship(sim, "rnon_ffg_fridtjof_nansen", "Nansen", Vector2(4, 0)),
		_catalogue_ship(sim, "rnon_ffg_fridtjof_nansen", "Amundsen", Vector2(-4, 0)),
	]
	var t := Track.new()
	t.id = "T1077"
	t.owner_faction = "BLUE"
	t.identity = "HOSTILE"
	t.domain = "surface"
	t.classification = Track.Classification.SURFACE
	t.status = Track.Status.ACTIVE
	t.position = Vector2(0, 40)
	t.last_seen_time = SimClock.sim_time
	sim.track_manager._tracks["BLUE"] = [t]
	var volley := 0
	for u: Unit in members:
		for spec: WeaponSpec in u.weapons_for_track(t):
			if bool(sim.weapon_manager.engagement_check(u, spec, t, 0.0).ok):
				volley += mini(spec.salvo_default, u.magazine_count(spec.id))
				break
	var fresh := GroupAttackManager.default_budget(members, t, sim.weapon_manager)
	assert_true(fresh >= 2 and fresh <= volley, "a fresh contact draws what its strength needs, at most a salvo each: %d of %d" % [fresh, volley])
	t.damage_estimate = 76.0
	var nearly_dead := GroupAttackManager.default_budget(members, t, sim.weapon_manager)
	assert_true(nearly_dead >= 1 and nearly_dead <= 2, "76%% destroyed: %d rounds in all, not %d" % [nearly_dead, volley])
	sim.unit_manager.issue_order(members[0], Order.group_attack(members, [t], 0))
	var g: GroupAttack = sim.group_attack_manager.groups.back() if not sim.group_attack_manager.groups.is_empty() else null
	assert_true(g != null, "the group attack is running")
	if g != null:
		assert_eq(g.budget, nearly_dead, "the order takes the default budget")
		for i in 400:
			t.last_seen_time = SimClock.sim_time
			t.status = Track.Status.ACTIVE
			SimClock.advance(DT)
		assert_true(g.fired_total >= 1 and g.fired_total <= 2, "the group fired %d rounds" % g.fired_total)
	sim.weapon_manager.clear()
	sim.group_attack_manager.clear()
	sim.unit_manager.clear()
	sim.free()


# --- verify:radar-off-order: the crew lights a radar the commander put out only for its own defence

func _def_ship(callsign: String, pos: Vector2) -> Unit:
	var u := _unit("BLUE", pos, "surface", 0)
	u.callsign = callsign
	u.decoys = 0
	var radar := SensorSpec.new()
	radar.kind = "radar"
	radar.range_surface_nm = 40.0
	radar.range_air_nm = 200.0
	radar.antenna_height_m = 20.0
	u.sensors.append(radar)
	var sam := WeaponSpec.new()
	sam.id = "test_sarh"
	sam.display_name = "Test SARH"
	sam.type = "sam"
	sam.guidance = "semi_active_radar"
	sam.target_types = PackedStringArray(["missile"])
	sam.max_range_nm = 20.0
	sam.min_range_nm = 0.5
	sam.speed_kn = 2400.0
	sam.turn_rate_deg_s = 120.0
	sam.base_pk = 0.0
	sam.salvo_default = 1
	sam.launch_interval_s = 1.0
	u.weapons.append(sam)
	u.magazines[sam.id] = 32
	return u


func _def_round(wm: WeaponManager, pos: Vector2, target: Unit, wid: int) -> Weapon:
	var w := Weapon.new()
	w.id = wid
	w.spec = _strike_spec("test_asm", "asm", ["surface"])
	w.spec.altitude_m = 10.0
	w.faction = "RED"
	w.position = pos
	w.acquired = target
	w.aim_point = target.position
	w.heading_deg = Geo.bearing_deg(pos, target.position)
	w.phase = Weapon.Phase.TERMINAL
	wm.in_flight.append(w)
	return w


## The commander switches a ship's radar off with a plain order. A round coming at her consort does
## not make her crew light it; one coming at her does, and the crew says so. With the threat past,
## the radar goes dark again as the commander had it. Had the commander ordered it on meanwhile,
## it stays on.
func test_a_radar_ordered_off_is_lit_only_for_a_round_at_the_ship_and_put_out_after() -> void:
	Terrain.clear()
	for commander_relights: bool in [false, true]:
		var dark := _def_ship("Dark", Vector2.ZERO)
		var consort := _def_ship("Consort", Vector2(6.0, 0.0))
		consort.radar_on = true
		var um := UnitManager.new()
		um.add_unit(dark)
		um.add_unit(consort)
		var tm := ThreatManager.new()
		var wm := WeaponManager.new()
		wm.unit_manager = um
		um.weapon_manager = wm
		var lit_lines: Array = []
		wm.self_defence_emcon.connect(func(u: Unit, lit: bool) -> void:
			if lit:
				lit_lines.append(u.callsign))
		assert_true(um.issue_order(dark, Order.silence_radar()), "the commander's order is taken")
		assert_true(not dark.radar_on)
		wm.tick(DT, 0.0)
		var at_consort := _def_round(wm, Vector2(6.0, 15.0), consort, 901)
		tm.mark_detected("BLUE", at_consort, 1.0)
		AirDefence.run_cycle(um, tm, wm, 1.0)
		assert_true(not dark.radar_on, "a round at the consort leaves her radar as ordered")
		wm.defeat_weapon(at_consort, "TEST")
		var at_her := _def_round(wm, Vector2(0.0, 15.0), dark, 902)
		tm.mark_detected("BLUE", at_her, 2.0)
		AirDefence.run_cycle(um, tm, wm, 2.0)
		assert_true(dark.radar_on, "a round coming at her: the crew lights the radar to fight it")
		assert_true(lit_lines.has("Dark"), "and says so on the radio")
		if commander_relights:
			assert_true(um.issue_order(dark, Order.activate_radar()))
		wm.defeat_weapon(at_her, "TEST")
		var now := 2.0
		while now < 2.0 + AirDefence.DEFENCE_RADAR_QUIET_S + 5.0:
			now += 1.0
			wm.tick(1.0, now)
			AirDefence.run_cycle(um, tm, wm, now)
		if commander_relights:
			assert_true(dark.radar_on, "the commander ordered it on: it stays on")
		else:
			assert_true(not dark.radar_on, "the threat has passed: dark again as the commander had it")
		wm.clear()
		tm.free()
		wm.free()
		um.free()
