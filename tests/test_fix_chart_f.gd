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


# --- The overview map keeps its names off the force --------------------------------------------

func test_the_overview_map_prints_no_place_name_across_an_own_ship() -> void:
	var preview := ScenarioPreview.new()
	_root().add_child(preview)
	# The own symbol's frame and heading tick reach this far from its centre at the preview's scale.
	var reach := (MapSymbols.RADIUS + MapSymbols.HEADING_TICK) * 0.8
	for file in DirAccess.get_files_at("res://data/scenarios"):
		if not file.ends_with(".json"):
			continue
		var sc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/" + file))
		if not sc is Dictionary or not (sc as Dictionary).has("map"):
			continue
		preview.set_scenario(sc)
		for side in [180.0, 240.0, 300.0, 380.0]:
			preview.size = Vector2(side, side)
			var layout := preview.label_layout()
			var names := []
			for placed: Dictionary in layout["labels"]:
				names.append(placed["text"])
				var rect: Rect2 = placed["rect"]
				for unit: Dictionary in layout["force"]:
					var ship := Rect2((unit["point"] as Vector2) - Vector2.ONE * reach, Vector2.ONE * reach * 2.0)
					assert_true(not ship.intersects(rect), "%s: '%s' prints clear of the ship at %s on a %d px map" % [file, placed["text"], unit["point"], side])
			if file == "aegis_bastion.json" and side >= 240.0:
				# The desk's first operation opens with the force off the cape: the name moves
				# clear of the ships rather than leaving the map unnamed.
				assert_true(not (layout["force"] as Array).is_empty(), "the force is on the map at %d px" % side)
				assert_true(names.has("NORTH CAPE"), "the cape the force is rounding is still named at %d px: %s" % [side, names])
	preview.free()


# --- The chart's numbers: clear of the hook and of each other ----------------------------------

func _label(key: String, at: Vector2, number: String, priority := false) -> Dictionary:
	var hook := roundf(TacticalMap._bracket_box(MapSymbols.RADIUS) * 0.5) + MapSymbols.STROKE * 0.5 if priority else 0.0
	return {"key": key, "at": at, "extent": MapSymbols.RADIUS, "size": Vector2(39, 17), "ascent": 13.0, "priority": priority, "number": number, "tag": "", "alpha": 1.0, "hook": hook}


func test_the_hooked_number_stands_a_clear_space_from_its_brackets() -> void:
	var at := Vector2(400, 300)
	var hooked := _label("u:1", at, "0004", true)
	var half := roundf(TacticalMap._bracket_box(MapSymbols.RADIUS) * 0.5) + MapSymbols.STROKE * 0.5
	for k in ChartLabels.OFFSETS.size():
		var rect := ChartLabels.slot_box(hooked, k)
		var clear := rect.position.x - (at.x + half) if ChartLabels.OFFSETS[k].x > 0.0 else (at.x - half) - rect.end.x
		assert_true(clear >= 5.0, "the number in corner %d stands %.0f px from the brackets' outer edge, enough not to read as '[]0004'" % [k, clear])


func test_numbers_in_neighbouring_corners_do_not_stack_into_one_block() -> void:
	# Northern Passage at ten minutes, 1280x720: the hooked flagship, the frigate and the merchant
	# in a column, a contact beside them, as the chart queued them.
	var labels := [
		_label("t:1001", Vector2(732, 275), "1001"),
		_label("t:1002", Vector2(635, 361), "1002"),
		_label("t:1003", Vector2(743, 238), "1003"),
		_label("u:1", Vector2(607, 331), "0001", true),
		_label("u:2", Vector2(607, 368), "0002"),
		_label("u:3", Vector2(589, 349), "0003"),
	]
	var slots := ChartLabels.place(labels, Rect2(0, 0, 1280, 720))
	var placed: Array[Rect2] = []
	for l: Dictionary in labels:
		var k := int(slots[l.key])
		assert_true(k != ChartLabels.HIDDEN, "%s keeps its number" % l.number)
		if k != ChartLabels.HIDDEN:
			placed.append(ChartLabels.slot_box(l, k))
	for i in placed.size():
		for j in range(i + 1, placed.size()):
			var a := placed[i]
			var b := placed[j]
			if a.position.x < b.end.x and b.position.x < a.end.x:
				var gap := maxf(b.position.y - a.end.y, a.position.y - b.end.y)
				assert_true(gap >= 4.0, "two numbers over each other keep %.0f px apart, enough to read as two labels: %s %s" % [gap, a, b])
