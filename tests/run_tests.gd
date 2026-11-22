extends SceneTree
## Headless test runner:
##   ~/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/run_tests.gd
##   ... --script tests/run_tests.gd -- --only=test_attack.gd,test_cds.gd   (a few files)

## Files in tests/ that match test_*.gd but hold no tests.
const HELPERS := ["test_case.gd", "test_error_log.gd"]


## Every tests/test_*.gd in name order, so a new test file needs no registration here.
static func discover() -> Array[String]:
	var found: Array[String] = []
	for file: String in DirAccess.get_files_at("res://tests"):
		if file.begins_with("test_") and file.ends_with(".gd") and not HELPERS.has(file):
			found.append("res://tests/" + file)
	found.sort()
	return found


## The simulation keeps its chart, sea floor and environment in statics. A test file that loads a
## coast must not hand it to the next file, so every file starts from open ocean in daylight.
static func reset_world() -> void:
	Terrain.clear()
	Bathymetry.clear()
	Detection.sea_state = 0
	Detection.environment = {}
	Detection.light = 1.0
	Detection.jammers = []
	SubmarinePower.events.clear()


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
	var paths := discover()
	if OS.get_cmdline_user_args().has("--self-test-runtime-error"):
		paths = ["res://tests/fixtures/runtime_error.gd"]
	# `-- --only=test_attack.gd,test_cds.gd` runs a few files while working on them.
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			var wanted := arg.get_slice("=", 1).split(",", false)
			paths = paths.filter(func(path: String) -> bool: return wanted.has(path.get_file()))
	for path in paths:
		reset_world()
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
