extends TestCase
## An enemy that fights back: a unit under fire answers, picks shots the launcher will take, and a
## boat works its contact into a solution and shoots. Every contact is a plot on RED's picture.

const DT := 0.25


func _platform(hp := 100.0) -> PlatformSpec:
	var p := PlatformSpec.new()
	p.short_name = "DDG Test"
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


func _ship(callsign: String, pos: Vector2, weapon: WeaponSpec = null, rounds := 8, faction := "RED") -> Unit:
	var u := Unit.new()
	u.spec = _platform()
	u.faction = faction
	u.callsign = callsign
	u.position = pos
	u.health = 100.0
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
		um.clear()
		ai.free()
		wm.free()
		threats.free()
		tm.free()
		um.free()


func _harness(units: Array, plans: Array = []) -> Harness:
	Terrain.clear()
	var h := Harness.new()
	h.um = UnitManager.new()
	for u: Unit in units:
		h.um.add_unit(u)
	h.tm = TrackManager.new()
	h.threats = ThreatManager.new()
	h.wm = WeaponManager.new()
	h.wm.unit_manager = h.um
	h.wm.track_manager = h.tm
	h.wm.rng.seed = 5
	h.ai = AIController.new()
	h.ai.faction = "RED"
	h.ai.unit_manager = h.um
	h.ai.track_manager = h.tm
	h.ai.threat_manager = h.threats
	h.ai.weapon_manager = h.wm
	h.ai.configure_plans(plans)
	h.um.order_issued.connect(func(u: Unit, o: Order) -> void: h.orders.append({"unit": u, "order": o}))
	return h


## A contact on RED's plot with no truth behind it.
func _plot(h: Harness, id: String, pos: Vector2, category := "frigate", cls := "FFG Test") -> Track:
	var t := Track.new()
	t.id = id
	t.owner_faction = "RED"
	t.position = pos
	t.classification = Track.Classification.CLASS_KNOWN
	t.identity = "HOSTILE"
	t.domain = "surface"
	t.known_category = category
	t.known_class = cls
	t.status = Track.Status.ACTIVE
	t.has_kinematics = true
	t.course_deg = 90.0
	t.speed_kn = 12.0
	if not h.tm._tracks.has("RED"):
		h.tm._tracks["RED"] = []
	h.tm._tracks["RED"].append(t)
	return t


func _orders_of(h: Harness, type: Order.Type, u: Unit = null) -> Array:
	return h.orders.filter(func(e: Dictionary) -> bool: return e["order"].type == type and (u == null or e["unit"] == u))


## A round of BLUE's closing on `target`, seen by RED.
func _inbound(h: Harness, target: Unit, from: Vector2) -> Weapon:
	var w := Weapon.new()
	w.id = 700
	w.spec = _asm()
	w.faction = "BLUE"
	w.position = from
	w.acquired = target
	w.heading_deg = Geo.bearing_deg(from, target.position)
	w.phase = Weapon.Phase.TERMINAL
	h.wm.in_flight.append(w)
	h.threats.mark_detected("RED", w, 100.0)
	return w


# --- A unit under fire shoots back ---------------------------------------------------------

func test_a_striker_waiting_on_its_plan_answers_the_ship_that_is_shooting_at_it() -> void:
	var red := _ship("RED-1", Vector2.ZERO, _asm(60.0))
	# Shipping is what the plan is after and none is held yet, so the group is still looking.
	var h := _harness([red], [{"id": "plan", "faction": "RED", "kind": "attack_shipping", "units": ["RED-1"], "priorities": ["merchant"], "threat_nm": 4, "search_window_s": 3000}])
	var frigate := _plot(h, "T4001", Vector2(0, 7))
	h.ai.tick(100.0)
	assert_true(_orders_of(h, Order.Type.ENGAGE).is_empty(), "a frigate outside the threat radius is left alone while nothing shoots")
	# The frigate's rounds start landing: the striker knows it is being shot at.
	h.wm.weapon_impact.emit("BLUE", _asm(), red, true)
	h.ai.tick(102.0)
	var shots := _orders_of(h, Order.Type.ENGAGE)
	assert_eq(shots.size(), 1, "a ship being shot at shoots back at the hostile it holds and can reach")
	if not shots.is_empty():
		assert_eq(shots[0]["order"].track, frigate)
	h.free_all()


func test_a_ship_turning_away_from_a_round_still_fires_at_the_shooter() -> void:
	var red := _ship("RED-1", Vector2.ZERO, _asm(60.0))
	var blue := _ship("BLUE-1", Vector2(0, 20), null, 0, "BLUE")
	var h := _harness([red, blue])
	var t := _plot(h, "T4002", Vector2(0, 20))
	_inbound(h, red, Vector2(0, 10))
	h.ai.tick(100.0)
	assert_eq(h.ai.state_name(red), "DEFEND", "the round coming at it still comes first")
	var shots := _orders_of(h, Order.Type.ENGAGE)
	assert_eq(shots.size(), 1, "and the ship fights back while it turns")
	if not shots.is_empty():
		assert_eq(shots[0]["order"].track, t)
	h.free_all()


func test_weapons_tight_answers_fire_and_weapons_hold_does_not() -> void:
	var red := _ship("RED-1", Vector2.ZERO, _asm(60.0))
	red.roe = Unit.Roe.TIGHT
	var h := _harness([red])
	_plot(h, "T4003", Vector2(0, 20))
	h.ai.tick(100.0)
	assert_true(_orders_of(h, Order.Type.ENGAGE).is_empty(), "weapons tight starts nothing")
	h.wm.weapon_impact.emit("BLUE", _asm(), red, false)
	h.ai.tick(102.0)
	assert_eq(_orders_of(h, Order.Type.ENGAGE).size(), 1, "but a ship shot at under weapons tight shoots back at a hostile")
	h.free_all()
	var held := _ship("RED-1", Vector2.ZERO, _asm(60.0))
	held.roe = Unit.Roe.HOLD
	var h2 := _harness([held])
	_plot(h2, "T4004", Vector2(0, 20))
	h2.wm.weapon_impact.emit("BLUE", _asm(), held, true)
	h2.ai.tick(102.0)
	assert_true(_orders_of(h2, Order.Type.ENGAGE).is_empty(), "an explicit hold is obeyed even under fire")
	h2.free_all()


func test_under_fire_wears_off() -> void:
	var red := _ship("RED-1", Vector2.ZERO, _asm(60.0))
	red.roe = Unit.Roe.TIGHT
	var h := _harness([red])
	_plot(h, "T4005", Vector2(0, 20))
	h.wm.now_s = 100.0
	h.wm.weapon_impact.emit("BLUE", _asm(), red, false)
	h.ai.tick(100.0 + AIController.UNDER_FIRE_MEMORY_S + 10.0)
	assert_true(_orders_of(h, Order.Type.ENGAGE).is_empty(), "long after the last round a tight ship starts nothing again")
	h.free_all()


# --- Shots the launcher will take ----------------------------------------------------------

func _sam(id: String, guidance: String) -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = id
	w.display_name = id
	w.type = "sam"
	w.guidance = guidance
	w.target_types = ["air", "missile"]
	w.max_range_nm = 20.0
	w.min_range_nm = 0.5
	w.speed_kn = 1500.0
	w.seeker_range_nm = 5.0
	w.intercept_max_altitude_m = 20000.0
	w.base_pk = 0.7
	w.salvo_default = 2
	return w


func test_a_ship_held_silent_fires_the_weapon_that_needs_no_radar_instead_of_asking_again() -> void:
	var red := _ship("RED-1", Vector2.ZERO)
	var guided := _sam("test_sarh_sam", "semi_active_radar")
	var heat := _sam("test_ir_sam", "infrared")
	red.weapons.append(guided)
	red.magazines[guided.id] = 8
	red.weapons.append(heat)
	red.magazines[heat.id] = 8
	red.emcon = Unit.Emcon.SILENT
	red.radar_on = false
	var h := _harness([red])
	var jet := _plot(h, "T4010", Vector2(0, 8), "fighter", "Fighter")
	jet.domain = "air"
	jet.altitude_m = 3000.0
	h.ai.tick(100.0)
	var shots := _orders_of(h, Order.Type.ENGAGE)
	assert_eq(shots.size(), 1, "one shot at the jet")
	if not shots.is_empty():
		assert_eq(shots[0]["order"].weapon_id, heat.id, "a radar held silent cannot guide the first missile, so the second goes")
		assert_true(h.wm.engagement_check(red, red.get_weapon(shots[0]["order"].weapon_id), jet, 100.0)["ok"], "and the launcher takes it")
	h.free_all()


func test_a_ship_with_its_radar_merely_off_lights_it_for_the_better_missile() -> void:
	var red := _ship("RED-1", Vector2.ZERO)
	var guided := _sam("test_sarh_sam", "semi_active_radar")
	var heat := _sam("test_ir_sam", "infrared")
	red.weapons.append(guided)
	red.magazines[guided.id] = 8
	red.weapons.append(heat)
	red.magazines[heat.id] = 8
	red.radar_on = false
	var h := _harness([red])
	var jet := _plot(h, "T4011", Vector2(0, 8), "fighter", "Fighter")
	jet.domain = "air"
	jet.altitude_m = 3000.0
	h.ai.tick(100.0)
	var shots := _orders_of(h, Order.Type.ENGAGE)
	assert_eq(shots.size(), 1)
	if not shots.is_empty():
		assert_eq(shots[0]["order"].weapon_id, guided.id, "the switch is the captain's to make, so the first choice stands")
	assert_true(red.radar_on, "and the radar is lit for it")
	h.free_all()


# --- A boat works its contact and shoots ---------------------------------------------------

func _boat(pos: Vector2) -> Unit:
	var u := Unit.new()
	var p := PlatformSpec.new()
	p.short_name = "SSK Test"
	p.domain = "subsurface"
	p.max_speed_kn = 17.0
	p.cruise_speed_kn = 6.0
	p.max_depth_m = 300.0
	p.patrol_depth_m = 90.0
	p.depth_rate_m_s = 2.0
	p.health = 60.0
	u.spec = p
	u.faction = "RED"
	u.callsign = "RED-SSK"
	u.position = pos
	u.health = p.health
	u.depth_m = 90.0
	u.ordered_depth_m = 90.0
	u.heading_deg = 0.0
	return u


func _heavyweight(wire := true) -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = "test_heavyweight"
	w.type = "torpedo"
	w.profile = "subsurface"
	w.guidance = "acoustic_homing"
	w.target_types = ["surface", "subsurface"]
	w.min_range_nm = 1.3
	w.max_range_nm = 22.0
	w.speed_kn = 50.0
	w.seeker_range_nm = 2.2
	w.midcourse_updates = wire
	return w


## A surface ship held on the boat's own sonar as a line of bearing, `quality` its range solution.
## A boat off the link holds its own picture, so the plot is built the way its sonar builds it.
func _bearing_plot(h: Harness, boat: Unit, id: String, pos: Vector2, quality: float) -> Track:
	var ship := _ship("BLUE-%s" % id, pos, null, 0, "BLUE")
	h.um.add_unit(ship)
	var c := SensorContact.make(ship, pos, 0.5, 0.8, 1.0, boat.position.distance_to(pos), "sonar_passive", boat)
	h.tm.observe_contact(boat.faction, c, 0.0, 1.0)
	var t := h.tm.find_for(boat, ship)
	t.position = pos
	t.classification = Track.Classification.CLASS_KNOWN
	t.identity = "HOSTILE"
	t.known_category = "destroyer"
	t.known_class = "DDG Test"
	t.domain = "surface"
	t.status = Track.Status.ACTIVE
	t.bearing_only = true
	t.tma_quality = quality
	t.has_kinematics = quality >= Track.FIRE_CONTROL_SOLUTION_QUALITY
	return t


func _courses(h: Harness, u: Unit) -> Array:
	return _orders_of(h, Order.Type.SET_COURSE, u).map(func(e: Dictionary) -> float: return e["order"].heading_deg)


func test_a_boat_holding_only_a_bearing_works_legs_either_side_of_it() -> void:
	var boat := _boat(Vector2.ZERO)
	var fish := _heavyweight()
	boat.weapons.append(fish)
	boat.magazines[fish.id] = 14
	var h := _harness([boat])
	_bearing_plot(h, boat, "T4020", Vector2(0, 12), 0.0)  # due north, range unknown
	var t0 := 4.0 * AIController.TMA_LEG_S
	h.ai.tick(t0)
	h.ai.tick(t0 + AIController.TMA_LEG_S)
	h.ai.tick(t0 + 2.0 * AIController.TMA_LEG_S)
	assert_true(_orders_of(h, Order.Type.ENGAGE).is_empty(), "no shot on a bare line")
	var courses := _courses(h, boat)
	assert_eq(courses.size(), 3, "a new leg each time")
	if courses.size() == 3:
		var first := Geo.heading_delta(0.0, courses[0])
		var second := Geo.heading_delta(0.0, courses[1])
		assert_true(absf(first) >= 30.0 and absf(second) >= 30.0, "each leg well off the line of bearing (%.0f, %.0f)" % [first, second])
		assert_true(signf(first) != signf(second), "on alternate sides of it, so the bearing rate changes between legs")
		assert_near(courses[2], courses[0], 1.0, "and back again")
	h.free_all()


func test_a_boat_fires_a_wire_guided_fish_on_a_rough_range_well_inside_its_reach() -> void:
	var boat := _boat(Vector2.ZERO)
	var fish := _heavyweight()
	boat.weapons.append(fish)
	boat.magazines[fish.id] = 14
	var h := _harness([boat])
	# Nine miles at fifty knots is an eleven-minute run, and the plot's range is still rough.
	var t := _bearing_plot(h, boat, "T4021", Vector2(0, 9), 0.35)
	h.ai.tick(1000.0)
	var shots := _orders_of(h, Order.Type.ENGAGE)
	assert_eq(shots.size(), 1, "a boat with a wire on its fish shoots at nine miles on a rough solution")
	if not shots.is_empty():
		assert_eq(shots[0]["order"].track, t)
	h.free_all()


func test_a_free_running_fish_waits_for_a_solution_and_a_short_run() -> void:
	var boat := _boat(Vector2.ZERO)
	var fish := _heavyweight(false)
	boat.weapons.append(fish)
	boat.magazines[fish.id] = 14
	var h := _harness([boat])
	_bearing_plot(h, boat, "T4022", Vector2(0, 9), 0.35)
	h.ai.tick(1000.0)
	assert_true(_orders_of(h, Order.Type.ENGAGE).is_empty(), "nothing steers it after it leaves, so it is not sent eleven minutes down a rough line")
	h.free_all()


func test_a_wire_guided_fish_still_waits_when_the_rough_range_is_near_the_edge_of_its_reach() -> void:
	var boat := _boat(Vector2.ZERO)
	var fish := _heavyweight()
	boat.weapons.append(fish)
	boat.magazines[fish.id] = 14
	var h := _harness([boat])
	_bearing_plot(h, boat, "T4023", Vector2(0, 16), 0.35)
	h.ai.tick(1000.0)
	assert_true(_orders_of(h, Order.Type.ENGAGE).is_empty(), "sixteen miles on a rough range could be twenty-five")
	h.free_all()

