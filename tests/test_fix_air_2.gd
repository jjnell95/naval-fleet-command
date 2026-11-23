extends TestCase
## The Air Operations dialog on the shipped Carrier Watch operation: it fits the window at both
## common interface sizes, its planner does not carry a wrong choice from one mission to the next,
## and an accepted order is answered with what was done.

const CARRIER_WATCH := "res://data/scenarios/cold_war_03_carrier.json"
const IKE := "USS Dwight D. Eisenhower (CVN 69)"
const TOMCAT := "cw90_f14a"
const NORTHERN_PASSAGE := "res://data/scenarios/northern_passage.json"

var _sim: Simulation
var _holder: Control


func _load(path := CARRIER_WATCH) -> Simulation:
	SimClock.set_paused(true)
	_sim = Simulation.new()
	_sim.seed_override = 7
	(Engine.get_main_loop() as SceneTree).root.add_child(_sim)
	assert_true(_sim.load_scenario(path), path)
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


# --- The mission planner does not carry a wrong choice ------------------------------------

## Choosing a mission the chosen type cannot fly moves the type picker to the deck's type that
## can, with one aircraft, instead of offering "ASSIGN STRIKE · 0" for a type with no weapons.
func test_a_mission_opens_on_a_type_that_can_fly_it() -> void:
	_load()
	var cv := _unit(IKE)
	var ui := _dialog(Vector2(1600, 900))
	ui.open_for([cv])
	ui._type_id = TOMCAT
	ui.refresh()
	ui._plan_tabs.current_tab = 1
	for kind: int in [AirMission.Kind.ASW, AirMission.Kind.STRIKE, AirMission.Kind.RECON, AirMission.Kind.CAP]:
		ui.set_mission_kind(kind)
		var label: String = AirMission.KIND_LABELS[kind]
		var spec := DataDB.platform(ui._type_id)
		assert_true(AirMissionManager.type_suits(spec, kind), "%s opens on %s, which cannot fly it" % [label, spec.short_name])
		assert_eq(ui._type_picker.selected, ui._type_ids.find(ui._type_id), "%s: the picker shows the type chosen" % label)
		assert_true(int(ui._count.value) >= 1, "%s: one aircraft to start with, not %d" % [label, int(ui._count.value)])
		assert_true(not ui._launch_hint.text.contains("carries no") and not ui._launch_hint.text.contains("has no"), "%s: %s" % [label, ui._launch_hint.text])
	ui._type_id = TOMCAT
	ui.refresh()
	ui.set_mission_kind(AirMission.Kind.CAP)
	assert_eq(ui._type_id, TOMCAT, "a type that suits the mission is left alone")
	ui.free()
	_done()


## After a CAP is assigned, the next mission starts with no station: Reconnaissance does not open
## on the CAP's station with ASSIGN live.
func test_an_assigned_station_does_not_carry_to_the_next_mission() -> void:
	_load()
	var cv := _unit(IKE)
	var ui := _dialog(Vector2(1600, 900))
	ui.open_for([cv])
	_assign_cap(ui, cv, Vector2(40, 45), 2)
	assert_eq(_sim.air_mission_manager.active_missions("BLUE").size(), 1, ui._receipt.text)
	ui.set_mission_kind(AirMission.Kind.RECON)
	assert_true(ui._station_label.text.contains("none"), ui._station_label.text)
	assert_true(ui._launch.disabled, "nothing to assign until a search area is placed: %s" % ui._launch.text)
	ui.set_mission_kind(AirMission.Kind.CAP)
	assert_true(ui._station_label.text.contains("none"), "nor does the CAP keep it: %s" % ui._station_label.text)
	ui.free()
	_done()


## Relief and Back to station mean nothing to a strike: they show clear as well as greyed, and
## come back as the commander left them on a mission that uses them.
func test_options_a_mission_cannot_use_show_clear() -> void:
	_load()
	var cv := _unit(IKE)
	var ui := _dialog(Vector2(1600, 900))
	ui.open_for([cv])
	ui._plan_tabs.current_tab = 1
	ui.set_mission_kind(AirMission.Kind.CAP)
	ui._relief.button_pressed = true
	assert_true(ui._auto_return.button_pressed)
	ui.set_mission_kind(AirMission.Kind.STRIKE)
	for box: CheckBox in [ui._relief, ui._auto_return]:
		assert_true(box.disabled, "%s greyed for a strike" % box.text)
		assert_true(not box.button_pressed, "%s not ticked for a strike" % box.text)
	assert_true(not ui._planned_order().relief, "a strike order asks for no relief")
	ui.set_mission_kind(AirMission.Kind.CAP)
	assert_true(ui._relief.button_pressed and not ui._relief.disabled, "relief comes back for the CAP")
	assert_true(ui._auto_return.button_pressed and not ui._auto_return.disabled, "so does back to station")
	ui.free()
	_done()


## A new engagement does not open on the last one's receipt, station or target.
func test_a_new_engagement_starts_with_a_clean_receipt() -> void:
	_load()
	var cv := _unit(IKE)
	var ui := _dialog(Vector2(1600, 900))
	ui.open_for([cv])
	ui.apply_station(cv.position + Vector2(20, 20))
	ui.show_receipt("Charles de Gaulle (R 91): launching 2 of 2 × Rafale M.", true)
	ui.clear_selection()
	assert_eq(ui._receipt.text, AirOperations.RECEIPT_PROMPT)
	assert_true(not ui._station.is_finite(), "the station goes with the engagement")
	ui.free()
	_done()


# --- An accepted launch is answered with what was done ------------------------------------

## The first launch of the first operation: the destroyer's only helicopter goes, and the dialog
## says so in its footer and hint, while the button names the type instead of "LAUNCH 0 ×" over
## "Requested Aircraft Not Ready".
func test_an_accepted_launch_shows_the_receipt_not_a_refusal() -> void:
	_load(NORTHERN_PASSAGE)
	var ship := _unit("USS Truxtun (DDG 103)")
	assert_true(ship != null and not ship.stowed_aircraft().is_empty(), "the destroyer carries a ready helicopter")
	var ui := _dialog(Vector2(1280, 720))
	ui.order_requested.disconnect(ui.order_requested.get_connections()[0]["callable"])
	ui.order_requested.connect(func(base: Unit, order: Order) -> void:
		var before := base.launch_spots_busy()
		var ok := _sim.unit_manager.issue_order(base, order)
		ui.show_receipt("%s: launching %d of %d × MH-60R." % [base.callsign, base.launch_spots_busy() - before, order.aircraft_count] if ok else "refused", ok))
	ui.open_for([ship])
	assert_true(not ui._launch.disabled, "%s / %s" % [ui._launch.text, ui._launch_hint.text])
	ui._launch_selected()
	_layout(ui)
	assert_true(ui._receipt.text.contains("launching 1 of 1"), ui._receipt.text)
	assert_true(_inside(ui._dialog.get_global_rect(), ui._receipt), "the receipt is in sight")
	assert_true(not ui._launch.text.contains("0 ×"), ui._launch.text)
	assert_true(ui._launch.disabled, "nothing left to launch")
	assert_true(not ui._launch_hint.text.to_lower().contains("not ready"), ui._launch_hint.text)
	assert_true(ui._launch_hint.text.contains("launching"), ui._launch_hint.text)
	ui.free()
	_done()
