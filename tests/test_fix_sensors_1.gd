extends TestCase
## Contacts that behave like contacts: what the plot does with a bearing, with a lost contact and
## with a first look, played through the whole sensor cycle wherever the cycle is the point.

const SCENARIO_PATH := "user://test_fix_sensors_1.json"

var _sim: Simulation


func _load(units: Array, environment := {"sea_state": 2, "visibility_nm": 10}) -> Simulation:
	var scenario := {
		"id": "fix_sensors", "name": "FIXTURE", "seed": 7, "player_faction": "BLUE",
		"map": {"center_nm": [0, 0], "extent_nm": 300}, "environment": environment,
		"objectives": {"text": "", "victory": [{"id": "watch", "type": "time_elapsed", "seconds": 90000, "text": "Keep the watch"}], "loss": []},
		"units": units,
	}
	var f := FileAccess.open(SCENARIO_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(scenario))
	f.close()
	SimClock.set_paused(true)
	_sim = Simulation.new()
	_sim.seed_override = 7
	(Engine.get_main_loop() as SceneTree).root.add_child(_sim)
	assert_true(_sim.load_scenario(SCENARIO_PATH), "the fixture loads")
	_sim.ai_enabled = false
	return _sim


func _free() -> void:
	if _sim == null:
		return
	_sim.unit_manager.clear()
	_sim.free()
	_sim = null


func _unit(callsign: String) -> Unit:
	for u in _sim.unit_manager.units:
		if u.callsign == callsign:
			return u
	return null


func _ship(platform: String, callsign: String, faction: String, at: Array, heading: float, speed: float, radar: bool) -> Dictionary:
	return {"platform": platform, "callsign": callsign, "faction": faction, "position_nm": at, "heading_deg": heading, "speed_kn": speed, "radar_on": radar, "air_wing": []}


func _run(seconds: float) -> void:
	for i in int(seconds * 4.0):
		SimClock.advance(0.25)


const BURKE := "usn_ddg_arleigh_burke_iia"
const GORSHKOV := "rfn_ffg_admiral_gorshkov"
const P8 := "usn_mpa_p8a"
const SU34 := "rfn_strike_su34"


# --- A fix handed to bearings -------------------------------------------------------------------

## A patrol aircraft holding a frigate on radar switches the radar off; its ESM still hears her.
func test_a_radar_fix_handed_to_esm_stays_where_the_ship_is() -> void:
	_load([_ship(BURKE, "Burke", "BLUE", [0, 0], 0, 15, true), _ship(P8, "Poseidon", "BLUE", [80, 0], 90, 380, true), _ship(GORSHKOV, "Gorshkov", "RED", [80, 40], 270, 14, true)])
	var p8 := _unit("Poseidon")
	var ship := _unit("Gorshkov")
	_run(120.0)
	var t := _sim.track_manager.find_track("BLUE", ship)
	assert_true(t != null and not t.bearing_only and t.has_kinematics, "held on radar with a course and speed before the switch")
	if t == null:
		_free()
		return
	var speed_before := t.speed_kn
	p8.radar_on = false
	var worst_step := 0.0
	var worst_miss := 0.0
	var last := t.position
	for second in 150:
		_run(1.0)
		worst_step = maxf(worst_step, last.distance_to(t.position))
		worst_miss = maxf(worst_miss, t.position.distance_to(ship.position))
		last = t.position
	assert_eq(t.source, "esm", "the plot now rests on the intercept")
	assert_true(worst_step < 1.0, "the plot does not leap when the radar goes off (worst %.1f nm in a second)" % worst_step)
	assert_true(worst_miss < 3.0, "the last fix is carried forward, not replaced by a guess (worst %.1f nm off)" % worst_miss)
	assert_eq(t.solution_text(), "ESTIMATED FIX", "a range carried on bearings is an estimate, not a bare bearing")
	assert_true(t.has_kinematics and absf(t.speed_kn - speed_before) < 3.0, "a bearing does not wipe the course and speed")
	assert_true(t.position_error_nm > 1.0 and t.position_error_nm >= worst_miss * 0.5, "the ellipse has grown to cover it (%.1f nm)" % t.position_error_nm)
	p8.radar_on = true
	_run(3.0)
	assert_eq(t.solution_text(), "MEASURED FIX")
	assert_true(t.position.distance_to(ship.position) < 1.0, "the first radar plot replaces the estimate outright")
	_free()


## Two silent destroyers hearing one radiating aircraft a long way off: marginal crossing geometry.
func test_crossed_esm_bearings_do_not_flip_between_fix_and_bearing() -> void:
	_load([_ship(BURKE, "Burke A", "BLUE", [0, 0], 0, 0, false), _ship(BURKE, "Burke B", "BLUE", [0, 45], 0, 0, false),
		{"platform": SU34, "callsign": "Fullback", "faction": "RED", "position_nm": [110, -60], "heading_deg": 350, "speed_kn": 480, "radar_on": true, "altitude_m": 9000}])
	var jet := _unit("Fullback")
	var flips := 0
	var leaps := 0
	var last_text := ""
	var last := Vector2.INF
	var claimed := 0
	var wrong := 0
	for second in 700:
		_run(1.0)
		var t := _sim.track_manager.find_track("BLUE", jet)
		if t == null:
			continue
		if t.solution_text() == "ESTIMATED FIX":
			claimed += 1
			if t.position.distance_to(jet.position) > 3.0 * t.position_error_nm:
				wrong += 1
		if last_text != "" and t.solution_text() != last_text:
			flips += 1
		if last != Vector2.INF and last.distance_to(t.position) > 5.0:
			leaps += 1
		last_text = t.solution_text()
		last = t.position
	assert_true(last_text != "", "the aircraft's radar was heard")
	assert_true(flips <= 2, "the plot settles on one kind of solution (changed %d times)" % flips)
	assert_true(leaps <= 1, "only the first range moves the plot far (%d leaps over 5 nm)" % leaps)
	assert_true(claimed > 300, "the crossed lines gave an estimated fix (%d s)" % claimed)
	assert_true(wrong * 50 <= claimed, "an estimated fix on an aircraft claims no more than it knows (%d of %d s beyond three times its error)" % [wrong, claimed])
	_free()


## A range the plot holds is given up only when it is old, never because one bearing arrived.
func test_a_bearing_after_a_fix_keeps_the_range_and_gives_it_up_when_old() -> void:
	var tm := TrackManager.new()
	var u := Unit.new()
	u.spec = PlatformSpec.new()
	u.faction = "RED"
	tm.observe("BLUE", u, Vector2(0, 30), 0.5, 1.0, 0.0, 1.0, 30.0)
	var t := tm.find_track("BLUE", u)
	t.domain = "surface"
	for second in range(1, 700):
		var c := SensorContact.new()
		c.target = u
		c.bearing_only = true
		c.bearing_key = "listener"
		c.bearing_origin = Vector2.ZERO
		c.bearing_accuracy_deg = 1.5
		c.bearing_range_limit_nm = 200.0
		c.error_axis_deg = Geo.bearing_deg(Vector2.ZERO, Vector2(0, 30))
		c.position = Vector2(0, 80)
		c.error_major_nm = 60.0
		c.source = "esm"
		tm.observe_contact("BLUE", c, float(second), 1.0)
		tm.tick(float(second), 1.0)
		if second == 300:
			assert_true(not t.is_bearing_only(), "five minutes on bearings: the ship's range is still an estimate")
			assert_true(t.position.distance_to(Vector2(0, 30)) < 0.5, "and still where it was fixed")
	assert_true(t.is_bearing_only(), "after ten minutes nothing has measured the range: it is a bearing")
	assert_true(t.position.distance_to(Vector2(0, 30)) < 0.5, "giving the range up does not move the plot to a guess")
	assert_true(not t.has_kinematics, "no range, so no course and speed")
	tm.free()


# --- Passive ranging ----------------------------------------------------------------------------

func _target_unit() -> Unit:
	var u := Unit.new()
	u.spec = PlatformSpec.new()
	u.spec.short_name = "TEST"
	u.faction = "RED"
	return u


func _look(u: Unit, origin: Vector2, bearing: float, key: String, accuracy: float, limit := 30.0) -> SensorContact:
	var c := SensorContact.new()
	c.target = u
	c.bearing_only = true
	c.bearing_key = key
	c.bearing_origin = origin
	c.bearing_accuracy_deg = accuracy
	c.bearing_range_limit_nm = limit
	c.error_axis_deg = bearing
	c.position = origin + Geo.heading_to_vector(bearing) * 4.0
	c.range_nm = 4.0
	c.error_major_nm = 4.0
	c.error_minor_nm = 0.3
	c.source = "sonar_passive"
	return c


## A boat at 6 kn hearing a submarine five miles off on a set good to 1.6 degrees a look, as shipped.
## Returns [seconds until the plot held a range (-1 for never), the track, the target's position].
func _listen(zigzag: bool, seconds: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var tm := TrackManager.new()
	var u := _target_unit()
	var own := Vector2.ZERO
	var target := Vector2(1.5, 5.0)
	var target_velocity := Geo.heading_to_vector(200.0) * Geo.knots_to_nm_per_s(7.0)
	var course := 300.0
	var resolved := -1
	for second in range(1, seconds + 1):
		if zigzag and second % 300 == 0:
			course = 80.0 if course > 180.0 else 300.0
		own += Geo.heading_to_vector(course) * Geo.knots_to_nm_per_s(6.0)
		target += target_velocity
		var bearing := Geo.bearing_deg(own, target) + rng.randfn(0.0, 1.6)
		tm.observe_contact("BLUE", _look(u, own, bearing, "boat", 1.6), float(second), 1.0)
		tm.tick(float(second), 1.0)
		if resolved < 0 and not tm.find_track("BLUE", u).is_bearing_only():
			resolved = second
	var t := tm.find_track("BLUE", u)
	tm.free()
	return [resolved, t, target]


func test_a_change_of_course_resolves_a_passive_range_in_minutes() -> void:
	var run := _listen(true, 900)
	var resolved: int = run[0]
	var t: Track = run[1]
	var truth: Vector2 = run[2]
	assert_true(resolved > 0 and resolved <= 720, "two legs either side of a turn give a range (resolved at %d s)" % resolved)
	assert_true(not t.is_bearing_only(), "and the plot still holds it after a third leg")
	assert_true(t.position.distance_to(truth) <= maxf(t.position_error_nm * 1.5, 1.0), "the contact lies inside the ellipse the plot claims (%.1f nm off, claimed %.1f)" % [t.position.distance_to(truth), t.position_error_nm])
	assert_true(t.position_error_nm < 4.0, "the estimate is worth having")


func test_a_steady_course_never_resolves_a_passive_range() -> void:
	var run := _listen(false, 900)
	assert_eq(run[0], -1, "no manoeuvre, no range")
	assert_true((run[1] as Track).is_bearing_only())


## A quiet boat heard at a mile and a half on a set whose catalogue reach is 38 nm.
func test_the_first_range_guess_comes_from_the_reach_the_contact_was_heard_at() -> void:
	var tm := TrackManager.new()
	var sm := SensorManager.new()
	sm.track_manager = tm
	sm.rng.seed = 5
	var listener := Unit.new()
	listener.spec = PlatformSpec.new()
	listener.spec.short_name = "HELO"
	listener.faction = "BLUE"
	listener.position = Vector2(10, 10)
	var set := SensorSpec.new()
	set.kind = "sonar"
	set.passive_sensitivity_nm = 38.0
	set.bearing_accuracy_deg = 1.6
	var boat := _target_unit()
	boat.position = Vector2(10, 11.5)
	sm._report_passive(listener, boat, 1.5, 3.0, set, 1.0, 10.0)
	var t := tm.find_for(listener, boat)
	assert_true(t != null and t.is_bearing_only())
	if t != null:
		var plotted := t.position.distance_to(listener.position)
		assert_true(plotted <= 3.0, "the line ends inside the reach it was heard at (%.1f nm), not at half the catalogue range" % plotted)
		assert_true(t.error_major_nm <= 3.0, "and its length is that reach")
		assert_true(t.bearing_origin.distance_to(listener.position) < 0.01, "the plot records where the bearing was taken from")
	sm.free()
	tm.free()


# --- Aircraft held on intercepts ----------------------------------------------------------------

func _zigzag_history(speed_limit: float) -> Array:
	var history := []
	var u := _target_unit()
	var own := Vector2.ZERO
	var course := 300.0
	for second in range(1, 601):
		if second % 300 == 0:
			course = 80.0
		own += Geo.heading_to_vector(course) * Geo.knots_to_nm_per_s(12.0)
		var c := _look(u, own, Geo.bearing_deg(own, Vector2(1.0, 5.0)), "ship", 0.5)
		c.bearing_speed_limit_kn = speed_limit
		BearingSolution.add(history, c, float(second))
	return history


## One listener's bearings over minutes fit a steady course and speed. A ship holds one; a jet does
## not, so nothing that may be a jet is ranged that way.
func test_only_ship_speed_contacts_are_ranged_from_one_listeners_bearings() -> void:
	assert_true(not BearingSolution.estimate(_zigzag_history(70.0), 600.0).is_empty(), "a ship-speed contact is ranged across the listener's turn")
	assert_true(BearingSolution.estimate(_zigzag_history(1200.0), 600.0).is_empty(), "something that may be an aircraft is not")
	assert_true(not BearingSolution.estimate(_zigzag_history(1200.0), 600.0, 70.0).is_empty(), "unless the plot knows it for a ship")


## Crossed intercepts put an aircraft miles from where it is; then a radar finds it.
func test_the_first_radar_plot_on_an_esm_estimate_is_taken_as_it_stands() -> void:
	var tm := TrackManager.new()
	var u := _target_unit()
	var truth := Vector2(0, 60)
	for second in range(1, 31):
		for pair: Array in [[Vector2(-10, 0), "a", 1.5], [Vector2(10, 0), "b", -1.5]]:
			var c := _look(u, pair[0], Geo.bearing_deg(pair[0], truth) + float(pair[2]), pair[1], 1.5, 400.0)
			c.bearing_speed_limit_kn = 1200.0
			c.source = "esm"
			tm.observe_contact("BLUE", c, float(second), 1.0)
		tm.tick(float(second), 1.0)
	var t := tm.find_track("BLUE", u)
	assert_eq(t.solution_text(), "ESTIMATED FIX", "two crossing lines give an estimate")
	assert_true(t.position.distance_to(truth) > 5.0, "which three degrees of error between them put well off (%.1f nm)" % t.position.distance_to(truth))
	var plot := SensorContact.make(u, truth + Vector2(0.1, 0.0), 0.9, 0.5, 1.0, 60.0)
	tm.observe_contact("BLUE", plot, 31.0, 1.0)
	assert_eq(t.solution_text(), "MEASURED FIX")
	assert_true(t.position.distance_to(plot.position) < 0.01, "the radar plot replaces the estimate; it is not averaged with it (%.1f nm off)" % t.position.distance_to(plot.position))
	assert_true(t.position.distance_to(truth) <= t.position_error_nm, "so the plot is inside the error it claims")
	tm.free()


# --- A bearing on the chart ---------------------------------------------------------------------

## Only the patrol aircraft hears the frigate; a destroyer ninety miles away holds nothing.
func test_a_bearing_line_starts_at_the_unit_that_hears_the_contact() -> void:
	_load([_ship(BURKE, "Burke", "BLUE", [0, 0], 0, 15, false), _ship(P8, "Poseidon", "BLUE", [80, 0], 90, 380, false), _ship(GORSHKOV, "Gorshkov", "RED", [80, 70], 270, 14, true)])
	var burke := _unit("Burke")
	var p8 := _unit("Poseidon")
	var ship := _unit("Gorshkov")
	_run(20.0)
	var t := _sim.track_manager.find_track("BLUE", ship)
	assert_true(t != null and t.is_bearing_only(), "the frigate is held on an intercept alone")
	if t == null:
		_free()
		return
	var moved := 0.0
	var last := t.position
	for second in 60:
		_run(1.0)
		# Sideways movement of the line's end, not the aircraft carrying the line along with it.
		moved += maxf(last.distance_to(t.position) - Geo.knots_to_nm_per_s(p8.speed_kn), 0.0)
		last = t.position
	assert_true(moved / 60.0 < 0.3, "the line does not jitter with every look (%.2f nm a second)" % (moved / 60.0))
	assert_eq(t.bearing_unit(), p8, "the plot knows whose bearing it is")
	var start := TacticalMap.bearing_line_start(t, burke)
	assert_true(start.distance_to(p8.position) < 0.5, "the chart draws the line from the aircraft, not from the reference ship (%.0f nm from the aircraft)" % start.distance_to(p8.position))
	var true_bearing := Geo.bearing_deg(p8.position, ship.position)
	var drawn := Geo.bearing_deg(start, t.position)
	assert_true(absf(Geo.heading_delta(true_bearing, drawn)) < 4.0, "and along the bearing it was taken on (drawn %03.0f, true %03.0f)" % [drawn, true_bearing])
	var panel := ContactPanel.new()
	var text := panel._detail_text(t, burke, SimClock.sim_time)
	assert_true(text.contains("Poseidon: BRG"), "the track file gives the bearing from the unit that holds it")
	assert_true(not text.contains("Burke: BRG"), "not from a ship that does not")
	panel.free()
	_free()


## The same intercept on a radar at the masthead and on one at 9,000 m: the listener cannot tell.
func test_an_intercepts_first_range_does_not_follow_the_emitters_height() -> void:
	var tm := TrackManager.new()
	var sm := SensorManager.new()
	sm.track_manager = tm
	sm.rng.seed = 5
	var listener := Unit.new()
	listener.spec = PlatformSpec.new()
	listener.spec.mast_height_m = 30.0
	listener.faction = "BLUE"
	var set := SensorSpec.new()
	set.kind = "esm"
	set.esm_gain = 2.0
	set.antenna_height_m = 26.0
	set.bearing_accuracy_deg = 1.5
	var low := _target_unit()
	low.position = Vector2(0, 20)
	var high := _target_unit()
	high.position = Vector2(20, 0)
	sm._report_esm(listener, low, 20.0, 31.0, set, 1.0)
	sm._report_esm(listener, high, 20.0, 250.0, set, 1.0)
	var a := tm.find_for(listener, low)
	var b := tm.find_for(listener, high)
	assert_near(a.position.length(), b.position.length(), 0.01, "both lines are the set's nominal length")
	assert_near(a.error_major_nm, b.error_major_nm, 0.01)
	sm.free()
	tm.free()


# --- A first look ---------------------------------------------------------------------------------

## A strike aircraft coming in low: the destroyer's first radar plot on it, and what a SAM says.
func test_a_first_radar_plot_has_a_domain_and_can_be_engaged() -> void:
	_load([_ship(BURKE, "Burke", "BLUE", [0, 0], 0, 15, true),
		{"platform": SU34, "callsign": "Low", "faction": "RED", "position_nm": [40, 0], "heading_deg": 270, "speed_kn": 490, "radar_on": false, "altitude_m": 60}])
	var burke := _unit("Burke")
	var jet := _unit("Low")
	jet.altitude_m = 60.0
	jet.ordered_altitude_m = 60.0
	var sam := burke.get_weapon("sm2_family")
	assert_true(sam != null, "the destroyer carries its area SAM")
	var t: Track = null
	for second in 200:
		_run(1.0)
		t = _sim.track_manager.find_track("BLUE", jet)
		if t != null:
			break
	assert_true(t != null, "the radar finds the aircraft")
	if t != null and sam != null:
		assert_true(t.observation_time_s < 5.0, "this is the first look")
		assert_eq(t.domain, "air", "a plot with height is an aircraft at once")
		assert_eq(t.description(), "AIR CONTACT")
		var reason := str(Combat.check_engagement(burke, sam, t)["reason"])
		assert_true(reason != "WRONG WEAPON FOR CONTACT", "the SAM is not refused for want of a domain (%s)" % reason)
	_free()


func test_a_plot_takes_its_domain_from_the_sensor_and_a_bearing_waits() -> void:
	var tm := TrackManager.new()
	var ship := _target_unit()
	ship.spec.domain = "surface"
	tm.observe("BLUE", ship, Vector2(0, 20), 0.5, 1.0, 1.0, 1.0, 20.0)
	assert_eq(tm.find_track("BLUE", ship).domain, "surface", "a radar plot at sea level is a surface contact")
	var site := _target_unit()
	site.spec.domain = "land"
	tm.observe("BLUE", site, Vector2(5, 20), 0.5, 1.0, 1.0, 1.0, 20.0)
	assert_eq(tm.find_track("BLUE", site).domain, "land", "or a fixed site ashore")
	var boat := _target_unit()
	boat.spec.domain = "subsurface"
	boat.depth_m = 120.0
	tm.observe_contact("BLUE", SensorContact.make(boat, Vector2(0, 3), 0.4, 0.5, 1.0, 3.0, "sonar_active"), 1.0, 1.0)
	assert_eq(tm.find_track("BLUE", boat).domain, "subsurface", "an active echo from depth is a submarine")
	var heard := _target_unit()
	heard.spec.domain = "surface"
	for second in range(1, 20):
		tm.observe_contact("BLUE", _look(heard, Vector2.ZERO, 45.0, "ship", 1.5), float(second), 1.0)
	var t := tm.find_track("BLUE", heard)
	assert_eq(t.domain, "", "a bearing says nothing of what it is until it has been listened to")
	assert_eq(t.classification, Track.Classification.UNKNOWN)
	for second in range(20, 80):
		tm.observe_contact("BLUE", _look(heard, Vector2.ZERO, 45.0, "ship", 1.5), float(second), 1.0)
	assert_eq(t.domain, "surface", "listening long enough classifies it")
	tm.free()


# --- Lost contacts --------------------------------------------------------------------------------

## A contact held on radar for 70 s on a steady course, then never seen again.
func _held_then_lost(domain: String, speed_kn: float, altitude_m: float) -> Array:
	var tm := TrackManager.new()
	var u := _target_unit()
	u.spec.domain = domain
	var step := Geo.knots_to_nm_per_s(speed_kn)
	for second in range(1, 71):
		var c := SensorContact.make(u, Vector2(0.0, 50.0 - step * second), 0.5, 0.5, 1.0, 50.0, "sonar_active" if domain == "subsurface" else "radar")
		c.altitude_m = altitude_m
		tm.observe_contact("BLUE", c, float(second), 1.0)
		tm.tick(float(second), 1.0)
	u.depth_m = 100.0 if domain == "subsurface" else 0.0
	return [tm, u]


func _coast(tm: TrackManager, from: int, to: int) -> void:
	for second in range(from, to + 1):
		tm.tick(float(second), 1.0)


func test_a_lost_aircraft_stops_being_a_target_and_is_dropped_in_minutes() -> void:
	var held := _held_then_lost("air", 480.0, 9000.0)
	var tm: TrackManager = held[0]
	var t := tm.find_track("BLUE", held[1])
	assert_true(t.has_kinematics and t.fire_control_quality(), "held, with a course, and fit to shoot at")
	var last_seen := t.position
	_coast(tm, 71, 100)
	assert_eq(t.status, Track.Status.STALE, "thirty seconds unseen, an aircraft's plot is stale")
	assert_true(not t.fire_control_quality(), "and nothing but a torpedo may be laid on a stale plot")
	_coast(tm, 101, 180)
	assert_true(last_seen.distance_to(t.position) < 10.0, "the plot stops flying on once its ellipse is large (moved %.0f nm)" % last_seen.distance_to(t.position))
	assert_true(t.position_error_nm >= last_seen.distance_to(t.position), "and the ellipse covers how far it was moved (%.1f nm)" % t.position_error_nm)
	_coast(tm, 181, 200)
	assert_true(tm.find_track("BLUE", held[1]) == null, "two minutes unseen, the aircraft is dropped")
	tm.free()


func test_a_lost_ship_is_kept_ten_minutes_and_a_submarine_thirty() -> void:
	var ship := _held_then_lost("surface", 18.0, -1.0)
	var tm: TrackManager = ship[0]
	_coast(tm, 71, 400)
	var t := tm.find_track("BLUE", ship[1])
	assert_true(t != null and t.status == Track.Status.STALE, "a ship five minutes unseen is still plotted, stale")
	if t != null:
		assert_true(t.position_error_nm > 1.5 and t.position_error_nm < 6.0, "with an ellipse a ship could have covered (%.1f nm)" % t.position_error_nm)
	_coast(tm, 401, 700)
	assert_true(tm.find_track("BLUE", ship[1]) == null, "and dropped after ten")
	tm.free()
	var boat := _held_then_lost("subsurface", 6.0, -1.0)
	tm = boat[0]
	_coast(tm, 71, 1500)
	assert_true(tm.find_track("BLUE", boat[1]) != null, "a submarine datum is worth keeping for twenty minutes and more")
	_coast(tm, 1501, 1900)
	assert_true(tm.find_track("BLUE", boat[1]) == null, "and is dropped after thirty")
	tm.free()


## A missile sent at a plot five minutes old finds the ship. Nobody is watching; the plot was moving.
func test_a_hit_on_a_stale_plot_leaves_a_fixed_datum() -> void:
	var held := _held_then_lost("surface", 28.0, -1.0)
	var tm: TrackManager = held[0]
	var u: Unit = held[1]
	_coast(tm, 71, 300)
	var t := tm.find_track("BLUE", u)
	assert_true(t.status == Track.Status.STALE and t.has_kinematics, "a stale plot still dead-reckoning")
	var round := WeaponSpec.new()
	round.damage = 500.0
	tm.on_weapon_impact("BLUE", round, u, true)
	u.alive = false
	tm.on_unit_destroyed(u, "BLUE")
	var at := t.position
	_coast(tm, 301, 500)
	assert_true(tm.find_track("BLUE", u) == t, "the plot is kept: nobody saw what the round did")
	assert_near(t.position.distance_to(at), 0.0, 0.01, "but it is a datum where the round went in, not a ship sailing on")
	assert_true(not t.has_kinematics, "with no course and speed")
	tm.free()


# --- Track numbers --------------------------------------------------------------------------------

func test_a_contact_dropped_and_found_elsewhere_gets_a_new_number() -> void:
	var tm := TrackManager.new()
	var u := _target_unit()
	u.spec.domain = "surface"
	u.id = 41
	tm.observe("BLUE", u, Vector2(0, 30), 0.5, 1.0, 1.0, 1.0, 30.0)
	var first := tm.find_track("BLUE", u).id
	_coast(tm, 2, 700)
	assert_true(tm.find_track("BLUE", u) == null, "the contact was dropped")
	tm.observe("BLUE", u, Vector2(60, -20), 0.5, 1.0, 701.0, 1.0, 60.0)
	var again := tm.find_track("BLUE", u)
	assert_true(again.id != first, "found again seventy miles away it is a new contact, not the old number (%s then %s)" % [first, again.id])
	_coast(tm, 702, 1400)
	assert_true(tm.find_track("BLUE", u) == null)
	tm.observe("BLUE", u, again.position + Vector2(1.0, 0.5), 0.5, 1.0, 1401.0, 1.0, 60.0)
	assert_eq(tm.find_track("BLUE", u).id, again.id, "found again inside the ellipse it was dropped with, it is the same contact")
	tm.free()


# --- Fixed sites ----------------------------------------------------------------------------------

func test_a_shore_site_is_never_given_a_course_and_speed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var tm := TrackManager.new()
	var site := _target_unit()
	site.spec.domain = "land"
	var ship := _target_unit()
	ship.spec.domain = "surface"
	for second in range(1, 200):
		for pair: Array in [[site, Vector2(10, 40)], [ship, Vector2(-10, 40)]]:
			var noise := Vector2(rng.randfn(0.0, 0.2), rng.randfn(0.0, 0.2))
			tm.observe("BLUE", pair[0], (pair[1] as Vector2) + noise, 0.5, 1.0, float(second), 1.0, 40.0)
		tm.tick(float(second), 1.0)
	var t := tm.find_track("BLUE", site)
	assert_eq(t.domain, "land")
	assert_true(not t.has_kinematics, "the scatter of a radar's plots on a battery is not a course and speed")
	assert_near(t.speed_kn, 0.0, 0.001)
	assert_true(tm.find_track("BLUE", ship).has_kinematics, "a ship held the same way is still fitted")
	tm.free()
