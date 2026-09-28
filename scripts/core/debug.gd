extends Node
## Autoload `Debug`. Global switch for debug visualization (true positions, ranges, AI states).
## Switched on by the dev harness (--debug). Everything debug-only must be gated behind `Debug.enabled`.
##
## Also the event log and the frame profiler. `event()` prints the simulation's running commentary
## ("[Combat] ... launches ...") only while `log_events` is on: in debug builds and scripted runs,
## so a player's browser console stays quiet. `profiling` makes the presentation's heavy paths
## report how long they took each frame (the harness's --perf).

signal toggled(enabled: bool)

var enabled := false
## The simulation's event log goes to standard output only while this is on.
var log_events := OS.is_debug_build()
## While on, the chart, the regional map, the data display and the 3D view add their frame time to
## `timings` (microseconds by name); the profiler reads and clears it every frame.
var profiling := false
var timings: Dictionary = {}


func toggle() -> void:
	enabled = not enabled
	toggled.emit(enabled)


## A line of the event log, printed only while `log_events` is on.
func event(text: String) -> void:
	if log_events:
		print(text)


## Adds a path's time this frame, in microseconds. Cheap to call unconditionally: one branch.
func time_add(path: String, usec: int) -> void:
	if profiling:
		timings[path] = int(timings.get(path, 0)) + usec
