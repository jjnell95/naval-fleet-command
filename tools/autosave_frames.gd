extends SceneTree
## Measures what an autosave costs the frames it falls in, on the command screen itself:
## --scenario= --seed= --ff=S (simulated seconds before the save) --autopilot --no-worker
## (write as the browser build does, without a worker thread) --output-dir=res://work/x

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var script: GDScript = load("res://tools/autosave_frames_run.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	var code: int = await script.new().run(self)
	quit(code)
