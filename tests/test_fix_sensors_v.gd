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
