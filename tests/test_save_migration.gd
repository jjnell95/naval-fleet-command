extends TestCase
## An older authored battle keeps recognition context without assigning IFF from unit truth.

const PASSAGE := "res://data/scenarios/northern_passage.json"


func _old_record() -> Dictionary:
	var scenario := ScenarioLoader.load_file(PASSAGE)
	scenario.erase("recognition_affiliations")
	return {"version": 2, "scenario": scenario, "scenario_path": PASSAGE, "scenario_digest": SimSnapshot.scenario_digest(scenario), "units": [{"faction": "UNRELATED"}]}


func test_legacy_authored_brief_migration_uses_static_library_without_mutating_input() -> void:
	var old := _old_record()
	var before := var_to_bytes(old)
	var migrated := SimSnapshot.migrate(old)
	assert_eq(migrated.version, SimSnapshot.VERSION)
	assert_eq(migrated.scenario.recognition_affiliations, ScenarioLoader.load_file(PASSAGE).recognition_affiliations)
	assert_eq(migrated.units, old.units, "saved force allegiances are not read or rewritten")
	assert_eq(migrated.scenario_digest, SimSnapshot.scenario_digest(migrated.scenario))
	assert_true(var_to_bytes(old) == before, "loading must not rewrite an in-memory snapshot")


func test_explicit_empty_briefs_custom_missions_and_new_format_are_not_inferred() -> void:
	var explicit := _old_record()
	explicit.scenario["recognition_affiliations"] = {}
	assert_true(SimSnapshot.migrate(explicit).scenario.recognition_affiliations.is_empty())
	var custom := _old_record()
	custom["scenario_path"] = "user://my_operations/copied_passage.json"
	assert_true(not SimSnapshot.migrate(custom).scenario.has("recognition_affiliations"), "a custom scenario with a built-in id retains its authored ambiguity")
	custom.scenario.id = "new_custom_operation"
	custom.scenario_path = "res://data/scenarios/new_custom_operation.json"
	assert_true(not SimSnapshot.migrate(custom).scenario.has("recognition_affiliations"))
	var current := _old_record()
	current.version = SimSnapshot.VERSION
	assert_true(not SimSnapshot.migrate(current).scenario.has("recognition_affiliations"), "new saves can intentionally omit a recognition brief")


func test_legacy_engagement_restores_brief_and_resaves_deterministically() -> void:
	SimClock.set_paused(true)
	var sim := Simulation.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	sim.seed_override = 31
	assert_true(sim.load_scenario(PASSAGE))
	var old := SimSnapshot.capture(sim)
	old.version = 2
	old.scenario.erase("recognition_affiliations")
	old.scenario_digest = SimSnapshot.scenario_digest(old.scenario)
	var original := var_to_bytes(old)
	assert_eq(sim.restore_snapshot(old), "")
	assert_true(not sim.track_manager.recognition_affiliations.is_empty(), "new reports in an old battle retain the authored faction recognition context")
	assert_true(var_to_bytes(old) == original)
	var resaved := SimSnapshot.capture(sim)
	assert_eq(resaved.version, SimSnapshot.VERSION)
	assert_eq(sim.restore_snapshot(resaved), "")
	assert_true(var_to_bytes(SimSnapshot.capture(sim)) == var_to_bytes(resaved), "a migrated engagement has a stable subsequent save/load")
	sim.unit_manager.clear()
	sim.free()
