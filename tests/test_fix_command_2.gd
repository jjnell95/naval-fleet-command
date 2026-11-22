extends TestCase
## Orders, receipts, keys and what the crew tells the commander, played through the real command
## screen: what the radio line says after a hit, a salvo or a refusal, and which keys do what.

const SCENARIOS := "res://data/scenarios/"

var _save_root := ""
var _clock_speeds: Array[float] = []


func _boot(scenario: String, o: GameOptions = null, game_seed := 2) -> Main:
	_save_root = SaveGame.root_override
	_clock_speeds = SimClock.speeds()
	SaveGame.root_override = "user://test-command-two-%d" % Time.get_ticks_usec()
	var main: Main = preload("res://scenes/main/Main.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main._apply_options(o if o != null else GameOptions.normal(), false, false)
	main.simulation.seed_override = game_seed
	main.start_scenario(SCENARIOS + scenario)
	return main


## The operation with command taken and the clock paused at zero.
func _open(scenario: String, o: GameOptions = null, game_seed := 2) -> Main:
	var main := _boot(scenario, o, game_seed)
	main._on_briefing_start()
	SimClock.set_paused(true)
	return main


func _close(main: Main) -> void:
	main.free()
	var dir := DirAccess.open(SaveGame.root_override)
	if dir != null:
		for file in dir.get_files():
			dir.remove(file)
		DirAccess.remove_absolute(SaveGame.root_override)
	SaveGame.root_override = _save_root
	# The clock is shared with every other test file: hand it back as it was found.
	SimClock.set_speeds(_clock_speeds)
	SimClock.set_speed_index(0)
	SimClock.set_paused(true)


func _own(main: Main, part: String) -> Unit:
	for u: Unit in main.simulation.unit_manager.units:
		if u.faction == main.simulation.player_faction and u.callsign.contains(part):
			return u
	return null


func _key(main: Main, keycode: Key, shift := false, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.physical_keycode = keycode
	e.pressed = true
	e.shift_pressed = shift
	e.ctrl_pressed = ctrl
	main.get_viewport().push_input(e)
	var up := e.duplicate() as InputEventKey
	up.pressed = false
	main.get_viewport().push_input(up)


## Radio journal lines (crew traffic) holding every one of the given fragments.
func _journal(main: Main, fragments: Array) -> Array:
	var out := []
	for line: String in main.radio.journal:
		if fragments.all(func(f: String) -> bool: return line.contains(f)):
			out.append(line)
	return out


## The first contact of another side the player's plot holds, with its unit, after a short watch.
func _held_contact(main: Main, neutral: bool) -> Track:
	var sim := main.simulation
	for step in 40:
		for u: Unit in sim.unit_manager.units:
			if not u.alive or u.faction == sim.player_faction or u.is_aircraft():
				continue
			if sim.track_manager.neutral_factions.has(u.faction) != neutral:
				continue
			var t := main._held_track(u)
			if t != null and not t.is_bearing_only():
				return t
		SimClock.advance(5.0)
	return null


# --- A hit on a contact the plot holds as neutral or friendly --------------------------------

func test_a_hit_on_a_track_held_neutral_is_an_alert_and_never_a_good_hit() -> void:
	var main := _open("northern_passage.json")
	var sim := main.simulation
	var t := _held_contact(main, true)
	assert_true(t != null, "the plot holds a neutral ship")
	if t == null:
		_close(main)
		return
	t.identity = "NEUTRAL"
	var spec: WeaponSpec = main.map.selected[0].weapons[0]
	var before := main.radio.journal.size()
	sim.weapon_manager.weapon_impact.emit(sim.player_faction, spec, t.truth, true)
	var lines: Array = main.radio.journal.slice(before)
	assert_eq(lines.size(), 1, "one line for the hit: %s" % str(lines))
	assert_true(str(lines[0]).contains("Hit on neutral"), "it says a neutral was hit: %s" % str(lines))
	assert_true(str(lines[0]).contains(t.label()), "and names her as the plot does")
	assert_eq(str(main.map._radio.entries[-1]["severity"]), "alert", "as an alert, not a good hit")
	# The same hit on a contact held hostile is still the good line.
	var h := _held_contact(main, false)
	assert_true(h != null, "the plot holds a contact of the other side")
	if h != null:
		before = main.radio.journal.size()
		sim.weapon_manager.weapon_impact.emit(sim.player_faction, spec, h.truth, true)
		assert_true(str(main.radio.journal[-1]).ends_with("Hit"), "a hit on any other contact reads as before: %s" % str(main.radio.journal.slice(before)))
		assert_eq(str(main.map._radio.entries[-1]["severity"]), "good")
	_close(main)


# --- The pre-mission briefing has one way into the mission ------------------------------------

func test_escape_or_f1_on_the_first_briefing_returns_to_the_desk() -> void:
	for keycode: Key in [KEY_ESCAPE, KEY_F1]:
		var main := _boot("northern_passage.json")
		main._show_briefing()
		assert_true(main._briefing.visible and not main._command_taken, "the pre-mission briefing is up")
		_key(main, keycode)
		assert_true(not main._briefing.visible, "the briefing closed")
		assert_true(main._menu.visible, "to the operations desk, not to the chart")
		assert_true(not main._command_taken, "command was not taken")
		_key(main, KEY_SPACE)
		assert_true(SimClock.paused, "Space cannot run a mission nobody took command of")
		assert_eq(SimClock.sim_time, 0.0)
		assert_true(main.save_refusal() != "", "and there is nothing to save")
		_close(main)


func test_the_in_mission_briefing_still_closes_to_the_chart() -> void:
	var main := _open("northern_passage.json")
	_key(main, KEY_F1)
	assert_true(main._briefing.visible, "F1 opens the orders board in the mission")
	_key(main, KEY_ESCAPE)
	assert_true(not main._briefing.visible)
	assert_true(not main._menu.visible, "Esc closes it to the chart")
	assert_true(main._command_taken)
	_close(main)


# --- The debrief stays up until it is closed, and can be opened again --------------------------

func test_space_does_not_dismiss_the_debrief_and_it_reopens() -> void:
	var main := _open("northern_passage.json")
	SimClock.advance(20.0)
	main.simulation.mission_manager._finish(MissionManager.Result.DEFEAT, "The convoy was lost")
	assert_true(main._report.visible, "the debrief is up")
	# The report focuses its first button a frame later; give it the focus it will have.
	main._report._review.grab_focus()
	_key(main, KEY_SPACE)
	assert_true(main._report.visible, "Space leaves the debrief on screen")
	_key(main, KEY_ESCAPE)
	assert_true(not main._report.visible, "Esc closes it to review the picture")
	_key(main, KEY_F1)
	assert_true(main._report.visible, "F1 brings the debrief back once the mission has ended")
	assert_true(main._report._body.text.contains("The convoy was lost") or main._report._body.text.length() > 100, "with the report it closed with")
	_key(main, KEY_F1)
	assert_true(not main._report.visible, "and F1 closes it again")
	var entry := {}
	for it: Dictionary in CdsMenus.cds_items(main._cds_state()):
		if str(it.get("text", "")) == "Debrief":
			entry = it
	assert_true(not entry.is_empty() and not bool(entry["disabled"]), "the chart menu offers the debrief")
	main._run_cds_action(entry["action"])
	assert_true(main._report.visible, "and opens it")
	main.restart_scenario()
	assert_true(not main._report.visible)
	for it: Dictionary in CdsMenus.cds_items(main._cds_state()):
		if str(it.get("text", "")) == "Debrief":
			assert_true(bool(it["disabled"]), "a fresh mission has no debrief to show")
	_close(main)
