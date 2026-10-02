extends Node
## Autoload `SimClock`. Owns simulation time and time acceleration and emits fixed-step ticks.
## All simulation systems run on `tick`; rendering stays frame-based.

signal tick(dt: float)
signal speed_changed(index: int, multiplier: float)
signal paused_changed(paused: bool)

## The Normal time ladder. The ladder in use can be shorter (a 4× ceiling); read speeds() rather
## than this constant anywhere a player picks a speed.
const SPEEDS: Array[float] = [1.0, 2.0, 5.0, 10.0, 30.0, 60.0]
const TICK_DT := 0.25
const MAX_TICKS_PER_FRAME := 480

var sim_time := 0.0  # seconds since scenario start
var start_unix_time := 0
var speed_index := 0  # into speeds(), not SPEEDS
var paused := true
var _accum := 0.0
var _last_wall_usec := 0
## The time scales the player may choose from, slowest first; always starts at real time. Only
## how fast the fixed ticks are emitted depends on it, never what they compute.
var _speeds: Array[float] = SPEEDS.duplicate()


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
	while not paused and _accum >= TICK_DT - 1e-9 and n < MAX_TICKS_PER_FRAME:
		_accum -= TICK_DT
		sim_time += TICK_DT
		n += 1
		tick.emit(TICK_DT)
	if n >= MAX_TICKS_PER_FRAME:
		_accum = 0.0  # drop backlog instead of spiralling
	Debug.time_add("sim", Time.get_ticks_usec() - t0)


## Synchronously advance the simulation (dev/test use). Emits ticks immediately.
func advance(seconds: float) -> void:
	var n := int(seconds / TICK_DT)
	for i in n:
		sim_time += TICK_DT
		tick.emit(TICK_DT)


func multiplier() -> float:
	return _speeds[clampi(speed_index, 0, _speeds.size() - 1)]


## The ladder in use, slowest first. A copy: change it with set_speeds or set_ceiling.
func speeds() -> Array[float]:
	return _speeds.duplicate()


## The fastest time scale the ladder allows.
func ceiling() -> float:
	return _speeds[_speeds.size() - 1]


## Replaces the ladder. A list that is not usable (empty, not starting at real time, not rising)
## falls back to the Normal ladder. The watch keeps the fastest new speed that is no faster than
## the one it was running at, so a lower ceiling slows it down and never speeds it up.
func set_speeds(list: Array) -> void:
	var clean: Array[float] = []
	for v in list:
		clean.append(float(v))
	if not valid_ladder(clean):
		clean = SPEEDS.duplicate()
	var current := multiplier()
	var index := 0
	for i in clean.size():
		if clean[i] <= current + 1e-6:
			index = i
	var changed := clean != _speeds or index != speed_index
	_speeds = clean
	speed_index = index
	if changed:
		_accum = 0.0
		speed_changed.emit(speed_index, multiplier())


## The Normal ladder up to `max_multiplier`, with the ceiling itself as the last step: a 4× ceiling
## gives 1×, 2×, 4×.
func set_ceiling(max_multiplier: float) -> void:
	set_speeds(ladder_to(max_multiplier))


static func ladder_to(max_multiplier: float) -> Array[float]:
	var out: Array[float] = []
	for v in SPEEDS:
		if v < max_multiplier - 1e-6:
			out.append(v)
	out.append(maxf(max_multiplier, 1.0))
	return out


## Starts at real time, rises, and has at most one step per number key (1 to 6).
static func valid_ladder(list: Array) -> bool:
	if list.is_empty() or list.size() > SPEEDS.size() or not is_equal_approx(float(list[0]), 1.0):
		return false
	for i in range(1, list.size()):
		if float(list[i]) <= float(list[i - 1]) or float(list[i]) > SPEEDS[SPEEDS.size() - 1]:
			return false
	return true


func set_speed_index(i: int) -> void:
	i = clampi(i, 0, _speeds.size() - 1)
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
