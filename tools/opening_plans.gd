extends SceneTree
## One trial of tools/opening_plans.py: an operation flown headless from one scripted opening plan
## against the AI. See that script and tools/opening_plans_run.gd.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Loaded at run time: the runner names classes that use the autoloads, which are not yet
	# registered when this script is compiled.
	var script: GDScript = load("res://tools/opening_plans_run.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	quit(script.new().run(self))
