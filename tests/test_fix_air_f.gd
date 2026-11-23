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
