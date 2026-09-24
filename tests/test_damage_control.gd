extends TestCase
## A hit starts a fight for the ship rather than ending one. Fires spread or are put out, flooding
## is pumped down or runs away, damage control is what decides which, and decoys move a missile
## instead of deleting it.


func _ship(faction := "BLUE", pos := Vector2.ZERO, hp := 110.0) -> Unit:
	var p := PlatformSpec.new()
	p.short_name = "DDG Test"
	p.domain = "surface"
	p.max_speed_kn = 30.0
	p.cruise_speed_kn = 16.0
	p.health = hp
	p.signature_factor = 1.0
	var u := Unit.new()
	u.spec = p
	u.faction = faction
	u.callsign = "%s-%d" % [faction, int(pos.x * 10 + pos.y)]
	u.position = pos
	u.health = hp
	u.speed_kn = 20.0
	u.ordered_speed_kn = 20.0
	return u


func _run(u: Unit, seconds: float, units: Array = []) -> Array:
	var all := units if not units.is_empty() else [u]
	var events: Array = []
	var t := 0.0
	while t < seconds and u.alive:
		events.append_array(Damage.tick(all, 1.0))
		t += 1.0
	return events


func _kinds(events: Array) -> Array:
	return events.map(func(e: Dictionary) -> String: return e["event"])


func test_missile_hits_usually_start_fires_and_torpedoes_let_the_sea_in() -> void:
	Damage.rng.seed = 41
	var fires := 0
	var floods := 0
	for i in 40:
		var u := _ship()
		Damage.apply(u, 40.0, "asm", "RED")
		if u.fire > 0.0:
			fires += 1
		var v := _ship()
		Damage.apply(v, 40.0, "torpedo", "RED")
		if v.flooding > 0.0:
			floods += 1
	assert_true(fires >= 28, "most missile hits start a fire (%d/40)" % fires)
	assert_true(floods >= 38, "a torpedo nearly always floods (%d/40)" % floods)
	var plain := _ship()
	Damage.apply(plain, 40.0)
	assert_eq(plain.fire + plain.flooding, 0.0, "damage with no weapon context starts nothing")
	assert_eq(plain.last_attacker, "", "and credits nobody")


func test_a_small_fire_in_a_sound_ship_is_put_out() -> void:
	var u := _ship()
	u.fire = 0.12
	var events := _run(u, 1800.0)
	assert_eq(u.fire, 0.0, "out")
	assert_true(_kinds(events).has("fire_out"), "and reported")
	assert_true(u.alive and Damage.health_fraction(u) > 0.95, "at little cost")


func test_a_big_fire_in_a_crippled_ship_takes_her() -> void:
	var u := _ship()
	u.health = 20.0
	u.fire = 0.7
	u.dc_fortune = 0.6  # the hit cut the fire main
	u.last_attacker = "RED"
	assert_true(Damage.fire_out_of_control(u), "past what this crew can put out")
	var events := _run(u, 3.0 * 3600.0)
	assert_true(not u.alive, "lost to the fire")
	assert_true(_kinds(events).has("lost"), "reported as lost")
	assert_eq(u.last_attacker, "RED", "credited to whoever set it")


func test_the_same_fire_is_survivable_with_a_consort_alongside() -> void:
	var u := _ship()
	u.health = 20.0
	u.fire = 0.7
	u.dc_fortune = 0.6
	var helper := _ship("BLUE", Vector2(0.4, 0.0))
	_run(u, 3.0 * 3600.0, [u, helper])
	assert_true(u.alive, "saved by the ship alongside")
	assert_eq(u.fire, 0.0, "fire out")


func test_a_consort_alongside_helps_fight_the_fire() -> void:
	var u := _ship()
	u.health = 55.0
	var alone := Damage.damage_control(u, [u])
	var helper := _ship("BLUE", Vector2(0.5, 0.0))
	var far := _ship("BLUE", Vector2(5.0, 0.0))
	var enemy := _ship("RED", Vector2(0.3, 0.0))
	assert_true(Damage.damage_control(u, [u, helper]) > alone + 0.3, "hoses and pumps from alongside")
	assert_near(Damage.damage_control(u, [u, far, enemy]), alone, 1e-6, "not from five miles off, nor from the enemy")


func test_flooding_slows_the_ship_and_is_pumped_down() -> void:
	var u := _ship()
	var full := u.effective_max_speed()
	u.flooding = 0.6
	assert_true(u.effective_max_speed() < full * 0.8, "water aboard costs speed")
	var events := _run(u, 3600.0)
	assert_eq(u.flooding, 0.0, "a healthy crew gets it under control")
	assert_true(_kinds(events).has("flooding_controlled"), "and says so")
	assert_near(u.effective_max_speed(), full, 1e-3, "speed comes back")


func test_flooding_runs_away_when_damage_control_has_collapsed() -> void:
	var u := _ship()
	u.health = 12.0
	u.flooding = 0.9
	u.dc_fortune = 0.5
	_run(u, 2.0 * 3600.0)
	assert_true(not u.alive, "she goes down")


func test_systems_wait_until_the_ship_is_safe() -> void:
	var u := _ship()
	u.components["sensors"] = 0.2
	u.fire = 0.3
	Damage.tick([u], 60.0)
	assert_true(u.component("sensors") <= 0.2, "no repair while burning")
	u.fire = 0.0
	Damage.tick([u], 60.0)
	assert_true(u.component("sensors") > 0.2, "repair resumes once the fire is out")


# --- Decoys move a missile -------------------------------------------------------------

func _asm() -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = "test_asm"
	w.type = "asm"
	w.target_types = PackedStringArray(["surface"])
	w.speed_kn = 480.0
	w.seeker_range_nm = 8.0
	w.max_range_nm = 100.0
	return w


func _inbound(wm: WeaponManager, target: Unit) -> Weapon:
	var w := Weapon.new()
	w.spec = _asm()
	w.faction = "RED"
	w.position = target.position + Vector2(0.0, -2.0)
	w.heading_deg = 0.0  # flying north, straight at the target and on past it
	w.acquired = target
	w.phase = Weapon.Phase.TERMINAL
	wm.in_flight.append(w)
	return w


func test_a_decoyed_missile_can_lock_the_next_ship_down_its_track() -> void:
	var um := UnitManager.new()
	var escort := _ship("BLUE", Vector2.ZERO)
	var carrier := _ship("BLUE", Vector2(0.0, 4.0))  # directly behind, in the seeker's cone
	um.add_unit(escort)
	um.add_unit(carrier)
	var wm := WeaponManager.new()
	wm.unit_manager = um
	var retargeted := 0
	for i in 40:
		wm.rng.seed = 100 + i
		var w := _inbound(wm, escort)
		var got := wm.seduce(w, escort)
		if got != null:
			retargeted += 1
			assert_eq(got, carrier, "the ship behind, never the decoying one")
			assert_eq(w.phase, Weapon.Phase.TERMINAL, "still homing")
		else:
			assert_eq(w.dead_reason, "DECOYED", "or spent in the cloud")
	assert_true(retargeted >= 10 and retargeted <= 30, "sometimes, not always (%d/40)" % retargeted)
	wm.free()
	um.free()


func test_a_decoyed_missile_with_nothing_ahead_is_spent() -> void:
	var um := UnitManager.new()
	var escort := _ship("BLUE", Vector2.ZERO)
	var abeam := _ship("BLUE", Vector2(4.0, 0.0))  # outside a 35 degree cone ahead
	um.add_unit(escort)
	um.add_unit(abeam)
	var wm := WeaponManager.new()
	wm.unit_manager = um
	for i in 20:
		wm.rng.seed = 7 + i
		var w := _inbound(wm, escort)
		assert_true(wm.seduce(w, escort) == null, "nothing in the cone")
		assert_eq(w.dead_reason, "DECOYED")
	wm.free()
	um.free()
