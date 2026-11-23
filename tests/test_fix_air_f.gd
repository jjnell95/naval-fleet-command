extends TestCase
## Fighters on a combat air patrol fought by one doctrine on both sides: the shot goes at the full
## no-escape range, a raid that would shoot first is met over what the CAP holds rather than gone
## out to, and a fighter with a missile coming at it breaks.

const BASTION := "res://data/scenarios/aegis_bastion.json"
const CARRIER_WATCH := "res://data/scenarios/cold_war_03_carrier.json"

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
		if t.truth != null:
			t.position = t.truth.position


func _count(part: String) -> int:
	var n := 0
	for r in _reports:
		if r.contains(part):
			n += 1
	return n


func _carrier() -> Unit:
	for u in _sim.unit_manager.units:
		if u.faction == "BLUE" and u.callsign.contains("Eisenhower"):
			return u
	return null


func _plot(faction: String, pos: Vector2, id: String) -> Track:
	var t := Track.new()
	t.id = id
	t.owner_faction = faction
	t.position = pos
	t.altitude_m = 8000.0
	t.domain = "air"
	t.last_seen_time = SimClock.sim_time
	if not _sim.track_manager._tracks.has(faction):
		_sim.track_manager._tracks[faction] = []
	_sim.track_manager._tracks[faction].append(t)
	_held.append(t)
	return t


## A hostile air raid the plot holds by class, coming at `toward` at `speed_kn`.
func _raid(at: Vector2, id: String, platform_id: String, toward: Vector2, speed_kn := 600.0) -> Track:
	var raid := _plot("BLUE", at, id)
	raid.identity = "HOSTILE"
	raid.classification = Track.Classification.CLASS_KNOWN
	if platform_id != "":
		var spec := DataDB.platform(platform_id)
		raid.known_class = spec.short_name
		raid.known_category = spec.category
	raid.has_kinematics = true
	raid.course_deg = Geo.bearing_deg(at, toward)
	raid.speed_kn = speed_kn
	return raid


## One F/A-18E on a 15 nm CAP 70 nm out from the carrier, on station.
func _cap_on_station() -> AirMission:
	var cv := _carrier()
	var o := Order.air_mission(AirMission.Kind.CAP, "usn_fighter_fa18e", 1, cv.position + Vector2(70, -20), 15.0)
	assert_true(_sim.unit_manager.issue_order(cv, o), o.receipt)
	for i in 900:
		SimClock.advance(1.0)
		var ms := _sim.air_mission_manager.active_missions("BLUE")
		if not ms.is_empty() and not ms[0].aircraft.is_empty() and ms[0].tasks[ms[0].aircraft[0]]["state"] == AirMission.ON_STATION:
			break
	var m: AirMission = _sim.air_mission_manager.active_missions("BLUE")[0]
	assert_eq(m.aircraft.size(), 1)
	assert_eq(m.tasks[m.aircraft[0]]["state"], AirMission.ON_STATION, "the Hornet is on station")
	return m


## A Hornet with a Flanker coming straight in shoots as soon as the Flanker is inside its AIM-120's
## no-escape range, not at four fifths of it, the range its attack closes to.
func test_a_cap_fighter_fires_at_its_full_no_escape_range() -> void:
	_load(BASTION)
	var m := _cap_on_station()
	var a: Unit = m.aircraft[0]
	var dir := Vector2(1, 0)
	var raid := _raid(a.position + dir * 80.0, "T1990", "rfn_fighter_su35s", a.position)
	var spec := a.get_weapon("aim120_family")
	var no_escape := 0.0
	var fired_at := -1.0
	for i in 120:
		raid.position = a.position + dir * maxf(80.0 - 1.5 * i, 1.0)
		raid.course_deg = Geo.bearing_deg(raid.position, a.position)
		no_escape = Combat.air_no_escape_range_nm(spec, raid, a.position)
		SimClock.advance(1.0)
		if a.attack_rounds_fired > 0:
			fired_at = a.position.distance_to(raid.position)
			break
	assert_true(fired_at > 0.0, "it fired")
	assert_true(fired_at > UnitManager.ATTACK_STANDOFF_FRACTION * no_escape + 2.0, "at %.1f nm, the no-escape range being %.1f nm" % [fired_at, no_escape])
	assert_true(fired_at <= no_escape + 2.0, "and not from outside it")
	_done()


## A Flanker raid 90 nm out coming at the station would have its R-77 away before the Hornet's
## AIM-120: the Hornet waits for it over the station instead of flying out to meet it. A MiG-31K on
## the same track, which carries no air-to-air missile, is gone out to.
func test_a_cap_waits_over_its_station_for_a_raid_that_would_shoot_first() -> void:
	_load(BASTION)
	var m := _cap_on_station()
	var a: Unit = m.aircraft[0]
	var out := Vector2(0, -1)
	var flanker := _raid(m.station + out * 90.0, "T1991", "rfn_fighter_su35s", m.station)
	assert_true(AirMissionManager.outshoots(a, flanker), "the Flanker's shot outranges the Hornet's")
	assert_true(not AirMissionManager.cap_commits(m, a, flanker, AirMissionManager.COMMIT_HYSTERESIS_NM), "not committed on it")
	assert_true(AirMissionManager.cap_commits(m, a, flanker), "but one already sent at it is kept on it")
	for i in 5:
		SimClock.advance(1.0)
		flanker.position = m.station + out * 90.0
	assert_eq(a.attack_track, null, "the Hornet holds its station")
	assert_eq(_count("intercepting track T1991"), 0, "%s" % [_reports])
	# Once it comes in on the Hornet, it is answered.
	flanker.position = a.position + out * 55.0
	flanker.course_deg = Geo.bearing_deg(flanker.position, a.position)
	SimClock.advance(2.0)
	assert_eq(a.attack_track, flanker, "a Flanker coming in on it inside its reach is met")
	_done()


func test_a_cap_goes_out_to_a_raid_that_cannot_outshoot_it() -> void:
	_load(BASTION)
	var m := _cap_on_station()
	var a: Unit = m.aircraft[0]
	var out := Vector2(0, -1)
	var foxhound := _raid(m.station + out * 90.0, "T1992", "rfn_strike_mig31k", m.station, 500.0)
	assert_true(not AirMissionManager.outshoots(a, foxhound), "a MiG-31K carries no air-to-air missile")
	for i in 5:
		SimClock.advance(1.0)
		foxhound.position = m.station + out * 90.0
	assert_eq(a.attack_track, foxhound, "the Hornet goes out for it")
	_done()


## A Flanker fires an R-77 at the Hornet from 25 nm. The Hornet sees it coming and breaks, as a
## fighter of the other side does, before the round arrives.
func test_a_cap_fighter_breaks_from_a_missile_it_sees_coming() -> void:
	_load(BASTION)
	var m := _cap_on_station()
	var a: Unit = m.aircraft[0]
	var shooter: Unit = null
	for u in _sim.unit_manager.units:
		if u.faction == "RED" and u.alive and u.spec.id == "rfn_fighter_su35s":
			shooter = u
			break
	assert_true(shooter != null, "a Flanker in the scenario")
	shooter.flight_state = Unit.FlightState.AIRBORNE
	shooter.altitude_m = 8000.0
	shooter.position = a.position + Vector2(25, 0)
	shooter.heading_deg = Geo.bearing_deg(shooter.position, a.position)
	shooter.speed_kn = 500.0
	var hornet := _plot("RED", a.position, "T2001")
	hornet.truth = a
	hornet.identity = "HOSTILE"
	hornet.has_kinematics = true
	hornet.course_deg = a.heading_deg
	hornet.speed_kn = a.speed_kn
	var r77 := shooter.get_weapon("r77_family")
	var launched := _sim.weapon_manager.launch(shooter, r77, hornet, 1, SimClock.sim_time)
	assert_true(launched, "the R-77 is away")
	var broke := false
	for i in 90:
		SimClock.advance(1.0)
		if a.evasion_remaining_s > 0.0:
			broke = true
			break
		if not a.alive:
			break
		var flying := false
		for w: Weapon in _sim.weapon_manager.in_flight:
			if w.shooter == shooter and w.phase != Weapon.Phase.DEAD:
				flying = true
		if not flying:
			break
	assert_true(broke, "the Hornet broke while the round was coming: %s" % [_reports])
	assert_true(_count("breaking: missile inbound") >= 1, "and said so: %s" % [_reports])
	_done()


# --- Sent and recalled once, not by turns ------------------------------------------------------

const IKE := "USS Dwight D. Eisenhower (CVN 69)"


## One Tomcat on a 12 nm CAP with a 25 nm pursuit over the Carrier Watch carrier, on station.
func _tomcat_cap() -> AirMission:
	var cv: Unit = null
	for u in _sim.unit_manager.units:
		if u.callsign == IKE:
			cv = u
	var o := Order.air_mission(AirMission.Kind.CAP, "cw90_f14a", 1, cv.position + Vector2(-40, -40), 12.0)
	o.pursuit_nm = 25.0
	assert_true(_sim.unit_manager.issue_order(cv, o), o.receipt)
	SimClock.advance(600.0)
	var m: AirMission = _sim.air_mission_manager.active_missions("BLUE")[0]
	assert_eq(m.aircraft.size(), 1)
	return m


func _unknown(at: Vector2, id: String) -> Track:
	var t := _plot("BLUE", at, id)
	t.identity = "UNKNOWN"
	t.classification = Track.Classification.UNKNOWN
	return t


## An unknown aircraft just inside the ring and pursuit is not sent a look that the boundary would
## call off at the next swing of the plot; one well inside is, and is not called off while it stays
## inside the boundary.
func test_a_cap_look_is_sent_inside_its_boundary_by_a_margin() -> void:
	_load(CARRIER_WATCH)
	var m := _tomcat_cap()
	var a: Unit = m.aircraft[0]
	var limit := m.radius_nm + m.pursuit_nm
	var out := Vector2(1, 0)
	var edge := _unknown(m.station + out * (limit - 2.0), "T1980")
	for i in 3:
		SimClock.advance(1.0)
	assert_eq(_count("identifying track T1980"), 0, "no look at a contact at the edge: %s" % [_reports])
	edge.position = m.station + out * (limit - 8.0)
	SimClock.advance(2.0)
	assert_eq(_count("identifying track T1980"), 1, "a look once it is well inside: %s" % [_reports])
	# The contact drifts back out toward the edge, still inside the boundary.
	edge.position = m.station + out * (limit - 1.0)
	for i in 5:
		SimClock.advance(1.0)
	assert_eq(_count("returning: contact outside CAP pursuit boundary"), 0, "not recalled inside it: %s" % [_reports])
	_done()


## A Tomcat called back from a raid at its leash is not sent straight out after another one while it
## is still on its way back; a hostile that comes in on it is still answered.
func test_a_recalled_cap_fighter_is_not_sent_out_again_before_it_is_back() -> void:
	_load(CARRIER_WATCH)
	var m := _tomcat_cap()
	var a: Unit = m.aircraft[0]
	var leash := AirMissionManager.cap_commit_nm(m, a)
	var out := Vector2(0, 1)
	var raid := _raid(m.station + out * 40.0, "T1981", "", m.station, 0.0)
	raid.has_kinematics = false
	raid.known_class = ""
	SimClock.advance(3.0)
	assert_eq(a.attack_track, raid)
	_reports.clear()
	a.position = m.station + out * (leash + 10.0)
	a.attack_rounds_fired = 0
	raid.position = a.position + out * 45.0
	_moving(raid, Geo.bearing_deg(a.position, raid.position), 600.0)
	for i in 3:
		SimClock.advance(1.0)
		raid.position = a.position + out * 45.0
	assert_eq(_count("returning: contact outside CAP pursuit boundary"), 1, "recalled: %s" % [_reports])
	# A second raid sitting 30 nm off the station, which it would otherwise go for.
	var other := _raid(m.station + Vector2(30, 0), "T1982", "", m.station, 0.0)
	other.has_kinematics = false
	other.known_class = ""
	assert_true(AirMissionManager.cap_commits(m, a, other, AirMissionManager.COMMIT_HYSTERESIS_NM), "a raid it would be sent at")
	for i in 8:
		SimClock.advance(1.0)
		raid.position = a.position + out * 45.0
	assert_true(a.position.distance_to(m.station) > m.radius_nm + AirMissionManager.STATION_ARRIVAL_MARGIN_NM, "still on its way back")
	assert_eq(_count("intercepting track T1982"), 0, "not sent out again on the way back: %s" % [_reports])
	# One coming in on it is answered all the same.
	var flanker := _raid(a.position + Vector2(-35, 0), "T1983", "", a.position, 550.0)
	flanker.known_class = ""
	SimClock.advance(2.0)
	assert_eq(a.attack_track, flanker, "a hostile coming in on it is met: %s" % [_reports])
	_done()


## A position worked up from bearings alone is no fix on an aircraft: a CAP is not sent on it, even
## coming in, while the same contact on radar is answered.
func test_a_cap_is_not_sent_on_a_bearings_only_air_position() -> void:
	_load(CARRIER_WATCH)
	var m := _tomcat_cap()
	var a: Unit = m.aircraft[0]
	var raid := _raid(a.position + Vector2(40, 0), "T1984", "", a.position, 550.0)
	raid.known_class = ""
	raid.bearing_only = true
	assert_true(not AirMissionManager.cap_commits(m, a, raid, AirMissionManager.COMMIT_HYSTERESIS_NM), "not sent on a bearings-only position")
	raid.bearing_only = false
	assert_true(AirMissionManager.cap_commits(m, a, raid, AirMissionManager.COMMIT_HYSTERESIS_NM), "sent on a radar fix")
	_done()


func _moving(t: Track, course_deg: float, speed_kn: float) -> Track:
	t.has_kinematics = true
	t.course_deg = fposmod(course_deg, 360.0)
	t.speed_kn = speed_kn
	return t
