extends SceneTree
## The introductory guide through real viewport controls and real sensor reports.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var script: GDScript = load("res://tools/deep_command_playtest_run.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	await script.new().run(self)
