extends Node
## Autoload `SimClock`. Owns simulation time and time acceleration and emits fixed-step ticks.
## All simulation systems run on `tick`; rendering stays frame-based.

signal tick(dt: float)
signal speed_changed(index: int, multiplier: float)
signal paused_changed(paused: bool)

const SPEEDS: Array[float] = [1.0, 2.0, 5.0, 10.0, 30.0, 60.0]
const TICK_DT := 0.25
const MAX_TICKS_PER_FRAME := 480
## GAMEPLAY_ESTIMATE: the wall time one frame may spend stepping the simulation before it lets the
## chart draw. When the battle is too heavy for the chosen speed, a frame stops here and drops the
## rest of its backlog, so the clock runs slower than asked instead of the screen freezing: late in
## the Taiwan Strait a 60x frame otherwise steps up to 240 ticks of about 15 ms each and holds the
## screen, and every order, for three seconds and more. 50 ms plus a frame's drawing keeps the
## chart at roughly 12-20 frames a second and an order on screen in about a tenth of a second, the
## usual limit for a response to feel immediate. It costs only the drawing time of the extra
## frames (about a sixth of the throughput with 10 ms frames) and only while the simulation cannot
## keep up; a light battle does not reach it. At least one tick always runs, however slow.
const FRAME_BUDGET_USEC := 50000

var sim_time := 0.0  # seconds since scenario start
var start_unix_time := 0
var speed_index := 0
var paused := true
## The budget in force; 0 turns it off (tests and tools/measure_sensor_cycle.gd compare the two).
var frame_budget_usec := FRAME_BUDGET_USEC
var _accum := 0.0
var _last_wall_usec := 0


func _process(delta: float) -> void:
	if is_inside_tree():
		_process_wall_frame(delta, Time.get_ticks_usec())
	else:
		# Standalone clock tests provide explicit elapsed time.
		_advance_frame(delta)


func _process_wall_frame(engine_delta: float, now_usec: int) -> void:
	var elapsed := engine_delta if _last_wall_usec == 0 else maxf(float(now_usec - _last_wall_usec) / 1000000.0, 0.0)
	_last_wall_usec = now_usec
	# OS suspension must not enqueue minutes of catch-up. Ordinary frame stalls remain real time.
	_advance_frame(minf(elapsed, 1.0))


func _advance_frame(delta: float) -> void:
	if paused:
		return
	var t0 := Time.get_ticks_usec()
	_accum += delta * multiplier()
	var n := 0
	var over_budget := false
	while not paused and _accum >= TICK_DT - 1e-9 and n < MAX_TICKS_PER_FRAME:
		if n > 0 and frame_budget_usec > 0 and Time.get_ticks_usec() - t0 >= frame_budget_usec:
			over_budget = true
			break
		_accum -= TICK_DT
		sim_time += TICK_DT
		n += 1
		tick.emit(TICK_DT)
	if n >= MAX_TICKS_PER_FRAME or over_budget:
		_accum = 0.0  # drop backlog instead of spiralling
	Debug.time_add("sim", Time.get_ticks_usec() - t0)


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
	_last_wall_usec = 0
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
	_last_wall_usec = 0
	start_unix_time = start_unix


func datetime_string() -> String:
	if start_unix_time > 0:
		return Time.get_datetime_string_from_unix_time(start_unix_time + int(sim_time), true) + "Z"
	return Geo.format_duration(sim_time)
