extends RefCounted
## Arguments after --: --mode=straight|save|resume --scenario=res://... --seed=N --t1=S --t2=S
## --save=PATH --out=PATH. Both sides are flown by the AI so every system is exercised. The out
## file holds var_to_bytes of the whole SimSnapshot at t2; the driver compares those files.

func run(tree: SceneTree) -> int:
	var args := {}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			args[a.get_slice("=", 0).trim_prefix("--")] = a.get_slice("=", 1)
	var clock: Node = tree.root.get_node("SimClock")
	var debug: Node = tree.root.get_node_or_null("Debug")
	if debug != null:
		debug.log_events = false
	clock.set_paused(true)
	var sim := Simulation.new()
	sim.seed_override = int(args.get("seed", "31"))
	tree.root.add_child(sim)
	var mode := str(args.get("mode", "straight"))
	if mode == "resume":
		# A different seed: everything random must come from the save.
		sim.seed_override = int(args.get("seed", "31")) + 1000
		if not sim.load_scenario(str(args["scenario"])):
			return _fail("cannot load scenario")
		var file := SaveGame.read(str(args["save"]))
		if str(file.get("error", "")) != "":
			return _fail(str(file["error"]))
		var why := sim.restore_snapshot(file["payload"]["simulation"])
		if why != "":
			return _fail(why)
	else:
		if not sim.load_scenario(str(args["scenario"])):
			return _fail("cannot load scenario")
		sim.ai_plays_player = true
		sim._build_ai()
	var stop := float(args["t1"]) if mode == "save" else float(args["t2"])
	while clock.sim_time < stop - 0.125:
		clock.advance(0.25)
	if mode == "save":
		var header := {"label": "continuation", "serial": 1}
		var why := SaveGame.write(str(args["save"]), header, {"simulation": sim.capture_snapshot()})
		if why != "":
			return _fail(why)
		print("[continuation] saved at %.2f" % clock.sim_time)
		return 0
	var out := FileAccess.open(str(args["out"]), FileAccess.WRITE)
	out.store_buffer(var_to_bytes(SimSnapshot.capture(sim)))
	out.close()
	print("[continuation] %s ended at %.2f, %d units, %d weapons in flight, result %d" % [mode, clock.sim_time, sim.unit_manager.units.size(), sim.weapon_manager.in_flight.size(), sim.mission_manager.result])
	return 0


func _fail(why: String) -> int:
	print("[continuation] FAIL " + why)
	return 1
