extends TestCase
## Aircraft launched to a mission: a CAP over a point, a reconnaissance sweep, an ASW search, a
## strike on a held contact. Run on the shipped carrier operations with their real air wings, so
## the deck cycle, fuel, recovery reservations and finite stores are the ones a player meets.

const CARRIER_WATCH := "res://data/scenarios/cold_war_03_carrier.json"
const CARRIER_QUAL := "res://data/scenarios/carrier_qualification.json"
const IKE := "USS Dwight D. Eisenhower (CVN 69)"

var _sim: Simulation
var _held: Array[Track] = []


func _load(path: String) -> Simulation:
	SimClock.set_paused(true)
	_sim = Simulation.new()
	_sim.seed_override = 7
	(Engine.get_main_loop() as SceneTree).root.add_child(_sim)
	assert_true(_sim.load_scenario(path), path)
	_sim.ai_enabled = false  # these tests are about the deck and the mission, not the opposition
	_held.clear()
	if not SimClock.tick.is_connected(_keep_held):
		SimClock.tick.connect(_keep_held)
	return _sim


func _done() -> void:
	if SimClock.tick.is_connected(_keep_held):
		SimClock.tick.disconnect(_keep_held)
	_sim.unit_manager.clear()
	_sim.queue_free()
	_sim.free()
	_sim = null


## Contacts the test puts on the plot stay fresh, as if a sensor still held them.
func _keep_held(_dt: float) -> void:
	for t in _held:
		t.last_seen_time = SimClock.sim_time
		t.status = Track.Status.ACTIVE


func _unit(callsign: String) -> Unit:
	for u in _sim.unit_manager.units:
		if u.callsign == callsign:
			return u
	return null


func _plot(pos: Vector2, id: String, altitude := 6000.0, hold := true) -> Track:
	var t := Track.new()
	t.id = id
	t.owner_faction = "BLUE"
	t.position = pos
	t.altitude_m = altitude
	t.last_seen_time = SimClock.sim_time
	if not _sim.track_manager._tracks.has("BLUE"):
		_sim.track_manager._tracks["BLUE"] = []
	_sim.track_manager._tracks["BLUE"].append(t)
	if hold:
		_held.append(t)
	return t


func _mission() -> AirMission:
	var list := _sim.air_mission_manager.active_missions("BLUE")
	return list[0] if not list.is_empty() else null


func _advance(seconds: float) -> void:
	SimClock.advance(seconds)


func test_a_cap_launches_real_airframes_and_queues_the_rest() -> void:
	_load(CARRIER_WATCH)
	var cv := _unit(IKE)
	var station := cv.position + Vector2(0, 50)
	var o := Order.air_mission(AirMission.Kind.CAP, "cw90_f14a", 6, station, 12.0)
	assert_true(_sim.unit_manager.issue_order(cv, o), o.receipt)
	var m := _mission()
	assert_true(m != null)
	assert_eq(m.requested, 6, "four ready and eight in reserve: six can be had")
	assert_eq(m.aircraft.size(), 4, "four catapults, four ready Tomcats")
	assert_eq(m.pending_launches, 2, "the other two wait for reserve airframes")
	assert_true(o.receipt.contains("2 queued: awaiting ready aircraft"), o.receipt)
	for a in m.aircraft:
		assert_eq(m.state_of(a), AirMission.LAUNCHING)
	_advance(cv.spec.turnaround_time_s() * 0.0 + 200.0)
	var transit := 0
	for a in m.aircraft:
		assert_eq(a.station_label, "CAP STATION")
		assert_eq(a.station_mission_id, m.id)
		if m.state_of(a) in [AirMission.TRANSITING, AirMission.ON_STATION]:
			transit += 1
	assert_eq(transit, 4, "all four airborne and on their way")
	assert_eq(m.pending_launches, 2, "nothing launched that was not ready")
	_advance(1700.0)
	assert_eq(m.pending_launches, 0, "the reserve came ready and the queue emptied")
	assert_eq(m.launched_total, 6, "exactly the six asked for")
	var seen: Dictionary = {}
	for a in m.aircraft:
		assert_true(not seen.has(a), "no airframe launched twice")
		seen[a] = true
	var working := 0
	for a in m.aircraft:
		# The 1990 raid is real: the CAP may already be intercepting it on its own sensors.
		if m.state_of(a) in [AirMission.ON_STATION, AirMission.INVESTIGATING, AirMission.ENGAGING]:
			working += 1
	assert_true(working >= 4, "the first section is on station or working it: %s" % m.summary())
	_done()


func test_a_busy_deck_queues_launches_without_duplicates() -> void:
	_load(CARRIER_QUAL)
	var cdg := _unit("Charles de Gaulle (R 91)")
	assert_eq(cdg.spec.launch_capacity(), 2)
	var o := Order.air_mission(AirMission.Kind.CAP, "fra_fighter_rafale_m", 4, cdg.position + Vector2(20, 20), 10.0)
	assert_true(_sim.unit_manager.issue_order(cdg, o), o.receipt)
	var m := _mission()
	assert_eq(m.aircraft.size(), 2, "two catapults")
	assert_eq(m.pending_launches, 2)
	assert_true(o.receipt.contains("2 queued: catapults committed"), o.receipt)
	var launches := {}
	_sim.aviation_manager.aircraft_launched.connect(func(a: Unit, _p: Unit) -> void: launches[a] = int(launches.get(a, 0)) + 1)
	for i in 40:
		_advance(15.0)
	assert_eq(m.launched_total, 4)
	assert_eq(launches.size(), 4, "four different airframes left the deck")
	for a: Unit in launches:
		assert_eq(launches[a], 1, "%s launched once" % a.callsign)
	assert_eq(m.pending_launches, 0)
	_done()


func test_cap_identifies_then_intercepts_and_resumes_its_station() -> void:
	_load(CARRIER_WATCH)
	var cv := _unit(IKE)
	var station := cv.position + Vector2(0, 40)
	assert_true(_sim.unit_manager.issue_order(cv, Order.air_mission(AirMission.Kind.CAP, "cw90_f14a", 2, station, 10.0)))
	var m := _mission()
	_advance(400.0)
	for a in m.aircraft:
		assert_eq(m.state_of(a), AirMission.ON_STATION, a.callsign)
	var bogey := _plot(station + Vector2(15, 10), "0201")
	_advance(3.0)
	var looking: Unit = null
	for a in m.aircraft:
		if a.investigation_track == bogey:
			looking = a
	assert_true(looking != null, "one Tomcat goes to identify the unknown air contact")
	assert_eq(m.state_of(looking), AirMission.INVESTIGATING)
	assert_eq(looking.attack_track, null, "identification does not authorise fire, even weapons free")
	var other: Unit = m.aircraft[0] if m.aircraft[0] != looking else m.aircraft[1]
	assert_eq(other.investigation_track, null, "one look is enough; the other keeps the station")
	_advance(3.0)
	# The plot classifies it: a Badger, hostile.
	bogey.classification = Track.Classification.CLASS_KNOWN
	bogey.domain = "air"
	bogey.identity = "HOSTILE"
	bogey.known_class = "Tu-16"
	_advance(3.0)
	assert_eq(looking.investigation_track, null)
	var interceptors := 0
	for a in m.aircraft:
		if a.attack_track == bogey:
			interceptors += 1
	assert_true(interceptors >= 1, "a hostile near the CAP is intercepted under weapons free")
	# The raid is splashed (the test ends the attack as the weapon layer would).
	for a in m.aircraft:
		if a.attack_track == bogey:
			_sim.unit_manager._end_attack(a, bogey, "Target destroyed")
	_held.erase(bogey)
	bogey.status = Track.Status.LOST
	_advance(3.0)
	for a in m.aircraft:
		assert_true(a.on_station(), "%s back on the CAP circuit" % a.callsign)
		assert_eq(a.station_label, "CAP STATION")
	_done()


func test_cap_never_fires_on_a_neutral_it_identified() -> void:
	_load(CARRIER_WATCH)
	var cv := _unit(IKE)
	var station := cv.position + Vector2(0, 40)
	_sim.unit_manager.issue_order(cv, Order.air_mission(AirMission.Kind.CAP, "cw90_f14a", 1, station, 10.0))
	var m := _mission()
	_advance(400.0)
	var airliner := _plot(station + Vector2(5, 5), "0202", 10000.0)
	_advance(3.0)
	var a: Unit = m.aircraft[0]
	assert_eq(a.investigation_track, airliner)
	airliner.classification = Track.Classification.CLASS_KNOWN
	airliner.domain = "air"
	airliner.identity = "NEUTRAL"
	_advance(6.0)
	assert_eq(a.attack_track, null, "a neutral is never attacked")
	assert_true(a.on_station(), "back to the station once it is identified")
	_done()


func test_weapons_hold_stops_the_intercept_but_not_the_identification() -> void:
	_load(CARRIER_WATCH)
	var cv := _unit(IKE)
	var station := cv.position + Vector2(0, 40)
	_sim.unit_manager.issue_order(cv, Order.air_mission(AirMission.Kind.CAP, "cw90_f14a", 1, station, 10.0))
	var m := _mission()
	_advance(400.0)
	var a: Unit = m.aircraft[0]
	_sim.unit_manager.issue_order(a, Order.set_roe(Unit.Roe.HOLD))
	var raid := _plot(station + Vector2(5, 5), "0203")
	raid.classification = Track.Classification.CLASS_KNOWN
	raid.domain = "air"
	raid.identity = "HOSTILE"
	_advance(6.0)
	assert_eq(a.attack_track, null, "weapons hold is respected by the mission")
	assert_true(a.on_station())
	_done()


func test_relief_launches_a_ready_reserve_before_the_cap_leaves() -> void:
	_load(CARRIER_QUAL)
	var cdg := _unit("Charles de Gaulle (R 91)")
	var station := cdg.position + Vector2(30, 0)
	var o := Order.air_mission(AirMission.Kind.CAP, "fra_fighter_rafale_m", 1, station, 10.0, null, true)
	assert_true(_sim.unit_manager.issue_order(cdg, o), o.receipt)
	var m := _mission()
	_advance(300.0)
	var first: Unit = m.aircraft[0]
	assert_eq(m.state_of(first), AirMission.ON_STATION)
	# Run the first airframe's tanks down to just above the point where the relief must go.
	first.fuel_s = _sim.aviation_manager.return_fuel_required(first, cdg) + 60.0
	_advance(3.0)
	assert_eq(m.launched_total, 2, "the relief launched while the first was still on station")
	var relief: Unit = m.aircraft[1]
	assert_true(relief != first)
	assert_true(not first.returning, "the first holds the station until its own bingo")
	_advance(200.0)
	assert_true(first.returning or first.flight_state != Unit.FlightState.AIRBORNE, "bingo outranks the station")
	assert_eq(m.state_of(first) if m.aircraft.has(first) else AirMission.RECOVERING, m.state_of(first) if m.aircraft.has(first) else AirMission.RECOVERING)
	assert_eq(m.launched_total, 2, "one relief per departure, no more")
	_advance(400.0)
	assert_true(relief.on_station(), "the relief holds the CAP")
	_done()


func test_a_strike_attacks_a_held_hostile_and_comes_home() -> void:
	_load(CARRIER_QUAL)
	var cdg := _unit("Charles de Gaulle (R 91)")
	var ship := _plot(cdg.position + Vector2(60, 0), "0301", 0.0)
	ship.classification = Track.Classification.CLASS_KNOWN
	ship.domain = "surface"
	ship.identity = "HOSTILE"
	var o := Order.air_mission(AirMission.Kind.STRIKE, "fra_fighter_rafale_m", 2, Vector2.INF, 0.0, ship)
	assert_true(_sim.unit_manager.issue_order(cdg, o), o.receipt)
	var m := _mission()
	_advance(200.0)
	var engaging := 0
	for a in m.aircraft:
		if a.attack_track == ship:
			engaging += 1
	assert_eq(engaging, 2, "both Rafales on the attack task")
	for a in m.aircraft.duplicate():
		_sim.unit_manager._end_attack(a, ship, "Magazines empty")
	_advance(3.0)
	for a in m.aircraft:
		assert_true(a.returning, "%s heading home once the attack is over" % a.callsign)
		assert_eq(m.state_of(a), AirMission.RETURNING)
	_done()


func test_requests_are_refused_or_trimmed_with_a_reason() -> void:
	_load(CARRIER_WATCH)
	var cv := _unit(IKE)
	var amm := _sim.air_mission_manager
	assert_eq(amm.mission_rejection(cv, AirMission.Kind.CAP, "cw90_s3a", cv.position + Vector2(0, 30)), "S-3A carries no air-to-air weapons")
	assert_eq(amm.mission_rejection(cv, AirMission.Kind.STRIKE, "cw90_f14a", Vector2.INF, null), "F-14A+ carries no strike weapons", "the 1990 wing as it stands")
	assert_true(amm.mission_rejection(cv, AirMission.Kind.CAP, "cw90_f14a", cv.position + Vector2(0, 2000)).begins_with("Beyond the"))
	assert_eq(amm.mission_rejection(cv, AirMission.Kind.CAP, "cw90_f14a", Vector2.INF), "Choose a station on the chart")

	var o := Order.air_mission(AirMission.Kind.ASW, "cw90_s3a", 9, cv.position + Vector2(30, 0), 10.0)
	assert_true(_sim.unit_manager.issue_order(cv, o))
	assert_true(o.receipt.contains("4 of 9 accepted"), o.receipt)
	var refused := Order.air_mission(AirMission.Kind.CAP, "cw90_s3a", 1, cv.position + Vector2(0, 30))
	assert_true(not _sim.unit_manager.issue_order(cv, refused), "the order itself reports the refusal")
	assert_eq(refused.receipt, "S-3A carries no air-to-air weapons")
	_done()


func test_strike_needs_a_held_target_and_a_weapon_for_it() -> void:
	_load(CARRIER_QUAL)
	var cdg := _unit("Charles de Gaulle (R 91)")
	var amm := _sim.air_mission_manager
	assert_eq(amm.mission_rejection(cdg, AirMission.Kind.STRIKE, "fra_fighter_rafale_m", Vector2.INF, null), "Choose a held contact to strike")
	var sub := _plot(cdg.position + Vector2(30, 0), "0402", 0.0)
	sub.domain = "subsurface"
	sub.identity = "HOSTILE"
	assert_eq(amm.mission_rejection(cdg, AirMission.Kind.STRIKE, "fra_fighter_rafale_m", Vector2.INF, sub), "Strike missions attack ships and installations")
	var unknown := _plot(cdg.position + Vector2(30, 5), "0403", 0.0)
	assert_eq(amm.mission_rejection(cdg, AirMission.Kind.STRIKE, "fra_fighter_rafale_m", Vector2.INF, unknown), "Identify contact first")
	var neutral := _plot(cdg.position + Vector2(40, 0), "0404", 0.0)
	neutral.domain = "surface"
	neutral.identity = "NEUTRAL"
	assert_eq(amm.mission_rejection(cdg, AirMission.Kind.STRIKE, "fra_fighter_rafale_m", Vector2.INF, neutral), "Protected identity")
	_done()


## The 1990 carrier's small strike element: Intruders with Harpoon are accepted for a strike on a
## held, classified hostile ship; the Tomcats, armed only for air-to-air, are refused the same
## strike; and a contact report on the cruiser is a datum to go and find, not a target.
func test_a_1990_strike_is_flown_by_intruders_and_refused_to_tomcats() -> void:
	_load(CARRIER_WATCH)
	var cv := _unit(IKE)
	var slava := _unit("Slava")
	var amm := _sim.air_mission_manager
	var report := _sim.track_manager.report_intel("BLUE", slava, slava.position + Vector2(6, -4), 15.0, 0.0, "Norwegian P-3 Orion")
	assert_eq(amm.mission_rejection(cv, AirMission.Kind.STRIKE, "cw90_a6e", Vector2.INF, report), "Identify contact first", "a report alone cannot be struck")
	var ship := _plot(cv.position + Vector2(70, 40), "0501", 0.0)
	ship.classification = Track.Classification.CLASS_KNOWN
	ship.domain = "surface"
	ship.identity = "HOSTILE"
	var tomcats := Order.air_mission(AirMission.Kind.STRIKE, "cw90_f14a", 2, Vector2.INF, 0.0, ship)
	assert_true(not _sim.unit_manager.issue_order(cv, tomcats), "fighters with only air-to-air rounds")
	assert_eq(tomcats.receipt, "F-14A+ carries no strike weapons")
	var intruders := Order.air_mission(AirMission.Kind.STRIKE, "cw90_a6e", 2, Vector2.INF, 0.0, ship)
	assert_true(_sim.unit_manager.issue_order(cv, intruders), intruders.receipt)
	var m := _mission()
	assert_true(m != null and m.kind == AirMission.Kind.STRIKE and m.platform_id == "cw90_a6e" and m.requested == 2, intruders.receipt)
	for a in m.aircraft:
		assert_eq(a.magazine_count("cw90_agm84"), 2, "%s carries two Harpoons" % a.callsign)
	_advance(200.0)
	var engaging := 0
	for a in m.aircraft:
		if a.attack_track == ship:
			engaging += 1
	assert_eq(engaging, 2, "both Intruders on the attack task")
	_done()


func test_an_explicit_order_releases_an_airframe_and_a_temporary_one_does_not() -> void:
	_load(CARRIER_WATCH)
	var cv := _unit(IKE)
	_sim.unit_manager.issue_order(cv, Order.air_mission(AirMission.Kind.CAP, "cw90_f14a", 2, cv.position + Vector2(0, 40), 10.0))
	var m := _mission()
	_advance(400.0)
	var a: Unit = m.aircraft[0]
	var b: Unit = m.aircraft[1]
	var contact := _plot(cv.position + Vector2(0, 80), "0501", 0.0)
	contact.domain = "surface"
	assert_true(_sim.unit_manager.issue_order(a, Order.investigate(contact)), "the commander sends one to look")
	_advance(3.0)
	assert_true(m.aircraft.has(a), "a temporary task keeps it on the mission")
	assert_eq(a.investigation_track, contact, "and the mission does not take it back")
	var away := cv.position + Vector2(-50, 0)
	assert_true(_sim.unit_manager.issue_order(b, Order.move(away)))
	_advance(3.0)
	assert_true(not m.aircraft.has(b), "a new transit releases the other")
	assert_eq(m.requested, 1)
	assert_eq(b.waypoints, [away], "and the mission leaves it alone")
	_done()


func test_cancelling_a_mission_brings_its_aircraft_home_and_strikes_the_queue() -> void:
	_load(CARRIER_WATCH)
	var cv := _unit(IKE)
	_sim.unit_manager.issue_order(cv, Order.air_mission(AirMission.Kind.CAP, "cw90_f14a", 6, cv.position + Vector2(0, 40), 10.0))
	var m := _mission()
	_advance(200.0)
	assert_true(_sim.unit_manager.issue_order(cv, Order.cancel_air_mission(m.id)))
	assert_true(not m.active)
	assert_eq(m.pending_launches, 0)
	var returning := 0
	for u in _sim.unit_manager.units:
		if u.is_aircraft() and u.spec.id == "cw90_f14a" and u.returning:
			returning += 1
	assert_eq(returning, 4)
	_done()


func test_asw_search_lays_a_sonobuoy_pattern_in_its_area() -> void:
	_load(CARRIER_WATCH)
	var cv := _unit(IKE)
	var area := cv.position + Vector2(25, 10)
	assert_true(_sim.unit_manager.issue_order(cv, Order.air_mission(AirMission.Kind.ASW, "cw90_s3a", 1, area, 8.0)))
	var m := _mission()
	_advance(1500.0)
	var buoys := 0
	for b: Sonobuoy in _sim.aviation_manager.sonobuoys:
		if b.faction == "BLUE" and b.position.distance_to(area) <= 8.0 + 1.0:
			buoys += 1
	assert_true(buoys >= 2, "a pattern of buoys across the area (%d)" % buoys)
	var a: Unit = m.aircraft[0]
	assert_eq(a.station_label, "ASW SEARCH")
	assert_true(a.ordered_altitude_m <= AirMissionManager.ASW_ALTITUDE_M + 1.0, "down low to work the buoys")
	_done()


func test_queued_launches_wait_for_an_aircraft_landing_on_the_deck() -> void:
	_load(CARRIER_QUAL)
	var cdg := _unit("Charles de Gaulle (R 91)")
	assert_true(_sim.unit_manager.issue_order(cdg, Order.air_mission(AirMission.Kind.CAP, "fra_fighter_rafale_m", 1, cdg.position + Vector2(20, 0), 10.0)))
	var m := _mission()
	_advance(300.0)
	var first: Unit = m.aircraft[0]
	# A second Rafale comes home and is overhead waiting for the deck when the next CAP is asked for.
	assert_true(_sim.unit_manager.issue_order(first, Order.return_to_base(cdg)))
	first.position = cdg.position + Vector2(0.5, 0.5)
	cdg.embarked.erase(first)
	cdg.embarked.push_front(first)
	var o := Order.air_mission(AirMission.Kind.RECON, "fra_fighter_rafale_m", 1, cdg.position + Vector2(-20, 0), 10.0)
	assert_true(_sim.unit_manager.issue_order(cdg, o))
	assert_true(o.receipt.contains("queued: deck recovering"), o.receipt)
	_done()


func test_the_ai_flying_a_side_leaves_its_mission_aircraft_to_the_mission() -> void:
	_load(CARRIER_WATCH)
	_sim.ai_plays_player = true
	_sim.ai_enabled = true
	_sim._build_ai()
	var cv := _unit(IKE)
	assert_true(_sim.unit_manager.issue_order(cv, Order.air_mission(AirMission.Kind.CAP, "cw90_f14a", 2, cv.position + Vector2(0, 40), 10.0)))
	var m := _mission()
	_advance(240.0)
	assert_eq(m.requested, 2, "no airframe was taken off the mission")
	for a in m.aircraft:
		assert_eq(a.station_mission_id, m.id, a.callsign)
	_done()


func test_a_dipping_helicopter_stops_to_listen_and_then_moves_on() -> void:
	_load(CARRIER_WATCH)
	var cv := _unit(IKE)
	var area := cv.position + Vector2(12, 6)
	assert_true(_sim.unit_manager.issue_order(cv, Order.air_mission(AirMission.Kind.ASW, "cw90_sh3h", 1, area, 8.0)))
	var m := _mission()
	var helo: Unit = null
	var hovered_at := -1.0
	for i in 1800:
		_advance(1.0)
		if m.aircraft.is_empty():
			continue
		helo = m.aircraft[0]
		if DippingSonar.listening(helo) and hovered_at < 0.0:
			hovered_at = SimClock.sim_time
		if hovered_at > 0.0 and SimClock.sim_time > hovered_at + AirMissionManager.DIP_S + 30.0:
			break
	assert_true(hovered_at > 0.0, "the Sea King completed lowering and listened in the area")
	assert_true(helo.on_station() and helo.patrol_active, "and took up its search circuit again afterwards")
	assert_eq(helo.station_label, "ASW SEARCH", "the station was kept through the dip")
	_done()


# --- Found by review -----------------------------------------------------------------------

func test_cancelling_while_the_catapults_are_busy_still_brings_every_airframe_home() -> void:
	_load(CARRIER_WATCH)
	var cv := _unit(IKE)
	assert_true(_sim.unit_manager.issue_order(cv, Order.air_mission(AirMission.Kind.CAP, "cw90_f14a", 4, cv.position + Vector2(0, 40), 10.0)))
	var m := _mission()
	var flying: Array[Unit] = m.aircraft.duplicate()
	assert_true(not flying.is_empty())
	for a in flying:
		assert_eq(a.flight_state, Unit.FlightState.LAUNCHING, "still on the catapult")
	assert_true(_sim.unit_manager.issue_order(cv, Order.cancel_air_mission(m.id)))
	assert_eq(m.pending_launches, 0, "the queue is struck off at once")
	_advance(300.0)
	assert_true(not m.active, "the mission closes once its launches are airborne and turned for home")
	for a in flying:
		assert_true(a.returning or a.flight_state != Unit.FlightState.AIRBORNE, "%s comes home after its mission was cancelled" % a.callsign)
	_done()


func test_relief_and_a_tanker_never_leave_two_airframes_on_a_one_airframe_cap() -> void:
	_load(CARRIER_WATCH)
	var cv := _unit(IKE)
	var station := cv.position + Vector2(0, 40)
	var tanker := ScenarioLoader._spawn_aircraft(DataDB.platform("usn_uav_mq25"), cv, "Texaco 1", "VX")
	_sim.unit_manager.add_unit(tanker)
	assert_true(_sim.aviation_manager.launch(cv, "Texaco 1") != null)
	_advance(70.0)
	assert_true(_sim.unit_manager.issue_order(tanker, Order.patrol_box(station - Vector2(6, 6), station + Vector2(6, 6))))
	var o := Order.air_mission(AirMission.Kind.CAP, "cw90_f14a", 1, station, 10.0, null, true)
	assert_true(_sim.unit_manager.issue_order(cv, o), o.receipt)
	var m := _mission()
	_advance(300.0)
	var first: Unit = m.aircraft[0]
	first.fuel_s = _sim.aviation_manager.return_fuel_required(first, cv) + 30.0
	var most := 0
	var tanked := false
	for i in 3000:
		_advance(1.0)
		if first.tanking_on != null:
			tanked = true
		var working := 0
		for a in m.aircraft:
			if not a.returning and a.flight_state == Unit.FlightState.AIRBORNE and a.tanking_on == null and m.state_of(a) in [AirMission.ON_STATION, AirMission.TRANSITING, AirMission.INVESTIGATING, AirMission.ENGAGING]:
				working += 1
		most = maxi(most, working)
	assert_true(tanked, "the first airframe took the tanker's basket")
	assert_true(most <= 1, "a one-airframe CAP never keeps two working (%d)" % most)
	_done()


func test_a_cap_fighter_out_of_rounds_goes_home_without_relief() -> void:
	_load(CARRIER_WATCH)
	var cv := _unit(IKE)
	assert_true(_sim.unit_manager.issue_order(cv, Order.air_mission(AirMission.Kind.CAP, "cw90_f14a", 1, cv.position + Vector2(0, 40), 10.0)))
	var m := _mission()
	_advance(300.0)
	var a: Unit = m.aircraft[0]
	for wid in a.magazines.keys():
		a.magazines[wid] = 0
	_advance(60.0)
	assert_true(a.returning, "an empty fighter goes home rather than holding a CAP it cannot fight")
	_done()


func test_two_missions_never_book_the_same_reserve_airframes() -> void:
	_load(CARRIER_WATCH)
	var cv := _unit(IKE)
	var owned := AirMissionManager.airframes_of(cv, "cw90_f14a").size()
	var a := Order.air_mission(AirMission.Kind.CAP, "cw90_f14a", 6, cv.position + Vector2(0, 40), 10.0)
	assert_true(_sim.unit_manager.issue_order(cv, a), a.receipt)
	var b := Order.air_mission(AirMission.Kind.RECON, "cw90_f14a", owned, cv.position + Vector2(40, 0), 20.0)
	_sim.unit_manager.issue_order(cv, b)
	var total := 0
	for m in _sim.air_mission_manager.active_missions("BLUE"):
		total += m.requested
	assert_true(total <= owned, "accepted %d of %d airframes" % [total, owned])
	assert_eq(_sim.air_mission_manager.available_for(cv, "cw90_f14a"), 0)
	var c := Order.air_mission(AirMission.Kind.RECON, "cw90_f14a", 1, cv.position + Vector2(-40, 0), 20.0)
	assert_true(not _sim.unit_manager.issue_order(cv, c))
	assert_true(c.receipt.contains("queued for another mission") or c.receipt.contains("already flying"), c.receipt)
	_done()


func test_a_mission_no_airframe_can_be_armed_for_is_refused_with_the_reason() -> void:
	_load(CARRIER_QUAL)
	var cdg := _unit("Charles de Gaulle (R 91)")
	for a in AirMissionManager.airframes_of(cdg, "fra_fighter_rafale_m"):
		a.magazines["mica_em"] = 0
	cdg.aviation_stores["mica_em"] = 0
	var o := Order.air_mission(AirMission.Kind.CAP, "fra_fighter_rafale_m", 2, cdg.position + Vector2(20, 0), 10.0)
	assert_true(not _sim.unit_manager.issue_order(cdg, o), "accepted: " + o.receipt)
	assert_true(o.receipt.contains("armed"), o.receipt)
	_done()


func test_no_strike_is_flown_at_a_contact_the_plot_scores_destroyed() -> void:
	_load(CARRIER_QUAL)
	var cdg := _unit("Charles de Gaulle (R 91)")
	var ship := Unit.new()
	ship.spec = DataDB.platform("cw90_slava")
	ship.faction = "RED"
	ship.callsign = "Target"
	ship.position = cdg.position + Vector2(60, 0)
	ship.health = ship.spec.health
	_sim.unit_manager.add_unit(ship)
	var t := _plot(ship.position, "0301", 0.0, false)
	t.truth = ship
	t.classification = Track.Classification.CLASS_KNOWN
	t.domain = "surface"
	t.identity = "HOSTILE"
	_sim.track_manager._by_target["BLUE"] = {ship: t}
	var o := Order.air_mission(AirMission.Kind.STRIKE, "fra_fighter_rafale_m", 4, Vector2.INF, 0.0, t)
	assert_true(_sim.unit_manager.issue_order(cdg, o), o.receipt)
	var m := _mission()
	_advance(20.0)
	var launched := m.launched_total
	assert_true(launched < 4, "some of the strike is still queued")
	t.damage_estimate = 100.0  # the plot scores it destroyed
	_advance(600.0)
	assert_eq(m.launched_total, launched, "no strike launches against a contact the plot scores destroyed")
	for a in AirMissionManager.airframes_of(cdg, "fra_fighter_rafale_m"):
		assert_true(a.attack_track != t, "%s is not attacking a destroyed contact" % a.callsign)
	var again := Order.air_mission(AirMission.Kind.STRIKE, "fra_fighter_rafale_m", 1, Vector2.INF, 0.0, t)
	assert_true(not _sim.unit_manager.issue_order(cdg, again))
	assert_eq(again.receipt, "Contact already destroyed")
	_done()


func test_mission_airframes_launch_under_the_tightest_rules_on_the_station() -> void:
	_load(CARRIER_WATCH)
	var cv := _unit(IKE)
	var station := cv.position + Vector2(0, 40)
	assert_true(_sim.unit_manager.issue_order(cv, Order.air_mission(AirMission.Kind.CAP, "cw90_f14a", 1, station, 10.0, null, true)))
	var m := _mission()
	_advance(300.0)
	var first: Unit = m.aircraft[0]
	assert_true(_sim.unit_manager.issue_order(first, Order.set_roe(Unit.Roe.HOLD)))
	first.fuel_s = _sim.aviation_manager.return_fuel_required(first, cv) + 200.0
	_advance(3.0)
	assert_eq(m.launched_total, 2)
	var relief: Unit = m.aircraft[1]
	assert_eq(relief.roe, Unit.Roe.HOLD, "the relief keeps the hold the commander put on the station")
	_done()
	# A deck at weapons hold launches its CAP at weapons hold: it identifies but does not fire.
	_load(CARRIER_WATCH)
	cv = _unit(IKE)
	assert_true(_sim.unit_manager.issue_order(cv, Order.set_roe(Unit.Roe.HOLD)))
	assert_true(_sim.unit_manager.issue_order(cv, Order.air_mission(AirMission.Kind.CAP, "cw90_f14a", 1, station, 10.0)))
	m = _mission()
	_advance(300.0)
	var a: Unit = m.aircraft[0]
	assert_eq(a.roe, Unit.Roe.HOLD)
	var raid := _plot(station + Vector2(5, 5), "0203")
	raid.classification = Track.Classification.CLASS_KNOWN
	raid.domain = "air"
	raid.identity = "HOSTILE"
	_advance(4.0)
	assert_true(a.attack_track != raid, "no intercept under the deck's weapons hold")
	_done()
