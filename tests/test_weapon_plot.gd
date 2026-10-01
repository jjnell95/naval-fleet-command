extends TestCase
## The chart must keep missile telemetry responsive while preserving observer visibility.


func _fixture() -> Dictionary:
	var map := TacticalMap.new()
	map.size = Vector2(1000, 600)
	map.ppn = 10.0
	map.unit_manager = UnitManager.new()
	map.weapon_manager = WeaponManager.new()
	map.threat_manager = ThreatManager.new()
	var own := Unit.new()
	own.id = 1
	own.spec = PlatformSpec.new()
	own.spec.has_datalink = true
	own.faction = "BLUE"
	own.callsign = "Friendly shooter"
	map.unit_manager.add_unit(own)
	map.selected.append(own)
	return {"map": map, "own": own}


func _round(id: int, faction: String) -> Weapon:
	var w := Weapon.new()
	w.id = id
	w.faction = faction
	w.spec = WeaponSpec.new()
	w.spec.display_name = "Test missile"
	w.spec.speed_kn = 1000
	w.spec.max_range_nm = 60
	w.position = Vector2(3, 0)
	w.aim_point = Vector2(20, 0)
	return w


func _free(f: Dictionary) -> void:
	var map: TacticalMap = f["map"]
	map.unit_manager.free()
	map.weapon_manager.free()
	map.threat_manager.free()
	map.free()


func test_hover_reports_own_weapon_telemetry_and_ignores_dead_rounds() -> void:
	var f := _fixture()
	var map: TacticalMap = f["map"]
	var w := _round(7, "BLUE")
	w.shooter = f["own"]
	var contact := Track.new()
	contact.id = "T1901"
	contact.position = w.aim_point
	w.target_track = contact
	map.weapon_manager.in_flight.append(w)
	var text := map._get_tooltip(map.world_to_screen(w.position))
	assert_true(text.contains("OWN WEAPON #7") and text.contains("Friendly shooter"))
	assert_true(text.contains("estimated") and text.contains("range remaining"))
	w.phase = Weapon.Phase.DEAD
	assert_eq(map._get_tooltip(map.world_to_screen(w.position)), "", "resolved rounds cannot be inspected")
	_free(f)


func test_hover_obeys_current_observer_and_keeps_enemy_launcher_private() -> void:
	var f := _fixture()
	var map: TacticalMap = f["map"]
	var own: Unit = f["own"]
	var enemy := Unit.new()
	enemy.callsign = "Hidden enemy launcher"
	var w := _round(8, "RED")
	w.shooter = enemy
	map.weapon_manager.in_flight.append(w)
	var at := map.world_to_screen(w.position)
	assert_eq(map._get_tooltip(at), "", "undetected rounds stay hidden")
	map.threat_manager.mark_detected("BLUE", w, 0, own)
	assert_true(map._get_tooltip(at).contains("DETECTED WEAPON #8"))
	assert_true(not map._get_tooltip(at).contains(enemy.callsign), "the chart cannot identify an enemy launcher from missile truth")
	var isolated := Unit.new()
	isolated.spec = PlatformSpec.new()
	isolated.spec.has_datalink = false
	isolated.faction = "BLUE"
	map.selected.assign([isolated])
	assert_eq(map._get_tooltip(at), "", "an isolated observer cannot inherit another ship's detection")
	_free(f)


func test_trails_sample_once_per_tick_and_refresh_on_paused_picture_changes() -> void:
	var f := _fixture()
	var map: TacticalMap = f["map"]
	var old_time := SimClock.sim_time
	SimClock.sim_time = 10
	var w := _round(1, "BLUE")
	map.weapon_manager.in_flight.append(w)
	map._record_weapon_trails()
	w.position += Vector2(1, 0)
	map._record_weapon_trails()
	assert_eq(map._weapon_trails[1].size(), 1, "intervening presentation frames do not rescan round positions")
	SimClock.sim_time += 0.25
	map._record_weapon_trails()
	assert_eq(map._weapon_trails[1].size(), 2, "simulation ticks preserve the actual curved trail")
	var incoming := _round(2, "RED")
	map.weapon_manager.in_flight.append(incoming)
	map.threat_manager.mark_detected("BLUE", incoming, SimClock.sim_time, f["own"])
	map._record_weapon_trails()
	assert_true(map._weapon_trails.has(2), "paused new detections appear immediately")
	map.threat_manager.forget(incoming)
	map._record_weapon_trails()
	assert_true(not map._weapon_trails.has(2), "lost missile detections leave no plotted trail")
	map.reset_presentation()
	map._record_weapon_trails()
	assert_eq(map._weapon_trails[1].size(), 1, "restart clears trail cache gates as well as history")
	SimClock.sim_time = old_time
	_free(f)
