extends SceneTree
## Headless test runner:
##   ~/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/run_tests.gd
##   ... --script tests/run_tests.gd -- --only=test_attack.gd,test_cds.gd   (a few files)

const TESTS := ["res://tests/test_save_migration.gd", "res://tests/test_commander_reports.gd", "res://tests/test_command_training.gd", "res://tests/test_world_fittings.gd", "res://tests/test_weapon_fidelity.gd", "res://tests/test_submarine_comms.gd", "res://tests/test_crew_profiles.gd", "res://tests/test_dipping_sonar.gd", "res://tests/test_operation_director.gd", "res://tests/test_sensor_cycle.gd", "res://tests/test_game_options.gd", "res://tests/test_group_attack.gd", "res://tests/test_ai_plans.gd", "res://tests/test_save.gd", "res://tests/test_air_missions.gd", "res://tests/test_station.gd", "res://tests/test_attack.gd", "res://tests/test_integrated_defence.gd", "res://tests/test_air_combat.gd", "res://tests/test_readout.gd", "res://tests/test_voice.gd", "res://tests/test_investigate.gd", "res://tests/test_weapon_plot.gd", "res://tests/test_combat_commands.gd", "res://tests/test_weapon_tracking.gd", "res://tests/test_patrol.gd", "res://tests/test_northern_passage.gd", "res://tests/test_qc_fixes.gd", "res://tests/test_weapon_control.gd", "res://tests/test_fleet_workshop.gd", "res://tests/test_operations.gd", "res://tests/test_regressions.gd", "res://tests/test_cold_war.gd", "res://tests/test_air_operations.gd", "res://tests/test_roster_m20.gd", "res://tests/test_lifecycle.gd", "res://tests/test_relative_motion.gd", "res://tests/test_clock.gd", "res://tests/test_tracking.gd", "res://tests/test_realism.gd", "res://tests/test_cic.gd", "res://tests/test_aegis.gd", "res://tests/test_systems.gd", "res://tests/test_geo.gd", "res://tests/test_movement.gd", "res://tests/test_sensors.gd", "res://tests/test_combat.gd", "res://tests/test_defence.gd", "res://tests/test_ai.gd", "res://tests/test_mission.gd", "res://tests/test_sonar.gd", "res://tests/test_aviation.gd", "res://tests/test_flight_deck.gd", "res://tests/test_ew.gd", "res://tests/test_terrain.gd", "res://tests/test_art.gd", "res://tests/test_ux.gd", "res://tests/test_ocean.gd", "res://tests/test_damage_control.gd", "res://tests/test_shore_strike.gd", "res://tests/test_world_view.gd", "res://tests/test_cds.gd", "res://tests/test_fits.gd", "res://tests/test_torpedo_defence.gd", "res://tests/test_chart.gd", "res://tests/test_sensor_coverage.gd", "res://tests/test_theme.gd"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var errors = load("res://tests/test_error_log.gd").new()
	OS.add_logger(errors)
	# The simulation's running commentary would drown the PASS and FAIL lines. The autoload is
	# reached through the tree: this script is compiled before the autoloads are registered.
	var debug := root.get_node_or_null("Debug")
	if debug != null:
		debug.log_events = false
	var total := 0
	var failed := 0
	var paths := TESTS.duplicate()
	if OS.get_cmdline_user_args().has("--self-test-runtime-error"):
		paths = ["res://tests/fixtures/runtime_error.gd"]
	# `-- --only=test_attack.gd,test_cds.gd` runs a few files while working on them.
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			var wanted := arg.get_slice("=", 1).split(",", false)
			paths = paths.filter(func(path: String) -> bool: return wanted.has(path.get_file()))
	for path in paths:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			print("ERROR %s failed to load (parse error above)" % path.get_file())
			failed += 1
			total += 1
			continue
		var t = script.new()
		if t == null:
			print("ERROR %s could not be instantiated" % path.get_file())
			failed += 1
			total += 1
			continue
		for m in script.get_script_method_list():
			var n: String = m["name"]
			if not n.begins_with("test_"):
				continue
			total += 1
			t.failures.clear()
			t.expected_engine_errors.clear()
			t.call(n)
			for error: String in errors.take_errors():
				var expected := false
				for message: String in t.expected_engine_errors.duplicate():
					if error.contains(message):
						t.expected_engine_errors.erase(message)
						expected = true
						break
				if not expected:
					t.failures.append("Unexpected engine error: " + error)
			for missing: String in t.expected_engine_errors:
				t.failures.append("Expected engine error was not raised: " + missing)
			if t.failures.is_empty():
				print("PASS  %s::%s" % [path.get_file(), n])
			else:
				failed += 1
				print("FAIL  %s::%s" % [path.get_file(), n])
				for f in t.failures:
					print("      " + f)
	print("---- %d tests, %d failed ----" % [total, failed])
	OS.remove_logger(errors)
	quit(1 if failed > 0 else 0)
