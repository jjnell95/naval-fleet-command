extends TestCase
## A hull sent somewhere with land in the way is given the way round by sea and arrives; with no
## way it is refused and told why. One that is held by a coast all the same stops, says so once,
## and never shows a speed it is not making. The questions asked about the coast for every hull on
## every tick are answered from the sea grid exactly as every polygon in turn would answer them,
## and a shot is cleared against the same coastline that would stop the round in flight.

const DT := 0.25
const HORMUZ := "res://data/scenarios/gulf_01_hormuz.json"


func _platform(air := false) -> PlatformSpec:
	var p := PlatformSpec.new()
	p.short_name = "Test"
	p.max_speed_kn = 30.0
	p.cruise_speed_kn = 18.0
	p.turn_rate_deg_s = 3.0
	p.accel_kn_s = 0.5
	p.health = 100.0
	p.length_m = 155.0
	if air:
		p.domain = "air"
		p.max_speed_kn = 400.0
		p.cruise_speed_kn = 300.0
		p.cruise_altitude_m = 3000.0
		p.max_altitude_m = 9000.0
		p.altitude_rate_m_s = 20.0
		p.endurance_s = 36000.0
		p.length_m = 18.0
	return p


func _skimmer(max_range := 60.0) -> WeaponSpec:
	var w := WeaponSpec.new()
	w.id = "test_asm"
	w.display_name = "Test ASM"
	w.short_name = "ASM"
	w.type = "asm"
	w.profile = "sea_skimming"
	w.max_range_nm = max_range
	w.min_range_nm = 2.0
	w.speed_kn = 480.0
	w.turn_rate_deg_s = 30.0
	w.seeker_range_nm = 8.0
	w.damage = 40.0
	w.base_pk = 1.0
	w.salvo_default = 2
	w.launch_interval_s = 4.0
	return w


func _unit(faction: String, pos: Vector2, weapons: Array = [], air := false) -> Unit:
	var u := Unit.new()
	u.spec = _platform(air)
	u.faction = faction
	u.callsign = "%s-%s" % [faction, "air" if air else "ship"]
	u.position = pos
	u.health = 800.0
	u.spec.health = 800.0
	if air:
		u.flight_state = Unit.FlightState.AIRBORNE
		u.fuel_s = u.spec.endurance_s
		u.altitude_m = u.spec.cruise_altitude_m
		u.ordered_altitude_m = u.spec.cruise_altitude_m
		u.speed_kn = u.spec.cruise_speed_kn
		u.ordered_speed_kn = u.spec.cruise_speed_kn
	for w: WeaponSpec in weapons:
		u.weapons.append(w)
		u.magazines[w.id] = 8
	return u


func _track(target: Unit, identity := "HOSTILE") -> Track:
	var t := Track.new()
	t.id = "T2001"
	t.owner_faction = "BLUE"
	t.truth = target
	t.position = target.position
	t.status = Track.Status.ACTIVE
	t.domain = target.spec.domain
	t.identity = identity
	t.classification = Track.Classification.CLASS_KNOWN if identity != "UNKNOWN" else Track.Classification.SURFACE
	t.known_class = target.spec.short_name
	return t


class Harness:
	extends RefCounted
	var um: UnitManager
	var wm: WeaponManager
	var now := 0.0
	var blocked: Array = []
	var attacks_ended: Array = []
	var looks_ended: Array = []

	func step() -> void:
		now += 0.25
		um.tick(0.25, now)
		wm.tick(0.25, now)

	func advance(seconds: float, each := Callable()) -> void:
		for i in int(round(seconds / 0.25)):
			step()
			if each.is_valid():
				each.call()

	func until(predicate: Callable, limit_s: float, each := Callable()) -> bool:
		for i in int(round(limit_s / 0.25)):
			if predicate.call():
				return true
			step()
			if each.is_valid():
				each.call()
		return predicate.call()

	func free_all() -> void:
		um.free()
		wm.free()
		Terrain.clear()


func _harness(units: Array) -> Harness:
	var h := Harness.new()
	h.um = UnitManager.new()
	for u: Unit in units:
		h.um.add_unit(u)
	h.wm = WeaponManager.new()
	h.wm.unit_manager = h.um
	h.wm.rng.seed = 7
	h.um.weapon_manager = h.wm
	h.um.blocked_by_coast.connect(func(u: Unit) -> void: h.blocked.append(u))
	h.um.attack_ended.connect(func(u: Unit, t: Track, reason: String) -> void: h.attacks_ended.append([u, t, reason]))
	h.um.investigation_ended.connect(func(u: Unit, t: Track, reason: String) -> void: h.looks_ended.append([u, t, reason]))
	return h


func _land(polygons: Array) -> void:
	var land: Array = []
	for i in polygons.size():
		land.append({"id": "land%d" % i, "name": "Land %d" % i, "elevation_m": 80.0, "points_nm": polygons[i]})
	Terrain.load_from({"terrain": {"land": land}})


## Open water walled in on all four sides: four bars that overlap at the corners.
func _walled_sea() -> void:
	_land([
		[[-30, -30], [30, -30], [30, -20], [-30, -20]],
		[[-30, 20], [30, 20], [30, 30], [-30, 30]],
		[[-30, -30], [-20, -30], [-20, 30], [-30, 30]],
		[[20, -30], [30, -30], [30, 30], [20, 30]]])


func _legs_clear(from: Vector2, route: Array) -> bool:
	var at := from
	for p: Vector2 in route:
		if Terrain.first_land_contact_exhaustive(at, p) >= 0.0 or Terrain.is_land_exhaustive(p):
			return false
		at = p
	return true


# --- A move with land in the way -----------------------------------------------------------------

## The audit's case: Hormuz, a destroyer west of the Musandam peninsula sent to a point east of it.
func test_a_move_across_a_peninsula_sails_round_it_and_arrives_without_touching_the_coast() -> void:
	Terrain.load_from(ScenarioLoader.load_file(HORMUZ))
	var ship := _unit("BLUE", Vector2(-28.0, 10.2))
	var h := _harness([ship])
	var target := Vector2(48.4, -45.0)
	assert_true(Terrain.first_land_contact(ship.position, target) >= 0.0, "the fixture has land on the straight course")
	assert_true(h.um.issue_order(ship, Order.move(target)), "the order is accepted")
	assert_true(h.um.issue_order(ship, Order.set_speed(20.0)))
	assert_true(ship.waypoints.size() >= 2, "with the way round as waypoints, not one leg across the land")
	assert_eq(ship.waypoints.back(), target, "ending where she was sent")
	assert_true(_legs_clear(ship.position, ship.waypoints), "and no leg of it crosses a coast")
	var searches := Terrain.sea_route_searches
	var worst := [INF, INF]  # slowest speed once under way, nearest approach to land
	var ashore := [false]
	var arrived := h.until(func() -> bool: return ship.waypoints.is_empty(), 8.0 * 3600.0, func() -> void:
		if h.now > 120.0 and not ship.waypoints.is_empty() and ship.position.distance_to(target) > 1.0:
			worst[0] = minf(worst[0], ship.speed_kn)
		if Terrain.is_land(ship.position):
			ashore[0] = true)
	assert_true(arrived, "she gets there")
	assert_true(ship.position.distance_to(target) < 0.5, "to within half a mile (%.1f nm off)" % ship.position.distance_to(target))
	assert_true(h.now < 6.0 * 3600.0, "at about the speed she was told to make (%.1f h)" % (h.now / 3600.0))
	assert_true(worst[0] > 19.0, "keeping her speed the whole way (slowest %.1f kn)" % worst[0])
	assert_true(not ashore[0], "and never ashore")
	assert_true(h.blocked.is_empty(), "nor stopped by the coast")
	assert_eq(Terrain.sea_route_searches, searches, "the way was planned when the order was given, not on any tick")
	h.free_all()


func test_a_move_with_no_way_by_sea_is_refused_with_the_reason() -> void:
	_walled_sea()
	var ship := _unit("BLUE", Vector2(-60, 0))
	var h := _harness([ship])
	var inside := Order.move(Vector2(0, 0))
	assert_true(not Terrain.is_land(inside.target_pos), "the destination is water")
	assert_true(not h.um.issue_order(ship, inside), "but there is no way to it, so the order is refused")
	assert_eq(inside.receipt, "No sea route")
	assert_eq(UnitManager.move_rejection(ship, inside), "No sea route")
	assert_true(ship.waypoints.is_empty() and ship.ordered_speed_kn == 0.0, "and she is not sent at the coast")
	var ashore := Order.move(Vector2(0, 25))
	assert_true(not h.um.issue_order(ship, ashore), "a destination on dry land is refused as before")
	assert_eq(ashore.receipt, "Destination is ashore")
	# The far side of the walls is another matter: round the outside.
	var beyond := Order.move(Vector2(60, 0))
	assert_true(h.um.issue_order(ship, beyond))
	assert_true(ship.waypoints.size() >= 2 and _legs_clear(ship.position, ship.waypoints))
	# An aircraft goes where it is told.
	var jet := _unit("BLUE", Vector2(-60, 0), [], true)
	h.um.add_unit(jet)
	assert_true(h.um.issue_order(jet, Order.move(Vector2(0, 0))))
	assert_eq(jet.waypoints.size(), 1, "an aircraft is not routed")
	h.free_all()


func test_an_appended_waypoint_is_routed_from_the_end_of_the_route_not_from_the_ship() -> void:
	_land([[[-2, -20], [2, -20], [2, 20], [-2, 20]]])
	var ship := _unit("BLUE", Vector2(-30, 0))
	var h := _harness([ship])
	assert_true(h.um.issue_order(ship, Order.move(Vector2(-10, 0))))
	assert_eq(ship.waypoints.size(), 1, "open water: one leg")
	# From the end of that leg the next point lies behind the island; from the ship it does too.
	assert_true(h.um.issue_order(ship, Order.move(Vector2(10, 0), true)))
	assert_true(ship.waypoints.size() >= 3, "the way round is added after the first leg")
	assert_eq(ship.waypoints[0], Vector2(-10, 0), "which is kept")
	assert_eq(ship.waypoints.back(), Vector2(10, 0))
	assert_true(_legs_clear(ship.position, ship.waypoints))
	_walled_sea()
	ship.position = Vector2(-60, 0)
	assert_true(h.um.issue_order(ship, Order.move(Vector2(-50, 10))))
	var shut_in := Order.move(Vector2(0, 0), true)
	assert_true(not h.um.issue_order(ship, shut_in), "an added point with no way to it is refused")
	assert_eq(shut_in.receipt, "No sea route")
	assert_eq(ship.waypoints.size(), 1, "and the route is left as it was")
	h.free_all()


## Every route the router gives, on every chart shipped: ends where it was asked to, and no leg of
## it touches a coast, tested the slow way against every polygon.
func test_sea_routes_on_every_shipped_chart_never_cross_a_coast() -> void:
	var charts := 0
	var routed := 0
	var none := 0
	var worst_usec := 0
	for file in DirAccess.get_files_at("res://data/scenarios"):
		if not file.ends_with(".json"):
			continue
		Terrain.load_from(ScenarioLoader.load_file("res://data/scenarios/" + file))
		if Terrain.is_empty():
			continue
		charts += 1
		var rng := RandomNumberGenerator.new()
		rng.seed = 4201
		var area := Terrain.bounds.grow(5.0)
		var sea: Array[Vector2] = []
		while sea.size() < 60:
			var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
			if not Terrain.is_land(p):
				sea.append(p)
		for i in 30:
			var from := sea[i * 2]
			var to := sea[i * 2 + 1]
			var before := Terrain.sea_route_searches
			var route := Terrain.sea_route(from, to)
			if Terrain.sea_route_searches > before:
				worst_usec = maxi(worst_usec, Terrain.sea_route_last_usec)
			if route.is_empty():
				none += 1
				assert_true(Terrain.first_land_contact_exhaustive(from, to) >= 0.0, "%s: no route is only ever said of a pair with land between them" % file)
				continue
			if route.size() > 1:
				routed += 1
			assert_eq(route[route.size() - 1], to, "%s: the route ends at the destination" % file)
			assert_true(_legs_clear(from, Array(route)), "%s: a leg from %s to %s crosses a coast" % [file, from, to])
			assert_eq(Terrain.sea_route(from, to), route, "%s: asked again, the same way" % file)
	assert_true(charts >= 5 and routed >= 50, "the charts with coasts were tried (%d charts, %d routes round land)" % [charts, routed])
	# Bounded: the grid is at most SEA_GRID_MAX_AXIS cells a side, so a search has a ceiling whatever
	# the chart. Generous, because the machine that runs this is shared.
	assert_true(worst_usec < 2_000_000, "the slowest search took %.1f ms" % (worst_usec / 1000.0))
	print("    %d charts: %d routes round land, %d pairs with no way, slowest search %.1f ms" % [charts, routed, none, worst_usec / 1000.0])
	Terrain.clear()


func test_a_patrol_beyond_an_island_is_taken_up_by_sea_and_the_way_there_is_sailed_once() -> void:
	_land([[[-2, -20], [2, -20], [2, 20], [-2, 20]]])
	var ship := _unit("BLUE", Vector2(-10, 0))
	var h := _harness([ship])
	var box := Order.patrol_box(Vector2(8, -4), Vector2(16, 4))
	assert_true(h.um.issue_order(ship, box), "a circuit behind the island is accepted")
	assert_true(ship.waypoints.size() > box.route.size(), "with the way round the island ahead of its first corner")
	assert_true(_legs_clear(ship.position, ship.waypoints))
	assert_true(h.until(func() -> bool: return ship.patrol_legs_completed >= 6, 12.0 * 3600.0), "she gets there and sails the circuit")
	assert_true(h.blocked.is_empty())
	for p: Vector2 in ship.waypoints:
		assert_true(box.route.has(p), "only the corners of the circuit come round again, not the way she came (%s)" % p)
	assert_eq(ship.waypoints.size(), box.route.size())
	# Found on the far side of the island again, as after a task that took her there: the return
	# to station is routed too.
	ship.position = Vector2(-10, 0)
	assert_true(h.um.issue_order(ship, Order.return_to_station()), "she is not refused her station for the island in the way")
	assert_true(ship.waypoints.size() > box.route.size() and _legs_clear(ship.position, ship.waypoints))
	h.free_all()


# --- Tasks ----------------------------------------------------------------------------------------

func test_an_investigation_of_a_contact_behind_an_island_goes_round_without_planning_every_tick() -> void:
	_land([[[-2, -20], [2, -20], [2, 20], [-2, 20]]])
	var ship := _unit("BLUE", Vector2(-10, 0))
	var contact := _unit("RED", Vector2(10, 0))
	var h := _harness([ship, contact])
	var t := _track(contact, "UNKNOWN")
	assert_true(h.um.issue_order(ship, Order.investigate(t)), "accepted: there is a way round")
	assert_true(ship.waypoints.size() >= 2 and _legs_clear(ship.position, ship.waypoints))
	var searches := Terrain.sea_route_searches
	h.advance(1800.0)
	assert_true(Terrain.sea_route_searches - searches <= 1, "half an hour of steering round the island plans no more routes (%d)" % (Terrain.sea_route_searches - searches))
	assert_true(h.until(func() -> bool: return ship.position.distance_to(contact.position) < 0.5, 4.0 * 3600.0), "she closes the contact")
	assert_true(h.looks_ended.is_empty() and h.blocked.is_empty(), "the look was never given up for the land")
	# Walled in, there is nothing to plan: the order is refused with the reason.
	_walled_sea()
	ship.position = Vector2(-60, 0)
	contact.position = Vector2.ZERO
	t.position = contact.position
	assert_true(h.um.issue_order(ship, Order.stop()))
	assert_true(not h.um.issue_order(ship, Order.investigate(t)))
	assert_eq(UnitManager.investigation_rejection(ship, t), UnitManager.NO_SEA_ROUTE_TO_CONTACT)
	h.free_all()


func test_an_attack_out_of_range_behind_a_headland_closes_round_it_and_fires() -> void:
	# A wall with the target far beyond it: out of reach from here, and the firing point lies across the land.
	_land([[[-40, 20], [40, 20], [40, 24], [-40, 24]]])
	var ship := _unit("BLUE", Vector2.ZERO, [_skimmer(40.0)])
	var target := _unit("RED", Vector2(0, 110))
	var h := _harness([ship, target])
	assert_true(h.um.issue_order(ship, Order.attack(_track(target))))
	assert_true(ship.waypoints.size() >= 2, "the closing leg is the way round the wall")
	assert_true(_legs_clear(ship.position, ship.waypoints))
	var searches := Terrain.sea_route_searches
	assert_true(h.until(func() -> bool: return ship.attack_rounds_fired > 0, 10.0 * 3600.0), "she rounds it and fires")
	assert_true(h.attacks_ended.is_empty(), "without the attack ever being given back as stalled")
	assert_true(h.blocked.is_empty())
	assert_true(Terrain.sea_route_searches - searches < 40, "planning again only as her firing point moved (%d searches in %.1f h)" % [Terrain.sea_route_searches - searches, h.now / 3600.0])
	h.free_all()


# --- Held by the coast ----------------------------------------------------------------------------

func test_a_hull_steered_onto_a_coast_stops_and_reports_blocked_once() -> void:
	_land([[[-60, 10], [60, 10], [60, 14], [-60, 14]]])
	var ship := _unit("BLUE", Vector2.ZERO)
	var h := _harness([ship])
	assert_true(h.um.issue_order(ship, Order.set_course(0.0)), "a course names no destination, so nothing routes it")
	assert_true(h.um.issue_order(ship, Order.set_speed(20.0)))
	# Up to the beach, and then: every tick, the speed she shows is the way she actually made.
	var last := [ship.position]
	var overclaimed := [0.0]
	var touched := [-1.0]
	var check := func() -> void:
		var made_kn := ship.position.distance_to(last[0]) / DT * 3600.0
		overclaimed[0] = maxf(overclaimed[0], ship.speed_kn - made_kn)
		last[0] = ship.position
		if touched[0] < 0.0 and ship.position.y > 9.995:
			touched[0] = h.now
	assert_true(h.until(func() -> bool: return not h.blocked.is_empty(), 3600.0, check), "she reports that the coast has stopped her")
	assert_true(touched[0] > 0.0 and h.now - touched[0] <= Movement.COAST_BLOCKED_S + 10.0, "about twenty seconds after she ran out of water (%.0f s)" % (h.now - touched[0]))
	assert_true(overclaimed[0] < 0.5, "her speed never claimed way she was not making (%.2f kn over)" % overclaimed[0])
	assert_eq(ship.speed_kn, 0.0, "stopped")
	assert_eq(ship.ordered_speed_kn, 0.0, "and ordered to stop")
	assert_true(not Terrain.is_land(ship.position), "still afloat")
	assert_eq(DataDisplay.orders_text(ship), "Blocked by coast", "the orders line says why she is stopped")
	h.advance(600.0, check)
	assert_eq(h.blocked.size(), 1, "said once, not every twenty seconds")
	assert_eq(ship.speed_kn, 0.0)
	# Sent at the same beach again she stops again and says so again; turned away she goes.
	assert_true(h.um.issue_order(ship, Order.set_speed(15.0)))
	assert_true(h.um.issue_order(ship, Order.set_course(0.0)))
	assert_true(h.until(func() -> bool: return h.blocked.size() == 2, 300.0, check), "a new order onto the coast is reported afresh")
	assert_true(overclaimed[0] < 0.5)
	assert_true(h.um.issue_order(ship, Order.move(Vector2(0, -20))))
	h.advance(1800.0)
	assert_true(ship.position.y < 5.0 and ship.speed_kn > 10.0, "she is worked round off the beach and sails away (y %.1f, %.1f kn)" % [ship.position.y, ship.speed_kn])
	assert_true(not ship.coast_blocked)
	assert_eq(h.blocked.size(), 2)
	h.free_all()


func test_a_route_whose_water_has_gone_is_dropped_when_the_hull_is_stopped_by_it() -> void:
	var ship := _unit("BLUE", Vector2.ZERO)
	var h := _harness([ship])
	assert_true(h.um.issue_order(ship, Order.move(Vector2(0, 40))))
	assert_true(h.um.issue_order(ship, Order.move(Vector2(30, 60), true)))
	h.advance(600.0)
	# The coast is redrawn across the leg she is already on (the editor can do this, and a route
	# laid before a save was made with another chart): nothing plans it again.
	_land([[[-60, ship.position.y + 1.0], [60, ship.position.y + 1.0], [60, ship.position.y + 3.0], [-60, ship.position.y + 3.0]]])
	assert_true(h.until(func() -> bool: return not h.blocked.is_empty(), 1800.0))
	assert_true(ship.waypoints.is_empty(), "the blocked leg and what lay beyond it are given up")
	assert_eq(ship.speed_kn, 0.0)
	assert_eq(ship.ordered_speed_kn, 0.0)
	h.free_all()


func test_a_hull_meeting_a_coast_at_a_slant_follows_it_at_the_speed_and_heading_she_shows() -> void:
	_land([[[-200, 10], [200, 10], [200, 14], [-200, 14]]])
	var ship := _unit("BLUE", Vector2(-50, 5))
	var h := _harness([ship])
	assert_true(h.um.issue_order(ship, Order.set_course(70.0)))
	assert_true(h.um.issue_order(ship, Order.set_speed(20.0)))
	h.advance(3600.0)
	assert_true(ship.position.y > 9.5, "she has met the shore")
	var from := ship.position
	h.advance(600.0)
	var made_kn := ship.position.distance_to(from) * 6.0
	assert_true(made_kn > 15.0, "and runs along it (%.1f kn made good)" % made_kn)
	assert_near(ship.speed_kn, made_kn, 1.0, "at the speed she shows")
	assert_true(absf(Geo.heading_delta(ship.heading_deg, 90.0)) < 5.0, "on the heading she shows (%.0f)" % ship.heading_deg)
	assert_true(h.blocked.is_empty(), "making way, she is not reported blocked")
	h.free_all()


# --- The coast, asked cheaply ---------------------------------------------------------------------

## Ten thousand seeded points on every chart shipped: the sea grid's answer is the answer of every
## polygon in turn, down to which landmass the point is on. And a thousand lines: the same first
## crossing of the coast, to the last bit.
func test_point_and_line_queries_match_the_full_scan_on_every_shipped_chart() -> void:
	var charts := 0
	var ashore := 0
	var crossing := 0
	for file in DirAccess.get_files_at("res://data/scenarios"):
		if not file.ends_with(".json"):
			continue
		Terrain.load_from(ScenarioLoader.load_file("res://data/scenarios/" + file))
		if Terrain.is_empty():
			continue
		charts += 1
		var rng := RandomNumberGenerator.new()
		rng.seed = 9173
		var area := Terrain.bounds.grow(8.0)
		var wrong := 0
		var points: Array[Vector2] = []
		for i in 10000:
			var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
			points.append(p)
			var slow := Terrain.land_at_exhaustive(p)
			if Terrain.land_at(p) != slow or Terrain.is_land(p) != (slow != null):
				wrong += 1
			if slow != null:
				ashore += 1
		assert_eq(wrong, 0, "%s: points answered differently from the full scan" % file)
		var lines_wrong := 0
		for i in 1000:
			var a := points[i]
			var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.05, 90.0)
			var slow := Terrain.first_land_contact_exhaustive(a, b)
			if Terrain.first_land_contact(a, b) != slow:
				lines_wrong += 1
			if slow >= 0.0:
				crossing += 1
		assert_eq(lines_wrong, 0, "%s: lines answered differently from the full scan" % file)
	assert_true(charts >= 5 and ashore > 5000 and crossing > 500, "the charts were exercised (%d charts, %d points ashore, %d lines crossing a coast)" % [charts, ashore, crossing])
	Terrain.clear()


func test_a_point_on_overlapping_landmasses_is_on_the_first_as_the_full_scan_says() -> void:
	# Two overlapping islands and one wholly inside another, on a small hand-drawn chart.
	_land([
		[[0, 0], [20, 0], [20, 20], [0, 20]],
		[[10, 10], [30, 10], [30, 30], [10, 30]],
		[[4, 4], [8, 4], [8, 8], [4, 8]]])
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 4000:
		var p := Vector2(rng.randf_range(-5.0, 35.0), rng.randf_range(-5.0, 35.0))
		assert_eq(Terrain.land_at(p), Terrain.land_at_exhaustive(p), "at %s" % p)
	assert_eq(Terrain.land_at(Vector2(15, 15)), Terrain.landmasses[0], "the overlap belongs to the first")
	assert_eq(Terrain.land_at(Vector2(6, 6)), Terrain.landmasses[0])
	assert_eq(Terrain.land_at(Vector2(25, 25)), Terrain.landmasses[1])
	assert_true(not Terrain.is_land(Vector2(25, 5)))
	# Redrawn, the answers follow the new coast at once.
	_land([[[100, 100], [110, 100], [110, 110], [100, 110]]])
	assert_true(not Terrain.is_land(Vector2(15, 15)) and Terrain.is_land(Vector2(105, 105)))
	Terrain.clear()
	assert_true(not Terrain.is_land(Vector2(105, 105)))


# --- The line of fire ------------------------------------------------------------------------------

## What the launch check clears, the flight check does not then stop: seeded sea-to-sea shots on a
## shipped chart, each flown straight at sea level the way WeaponManager steps a round.
func test_a_shot_cleared_for_its_line_of_fire_never_flies_into_land() -> void:
	Terrain.load_from(ScenarioLoader.load_file(HORMUZ))
	var spec := _skimmer(120.0)
	var shooter := _unit("BLUE", Vector2.ZERO, [spec])
	var target := _unit("RED", Vector2.ZERO)
	var t := _track(target)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var area := Terrain.bounds
	var cleared := 0
	var refused := 0
	var disagreed := 0
	var flew_into_land := 0
	var tried := 0
	while tried < 4000:
		var a := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(4.0, 60.0)
		if Terrain.is_land(a) or Terrain.is_land(b):
			continue
		tried += 1
		shooter.position = a
		t.position = b
		if Combat.crosses_land(shooter, spec, t):
			refused += 1
			continue
		cleared += 1
		if Terrain.blocks_path(a, b):
			disagreed += 1  # the chart of ground heights would have refused it; the coastline does not
		# The round's own steps: a quarter of a second at its speed, each tested as _hits_terrain does.
		var travel := Geo.knots_to_nm_per_s(spec.speed_kn) * DT
		var steps := int(ceilf(a.distance_to(b) / travel))
		var at := a
		for i in steps:
			var next := a.move_toward(b, travel * float(i + 1))
			if Terrain.is_land(next) or Terrain.first_land_contact(at, next) >= 0.0:
				flew_into_land += 1
				break
			at = next
	assert_eq(flew_into_land, 0, "of %d shots cleared, none meets land in flight" % cleared)
	assert_true(cleared > 2000 and refused > 200, "both answers were exercised (%d cleared, %d refused)" % [cleared, refused])
	Terrain.clear()


## The audit's segments: a sea-to-sea line that crosses a coastline the coarse chart of ground
## heights does not show. The launch check must refuse it, because the round would not arrive.
func test_a_line_that_crosses_a_coast_the_height_chart_misses_is_no_line_of_fire() -> void:
	Terrain.load_from(ScenarioLoader.load_file(HORMUZ))
	var spec := _skimmer(120.0)
	var shooter := _unit("BLUE", Vector2.ZERO, [spec])
	var target := _unit("RED", Vector2.ZERO)
	var t := _track(target)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var area := Terrain.bounds
	var missed_by_heights := 0
	var cleared_anyway := 0
	var tried := 0
	while tried < 4000:
		var a := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(4.0, 60.0)
		if Terrain.is_land(a) or Terrain.is_land(b):
			continue
		tried += 1
		if Terrain.first_land_contact_exhaustive(a, b) < 0.0 or Terrain.blocks_path(a, b):
			continue
		missed_by_heights += 1
		shooter.position = a
		t.position = b
		if not Combat.crosses_land(shooter, spec, t):
			cleared_anyway += 1
		else:
			var check := Combat.check_engagement(shooter, spec, t)
			assert_eq(str(check["reason"]), "NO LINE OF FIRE", "from %s to %s" % [a, b])
	assert_true(missed_by_heights >= 10, "the fixture finds lines the height chart misses (%d)" % missed_by_heights)
	assert_eq(cleared_anyway, 0, "none of the %d is cleared to fire" % missed_by_heights)
	# A battery ashore and a target ashore are still not a line-of-fire question.
	t.domain = "land"
	assert_true(not Combat.crosses_land(shooter, spec, t))
	Terrain.clear()


func test_the_point_chosen_to_clear_a_line_of_fire_has_one_against_the_coastline() -> void:
	_land([[[-3, 12], [3, 12], [3, 18], [-3, 18]]])
	var from := Vector2.ZERO
	var target := Vector2(0, 30)
	var point := Combat.clear_standoff_point(from, target, 40.0)
	assert_true(point.is_finite())
	assert_true(Terrain.first_land_contact_exhaustive(point, target) < 0.0, "an open line to the target, by the coast itself")
	assert_true(Terrain.first_land_contact_exhaustive(from, point) < 0.0, "and a straight sail to it, taken before any way round")
	# Only a voyage would do it: a bar hundreds of miles long. That is no line of fire.
	_land([[[-300, 10], [300, 10], [300, 12], [-300, 12]]])
	assert_true(not Combat.clear_standoff_point(from, target, 40.0).is_finite())
	# A short way round is taken.
	_land([[[-12, 10], [12, 10], [12, 12], [-12, 12]]])
	var round_the_end := Combat.clear_standoff_point(from, target, 40.0)
	assert_true(round_the_end.is_finite(), "a point behind a short bar is worth sailing round to")
	assert_true(Terrain.first_land_contact_exhaustive(round_the_end, target) < 0.0)
	Terrain.clear()
