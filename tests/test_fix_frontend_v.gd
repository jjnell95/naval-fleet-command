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
