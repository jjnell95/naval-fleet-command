extends TestCase
## What a plot does with bearings that come and go, how honestly a passive range owns up to its
## error, why a radar holds what it holds, and what a commander may say about a contact himself.


# --- Crossed intercepts that come and go --------------------------------------------------------

const LISTENER_A := Vector2(0.0, 0.0)
const LISTENER_B := Vector2(45.0, 0.0)
const JET_CENTRE := Vector2(20.0, 80.0)
const JET_TURN_NM := 20.0
const JET_KN := 300.0


func _jet() -> Unit:
	var u := Unit.new()
	u.spec = PlatformSpec.new()
	u.spec.short_name = "TEST"
	u.spec.domain = "air"
	u.faction = "RED"
	return u


## Where the jet is at `second`: flying a wide circle, as a patrol aircraft on station does.
func _jet_at(second: int) -> Vector2:
	var angle := Geo.knots_to_nm_per_s(JET_KN) / JET_TURN_NM * float(second)
	return JET_CENTRE + Vector2(cos(angle), sin(angle)) * JET_TURN_NM


func _intercept(u: Unit, origin: Vector2, at: Vector2, key: String, rng: RandomNumberGenerator, accuracy := 1.0) -> SensorContact:
	var c := SensorContact.new()
	c.target = u
	c.observer = null
	c.bearing_only = true
	c.bearing_key = key
	c.bearing_origin = origin
	c.bearing_accuracy_deg = accuracy
	c.bearing_range_limit_nm = 200.0
	c.bearing_speed_limit_kn = 1200.0
	var bearing := Geo.bearing_deg(origin, at) + rng.randfn(0.0, accuracy)
	c.error_axis_deg = bearing
	c.range_nm = 30.0
	c.position = origin + Geo.heading_to_vector(bearing) * 30.0
	c.error_major_nm = 15.0
	c.error_minor_nm = 1.0
	c.altitude_m = 6000.0
	c.source = "esm"
	return c


## One listener hears the jet throughout; the other only in short bursts, the way a second ship's
## intercept comes and goes at the edge of its reach, until from `steady_from` it is held on a set
## good to `late_accuracy`. Returns per-second samples of [solution text, plot, truth, claimed
## error, solution quality] from the first second.
func _bursts(seconds: int, burst_every: int, burst_s: int, steady_from: int, late_accuracy := 1.0) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var tm := TrackManager.new()
	var u := _jet()
	var out := []
	for second in range(1, seconds + 1):
		var at := _jet_at(second)
		var now := float(second)
		tm.observe_contact("BLUE", _intercept(u, LISTENER_A, at, "a", rng), now, 1.0)
		var b_hears := second <= 60 or second >= steady_from or (second > 200 and (second - 200) % burst_every < burst_s)
		if b_hears:
			tm.observe_contact("BLUE", _intercept(u, LISTENER_B, at, "b", rng, late_accuracy if second >= steady_from else 1.0), now, 1.0)
		tm.tick(now, 1.0)
		var t := tm.find_track("BLUE", u)
		out.append([t.solution_text(), t.position, at, t.position_error_nm, t.tma_quality])
	tm.free()
	return out


func test_crossed_intercepts_that_come_and_go_do_not_toggle_the_plot() -> void:
	var samples := _bursts(1100, 130, 4, 1000)
	assert_eq(samples[59][0], "ESTIMATED FIX", "two listeners together fix the jet")
	var changes := 0
	for i in range(1, 1000):
		if samples[i][0] != samples[i - 1][0]:
			changes += 1
	assert_true(changes <= 2, "a crossing heard for a few seconds at a time does not swap the plot between a fix and a line (%d changes)" % changes)
	assert_eq(samples[-1][0], "ESTIMATED FIX", "a crossing that stands is taken again")


## The second listener comes back for good soon after the range was given up, on a poorer set, so
## the new crossing is a loose one: no better than what the plot still carries.
func test_a_range_given_up_or_taken_back_owns_up_to_where_the_plot_may_be() -> void:
	var samples := _bursts(700, 130, 4, 340, 4.0)
	var worst_step := 0.0
	var worst_over := 0.0
	var at_drop := ""
	for i in range(1, samples.size()):
		var plot: Vector2 = samples[i][1]
		var truth: Vector2 = samples[i][2]
		var claimed: float = samples[i][3]
		if i >= 120:
			worst_step = maxf(worst_step, plot.distance_to(samples[i - 1][1]))
		worst_over = maxf(worst_over, plot.distance_to(truth) - claimed)
		if at_drop == "" and samples[i - 1][0] == "ESTIMATED FIX" and samples[i][0] == "BEARING ONLY":
			at_drop = "%.1f -> %.1f nm, truth %.1f nm off" % [samples[i - 1][3], claimed, plot.distance_to(truth)]
			assert_true(claimed >= float(samples[i - 1][3]), "giving the range up does not shrink the ellipse (%s)" % at_drop)
	assert_true(at_drop != "", "the range was given up while only one listener heard the jet")
	assert_eq(samples[-1][0], "ESTIMATED FIX", "the loose crossing is taken once it has stood")
	# A 300 kn jet covers 0.08 nm a second; the plot may close on a new answer at three times that.
	assert_true(worst_step < 0.5, "the plot never leaps to a new answer (worst %.1f nm in a second)" % worst_step)
	assert_true(worst_over < 1.0, "the jet is always inside what the plot claims (worst %.1f nm outside)" % worst_over)


# --- A passive range after the contact turns ----------------------------------------------------

## One boat listening to a submarine, zigzagging to range it. The submarine holds a course for ten
## minutes, then turns away and sprints. Returns the worst ratio, over the quarter hour after the
## turn, of how far the plot is from the submarine to the error it claims while it claims a range,
## and how many seconds it claimed one.
func _listen_through_a_turn(seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var tm := TrackManager.new()
	var u := _jet()
	u.spec.domain = "subsurface"
	var own := Vector2.ZERO
	var target := Vector2(2.0, 7.0)
	var course := 80.0
	var worst := 0.0
	var ranged := 0
	for second in range(1, 1800):
		if second % 240 == 0:
			course = 200.0 if course < 180.0 else 80.0
		own += Geo.heading_to_vector(course) * Geo.knots_to_nm_per_s(6.0)
		var leg := Geo.heading_to_vector(0.0) * Geo.knots_to_nm_per_s(20.0) if second < 600 else Geo.heading_to_vector(270.0) * Geo.knots_to_nm_per_s(10.0)
		target += leg
		var c := SensorContact.new()
		c.target = u
		c.bearing_only = true
		c.bearing_key = "boat"
		c.bearing_origin = own
		c.bearing_accuracy_deg = 1.6
		c.bearing_range_limit_nm = 30.0
		c.bearing_speed_limit_kn = 70.0
		c.error_axis_deg = Geo.bearing_deg(own, target) + rng.randfn(0.0, 1.6)
		c.range_nm = 6.0
		c.position = own + Geo.heading_to_vector(c.error_axis_deg) * 6.0
		c.error_major_nm = 6.0
		c.error_minor_nm = 0.3
		c.source = "sonar_passive"
		tm.observe_contact("BLUE", c, float(second), 1.0)
		tm.tick(float(second), 1.0)
		var t := tm.find_track("BLUE", u)
		if second > 660 and not t.is_bearing_only():
			ranged += 1
			worst = maxf(worst, t.position.distance_to(target) / maxf(t.position_error_nm, 0.01))
	tm.free()
	return [worst, ranged]


func test_a_passive_range_after_the_contact_turns_owns_up_to_its_error() -> void:
	for seed_value in [2, 4, 8]:
		var result := _listen_through_a_turn(seed_value)
		assert_true(float(result[0]) <= 3.0, "seed %d: a range held after the turn is never further off than three times the error it claims (worst %.1f times, %d s ranged)" % [seed_value, result[0], result[1]])


# --- Identity: a look, the weather and the commander's own word ---------------------------------

const SCENARIO_PATH := "user://test_fix_sensors_v.json"
const BURKE := "usn_ddg_arleigh_burke_iia"
const GORSHKOV := "rfn_ffg_admiral_gorshkov"
const SU34 := "rfn_strike_su34"

var _sim: Simulation


func _load(units: Array, environment := {"sea_state": 2, "visibility_nm": 10}) -> Simulation:
	var scenario := {
		"id": "fix_sensors_v", "name": "FIXTURE", "seed": 7, "player_faction": "BLUE",
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


func _ship(platform: String, callsign: String, faction: String, at: Array, radar: bool) -> Dictionary:
	return {"platform": platform, "callsign": callsign, "faction": faction, "position_nm": at, "heading_deg": 0, "speed_kn": 0, "radar_on": radar, "air_wing": []}


func _run(seconds: float) -> void:
	for i in int(seconds * 4.0):
		SimClock.advance(0.25)


func test_the_commander_designates_a_contact_and_his_call_stands() -> void:
	_load([_ship(BURKE, "Burke", "BLUE", [0, 0], true), _ship(GORSHKOV, "Gorshkov", "RED", [20, 0], true)])
	var burke := _unit("Burke")
	var frigate := _unit("Gorshkov")
	_run(3.0)
	var t := _sim.track_manager.find_track("BLUE", frigate)
	assert_true(t != null and t.identity == "UNKNOWN", "a radar plot alone says nothing of whose she is")
	if t == null:
		_free()
		return
	assert_true(_sim.unit_manager.issue_order(burke, Order.designate(t, "NEUTRAL")), "the designation is taken")
	assert_eq(t.identity, "NEUTRAL")
	assert_eq(t.identity_evidence, "Commander's designation", "the track file says whose call it was")
	# A close look would read her colours; the commander's call is not overruled by it.
	frigate.position = burke.position + Vector2(0.5, 0.0)
	_run(3.0)
	assert_eq(t.identity, "NEUTRAL", "nothing a sensor says later changes the commander's call")
	assert_true(_sim.unit_manager.issue_order(burke, Order.designate(t, "HOSTILE")), "he may change his mind")
	assert_eq(t.identity, "HOSTILE")
	assert_true(not _sim.unit_manager.issue_order(burke, Order.designate(t, "PROBABLY")), "an identity that is not one is refused")
	assert_true(_sim.unit_manager.issue_order(burke, Order.designate(t, "UNKNOWN")), "and he may withdraw it")
	_run(3.0)
	assert_eq(t.identity, "HOSTILE", "after which the look alongside says what she is")
	assert_eq(t.identity_evidence, "Visual markings")
	var theirs := _sim.track_manager.find_track("RED", burke)
	if theirs != null:
		assert_true(not _sim.unit_manager.issue_order(burke, Order.designate(theirs, "FRIENDLY")), "no one designates the other side's contacts")
	_free()


func _sight(environment: Dictionary, altitude_m: float, offset_nm: float) -> Track:
	_load([_ship(BURKE, "Burke", "BLUE", [0, 0], false),
		{"platform": SU34, "callsign": "Fullback", "faction": "RED", "position_nm": [60, 0], "heading_deg": 270, "speed_kn": 480, "radar_on": false, "altitude_m": altitude_m}], environment)
	_run(1.0)
	var jet := _unit("Fullback")
	var ship := _unit("Burke")
	jet.position = ship.position + Vector2(offset_nm, 0.0)
	jet.altitude_m = altitude_m
	jet.ordered_altitude_m = altitude_m
	_sim.sensor_manager.run_cycle(SimClock.sim_time)
	return _sim.track_manager.find_track("BLUE", jet)


func test_a_look_at_the_limit_gives_a_class_and_only_a_close_one_gives_colours() -> void:
	var clear := {"sea_state": 2, "visibility_nm": 10, "cloud_cover": 0.1}
	var t := _sight(clear, 1500.0, 2.4)
	assert_true(t != null and t.classification >= Track.Classification.CLASS_KNOWN, "a jet near the limit of the eye is recognised by type")
	if t != null:
		assert_eq(t.identity, "UNKNOWN", "one look at the limit does not read whose she is")
	_free()
	t = _sight(clear, 300.0, 0.8)
	assert_true(t != null and t.identity == "HOSTILE" and t.identity_evidence == "Visual markings", "close to, her markings are read")
	_free()


func test_overcast_hides_an_aircraft_above_the_cloud_from_the_lookout() -> void:
	var overcast := {"sea_state": 2, "visibility_nm": 10, "cloud_cover": 0.9, "cloud_base_m": 900}
	var t := _sight(overcast, 1500.0, 0.6)
	assert_true(t == null or t.classification < Track.Classification.CLASS_KNOWN, "a jet above an overcast at 900 m is not seen from the bridge")
	_free()
	t = _sight(overcast, 300.0, 0.6)
	assert_true(t != null and t.classification >= Track.Classification.CLASS_KNOWN, "one under the cloud is")
	_free()
	t = _sight({"sea_state": 2, "visibility_nm": 10, "cloud_cover": 0.2, "cloud_base_m": 900}, 1500.0, 0.6)
	assert_true(t != null and t.classification >= Track.Classification.CLASS_KNOWN, "scattered cloud hides nothing for long")
	_free()


func test_the_contact_menu_offers_each_designation_as_an_order() -> void:
	var t := Track.new()
	t.id = "T1"
	t.owner_faction = "BLUE"
	var items := CdsMenus.designate_items(t)
	assert_eq(items.size(), 4, "hostile, neutral, friendly or unknown")
	var named := []
	for entry: Dictionary in items:
		var order: Order = entry["action"]["order"]
		assert_eq(order.type, Order.Type.DESIGNATE)
		assert_eq(order.track, t)
		named.append(order.designation)
	assert_eq(named, ["HOSTILE", "NEUTRAL", "FRIENDLY", "UNKNOWN"])


func test_a_lookout_who_keeps_a_ship_in_sight_reads_her_colours_in_time() -> void:
	_load([_ship(BURKE, "Burke", "BLUE", [0, 0], false), _ship(GORSHKOV, "Gorshkov", "RED", [4.5, 0], false)], {"sea_state": 2, "visibility_nm": 10, "cloud_cover": 0.1})
	var frigate := _unit("Gorshkov")
	_run(2.0)
	var t := _sim.track_manager.find_track("BLUE", frigate)
	assert_true(t != null and t.classification >= Track.Classification.CLASS_KNOWN, "a frigate at four and a half miles is recognised by eye")
	if t != null:
		assert_eq(t.identity, "UNKNOWN", "but a first look does not read her ensign")
		_run(25.0)
		assert_eq(t.identity, "HOSTILE", "kept in the glasses, it does")
		assert_eq(t.known_callsign, "", "though not her name from there")
	_free()
