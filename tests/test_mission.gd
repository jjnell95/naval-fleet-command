extends TestCase
## Objectives are data. These tests drive MissionManager through scenario-shaped dictionaries,
## and check the shipped scenario files actually describe winnable, losable missions.


func _unit(faction: String, callsign: String, pos: Vector2, hp := 100.0) -> Unit:
	var spec := PlatformSpec.new()
	spec.short_name = "FFG Test"
	spec.max_speed_kn = 28.0
	spec.cruise_speed_kn = 14.0
	spec.health = hp
	var u := Unit.new()
	u.spec = spec
	u.faction = faction
	u.callsign = callsign
	u.position = pos
	u.health = hp
	return u


func _mission(units: Array, objectives: Dictionary) -> Array:
	var um := UnitManager.new()
	for u: Unit in units:
		um.add_unit(u)
	var mm := MissionManager.new()
	mm.unit_manager = um
	mm.player_faction = "BLUE"
	mm.configure({"id": "test", "objectives": objectives})
	var results: Array[String] = []
	mm.mission_ended.connect(func(r: String, _s: String) -> void: results.append(r))
	return [um, mm, results]


func _cleanup(h: Array) -> void:
	h[1].free()
	h[0].free()


# --- Predicates --------------------------------------------------------------------------

func test_destroying_the_enemy_force_wins() -> void:
	var blue := _unit("BLUE", "Escort", Vector2.ZERO)
	var red := _unit("RED", "Raider", Vector2(0.0, 10.0))
	var h := _mission([blue, red], {"victory": [{"type": "force_destroyed", "faction": "RED", "text": "Destroy the raider"}]})
	h[1].tick(0.0)
	assert_eq(h[1].result, MissionManager.Result.RUNNING, "still running while the enemy floats")
	Damage.apply(red, 500.0)
	h[1].tick(10.0)
	assert_eq(h[2].size(), 1)
	assert_eq(h[2][0], "VICTORY")
	h[1].tick(20.0)
	assert_eq(h[2].size(), 1, "the mission ends exactly once")
	_cleanup(h)


func test_losing_a_protected_ship_loses_the_mission() -> void:
	var escort := _unit("BLUE", "Escort", Vector2.ZERO)
	var convoy := _unit("BLUE", "Maud", Vector2(1.0, 0.0))
	var h := _mission([escort, convoy], {
		"victory": [{"type": "time_elapsed", "seconds": 3600.0, "text": "Survive the transit"}],
		"loss": [{"type": "unit_lost", "callsigns": ["Maud"], "text": "Maud sunk"}],
	})
	h[1].tick(100.0)
	assert_eq(h[1].result, MissionManager.Result.RUNNING)
	Damage.apply(convoy, 500.0)
	h[1].tick(110.0)
	assert_eq(h[2][0], "DEFEAT", "the high-value unit was the whole point")
	_cleanup(h)


func test_loss_is_checked_before_victory() -> void:
	# Both conditions become true in the same tick; losing the escorted ship must still lose.
	var convoy := _unit("BLUE", "Maud", Vector2.ZERO)
	var h := _mission([convoy], {
		"victory": [{"type": "time_elapsed", "seconds": 100.0, "text": "Survive"}],
		"loss": [{"type": "unit_lost", "callsigns": ["Maud"], "text": "Maud sunk"}],
	})
	Damage.apply(convoy, 500.0)
	h[1].tick(200.0)
	assert_eq(h[2][0], "DEFEAT")
	_cleanup(h)


func test_reaching_an_area_can_win_or_lose_depending_on_the_list() -> void:
	var convoy := _unit("BLUE", "Maud", Vector2(0.0, 60.0))
	var raider := _unit("RED", "Raider", Vector2(0.0, -60.0))
	var area := [0, 0]
	# Same predicate shape, opposite meanings.
	var h := _mission([convoy, raider], {
		"victory": [{"type": "reach_area", "faction": "BLUE", "center_nm": area, "radius_nm": 10.0, "text": "Reach the rendezvous"}],
		"loss": [{"type": "reach_area", "faction": "RED", "center_nm": area, "radius_nm": 10.0, "text": "Raider broke out"}],
	})
	h[1].tick(0.0)
	assert_eq(h[1].result, MissionManager.Result.RUNNING)
	raider.position = Vector2(0.0, 5.0)
	h[1].tick(10.0)
	assert_eq(h[2][0], "DEFEAT", "the enemy got through first")
	_cleanup(h)


func test_reach_area_victory() -> void:
	var convoy := _unit("BLUE", "Maud", Vector2(0.0, 60.0))
	var h := _mission([convoy], {"victory": [{"type": "reach_area", "faction": "BLUE", "center_nm": [0, 0], "radius_nm": 10.0, "text": "Reach the rendezvous"}]})
	h[1].tick(0.0)
	assert_eq(h[1].result, MissionManager.Result.RUNNING)
	convoy.position = Vector2(0.0, 8.0)
	h[1].tick(10.0)
	assert_eq(h[2][0], "VICTORY")
	_cleanup(h)


func test_reach_area_ignores_the_dead() -> void:
	var convoy := _unit("BLUE", "Maud", Vector2(0.0, 2.0))
	Damage.apply(convoy, 500.0)
	var h := _mission([convoy], {"victory": [{"type": "reach_area", "faction": "BLUE", "center_nm": [0, 0], "radius_nm": 10.0, "text": "Reach"}]})
	h[1].tick(10.0)
	assert_eq(h[1].result, MissionManager.Result.RUNNING, "a wreck drifting in the box is not an arrival")
	_cleanup(h)


func test_all_victory_objectives_must_complete() -> void:
	var blue := _unit("BLUE", "Escort", Vector2(0.0, 60.0))
	var red := _unit("RED", "Raider", Vector2(0.0, 10.0))
	var h := _mission([blue, red], {"victory": [
		{"type": "force_destroyed", "faction": "RED", "text": "Destroy the raider"},
		{"type": "reach_area", "faction": "BLUE", "center_nm": [0, 0], "radius_nm": 10.0, "text": "Then withdraw south"},
	]})
	Damage.apply(red, 500.0)
	h[1].tick(10.0)
	assert_eq(h[1].result, MissionManager.Result.RUNNING, "one of two is not enough")
	blue.position = Vector2(0.0, 4.0)
	h[1].tick(20.0)
	assert_eq(h[2][0], "VICTORY")
	_cleanup(h)


func test_completed_objectives_latch() -> void:
	var blue := _unit("BLUE", "Escort", Vector2(0.0, 4.0))
	var o := MissionObjective.from_dict({"type": "reach_area", "faction": "BLUE", "center_nm": [0, 0], "radius_nm": 10.0})
	var um := UnitManager.new()
	um.add_unit(blue)
	assert_true(o.evaluate(um, 0.0), "arrived")
	blue.position = Vector2(0.0, 400.0)
	assert_true(o.evaluate(um, 10.0), "a rendezvous once made stays made")
	um.free()


func test_force_destroyed_respects_max_alive() -> void:
	var a := _unit("RED", "R1", Vector2.ZERO)
	var b := _unit("RED", "R2", Vector2.ZERO)
	var h := _mission([a, b], {"victory": [{"type": "force_destroyed", "faction": "RED", "max_alive": 1, "text": "Cripple the group"}]})
	h[1].tick(0.0)
	assert_eq(h[1].result, MissionManager.Result.RUNNING)
	Damage.apply(a, 500.0)
	h[1].tick(10.0)
	assert_eq(h[2][0], "VICTORY", "one loss was enough for this objective")
	_cleanup(h)


func test_unknown_objective_type_does_not_complete() -> void:
	var o := MissionObjective.from_dict({"type": "not_a_real_type"})
	var um := UnitManager.new()
	assert_eq(o.kind, MissionObjective.Kind.UNKNOWN)
	assert_true(not o.evaluate(um, 99999.0), "an unrecognised objective never silently succeeds")
	um.free()


# --- Shipped scenarios -------------------------------------------------------------------

func test_every_shipped_scenario_is_playable() -> void:
	var all := ScenarioIndex.list_all()
	assert_true(all.size() >= 4, "at least four scenarios ship")
	for entry: Dictionary in all:
		var sc := ScenarioLoader.load_file(entry["path"])
		var label: String = entry["id"]
		assert_true(not sc.get("units", []).is_empty(), "%s has units" % label)
		assert_true(sc.has("player_faction"), "%s names the player's side" % label)
		var obj: Dictionary = sc.get("objectives", {})
		assert_true(not obj.get("victory", []).is_empty(), "%s can be won" % label)
		assert_true(not obj.get("loss", []).is_empty(), "%s can be lost" % label)
		for d in obj.get("victory", []) + obj.get("loss", []):
			assert_true(MissionObjective.from_dict(d).kind != MissionObjective.Kind.UNKNOWN, "%s uses a real objective type" % label)
		var player_units := 0
		for ud in sc["units"]:
			var spec := DataDB.platform(ud.get("platform", ""))
			assert_true(spec != null, "%s references platform %s" % [label, ud.get("platform", "?")])
			if spec != null:
				for wid in ud.get("loadout", spec.weapon_loadout):
					assert_true(DataDB.weapon(wid) != null, "%s: %s carries real weapon %s" % [label, spec.id, wid])
				for sid in spec.sensor_ids:
					assert_true(DataDB.sensor(sid) != null, "%s: %s uses real sensor %s" % [label, spec.id, sid])
			if ud.get("faction", "") == sc["player_faction"]:
				player_units += 1
		assert_true(player_units > 0, "%s gives the player something to command" % label)


func test_scenario_objectives_reference_real_callsigns() -> void:
	for entry: Dictionary in ScenarioIndex.list_all():
		var sc := ScenarioLoader.load_file(entry["path"])
		var callsigns := PackedStringArray()
		var factions := PackedStringArray()
		for ud in sc.get("units", []):
			callsigns.append(ud.get("callsign", ""))
			if not factions.has(ud.get("faction", "")):
				factions.append(ud.get("faction", ""))
		var obj: Dictionary = sc.get("objectives", {})
		for d in obj.get("victory", []) + obj.get("loss", []):
			for c in d.get("callsigns", []):
				assert_true(callsigns.has(str(c)), "%s: objective names ship '%s'" % [entry["id"], c])
			if d.has("faction"):
				assert_true(factions.has(str(d["faction"])), "%s: objective names faction '%s'" % [entry["id"], d["faction"]])
