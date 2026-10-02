extends TestCase

const ClockScript := preload("res://scripts/simulation/sim_clock.gd")


func test_pause_during_acceleration_stops_at_the_current_tick() -> void:
	var clock := ClockScript.new()
	clock.set_speed_index(5)
	clock.set_paused(false)
	clock.tick.connect(func(_dt: float) -> void: clock.set_paused(true))
	clock._process(1.0)
	assert_near(clock.sim_time, 0.25, 0.001, "a pause must stop the rest of the accelerated frame")
	clock.free()


func test_combat_slowdown_discards_the_accelerated_backlog() -> void:
	var clock := ClockScript.new()
	clock.set_speed_index(5)
	clock.set_paused(false)
	clock.tick.connect(func(_dt: float) -> void: clock.drop_to_realtime())
	clock._process(1.0)
	assert_near(clock.sim_time, 0.25, 0.001, "combat must not run another minute after dropping to real time")
	clock._process(0.25)
	assert_near(clock.sim_time, 0.5, 0.001, "subsequent frames run at the new speed")
	clock.free()


func test_pause_resume_does_not_replay_fractional_time() -> void:
	var clock := ClockScript.new()
	clock.set_paused(false)
	clock._process(0.2)
	clock.set_paused(true)
	clock.set_paused(false)
	clock._process(0.1)
	assert_near(clock.sim_time, 0.0, 0.001)
	clock._process(0.15)
	assert_near(clock.sim_time, 0.25, 0.001)
	clock.free()


func test_fixed_ticks_are_independent_of_render_frame_size() -> void:
	var a := ClockScript.new()
	var b := ClockScript.new()
	a.set_speed_index(3)
	b.set_speed_index(3)
	a.set_paused(false)
	b.set_paused(false)
	a._process(2.0)
	for i in 100:
		b._process(0.02)
	assert_near(a.sim_time, b.sim_time, 0.001)
	assert_near(a.sim_time, 20.0, 0.001)
	a.free()
	b.free()


func test_wall_clock_preserves_time_during_engine_delta_clamping() -> void:
	var clock := ClockScript.new()
	clock.set_paused(false)
	clock._process_wall_frame(0, 1000000)
	clock._process_wall_frame(0.15, 1500000)
	assert_near(clock.sim_time, 0.5, 0.001, "500 ms stall is not shortened to the engine's 150 ms delta")
	clock.free()


func test_wall_clock_pause_and_os_suspension_do_not_replay_old_time() -> void:
	var clock := ClockScript.new()
	clock.set_paused(false)
	clock._process_wall_frame(0, 1000000)
	clock.set_paused(true)
	clock._process_wall_frame(0.15, 10000000)
	clock.set_paused(false)
	clock._process_wall_frame(0, 20000000)
	assert_near(clock.sim_time, 0)
	clock._process_wall_frame(0.15, 80000000)
	assert_near(clock.sim_time, 1, 0.001, "OS suspension catch-up is capped to one second")
	clock.free()


func test_the_clock_switches_ladders_and_a_lower_ceiling_only_slows_the_watch() -> void:
	var clock := ClockScript.new()
	assert_eq(Array(clock.speeds()), Array(ClockScript.SPEEDS), "the Normal ladder by default")
	clock.set_speed_index(4)  # 30x
	var changes: Array = []
	clock.speed_changed.connect(func(i: int, m: float) -> void: changes.append([i, m]))
	clock.set_ceiling(4.0)
	assert_eq(Array(clock.speeds()), [1.0, 2.0, 4.0])
	assert_eq(clock.multiplier(), 4.0, "a 30x watch comes down to the ceiling")
	assert_eq(clock.speed_index, 2)
	assert_eq(changes.size(), 1, "the change is announced once")
	clock.set_speed_index(5)
	assert_eq(clock.multiplier(), 4.0, "nothing past the ceiling")
	clock.set_speed_index(1)
	clock.set_speeds(ClockScript.SPEEDS)
	assert_eq(clock.multiplier(), 2.0, "raising the ceiling never speeds a watch up")
	clock.set_speeds([3.0, 9.0])
	assert_eq(Array(clock.speeds()), Array(ClockScript.SPEEDS), "an unusable ladder is the Normal one")
	assert_eq(ClockScript.SPEEDS.size(), 6, "SPEEDS stays the Normal ladder")
	clock.free()


func test_time_scale_never_changes_what_the_ticks_compute() -> void:
	var a := ClockScript.new()
	var b := ClockScript.new()
	a.set_ceiling(4.0)
	a.set_speed_index(2)  # 4x on the Classic ladder
	b.set_speed_index(2)  # 5x on the Normal one
	var ticks := [[], []]
	a.tick.connect(func(dt: float) -> void: ticks[0].append(dt))
	b.tick.connect(func(dt: float) -> void: ticks[1].append(dt))
	a.set_paused(false)
	b.set_paused(false)
	for i in 50:
		a._process(0.1)
		b._process(0.1)
	assert_near(a.sim_time, 20.0, 0.001, "4x for five seconds")
	assert_near(b.sim_time, 25.0, 0.001)
	for dt in ticks[0] + ticks[1]:
		assert_eq(dt, ClockScript.TICK_DT, "every tick is the same fixed step")
	a.free()
	b.free()
