extends SceneTree
## Load the real-scene driver after autoloads are registered.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await load("res://tools/passage_playtest_run.gd").new().run(self)
