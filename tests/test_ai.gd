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
