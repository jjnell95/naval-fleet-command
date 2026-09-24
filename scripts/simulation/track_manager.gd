class_name TrackManager
extends Node
## Maintains per-faction track pictures. Observations arrive from SensorManager; tracks age,
## go stale, dead-reckon, and are eventually dropped. No SimClock access: `now` is passed in.

signal track_added(faction: String, track: Track)
signal track_classified(faction: String, track: Track)
signal track_lost(faction: String, track: Track)

const BASE_ERROR_NM := 0.3
const ERROR_PER_NM := 0.01
const KINEMATICS_INTERVAL_S := 20.0
const KINEMATICS_WINDOW_S := 300.0
const KINEMATICS_MIN_SPAN_S := 45.0
const FIRM_BLEND := 0.5  # how hard a firm plot pulls the track onto itself
const BEARING_BLEND := 0.25  # a bearing estimate only nudges it
const TMA_DECAY_PER_S := 0.0008  # a solution goes off while contact is lost
const FIRM_HOLD_S := 1.5  # a firm plot this recent outranks any bearing
const HISTORY_INTERVAL_S := 30.0
const HISTORY_LENGTH := 48

## Factions that are not at war with anyone. Their ships classify as NEUTRAL rather than HOSTILE,
## which is what makes identification a decision rather than a formality.
var neutral_factions: PackedStringArray = []
var _tracks: Dictionary = {}  # faction -> Array[Track]
var _local_keys: Dictionary = {}
var _track_ids: Dictionary = {}
var _next_number: Dictionary = {}  # faction -> int


func get_tracks(faction: String) -> Array:
	return _tracks.get(faction, [])


## The picture as one unit actually has it, rather than the faction's whole plot.
func tracks_for(u: Unit) -> Array:
	if u == null:
		return []
	if u.datalink_connected():
		return get_tracks(u.faction)
	return _tracks.get(_local_keys.get(u, ""), [])


func find_for(u: Unit, target: Unit) -> Track:
	for t: Track in tracks_for(u):
		if t.truth == target:
			return t
	return null


func find_track(faction: String, target: Unit) -> Track:
	for t in get_tracks(faction):
		if t.truth == target:
			return t
	return null


## Convenience path for a firm circular plot, such as radar.
func observe(faction: String, target: Unit, observed_pos: Vector2, quality: float, classify_rate: float, now: float, dt: float, range_nm: float) -> void:
	observe_contact(faction, SensorContact.make(target, observed_pos, BASE_ERROR_NM + ERROR_PER_NM * range_nm, quality, classify_rate, range_nm), now, dt)


func observe_contact(faction: String, c: SensorContact, now: float, dt: float) -> void:
	if c.observer != null:
		if not _local_keys.has(c.observer):
			_local_keys[c.observer] = "local:%s" % c.observer.get_instance_id()
		_observe_picture(_local_keys[c.observer], faction, c, now, dt, false)
	if c.observer == null or c.observer.datalink_connected():
		_observe_picture(faction, faction, c, now, dt, true)


func _observe_picture(key: String, faction: String, c: SensorContact, now: float, dt: float, shared: bool) -> void:
	var target := c.target
	var t := find_track(key, target)
	var is_new := t == null
	if is_new:
		t = Track.new()
		t.owner_faction = faction
		t.truth = target
		var identity_key := "%s:%s" % [faction, target.get_instance_id()]
		if not _track_ids.has(identity_key):
			_track_ids[identity_key] = "T%d" % _next_id(faction)
		t.id = _track_ids[identity_key]
		t.position = c.position
		t.first_seen_time = now
		if not _tracks.has(key):
			_tracks[key] = []
		_tracks[key].append(t)
	var already_this_cycle := (not is_new) and is_equal_approx(t.last_seen_time, now)
	if not already_this_cycle:
		var reacquired := not is_new and t.age_s(now) > Track.STALE_AFTER_S
		t._cycle_start_position = t.position
		t._cycle_snap = is_new or reacquired
		t._cycle_has_plot = false
		t._cycle_firm = false
		t._cycle_error = INF
		t._cycle_observation_gain = 0.0
		t._cycle_tma_start = t.tma_quality
		t._cycle_tma_gain = 0.0
		if reacquired:
			_reset_kinematics(t)
	# Sensor order must not change classification speed, or multiply elapsed time.
	var gain := dt * (0.5 + c.quality) * maxf(c.classify_rate, 0.1)
	t.observation_time_s += maxf(gain - t._cycle_observation_gain, 0.0)
	t._cycle_observation_gain = maxf(t._cycle_observation_gain, gain)
	if c.observer != null:
		t.contributors[c.observer] = now
	t.networked = shared
	t.status = Track.Status.ACTIVE
	t.last_seen_time = now
	_update_classification(faction, t)
	if c.bearing_only and not is_new and now - t.last_firm_time <= FIRM_HOLD_S:
		# Something is holding this contact firmly. A bearing, or a convergence-zone ring, from
		# another sensor confirms it is there but must not drag a good plot toward a worse guess.
		return
	var error := maxf(c.error_major_nm, c.error_minor_nm)
	var firm := not c.bearing_only
	if t._cycle_has_plot:
		if (t._cycle_firm and not firm) or (t._cycle_firm == firm and error >= t._cycle_error):
			return
	if firm and t.is_bearing_only():
		# A measured range replaces a tentative bearing guess, including any guessed
		# positions that would otherwise produce a spurious velocity in the fit.
		t._cycle_snap = true
		_reset_kinematics(t)
	t._cycle_has_plot = true
	t._cycle_firm = firm
	t._cycle_error = error
	if not c.bearing_only:
		t.last_firm_time = now
	var blend := BEARING_BLEND if c.bearing_only else FIRM_BLEND
	t.position = c.position if t._cycle_snap else t._cycle_start_position.lerp(c.position, blend)
	# A firm plot hands over a range outright; a bearing has to be worked up over time.
	t._cycle_tma_gain = maxf(t._cycle_tma_gain, c.tma_gain)
	t.tma_quality = 1.0 if not c.bearing_only else clampf(t._cycle_tma_start + t._cycle_tma_gain, 0.0, 1.0)
	t.bearing_only = c.bearing_only
	t.error_major_nm = c.error_major_nm
	t.error_minor_nm = c.error_minor_nm
	t.error_axis_deg = c.error_axis_deg
	t.position_error_nm = maxf(c.error_major_nm, c.error_minor_nm)
	t.source = c.source
	if c.observer != null:
		t.contributors[c.observer] = now
	t.networked = shared
	t.status = Track.Status.ACTIVE
	t.last_seen_time = now
	_record_history(t, now)
	if not t.is_bearing_only():
		if not t._obs_times.is_empty() and is_equal_approx(t._obs_times[-1], now):
			t._obs_pos[-1] = c.position
		else:
			t._obs_times.append(now)
			t._obs_pos.append(c.position)
		while t._obs_times.size() > 0 and now - t._obs_times[0] > KINEMATICS_WINDOW_S:
			t._obs_times.remove_at(0)
			t._obs_pos.remove_at(0)
		_update_kinematics(t, now)
	else:
		_reset_kinematics(t)
	if is_new and shared:
		track_added.emit(faction, t)


func tick(now: float, dt: float) -> void:
	for faction in _tracks.keys():
		var list: Array = _tracks[faction]
		for i in range(list.size() - 1, -1, -1):
			var t: Track = list[i]
			if is_equal_approx(t.last_seen_time, now):
				continue
			var age := t.age_s(now)
			# Loss of sensor contact is the only evidence here. Hidden destruction must
			# not reveal itself by expiring this track earlier than an unseen survivor.
			if age > Track.LOST_AFTER_S:
				t.status = Track.Status.LOST
				list.remove_at(i)
				track_lost.emit(faction, t)
				continue
			if age > Track.STALE_AFTER_S:
				t.status = Track.Status.STALE
			if t.has_kinematics:
				t.position += Geo.heading_to_vector(t.course_deg) * Geo.knots_to_nm_per_s(t.speed_kn) * dt
			t.error_major_nm += Track.ERROR_GROWTH_NM_PER_S * dt
			t.error_minor_nm += Track.ERROR_GROWTH_NM_PER_S * dt
			t.position_error_nm = maxf(t.error_major_nm, t.error_minor_nm)
			t.tma_quality = maxf(t.tma_quality - TMA_DECAY_PER_S * dt, 0.0)


func _any_contributor_linked(t: Track) -> bool:
	for u: Unit in t.contributors:
		if u.datalink_connected():
			return true
	return false


func _update_classification(faction: String, t: Track) -> void:
	var level := t.classification
	for i in range(Track.CLASS_TIMES_S.size() - 1, -1, -1):
		if t.observation_time_s >= Track.CLASS_TIMES_S[i]:
			level = i as Track.Classification
			break
	if level == t.classification:
		return
	t.classification = level
	if level >= Track.Classification.SURFACE:
		t.domain = t.truth.spec.domain
	if level >= Track.Classification.CLASS_KNOWN:
		t.known_class = t.truth.spec.short_name
		t.known_category = t.truth.spec.category
		if neutral_factions.has(t.truth.faction):
			t.identity = "NEUTRAL"
		elif t.truth.faction == faction:
			t.identity = "FRIENDLY"
		else:
			t.identity = "HOSTILE"
	if level >= Track.Classification.IDENTIFIED:
		t.known_callsign = t.truth.callsign
	if t.networked:
		track_classified.emit(faction, t)


func _update_kinematics(t: Track, now: float) -> void:
	if t._last_est_time >= 0.0 and now > t._last_est_time and now - t._last_est_time < KINEMATICS_INTERVAL_S:
		return
	var n := t._obs_times.size()
	if n < 2 or t._obs_times[n - 1] - t._obs_times[0] < KINEMATICS_MIN_SPAN_S:
		return
	t._last_est_time = now
	# Least-squares linear fit of position vs time over the observation window.
	var mean_t := 0.0
	var mean_p := Vector2.ZERO
	for i in n:
		mean_t += t._obs_times[i]
		mean_p += t._obs_pos[i]
	mean_t /= n
	mean_p /= n
	var sxx := 0.0
	var sxy := Vector2.ZERO
	for i in n:
		var dtn := t._obs_times[i] - mean_t
		sxx += dtn * dtn
		sxy += (t._obs_pos[i] - mean_p) * dtn
	if sxx <= 0.0:
		return
	var vel := sxy / sxx  # nm per second
	t.speed_kn = vel.length() * 3600.0
	if vel.length() > 1e-6:
		t.course_deg = Geo.vector_to_heading(vel)
	t.has_kinematics = true


func _reset_kinematics(t: Track) -> void:
	t._obs_times.clear()
	t._obs_pos.clear()
	t._last_est_time = -1.0
	t.has_kinematics = false
	t.speed_kn = 0.0
	t.course_deg = 0.0


func _record_history(t: Track, now: float) -> void:
	if not t.history_times.is_empty():
		if is_equal_approx(t.history_times[-1], now):
			t.history_positions[-1] = t.position
			return
		if now - t.history_times[-1] < HISTORY_INTERVAL_S:
			return
	t.history_times.append(now)
	t.history_positions.append(t.position)
	while t.history_times.size() > HISTORY_LENGTH:
		t.history_times.remove_at(0)
		t.history_positions.remove_at(0)


func _next_id(faction: String) -> int:
	var n: int = _next_number.get(faction, 1001)
	_next_number[faction] = n + 1
	return n


func clear() -> void:
	_tracks.clear()
	_local_keys.clear()
	_track_ids.clear()
	_next_number.clear()
