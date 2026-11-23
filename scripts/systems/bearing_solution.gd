class_name BearingSolution
extends RefCounted
## Bearings-only tracking. Intersect independent simultaneous lines, fit constant target motion
## after the observer has changed its track, or range on the change of bearing rate across an
## observer's turn. Never reads a target or its hidden range.
## Values are deliberately conservative game estimates, not an operational fire-control model.

const WINDOW_S := 900.0
const SAMPLE_INTERVAL_S := 10.0
const MAX_SAMPLES := 144
const MIN_BASELINE_NM := 0.25
const MIN_CROSSING_SINE := 0.15
## The poorest solution worth reporting at all. The plot decides what it does with one.
const MIN_QUALITY := 0.2
## A contact that may be faster than this cannot be fitted with one steady course and speed over
## minutes of bearings: an aircraft turns inside the fit. It is fixed by simultaneous lines only.
const SHIP_SPEED_LIMIT_KN := 70.0
## How hard a new bearing pulls the reported line, and the gap after which the line starts afresh.
const SMOOTH_GAIN := 0.25
const SMOOTH_GAP_S := 5.0
## Averaging the looks inside one sample cannot beat a set's systematic error.
const SAMPLE_SIGMA_FLOOR_DEG := 0.3
## Bearing-rate ranging: the shortest leg worth a rate, and how alike two velocities are to be one
## leg and how far apart to be two.
const REFINE_PASSES := 4
## The refinement is started again from this many times the first answer's range, or half the
## reach the contact was heard at if that is further, along the newest bearing. Where both
## starts settle apart and fit about equally (within two standard deviations), the bearings do
## not say which, and the answer is no better than the distance between them.
const FAR_START_FACTOR := 3.0
const AMBIGUITY_ALLOWANCE := 4.0
## One standard deviation of a ship's speed along each axis, before any bearing says otherwise.
const LIKELY_SPEED_KN := 15.0
const LEG_MIN_S := 80.0
const LEG_MIN_SAMPLES := 5
const LEG_SAME_KN := 1.5
const LEG_CHANGE_KN := 2.0
## A contact's turn shows as this many consecutive looks to one side of a steady-course fit, their
## misses summing beyond this many of their own standard deviations per root look. One chance run
## that long in a quarter-hour of looks at a steady contact is a few in a thousand.
const TURN_RUN_SAMPLES := 8
const TURN_RUN_LIMIT := 4.5


## Files one bearing and returns the stored report. Besides the latest look, a report carries the
## line as smoothed for display ("smooth") and the mean of every look in its ten-second sample
## ("mean_bearing", "mean_origin", "mean_time", "n"), which is what the motion solutions work on.
##
## `latest`, when given, is the caller's index of each listener's newest report in this history
## (key -> report), kept up to date here, so the history is not searched for every look. Pass an
## empty dictionary to have it built from the history on first use.
static func add(history: Array, c: SensorContact, now: float, latest: Variant = null) -> Dictionary:
	if c.bearing_key == "":
		return {}
	var index: Dictionary = latest if latest is Dictionary else {}
	if latest is Dictionary and index.is_empty():
		for entry: Dictionary in history:
			index[entry["key"]] = entry
	# Replace a recent sample from the same observer: a rapid sensor refresh is not a new
	# baseline. Keep the window bounded for both simulation cost and saved engagements.
	var prev: Dictionary = index.get(c.bearing_key, {}) if latest is Dictionary else _newest(history, c.bearing_key)
	var smooth := c.error_axis_deg
	if not prev.is_empty():
		var gap := now - float(prev["time"])
		if gap <= SMOOTH_GAP_S:
			var line := float(prev.get("smooth", prev["bearing"]))
			smooth = fposmod(line + SMOOTH_GAIN * Geo.heading_delta(line, c.error_axis_deg), 360.0)
		# Preserve regular history samples, but carry the latest bearing separately below.
		if gap < SAMPLE_INTERVAL_S and now - float(prev.get("sample_start", prev["time"])) < SAMPLE_INTERVAL_S:
			var sample_start: Variant = prev.get("sample_start", prev["time"])
			var n := int(prev.get("n", 1)) + 1
			var mean := float(prev.get("mean_bearing", prev["bearing"]))
			var mean_origin: Vector2 = prev.get("mean_origin", prev["origin"])
			var mean_time := float(prev.get("mean_time", prev["time"]))
			var mean_bearing := fposmod(mean + Geo.heading_delta(mean, c.error_axis_deg) / n, 360.0)
			var merged_origin := mean_origin + (c.bearing_origin - mean_origin) / n
			var merged_time := mean_time + (now - mean_time) / n
			if not prev.has("mean_time"):
				# A sample saved before the means were kept takes the full layout first, so every
				# sample in a history has its fields in the one order.
				var fresh := _report(c, now, smooth)
				prev.clear()
				prev.merge(fresh)
			# The sample takes the new figures where it stands in the history, in place: most looks
			# land in a sample already open, and this is the sensor cycle's commonest filing.
			prev["origin"] = c.bearing_origin
			prev["bearing"] = c.error_axis_deg
			prev["sigma"] = maxf(c.bearing_accuracy_deg, 0.1)
			prev["limit"] = c.bearing_range_limit_nm
			prev["speed_limit"] = c.bearing_speed_limit_kn
			prev["time"] = now
			prev["smooth"] = smooth
			prev["n"] = n
			prev["mean_bearing"] = mean_bearing
			prev["mean_origin"] = merged_origin
			prev["mean_time"] = merged_time
			prev["sample_start"] = sample_start
			return prev
	var report := _report(c, now, smooth)
	history.append(report)
	index[c.bearing_key] = report
	while not history.is_empty() and (now - float(history[0]["time"]) > WINDOW_S or history.size() > MAX_SAMPLES):
		var gone: Dictionary = history.pop_front()
		if is_same(index.get(gone["key"]), gone):
			index.erase(gone["key"])
	return report


## A new sample holding one look.
static func _report(c: SensorContact, now: float, smooth: float) -> Dictionary:
	return {"key": c.bearing_key, "origin": c.bearing_origin,
		"bearing": c.error_axis_deg, "sigma": maxf(c.bearing_accuracy_deg, 0.1),
		"limit": c.bearing_range_limit_nm, "speed_limit": c.bearing_speed_limit_kn, "time": now,
		"smooth": smooth, "n": 1, "mean_bearing": c.error_axis_deg,
		"mean_origin": c.bearing_origin, "mean_time": now}


## The newest report from this listener, or an empty dictionary.
static func _newest(history: Array, key: String) -> Dictionary:
	for i in range(history.size() - 1, -1, -1):
		if history[i]["key"] == key:
			return history[i]
	return {}


## `speed_limit_kn` is the fastest the contact is believed able to go; below zero it is taken from
## the newest report. Nothing at all for a contact that cannot move: every line ever taken on a
## fixed site crosses at it.
static func estimate(history: Array, now: float, speed_limit_kn := -1.0) -> Dictionary:
	if history.is_empty():
		return {}
	# Lines taken together are crossed as the plot draws them, smoothed: a fix from two raw looks
	# a hundred miles off would leap about by more than the contact can move.
	# Samples are filed in the order they were started, so nothing before the first one started
	# more than two sample intervals ago can still be current.
	var current := PackedInt32Array()
	for i in range(history.size() - 1, -1, -1):
		var report: Dictionary = history[i]
		if now - float(report.get("sample_start", report["time"])) > SAMPLE_INTERVAL_S * 2.0:
			break
		if now - float(report["time"]) <= 2.0:
			current.append(i)
	current.reverse()
	var crossed := _crossed_fix_of(history, current)
	if not crossed.is_empty():
		return crossed
	var limit := speed_limit_kn if speed_limit_kn >= 0.0 else float(history[-1].get("speed_limit", SHIP_SPEED_LIMIT_KN))
	if limit > SHIP_SPEED_LIMIT_KN:
		return {}
	var samples := _samples(history)
	if limit <= 0.0:
		return _fit(samples, now, false) if _observer_spread(samples) >= MIN_BASELINE_NM else {}
	if samples.size() < 12 or now - float(samples[0]["time"]) < 120.0:
		return _bearing_rate_range(samples, now, limit)
	# Straight, constant-speed own motion cannot separate unknown target velocity and range.
	# The four-unknown fit is only attempted after a useful departure from that baseline.
	if _observer_manoeuvre(samples) >= 0.15:
		var fitted := _fit(samples, now, true, limit)
		if not fitted.is_empty():
			return fitted
	return _bearing_rate_range(samples, now, limit)


## The history as one averaged look per sample: the same reports, with each one's bearing, origin
## and time replaced by the means of the looks that went into it and its error shrunk to match.
static func _samples(history: Array) -> Array:
	var out := []
	for report: Dictionary in history:
		var n := int(report.get("n", 1))
		if n <= 1:
			out.append(report)
			continue
		var mean := report.duplicate()
		mean["bearing"] = report["mean_bearing"]
		mean["origin"] = report["mean_origin"]
		mean["time"] = report["mean_time"]
		mean["sigma"] = maxf(float(report["sigma"]) / sqrt(float(n)), minf(SAMPLE_SIGMA_FLOOR_DEG, float(report["sigma"])))
		out.append(mean)
	return out


## The widest separation between any two places a bearing was taken from.
static func _observer_spread(reports: Array) -> float:
	var spread := 0.0
	if reports.is_empty():
		return spread
	var first: Vector2 = reports[0]["origin"]
	for report: Dictionary in reports:
		spread = maxf(spread, first.distance_to(report["origin"]))
	return spread


## A fix from lines taken together: the history's current reports, picked out by index, each line
## as smoothed, crossed where at least two listeners apart see it at a useful angle. It is reworked
## for every look at something that may be an aircraft, so it reads the reports where they stand
## rather than copying each one, and solves its two unknowns with the same operations, in the same
## order, as _fit(reports, newest time, false) and _inverse: the same answer to the last bit.
static func _crossed_fix_of(history: Array, current: PackedInt32Array) -> Dictionary:
	var count := current.size()
	if count < 2:
		return {}
	var keys: Array = []
	var origins := PackedVector2Array()
	var bearings := PackedFloat64Array()
	keys.resize(count)
	origins.resize(count)
	bearings.resize(count)
	for k in count:
		var report: Dictionary = history[current[k]]
		keys[k] = report["key"]
		origins[k] = report["origin"]
		bearings[k] = float(report.get("smooth", report["bearing"]))
	var good_geometry := false
	for i in count:
		for j in range(i + 1, count):
			if keys[i] == keys[j] or origins[i].distance_to(origins[j]) < MIN_BASELINE_NM:
				continue
			if absf(sin(deg_to_rad(bearings[i] - bearings[j]))) >= MIN_CROSSING_SINE:
				good_geometry = true
				break
		if good_geometry:
			break
	if not good_geometry:
		return {}
	# _fit(reports, newest time, false): the normal equations of the lines' perpendiculars.
	var directions := PackedVector2Array()
	directions.resize(count)
	var a00 := 0.0
	var a01 := 0.0
	var a10 := 0.0
	var a11 := 0.0
	var r0 := 0.0
	var r1 := 0.0
	for k in count:
		var dir := Geo.heading_to_vector(bearings[k])
		directions[k] = dir
		var n := Vector2(-dir.y, dir.x)
		var nx: float = n.x
		var ny: float = n.y
		var value: float = n.dot(origins[k])
		r0 += nx * value
		a00 += nx * nx
		a01 += nx * ny
		r1 += ny * value
		a10 += ny * nx
		a11 += ny * ny
	# _inverse on [[a00, a01 | 1, 0], [a10, a11 | 0, 1]], Gauss-Jordan with partial pivoting.
	var m := [[a00, a01, 1.0, 0.0], [a10, a11, 0.0, 1.0]]
	for col in 2:
		var pivot := col
		if col == 0 and absf(float(m[1][0])) > absf(float(m[0][0])):
			pivot = 1
		if absf(float(m[pivot][col])) < 0.000001:
			return {}
		var swap: Array = m[col]
		m[col] = m[pivot]
		m[pivot] = swap
		var divisor: float = m[col][col]
		var top: Array = m[col]
		for j in 4:
			top[j] /= divisor
		var other: Array = m[1 - col]
		var scale: float = other[col]
		for j in 4:
			other[j] -= scale * float(top[j])
	var i00: float = m[0][2]
	var i01: float = m[0][3]
	var i10: float = m[1][2]
	var i11: float = m[1][3]
	var s0 := 0.0
	s0 += i00 * r0
	s0 += i01 * r1
	var s1 := 0.0
	s1 += i10 * r0
	s1 += i11 * r1
	var position := Vector2(s0, s1)
	var newest: Dictionary = history[current[count - 1]]
	var fastest := float(newest.get("speed_limit", SHIP_SPEED_LIMIT_KN))
	if not position.is_finite() or 0.0 > fastest:
		return {}
	var variance := 0.0
	var residual := 0.0
	var mean_range := 0.0
	for k in count:
		var report: Dictionary = history[current[k]]
		var delta: Vector2 = position - origins[k]
		var dir := directions[k]
		var along: float = delta.dot(dir)
		if along <= 0.1 or along > float(report["limit"]) * 1.5:
			return {}
		mean_range += along
		variance += pow(maxf(along * tan(deg_to_rad(float(report["sigma"]))), 0.01), 2.0)
		residual += pow(delta.cross(dir), 2.0)
	mean_range /= count
	variance = maxf(variance / count, residual / maxf(count - 2, 1)) * 1.0
	var a := i00 * variance
	var b := i01 * variance
	var d := i11 * variance
	var root := sqrt(maxf(pow(a - d, 2.0) + 4.0 * b * b, 0.0))
	var major := maxf(maxf(2.0 * sqrt(maxf((a + d + root) * 0.5, 0.0)), 0.2), 0.0)
	var minor := maxf(2.0 * sqrt(maxf((a + d - root) * 0.5, 0.0)), 0.1)
	var quality := clampf(1.0 - major / maxf(mean_range * 0.5, 0.5), 0.0, 0.95)
	if quality < MIN_QUALITY:
		return {}
	var axis_rad := 0.5 * atan2(2.0 * b, a - d)
	return {"position": position, "velocity": Vector2.ZERO, "major": major, "minor": minor,
		"axis": Geo.vector_to_heading(Vector2(cos(axis_rad), sin(axis_rad))), "quality": quality}


static func _observer_manoeuvre(reports: Array) -> float:
	var by_observer := {}
	for report: Dictionary in reports:
		var key: String = report["key"]
		if not by_observer.has(key):
			by_observer[key] = []
		by_observer[key].append(report)
	var bend := 0.0
	for samples: Array in by_observer.values():
		if samples.size() < 3:
			continue
		var first: Dictionary = samples[0]
		var last: Dictionary = samples[-1]
		var span := float(last["time"]) - float(first["time"])
		if span < 120.0:
			continue
		for sample: Dictionary in samples:
			var fraction := (float(sample["time"]) - float(first["time"])) / span
			var straight: Vector2 = (first["origin"] as Vector2).lerp(last["origin"], fraction)
			bend = maxf(bend, straight.distance_to(sample["origin"]))
	return bend


static func _fit(reports: Array, now: float, motion: bool, speed_limit_kn := -1.0) -> Dictionary:
	var dim := 4 if motion else 2
	var normal := []
	var rhs := []
	for i in dim:
		normal.append([])
		rhs.append(0.0)
		for j in dim:
			normal[i].append(0.0)
	# Normalize the time term to keep Gaussian elimination well conditioned.
	for report: Dictionary in reports:
		var dir := Geo.heading_to_vector(float(report["bearing"]))
		var n := Vector2(-dir.y, dir.x)
		var tau := (float(report["time"]) - now) / WINDOW_S
		var row := [n.x, n.y, n.x * tau, n.y * tau]
		var value := n.dot(report["origin"])
		for i in dim:
			rhs[i] += row[i] * value
			for j in dim:
				normal[i][j] += row[i] * row[j]
	var inverse := _inverse(normal)
	if inverse.is_empty():
		return {}
	var state := []
	for i in dim:
		var value := 0.0
		for j in dim:
			value += float(inverse[i][j]) * float(rhs[j])
		state.append(value)
	var spread := -1.0
	var ambiguity := 0.0
	if motion:
		# The straight-line fit weighs every look alike and reads short when the bearings are noisy
		# for the geometry, and a contact close by and fast can fit thin geometry as well as one
		# far off and slow. Refine from the first answer and from well beyond it.
		var anchor: Vector2 = reports[-1]["origin"]
		var near := _refine(reports, now, state)
		var first := Vector2(float(state[0]), float(state[1])) - anchor
		var beyond := Geo.heading_to_vector(float(reports[-1]["bearing"])) * maxf(first.length() * FAR_START_FACTOR, float(reports[-1]["limit"]) * 0.5)
		var far := _refine(reports, now, [anchor.x + beyond.x, anchor.y + beyond.y, 0.0, 0.0])
		var far_wins := near.is_empty() or (not far.is_empty() and float(far["misfit"]) < float(near["misfit"]))
		var chosen := far if far_wins else near
		var other := near if far_wins else far
		if chosen.is_empty():
			return {}
		state = chosen["state"]
		inverse = chosen["covariance"]
		spread = chosen["spread"]
		if not other.is_empty() and float(other["misfit"]) - float(chosen["misfit"]) <= AMBIGUITY_ALLOWANCE * maxf(spread, 1.0):
			ambiguity = Vector2(float(state[0]) - float(other["state"][0]), float(state[1]) - float(other["state"][1])).length()
	var position := Vector2(state[0], state[1])
	var velocity := Vector2(state[2], state[3]) / WINDOW_S if motion else Vector2.ZERO
	var fastest := speed_limit_kn if speed_limit_kn >= 0.0 else float(reports[-1].get("speed_limit", SHIP_SPEED_LIMIT_KN))
	if not position.is_finite() or velocity.length() * 3600.0 > fastest:
		return {}  # do not fabricate a fix for physically inconsistent bearing histories
	if motion and _turned_inside(reports, now, position, velocity):
		return {}
	var variance := 0.0
	var residual := 0.0
	var mean_range := 0.0
	for report: Dictionary in reports:
		var at := position + velocity * (float(report["time"]) - now)
		var delta: Vector2 = at - (report["origin"] as Vector2)
		var dir := Geo.heading_to_vector(float(report["bearing"]))
		var along := delta.dot(dir)
		if along <= 0.1 or along > float(report["limit"]) * 1.5:
			return {}
		mean_range += along
		variance += pow(maxf(along * tan(deg_to_rad(float(report["sigma"]))), 0.01), 2.0)
		residual += pow(delta.cross(dir), 2.0)
	mean_range /= reports.size()
	# Successive bearing errors are correlated; never award unlimited precision for waiting.
	var correlation := maxf(float(reports.size()) / 48.0, 1.0) if motion else 1.0
	variance = maxf(variance / reports.size(), residual / maxf(reports.size() - dim, 1)) * correlation
	if spread >= 0.0:
		# The refined fit's own covariance, widened if the looks scatter more than their sets say.
		variance = maxf(spread, 1.0) * correlation
	var a := float(inverse[0][0]) * variance
	var b := float(inverse[0][1]) * variance
	var d := float(inverse[1][1]) * variance
	var root := sqrt(maxf(pow(a - d, 2.0) + 4.0 * b * b, 0.0))
	var major := maxf(maxf(2.0 * sqrt(maxf((a + d + root) * 0.5, 0.0)), 0.2), ambiguity)
	var minor := maxf(2.0 * sqrt(maxf((a + d - root) * 0.5, 0.0)), 0.1)
	var quality := clampf(1.0 - major / maxf(mean_range * 0.5, 0.5), 0.0, 0.95)
	if quality < MIN_QUALITY:
		return {}
	var axis_rad := 0.5 * atan2(2.0 * b, a - d)
	return {"position": position, "velocity": velocity, "major": major, "minor": minor,
		"axis": Geo.vector_to_heading(Vector2(cos(axis_rad), sin(axis_rad))), "quality": quality}


## Whether the contact cannot have held one course and speed through these bearings: a run of
## consecutive looks all falling to one side of the fitted track by more than chance allows. A
## nearer, slower contact on a steady course explains almost any turn by a further one about as
## well, so the fit's own spread says nothing of it, and the range it gives, and the small
## ellipse that comes with it, are an artefact of the turn. A crew that sees the bearing drift
## break away from its solution starts the solution again; until the turn has left the window
## there is none.
static func _turned_inside(reports: Array, now: float, position: Vector2, velocity: Vector2) -> bool:
	if reports.size() < TURN_RUN_SAMPLES:
		return false
	var misses := PackedFloat64Array()
	for report: Dictionary in reports:
		var at := position + velocity * (float(report["time"]) - now)
		misses.append(Geo.heading_delta(Geo.bearing_deg(report["origin"], at), float(report["bearing"])) / maxf(float(report["sigma"]), 0.1))
	var run := 0.0
	for i in misses.size():
		run += misses[i]
		if i >= TURN_RUN_SAMPLES:
			run -= misses[i - TURN_RUN_SAMPLES]
		if i >= TURN_RUN_SAMPLES - 1 and absf(run) > TURN_RUN_LIMIT * sqrt(float(TURN_RUN_SAMPLES)):
			return true
	return false


## Range from the change in bearing rate across the listener's last change of course or speed.
## On each steady leg the bearing drifts at (target minus own velocity across the line) over the
## range; the target's share is the same on both, so the difference in rate is the difference in
## own velocity over the range. Solved as the steady-target fit through those two legs alone, so
## it needs a few minutes either side of one turn, not a long history, and does not care what the
## target did before them.
static func _bearing_rate_range(samples: Array, now: float, speed_limit_kn := -1.0) -> Dictionary:
	if samples.is_empty():
		return {}
	var key: String = samples[-1]["key"]
	var own := []
	for report: Dictionary in samples:
		if report["key"] == key:
			own.append(report)
	if own.size() < 2 * LEG_MIN_SAMPLES or now - float(own[-1]["time"]) > SAMPLE_INTERVAL_S * 2.0:
		return {}
	var later := _leg_ending_at(own, own.size() - 1)
	if later.is_empty():
		return {}
	# Skip the turn itself: step back until the listener is steady again on a different velocity.
	var end := int(later["first"]) - 1
	while end >= LEG_MIN_SAMPLES - 1:
		var earlier := _leg_ending_at(own, end)
		if not earlier.is_empty() and ((earlier["velocity"] as Vector2) - (later["velocity"] as Vector2)).length() * 3600.0 >= LEG_CHANGE_KN:
			return _fit(own.slice(int(earlier["first"])), now, true, speed_limit_kn)
		end -= 1
	return {}


## The steady leg that ends at sample `last`: the longest run back from it over which the listener
## held one velocity. Empty when too short.
static func _leg_ending_at(own: Array, last: int) -> Dictionary:
	if last < 1:
		return {}
	var first := last
	var velocity := Vector2.ZERO
	while first > 0:
		var a: Dictionary = own[first - 1]
		var b: Dictionary = own[first]
		var step := float(b["time"]) - float(a["time"])
		if step <= 0.0 or step > SAMPLE_INTERVAL_S * 3.0:
			break
		var v: Vector2 = ((b["origin"] as Vector2) - (a["origin"] as Vector2)) / step
		if first == last:
			velocity = v
		elif (v - velocity).length() * 3600.0 > LEG_SAME_KN:
			break
		first -= 1
	var n := last - first + 1
	var span := float(own[last]["time"]) - float(own[first]["time"])
	if n < LEG_MIN_SAMPLES or span < LEG_MIN_S:
		return {}
	velocity = ((own[last]["origin"] as Vector2) - (own[first]["origin"] as Vector2)) / span
	return {"first": first, "last": last, "velocity": velocity}


## A few passes on the bearings themselves, each weighed by its own error, with what is known of
## ships (they are seldom fast) to settle what thin geometry leaves open. Returns the state, its
## covariance, how badly it misses and how far the looks scatter about it relative to their stated
## errors; empty if it falls apart.
static func _refine(reports: Array, now: float, start: Array) -> Dictionary:
	var state := start.duplicate()
	var inverse := []
	var chi := 0.0
	var prior := 1.0 / pow(Geo.knots_to_nm_per_s(LIKELY_SPEED_KN) * WINDOW_S, 2.0)
	for pass_index in REFINE_PASSES + 1:
		var normal := []
		var rhs := [0.0, 0.0, 0.0, 0.0]
		for i in 4:
			normal.append([0.0, 0.0, 0.0, 0.0])
		chi = 0.0
		for report: Dictionary in reports:
			var tau := (float(report["time"]) - now) / WINDOW_S
			var delta: Vector2 = Vector2(float(state[0]) + float(state[2]) * tau, float(state[1]) + float(state[3]) * tau) - (report["origin"] as Vector2)
			var distance := delta.length()
			if distance < 0.05:
				return {}
			var sight := delta / distance
			var miss := asin(clampf(sight.cross(Geo.heading_to_vector(float(report["bearing"]))), -1.0, 1.0))
			var weight := 1.0 / pow(deg_to_rad(float(report["sigma"])), 2.0)
			var turn := Vector2(-sight.y, sight.x) / distance
			var row := [turn.x, turn.y, turn.x * tau, turn.y * tau]
			chi += weight * miss * miss
			for i in 4:
				rhs[i] += weight * row[i] * miss
				for j in 4:
					normal[i][j] += weight * row[i] * row[j]
		for i in [2, 3]:
			normal[i][i] += prior
			rhs[i] -= prior * float(state[i])
		inverse = _inverse(normal)
		if inverse.is_empty():
			return {}
		if pass_index == REFINE_PASSES:
			break  # the last pass only measures the fit it has arrived at
		for i in 4:
			for j in 4:
				state[i] += float(inverse[i][j]) * float(rhs[j])
			if not is_finite(float(state[i])):
				return {}
	var speed := prior * (pow(float(state[2]), 2.0) + pow(float(state[3]), 2.0))
	return {"state": state, "covariance": inverse, "misfit": chi + speed, "spread": chi / maxf(reports.size() - 4, 1)}


static func _inverse(matrix: Array) -> Array:
	var n := matrix.size()
	var rows := []
	for i in n:
		var row: Array = matrix[i].duplicate()
		for j in n:
			row.append(1.0 if i == j else 0.0)
		rows.append(row)
	for col in n:
		var pivot := col
		for i in range(col + 1, n):
			if absf(float(rows[i][col])) > absf(float(rows[pivot][col])):
				pivot = i
		if absf(float(rows[pivot][col])) < 0.000001:
			return []
		var swap: Array = rows[col]
		rows[col] = rows[pivot]
		rows[pivot] = swap
		var divisor: float = rows[col][col]
		for j in 2 * n:
			rows[col][j] /= divisor
		for i in n:
			if i == col:
				continue
			var scale: float = rows[i][col]
			for j in 2 * n:
				rows[i][j] -= scale * rows[col][j]
	var inverse := []
	for row: Array in rows:
		inverse.append(row.slice(n))
	return inverse
