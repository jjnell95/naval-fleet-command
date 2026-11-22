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
## How long the achieved rate takes to follow a change (seconds of wall time): long enough to read
## steadily through the tick quantisation at 1x, short enough to show a heavy moment as it comes.
const RATE_SMOOTHING_S := 1.5
## The achieved rate is shown beside the asked one once it falls below this share of it.
const RATE_SHORTFALL := 0.9

var sim_time := 0.0  # seconds since scenario start
var start_unix_time := 0
var speed_index := 0  # into speeds(), not SPEEDS
var paused := true
## The budget in force; 0 turns it off (tests and tools/measure_sensor_cycle.gd compare the two).
var frame_budget_usec := FRAME_BUDGET_USEC
var _accum := 0.0
var _last_wall_usec := 0
## Simulation seconds actually stepped per wall second, smoothed. It is the asked rate until a frame
## has to drop backlog it had no time for. Presentation only: no tick reads it.
var _achieved := 1.0
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
	var over_budget := false
	while not paused and _accum >= TICK_DT - 1e-9 and n < MAX_TICKS_PER_FRAME:
		if n > 0 and frame_budget_usec > 0 and Time.get_ticks_usec() - t0 >= frame_budget_usec:
			over_budget = true
			break
		_accum -= TICK_DT
		sim_time += TICK_DT
		n += 1
		tick.emit(TICK_DT)
	var dropped := 0.0
	if n >= MAX_TICKS_PER_FRAME or over_budget:
		dropped = _accum
		_accum = 0.0  # drop backlog instead of spiralling
	_note_rate(delta, delta * multiplier() - dropped)
	Debug.time_add("sim", Time.get_ticks_usec() - t0)


## Folds one frame into the achieved rate: the simulation time the frame was owed, less what it
## dropped for want of time, over the wall time it took.
func _note_rate(wall_s: float, sim_s: float) -> void:
	if wall_s <= 0.0:
		return
	var sample := maxf(sim_s, 0.0) / wall_s
	_achieved += (sample - _achieved) * (1.0 - exp(-wall_s / RATE_SMOOTHING_S))


## The time rate the simulation is actually running at, smoothed over the last second or two.
func achieved_rate() -> float:
	return _achieved


## True when the simulation is running well short of the asked rate: the battle costs more per
## tick than the frame budget allows at this speed.
func rate_short() -> bool:
	return not paused and _achieved < multiplier() * RATE_SHORTFALL


## The rate for the screen: "60x", or "60x > 18x" while the simulation delivers less than asked.
func rate_text() -> String:
	var asked := "%dx" % int(multiplier())
	if not rate_short():
		return asked
	return "%s > %dx" % [asked, maxi(1, roundi(_achieved))]


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
		_achieved = multiplier()
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
	# A new speed is taken at its word until frames show otherwise.
	_achieved = multiplier()
	speed_changed.emit(speed_index, multiplier())


func set_paused(p: bool) -> void:
	if p == paused:
		return
	_accum = 0.0
	_last_wall_usec = 0
	_achieved = multiplier()
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
	_achieved = multiplier()
	start_unix_time = start_unix


func datetime_string() -> String:
	if start_unix_time > 0:
		return Time.get_datetime_string_from_unix_time(start_unix_time + int(sim_time), true) + "Z"
	return Geo.format_duration(sim_time)
