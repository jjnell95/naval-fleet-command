extends TestCase
## Plots on bearings that stay where the evidence put them, passive ranges that own up to what a
## manoeuvre may have done to them, and a small drone a warship's air-search radar can hold.

const SCENARIO_PATH := "user://test_fix_sensors_f.json"

var _sim: Simulation


func _load(units: Array, environment := {"sea_state": 2, "visibility_nm": 10}) -> Simulation:
	var scenario := {
		"id": "fix_sensors_f", "name": "FIXTURE", "seed": 5, "player_faction": "BLUE",
		"map": {"center_nm": [0, 0], "extent_nm": 300}, "environment": environment,
		"objectives": {"text": "", "victory": [{"id": "watch", "type": "time_elapsed", "seconds": 90000, "text": "Keep the watch"}], "loss": []},
		"units": units,
	}
	var f := FileAccess.open(SCENARIO_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(scenario))
	f.close()
	SimClock.set_paused(true)
	_sim = Simulation.new()
	_sim.seed_override = 5
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


func _run(seconds: float) -> void:
	for i in int(seconds * 4.0):
		SimClock.advance(0.25)


const BURKE := "usn_ddg_arleigh_burke_iia"
const MOHAJER := "irn_uav_mohajer6"


# --- A drone on radar ---------------------------------------------------------------------------

## A radiating destroyer and a Mohajer-6 at its cruising height, well inside the reach a
## fourth-root radar law gives a drone of its size and well outside the old 16 nm.
func test_a_radiating_destroyer_holds_a_small_drone_on_radar() -> void:
	for distance: float in [22.0, 40.0]:
		_load([{"platform": BURKE, "callsign": "Defender", "faction": "BLUE", "position_nm": [0, 0], "heading_deg": 0, "speed_kn": 12, "radar_on": true, "air_wing": []},
			{"platform": MOHAJER, "callsign": "Drone", "faction": "RED", "position_nm": [0, distance], "heading_deg": 90, "speed_kn": 90}])
		var drone := _unit("Drone")
		_run(20.0)
		var t := _sim.track_manager.find_track("BLUE", drone)
		assert_true(t != null, "the drone is held at %.0f nm" % distance)
		if t != null:
			assert_true(not t.is_bearing_only() and t.source == "radar", "by radar, with a range, at %.0f nm (source %s, bearing only %s)" % [distance, t.source, t.is_bearing_only()])
			assert_true(t.position.distance_to(drone.position) < 2.0, "where the drone is (%.1f nm off)" % t.position.distance_to(drone.position))
		_free()
	_load([{"platform": BURKE, "callsign": "Defender", "faction": "BLUE", "position_nm": [0, 0], "heading_deg": 0, "speed_kn": 12, "radar_on": true, "air_wing": []},
		{"platform": MOHAJER, "callsign": "Drone", "faction": "RED", "position_nm": [0, 75], "heading_deg": 90, "speed_kn": 90}])
	_run(20.0)
	var far := _sim.track_manager.find_track("BLUE", _unit("Drone"))
	assert_true(far == null or far.source != "radar", "a drone is still a small target: not held by radar at 75 nm")
	_free()


# --- Crossed intercepts on an aircraft ----------------------------------------------------------

func _air_target() -> Unit:
	var u := Unit.new()
	u.spec = PlatformSpec.new()
	u.spec.short_name = "JET"
	u.faction = "RED"
	return u


## One ESM intercept as SensorManager files it: a line from the listener, its nominal length short
## of the aircraft's real range, the plot's first guess part way along it.
func _intercept(u: Unit, origin: Vector2, at: Vector2, key: String, rng: RandomNumberGenerator) -> SensorContact:
	var bearing := Geo.bearing_deg(origin, at) + rng.randfn(0.0, 2.5)
	var c := SensorContact.new()
	c.target = u
	c.bearing_only = true
	c.bearing_key = key
	c.bearing_origin = origin
	c.bearing_accuracy_deg = 2.5
	c.bearing_range_limit_nm = 400.0
	c.bearing_speed_limit_kn = 1200.0
	c.error_axis_deg = bearing
	c.range_nm = 28.0
	c.position = origin + Geo.heading_to_vector(bearing) * 28.0
	c.error_major_nm = 25.5
	c.error_minor_nm = 1.0
	c.source = "esm"
	return c


## A listener has held an aircraft on a bare line for a while when a second, well apart, starts
## hearing it too, and its look comes first in each sensor cycle. The crossing is marginal: an
## estimate looser than the line's nominal ellipse. Once the plot takes the range it keeps it,
## and when the second listener falls silent the plot stays where the range put it.
func test_a_marginal_crossing_on_an_aircraft_neither_flickers_nor_teleports() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var tm := TrackManager.new()
	var u := _air_target()
	var a := Vector2.ZERO
	var b := Vector2(0, 60)
	var jet := Vector2(150, 10)
	var velocity := Geo.heading_to_vector(270.0) * Geo.knots_to_nm_per_s(450.0)
	var t: Track = null
	var first_fix := -1
	var changes := 0
	var worst_leap := 0.0
	var worst_drop_shrink := 0.0
	var worst_drop_miss := 0.0
	var was_fix := false
	var last := Vector2.INF
	var last_error := 0.0
	for second in range(1, 241):
		jet += velocity
		tm.cycle_at = float(second)
		# The plot as the chart shows it after each tick of the cycle, not only once it is complete.
		for look in 2:
			var now := float(second) + 0.25 * look
			if look == 0 and second > 30 and second <= 180:
				tm.observe_contact("BLUE", _intercept(u, b, jet, "b", rng), now, 1.0)
			elif look == 1:
				tm.observe_contact("BLUE", _intercept(u, a, jet, "a", rng), now, 1.0)
				tm.tick(now, 1.0)
			if t == null:
				t = tm.find_track("BLUE", u)
				if t == null:
					continue
				t.domain = "air"
			var fix := not t.is_bearing_only()
			if fix and first_fix < 0:
				first_fix = second
			elif first_fix > 0:
				if fix != was_fix:
					changes += 1
				worst_leap = maxf(worst_leap, last.distance_to(t.position))
				if was_fix and not fix:
					worst_drop_shrink = maxf(worst_drop_shrink, last_error - t.position_error_nm)
					worst_drop_miss = maxf(worst_drop_miss, t.position.distance_to(jet) - t.position_error_nm)
			was_fix = fix
			last = t.position
			last_error = t.position_error_nm
	tm.free()
	assert_true(first_fix > 0, "the crossed intercepts gave the aircraft a range")
	assert_true(changes <= 1, "the plot holds its range until the second listener has been silent a while (changed %d times)" % changes)
	assert_true(worst_leap < 5.0, "after the first range the plot never leaps (worst %.1f nm in a tick)" % worst_leap)
	assert_true(worst_drop_shrink <= 0.0, "giving the range up never shrinks the ellipse (by %.1f nm)" % worst_drop_shrink)
	assert_true(worst_drop_miss <= 0.0, "and the ellipse still covers the aircraft (%.1f nm outside it)" % worst_drop_miss)
