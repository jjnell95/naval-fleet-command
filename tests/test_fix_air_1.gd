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
