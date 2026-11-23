extends TestCase
## The Air Operations dialog on the shipped Carrier Watch operation: it fits the window at both
## common interface sizes, its planner does not carry a wrong choice from one mission to the next,
## and an accepted order is answered with what was done.

const CARRIER_WATCH := "res://data/scenarios/cold_war_03_carrier.json"
const IKE := "USS Dwight D. Eisenhower (CVN 69)"
const TOMCAT := "cw90_f14a"

var _sim: Simulation
var _holder: Control


func _load() -> Simulation:
	SimClock.set_paused(true)
	_sim = Simulation.new()
	_sim.seed_override = 7
	(Engine.get_main_loop() as SceneTree).root.add_child(_sim)
	assert_true(_sim.load_scenario(CARRIER_WATCH), CARRIER_WATCH)
	_sim.ai_enabled = false
	return _sim


func _done() -> void:
	if _holder != null:
		_holder.free()
		_holder = null
	_sim.unit_manager.clear()
	_sim.queue_free()
	_sim.free()
	_sim = null


func _unit(callsign: String) -> Unit:
	for u in _sim.unit_manager.units:
		if u.callsign == callsign:
			return u
	return null


## The dialog in a window of the given logical size, dressed in the game's own theme, with its
## orders carried out and answered as Main answers them.
func _dialog(window: Vector2) -> AirOperations:
	_holder = Control.new()
	_holder.theme = UITheme.build()
	_holder.size = window
	(Engine.get_main_loop() as SceneTree).root.add_child(_holder)
	var ui := AirOperations.new()
	ui.simulation = _sim
	_holder.add_child(ui)
	ui.order_requested.connect(func(base: Unit, order: Order) -> void:
		var ok := _sim.unit_manager.issue_order(base, order)
		ui.show_receipt(order.receipt if order.receipt != "" else ("accepted" if ok else "refused"), ok))
	return ui


## Lays the dialog out now, as the next frames would: measure, fit, place, and again once wrapped
## text knows its width.
func _layout(ui: AirOperations) -> void:
	for i in 4:
		ui._fit()
		ui.propagate_notification(Container.NOTIFICATION_SORT_CHILDREN)


func _inside(outer: Rect2, c: Control) -> bool:
	var r := c.get_global_rect()
	return c.is_visible_in_tree() and outer.grow(1.0).encloses(r)


func _assign_cap(ui: AirOperations, cv: Unit, offset: Vector2, count: int) -> void:
	ui._plan_tabs.current_tab = 1
	ui.set_mission_kind(AirMission.Kind.CAP)
	ui._type_id = TOMCAT
	ui.refresh()
	ui.apply_station(cv.position + offset)
	ui._count.value = count
	assert_true(not ui._launch.disabled, "%s: %s" % [ui._launch.text, ui._launch_hint.text])
	ui._launch_selected()


# --- The dialog fits ----------------------------------------------------------------------

## With twelve Tomcats on the deck and three CAPs flying, both lists show at least six entries,
## the page needs no scroll bar of its own, and the receipt and the mission commands stand inside
## the dialog, which stands inside the window, at 1600 x 900 and at 125 percent (1280 x 720).
func test_the_dialog_keeps_six_rows_in_each_list_and_its_receipt_in_sight() -> void:
	for window: Vector2 in [Vector2(1600, 900), Vector2(1280, 720)]:
		_load()
		var cv := _unit(IKE)
		var ui := _dialog(window)
		ui.open_for([cv])
		_assign_cap(ui, cv, Vector2(40, 45), 4)
		_assign_cap(ui, cv, Vector2(-40, 45), 4)
		_assign_cap(ui, cv, Vector2(0, 60), 2)
		ui._type_id = TOMCAT
		ui.refresh()
		ui._lower_tabs.current_tab = 1
		_layout(ui)
		var where := "%dx%d" % [int(window.x), int(window.y)]
		var dialog := ui._dialog.get_global_rect()
		assert_true(Rect2(Vector2.ZERO, window).encloses(dialog), "%s: the dialog %s stands inside the window" % [where, dialog])
		assert_true(ui._deck_rows.size() >= 12, "%s: %d Tomcats on the deck" % [where, ui._deck_rows.size()])
		var deck_rows := ui._deck_frame.size.y / ui._deck_row_height()
		assert_true(deck_rows >= 7.0 - 0.05, "%s: the deck shows a heading and six airframes, not %.1f rows" % [where, deck_rows])
		var tree_rows := ui._tree_rows(ui._missions)
		assert_true(tree_rows >= 12, "%s: three missions and their airframes make %d rows" % [where, tree_rows])
		var row := ui._tree_row_height(ui._missions)
		var shown := (ui._missions.size.y - ui._missions.get_theme_stylebox("panel").get_minimum_size().y) / row - 1.0
		assert_true(shown >= 6.0 - 0.05, "%s: the missions list shows six rows below its titles, not %.1f" % [where, shown])
		assert_true(ui._page.get_combined_minimum_size().y <= ui._body.size.y + 1.0, "%s: the page needs %.0f px and has %.0f, so it would scroll" % [where, ui._page.get_combined_minimum_size().y, ui._body.size.y])
		assert_true(not ui._body.is_ancestor_of(ui._receipt), "%s: the receipt sits in the fixed footer, not the scrolling page" % where)
		for c: Control in [ui._receipt, ui._back, ui._launch, ui._edit_mission, ui._cancel_mission]:
			assert_true(_inside(dialog, c), "%s: %s %s stands inside the dialog %s" % [where, c.get_class(), c.get_global_rect(), dialog])
		assert_true(ui._receipt.text.contains("Combat air patrol"), ui._receipt.text)
		ui.free()
		_done()


## With nothing airborne and no missions the dialog stands only as tall as what it shows, instead
## of a full-height frame two thirds empty.
func test_the_dialog_stands_as_tall_as_its_content() -> void:
	_load()
	var cv := _unit(IKE)
	var ui := _dialog(Vector2(1600, 900))
	ui.open_for([cv])
	_layout(ui)
	assert_true(not ui._lower_tabs.visible, "no airborne aircraft and no missions")
	var need := ui._page.get_combined_minimum_size().y
	assert_true(ui._body.size.y <= need + 2.0, "the page area is %.0f px for %.0f px of content" % [ui._body.size.y, need])
	assert_eq(ui._back.text, UITheme.DIALOG_CLOSE, "one CLOSE, in the shared dialog header")
	assert_true(ui._header.is_ancestor_of(ui._back), "CLOSE sits in the header")
	ui.free()
	_done()
