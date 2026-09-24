extends TestCase
## Regressions for defects found in the September 2026 debugging pass. Each test fails on the code
## before its fix.


func _unit(pid: String, faction: String, pos: Vector2, callsign := "") -> Unit:
	var spec := DataDB.platform(pid)
	var u := Unit.new()
	u.spec = spec
	u.faction = faction
	u.callsign = callsign if callsign != "" else "%s %s" % [faction, pid]
	u.position = pos
	u.health = spec.health
	for sid in spec.sensor_ids:
		var s := DataDB.sensor(sid)
		if s != null:
			u.sensors.append(s)
	return u


# --- Weapons ---------------------------------------------------------------------------------

## An interceptor is stepped before the round it chases, so the round can already be dead when its
## own step comes round in the same tick. It must not then fly on and roll an impact.
func test_a_round_killed_earlier_in_the_tick_cannot_hit() -> void:
	Terrain.clear()
	var ship := _unit("cw90_ticonderoga", "BLUE", Vector2.ZERO)
	var red := _unit("cw90_slava", "RED", Vector2(0, 100))
	var um := UnitManager.new()
	um.add_unit(ship)
	um.add_unit(red)
	var wm := WeaponManager.new()
	wm.unit_manager = um
	var threat := Weapon.new()
	threat.id = 1
	threat.spec = DataDB.weapon("cw90_kh22")
	threat.faction = "RED"
	threat.shooter = red
	threat.position = Vector2(0.0, 0.05)  # already inside the impact distance
	threat.heading_deg = 180.0
	threat.acquired = ship
	threat.phase = Weapon.Phase.TERMINAL
	wm.in_flight.append(threat)
	wm.defeat_weapon(threat, "INTERCEPTED", ship)
	var impacts := [0]
	wm.weapon_impact.connect(func(_f: String, _s: WeaponSpec, _t: Unit, _hit: bool) -> void: impacts[0] += 1)
	wm.tick(0.25, 0.25)
	assert_eq(impacts[0], 0, "an intercepted round rolls no impact")
	assert_eq(threat.dead_reason, "INTERCEPTED", "the reason it died is not overwritten")
	assert_near(ship.health, ship.spec.health, 0.001, "the ship is untouched")
	assert_true(wm.in_flight.is_empty(), "the dead round is removed")
	wm.free()
	um.free()


## End to end with the real close-in defence: across many geometries no round is both reported
## intercepted and allowed to strike.
func test_no_round_is_both_intercepted_and_scored() -> void:
	Terrain.clear()
	var kh22 := DataDB.weapon("cw90_kh22")
	var ciws := DataDB.weapon("cw90_phalanx")
	var trials := 120
	var intercepted := 0
	var both := 0
	for n in trials:
		var ship := _unit("cw90_ticonderoga", "BLUE", Vector2.ZERO)
		var red := _unit("cw90_slava", "RED", Vector2(0, 100))
		var um := UnitManager.new()
		um.add_unit(ship)
		um.add_unit(red)
		var wm := WeaponManager.new()
		wm.unit_manager = um
		wm.rng.seed = 1000 + n
		var threat := Weapon.new()
		threat.id = 1
		threat.spec = kh22
		threat.faction = "RED"
		threat.shooter = red
		threat.position = Vector2(0.0, 0.14 + 0.53 * float(n) / float(trials))
		threat.heading_deg = 180.0
		threat.acquired = ship
		threat.phase = Weapon.Phase.TERMINAL
		wm.in_flight.append(threat)
		var events: Array[String] = []
		wm.weapon_defeated.connect(func(_w: Weapon, r: String, _u: Unit) -> void: events.append("defeated:" + r))
		wm.weapon_impact.connect(func(_f: String, _s: WeaponSpec, _t: Unit, _hit: bool) -> void: events.append("impact"))
		if not ship.weapons.has(ciws):
			ship.weapons.append(ciws)
		ship.magazines[ciws.id] = 10
		wm.launch_interceptor(ship, ciws, threat, 1, 0.0)
		var now := 0.0
		for i in 40:
			now += 0.25
			wm.tick(0.25, now)
			if wm.in_flight.is_empty():
				break
		if events.has("defeated:INTERCEPTED"):
			intercepted += 1
			if events.has("impact"):
				both += 1
		wm.free()
		um.free()
	assert_true(intercepted > 0, "the geometry produces interceptions to test")
	assert_eq(both, 0, "no intercepted round also struck")


## A seeker loses a helicopter that lands on its deck: the round does not follow it into the hangar.
func test_a_round_does_not_chase_a_helicopter_onto_the_deck() -> void:
	Terrain.clear()
	var ship := _unit("cw90_spruance", "BLUE", Vector2.ZERO, "Spruance")
	var helo := _unit("cw90_sh60b", "BLUE", Vector2(0.0, 0.05), "Seahawk")
	helo.home = ship
	ship.embarked.append(helo)
	var shooter := _unit("cw90_slava", "RED", Vector2(0.0, 30.0))
	var um := UnitManager.new()
	for u in [ship, helo, shooter]:
		um.add_unit(u)
	var av := AviationManager.new()
	av.unit_manager = um
	var wm := WeaponManager.new()
	wm.unit_manager = um
	wm.rng.seed = 1
	helo.flight_state = Unit.FlightState.RECOVERING
	helo.fuel_s = helo.spec.endurance_s
	helo.altitude_m = 30.0
	helo.state_timer_s = 1.0
	helo.recovery_base = ship
	ship.inbound_aircraft.append(helo)
	var sam: WeaponSpec = null
	for w in DataDB.all_weapons():
		if w.type == "sam" and w.target_types.has("air") and w.speed_kn < 2500.0:
			sam = w
			break
	var r := Weapon.new()
	r.id = 99
	r.spec = sam
	r.faction = "RED"
	r.shooter = shooter
	r.position = Vector2(0.0, 6.0)
	r.heading_deg = 180.0
	r.acquired = helo
	r.phase = Weapon.Phase.TERMINAL
	wm.in_flight.append(r)
	var hits_on_helo := [0]
	wm.weapon_impact.connect(func(_f: String, _s: WeaponSpec, t: Unit, _hit: bool) -> void:
		if t == helo:
			hits_on_helo[0] += 1)
	var landed := false
	var now := 0.0
	for i in 4 * 120:
		now += 0.25
		um.tick(0.25)
		av.tick(0.25, now)
		wm.tick(0.25, now)
		landed = landed or helo.flight_state == Unit.FlightState.TURNAROUND
		if r.phase == Weapon.Phase.DEAD:
			break
	assert_true(landed, "the helicopter touched down before the round arrived")
	assert_eq(hits_on_helo[0], 0, "no impact is rolled against a stowed airframe")
	assert_eq(r.dead_reason, "TARGET LOST", "the seeker reports the lost target")
	wm.free()
	av.free()
	um.free()


# --- Sensors ---------------------------------------------------------------------------------

## A dipping set is in the water only while the helicopter hovers low. In cruise it hears neither
## a pinging ship nor a running torpedo.
func test_dipping_sonar_hears_nothing_in_cruise_flight() -> void:
	Terrain.clear()
	Detection.set_environment({"sea_state": 2})
	var helo := _unit("cw90_sh3h", "BLUE", Vector2.ZERO)
	var dipping := false
	for s in helo.sensors:
		dipping = dipping or (s.kind == "sonar" and s.requires_hover)
	assert_true(dipping, "the SH-3H carries a dipping sonar")
	helo.flight_state = Unit.FlightState.AIRBORNE
	helo.altitude_m = helo.spec.cruise_altitude_m
	helo.speed_kn = helo.spec.cruise_speed_kn
	var red := _unit("cw90_slava", "RED", Vector2(0.0, 14.0))
	red.active_sonar_on = true
	var torpedo: WeaponSpec = null
	for w in DataDB.all_weapons():
		if w.is_torpedo():
			torpedo = w
			break
	assert_true(not helo.is_hovering(), "cruising, not hovering")
	assert_near(Detection.active_sonar_detection_nm(helo, red), 0.0, 0.001, "no ping heard in cruise")
	assert_near(Detection.torpedo_detection_nm(helo, torpedo), 0.0, 0.001, "no torpedo heard in cruise")
	helo.altitude_m = 20.0
	helo.speed_kn = 0.0
	assert_true(helo.is_hovering(), "now in the dip")
	assert_true(Detection.active_sonar_detection_nm(helo, red) > 0.0, "the dipping set hears the ping once in the water")
	assert_true(Detection.torpedo_detection_nm(helo, torpedo) > 0.0, "and a torpedo")
	Detection.set_environment({})


# --- Objectives ------------------------------------------------------------------------------

## The scenario editor writes a reach-area objective with no named units. It must mean the
## player's force, not nobody.
func test_an_editor_area_objective_is_about_the_player_force() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var ship := _unit("cw90_spruance", "BLUE", Vector2(0, 20), "Spruance")
	um.add_unit(ship)
	var mm := MissionManager.new()
	mm.unit_manager = um
	mm.player_faction = "BLUE"
	mm.configure({"objectives": {"victory": [{"id": "reach", "type": "reach_area", "center_nm": [0.0, 20.0], "radius_nm": 8.0, "callsigns": [], "text": "Bring the force into the objective area"}]}})
	var o: MissionObjective = mm.victory_objectives[0]
	assert_eq(o.faction, "BLUE", "the objective is scoped to the player's faction")
	assert_true(o.evaluate(um, 10.0), "a ship inside the area completes it")
	mm.free()
	um.free()


## A whole-force area count counts ships and flying aircraft, not airframes in a hangar.
func test_stowed_aircraft_do_not_count_as_arrivals() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var cv := _unit("cw90_nimitz", "RED", Vector2(0, 20), "CV")
	um.add_unit(cv)
	for i in 2:
		var a := _unit("cw90_sh3h", "RED", Vector2(500, 500), "helo %d" % i)
		a.home = cv
		cv.embarked.append(a)
		um.add_unit(a)
	um.tick(0.25)  # stowed airframes ride the deck into the area
	var o := MissionObjective.from_dict({"type": "reach_area", "faction": "RED", "center_nm": [0.0, 20.0], "radius_nm": 8.0, "count": 3})
	assert_true(not o.evaluate(um, 10.0), "one carrier is one arrival, whatever is in its hangar")
	var o1 := MissionObjective.from_dict({"type": "reach_area", "faction": "RED", "center_nm": [0.0, 20.0], "radius_nm": 8.0, "count": 1})
	assert_true(o1.evaluate(um, 10.0), "the carrier itself counts")
	um.free()


## A raider that flies home off the chart has departed. It has not been neutralized, so an
## objective to destroy it stays open, and a loss condition on it is not triggered.
func test_a_departed_aircraft_is_not_a_lost_aircraft() -> void:
	var um := UnitManager.new()
	var raider := _unit("cw90_tu22m3", "RED", Vector2.ZERO, "Backfire raid 1")
	um.add_unit(raider)
	var kill := MissionObjective.from_dict({"type": "all_units_lost", "callsigns": ["Backfire raid 1"]})
	var any := MissionObjective.from_dict({"type": "unit_lost", "callsigns": ["Backfire raid 1"]})
	raider.alive = false
	raider.departed = true
	assert_true(not kill.evaluate(um, 10.0), "flying home is not being destroyed")
	assert_true(not any.evaluate(um, 10.0), "nor being lost")
	raider.departed = false
	assert_true(kill.evaluate(um, 20.0), "shot down, it is lost")
	um.free()


## The off-map return marks the aircraft departed as it leaves the board.
func test_off_map_return_marks_the_aircraft_departed() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var raider := _unit("cw90_tu22m3", "RED", Vector2(0.0, 160.0), "Backfire raid 1")
	raider.flight_state = Unit.FlightState.AIRBORNE
	raider.altitude_m = raider.spec.cruise_altitude_m
	raider.speed_kn = raider.spec.cruise_speed_kn
	raider.fuel_s = raider.spec.endurance_s * 0.2
	um.add_unit(raider)
	var av := AviationManager.new()
	av.unit_manager = um
	av.map_center = Vector2.ZERO
	av.map_extent_nm = 300.0
	var now := 0.0
	for i in 4 * 900:
		now += 0.25
		um.tick(0.25)
		av.tick(0.25, now)
		if not raider.alive:
			break
	assert_true(not raider.alive, "the raider left the board")
	assert_true(raider.departed, "and is recorded as departed rather than lost")
	av.free()
	um.free()


# --- Command deck ----------------------------------------------------------------------------

## A deck aircraft selected from the roster sees through its ship. Its own sensors are dark and it
## is off the link, so taking it as the reference would blank the picture and every alert.
func test_a_stowed_aircraft_defers_the_picture_to_its_ship() -> void:
	var ship := _unit("cw90_spruance", "BLUE", Vector2.ZERO, "Spruance")
	var helo := _unit("cw90_sh60b", "BLUE", Vector2.ZERO, "Seahawk")
	helo.home = ship
	ship.embarked.append(helo)
	var map := TacticalMap.new()
	map.selected = [helo]
	assert_eq(map.reference_unit(), ship, "a stowed airframe's picture is its ship's")
	helo.flight_state = Unit.FlightState.AIRBORNE
	helo.altitude_m = 150.0
	assert_eq(map.reference_unit(), helo, "once flying it is its own reference")
	map.free()


## Arming Plot Move mid-drag must release the drag; the move tool swallows the button release.
func test_arming_plot_move_releases_a_drag_in_progress() -> void:
	var ship := _unit("cw90_spruance", "BLUE", Vector2.ZERO, "Spruance")
	var um := UnitManager.new()
	um.add_unit(ship)
	var map := TacticalMap.new()
	map.unit_manager = um
	map.player_faction = "BLUE"
	map.selected = [ship]
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = Vector2(200, 200)
	map._begin_drag(TacticalMap.DragMode.PAN, press)
	assert_eq(map._drag_mode, TacticalMap.DragMode.PAN, "the pan has begun")
	map.set_move_mode(true)
	assert_eq(map.interaction_mode, TacticalMap.InteractionMode.MOVE, "the move tool is armed")
	assert_eq(map._drag_mode, TacticalMap.DragMode.NONE, "and the pan is released")
	map.free()
	um.free()


## Altitude presets mean each airframe's own cruise or ceiling, not the first one's.
func test_altitude_presets_are_per_airframe() -> void:
	var helo := _unit("cw90_sh3h", "BLUE", Vector2.ZERO, "Sea King")
	var jet := _unit("cw90_s3a", "BLUE", Vector2.ZERO, "Viking")
	for a in [helo, jet]:
		a.flight_state = Unit.FlightState.AIRBORNE
		a.altitude_m = 300.0
	assert_true(helo.spec.cruise_altitude_m != jet.spec.cruise_altitude_m, "the two cruise at different heights")
	var panel := OrdersPanel.new()
	panel._units = [helo, jet]
	var sent: Array = []
	panel.unit_orders_requested.connect(func(pairs: Array) -> void: sent.append_array(pairs))
	panel._emit_altitude(-1.0)
	assert_eq(sent.size(), 2, "one order per airframe")
	for pair: Array in sent:
		var u: Unit = pair[0]
		assert_near((pair[1] as Order).altitude_m, u.spec.cruise_altitude_m, 0.01, "%s goes to its own cruise altitude" % u.callsign)
	sent.clear()
	panel._emit_altitude(-2.0)
	for pair: Array in sent:
		var u: Unit = pair[0]
		assert_near((pair[1] as Order).altitude_m, u.spec.max_altitude_m, 0.01, "%s goes to its own ceiling" % u.callsign)
	panel.free()
