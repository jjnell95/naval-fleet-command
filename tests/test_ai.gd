extends TestCase
## The central claim under test: the AI decides from its own Track and Threat picture only.
## It must be blind to enemy Units it has not detected, and reluctant to shoot at bad data.

const DT := 0.25


func _platform(hp := 100.0) -> PlatformSpec:
	var p := PlatformSpec.new()
	p.short_name = "FFG Test"
	p.max_speed_kn = 28.0
	p.cruise_speed_kn = 14.0
	p.health = hp
	p.fire_control_channels = 4
	return p


func _radar() -> SensorSpec:
	var s := SensorSpec.new()
	s.kind = "radar"
	s.range_surface_nm = 40.0
	s.range_air_nm = 200.0
	s.antenna_height_m = 20.0
	return s


func _asm(max_range := 60.0) -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = "test_asm"
	w.display_name = "Test ASM"
	w.type = "asm"
	w.max_range_nm = max_range
	w.min_range_nm = 2.0
	w.speed_kn = 480.0
	w.seeker_range_nm = 8.0
	w.damage = 40.0
	w.base_pk = 0.8
	return w


func _ship(faction: String, pos: Vector2, hp := 100.0, weapon: WeaponSpec = null, rounds := 8) -> Unit:
	var u := Unit.new()
	u.spec = _platform(hp)
	u.faction = faction
	u.callsign = "%s-1" % faction
	u.position = pos
	u.health = hp
	u.heading_deg = 0.0
	u.ordered_heading_deg = 0.0
	u.sensors.append(_radar())
	if weapon != null:
		u.weapons.append(weapon)
		u.magazines[weapon.id] = rounds
	return u


class Harness:
	extends RefCounted
	var um: UnitManager
	var tm: TrackManager
	var threats: ThreatManager
	var wm: WeaponManager
	var ai: AIController
	var orders: Array = []

	func free_all() -> void:
		orders.clear()
		ai.free()
		wm.free()
		threats.free()
		tm.free()
		um.free()


func _harness(units: Array, faction := "RED") -> Harness:
	var h := Harness.new()
	h.um = UnitManager.new()
	for u: Unit in units:
		h.um.add_unit(u)
	h.tm = TrackManager.new()
	h.threats = ThreatManager.new()
	h.wm = WeaponManager.new()
	h.wm.unit_manager = h.um
	h.wm.rng.seed = 5
	h.ai = AIController.new()
	h.ai.faction = faction
	h.ai.unit_manager = h.um
	h.ai.track_manager = h.tm
	h.ai.threat_manager = h.threats
	h.ai.weapon_manager = h.wm
	h.um.order_issued.connect(func(u: Unit, o: Order) -> void: h.orders.append({"unit": u, "order": o}))
	return h


## Builds a perception of `target` for `faction` at the stated quality, without ever letting the
## AI reach the real unit.
func _make_track(h: Harness, faction: String, target: Unit, pos: Vector2, classification := Track.Classification.CLASS_KNOWN, status := Track.Status.ACTIVE) -> Track:
	h.tm.observe(faction, target, pos, 0.8, 1.0, 0.0, 1.0, 10.0)
	var t := h.tm.find_track(faction, target)
	t.position = pos
	t.classification = classification
	t.identity = "HOSTILE" if classification >= Track.Classification.CLASS_KNOWN else "UNKNOWN"
	t.known_class = target.spec.short_name
	t.status = status
	t.domain = target.spec.domain
	t.has_kinematics = true
	t.course_deg = 0.0
	t.speed_kn = 10.0
	return t


func _orders_of(h: Harness, type: Order.Type) -> Array:
	return h.orders.filter(func(e: Dictionary) -> bool: return e["order"].type == type)


# --- No omniscience ----------------------------------------------------------------------

func test_ai_is_blind_to_undetected_enemies() -> void:
	var red := _ship("RED", Vector2.ZERO, 100.0, _asm(), 8)
	var blue := _ship("BLUE", Vector2(0.0, 5.0), 100.0)  # 5 nm away and completely undetected
	var h := _harness([red, blue])
	h.ai.tick(100.0)
	assert_true(_orders_of(h, Order.Type.ENGAGE).is_empty(), "no track means no shot, however close the enemy is")
	assert_eq(h.ai.state_name(red), "PATROL", "with no contact and no memory the AI just patrols")
	assert_eq(red.magazine_count("test_asm"), 8, "no rounds spent")
	h.free_all()


func test_ai_will_not_fire_at_an_unclassified_contact() -> void:
	var red := _ship("RED", Vector2.ZERO, 100.0, _asm(), 8)
	var blue := _ship("BLUE", Vector2(0.0, 20.0))
	var h := _harness([red, blue])
	_make_track(h, "RED", blue, Vector2(0.0, 20.0), Track.Classification.SURFACE)
	h.ai.tick(100.0)
	assert_true(_orders_of(h, Order.Type.ENGAGE).is_empty(), "a surface contact of unknown identity is not a target")
	assert_eq(h.ai.state_name(red), "INVESTIGATE", "it closes to identify instead")
	h.free_all()


func test_ai_will_not_fire_at_a_stale_track() -> void:
	var red := _ship("RED", Vector2.ZERO, 100.0, _asm(), 8)
	var blue := _ship("BLUE", Vector2(0.0, 20.0))
	var h := _harness([red, blue])
	_make_track(h, "RED", blue, Vector2(0.0, 20.0), Track.Classification.CLASS_KNOWN, Track.Status.STALE)
	h.ai.tick(100.0)
	assert_true(_orders_of(h, Order.Type.ENGAGE).is_empty(), "stale position data is not worth a salvo")
	h.free_all()


# --- Engagement --------------------------------------------------------------------------

func test_ai_engages_a_confirmed_hostile_in_envelope() -> void:
	var red := _ship("RED", Vector2.ZERO, 100.0, _asm(60.0), 8)
	var blue := _ship("BLUE", Vector2(0.0, 20.0))
	var h := _harness([red, blue])
	var t := _make_track(h, "RED", blue, Vector2(0.0, 20.0))
	h.ai.tick(100.0)
	var engagements := _orders_of(h, Order.Type.ENGAGE)
	assert_eq(engagements.size(), 1, "one salvo ordered")
	assert_eq(h.ai.state_name(red), "ENGAGE")
	var order: Order = engagements[0]["order"]
	assert_eq(order.track, t, "fired at the track, not at the unit")
	assert_eq(order.weapon_id, "test_asm")
	assert_true(order.salvo >= 1 and order.salvo <= 8)
	h.free_all()


func test_ai_holds_fire_when_a_salvo_is_already_on_the_way() -> void:
	var red := _ship("RED", Vector2.ZERO, 100.0, _asm(60.0), 8)
	var blue := _ship("BLUE", Vector2(0.0, 20.0))
	var h := _harness([red, blue])
	var t := _make_track(h, "RED", blue, Vector2(0.0, 20.0))
	h.ai.tick(100.0)
	assert_eq(_orders_of(h, Order.Type.ENGAGE).size(), 1)
	h.ai.tick(110.0)
	assert_eq(_orders_of(h, Order.Type.ENGAGE).size(), 1, "it waits and assesses rather than emptying the magazine")
	# The assessment window scales with how long the salvo takes to arrive, so a 20 nm shot with
	# a 480 kn weapon is not reassessed after the bare minimum wait.
	h.ai.tick(100.0 + AIController.ENGAGE_COOLDOWN_S + 10.0)
	assert_eq(_orders_of(h, Order.Type.ENGAGE).size(), 1, "still waiting for the first salvo to arrive")
	h.ai.tick(100.0 + 600.0)
	assert_eq(_orders_of(h, Order.Type.ENGAGE).size(), 2, "re-attacks once the assessment window has passed")
	assert_eq(t.id, h.tm.find_track("RED", blue).id)
	h.free_all()


func test_ai_closes_when_the_target_is_out_of_range() -> void:
	var red := _ship("RED", Vector2.ZERO, 100.0, _asm(20.0), 8)
	var blue := _ship("BLUE", Vector2(0.0, 60.0))
	var h := _harness([red, blue])
	_make_track(h, "RED", blue, Vector2(0.0, 60.0))
	h.ai.tick(100.0)
	assert_true(_orders_of(h, Order.Type.ENGAGE).is_empty(), "60 nm is outside a 20 nm weapon")
	assert_eq(h.ai.state_name(red), "SHADOW")
	var moves := _orders_of(h, Order.Type.MOVE)
	assert_eq(moves.size(), 1, "it manoeuvres to close the range")
	var goal: Vector2 = moves[0]["order"].target_pos
	assert_true(goal.y < 60.0 and goal.y > 0.0, "the destination lies between the ship and the contact")
	h.free_all()


# --- Survival ----------------------------------------------------------------------------

func test_ai_withdraws_when_heavily_damaged() -> void:
	var red := _ship("RED", Vector2.ZERO, 100.0, _asm(60.0), 8)
	red.health = 20.0  # 20 percent, below the withdrawal threshold
	var blue := _ship("BLUE", Vector2(0.0, 20.0))
	var h := _harness([red, blue])
	_make_track(h, "RED", blue, Vector2(0.0, 20.0))
	h.ai.tick(100.0)
	assert_eq(h.ai.state_name(red), "WITHDRAW")
	assert_true(_orders_of(h, Order.Type.ENGAGE).is_empty(), "a crippled ship breaks contact rather than trading")
	var courses := _orders_of(h, Order.Type.SET_COURSE)
	assert_eq(courses.size(), 1)
	assert_near(courses[0]["order"].heading_deg, 180.0, 1.0, "it runs directly away from the contact")
	var speeds := _orders_of(h, Order.Type.SET_SPEED)
	assert_near(speeds[0]["order"].speed_kn, 28.0, 0.01, "at maximum speed")
	h.free_all()


func test_ai_withdraws_when_out_of_strike_weapons() -> void:
	var red := _ship("RED", Vector2.ZERO, 100.0, _asm(60.0), 0)  # empty launcher
	var blue := _ship("BLUE", Vector2(0.0, 20.0))
	var h := _harness([red, blue])
	_make_track(h, "RED", blue, Vector2(0.0, 20.0))
	h.ai.tick(100.0)
	assert_eq(h.ai.state_name(red), "WITHDRAW", "no missiles left means no reason to stay")
	h.free_all()


func test_ai_turns_away_and_accelerates_when_a_round_is_inbound() -> void:
	var red := _ship("RED", Vector2.ZERO, 100.0, _asm(60.0), 8)
	var blue := _ship("BLUE", Vector2(0.0, 20.0))
	var h := _harness([red, blue])
	_make_track(h, "RED", blue, Vector2(0.0, 20.0))
	var inbound := Weapon.new()
	inbound.id = 700
	inbound.spec = _asm()
	inbound.faction = "BLUE"
	inbound.position = Vector2(0.0, 10.0)  # due north of the ship, closing
	inbound.acquired = red
	inbound.heading_deg = 180.0
	inbound.phase = Weapon.Phase.TERMINAL
	h.wm.in_flight.append(inbound)
	h.threats.mark_detected("RED", inbound, 100.0)
	h.ai.tick(100.0)
	assert_eq(h.ai.state_name(red), "DEFEND", "defence outranks attacking")
	var courses := _orders_of(h, Order.Type.SET_COURSE)
	assert_eq(courses.size(), 1)
	assert_near(courses[0]["order"].heading_deg, 180.0, 2.0, "turns away from the inbound bearing")
	var speeds := _orders_of(h, Order.Type.SET_SPEED)
	assert_near(speeds[0]["order"].speed_kn, 28.0, 0.01, "opens the geometry at speed")
	h.free_all()


# --- Standing orders ---------------------------------------------------------------------

func test_ai_follows_its_patrol_route() -> void:
	var red := _ship("RED", Vector2.ZERO, 100.0, _asm(), 8)
	red.patrol_route = [Vector2(0.0, 40.0), Vector2(40.0, 40.0)] as Array[Vector2]
	var h := _harness([red])
	h.ai.tick(100.0)
	assert_eq(h.ai.state_name(red), "PATROL")
	var moves := _orders_of(h, Order.Type.MOVE)
	assert_eq(moves.size(), 1)
	assert_eq(moves[0]["order"].target_pos, Vector2(0.0, 40.0), "heads for the first leg")
	h.free_all()


func test_ai_searches_the_last_known_position_after_losing_contact() -> void:
	var red := _ship("RED", Vector2.ZERO, 100.0, _asm(), 8)
	var blue := _ship("BLUE", Vector2(0.0, 30.0))
	var h := _harness([red, blue])
	var t := _make_track(h, "RED", blue, Vector2(0.0, 30.0))
	h.ai.tick(100.0)
	# Contact is lost: the track drops out of the picture entirely.
	t.status = Track.Status.LOST
	h.orders.clear()
	h.ai.tick(160.0)
	assert_eq(h.ai.state_name(red), "SEARCH", "it remembers where the contact was")
	var moves := _orders_of(h, Order.Type.MOVE)
	assert_true(not moves.is_empty(), "it goes looking")
	assert_eq(moves[0]["order"].target_pos, Vector2(0.0, 30.0), "at the last known position")
	h.free_all()


func test_every_ai_decision_leaves_through_the_normal_order_path() -> void:
	var red := _ship("RED", Vector2.ZERO, 100.0, _asm(60.0), 8)
	var blue := _ship("BLUE", Vector2(0.0, 20.0))
	var h := _harness([red, blue])
	_make_track(h, "RED", blue, Vector2(0.0, 20.0))
	h.ai.tick(100.0)
	assert_true(not h.orders.is_empty(), "the AI acts only by issuing Orders")
	for e: Dictionary in h.orders:
		assert_eq(e["unit"].faction, "RED", "it commands only its own ships")
	h.free_all()


func test_ai_only_commands_its_own_faction() -> void:
	var red := _ship("RED", Vector2.ZERO, 100.0, _asm(60.0), 8)
	var blue := _ship("BLUE", Vector2(0.0, 20.0), 100.0, _asm(60.0), 8)
	var h := _harness([red, blue], "RED")
	_make_track(h, "RED", blue, Vector2(0.0, 20.0))
	# Give BLUE a perfect picture too; the RED controller must ignore it.
	_make_track(h, "BLUE", red, Vector2.ZERO)
	h.ai.tick(100.0)
	assert_eq(blue.magazine_count("test_asm"), 8, "the RED controller never fires BLUE's weapons")
	assert_eq(h.ai.state_name(blue), "", "and keeps no state for ships it does not command")
	h.free_all()


# --- Submarines use the water ------------------------------------------------------------

func _boat(faction: String, pos: Vector2) -> Unit:
	var u := Unit.new()
	var p := PlatformSpec.new()
	p.short_name = "SSN Test"
	p.domain = "subsurface"
	p.max_speed_kn = 28.0
	p.cruise_speed_kn = 8.0
	p.max_depth_m = 400.0
	p.patrol_depth_m = 120.0
	p.depth_rate_m_s = 2.0
	p.health = 60.0
	u.spec = p
	u.faction = faction
	u.callsign = "%s-SSN" % faction
	u.position = pos
	u.health = p.health
	u.depth_m = 120.0
	u.ordered_depth_m = 120.0
	return u


func _water(bottom_m: float, layer_m: float) -> void:
	var env := {"bottom_m": bottom_m, "layer_depth_m": layer_m, "layer_strength": 0.8}
	Detection.set_environment(env)
	Bathymetry.load_for({"environment": env})


func _last_depth_order(h: Harness) -> float:
	var depths := _orders_of(h, Order.Type.SET_DEPTH)
	return depths[-1]["order"].depth_m if not depths.is_empty() else -1.0


func test_a_patrolling_boat_goes_under_the_layer_when_the_water_allows() -> void:
	_water(3000.0, 180.0)
	var boat := _boat("RED", Vector2.ZERO)
	var h := _harness([boat])
	h.ai.tick(100.0)
	assert_near(_last_depth_order(h), 180.0 + Acoustics.BELOW_LAYER_MARGIN_M, 0.5, "under the layer, not at the book patrol depth")
	h.free_all()
	_water(130.0, 180.0)
	boat = _boat("RED", Vector2.ZERO)
	h = _harness([boat])
	h.ai.tick(100.0)
	assert_near(_last_depth_order(h), 130.0 - Acoustics.KEEL_CLEARANCE_M, 0.5, "on the shelf there is no under, and the floor bounds it")
	h.free_all()
	Detection.set_environment({})
	Bathymetry.clear()


func test_a_boat_comes_back_above_the_layer_to_hold_a_surface_contact() -> void:
	_water(3000.0, 180.0)
	var boat := _boat("RED", Vector2.ZERO)
	boat.weapons.append(_asm(20.0))
	boat.magazines["test_asm"] = 4
	boat.depth_m = 15.0  # at periscope depth, on the link, so the group's picture reaches it
	boat.ordered_depth_m = 15.0
	var ship := _ship("BLUE", Vector2(0, 30))
	var h := _harness([boat, ship])
	_make_track(h, "RED", ship, Vector2(0, 30))
	h.ai.tick(100.0)
	assert_eq(h.ai.state_name(boat), "SHADOW", "a hostile it cannot shoot yet")
	assert_near(_last_depth_order(h), 120.0, 0.5, "patrol depth, where its arrays hear the surface")
	h.free_all()
	Detection.set_environment({})
	Bathymetry.clear()


func test_breakout_retains_radar_and_route_without_inventing_targets() -> void:
	var red := _ship("RED", Vector2.ZERO, 100.0, _asm(), 8)
	var esm := SensorSpec.new()
	esm.kind = "esm"
	red.sensors.append(esm)
	red.ai_posture = "breakout"
	red.radar_on = true
	red.patrol_route = [Vector2(0, 30)]
	var h := _harness([red])
	h.ai.tick(100)
	assert_true(red.radar_on, "a radar-active breakout retains the picture needed for defence")
	assert_true(not red.waypoints.is_empty(), "breakout still follows its gate route")
	assert_true(_orders_of(h, Order.Type.ENGAGE).is_empty(), "no track means no invented firing solution")
	h.free_all()


func test_silent_breakout_uses_held_bearings_to_build_picture_without_detouring() -> void:
	var red := _ship("RED", Vector2.ZERO, 100.0, _asm(), 8)
	var blue := _ship("BLUE", Vector2(0, 15))
	var esm := SensorSpec.new()
	esm.kind = "esm"
	red.sensors.append(esm)
	red.ai_posture = "breakout"
	red.radar_on = false
	red.patrol_route = [Vector2(0, 30)]
	var h := _harness([red, blue])
	h.ai.tick(100)
	assert_true(not red.radar_on, "silent transit remains silent with an empty picture")
	var t := _make_track(h, "RED", blue, Vector2(0, 15), Track.Classification.SURFACE)
	h.ai.tick(110)
	assert_true(red.radar_on, "a held unknown prompts radar classification while transiting")
	assert_eq(h.ai.state_name(red), "PATROL", "it continues toward the gate instead of chasing the contact")
	assert_true(_orders_of(h, Order.Type.ENGAGE).is_empty(), "unknown contact remains protected from fire")
	t.identity = "HOSTILE"
	t.classification = Track.Classification.CLASS_KNOWN
	h.ai.tick(120)
	assert_true(not _orders_of(h, Order.Type.ENGAGE).is_empty(), "confirmed contact permits a shot on the transit")
	assert_true(red.radar_on, "route following after the shot must not silence the radar again")
	h.free_all()


# --- ASW search and prosecution ----------------------------------------------------------

func _asw_torpedo() -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = "test_asw_torpedo"
	w.type = "torpedo"
	w.profile = "subsurface"
	w.target_types = ["subsurface"]
	w.min_range_nm = 0.5
	w.max_range_nm = 12.0
	w.speed_kn = 45.0
	return w


func _local_submarine_track(h: Harness, observer: Unit, target: Unit) -> Track:
	var c := SensorContact.make(target, target.position, 0.5, 0.8, 1.0, observer.position.distance_to(target.position), "sonar_passive", observer)
	h.tm.observe_contact(observer.faction, c, 0.0, 1.0)
	var t := h.tm.find_for(observer, target)
	t.classification = Track.Classification.CLASS_KNOWN
	t.identity = "HOSTILE"
	t.domain = "subsurface"
	return t


func test_armed_torpedo_only_submarine_prosecutes_its_local_contact() -> void:
	var boat := _boat("RED", Vector2.ZERO)
	var torpedo := _asw_torpedo()
	boat.weapons.append(torpedo)
	boat.magazines[torpedo.id] = 4
	var target := _boat("BLUE", Vector2(0, 3))
	var h := _harness([boat, target])
	_local_submarine_track(h, boat, target)
	assert_true(h.tm.get_tracks("RED").is_empty(), "the submerged boat's contact is local, not a shared shortcut")
	h.ai.tick(100.0)
	assert_eq(h.ai.state_name(boat), "ENGAGE", "torpedoes are usable ammunition, even without anti-ship missiles")
	var shots := _orders_of(h, Order.Type.ENGAGE)
	assert_eq(shots.size(), 1, "a confirmed local contact inside the torpedo envelope produces an order")
	if not shots.is_empty():
		assert_eq(shots[0]["order"].weapon_id, torpedo.id)
	h.free_all()


func test_submarine_with_empty_asw_magazine_withdraws_despite_surface_missiles() -> void:
	var boat := _boat("RED", Vector2.ZERO)
	var torpedo := _asw_torpedo()
	boat.weapons.append(torpedo)
	boat.magazines[torpedo.id] = 0
	boat.weapons.append(_asm())
	boat.magazines["test_asm"] = 8
	var target := _boat("BLUE", Vector2(0, 3))
	var h := _harness([boat, target])
	_local_submarine_track(h, boat, target)
	h.ai.tick(100.0)
	assert_eq(h.ai.state_name(boat), "WITHDRAW", "ammunition for the wrong domain cannot keep an unarmed submarine in the fight")
	assert_true(_orders_of(h, Order.Type.ENGAGE).is_empty())
	h.free_all()


func test_surface_air_defence_ship_engages_aircraft_with_its_remaining_sams() -> void:
	var sam := WeaponSpec.new()
	sam.id = "test_sam"
	sam.type = "sam"
	sam.target_types = ["air"]
	sam.min_range_nm = 1.0
	sam.max_range_nm = 60.0
	sam.speed_kn = 2200.0
	var ship := _ship("RED", Vector2.ZERO, 100.0, sam, 8)
	var aircraft := _asw_aircraft()
	aircraft.faction = "BLUE"
	aircraft.position = Vector2(0, 20)
	var h := _harness([ship, aircraft])
	_make_track(h, "RED", aircraft, aircraft.position)
	h.ai.tick(100.0)
	assert_eq(h.ai.state_name(ship), "ENGAGE", "a healthy air-defence ship with SAMs must not withdraw for lacking strike missiles")
	var shots := _orders_of(h, Order.Type.ENGAGE)
	assert_eq(shots.size(), 1, "a confirmed aircraft inside the SAM envelope produces an engagement")
	if not shots.is_empty():
		assert_eq(shots[0]["order"].weapon_id, sam.id)
	h.free_all()


func _asw_aircraft(can_hover := false, dipping_sonar := false) -> Unit:
	var a := Unit.new()
	a.spec = _platform(25.0)
	a.spec.domain = "air"
	a.spec.max_speed_kn = 300.0
	a.spec.cruise_speed_kn = 150.0
	a.spec.cruise_altitude_m = 400.0
	a.spec.max_altitude_m = 6000.0
	a.spec.can_hover = can_hover
	a.spec.sonobuoy_count = 16
	a.spec.sonobuoy_sensitivity_nm = 15.0
	a.faction = "RED"
	a.callsign = "RED-ASW"
	a.health = a.spec.health
	a.flight_state = Unit.FlightState.AIRBORNE
	a.altitude_m = a.spec.cruise_altitude_m
	a.ordered_altitude_m = a.altitude_m
	a.speed_kn = a.spec.cruise_speed_kn
	a.ordered_speed_kn = a.speed_kn
	a.sonobuoys = a.spec.sonobuoy_count
	var torpedo := _asw_torpedo()
	a.weapons.append(torpedo)
	a.magazines[torpedo.id] = 2
	if dipping_sonar:
		var sonar := SensorSpec.new()
		sonar.kind = "sonar"
		sonar.requires_hover = true
		sonar.passive_sensitivity_nm = 15.0
		a.sensors.append(sonar)
	return a


func test_routed_asw_patrol_saves_buoys_for_station_and_spaces_its_field() -> void:
	var a := _asw_aircraft()
	a.patrol_route = [Vector2(0, 40), Vector2(30, 40)]
	var h := _harness([a])
	h.ai.tick(100.0)
	a.position = Vector2(0, 20)
	h.ai.tick(400.0)
	assert_true(_orders_of(h, Order.Type.DEPLOY_SONOBUOY).is_empty(), "the ferry leg must not consume the barrier's buoy inventory")
	a.position = Vector2(0, 40)
	h.ai.tick(1000.0)
	assert_eq(_orders_of(h, Order.Type.DEPLOY_SONOBUOY).size(), 1, "arrival begins the field without needing an enemy datum")
	assert_true(not a.waypoints.is_empty(), "laying the field preserves the authored patrol")
	if not a.waypoints.is_empty():
		assert_eq(a.waypoints[0], Vector2(30, 40))
	a.position = Vector2(4.1, 40)
	h.ai.tick(1000.0 + AIController.BUOY_INTERVAL_S)
	assert_eq(_orders_of(h, Order.Type.DEPLOY_SONOBUOY).size(), 1, "spatial separation alone cannot bypass the drop interval")
	a.position = Vector2(3.9, 40)
	h.ai.tick(1001.0 + AIController.BUOY_INTERVAL_S)
	assert_eq(_orders_of(h, Order.Type.DEPLOY_SONOBUOY).size(), 1, "elapsed time alone cannot duplicate the same station")
	a.position = Vector2(4.1, 40)
	h.ai.tick(1002.0 + AIController.BUOY_INTERVAL_S)
	assert_eq(_orders_of(h, Order.Type.DEPLOY_SONOBUOY).size(), 2, "a separated station after the interval extends the field")
	h.ai.tick(1003.0 + 2.0 * AIController.BUOY_INTERVAL_S)
	assert_eq(_orders_of(h, Order.Type.DEPLOY_SONOBUOY).size(), 2, "remaining at that station must not repeatedly lay buoys")
	h.free_all()


func test_asw_aircraft_searches_around_a_lost_datum_with_buoys() -> void:
	var a := _asw_aircraft()
	var target := _boat("BLUE", Vector2(0, 30))
	var h := _harness([a, target])
	var t := _make_track(h, "RED", target, target.position)
	h.ai.tick(100.0)
	t.status = Track.Status.LOST
	a.position = target.position
	a.waypoints.clear()  # arrived at the last reported datum
	h.orders.clear()
	h.ai.tick(160.0)
	assert_eq(h.ai.state_name(a), "SEARCH")
	assert_true(not a.waypoints.is_empty(), "search continues beyond the datum")
	if not a.waypoints.is_empty():
		assert_true(a.waypoints[0].distance_to(t.position) > 1.0, "the next station surrounds the last report instead of remaining on it")
		a.position = a.waypoints[0]
		a.waypoints.clear()
		h.ai.tick(320.0)
		assert_eq(_orders_of(h, Order.Type.DEPLOY_SONOBUOY).size(), 1, "arrival at the search station lays a buoy despite having lost the contact")
	h.free_all()


func test_dipping_search_resumes_its_next_leg_after_listening() -> void:
	var a := _asw_aircraft(true, true)
	var h := _harness([a])
	h.ai.tick(100.0)
	assert_true(not a.waypoints.is_empty())
	if a.waypoints.is_empty():
		h.free_all()
		return
	a.position = a.waypoints[0]
	a.waypoints.clear()
	h.ai.tick(200.0)
	h.ai.tick(201.0)
	assert_near(a.ordered_speed_kn, 0.0, 0.01, "a helicopter with a dipping set stops to listen at the station")
	assert_true(a.ordered_altitude_m <= Unit.HOVER_ALTITUDE_M, "the transducer can be lowered only from low hover")
	var after_dip := 202.0 + AIController.DIP_DURATION_S
	h.ai.tick(after_dip)
	assert_true(not a.waypoints.is_empty(), "dip completion restores the next search leg")
	if not a.waypoints.is_empty():
		var next_station := a.waypoints[0]
		assert_true(next_station.distance_to(a.position) > 1.0, "the aircraft proceeds to a different listening station")
		h.ai.tick(after_dip + 1.0)
		assert_true(not a.waypoints.is_empty(), "the following decision must not cancel the restored leg for another dip")
		if not a.waypoints.is_empty():
			assert_eq(a.waypoints[0], next_station)
	assert_true(a.ordered_speed_kn > Unit.HOVER_SPEED_KN, "it accelerates out of hover instead of cycling dips forever")
	h.free_all()


func test_buoy_only_helicopter_search_does_not_invent_a_dipping_set() -> void:
	var a := _asw_aircraft(true, false)  # SH-60B-style buoy fit
	var h := _harness([a])
	h.ai.tick(100.0)
	assert_true(not a.waypoints.is_empty())
	if a.waypoints.is_empty():
		h.free_all()
		return
	a.position = a.waypoints[0]
	a.waypoints.clear()
	h.orders.clear()
	h.ai.tick(200.0)
	h.ai.tick(201.0)
	assert_true(not _orders_of(h, Order.Type.DEPLOY_SONOBUOY).is_empty(), "the buoy-only helicopter still searches acoustically")
	assert_true(not a.waypoints.is_empty(), "after its drop it continues to the next station")
	assert_true(a.ordered_speed_kn > Unit.HOVER_SPEED_KN, "hover capability alone must not trigger a sonar dip")
	h.free_all()
