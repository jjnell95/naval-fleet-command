class_name Order
extends RefCounted
## Command object issued to a Unit. Pure data; UI and AI both create these and hand them to
## UnitManager.issue_order(). Never mutate a unit from UI code directly.

enum Type { MOVE, SET_COURSE, SET_SPEED, STOP, CLEAR_WAYPOINTS, ACTIVATE_RADAR, SILENCE_RADAR, ENGAGE, SET_DEPTH, ACTIVE_SONAR, PASSIVE_SONAR, SET_ALTITUDE, LAUNCH_AIRCRAFT, RETURN_TO_BASE, DEPLOY_SONOBUOY, SET_EMCON, SET_ROE, FORM_UP, BREAK_FORMATION, DEPLOY_COUNTERMEASURES, EVADE, RESUME_PLAN, SET_DEFENCE_POLICY, SET_AUTO_COUNTERMEASURES, CANCEL_FIRE, PATROL }

var type: Type = Type.STOP
var target_pos := Vector2.ZERO
var append := false
var route: Array[Vector2] = []
var heading_deg := 0.0
var speed_kn := 0.0
var track: Track
var weapon_id := ""
var salvo := 1
var depth_m := 0.0
var altitude_m := 0.0
var aircraft_id := ""
var aircraft_count := 1
var recovery_base: Unit
var emcon_silent := false
var roe := 2
var leader: Unit
var offset_nm := Vector2.ZERO
var countermeasure_kind := "radar"
var evasion_mode := "auto"
var defence_policy := "balanced"
var automatic := true
## Specialist managers set this during the synchronous order_issued route. UnitManager returns it
## to the caller, so a UI receipt can distinguish a command that was merely routed from one that
## actually secured a firing channel, deck spot, return state, or buoy deployment.
var execution_accepted := true


static func cancel_fire(target: Track = null) -> Order:
	var o := Order.new()
	o.type = Type.CANCEL_FIRE
	o.track = target
	return o


static func deploy_countermeasures(kind := "radar") -> Order:
	var o := Order.new()
	o.type = Type.DEPLOY_COUNTERMEASURES
	o.countermeasure_kind = kind
	return o


static func evade(mode := "auto") -> Order:
	var o := Order.new()
	o.type = Type.EVADE
	o.evasion_mode = mode
	return o


static func resume_plan() -> Order:
	var o := Order.new()
	o.type = Type.RESUME_PLAN
	return o


static func set_defence_policy(policy: String) -> Order:
	var o := Order.new()
	o.type = Type.SET_DEFENCE_POLICY
	o.defence_policy = policy
	return o


static func set_auto_countermeasures(enabled: bool) -> Order:
	var o := Order.new()
	o.type = Type.SET_AUTO_COUNTERMEASURES
	o.automatic = enabled
	return o


static func move(pos: Vector2, append_waypoint := false) -> Order:
	var o := Order.new()
	o.type = Type.MOVE
	o.target_pos = pos
	o.append = append_waypoint
	return o


static func patrol(points: Array[Vector2]) -> Order:
	var o := Order.new()
	o.type = Type.PATROL
	o.route.assign(points)
	return o


## Rectangular circuit, specified by opposite corners in world nautical miles.
static func patrol_box(a: Vector2, b: Vector2) -> Order:
	return patrol([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)])


static func set_course(deg: float) -> Order:
	var o := Order.new()
	o.type = Type.SET_COURSE
	o.heading_deg = deg
	return o


static func set_speed(kn: float) -> Order:
	var o := Order.new()
	o.type = Type.SET_SPEED
	o.speed_kn = kn
	return o


static func stop() -> Order:
	var o := Order.new()
	o.type = Type.STOP
	return o


static func clear_waypoints() -> Order:
	var o := Order.new()
	o.type = Type.CLEAR_WAYPOINTS
	return o


static func activate_radar() -> Order:
	var o := Order.new()
	o.type = Type.ACTIVATE_RADAR
	return o


static func silence_radar() -> Order:
	var o := Order.new()
	o.type = Type.SILENCE_RADAR
	return o


static func engage(target_track: Track, weapon: String, rounds: int) -> Order:
	var o := Order.new()
	o.type = Type.ENGAGE
	o.track = target_track
	o.weapon_id = weapon
	o.salvo = maxi(rounds, 1)
	return o


## Sends a section off one deck rather than a single airframe. A deck that works several spots
## should be allowed to use them; a deck that does not will simply launch what it can.
static func launch_flight(first_aircraft: String, count: int) -> Order:
	var o := Order.new()
	o.type = Type.LAUNCH_AIRCRAFT
	o.aircraft_id = first_aircraft
	o.aircraft_count = maxi(count, 1)
	return o


static func set_depth(metres: float) -> Order:
	var o := Order.new()
	o.type = Type.SET_DEPTH
	o.depth_m = maxf(metres, 0.0)
	return o


static func active_sonar() -> Order:
	var o := Order.new()
	o.type = Type.ACTIVE_SONAR
	return o


static func passive_sonar() -> Order:
	var o := Order.new()
	o.type = Type.PASSIVE_SONAR
	return o


static func set_altitude(metres: float) -> Order:
	var o := Order.new()
	o.type = Type.SET_ALTITUDE
	o.altitude_m = maxf(metres, 0.0)
	return o


static func launch_aircraft(which := "") -> Order:
	var o := Order.new()
	o.type = Type.LAUNCH_AIRCRAFT
	o.aircraft_id = which
	return o


static func return_to_base(destination: Unit = null) -> Order:
	var o := Order.new()
	o.type = Type.RETURN_TO_BASE
	o.recovery_base = destination
	return o


static func deploy_sonobuoy() -> Order:
	var o := Order.new()
	o.type = Type.DEPLOY_SONOBUOY
	return o


static func set_emcon(silent: bool) -> Order:
	var o := Order.new()
	o.type = Type.SET_EMCON
	o.emcon_silent = silent
	return o


static func set_roe(level: int) -> Order:
	var o := Order.new()
	o.type = Type.SET_ROE
	o.roe = clampi(level, 0, 2)
	return o


static func form_up(on: Unit, offset: Vector2) -> Order:
	var o := Order.new()
	o.type = Type.FORM_UP
	o.leader = on
	o.offset_nm = offset
	return o


static func break_formation() -> Order:
	var o := Order.new()
	o.type = Type.BREAK_FORMATION
	return o


func describe() -> String:
	match type:
		Type.DEPLOY_COUNTERMEASURES:
			return "DEPLOY %s COUNTERMEASURES" % countermeasure_kind.to_upper()
		Type.EVADE:
			return "EVASIVE MANEUVER %s" % evasion_mode.to_upper()
		Type.RESUME_PLAN:
			return "RESUME ROUTE / STATION"
		Type.SET_DEFENCE_POLICY:
			return "DEFENCE %s" % defence_policy.to_upper()
		Type.SET_AUTO_COUNTERMEASURES:
			return "COUNTERMEASURES %s" % ("AUTO" if automatic else "MANUAL")
		Type.MOVE:
			return "MOVE to %s/%s%s" % [Geo.format_axis(target_pos.x, "E", "W"), Geo.format_axis(target_pos.y, "N", "S"), " (append)" if append else ""]
		Type.PATROL:
			return "PATROL %d-POINT CIRCUIT" % route.size()
		Type.SET_COURSE:
			return "COURSE %s" % Geo.format_bearing(heading_deg)
		Type.SET_SPEED:
			return "SPEED %.0f kn" % speed_kn
		Type.STOP:
			return "ALL STOP"
		Type.CLEAR_WAYPOINTS:
			return "CLEAR WAYPOINTS"
		Type.ACTIVATE_RADAR:
			return "RADAR ACTIVE"
		Type.SILENCE_RADAR:
			return "RADAR SILENT"
		Type.CANCEL_FIRE:
			return "CANCEL QUEUED FIRE"
		Type.ENGAGE:
			return "ENGAGE %s with %d x %s" % [track.id if track != null else "?", salvo, weapon_id]
		Type.SET_DEPTH:
			return "DEPTH %.0f m" % depth_m
		Type.ACTIVE_SONAR:
			return "SONAR ACTIVE"
		Type.PASSIVE_SONAR:
			return "SONAR PASSIVE"
		Type.SET_ALTITUDE:
			return "ALTITUDE %.0f m" % altitude_m
		Type.LAUNCH_AIRCRAFT:
			return "LAUNCH %d x %s" % [aircraft_count, aircraft_id if aircraft_id != "" else "READY AIRCRAFT"]
		Type.RETURN_TO_BASE:
			return "RETURN TO %s" % (recovery_base.callsign if recovery_base != null else "BASE")
		Type.DEPLOY_SONOBUOY:
			return "DEPLOY SONOBUOY"
		Type.SET_EMCON:
			return "EMCON %s" % ("SILENT" if emcon_silent else "FREE")
		Type.SET_ROE:
			return "WEAPONS %s" % ["HOLD", "TIGHT", "FREE"][roe]
		Type.FORM_UP:
			return "FORM UP on %s" % (leader.callsign if leader != null else "?")
		Type.BREAK_FORMATION:
			return "BREAK FORMATION"
	return "UNKNOWN"
