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
