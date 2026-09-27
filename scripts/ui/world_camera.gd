class_name WorldCamera
extends RefCounted
## The world view's camera, after the four camera modes of the 1990s fleet-command games:
## Tether, Fly-by, Action and Detached. Pure state and geometry with no node in sight, so every
## rule is testable headless; WorldView feeds it the subject's frame each frame and applies the
## shot it returns to the Camera3D.
##
## Frames are world dictionaries as WorldScene.focus_frame returns them: {position: Vector3 in
## metres about the floating origin, length, heading, domain, speed_mps}. Places that must hold
## still while that origin slides under them (a fly-by station, a detached eye, an impact being
## watched) are kept in chart coordinates instead: Vector3(nm east, nm north, metres up).

const TETHER := 0
const FLYBY := 1
const ACTION := 2
const DETACHED := 3
const MODE_NAMES: Array[String] = ["Tether", "Fly-by", "Action", "Detached"]

## Tether framing. Azimuth is measured from the subject's bow, clockwise, to the camera, so 180
## is dead astern and the default sits off the port quarter, looking forward past the bridge.
const DEFAULT_AZ := 215.0
const DEFAULT_PITCH := 6.0
const MIN_PITCH := 1.5
const MAX_PITCH := 85.0
const MIN_ZOOM := 0.3
const MAX_ZOOM := 30.0
const TETHER_LENGTHS := 1.9
const TETHER_MIN_M := 40.0
const TETHER_MAX_M := 90000.0
const FOV_DEG := 58.0  # horizontal: the pane is wide, and the frame should not widen with it
const FOLLOW_RATE := 3.0
## Fly-by: how far ahead of the subject the camera waits, in seconds of its run and in lengths,
## and how far past it the subject goes before the camera moves on.
const FLYBY_LEAD_S := 20.0
const FLYBY_LEAD_LENGTHS := 3.0
const FLYBY_SIDE_LENGTHS := 0.9
const FLYBY_PAST_LENGTHS := 2.5
const FLYBY_GIVE_UP_LENGTHS := 14.0
## Action: how long a watched event holds the camera, how long a launch is followed, and how
## stale a queued event may grow before it is not worth a cut.
const ACTION_HOLD_S := 6.0
const ACTION_FOLLOW_S := 8.0
const ACTION_QUEUE := 4
const ACTION_STALE_S := 3.0
## Which events Action cuts to, and which may cut away from a running one.
const EVENT_PRIORITY := {"destroyed": 4, "hit": 3, "intercept": 2, "launch": 1, "air_launch": 1, "recovery": 1}
const MIN_SHOT_S := 2.5

var mode := TETHER
## Tether orbit and zoom, remembered for the session whatever the subject.
var orbit_az := DEFAULT_AZ
var orbit_pitch := DEFAULT_PITCH
var zoom := 1.0

var _az := DEFAULT_AZ  # smoothed azimuth, absolute (degrees true, focus to camera)
var _pitch := DEFAULT_PITCH
var _dist := 400.0
var _valid := false
var _cut := true
var _station := Vector3.ZERO  # fly-by eye, chart coordinates
var _station_valid := false
var _detached := Vector3.ZERO  # detached eye, chart coordinates
var _detached_valid := false
var _last_eye := Vector3.ZERO  # the previous shot's eye, chart coordinates
var _last_eye_valid := false
var _queue: Array[Dictionary] = []
var _action: Dictionary = {}
var _clock := 0.0


# --- Modes -------------------------------------------------------------------------------

func set_mode(next: int) -> void:
	next = clampi(next, TETHER, DETACHED)
	if next == mode:
		return
	mode = next
	_station_valid = false
	_action = {}
	_queue.clear()
	if mode == DETACHED:
		_detached = _last_eye
		_detached_valid = _last_eye_valid
	_cut = true


func cycle_mode() -> void:
	set_mode((mode + 1) % MODE_NAMES.size())


func mode_name() -> String:
	return MODE_NAMES[mode]


## A new subject: the next shot jumps instead of sweeping across the sea, and a fly-by picks a new
## station. The tether orbit is kept; that is the player's own framing.
func cut() -> void:
	_cut = true
	_station_valid = false
	if mode == DETACHED:
		_detached_valid = false


## Drag: `dx`, `dy` in screen pixels.
func orbit(dx: float, dy: float) -> void:
	orbit_az = wrapf(orbit_az - dx * 0.35, 0.0, 360.0)
	orbit_pitch = clampf(orbit_pitch + dy * 0.25, MIN_PITCH, MAX_PITCH)


## Wheel: a factor above one pulls back.
func zoom_by(factor: float) -> void:
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)


func reset_orbit() -> void:
	orbit_az = DEFAULT_AZ
	orbit_pitch = DEFAULT_PITCH
	zoom = 1.0


# --- Action events -----------------------------------------------------------------------

## Something Action may cut to. The caller has already decided the player may see it: a launch of
## ours, a hit on something held, an aircraft of ours leaving or reaching a deck. `key` names an
## entity to follow (a round, an aircraft), or "" for a fixed point.
func notify(kind: String, at: Vector3, key := "") -> void:
	if not EVENT_PRIORITY.has(kind):
		return
	if mode != ACTION:
		return
	var e := {"kind": kind, "at": at, "key": key, "time": _clock, "priority": int(EVENT_PRIORITY[kind])}
	_queue.append(e)
	_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["priority"]) > int(b["priority"]) or (int(a["priority"]) == int(b["priority"]) and float(a["time"]) > float(b["time"])))
	if _queue.size() > ACTION_QUEUE:
		_queue.resize(ACTION_QUEUE)


## What Action is showing now: {} between events, else the event dictionary.
func action() -> Dictionary:
	return _action


func _start(e: Dictionary) -> void:
	var shot := e.duplicate()
	shot["since"] = _clock
	var follow: bool = e["key"] != "" and e["kind"] in ["launch", "air_launch"]
	shot["follow"] = follow
	shot["until"] = _clock + (ACTION_FOLLOW_S if follow else ACTION_HOLD_S)
	shot["eye_valid"] = false
	_action = shot
	_cut = true


func _next_action() -> void:
	while not _queue.is_empty():
		var e: Dictionary = _queue.pop_front()
		if _clock - float(e["time"]) <= ACTION_STALE_S:
			_start(e)
			return
	if not _action.is_empty():
		_action = {}
		_cut = true


# --- The shot ----------------------------------------------------------------------------

## One frame. `subject` is the focus's world frame ({} when there is nothing to look at);
## `lookup` returns the world frame for an entity key, {} when it has gone. Returns
## {eye: Vector3, look: Vector3, fov: float, cut: bool} in world metres, or {} for no shot.
func update(delta: float, origin_nm: Vector2, subject: Dictionary, lookup: Callable) -> Dictionary:
	_clock += delta
	if mode == ACTION:
		if _action.is_empty() or _clock >= float(_action["until"]):
			_next_action()
		elif not _queue.is_empty() and int(_queue[0]["priority"]) > int(_action["priority"]) and _clock - float(_action["since"]) >= MIN_SHOT_S:
			_next_action()
	var shot := {}
	if mode == ACTION and not _action.is_empty():
		shot = _action_shot(delta, origin_nm, lookup)
	if shot.is_empty():
		if subject.is_empty():
			return {}
		match mode:
			FLYBY:
				shot = _flyby_shot(origin_nm, subject)
			DETACHED:
				shot = _detached_shot(origin_nm, subject)
			_:
				shot = _tether_shot(delta, subject)
	shot["cut"] = _cut
	_cut = false
	_last_eye = to_chart(shot["eye"], origin_nm)
	_last_eye_valid = true
	return shot


func _tether_shot(delta: float, subject: Dictionary) -> Dictionary:
	var target: Vector3 = subject["position"]
	var want_az := wrapf(float(subject.get("heading", 0.0)) + orbit_az, 0.0, 360.0)
	var want_dist := tether_distance(float(subject.get("length", 150.0)), zoom)
	if _cut or not _valid:
		_az = want_az
		_pitch = orbit_pitch
		_dist = want_dist
		_valid = true
	else:
		var rate := 1.0 - exp(-FOLLOW_RATE * delta)
		_az = wrapf(_az + Geo.heading_delta(_az, want_az) * rate, 0.0, 360.0)
		_pitch = lerpf(_pitch, orbit_pitch, minf(rate * 2.0, 1.0))
		_dist = lerpf(_dist, want_dist, minf(rate * 2.0, 1.0))
	return {"eye": target + orbit_offset(_az, _pitch, _dist), "look": target, "fov": FOV_DEG}


func _flyby_shot(origin_nm: Vector2, subject: Dictionary) -> Dictionary:
	var target: Vector3 = subject["position"]
	var length := float(subject.get("length", 150.0))
	var heading := float(subject.get("heading", 0.0))
	var here := to_chart(target, origin_nm)
	var here_nm := Vector2(here.x, here.y)
	if not _station_valid or flyby_passed(_station, here_nm, heading, length):
		_station = flyby_station(here_nm, heading, float(subject.get("speed_mps", 0.0)), length, String(subject.get("domain", "surface")), here.z)
		_station_valid = true
		_cut = true
	return {"eye": to_world(_station, origin_nm), "look": target, "fov": FOV_DEG}


func _detached_shot(origin_nm: Vector2, subject: Dictionary) -> Dictionary:
	var target: Vector3 = subject["position"]
	if not _detached_valid:
		var start := target + orbit_offset(wrapf(float(subject.get("heading", 0.0)) + orbit_az, 0.0, 360.0), orbit_pitch, tether_distance(float(subject.get("length", 150.0)), zoom))
		_detached = to_chart(start, origin_nm)
		_detached_valid = true
	return {"eye": to_world(_detached, origin_nm), "look": target, "fov": FOV_DEG}


func _action_shot(delta: float, origin_nm: Vector2, lookup: Callable) -> Dictionary:
	var a := _action
	if a["follow"]:
		var frame: Dictionary = lookup.call(String(a["key"])) if lookup.is_valid() else {}
		if not frame.is_empty():
			var target: Vector3 = frame["position"]
			a["at"] = to_chart(target, origin_nm)
			var length := maxf(float(frame.get("length", 6.0)), 4.0)
			var dist := clampf(length * 9.0, 60.0, 400.0)
			var az := wrapf(float(frame.get("heading", 0.0)) + 200.0, 0.0, 360.0)
			if not a.has("az"):
				a["az"] = az
			else:
				a["az"] = wrapf(float(a["az"]) + Geo.heading_delta(float(a["az"]), az) * (1.0 - exp(-4.0 * delta)), 0.0, 360.0)
			return {"eye": target + orbit_offset(float(a["az"]), 9.0, dist), "look": target, "fov": FOV_DEG}
		# The round has gone: stay on where it was for a moment, then move on.
		a["follow"] = false
		a["until"] = minf(float(a["until"]), _clock + 2.0)
	var at: Vector3 = a["at"]
	var look := to_world(at, origin_nm) + Vector3(0.0, 8.0, 0.0)
	if not a["eye_valid"]:
		a["eye"] = watch_station(at, _last_eye if _last_eye_valid else at + Vector3(0.0, -0.5, 200.0), String(a["kind"]))
		a["eye_valid"] = true
	return {"eye": to_world(a["eye"], origin_nm), "look": look, "fov": FOV_DEG}


# --- Geometry (pure) ---------------------------------------------------------------------

## Tether range for a subject `length_m` long at a zoom factor.
static func tether_distance(length_m: float, zoom_factor: float) -> float:
	return clampf(maxf(length_m, 12.0) * TETHER_LENGTHS * zoom_factor, TETHER_MIN_M, TETHER_MAX_M)


## Offset from a target to a camera on bearing `az_deg` (true, target to camera), `pitch_deg`
## above the horizontal, `dist_m` away.
static func orbit_offset(az_deg: float, pitch_deg: float, dist_m: float) -> Vector3:
	var dir := WorldPresentation.heading_vector(az_deg)
	var p := deg_to_rad(pitch_deg)
	return dir * cos(p) * dist_m + Vector3(0.0, sin(p) * dist_m, 0.0)


## Where a fly-by camera waits: ahead of the subject along its course and off its starboard side,
## low over the water for a ship and level with an aircraft. Chart coordinates.
static func flyby_station(pos_nm: Vector2, heading_deg: float, speed_mps: float, length_m: float, domain: String, height_m := 0.0) -> Vector3:
	var length := maxf(length_m, 12.0)
	var ahead_m := maxf(speed_mps * FLYBY_LEAD_S, length * FLYBY_LEAD_LENGTHS)
	var side_m := maxf(length * FLYBY_SIDE_LENGTHS, 30.0)
	var fwd := Geo.heading_to_vector(heading_deg)
	var stbd := Geo.heading_to_vector(heading_deg + 90.0)
	var p := pos_nm + (fwd * ahead_m + stbd * side_m) / WorldPresentation.NM_TO_M
	var h := maxf(length * 0.14, 6.0) + 4.0
	if domain == "air":
		h = maxf(height_m, 50.0) + length * 0.4
	return Vector3(p.x, p.y, h)


## True once the subject has run far enough past a fly-by station, or strayed so far from it that
## waiting is pointless.
static func flyby_passed(station: Vector3, pos_nm: Vector2, heading_deg: float, length_m: float) -> bool:
	var length := maxf(length_m, 12.0)
	var rel := (pos_nm - Vector2(station.x, station.y)) * WorldPresentation.NM_TO_M
	var along := rel.dot(Geo.heading_to_vector(heading_deg))
	return along > length * FLYBY_PAST_LENGTHS or rel.length() > maxf(length * FLYBY_GIVE_UP_LENGTHS, 2500.0)


## Where Action stands to watch an event at `at`: along the line from the event back toward the
## previous eye, close enough to see it and a little above. Chart coordinates.
static func watch_station(at: Vector3, from: Vector3, kind: String) -> Vector3:
	var dist := 900.0 if kind == "destroyed" else (1400.0 if kind == "intercept" else 650.0)
	var rel := Vector2(from.x - at.x, from.y - at.y)
	var dir := rel.normalized() if rel.length_squared() > 1e-12 else Vector2(0.0, -1.0)
	var p := Vector2(at.x, at.y) + dir * dist / WorldPresentation.NM_TO_M
	return Vector3(p.x, p.y, maxf(at.z, 0.0) + dist * 0.2)


static func to_chart(world: Vector3, origin_nm: Vector2) -> Vector3:
	return Vector3(origin_nm.x + world.x / WorldPresentation.NM_TO_M, origin_nm.y - world.z / WorldPresentation.NM_TO_M, world.y)


static func to_world(chart: Vector3, origin_nm: Vector2) -> Vector3:
	return WorldPresentation.to_world(Vector2(chart.x, chart.y), origin_nm, chart.z)
