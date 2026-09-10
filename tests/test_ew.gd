extends TestCase
## Operational depth: hearing someone transmit, sharing what you know, deciding what may be shot
## at without asking, being damaged in ways that matter, and keeping station.

const DT := 0.25


func _spec(domain := "surface") -> PlatformSpec:
	var p := PlatformSpec.new()
	p.short_name = "DDG Test"
	p.domain = domain
	p.max_speed_kn = 30.0
	p.cruise_speed_kn = 16.0
	p.health = 110.0
	p.signature_factor = 1.0
	p.mast_height_m = 30.0
	p.acoustic_signature = 1.0
	if domain == "subsurface":
		p.max_depth_m = 240.0
		p.depth_rate_m_s = 2.0
		p.acoustic_signature = 0.05
	return p


func _radar(surface := 40.0, antenna := 20.0) -> SensorSpec:
	var s := SensorSpec.new()
	s.kind = "radar"
	s.range_surface_nm = surface
	s.range_air_nm = 200.0
	s.antenna_height_m = antenna
	s.classify_rate = 1.0
	return s


func _esm(gain := 2.0, antenna := 26.0) -> SensorSpec:
	var s := SensorSpec.new()
	s.kind = "esm"
	s.esm_gain = gain
	s.antenna_height_m = antenna
	s.bearing_accuracy_deg = 1.5
	s.classify_rate = 1.2
	return s


func _unit(spec: PlatformSpec, faction: String, pos: Vector2, speed := 0.0) -> Unit:
	var u := Unit.new()
	u.spec = spec
	u.faction = faction
	u.callsign = "%s-%d" % [faction, randi() % 10000]
	u.position = pos
	u.speed_kn = speed
	u.ordered_speed_kn = speed
	u.health = spec.health
	return u


# --- Electronic support ------------------------------------------------------------------

func test_esm_hears_a_radar_and_nothing_when_it_stops() -> void:
	var listener := _unit(_spec(), "BLUE", Vector2.ZERO)
	listener.sensors.append(_esm())
	listener.radar_on = false
	var emitter := _unit(_spec(), "RED", Vector2(0.0, 15.0))
	emitter.sensors.append(_radar())
	emitter.radar_on = true
	assert_true(Detection.best_esm(listener, emitter)["range_nm"] > 15.0, "a radiating ship is audible")
	emitter.radar_on = false
	assert_near(Detection.best_esm(listener, emitter)["range_nm"], 0.0, 1e-6, "silence is silence")


func test_esm_does_not_care_how_small_the_emitter_is() -> void:
	var listener := _unit(_spec(), "BLUE", Vector2.ZERO)
	listener.sensors.append(_esm())
	listener.sensors.append(_radar())
	var stealthy := _spec()
	stealthy.signature_factor = 0.15  # very hard to see on radar
	var emitter := _unit(stealthy, "RED", Vector2(0.0, 12.0))
	emitter.sensors.append(_radar(30.0))
	emitter.radar_on = true
	var by_radar := Detection.best_radar_range_nm(listener, emitter.spec.signature_factor, emitter.spec.mast_height_m)
	var by_esm: float = Detection.best_esm(listener, emitter)["range_nm"]
	assert_true(by_esm > by_radar * 2.0, "switching on gives away a ship radar could barely see")


func test_esm_needs_the_emitter_in_line_of_sight() -> void:
	var listener := _unit(_spec(), "BLUE", Vector2.ZERO)
	listener.sensors.append(_esm(20.0))  # absurd gain, to prove the horizon still binds
	var emitter := _unit(_spec(), "RED", Vector2(0.0, 200.0))
	emitter.sensors.append(_radar())
	emitter.radar_on = true
	var reach: float = Detection.best_esm(listener, emitter)["range_nm"]
	assert_true(reach < 30.0, "two ships cannot hear each other over the curve of the earth")


func test_altitude_turns_esm_into_a_very_long_ear() -> void:
	var air_spec := _spec("air")
	air_spec.cruise_altitude_m = 8000.0
	air_spec.max_altitude_m = 12000.0
	air_spec.altitude_rate_m_s = 15.0
	air_spec.endurance_s = 14400.0
	var patrol := _unit(air_spec, "BLUE", Vector2.ZERO)
	patrol.flight_state = Unit.FlightState.AIRBORNE
	patrol.altitude_m = 8000.0
	patrol.sensors.append(_esm(2.2, 3.0))
	var ship := _unit(_spec(), "RED", Vector2(0.0, 60.0))
	ship.sensors.append(_radar(40.0))
	ship.radar_on = true
	var from_air: float = Detection.best_esm(patrol, ship)["range_nm"]
	var from_deck := _unit(_spec(), "BLUE", Vector2.ZERO)
	from_deck.sensors.append(_esm(2.2, 26.0))
	var deck_reach: float = Detection.best_esm(from_deck, ship)["range_nm"]
	assert_true(from_air > deck_reach * 2.5, "height is what makes an ESM aircraft worth having")


func _esm_harness(listener: Unit, emitter: Unit) -> Array:
	var um := UnitManager.new()
	um.add_unit(listener)
	um.add_unit(emitter)
	var tm := TrackManager.new()
	var sm := SensorManager.new()
	sm.unit_manager = um
	sm.track_manager = tm
	sm.rng.seed = 6
	return [um, tm, sm]


func test_an_esm_contact_is_a_bearing_not_a_position() -> void:
	var listener := _unit(_spec(), "BLUE", Vector2.ZERO)
	listener.sensors.append(_esm())
	listener.radar_on = false
	var emitter := _unit(_spec(), "RED", Vector2(0.0, 14.0))
	emitter.sensors.append(_radar())
	emitter.radar_on = true
	var h := _esm_harness(listener, emitter)
	for i in 6:
		h[2].run_cycle(float(i + 1))
	var t: Track = h[1].get_tracks("BLUE")[0]
	assert_eq(t.source, "esm")
	assert_true(t.bearing_only, "a bearing, with a guess at range")
	assert_true(t.error_major_nm > t.error_minor_nm * 3.0, "uncertainty runs down the bearing")
	assert_near(absf(Geo.heading_delta(t.error_axis_deg, 0.0)), 0.0, 8.0, "and the bearing is good")
	h[2].free()
	h[1].free()
	h[0].free()


# --- Datalink ----------------------------------------------------------------------------

func test_a_submerged_boat_is_off_the_network() -> void:
	var boat := _unit(_spec("subsurface"), "BLUE", Vector2.ZERO)
	boat.depth_m = 90.0
	assert_true(not boat.datalink_connected(), "no aerial out of the water")
	boat.depth_m = 10.0
	assert_true(boat.datalink_connected(), "at periscope depth it can take the picture")


func test_a_contact_found_by_a_linked_unit_reaches_everyone_linked() -> void:
	var finder := _unit(_spec(), "BLUE", Vector2.ZERO)
	var consort := _unit(_spec(), "BLUE", Vector2(0.0, 30.0))
	var target := _unit(_spec(), "RED", Vector2(0.0, 5.0))
	var tm := TrackManager.new()
	var c := SensorContact.make(target, target.position, 0.5, 0.8, 1.0, 5.0, "radar", finder)
	tm.observe_contact("BLUE", c, 1.0, 1.0)
	var t: Track = tm.get_tracks("BLUE")[0]
	assert_true(t.networked)
	assert_true(t.visible_to(finder), "the ship that found it knows about it")
	assert_true(t.visible_to(consort), "and so does everyone else on the link")
	assert_eq(tm.tracks_for(consort).size(), 1)
	tm.free()


func test_a_contact_found_off_the_link_stays_with_the_finder() -> void:
	var boat := _unit(_spec("subsurface"), "BLUE", Vector2.ZERO)
	boat.depth_m = 120.0  # deep, and therefore alone
	var consort := _unit(_spec(), "BLUE", Vector2(0.0, 30.0))
	var target := _unit(_spec(), "RED", Vector2(0.0, 5.0))
	var tm := TrackManager.new()
	var c := SensorContact.make(target, target.position, 0.5, 0.8, 1.0, 5.0, "sonar_passive", boat)
	tm.observe_contact("BLUE", c, 1.0, 1.0)
	var t: Track = tm.get_tracks("BLUE")[0]
	assert_true(not t.networked, "nothing was relayed")
	assert_true(t.visible_to(boat), "the boat knows what it heard")
	assert_true(not t.visible_to(consort), "the ship thirty miles away does not")
	assert_eq(tm.tracks_for(consort).size(), 0)
	tm.free()


func test_a_sonobuoy_report_is_always_relayed() -> void:
	var consort := _unit(_spec(), "BLUE", Vector2.ZERO)
	var target := _unit(_spec("subsurface"), "RED", Vector2(0.0, 5.0))
	var tm := TrackManager.new()
	var c := SensorContact.make(target, target.position, 1.0, 0.5, 0.8, 5.0, "sonobuoy", null)
	tm.observe_contact("BLUE", c, 1.0, 1.0)
	var t: Track = tm.get_tracks("BLUE")[0]
	assert_true(t.networked, "a buoy reports over the link by definition")
	assert_true(t.visible_to(consort))
	tm.free()


# --- Rules of engagement -----------------------------------------------------------------

func _armed(faction: String, pos: Vector2) -> Unit:
	var u := _unit(_spec(), faction, pos)
	var w := WeaponSpec.new()
	w.id = "test_asm"
	w.type = "asm"
	w.target_types = PackedStringArray(["surface"])
	w.max_range_nm = 60.0
	w.min_range_nm = 2.0
	w.speed_kn = 480.0
	w.base_pk = 0.8
	u.weapons.append(w)
	u.magazines[w.id] = 8
	return u


func _hostile_track(target: Unit) -> Track:
	var t := Track.new()
	t.id = "T1"
	t.truth = target
	t.position = target.position
	t.status = Track.Status.ACTIVE
	t.identity = "HOSTILE"
	t.classification = Track.Classification.CLASS_KNOWN
	t.domain = target.spec.domain
	return t


func test_weapons_hold_refuses_the_shot() -> void:
	var shooter := _armed("BLUE", Vector2.ZERO)
	var target := _unit(_spec(), "RED", Vector2(0.0, 20.0))
	var t := _hostile_track(target)
	var spec := shooter.weapons[0]
	assert_true(Combat.check_engagement(shooter, spec, t)["ok"], "weapons free by default")
	shooter.apply_order(Order.set_roe(Unit.Roe.HOLD))
	assert_eq(Combat.check_engagement(shooter, spec, t)["reason"], "WEAPONS HOLD")
	shooter.apply_order(Order.set_roe(Unit.Roe.FREE))
	assert_true(Combat.check_engagement(shooter, spec, t)["ok"], "and free again when told")


func test_weapons_tight_stops_the_ai_starting_something() -> void:
	var um := UnitManager.new()
	var shooter := _armed("RED", Vector2.ZERO)
	var target := _unit(_spec(), "BLUE", Vector2(0.0, 20.0))
	um.add_unit(shooter)
	um.add_unit(target)
	var tm := TrackManager.new()
	tm.observe_contact("RED", SensorContact.make(target, target.position, 0.5, 0.9, 1.0, 20.0, "radar", shooter), 0.0, 1.0)
	var track: Track = tm.get_tracks("RED")[0]
	track.identity = "HOSTILE"
	track.classification = Track.Classification.CLASS_KNOWN
	track.domain = "surface"
	var ai := AIController.new()
	ai.faction = "RED"
	ai.unit_manager = um
	ai.track_manager = tm
	ai.weapon_manager = WeaponManager.new()
	ai.weapon_manager.unit_manager = um
	var orders: Array = []
	um.order_issued.connect(func(_u: Unit, o: Order) -> void: orders.append(o.type))
	shooter.roe = Unit.Roe.TIGHT
	ai.tick(10.0)
	assert_true(not orders.has(Order.Type.ENGAGE), "tight means it will not open fire on its own")
	orders.clear()
	shooter.roe = Unit.Roe.FREE
	ai.tick(20.0)
	assert_true(orders.has(Order.Type.ENGAGE), "free means it will")
	ai.weapon_manager.free()
	ai.free()
	tm.free()
	um.free()


func test_emcon_silent_shuts_everything_down() -> void:
	var u := _unit(_spec(), "BLUE", Vector2.ZERO)
	u.sensors.append(_radar())
	u.radar_on = true
	u.active_sonar_on = true
	u.apply_order(Order.set_emcon(true))
	assert_eq(u.emcon, Unit.Emcon.SILENT)
	assert_true(not u.radar_on and not u.active_sonar_on, "one order covers every transmitter")
	u.apply_order(Order.set_emcon(false))
	assert_true(u.radar_on, "and switches back on")


# --- Component damage --------------------------------------------------------------------

func test_damage_can_knock_out_a_subsystem() -> void:
	Damage.rng.seed = 3
	var u := _unit(_spec(), "BLUE", Vector2.ZERO, 30.0)
	assert_near(u.effective_max_speed(), 30.0, 1e-4, "undamaged, full speed")
	var hits := 0
	while hits < 40:
		u.health = u.spec.health  # kept afloat, so this isolates the subsystem roll from the hull
		Damage.apply(u, 12.0)
		hits += 1
		if Damage.damage_report(u) != "all systems":
			break
	assert_true(Damage.damage_report(u) != "all systems", "sustained hits eventually break something")


func test_a_damaged_plant_will_not_make_full_speed() -> void:
	var u := _unit(_spec(), "BLUE", Vector2.ZERO, 30.0)
	u.components["propulsion"] = 0.4
	var capped := u.effective_max_speed()
	assert_true(capped < 30.0 and capped > 0.0, "slower, but still under way")
	u.apply_order(Order.set_speed(30.0))
	assert_near(u.ordered_speed_kn, capped, 1e-4, "an order for full speed only gets what is left")
	u.speed_kn = 30.0
	Movement.step(u, DT)
	assert_true(u.speed_kn < 30.0, "and it slows down to it")


func test_damaged_arrays_shorten_every_sensor() -> void:
	var healthy := _unit(_spec(), "BLUE", Vector2.ZERO)
	healthy.sensors.append(_radar())
	var hurt := _unit(_spec(), "BLUE", Vector2.ZERO)
	hurt.sensors.append(_radar())
	hurt.components["sensors"] = 0.3
	assert_true(Detection.best_radar_range_nm(hurt, 1.0, 25.0) < Detection.best_radar_range_nm(healthy, 1.0, 25.0) * 0.8,
		"a wrecked array does not see as far")


func test_wrecked_launchers_cannot_fire() -> void:
	var shooter := _armed("BLUE", Vector2.ZERO)
	var target := _unit(_spec(), "RED", Vector2(0.0, 20.0))
	var t := _hostile_track(target)
	shooter.components["weapons"] = 0.1
	assert_true(not shooter.can_fire())
	assert_eq(Combat.check_engagement(shooter, shooter.weapons[0], t)["reason"], "LAUNCHERS DAMAGED")


# --- Formation ---------------------------------------------------------------------------

func test_station_is_computed_in_the_leaders_frame() -> void:
	var leader := _unit(_spec(), "BLUE", Vector2.ZERO)
	leader.heading_deg = 0.0  # due north
	var consort := _unit(_spec(), "BLUE", Vector2(20.0, 20.0))
	consort.formation_leader = leader
	consort.formation_offset = Vector2(3.0, 5.0)  # three to starboard, five ahead
	var station := Formation.station_for(consort)
	assert_near(station.x, 3.0, 0.01, "starboard is east when heading north")
	assert_near(station.y, 5.0, 0.01, "ahead is north")
	leader.heading_deg = 90.0  # now heading east
	station = Formation.station_for(consort)
	assert_near(station.x, 5.0, 0.01, "ahead is now east")
	assert_near(station.y, -3.0, 0.01, "and starboard is south")


func test_a_consort_closes_on_its_station() -> void:
	var leader := _unit(_spec(), "BLUE", Vector2.ZERO, 15.0)
	leader.heading_deg = 0.0
	leader.ordered_heading_deg = 0.0
	var consort := _unit(_spec(), "BLUE", Vector2(6.0, -6.0), 15.0)
	consort.heading_deg = 0.0
	consort.apply_order(Order.form_up(leader, Vector2(3.0, 0.0)))
	var start := consort.position.distance_to(Formation.station_for(consort))
	for i in int(5400.0 / DT):
		Formation.step(leader)
		Movement.step(leader, DT)
		Formation.step(consort)
		Movement.step(consort, DT)
	var finish := consort.position.distance_to(Formation.station_for(consort))
	assert_true(finish < start * 0.2, "it takes station and keeps it")
	assert_true(finish < 1.0, "within a mile of where it should be")


func test_breaking_formation_returns_control() -> void:
	var leader := _unit(_spec(), "BLUE", Vector2.ZERO)
	var consort := _unit(_spec(), "BLUE", Vector2(5.0, 0.0))
	consort.apply_order(Order.form_up(leader, Vector2(3.0, 0.0)))
	assert_true(consort.in_formation())
	consort.apply_order(Order.break_formation())
	assert_true(not consort.in_formation(), "it steers for itself again")


func test_a_pattern_assigns_a_station_to_every_consort() -> void:
	var a := _unit(_spec(), "BLUE", Vector2.ZERO)
	var b := _unit(_spec(), "BLUE", Vector2(1.0, 0.0))
	var c := _unit(_spec(), "BLUE", Vector2(2.0, 0.0))
	var orders := Formation.assign([a, b, c], "screen")
	assert_eq(orders.size(), 2, "the leader does not take station on itself")
	for entry: Dictionary in orders:
		assert_eq(entry["order"].leader, a)
		assert_true(entry["order"].offset_nm != Vector2.ZERO)
	assert_true(orders[0]["order"].offset_nm != orders[1]["order"].offset_nm, "and they do not stack up")
	assert_true(Formation.assign([a], "screen").is_empty(), "one ship is not a formation")


# --- Shipped data ------------------------------------------------------------------------

func test_shipped_esm_data_loads_and_is_fitted() -> void:
	for sid in ["an_slq_32", "an_alq_240", "mp_405", "nato_esm_suite"]:
		var s := DataDB.sensor(sid)
		assert_true(s != null, "%s loads" % sid)
		if s != null:
			assert_eq(s.kind, "esm")
			assert_true(s.esm_gain > 1.0, "%s hears further than the radar reaches" % sid)
	for pid in ["usn_ddg_arleigh_burke_iia", "rnon_ffg_fridtjof_nansen", "rfn_ffg_admiral_gorshkov", "usn_mpa_p8a"]:
		var p := DataDB.platform(pid)
		assert_true(p != null)
		if p == null:
			continue
		var has_esm := false
		for sid in p.sensor_ids:
			var s := DataDB.sensor(sid)
			if s != null and s.kind == "esm":
				has_esm = true
		assert_true(has_esm, "%s carries electronic support" % pid)


func test_civil_traffic_is_not_on_a_military_network() -> void:
	var merchant := DataDB.platform("civ_merchant_bulk")
	assert_true(merchant != null)
	if merchant != null:
		assert_true(not merchant.has_datalink, "a bulk carrier is not on the link")
	var burke := DataDB.platform("usn_ddg_arleigh_burke_iia")
	if burke != null:
		assert_true(burke.has_datalink, "a warship is")
