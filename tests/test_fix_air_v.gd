extends TestCase
## Air missions flown on the shipped Carrier Watch operation with its real air wing: fighters that
## answer what shoots at them and stay on their leash, reconnaissance that stays out of a ship's
## missile cover once it knows the ship, honest deck receipts and sections flown as two aircraft.

const CARRIER_WATCH := "res://data/scenarios/cold_war_03_carrier.json"
const IKE := "USS Dwight D. Eisenhower (CVN 69)"

var _sim: Simulation
var _held: Array[Track] = []
var _reports: Array[String] = []


func _load(path: String, ai := false) -> Simulation:
	SimClock.set_paused(true)
	_sim = Simulation.new()
	_sim.seed_override = 7
	(Engine.get_main_loop() as SceneTree).root.add_child(_sim)
	assert_true(_sim.load_scenario(path), path)
	_sim.ai_enabled = ai
	_held.clear()
	_reports.clear()
	if not SimClock.tick.is_connected(_keep_held):
		SimClock.tick.connect(_keep_held)
	_sim.air_mission_manager.mission_report.connect(_on_report)
	return _sim


func _done() -> void:
	if SimClock.tick.is_connected(_keep_held):
		SimClock.tick.disconnect(_keep_held)
	_sim.unit_manager.clear()
	_sim.queue_free()
	_sim.free()
	_sim = null


func _on_report(_m: AirMission, message: String, _good: bool) -> void:
	_reports.append(message)


func _keep_held(_dt: float) -> void:
	for t in _held:
		t.last_seen_time = SimClock.sim_time
		t.status = Track.Status.ACTIVE


func _unit(callsign: String) -> Unit:
	for u in _sim.unit_manager.units:
		if u.callsign == callsign:
			return u
	return null


func _advance(seconds: float) -> void:
	SimClock.advance(seconds)


func _plot(pos: Vector2, id: String, altitude := 6000.0) -> Track:
	var t := Track.new()
	t.id = id
	t.owner_faction = "BLUE"
	t.position = pos
	t.altitude_m = altitude
	t.last_seen_time = SimClock.sim_time
	if not _sim.track_manager._tracks.has("BLUE"):
		_sim.track_manager._tracks["BLUE"] = []
	_sim.track_manager._tracks["BLUE"].append(t)
	_held.append(t)
	return t


func _raid(at: Vector2, id: String) -> Track:
	var raid := _plot(at, id, 8000.0)
	raid.domain = "air"
	raid.identity = "HOSTILE"
	raid.classification = Track.Classification.CLASS_KNOWN
	return raid


func _moving(t: Track, course_deg: float, speed_kn: float) -> Track:
	t.has_kinematics = true
	t.course_deg = fposmod(course_deg, 360.0)
	t.speed_kn = speed_kn
	return t


func _ship_contact(at: Vector2, id: String, identity: String) -> Track:
	var t := _plot(at, id, 0.0)
	t.domain = "surface"
	t.identity = identity
	t.classification = Track.Classification.SURFACE
	return t


## One Tomcat on a 12 nm CAP with a 25 nm pursuit, on station.
func _cap_on_station(station_offset: Vector2, count := 1) -> AirMission:
	var cv := _unit(IKE)
	var o := Order.air_mission(AirMission.Kind.CAP, "cw90_f14a", count, cv.position + station_offset, 12.0)
	o.pursuit_nm = 25.0
	assert_true(_sim.unit_manager.issue_order(cv, o), o.receipt)
	_advance(600.0)
	var m: AirMission = _sim.air_mission_manager.active_missions("BLUE")[0]
	assert_eq(m.aircraft.size(), count)
	return m


func _count(prefix: String) -> int:
	var n := 0
	for r in _reports:
		if r.contains(prefix):
			n += 1
	return n


# --- A CAP answers what shoots at it --------------------------------------------------------

## A Tomcat flying out after a raid it has not yet reached is come at by a second hostile from 40 nm,
## inside its own missiles' reach: it turns on that one instead of flying on into its missiles.
func test_a_cap_fighter_turns_on_a_hostile_coming_in_on_it() -> void:
	_load(CARRIER_WATCH)
	var m := _cap_on_station(Vector2(-40, -40))
	var a: Unit = m.aircraft[0]
	var raid := _raid(m.station + Vector2(0, 55), "T1990")
	_advance(3.0)
	assert_eq(a.attack_track, raid, "the CAP goes for the raid")
	var flanker := _raid(a.position + Vector2(40, 0), "T1991")
	_moving(flanker, Geo.bearing_deg(flanker.position, a.position), 550.0)
	_advance(3.0)
	assert_eq(a.attack_track, flanker, "it answers the fighter coming in on it")
	assert_true(_count("turning on track T1991") >= 1, "and says so: %s" % [_reports])
	_done()


## The same Tomcat leaves a hostile that is inside its reach but flying away from it alone: only one
## coming in on it takes it off the raid it was sent at.
func test_a_cap_fighter_keeps_its_raid_when_the_other_hostile_is_not_coming_in() -> void:
	_load(CARRIER_WATCH)
	var m := _cap_on_station(Vector2(-40, -40))
	var a: Unit = m.aircraft[0]
	var raid := _raid(m.station + Vector2(0, 55), "T1992")
	_advance(3.0)
	assert_eq(a.attack_track, raid)
	var other := _raid(a.position + Vector2(40, 0), "T1993")
	_moving(other, Geo.bearing_deg(a.position, other.position), 450.0)
	_advance(3.0)
	assert_eq(a.attack_track, raid, "a hostile running away does not pull it off its raid")
	_done()


# --- One leash for commit and recall --------------------------------------------------------

## A raid running away from the station at 500 kn, 60 nm out: the Tomcat could not get a shot
## before it would be beyond its leash, so it is not sent.
func test_a_cap_is_not_sent_after_a_raid_it_cannot_catch_inside_its_leash() -> void:
	_load(CARRIER_WATCH)
	var m := _cap_on_station(Vector2(-40, -40))
	var a: Unit = m.aircraft[0]
	var raid := _raid(m.station + Vector2(0, 60), "T1994")
	_moving(raid, Geo.bearing_deg(m.station, raid.position), 500.0)
	assert_true(not AirMissionManager.cap_commits(m, a, raid), "no commit on a raid it would chase beyond the leash")
	_advance(5.0)
	assert_eq(a.attack_track, null)
	_done()


## A Tomcat beyond its leash chasing a raid that stays ahead of it is called back once, and is not
## sent out again the next second: commit and recall are the same test.
func test_a_cap_recalled_at_its_leash_is_not_sent_straight_back_out() -> void:
	_load(CARRIER_WATCH)
	var m := _cap_on_station(Vector2(-40, -40))
	var a: Unit = m.aircraft[0]
	var leash := AirMissionManager.cap_commit_nm(m, a)
	var out := Vector2(0, 1)
	var raid := _raid(m.station + out * 55.0, "T1995")
	_advance(3.0)
	assert_eq(a.attack_track, raid)
	_reports.clear()
	# The fight has drawn it out past the leash, its first pair long since gone, and the raid is
	# 45 nm ahead, running away.
	a.position = m.station + out * (leash + 10.0)
	a.attack_rounds_fired = 0
	raid.position = a.position + out * 45.0
	_moving(raid, Geo.bearing_deg(a.position, raid.position), 600.0)
	for i in 60:
		_advance(1.0)
		raid.position = a.position + out * 45.0
	assert_eq(_count("returning: contact outside CAP pursuit boundary"), 1, "recalled once: %s" % [_reports])
	assert_eq(_count("intercepting track T1995"), 0, "and not recommitted: %s" % [_reports])
	assert_true(a.attack_track == null, "flying back to its station")
	_done()


## A raid over a hostile ship 50 nm from the station: the Tomcat would have to fly into the ship's
## missile cover to take its shot, so it stays out; one that comes in on it is still answered.
func test_a_cap_does_not_follow_a_raid_into_a_hostile_ships_missile_cover() -> void:
	_load(CARRIER_WATCH)
	var m := _cap_on_station(Vector2(-40, -40))
	var a: Unit = m.aircraft[0]
	var ship := _ship_contact(m.station + Vector2(0, 55), "T1996", "HOSTILE")
	ship.classification = Track.Classification.CLASS_KNOWN
	ship.known_class = "CG Slava"
	ship.known_category = "cruiser"
	assert_true(AirMissionManager.air_defence_standoff_nm(ship) >= 45.0, "the plot knows the class's missile reach")
	var raid := _raid(ship.position + Vector2(3, 0), "T1997")
	assert_true(AirMissionManager.cap_commits(m, a, raid), "inside the leash")
	_advance(5.0)
	assert_eq(a.attack_track, null, "not sent over the cruiser")
	_moving(raid, Geo.bearing_deg(raid.position, a.position), 550.0)
	raid.position = a.position + (raid.position - a.position).normalized() * 50.0
	_advance(3.0)
	assert_eq(a.attack_track, raid, "one coming in on it is answered")
	_done()


# --- Reconnaissance leaves a ship it has identified ------------------------------------------

## A quick look at an unknown ship is flown by an armed jet. Once the plot calls the ship a hostile
## Slava the jet's circuit moves out beyond the cruiser's missiles, instead of circling over it.
func test_a_quick_look_moves_off_the_ship_once_it_is_identified() -> void:
	_load(CARRIER_WATCH)
	var cv := _unit(IKE)
	var ship := _ship_contact(cv.position + Vector2(0, 70), "T1998", "UNKNOWN")
	var o := _sim.air_mission_manager.quick_order(cv, AirMission.Kind.RECON, ship.position, ship)
	assert_true(o != null)
	assert_true(_sim.unit_manager.issue_order(cv, o), o.receipt)
	var m: AirMission = _sim.air_mission_manager.active_missions("BLUE")[0]
	_advance(120.0)
	assert_true(not m.aircraft.is_empty())
	var jet: Unit = m.aircraft[0]
	ship.classification = Track.Classification.CLASS_KNOWN
	ship.known_class = "CG Slava"
	ship.known_category = "cruiser"
	ship.identity = "HOSTILE"
	var cover := AirMissionManager.air_defence_standoff_nm(ship) - AirMissionManager.AIR_DEFENCE_MARGIN_NM
	var nearest := INF
	for i in 2400:
		_advance(1.0)
		if not jet.alive or not jet.in_flight():
			break
		if i > 900:
			nearest = minf(nearest, jet.position.distance_to(ship.position))
	assert_true(jet.alive, "the jet survives")
	assert_true(nearest > cover, "it keeps outside the %.0f nm cover: nearest %.1f nm" % [cover, nearest])
	_done()


# --- Deck receipts name what the aircraft launches from ---------------------------------------

## With every catapult taken by a Tomcat section, a Sea King queued for an ASW search waits for a
## spot on the flight deck: the receipt says so instead of naming the catapults it never uses.
func test_a_helicopter_queued_on_a_carrier_waits_for_the_flight_deck_not_the_catapults() -> void:
	_load(CARRIER_WATCH)
	var cv := _unit(IKE)
	var jets := _sim.aviation_manager.launch_flight(cv, cv.spec.launch_capacity(), "cw90_f14a")
	assert_eq(jets.size(), cv.spec.launch_capacity(), "every spot taken")
	var why := _sim.aviation_manager.launch_rejection_reason(cv, "cw90_sh3h")
	assert_eq(why, "FLIGHT DECK COMMITTED")
	var jet_type := ""
	for a in cv.stowed_aircraft():
		if not a.spec.can_hover:
			jet_type = a.spec.id
	assert_true(jet_type != "", "a jet still on deck")
	assert_eq(_sim.aviation_manager.launch_rejection_reason(cv, jet_type), "CATAPULTS COMMITTED", "a jet still waits for the catapults")
	var o := Order.air_mission(AirMission.Kind.ASW, "cw90_sh3h", 1, cv.position + Vector2(0, 20), 10.0)
	assert_true(_sim.unit_manager.issue_order(cv, o), o.receipt)
	assert_true(o.receipt.contains("queued: flight deck committed"), o.receipt)
	assert_true(not o.receipt.contains("catapult"), o.receipt)
	_done()


# --- A section is two aircraft on the chart ---------------------------------------------------

## Two Tomcats holding one CAP fly their own circuits a couple of miles apart, instead of closing
## up on each other after the launch interval and showing as one symbol all sortie.
func test_a_section_on_station_keeps_apart() -> void:
	_load(CARRIER_WATCH)
	var m := _cap_on_station(Vector2(-40, -40), 2)
	var lead: Unit = m.aircraft[0]
	var wing: Unit = m.aircraft[1]
	var close := 0
	var samples := 0
	var nearest := INF
	for i in 80:
		_advance(30.0)
		if not (lead.alive and wing.alive) or lead.returning or wing.returning:
			break
		var d := lead.position.distance_to(wing.position)
		nearest = minf(nearest, d)
		samples += 1
		if d < 1.0:
			close += 1
	assert_true(samples >= 40, "%d samples on station" % samples)
	assert_true(close <= samples / 20, "%d of %d samples under 1 nm apart, nearest %.2f nm" % [close, samples, nearest])
	assert_true(nearest >= 0.8, "nearest %.2f nm" % nearest)
	_done()


## A Tomcat already fighting a hostile that is coming in on it does not hop to a second one a few
## miles nearer, and turns only for one a good deal nearer.
func test_a_cap_fighter_in_a_fight_does_not_hop_between_threats() -> void:
	_load(CARRIER_WATCH)
	var m := _cap_on_station(Vector2(-40, -40))
	var a: Unit = m.aircraft[0]
	var first := _raid(a.position + Vector2(0, 58), "T1999")
	_moving(first, Geo.bearing_deg(first.position, a.position), 500.0)
	_advance(2.0)
	assert_eq(a.attack_track, first, "it takes the one coming in on it")
	var second := _raid(a.position + (first.position - a.position).rotated(PI / 2.0).normalized() * (a.position.distance_to(first.position) - 3.0), "T2000")
	_moving(second, Geo.bearing_deg(second.position, a.position), 500.0)
	_advance(2.0)
	assert_eq(a.attack_track, first, "a second only a little nearer does not take it off the first")
	second.position = a.position + (second.position - a.position).normalized() * (a.position.distance_to(first.position) - 20.0)
	second.course_deg = Geo.bearing_deg(second.position, a.position)
	_advance(2.0)
	assert_eq(a.attack_track, second, "one much nearer does")
	_done()
