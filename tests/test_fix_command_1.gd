extends TestCase
## The commander's picture is the force's, whatever is hooked: the chart, the inbound warnings and
## the contact reports, played through the real command screen.

const SCENARIOS := "res://data/scenarios/"

var _save_root := ""
var _clock_speeds: Array[float] = []


func _open(scenario: String, o: GameOptions = null, game_seed := 2) -> Main:
	_save_root = SaveGame.root_override
	_clock_speeds = SimClock.speeds()
	SaveGame.root_override = "user://test-command-picture-%d" % Time.get_ticks_usec()
	var main: Main = preload("res://scenes/main/Main.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main._apply_options(o if o != null else GameOptions.normal(), false, false)
	main.simulation.seed_override = game_seed
	main.start_scenario(SCENARIOS + scenario)
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


static func _ids(tracks: Array) -> Array:
	var out: Array = tracks.map(func(t: Track) -> String: return t.id)
	out.sort()
	return out


## What the commander should hold, worked out here from the simulation alone: the networked plot
## and whatever each reporting off-link unit holds beyond it.
func _expected_ids(main: Main) -> Array:
	var sim := main.simulation
	var ids := {}
	for t: Track in sim.track_manager.get_tracks(sim.player_faction):
		ids[t.id] = true
	for u: Unit in sim.unit_manager.units:
		if u.faction == sim.player_faction and u.is_engageable() and not u.datalink_connected() and Main._receives_report(u):
			for t: Track in sim.track_manager.tracks_for(u):
				if t.status != Track.Status.LOST:
					ids[t.id] = true
	var out: Array = ids.keys()
	out.sort()
	return out


func _hostile_rounds_held(main: Main) -> Array:
	var sim := main.simulation
	return AirDefence.inbound_threats(sim.unit_manager, sim.threat_manager, sim.player_faction)


func _warning_lines(main: Main) -> int:
	var n := 0
	for line: String in main.radio.journal:
		if line.contains("INCOMING") or line.contains("INBOUND"):
			n += 1
	return n


## Strait of Hormuz for two minutes from the moment the Qeshm battery comes out of its hides, with
## the hook as given: "default" leaves the opening hook alone, "merchant" hooks the tanker, "none"
## clears the hook.
func _hormuz_watch(hook: String) -> void:
	var main := _open("gulf_01_hormuz.json")
	var sim := main.simulation
	var tanker := _own(main, "Gulf Horizon")
	assert_true(tanker != null and not tanker.spec.has_datalink, "the tanker is in the force and off the link")
	for wait in 300:
		if sim.director.fired.has("qeshm_battery_up"):
			break
		SimClock.advance(5.0)
	assert_true(sim.director.fired.has("qeshm_battery_up"), "[%s] the shore battery came out" % hook)
	match hook:
		"merchant":
			main.map.select_units([tanker])
		"none":
			main.map.clear_selection()
	var peak_side := 0
	var peak_shown := 0
	var banner_seen := false
	var glyphs_checked := 0
	for step in 24:
		SimClock.advance(5.0)
		main._process(1.0)
		var side := _hostile_rounds_held(main)
		var shown := main._commander_inbound()
		assert_eq(shown.size(), side.size(), "[%s] t=%d every inbound round the force holds is shown to the commander" % [hook, int(SimClock.sim_time)])
		assert_eq(main.map._threats.size() if _refresh(main) else -1, side.size(), "[%s] t=%d and marked on the chart" % [hook, int(SimClock.sim_time)])
		peak_side = maxi(peak_side, side.size())
		peak_shown = maxi(peak_shown, shown.size())
		if not shown.is_empty():
			banner_seen = banner_seen or main.data_display.threat_text.contains("INBOUND")
		if hook != "merchant":
			# With a merchant hooked the round's own glyph still waits on the chart's weapon filter.
			for entry: Dictionary in side:
				glyphs_checked += 1
				assert_true(WorldPresentation.weapon_visible(entry["weapon"], sim.player_faction, main.map.reference_unit(), sim.threat_manager, sim.unit_manager), "[%s] the round is drawn" % hook)
	var plot: Array = sim.track_manager.get_tracks(sim.player_faction)
	assert_true(plot.size() >= 2, "[%s] the force holds contacts by two minutes in (%d)" % [hook, plot.size()])
	assert_eq(_ids(main.map._plotted_tracks()), _ids(plot), "[%s] the chart plots the force's networked tracks" % hook)
	assert_eq(_ids(main.contact_panel.visible_tracks()), _ids(plot), "[%s] and the contact list holds the same" % hook)
	assert_true(peak_side >= 3, "[%s] the opening salvo arrives inside two minutes (%d)" % [hook, peak_side])
	assert_eq(peak_shown, peak_side, "[%s] and all of it reached the commander" % hook)
	assert_true(banner_seen, "[%s] the inbound banner was raised" % hook)
	assert_true(int(main._stats["hostile_rounds"]) >= peak_side, "[%s] each round was announced (%d)" % [hook, int(main._stats["hostile_rounds"])])
	assert_true(_warning_lines(main) >= peak_side, "[%s] on the radio line (%d lines)" % [hook, _warning_lines(main)])
	assert_true(hook == "merchant" or glyphs_checked > 0)
	match hook:
		"merchant":
			assert_eq(main.map.selected, [tanker] as Array[Unit], "the hook stayed on the tanker")
			assert_eq(main.map.reference_unit(), tanker, "and ranges are still read from her")
		"none":
			assert_true(main.map.selected.is_empty())
	_close(main)


func _refresh(main: Main) -> bool:
	main.map._refresh_threats()
	return true


func test_hormuz_opens_with_the_force_plot_and_missile_warnings() -> void:
	_hormuz_watch("default")


func test_hormuz_plot_and_warnings_survive_hooking_the_tanker() -> void:
	_hormuz_watch("merchant")


func test_hormuz_plot_and_warnings_survive_hooking_nothing() -> void:
	_hormuz_watch("none")


func test_every_operation_opens_on_a_fighting_unit_with_the_force_plot() -> void:
	for file: String in DirAccess.get_files_at(SCENARIOS):
		if not file.ends_with(".json"):
			continue
		var main := _open(file)
		var sim := main.simulation
		assert_true(main.map.selected.size() <= 1, "%s: at most one unit hooked" % file)
		for u: Unit in main.map.selected:
			assert_true(u.is_engageable(), "%s: the opening hook is not an airframe on deck (%s)" % [file, u.callsign])
			assert_true(u.datalink_connected() or not u.weapons.is_empty(), "%s: nor a merchant (%s)" % [file, u.callsign])
		if CommanderPicture.first_linked_combatant(sim.unit_manager, sim.player_faction) != null:
			assert_true(not main.map.selected.is_empty() and CommanderPicture.is_linked_combatant(main.map.selected[0]), "%s: a force with a warship on the link opens aboard one" % file)
		var merchant: Unit = null
		for u: Unit in sim.unit_manager.get_engageable_units(sim.player_faction):
			if not u.spec.has_datalink and u.weapons.is_empty():
				merchant = u
				break
		var populated := false
		for step in 10:
			SimClock.advance(60.0)
			var expected := _expected_ids(main)
			assert_eq(_ids(main.map._plotted_tracks()), expected, "%s t=%d: the chart is the commander's picture" % [file, int(SimClock.sim_time)])
			if expected.is_empty():
				continue
			populated = true
			# Whatever is under the hook, the same picture.
			var hooked: Array[Unit] = main.map.selected.duplicate()
			main.map.clear_selection()
			assert_eq(_ids(main.map._plotted_tracks()), expected, "%s: with nothing hooked" % file)
			if merchant != null and merchant.alive:
				main.map.select_units([merchant])
				assert_eq(_ids(main.map._plotted_tracks()), expected, "%s: with %s hooked" % [file, merchant.callsign])
			main.map.select_units(hooked.filter(func(u: Unit) -> bool: return u.alive))
			break
		if not populated:
			assert_true(sim.track_manager.get_tracks(sim.player_faction).is_empty(), "%s: no contacts in ten minutes, and none hidden" % file)
		_close(main)


## A contact held only aboard an own unit that is off the link, put there through the track
## manager the way that unit's sonar would.
func _private_contact(main: Main, holder: Unit, target: Unit) -> Track:
	var sim := main.simulation
	var c := SensorContact.make(target, target.position, 1.5, 0.8, 1.0, holder.position.distance_to(target.position), "sonar", holder)
	sim.track_manager.observe_contact(holder.faction, c, sim.unit_manager.now_s, SimClock.TICK_DT)
	return sim.track_manager.find_for(holder, target)


func _first_hostile(main: Main, domain: String) -> Unit:
	for u: Unit in main.simulation.unit_manager.units:
		if u.faction != main.simulation.player_faction and u.alive and u.spec.domain == domain and not main.simulation.track_manager.neutral_factions.has(u.faction):
			return u
	return null


func test_barrier_shows_the_deep_boats_contact_whatever_is_hooked() -> void:
	var main := _open("cold_war_02_barrier.json")
	var sim := main.simulation
	var boat := _own(main, "Dallas")
	var ship := _own(main, "Spruance")
	var victor := _first_hostile(main, "subsurface")
	assert_true(boat != null and ship != null and victor != null, "the barrier has its boat, a destroyer and an intruder")
	assert_true(boat.submerged() and not boat.datalink_connected() and Main._receives_report(boat), "Normal rules: the boat is deep, off the link and still reporting")
	assert_eq(main.map.selected, [ship] as Array[Unit], "the watch opens aboard the first warship on the link, not the deep boat")
	var held := _private_contact(main, boat, victor)
	assert_true(held != null and not held.networked, "the boat holds the intruder on its own picture")
	assert_true(sim.track_manager.find_track(sim.player_faction, victor) == null, "and the networked plot does not")
	for hook: Array in [[ship], [boat], []]:
		var units: Array[Unit] = []
		units.assign(hook)
		main.map.select_units(units)
		var label := "nothing" if units.is_empty() else units[0].callsign
		assert_true(main.map._plotted_tracks().has(held), "the boat's contact is on the chart with %s hooked" % label)
		assert_true(main.contact_panel.visible_tracks().has(held), "and in the contact list with %s hooked" % label)
		assert_true(main._commander_sees_track(held), "and is the commander's with %s hooked" % label)
		main.map.select_track(held)
		main.map._process(0.016)
		assert_eq(main.map.selected_track, held, "and stays hooked as a contact with %s hooked" % label)
		main.map.select_track(null)
	# Once a ship on the link holds the same intruder, it is one contact, and the plot's own.
	var linked := SensorContact.make(victor, victor.position, 0.5, 0.9, 1.0, ship.position.distance_to(victor.position), "sonar", ship)
	sim.track_manager.observe_contact(ship.faction, linked, sim.unit_manager.now_s, SimClock.TICK_DT)
	var plotted := sim.track_manager.find_track(sim.player_faction, victor)
	assert_true(plotted != null and plotted.networked)
	assert_eq(_ids(main.map._plotted_tracks()), [plotted.id], "shown once")
	assert_true(main.map._plotted_tracks().has(plotted) and not main.map._plotted_tracks().has(held), "as the networked track")
	_close(main)


func test_classic_boat_out_of_contact_adds_nothing_until_it_reports() -> void:
	var main := _open("cold_war_02_barrier.json", GameOptions.classic())
	var sim := main.simulation
	var boat := _own(main, "Dallas")
	var victor := _first_hostile(main, "subsurface")
	assert_true(SubmarineComms.restricted(boat) and not SubmarineComms.connected(boat), "Classic rules: the boat is deep and out of contact")
	var held := _private_contact(main, boat, victor)
	assert_true(held != null)
	for hook: Array in [[boat], []]:
		var units: Array[Unit] = []
		units.assign(hook)
		main.map.select_units(units)
		assert_true(not main.map._plotted_tracks().has(held), "a silent boat's contact stays aboard, hooked or not")
		assert_true(not main._commander_sees_track(held))
	# Its torpedo warning stays aboard too, while one a reporting ship holds is shown.
	var ship := _own(main, "Spruance")
	main.map.select_units([boat] as Array[Unit])
	var fish := Weapon.new()
	fish.id = 9001
	fish.faction = victor.faction
	fish.spec = victor.weapons[0] if not victor.weapons.is_empty() else null
	if fish.spec != null:
		sim.threat_manager.mark_detected(boat.faction, fish, sim.unit_manager.now_s, boat)
		assert_true(not main._commander_sees_threat(fish), "the silent boat's own detection is not the commander's")
		assert_true(not main.map._threat_visible(boat, fish), "nor on the chart with the boat hooked")
		sim.threat_manager.mark_detected(ship.faction, fish, sim.unit_manager.now_s, ship)
		assert_true(main._commander_sees_threat(fish), "the same weapon reported by a ship on the link is")
		assert_true(main.map._threat_visible(boat, fish), "and the chart shows it even with the silent boat hooked")
	# At communications depth the boat reports what it holds.
	boat.depth_m = 0.0
	assert_true(Main._receives_report(boat))
	if not boat.datalink_connected():
		assert_true(main.map._plotted_tracks().has(held), "a boat that has come up to report adds its picture")
	_close(main)


## Stands in for the track manager's reports of a unit's private picture.
class PrivatePictureReports:
	extends RefCounted
	signal local_track_added(observer: Unit, track: Track)
	signal local_track_classified(observer: Unit, track: Track)


func _lines(main: Main, part: String) -> int:
	var n := 0
	for line: String in main.radio.journal:
		if line.contains(part):
			n += 1
	return n


func test_deep_boat_reports_its_contact_once_on_the_radio_line() -> void:
	var main := _open("cold_war_02_barrier.json")
	var sim := main.simulation
	var reports := PrivatePictureReports.new()
	main._connect_private_contact_reports(reports)
	var boat := _own(main, "Dallas")
	var ship := _own(main, "Spruance")
	var victor := _first_hostile(main, "subsurface")
	main.map.select_units([ship] as Array[Unit])
	SimClock.set_paused(false)
	SimClock.set_speed_index(2)
	var held := _private_contact(main, boat, victor)
	reports.local_track_added.emit(boat, held)
	var number := DataDisplay.track_number_for_track(held)
	assert_eq(_lines(main, "New contact, track %s" % number), 1, "the boat's contact is called on the radio line though a destroyer is hooked")
	assert_eq(int(main._stats["contacts"]), 1, "and counted")
	assert_eq(SimClock.speed_index, 0, "and the watch is handed back at real time")
	reports.local_track_added.emit(boat, held)
	assert_eq(_lines(main, "New contact, track %s" % number), 1, "once")
	# The boat classifies it.
	held.classification = Track.Classification.CLASS_KNOWN
	held.known_class = "Victor III"
	held.identity = "HOSTILE"
	SimClock.set_speed_index(2)
	reports.local_track_classified.emit(boat, held)
	reports.local_track_classified.emit(boat, held)
	assert_eq(_lines(main, "Track %s classified Victor III, hostile" % number), 1, "its classification is called, once")
	assert_eq(int(main._stats["classified"]), 1)
	assert_eq(SimClock.speed_index, 0)
	# A ship on the link gains the same contact: the plot takes it over without a second call.
	main.map.select_track(held)
	var linked := SensorContact.make(victor, victor.position, 0.5, 0.9, 1.0, ship.position.distance_to(victor.position), "sonar", ship)
	sim.track_manager.observe_contact(ship.faction, linked, sim.unit_manager.now_s, SimClock.TICK_DT)
	var plotted := sim.track_manager.find_track(sim.player_faction, victor)
	assert_true(plotted != null and plotted != held)
	assert_eq(_lines(main, "New contact, track %s" % number), 1, "the networked plot gaining it is not a new contact")
	assert_eq(main.map.selected_track, plotted, "and the hooked contact follows to the plot's track")
	# Somebody else's boat is nobody's report.
	var theirs := Track.new()
	theirs.id = "T7777"
	theirs.owner_faction = victor.faction
	reports.local_track_added.emit(victor, theirs)
	assert_eq(_lines(main, "New contact"), 1)
	SimClock.set_paused(true)
	_close(main)


func test_a_contact_the_plot_already_holds_is_not_reported_again_from_a_boat() -> void:
	var main := _open("cold_war_02_barrier.json")
	var sim := main.simulation
	var reports := PrivatePictureReports.new()
	main._connect_private_contact_reports(reports)
	var boat := _own(main, "Dallas")
	var ship := _own(main, "Spruance")
	var victor := _first_hostile(main, "subsurface")
	var linked := SensorContact.make(victor, victor.position, 0.5, 0.9, 1.0, ship.position.distance_to(victor.position), "sonar", ship)
	sim.track_manager.observe_contact(ship.faction, linked, sim.unit_manager.now_s, SimClock.TICK_DT)
	assert_eq(_lines(main, "New contact"), 1, "the plot's contact is called")
	var held := _private_contact(main, boat, victor)
	reports.local_track_added.emit(boat, held)
	held.classification = Track.Classification.CLASS_KNOWN
	held.known_class = "Victor III"
	held.identity = "HOSTILE"
	reports.local_track_classified.emit(boat, held)
	assert_eq(_lines(main, "New contact"), 1, "the boat holding it too adds no second call")
	assert_eq(_lines(main, "classified"), 0, "and the chart's track is the plot's, so the boat's own classification is not called over it")
	_close(main)


func test_a_silent_classic_boat_reports_what_it_holds_when_it_comes_up() -> void:
	var main := _open("cold_war_02_barrier.json", GameOptions.classic())
	var sim := main.simulation
	var reports := PrivatePictureReports.new()
	main._connect_private_contact_reports(reports)
	var boat := _own(main, "Dallas")
	var victor := _first_hostile(main, "subsurface")
	var held := _private_contact(main, boat, victor)
	reports.local_track_added.emit(boat, held)
	main._process(1.0)
	assert_eq(_lines(main, "New contact"), 0, "a boat out of contact reports nothing")
	boat.depth_m = 0.0
	if boat.datalink_connected():
		# On the link at communications depth: its next look puts the contact on the plot.
		_private_contact(main, boat, victor)
	main._process(1.0)
	assert_eq(_lines(main, "New contact"), 1, "at communications depth the contact it holds is called, once")
	main._process(1.0)
	assert_eq(_lines(main, "New contact"), 1)
	_close(main)


func test_a_boats_own_track_outranks_an_intelligence_datum_on_the_same_contact() -> void:
	var main := _open("cold_war_02_barrier.json")
	var sim := main.simulation
	var boat := _own(main, "Dallas")
	var ship := _own(main, "Spruance")
	var victor := _first_hostile(main, "subsurface")
	var held := _private_contact(main, boat, victor)
	main._process(1.0)
	main.map.select_units([boat] as Array[Unit])
	main.map.select_track(held)
	var datum := sim.track_manager.report_intel(sim.player_faction, victor, victor.position + Vector2(9.0, 0.0), 12.0, sim.unit_manager.now_s, "Fixed acoustic array")
	assert_true(datum != null and datum.reported and datum.id == held.id, "a shore array cues the same contact onto the networked plot")
	assert_eq(_ids(main.map._plotted_tracks()), [held.id], "the contact is still shown once")
	assert_true(main.map._plotted_tracks().has(held), "as the boat's own track, the one a weapon can be laid on")
	SimClock.advance(SimClock.TICK_DT)
	main.map._process(0.016)
	assert_eq(main.map.selected_track, held, "and it stays hooked")
	assert_eq(_lines(main, "New contact"), 1, "nor is the cue a second new contact")
	# A ship on the link then holds it with her own sonar: the plot's track takes over, hook and all.
	var linked := SensorContact.make(victor, victor.position, 0.5, 0.9, 1.0, ship.position.distance_to(victor.position), "sonar", ship)
	sim.track_manager.observe_contact(ship.faction, linked, sim.unit_manager.now_s, SimClock.TICK_DT)
	SimClock.advance(SimClock.TICK_DT)
	main.map._process(0.016)
	assert_true(not datum.reported, "the plot now holds the contact itself")
	assert_eq(main.map._plotted_tracks(), [datum], "and its track is the one shown")
	assert_eq(main.map.selected_track, datum, "with the hook moved onto it")
	assert_eq(main.map.selected, [boat] as Array[Unit], "and the boat still under command")
	_close(main)


func _ships(main: Main) -> Array[Unit]:
	var out: Array[Unit] = []
	for u: Unit in main.simulation.unit_manager.get_faction_units(main.simulation.player_faction):
		if u.needs_sea_room() and u.spec.max_speed_kn > 0.0:
			out.append(u)
	return out


## The synchronous suite yields no frame for the window to lay out its panes.
func _lay_out(main: Main) -> void:
	main.map.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main.map.size = Vector2(1000, 600)
	main.map._apply_pending_fit()


func _assert_force_framed(main: Main, why: String) -> void:
	var rect := main.map.unobstructed_chart_rect()
	var ships := _ships(main)
	assert_true(ships.size() >= 2)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for u in ships:
		var at := main.map.world_to_screen(u.position)
		assert_true(rect.has_point(at), "%s: %s is on the chart" % [why, u.callsign])
		lo = lo.min(at)
		hi = hi.max(at)
	var spread := maxf(hi.x - lo.x, hi.y - lo.y)
	assert_true(spread >= minf(rect.size.x, rect.size.y) * 0.25, "%s: the formation fills a readable part of the chart (%d px of %d)" % [why, int(spread), int(minf(rect.size.x, rect.size.y))])


func test_hormuz_opens_on_the_force_not_the_whole_theatre() -> void:
	var main := _open("gulf_01_hormuz.json")
	_lay_out(main)
	var theatre := main.simulation.map_extent_nm
	var shown_nm := main.map.unobstructed_chart_rect().size.y / main.map.ppn
	assert_true(shown_nm <= theatre / 3.0, "the opening chart spans %d nm, not the theatre's %d" % [int(shown_nm), int(theatre)])
	_assert_force_framed(main, "opening view")
	assert_true(not main.map.show_coverage, "and the sensor coverage layer waits to be asked for")
	assert_true(main.map.toggle_layer("coverage"), "its key still turns it on")
	main.map.toggle_layer("coverage")
	# Fit force (Home) frames the same thing from anywhere.
	main.map.fit_to(Vector2(400.0, -300.0), 500.0)
	var k := InputEventKey.new()
	k.keycode = KEY_HOME
	k.physical_keycode = KEY_HOME
	k.pressed = true
	main._unhandled_key_input(k)
	_assert_force_framed(main, "Home")
	assert_near(main.map.unobstructed_chart_rect().size.y / main.map.ppn, shown_nm, 1.0, "at the opening scale")
	_close(main)


func test_an_authored_opening_focus_is_kept() -> void:
	var main := _open("cold_war_02_barrier.json")
	var chart: Dictionary = main.simulation.scenario["map"]
	assert_true(chart.has("focus_extent_nm"))
	var opening := main._opening_view()
	assert_eq(Vector2(opening.x, opening.y), Vector2(chart["focus_center_nm"][0], chart["focus_center_nm"][1]))
	assert_near(opening.z, float(chart["focus_extent_nm"]), 0.01)
	_close(main)
