extends RefCounted
## The late-battle workload, measured. Both sides are flown by the AI. The battle is run once to
## `--from` and saved (kept under work/measure/ and reused; --fresh rebuilds it), and every
## measurement then starts from that save, so every run steps through exactly the same battle.
##
## Flags, after a bare `--`:
##   --scenario=res://...   default the Taiwan Strait, the largest air battle
##   --seed=N               default 42
##   --from=S               simulated second the measurement starts at (default 2400)
##   --span=S               simulated seconds stepped tick by tick (default 600)
##   --clock-span=S         simulated seconds run on the real frame clock at 60x (default 240, 0 skips)
##   --repeats=N            default 3; paths are interleaved so machine load falls on each alike
##   --paths=a,b            "current" (the code as it stands), or "reference" and "optimized" to
##                          switch SensorManager's old reporting path on and off for an A/B pair
##   --fresh                rebuild the save at --from
##
## Stepped phase: the clock is advanced one 0.25 s tick at a time. Each sensor cycle's own time is
## read from the profiler (Debug.time_add "sim/sensors" on the ticks the cycle ran), each tick's
## wall time is timed around SimClock.advance, and every 120 simulated seconds a batch of move
## orders goes to the player's ships, timed as it is issued and with the tick that carries it.
## The final state's digest must be the same for every path: an optimisation that changed the
## battle would show here.
##
## Clock phase: the real SimClock frame loop at 60x (headless, so no rendering). It reports the
## acceleration the clock actually achieves and, for an order batch issued at the start of a frame,
## the wall time until the next frame begins: the order applied and the ticks that frame ran, which
## is what a player waits before the chart can show the order taking effect. A window adds its own
## render time on top.

const TICK := 0.25
const ORDER_EVERY_S := 120.0
const BUDGET_60X_MS := 1000.0 * TICK / 60.0

var _args := {}


func run(tree: SceneTree) -> int:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			_args[a.get_slice("=", 0).trim_prefix("--")] = a.get_slice("=", 1) if a.contains("=") else "1"
	Debug.log_events = false
	SimClock.set_paused(true)
	var scenario := str(_args.get("scenario", "res://data/scenarios/pacific_02_taiwan_strait.json"))
	var seed_value := int(_args.get("seed", "42"))
	var from := float(_args.get("from", "2400"))
	var span := float(_args.get("span", "600"))
	var clock_span := float(_args.get("clock-span", "240"))
	var repeats := int(_args.get("repeats", "3"))
	var paths := str(_args.get("paths", "current")).split(",")
	var save := "res://work/measure/%s-s%d-t%d.nfcsave" % [scenario.get_file().get_basename(), seed_value, int(from)]
	if _args.has("fresh") or not FileAccess.file_exists(save):
		var why := _build_save(tree, scenario, seed_value, from, save)
		if why != "":
			print("[measure] FAIL " + why)
			return 1
	print("[measure] %s seed %d from %.0f s: %.0f s stepped, %.0f s on the 60x clock, %d repeats, paths %s" % [scenario.get_file(), seed_value, from, span, clock_span, repeats, ",".join(paths)])
	var stepped: Dictionary = {}
	var clocked: Dictionary = {}
	for path in paths:
		stepped[path] = []
		clocked[path] = []
	for r in repeats:
		for path in paths:
			var sim := _restore(tree, scenario, save, path)
			if sim == null:
				return 1
			if r == 0 and path == paths[0]:
				_census(sim)
			var result := _stepped(sim, span)
			print("[measure] run %d %-9s stepped: sensor cycle mean %.2f ms p95 %.2f ms; tick mean %.2f ms p95 %.2f ms; %.1f s wall per %.0f s (%.1fx); orders %.2f ms, their tick %.2f ms; state %s" % [r + 1, path, result["cycle_mean"], result["cycle_p95"], result["tick_mean"], result["tick_p95"], result["wall_s"], span, result["accel"], result["order_ms"], result["order_tick_ms"], result["digest"]])
			stepped[path].append(result)
			_free(sim)
			if clock_span > 0.0:
				sim = _restore(tree, scenario, save, path)
				var c: Dictionary = await _clocked(tree, sim, clock_span)
				print("[measure] run %d %-9s 60x clock: %.1fx achieved, frame mean %.0f ms p95 %.0f ms, %.0f ticks per frame; order to next frame mean %.0f ms max %.0f ms (%d batches)" % [r + 1, path, c["accel"], c["frame_mean"], c["frame_p95"], c["ticks_per_frame"], c["latency_mean"], c["latency_max"], c["batches"]])
				clocked[path].append(c)
				_free(sim)
	print("[measure] ---- min / median over %d runs ----" % repeats)
	for path in paths:
		var s: Array = stepped[path]
		print("[measure] %-9s sensor cycle mean ms   %s" % [path, _min_median(s, "cycle_mean")])
		print("[measure] %-9s sensor cycle p95 ms    %s" % [path, _min_median(s, "cycle_p95")])
		print("[measure] %-9s sensor share of 60x tick budget %s" % [path, _min_median(s, "sensor_share_60x", "%.0f%%")])
		var part_text := PackedStringArray()
		for k in ["radar", "esm", "sonar", "buoys", "tracks", "weapons"]:
			part_text.append("%.2f" % _median(s.map(func(x: Dictionary) -> float: return float(x["parts"].get(k, 0.0)))))
		print("[measure] %-9s   radar / esm / sonar / buoys / tracks / weapons ms per cycle (median): %s" % [path, " / ".join(part_text)])
		print("[measure] %-9s tick mean ms           %s" % [path, _min_median(s, "tick_mean")])
		print("[measure] %-9s tick p95 ms            %s" % [path, _min_median(s, "tick_p95")])
		print("[measure] %-9s wall s per %.0f sim s   %s" % [path, span, _min_median(s, "wall_s")])
		print("[measure] %-9s stepped acceleration   %s" % [path, _min_median(s, "accel", "%.1fx")])
		print("[measure] %-9s order batch apply ms   %s" % [path, _min_median(s, "order_ms")])
		print("[measure] %-9s tick carrying orders ms %s" % [path, _min_median(s, "order_tick_ms")])
		print("[measure] %-9s final state            %s" % [path, ", ".join(PackedStringArray(s.map(func(x: Dictionary) -> String: return x["digest"])))])
		var c: Array = clocked[path]
		if not c.is_empty():
			print("[measure] %-9s 60x clock acceleration %s" % [path, _min_median(c, "accel", "%.1fx")])
			print("[measure] %-9s 60x frame mean ms      %s" % [path, _min_median(c, "frame_mean", "%.0f")])
			print("[measure] %-9s 60x order to frame ms  %s (mean); max %s" % [path, _min_median(c, "latency_mean", "%.0f"), _min_median(c, "latency_max", "%.0f")])
	var digests := {}
	for path in paths:
		for x: Dictionary in stepped[path]:
			digests[x["digest"]] = true
	print("[measure] every run ended in the same state: %s" % ("yes" if digests.size() == 1 else "NO (%d different)" % digests.size()))
	return 0 if digests.size() == 1 else 2


## Runs the battle from the start to `from` and saves it there.
func _build_save(tree: SceneTree, scenario: String, seed_value: int, from: float, save: String) -> String:
	var sim := Simulation.new()
	sim.seed_override = seed_value
	tree.root.add_child(sim)
	if not sim.load_scenario(scenario):
		return "cannot load " + scenario
	sim.ai_plays_player = true
	sim._build_ai()
	var started := Time.get_ticks_usec()
	while SimClock.sim_time < from - TICK * 0.5:
		SimClock.advance(TICK)
	print("[measure] ran the opening %.0f s in %.1f s wall; saved for reuse" % [from, float(Time.get_ticks_usec() - started) / 1.0e6])
	var why := SaveGame.write(ProjectSettings.globalize_path(save), {"label": "measure", "serial": 1}, {"simulation": sim.capture_snapshot()})
	_free(sim)
	return why


func _restore(tree: SceneTree, scenario: String, save: String, path: String) -> Simulation:
	var sim := Simulation.new()
	tree.root.add_child(sim)
	if not sim.load_scenario(scenario):
		print("[measure] FAIL cannot load " + scenario)
		return null
	var file := SaveGame.read(ProjectSettings.globalize_path(save))
	if str(file.get("error", "")) != "":
		print("[measure] FAIL " + str(file["error"]))
		return null
	var why := sim.restore_snapshot(file["payload"]["simulation"])
	if why != "":
		print("[measure] FAIL " + why)
		return null
	_set_path(sim, path)
	return sim


## "reference" runs SensorManager's original reporting; "optimized" and "current" the code as it is.
func _set_path(sim: Simulation, path: String) -> void:
	if path == "reference" or path == "optimized":
		sim.sensor_manager.set("reference_path", path == "reference")


func _free(sim: Simulation) -> void:
	SimClock.set_paused(true)
	SimClock.set_speed_index(0)
	sim.get_parent().remove_child(sim)
	sim.free()


## What the sensor layer is working on at the start.
func _census(sim: Simulation) -> void:
	var by_faction := {}
	for u: Unit in sim.unit_manager.units:
		if not u.is_engageable():
			continue
		var row: Dictionary = by_faction.get(u.faction, {"engageable": 0, "airborne": 0, "radiating": 0, "esm": 0, "sonar": 0})
		row["engageable"] += 1
		row["airborne"] += 1 if u.in_flight() else 0
		row["radiating"] += 1 if u.radar_emitting() else 0
		row["esm"] += 1 if u.has_esm() else 0
		row["sonar"] += 1 if u.has_sonar() else 0
		by_faction[u.faction] = row
	print("[measure] at %.0f s: %d units (%d weapons in flight); engageable by side %s" % [SimClock.sim_time, sim.unit_manager.units.size(), sim.weapon_manager.in_flight.size(), by_faction])
	var pictures := 0
	var tracks := 0
	for key in sim.track_manager._tracks:
		pictures += 1
		tracks += sim.track_manager._tracks[key].size()
	print("[measure] %d track pictures holding %d tracks" % [pictures, tracks])


func _stepped(sim: Simulation, span: float) -> Dictionary:
	var stop := SimClock.sim_time + span
	var next_orders := SimClock.sim_time + ORDER_EVERY_S * 0.5
	var cycles := PackedFloat64Array()
	var ticks := PackedFloat64Array()
	var parts := {}
	var order_ms := PackedFloat64Array()
	var order_tick_ms := PackedFloat64Array()
	var sensor_total := 0.0
	var totals := {}
	Debug.profiling = true
	while SimClock.sim_time < stop - TICK * 0.5:
		var carrying := false
		if SimClock.sim_time >= next_orders:
			next_orders += ORDER_EVERY_S
			order_ms.append(_issue_batch(sim))
			carrying = true
		Debug.timings.clear()
		var at := Time.get_ticks_usec()
		SimClock.advance(TICK)
		var tick_ms := float(Time.get_ticks_usec() - at) / 1000.0
		ticks.append(tick_ms)
		if carrying:
			order_tick_ms.append(tick_ms)
		sensor_total += float(Debug.timings.get("sim/sensors", 0)) / 1000.0
		if Debug.timings.has("sensors/tracks"):
			cycles.append(float(Debug.timings.get("sim/sensors", 0)) / 1000.0)
			for k in ["radar", "esm", "sonar", "buoys", "tracks", "weapons"]:
				parts[k] = float(parts.get(k, 0.0)) + float(Debug.timings.get("sensors/" + k, 0)) / 1000.0
		for k: String in Debug.timings:
			totals[k] = float(totals.get(k, 0.0)) + float(Debug.timings[k])
	Debug.profiling = false
	Debug.timings.clear()
	for k in parts:
		parts[k] = float(parts[k]) / maxf(cycles.size(), 1)
	var wall := _sum(ticks) / 1000.0
	if _args.has("profile"):
		# Every path the profiler saw: simulation phases per tick, sensor paths per cycle (counts
		# under n/ are calls, everything else microseconds turned into milliseconds).
		var keys := totals.keys()
		keys.sort()
		for k: String in keys:
			if k.begins_with("n/"):
				print("[measure]     %-24s %10.1f calls per cycle" % [k, float(totals[k]) / maxf(cycles.size(), 1)])
			elif k.begins_with("sim"):
				print("[measure]     %-24s %10.3f ms per tick" % [k, float(totals[k]) / 1000.0 / maxf(ticks.size(), 1)])
			else:
				print("[measure]     %-24s %10.3f ms per cycle" % [k, float(totals[k]) / 1000.0 / maxf(cycles.size(), 1)])
	return {
		"cycle_mean": _mean(cycles), "cycle_p95": _p95(cycles), "cycles": cycles.size(),
		"tick_mean": _mean(ticks), "tick_p95": _p95(ticks),
		"sensor_share_60x": 100.0 * sensor_total / maxf(ticks.size(), 1) / BUDGET_60X_MS,
		"wall_s": wall, "accel": span / maxf(wall, 1e-6), "parts": parts,
		"order_ms": _mean(order_ms), "order_tick_ms": _mean(order_tick_ms),
		"digest": _digest(sim),
	}


## The real frame clock at 60x. Every other frame starts with an order batch.
func _clocked(tree: SceneTree, sim: Simulation, clock_span: float) -> Dictionary:
	var start_sim := SimClock.sim_time
	var stop := start_sim + clock_span
	SimClock.set_speed_index(SimClock.SPEEDS.size() - 1)
	SimClock.set_paused(false)
	await tree.process_frame
	var frames := PackedFloat64Array()
	var latencies := PackedFloat64Array()
	var tick_count := 0
	var started := Time.get_ticks_usec()
	var frame_start := started
	var n := 0
	while SimClock.sim_time < stop and Time.get_ticks_usec() - started < 600 * 1000000:
		var issued := -1
		if n % 2 == 1:
			issued = Time.get_ticks_usec()
			_issue_batch(sim)
		var before := SimClock.sim_time
		await tree.process_frame
		var now := Time.get_ticks_usec()
		tick_count += int(round((SimClock.sim_time - before) / TICK))
		frames.append(float(now - frame_start) / 1000.0)
		if issued >= 0:
			latencies.append(float(now - issued) / 1000.0)
		frame_start = now
		n += 1
	var wall := float(Time.get_ticks_usec() - started) / 1.0e6
	var advanced := SimClock.sim_time - start_sim
	SimClock.set_paused(true)
	return {
		"accel": advanced / maxf(wall, 1e-6), "frame_mean": _mean(frames), "frame_p95": _p95(frames),
		"ticks_per_frame": float(tick_count) / maxf(frames.size(), 1),
		"latency_mean": _mean(latencies), "latency_max": _max(latencies), "batches": latencies.size(),
	}


## A player's typical batch: every ship of the player's side told to steer five miles ahead.
## Returns how long issuing it took, in milliseconds.
func _issue_batch(sim: Simulation) -> float:
	var at := Time.get_ticks_usec()
	for u: Unit in sim.unit_manager.get_faction_units(sim.player_faction):
		if u.is_aircraft() or u.spec.max_speed_kn <= 0.0:
			continue
		sim.unit_manager.issue_order(u, Order.move(u.position + Geo.heading_to_vector(u.heading_deg) * 5.0))
	return float(Time.get_ticks_usec() - at) / 1000.0


func _digest(sim: Simulation) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes(SimSnapshot.capture(sim)))
	return hashing.finish().hex_encode().substr(0, 16)


func _min_median(rows: Array, key: String, fmt := "%.2f") -> String:
	var values := PackedFloat64Array(rows.map(func(x: Dictionary) -> float: return float(x[key])))
	values.sort()
	return ("min " + fmt + "  median " + fmt) % [values[0], _median(values)]


static func _median(values: Variant) -> float:
	var v := PackedFloat64Array(values)
	if v.is_empty():
		return 0.0
	v.sort()
	return v[v.size() / 2] if v.size() % 2 == 1 else (v[v.size() / 2 - 1] + v[v.size() / 2]) * 0.5


static func _sum(v: PackedFloat64Array) -> float:
	var total := 0.0
	for x in v:
		total += x
	return total


static func _mean(v: PackedFloat64Array) -> float:
	return _sum(v) / maxf(v.size(), 1)


static func _max(v: PackedFloat64Array) -> float:
	var best := 0.0
	for x in v:
		best = maxf(best, x)
	return best


static func _p95(v: PackedFloat64Array) -> float:
	if v.is_empty():
		return 0.0
	var s := v.duplicate()
	s.sort()
	return s[mini(int(floor(s.size() * 0.95)), s.size() - 1)]
