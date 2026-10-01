extends TestCase
## The standing attack: one order closes a platform to weapon range on the held plot, chooses
## the weapon, fires, and keeps firing until the contact is destroyed or lost. The task reads
## the plot only; the one truth lookup is the manager ending every attack on a unit that sank.

const DT := 0.25


func _platform(hp := 100.0, air := false) -> PlatformSpec:
	var p := PlatformSpec.new()
	p.short_name = "Test"
	p.max_speed_kn = 28.0
	p.cruise_speed_kn = 14.0
	p.turn_rate_deg_s = 6.0
	p.accel_kn_s = 1.0
	p.health = hp
	if air:
		p.domain = "air"
		p.max_speed_kn = 400.0
		p.cruise_speed_kn = 300.0
		p.cruise_altitude_m = 3000.0
		p.max_altitude_m = 9000.0
		p.altitude_rate_m_s = 20.0
		p.endurance_s = 36000.0
		p.turn_rate_deg_s = 3.0
	return p


func _asm(max_range := 60.0, rounds_damage := 40.0) -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = "test_asm"
	w.display_name = "Test ASM"
	w.short_name = "ASM"
	w.type = "asm"
	w.max_range_nm = max_range
	w.min_range_nm = 2.0
	w.speed_kn = 480.0
	w.turn_rate_deg_s = 30.0
	w.seeker_range_nm = 8.0
	w.damage = rounds_damage
	w.base_pk = 1.0
	w.salvo_default = 2
	w.launch_interval_s = 4.0
	return w


func _gun() -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = "test_gun"
	w.display_name = "Test gun"
	w.short_name = "GUN"
	w.type = "gun"
	w.max_range_nm = 10.0
	w.min_range_nm = 0.0
	w.speed_kn = 1500.0
	w.seeker_range_nm = 0.0
	w.damage = 15.0
	w.base_pk = 1.0
	w.salvo_default = 4
	w.launch_interval_s = 2.0
	return w


func _torpedo() -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = "test_torpedo"
	w.display_name = "Test torpedo"
	w.type = "torpedo"
	w.target_types = PackedStringArray(["subsurface", "surface"])
	w.max_range_nm = 12.0
	w.min_range_nm = 0.5
	w.speed_kn = 50.0
	w.damage = 90.0
	w.base_pk = 1.0
	w.salvo_default = 2
	return w


func _unit(faction: String, pos: Vector2, hp := 100.0, weapons: Array = [], rounds := 8, air := false) -> Unit:
	var u := Unit.new()
	u.spec = _platform(hp, air)
	u.faction = faction
	u.callsign = "%s-%d" % [faction, randi() % 1000]
	u.position = pos
	u.health = hp
	u.heading_deg = 0.0
	u.ordered_heading_deg = 0.0
	if air:
		u.flight_state = Unit.FlightState.AIRBORNE
		u.fuel_s = u.spec.endurance_s
		u.altitude_m = u.spec.cruise_altitude_m
	for w: WeaponSpec in weapons:
		u.weapons.append(w)
		u.magazines[w.id] = rounds
	return u


func _track(target: Unit, pos: Vector2, identity := "HOSTILE") -> Track:
	var t := Track.new()
	t.id = "T1076"
	t.owner_faction = "BLUE"
	t.truth = target
	t.position = pos
	t.status = Track.Status.ACTIVE
	t.domain = target.spec.domain
	t.identity = identity
	t.classification = Track.Classification.CLASS_KNOWN if identity != "UNKNOWN" else Track.Classification.SURFACE
	t.known_class = target.spec.short_name
	return t


class Harness:
	extends RefCounted
	var um: UnitManager
	var wm: WeaponManager
	var now := 0.0
	var ended: Array = []

	func advance(seconds: float) -> void:
		var steps := int(round(seconds / 0.25))
		for i in steps:
			now += 0.25
			um.tick(0.25, now)
			wm.tick(0.25, now)

	## Ticks until the predicate holds, at most `limit_s` of simulation time. Returns success.
	func until(predicate: Callable, limit_s: float) -> bool:
		var steps := int(round(limit_s / 0.25))
		for i in steps:
			if predicate.call():
				return true
			now += 0.25
			um.tick(0.25, now)
			wm.tick(0.25, now)
		return predicate.call()

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
	h.wm.rng.seed = 7
	h.um.weapon_manager = h.wm
	h.um.attack_ended.connect(func(u: Unit, t: Track, reason: String) -> void: h.ended.append([u, t, reason]))
	return h


# --- The loop ---------------------------------------------------------------------------

func test_attack_order_plots_the_intercept_then_closes_and_fires_without_further_orders() -> void:
	var asm := _asm(60.0)
	var shooter := _unit("BLUE", Vector2.ZERO, 100.0, [asm])
	var target := _unit("RED", Vector2(0, 80))
	var t := _track(target, Vector2(0, 80))
	var h := _harness([shooter, target])
	assert_true(h.um.issue_order(shooter, Order.attack(t)), "a classified hostile is a legal attack even out of range")
	assert_eq(shooter.attack_track, t, "the task is recorded without a simulation tick")
	assert_eq(shooter.attack_phase, "Intercept track")
	assert_eq(shooter.waypoints.size(), 1, "the intercept leg is plotted while still paused")
	assert_near(shooter.waypoints[0].distance_to(t.position), 48.0, 0.01, "to a standoff inside the envelope, not its edge")
	assert_eq(shooter.magazines[asm.id], 8, "nothing is fired out of range")
	assert_eq(shooter.ordered_speed_kn, shooter.spec.cruise_speed_kn, "a stopped ship gets under way at cruise")
	h.um.issue_order(shooter, Order.set_speed(28.0))
	var fired := h.until(func() -> bool: return shooter.attack_rounds_fired > 0, 3600.0)
	assert_true(fired, "the ship closes and fires on its own")
	assert_true(shooter.position.distance_to(t.position) <= 60.5, "the salvo goes as soon as the contact is in range")
	assert_true(shooter.position.distance_to(t.position) > 55.0, "not after a needless run to the standoff")
	assert_eq(shooter.magazines[asm.id], 6, "one salvo of the weapon's default size")
	assert_true(shooter.attack_phase.begins_with("Engaging track"), shooter.attack_phase)
	assert_true(h.ended.is_empty(), "the task is still running while rounds are away")
	var destroyed := h.until(func() -> bool: return not h.ended.is_empty(), 1800.0)
	assert_true(destroyed, "the attack keeps firing until the target is sunk")
	assert_eq(h.ended.size(), 1, "one completion report per task")
	assert_eq(h.ended[0], [shooter, t, "Target destroyed"])
	assert_eq(shooter.attack_track, null)
	assert_eq(shooter.attack_result, "Target destroyed")
	assert_eq(shooter.attack_track_id, t.id, "the result stays readable against the track it concerned")
	assert_true(not target.alive)
	assert_eq(shooter.magazines[asm.id], 4, "a second salvo was needed; nothing beyond it")
	var left: int = shooter.magazines[asm.id]
	h.advance(120.0)
	assert_eq(shooter.magazines[asm.id], left, "a finished attack spends nothing more")
	assert_true(shooter.waypoints.is_empty(), "the ship holds where the attack ended")
	h.free_all()


func test_in_range_attack_fires_at_once_holds_station_and_assesses_between_salvos() -> void:
	var asm := _asm(60.0)
	var shooter := _unit("BLUE", Vector2.ZERO, 100.0, [asm])
	var target := _unit("RED", Vector2(0, 30), 500.0)
	var t := _track(target, Vector2(0, 30))
	var h := _harness([shooter, target])
	h.um.issue_order(shooter, Order.attack(t))
	assert_true(shooter.waypoints.is_empty(), "inside the envelope there is no intercept leg")
	h.advance(DT)
	assert_eq(shooter.attack_rounds_fired, 2, "the first salvo goes on the first tick")
	assert_eq(shooter.ordered_speed_kn, 0.0, "the ship holds station inside the envelope")
	assert_eq(shooter.attack_phase, "Engaging track")
	h.advance(DT)
	assert_true(shooter.attack_phase.begins_with("Engaging track · ") and shooter.attack_phase.ends_with(" away"), shooter.attack_phase)
	var arrived := h.until(func() -> bool: return h.wm.in_flight.all(func(w: Weapon) -> bool: return w.phase == Weapon.Phase.DEAD), 900.0)
	assert_true(arrived, "the salvo resolves")
	h.advance(DT)
	assert_eq(shooter.attack_rounds_fired, 2, "no second salvo until the plot has been read")
	assert_eq(shooter.attack_phase, "Engaging track · assessing")
	h.advance(UnitManager.ATTACK_ASSESS_S + DT)
	assert_eq(shooter.attack_rounds_fired, 4, "then the next salvo goes")
	assert_true(target.alive and target.health < 500.0, "the target is hurt, not sunk, so the attack continues")
	assert_true(h.ended.is_empty())
	assert_true(shooter.position.length() < 0.5, "the ship never moved: it was in range from the start")
	h.free_all()


func test_attack_falls_to_the_next_weapon_when_a_magazine_empties() -> void:
	var asm := _asm(60.0)
	var gun := _gun()
	var shooter := _unit("BLUE", Vector2.ZERO, 100.0, [asm, gun], 20)
	shooter.magazines[asm.id] = 2
	var target := _unit("RED", Vector2(0, 20), 800.0)
	var t := _track(target, Vector2(0, 20))
	var h := _harness([shooter, target])
	h.um.issue_order(shooter, Order.attack(t))
	h.um.issue_order(shooter, Order.set_speed(28.0))
	assert_eq(shooter.attack_track, t, "a speed order supports the attack rather than replacing it")
	h.advance(DT)
	assert_eq(shooter.magazines[asm.id], 0, "the missiles go first: longest reach, guns last")
	var closing := h.until(func() -> bool: return shooter.attack_phase == "Intercept track", 1200.0)
	assert_true(closing, "with the missiles gone the ship closes to gun range")
	assert_eq(shooter.waypoints.size(), 1)
	assert_near(shooter.waypoints[0].distance_to(t.position), 8.0, 0.01, "to the gun's standoff")
	assert_eq(shooter.ordered_speed_kn, 28.0, "at the speed the commander chose")
	var gunfire := h.until(func() -> bool: return shooter.magazines[gun.id] < 20, 4000.0)
	assert_true(gunfire, "and opens fire with the gun")
	assert_eq(shooter.magazines[gun.id], 16, "a gun salvo of its default size")
	assert_true(shooter.position.distance_to(t.position) <= 10.5, "fired as soon as the gun reaches")
	h.free_all()


func test_magazines_empty_ends_the_task_with_a_report() -> void:
	var asm := _asm(60.0)
	var shooter := _unit("BLUE", Vector2.ZERO, 100.0, [asm], 2)
	var target := _unit("RED", Vector2(0, 30), 800.0)
	var t := _track(target, Vector2(0, 30))
	var h := _harness([shooter, target])
	h.um.issue_order(shooter, Order.attack(t))
	var done := h.until(func() -> bool: return not h.ended.is_empty(), 1200.0)
	assert_true(done)
	assert_eq(h.ended[0][2], "Magazines empty")
	assert_eq(shooter.attack_result, "Magazines empty")
	h.free_all()


# --- Rejections -------------------------------------------------------------------------

func test_attack_is_refused_for_protected_lost_unidentified_and_unarmed_cases() -> void:
	var asm := _asm()
	var shooter := _unit("BLUE", Vector2.ZERO, 100.0, [asm])
	var target := _unit("RED", Vector2(0, 30))
	assert_eq(UnitManager.attack_rejection(shooter, _track(target, Vector2(0, 30), "NEUTRAL")), "Protected identity")
	assert_eq(UnitManager.attack_rejection(shooter, _track(target, Vector2(0, 30), "FRIENDLY")), "Protected identity")
	var lost := _track(target, Vector2(0, 30))
	lost.status = Track.Status.LOST
	assert_eq(UnitManager.attack_rejection(shooter, lost), "Contact lost")
	var unknown := _track(target, Vector2(0, 30), "UNKNOWN")
	unknown.domain = ""
	unknown.classification = Track.Classification.UNKNOWN
	assert_eq(UnitManager.attack_rejection(shooter, unknown), "Identify contact first")
	unknown.domain = "surface"
	assert_eq(UnitManager.attack_rejection(shooter, unknown), "", "weapons free may attack an unidentified surface contact")
	shooter.roe = Unit.Roe.TIGHT
	assert_eq(UnitManager.attack_rejection(shooter, unknown), "Identify contact first (weapons tight)")
	assert_eq(UnitManager.attack_rejection(shooter, _track(target, Vector2(0, 30))), "", "weapons tight may attack a hostile")
	shooter.roe = Unit.Roe.HOLD
	assert_eq(UnitManager.attack_rejection(shooter, _track(target, Vector2(0, 30))), "Weapons hold")
	shooter.roe = Unit.Roe.FREE
	var sub := _unit("RED", Vector2(0, 5))
	sub.spec.domain = "subsurface"
	var sub_track := _track(sub, Vector2(0, 5))
	assert_eq(UnitManager.attack_rejection(shooter, sub_track), "No suitable weapon aboard", "an anti-ship missile cannot attack a submarine")
	shooter.magazines[asm.id] = 0
	assert_eq(UnitManager.attack_rejection(shooter, _track(target, Vector2(0, 30))), "Magazines empty")
	shooter.magazines[asm.id] = 8
	var bearing := _track(target, Vector2(0, 30))
	bearing.bearing_only = true
	bearing.tma_quality = 0.0
	assert_eq(UnitManager.attack_rejection(shooter, bearing), "Contact range unresolved", "a missile needs a range")
	var boat := _unit("BLUE", Vector2.ZERO, 100.0, [_torpedo()])
	assert_eq(UnitManager.attack_rejection(boat, bearing), "", "a torpedo may run down a bearing")
	assert_eq(UnitManager.attack_rejection(shooter, _track(target, Vector2(0, 30)), "test_gun"), "Weapon not aboard")
	assert_eq(UnitManager.attack_rejection(shooter, sub_track, "test_asm"), "Wrong weapon for contact")
	var unarmed := _unit("BLUE", Vector2.ZERO)
	assert_eq(UnitManager.attack_rejection(unarmed, _track(target, Vector2(0, 30))), "No weapons aboard")
	var um := UnitManager.new()
	um.add_unit(shooter)
	assert_true(not um.issue_order(shooter, Order.attack(_track(target, Vector2(0, 30), "NEUTRAL"))), "a refused attack is refused at the order")
	assert_eq(shooter.attack_track, null)
	um.free()


func test_weapons_hold_and_navigation_end_or_replace_the_attack() -> void:
	var asm := _asm(60.0)
	var shooter := _unit("BLUE", Vector2.ZERO, 100.0, [asm])
	var target := _unit("RED", Vector2(0, 56), 800.0)
	var t := _track(target, Vector2(0, 56))
	var h := _harness([shooter, target])
	h.um.issue_order(shooter, Order.attack(t))
	h.advance(1.0)
	h.um.issue_order(shooter, Order.set_roe(Unit.Roe.HOLD))
	h.advance(DT)
	assert_eq(h.ended.size(), 1, "weapons hold ends the attack")
	assert_eq(h.ended[0][2], "Weapons hold")
	assert_true(shooter.waypoints.is_empty(), "and the intercept leg is dropped")
	h.um.issue_order(shooter, Order.set_roe(Unit.Roe.FREE))
	h.um.issue_order(shooter, Order.attack(t))
	h.advance(1.0)
	assert_eq(shooter.attack_track, t)
	h.um.issue_order(shooter, Order.move(Vector2(-30, 0)))
	assert_eq(shooter.attack_track, null, "a transit order replaces the attack")
	assert_eq(shooter.attack_result, "", "silently: the commander changed his mind")
	assert_eq(shooter.waypoints, [Vector2(-30, 0)])
	h.advance(1.0)
	assert_eq(h.ended.size(), 1, "no completion report for a replaced task")
	var unknown := _track(target, Vector2(0, 56), "UNKNOWN")
	h.um.issue_order(shooter, Order.attack(unknown))
	assert_eq(shooter.attack_track, unknown, "weapons free may attack an unidentified surface contact")
	assert_true(h.um.issue_order(shooter, Order.investigate(unknown)))
	assert_eq(shooter.attack_track, null, "investigate replaces attack")
	assert_eq(shooter.investigation_track, unknown)
	h.um.issue_order(shooter, Order.attack(unknown))
	assert_eq(shooter.investigation_track, null, "and attack replaces investigate")
	h.free_all()


func test_stale_plot_holds_fire_and_a_lost_contact_ends_the_task() -> void:
	var asm := _asm(60.0)
	var shooter := _unit("BLUE", Vector2.ZERO, 100.0, [asm])
	var target := _unit("RED", Vector2(0, 30), 800.0)
	var t := _track(target, Vector2(0, 30))
	t.status = Track.Status.STALE
	var h := _harness([shooter, target])
	h.um.issue_order(shooter, Order.attack(t))
	h.advance(2.0)
	assert_eq(shooter.attack_rounds_fired, 0, "never shoot at a stale plot")
	assert_eq(shooter.attack_phase, "Intercept track · contact stale")
	assert_true(not shooter.waypoints.is_empty() or shooter.ordered_speed_kn == 0.0)
	t.status = Track.Status.ACTIVE
	h.advance(DT)
	assert_eq(shooter.attack_rounds_fired, 2, "a fresh plot is fired on")
	t.status = Track.Status.LOST
	h.advance(DT)
	assert_eq(h.ended.size(), 1)
	assert_eq(h.ended[0][2], "Contact lost")
	h.free_all()


func test_evasion_suspends_the_attack_and_hands_back() -> void:
	var asm := _asm(60.0)
	var shooter := _unit("BLUE", Vector2.ZERO, 100.0, [asm])
	var target := _unit("RED", Vector2(0, 56), 800.0)
	var t := _track(target, Vector2(0, 56))
	var h := _harness([shooter, target])
	h.um.issue_order(shooter, Order.attack(t))
	h.advance(1.0)
	shooter.evasion_remaining_s = 30.0
	shooter.evasion_course_deg = 180.0
	shooter.waypoints.clear()
	h.advance(1.0)
	assert_true(shooter.waypoints.is_empty(), "evasion steers; the attack waits")
	assert_eq(shooter.attack_track, t)
	shooter.evasion_remaining_s = 0.0
	h.advance(DT)
	assert_eq(shooter.waypoints.size(), 1, "the intercept resumes afterwards")
	h.free_all()


func test_fixed_wing_aircraft_keeps_flying_inside_the_envelope_and_after_the_attack() -> void:
	var asm := _asm(60.0)
	var strike := _unit("BLUE", Vector2.ZERO, 100.0, [asm], 2, true)
	var target := _unit("RED", Vector2(0, 30), 800.0)
	var t := _track(target, Vector2(0, 30))
	var h := _harness([strike, target])
	assert_true(h.um.issue_order(strike, Order.attack(t)))
	h.advance(DT)
	assert_eq(strike.attack_rounds_fired, 2)
	assert_true(strike.ordered_speed_kn >= strike.spec.cruise_speed_kn, "an aircraft does not stop to hold station")
	var done := h.until(func() -> bool: return not h.ended.is_empty(), 1200.0)
	assert_true(done)
	assert_eq(h.ended[0][2], "Magazines empty")
	assert_true(strike.ordered_speed_kn >= strike.spec.cruise_speed_kn, "and keeps flying when the attack ends")
	h.free_all()


func test_a_sunk_target_ends_every_attack_on_it_even_by_another_shooter() -> void:
	var asm := _asm(60.0)
	var one := _unit("BLUE", Vector2(-10, 0), 100.0, [asm])
	var two := _unit("BLUE", Vector2(10, 0), 100.0, [asm])
	var target := _unit("RED", Vector2(0, 56), 100.0)
	var t := _track(target, Vector2(0, 56))
	var h := _harness([one, two, target])
	h.um.issue_order(one, Order.attack(t))
	h.um.issue_order(two, Order.attack(t))
	h.advance(1.0)
	Damage.apply(target, 1000.0, "asm", "GREEN")
	h.wm.unit_destroyed.emit(target, "GREEN")
	assert_eq(h.ended.size(), 2, "both attacks end")
	assert_eq(h.ended[0][2], "Target destroyed")
	assert_eq(one.attack_track, null)
	assert_eq(two.attack_track, null)
	h.free_all()


func test_unit_manager_clear_drops_attack_tasks() -> void:
	var asm := _asm(60.0)
	var shooter := _unit("BLUE", Vector2.ZERO, 100.0, [asm])
	var target := _unit("RED", Vector2(0, 56))
	var h := _harness([shooter, target])
	h.um.issue_order(shooter, Order.attack(_track(target, Vector2(0, 56))))
	h.um.clear()
	assert_eq(shooter.attack_track, null)
	assert_eq(shooter.attack_track_id, "")
	h.free_all()


func test_cancel_fire_on_the_contact_ends_the_attack_and_counts_as_carried_out() -> void:
	var asm := _asm(60.0)
	var shooter := _unit("BLUE", Vector2.ZERO, 100.0, [asm])
	var target := _unit("RED", Vector2(0, 30), 800.0)
	var t := _track(target, Vector2(0, 30))
	var other := _track(_unit("RED", Vector2(10, 30)), Vector2(10, 30))
	other.id = "T1099"
	var h := _harness([shooter, target])
	var receipts: Array = []
	h.um.order_issued.connect(func(_u: Unit, o: Order) -> void:
		if o.type == Order.Type.CANCEL_FIRE:
			o.execution_accepted = h.wm.cancel_salvo(_u, o.track) > 0 or o.stopped_attack
			receipts.append(o.execution_accepted))
	h.um.issue_order(shooter, Order.attack(t))
	h.advance(DT)
	assert_eq(shooter.attack_rounds_fired, 2)
	h.um.issue_order(shooter, Order.cancel_fire(other))
	assert_eq(shooter.attack_track, t, "cancelling fire on another contact leaves this attack alone")
	h.um.issue_order(shooter, Order.cancel_fire(t))
	assert_eq(shooter.attack_track, null, "cancelling fire on the contact under attack ends the attack")
	assert_eq(shooter.attack_result, "Fire cancelled")
	assert_eq(receipts[-1], true, "and the cancel reports as carried out")
	var left: int = shooter.magazines[asm.id]
	h.advance(120.0)
	assert_eq(shooter.magazines[asm.id], left, "nothing more is fired after the assessment")
	assert_true(h.ended.is_empty(), "a commander's cancel is not reported back as a completion")
	h.free_all()


func test_repeating_the_attack_order_keeps_the_task_and_its_assessment() -> void:
	var asm := _asm(60.0)
	var shooter := _unit("BLUE", Vector2.ZERO, 100.0, [asm])
	var target := _unit("RED", Vector2(0, 30), 800.0)
	var t := _track(target, Vector2(0, 30))
	var h := _harness([shooter, target])
	h.um.issue_order(shooter, Order.attack(t))
	h.advance(DT)
	assert_eq(shooter.attack_rounds_fired, 2)
	var arrived := h.until(func() -> bool: return h.wm.in_flight.all(func(w: Weapon) -> bool: return w.phase == Weapon.Phase.DEAD), 900.0)
	assert_true(arrived)
	h.advance(DT)
	assert_eq(shooter.attack_phase, "Engaging track · assessing")
	assert_true(h.um.issue_order(shooter, Order.attack(t)), "a second right-click is accepted")
	assert_eq(shooter.attack_rounds_fired, 2, "without resetting the task's count")
	h.advance(DT)
	assert_eq(shooter.attack_rounds_fired, 2, "or skipping the assessment pause")
	h.free_all()


func test_inside_minimum_range_the_platform_opens_out_and_then_fires() -> void:
	var asm := _asm(60.0)
	asm.min_range_nm = 6.0
	var shooter := _unit("BLUE", Vector2.ZERO, 100.0, [asm])
	var target := _unit("RED", Vector2(0, 3), 800.0)
	var t := _track(target, Vector2(0, 3))
	var h := _harness([shooter, target])
	h.um.issue_order(shooter, Order.attack(t))
	h.advance(DT)
	assert_eq(shooter.attack_phase, "Opening to range")
	assert_eq(shooter.waypoints.size(), 1, "the ship steers out, not to a halt")
	assert_true(shooter.waypoints[0].distance_to(t.position) > 6.0)
	var fired := h.until(func() -> bool: return shooter.attack_rounds_fired > 0, 1800.0)
	assert_true(fired, "and fires once it is outside the minimum range")
	h.free_all()


func test_an_opening_target_is_chased_rather_than_held_off() -> void:
	var torpedo := _torpedo()
	var boat := _unit("BLUE", Vector2.ZERO, 100.0, [torpedo])
	boat.spec.max_speed_kn = 35.0
	var target := _unit("RED", Vector2(0, 11), 800.0)
	var t := _track(target, Vector2(0, 11))
	t.has_kinematics = true
	t.course_deg = 0.0
	t.speed_kn = 20.0
	var h := _harness([boat, target])
	h.um.issue_order(boat, Order.attack(t))
	h.um.issue_order(boat, Order.set_speed(35.0))
	h.advance(DT)
	assert_eq(boat.attack_phase, "Intercept track", "the lead point is beyond a slow weapon's reach")
	assert_eq(boat.waypoints.size(), 1)
	assert_true(boat.waypoints[0].distance_to(t.position) < 11.0 * 0.6, "so the boat keeps closing, well inside the usual standoff")
	h.free_all()


func test_land_in_the_line_of_fire_moves_the_ship_to_open_water_or_ends_the_attack() -> void:
	var asm := _asm(60.0)
	asm.profile = "sea_skimming"
	var shooter := _unit("BLUE", Vector2.ZERO, 100.0, [asm])
	var target := _unit("RED", Vector2(0, 30), 800.0)
	var t := _track(target, Vector2(0, 30))
	var h := _harness([shooter, target])
	Terrain.load_from({"terrain": {"land": [{"id": "isle", "name": "Isle", "elevation_m": 80.0, "points_nm": [[-3, 12], [3, 12], [3, 18], [-3, 18]]}]}})
	assert_true(Terrain.blocks_path(shooter.position, t.position), "the fixture puts an island in the way")
	h.um.issue_order(shooter, Order.attack(t))
	h.advance(DT)
	assert_eq(shooter.attack_phase, "Intercept track · clearing the line of fire")
	assert_eq(shooter.waypoints.size(), 1)
	assert_true(not Terrain.blocks_path(shooter.waypoints[0], t.position), "to a point with an open line")
	var fired := h.until(func() -> bool: return shooter.attack_rounds_fired > 0, 3600.0)
	assert_true(fired, "and fires from there")
	assert_eq(UnitManager.ATTACK_STALL_S > 0.0, true)
	Terrain.clear()
	h.free_all()


func test_a_bearing_only_attack_closes_to_torpedo_range_not_rocket_range() -> void:
	var torpedo := _torpedo()
	var rocket := WeaponSpec.new()
	rocket.id = "test_rocket"
	rocket.display_name = "Test ASW rocket"
	rocket.type = "asw_rocket"
	rocket.target_types = PackedStringArray(["subsurface"])
	rocket.max_range_nm = 25.0
	rocket.min_range_nm = 1.0
	rocket.speed_kn = 600.0
	var ship := _unit("BLUE", Vector2.ZERO, 100.0, [rocket, torpedo])
	var sub := _unit("RED", Vector2(0, 30), 800.0)
	sub.spec.domain = "subsurface"
	var t := _track(sub, Vector2(0, 30))
	t.bearing_only = true
	t.tma_quality = 0.0
	var h := _harness([ship, sub])
	assert_true(h.um.issue_order(ship, Order.attack(t)), "a torpedo aboard can run down a bearing")
	h.advance(DT)
	assert_eq(ship.waypoints.size(), 1)
	assert_near(ship.waypoints[0].distance_to(t.position), 12.0 * UnitManager.ATTACK_STANDOFF_FRACTION, 0.01, "the torpedo's standoff, not the rocket's")
	h.free_all()


func test_an_attack_that_can_neither_fire_nor_move_ends_with_the_reason() -> void:
	var asm := _asm(60.0)
	asm.type = "sam"
	asm.guidance = "semi_active_radar"
	assert_true(asm.requires_radar_support(), "the fixture's weapon needs the ship's radar to guide")
	var shooter := _unit("BLUE", Vector2.ZERO, 100.0, [asm])
	shooter.radar_on = false
	var target := _unit("RED", Vector2(0, 30), 800.0)
	var t := _track(target, Vector2(0, 30))
	var h := _harness([shooter, target])
	h.um.issue_order(shooter, Order.attack(t))
	h.advance(DT)
	assert_eq(shooter.attack_rounds_fired, 0, "with its radar off the ship cannot guide the round")
	assert_eq(shooter.attack_phase, "Attack track · radar guidance unavailable")
	assert_true(shooter.waypoints.is_empty(), "it is inside the envelope, so it holds")
	h.advance(UnitManager.ATTACK_STALL_S - 10.0)
	assert_true(h.ended.is_empty(), "a passing problem gets time to clear")
	var ended := h.until(func() -> bool: return not h.ended.is_empty(), 20.0)
	assert_true(ended, "but the task does not park the ship forever")
	assert_eq(h.ended[0][2], "Cannot engage: radar guidance unavailable")
	h.free_all()
