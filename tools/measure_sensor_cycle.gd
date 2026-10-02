extends SceneTree
## Measures the sensor cycle, the simulation tick and command responsiveness late in a large
## battle. See tools/measure_sensor_cycle_run.gd for the flags and what each number means.
##
##   godot --headless --path . --script tools/measure_sensor_cycle.gd -- --from=2400 --span=600

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Loaded at run time: the runner names classes that use the autoloads, which are not yet
	# registered when this script is compiled.
	var script: GDScript = load("res://tools/measure_sensor_cycle_run.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	quit(await script.new().run(self))
