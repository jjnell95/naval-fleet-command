extends TestCase
## An operation's events: drawn once per engagement from their own stream, fired by the battle
## (a convoy's progress, what a side's own plot holds, a base's readiness), announced only to the
## side they concern, and never a source of free information. A contact report is a datum to go
## and look at, not a firing solution; a tasking change says what changed and is credited fairly.

var _um: UnitManager
var _tm: TrackManager
var _mm: MissionManager
var _director: OperationDirector
var _heard: Array = []


func _harness(units: Array, objectives: Dictionary, events: Array, seed := 7) -> OperationDirector:
	Terrain.clear()
	_um = UnitManager.new()
	_tm = TrackManager.new()
	_mm = MissionManager.new()
	_mm.unit_manager = _um
	_mm.track_manager = _tm
	_director = OperationDirector.new()
	_director.unit_manager = _um
	_director.track_manager = _tm
	_director.mission_manager = _mm
	_heard = []
	_director.message.connect(func(text: String) -> void: _heard.append(text))
	var sc := {"player_faction": "BLUE", "map": {"anchor_lat": 68.0, "anchor_lon": 4.0}, "units": units,
		"objectives": objectives, "events": events}
	ScenarioLoader.populate(_um, sc)
	_mm.configure(sc)
	_director.configure(sc, seed)
	return _director


func _cleanup() -> void:
	_director.free()
	_mm.free()
	_tm.free()
	_um.free()


func _unit(callsign: String) -> Unit:
	for u in _um.units:
		if u.callsign == callsign:
			return u
	return null


func _convoy() -> Array:
	return [
		{"platform": "cw90_merchant", "callsign": "Cargo", "faction": "BLUE", "position_nm": [0, 0]},
		{"platform": "cw90_perry", "callsign": "Escort", "faction": "BLUE", "position_nm": [2, 0]},
		{"platform": "cw90_nanuchka", "callsign": "Corvette", "faction": "RED", "position_nm": [0, 30], "patrol_nm": [[0, 20]]},
	]


const WATCH := {"victory": [{"id": "watch", "type": "time_elapsed", "seconds": 3600, "text": "Complete the watch"}], "loss": []}


func test_draws_are_repeatable_per_seed_and_differ_between_seeds() -> void:
	var events := [
		{"id": "raid", "at_s_window": [1200, 3000], "variants": [{"id": "north", "message": "north"}, {"id": "east", "message": "east"}, {"id": "south", "weight": 2, "message": "south"}]},
		{"id": "second", "chance": 0.5, "at_s_window": [600, 900]},
		{"id": "late", "latest_s_window": [100, 5000], "when": {"type": "time_elapsed", "seconds": 99999}},
	]
	var by_seed := {}
	for seed in [2, 13, 31, 2]:
		_harness(_convoy(), WATCH, events, seed)
		var drawn: Dictionary = _director.variant.duplicate(true)
		for e: Dictionary in _director.events:
			assert_true(not e.has("at_s_window") and not e.has("variants"), "a resolved event carries its draws, not its options")
		assert_true(float(_director.event("raid")["at_s"]) >= 1200.0 and float(_director.event("raid")["at_s"]) <= 3000.0)
		assert_eq(str(_director.event("raid")["message"]), str(drawn["raid"]["variant"]), "the chosen variant is merged into the event")
		if by_seed.has(seed):
			assert_eq(drawn, by_seed[seed], "the same seed draws the same operation")
		by_seed[seed] = drawn
		_cleanup()
	assert_true(by_seed[2] != by_seed[13] and by_seed[13] != by_seed[31], "another seed draws another operation")


func test_triggers_follow_the_convoy_and_after_names_events() -> void:
	_harness(_convoy(), WATCH, [
		{"id": "midway", "when": {"type": "reach_area", "callsigns": ["Cargo"], "center_nm": [0, 10], "radius_nm": 3}, "message": "Cargo passed the midway mark"},
		{"id": "follow_up", "after": ["midway"], "at_s": 100, "message": "Follow-up"},
	])
	_director.tick(50.0)
	assert_true(_director.fired.is_empty(), "the convoy has not got there yet")
	_unit("Cargo").position = Vector2(0, 9)
	_director.tick(60.0)
	assert_eq(_director.fired.keys(), ["midway"])
	assert_eq(float(_director.fired["midway"]), 60.0, "the record keeps when it fired")
	_director.tick(99.0)
	assert_eq(_director.fired.keys(), ["midway"], "an event waits for its own time as well as its predecessor")
	_director.tick(100.0)
	assert_eq(_director.fired.keys(), ["midway", "follow_up"])
	assert_eq(_heard, ["Cargo passed the midway mark", "Follow-up"])
	_director.tick(200.0)
	assert_eq(_heard.size(), 2, "every event fires once")
	_cleanup()


func test_a_sides_own_plot_is_the_trigger_and_a_report_does_not_count() -> void:
	_harness(_convoy(), WATCH, [
		{"id": "spotted", "side": "RED", "when": {"type": "track_held", "faction": "RED", "callsigns": ["Cargo"], "min_classification": "SURFACE"},
			"ai": [{"units": ["Corvette"], "ai_posture": "breakout", "patrol_nm": [[0, 2]]}], "message": "RED: target located"},
	])
	var cargo := _unit("Cargo")
	var corvette := _unit("Corvette")
	# BLUE holding its own merchant, or a report on RED's plot, is not RED seeing her.
	_tm.observe("BLUE", corvette, corvette.position, 1.0, 1.0, 1.0, 600.0, 10.0)
	_tm.report_intel("RED", cargo, cargo.position + Vector2(3, 0), 8.0, 1.0, "Test")
	_director.tick(2.0)
	assert_true(_director.fired.is_empty(), "neither the other side's plot nor a contact report is detection")
	_tm.observe("RED", cargo, cargo.position, 1.0, 1.0, 3.0, 60.0, 30.0)
	_director.tick(3.0)
	assert_true(_director.fired.has("spotted"), "RED's own plot holding the merchant, classified")
	assert_eq(corvette.ai_posture, "breakout")
	assert_eq(corvette.patrol_route, [Vector2(0, 2)] as Array[Vector2])
	assert_eq(_heard, [], "the enemy's decision is never announced to the player")
	_cleanup()


func test_an_event_acts_only_on_its_own_sides_units_and_never_adds_an_airframe() -> void:
	var units := _convoy()
	units.append({"platform": "cw90_airfield", "callsign": "Field", "faction": "RED", "position_nm": [0, 80],
		"air_wing": [{"platform": "cw90_tu22m3", "count": 2, "callsign": "Backfire", "first_modex": 1, "ready_after_s": 3000}]})
	_harness(units, WATCH, [
		{"id": "order", "side": "RED", "at_s": 10, "ai": [{"units": ["Corvette", "Escort"], "patrol_nm": [[5, 5]]}],
			"ready": [{"host": "Field", "platform": "tu22", "count": 1, "ready_after_s": 300}]},
	])
	var escort_route := _unit("Escort").patrol_route.duplicate()
	var before := _um.units.size()
	_director.tick(10.0)
	assert_eq(_unit("Corvette").patrol_route, [Vector2(5, 5)] as Array[Vector2])
	assert_eq(_unit("Escort").patrol_route, escort_route, "a RED event cannot steer a BLUE ship")
	assert_eq(_unit("Backfire 1").state_timer_s, 300.0, "the first reserve airframe brought forward")
	assert_eq(_unit("Backfire 2").state_timer_s, 3000.0, "only as many as the order names")
	assert_eq(_um.units.size(), before, "readiness changes timing, never the inventory")
	assert_true(OperationDirector.event_problem({"units": units, "events": [{"id": "x", "side": "RED", "ai": [{"units": ["Escort"]}]}]}).contains("not one of the RED side's units"))
	_cleanup()


func test_a_contact_report_is_a_datum_never_a_firing_solution() -> void:
	_harness(_convoy(), WATCH, [
		{"id": "cue", "at_s": 30, "intel": [{"target": "Corvette", "error_nm": 12, "source": "Coastal radar station"}],
			"message": "Coastal radar reports a fast surface contact near {pos}, accuracy 12 nm."},
	])
	var corvette := _unit("Corvette")
	var escort := _unit("Escort")
	_director.tick(30.0)
	var t := _tm.find_track("BLUE", corvette)
	assert_true(t != null, "the report is on BLUE's plot")
	assert_true(t.reported and t.source == "intel")
	assert_eq(t.classification, Track.Classification.UNKNOWN, "nothing is classified from a report")
	assert_eq(t.identity, "UNKNOWN")
	assert_eq(t.domain, "")
	assert_eq(t.tma_quality, 0.0, "no range solution")
	assert_eq(t.last_firm_time, -1.0e9, "the firm-plot clock is not started")
	assert_true(not t.has_kinematics, "no velocity from a single report")
	assert_true(t.position != corvette.position and t.position.distance_to(corvette.position) <= 12.0, "reported within its stated error, not at truth")
	assert_eq(t.error_major_nm, 12.0)
	# What the plot lets anyone do with it: go and look, not shoot.
	assert_eq(UnitManager.attack_rejection(escort, t), "Identify contact first")
	var harpoon := escort.get_weapon("cw90_harpoon")
	assert_true(not Combat.check_engagement(escort, harpoon, t)["ok"], "no weapon can be laid on a report")
	assert_eq(UnitManager.investigation_rejection(escort, t), "", "a report is exactly what an investigation is for")
	assert_eq(DataDisplay.source_readout(t), "Contact report, Coastal radar station")
	# The message reads the reported position, in the chart's latitude and longitude.
	assert_eq(_heard.size(), 1)
	assert_true(_heard[0].contains(_director.chart_position(t.position)), _heard[0])
	assert_true(not _heard[0].contains(_director.chart_position(corvette.position)), "never the true position")
	# A second report on a contact the plot already holds changes nothing.
	assert_true(_tm.report_intel("BLUE", corvette, corvette.position, 1.0, 40.0, "Again") == null)
	# The side's own first look replaces the report outright.
	_tm.observe("BLUE", corvette, corvette.position, 1.0, 1.0, 50.0, 1.0, 20.0)
	assert_true(not t.reported)
	assert_eq(t.position, corvette.position, "snapped to the sensor, not blended with the report")
	assert_eq(t.source, "radar")
	_cleanup()


func test_tasking_changes_say_what_changed_and_a_bonus_never_blocks_the_win() -> void:
	_harness(_convoy(), {"victory": [
		{"id": "watch", "type": "time_elapsed", "seconds": 3600, "text": "Complete the watch"},
		{"id": "deliver", "type": "reach_area", "callsigns": ["Cargo"], "center_nm": [0, 20], "radius_nm": 3, "text": "Deliver the cargo"}], "loss": []}, [
		{"id": "retask", "at_s": 600, "message": "TASKING UPDATE: the handover moves north; the corvette is a bonus target.",
			"objectives": {"add": [{"id": "sink_corvette", "type": "all_units_lost", "callsigns": ["Corvette"], "optional": true, "text": "Sink the corvette"}],
				"update": {"deliver": {"center_nm": [0, 25], "text": "Deliver the cargo to the new box"}}, "briefing": "New orders."}},
	])
	var changed := [0]
	_mm.objectives_changed.connect(func() -> void: changed[0] += 1)
	_director.tick(600.0)
	assert_eq(changed[0], 1, "the screens are told the tasking changed")
	assert_eq(_mm.objective("deliver").center, Vector2(0, 25))
	assert_eq(_mm.objective("deliver").text, "Deliver the cargo to the new box")
	assert_true(_mm.objective("sink_corvette").optional)
	assert_eq(_mm.briefing, "New orders.")
	assert_eq(_mm.tasking_updates, [{"time_s": 600.0, "text": "TASKING UPDATE: the handover moves north; the corvette is a bonus target."}])
	_unit("Cargo").position = Vector2(0, 20)
	_mm.tick(3600.0)
	assert_eq(_mm.result, MissionManager.Result.RUNNING, "the old box no longer counts")
	_unit("Cargo").position = Vector2(0, 25)
	_mm.tick(3601.0)
	assert_eq(_mm.result, MissionManager.Result.VICTORY, "a bonus left undone never blocks the win")
	var a := _mm.assessment()
	assert_eq([a["bonus_done"], a["bonus_total"], a["bonus"]], [0, 1, 0.0])
	assert_eq(a["task"], MissionManager.TASK_WEIGHT, "the required tasks are the whole task")
	Damage.apply(_unit("Corvette"), 10000)
	_mm.objective("sink_corvette").evaluate(_um, 3602.0)
	a = _mm.assessment()
	assert_eq(a["bonus"], MissionManager.BONUS_WEIGHT, "and is credited when done")
	assert_true(MissionManager.assessment_text(a).contains("Bonus 10/10"))
	_cleanup()


func test_unless_cancels_latest_forces_and_expiry_ends_an_event() -> void:
	_harness(_convoy(), WATCH, [
		{"id": "report", "at_s": 100, "unless": {"type": "all_units_lost", "callsigns": ["Corvette"]}, "intel": [{"target": "Corvette"}], "message": "At {pos}"},
		{"id": "raid", "when": {"type": "track_held", "faction": "RED", "callsigns": ["Cargo"]}, "latest_s": 500},
		{"id": "window", "at_s": 0, "when": {"type": "time_elapsed", "seconds": 99999}, "expires_s": 300},
	])
	Damage.apply(_unit("Corvette"), 10000)
	_director.tick(100.0)
	assert_eq(_director.skipped.get("report", ""), "unless", "a report on a sunk ship is never made")
	_director.tick(499.0)
	assert_true(not _director.fired.has("raid"))
	assert_eq(_director.skipped.get("window", ""), "expired")
	_director.tick(500.0)
	assert_true(_director.fired.has("raid"), "the latest time fires it whatever the plot holds")
	assert_eq(_heard, [])
	_cleanup()


func test_authoring_checks_name_what_is_wrong() -> void:
	var units := _convoy()
	var cases := {
		"unknown unit": [{"id": "a", "intel": [{"target": "Nobody"}]}, "contact report needs a target"],
		"unknown prerequisite": [{"id": "a", "after": ["missing"]}, "waits on 'missing'"],
		"unknown trigger": [{"id": "a", "when": {"type": "moon_phase"}}, "unknown condition type"],
		"bad window": [{"id": "a", "at_s_window": [900, 600]}, "needs [earliest, latest]"],
		"duplicate id": [{"id": "watch"}, "used twice"],
		"position without report": [{"id": "a", "message": "At {pos}"}, "makes no report"],
		"other side's base": [{"id": "a", "side": "RED", "ready": [{"host": "Escort"}]}, "not one of the RED side's bases"],
	}
	for name: String in cases:
		var why := OperationDirector.event_problem({"units": units, "objectives": WATCH, "events": [cases[name][0]]})
		assert_true(why.contains(str(cases[name][1])), "%s: %s" % [name, why])
	assert_eq(OperationDirector.event_problem({"units": units, "objectives": WATCH, "events": [
		{"id": "a", "after": ["watch"], "when": {"type": "any", "of": [{"type": "track_held", "faction": "RED", "callsigns": ["Cargo"]}, {"type": "time_elapsed", "seconds": 60}]}},
		{"id": "b", "after": ["a"], "objectives": {"add": [{"id": "bonus", "type": "unit_lost", "callsigns": ["Corvette"], "optional": true}]}},
		{"id": "c", "after": ["bonus"]}]}), "")
