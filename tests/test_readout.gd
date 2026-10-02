extends TestCase
## The contact readout of the data display: where a plot came from (platform and set), the battle
## damage assessment from a side's own hits, plain course and speed, the hover read with nothing
## hooked, and F7 finding a contact's reference entry from its reported class.


func _spec(short_name: String, health := 110.0) -> PlatformSpec:
	var p := PlatformSpec.new()
	p.short_name = short_name
	p.domain = "surface"
	p.max_speed_kn = 30.0
	p.cruise_speed_kn = 16.0
	p.acoustic_signature = 1.0
	p.health = health
	p.signature_factor = 1.0
	p.mast_height_m = 30.0
	return p


func _unit(spec: PlatformSpec, faction: String, pos: Vector2, speed := 0.0) -> Unit:
	var u := Unit.new()
	u.spec = spec
	u.faction = faction
	u.callsign = "%s-%s" % [faction, spec.short_name]
	u.position = pos
	u.speed_kn = speed
	u.ordered_speed_kn = speed
	u.health = spec.health
	return u


func _radar() -> SensorSpec:
	var s := SensorSpec.new()
	s.id = "test_radar"
	s.display_name = "AN/SPS-99 surface search radar (test fit)"
	s.kind = "radar"
	s.range_surface_nm = 40.0
	s.range_air_nm = 200.0
	s.antenna_height_m = 20.0
	return s


func _sonar() -> SensorSpec:
	var s := SensorSpec.new()
	s.id = "test_sonar"
	s.display_name = "Test hull sonar"
	s.kind = "sonar"
	s.passive_sensitivity_nm = 40.0
	s.active_range_nm = 0.0
	s.self_noise_tolerance = 0.6
	s.bearing_accuracy_deg = 1.0
	s.classify_rate = 1.0
	return s


func _harness(observer: Unit, target: Unit) -> Array:
	var um := UnitManager.new()
	um.add_unit(observer)
	um.add_unit(target)
	var tm := TrackManager.new()
	var sm := SensorManager.new()
	sm.unit_manager = um
	sm.track_manager = tm
	sm.rng.seed = 5
	return [um, tm, sm]


func _cleanup(h: Array) -> void:
	h[2].free()
	h[1].free()
	h[0].free()


static func _text(rows: Array) -> String:
	var lines := PackedStringArray()
	for row: Array in rows:
		var line := ""
		for span: Array in row:
			if str(span[0]) != "FLOW" and str(span[0]) != DataDisplay.CELL:
				line += str(span[0])
		lines.append(line)
	return "\n".join(lines)


func _held(faction: String, target: Unit, tm: TrackManager, observer: Unit = null) -> Track:
	var c := SensorContact.make(target, target.position, 0.5, 0.8, 1.0, 10.0, "radar", observer, _radar())
	tm.observe_contact(faction, c, 1.0, 1.0)
	return tm.find_track(faction, target)


# --- Source ---------------------------------------------------------------------------------

func test_radar_plot_names_the_platform_and_the_set() -> void:
	var observer := _unit(_spec("MH-60R"), "BLUE", Vector2.ZERO)
	observer.sensors.append(_radar())
	var target := _unit(_spec("FFG Test"), "RED", Vector2(0.0, 10.0), 12.0)
	var h := _harness(observer, target)
	h[2].run_cycle(1.0)
	var t: Track = h[1].find_track("BLUE", target)
	assert_true(t != null, "the radar holds the contact")
	if t != null:
		assert_eq(t.source, "radar")
		assert_eq(t.source_platform, "MH-60R", "the observing platform's class, which is no secret to its own side")
		assert_eq(t.source_sensor_id, "test_radar")
		assert_eq(t.source_sensor, "AN/SPS-99 surface search radar (test fit)")
		assert_eq(DataDisplay.source_readout(t), "MH-60R SPS-99 surface search radar", "no AN/ prefix and no fit note")
		assert_true(_text(DataDisplay.track_rows(t, observer, 1.0)).contains("SOURCE: MH-60R SPS-99 surface search radar"))
	_cleanup(h)


func test_passive_sonar_bearing_names_the_listener_and_its_array() -> void:
	var listener := _unit(_spec("DDG Listener"), "BLUE", Vector2.ZERO, 4.0)
	listener.radar_on = false
	listener.sensors.append(_sonar())
	var target := _unit(_spec("FFG Noisy"), "RED", Vector2(0.0, 12.0), 16.0)
	var h := _harness(listener, target)
	for i in 3:
		h[2].run_cycle(float(i + 1))
	var t: Track = h[1].find_track("BLUE", target)
	assert_true(t != null, "the array hears the contact")
	if t != null:
		assert_eq(t.source, "sonar_passive")
		assert_eq(t.source_platform, "DDG Listener")
		assert_eq(t.source_sensor_id, "test_sonar")
		assert_eq(DataDisplay.source_readout(t), "DDG Listener Test hull sonar, passive")
	_cleanup(h)


func test_buoys_and_relayed_plots_say_so() -> void:
	var t := Track.new()
	t.source = "sonobuoy"
	t.source_sensor = "Sonobuoy field"
	t.source_sensor_id = "sonobuoy"
	assert_eq(DataDisplay.source_readout(t), "Sonobuoy field")
	var relayed := Track.new()
	relayed.source = "radar"
	assert_eq(DataDisplay.source_readout(relayed), "Link", "a plot no unit of ours made came in over the link")
	relayed.contributors[Unit.new()] = 0.0
	assert_eq(DataDisplay.source_readout(relayed), "Radar", "an older plot without a named set keeps its category")
	assert_eq(DataDisplay.sensor_label("AN/SPY-6(V)1 multifunction radar"), "SPY-6(V)1 multifunction radar", "a variant in brackets is part of the name")


# --- Battle damage assessment ---------------------------------------------------------------

func test_own_hit_raises_only_the_shooters_estimate_over_the_class_health() -> void:
	var tm := TrackManager.new()
	var target := _unit(DataDB.platform("rfn_cg_slava"), "RED", Vector2(0, 10))
	var blue := _held("BLUE", target, tm)
	var green := _held("GREEN", target, tm)
	blue.classification = Track.Classification.CLASS_KNOWN
	blue.known_class = "CG Slava"
	var weapon := WeaponSpec.new()
	weapon.id = "test_asm"
	weapon.damage = 35.0
	tm.on_weapon_impact("BLUE", weapon, target, true)
	var health := DataDB.platform("rfn_cg_slava").health
	assert_near(blue.damage_estimate, 100.0 * 35.0 / health, 0.01, "damage over the reported class's catalogue health")
	assert_near(green.damage_estimate, 0.0, 1e-6, "a side that did not shoot learns nothing from the hit")
	tm.on_weapon_impact("BLUE", weapon, target, false)
	assert_near(blue.damage_estimate, 100.0 * 35.0 / health, 0.01, "a miss assesses nothing")
	for i in 10:
		tm.on_weapon_impact("BLUE", weapon, target, true)
	assert_near(blue.damage_estimate, 100.0, 1e-6, "capped at 100")
	assert_true(target.health == DataDB.platform("rfn_cg_slava").health, "assessment never touches or reads the target's health")
	tm.free()


func test_unclassified_contact_is_assessed_against_a_generic_pool() -> void:
	var tm := TrackManager.new()
	var target := _unit(_spec("Secret", 400.0), "RED", Vector2(0, 10))
	var t := _held("BLUE", target, tm)
	assert_true(t.classification < Track.Classification.CLASS_KNOWN)
	var weapon := WeaponSpec.new()
	weapon.damage = 25.0
	tm.record_hit("BLUE", weapon, target)
	assert_near(t.damage_estimate, 100.0 * 25.0 / TrackManager.GENERIC_HEALTH, 1e-4, "not the true 400-point pool")
	assert_true(_text(DataDisplay.track_rows(t, null, 1.0)).contains("%DAMAGE: 25 (est)"))
	tm.free()


func test_a_kill_the_plot_sees_reads_one_hundred() -> void:
	var tm := TrackManager.new()
	var target := _unit(_spec("FFG Test"), "RED", Vector2(0, 10))
	var t := _held("BLUE", target, tm)
	tm.on_unit_destroyed(target, "BLUE")
	assert_near(t.damage_estimate, 100.0, 1e-6)
	tm.free()


func test_simulation_wires_impacts_into_the_plot() -> void:
	var sim := Simulation.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	var target := _unit(_spec("FFG Test"), "RED", Vector2(0, 10))
	var t := _held("BLUE", target, sim.track_manager)
	var weapon := WeaponSpec.new()
	weapon.damage = 50.0
	sim.weapon_manager.weapon_impact.emit("BLUE", weapon, target, true)
	assert_near(t.damage_estimate, 50.0, 1e-4, "Simulation connects WeaponManager.weapon_impact")
	sim.weapon_manager.unit_destroyed.emit(target, "BLUE")
	assert_near(t.damage_estimate, 100.0, 1e-4, "and unit_destroyed")
	sim.free()


# --- Course and speed -----------------------------------------------------------------------

func test_held_kinematics_read_plainly() -> void:
	var t := Track.new()
	t.id = "T1201"
	t.identity = "HOSTILE"
	t.has_kinematics = true
	t.course_deg = 162.0
	t.speed_kn = 17.0
	t.position_error_nm = 0.4
	var text := _text(DataDisplay.track_rows(t, null, 0.0))
	assert_true(text.contains("COURSE: 162   SPEED: 17 KTS"), text)
	assert_true(text.contains("%DAMAGE: not assessed"), "no reported hit is not proof of an undamaged hull")
	assert_true(not text.contains("162 (est)") and not text.contains("KTS (est)"))
	assert_true(text.contains("POSITION: +/-0.4 nm"), "the position row states the uncertainty")


# --- Hover ----------------------------------------------------------------------------------

func test_hovered_contact_reads_out_only_with_nothing_hooked() -> void:
	var tm := TrackManager.new()
	var target := _unit(_spec("FFG Test"), "RED", Vector2(4, 4))
	var t := _held("BLUE", target, tm)
	var other_target := _unit(_spec("FFG Other"), "RED", Vector2(-30, -30))
	var other := _held("BLUE", other_target, tm)
	var map := TacticalMap.new()
	map.track_manager = tm
	map.player_faction = "BLUE"
	var simulation := Simulation.new()
	var display := DataDisplay.new()
	display.map = map
	display.simulation = simulation
	assert_eq(map.hovered_track(), null, "no cursor on the chart, no hover")
	var mission := _text(display.build_rows())
	map._mouse_inside = true
	map._mouse = map.world_to_screen(t.position)
	assert_eq(map.hovered_track(), t)
	var hover := _text(display.build_rows())
	assert_true(hover.contains("TRACK #: %s" % DataDisplay.track_number_for_track(t)), "the hovered contact fills the display")
	map._mouse = map.world_to_screen(t.position) + Vector2(200, 200)
	assert_eq(map.hovered_track(), null)
	assert_eq(_text(display.build_rows()), mission, "moving off restores the mission page")
	map._mouse = map.world_to_screen(t.position)
	map.menu_open = true
	assert_eq(map.hovered_track(), null, "an open menu owns the cursor")
	map.menu_open = false
	map.select_track(other)
	assert_eq(map.inspection_track(), other)
	assert_true(_text(display.build_rows()).contains("TRACK #: %s" % DataDisplay.track_number_for_track(other)), "an inspected contact outranks the hover")
	map.select_track(null)
	var shooter := _unit(DataDB.platform("usn_ddg_burke_iii"), "BLUE", Vector2(50, 50))
	for sensor_id in shooter.spec.sensor_ids:
		shooter.sensors.append(DataDB.sensor(sensor_id))
	map.select_units([shooter])
	assert_true(not _text(display.build_rows()).contains("TRACK #: %s" % DataDisplay.track_number_for_track(t)), "a hooked platform outranks the hover")
	display.free()
	map.free()
	simulation.free()
	tm.free()


# --- F7 -------------------------------------------------------------------------------------

func test_reference_entry_comes_from_the_reported_class() -> void:
	var t := Track.new()
	t.truth = _unit(DataDB.platform("usn_ddg_burke_iii"), "RED", Vector2.ZERO)
	assert_eq(PlatformLibrary.entry_for_track(t), null, "an unclassified contact has no entry")
	t.classification = Track.Classification.SURFACE
	t.domain = "surface"
	assert_eq(PlatformLibrary.entry_for_track(t), null, "a domain is not a class")
	t.classification = Track.Classification.CLASS_KNOWN
	t.known_class = "CG Slava"
	var modern := PlatformLibrary.entry_for_track(t, "usn_ddg_burke_iii")
	var period := PlatformLibrary.entry_for_track(t, "cw90_ticonderoga")
	assert_true(modern != null and modern.id == "rfn_cg_slava", "the reported class, never the unit under the track")
	assert_true(period != null and period.id == "cw90_slava", "a shared class name resolves in the mission's own catalogue")
	assert_eq(DataDB.platform_by_short_name("No Such Class"), null)
	var burke := DataDB.platform("usn_ddg_burke_iii")
	assert_eq(DataDB.platform_by_short_name(burke.short_name), burke, "an unshared short name finds its class")
	assert_eq(PlatformLibrary.entry_for_track(null), null)


func test_old_contact_kinematics_and_freshness_are_explicit() -> void:
	var t := Track.new()
	t.classification = Track.Classification.CLASS_KNOWN
	t.known_class = "FFG Test"
	t.last_seen_time = 10.0
	t.has_kinematics = true
	t.course_deg = 90.0
	t.speed_kn = 12.0
	t.status = Track.Status.STALE
	var text := _text(DataDisplay.track_rows(t, null, 130.0))
	assert_true(text.contains("PLOT: STALE - last report 2m ago"), text)
	assert_true(text.contains("LAST COURSE: 090"), "old kinematics must not imply a fresh observation")
	t.status = Track.Status.LOST
	assert_eq(DataDisplay.plot_text(t, 130.0), "LOST - last report 2m ago")
	t.status = Track.Status.ACTIVE
	t.reported = true
	assert_eq(DataDisplay.plot_text(t, 15.0), "CONTACT REPORT - 5s ago", "an external report is not a live sensor plot")
	t.reported = false
	assert_eq(DataDisplay.plot_text(t, 15.0), "LIVE - updated 5s ago")


func test_bearing_only_and_unassessed_damage_do_not_imply_measured_facts() -> void:
	var t := Track.new()
	t.bearing_only = true
	t.has_kinematics = true
	t.speed_kn = 99.0
	var text := _text(DataDisplay.track_rows(t, _unit(_spec("Own"), "BLUE", Vector2.ZERO), 0.0))
	assert_true(text.contains("range unresolved"))
	assert_true(not text.contains("99 KTS") and not text.contains("RANGE:"), "a bearing-only datum supplies neither speed nor measured range")
	assert_eq(DataDisplay.damage_text(t), "not assessed")
	t.damage_estimate = 35.0
	assert_eq(DataDisplay.damage_text(t), "35 (est)", "reported hits remain estimates")
