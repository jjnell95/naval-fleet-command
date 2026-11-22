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
## Bearing-rate ranging: the shortest leg worth a rate, how alike two velocities are to be one leg
## and how far apart to be two, and the target speed its range is allowed to drift at afterwards.
const LEG_MIN_S := 80.0
const LEG_MIN_SAMPLES := 5
const LEG_SAME_KN := 1.5
const LEG_CHANGE_KN := 2.0
const RATE_SIGNIFICANCE := 2.5
const RATE_DRIFT_KN := 8.0
const RATE_QUALITY_CAP := 0.7


## Files one bearing and returns the stored report. Besides the latest look, a report carries the
## line as smoothed for display ("smooth") and the mean of every look in its ten-second sample
## ("mean_bearing", "mean_origin", "mean_time", "n"), which is what the motion solutions work on.
static func add(history: Array, c: SensorContact, now: float) -> Dictionary:
	if c.bearing_key == "":
		return {}
	var report := {"key": c.bearing_key, "origin": c.bearing_origin,
		"bearing": c.error_axis_deg, "sigma": maxf(c.bearing_accuracy_deg, 0.1),
		"limit": c.bearing_range_limit_nm, "speed_limit": c.bearing_speed_limit_kn, "time": now,
		"smooth": c.error_axis_deg, "n": 1, "mean_bearing": c.error_axis_deg,
		"mean_origin": c.bearing_origin, "mean_time": now}
	# Replace a recent sample from the same observer: a rapid sensor refresh is not a new
	# baseline. Keep the window bounded for both simulation cost and saved engagements.
	for i in range(history.size() - 1, -1, -1):
		if history[i]["key"] == c.bearing_key:
			var prev: Dictionary = history[i]
			var gap := now - float(prev["time"])
			if gap <= SMOOTH_GAP_S:
				var line := float(prev.get("smooth", prev["bearing"]))
				report["smooth"] = fposmod(line + SMOOTH_GAIN * Geo.heading_delta(line, c.error_axis_deg), 360.0)
			if gap < SAMPLE_INTERVAL_S:
				# Preserve regular history samples, but carry the latest bearing separately below.
				if now - float(prev.get("sample_start", prev["time"])) < SAMPLE_INTERVAL_S:
					report["sample_start"] = prev.get("sample_start", prev["time"])
					var n := int(prev.get("n", 1)) + 1
					var mean := float(prev.get("mean_bearing", prev["bearing"]))
					var mean_origin: Vector2 = prev.get("mean_origin", prev["origin"])
					var mean_time := float(prev.get("mean_time", prev["time"]))
					report["n"] = n
					report["mean_bearing"] = fposmod(mean + Geo.heading_delta(mean, c.error_axis_deg) / n, 360.0)
					report["mean_origin"] = mean_origin + (c.bearing_origin - mean_origin) / n
					report["mean_time"] = mean_time + (now - mean_time) / n
					history[i] = report
					return report
			break
	history.append(report)
	while not history.is_empty() and (now - float(history[0]["time"]) > WINDOW_S or history.size() > MAX_SAMPLES):
		history.pop_front()
	return report


## `speed_limit_kn` is the fastest the contact is believed able to go; below zero it is taken from
## the newest report. Nothing at all for a contact that cannot move: every line ever taken on a
## fixed site crosses at it.
static func estimate(history: Array, now: float, speed_limit_kn := -1.0) -> Dictionary:
	if history.is_empty():
		return {}
	# Lines taken together are crossed as the plot draws them, smoothed: a fix from two raw looks
	# a hundred miles off would leap about by more than the contact can move.
	var current := []
	for report: Dictionary in history:
		if now - float(report["time"]) <= 2.0:
			var line := report.duplicate()
			line["bearing"] = report.get("smooth", report["bearing"])
			current.append(line)
	var crossed := _crossed_fix(current)
	if not crossed.is_empty():
		return crossed
	var limit := speed_limit_kn if speed_limit_kn >= 0.0 else float(history[-1].get("speed_limit", SHIP_SPEED_LIMIT_KN))
	if limit > SHIP_SPEED_LIMIT_KN:
		return {}
	var samples := _samples(history)
	if limit <= 0.0:
		return _fit(samples, now, false) if _observer_spread(samples) >= MIN_BASELINE_NM else {}
	if samples.size() < 12 or now - float(samples[0]["time"]) < 120.0:
		return _bearing_rate_range(samples, now)
	# Straight, constant-speed own motion cannot separate unknown target velocity and range.
	# The four-unknown fit is only attempted after a useful departure from that baseline.
	if _observer_manoeuvre(samples) >= 0.15:
		var fitted := _fit(samples, now, true, limit)
		if not fitted.is_empty():
			return fitted
	return _bearing_rate_range(samples, now)


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


static func _crossed_fix(reports: Array) -> Dictionary:
	if reports.size() < 2:
		return {}
	var good_geometry := false
	for i in reports.size():
		for j in range(i + 1, reports.size()):
			var a: Dictionary = reports[i]
			var b: Dictionary = reports[j]
			if a["key"] == b["key"] or (a["origin"] as Vector2).distance_to(b["origin"]) < MIN_BASELINE_NM:
				continue
			if absf(sin(deg_to_rad(float(a["bearing"]) - float(b["bearing"])))) >= MIN_CROSSING_SINE:
				good_geometry = true
	if not good_geometry:
		return {}
	return _fit(reports, float(reports[-1]["time"]), false)


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
	var position := Vector2(state[0], state[1])
	var velocity := Vector2(state[2], state[3]) / WINDOW_S if motion else Vector2.ZERO
	var fastest := speed_limit_kn if speed_limit_kn >= 0.0 else float(reports[-1].get("speed_limit", SHIP_SPEED_LIMIT_KN))
	if not position.is_finite() or velocity.length() * 3600.0 > fastest:
		return {}  # do not fabricate a fix for physically inconsistent bearing histories
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
	var a := float(inverse[0][0]) * variance
	var b := float(inverse[0][1]) * variance
	var d := float(inverse[1][1]) * variance
	var root := sqrt(maxf(pow(a - d, 2.0) + 4.0 * b * b, 0.0))
	var major := maxf(2.0 * sqrt(maxf((a + d + root) * 0.5, 0.0)), 0.2)
	var minor := maxf(2.0 * sqrt(maxf((a + d - root) * 0.5, 0.0)), 0.1)
	var quality := clampf(1.0 - major / maxf(mean_range * 0.5, 0.5), 0.0, 0.95)
	if quality < MIN_QUALITY:
		return {}
	var axis_rad := 0.5 * atan2(2.0 * b, a - d)
	return {"position": position, "velocity": velocity, "major": major, "minor": minor,
		"axis": Geo.vector_to_heading(Vector2(cos(axis_rad), sin(axis_rad))), "quality": quality}


## Range from the change in bearing rate across the listener's last change of course or speed.
## On each steady leg the bearing drifts at (target minus own velocity across the line) over the
## range; the target's share is the same on both, so the difference in rate is the difference in
## own velocity over the range. It needs two legs of a few minutes, not a long history, and does
## not care what the target did before them.
static func _bearing_rate_range(samples: Array, now: float) -> Dictionary:
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
	var earlier := {}
	var end := int(later["first"]) - 1
	while end >= LEG_MIN_SAMPLES - 1:
		var candidate := _leg_ending_at(own, end)
		if not candidate.is_empty() and ((candidate["velocity"] as Vector2) - (later["velocity"] as Vector2)).length() * 3600.0 >= LEG_CHANGE_KN:
			earlier = candidate
			break
		end -= 1
	if earlier.is_empty():
		return {}
	var turn_time := 0.5 * (float(own[int(earlier["last"])]["time"]) + float(own[int(later["first"])]["time"]))
	var bearing_at_turn := 0.5 * (_leg_bearing(earlier, turn_time) + _leg_bearing(later, turn_time))
	var across := Geo.heading_to_vector(bearing_at_turn + 90.0)
	var rate_change := deg_to_rad(float(later["rate"]) - float(earlier["rate"]))
	var rate_sigma := deg_to_rad(sqrt(pow(float(later["rate_sigma"]), 2.0) + pow(float(earlier["rate_sigma"]), 2.0)))
	if absf(rate_change) < RATE_SIGNIFICANCE * rate_sigma or rate_sigma <= 0.0:
		return {}
	var range_at_turn := ((earlier["velocity"] as Vector2) - (later["velocity"] as Vector2)).dot(across) / rate_change
	var latest: Dictionary = own[-1]
	if range_at_turn <= 0.1 or range_at_turn > float(latest["limit"]) * 1.5:
		return {}
	# Since the turn the listener has opened or closed along the line by its own motion; what the
	# target has done along it is not known and goes into the error instead.
	var since := maxf(now - turn_time, 0.0)
	var line := _leg_bearing(later, now)
	var along := Geo.heading_to_vector(line)
	var range_now := range_at_turn - (later["velocity"] as Vector2).dot(along) * since
	if range_now <= 0.1:
		return {}
	var sigma := range_at_turn * rate_sigma / absf(rate_change)
	var major := maxf(2.0 * sigma, 0.2) + Geo.knots_to_nm_per_s(RATE_DRIFT_KN) * since
	var quality := clampf(1.0 - major / maxf(range_now * 0.5, 0.5), 0.0, RATE_QUALITY_CAP)
	if quality < MIN_QUALITY:
		return {}
	var origin: Vector2 = latest["origin"]
	var target_across := range_at_turn * deg_to_rad(float(later["rate"])) + (later["velocity"] as Vector2).dot(across)
	return {"position": origin + (later["velocity"] as Vector2) * (now - float(latest["time"])) + along * range_now,
		"velocity": across * target_across, "major": major,
		"minor": minf(maxf(range_now * tan(deg_to_rad(float(later["line_sigma"]) * 2.0)), 0.1), major),
		"axis": fposmod(line, 360.0), "quality": quality}


## The steady leg that ends at sample `last`: the longest run back from it over which the listener
## held one velocity, with the straight line fitted through its bearings. Empty when too short.
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
	# Bearings unwrapped about the first, so a leg across north is still a straight line.
	var base := float(own[first]["bearing"])
	var mean_t := 0.0
	var mean_b := 0.0
	var offsets := PackedFloat64Array()
	for i in range(first, last + 1):
		var offset := Geo.heading_delta(base, float(own[i]["bearing"]))
		offsets.append(offset)
		mean_t += float(own[i]["time"])
		mean_b += offset
	mean_t /= n
	mean_b /= n
	var stt := 0.0
	var stb := 0.0
	for i in n:
		var dt := float(own[first + i]["time"]) - mean_t
		stt += dt * dt
		stb += dt * (offsets[i] - mean_b)
	if stt <= 0.0:
		return {}
	var rate := stb / stt  # degrees a second
	var residual := 0.0
	var sigma := 0.0
	for i in n:
		var dt := float(own[first + i]["time"]) - mean_t
		residual += pow(offsets[i] - mean_b - rate * dt, 2.0)
		sigma += pow(float(own[first + i]["sigma"]), 2.0)
	var scatter := sqrt(maxf(residual / maxf(n - 2, 1), sigma / n))
	return {"first": first, "last": last, "velocity": velocity, "rate": rate,
		"rate_sigma": scatter / sqrt(stt), "line_sigma": scatter / sqrt(float(n)),
		"base": base + mean_b, "mean_time": mean_t}


static func _leg_bearing(leg: Dictionary, at: float) -> float:
	return float(leg["base"]) + float(leg["rate"]) * (at - float(leg["mean_time"]))


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
