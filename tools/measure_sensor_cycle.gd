extends SceneTree
## Measures the sensor cycle, the simulation tick and command responsiveness late in a large
## battle. See tools/measure_sensor_cycle_run.gd for the flags and what each number means.
##
## Before and after, interleaved in one process so machine load falls on both alike (the Taiwan
## Strait, seed 42, from 2400 s; 600 s stepped and 240 s on the 60x clock, three times each):
##
##   godot --headless --path . --script tools/measure_sensor_cycle.gd -- --paths=reference,optimized --repeats=3
##
## The first run plays the opening 2400 s once (several minutes) and keeps it under work/measure/.
## The 60x clock runs twice for each path, without and with SimClock's per-frame wall-time budget
## (--budget=on or --budget=off for one), and the first repeat replays each clocked run tick by
## tick to show frame pacing leaves the battle unchanged. Add --profile for every profiler path per
## tick and per cycle; --span=120 --clock-span=0 for a quick look.

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
