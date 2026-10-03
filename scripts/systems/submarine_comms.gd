class_name SubmarineComms
extends RefCounted
## Classic command abstraction: a receive-only summons can call a boat to a communication
## window, while detailed orders and reports wait for shallow water. 150 ft is the original
## game's threshold, not a claim about every real antenna. Crews keep their existing task.
const DEPTH_M := 45.72
const WINDOW_S := 60.0
const INTERVALS := [0.0, 3600.0, 7200.0, 14400.0]
const MAX_PENDING := 64


static func restricted(u: Unit) -> bool:
	return u != null and u.spec != null and u.is_submarine() and u.comms_enabled


static func connected(u: Unit) -> bool:
	return not restricted(u) or (u.alive and u.depth_m <= DEPTH_M + 0.01)


static func should_queue(u: Unit, o: Order) -> bool:
	return restricted(u) and not connected(u) and o.origin == "player" and o.type != Order.Type.REQUEST_SUB_CHECKIN


static func initialize(u: Unit, now: float) -> void:
	if u.comms_report.is_empty():
		_report(u, now)  # starting deployment is the commander's last known report
	if u.comms_next_check_s < 0.0 and u.comms_interval_s > 0.0:
		u.comms_next_check_s = now + u.comms_interval_s


static func queue_order(u: Unit, o: Order) -> bool:
	if u.comms_pending.size() >= MAX_PENDING:
		o.receipt = "Submarine order queue full; wait for a check-in."
		o.execution_accepted = false
		return false
	var data := {}
	# Plain dictionaries preserve references through SimSnapshot's existing Unit/Track codec;
	# never store an Order object in a saved engagement. Copy arrays so caller edits cannot
	# silently change an already transmitted instruction.
	for property: Dictionary in o.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var value: Variant = o.get(property["name"])
			data[property["name"]] = value.duplicate(true) if value is Array or value is Dictionary else value
	u.comms_pending.append(data)
	o.receipt = "Queued for submarine check-in · %d pending" % u.comms_pending.size()
	o.execution_accepted = true
	return true


static func take_pending(u: Unit) -> Array[Order]:
	var out: Array[Order] = []
	for data: Dictionary in u.comms_pending:
		var o := Order.new()
		for property: Dictionary in o.get_property_list():
			var key: String = property["name"]
			if not int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE or not data.has(key):
				continue
			var current: Variant = o.get(key)
			if current is Array and data[key] is Array:
				current.assign(data[key])
			else:
				o.set(key, data[key])
		# It remains a player order when delivered, so a new route replaces its old station.
		o.receipt = ""
		out.append(o)
	u.comms_pending.clear()
	return out


static func on_order(u: Unit, o: Order, now: float) -> bool:
	match o.type:
		Order.Type.REQUEST_SUB_CHECKIN:
			initialize(u, now)
			if connected(u):
				_report(u, now)
				o.receipt = "Submarine already at communication depth."
			else:
				_begin(u)
				o.receipt = "Check-in requested; full orders wait for communication depth."
			return true
		Order.Type.SET_SUB_COMMS_INTERVAL:
			u.comms_interval_s = o.comms_interval_s
			u.comms_next_check_s = now + o.comms_interval_s if o.comms_interval_s > 0.0 else -1.0
			o.receipt = "Check-in on demand" if o.comms_interval_s <= 0.0 else "Check-in every %d hours" % int(o.comms_interval_s / 3600.0)
			return true
		Order.Type.SET_DEPTH:
			# A newly received depth instruction wins over the pre-check-in depth.
			if u.comms_phase in ["ascending", "reporting"]:
				u.comms_return_depth_m = clampf(o.depth_m, 0.0, u.spec.max_depth_m)
				o.receipt = "Depth order received; execute after communication window."
				return true
	return false


## Returns orders ready for delivery. UnitManager rechecks current capability and emits the
## normal order signals only when each command is actually delivered to its crew.
static func step(u: Unit, now: float) -> Array[Order]:
	var ready: Array[Order] = []
	if not restricted(u) or not u.alive:
		return ready
	initialize(u, now)
	if connected(u):
		if u.comms_phase == "ascending":
			u.comms_phase = "reporting"
			u.comms_window_until_s = now + WINDOW_S
			u.comms_next_check_s = now + u.comms_interval_s if u.comms_interval_s > 0.0 else -1.0
		_report(u, now)
		u.comms_next_check_s = now + u.comms_interval_s if u.comms_interval_s > 0.0 else -1.0
		ready = take_pending(u)
		if u.comms_phase == "reporting":
			if now >= u.comms_window_until_s:
				u.ordered_depth_m = maxf(u.comms_return_depth_m, 0.0)
				u.comms_return_depth_m = -1.0
				u.comms_phase = "submerged"
			else:
				u.ordered_depth_m = minf(u.ordered_depth_m, DEPTH_M)
		return ready
	if u.comms_phase == "ascending":
		# Emergency evasion may defer a check-in; resume ascent once its maneuver ends.
		if u.evasion_remaining_s <= 0.0:
			u.ordered_depth_m = minf(u.ordered_depth_m, DEPTH_M)
	elif u.comms_next_check_s >= 0.0 and now >= u.comms_next_check_s and u.evasion_remaining_s <= 0.0:
		_begin(u)
	return ready


static func configure(u: Unit, enabled: bool, now: float) -> Array[Order]:
	var pending: Array[Order] = []
	if not u.is_submarine():
		return pending
	var was_enabled := u.comms_enabled
	u.comms_enabled = enabled
	if enabled:
		if not was_enabled:
			# Immediate control has kept the commander's picture current. Starting windows
			# takes that known deployment as the new report; reapplying an already active
			# option must never reset a saved check-in timer or an ascent in progress.
			_report(u, now)
			u.comms_next_check_s = now + u.comms_interval_s if u.comms_interval_s > 0.0 else -1.0
		initialize(u, now)
	else:
		if u.comms_return_depth_m >= 0.0:
			u.ordered_depth_m = u.comms_return_depth_m
		u.comms_return_depth_m = -1.0
		u.comms_window_until_s = -1.0
		u.comms_phase = "submerged"
		pending = take_pending(u)
	return pending


static func _begin(u: Unit) -> void:
	if u.comms_phase in ["ascending", "reporting"]:
		return
	u.comms_return_depth_m = u.ordered_depth_m
	u.comms_phase = "ascending"
	u.ordered_depth_m = minf(u.ordered_depth_m, DEPTH_M)


static func _report(u: Unit, now: float) -> void:
	u.comms_last_report_s = now
	u.comms_report = {"position": u.position, "heading_deg": u.heading_deg, "speed_kn": u.speed_kn, "depth_m": u.depth_m, "health": u.health}


static func reported_position(u: Unit) -> Vector2:
	return u.comms_report.get("position", u.position) if not connected(u) else u.position


static func reported_heading(u: Unit) -> float:
	return float(u.comms_report.get("heading_deg", u.heading_deg)) if not connected(u) else u.heading_deg


static func reported_speed(u: Unit) -> float:
	return float(u.comms_report.get("speed_kn", u.speed_kn)) if not connected(u) else u.speed_kn


static func reported_depth(u: Unit) -> float:
	return float(u.comms_report.get("depth_m", u.depth_m)) if not connected(u) else u.depth_m


static func status(u: Unit, now: float) -> String:
	if not restricted(u): return "Communications: immediate"
	var state := "connected" if connected(u) else ("ascending to check in" if u.comms_phase == "ascending" else "submerged · last report %s ago" % _duration(now - u.comms_last_report_s))
	return "Comms: %s · %d pending" % [state, u.comms_pending.size()]


static func detail(u: Unit, now: float) -> String:
	var next := "on demand" if u.comms_interval_s <= 0.0 else "in " + _duration(maxf(u.comms_next_check_s - now, 0.0))
	return "%s\nNext check-in: %s · last report %s ago\n150 ft / 46 m communication depth is a Classic gameplay abstraction.\n%s" % [status(u, now), next, _duration(maxf(now - u.comms_last_report_s, 0.0)), u.comms_note]


static func _duration(seconds: float) -> String:
	var s := maxi(ceili(seconds), 0)
	if s >= 3600: return "%dh %dm" % [s / 3600, (s % 3600) / 60]
	if s >= 60: return "%dm %ds" % [s / 60, s % 60]
	return "%ds" % s
