extends Node
## Autoload `SimClock`. Owns simulation time and time acceleration and emits fixed-step ticks.
## All simulation systems run on `tick`; rendering stays frame-based.

signal tick(dt: float)
signal speed_changed(index: int, multiplier: float)
signal paused_changed(paused: bool)

const SPEEDS: Array[float] = [1.0, 2.0, 5.0, 10.0, 30.0, 60.0]
const TICK_DT := 0.25
const MAX_TICKS_PER_FRAME := 480

var sim_time := 0.0  # seconds since scenario start
var start_unix_time := 0
var speed_index := 0
var paused := true
var _accum := 0.0


func _process(delta: float) -> void:
	if paused:
		return
	_accum += delta * multiplier()
	var n := 0
	while not paused and _accum >= TICK_DT - 1e-9 and n < MAX_TICKS_PER_FRAME:
		_accum -= TICK_DT
		sim_time += TICK_DT
		n += 1
		tick.emit(TICK_DT)
	if n >= MAX_TICKS_PER_FRAME:
		_accum = 0.0  # drop backlog instead of spiralling


## Synchronously advance the simulation (dev/test use). Emits ticks immediately.
func advance(seconds: float) -> void:
	var n := int(seconds / TICK_DT)
	for i in n:
		sim_time += TICK_DT
		tick.emit(TICK_DT)


func multiplier() -> float:
	return SPEEDS[speed_index]


func set_speed_index(i: int) -> void:
	i = clampi(i, 0, SPEEDS.size() - 1)
	if i == speed_index:
		return
	# A tick may trigger combat slowdown. Its old accelerated backlog must not keep
	# advancing the battle after the player has been handed control at real time.
	_accum = 0.0
	speed_index = i
	speed_changed.emit(speed_index, multiplier())


func set_paused(p: bool) -> void:
	if p == paused:
		return
	_accum = 0.0
	paused = p
	paused_changed.emit(paused)


func toggle_pause() -> void:
	set_paused(not paused)


## For combat events (missile launch, torpedo detected, unit lost): fall back to real time.
func drop_to_realtime() -> void:
	set_speed_index(0)


func reset(start_unix := 0) -> void:
	sim_time = 0.0
	_accum = 0.0
	start_unix_time = start_unix


func datetime_string() -> String:
	if start_unix_time > 0:
		return Time.get_datetime_string_from_unix_time(start_unix_time + int(sim_time), true) + "Z"
	return Geo.format_duration(sim_time)
