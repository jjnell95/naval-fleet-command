extends SceneTree
## Deliberate mixer playback check. Delayed loading lets the project autoloads initialise first.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var script: GDScript = load("res://tools/audio/audio_playtest_run.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	await script.new().run(self)
