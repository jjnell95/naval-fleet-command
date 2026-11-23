extends TestCase
## The overview map, the chart's labels, the key board, the reference book and the debrief show
## what is there: map names clear of the force, a hooked number clear of its bracket, close numbers
## kept apart, the restart key as it behaves, one heading for civil shipping and hits counted once.


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


# --- The key board's restart row ---------------------------------------------------------------

func test_the_key_board_says_one_ctrl_f10_restarts_after_asking() -> void:
	var rows := KeyCommands.all_rows()
	var restart := ""
	for row: String in rows:
		if row.contains("Restart the mission"):
			restart = row
	assert_true(restart != "", "the board has a restart row")
	assert_true(restart.begins_with("Ctrl+F10:"), "one Ctrl+F10 opens the restart question, so the key is not doubled: %s" % restart)
	assert_true(not restart.contains("twice"), "the row does not ask for the key twice: %s" % restart)
	assert_true(restart.contains("asks first"), "the row says the game asks before it restarts: %s" % restart)


# --- One heading for civil shipping ------------------------------------------------------------

func test_civil_shipping_sits_under_one_reference_heading() -> void:
	var civil := {}
	for p: PlatformSpec in DataDB.all_platforms():
		if p.nation.begins_with("Civil"):
			civil[p.nation] = true
	assert_eq(civil.keys().size(), 1, "every merchant, tanker and trawler names the same civil owner: %s" % [civil.keys()])
	var lib := PlatformLibrary.new()
	_root().add_child(lib)
	lib._filter("", [], false)
	var headings := []
	for row in lib._list.item_count:
		if not lib._list.is_item_selectable(row) and lib._list.get_item_text(row).begins_with("CIVIL"):
			headings.append(lib._list.get_item_text(row))
	assert_eq(headings.size(), 1, "the reference lists civil shipping under one heading: %s" % [headings])
	lib.free()


# --- The debrief's hits scored -----------------------------------------------------------------

func test_hits_on_a_neutral_are_civilian_incidents_not_hits_scored() -> void:
	var save_root := SaveGame.root_override
	var log_path := CommanderLog.path_override
	var use_worker := SaveGame.use_worker
	SaveGame.root_override = "user://test-chart-f-%d" % Time.get_ticks_usec()
	CommanderLog.path_override = SaveGame.root_override + "-log.json"
	var main: Main = preload("res://scenes/main/Main.tscn").instantiate()
	_root().add_child(main)
	main._apply_options(GameOptions.normal(), false, false)
	main.simulation.seed_override = 2
	main.start_scenario("res://data/scenarios/northern_passage.json")
	main._on_briefing_start()
	SimClock.set_paused(true)
	var sim := main.simulation
	var neutral: Unit = null
	var hostile: Unit = null
	var own: Unit = null
	for u: Unit in sim.unit_manager.units:
		if neutral == null and sim.mission_manager.neutral_factions.has(u.faction):
			neutral = u
		elif hostile == null and u.faction != sim.player_faction and not sim.mission_manager.neutral_factions.has(u.faction):
			hostile = u
		elif own == null and u.faction == sim.player_faction:
			own = u
	assert_true(neutral != null and hostile != null and own != null, "the operation has a neutral, an enemy and an own ship")
	var spec := DataDB.weapon("agm_84_harpoon")
	# Two rounds strike the merchant the force had held as neutral, one strikes the enemy and one
	# strikes a ship of the force's own.
	sim.weapon_manager.weapon_impact.emit(sim.player_faction, spec, neutral, true)
	sim.weapon_manager.weapon_impact.emit(sim.player_faction, spec, neutral, true)
	sim.weapon_manager.weapon_impact.emit(sim.player_faction, spec, hostile, true)
	sim.weapon_manager.weapon_impact.emit(sim.player_faction, spec, own, true)
	main._on_mission_ended("DEFEAT", "Test")
	var sword := ""
	for line: String in main._report._timeline.text.split("\n"):
		if line.contains("hits scored"):
			sword = line
	assert_true(sword.ends_with("· 1 hits scored") or sword.ends_with("· 1 hit scored"), "only the hit on the enemy is a hit scored: %s" % sword)
	assert_eq(((main._report._tiles["hits_scored"] as Dictionary)["value"] as Label).text, "1", "the results tile counts the enemy hit alone")
	assert_true(main._report._body.text.contains("2 hits on a neutral"), "the hits on the merchant are civilian incidents")
	SaveGame.finish_writing()
	SaveGame.force_next_autosave = false
	SaveGame.use_worker = use_worker
	main.free()
	var dir := DirAccess.open(SaveGame.root_override)
	if dir != null:
		for file in dir.get_files():
			dir.remove(file)
		DirAccess.remove_absolute(SaveGame.root_override)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CommanderLog.path()))
	SaveGame.root_override = save_root
	CommanderLog.path_override = log_path
	SimClock.set_speed_index(0)
	SimClock.set_paused(true)
