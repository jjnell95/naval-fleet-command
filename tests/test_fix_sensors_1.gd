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
	for second in 700:
		_run(1.0)
		var t := _sim.track_manager.find_track("BLUE", jet)
		if t == null:
			continue
		if last_text != "" and t.solution_text() != last_text:
			flips += 1
		if last != Vector2.INF and last.distance_to(t.position) > 5.0:
			leaps += 1
		last_text = t.solution_text()
		last = t.position
	assert_true(last_text != "", "the aircraft's radar was heard")
	assert_true(flips <= 2, "the plot settles on one kind of solution (changed %d times)" % flips)
	assert_true(leaps <= 1, "only the first range moves the plot far (%d leaps over 5 nm)" % leaps)
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
