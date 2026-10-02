class_name DippingSonar
extends RefCounted
## Deliberate helicopter sonar handling. Durations are gameplay estimates, not equipment specs.
## Navigation intent stays on Unit while the crew holds a hover; a new order retracts the array
## first, then Movement carries out the newest intent. All timers use simulation seconds.
enum Phase { STOWED, POSITIONING, LOWERING, LISTENING, RAISING }
const LOWER_S := 30.0
const RAISE_S := 20.0
const HOVER_M := 20.0
const MAX_SPEED_KN := 1.0
const MAX_ALTITUDE_M := 30.0


static func capable(u: Unit) -> bool:
	if u == null or u.spec == null or not u.spec.can_hover:
		return false
	for s in u.sensors:
		if s.kind == "sonar" and s.requires_hover:
			return true
	return false


static func rejection(u: Unit) -> String:
	if not capable(u): return "No dipping sonar fitted."
	if not u.alive or not u.airborne(): return "Aircraft must be airborne."
	if u.returning or u.tanking_on != null: return "Aircraft committed to recovery or refuelling."
	if u.evasion_remaining_s > 0.0: return "Aircraft is evading."
	if u.component("sensors") <= 0.0: return "Sonar damaged."
	if Terrain.is_land(u.position): return "Dipping sonar requires open water."
	if u.dip_phase != Phase.STOWED: return "A sonar cycle is already in progress."
	return ""


static func listening(u: Unit) -> bool:
	return u.dip_phase == Phase.LISTENING and u.alive and u.airborne() and u.component("sensors") > 0.0 and u.speed_kn <= MAX_SPEED_KN and u.altitude_m <= MAX_ALTITUDE_M and not Terrain.is_land(u.position)


static func deploy(u: Unit, listen_s: float) -> void:
	u.dip_phase = Phase.POSITIONING
	u.dip_timer_s = 0.0
	u.dip_listen_s = maxf(listen_s, 0.0)  # zero holds until an explicit recovery or navigation order


static func recover(u: Unit) -> void:
	if u.dip_phase in [Phase.STOWED, Phase.RAISING]: return
	# No cable has left the aircraft during positioning; navigation can resume immediately.
	if u.dip_phase == Phase.POSITIONING:
		u.dip_phase = Phase.STOWED
		u.dip_timer_s = 0.0
	else:
		u.dip_phase = Phase.RAISING
		u.dip_timer_s = RAISE_S


static func on_order(u: Unit, order: Order) -> void:
	if order.type == Order.Type.DEPLOY_DIPPING_SONAR:
		deploy(u, order.listen_s)
	elif order.type == Order.Type.RECOVER_DIPPING_SONAR:
		recover(u)
	elif order.type in Unit.NAVIGATION_ORDERS or order.type in [Order.Type.SET_SPEED, Order.Type.SET_ALTITUDE, Order.Type.EVADE, Order.Type.RESUME_PLAN]:
		recover(u)


## Owns motion only during handling. Does not overwrite waypoints, station or ordered speed/height.
static func step_motion(u: Unit, dt: float) -> bool:
	if u.dip_phase == Phase.STOWED: return false
	if not u.alive or not u.airborne():
		u.dip_phase = Phase.STOWED
		u.dip_timer_s = 0.0
		return false
	if u.returning or u.tanking_on != null or u.evasion_remaining_s > 0.0 or u.component("sensors") <= 0.0 or Terrain.is_land(u.position):
		recover(u)
		if u.dip_phase == Phase.STOWED: return false
	if u.dip_phase in [Phase.LOWERING, Phase.LISTENING] and (u.speed_kn > MAX_SPEED_KN or u.altitude_m > MAX_ALTITUDE_M):
		recover(u)
	u.speed_kn = move_toward(u.speed_kn, 0.0, u.spec.accel_kn_s * dt)
	u.position += Geo.heading_to_vector(u.heading_deg) * Geo.knots_to_nm_per_s(u.speed_kn) * dt
	u.altitude_m = move_toward(u.altitude_m, HOVER_M, u.spec.altitude_rate_m_s * dt)
	if u.dip_phase == Phase.POSITIONING:
		if u.speed_kn <= MAX_SPEED_KN and u.altitude_m <= MAX_ALTITUDE_M and not Terrain.is_land(u.position):
			u.dip_phase = Phase.LOWERING
			u.dip_timer_s = LOWER_S
		return true
	if u.dip_phase == Phase.LISTENING and u.dip_listen_s <= 0.0:
		return true
	u.dip_timer_s = maxf(u.dip_timer_s - dt, 0.0)
	if u.dip_timer_s <= 0.0:
		match u.dip_phase:
			Phase.LOWERING:
				u.dip_phase = Phase.LISTENING
				u.dip_timer_s = u.dip_listen_s
			Phase.LISTENING: recover(u)
			Phase.RAISING: u.dip_phase = Phase.STOWED
	return true


static func status(u: Unit) -> String:
	match u.dip_phase:
		Phase.POSITIONING: return "Sonar: establishing hover"
		Phase.LOWERING: return "Sonar: lowering · %ds" % ceili(u.dip_timer_s)
		Phase.LISTENING:
			return "Sonar: %s%s" % ["pinging" if u.active_sonar_on else "listening", " · %ds" % ceili(u.dip_timer_s) if u.dip_listen_s > 0.0 else " · holding"]
		Phase.RAISING: return "Sonar: raising · %ds" % ceili(u.dip_timer_s)
	return "Sonar: stowed"
