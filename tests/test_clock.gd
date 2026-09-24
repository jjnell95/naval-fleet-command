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
