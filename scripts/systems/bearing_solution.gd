class_name BearingSolution
extends RefCounted
## Bearings-only tracking. Intersect independent simultaneous lines, or fit constant target
## motion after the observer has changed its track. Never reads a target or its hidden range.
## Values are deliberately conservative game estimates, not an operational fire-control model.

const WINDOW_S := 900.0
const SAMPLE_INTERVAL_S := 10.0
const MAX_SAMPLES := 144
const MIN_BASELINE_NM := 0.25
const MIN_CROSSING_SINE := 0.15


static func add(history: Array, c: SensorContact, now: float) -> void:
	if c.bearing_key == "":
		return
	var report := {"key": c.bearing_key, "origin": c.bearing_origin,
		"bearing": c.error_axis_deg, "sigma": maxf(c.bearing_accuracy_deg, 0.1),
		"limit": c.bearing_range_limit_nm, "speed_limit": c.bearing_speed_limit_kn, "time": now}
	# Replace a recent sample from the same observer: a rapid sensor refresh is not a new
	# baseline. Keep the window bounded for both simulation cost and saved engagements.
	for i in range(history.size() - 1, -1, -1):
		if history[i]["key"] == c.bearing_key:
			if now - float(history[i]["time"]) < SAMPLE_INTERVAL_S:
				# Preserve regular history samples, but carry the latest bearing separately below.
				if now - float(history[i].get("sample_start", history[i]["time"])) < SAMPLE_INTERVAL_S:
					report["sample_start"] = history[i].get("sample_start", history[i]["time"])
					history[i] = report
					return
			break
	history.append(report)
	while not history.is_empty() and (now - float(history[0]["time"]) > WINDOW_S or history.size() > MAX_SAMPLES):
		history.pop_front()


static func estimate(history: Array, now: float) -> Dictionary:
	var current := []
	for report: Dictionary in history:
		if now - float(report["time"]) <= 2.0:
			current.append(report)
	var crossed := _crossed_fix(current)
	if not crossed.is_empty():
		return crossed
	if history.size() < 12 or now - float(history[0]["time"]) < 120.0:
		return {}
	# Straight, constant-speed own motion cannot separate unknown target velocity and range.
	# The four-unknown fit is only attempted after a useful departure from that baseline.
	if _observer_manoeuvre(history) < 0.15:
		return {}
	return _fit(history, now, true)


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


static func _fit(reports: Array, now: float, motion: bool) -> Dictionary:
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
	if not position.is_finite() or velocity.length() * 3600.0 > float(reports[-1].get("speed_limit", 70.0)):
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
	if quality < 0.6:
		return {}
	var axis_rad := 0.5 * atan2(2.0 * b, a - d)
	return {"position": position, "velocity": velocity, "major": major, "minor": minor,
		"axis": Geo.vector_to_heading(Vector2(cos(axis_rad), sin(axis_rad))), "quality": quality}


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
