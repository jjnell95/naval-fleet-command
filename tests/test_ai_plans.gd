extends TestCase
## Opposing-force mission plans (AIPlan). The claim under test: a formation with a plan pursues its
## objective instead of shooting at whatever is nearest, it coordinates (scouts first, a shared
## round budget, separate attack axes), and it still knows nothing but its own picture. Most
## contacts here are plotted with no `truth` at all, so any read of it would fail the test.

const DT := 0.25
const FIXTURE := "res://tests/fixtures/ai_plan_carrier.json"


func _platform(hp := 100.0) -> PlatformSpec:
	var p := PlatformSpec.new()
	p.short_name = "DDG Test"
	p.max_speed_kn = 28.0
	p.cruise_speed_kn = 14.0
	p.health = hp
	p.fire_control_channels = 4
	return p


func _radar() -> SensorSpec:
	var s := SensorSpec.new()
	s.kind = "radar"
	s.range_surface_nm = 40.0
	s.range_air_nm = 200.0
	s.antenna_height_m = 20.0
	return s


func _asm(max_range := 60.0) -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = "test_asm"
	w.display_name = "Test ASM"
	w.type = "asm"
	w.max_range_nm = max_range
	w.min_range_nm = 2.0
	w.speed_kn = 480.0
	w.seeker_range_nm = 8.0
	w.damage = 40.0
	w.base_pk = 0.8
	return w


func _ship(callsign: String, pos: Vector2, weapon: WeaponSpec = null, rounds := 8) -> Unit:
	var u := Unit.new()
	u.spec = _platform()
	u.faction = "RED"
	u.callsign = callsign
	u.position = pos
	u.health = 100.0
	u.sensors.append(_radar())
	if weapon != null:
		u.weapons.append(weapon)
		u.magazines[weapon.id] = rounds
	return u


class Harness:
	extends RefCounted
	var um: UnitManager
	var tm: TrackManager
	var threats: ThreatManager
	var wm: WeaponManager
	var ai: AIController
	var orders: Array = []

	func free_all() -> void:
		orders.clear()
		um.clear()
		ai.free()
		wm.free()
		threats.free()
		tm.free()
		um.free()


## A RED controller over these units. With `fire`, an ENGAGE is carried out by the WeaponManager
## exactly as Simulation routes it, so rounds are really launched and queued.
func _harness(units: Array, plans: Array = [], fire := false) -> Harness:
	Terrain.clear()
	var h := Harness.new()
	h.um = UnitManager.new()
	for u: Unit in units:
		h.um.add_unit(u)
	h.tm = TrackManager.new()
	h.threats = ThreatManager.new()
	h.wm = WeaponManager.new()
	h.wm.unit_manager = h.um
	h.wm.rng.seed = 5
	h.ai = AIController.new()
	h.ai.faction = "RED"
	h.ai.unit_manager = h.um
	h.ai.track_manager = h.tm
	h.ai.threat_manager = h.threats
	h.ai.weapon_manager = h.wm
	h.ai.configure_plans(plans)
	var wm := h.wm
	h.um.order_issued.connect(func(u: Unit, o: Order) -> void:
		h.orders.append({"unit": u, "order": o})
		if fire and o.type == Order.Type.ENGAGE:
			o.execution_accepted = wm.launch(u, u.get_weapon(o.weapon_id), o.track, o.salvo, 0.0))
	return h


## A contact on RED's plot with no truth behind it: only what a track reports. `category` and
## `cls` are what the plot would say once classified, and are left empty below CLASS_KNOWN.
func _plot(h: Harness, id: String, pos: Vector2, category := "", cls := "", classification := Track.Classification.CLASS_KNOWN) -> Track:
	var t := Track.new()
	t.id = id
	t.owner_faction = "RED"
	t.position = pos
	t.classification = classification
	t.identity = "HOSTILE" if classification >= Track.Classification.CLASS_KNOWN else "UNKNOWN"
	t.domain = "surface" if classification >= Track.Classification.SURFACE else ""
	if classification >= Track.Classification.CLASS_KNOWN:
		t.known_category = category
		t.known_class = cls
	t.status = Track.Status.ACTIVE
	t.has_kinematics = true
	t.course_deg = 90.0
	t.speed_kn = 12.0
	if not h.tm._tracks.has("RED"):
		h.tm._tracks["RED"] = []
	h.tm._tracks["RED"].append(t)
	return t


func _orders_of(h: Harness, type: Order.Type, u: Unit = null) -> Array:
	return h.orders.filter(func(e: Dictionary) -> bool: return e["order"].type == type and (u == null or e["unit"] == u))


func _goal(h: Harness, u: Unit) -> Vector2:
	var moves := _orders_of(h, Order.Type.MOVE, u)
	return moves[-1]["order"].target_pos if not moves.is_empty() else Vector2.INF


func _plan(kind: String, extra := {}) -> Dictionary:
	var d := {"id": "plan", "faction": "RED", "kind": kind}
	d.merge(extra, true)
	return d


## Moves the harness's units for `seconds`, deciding every two seconds as Simulation does.
func _play(h: Harness, start: float, seconds: float) -> float:
	var now := start
	var next_ai := now
	while now < start + seconds:
		if now >= next_ai:
			h.ai.tick(now)
			next_ai += 2.0
		h.um.tick(DT, now)
		now += DT
	return now


# --- What the formation is after -------------------------------------------------------------

func test_threaten_carrier_fires_at_the_classified_carrier_not_the_nearer_escort() -> void:
	var red := _ship("RED-1", Vector2.ZERO, _asm(60.0))
	# Without a plan the nearest acceptable shot wins: the frigate.
	var h := _harness([red])
	_plot(h, "T2001", Vector2(0, 15), "frigate", "FFG Perry")
	_plot(h, "T2002", Vector2(0, 45), "carrier", "CVN Nimitz")
	h.ai.tick(100.0)
	var shots := _orders_of(h, Order.Type.ENGAGE)
	assert_eq(shots.size(), 1)
	if not shots.is_empty():
		assert_eq(shots[0]["order"].track.id, "T2001", "the baseline picks the nearest target")
	h.free_all()
	red = _ship("RED-1", Vector2.ZERO, _asm(60.0))
	h = _harness([red], [_plan("threaten_carrier", {"units": ["RED-1"], "threat_nm": 10, "assembly_window_s": 0})])
	_plot(h, "T2001", Vector2(0, 15), "frigate", "FFG Perry")
	_plot(h, "T2002", Vector2(0, 45), "carrier", "CVN Nimitz")
	h.ai.tick(100.0)
	shots = _orders_of(h, Order.Type.ENGAGE)
	assert_eq(shots.size(), 1, "one salvo")
	if not shots.is_empty():
		assert_eq(shots[0]["order"].track.id, "T2002", "the raid spends its missiles on the carrier, not the escort in between")
	var p := h.ai.plans[0]
	assert_eq(p.target_track_id, "T2002")
	assert_eq(p.phase, AIPlan.Phase.ATTACK)
	assert_true(h.ai.describe(red).contains("plan ATTACK strike"), h.ai.describe(red))
	h.free_all()


func test_threaten_carrier_steers_for_the_carrier_rather_than_shadowing_the_escort() -> void:
	var red := _ship("RED-1", Vector2.ZERO, _asm(20.0))
	var h := _harness([red], [_plan("threaten_carrier", {"units": ["RED-1"], "threat_nm": 10})])
	var frigate := _plot(h, "T2001", Vector2(12, 10), "frigate", "FFG Perry")
	var carrier := _plot(h, "T2002", Vector2(0, 45), "aircraft carrier", "CV Kuznetsov")
	h.ai.tick(100.0)
	assert_true(_orders_of(h, Order.Type.ENGAGE).is_empty(), "the frigate is in the envelope but is not what the raid is for")
	assert_eq(h.ai.state_name(red), "APPROACH")
	var goal := _goal(h, red)
	assert_true(goal.is_finite(), "it moves")
	assert_near(goal.distance_to(carrier.position), 0.8 * 20.0, 0.5, "to its attack position inside its envelope round the carrier")
	assert_true(goal.distance_to(frigate.position) > goal.distance_to(carrier.position), "not toward the escort")
	h.free_all()


func test_attack_shipping_prefers_the_merchant_over_a_nearer_frigate() -> void:
	var red := _ship("RED-1", Vector2.ZERO, _asm(60.0))
	var h := _harness([red], [_plan("attack_shipping", {"units": ["RED-1"], "threat_nm": 8, "assembly_window_s": 0})])
	_plot(h, "T3001", Vector2(0, 12), "frigate", "FFG Perry")
	_plot(h, "T3002", Vector2(10, 30), "merchant", "Merchant")
	h.ai.tick(100.0)
	var shots := _orders_of(h, Order.Type.ENGAGE)
	assert_eq(shots.size(), 1)
	if not shots.is_empty():
		assert_eq(shots[0]["order"].track.id, "T3002", "shipping first: the frigate is only in the way")
	h.free_all()


func test_a_warship_that_closes_on_the_raid_is_engaged_as_a_threat() -> void:
	var red := _ship("RED-1", Vector2.ZERO, _asm(60.0))
	var h := _harness([red], [_plan("threaten_carrier", {"units": ["RED-1"], "threat_nm": 10})])
	_plot(h, "T2001", Vector2(0, 8), "frigate", "FFG Perry")  # inside the threat radius
	h.ai.tick(100.0)
	var shots := _orders_of(h, Order.Type.ENGAGE)
	assert_eq(shots.size(), 1, "ignored until it threatens, and then engaged")
	if not shots.is_empty():
		assert_eq(shots[0]["order"].track.id, "T2001")
	h.free_all()


func test_before_its_start_a_plan_leaves_its_members_to_their_own_judgement() -> void:
	var red := _ship("RED-1", Vector2.ZERO, _asm(60.0))
	var h := _harness([red], [_plan("threaten_carrier", {"units": ["RED-1"], "start_s": 500, "threat_nm": 10, "assembly_window_s": 0})])
	_plot(h, "T2001", Vector2(0, 15), "frigate", "FFG Perry")
	_plot(h, "T2002", Vector2(0, 45), "carrier", "CVN Nimitz")
	h.ai.tick(100.0)
	assert_eq(h.ai.plans[0].phase, AIPlan.Phase.WAITING)
	var shots := _orders_of(h, Order.Type.ENGAGE)
	assert_eq(shots.size(), 1)
	if not shots.is_empty():
		assert_eq(shots[0]["order"].track.id, "T2001", "not yet the plan's: the nearest shot, as ever")
	h.free_all()


func test_a_routed_striker_keeps_to_its_route_while_the_plan_searches() -> void:
	var red := _ship("RED-1", Vector2.ZERO, _asm(60.0))
	red.patrol_route = [Vector2(0, 40), Vector2(40, 40)]
	var h := _harness([red], [_plan("threaten_carrier", {"units": ["RED-1"], "threat_nm": 10})])
	_plot(h, "T2001", Vector2(20, 10), "frigate", "FFG Perry")
	h.ai.tick(100.0)
	assert_eq(h.ai.state_name(red), "HOLD")
	assert_eq(_goal(h, red), Vector2(0, 40), "its authored route, not the frigate")
	assert_true(_orders_of(h, Order.Type.ENGAGE).is_empty())
	h.free_all()


# --- Kinds that hold ground ------------------------------------------------------------------

func test_protect_breakout_escort_stays_with_the_breakout_unit() -> void:
	var runner := _ship("Gorshkov", Vector2.ZERO)
	runner.ai_posture = "breakout"
	runner.patrol_route = [Vector2(0, 200)]
	runner.heading_deg = 0.0
	runner.ordered_heading_deg = 0.0
	var escort := _ship("Escort", Vector2(0, 5), _asm(60.0))
	escort.heading_deg = 0.0
	escort.ordered_heading_deg = 0.0
	var plan := _plan("protect_breakout", {"units": ["Escort"], "protect": ["Gorshkov"], "screen_nm": 8, "engage_within_nm": 25, "threat_nm": 10})
	var h := _harness([runner, escort], [plan])
	var distraction := _plot(h, "T4001", Vector2(40, 10), "frigate", "FFG Perry")
	var start_gap := escort.position.distance_to(distraction.position)
	var now := 100.0
	var next_ai := now
	for i in int(600.0 / DT):
		if now >= next_ai:
			h.ai.tick(now)
			next_ai += 2.0
		h.um.tick(DT, now)
		now += DT
	assert_true(_orders_of(h, Order.Type.ENGAGE).is_empty(), "the distraction off to one side is not the screen's business")
	assert_eq(h.ai.state_name(escort), "SCREEN")
	assert_true(escort.position.distance_to(runner.position) <= 8.0 + 4.0, "the escort is still on the screen: %.1f nm off" % escort.position.distance_to(runner.position))
	assert_true(runner.position.y > 3.0, "and the breakout ship has been running for the gate")
	assert_true(escort.position.distance_to(distraction.position) >= start_gap - 6.0, "it never turned toward the distraction")
	# A contact closing on the ship being protected is the screen's business.
	var threat := _plot(h, "T4002", runner.position + Vector2(5, 15), "frigate", "FFG Perry")
	h.ai.tick(now)
	var shots := _orders_of(h, Order.Type.ENGAGE)
	assert_eq(shots.size(), 1)
	if not shots.is_empty():
		assert_eq(shots[0]["order"].track, threat, "the threat to the breakout, not the nearer-to-hand distraction")
	h.free_all()


func test_defend_installation_does_not_chase_beyond_its_leash() -> void:
	var guard := _ship("Guard", Vector2(0, 15), _asm(20.0))
	var plan := _plan("defend_installation", {"units": ["Guard"], "objective_nm": [0, 0], "area_radius_nm": 30, "leash_nm": 40, "threat_nm": 5})
	var h := _harness([guard], [plan])
	_plot(h, "T5001", Vector2(0, 60), "destroyer", "DDG Burke")  # well outside the defended area
	h.ai.tick(100.0)
	assert_eq(h.ai.state_name(guard), "GUARD", "a contact outside the area is not chased")
	assert_true(_orders_of(h, Order.Type.MOVE).is_empty(), "the defender is on its station and stays there")
	assert_true(_orders_of(h, Order.Type.ENGAGE).is_empty())
	# Pushed out past its leash with an intruder inside the area, it comes back to its station.
	guard.position = Vector2(0, 50)
	_plot(h, "T5002", Vector2(0, 29), "destroyer", "DDG Burke")
	h.ai.tick(110.0)
	assert_eq(h.ai.state_name(guard), "SHADOW")
	var goal := _goal(h, guard)
	assert_true(goal.is_finite())
	assert_true(goal.length() <= 40.0 + 0.01, "never steered past the leash: goal %s" % goal)
	assert_near(goal.distance_to(Vector2(0, 15)), 0.0, 0.5, "back to its station first")
	# Back inside the leash, it closes on the intruder, still no further than the leash allows.
	guard.position = Vector2(0, 5)
	guard.waypoints.clear()  # as if it had got back
	h.orders.clear()
	h.ai.tick(120.0)
	goal = _goal(h, guard)
	assert_true(goal.is_finite())
	assert_true(goal.length() <= 40.0 + 0.01)
	assert_true(goal.y > 5.0, "toward the intruder")
	h.free_all()


## A station ashore is held from the water nearest it, not re-ordered every cycle from there.
func test_a_defender_whose_station_is_ashore_holds_off_the_beach() -> void:
	var guard := _ship("Guard", Vector2(0, 23), _asm(20.0))
	var h := _harness([guard], [_plan("defend_installation", {"units": ["Guard"], "objective_nm": [0, 0], "area_radius_nm": 30, "leash_nm": 40})])
	# Its station, fifteen miles from the installation, is five miles inland on this island.
	Terrain.load_from({"terrain": {"land": [{"id": "isle", "name": "Isle", "elevation_m": 80.0, "points_nm": [[-20, -20], [20, -20], [20, 20], [-20, 20]]}]}})
	_play(h, 100.0, 1200.0)
	assert_true(guard.position.y > 20.0 and guard.position.y < 21.5, "off the beach nearest its station: %s" % guard.position)
	assert_true(_orders_of(h, Order.Type.MOVE, guard).size() <= 2, "%d moves: arrived and holding, not sent again each cycle" % _orders_of(h, Order.Type.MOVE, guard).size())
	Terrain.clear()
	h.free_all()


# --- Coordination ----------------------------------------------------------------------------

func test_recon_scouts_go_first_and_the_strike_waits_for_a_classified_target() -> void:
	var scout := _ship("Scout", Vector2.ZERO)
	var s1 := _ship("S1", Vector2(-5, 0), _asm(60.0))
	var s2 := _ship("S2", Vector2(5, 0), _asm(60.0))
	var plan := _plan("threaten_carrier", {"units": ["S1", "S2"], "recon": ["Scout"], "objective_nm": [0, 50], "area_radius_nm": 30, "assembly_nm": [0, -5], "assembly_window_s": 600, "package": 2, "threat_nm": 10})
	var h := _harness([scout, s1, s2], [plan])
	var unknown := _plot(h, "T6001", Vector2(0, 45), "", "", Track.Classification.SURFACE)
	_plot(h, "T6002", Vector2(15, 20), "frigate", "FFG Perry")
	h.ai.tick(100.0)
	var p := h.ai.plans[0]
	assert_eq(p.phase, AIPlan.Phase.RECON, "nothing it wants is classified yet")
	assert_eq(h.ai.state_name(scout), "SCOUT")
	var look := _goal(h, scout)
	assert_true(look.is_finite() and look.distance_to(unknown.position) < unknown.position.length(), "the scout closes on the unclassified contact in the area")
	assert_eq(_goal(h, s1), Vector2(0, -5), "the strikers gather at the assembly point")
	assert_eq(_goal(h, s2), Vector2(0, -5))
	assert_true(_orders_of(h, Order.Type.ENGAGE).is_empty(), "and nobody fires at the frigate in the meantime")
	# The scout's report: the contact is the carrier. The strike assembles but does not yet fire.
	unknown.classification = Track.Classification.CLASS_KNOWN
	unknown.identity = "HOSTILE"
	unknown.known_category = "carrier"
	unknown.known_class = "CVN Nimitz"
	h.ai.tick(110.0)
	assert_eq(p.phase, AIPlan.Phase.ASSEMBLE)
	assert_true(_orders_of(h, Order.Type.ENGAGE).is_empty(), "in range, but the package is not together")
	# Both arrive: the plan goes over to the attack, on separate axes, still with weapons held.
	s1.position = Vector2(0, -5)
	s2.position = Vector2(1, -5)
	h.orders.clear()
	h.ai.tick(120.0)
	assert_eq(p.phase, AIPlan.Phase.ATTACK)
	assert_true(not p.weapons_free, "nobody is on an axis yet")
	assert_true(_orders_of(h, Order.Type.ENGAGE).is_empty())
	# The window closes: weapons free, and the volley goes at the carrier.
	h.ai.tick(120.0 + 601.0)
	assert_true(p.weapons_free)
	var shots := _orders_of(h, Order.Type.ENGAGE)
	assert_true(not shots.is_empty(), "the window closed: attack with what is in position")
	for e: Dictionary in shots:
		assert_eq(e["order"].track, unknown, "every round goes at the carrier")
	h.free_all()


func test_air_reconnaissance_is_asked_of_a_plan_deck_before_any_strike() -> void:
	var field := Unit.new()
	field.spec = PlatformSpec.new()
	field.spec.short_name = "Airfield"
	field.spec.domain = "land"
	field.spec.max_speed_kn = 0.0
	field.spec.aircraft_capacity = 8
	field.spec.health = 300.0
	field.faction = "RED"
	field.callsign = "Field"
	field.health = 300.0
	var striker := _ship("S1", Vector2(0, 0), _asm(60.0))
	var plan := _plan("threaten_carrier", {"units": ["S1"], "recon": [{"base": "Field", "platform": "rfn_mpa_il38n", "count": 1}], "objective_nm": [0, 80], "area_radius_nm": 40})
	var h := _harness([field, striker], [plan])
	h.ai.tick(100.0)
	var asks := _orders_of(h, Order.Type.AIR_MISSION, field)
	assert_eq(asks.size(), 1, "one reconnaissance mission over the objective")
	if not asks.is_empty():
		var o: Order = asks[0]["order"]
		assert_eq(o.mission_kind, AirMission.Kind.RECON)
		assert_eq(o.target_pos, Vector2(0, 80))
		assert_eq(o.aircraft_id, "rfn_mpa_il38n")
	h.ai.tick(102.0)
	assert_eq(_orders_of(h, Order.Type.AIR_MISSION).size(), 1, "asked once, not every cycle")
	h.free_all()


func _airframe(callsign: String, host: Unit, weapon: WeaponSpec = null) -> Unit:
	var a := Unit.new()
	a.spec = _platform(20.0)
	a.spec.domain = "air"
	a.spec.max_speed_kn = 500.0
	a.spec.cruise_speed_kn = 400.0
	a.spec.cruise_altitude_m = 8000.0
	a.spec.max_altitude_m = 12000.0
	a.spec.endurance_s = 14400.0
	a.faction = "RED"
	a.callsign = callsign
	a.health = 20.0
	a.sensors.append(_radar())
	if weapon != null:
		a.weapons.append(weapon)
		a.magazines[weapon.id] = 2
	a.flight_state = Unit.FlightState.STOWED
	a.home = host
	a.home_callsign = host.callsign
	a.position = host.position
	host.embarked.append(a)
	return a


func test_a_plan_deck_sends_its_scout_first_and_its_strike_only_at_the_target() -> void:
	var field := Unit.new()
	field.spec = PlatformSpec.new()
	field.spec.short_name = "Airfield"
	field.spec.domain = "land"
	field.spec.max_speed_kn = 0.0
	field.spec.aircraft_capacity = 8
	field.spec.health = 300.0
	field.faction = "RED"
	field.callsign = "Field"
	field.health = 300.0
	var eyes := _airframe("Eyes 1", field)
	var bomber := _airframe("Raid 1", field, _asm(120.0))
	var h := _harness([field, eyes, bomber], [_plan("threaten_carrier", {"units": ["Field"], "objective_nm": [0, 150]})])
	_plot(h, "T7001", Vector2(10, 60), "frigate", "FFG Perry")
	h.ai.tick(100.0)
	var p := h.ai.plans[0]
	assert_eq(p.role_of(eyes), "recon", "a surveillance airframe on the plan's field is its scout")
	assert_eq(p.role_of(bomber), "strike")
	var launches := _orders_of(h, Order.Type.LAUNCH_AIRCRAFT, field)
	assert_eq(launches.size(), 1, "one launch: the scout")
	if not launches.is_empty():
		assert_eq(launches[0]["order"].aircraft_id, "Eyes 1")
	eyes.flight_state = Unit.FlightState.AIRBORNE  # as the deck would put it up
	h.ai.tick(400.0)
	assert_eq(_orders_of(h, Order.Type.LAUNCH_AIRCRAFT, field).size(), 1, "a frigate is not worth the raid")
	_plot(h, "T7002", Vector2(0, 150), "carrier", "CVN Nimitz")
	h.ai.tick(700.0)
	launches = _orders_of(h, Order.Type.LAUNCH_AIRCRAFT, field)
	assert_eq(launches.size(), 2, "the carrier is: the strike goes up")
	if launches.size() == 2:
		assert_eq(launches[1]["order"].aircraft_id, "Raid 1")
	h.free_all()


func test_plan_scouts_leave_the_recon_missions_airframes_to_it() -> void:
	var field := Unit.new()
	field.spec = PlatformSpec.new()
	field.spec.short_name = "Airfield"
	field.spec.domain = "land"
	field.spec.max_speed_kn = 0.0
	field.spec.aircraft_capacity = 8
	field.spec.health = 300.0
	field.faction = "RED"
	field.callsign = "Field"
	field.health = 300.0
	var eyes := _airframe("Eyes 1", field)
	eyes.spec.id = "test_mpa"
	var h := _harness([field, eyes], [_plan("threaten_carrier", {"units": ["Field"], "recon": [{"base": "Field", "platform": "test_mpa", "count": 1}], "objective_nm": [0, 150]})])
	h.ai.tick(100.0)
	assert_eq(h.ai.plans[0].role_of(eyes), "recon")
	assert_eq(_orders_of(h, Order.Type.AIR_MISSION, field).size(), 1, "the reconnaissance mission is asked for")
	assert_true(_orders_of(h, Order.Type.LAUNCH_AIRCRAFT, field).is_empty(), "and its airframe is not also sent up as a scout")
	h.free_all()


func test_attack_axes_differ_between_shooters() -> void:
	var units := [_ship("S1", Vector2(-4, 0), _asm(20.0)), _ship("S2", Vector2(0, 0), _asm(20.0)), _ship("S3", Vector2(4, 0), _asm(20.0))]
	var h := _harness(units, [_plan("threaten_carrier", {"units": ["S1", "S2", "S3"]})])
	var carrier := _plot(h, "T8001", Vector2(0, 60), "carrier", "CVN Nimitz")
	h.ai.tick(100.0)
	var bearings: Array[float] = []
	for u: Unit in units:
		var goal := _goal(h, u)
		assert_true(goal.is_finite(), "%s moves to its attack position" % u.callsign)
		bearings.append(Geo.bearing_deg(carrier.position, goal))
	for i in bearings.size():
		for j in range(i + 1, bearings.size()):
			assert_true(absf(Geo.heading_delta(bearings[i], bearings[j])) >= 30.0, "axes %.0f and %.0f are separate approaches" % [bearings[i], bearings[j]])
	h.free_all()


# --- Round budget and the shared assessment --------------------------------------------------

func _committed(h: Harness) -> int:
	return h.wm.in_flight.size() + h.wm._pending.size()


func test_plan_budget_counts_queued_rounds_and_is_not_exceeded() -> void:
	var units: Array = []
	for i in 4:
		units.append(_ship("S%d" % i, Vector2(i, 0), _asm(60.0)))
	var plan := _plan("threaten_carrier", {"units": ["S0", "S1", "S2", "S3"], "budget": 8, "salvo": 4, "assess_s": 300, "assembly_window_s": 0})
	var h := _harness(units, [plan], true)
	_plot(h, "T9001", Vector2(0, 40), "carrier", "CVN Nimitz")
	h.ai.tick(100.0)
	assert_eq(_committed(h), 8, "two salvos of four, flying and queued, fill the budget")
	assert_eq(_orders_of(h, Order.Type.ENGAGE).size(), 2, "the third and fourth ships hold their fire")
	assert_true(not h.wm._pending.is_empty(), "most of each salvo is still queued on the launcher")
	# The volley arrives. The budget is free again, but the plan waits to see what it did.
	h.wm.in_flight.clear()
	h.wm._pending.clear()
	h.ai.tick(200.0)
	assert_eq(_orders_of(h, Order.Type.ENGAGE).size(), 2, "the shared assessment holds the ships that never fired too")
	var p := h.ai.plans[0]
	assert_true(p.assessing("T9001", 200.0))
	h.ai.tick(100.0 + 460.0)
	assert_true(_orders_of(h, Order.Type.ENGAGE).size() > 2, "after the assessment the plan attacks again")
	assert_true(_committed(h) <= 8, "and again within its budget")
	h.free_all()


## The plan's budget is for its target. A warship that merely came too close gets what the side
## would put on any contact, however large the budget.
func test_a_contact_that_only_threatens_gets_the_sides_usual_weight() -> void:
	var units: Array = []
	for i in 6:
		units.append(_ship("S%d" % i, Vector2(i, 0), _asm(60.0)))
	var h := _harness(units, [_plan("threaten_carrier", {"units": ["S0", "S1", "S2", "S3", "S4", "S5"], "budget": 24, "salvo": 4, "threat_nm": 15})], true)
	_plot(h, "T9101", Vector2(0, 10), "frigate", "FFG Perry")
	h.ai.tick(100.0)
	assert_eq(_committed(h), AIController.MAX_ROUNDS_IN_FLIGHT_PER_TRACK, "%d rounds at a threat" % _committed(h))
	assert_eq(_orders_of(h, Order.Type.ENGAGE).size(), 2)
	h.free_all()


func test_faction_cap_counts_queued_salvo_rounds_without_a_plan() -> void:
	var units: Array = []
	for i in 4:
		units.append(_ship("S%d" % i, Vector2(i, 0), _asm(60.0)))
	var h := _harness(units, [], true)
	_plot(h, "T9001", Vector2(0, 40), "carrier", "CVN Nimitz")
	h.ai.tick(100.0)
	assert_true(_committed(h) <= AIController.MAX_ROUNDS_IN_FLIGHT_PER_TRACK, "%d rounds flying and queued at one contact" % _committed(h))
	assert_eq(_orders_of(h, Order.Type.ENGAGE).size(), 2, "four ships no longer put sixteen rounds on one target")
	h.free_all()


# --- Information discipline ------------------------------------------------------------------

func test_an_unclassified_track_is_not_given_a_category_from_truth() -> void:
	var red := _ship("RED-1", Vector2.ZERO, _asm(60.0))
	var carrier := Unit.new()
	carrier.spec = _platform(300.0)
	carrier.spec.short_name = "CVN Nimitz"
	carrier.spec.category = "carrier"
	carrier.faction = "BLUE"
	carrier.callsign = "Nimitz"
	carrier.position = Vector2(0, 30)
	carrier.health = 300.0
	var h := _harness([red, carrier], [_plan("threaten_carrier", {"units": ["RED-1"], "assembly_window_s": 0})])
	h.tm.observe("RED", carrier, carrier.position, 0.8, 1.0, 0.0, 1.0, 30.0)
	var t := h.tm.find_track("RED", carrier)
	t.classification = Track.Classification.SURFACE  # a surface contact: what it is, nobody knows
	t.domain = "surface"
	h.ai.tick(100.0)
	var p := h.ai.plans[0]
	assert_eq(p.priority_rank(t), -1, "an unclassified contact matches nothing, whatever it really is")
	assert_eq(t.known_category, "")
	assert_eq(p.target_track_id, "", "so the plan has no target")
	assert_eq(p.phase, AIPlan.Phase.RECON)
	assert_true(_orders_of(h, Order.Type.ENGAGE).is_empty())
	# Classified wrongly, it is what the plot says it is, not what it is.
	t.classification = Track.Classification.CLASS_KNOWN
	t.identity = "HOSTILE"
	t.known_category = "destroyer"
	t.known_class = "DDG"
	h.ai.tick(110.0)
	assert_eq(p.target_track_id, "", "a carrier reported as a destroyer is a destroyer to the plan")
	h.free_all()


func test_the_plan_is_blind_to_an_undetected_carrier() -> void:
	var red := _ship("RED-1", Vector2.ZERO, _asm(60.0))
	var carrier := _ship("Nimitz", Vector2(0, 30))
	carrier.faction = "BLUE"
	carrier.spec.category = "carrier"
	var h := _harness([red, carrier], [_plan("threaten_carrier", {"units": ["RED-1"], "assembly_window_s": 0})])
	h.ai.tick(100.0)
	assert_eq(h.ai.plans[0].phase, AIPlan.Phase.RECON, "no track, no target, however close it is")
	assert_true(_orders_of(h, Order.Type.ENGAGE).is_empty())
	assert_true(_orders_of(h, Order.Type.MOVE).is_empty(), "and no move toward where it really is")
	h.free_all()


# --- Authoring ------------------------------------------------------------------------------

func test_malformed_plans_are_skipped_not_fatal() -> void:
	var red := _ship("RED-1", Vector2.ZERO, _asm(60.0))
	var plans := ["not a plan", {"id": "a", "faction": "RED", "kind": "invade_mars"}, {"id": "b", "faction": "RED", "kind": "threaten_carrier", "objective_nm": "here"}, {"id": "c", "faction": "RED", "kind": "attack_shipping", "units": ["RED-1"]}, {"id": "c", "faction": "RED", "kind": "attack_shipping"}, {"id": "d", "faction": "BLUE", "kind": "attack_shipping"}]
	var h := _harness([red], plans)
	assert_eq(h.ai.plans.size(), 1, "only the well-formed RED plan survives")
	assert_eq(h.ai.plans[0].id, "c")
	h.ai.tick(100.0)
	assert_eq(h.ai.plan_for(red), h.ai.plans[0])
	h.ai.configure_plans("not an array")
	assert_true(h.ai.plans.is_empty())
	h.free_all()


func test_a_tagged_reinforcement_joins_its_plan_on_arrival() -> void:
	var red := _ship("RED-1", Vector2.ZERO, _asm(60.0))
	var h := _harness([red], [_plan("threaten_carrier", {"units": ["RED-1"]})])
	h.ai.tick(100.0)
	ScenarioLoader.populate(h.um, {"units": [{"platform": "cw90_sovremenny", "callsign": "Late", "faction": "RED", "position_nm": [5, 0], "air_wing": [], "ai_plan": "plan", "ai_role": "recon"}]})
	var late: Unit = h.um.units[-1]
	assert_eq(late.ai_plan_id, "plan")
	h.ai.tick(102.0)
	assert_eq(h.ai.plan_for(late), h.ai.plans[0])
	assert_eq(h.ai.plans[0].role_of(late), "recon", "the authored role, not the kind's default")
	h.free_all()


func _scenario() -> Dictionary:
	return {"name": "Plan check", "player_faction": "BLUE", "map": {"center_nm": [0, 0], "extent_nm": 120},
		"units": [{"platform": "cw90_perry", "callsign": "Perry", "position_nm": [0, 0], "faction": "BLUE", "air_wing": []},
			{"platform": "cw90_sovremenny", "callsign": "Otlichny", "position_nm": [0, 60], "faction": "RED", "air_wing": []}],
		"objectives": {"victory": [{"id": "wait", "type": "time_elapsed", "seconds": 100}]},
		"ai_plans": [{"id": "raid", "faction": "RED", "kind": "threaten_carrier", "units": ["Otlichny"], "objective_nm": [0, 0]}]}


func test_the_workshop_checks_plans_against_the_scenario() -> void:
	assert_eq(ScenarioWorkshop.validate(_scenario()), "", "a well-formed plan passes")
	var sc := _scenario()
	sc["ai_plans"][0]["kind"] = "invade_mars"
	assert_true(ScenarioWorkshop.validate(sc).contains("kind"))
	sc = _scenario()
	sc["ai_plans"][0]["units"] = ["Nobody"]
	assert_true(ScenarioWorkshop.validate(sc).contains("missing unit"))
	sc = _scenario()
	sc["ai_plans"][0]["units"] = ["Perry"]
	assert_true(ScenarioWorkshop.validate(sc).contains("not on its side"))
	sc = _scenario()
	sc["ai_plans"][0]["objective_nm"] = [0, "north"]
	assert_true(ScenarioWorkshop.validate(sc) != "")
	sc = _scenario()
	sc["ai_plans"][0]["budget"] = -2
	assert_true(ScenarioWorkshop.validate(sc) != "")
	sc = _scenario()
	sc["ai_plans"].append({"id": "screen", "faction": "RED", "kind": "protect_breakout"})
	assert_true(ScenarioWorkshop.validate(sc).contains("protects"))
	sc = _scenario()
	sc["units"][1]["ai_plan"] = "elsewhere"
	assert_true(ScenarioWorkshop.validate(sc).contains("missing AI plan"))
	sc = _scenario()
	sc["units"][1]["ai_role"] = "admiral"
	assert_true(ScenarioWorkshop.validate(sc).contains("role"))
	sc = _scenario()
	sc["ai_plans"] = "everything"
	assert_true(ScenarioWorkshop.validate(sc) != "")


# --- A seeded run ---------------------------------------------------------------------------

## The fixture: a RED surface group with a scouting bomber, told to threaten a carrier. A BLUE
## frigate sits nearer the group than the carrier does. Returns RED's order log.
func _run_fixture(seconds: float) -> Array:
	SimClock.set_paused(true)
	var sim := Simulation.new()
	sim.seed_override = 11
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	assert_true(sim.load_scenario(FIXTURE), FIXTURE)
	var log: Array = []
	var record := func(u: Unit, o: Order) -> void:
		if u.faction != "RED":
			return
		var entry := {"t": SimClock.sim_time, "unit": u.callsign, "type": o.type, "track": o.track.id if o.track != null else "", "category": o.track.known_category if o.track != null else "", "goal": o.target_pos}
		log.append(entry)
	sim.unit_manager.order_issued.connect(record)
	var frigate: Unit = null
	for u in sim.unit_manager.units:
		if u.callsign == "Picket":
			frigate = u
	var closest := INF
	var elapsed := 0.0
	while elapsed < seconds:
		SimClock.advance(10.0)
		elapsed += 10.0
		for u in sim.unit_manager.get_faction_units("RED"):
			if not u.is_aircraft():
				closest = minf(closest, u.position.distance_to(frigate.position))
	log.append({"closest_to_picket": closest})
	sim.unit_manager.order_issued.disconnect(record)
	sim.unit_manager.clear()
	sim.queue_free()
	sim.free()
	return log


func test_a_seeded_red_formation_pursues_the_carrier_past_a_nearer_escort() -> void:
	var log := _run_fixture(3600.0)
	var closest: float = log.pop_back()["closest_to_picket"]
	var first_shot: Dictionary = {}
	var picket_shots_before := 0
	for e: Dictionary in log:
		if e["type"] != Order.Type.ENGAGE:
			continue
		if str(e["category"]).contains("carrier"):
			first_shot = e
			break
		picket_shots_before += 1
	assert_true(not first_shot.is_empty(), "the raid gets its missiles away at the carrier within the hour")
	assert_eq(picket_shots_before, 0, "nothing was spent on the frigate first")
	assert_true(closest > 12.0, "the strikers never closed on the nearer frigate (closest %.1f nm)" % closest)
	# The same seed plays out the same way.
	var again := _run_fixture(3600.0)
	again.pop_back()
	var n := mini(log.size(), again.size())
	assert_true(n > 0)
	var same := log.size() == again.size()
	for i in n:
		if log[i]["t"] != again[i]["t"] or log[i]["unit"] != again[i]["unit"] or log[i]["type"] != again[i]["type"] or log[i]["track"] != again[i]["track"]:
			same = false
			break
	assert_true(same, "two runs with one seed give one order log")
