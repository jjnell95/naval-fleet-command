extends SceneTree
## Run after autoloads are ready, like the other native playtests.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var script: GDScript = load("res://tools/operational_fittings_playtest_run.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	await script.new().run(self)
