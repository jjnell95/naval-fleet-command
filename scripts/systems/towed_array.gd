class_name TowedArray
extends RefCounted
## Surface-ship variable-depth and towed arrays take time to stream and recover. The crew
## handles speed and cable while keeping the commander's route intact. Times/speeds are gameplay
## estimates, not claims about any named sonar. Submarine integrated suites remain hull-relative.
enum Phase { STOWED, STREAMING, LISTENING, RECOVERING }
const STREAM_S := 120.0
const RECOVER_S := 90.0
const QUIET_SPEED_KN := 8.0
const MIN_WATER_M := 25.0


static func requires_deployment(u: Unit, sensor: SensorSpec) -> bool:
	return u.spec.domain == "surface" and sensor.kind == "sonar" and sensor.array_depth_m > 0.0 and not sensor.requires_hover


static func capable(u: Unit) -> bool:
	if u == null or u.spec == null: return false
	for sensor: SensorSpec in u.sensors:
		if requires_deployment(u, sensor): return true
	return false


static func safe_water(u: Unit) -> bool:
	var floor_m := Acoustics.bottom_m(u)
	return not Terrain.is_land(u.position) and (floor_m < 0.0 or floor_m >= MIN_WATER_M)


static func rejection(u: Unit) -> String:
	if not capable(u): return "No deployable ship sonar fitted."
	if not u.alive or u.component("sensors") <= 0.0: return "Sonar unavailable."
	if u.evasion_remaining_s > 0.0: return "Ship is evading."
	if not safe_water(u): return "Insufficient water beneath the array."
	if u.array_search_active: return "ASW search is already active."
	if u.array_phase == Phase.RECOVERING: return "Array recovery in progress."
	return ""


static func sensor_ready(u: Unit, sensor: SensorSpec) -> bool:
	if not requires_deployment(u, sensor): return true
	return u.array_phase == Phase.LISTENING and u.alive and u.component("sensors") > 0.0 and u.speed_kn <= QUIET_SPEED_KN + 0.1 and safe_water(u)


static func search(u: Unit) -> void:
	u.array_search_active = true
	if u.array_phase == Phase.STOWED:
		u.array_phase = Phase.STREAMING
		u.array_timer_s = STREAM_S


static func recover(u: Unit) -> void:
	u.array_search_active = false
	if u.array_phase in [Phase.STOWED, Phase.RECOVERING]: return
	u.array_phase = Phase.RECOVERING
	u.array_timer_s = RECOVER_S


static func on_order(u: Unit, order: Order) -> void:
	if order.type == Order.Type.ASW_SEARCH:
		search(u)
	elif order.type == Order.Type.RECOVER_TOWED_ARRAY:
		recover(u)
	elif order.type in Unit.NAVIGATION_ORDERS or order.type in [Order.Type.SET_SPEED, Order.Type.EVADE]:
		recover(u)


static func speed_limit(u: Unit) -> float:
	return QUIET_SPEED_KN if u.array_phase != Phase.STOWED else INF


static func step(u: Unit, dt: float) -> void:
	if u.array_phase == Phase.STOWED: return
	if not u.alive:
		u.array_phase = Phase.STOWED
		u.array_timer_s = 0.0
		u.array_search_active = false
		return
	if u.component("sensors") <= 0.0 or u.evasion_remaining_s > 0.0 or not safe_water(u):
		recover(u)
	# Pay out only after slowing. This prevents a fast ship acquiring an instant quiet-water fix.
	if u.array_phase == Phase.STREAMING and u.speed_kn > QUIET_SPEED_KN + 0.1: return
	if u.array_phase == Phase.LISTENING: return
	u.array_timer_s = maxf(u.array_timer_s - dt, 0.0)
	if u.array_timer_s <= 0.0:
		u.array_phase = Phase.LISTENING if u.array_phase == Phase.STREAMING else Phase.STOWED


static func status(u: Unit) -> String:
	match u.array_phase:
		Phase.STREAMING:
			return "Array: slowing to %d kn" % int(QUIET_SPEED_KN) if u.speed_kn > QUIET_SPEED_KN + 0.1 else "Array: streaming · %ds" % ceili(u.array_timer_s)
		Phase.LISTENING: return "Array: %s · quiet search" % ("pinging" if u.active_sonar_on else "listening")
		Phase.RECOVERING: return "Array: recovering · %ds" % ceili(u.array_timer_s)
	return "Array: stowed"
