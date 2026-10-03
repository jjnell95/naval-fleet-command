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
	expect_engine_error("MissionObjective: unknown type")
	var o := MissionObjective.from_dict({"type": "not_a_real_type"})
	var um := UnitManager.new()
	assert_eq(o.kind, MissionObjective.Kind.UNKNOWN)
	assert_true(not o.evaluate(um, 99999.0), "an unrecognised objective never silently succeeds")
	um.free()


# --- Shipped scenarios -------------------------------------------------------------------

# --- Mission effectiveness and the commander's log ----------------------------------------

func _category(u: Unit, category: String) -> Unit:
	u.spec.category = category
	return u


func test_effectiveness_grades_task_force_and_attrition() -> void:
	var escort := _category(_unit("BLUE", "Escort", Vector2.ZERO), "frigate")
	var raider := _category(_unit("RED", "Raider", Vector2(0.0, 10.0), 100.0), "destroyer")
	var h := _mission([escort, raider], {"victory": [{"type": "force_destroyed", "faction": "RED", "text": "Destroy the raider"}]})
	var mm: MissionManager = h[1]
	mm.tick(0.0)
	var a := mm.assessment()
	assert_eq(a["task_done"], 0)
	assert_eq(a["hostile_points"], 400)
	assert_eq(a["friendly_points"], 250)
	assert_eq(a["percent"], 20, "nothing done yet: only the intact force counts")
	Damage.apply(raider, 50.0, "asm", "BLUE")
	a = mm.assessment()
	assert_near(float(a["attrition"]), 10.0, 0.01, "half the raider's points for half its health")
	assert_eq(a["percent"], 30)
	Damage.apply(raider, 500.0, "asm", "BLUE")
	mm.tick(10.0)
	assert_eq(mm.result, MissionManager.Result.VICTORY)
	a = mm.assessment()
	assert_eq(a["percent"], 100, "task done, force intact, enemy sunk")
	assert_eq(MissionManager.assessment_text(a), "Task 60/60 · Force 20/20 · Attrition 20/20 = 100%")
	_cleanup(h)


func test_effectiveness_charges_own_losses_and_neutral_sinkings() -> void:
	var escort := _category(_unit("BLUE", "Escort", Vector2.ZERO), "frigate")
	var convoy := _category(_unit("BLUE", "Maud", Vector2(1.0, 0.0)), "merchant")
	var raider := _category(_unit("RED", "Raider", Vector2(0.0, 10.0)), "corvette")
	var trawler := _category(_unit("NEUTRAL", "Trawler", Vector2(5.0, 5.0)), "fishing vessel")
	var um := UnitManager.new()
	for u: Unit in [escort, convoy, raider, trawler]:
		um.add_unit(u)
	var mm := MissionManager.new()
	mm.unit_manager = um
	mm.player_faction = "BLUE"
	mm.configure({"id": "test", "neutral_factions": ["NEUTRAL"], "objectives": {"victory": [{"type": "time_elapsed", "seconds": 3600.0, "text": "Survive"}], "loss": [{"type": "unit_lost", "callsigns": ["Maud"], "text": "Maud lost"}]}})
	var a := mm.assessment()
	assert_eq(a["friendly_points"], 550, "frigate 250 and merchant 300")
	assert_eq(a["percent"], 20)
	Damage.apply(convoy, 1000.0, "asm", "RED")
	mm.tick(10.0)
	assert_eq(mm.result, MissionManager.Result.DEFEAT)
	a = mm.assessment()
	assert_near(float(a["force"]), 20.0 * 250.0 / 550.0, 0.01, "the merchant's share of the force is gone")
	assert_eq(a["percent"], 9)
	Damage.apply(trawler, 1000.0, "asm", "BLUE")
	a = mm.assessment()
	assert_eq(a["neutral_hit"], 1)
	assert_near(float(a["civilian"]), 25.0, 0.01, "a neutral sunk by the player's weapons costs a quarter of the scale")
	assert_eq(a["percent"], 0, "and the grade cannot go below zero")
	assert_true(MissionManager.assessment_text(a).contains("Civilian −25"))
	Damage.apply(raider, 1000.0, "asm", "RED")
	assert_eq(mm.assessment()["attrition"], 20.0, "an enemy lost to anyone counts: the sea is cleared")
	mm.free()
	um.free()


func test_any_mode_victory_is_the_whole_task_and_a_defeat_earns_no_task_share() -> void:
	var escort := _category(_unit("BLUE", "Escort", Vector2.ZERO), "frigate")
	var kilo := _category(_unit("RED", "Kilo", Vector2(0.0, 10.0)), "diesel-electric submarine")
	var h := _mission([escort, kilo], {"victory": [
		{"id": "watch", "type": "time_elapsed", "seconds": 600.0, "text": "Hold the watch"},
		{"id": "sink", "type": "all_units_lost", "callsigns": ["Kilo"], "text": "Sink the Kilo"}]})
	var mm: MissionManager = h[1]
	mm.victory_mode = "any"
	mm.tick(700.0)
	assert_eq(mm.result, MissionManager.Result.VICTORY, "holding the watch wins an any-mode mission")
	var a := mm.assessment()
	assert_eq(a["task"], MissionManager.TASK_WEIGHT, "one way of winning taken is the whole task")
	assert_eq(a["percent"], 80, "a flawless watch: task and force, no attrition")
	_cleanup(h)
	var ship := _category(_unit("BLUE", "Escort", Vector2.ZERO), "frigate")
	var raider := _category(_unit("RED", "Raider", Vector2(0.0, 10.0)), "corvette")
	var convoy := _category(_unit("BLUE", "Maud", Vector2(1.0, 0.0)), "merchant")
	var g := _mission([ship, raider, convoy], {
		"victory": [{"id": "a", "type": "force_destroyed", "faction": "RED", "text": "Sink the raider"}, {"id": "b", "type": "time_elapsed", "seconds": 3600.0, "text": "Hold"}],
		"loss": [{"type": "unit_lost", "callsigns": ["Maud"], "text": "Maud lost"}]})
	var gm: MissionManager = g[1]
	Damage.apply(raider, 1000.0, "asm", "BLUE")
	gm.tick(10.0)
	assert_eq(gm.assessment()["task_done"], 1, "half the task is done while running")
	Damage.apply(convoy, 1000.0, "asm", "RED")
	gm.tick(20.0)
	assert_eq(gm.result, MissionManager.Result.DEFEAT)
	var d := gm.assessment()
	assert_eq(d["task"], 0.0, "a lost mission earns no task share")
	assert_true(int(d["percent"]) <= int(MissionManager.FORCE_WEIGHT + MissionManager.ATTRITION_WEIGHT), "so a defeat never grades like a victory")
	_cleanup(g)


func test_aircraft_aboard_a_sunk_ship_count_as_lost_with_her() -> void:
	var carrier := _category(_unit("BLUE", "Carrier", Vector2.ZERO), "carrier")
	var fighter := _category(_unit("BLUE", "Fighter 1", Vector2.ZERO), "fighter")
	fighter.spec.domain = "air"
	fighter.flight_state = Unit.FlightState.STOWED
	fighter.home = carrier
	var h := _mission([carrier, fighter], {"victory": [{"type": "time_elapsed", "seconds": 99999.0, "text": "Hold"}]})
	var mm: MissionManager = h[1]
	assert_eq(mm.assessment()["friendly_lost"], 0.0)
	Damage.apply(carrier, 1000.0, "asm", "RED")
	assert_true(fighter.alive, "aviation has not swept the deck yet")
	assert_near(float(mm.assessment()["friendly_lost"]), 1060.0, 0.01, "the carrier's 1000 and the fighter's 60 are both gone")
	fighter.home = null
	_cleanup(h)


func test_platform_points_follow_category_then_domain_then_authored_value() -> void:
	var spec := PlatformSpec.new()
	spec.category = "carrier"
	assert_eq(MissionManager.platform_points(spec), 1000)
	spec.category = "an unusual hull"
	spec.domain = "subsurface"
	assert_eq(MissionManager.platform_points(spec), 300, "an unlisted category falls back to its domain")
	assert_eq(MissionManager.platform_points(spec, 42), 42, "a scenario's own value wins")
	assert_eq(MissionManager.platform_points(null), 0)
	var sc := ScenarioLoader.load_file("res://data/scenarios/northern_passage.json")
	var um := UnitManager.new()
	ScenarioLoader.populate(um, sc)
	var total := 0
	for u: Unit in um.units:
		total += MissionManager.platform_points(u.spec, u.points)
	assert_true(total > 0, "every shipped unit is worth something")
	um.free()


func test_commander_log_keeps_the_best_result_and_counts_attempts() -> void:
	CommanderLog.path_override = "user://test_commander_log.json"
	CommanderLog.clear()
	assert_eq(CommanderLog.best("op"), {})
	var first := CommanderLog.record("op", "DEFEAT", 70, "2026-10-01T08:00:00Z")
	assert_true(bool(first["improved"]))
	assert_eq(int(first["attempts"]), 1)
	var second := CommanderLog.record("op", "VICTORY", 60, "2026-10-01T09:00:00Z")
	assert_true(bool(second["improved"]), "a victory outranks a defeat with a higher percentage")
	var third := CommanderLog.record("op", "VICTORY", 55, "2026-10-01T10:00:00Z")
	assert_true(not bool(third["improved"]))
	var best := CommanderLog.best("op")
	assert_eq(int(best["best_percent"]), 60)
	assert_eq(best["result"], "VICTORY")
	assert_eq(best["date"], "2026-10-01T09:00:00Z")
	assert_eq(int(best["attempts"]), 3)
	assert_eq(int(best["last_percent"]), 55)
	assert_eq(CommanderLog.record("", "VICTORY", 90, ""), {}, "an unnamed scenario is not logged")
	CommanderLog.clear()
	assert_eq(CommanderLog.best("op"), {})
	CommanderLog.path_override = ""


func test_a_damaged_commander_log_reads_as_typed_entries_and_can_be_written_again() -> void:
	CommanderLog.path_override = "user://test_commander_log_damaged.json"
	var f := FileAccess.open(CommanderLog.path_override, FileAccess.WRITE)
	f.store_string('{"op": {"best_percent": null, "result": 7, "attempts": "many"}, "junk": [1, 2], "big": {"best_percent": 400}}')
	f.close()
	var all := CommanderLog.load_all()
	assert_true(not all.has("junk"), "a value that is not an entry is dropped")
	assert_eq(all["op"]["best_percent"], 0, "a value that is not a number reads as none")
	assert_eq(typeof(all["op"]["result"]), TYPE_STRING, "a result is always text")
	assert_eq(all["op"]["attempts"], 1)
	assert_eq(all["big"]["best_percent"], 100, "and a percentage stays a percentage")
	var entry := CommanderLog.record("op", "VICTORY", 72, "2026-10-01 09:00:00")
	assert_true(bool(entry["improved"]), "the damaged entry is replaced, not stuck")
	assert_eq(int(CommanderLog.best("op")["best_percent"]), 72)
	f = FileAccess.open(CommanderLog.path_override, FileAccess.WRITE)
	f.store_string("not json at all")
	f.close()
	assert_eq(CommanderLog.load_all(), {}, "an unreadable file is an empty log")
	CommanderLog.clear()
	CommanderLog.path_override = ""


func test_campaigns_hold_every_operation_once_in_date_order() -> void:
	var campaigns := CampaignBook.load_all()
	assert_eq(campaigns.size(), 2, "1990 and 2027")
	var shipped := {}
	for e: Dictionary in ScenarioIndex.list_all():
		if not e["custom"] and e["collection"] == "operations":
			shipped[str(e["id"])] = e
	var seen := {}
	for c: Dictionary in campaigns:
		assert_eq(int(c["gate_percent"]), 60, "a clean victory opens the next operation")
		var previous := ""
		for id: String in c["operations"]:
			assert_true(shipped.has(id), "%s is a shipped operation" % id)
			assert_true(not seen.has(id), "%s sits in one campaign only" % id)
			seen[id] = true
			var date := str(ScenarioLoader.load_file(shipped[id]["path"]).get("start_time_utc", ""))
			assert_true(date > previous, "%s follows the operation before it in time" % id)
			previous = date
	assert_eq(seen.size(), shipped.size(), "every operation on the desk belongs to a campaign")

func _states(log: Dictionary) -> Array:
	return CampaignBook.steps(CampaignBook.load_all()[0], log).map(func(s: Dictionary) -> String: return s["state"])

func test_a_campaign_opens_each_operation_on_a_clean_win_of_the_one_before() -> void:
	assert_eq(_states({}), ["open", "locked", "locked"], "the first operation is open from the start")
	assert_eq(_states({"cold_war_03_carrier": {"result": "VICTORY", "best_percent": 90}}), ["open", "locked", "locked"], "a win from the Operations shelf does not skip the order")
	var log := {"cold_war_01_convoy": {"result": "VICTORY", "best_percent": 72}}
	assert_eq(_states(log), ["won", "open", "locked"])
	log["cold_war_02_barrier"] = {"result": "DEFEAT", "best_percent": 35}
	assert_eq(_states(log), ["won", "open", "locked"], "a defeat opens nothing")
	log["cold_war_02_barrier"] = {"result": "VICTORY", "best_percent": 55}
	assert_eq(_states(log), ["won", "open", "locked"], "nor does a win spoiled by a sunk neutral")
	log["cold_war_02_barrier"] = {"result": "VICTORY", "best_percent": 64}
	assert_eq(_states(log), ["won", "won", "open"])
	var progress := CampaignBook.progress(CampaignBook.load_all()[0], log)
	assert_eq(progress["won"], 2)
	assert_eq(progress["average"], 45, "an unplayed operation counts as nothing")
	log["cold_war_03_carrier"] = "damaged"
	assert_eq(_states(log), ["won", "won", "open"], "a damaged record reads as unplayed")

func test_the_debrief_names_what_a_campaign_result_opens() -> void:
	var won := AfterAction.campaign_line("cold_war_01_convoy", {"cold_war_01_convoy": {"result": "VICTORY", "best_percent": 72}})
	assert_true(won.contains("cleared") and won.contains("THE ICELAND-FAROE BARRIER is open"), won)
	var short := AfterAction.campaign_line("cold_war_01_convoy", {"cold_war_01_convoy": {"result": "VICTORY", "best_percent": 55}})
	assert_true(short.contains("win at 60% or better to open THE ICELAND-FAROE BARRIER"), short)
	var last := AfterAction.campaign_line("med_01_tartus", {"aegis_bastion": {"result": "VICTORY", "best_percent": 80},
		"pacific_02_taiwan_strait": {"result": "VICTORY", "best_percent": 70}, "gulf_01_hormuz": {"result": "VICTORY", "best_percent": 60},
		"med_01_tartus": {"result": "VICTORY", "best_percent": 90}})
	assert_true(last.contains("The campaign is complete, averaging 75%"), last)
	assert_eq(AfterAction.campaign_line("northern_passage", {}), "", "training is in no campaign")
	var ahead := AfterAction.campaign_line("pacific_02_taiwan_strait", {"pacific_02_taiwan_strait": {"result": "VICTORY", "best_percent": 80}})
	assert_true(ahead.contains("is not open yet") and ahead.contains("Win NORTH CAPE / BALLISTIC MISSILE DEFENCE at 60% or better first"), ahead)
	assert_true(ahead.contains("this 80% win counts once the campaign reaches it"), "a win flown ahead of the campaign is credited, not contradicted")
	assert_true(not ahead.contains("to open STRAIT OF HORMUZ"), "and the debrief does not ask for the win just flown")


func _write_probe(path: String, name: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"id": "custom_index_probe", "name": name, "player_faction": "BLUE", "units": [],
		"objectives": {"victory": [], "loss": []}}))
	f.close()

func _probe_name() -> String:
	for e: Dictionary in ScenarioIndex.list_all():
		if e["id"] == "custom_index_probe":
			return e["name"]
	return ""

func test_the_desk_index_parses_shipped_missions_once_and_rereads_a_changed_custom_one() -> void:
	var first := ScenarioIndex.list_all()
	var parsed := ScenarioIndex.parses
	var shipped := first.filter(func(e: Dictionary) -> bool: return not e["custom"])
	assert_eq(shipped.size(), 11, "seven operations and four training missions ship")
	first[0]["name"] = "scribbled on by a caller"
	var again := ScenarioIndex.list_all()
	assert_eq(ScenarioIndex.parses, parsed, "a second refresh parses nothing it has already read")
	assert_true(again[0]["name"] != "scribbled on by a caller", "callers get copies, not the cache")
	ScenarioIndex.ensure_user_dir()
	var path := ScenarioIndex.custom_path("custom_index_probe")
	_write_probe(path, "Probe A")
	assert_eq(_probe_name(), "Probe A", "a new custom mission appears")
	_write_probe(path, "Probe Bee")
	assert_eq(_probe_name(), "Probe Bee", "a rewrite of a different length is seen at once")
	_write_probe(path, "Probe Cee")
	ScenarioIndex.forget(path)
	assert_eq(_probe_name(), "Probe Cee", "and a same-length rewrite once the writer says so")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_eq(_probe_name(), "", "a deleted mission leaves the desk")
	ScenarioIndex.forget(path)


func test_the_commander_log_lives_beside_the_mission_library_not_in_it() -> void:
	assert_eq(CommanderLog.path(), "user://commander_log.json", "in play, beside user://scenarios")
	assert_true(not CommanderLog.path().begins_with(ScenarioIndex.USER_ROOT + "/"), "never inside the library the desk scans")

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
