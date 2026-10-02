extends SceneTree
## Air missions and stations through the real screen; use Xvfb and --resolution, optionally
## --capture and --output-dir=res://work/<name> to keep screenshots and the JSON record.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var script: GDScript = load("res://tools/air_mission_playtest_run.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	await script.new().run(self)
