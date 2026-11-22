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
