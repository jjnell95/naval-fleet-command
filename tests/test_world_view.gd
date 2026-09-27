extends TestCase
## The world view's rules: what may be shown, where and as what; the solar model; and the axis
## conventions. All headless over hand-built managers, with no viewport anywhere.

const ENV := {"visibility_nm": 10.0}


func _unit(pid: String, faction: String, pos: Vector2, callsign := "") -> Unit:
	var spec := DataDB.platform(pid)
	var u := Unit.new()
	u.spec = spec
	u.faction = faction
	u.callsign = callsign if callsign != "" else "%s %s" % [faction, pid]
	u.position = pos
	u.health = spec.health
	for sid in spec.sensor_ids:
		var s := DataDB.sensor(sid)
		if s != null:
			u.sensors.append(s)
	return u


func _managers(units: Array) -> Dictionary:
	var um := UnitManager.new()
	for u in units:
		um.add_unit(u)
	return {"um": um, "tm": TrackManager.new()}


func _free_all(m: Dictionary) -> void:
	m["um"].free()
	m["tm"].free()


func _hold(tm: TrackManager, id: String, truth: Unit, position: Vector2, classification: int, domain := "surface") -> Track:
	var t := Track.new()
	t.id = id
	t.owner_faction = "BLUE"
	t.truth = truth
	t.position = position
	t.status = Track.Status.ACTIVE
	t.classification = classification as Track.Classification
	t.domain = domain
	t.identity = "HOSTILE"
	if classification >= Track.Classification.CLASS_KNOWN:
		t.known_class = truth.spec.short_name
	var list: Array = tm._tracks.get("BLUE", [])
	list.append(t)
	tm._tracks["BLUE"] = list
	return t


func _find(entries: Array, key: String) -> Dictionary:
	for e in entries:
		if e["key"] == key:
			return e
	return {}


func _unix(text: String) -> float:
	return float(Time.get_unix_time_from_datetime_string(text))


# --- Sun ---------------------------------------------------------------------------------

func test_sun_is_up_and_south_at_noon_in_march_at_sixty_north() -> void:
	var a := WorldPresentation.sun_angles(_unix("1990-03-21T12:00:00"), 60.0, 0.0)
	assert_true(a.x > 24.0 and a.x < 36.0, "equinox noon at 60N is about 30 degrees up, got %.1f" % a.x)
	assert_true(absf(a.y - 180.0) < 12.0, "the noon sun bears roughly south, got %.1f" % a.y)
	var d := WorldPresentation.sun_direction(_unix("1990-03-21T12:00:00"), 60.0, 0.0)
	assert_true(d.y > 0.4, "the direction toward the sun points up")
	assert_true(d.z > 0.5, "south is +Z, so the noon sun lies toward +Z")
	assert_true(absf(d.x) < 0.25, "and hardly east or west")


func test_sun_is_below_the_horizon_at_local_midnight() -> void:
	var a := WorldPresentation.sun_angles(_unix("1990-03-21T00:00:00"), 60.0, 0.0)
	assert_true(a.x < -20.0, "equinox midnight at 60N is well below the horizon, got %.1f" % a.x)
	assert_true(WorldPresentation.sun_direction(_unix("1990-03-21T00:00:00"), 60.0, 0.0).y < 0.0)


func test_sun_follows_longitude() -> void:
	var east := WorldPresentation.sun_angles(_unix("1990-03-21T06:00:00"), 60.0, 90.0).x
	var prime := WorldPresentation.sun_angles(_unix("1990-03-21T06:00:00"), 60.0, 0.0).x
	assert_true(east > 24.0, "06:00Z is local noon at 90E, got %.1f" % east)
	assert_true(prime < 6.0, "and only dawn on the meridian, got %.1f" % prime)


func test_midnight_sun_stands_north() -> void:
	var a := WorldPresentation.sun_angles(_unix("1990-06-21T00:00:00"), 78.0, 0.0)
	assert_true(a.x > 5.0, "June midnight at 78N is still daylight, got %.1f" % a.x)
	assert_true(minf(a.y, 360.0 - a.y) < 15.0, "and the sun stands to the north, got %.1f" % a.y)


# --- What may be shown -------------------------------------------------------------------

func test_own_units_are_always_present() -> void:
	var ship := _unit("cw90_ticonderoga", "BLUE", Vector2.ZERO)
	var jet := _unit("cw90_f14a", "BLUE", Vector2(30, 5))
	jet.flight_state = Unit.FlightState.AIRBORNE
	jet.altitude_m = 6000.0
	var boat := _unit("cw90_los_angeles", "BLUE", Vector2(-20, 0))
	boat.depth_m = 150.0
	var stowed := _unit("cw90_f14a", "BLUE", Vector2.ZERO)
	var m := _managers([ship, jet, boat, stowed])
	var entries := WorldPresentation.unit_entries(m["um"], m["tm"], "BLUE", ENV)
	assert_eq(entries.size(), 3, "every engageable own unit and nothing else")
	for e in entries:
		assert_eq(e["kind"], "own")
	assert_eq(_find(entries, "u:%d" % jet.id)["height_m"], 6000.0, "aircraft fly at their altitude")
	assert_eq(_find(entries, "u:%d" % boat.id)["height_m"], -150.0, "boats sit at minus their depth")
	assert_eq(_find(entries, "u:%d" % ship.id)["model"], "cw90_ticonderoga")
	assert_true(_find(entries, "u:%d" % stowed.id).is_empty(), "an airframe in the hangar is not on the board")
	_free_all(m)


func test_hostile_beyond_visual_range_without_a_track_is_absent() -> void:
	var own := _unit("cw90_ticonderoga", "BLUE", Vector2.ZERO)
	var red := _unit("cw90_slava", "RED", Vector2(40, 0))
	var m := _managers([own, red])
	var entries := WorldPresentation.unit_entries(m["um"], m["tm"], "BLUE", ENV)
	assert_eq(entries.size(), 1, "the enemy is neither seen nor plotted")
	assert_eq(entries[0]["key"], "u:%d" % own.id)
	_free_all(m)


func test_bearing_only_track_is_absent() -> void:
	var own := _unit("cw90_ticonderoga", "BLUE", Vector2.ZERO)
	var red := _unit("cw90_slava", "RED", Vector2(40, 0))
	var m := _managers([own, red])
	var t := _hold(m["tm"], "T1001", red, Vector2(38, 2), Track.Classification.SURFACE)
	t.bearing_only = true
	t.tma_quality = 0.2
	var entries := WorldPresentation.unit_entries(m["um"], m["tm"], "BLUE", ENV)
	assert_eq(entries.size(), 1, "a bearing has no range to put a contact at")
	t.tma_quality = 0.9
	entries = WorldPresentation.unit_entries(m["um"], m["tm"], "BLUE", ENV)
	assert_eq(entries.size(), 2, "a bearing with a range solution is plotted")
	_free_all(m)


func test_firm_track_is_a_generic_marker_at_the_plot_not_the_truth() -> void:
	var own := _unit("cw90_ticonderoga", "BLUE", Vector2.ZERO)
	var red := _unit("cw90_slava", "RED", Vector2(40, 0))
	red.heading_deg = 225.0
	var m := _managers([own, red])
	var t := _hold(m["tm"], "T1001", red, Vector2(38, 2), Track.Classification.SURFACE)
	var entries := WorldPresentation.unit_entries(m["um"], m["tm"], "BLUE", ENV)
	var e := _find(entries, "t:T1001")
	assert_true(not e.is_empty(), "an active firm track is shown")
	assert_eq(e["kind"], "plotted")
	assert_eq(e["model"], "", "below CLASS_KNOWN there is no class geometry")
	assert_eq(e["position"], t.position, "the contact stands where the plot says")
	assert_true(e["position"] != red.position, "and not where the enemy really is")
	assert_true(not e["has_heading"], "no kinematics, no heading")
	assert_eq(e["color"], TacticalMap.COL_HOSTILE)
	assert_eq(e["label"], "T1001")
	assert_eq(e["sublabel"], "SURFACE CONTACT")
	t.has_kinematics = true
	t.course_deg = 100.0
	e = _find(WorldPresentation.unit_entries(m["um"], m["tm"], "BLUE", ENV), "t:T1001")
	assert_true(e["has_heading"])
	assert_eq(e["heading_deg"], 100.0, "the estimated course, never the true heading")
	_free_all(m)


func test_class_known_track_carries_the_class_model() -> void:
	var own := _unit("cw90_ticonderoga", "BLUE", Vector2.ZERO)
	var red := _unit("cw90_slava", "RED", Vector2(40, 0))
	var m := _managers([own, red])
	var t := _hold(m["tm"], "T1001", red, Vector2(38, 2), Track.Classification.CLASS_KNOWN)
	var e := _find(WorldPresentation.unit_entries(m["um"], m["tm"], "BLUE", ENV), "t:T1001")
	assert_eq(e["model"], "cw90_slava", "a known class is drawn as its class")
	assert_eq(e["position"], t.position, "still at the plotted position")
	assert_eq(e["length_m"], red.spec.length_m)
	_free_all(m)


func test_unit_inside_visual_range_is_shown_as_truth_once() -> void:
	var own := _unit("cw90_ticonderoga", "BLUE", Vector2.ZERO)
	var red := _unit("cw90_slava", "RED", Vector2(5, 0))
	red.heading_deg = 300.0
	var m := _managers([own, red])
	var entries := WorldPresentation.unit_entries(m["um"], m["tm"], "BLUE", ENV)
	var e := _find(entries, "u:%d" % red.id)
	assert_eq(e["kind"], "visual")
	assert_eq(e["model"], "cw90_slava")
	assert_eq(e["position"], red.position)
	assert_eq(e["heading_deg"], 300.0)
	assert_eq(e["label"], "SIGHTED", "eyes give no callsign")
	_hold(m["tm"], "T1001", red, Vector2(5.5, 0.5), Track.Classification.SURFACE)
	entries = WorldPresentation.unit_entries(m["um"], m["tm"], "BLUE", ENV)
	assert_eq(entries.size(), 2, "a sighted unit that is also plotted is shown once")
	assert_true(_find(entries, "t:T1001").is_empty(), "as what it is, not as its plot")
	assert_eq(_find(entries, "u:%d" % red.id)["label"], "T1001", "labelled with what the plot knows")
	_free_all(m)


func test_visual_range_is_the_lesser_of_weather_and_horizon() -> void:
	var own := _unit("cw90_ticonderoga", "BLUE", Vector2.ZERO)
	var red := _unit("cw90_slava", "RED", Vector2(8, 0))
	assert_near(WorldPresentation.visual_range_nm(own, red, {"visibility_nm": 3.0}), 3.0, 0.001, "thick weather caps the range")
	assert_near(WorldPresentation.visual_range_nm(own, red, {"visibility_nm": 100.0}), Detection.radar_horizon_nm(27.0, 27.0), 0.001, "clear weather leaves the horizon")
	assert_near(WorldPresentation.visual_range_nm(own, red, {}), 10.0, 0.001, "the default visibility is 10 nm")
	var m := _managers([own, red])
	assert_eq(WorldPresentation.unit_entries(m["um"], m["tm"], "BLUE", {"visibility_nm": 3.0}).size(), 1, "8 nm away in 3 nm visibility is unseen")
	assert_eq(WorldPresentation.unit_entries(m["um"], m["tm"], "BLUE", ENV).size(), 2, "and seen in 10")
	_free_all(m)


func test_submerged_hostile_two_miles_away_is_absent() -> void:
	var own := _unit("cw90_ticonderoga", "BLUE", Vector2.ZERO)
	var boat := _unit("cw90_victor3", "RED", Vector2(2, 0))
	boat.depth_m = 100.0
	var m := _managers([own, boat])
	assert_eq(WorldPresentation.unit_entries(m["um"], m["tm"], "BLUE", ENV).size(), 1, "nothing to see under the water")
	boat.depth_m = 0.0
	assert_eq(WorldPresentation.unit_entries(m["um"], m["tm"], "BLUE", ENV).size(), 2, "surfaced, it is a ship like any other")
	_free_all(m)


func test_weapons_follow_the_threat_picture() -> void:
	var own := _unit("cw90_ticonderoga", "BLUE", Vector2.ZERO)
	var red := _unit("cw90_slava", "RED", Vector2(60, 0))
	var wm := WeaponManager.new()
	var thm := ThreatManager.new()
	var ours := Weapon.new()
	ours.id = 1
	ours.spec = DataDB.weapon("cw90_harpoon")
	ours.faction = "BLUE"
	ours.shooter = own
	ours.position = Vector2(10, 0)
	wm.in_flight.append(ours)
	var theirs := Weapon.new()
	theirs.id = 2
	theirs.spec = DataDB.weapon("cw90_kh22")
	theirs.faction = "RED"
	theirs.shooter = red
	theirs.position = Vector2(20, 0)
	wm.in_flight.append(theirs)
	var entries := WorldPresentation.weapon_entries(wm, thm, "BLUE", own)
	assert_eq(entries.size(), 1, "an undetected hostile round is invisible")
	assert_eq(entries[0]["key"], "w:1")
	assert_true(entries[0]["own"])
	assert_eq(entries[0]["height_m"], 10.0, "a sea-skimmer at its cruise altitude")
	thm.mark_detected("BLUE", theirs, 10.0, own)
	entries = WorldPresentation.weapon_entries(wm, thm, "BLUE", own)
	assert_eq(entries.size(), 2, "detected, it appears")
	var seen := _find(entries, "w:2")
	assert_eq(seen["color"], TacticalMap.COL_MISSILE_HOSTILE)
	assert_eq(seen["height_m"], 12000.0)
	assert_eq(WorldPresentation.weapon_entries(wm, thm, "BLUE", null).size(), 1, "with no reference unit only our own rounds show")
	wm.free()
	thm.free()


func test_weapon_heights() -> void:
	var torpedo := Weapon.new()
	torpedo.spec = DataDB.weapon("cw90_mk46")
	assert_eq(WorldPresentation.weapon_height_m(torpedo), -WorldPresentation.TORPEDO_DEPTH_M, "a torpedo runs a few metres down")
	assert_near(WorldPresentation.ballistic_height_m(0.0, 200.0), 0.0, 0.001)
	assert_true(WorldPresentation.ballistic_height_m(100.0, 200.0) > WorldPresentation.ballistic_height_m(50.0, 200.0), "a ballistic round climbs to mid-course")
	assert_true(WorldPresentation.ballistic_height_m(150.0, 200.0) < WorldPresentation.ballistic_height_m(100.0, 200.0), "and comes down again")
	var threat := Weapon.new()
	threat.spec = DataDB.weapon("cw90_kh22")
	var sam := Weapon.new()
	sam.spec = DataDB.weapon("cw90_sm2mr")
	sam.intercept_target = threat
	sam.time_alive_s = 0.0
	var low := WorldPresentation.weapon_height_m(sam)
	sam.time_alive_s = WorldPresentation.INTERCEPTOR_CLIMB_S
	assert_true(WorldPresentation.weapon_height_m(sam) > low, "an interceptor climbs toward what it chases")
	assert_near(WorldPresentation.weapon_height_m(sam), 12000.0, 0.001)


# --- Focus, culling, axes ----------------------------------------------------------------

func test_focus_prefers_hooked_unit_then_hooked_contact_then_force_centre() -> void:
	var ship := _unit("cw90_ticonderoga", "BLUE", Vector2(3, 4))
	var escort := _unit("cw90_ticonderoga", "BLUE", Vector2(7, 4))
	var jet := _unit("cw90_f14a", "BLUE", Vector2(30, 5))
	jet.flight_state = Unit.FlightState.AIRBORNE
	var stowed := _unit("cw90_f14a", "BLUE", Vector2(3, 4))
	stowed.home = ship
	var m := _managers([jet, ship, escort, stowed])
	var red := _unit("cw90_slava", "RED", Vector2(40, 0))
	var t := _hold(m["tm"], "T1001", red, Vector2(38, 2), Track.Classification.SURFACE)
	var own: Array = m["um"].get_faction_units("BLUE")
	assert_eq(WorldPresentation.choose_focus([jet], t, own)["key"], "u:%d" % jet.id, "the hooked own unit wins")
	assert_eq(WorldPresentation.choose_focus([stowed], t, own)["key"], "u:%d" % ship.id, "a deck-bound airframe stands for its ship")
	var hooked := WorldPresentation.choose_focus([], t, own)
	assert_eq(hooked["key"], "t:T1001", "then the hooked contact")
	assert_eq(hooked["position"], t.position, "where the plot holds it")
	var force := WorldPresentation.choose_focus([], null, own)
	assert_eq(force["key"], "force", "with nothing hooked, the force centre")
	assert_eq(force["position"], Vector2(5, 4), "the centre of the ships, not pulled out by the aircraft")
	assert_true(float(force["length_m"]) >= WorldPresentation.FORCE_MIN_FRAME_M, "framed to take in the group")
	t.bearing_only = true
	assert_eq(WorldPresentation.choose_focus([], t, own)["key"], "force", "a bearing cannot be looked at")
	assert_true(WorldPresentation.choose_focus([], null, []).is_empty())
	_free_all(m)


func test_force_centre_reads_only_own_units_and_falls_back_to_aircraft() -> void:
	var jet := _unit("cw90_f14a", "BLUE", Vector2(30, 10))
	jet.flight_state = Unit.FlightState.AIRBORNE
	jet.heading_deg = 90.0
	jet.speed_kn = 400.0
	var force := WorldPresentation.force_focus([jet])
	assert_eq(force["position"], Vector2(30, 10), "only aircraft left: they are the force")
	assert_near(float(force["heading_deg"]), 90.0, 0.01, "facing the way they fly")
	var dead := _unit("cw90_ticonderoga", "BLUE", Vector2(-50, -50))
	dead.alive = false
	force = WorldPresentation.force_focus([jet, dead])
	assert_eq(force["position"], Vector2(30, 10), "a sunk ship is not part of the force")
	var far := _unit("cw90_ticonderoga", "BLUE", Vector2(0, 0))
	var near := _unit("cw90_ticonderoga", "BLUE", Vector2(40, 0))
	force = WorldPresentation.force_focus([far, near])
	assert_near(float(force["length_m"]), clampf(20.0 * WorldPresentation.NM_TO_M * 0.7, WorldPresentation.FORCE_MIN_FRAME_M, WorldPresentation.FORCE_MAX_FRAME_M), 0.01, "a spread group is framed by its spread")


func test_hooked_contact_in_sight_is_followed_as_the_sighted_unit() -> void:
	var own := _unit("cw90_ticonderoga", "BLUE", Vector2.ZERO)
	var red := _unit("cw90_slava", "RED", Vector2(5, 0))
	var m := _managers([own, red])
	var t := _hold(m["tm"], "T1001", red, Vector2(5.5, 0.5), Track.Classification.SURFACE)
	var entries := WorldPresentation.unit_entries(m["um"], m["tm"], "BLUE", ENV)
	var focus := WorldPresentation.choose_focus([], t, [own])
	assert_eq(WorldPresentation.resolve_focus_key(entries, focus), "u:%d" % red.id, "drawn once, as the ship a lookout sees, so followed as that")
	red.position = Vector2(30, 0)
	entries = WorldPresentation.unit_entries(m["um"], m["tm"], "BLUE", ENV)
	assert_eq(WorldPresentation.resolve_focus_key(entries, focus), "t:T1001", "out of sight it is the plotted contact again")
	assert_eq(WorldPresentation.resolve_focus_key(entries, WorldPresentation.choose_focus([own], null, [own])), "u:%d" % own.id, "an own unit is itself")
	_free_all(m)


func test_events_are_drawn_only_where_the_player_could_witness_them() -> void:
	var own := _unit("cw90_ticonderoga", "BLUE", Vector2.ZERO)
	var red := _unit("cw90_slava", "RED", Vector2(40, 0))
	var m := _managers([own, red])
	assert_eq(WorldPresentation.witness_point(Vector2(6, 0), [own], [], ENV), Vector2(6, 0), "inside visibility of one of ours: seen where it happens")
	assert_eq(WorldPresentation.witness_point(Vector2(40, 0), [own], [], ENV), Vector2.INF, "far off and not on the plot: not drawn at all")
	var t := _hold(m["tm"], "T1001", red, Vector2(39.4, 0.6), Track.Classification.SURFACE)
	t.position_error_nm = 0.5
	var tracks: Array = m["tm"].get_tracks("BLUE")
	assert_eq(WorldPresentation.witness_point(Vector2(40, 0), [own], tracks, ENV), t.position, "a hit on a held contact is drawn where the plot has it, not at the truth")
	t.bearing_only = true
	t.tma_quality = 0.1
	assert_eq(WorldPresentation.witness_point(Vector2(40, 0), [own], tracks, ENV), Vector2.INF, "a bearing is not a place")
	_free_all(m)


func test_gun_rounds_are_flagged_and_drawn_as_tracers() -> void:
	var own := _unit("cw90_ticonderoga", "BLUE", Vector2.ZERO)
	var wm := WeaponManager.new()
	var shell := Weapon.new()
	shell.id = 3
	shell.spec = DataDB.weapon("cw90_mk45")
	shell.faction = "BLUE"
	shell.shooter = own
	shell.position = Vector2(1, 0)
	wm.in_flight.append(shell)
	var missile := Weapon.new()
	missile.id = 4
	missile.spec = DataDB.weapon("cw90_harpoon")
	missile.faction = "BLUE"
	missile.shooter = own
	missile.position = Vector2(2, 0)
	wm.in_flight.append(missile)
	var entries := WorldPresentation.weapon_entries(wm, null, "BLUE", own)
	assert_true(_find(entries, "w:3")["gun"], "a gun round is a gun round")
	assert_eq(_find(entries, "w:3")["length_m"], WorldPresentation.TRACER_LENGTH_M, "drawn as its tracer streak")
	assert_true(not _find(entries, "w:4")["gun"], "a missile is not")
	wm.free()


func test_cull_keeps_the_nearest_within_range_and_caps_the_count() -> void:
	var entries: Array = []
	for i in 70:
		entries.append({"key": "u:%d" % i, "position": Vector2(float(69 - i) * 0.5, 0.0)})
	entries.append({"key": "far", "position": Vector2(100, 0)})
	var kept := WorldPresentation.cull(entries, Vector2.ZERO, "far")
	assert_eq(kept.size(), WorldPresentation.MAX_ENTITIES, "capped at the entity budget")
	assert_eq(kept[0]["key"], "far", "the focus is kept even beyond the range, and first")
	var last := 0.0
	for e in kept.slice(1):
		var d: float = (e["position"] as Vector2).length()
		assert_true(d <= WorldPresentation.MAX_RANGE_NM, "everything else lies within 40 nm")
		assert_true(d >= last, "nearest first")
		last = d
	assert_eq(WorldPresentation.cull(entries, Vector2(200, 0), "").size(), 0, "nothing near a distant focus")


func test_heading_and_axis_conventions() -> void:
	var north := WorldPresentation.heading_vector(0.0)
	assert_near(north.z, -1.0, 1e-6, "north is -Z")
	assert_near(north.x, 0.0, 1e-6)
	var east := WorldPresentation.heading_vector(90.0)
	assert_near(east.x, 1.0, 1e-6, "east is +X")
	assert_near(east.z, 0.0, 1e-6)
	assert_near(WorldPresentation.heading_vector(180.0).z, 1.0, 1e-6, "south is +Z")
	assert_near(WorldPresentation.heading_vector(270.0).x, -1.0, 1e-6, "west is -X")
	for h in [0.0, 45.0, 90.0, 200.0, 315.0]:
		var bow := Basis(Vector3.UP, WorldPresentation.heading_to_yaw(h)).x
		var want := WorldPresentation.heading_vector(h)
		assert_near(bow.x, want.x, 1e-5, "a +X bow yawed for heading %d points down the heading" % int(h))
		assert_near(bow.z, want.z, 1e-5)
	var w := WorldPresentation.to_world(Vector2(1, 2), Vector2.ZERO, 30.0)
	assert_near(w.x, 1852.0, 1e-3, "one mile east is 1852 m of +X")
	assert_near(w.y, 30.0, 1e-6)
	assert_near(w.z, -3704.0, 1e-3, "two miles north is 3704 m of -Z")
	assert_eq(WorldPresentation.to_world(Vector2(5, 5), Vector2(5, 5), 0.0), Vector3.ZERO, "the focus sits at the origin")


func test_scale_and_waterline() -> void:
	assert_near(WorldPresentation.model_scale(332.8), 33.28, 1e-6, "a 333 m carrier scales a 10-unit model by 33.28")
	var lift := WorldPresentation.hull_lift_m(3.0, 10.0)
	var bottom := -1.5 * 10.0 + lift
	assert_near(bottom, -0.2 * 30.0, 1e-6, "a fifth of the hull's height sits below the waterline")
	var d := WorldPresentation.length_of(DataDB.platform("cw90_ticonderoga"))
	assert_near(d, 172.8, 1e-6)
	var spec := PlatformSpec.new()
	spec.domain = "air"
	assert_near(WorldPresentation.length_of(spec), 15.0, 1e-6, "an airframe with no length falls back to 15 m")


# --- Scene -------------------------------------------------------------------------------

func test_scene_pools_models_and_keeps_a_lost_hull_while_it_sinks() -> void:
	var scene := WorldScene.new()
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(scene)
	scene.build()
	var ship := _unit("cw90_ticonderoga", "BLUE", Vector2.ZERO)
	ship.id = 7
	ship.speed_kn = 18.0
	var own := WorldPresentation.own_entry(ship)
	scene.update(0.016, [own], own["key"])
	assert_true(scene._records.has("u:7"), "a shown unit has a record")
	assert_eq(scene._records["u:7"]["model_id"], "cw90_ticonderoga", "drawn as its class")
	assert_true(scene._records["u:7"]["wake"] != null, "a hull under way lays a wake from its first frame")
	assert_eq(scene.anchors().size(), 1, "and offers one label anchor")
	assert_true(not scene.focus_frame("u:7").is_empty())
	ship.alive = false
	scene.update(0.016, [], "")
	assert_true(scene._records.has("u:7"), "a hull that died on screen is kept while it sinks")
	assert_true(float(scene._records["u:7"]["dying_since"]) >= 0.0)
	assert_true(scene.anchors().is_empty(), "but no longer labelled")
	scene.anim += WorldPresentation.SINK_DURATION_S + 1.0
	scene.update(0.016, [], "")
	assert_true(not scene._records.has("u:7"), "and released once it has gone under")
	var t := Track.new()
	t.id = "T1"
	t.status = Track.Status.ACTIVE
	t.position = Vector2(10, 0)
	t.domain = "surface"
	t.identity = "HOSTILE"
	var plotted := WorldPresentation.plotted_entry(t)
	scene.update(0.016, [plotted], "")
	assert_eq(scene._records["t:T1"]["model_id"], "marker:surface", "an unclassified contact is a generic marker")
	assert_true(scene._records["t:T1"]["ring"] != null, "with a ring on the water")
	scene.update(0.016, [], "")
	assert_true(not scene._records.has("t:T1"), "a contact that drops off the plot goes at once")
	root.remove_child(scene)
	scene.free()


# --- Camera --------------------------------------------------------------------------------

func _frame(pos: Vector3, heading: float, length := 150.0, speed := 9.0) -> Dictionary:
	return {"position": pos, "length": length, "heading": heading, "domain": "surface", "speed_mps": speed}


func test_camera_modes_cycle_and_name_themselves() -> void:
	var cam := WorldCamera.new()
	assert_eq(cam.mode, WorldCamera.TETHER, "Tether is the default")
	var names: Array[String] = []
	for i in 5:
		names.append(cam.mode_name())
		cam.cycle_mode()
	assert_eq(names, ["Tether", "Fly-by", "Action", "Detached", "Tether"] as Array[String], "T cycles the four modes in order")
	cam.set_mode(99)
	assert_eq(cam.mode, WorldCamera.DETACHED, "out-of-range modes clamp")


func test_tether_sits_behind_and_above_and_keeps_the_players_orbit() -> void:
	var cam := WorldCamera.new()
	var ship := _frame(Vector3.ZERO, 0.0)
	var shot := cam.update(0.016, Vector2.ZERO, ship, Callable())
	var eye: Vector3 = shot["eye"]
	assert_true(shot["cut"], "the first shot is a cut")
	assert_true(eye.z > 0.0, "a ship heading north is watched from the south: astern")
	assert_true(eye.x < 0.0, "off the port quarter by default")
	assert_true(eye.y > 0.0, "and above the water")
	assert_near(eye.length(), WorldCamera.tether_distance(150.0, 1.0), 0.01, "at the tether range")
	assert_eq(shot["look"], Vector3.ZERO, "looking at the subject")
	cam.orbit(-100.0, 40.0)
	cam.zoom_by(2.0)
	var az := cam.orbit_az
	var pitch := cam.orbit_pitch
	cam.cut()
	shot = cam.update(0.016, Vector2.ZERO, _frame(Vector3(500, 0, 0), 90.0, 40.0), Callable())
	assert_eq(cam.orbit_az, az, "a new subject keeps the player's orbit")
	assert_eq(cam.orbit_pitch, pitch)
	assert_near((shot["eye"] - Vector3(500, 0, 0)).length(), WorldCamera.tether_distance(40.0, 2.0), 0.01, "and zoom, scaled to the new subject")
	cam.zoom_by(1000.0)
	assert_eq(cam.zoom, WorldCamera.MAX_ZOOM, "zoom is bounded")
	cam.orbit(0.0, 1.0e6)
	assert_eq(cam.orbit_pitch, WorldCamera.MAX_PITCH, "and so is pitch")


func test_tether_follows_a_turn_smoothly_not_in_one_jump() -> void:
	var cam := WorldCamera.new()
	cam.update(0.016, Vector2.ZERO, _frame(Vector3.ZERO, 0.0), Callable())
	var shot := cam.update(0.016, Vector2.ZERO, _frame(Vector3.ZERO, 90.0), Callable())
	var want := WorldCamera.orbit_offset(90.0 + WorldCamera.DEFAULT_AZ, WorldCamera.DEFAULT_PITCH, WorldCamera.tether_distance(150.0, 1.0))
	assert_true(not shot["cut"], "following is not a cut")
	assert_true((shot["eye"] as Vector3).distance_to(want) > 50.0, "one frame after a turn the camera has not snapped round")
	for i in 400:
		shot = cam.update(0.016, Vector2.ZERO, _frame(Vector3.ZERO, 90.0), Callable())
	assert_true((shot["eye"] as Vector3).distance_to(want) < 1.0, "a few seconds later it has swung astern again")


func test_flyby_waits_ahead_and_beside_then_moves_on_once_passed() -> void:
	var station := WorldCamera.flyby_station(Vector2.ZERO, 0.0, 10.0, 150.0, "surface")
	assert_true(station.y > 0.0, "ahead of a ship heading north")
	assert_true(station.x > 0.0, "and off its starboard side")
	assert_near(station.y * WorldPresentation.NM_TO_M, maxf(10.0 * WorldCamera.FLYBY_LEAD_S, 150.0 * WorldCamera.FLYBY_LEAD_LENGTHS), 0.5, "far enough ahead to watch it come")
	assert_true(station.z > 0.0 and station.z < 60.0, "low over the water")
	assert_true(not WorldCamera.flyby_passed(station, Vector2.ZERO, 0.0, 150.0), "not passed while approaching")
	var beyond := Vector2(0.0, station.y + 150.0 * (WorldCamera.FLYBY_PAST_LENGTHS + 0.5) / WorldPresentation.NM_TO_M)
	assert_true(WorldCamera.flyby_passed(station, beyond, 0.0, 150.0), "passed once it has run on by a few lengths")
	assert_true(WorldCamera.flyby_passed(station, Vector2(-5, 0), 180.0, 150.0), "or when it has gone far off the other way")
	var air := WorldCamera.flyby_station(Vector2.ZERO, 90.0, 250.0, 20.0, "air", 3000.0)
	assert_true(air.z > 3000.0, "an aircraft is met at its own height")
	var cam := WorldCamera.new()
	cam.set_mode(WorldCamera.FLYBY)
	var first := cam.update(0.016, Vector2.ZERO, _frame(Vector3.ZERO, 0.0), Callable())
	var still := cam.update(0.016, Vector2(0, 0.05), _frame(Vector3.ZERO, 0.0), Callable())
	assert_true(not still["cut"], "the camera holds its station while the ship comes on")
	assert_near((WorldCamera.to_chart(first["eye"], Vector2.ZERO) - WorldCamera.to_chart(still["eye"], Vector2(0, 0.05))).length(), 0.0, 1e-6, "fixed in the chart as the origin slides")
	var moved := cam.update(0.016, beyond, _frame(Vector3.ZERO, 0.0), Callable())
	assert_true(moved["cut"], "once passed, it cuts to a new station")


func test_detached_freezes_the_eye_and_keeps_looking() -> void:
	var cam := WorldCamera.new()
	var shot := cam.update(0.016, Vector2.ZERO, _frame(Vector3.ZERO, 0.0), Callable())
	var eye_chart := WorldCamera.to_chart(shot["eye"], Vector2.ZERO)
	cam.set_mode(WorldCamera.DETACHED)
	var origin := Vector2(0.0, 0.5)
	var later := cam.update(0.016, origin, _frame(Vector3.ZERO, 0.0), Callable())
	assert_near(WorldCamera.to_chart(later["eye"], origin).distance_to(eye_chart), 0.0, 1e-6, "the eye stays where it was when detached")
	assert_eq(later["look"], Vector3.ZERO, "while it keeps looking at the subject as it moves away")


func test_action_cuts_to_events_holds_then_returns_to_the_tether() -> void:
	var cam := WorldCamera.new()
	cam.notify("hit", Vector3(1, 1, 9))
	assert_true(cam.action().is_empty(), "outside Action, events are ignored")
	cam.set_mode(WorldCamera.ACTION)
	var ship := _frame(Vector3.ZERO, 0.0)
	cam.update(0.016, Vector2.ZERO, ship, Callable())
	cam.notify("launch", Vector3(0, 0, 10), "w:5")
	var round := {"position": Vector3(0, 30, -200), "length": 6.0, "heading": 0.0, "domain": "weapon"}
	var lookup := func(key: String) -> Dictionary: return round if key == "w:5" else {}
	var shot := cam.update(0.016, Vector2.ZERO, ship, lookup)
	assert_eq(cam.action()["kind"], "launch", "a launch of ours is shown")
	assert_true(shot["cut"], "with a cut")
	assert_eq(shot["look"], round["position"], "following the round")
	assert_eq(cam.mode_name(), "Action", "the mode stays Action throughout")
	cam.notify("destroyed", Vector3(0.5, 0.5, 9))
	shot = cam.update(WorldCamera.MIN_SHOT_S + 0.1, Vector2.ZERO, ship, lookup)
	assert_eq(cam.action()["kind"], "destroyed", "a kill cuts away from a launch once the launch has been seen a moment")
	assert_true((shot["look"] as Vector3).distance_to(WorldCamera.to_world(Vector3(0.5, 0.5, 9), Vector2.ZERO)) < 10.0, "and watches the point")
	for i in int(WorldCamera.ACTION_HOLD_S / 0.25) + 2:
		shot = cam.update(0.25, Vector2.ZERO, ship, lookup)
	assert_true(cam.action().is_empty(), "about six seconds later it is over")
	assert_near((shot["eye"] as Vector3).length(), WorldCamera.tether_distance(150.0, 1.0), 1.0, "and the camera is back on the tether")


func test_action_drops_stale_events_and_lets_a_lost_round_go() -> void:
	var cam := WorldCamera.new()
	cam.set_mode(WorldCamera.ACTION)
	var ship := _frame(Vector3.ZERO, 0.0)
	cam.notify("hit", Vector3(1, 1, 9))
	cam.notify("launch", Vector3(0, 0, 9), "w:1")
	cam.update(0.016, Vector2.ZERO, ship, func(_k: String) -> Dictionary: return {})
	assert_eq(cam.action()["kind"], "hit", "the higher priority event goes first")
	for i in 30:
		cam.update(0.25, Vector2.ZERO, ship, func(_k: String) -> Dictionary: return {})
	assert_true(cam.action().is_empty(), "the launch waited too long to be worth a cut")
	cam.notify("launch", Vector3(0, 0, 9), "w:2")
	cam.update(0.016, Vector2.ZERO, ship, func(_k: String) -> Dictionary: return {})
	assert_eq(cam.action()["kind"], "launch")
	for i in 12:
		cam.update(0.25, Vector2.ZERO, ship, func(_k: String) -> Dictionary: return {})
	assert_true(cam.action().is_empty(), "a round that has gone is watched briefly, not for the full follow")
	for i in 10:
		cam.notify("launch", Vector3(0, 0, 9), "w:%d" % (10 + i))
	assert_true(cam._queue.size() <= WorldCamera.ACTION_QUEUE, "the queue is bounded")


func test_watch_station_stands_off_along_the_line_of_sight() -> void:
	var at := Vector3(0, 0, 10)
	var from := Vector3(0, -1, 100)
	var st := WorldCamera.watch_station(at, from, "hit")
	assert_true(st.y < 0.0, "on the side the camera was already looking from")
	assert_near(Vector2(st.x, st.y).length() * WorldPresentation.NM_TO_M, 650.0, 0.5, "close enough to see a hit")
	assert_true(st.z > at.z, "and a little above it")
	var chart := Vector3(1.5, -2.0, 30.0)
	var back := WorldCamera.to_chart(WorldCamera.to_world(chart, Vector2(3, 3)), Vector2(3, 3))
	assert_near(back.distance_to(chart), 0.0, 1e-6, "chart and world coordinates round-trip")


# --- Land and effects ----------------------------------------------------------------------

func test_land_climates_and_filter_weights() -> void:
	assert_eq(WorldLand.climate("arabian_sea", 12.0), "arid", "the Red Sea is desert")
	assert_eq(WorldLand.climate("north_atlantic", 68.0), "boreal", "Lofoten is boreal")
	assert_eq(WorldLand.climate("west_pacific", 10.0), "tropical")
	assert_eq(WorldLand.climate("mediterranean", 32.0), "arid", "the Libyan shore is desert")
	assert_eq(WorldLand.climate("mediterranean", 43.0), "mediterranean")
	for t in [0.0, 0.3, 0.77, 1.0]:
		var sum := 0.0
		for i in 4:
			sum += WorldLand.bspline_weight(t, i)
		assert_near(sum, 1.0, 1e-5, "B-spline weights sum to one at %.2f" % t)
	var mesh := WorldLand.grid_mesh()
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(verts.size(), (WorldLand.MESH_CELLS + 1) * (WorldLand.MESH_CELLS + 1), "one static grid")
	var n := WorldLand.MESH_CELLS + 1
	var centre_step: float = verts[n / 2 + 1].x - verts[n / 2].x
	var edge_step: float = verts[n - 1].x - verts[n - 2].x
	assert_true(centre_step < edge_step * 0.2, "dense at the focus, sparse at the edge")
	assert_near(verts[n - 1].x, WorldLand.MESH_HALF_NM * WorldPresentation.NM_TO_M, 0.5, "reaching the edge of the window")


func test_land_follows_the_chart_coast_and_heights() -> void:
	var sc := {"map": {"anchor_lat": 68.8, "anchor_lon": 13.5, "chart_region": "north_atlantic"}, "terrain": {"land": [{"id": "isle", "points_nm": [[0, 0], [4, 0], [4, 4], [0, 4]], "elevation_m": 200}]}}
	Bathymetry.load_for(sc)
	Terrain.load_from(sc)
	var land := WorldLand.new()
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(land)
	land.build()
	land.update(Vector2(2, 2))
	assert_true(land.is_land(Vector2(2, 2)), "inside the coastline is land")
	assert_true(not land.is_land(Vector2(-3, 2)), "outside it is sea, whatever the raster says")
	assert_eq(land.height_at(Vector2(-3, 2)), 0.0, "and has no ground")
	assert_true(land.height_at(Vector2(2, 2)) >= WorldLand.BASE_M + WorldLand.MIN_INLAND_M - 0.01, "land stands above the water")
	assert_true(land.height_at(Vector2(2, 2), 10.0) < land.height_at(Vector2(2, 2), 3000.0), "and rises inland from the beach")
	assert_true(land._mesh.visible, "the grid is drawn when there is land in the window")
	land.update(Vector2(500, 500))
	land.update(Vector2(500, 500))
	assert_true(not land._mesh.visible, "and not over open ocean")
	root.remove_child(land)
	land.free()
	Terrain.clear()
	Bathymetry.clear()


func test_smoke_trails_linger_after_the_round_and_then_go() -> void:
	var fx := WorldEffects.new()
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(fx)
	fx.eye = Vector3(0, 50, 500)
	var seed := PackedVector3Array([Vector3(0, 0, 12), Vector3(0, 0, 80)])
	fx.trail_extend("w:1", Vector2(0, 0.1), 200.0, 30.0, seed)
	for i in 20:
		fx.tick(0.1)
		fx.trail_extend("w:1", Vector2(0, 0.1 + i * 0.02), 200.0, 30.0)
		fx.draw_trails()
	assert_true(fx.has_trail("w:1"), "a flying round lays a trail")
	var pts: PackedVector4Array = fx._trails["w:1"]["pts"]
	assert_eq(Vector2(pts[0].x, pts[0].y), Vector2.ZERO, "starting at the launcher")
	assert_true(pts.size() <= WorldEffects.TRAIL_SAMPLES, "with a bounded number of samples")
	fx.trail_release("w:1")
	fx.tick(WorldEffects.TRAIL_LIFE_S * 0.5)
	fx.draw_trails()
	assert_true(fx.has_trail("w:1"), "the smoke lingers after the round has gone")
	fx.rate = 0.0
	fx.tick(WorldEffects.TRAIL_LIFE_S * 2.0)
	fx.draw_trails()
	assert_true(fx.has_trail("w:1"), "and holds still while the simulation is paused")
	fx.rate = 1.0
	fx.tick(WorldEffects.TRAIL_LIFE_S)
	fx.draw_trails()
	assert_true(not fx.has_trail("w:1"), "then fades out and is released")
	for i in WorldEffects.MAX_TRAILS + 6:
		fx.trail_extend("w:%d" % (100 + i), Vector2(i, 0), 10.0, 30.0)
		fx.trail_release("w:%d" % (100 + i))
	assert_true(fx.trail_count() <= WorldEffects.MAX_TRAILS, "the number of trails is bounded")
	root.remove_child(fx)
	fx.free()
