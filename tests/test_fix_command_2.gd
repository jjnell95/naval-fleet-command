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
	main.start_scenario(scenario if scenario.contains("://") else SCENARIOS + scenario)
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


# --- Manual missile defence: X and the cue ----------------------------------------------------

## Classic rules in the Strait until the commander holds inbound missiles, once the shore battery
## has come out of its hides. Returns them.
func _classic_raid(main: Main) -> Array:
	for step in 340:
		SimClock.advance(5.0)
		var held: Array = main._commander_inbound().filter(func(e: Dictionary) -> bool: return not (e["weapon"] as Weapon).spec.is_torpedo())
		if held.size() >= 2:
			return held
	return []


func _cleared(w: Weapon) -> bool:
	return not w.intercept_cleared.is_empty()


func test_classic_x_with_nothing_hooked_orders_the_force_to_engage() -> void:
	var main := _open("gulf_01_hormuz.json", GameOptions.classic())
	var held := _classic_raid(main)
	assert_true(held.size() >= 2, "the raid is held (%d rounds)" % held.size())
	assert_true(held.all(func(e: Dictionary) -> bool: return not _cleared(e["weapon"])), "manual defence: no SAM is cleared before the order")
	var sams_before := int(main._stats["launched"])
	main._process(1.0)
	assert_true(main.data_display.threat_text.contains("X ENGAGES %d UNCLEARED" % held.size()), "the banner says X engages, and how many wait: %s" % main.data_display.threat_text)
	main.map.clear_selection()
	_key(main, KEY_X)
	assert_true(main.radio.last_advice != "Select a controllable platform first", "the order is not refused for want of a hook")
	assert_true(held.any(func(e: Dictionary) -> bool: return _cleared(e["weapon"])), "the force's ships are cleared on the rounds they hold")
	assert_true(_journal(main, ["Force engaging inbound weapons"]).size() == 1, "one receipt for the force: %s" % main.radio.latest_text)
	SimClock.advance(10.0)
	assert_true(int(main._stats["launched"]) > sams_before, "and interceptors are away (%d)" % (int(main._stats["launched"]) - sams_before))
	_close(main)


func test_classic_x_with_a_helicopter_or_a_contact_hooked_still_reaches_the_force() -> void:
	var main := _open("gulf_01_hormuz.json", GameOptions.classic())
	var held := _classic_raid(main)
	assert_true(held.size() >= 2)
	var bystander: Unit = null
	for u: Unit in main.simulation.unit_manager.get_faction_units(main.simulation.player_faction):
		if u.is_engageable() and not CdsMenus.carries_interceptors(u):
			bystander = u
			break
	assert_true(bystander != null, "the force has a unit with no anti-missile weapons (the tanker)")
	main.map.select_units([bystander])
	_key(main, KEY_X)
	assert_true(held.any(func(e: Dictionary) -> bool: return _cleared(e["weapon"])), "X with %s hooked goes to the ships that can engage" % bystander.callsign)
	_close(main)


func test_a_hooked_ship_that_refuses_the_intercept_still_says_why() -> void:
	var main := _open("gulf_01_hormuz.json", GameOptions.classic())
	var held := _classic_raid(main)
	assert_true(held.size() >= 2)
	var ship: Unit = null
	for u: Unit in main.simulation.unit_manager.get_faction_units(main.simulation.player_faction):
		if CdsMenus.carries_interceptors(u):
			ship = u
			break
	ship.roe = Unit.Roe.HOLD
	main.map.select_units([ship])
	_key(main, KEY_X)
	assert_eq(main.radio.last_advice, "Cannot intercept: weapons hold", "a hooked missile-defence ship keeps her own answer")
	assert_true(held.all(func(e: Dictionary) -> bool: return not _cleared(e["weapon"])), "and nobody else fires for her")
	_close(main)


func test_the_x_cue_counts_every_uncleared_round_not_only_the_first() -> void:
	var main := _open("gulf_01_hormuz.json", GameOptions.classic())
	var held := _classic_raid(main)
	assert_true(held.size() >= 2)
	var ship: Unit = null
	for u: Unit in main.simulation.unit_manager.get_faction_units(main.simulation.player_faction):
		if AirDefence.intercept_rejection(u) == "":
			ship = u
			break
	# The most urgent round was cleared by an earlier order; the ones behind it were not.
	var first: Weapon = main._commander_inbound()[0]["weapon"]
	first.intercept_cleared.append(ship.id)
	main._process(1.0)
	var waiting: int = main._commander_inbound().filter(func(e: Dictionary) -> bool: return not (e["weapon"] as Weapon).spec.is_torpedo() and not _cleared(e["weapon"])).size()
	assert_true(waiting >= 1)
	assert_true(main.data_display.threat_text.contains("X ENGAGES %d UNCLEARED" % waiting), "the cue stays for the %d rounds still waiting: %s" % [waiting, main.data_display.threat_text])
	for e: Dictionary in main._commander_inbound():
		if not (e["weapon"] as Weapon).intercept_cleared.has(ship.id):
			(e["weapon"] as Weapon).intercept_cleared.append(ship.id)
	main._process(1.0)
	assert_true(not main.data_display.threat_text.contains("X ENGAGES"), "and goes once every held round is cleared: %s" % main.data_display.threat_text)
	_close(main)


# --- The contact menu: names as held, and Identify for anything of unknown allegiance ----------

func _menu_texts(items: Array) -> Array:
	return items.map(func(it: Dictionary) -> String: return str(it.get("text", "")))


func test_the_contact_menu_shows_a_class_name_as_the_plot_holds_it() -> void:
	var t := Track.new()
	t.id = "T1001"
	t.owner_faction = "BLUE"
	t.domain = "air"
	t.classification = Track.Classification.CLASS_KNOWN
	for name: String in ["Tu-22M3", "MV Merchant", "FFG Gorshkov"]:
		t.known_class = name
		var title := str(CdsMenus.engage_items([], t, false)[0]["text"])
		assert_true(title.ends_with("  " + name), "the header reads %s, not a re-capitalised name: %s" % [name, title])
	t.classification = Track.Classification.SURFACE
	assert_true(str(CdsMenus.engage_items([], t, false)[0]["text"]).ends_with("Air Contact"), "an unclassified contact keeps its plain wording")


func test_the_contact_menu_offers_identify_on_a_classified_contact_of_unknown_allegiance() -> void:
	var main := _open("northern_passage.json")
	var sim := main.simulation
	var t := _held_contact(main, true)
	assert_true(t != null)
	var ship: Unit = main.map.selected[0]
	# What an emitter or a hull form gives: a class, and no allegiance yet.
	t.classification = Track.Classification.CLASS_KNOWN
	t.known_class = "MV Merchant"
	t.identity = "UNKNOWN"
	var items := CdsMenus.engage_items([ship], t, true, sim.weapon_manager)
	var texts := _menu_texts(items)
	assert_true(texts.has("Identify contact"), "an unknown merchant offers Identify: %s" % str(texts))
	var identify: Dictionary = items[texts.find("Identify contact")]
	assert_true(not bool(identify["disabled"]), "and the hooked ship can take it: %s" % str(identify.get("tooltip", "")))
	assert_true(texts.find("Identify contact") < texts.find("Attack track %s" % DataDisplay.track_number_for_track(t)), "ahead of the attack verbs")
	main._run_cds_action(identify["action"])
	assert_eq(ship.investigation_track, t, "choosing it sends the ship to look")
	t.identity = "NEUTRAL"
	assert_true(not _menu_texts(CdsMenus.engage_items([ship], t, true, sim.weapon_manager)).has("Identify contact"), "an identified contact no longer offers it")
	_close(main)


# --- Salvos: the receipt, the clock and how the rounds ended ----------------------------------

const RANGE := {"id": "command_two_range", "name": "Firing Range", "player_faction": "BLUE", "environment": {"sea_state": 3}, "map": {"center_nm": [0, 0], "extent_nm": 80},
	"objectives": {"text": "Range practice", "victory": [{"id": "hold", "type": "time_elapsed", "seconds": 60000}], "loss": []}, "units": [
	{"platform": "usn_cg_ticonderoga", "callsign": "USS Range Cruiser", "faction": "BLUE", "position_nm": [0, 0], "speed_kn": 0},
	{"platform": "usn_ddg_burke_iii", "callsign": "USS Range Destroyer", "faction": "BLUE", "position_nm": [-3, -2], "speed_kn": 0},
	{"platform": "cw90_sovremenny", "callsign": "Range Target", "faction": "RED", "position_nm": [0, 10], "speed_kn": 0}]}
const MISSILE := "tomahawk_block_v"


## Two own ships and one held hostile ten miles off, nobody shooting back: {main, own, enemy, track}.
## `bystander` puts a merchant of a neutral flag beside the target.
func _range(bystander := false) -> Dictionary:
	var path := "user://test-command-two-range.json"
	var scenario: Dictionary = RANGE.duplicate(true)
	if bystander:
		scenario["neutral_factions"] = ["NEUTRAL"]
		scenario["units"].append({"platform": "civ_merchant_bulk", "callsign": "MV Bystander", "faction": "NEUTRAL", "position_nm": [7, 9], "speed_kn": 0})
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(scenario))
	file.close()
	var main := _open(path)
	var sim := main.simulation
	sim.ai_enabled = false
	var own: Array = sim.unit_manager.get_engageable_units("BLUE")
	var enemy: Unit = sim.unit_manager.get_engageable_units("RED")[0]
	sim.track_manager.observe("BLUE", enemy, enemy.position, 1, 1, SimClock.sim_time, 1, 10)
	var track := sim.track_manager.find_track("BLUE", enemy)
	track.identity = "HOSTILE"
	track.domain = "surface"
	main.map.select_units([own[0]])
	main.map.select_track(track)
	return {"main": main, "own": own, "enemy": enemy, "track": track}


func _own_rounds(main: Main) -> Array:
	return main.simulation.weapon_manager.in_flight.filter(func(w: Weapon) -> bool:
		return w.faction == main.simulation.player_faction and not w.is_interceptor() and w.phase != Weapon.Phase.DEAD)


func test_a_salvo_receipt_counts_each_round_once() -> void:
	var f := _range()
	var main: Main = f["main"]
	var ship: Unit = f["own"][0]
	var number := DataDisplay.track_number_for_track(f["track"])
	main._apply_order_to_selection(Order.engage(f["track"], MISSILE, 4))
	var away := _own_rounds(main).size()
	var waiting := main.simulation.weapon_manager.committed_rounds(ship, DataDB.weapon(MISSILE), f["track"], true)
	assert_eq(away + waiting, 4, "four rounds in all: %d away, %d on the launcher" % [away, waiting])
	assert_true(waiting > 0, "a salvo of four leaves rounds waiting on the launcher")
	var name := DataDB.weapon(MISSILE).compact_name()
	var lines := _journal(main, ["4 × %s at track %s: %d away, %d on the launcher" % [name, number, away, waiting]])
	assert_eq(lines.size(), 1, "the receipt says so once: %s" % str(main.radio.journal))
	for line: String in main.radio.journal:
		assert_true(not line.contains("; %d queued" % waiting), "and never as rounds on top of the salvo: %s" % line)
	main._apply_order_to_selection(Order.engage(f["track"], "mk45_mod4_gun", 1))
	assert_eq(_journal(main, ["1 × ", " away at track %s" % number]).size(), 1, "a single round is simply away: %s" % str(main.radio.journal.slice(-2)))
	_close(main)


func test_own_salvos_in_one_engagement_drop_time_compression_once() -> void:
	var f := _range()
	var main: Main = f["main"]
	var fast := SimClock.speeds().size() - 1
	var drops: Array[int] = [0]
	var count := func(index: int, _m: float) -> void:
		if index == 0:
			drops[0] += 1
	SimClock.speed_changed.connect(count)
	SimClock.set_speed_index(fast)
	main._apply_order_to_selection(Order.engage(f["track"], "mk45_mod4_gun", 2))
	assert_eq(drops[0], 1, "the first salvo of the engagement hands the watch back at real time")
	SimClock.set_speed_index(fast)
	SimClock.advance(20.0)
	main._apply_order_to_selection(Order.engage(f["track"], "mk45_mod4_gun", 2))
	assert_eq(drops[0], 1, "the next salvo at the same contact leaves the time scale alone")
	assert_eq(SimClock.speed_index, fast)
	main.simulation.weapon_manager.weapon_impact.emit(main.simulation.player_faction, DataDB.weapon("mk45_mod4_gun"), f["enemy"], true)
	assert_eq(drops[0], 1, "and so does a hit scored in the same engagement")
	# What is done to the commander's own ships still stops the clock every time.
	main.simulation.weapon_manager.weapon_impact.emit("RED", DataDB.weapon("mk45_mod4_gun"), f["own"][1], true)
	assert_eq(drops[0], 2, "a hit taken drops to real time")
	SimClock.speed_changed.disconnect(count)
	_close(main)


func test_a_salvo_shot_down_is_reported_in_one_line() -> void:
	var f := _range()
	var main: Main = f["main"]
	var wm := main.simulation.weapon_manager
	main._apply_order_to_selection(Order.engage(f["track"], MISSILE, 3))
	for step in 60:
		if _own_rounds(main).size() >= 3:
			break
		SimClock.advance(1.0)
	var rounds := _own_rounds(main)
	assert_eq(rounds.size(), 3, "three rounds are in the air")
	var before := main.radio.journal.size()
	for w: Weapon in rounds:
		wm.defeat_weapon(w, "INTERCEPTED", f["enemy"])
	SimClock.advance(6.0)
	var said: Array = main.radio.journal.slice(before)
	var number := DataDisplay.track_number_for_track(f["track"])
	assert_eq(said.size(), 1, "one line for the salvo: %s" % str(said))
	assert_true(not said.is_empty() and str(said[0]).ends_with("3 × %s at track %s shot down" % [DataDB.weapon(MISSILE).compact_name(), number]), "saying all three were shot down: %s" % str(said))
	_close(main)


func test_one_round_shot_down_and_a_mixed_salvo_read_plainly() -> void:
	assert_eq(Main.round_report_line({"name": "Harpoon", "at": "track 1002", "outcomes": {"shot down": 1}}), "Harpoon at track 1002 shot down")
	assert_eq(Main.round_report_line({"name": "Harpoon", "at": "track 1002", "outcomes": {"shot down": 3, "missed": 1}}), "4 × Harpoon at track 1002: 3 shot down, 1 missed")


func test_a_miss_the_plot_can_see_is_reported() -> void:
	var f := _range()
	var main: Main = f["main"]
	main._apply_order_to_selection(Order.engage(f["track"], MISSILE, 1))
	var rounds := _own_rounds(main)
	assert_eq(rounds.size(), 1)
	var before := main.radio.journal.size()
	var w: Weapon = rounds[0]
	w.acquired = f["enemy"]
	w.phase = Weapon.Phase.DEAD
	w.dead_reason = "MISS"
	SimClock.advance(6.0)
	var said: Array = main.radio.journal.slice(before)
	assert_true(said.size() == 1 and str(said[0]).ends_with("at track %s missed" % DataDisplay.track_number_for_track(f["track"])), "the miss is said: %s" % str(said))
	_close(main)


func test_cancelled_queued_rounds_fold_into_one_line() -> void:
	var f := _range()
	var main: Main = f["main"]
	var ship: Unit = f["own"][0]
	var spec := DataDB.weapon(MISSILE)
	var before := main.radio.journal.size()
	for i in 5:
		main.simulation.weapon_manager.engagement_rejected.emit(ship, spec, "QUEUED ROUND CANCELLED: OUT OF RANGE")
	SimClock.advance(2.0)
	var said: Array = main.radio.journal.slice(before)
	assert_eq(said.size(), 1, "five cancellations, one line: %s" % str(said))
	assert_true(not said.is_empty() and str(said[0]).contains("5 QUEUED ROUNDS CANCELLED: OUT OF RANGE"), str(said))
	_close(main)


func test_the_boot_banner_names_a_version_and_no_milestone() -> void:
	assert_true(Main.VERSION.is_valid_float() or Main.VERSION.split(".").size() >= 2, "a plain version: %s" % Main.VERSION)
	assert_true(not Main.VERSION.contains("M3") and not Main.VERSION.contains("/"), Main.VERSION)


func test_the_firing_board_keeps_the_running_groups_budget_and_says_each_count_once() -> void:
	var f := _range()
	var main: Main = f["main"]
	main.map.select_units(f["own"])
	main._toggle_weapon_control()
	var board := main._weapon_control
	assert_true(board.visible and board._group_row.visible, "the board is open with the group row")
	var suggested := int(board._budget.value)
	board._budget.value = suggested + 3
	board._group_commit.pressed.emit()
	var groups: Array = main.simulation.group_attack_manager.active_groups("BLUE")
	assert_eq(groups.size(), 1, "the group attack is running: %s" % board._receipt.text)
	if groups.size() == 1:
		var g: GroupAttack = groups[0]
		assert_eq(g.budget, suggested + 3)
		board.refresh()
		assert_eq(int(board._budget.value), g.budget, "the budget box stays on the running group's budget")
		var line := board._group_status.text
		assert_true(line.contains("budget %d" % g.budget), line)
		for word: String in ["queued", "away"]:
			assert_true(not line.contains(word), "the counts are not repeated in words (%s): %s" % [word, line])
		for word: String in ["fired ", "on the launcher", "in flight"]:
			assert_eq(line.count(word), 1, "%s once: %s" % [word, line])
	main._close_weapon_control()
	_close(main)


# --- A group order that only some platforms take says who refused and why -----------------------

func test_a_partly_refused_group_order_names_who_refused_and_why() -> void:
	var f := _range()
	var main: Main = f["main"]
	var taker: Unit = f["own"][0]
	var refuser: Unit = f["own"][1]
	main.map.select_units([taker, refuser])
	# The standing attack: one ship is on weapons hold.
	refuser.roe = Unit.Roe.HOLD
	var why := UnitManager.attack_rejection(refuser, f["track"])
	assert_true(why != "" and UnitManager.attack_rejection(taker, f["track"]) == "", "one ship can attack, the other cannot (%s)" % why)
	main._apply_order_to_selection(Order.attack(f["track"]))
	var line := main.radio.latest_text
	assert_true(line.contains("1 order accepted / 1 refused"), line)
	assert_true(line.contains("%s: %s" % [refuser.callsign, why.to_lower()]), "the receipt names the ship and its reason: %s" % line)
	# A defence order: one ship has no chaff left.
	refuser.roe = Unit.Roe.FREE
	refuser.decoys = 0
	main._apply_order_to_selection(Order.deploy_countermeasures("radar"))
	assert_eq(_journal(main, ["1 refused", refuser.callsign + ": no chaff or flare countermeasures aboard"]).size(), 1, "every order type gives its reason: %s" % str(main.radio.journal.slice(-2)))
	# A sensor order, through the per-platform route the boards use.
	main._apply_unit_orders([[taker, Order.set_altitude(500.0)], [refuser, Order.set_roe(Unit.Roe.TIGHT)]])
	line = main.radio.latest_text
	assert_true(line.contains("1 refused") and line.contains(taker.callsign + ": not airborne"), "and so does a board's order: %s" % line)
	_close(main)


# --- Chaff with nothing to work on ------------------------------------------------------------

func _inbound(main: Main, at: Unit, distance_nm: float) -> Weapon:
	var w := Weapon.new()
	w.id = 99001
	w.spec = DataDB.weapon("cw90_harpoon")
	w.faction = "RED"
	w.position = at.position + Vector2(0, distance_nm)
	w.heading_deg = 180
	w.acquired = at
	w.phase = Weapon.Phase.TERMINAL
	main.simulation.weapon_manager.in_flight.append(w)
	main.simulation.threat_manager.mark_detected("BLUE", w, 0, at)
	return w


func test_chaff_ordered_with_no_seeker_in_reach_says_so() -> void:
	var f := _range()
	var main: Main = f["main"]
	var ship: Unit = f["own"][0]
	var packs := ship.decoys
	var w := _inbound(main, ship, 15.0)
	assert_eq(w.spec.seeker_band(), "radar")
	var before := main.radio.journal.size()
	_key(main, KEY_D)
	assert_eq(ship.decoys, packs - 1, "the order is kept: a pack is fired")
	var said: Array = main.radio.journal.slice(before)
	assert_true(said.any(func(line: String) -> bool: return line.contains("Chaff away with no radar seeker inside 2.5 nm") and line.contains("15.0 nm")), "and the radio says it has nothing to work on: %s" % str(said))
	# With the seeker inside the reach of chaff there is nothing to add.
	ship.countermeasure_reload_s = 0.0
	w.position = ship.position + Vector2(0, 2.0)
	before = main.radio.journal.size()
	_key(main, KEY_D)
	assert_eq(ship.decoys, packs - 2)
	assert_true(not main.radio.journal.slice(before).any(func(line: String) -> bool: return line.contains("away with no")), "chaff against a seeker in reach draws no warning: %s" % str(main.radio.journal.slice(before)))
	_close(main)


# --- The data display: what produced the plot, and its own right-click menu ---------------------

func _plot(domain: String, source: String, sensor: String, sensor_id := "") -> Track:
	var t := Track.new()
	t.id = "T1003"
	t.owner_faction = "BLUE"
	t.domain = domain
	t.source = source
	t.source_platform = "FFG Perry"
	t.source_sensor = sensor
	t.source_sensor_id = sensor_id
	t.classification = Track.Classification.CLASS_KNOWN
	t.known_class = "Nanuchka"
	return t


func test_the_source_line_does_not_credit_a_ship_plot_to_an_air_search_set() -> void:
	var ship := _plot("surface", "radar", "AN/SPS-49 air-search radar")
	assert_eq(DataDisplay.source_readout(ship), "FFG Perry radar", "a surface plot is the ship's radar, not her air-search set")
	assert_eq(DataDisplay.source_readout(_plot("air", "radar", "AN/SPS-49 air-search radar")), "FFG Perry SPS-49 air-search radar", "an air plot still names it")
	assert_eq(DataDisplay.source_readout(_plot("surface", "radar", "AWS-1 air and surface search radar")), "FFG Perry AWS-1 air and surface search radar", "a set named for both fits both")
	assert_eq(DataDisplay.source_readout(_plot("air", "radar", "Navigation and surface-search radar")), "FFG Perry radar")
	assert_eq(DataDisplay.source_readout(_plot("surface", "visual", "Visual recognition", "lookout")), "FFG Perry lookouts", "a sighting is the lookouts'")


func test_class_evidence_of_a_sighted_contact_is_the_sighting() -> void:
	var t := _plot("surface", "visual", "Visual recognition", "lookout")
	t.identity = "HOSTILE"
	t.identity_evidence = "Visual markings"
	# What a hold on sonar writes over a contact already recognised by eye.
	t.class_evidence = "Acoustic library match"
	var text := DataDisplay.rows_text(DataDisplay.track_rows(t, null, 0.0))
	assert_true(text.contains("CLASS EVIDENCE: Visual recognition"), "seen is seen: %s" % text)
	assert_true(not text.contains("Acoustic library match"), text)
	t.identity_evidence = "Scenario recognition brief"
	assert_true(DataDisplay.rows_text(DataDisplay.track_rows(t, null, 0.0)).contains("CLASS EVIDENCE: Acoustic library match"), "a contact never seen keeps the library's word")


func _right_click(control: Control, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = true
	e.position = at
	control._gui_input(e)


func test_a_right_click_on_the_data_display_opens_the_hooked_platforms_menu() -> void:
	var f := _range()
	var main: Main = f["main"]
	var ship: Unit = f["own"][0]
	main.map.select_track(null)
	main.map.select_units([ship])
	var at := Vector2(180.0, 90.0)
	_right_click(main.data_display, at)
	var menu := main._cds_menus._root
	assert_true(menu != null and is_instance_valid(menu), "a menu opens")
	if menu != null:
		var texts := []
		for i in menu.item_count:
			texts.append(menu.get_item_text(i))
		assert_true(texts.has("Navigation") and texts.has("Weapons state"), "it is the hooked platform's orders menu: %s" % str(texts))
	main._cds_menus.close()
	# With a contact being inspected the read-out is the contact's, and so is the menu.
	main.map.select_track(f["track"])
	assert_eq(main.map.inspection_track(), f["track"])
	_right_click(main.data_display, at)
	menu = main._cds_menus._root
	assert_true(menu != null and menu.get_item_text(0).begins_with("Track %s" % DataDisplay.track_number_for_track(f["track"])), "the contact's menu for an inspected contact: %s" % (menu.get_item_text(0) if menu != null else "no menu"))
	main._cds_menus.close()
	_close(main)


# --- The chart's filters are reachable ---------------------------------------------------------

func _find_item(items: Array, text: String) -> Dictionary:
	for it: Dictionary in items:
		if str(it.get("text", "")) == text:
			return it
	return {}


func test_the_chart_menu_has_filters_that_hide_and_show_contacts() -> void:
	var f := _range()
	var main: Main = f["main"]
	var track: Track = f["track"]
	main.map.select_track(null)
	assert_true(main.map._plotted_tracks().has(track), "the hostile is on the chart")
	for menu: Array in [CdsMenus.cds_items(main._cds_state()), CommandBar.chart_items(main.map)]:
		var filters := _find_item(menu, "Filters")
		assert_true(not filters.is_empty() and not bool(filters["disabled"]), "the menu has a Filters submenu")
		var hostile := _find_item(filters.get("children", []), "Hostile contacts")
		assert_true(not hostile.is_empty() and int(hostile["checked"]) == 1, "hostile contacts are checked while shown")
		main._run_cds_action(hostile["action"])
		assert_true(not main.map._plotted_tracks().has(track), "unchecking it takes the hostile off the chart")
		assert_true(main.radio.last_advice.contains("hostile contacts hidden"), "and the radio line says so: %s" % main.radio.last_advice)
		assert_true(main.simulation.track_manager.get_tracks("BLUE").has(track), "the contact is still held")
		var again := _find_item(_find_item(CdsMenus.cds_items(main._cds_state()), "Filters")["children"], "Hostile contacts")
		assert_eq(int(again["checked"]), 0, "the check mark follows")
		main._run_cds_action(again["action"])
		assert_true(main.map._plotted_tracks().has(track), "checking it again brings her back")
	var children: Array = _find_item(CdsMenus.cds_items(main._cds_state()), "Filters")["children"]
	for text: String in ["Neutral contacts", "Unknown contacts", "Routes and waypoints", "Range grid"]:
		var it := _find_item(children, text)
		assert_true(not it.is_empty(), "%s is offered" % text)
		var layer := str(it["action"]["name"])
		var was := main.map.has_layer(layer)
		main._run_cds_action(it["action"])
		assert_eq(main.map.has_layer(layer), not was, "%s toggles its layer" % text)
		main._run_cds_action(it["action"])
	_close(main)


# --- Hotkeys leave a text field and a dialog alone ----------------------------------------------

func test_command_chords_do_not_fire_while_a_text_field_has_focus() -> void:
	var main := _open("northern_passage.json")
	main.status_boards.open_board(StatusBoards.BOARD_TASK_GROUP)
	var field: LineEdit = main.unit_panel._roster_search
	field.grab_focus()
	assert_eq(main.get_viewport().gui_get_focus_owner(), field, "the roster search has the keyboard")
	var scale := main.map.has_layer("scale")
	var latlon := main.map.has_layer("latlon")
	var sound: bool = SoundFx.enabled
	_key(main, KEY_S, false, true)
	_key(main, KEY_L, false, true)
	_key(main, KEY_M, false, true)
	_key(main, KEY_1, false, true)
	_key(main, KEY_E, false, true)
	assert_eq(main.map.has_layer("scale"), scale, "Ctrl+S in a text field does not toggle the scale bar")
	assert_eq(main.map.has_layer("latlon"), latlon, "nor Ctrl+L the lat-long readout")
	assert_eq(SoundFx.enabled, sound, "nor Ctrl+M the sound")
	assert_true(main._control_groups.is_empty(), "nor Ctrl+1 store a selection group")
	assert_true(not main._editor.visible, "nor Ctrl+E open the editor")
	# The field takes the first Escape to leave its own editing; the next is the board's.
	_key(main, KEY_ESCAPE)
	_key(main, KEY_ESCAPE)
	assert_true(not main.status_boards.visible, "Escape still closes the board")
	# With the chart focused the same chords are commands again.
	main.map.grab_focus()
	_key(main, KEY_S, false, true)
	assert_eq(main.map.has_layer("scale"), not scale, "Ctrl+S toggles the scale bar from the chart")
	_close(main)


func test_hotkeys_do_not_reach_the_mission_behind_the_readout_dialog() -> void:
	var main := _open("northern_passage.json")
	main.data_display.open_details()
	assert_true(main.data_display._details.visible, "the read-out dialog is open")
	var speed := SimClock.speed_index
	_key(main, KEY_M)
	_key(main, KEY_3)
	_key(main, KEY_F1)
	assert_true(not main._menu.visible and not main._briefing.visible, "M and F1 do not open screens behind the dialog")
	assert_eq(SimClock.speed_index, speed, "and the time scale is left alone")
	main.data_display.close_details()
	_close(main)


# --- A round that takes a ship it was not fired at ---------------------------------------------

func test_an_own_round_that_hits_an_unidentified_ship_it_was_not_fired_at_is_an_alert() -> void:
	var f := _range(true)
	var main: Main = f["main"]
	var sim := main.simulation
	var merchant: Unit = sim.unit_manager.get_engageable_units("NEUTRAL")[0]
	sim.track_manager.observe("BLUE", merchant, merchant.position, 1, 1, SimClock.sim_time, 1, 10)
	var bystander := sim.track_manager.find_track("BLUE", merchant)
	# A class from her radar and no allegiance yet: the plot does not hold her as neutral.
	bystander.identity = "UNKNOWN"
	bystander.classification = Track.Classification.CLASS_KNOWN
	bystander.known_class = "MV Merchant"
	main._apply_order_to_selection(Order.engage(f["track"], MISSILE, 1))
	var rounds := _own_rounds(main)
	assert_eq(rounds.size(), 1, "one round is away at the hostile")
	var w: Weapon = rounds[0]
	# Its seeker takes the merchant instead.
	w.acquired = merchant
	w.phase = Weapon.Phase.DEAD
	w.dead_reason = "HIT"
	var fast := SimClock.speeds().size() - 1
	SimClock.set_speed_index(fast)
	sim.weapon_manager.weapon_impact.emit(sim.player_faction, w.spec, merchant, true)
	var line := str(main.radio.journal[-1])
	assert_true(line.contains("Hit on %s" % bystander.label()) and line.contains("not the contact fired at"), "the radio says the round took another ship: %s" % line)
	assert_eq(str(main.map._radio.entries[-1]["severity"]), "alert", "as an alert, not a good hit")
	assert_eq(SimClock.speed_index, 0, "and the clock stops for it")
	# The same weapon on the contact it was fired at is the good line.
	sim.weapon_manager.weapon_impact.emit(sim.player_faction, w.spec, f["enemy"], true)
	assert_true(str(main.radio.journal[-1]).ends_with("Hit"), str(main.radio.journal[-1]))
	assert_eq(str(main.map._radio.entries[-1]["severity"]), "good")
	_close(main)
