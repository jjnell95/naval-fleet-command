class_name SubmarinePower
extends RefCounted
## Diesel-electric propulsion: the battery, the air-independent plant and the snorkel.
##
## A nuclear boat makes its top speed for as long as it likes. A conventional boat does not: under
## water it lives on a battery, and the load on that battery rises with the cube of speed, so the
## same charge that lasts days at a crawl is gone in about an hour flat out. That is the whole
## character of the type. It is the quietest thing in the sea while it sits and waits, and it
## cannot chase, cannot run for long, and after a sprint has to come up and run its diesels
## through a snorkel mast, which is loud in the water and visible to radar.
##
## * Drain per hour = 1 / battery_hotel_h + (speed / top speed)^3 / battery_sprint_h.
## * An air-independent plant carries the boat up to its `aip_speed_kn` without drawing on the
##   battery, for `aip_endurance_h` in all. Above that speed the battery takes the load.
## * On diesels (snorkelling at periscope depth, or on the surface) the boat charges instead: a
##   full charge in `battery_charge_h`. It is then DIESEL_NOISE times as loud, shows a snorkel
##   head to radar, and is held to SNORKEL_SPEED_KN while the mast is up.
## * A flat battery leaves steerage way and nothing else until the boat charges.
## * The crew secures the snorkel by itself when the charge is complete or the boat turns away
##   from a weapon, and goes back to the depth it came up from.
##
## The shape follows public descriptions of conventional-submarine operations (submerged
## endurance tables, "indiscretion rate"); every constant and catalogue figure is a
## GAMEPLAY_ESTIMATE, not a claim about any class.

const SNORKEL_DEPTH_M := 15.0
const SNORKEL_SPEED_KN := 8.0
const DIESEL_NOISE := 4.0  # radiated noise multiplier; passive range goes with its square root
const SNORKEL_RADAR_SIGNATURE := 0.15  # of the surfaced boat; a periscope alone is 0.05
const EXHAUSTED_SPEED_KN := 3.0
const SURFACED_M := 0.5
## Reporting thresholds, and where a crew left to itself starts and stops a charge.
const LOW := 0.30
const CRITICAL := 0.10
const FULL := 0.995

## Threshold crossings since the simulation last asked: {unit, event} with event one of
## `battery_low`, `battery_critical`, `battery_flat`, `battery_charged`. Drained every tick.
static var events: Array = []


static func fitted(u: Unit) -> bool:
	return u != null and u.spec != null and u.spec.battery_sprint_h > 0.0 and u.is_submarine()


## Diesels running: charging, loud, and breathing air. On the surface they always are.
static func on_diesels(u: Unit) -> bool:
	if not fitted(u) or not u.alive:
		return false
	return u.depth_m <= SURFACED_M or (u.snorkel_on and u.depth_m <= Unit.PERISCOPE_DEPTH_M)


## The mast is up at periscope depth, as distinct from a boat running on the surface.
static func snorkelling(u: Unit) -> bool:
	return on_diesels(u) and u.depth_m > SURFACED_M


static func aip_left_s(u: Unit) -> float:
	return maxf(u.spec.aip_endurance_h * 3600.0 - u.aip_used_s, 0.0) if fitted(u) else 0.0


## Whether the air-independent plant is carrying the boat at this speed.
static func on_aip(u: Unit) -> bool:
	return fitted(u) and u.spec.aip_speed_kn > 0.0 and u.speed_kn <= u.spec.aip_speed_kn + 0.05 and aip_left_s(u) > 0.0


## Fraction of the battery spent per hour at this speed, submerged on the battery alone.
static func drain_per_hour(spec: PlatformSpec, speed_kn: float) -> float:
	if spec.battery_sprint_h <= 0.0:
		return 0.0
	var frac := clampf(speed_kn / maxf(spec.max_speed_kn, 1.0), 0.0, 1.0)
	var hotel := 1.0 / spec.battery_hotel_h if spec.battery_hotel_h > 0.0 else 0.0
	return hotel + frac * frac * frac / spec.battery_sprint_h


## Hours the charge now aboard lasts at this speed. INF where nothing is being drawn.
static func endurance_h(u: Unit, speed_kn: float) -> float:
	if not fitted(u):
		return INF
	if u.spec.aip_speed_kn > 0.0 and speed_kn <= u.spec.aip_speed_kn + 0.05 and aip_left_s(u) > 0.0:
		return aip_left_s(u) / 3600.0
	var rate := drain_per_hour(u.spec, speed_kn)
	return u.battery / rate if rate > 0.0 else INF


static func speed_limit(u: Unit) -> float:
	if not fitted(u):
		return INF
	if snorkelling(u):
		return SNORKEL_SPEED_KN
	if u.battery <= 0.0 and not on_diesels(u) and not on_aip(u):
		return maxf(EXHAUSTED_SPEED_KN, u.spec.aip_speed_kn if aip_left_s(u) > 0.0 else 0.0)
	return INF


## Why this boat cannot raise (or secure) its snorkel now, or "".
static func snorkel_rejection(u: Unit, raise: bool) -> String:
	if not fitted(u):
		return "No diesel-electric plant aboard."
	if not u.alive:
		return "Boat lost."
	if not raise:
		return "" if u.snorkel_on else "Snorkel is not raised."
	if u.snorkel_on:
		return "Already snorkelling."
	if u.evasion_remaining_s > 0.0:
		return "Boat is evading."
	if u.battery >= FULL:
		return "Battery is fully charged."
	return ""


static func on_order(u: Unit, order: Order) -> void:
	if not fitted(u):
		return
	if order.type == Order.Type.SNORKEL:
		if order.automatic:
			u.snorkel_return_depth_m = u.ordered_depth_m if u.ordered_depth_m > Unit.PERISCOPE_DEPTH_M else -1.0
			u.snorkel_on = true
			u.snorkel_note = ""
			if u.ordered_depth_m > SNORKEL_DEPTH_M:
				u.ordered_depth_m = SNORKEL_DEPTH_M
		else:
			secure(u, "secured")
	elif order.type == Order.Type.SET_DEPTH and u.snorkel_on and order.depth_m > Unit.PERISCOPE_DEPTH_M:
		# Ordered deep: the mast comes down, and the new depth is the one that stands.
		u.snorkel_on = false
		u.snorkel_return_depth_m = -1.0
		u.snorkel_note = "secured: ordered deep"


static func secure(u: Unit, note: String) -> void:
	if not u.snorkel_on:
		return
	u.snorkel_on = false
	u.snorkel_note = note
	if u.snorkel_return_depth_m >= 0.0:
		u.ordered_depth_m = minf(u.snorkel_return_depth_m, u.spec.max_depth_m)
	u.snorkel_return_depth_m = -1.0


static func step(u: Unit, dt: float) -> void:
	if not fitted(u) or not u.alive:
		return
	if u.snorkel_on and u.evasion_remaining_s > 0.0:
		secure(u, "secured: evading")
	var before := u.battery
	if on_diesels(u):
		if u.spec.battery_charge_h > 0.0:
			u.battery = minf(u.battery + dt / (u.spec.battery_charge_h * 3600.0), 1.0)
		if u.battery >= FULL and u.snorkel_on:
			u.battery = 1.0
			secure(u, "charged")
			_note(u, "battery_charged")
	elif on_aip(u):
		u.aip_used_s += dt
	else:
		u.battery = maxf(u.battery - drain_per_hour(u.spec, u.speed_kn) * dt / 3600.0, 0.0)
		if before > 0.0 and u.battery <= 0.0:
			_note(u, "battery_flat")
		elif before > CRITICAL and u.battery <= CRITICAL:
			_note(u, "battery_critical")
		elif before > LOW and u.battery <= LOW:
			_note(u, "battery_low")


static func _note(u: Unit, event: String) -> void:
	if events.size() < 256:
		events.append({"unit": u, "event": event})


static func take_events() -> Array:
	var out := events
	events = []
	return out


## The plant line of the data display: what the boat is running on and how long it lasts.
static func status(u: Unit) -> String:
	if not fitted(u):
		return ""
	if snorkelling(u):
		return "SNORKELLING · charging"
	if u.snorkel_on:
		return "coming up to snorkel"
	if on_diesels(u):
		return "surfaced · charging" if u.battery < FULL else "surfaced · on diesels"
	if on_aip(u):
		return "air-independent · %s left" % _hours(aip_left_s(u) / 3600.0)
	if u.battery <= 0.0:
		return "FLAT · steerage way only"
	return "%s at this speed" % _hours(endurance_h(u, u.speed_kn))


static func _hours(h: float) -> String:
	if is_inf(h) or h > 999.0:
		return "days"
	if h >= 48.0:
		return "%d days" % int(h / 24.0)
	if h >= 10.0:
		return "%d h" % int(h)
	if h >= 1.0:
		return "%.1f h" % h
	return "%d min" % int(round(h * 60.0))
