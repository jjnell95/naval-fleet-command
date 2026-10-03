extends SceneTree
## Native workflow check. Run with --resolution 1280x720 -- --ui-scale=125 --capture.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var script: GDScript = load("res://tools/fidelity_playtest_run.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	await script.new().run(self)
