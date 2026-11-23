extends TestCase
## What the desk, the briefing, the reference book and the debrief tell the player agrees with what
## the game does: the rule of manual missile defence, a catalogue whose every row sits under its
## heading, and every hit on a neutral named in the debrief that charges for it.


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


# --- Manual missile defence as the desk and the briefing word it ----------------------------

func test_manual_defence_summary_says_point_defence_missiles_fire_by_themselves() -> void:
	var options := GameOptions.classic()
	assert_true(options.manual_missile_defence(), "the classic preset holds missile defence for orders")
	var line := ""
	for l: String in options.summary_lines():
		if l.begins_with("Missile defence:"):
			line = l
	assert_true(line != "", "the summary has a missile-defence line")
	assert_true(line.contains("area SAMs"), "the line says it is the area SAMs that wait for the order: %s" % line)
	assert_true(line.contains("point-defence missiles"), "the line says the point-defence missiles fire by themselves, as they do: %s" % line)
	assert_true(not line.contains("ships fire SAMs only when ordered"), "the line no longer says every SAM waits for the order")
	var tooltip := GameOptions.option_tooltip("manual_defence")
	assert_true(tooltip.contains("point-defence missiles fire by themselves"), "the summary and the option's own tooltip state the same rule")


# --- The reference catalogue's headings ------------------------------------------------------

func test_every_reference_row_sits_under_a_worded_heading_and_shared_platforms_come_after_the_navies() -> void:
	var lib := PlatformLibrary.new()
	_root().add_child(lib)
	lib._filter("", [], false)
	assert_true(lib._list.item_count > 2, "the catalogue lists its platforms")
	assert_true(not lib._list.is_item_selectable(0), "the list opens on a heading, not on an entry without one")
	var seen_shared := -1
	var last_navy := -1
	for row in lib._list.item_count:
		if lib._list.is_item_selectable(row):
			continue
		var heading := lib._list.get_item_text(row)
		assert_true(heading.strip_edges() != "", "row %d is a heading with words on it, not a blank line" % row)
		if heading == PlatformLibrary.SHARED_HEADING.to_upper():
			seen_shared = row
		elif not heading.begins_with("CIVIL"):
			last_navy = row
	var station := -1
	for i in lib._specs.size():
		if (lib._specs[i] as PlatformSpec).nation == "":
			station = lib._rows.find(i)
			break
	if station >= 0:
		assert_true(seen_shared >= 0 and seen_shared < station, "a platform of no one navy sits under the shared heading")
		assert_true(seen_shared > last_navy, "and the shared platforms follow every navy rather than heading the list")
		var head := station - 1
		while head >= 0 and lib._list.is_item_selectable(head):
			head -= 1
		assert_eq(lib._list.get_item_text(head), PlatformLibrary.SHARED_HEADING.to_upper(), "the nearest heading above an air station is the shared one")
	lib.free()


# --- The debrief's civilian incidents --------------------------------------------------------

var _save_root := ""
var _log_path := ""
var _clock_speeds: Array[float] = []


func _open_main(scenario := "res://data/scenarios/northern_passage.json") -> Main:
	_save_root = SaveGame.root_override
	_log_path = CommanderLog.path_override
	_clock_speeds = SimClock.speeds()
	SaveGame.root_override = "user://test-frontend-v-%d" % Time.get_ticks_usec()
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


static func _lay_out(control: Control) -> void:
	for pass_index in 3:
		for label: Control in control.find_children("*", "Label", true, false):
			label.update_minimum_size()
		control.propagate_notification(Container.NOTIFICATION_SORT_CHILDREN)


func test_the_debrief_names_every_hit_on_a_neutral_that_the_grade_charges_for() -> void:
	var main := _open_main()
	var um := main.simulation.unit_manager
	var mm := main.simulation.mission_manager
	var neutral: Unit = null
	for u in um.units:
		if mm.neutral_factions.has(u.faction) and u.callsign == "MV Coastal Star":
			neutral = u
	assert_true(neutral != null, "the passage has the coaster")
	var nsm := WeaponSpec.new()
	nsm.id = "test_nsm"
	nsm.short_name = "NSM"
	nsm.type = "asm"
	var gun := WeaponSpec.new()
	gun.id = "test_gun"
	gun.short_name = "57 mm"
	gun.type = "gun"
	um.now_s = 381.0
	mm.record_impact(main.simulation.player_faction, nsm, neutral, true)
	um.now_s = 1183.0
	mm.record_impact(main.simulation.player_faction, gun, neutral, true)
	mm.record_impact(main.simulation.player_faction, gun, neutral, true)
	main._on_mission_ended("VICTORY", "The convoy reached the handover box with its cargo intact.")
	var args: Array = main._last_report.duplicate()
	_close_main(main)
	var assessment: Dictionary = args[11]
	assert_eq(int(assessment.get("neutral_hits", 0)), 3, "the grade charges for three hits on her")
	for screen: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		var port := SubViewport.new()
		port.size = screen
		port.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_root().add_child(port)
		var report := AfterAction.new()
		port.add_child(report)
		report.callv("show_report", args)
		_lay_out(report)
		var shown := report._body.get_parsed_text()
		var at := shown.find("CIVILIAN INCIDENTS")
		assert_true(at >= 0, "%s: the debrief has its civilian incidents section" % screen)
		var section := shown.substr(at, shown.find("\n", at) - at if shown.find("\n", at) > at else -1)
		assert_true(section.contains("3 hits on a neutral"), "%s: it counts the three hits the grade charges for: %s" % [screen, section])
		assert_true(section.contains("MV Coastal Star"), "%s: and names the vessel struck" % screen)
		assert_true(section.contains("NSM at 6 min") and section.contains("57 mm ×2 at 19 min"), "%s: with each weapon and the mission time it struck: %s" % [screen, section])
		assert_true(not section.contains("No "), "%s: and does not say nothing happened" % screen)
		var body := report._body
		assert_true(body.get_content_height() <= body.size.y + 1.0, "%s: the results still read whole, %d px of %d" % [screen, body.get_content_height(), int(body.size.y)])
		port.free()


func test_a_debrief_from_an_older_report_without_the_hit_record_still_names_the_sinkings() -> void:
	assert_eq(AfterAction.civilian_text(PackedStringArray(), []), "No hits on neutral vessels by your force")
	var text := AfterAction.civilian_text(PackedStringArray(["MV Skerry Trader"]), [])
	assert_true(text.contains("1 neutral vessel sunk: MV Skerry Trader"), text)
	var many: Array = []
	for i in 9:
		many.append({"time_s": 60.0 * i, "callsign": "Dhow %d" % (i % 7), "weapon": "gun"})
	text = AfterAction.civilian_text(PackedStringArray(), many)
	assert_true(text.contains("9 hits on a neutral") and text.contains("Dhow 0 (gun at 0 min, gun at 7 min)") and text.contains("2 other vessels"), "a long record is named in part and counted whole: %s" % text)
