extends SceneTree
## Headless test runner:
##   ~/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/run_tests.gd

const TESTS := ["res://tests/test_realism.gd", "res://tests/test_cic.gd", "res://tests/test_aegis.gd", "res://tests/test_systems.gd", "res://tests/test_geo.gd", "res://tests/test_movement.gd", "res://tests/test_sensors.gd", "res://tests/test_combat.gd", "res://tests/test_defence.gd", "res://tests/test_ai.gd", "res://tests/test_mission.gd", "res://tests/test_sonar.gd", "res://tests/test_aviation.gd", "res://tests/test_ew.gd", "res://tests/test_terrain.gd", "res://tests/test_art.gd", "res://tests/test_ux.gd", "res://tests/test_ocean.gd", "res://tests/test_damage_control.gd"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var total := 0
	var failed := 0
	for path in TESTS:
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
			t.call(n)
			if t.failures.is_empty():
				print("PASS  %s::%s" % [path.get_file(), n])
			else:
				failed += 1
				print("FAIL  %s::%s" % [path.get_file(), n])
				for f in t.failures:
					print("      " + f)
	print("---- %d tests, %d failed ----" % [total, failed])
	quit(1 if failed > 0 else 0)
