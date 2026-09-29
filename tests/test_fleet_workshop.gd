extends TestCase


func _ship(faction := "BLUE") -> Unit:
	var u := Unit.new()
	u.spec = PlatformSpec.new()
	u.spec.domain = "surface"
	u.spec.max_speed_kn = 30
	u.spec.accel_kn_s = 0.5
	u.spec.turn_rate_deg_s = 2
	u.spec.length_m = 150
	u.spec.decoy_effectiveness = 0.9
	u.spec.torpedo_decoy_effectiveness = 0.8
	u.spec.fire_control_channels = 1
	u.spec.has_datalink = true
	u.faction = faction
	u.callsign = faction
	u.speed_kn = 18
	u.ordered_speed_kn = 18
	u.health = 100
	u.decoys = 3
	u.torpedo_decoys = 2
	return u


func _round(u: Unit, guidance := "active_radar_homing") -> Weapon:
	var w := Weapon.new()
	w.id = 900
	w.spec = WeaponSpec.new()
	w.spec.guidance = guidance
	w.spec.speed_kn = 480
	w.spec.max_range_nm = 60
	w.spec.min_range_nm = 0.1
	w.spec.base_pk = 0.8
	w.position = Vector2(1, 0)
	w.faction = "RED"
	w.heading_deg = 270
	w.acquired = u
	w.phase = Weapon.Phase.TERMINAL
	return w


func _harness() -> Array:
	Terrain.clear()
	var um := UnitManager.new()
	var u := _ship()
	um.add_unit(u)
	var tm := ThreatManager.new()
	var wm := WeaponManager.new()
	wm.unit_manager = um
	wm.rng.seed = 29
	return [um, tm, wm, u]


func _clean(h: Array) -> void:
	h[2].clear()
	h[2].free()
	h[1].free()
	h[0].free()


func test_manual_pulse_consumes_one_pack_has_a_window_and_cannot_be_spammed() -> void:
	var h := _harness()
	var u: Unit = h[3]
	assert_true(DefensiveResponse.deploy(u, "radar", h[2]))
	assert_eq(u.decoys, 2)
	assert_true(not DefensiveResponse.deploy(u, "radar", h[2]))
	assert_eq(u.decoys, 2)
	DefensiveResponse.tick(u, 20)
	assert_eq(u.countermeasure_remaining_s, 0.0)
	assert_true(not DefensiveResponse.can_deploy(u, "radar"))
	DefensiveResponse.tick(u, 5)
	assert_true(DefensiveResponse.can_deploy(u, "radar"))
	_clean(h)


func test_radar_decoys_do_not_roll_against_infrared_or_acoustic_seekers() -> void:
	var h := _harness()
	var u: Unit = h[3]
	DefensiveResponse.deploy(u, "radar", h[2])
	var ir := _round(u, "imaging_infrared")
	assert_true(not DefensiveResponse.try_active(u, ir, h[2]))
	assert_true(ir.countermeasure_attempts.is_empty())
	assert_true(ir.acquired == u)
	var torpedo := _round(u, "acoustic_homing")
	torpedo.spec.type = "torpedo"
	assert_true(not DefensiveResponse.try_active(u, torpedo, h[2]))
	assert_true(torpedo.countermeasure_attempts.is_empty())
	_clean(h)


func test_a_pulse_has_one_roll_per_threat_and_can_cover_a_salvo() -> void:
	var h := _harness()
	var u: Unit = h[3]
	DefensiveResponse.deploy(u, "radar", h[2])
	for i in 4:
		var w := _round(u)
		w.id += i
		DefensiveResponse.try_active(u, w, h[2])
		DefensiveResponse.try_active(u, w, h[2])
		assert_eq(w.countermeasure_attempts.size(), 1)
	assert_eq(u.decoys, 2, "four threats do not require four simultaneous deployments")
	_clean(h)


func test_manual_acoustic_decoy_uses_its_own_inventory_and_wake_homing_is_distinct() -> void:
	var h := _harness()
	var u: Unit = h[3]
	assert_true(DefensiveResponse.deploy(u, "acoustic", h[2]))
	assert_eq(u.torpedo_decoys, 1)
	assert_eq(u.decoys, 3)
	var w := _round(u, "wake_homing_abstracted")
	w.spec.type = "torpedo"
	assert_eq(w.spec.seeker_band(), "none")
	assert_true(not DefensiveResponse.try_active(u, w, h[2]))
	_clean(h)


func test_automatic_soft_kill_still_works_under_weapons_hold_and_damage() -> void:
	var h := _harness()
	var u: Unit = h[3]
	u.roe = Unit.Roe.HOLD
	u.components["weapons"] = 0
	var w := _round(u)
	h[1].mark_detected("BLUE", w, 0, u)
	DefensiveResponse.run_cycle(h[0], h[1], h[2])
	assert_eq(u.decoys, 2)
	assert_eq(w.countermeasure_attempts.size(), 1)
	_clean(h)


func test_manual_mode_does_not_spend_packs_automatically() -> void:
	var h := _harness()
	var u: Unit = h[3]
	u.auto_countermeasures = false
	var w := _round(u)
	h[1].mark_detected("BLUE", w, 0, u)
	DefensiveResponse.run_cycle(h[0], h[1], h[2])
	assert_eq(u.decoys, 3)
	assert_true(DefensiveResponse.deploy(u, "radar", h[2]))
	DefensiveResponse.run_cycle(h[0], h[1], h[2])
	assert_eq(w.countermeasure_attempts.size(), 1)
	_clean(h)


func test_undetected_or_non_threatening_weapons_cannot_supply_an_evasion_bearing() -> void:
	var h := _harness()
	var u: Unit = h[3]
	var w := _round(u)
	h[2].in_flight.append(w)
	assert_true(not DefensiveResponse.start_evasion(u, h[0], h[1]))
	assert_eq(u.evasion_remaining_s, 0.0)
	h[1].mark_detected("BLUE", w, 0, u)
	assert_true(DefensiveResponse.start_evasion(u, h[0], h[1]))
	_clean(h)


func test_evasion_preserves_routes_and_uses_real_turning_before_it_helps() -> void:
	var h := _harness()
	var u: Unit = h[3]
	u.waypoints.append(Vector2(0, 20))
	var route := u.waypoints.duplicate()
	var w := _round(u)
	w.position = Vector2(0, 2)
	h[1].mark_detected("BLUE", w, 0, u)
	assert_true(DefensiveResponse.start_evasion(u, h[0], h[1]))
	assert_eq(DefensiveResponse.evasion_factor(u, w.spec), 1.0, "the button cannot grant immediate immunity")
	Movement.step(u, 0.25)
	assert_true(absf(Geo.heading_delta(0, u.heading_deg)) <= u.spec.turn_rate_deg_s * 0.25)
	assert_eq(u.waypoints, route)
	u.heading_deg = u.evasion_course_deg
	u.speed_kn = u.effective_max_speed()
	assert_true(DefensiveResponse.evasion_factor(u, w.spec) < 1.0)
	DefensiveResponse.tick(u, 60)
	Movement.step(u, 0.25)
	assert_eq(u.waypoints, route)
	assert_eq(u.evasion_remaining_s, 0.0)
	_clean(h)


func test_new_navigation_orders_override_emergency_steering() -> void:
	var u := _ship()
	u.evasion_remaining_s = 60
	u.apply_order(Order.set_course(180))
	assert_eq(u.evasion_remaining_s, 0.0)
	assert_eq(u.ordered_heading_deg, 180.0)


func test_evasion_preserves_formation_and_station_keeping_resumes() -> void:
	var leader := _ship()
	var member := _ship()
	member.apply_order(Order.form_up(leader, Vector2(4, 0)))
	member.evasion_remaining_s = 60
	member.ordered_heading_deg = 123
	Formation.step(member)
	assert_eq(member.ordered_heading_deg, 123.0)
	assert_true(member.formation_leader == leader)
	member.apply_order(Order.resume_plan())
	Formation.step(member)
	assert_near(member.ordered_heading_deg, 90)
	member.formation_leader = null


func test_large_patterns_never_reuse_stations() -> void:
	for pattern: String in ["screen", "column", "abreast", "wedge", "dispersed"]:
		var positions: Dictionary = {}
		for i in 96:
			var offset := Formation.offset_for(i, pattern)
			assert_true(not positions.has(offset), "%s station %d is unique" % [pattern, i])
			assert_true(offset.length() > 0)
			positions[offset] = true


func test_formation_cannot_cross_factions_domains_or_create_a_reference_cycle() -> void:
	var a := _ship()
	var b := _ship()
	var enemy := _ship("RED")
	assert_true(not UnitManager.can_accept_order(a, Order.form_up(enemy, Vector2.ONE)))
	b.apply_order(Order.form_up(a, Vector2.ONE))
	assert_true(not UnitManager.can_accept_order(a, Order.form_up(b, Vector2.ONE)))
	assert_true(not UnitManager.can_accept_order(a, Order.form_up(a, Vector2.ONE)))
	b.formation_leader = null
	b.spec.domain = "subsurface"
	assert_true(not Formation.can_join(b, a))


func test_flagship_paces_the_slowest_damaged_consort_and_dead_members_do_not_limit_it() -> void:
	var h := _harness()
	var leader: Unit = h[3]
	var slow := _ship()
	slow.spec.max_speed_kn = 20
	slow.components["propulsion"] = 0.5
	h[0].add_unit(slow)
	slow.apply_order(Order.form_up(leader, Vector2(4, 0)))
	Formation.update_speed_caps(h[0].units)
	assert_near(leader.formation_speed_cap_kn, slow.effective_max_speed())
	slow.alive = false
	Formation.update_speed_caps(h[0].units)
	assert_eq(leader.formation_speed_cap_kn, INF)
	_clean(h)


func test_losing_a_flagship_promotes_a_surviving_consort_without_cycles() -> void:
	var h := _harness()
	var leader: Unit = h[3]
	var a := _ship()
	var b := _ship()
	a.position = Vector2(4, 0)
	b.position = Vector2(-4, 0)
	h[0].add_unit(a)
	h[0].add_unit(b)
	a.apply_order(Order.form_up(leader, Vector2(4, 0)))
	b.apply_order(Order.form_up(leader, Vector2(-4, 0)))
	leader.alive = false
	Formation.update_speed_caps(h[0].units)
	assert_true(a.formation_leader == null)
	assert_true(b.formation_leader == a)
	assert_near(b.position.distance_to(Formation.station_for(b)), 0)
	_clean(h)


func test_ram_is_self_guided_and_can_answer_with_a_busy_area_defence_channel() -> void:
	var h := _harness()
	var u: Unit = h[3]
	var ram := DataDB.weapon("ram_block2")
	assert_true(not ram.requires_radar_support())
	assert_true(not ram.requires_fire_control_channel())
	var area := WeaponSpec.new()
	area.type = "sam"
	area.guidance = "semi_active_radar"
	var other := _round(u)
	other.id = 901
	var engaged := Weapon.new()
	engaged.spec = area
	engaged.shooter = u
	engaged.intercept_target = other
	h[2].in_flight.append(engaged)
	assert_true(not h[2].channel_available(u, _round(u)))
	u.weapons.append(ram)
	u.magazines[ram.id] = 10
	u.radar_on = false
	var threat := _round(u)
	assert_eq(h[2].launch_interceptor(u, ram, threat, 1, 0), 1)
	assert_eq(h[2].channel_targets(u).size(), 1, "RAM does not occupy a second illumination channel")
	_clean(h)


func test_interceptor_policy_escalates_conserve_when_the_threat_is_urgent() -> void:
	var u := _ship()
	u.defence_policy = "conserve"
	assert_eq(AirDefence.guided_budget(u, 120), 1)
	assert_eq(AirDefence.guided_budget(u, 20), 2)
	u.defence_policy = "balanced"
	assert_eq(AirDefence.guided_budget(u, 120), 2)
	u.defence_policy = "saturation"
	assert_eq(AirDefence.guided_budget(u, 120), 3)


func test_an_unspecified_inertial_terminal_weapon_is_not_magically_vulnerable_to_flares() -> void:
	for id: String in ["kinzhal_family", "kh38_family", "oneway_attack_drone"]:
		assert_eq(DataDB.weapon(id).seeker_band(), "none")
	assert_eq(DataDB.weapon("agm_158b_jassm_er").seeker_band(), "infrared")
	assert_eq(DataDB.weapon("agm_158c_lrasm").seeker_band(), "infrared")


func test_recipe_is_reproducible_and_different_seeds_change_the_mix() -> void:
	var a := ScenarioWorkshop.generate({"seed": 29})
	var b := ScenarioWorkshop.generate({"seed": 29})
	assert_eq(JSON.stringify(a), JSON.stringify(b))
	var c := ScenarioWorkshop.generate({"seed": 31})
	assert_true(JSON.stringify(a["units"]) != JSON.stringify(c["units"]))


func test_generated_fleets_validate_in_every_theatre_and_both_eras() -> void:
	for region in 4:
		for year in [1990, 2027]:
			var sc := ScenarioWorkshop.generate({"region": region, "year": year, "seed": 29, "coastlines": true})
			assert_eq(ScenarioWorkshop.validate(sc), "", "%d region %d" % [year, region])
			for u: Dictionary in sc["units"]:
				assert_eq(str(u["platform"]).begins_with("cw90_"), year == 1990)


func test_big_recipe_loads_finite_wings_and_unique_surface_stations() -> void:
	Terrain.clear()
	var sc := ScenarioWorkshop.generate({"blue_ships": 32, "red_ships": 32, "blue_carriers": 2, "red_carriers": 2, "aircraft_per_carrier": 16})
	assert_eq(ScenarioWorkshop.validate(sc), "")
	var um := UnitManager.new()
	ScenarioLoader.populate(um, sc)
	var surface := 0
	for u in um.units:
		if u.spec.domain == "surface":
			surface += 1
		if u.spec.category.contains("carrier"):
			assert_eq(u.embarked.size(), 16)
	assert_eq(surface, 64)
	assert_true(um.units.size() > 128, "escort helicopter detachments are additional actors")
	um.free()


func test_reinforcements_are_exported_once_and_do_not_allow_an_early_victory() -> void:
	Terrain.clear()
	var sc := ScenarioWorkshop.generate({"blue_ships": 1, "red_ships": 1, "blue_carriers": 0, "blue_subs": 0, "red_subs": 0})
	sc["units"][1]["editor_arrival_s"] = 300
	var exported := ScenarioWorkshop.export_scenario(sc)
	assert_eq(exported["events"].size(), 1)
	assert_eq(exported["units"].size(), 1)
	assert_true(exported["objectives"]["victory"][0]["after"].has("waves_arrived_red"))
	var um := UnitManager.new()
	ScenarioLoader.populate(um, exported)
	var mm := MissionManager.new()
	mm.unit_manager = um
	mm.configure(exported)
	mm.tick(0)
	assert_eq(mm.result, MissionManager.Result.RUNNING)
	ScenarioLoader.populate(um, {"units": exported["events"][0]["reinforcements"]})
	mm.tick(300)
	assert_eq(mm.result, MissionManager.Result.RUNNING)
	for u in um.units:
		if u.faction == "RED":
			u.alive = false
	mm.tick(301)
	assert_eq(mm.result, MissionManager.Result.VICTORY)
	mm.free()
	um.free()


func test_validator_reports_malformed_imports_and_impossible_fits() -> void:
	assert_true(ScenarioWorkshop.structural_problem({"units": "bad"}) != "")
	assert_true(ScenarioWorkshop.structural_problem({"units": [{"position_nm": [1, "bad"]}]}) != "")
	assert_true(ScenarioWorkshop.structural_problem({"objectives": {"victory": [{"after": "bad"}]}}) != "")
	var sc := ScenarioWorkshop.generate({"blue_carriers": 0})
	sc["units"][0]["platform"] = "usn_ddg_arleigh_burke_iia"
	sc["units"][0]["loadout"] = {"essm_family": 500}
	assert_true(ScenarioWorkshop.validate(sc).contains("VLS"))
	sc["units"][0]["loadout"] = {"not_a_weapon": 1}
	assert_true(ScenarioWorkshop.validate(sc).contains("incompatible"))


func test_objective_cycles_and_missing_units_are_rejected() -> void:
	var sc := ScenarioWorkshop.generate({})
	sc["objectives"]["victory"] = [{"id": "a", "type": "time_elapsed", "after": ["b"]}, {"id": "b", "type": "time_elapsed", "after": ["a"]}]
	assert_true(ScenarioWorkshop.validate(sc).contains("cycle"))
	sc["objectives"]["victory"] = [{"id": "reach", "type": "reach_area", "callsigns": ["missing"]}]
	assert_true(ScenarioWorkshop.validate(sc).contains("missing"))


func test_air_wing_limits_reject_overbooking_but_do_not_double_count_default_detachments() -> void:
	var sc := ScenarioWorkshop.generate({"blue_ships": 1, "red_ships": 1, "blue_carriers": 0, "blue_subs": 0, "red_subs": 0})
	sc["units"][0]["platform"] = "usn_ddg_arleigh_burke_iia"
	sc["units"].append({"platform": "usn_helo_mh60r", "callsign": "Helo", "faction": "BLUE", "home": "BLUE 01"})
	assert_eq(ScenarioWorkshop.validate(sc), "", "the default detachment fills only spare hangar spots")
	sc["units"][0]["air_wing"] = [{"platform": "usn_helo_mh60r", "count": 2}]
	assert_true(ScenarioWorkshop.validate(sc).contains("exceeds"))


func test_import_rejects_non_numeric_rounds_and_task_values_without_runtime_casts() -> void:
	for malformed in [{"units": [{"loadout": {"sm2_family": []}}]}, {"units": [{"air_wing": [{"platform": "usn_fa18e", "count": 1.5}]}]}, {"objectives": {"victory": [{"seconds": "bad"}]}}, {"objectives": {"victory": [{"callsigns": [{}]}]}}, {"map": {"extent_nm": -20}}]:
		assert_true(ScenarioWorkshop.structural_problem(malformed) != "")


func test_an_all_late_player_force_is_rejected_after_wave_export() -> void:
	var sc := ScenarioWorkshop.generate({"blue_ships": 1, "red_ships": 1, "blue_subs": 0, "red_subs": 0})
	sc["units"][0]["editor_arrival_s"] = 300
	assert_true(ScenarioWorkshop.validate(ScenarioWorkshop.export_scenario(sc)).contains("start"))


func test_authoring_rejects_formation_cycles_enemy_leaders_and_late_flagships() -> void:
	var sc := ScenarioWorkshop.generate({"blue_ships": 2, "red_ships": 1, "blue_subs": 0, "red_subs": 0})
	sc["units"][0]["formation_leader"] = "BLUE 02"
	assert_true(ScenarioWorkshop.validate(sc).contains("cycle"))
	sc["units"][0].erase("formation_leader")
	sc["units"][1]["formation_leader"] = "RED 01"
	assert_true(ScenarioWorkshop.validate(sc).contains("friendly"))
	sc["units"][1]["formation_leader"] = "BLUE 01"
	sc["units"][0]["editor_arrival_s"] = 300
	assert_true(ScenarioWorkshop.validate(ScenarioWorkshop.export_scenario(sc)).contains("arrives before"))


func test_coastal_large_recipes_do_not_stack_ships_on_the_same_water_point() -> void:
	for region in 4:
		var sc := ScenarioWorkshop.generate({"region": region, "coastlines": true, "blue_ships": 24, "red_ships": 24})
		assert_eq(ScenarioWorkshop.validate(sc), "")
		var seen: Dictionary = {}
		for u: Dictionary in sc["units"]:
			var p := Vector2(u["position_nm"][0], u["position_nm"][1])
			assert_true(not seen.has(p), "coastal placement has independent stations")
			seen[p] = true
		assert_true(not sc["map"].has("focus_center_nm"), "a template's camera cannot hide the generated fleet")


func test_a_nested_formation_paces_its_slowest_descendant() -> void:
	var h := _harness()
	var root: Unit = h[3]
	var section := _ship()
	var slow := _ship()
	slow.components["propulsion"] = 0.2
	h[0].add_unit(section)
	h[0].add_unit(slow)
	section.apply_order(Order.form_up(root, Vector2(3, -3)))
	slow.apply_order(Order.form_up(section, Vector2(3, -3)))
	Formation.update_speed_caps(h[0].units)
	assert_near(root.formation_speed_cap_kn, slow.effective_max_speed())
	assert_near(section.formation_speed_cap_kn, slow.effective_max_speed())
	_clean(h)


class PictureProbe:
	extends AIController
	var seen: Dictionary = {}
	func _update_unit(u: Unit, _now: float) -> void:
		seen[u] = _inbound_on(u).size()


func test_ai_shared_geometry_preserves_per_ship_visibility_and_forgets_old_picture() -> void:
	var h := _harness()
	var victim: Unit = h[3]
	victim.spec.has_datalink = false
	var sensor := _ship()
	h[0].add_unit(sensor)
	var w := _round(victim)
	h[1].mark_detected("BLUE", w, 0, sensor)
	var ai := PictureProbe.new()
	ai.faction = "BLUE"
	ai.unit_manager = h[0]
	ai.threat_manager = h[1]
	ai.tick(0)
	assert_eq(ai.seen[victim], 0, "a disconnected victim cannot use another ship's detection")
	h[1].mark_detected("BLUE", w, 0, victim)
	ai.tick(1)
	assert_eq(ai.seen[victim], 1)
	h[1].forget(w)
	ai.tick(2)
	assert_eq(ai.seen[victim], 0, "the next cycle must discard the old geometry")
	ai.free()
	_clean(h)


func test_chart_cached_geometry_updates_observer_and_new_detections_while_paused() -> void:
	var h := _harness()
	var victim: Unit = h[3]
	victim.spec.has_datalink = false
	var sensor := _ship()
	h[0].add_unit(sensor)
	var chart := TacticalMap.new()
	chart.unit_manager = h[0]
	chart.threat_manager = h[1]
	chart.player_faction = "BLUE"
	chart.selected = [victim]
	var w := _round(victim)
	h[1].mark_detected("BLUE", w, 0, sensor)
	chart._refresh_threats()
	assert_eq(chart._threats.size(), 0)
	chart.selected = [sensor]
	chart._refresh_threats()
	assert_eq(chart._threats.size(), 1, "changing the observer refreshes visibility without advancing time")
	h[1].forget(w)
	chart._refresh_threats()
	assert_eq(chart._threats.size(), 0)
	h[1].mark_detected("BLUE", w, 0, victim)
	chart.selected = [victim]
	chart._refresh_threats()
	assert_eq(chart._threats.size(), 1, "a new detection invalidates geometry even while paused")
	w.phase = Weapon.Phase.DEAD
	chart._refresh_threats()
	assert_eq(chart._threats.size(), 0, "a resolved round vanishes immediately")
	chart.free()
	_clean(h)
