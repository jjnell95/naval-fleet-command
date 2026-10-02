extends SceneTree
## One leg of tools/verify_save_continuation.py: run an operation straight to a time, or to a save
## point and write a save, or load a save in a fresh process and carry on. See that script.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Loaded at run time: the runner names classes that use the autoloads, which are not yet
	# registered when this script is compiled.
	var script: GDScript = load("res://tools/save_continuation_run.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	quit(script.new().run(self))
