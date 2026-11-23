extends TestCase
## Saving as a player meets it: an autosave does not stop the game while it is written, it still
## brings back the moment it was taken, and a run can make one happen to measure it.

var _save_root := ""
var _log_path := ""
var _clock_speeds: Array[float] = []
var _use_worker := true


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


## The command screen on an operation with command taken and the clock paused at zero, keeping
## its saves and commander's log out of the player's own.
func _open_main(scenario := "res://data/scenarios/northern_passage.json") -> Main:
	_save_root = SaveGame.root_override
	_log_path = CommanderLog.path_override
	_clock_speeds = SimClock.speeds()
	_use_worker = SaveGame.use_worker
	SaveGame.root_override = "user://test-frontend-two-%d" % Time.get_ticks_usec()
	CommanderLog.path_override = SaveGame.root_override + "-log.json"
	var main: Main = preload("res://scenes/main/Main.tscn").instantiate()
	_root().add_child(main)
	main._apply_options(GameOptions.normal(), false, false)
	main.simulation.seed_override = 2
	main.start_scenario(scenario)
	main._on_briefing_start()
	SimClock.set_paused(true)
	return main


func _close_main(main: Main) -> void:
	SaveGame.finish_writing()
	SaveGame.force_next_autosave = false
	SaveGame.use_worker = _use_worker
	main.free()
	var dir := DirAccess.open(SaveGame.root_override)
	if dir != null:
		for file in dir.get_files():
			dir.remove(file)
		DirAccess.remove_absolute(SaveGame.root_override)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CommanderLog.path()))
	SaveGame.root_override = _save_root
	CommanderLog.path_override = _log_path
	SimClock.set_speeds(_clock_speeds)
	SimClock.set_speed_index(0)
	SimClock.set_paused(true)


func _autosaves() -> Array:
	return SaveGame.list_saves().filter(func(h: Dictionary) -> bool: return str(h.get("kind", "")) == "auto")


## Plays `seconds` of the engagement with the clock running, as the autosave expects.
static func _play(seconds: int) -> void:
	SimClock.set_paused(false)
	for i in seconds:
		SimClock.advance(1.0)


## The autosave the player's own session takes when its interval comes round.
static func _due_autosave(main: Main) -> void:
	main._autosave_enabled = true
	main._autosaved_at = SimClock.sim_time - SaveGame.AUTOSAVE_INTERVAL_S
	main._autosave_if_due()


func test_an_autosave_is_written_over_the_frames_after_it_is_taken_and_brings_that_moment_back() -> void:
	var main := _open_main()
	SaveGame.use_worker = false  # the browser build's way, frame by frame
	_play(30)
	var taken := SimClock.sim_time
	_due_autosave(main)
	assert_eq(_autosaves().size(), 0, "the frame that takes the autosave only captures it: nothing is encoded or written in it")
	var job := SaveGame.writing()
	assert_true(job != null, "the autosave is under way")
	var frames := 0
	while job != null and not job.step() and frames < 20:
		frames += 1
		SimClock.advance(1.0)  # the battle goes on while it is written
	assert_true(job != null and job.done, "it finishes")
	assert_true(frames >= 3, "the encoding, the compression and the file each take a frame of their own, %d frames" % frames)
	assert_eq(job.error, "")
	assert_eq(_autosaves().size(), 1, "and then it is on disk")
	assert_true(SimClock.sim_time > taken, "the engagement ran on meanwhile")
	SimClock.set_paused(true)
	assert_eq(main.load_engagement(str(_autosaves()[0]["path"])), "", "the autosave loads")
	assert_eq(SimClock.sim_time, taken, "at the moment it was taken, not the one it was finished at")
	_close_main(main)


func test_where_there_are_threads_the_file_is_written_on_a_worker() -> void:
	if not OS.has_feature("threads"):
		return
	var main := _open_main()
	SaveGame.use_worker = true
	_play(20)
	var taken := SimClock.sim_time
	_due_autosave(main)
	var job := SaveGame.writing()
	assert_true(job != null and _autosaves().is_empty(), "taking it writes nothing in that frame")
	if job != null:
		job.step()  # the next frame encodes it and hands the rest to a worker
		assert_true(job._task >= 0 or job.done, "the compression and the file are on a worker")
		assert_eq(job.finish(), "")
	assert_eq(_autosaves().size(), 1)
	SimClock.set_paused(true)
	assert_eq(main.load_engagement(str(_autosaves()[0]["path"])), "")
	assert_eq(SimClock.sim_time, taken)
	_close_main(main)


func test_a_run_can_force_an_autosave_to_exercise_it() -> void:
	var main := _open_main()
	main._scripted_session = true  # a dev-harness run, which never autosaves on its own
	_play(10)
	SimClock.set_paused(true)
	main._autosave_if_due()
	SaveGame.finish_writing()
	assert_eq(_autosaves().size(), 0, "a driven run leaves the saves alone")
	SaveGame.force_next_autosave = true
	main._autosave_if_due()
	assert_true(not SaveGame.force_next_autosave, "the request is used up")
	assert_eq(SaveGame.finish_writing(), "")
	assert_eq(_autosaves().size(), 1, "paused and driven, the forced autosave is taken")
	main._autosave_if_due()
	SaveGame.finish_writing()
	assert_eq(_autosaves().size(), 1, "once")
	_close_main(main)


func test_leaving_finishes_the_autosave_under_way_and_writes_its_own_before_it_returns() -> void:
	var main := _open_main()
	SaveGame.use_worker = false
	_play(15)
	_due_autosave(main)
	assert_true(SaveGame.writing() != null, "one autosave is still being written")
	_play(5)
	SimClock.set_paused(true)
	main._autosave_if_due(true)
	assert_true(SaveGame.writing() == null, "nothing is left half written when the engagement is replaced")
	var slots: Array = _autosaves().map(func(h: Dictionary) -> String: return str(h["slot"]))
	slots.sort()
	assert_eq(slots, [SaveGame.AUTOSAVE_PREFIX + "1", SaveGame.AUTOSAVE_PREFIX + "2"], "both are on disk, in the order taken")
	_close_main(main)


func test_staged_autosaves_keep_only_the_newest() -> void:
	var main := _open_main()
	SaveGame.use_worker = false
	for i in SaveGame.AUTOSAVE_KEEP + 2:
		_play(2)
		_due_autosave(main)
	SaveGame.finish_writing()
	var autos := _autosaves()
	assert_eq(autos.size(), SaveGame.AUTOSAVE_KEEP, "the oldest are dropped")
	assert_eq(str(autos[0]["slot"]), SaveGame.AUTOSAVE_PREFIX + str(SaveGame.AUTOSAVE_KEEP + 2), "newest first")
	_close_main(main)
