extends RefCounted
## Brings an operation to a moment of the battle through the command screen, then times every
## frame of a second of play without a save and of the frames an autosave forced at that moment
## takes, and prints the longest of each. The saves go to the output directory, never the
## player's own.

var tree: SceneTree
var args := {}


func run(scene_tree: SceneTree) -> int:
	tree = scene_tree
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			args[a.get_slice("=", 0).trim_prefix("--")] = a.get_slice("=", 1) if a.contains("=") else "1"
	var output_dir := str(args.get("output-dir", "res://work/autosave-frames")).trim_suffix("/")
	DirAccess.make_dir_recursive_absolute(output_dir)
	SaveGame.root_override = output_dir.path_join("saves")
	CommanderLog.path_override = output_dir.path_join("commander_log.json")
	Debug.log_events = false
	if args.has("no-worker"):
		SaveGame.use_worker = false  # as the browser build writes it, a stage a frame
	var main: Main = load("res://scenes/main/Main.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	main._apply_options(GameOptions.normal(), false, false)
	main.simulation.seed_override = int(args.get("seed", "2"))
	main.start_scenario(str(args.get("scenario", "res://data/scenarios/pacific_02_taiwan_strait.json")))
	main._on_briefing_start()
	if args.has("autopilot"):
		main.simulation.ai_plays_player = true
		main.simulation._build_ai()
	SimClock.set_paused(true)
	SimClock.advance(float(args.get("ff", "1500")))
	SimClock.set_speed_index(0)
	SimClock.set_paused(false)
	# The screen catches up with the jump first: the chart, the boards and the 3D view.
	await _frames(240, func() -> bool: return false)
	var before := _count_saves()
	var quiet := await _frames(240, func() -> bool: return false)
	SaveGame.force_next_autosave = true
	var saving := await _frames(600, func() -> bool: return _count_saves() > before and SaveGame.writing() == null)
	SimClock.set_paused(true)
	var written := _count_saves() > before
	print("[autosave] %s at %.0f s: without a save the longest frame %.1f ms (mean %.1f) over %d frames; with an autosave the longest %.1f ms, frames over 50 ms %s, file %s after %d frames" % [
		main.simulation.scenario_name, SimClock.sim_time, quiet["max"], quiet["mean"], quiet["count"], saving["max"],
		saving["long"], "written" if written else "NOT written", saving["count"]])
	main.free()
	return 0 if written else 1


func _count_saves() -> int:
	return SaveGame.list_saves().size()


## Times `limit` frames, or until `stop` holds once the autosave has had its chance.
func _frames(limit: int, stop: Callable) -> Dictionary:
	var longest := 0.0
	var total := 0.0
	var long: Array[String] = []
	var count := 0
	var last := Time.get_ticks_usec()
	for i in limit:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		var ms := float(now - last) / 1000.0
		last = now
		longest = maxf(longest, ms)
		total += ms
		count += 1
		if ms > 50.0:
			long.append("%.0f" % ms)
		if stop.call():
			break
	return {"max": longest, "mean": total / maxf(count, 1), "count": count, "long": "[" + ", ".join(long) + "]"}
