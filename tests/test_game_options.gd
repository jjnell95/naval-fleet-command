extends TestCase
## The gameplay options: the Normal and Classic presets and their persistence, the time ladder and
## its ceiling, manual missile defence and the commander's intercept, engagement after hostile
## identification, the 1990 campaign's start, and the clock that drops to real time only for what
## the player's side could see. Preferences go to a scratch file, never the player's own.

const SCRATCH_SETTINGS := "user://test_game_options_settings.cfg"
const CARRIER_QUAL := "res://data/scenarios/carrier_qualification.json"


func _with_scratch_settings(fn: Callable) -> void:
	var saved_path := UserSettings.path
	var saved_writable := UserSettings.writable
	UserSettings.path = SCRATCH_SETTINGS
	UserSettings.writable = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_SETTINGS))
	fn.call()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_SETTINGS))
	UserSettings.path = saved_path
	UserSettings.writable = saved_writable


# --- Presets and persistence -------------------------------------------------------------

func test_normal_is_the_game_as_it_was_and_classic_is_the_late_nineties_rule_set() -> void:
	var normal := GameOptions.normal()
	assert_eq(normal.preset(), GameOptions.NORMAL)
	assert_eq(Array(normal.time_scales), Array(SimClock.SPEEDS), "Normal keeps the whole ladder to 60x")
	assert_eq(normal.missile_defence, GameOptions.DEFENCE_AUTO)
	assert_true(not normal.engage_on_hostile_id)
	assert_eq(GameOptions.normal(true, false).preset(), GameOptions.NORMAL, "Normal leaves sound as the player set it")
	var classic := GameOptions.classic()
	assert_eq(classic.preset(), GameOptions.CLASSIC)
	assert_eq(Array(classic.time_scales), [1.0, 2.0, 4.0], "Classic stops at 4x")
	assert_eq(classic.ceiling(), 4.0)
	assert_true(classic.manual_missile_defence())
	assert_true(classic.engage_on_hostile_id)
	assert_true(classic.voice and classic.ambient, "Classic has the crew and the sea audible")
	assert_eq(classic.label(), "CLASSIC 4×")
	assert_eq(normal.label(), "NORMAL")


func test_changing_any_one_option_makes_the_preset_custom() -> void:
	var changes := {
		"time": func(o: GameOptions) -> void: o.time_scales = GameOptions.scales_to(10.0),
		"defence": func(o: GameOptions) -> void: o.missile_defence = GameOptions.DEFENCE_AUTO,
		"engage": func(o: GameOptions) -> void: o.engage_on_hostile_id = false,
		"voice": func(o: GameOptions) -> void: o.voice = false,
		"ambient": func(o: GameOptions) -> void: o.ambient = false,
	}
	for key: String in changes:
		var o := GameOptions.classic()
		changes[key].call(o)
		assert_eq(o.preset(), GameOptions.CUSTOM, "Classic with %s changed" % key)
	var manual_normal := GameOptions.normal()
	manual_normal.missile_defence = GameOptions.DEFENCE_MANUAL
	assert_eq(manual_normal.preset(), GameOptions.CUSTOM)
	assert_eq(manual_normal.label(), "CUSTOM 60×")
	var engage_normal := GameOptions.normal()
	engage_normal.engage_on_hostile_id = true
	assert_eq(engage_normal.preset(), GameOptions.CUSTOM)


func test_each_option_toggles_on_its_own_and_the_classic_ladder_is_one_constant() -> void:
	var o := GameOptions.normal(false, true)
	for key: String in GameOptions.OPTION_KEYS:
		if key == "":
			continue
		var flipped := o.toggled(key)
		assert_true(flipped.option_on(key) != o.option_on(key), "%s switches" % key)
		for other: String in GameOptions.OPTION_KEYS:
			if other != "" and other != key:
				assert_eq(flipped.option_on(other), o.option_on(other), "%s leaves %s alone" % [key, other])
		assert_true(flipped.toggled(key).equals(o), "%s switches back" % key)
	# Every Classic number is read from CLASSIC_SCALES, so a different ceiling is a one-line edit.
	assert_eq(GameOptions.CLASSIC_CEILING, GameOptions.CLASSIC_SCALES[GameOptions.CLASSIC_SCALES.size() - 1])
	assert_true(GameOptions.valid_scales(GameOptions.CLASSIC_SCALES))
	assert_eq(Array(o.toggled("ceiling").time_scales), Array(GameOptions.CLASSIC_SCALES), "the ceiling option is the Classic ladder")
	assert_eq(GameOptions.option_text("ceiling"), "Time ceiling 4× (1×, 2×, 4×)")
	assert_true(GameOptions.preset_description(GameOptions.CLASSIC).begins_with("4× time ceiling"))
	var classic := GameOptions.classic()
	assert_eq(classic.summary(), "4× ceiling · manual missile defence · engage after identification")
	assert_eq(GameOptions.normal().summary(), "60× ceiling · automatic missile defence · attack on orders")
	assert_eq(classic.toggled("engage_on_id").toggled("engage_on_id").preset(), GameOptions.CLASSIC)


func test_options_round_trip_and_tolerate_damaged_data() -> void:
	var classic := GameOptions.classic()
	var copy := GameOptions.from_dict(classic.to_dict())
	assert_true(copy.equals(classic), "a saved engagement restores exactly the options it was fought under")
	assert_eq(copy.preset(), GameOptions.CLASSIC)
	assert_eq(int(classic.to_dict()["version"]), GameOptions.VERSION)
	var junk := GameOptions.from_dict({"time_scales": [2.0, 1.0], "missile_defence": "sometimes", "engage_on_hostile_id": "yes", "voice": 1, "ambient": null})
	assert_eq(Array(junk.time_scales), Array(SimClock.SPEEDS), "a ladder that does not start at real time is refused")
	assert_eq(junk.missile_defence, GameOptions.DEFENCE_AUTO)
	assert_true(not junk.engage_on_hostile_id, "only a real true turns engagement on")
	assert_true(not junk.voice)
	assert_true(junk.ambient)
	assert_eq(GameOptions.from_dict({}).preset(), GameOptions.NORMAL, "nothing stored is Normal")
	for bad: Array in [[], [1.0, 2.0, 2.0], [1.0, 120.0], [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0]]:
		assert_true(not GameOptions.valid_scales(bad), "refused ladder %s" % [bad])
	assert_eq(Array(GameOptions.from_dict({"time_scales": [1, 2, 4]}).time_scales), [1.0, 2.0, 4.0], "whole numbers from a config file are read")


func test_the_preference_persists_in_the_gameplay_section_and_only_where_writable() -> void:
	_with_scratch_settings(func() -> void:
		assert_eq(GameOptions.load_preferred().preset(), GameOptions.NORMAL, "a fresh player starts on Normal")
		assert_true(GameOptions.save_preferred(GameOptions.classic()))
		var back := GameOptions.load_preferred()
		assert_eq(back.preset(), GameOptions.CLASSIC, "Classic survives a restart")
		assert_eq(str(UserSettings.get_value("gameplay", "missile_defence", "")), "manual")
		assert_eq(bool(UserSettings.get_value("audio", "voice", CrewVoice.default_on())), true, "voice keeps its own key")
		assert_eq(bool(UserSettings.get_value("audio", "ambient", true)), true, "ambient keeps its own key")
		var quiet := GameOptions.classic()
		quiet.ambient = false
		GameOptions.save_preferred(quiet)
		assert_eq(UserSettings.get_value("audio", "ambient", true), false, "a changed ambient choice is written where SoundFx reads it")
		assert_eq(GameOptions.load_preferred().preset(), GameOptions.CUSTOM)
		GameOptions.save_preferred(GameOptions.classic())
		var custom := GameOptions.classic()
		custom.missile_defence = GameOptions.DEFENCE_AUTO
		GameOptions.save_preferred(custom)
		assert_eq(GameOptions.load_preferred().preset(), GameOptions.CUSTOM)
		UserSettings.writable = false
		assert_true(not GameOptions.save_preferred(GameOptions.normal()), "a scripted run never saves")
		assert_eq(GameOptions.load_preferred().preset(), GameOptions.CUSTOM, "and the stored preference is untouched")
		UserSettings.writable = true)


func test_choosing_normal_does_not_make_a_platform_voice_default_explicit() -> void:
	_with_scratch_settings(func() -> void:
		GameOptions.save_preferred(GameOptions.normal(CrewVoice.default_on(), true))
		assert_true(not UserSettings.has_value("audio", "voice"), "an unchanged default stays a default")
		assert_true(not UserSettings.has_value("audio", "ambient"))
		assert_true(UserSettings.has_value("gameplay", "time_scales")))


# --- The time ladder ---------------------------------------------------------------------

func test_menus_and_the_key_board_offer_only_the_ladder_in_use() -> void:
	var saved := SimClock.speeds()
	var saved_index := SimClock.speed_index
	SimClock.set_ceiling(4.0)
	var items := CommandBar.time_items()
	assert_eq(items.size(), 3, "1x, 2x and 4x")
	assert_true(str(items[2]["text"]).begins_with("4×") and str(items[2]["text"]).contains("Ceiling"), items[2]["text"])
	assert_eq(items[2]["action"]["id"], "speed_2")
	var rows := " | ".join(KeyCommands.all_rows())
	assert_true(rows.contains("1 - 3: Time scale 1x, 2x, 4x (the ceiling)"), rows)
	assert_true(not rows.contains("60x"))
	SimClock.set_speeds(saved)
	SimClock.set_speed_index(saved_index)
	assert_eq(CommandBar.time_items().size(), 6, "Normal: six steps again")
	assert_true(" | ".join(KeyCommands.all_rows()).contains("1 - 6: Time scale 1x, 2x, 5x, 10x, 30x, 60x"))


# --- Manual missile defence --------------------------------------------------------------

func _asm() -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = "test_asm"
	w.display_name = "Test ASM"
	w.type = "asm"
	w.max_range_nm = 70.0
	w.speed_kn = 480.0
	w.turn_rate_deg_s = 15.0
	w.seeker_range_nm = 8.0
	w.damage = 40.0
	w.base_pk = 1.0
	w.altitude_m = 10.0
	return w


func _sam(id: String, max_range: float, kind := "sam", salvo := 2) -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = id
	w.display_name = id
	w.type = kind
	w.target_types = PackedStringArray(["missile"])
	w.max_range_nm = max_range
	w.min_range_nm = 0.05
	w.speed_kn = 2400.0
	w.turn_rate_deg_s = 120.0
	w.base_pk = 1.0
	w.salvo_default = salvo
	w.launch_interval_s = 1.0
	return w


func _ship(faction: String, pos: Vector2, defensive: Array, rounds := 32) -> Unit:
	var p := PlatformSpec.new()
	p.short_name = "FFG Test"
	p.max_speed_kn = 30.0
	p.cruise_speed_kn = 15.0
	p.health = 100.0
	var u := Unit.new()
	u.spec = p
	u.faction = faction
	u.callsign = "%s-%d" % [faction, int(pos.x)]
	u.position = pos
	u.health = 100.0
	var s := SensorSpec.new()
	s.kind = "radar"
	s.range_surface_nm = 40.0
	s.range_air_nm = 200.0
	s.antenna_height_m = 20.0
	u.sensors.append(s)
	for spec: WeaponSpec in defensive:
		u.weapons.append(spec)
		u.magazines[spec.id] = rounds
	return u


func _harness(units: Array) -> Array:
	var um := UnitManager.new()
	for u: Unit in units:
		um.add_unit(u)
	var tm := ThreatManager.new()
	var wm := WeaponManager.new()
	wm.unit_manager = um
	wm.rng.seed = 11
	return [um, tm, wm]


func _incoming(wm: WeaponManager, faction: String, pos: Vector2, target: Unit, wid := 900) -> Weapon:
	var w := Weapon.new()
	w.id = wid
	w.spec = _asm()
	w.faction = faction
	w.position = pos
	w.acquired = target
	w.aim_point = target.position
	w.heading_deg = Geo.bearing_deg(pos, target.position)
	w.phase = Weapon.Phase.TERMINAL
	wm.in_flight.append(w)
	return w


## The defence cycle as Simulation runs it, with every round seen by the other side.
func _run(h: Array, seconds: float) -> void:
	var um: UnitManager = h[0]
	var tm: ThreatManager = h[1]
	var wm: WeaponManager = h[2]
	var now := 0.0
	var accum := 0.0
	for i in int(seconds / 0.25):
		now += 0.25
		um.tick(0.25)
		wm.tick(0.25, now)
		accum += 0.25
		if accum >= 1.0:
			accum -= 1.0
			tm.begin_cycle()
			for w: Weapon in wm.in_flight:
				if w.intercept_target == null:
					for u in um.units:
						if u.faction != w.faction:
							tm.mark_detected(u.faction, w, now, u)
			AirDefence.run_cycle(um, tm, wm, now)


func _cleanup(h: Array) -> void:
	h[1].free()
	h[2].free()
	h[0].free()


func test_a_manual_ship_holds_its_sams_while_the_other_side_still_defends_itself() -> void:
	var blue := _ship("BLUE", Vector2.ZERO, [_sam("essm", 25.0)])
	var red := _ship("RED", Vector2(60, 0), [_sam("essm", 25.0)])
	var h := _harness([blue, red])
	assert_true(h[0].issue_order(blue, Order.set_air_defence_mode(false)))
	assert_true(not blue.auto_air_defence)
	assert_true(red.auto_air_defence, "the opposing side keeps automatic defence")
	_incoming(h[2], "RED", Vector2(0, 12), blue, 900)
	_incoming(h[2], "BLUE", Vector2(60, 12), red, 901)
	_run(h, 120.0)
	assert_eq(blue.magazine_count("essm"), 32, "no SAM leaves a manual ship unordered")
	assert_near(blue.health, 60.0, 1e-3, "and the round arrives")
	assert_true(red.magazine_count("essm") < 32, "an automatic ship still defends itself")
	_cleanup(h)


func test_close_in_guns_answer_on_manual_but_not_under_weapons_hold() -> void:
	for roe: int in [Unit.Roe.FREE, Unit.Roe.HOLD]:
		var ciws := _sam("ciws", 1.2, "ciws", 3)
		var ship := _ship("BLUE", Vector2.ZERO, [_sam("essm", 25.0), ciws])
		var h := _harness([ship])
		h[0].issue_order(ship, Order.set_air_defence_mode(false))
		h[0].issue_order(ship, Order.set_roe(roe))
		_incoming(h[2], "RED", Vector2(0, 10), ship)
		_run(h, 75.0)
		assert_eq(ship.magazine_count("essm"), 32, "the SAMs wait for an order")
		if roe == Unit.Roe.FREE:
			assert_true(ship.magazine_count("ciws") < 32, "the last-ditch guns stay automatic")
		else:
			assert_eq(ship.magazine_count("ciws"), 32, "weapons hold silences even the guns")
		_cleanup(h)


func test_an_intercept_order_clears_the_round_and_the_defence_cycle_follows_it() -> void:
	var ship := _ship("BLUE", Vector2.ZERO, [_sam("essm", 25.0)])
	var h := _harness([ship])
	h[0].issue_order(ship, Order.set_air_defence_mode(false))
	var w := _incoming(h[2], "RED", Vector2(0, 40), ship)
	var tm: ThreatManager = h[1]
	tm.mark_detected("BLUE", w, 0.0, ship)
	var result := AirDefence.order_intercept(ship, w, h[0], tm, h[2], 0.0)
	assert_eq(int(result["cleared"]), 1, result["reason"])
	assert_eq(int(result["fired"]), 0, "at 40 nm the round is outside the SAM's reach: cleared, not yet fired")
	assert_true(w.intercept_cleared.has(ship.id))
	_run(h, 240.0)
	assert_true(ship.magazine_count("essm") < 32, "the cycle engages the cleared round as it closes")
	assert_near(ship.health, 100.0, 1e-3, "and stops it")
	_cleanup(h)


func test_the_intercept_order_respects_weapons_hold_magazines_and_the_picture() -> void:
	var ship := _ship("BLUE", Vector2.ZERO, [_sam("essm", 25.0)])
	var h := _harness([ship])
	var tm: ThreatManager = h[1]
	var w := _incoming(h[2], "RED", Vector2(0, 10), ship)
	assert_eq(AirDefence.threat_rejection(ship, w, tm), "That weapon is not held on this unit's picture", "a round the plot does not hold cannot be named")
	tm.mark_detected("BLUE", w, 0.0, ship)
	h[0].issue_order(ship, Order.set_roe(Unit.Roe.HOLD))
	assert_true(not UnitManager.can_accept_order(ship, Order.intercept(w)), "weapons hold refuses the order")
	assert_eq(AirDefence.intercept_rejection(ship), "Weapons hold")
	h[0].issue_order(ship, Order.set_roe(Unit.Roe.FREE))
	ship.magazines["essm"] = 0
	assert_eq(AirDefence.intercept_rejection(ship), "Interceptor magazines empty", "no rounds, no intercept")
	var bare := _ship("BLUE", Vector2(1, 0), [])
	assert_eq(AirDefence.intercept_rejection(bare), "No anti-missile weapons aboard")
	ship.magazines["essm"] = 1
	var result := AirDefence.order_intercept(ship, w, h[0], tm, h[2], 0.0)
	assert_eq(int(result["fired"]), 1, "one round aboard, one round away")
	assert_eq(ship.magazine_count("essm"), 0, "the magazine is spent, not refilled")
	var own := _incoming(h[2], "BLUE", Vector2(0, 5), ship, 902)
	assert_eq(AirDefence.threat_rejection(ship, own, tm), "Not an inbound weapon")
	_cleanup(h)


func test_the_intercept_order_is_limited_by_fire_control_channels() -> void:
	for channels: int in [1, 2]:
		# Two launchers, so only the guidance channels can stop the second shot.
		var ship := _ship("BLUE", Vector2.ZERO, [_sam("sam_a", 25.0), _sam("sam_b", 25.0)])
		ship.spec.fire_control_channels = channels
		var h := _harness([ship])
		h[0].issue_order(ship, Order.set_air_defence_mode(false))
		var tm: ThreatManager = h[1]
		var first := _incoming(h[2], "RED", Vector2(0, 12), ship, 900)
		var second := _incoming(h[2], "RED", Vector2(2, 12), ship, 901)
		tm.mark_detected("BLUE", first, 0.0, ship)
		tm.mark_detected("BLUE", second, 0.0, ship)
		var result := AirDefence.order_intercept(ship, null, h[0], tm, h[2], 0.0)
		assert_eq(int(result["cleared"]), 2, "X clears every inbound round the ship holds")
		assert_eq(int(result["fired"]), channels, "%d channel(s), %d engagement(s) at a time" % [channels, channels])
		assert_eq(h[2].channel_targets(ship).size(), channels)
		_cleanup(h)


func test_the_simulation_routes_the_intercept_with_its_own_picture() -> void:
	var sim := Simulation.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	sim.ai_enabled = false
	var ship := _ship("BLUE", Vector2.ZERO, [_sam("essm", 25.0)])
	sim.unit_manager.add_unit(ship)
	sim.unit_manager.issue_order(ship, Order.set_air_defence_mode(false))
	var w := _incoming(sim.weapon_manager, "RED", Vector2(0, 10), ship)
	var unseen := Order.intercept(w)
	assert_true(not sim.unit_manager.issue_order(ship, unseen), "an unheld round is refused")
	assert_true(unseen.receipt.contains("not held"), unseen.receipt)
	sim.threat_manager.mark_detected("BLUE", w, 0.0, ship)
	var order := Order.intercept(w)
	assert_true(sim.unit_manager.issue_order(ship, order), order.receipt)
	assert_eq(ship.magazine_count("essm"), 31, "the first interceptor leaves at once")
	sim.unit_manager.clear()
	sim.weapon_manager.clear()
	sim.queue_free()
	sim.free()


func test_a_held_inbound_round_on_the_chart_is_intercepted_by_a_right_click() -> void:
	Terrain.clear()
	var ship := _ship("BLUE", Vector2(-20, 0), [_sam("essm", 25.0)])
	var h := _harness([ship])
	var tm: ThreatManager = h[1]
	var w := _incoming(h[2], "RED", Vector2(0, 0), ship)
	var map := TacticalMap.new()
	map.unit_manager = h[0]
	map.weapon_manager = h[2]
	map.threat_manager = tm
	map.track_manager = TrackManager.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(map)
	map.size = Vector2(1000, 700)
	map.center_nm = Vector2.ZERO
	map.ppn = 4.0
	var at := map.world_to_screen(w.position)
	assert_eq(map.context_at(at)["kind"], "water", "a round the picture does not hold is not there to click")
	tm.mark_detected("BLUE", w, 0.0, ship)
	var ctx := map.context_at(at)
	assert_eq(ctx["kind"], "weapon")
	assert_true(ctx["weapon"] == w)
	var asked: Array = []
	var menus: Array = []
	map.intercept_requested.connect(func(x: Weapon) -> void: asked.append(x))
	map.context_menu_requested.connect(func(_at: Vector2, c: Dictionary) -> void: menus.append(c))
	for pressed: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_RIGHT
		e.pressed = pressed
		e.position = at
		map._gui_input(e)
	assert_true(asked.is_empty() and menus.size() == 1 and menus[0]["kind"] == "weapon", "nothing hooked: the round's menu")
	map.select_units([ship])
	for pressed: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_RIGHT
		e.pressed = pressed
		e.position = at
		map._gui_input(e)
	assert_eq(asked.size(), 1, "a ship hooked: a bare right-click intercepts the round")
	var items := CdsMenus.weapon_items(w, [ship], true, true)
	var engage: Dictionary = items[1]
	assert_true(not bool(engage["disabled"]))
	var order: Order = engage["action"]["order"]
	assert_true(order.type == Order.Type.INTERCEPT and order.threat == w)
	ship.roe = Unit.Roe.HOLD
	assert_true(bool(CdsMenus.weapon_items(w, [ship], true, true)[1]["disabled"]), "weapons hold greys the intercept")
	map.track_manager.free()
	map.free()
	_cleanup(h)
