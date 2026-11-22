extends TestCase
## Formation keeping, helm orders and a submarine's own initiative. An escort sent off by a helm
## order is still part of the screen; station keeping regains station in minutes, not hours; a helm
## order does what it says and no more; and a boat out of touch under Classic rules still looks
## after itself.

const DT := 0.25


func _ship(pos := Vector2.ZERO, callsign := "", platform := "usn_ddg_arleigh_burke_iia") -> Unit:
	var u := Unit.new()
	u.spec = DataDB.platform(platform)
	for sid in u.spec.sensor_ids:
		var sensor := DataDB.sensor(sid)
		if sensor != null:
			u.sensors.append(sensor)
	for wid: String in u.spec.weapon_loadout:
		var w := DataDB.weapon(wid)
		if w != null:
			u.weapons.append(w)
			u.magazines[wid] = int(u.spec.weapon_loadout[wid])
	u.faction = "BLUE"
	u.callsign = callsign
	u.position = pos
	u.health = u.spec.health
	if u.spec.domain == "air":
		u.flight_state = Unit.FlightState.AIRBORNE
		u.fuel_s = u.spec.endurance_s
		u.altitude_m = u.spec.cruise_altitude_m
		u.ordered_altitude_m = u.spec.cruise_altitude_m
	return u


func _run(um: UnitManager, seconds: float, now_start := 0.0) -> float:
	var now := now_start
	for i in int(round(seconds / DT)):
		now += DT
		um.tick(DT, now)
	return now


func _screen(um: UnitManager) -> Array[Unit]:
	var guide := _ship(Vector2.ZERO, "Guide")
	var escort := _ship(Vector2(4.0, 6.0), "Escort")
	guide.ordered_speed_kn = 12.0
	guide.speed_kn = 12.0
	escort.speed_kn = 12.0
	um.add_unit(guide)
	um.add_unit(escort)
	assert_true(um.issue_order(escort, Order.form_up(guide, Vector2(4.0, 6.0))))
	return [guide, escort]


# --- An escort sent off by a helm order keeps her station to go back to ---------------------

func test_a_helm_order_to_an_escort_interrupts_her_station_and_s_takes_her_back() -> void:
	Terrain.clear()
	for order: Order in [Order.move(Vector2(-20, -20)), Order.set_course(200.0), Order.stop()]:
		var um := UnitManager.new()
		var pair := _screen(um)
		var guide: Unit = pair[0]
		var escort: Unit = pair[1]
		_run(um, 30.0)
		assert_true(um.issue_order(escort, order))
		var now := _run(um, 300.0)
		assert_true(not escort.in_formation(), "she leaves the screen to do as she was told")
		assert_eq(escort.station_kind, "formation", "the station is kept to go back to")
		assert_eq(UnitManager.station_rejection(escort), "", "Return to Station is open to her")
		assert_true(um.issue_order(escort, Order.return_to_station()))
		assert_true(escort.in_formation() and escort.on_station(), "S puts her back in the screen on %s" % guide.callsign)
		var away := escort.position.distance_to(Formation.station_for(escort))
		_run(um, 900.0, now)
		assert_true(escort.position.distance_to(Formation.station_for(escort)) < away, "and she closes it")
		um.free()


func test_the_single_ship_orders_menu_offers_to_rejoin_the_formation() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var pair := _screen(um)
	var escort: Unit = pair[1]
	assert_true(um.issue_order(escort, Order.move(Vector2(-20, -20))))
	var found := {}
	for entry: Dictionary in CdsMenus.orders_items([escort], null, true, true):
		_collect(entry, found)
	assert_true(found.has("Rejoin formation"), "one ship away from her station can be sent back to it")
	var rejoin: Dictionary = found["Rejoin formation"]
	assert_true(not bool(rejoin.get("disabled", false)), "and the item is live")
	um.free()


func _collect(entry: Dictionary, out: Dictionary) -> void:
	if entry.has("text"):
		out[str(entry["text"])] = entry
	for child: Dictionary in entry.get("children", []):
		_collect(child, out)


# --- Station keeping regains station in minutes and holds it ---------------------------------

## A guide at 15 kn with four 30-knot consorts on the stations given. Returns the guide and the
## consorts, all on station and steady, the guide on 000.
func _group(um: UnitManager, offsets: Array) -> Array[Unit]:
	var guide := _ship(Vector2.ZERO, "Guide")
	guide.speed_kn = 15.0
	um.add_unit(guide)
	assert_true(um.issue_order(guide, Order.set_course(0.0)))
	assert_true(um.issue_order(guide, Order.set_speed(15.0)))
	var out: Array[Unit] = [guide]
	for i in offsets.size():
		var offset: Vector2 = offsets[i]
		var c := _ship(offset, "C%d" % (i + 1))
		c.speed_kn = 15.0
		um.add_unit(c)
		assert_true(um.issue_order(c, Order.form_up(guide, offset)))
		out.append(c)
	return out


## Seconds from now until every consort is inside tolerance and stays there to the end of the
## run; INF if one never settles.
func _settle_after(um: UnitManager, group: Array[Unit], seconds: float, now: float) -> Array:
	var settled := {}
	var t := 0.0
	while t < seconds:
		now += DT
		t += DT
		um.tick(DT, now)
		for i in range(1, group.size()):
			var c: Unit = group[i]
			var err := c.position.distance_to(Formation.station_for(c))
			if err > Formation.STATION_TOLERANCE_NM:
				settled.erase(c)
			elif not settled.has(c):
				settled[c] = t
	var worst := 0.0
	for i in range(1, group.size()):
		worst = maxf(worst, float(settled.get(group[i], INF)))
	return [worst, now]


func test_a_close_screen_regains_station_within_five_minutes_of_a_ninety_degree_turn() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var group := _group(um, [Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2(0.0, -1.0)])
	var r := _settle_after(um, group, 600.0, 0.0)
	assert_true(float(r[0]) < 300.0, "the group settles from its start positions: %.0f s" % float(r[0]))
	assert_true(um.issue_order(group[0], Order.set_course(90.0)))
	r = _settle_after(um, group, 1200.0, float(r[1]))
	assert_true(float(r[0]) < 300.0, "every consort is back inside %.1f nm within 5 minutes of the turn and stays there: %.0f s" % [Formation.STATION_TOLERANCE_NM, float(r[0])])
	um.free()


func test_a_wide_screen_settles_on_station_and_regains_it_after_a_turn() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var offsets: Array = []
	for i in 4:
		offsets.append(Formation.offset_for(i, "screen"))
	var group := _group(um, offsets)
	for i in range(1, group.size()):
		group[i].position = Vector2(-6.0 + (i - 1) * 4.0, -4.0)  # the repro's start: well off station
	var r := _settle_after(um, group, 3600.0, 0.0)
	assert_true(float(r[0]) < 3600.0, "every consort is on station within the hour, not 1-2 nm astern of it")
	for i in range(1, group.size()):
		assert_near((group[i] as Unit).speed_kn, 15.0, 0.5, "and steaming at the guide's speed")
	assert_true(um.issue_order(group[0], Order.set_course(90.0)))
	r = _settle_after(um, group, 3600.0, float(r[1]))
	# The stations swing up to ten miles; the forward ones lie up the guide's new course, and a
	# 30-knot ship needs about 40 minutes to overtake a station making 15 kn that far ahead.
	assert_true(float(r[0]) < 45.0 * 60.0, "every consort regains her station after the turn and keeps it: %.0f s" % float(r[0]))
	um.free()


func test_the_guide_keeps_knots_in_hand_for_its_consorts() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var group := _group(um, [Vector2(2.0, 0.0)])
	_run(um, 1.0)
	var consort: Unit = group[1]
	assert_true(group[0].formation_speed_cap_kn <= consort.effective_max_speed() - 3.0, "the guide paces the group a few knots under the slowest consort")
	um.free()



# --- Helm orders do what they say ----------------------------------------------------------

func test_a_speed_order_to_a_consort_keeping_station_is_refused_naming_the_guide() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var pair := _screen(um)
	var escort: Unit = pair[1]
	_run(um, 60.0)
	var order := Order.set_speed(28.0)
	assert_true(not um.issue_order(escort, order), "her speed is the station's, so the order is refused")
	assert_true(order.receipt.contains("Guide"), "and the reason names the guide: '%s'" % order.receipt)
	assert_eq(Main._refusal_reason(escort, order), order.receipt, "which is what the radio line reports")
	assert_true(um.issue_order(pair[0], Order.set_speed(20.0)), "the guide takes a speed order")
	um.free()


func test_a_course_order_to_a_stopped_ship_gets_way_on_and_steers_it() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var ship := _ship(Vector2.ZERO, "Ship")
	ship.speed_kn = 15.0
	ship.ordered_speed_kn = 15.0
	um.add_unit(ship)
	assert_true(um.issue_order(ship, Order.move(Vector2(0, 2))))
	var now := _run(um, 1200.0)
	assert_near(ship.speed_kn, 0.0, 0.01, "she stops at the end of the move")
	var lay := ship.position
	assert_true(um.issue_order(ship, Order.set_course(90.0)))
	_run(um, 600.0, now)
	assert_near(ship.heading_deg, 90.0, 2.0, "she comes round to the ordered course")
	assert_true(ship.speed_kn > 5.0 and ship.position.distance_to(lay) > 1.0, "with way on, making %.1f kn" % ship.speed_kn)
	um.free()


func test_a_last_waypoint_inside_the_turning_circle_is_reached_not_dropped() -> void:
	Terrain.clear()
	for abeam: float in [0.15, 0.25, 0.35]:
		var um := UnitManager.new()
		var ship := _ship(Vector2.ZERO, "Ship")
		ship.speed_kn = 20.0
		ship.ordered_speed_kn = 20.0
		um.add_unit(ship)
		var point := Vector2(abeam, 0.0)
		assert_true(um.issue_order(ship, Order.move(point)))
		_run(um, DT)
		assert_true(not ship.waypoints.is_empty(), "a point %.2f nm abeam is not dropped on the first tick" % abeam)
		var closest := INF
		var now := 0.0
		while now < 600.0 and not ship.waypoints.is_empty():
			now = _run(um, DT, now)
			closest = minf(closest, ship.position.distance_to(point))
		assert_true(closest <= 0.12, "she opens out and comes back to it: closest %.2f nm" % closest)
		assert_true(ship.waypoints.is_empty(), "and arrives there")
		um.free()


# --- A boat under Classic communications ----------------------------------------------------

func _classic_boat(um: UnitManager, platform := "jmsdf_ssk_taigei", depth := 200.0) -> Unit:
	var boat := _ship(Vector2.ZERO, "Boat", platform)
	boat.speed_kn = 5.0
	boat.ordered_speed_kn = 5.0
	boat.depth_m = depth
	boat.ordered_depth_m = depth
	um.add_unit(boat)
	um.configure_submarine_comms("BLUE", true)
	return boat


func test_a_snorkel_order_delivered_at_check_in_is_not_undone_when_the_window_closes() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var boat := _classic_boat(um)
	boat.battery = 0.25
	assert_true(um.issue_order(boat, Order.request_sub_checkin()))
	var snorkel := Order.snorkel(true)
	assert_true(um.issue_order(boat, snorkel))
	assert_true(snorkel.receipt.begins_with("Queued"), "deep, the order waits for the check-in")
	var now := _run(um, 1800.0)
	assert_true(boat.depth_m <= Unit.PERISCOPE_DEPTH_M, "she stays up to snorkel after the window: %.0f m" % boat.depth_m)
	assert_true(SubmarinePower.on_diesels(boat), "on her diesels")
	var charge := boat.battery
	_run(um, 600.0, now)
	assert_true(boat.battery > charge, "and charging")
	boat.battery = SubmarinePower.FULL
	_run(um, 60.0, now + 600.0)
	assert_true(not boat.snorkel_on, "the crew secures when the charge is complete")
	assert_near(boat.ordered_depth_m, 200.0, 0.1, "and takes her back to the depth she came up from")
	um.free()


# --- Aircraft keep their height over the ground --------------------------------------------

func test_an_aircraft_ordered_low_climbs_over_high_ground_and_never_flies_into_it() -> void:
	Terrain.load_from({"terrain": {"land": [{"id": "ridge", "name": "Ridge", "elevation_m": 900.0, "points_nm": [[-20.0, 20.0], [20.0, 20.0], [20.0, 40.0], [-20.0, 40.0]]}]}})
	var um := UnitManager.new()
	var jet := _ship(Vector2.ZERO, "Jet", "usn_fighter_fa18e")
	jet.speed_kn = 420.0
	jet.ordered_speed_kn = 420.0
	um.add_unit(jet)
	assert_true(um.issue_order(jet, Order.set_altitude(150.0)))
	assert_true(um.issue_order(jet, Order.move(Vector2(0.0, 60.0))))
	var lowest_over_land := INF
	var now := 0.0
	while now < 600.0 and jet.position.y < 45.0:
		now = _run(um, 1.0, now)
		if Terrain.elevation_at(jet.position) > 0.0:
			lowest_over_land = minf(lowest_over_land, jet.altitude_m - Terrain.elevation_at(jet.position))
	assert_true(jet.position.y >= 45.0, "she crossed the ridge")
	assert_true(lowest_over_land >= Movement.TERRAIN_CLEARANCE_FIXED_WING_M * 0.9, "with a safety height over it all the way: %.0f m at the lowest" % lowest_over_land)
	_run(um, 300.0, now)
	assert_near(jet.altitude_m, 150.0, 1.0, "and comes back down to the ordered height over the sea")
	Terrain.clear()
	um.free()


func test_an_altitude_order_is_held_above_the_sea() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var jet := _ship(Vector2.ZERO, "Jet", "usn_fighter_fa18e")
	jet.speed_kn = 420.0
	jet.ordered_speed_kn = 420.0
	um.add_unit(jet)
	assert_true(um.issue_order(jet, Order.set_altitude(0.0)))
	_run(um, 600.0)
	assert_true(jet.alive and jet.altitude_m >= Unit.MIN_ALTITUDE_FIXED_WING_M - 0.01, "a jet is not flown into the sea: %.0f m" % jet.altitude_m)
	um.free()


# --- A helm order does not silently stow the sensor ----------------------------------------

func _streamed_frigate(um: UnitManager) -> Unit:
	var ship := _ship(Vector2.ZERO, "Frigate", "fra_ffg_fremm")
	ship.speed_kn = 8.0
	ship.ordered_speed_kn = 8.0
	um.add_unit(ship)
	assert_true(TowedArray.capable(ship), "the frigate tows an array")
	assert_true(um.issue_order(ship, Order.asw_search()))
	_run(um, TowedArray.STREAM_S + 10.0)
	assert_eq(ship.array_phase, TowedArray.Phase.LISTENING)
	TowedArray.take_events()
	return ship


func test_helm_and_task_orders_keep_the_towed_array_streamed() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var ship := _streamed_frigate(um)
	var t := Track.new()
	t.id = "0400"
	t.owner_faction = "BLUE"
	t.position = Vector2(6.0, 6.0)
	t.domain = "subsurface"
	for order: Order in [Order.set_course(ship.heading_deg + 20.0), Order.set_speed(5.0), Order.move(Vector2(-5.0, 5.0)), Order.patrol_box(Vector2(-6, 4), Vector2(6, 12)), Order.investigate(t)]:
		assert_true(um.issue_order(ship, order), "order %d accepted" % order.type)
		_run(um, 30.0)
		assert_eq(ship.array_phase, TowedArray.Phase.LISTENING, "order %d is steered with the array streamed" % order.type)
		assert_true(ship.speed_kn <= TowedArray.QUIET_SPEED_KN + 0.1, "at the towing speed")
	assert_true(TowedArray.take_events().is_empty(), "nothing to report")
	um.free()


func test_a_speed_above_the_towing_limit_recovers_the_array_and_says_so() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var ship := _streamed_frigate(um)
	assert_true(um.issue_order(ship, Order.set_speed(24.0)))
	assert_eq(ship.array_phase, TowedArray.Phase.RECOVERING, "the cable will not take 24 knots")
	var events := TowedArray.take_events()
	assert_true(events.size() == 1 and events[0]["unit"] == ship and events[0]["event"] == "array_recovering", "the recovery is reported")
	um.free()


func test_a_dipping_helicopter_holds_the_dip_for_a_hover_order_and_reports_raising_the_dome() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var helo := _ship(Vector2.ZERO, "Helo", "usn_helo_mh60r")
	helo.altitude_m = 20.0
	um.add_unit(helo)
	assert_true(um.issue_order(helo, Order.deploy_dipping_sonar(0.0)))
	_run(um, DippingSonar.LOWER_S + 120.0)
	assert_true(DippingSonar.listening(helo), "in the dip")
	DippingSonar.take_events()
	assert_true(um.issue_order(helo, Order.set_speed(0.0)))
	assert_true(DippingSonar.listening(helo), "an order to hold still keeps the dome in the water")
	assert_true(DippingSonar.take_events().is_empty())
	assert_true(um.issue_order(helo, Order.move(Vector2(10, 10))))
	assert_eq(helo.dip_phase, DippingSonar.Phase.RAISING, "she cannot fly off with the dome down")
	var events := DippingSonar.take_events()
	assert_true(events.size() == 1 and events[0]["event"] == "dip_raising", "and the crew says the dome is coming up")
	um.free()


func _fish(boat: Unit, tm: ThreatManager, from: Vector2) -> Weapon:
	var fish := Weapon.new()
	fish.id = 9101
	fish.faction = "RED"
	fish.spec = DataDB.weapon("cw90_53_65")
	fish.position = from
	fish.heading_deg = Geo.bearing_deg(from, boat.position)
	fish.acquired = boat
	tm.mark_detected(boat.faction, fish, 0.0, boat)
	return fish


func test_a_boat_out_of_touch_turns_away_from_a_torpedo_she_hears_and_reports_it_at_check_in() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var boat := _classic_boat(um, "usn_ssn_virginia", 200.0)
	_run(um, 1.0)
	assert_true(not SubmarineComms.connected(boat), "deep and out of touch")
	var tm := ThreatManager.new()
	_fish(boat, tm, boat.position + Vector2(3.0, 0.0))
	SubmarineInitiative.run_cycle(um, tm)
	assert_true(boat.evasion_remaining_s > 0.0, "she turns away without waiting for orders")
	assert_true(absf(Geo.heading_delta(boat.evasion_course_deg, 270.0)) < 1.0, "away from the torpedo")
	assert_eq(boat.comms_initiative.size(), 1, "and the crew logs it for the next report")
	SubmarineComms.take_events()
	assert_true(um.issue_order(boat, Order.request_sub_checkin()))
	_run(um, 900.0, 1.0)
	assert_true(boat.comms_initiative_report.contains("torpedo"), "she reports it at the check-in: '%s'" % boat.comms_initiative_report)
	var events := SubmarineComms.take_events()
	assert_true(events.size() == 1 and events[0]["event"] == "initiative_report")
	um.free()


func test_evade_and_decoy_orders_to_a_deep_boat_are_never_queued_for_check_in() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var boat := _classic_boat(um, "usn_ssn_virginia", 200.0)
	_run(um, 1.0)
	for order: Order in [Order.evade(), Order.deploy_countermeasures("acoustic")]:
		um.issue_order(boat, order)
		assert_true(not order.receipt.begins_with("Queued"), "order %d is the crew's to act on now" % order.type)
	assert_true(boat.comms_pending.is_empty(), "nothing waits for a check-in")
	um.free()


func test_a_diesel_boat_out_of_touch_snorkels_by_herself_at_critical_battery() -> void:
	Terrain.clear()
	var um := UnitManager.new()
	var boat := _classic_boat(um, "rfn_ssk_kilo", 200.0)
	boat.battery = SubmarinePower.CRITICAL - 0.01
	_run(um, 1.0)
	assert_true(um.issue_order(boat, Order.set_sub_comms_interval(0.0)), "check-in on demand: nobody calls her up")
	var tm := ThreatManager.new()
	SubmarineInitiative.run_cycle(um, tm)
	assert_true(boat.snorkel_on, "she comes up to snorkel by herself")
	_run(um, 1200.0, 1.0)
	assert_true(SubmarinePower.on_diesels(boat), "and charges")
	assert_true(boat.comms_initiative_report.contains("snorkel"), "which she reports once she is up: '%s'" % boat.comms_initiative_report)
	um.free()
