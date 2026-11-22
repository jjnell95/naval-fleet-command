extends TestCase
## Aircraft doing their job once airborne, flown on the shipped Carrier Watch operation with its
## real air wing and, where the job is about the raid, its real opposition.

const CARRIER_WATCH := "res://data/scenarios/cold_war_03_carrier.json"
const CARRIER_QUAL := "res://data/scenarios/carrier_qualification.json"
const IKE := "USS Dwight D. Eisenhower (CVN 69)"

var _sim: Simulation
var _held: Array[Track] = []


func _load(path: String, ai := false) -> Simulation:
	SimClock.set_paused(true)
	_sim = Simulation.new()
	_sim.seed_override = 7
	(Engine.get_main_loop() as SceneTree).root.add_child(_sim)
	assert_true(_sim.load_scenario(path), path)
	_sim.ai_enabled = ai
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


func _advance(seconds: float) -> void:
	SimClock.advance(seconds)


# --- Intercept with fighters -------------------------------------------------------------

## The contact menu's "Intercept with fighters" on the first Backfire the Hawkeye calls hostile:
## the Tomcats go for that raid and shoot before it can release its missile, then come home.
func test_a_quick_intercept_shoots_the_raid_before_it_releases() -> void:
	_load(CARRIER_WATCH, true)
	var cv := _unit(IKE)
	var air := _sim.air_mission_manager
	assert_true(_sim.unit_manager.issue_order(cv, Order.air_mission(AirMission.Kind.RECON, "cw90_e2c", 1, cv.position + Vector2(30, 35), 25.0, null, true, true)))
	var fired := {}
	var on_fire := func(shooter: Unit, spec: WeaponSpec, _t: Track, _rounds: int) -> void:
		if not fired.has(spec.id):
			fired[spec.id] = SimClock.sim_time
		if shooter.faction == "BLUE" and shooter.is_aircraft() and not fired.has("blue_air"):
			fired["blue_air"] = SimClock.sim_time
	_sim.weapon_manager.weapon_launched.connect(on_fire)
	var intercept: AirMission = null
	for second in 1800:
		_advance(1.0)
		if intercept == null and second > 30:
			for t: Track in _sim.track_manager.get_tracks("BLUE"):
				if t.status == Track.Status.ACTIVE and t.identity == "HOSTILE" and t.domain == "air":
					var items := CdsMenus.air_contact_items(air, "BLUE", t)
					assert_true(not (items.is_empty()))
					var action: Dictionary = items[0]["action"]
					assert_eq(action.get("kind"), "quick_air_now")
					var order: Order = action["order"]
					assert_true(not (order.relief), "an intercept is not relieved")
					assert_true(_sim.unit_manager.issue_order(action["base"], order), order.receipt)
					for m in air.active_missions("BLUE"):
						if m.intercept:
							intercept = m
					break
		if fired.has("blue_air") and fired.has("cw90_kh22"):
			break
	assert_true(intercept != null, "an intercept was flown")
	assert_true(fired.has("blue_air"), "the fighters fired")
	assert_true(not fired.has("cw90_kh22") or float(fired["blue_air"]) < float(fired["cw90_kh22"]), "the fighters fired (%s) before the raid released (%s)" % [fired.get("blue_air"), fired.get("cw90_kh22")])
	# Then they come home: no station is held over the sky the raid has left.
	_advance(1200.0)
	if intercept.active:
		for a in intercept.aircraft:
			assert_true(not a.alive or a.returning or not a.airborne(), "%s comes home after the intercept: %s" % [a.callsign, intercept.state_of(a)])
	assert_eq(intercept.launched_total, 2, "no relief launched for an intercept")
	_sim.weapon_manager.weapon_launched.disconnect(on_fire)
	_done()


func test_an_intercept_keeps_its_contact_wherever_it_flies() -> void:
	_load(CARRIER_WATCH)
	var cv := _unit(IKE)
	var raid := _plot(cv.position + Vector2(0, 120), "T1950", 8000.0)
	raid.domain = "air"
	raid.identity = "HOSTILE"
	raid.classification = Track.Classification.CLASS_KNOWN
	var air := _sim.air_mission_manager
	var o := air.quick_order(cv, AirMission.Kind.CAP, raid.position, raid)
	assert_true(o != null)
	assert_true(_sim.unit_manager.issue_order(cv, o), o.receipt)
	var m: AirMission = air.active_missions("BLUE")[0]
	assert_true(m.intercept)
	assert_eq(m.target, raid)
	_advance(120.0)
	# The raid runs off sideways, 60 nm from where it was ordered: the fighters still go for it.
	raid.position = cv.position + Vector2(60, 120)
	_advance(30.0)
	for a in m.aircraft:
		assert_eq(a.attack_track, raid, "%s keeps the raid" % a.callsign)
		assert_true(not (a.returning))
		assert_near(a.ordered_speed_kn, a.spec.flight_speed("dash"), 1.0, "at dash")
	assert_true(m.station.distance_to(raid.position) < 1.0, "the mission follows the raid")
	assert_true(air.revision_rejection(cv, Order.revise_air_mission(m, cv.position, 12.0, 2, true, true)) != "", "an intercept cannot be turned into a station")
	_done()


# --- When a CAP commits ------------------------------------------------------------------

func _cap_on_station(station_offset: Vector2) -> AirMission:
	var cv := _unit(IKE)
	var o := Order.air_mission(AirMission.Kind.CAP, "cw90_f14a", 1, cv.position + station_offset, 12.0)
	assert_true(_sim.unit_manager.issue_order(cv, o), o.receipt)
	_advance(600.0)
	var m: AirMission = _sim.air_mission_manager.active_missions("BLUE")[0]
	assert_eq(m.aircraft.size(), 1)
	return m


func _raid(at: Vector2, id: String) -> Track:
	var raid := _plot(at, id, 8000.0)
	raid.domain = "air"
	raid.identity = "HOSTILE"
	raid.classification = Track.Classification.CLASS_KNOWN
	return raid


## On the order's own defaults (12 nm ring, 25 nm pursuit) a raid 50 nm out is outside the ring
## and the pursuit, but well inside the Tomcat's own missile reach: it goes after it.
func test_a_cap_commits_on_a_raid_inside_its_own_missile_reach() -> void:
	_load(CARRIER_WATCH)
	var m := _cap_on_station(Vector2(0, 40))
	var a: Unit = m.aircraft[0]
	var raid := _raid(m.station + Vector2(0, 50), "T1960")
	_advance(5.0)
	assert_eq(a.attack_track, raid, "the CAP commits on a raid it can shoot")
	_done()


## A raid 90 nm out, beyond the ring, the pursuit and a missile shot from the station, is met when
## it is closing on the carrier the CAP covers, and left alone when it is heading away.
func test_a_cap_meets_a_raid_closing_on_what_it_covers() -> void:
	_load(CARRIER_WATCH)
	var cv := _unit(IKE)
	var m := _cap_on_station(Vector2(0, 40))
	var a: Unit = m.aircraft[0]
	var raid := _raid(m.station + Vector2(0, 90), "T1961")
	raid.has_kinematics = true
	raid.speed_kn = 500.0
	raid.course_deg = Geo.bearing_deg(raid.position, cv.position) + 180.0
	_advance(5.0)
	assert_eq(a.attack_track, null, "a raid heading away is not chased")
	raid.course_deg = Geo.bearing_deg(raid.position, cv.position)
	_advance(5.0)
	assert_eq(a.attack_track, raid, "a raid closing on the carrier is met")
	_done()


func test_quick_and_dialog_caps_pursue_at_least_sixty_miles() -> void:
	_load(CARRIER_WATCH)
	var cv := _unit(IKE)
	var o := _sim.air_mission_manager.quick_order(cv, AirMission.Kind.CAP, cv.position + Vector2(0, 30))
	assert_true(o.pursuit_nm >= 60.0, "quick CAP pursuit %.0f" % o.pursuit_nm)
	assert_true(AirMissionManager.COMMIT_MARGIN_NM >= 60.0)
	assert_true(AirMission.new().pursuit_nm >= 60.0)
	_done()


# --- Recovery order ----------------------------------------------------------------------

## Two Tomcats and a Sea King back at the carrier together: the Tomcat with less fuel is called
## down first though the other is nearer, and the Sea King does not wait behind the jets.
func test_the_deck_takes_the_thirstiest_first_and_helicopters_have_their_own_spot() -> void:
	_load(CARRIER_WATCH)
	var cv := _unit(IKE)
	var av := _sim.aviation_manager
	var flight := av.launch_flight(cv, 2, "cw90_f14a")
	var helo: Unit = null
	for a in cv.stowed_aircraft():
		if a.spec.id == "cw90_sh3h":
			helo = av.launch(cv, a.callsign)
			break
	assert_eq(flight.size(), 2)
	assert_true(helo != null)
	_advance(200.0)
	var full: Unit = flight[0]
	var thirsty: Unit = flight[1]
	var astern := -Geo.heading_to_vector(cv.heading_deg)
	full.position = cv.position + astern * 3.0
	thirsty.position = cv.position + astern * 6.0
	helo.position = cv.position + astern * 4.0
	full.fuel_s = full.spec.endurance_s * 0.6
	thirsty.fuel_s = thirsty.spec.endurance_s * 0.3
	helo.fuel_s = helo.spec.endurance_s * 0.3
	for a in [full, thirsty, helo]:
		a.altitude_m = 300.0
		assert_true(_sim.unit_manager.issue_order(a, Order.return_to_base()))
	var first_jet: Unit = null
	var helo_down_at := -1.0
	var jets_down_at := -1.0
	for i in 1800:
		_advance(1.0)
		for jet in [full, thirsty]:
			if first_jet == null and jet.flight_state == Unit.FlightState.RECOVERING:
				first_jet = jet
		if helo_down_at < 0.0 and helo.flight_state == Unit.FlightState.TURNAROUND:
			helo_down_at = SimClock.sim_time
		if jets_down_at < 0.0 and full.flight_state == Unit.FlightState.TURNAROUND and thirsty.flight_state == Unit.FlightState.TURNAROUND:
			jets_down_at = SimClock.sim_time
		if helo_down_at > 0.0 and jets_down_at > 0.0:
			break
	assert_eq(first_jet, thirsty, "the Tomcat on 30% is called down before the one on 60%")
	assert_true(helo_down_at > 0.0 and jets_down_at > 0.0, "all three aboard")
	assert_true(helo_down_at < jets_down_at, "the Sea King is aboard before the second Tomcat")
	_done()


## Carrier Watch with everything the deck has in the air, then "Recall all aircraft": every one of
## the twenty-eight comes aboard and none runs dry in the stack.
func test_a_full_recall_loses_nothing_to_fuel() -> void:
	_load(CARRIER_WATCH, true)
	var cv := _unit(IKE)
	var lost: Array[String] = []
	var on_lost := func(a: Unit, reason: String) -> void:
		if a.faction == "BLUE":
			lost.append("%s %s" % [a.callsign, reason])
	_sim.aviation_manager.aircraft_lost.connect(on_lost)
	var um := _sim.unit_manager
	_advance(1.0)
	assert_true(um.issue_order(cv, Order.air_mission(AirMission.Kind.CAP, "cw90_f14a", 4, cv.position + Vector2(40, 45), 12.0, null, false, true)))
	assert_true(um.issue_order(cv, Order.air_mission(AirMission.Kind.ASW, "cw90_s3a", 4, cv.position + Vector2(-15, 12), 10.0, null, false, true)))
	assert_true(um.issue_order(cv, Order.air_mission(AirMission.Kind.ASW, "cw90_sh3h", 4, cv.position + Vector2(8, -8), 6.0, null, false, true)))
	assert_true(um.issue_order(cv, Order.air_mission(AirMission.Kind.RECON, "cw90_e2c", 1, cv.position + Vector2(30, 35), 25.0, null, false, true)))
	_advance(1999.0)
	assert_true(um.issue_order(cv, Order.air_mission(AirMission.Kind.CAP, "cw90_f14a", 8, cv.position + Vector2(-40, 45), 12.0, null, false, true)))
	assert_true(um.issue_order(cv, Order.air_mission(AirMission.Kind.RECON, "cw90_e2c", 3, cv.position + Vector2(-30, 35), 25.0, null, false, true)))
	_advance(600.0)
	assert_true(um.issue_order(cv, Order.air_mission(AirMission.Kind.RECON, "cw90_a6e", 4, cv.position + Vector2(0, -50), 25.0, null, false, true)))
	_advance(3700.0)
	var told := _sim.air_mission_manager.recall_all(cv)
	assert_true(told >= 24, "most of the air wing is up: %d" % told)
	_advance(5000.0)
	assert_eq(lost, [] as Array[String], "nothing lost: %s" % [lost])
	var flying := cv.embarked.filter(func(a: Unit) -> bool: return a.alive and a.in_flight()).size()
	assert_eq(flying, 0, "every airframe is aboard")
	_sim.aviation_manager.aircraft_lost.disconnect(on_lost)
	_done()
