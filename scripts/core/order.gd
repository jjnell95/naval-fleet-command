class_name Order
extends RefCounted
## Command object issued to a Unit. Pure data; UI and AI both create these and hand them to
## UnitManager.issue_order(). Never mutate a unit from UI code directly.

enum Type { MOVE, SET_COURSE, SET_SPEED, STOP, CLEAR_WAYPOINTS, ACTIVATE_RADAR, SILENCE_RADAR, ENGAGE, SET_DEPTH, ACTIVE_SONAR, PASSIVE_SONAR, SET_ALTITUDE, LAUNCH_AIRCRAFT, RETURN_TO_BASE, DEPLOY_SONOBUOY, SET_EMCON, SET_ROE, FORM_UP, BREAK_FORMATION }

var type: Type = Type.STOP
var target_pos := Vector2.ZERO
var append := false
var heading_deg := 0.0
var speed_kn := 0.0
var track: Track
var weapon_id := ""
var salvo := 1
var depth_m := 0.0
var altitude_m := 0.0
var aircraft_id := ""
var aircraft_count := 1
var emcon_silent := false
var roe := 2
var leader: Unit
var offset_nm := Vector2.ZERO
## Specialist managers set this during the synchronous order_issued route. UnitManager returns it
## to the caller, so a UI receipt can distinguish a command that was merely routed from one that
## actually secured a firing channel, deck spot, return state, or buoy deployment.
var execution_accepted := true


static func move(pos: Vector2, append_waypoint := false) -> Order:
	var o := Order.new()
	o.type = Type.MOVE
	o.target_pos = pos
	o.append = append_waypoint
	return o


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


static func return_to_base() -> Order:
	var o := Order.new()
	o.type = Type.RETURN_TO_BASE
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
		Type.MOVE:
			return "MOVE to %s/%s%s" % [Geo.format_axis(target_pos.x, "E", "W"), Geo.format_axis(target_pos.y, "N", "S"), " (append)" if append else ""]
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
			return "LAUNCH AIRCRAFT"
		Type.RETURN_TO_BASE:
			return "RETURN TO BASE"
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
