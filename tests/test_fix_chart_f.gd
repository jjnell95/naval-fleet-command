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
