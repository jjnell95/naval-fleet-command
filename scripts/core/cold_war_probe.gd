class_name ColdWarProbe
extends RefCounted
## Development-only behavioral record through Main's real autoload and scene lifecycle.
## --cold-war-probe --scenario=res://... --seed=2 [--autopilot] --probe-output=/path.json

static func run(main: Main) -> void:
	var id: String = main.simulation.scenario.get("id", "")
	var output := "user://cold-war-behavior.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-output="):
			output = arg.get_slice("=", 1)
	var budget := 10800 if id in ["cold_war_01_convoy", "cold_war_02_barrier"] else 7200
	var samples: Array = []
	var ended := {}
	var buoy_tally := {"BLUE": 0, "RED": 0}
	main.simulation.aviation_manager.sonobuoy_deployed.connect(func(_b: Sonobuoy, a: Unit) -> void: buoy_tally[a.faction] = int(buoy_tally.get(a.faction, 0)) + 1)
	main.simulation.mission_manager.mission_ended.connect(func(_r: String, _s: String) -> void: ended["time_s"] = SimClock.sim_time)
	SimClock.set_paused(true)
	while SimClock.sim_time < budget and main.simulation.mission_manager.result == MissionManager.Result.RUNNING:
		SimClock.advance(30)
		if int(SimClock.sim_time) % 600 == 0:
			samples.append(snapshot(main))
	var report := snapshot(main)
	report["buoys_deployed"] = buoy_tally
	report["resolved_s"] = ended.get("time_s", -1.0)
	report["sample_interval_s"] = 30
	report["scenario"] = id
	report["seed"] = main.simulation.seed_override
	report["player"] = "AI" if main.simulation.ai_plays_player else "passive"
	report["samples"] = samples
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Could not write behavioral probe: %s" % output)
		main.get_tree().quit(1)
		return
	file.store_string(JSON.stringify(report, "  "))
	print("[Behavior] %s result=%s at %.0f s; %s" % [id, report["result"], report["time_s"], output])
	main.get_tree().quit()

static func snapshot(main: Main) -> Dictionary:
	var sim := main.simulation
	var actors: Array = []
	for unit: Unit in sim.unit_manager.units:
		var tracks: Array = []
		for t: Track in sim.track_manager.tracks_for(unit):
			tracks.append({"id":t.id,"identity":t.identity,"classification":t.classification,"error_nm":t.position_error_nm})
		actors.append({"name":unit.callsign,"alive":unit.alive,"hp":unit.health,"position_nm":[unit.position.x,unit.position.y],"speed_kn":unit.speed_kn,"depth_m":unit.depth_m,"local_tracks":tracks,"ai":sim.ai_state_for(unit),"aground":unit.needs_sea_room() and Terrain.is_land(unit.position)})
	return {"time_s":SimClock.sim_time,"result":sim.mission_manager.result,"stats":main._stats.duplicate(),"sonobuoys_in_water":sim.aviation_manager.sonobuoys.size(),"actors":actors}
