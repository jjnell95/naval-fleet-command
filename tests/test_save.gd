extends TestCase
## Saved engagements: a save taken mid-battle and loaded into a fresh simulation must carry on
## exactly as the uninterrupted battle did, tick for tick, with rounds in the air, salvoes queued,
## aircraft recovering, crews on temporary tasks and a scheduled event still to come. Compared as
## the bytes of the whole tactical state, not as "it loaded".

const CARRIER_WATCH := "res://data/scenarios/cold_war_03_carrier.json"
const PASSAGE := "res://data/scenarios/northern_passage.json"
const PLAN_FIXTURE := "res://tests/fixtures/ai_plan_carrier.json"
const IKE := "USS Dwight D. Eisenhower (CVN 69)"
const SAVE_AT := 601.75  # off the one- and two-second cycle boundaries, so every phase matters
const COMPARE_AT := 2460.0  # after the follow-on raid scheduled at 2400 s

var _sim: Simulation
var _scratch := "user://test-saves-%d" % OS.get_process_id()


func _fresh(path: String, seed: int) -> Simulation:
	SimClock.set_paused(true)
	_sim = Simulation.new()
	_sim.seed_override = seed
	(Engine.get_main_loop() as SceneTree).root.add_child(_sim)
	assert_true(_sim.load_scenario(path), path)
	return _sim


func _free() -> void:
	if _sim == null:
		return
	_sim.unit_manager.clear()
	_sim.free()
	_sim = null


func _unit(callsign: String) -> Unit:
	for u in _sim.unit_manager.units:
		if u.callsign == callsign:
			return u
	return null


func _bytes() -> PackedByteArray:
	return var_to_bytes(SimSnapshot.capture(_sim))


## The commander's orders before the save, the same in both runs: a CAP with relief and an ASW
## search off the carrier, an escort sent to look at the first contact, and one Tomcat recalled so
## that it is on its way back to the deck when the save is taken.
func _play_to_save_point() -> void:
	var cv := _unit(IKE)
	var escort := _unit("USS Spruance (DD 963)")
	_sim.unit_manager.issue_order(cv, Order.air_mission(AirMission.Kind.CAP, "cw90_f14a", 2, cv.position + Vector2(20, 60), 12.0, null, true))
	_sim.unit_manager.issue_order(cv, Order.air_mission(AirMission.Kind.ASW, "cw90_s3a", 1, cv.position + Vector2(-20, 20), 10.0))
	var investigated := false
	var recalled := false
	while SimClock.sim_time < SAVE_AT - 0.25:
		SimClock.advance(0.25)
		if not investigated:
			for t: Track in _sim.track_manager.tracks_for(escort):
				if UnitManager.investigation_rejection(escort, t) == "":
					investigated = _sim.unit_manager.issue_order(escort, Order.investigate(t))
					break
		if not recalled and SimClock.sim_time >= 540.0:
			var m: AirMission = _sim.air_mission_manager.active_missions("BLUE")[0]
			for a in m.aircraft:
				if a.airborne() and not a.returning:
					recalled = _sim.unit_manager.issue_order(a, Order.return_to_base(cv))
					break
	SimClock.advance(0.25)


func _write_and_read(snapshot: Dictionary) -> Dictionary:
	SaveGame.root_override = _scratch
	var path := SaveGame.slot_path("continuation")
	assert_eq(SaveGame.write(path, {"label": "test"}, {"simulation": snapshot}), "")
	var back := SaveGame.read(path)
	assert_eq(back.get("error", "?"), "")
	DirAccess.remove_absolute(path)
	return back["payload"]["simulation"]


func test_continuation_after_reload_matches_the_uninterrupted_battle() -> void:
	_fresh(CARRIER_WATCH, 31)
	_play_to_save_point()
	assert_eq(SimClock.sim_time, SAVE_AT)
	# What the save has to carry, present at the moment it is taken.
	var wm := _sim.weapon_manager
	assert_true(wm.in_flight.any(func(w: Weapon) -> bool: return w.phase != Weapon.Phase.DEAD), "rounds airborne at the save")
	assert_true(not wm._pending.is_empty(), "shots queued on the launchers at the save")
	assert_true(_sim.unit_manager.units.any(func(u: Unit) -> bool: return u.alive and u.is_aircraft() and (u.returning or u.flight_state == Unit.FlightState.RECOVERING)), "an aircraft on its way back to the deck")
	assert_true(_sim.unit_manager.units.any(func(u: Unit) -> bool: return u.alive and (u.attack_track != null or u.investigation_track != null)), "a crew on a temporary task")
	assert_true(not _sim.completed_events.has("follow_on_raid"), "the follow-on raid is still to come")
	assert_true(not _sim.air_mission_manager.active_missions("BLUE").is_empty(), "air missions flying")
	var saved := _write_and_read(SimSnapshot.capture(_sim))
	SimClock.advance(COMPARE_AT - SAVE_AT)
	var expected := _bytes()
	var expected_result := _sim.mission_manager.result
	assert_true(_sim.completed_events.has("follow_on_raid"), "the uninterrupted battle saw the raid")
	_free()
	# A different seed: the restore must replace every random stream, not continue this one's.
	_fresh(CARRIER_WATCH, 999)
	assert_eq(_sim.restore_snapshot(saved), "")
	assert_eq(SimClock.sim_time, SAVE_AT, "the clock resumes at the saved tick")
	SimClock.advance(COMPARE_AT - SAVE_AT)
	var got := _bytes()
	assert_true(_sim.completed_events.has("follow_on_raid"), "the scheduled raid still arrives after a reload")
	assert_eq(_sim.mission_manager.result, expected_result)
	if got != expected:
		failures.append("continuation differs: %s" % _first_difference(bytes_to_var(expected), bytes_to_var(got), ""))
	_free()


## Both sides fighting through Northern Passage, saved after hits have been taken, so the damage
## stream has moved on from its seed and fires and flooding are being fought at the save.
func test_continuation_after_damage_matches_the_uninterrupted_battle() -> void:
	_fresh(PASSAGE, 31)
	_sim.ai_plays_player = true
	_sim._build_ai()
	var save_at := 500.75
	SimClock.advance(save_at)
	var untouched := RandomNumberGenerator.new()
	untouched.seed = Damage.rng.seed
	assert_true(Damage.rng.state != untouched.state, "damage has been rolled before the save")
	assert_eq(_sim.mission_manager.result, MissionManager.Result.RUNNING, "still being fought at the save")
	var saved := _write_and_read(SimSnapshot.capture(_sim))
	SimClock.advance(300.0)
	var expected := _bytes()
	_free()
	_fresh(PASSAGE, 5)
	assert_eq(_sim.restore_snapshot(saved), "")
	SimClock.advance(300.0)
	var got := _bytes()
	if got != expected:
		failures.append("continuation differs: %s" % _first_difference(bytes_to_var(expected), bytes_to_var(got), ""))
	_free()


## An opposing force pursuing a mission plan (tests/fixtures/ai_plan_carrier.json), saved twice:
## while its scout is still looking, so the reload crosses the moment the carrier is classified and
## the strike's weapons-free window; and in the first volley, with rounds flying and queued, so it
## crosses the shared assessment that holds every striker. Each must carry on as if never saved.
func test_continuation_of_an_enemy_mission_plan_matches_the_uninterrupted_battle() -> void:
	_fresh(PLAN_FIXTURE, 11)
	var plan: AIPlan = _sim.ai_controllers["RED"].plans[0]
	SimClock.advance(150.75)
	assert_eq(plan.phase, AIPlan.Phase.RECON, "the scout is looking at the first save")
	assert_true(_unit("Backfire Scout").airborne())
	var searching := _write_and_read(SimSnapshot.capture(_sim))
	SimClock.advance(900.0 - 150.75)
	var expected_found := _bytes()
	assert_eq(plan.phase, AIPlan.Phase.ATTACK, "the carrier was found and the window has run")
	assert_true(plan.weapons_free)
	while plan.salvos == 0 and SimClock.sim_time < 3000.0:
		SimClock.advance(0.25)
	SimClock.advance(2.75)  # off the one- and two-second cycle boundaries
	var at := SimClock.sim_time
	assert_true(plan.salvos > 0, "the strike has fired by the second save")
	assert_true(at < float(plan.volley_until.get(plan.target_track_id, -1.0)), "the volley is still open")
	assert_true(not _sim.weapon_manager._pending.is_empty() or not _sim.weapon_manager.in_flight.is_empty(), "rounds on the way")
	var striking := SimSnapshot.capture(_sim)
	SimClock.advance(500.0)
	var expected_struck := _bytes()
	_free()
	_fresh(PLAN_FIXTURE, 999)
	assert_eq(_sim.restore_snapshot(searching), "")
	plan = _sim.ai_controllers["RED"].plans[0]
	assert_eq(plan.phase, AIPlan.Phase.RECON)
	assert_true(plan.members.has(_unit("Otlichny")) and plan.members.has(_unit("Backfire Scout")), "members come back as the units in the list")
	SimClock.advance(900.0 - 150.75)
	var got := _bytes()
	if got != expected_found:
		failures.append("continuation from the search differs: %s" % _first_difference(bytes_to_var(expected_found), bytes_to_var(got), ""))
	_free()
	_fresh(PLAN_FIXTURE, 5)
	assert_eq(_sim.restore_snapshot(striking), "")
	plan = _sim.ai_controllers["RED"].plans[0]
	assert_true(_sim.track_manager.get_tracks("RED").has(plan.target), "the plan's target is the track in its side's own picture")
	assert_true(plan.weapons_free and plan.salvos > 0, "the strike's progress comes back")
	assert_true(not plan.assessing(plan.target_track_id, at) and plan.assessing(plan.target_track_id, at + AIPlan.VOLLEY_S + 1.0), "the open volley, and the shared assessment after it")
	SimClock.advance(500.0)
	got = _bytes()
	if got != expected_struck:
		failures.append("continuation from the volley differs: %s" % _first_difference(bytes_to_var(expected_struck), bytes_to_var(got), ""))
	_free()


func test_restore_into_the_same_simulation_is_an_identity() -> void:
	_fresh(PASSAGE, 31)
	SimClock.advance(612.75)  # off the one- and two-second cycle boundaries
	var first := SimSnapshot.capture(_sim)
	assert_eq(_sim.restore_snapshot(first), "")
	assert_true(var_to_bytes(SimSnapshot.capture(_sim)) == var_to_bytes(first), "captured again, nothing changed")
	_free()


## A snapshot kept in memory (never written out) stays what it was when it was taken. A track's
## observation window is a packed array, which a Variant shares rather than copies; held by
## reference, the snapshot went on changing with the battle, and a restored battle wrote back
## into it, so loading it a second time gave a different engagement.
func test_a_snapshot_held_in_memory_does_not_change_with_the_battle() -> void:
	_fresh(PASSAGE, 31)
	SimClock.advance(120.0)
	var snapshot := SimSnapshot.capture(_sim)
	var taken := var_to_bytes(snapshot)
	SimClock.advance(30.0)
	assert_true(var_to_bytes(snapshot) == taken, "unchanged by the battle going on")
	assert_eq(_sim.restore_snapshot(snapshot), "")
	SimClock.advance(30.0)
	assert_true(var_to_bytes(snapshot) == taken, "unchanged by the restored battle going on")
	_free()


func test_restore_emits_no_simulation_events() -> void:
	_fresh(CARRIER_WATCH, 31)
	SimClock.advance(400.0)
	var snapshot := SimSnapshot.capture(_sim)
	var heard := []
	_sim.track_manager.track_added.connect(func(_f: String, _t: Track) -> void: heard.append("track"))
	_sim.threat_manager.threat_detected.connect(func(_f: String, _w: Weapon) -> void: heard.append("threat"))
	_sim.unit_manager.unit_added.connect(func(_u: Unit) -> void: heard.append("unit"))
	_sim.aviation_manager.aircraft_launched.connect(func(_a: Unit, _p: Unit) -> void: heard.append("launch"))
	assert_eq(_sim.restore_snapshot(snapshot), "")
	assert_eq(heard, [], "nothing is detected, added or launched a second time")
	_free()


func test_references_come_back_as_the_same_objects() -> void:
	_fresh(CARRIER_WATCH, 31)
	_play_to_save_point()
	assert_eq(_sim.restore_snapshot(SimSnapshot.capture(_sim)), "")
	var by_id := {}
	for u in _sim.unit_manager.units:
		by_id[u.id] = u
	for u in _sim.unit_manager.units:
		if u.home != null:
			assert_true(by_id[u.home.id] == u.home, "%s home is the unit in the list" % u.callsign)
			assert_true(u.home.embarked.has(u) or not u.alive, "%s is in its home's air wing" % u.callsign)
		if u.attack_track != null:
			var held := false
			for list: Array in _sim.track_manager._tracks.values():
				held = held or list.has(u.attack_track)
			assert_true(held or u.attack_track.status == Track.Status.LOST, "an attack follows the plotted track object itself")
	for w: Weapon in _sim.weapon_manager.in_flight:
		if w.shooter != null:
			assert_true(by_id[w.shooter.id] == w.shooter)
	for m: AirMission in _sim.air_mission_manager.missions:
		for a in m.aircraft:
			assert_true(_sim.air_mission_manager.mission_for(a) == m, "mission ownership survives")
	_free()


func test_the_sea_floor_cache_survives_a_reload() -> void:
	_fresh(PASSAGE, 31)
	SimClock.advance(300.0)
	var before := {}
	for u in _sim.unit_manager.units:
		before[u.id] = [u.bottom_depth_m, u.bottom_sampled_at, u.bottom_generation == Bathymetry.generation]
	assert_eq(_sim.restore_snapshot(SimSnapshot.capture(_sim)), "")
	for u in _sim.unit_manager.units:
		var b: Array = before[u.id]
		assert_eq([u.bottom_depth_m, u.bottom_sampled_at, u.bottom_generation == Bathymetry.generation], b, u.callsign)
	_free()


func test_damaged_foreign_and_newer_saves_are_refused_and_the_battle_is_untouched() -> void:
	_fresh(PASSAGE, 31)
	SimClock.advance(200.0)
	var good := SimSnapshot.capture(_sim)
	var units_before := _sim.unit_manager.units.size()
	var time_before := SimClock.sim_time
	var cases := {
		"not a dictionary": [[], "Not a saved engagement"],
		"foreign format": [{"format": "something else"}, "Not a saved engagement (unknown format)"],
	}
	var newer := good.duplicate(true)
	newer["version"] = SimSnapshot.VERSION + 1
	cases["newer"] = [newer, "Saved by a newer version of the game"]
	var tampered := good.duplicate(true)
	tampered["scenario"]["name"] = "SOMETHING ELSE"
	cases["damaged"] = [tampered, "Saved engagement is damaged"]
	var unknown := good.duplicate(true)
	unknown["units"][0]["spec"] = {"$p": "no_such_platform"}
	cases["unknown platform"] = [unknown, "Saved engagement uses platform 'no_such_platform'"]
	var incomplete := good.duplicate(true)
	incomplete.erase("weapons")
	cases["incomplete"] = [incomplete, "Saved engagement is incomplete"]
	# Structural damage that passed earlier checks and stopped a restore half-way.
	var garbage := good.duplicate(true)
	garbage["units"][3] = "garbage"
	cases["garbage record"] = [garbage, "Saved engagement is damaged (a record in units)"]
	var dangling := good.duplicate(true)
	dangling["units"][0]["formation_leader"] = {"$u": 999}
	cases["dangling unit"] = [dangling, "Saved engagement is damaged (unit 999 missing)"]
	var lost_track := good.duplicate(true)
	lost_track["managers"]["TrackManager"]["_tracks"]["BLUE"] = [{"$t": 100000}]
	cases["dangling track"] = [lost_track, "Saved engagement is damaged (track 100000 missing)"]
	var twin := good.duplicate(true)
	twin["units"][1]["id"] = twin["units"][0]["id"]
	cases["duplicate id"] = [twin, "Saved engagement is damaged (two units"]
	var bad_stream := good.duplicate(true)
	bad_stream["rng"]["damage"] = ["x"]
	cases["random stream"] = [bad_stream, "Saved engagement is damaged (random stream damage)"]
	for name: String in cases:
		var why := _sim.restore_snapshot(cases[name][0])
		assert_true(why.begins_with(str(cases[name][1])), "%s: %s" % [name, why])
		assert_eq(_sim.unit_manager.units.size(), units_before, name)
		assert_eq(SimClock.sim_time, time_before, name)
	_free()


func test_save_files_reject_garbage_and_stay_in_their_own_storage() -> void:
	SaveGame.root_override = _scratch
	DirAccess.make_dir_recursive_absolute(_scratch)
	var junk := _scratch.path_join("junk." + SaveGame.EXTENSION)
	var f := FileAccess.open(junk, FileAccess.WRITE)
	f.store_string("not a save at all")
	f.close()
	assert_true(not str(SaveGame.read(junk)["error"]).is_empty(), "plain text is not a save")
	assert_eq(SaveGame.read(_scratch.path_join("missing." + SaveGame.EXTENSION))["error"], "No saved engagement there")
	DirAccess.remove_absolute(junk)
	assert_true(SaveGame.root().begins_with("user://test-saves"), "tests never write to a player's saves")
	# Autosaves keep a bounded history.
	for i in SaveGame.AUTOSAVE_KEEP + 3:
		var slot := SaveGame.next_autosave_slot()
		assert_eq(SaveGame.write(SaveGame.slot_path(slot), {"serial": SaveGame.next_serial(), "label": slot}, {"simulation": {}}), "")
		SaveGame.prune_autosaves()
	var autos := SaveGame.list_saves().filter(func(h: Dictionary) -> bool: return str(h["slot"]).begins_with(SaveGame.AUTOSAVE_PREFIX))
	assert_eq(autos.size(), SaveGame.AUTOSAVE_KEEP, "only the newest autosaves are kept")
	assert_eq(str(autos[0]["slot"]), SaveGame.AUTOSAVE_PREFIX + str(SaveGame.AUTOSAVE_KEEP + 3), "newest first")
	for h in SaveGame.list_saves():
		DirAccess.remove_absolute(str(h["path"]))
	DirAccess.remove_absolute(_scratch)
	SaveGame.root_override = ""


## Bytes changed on disk inside a well-formed compressed stream must not load as a different
## battle: the header carries a checksum of the engagement.
func test_a_save_damaged_on_disk_never_loads_as_a_different_battle() -> void:
	_fresh(PASSAGE, 31)
	SimClock.advance(120.0)
	SaveGame.root_override = _scratch
	var path := SaveGame.slot_path("flipped")
	assert_eq(SaveGame.write(path, {"label": "test"}, {"simulation": SimSnapshot.capture(_sim)}), "")
	var original := var_to_bytes(SaveGame.read(path)["payload"])
	var raw := FileAccess.get_file_as_bytes(path)
	var accepted_changed := 0
	var refused := 0
	for i in 60:
		var damaged := raw.duplicate()
		var at := 8 + int(float(i) / 60.0 * float(raw.size() - 9))
		damaged[at] = damaged[at] ^ 0x5A
		var copy := FileAccess.open(path, FileAccess.WRITE)
		copy.store_buffer(damaged)
		copy.close()
		var back := SaveGame.read(path)
		if str(back.get("error", "")) != "":
			refused += 1
		elif var_to_bytes(back["payload"]) != original:
			accepted_changed += 1
	assert_eq(accepted_changed, 0, "no damaged file loads as a different battle")
	assert_true(refused > 0)
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(_scratch)
	SaveGame.root_override = ""
	_free()


## Loading from the list can happen over any operation, or none: the save brings its own world.
func test_a_save_restores_over_a_different_operation() -> void:
	_fresh(PASSAGE, 31)
	SimClock.advance(300.75)
	var saved := _write_and_read(SimSnapshot.capture(_sim))
	SimClock.advance(120.0)
	var expected := _bytes()
	_free()
	_fresh(CARRIER_WATCH, 7)
	SimClock.advance(50.0)
	assert_eq(_sim.restore_snapshot(saved), "")
	assert_eq(_sim.scenario_name, str(saved["scenario"].get("name", "")))
	SimClock.advance(120.0)
	var got := _bytes()
	if got != expected:
		failures.append("restored over another operation, the battle differs: %s" % _first_difference(bytes_to_var(expected), bytes_to_var(got), ""))
	_free()


## Every script variable on the saved classes is either saved or listed as transient with a
## reason, so state added later cannot silently fall out of a save.
func test_every_simulation_field_is_saved_or_declared_transient() -> void:
	_fresh(CARRIER_WATCH, 31)
	for pair: Array in [[Unit.new(), SimSnapshot.UNIT_SKIP], [Track.new(), SimSnapshot.TRACK_SKIP], [Weapon.new(), SimSnapshot.WEAPON_SKIP], [AirMission.new(), SimSnapshot.MISSION_SKIP], [Sonobuoy.new(), SimSnapshot.BUOY_SKIP], [AIPlan.new(), SimSnapshot.PLAN_SKIP]]:
		# Reflective classes: everything is saved except what the skip list names, and the skip
		# list names only real fields.
		var names := SimSnapshot.script_variables(pair[0])
		for skipped: String in (pair[1] as Dictionary):
			assert_true(names.has(skipped), "%s skip list names a field that exists" % skipped)
	var managers: Array = [_sim.unit_manager, _sim.track_manager, _sim.sensor_manager, _sim.threat_manager, _sim.weapon_manager, _sim.aviation_manager, _sim.air_mission_manager, _sim.mission_manager]
	managers.append_array(_sim.ai_controllers.values())
	for node: Object in managers:
		var name: String = node.get_script().get_global_name()
		var saved: Array = SimSnapshot.MANAGER_FIELDS.get(name, [])
		var transient: Array = SimSnapshot.MANAGER_TRANSIENT.get(name, [])
		for field: String in SimSnapshot.script_variables(node):
			assert_true(saved.has(field) or transient.has(field), "%s.%s is neither saved nor declared transient" % [name, field])
	_free()


## The path to the first difference between two snapshots, for a readable failure.
func _first_difference(a: Variant, b: Variant, path: String) -> String:
	if typeof(a) != typeof(b):
		return "%s: %s vs %s" % [path, a, b]
	match typeof(a):
		TYPE_DICTIONARY:
			for k in a:
				if not b.has(k):
					return "%s/%s missing" % [path, k]
				var d := _first_difference(a[k], b[k], "%s/%s" % [path, k])
				if d != "":
					return d
			for k in b:
				if not a.has(k):
					return "%s/%s extra" % [path, k]
			return ""
		TYPE_ARRAY:
			if a.size() != b.size():
				return "%s: %d vs %d entries" % [path, a.size(), b.size()]
			for i in a.size():
				var d := _first_difference(a[i], b[i], "%s[%d]" % [path, i])
				if d != "":
					return d
			return ""
	return "" if var_to_bytes(a) == var_to_bytes(b) else "%s: %s vs %s" % [path, a, b]
