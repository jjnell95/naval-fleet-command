class_name TrackManager
extends Node
## Maintains per-faction track pictures. Observations arrive from SensorManager; tracks age,
## go stale, dead-reckon, and are eventually dropped. No SimClock access: `now` is passed in.

## These fire from inside the sensor cycle, which works out every unit's position, emissions and
## heights once at its start. A handler must not move a unit, switch a set or change its damage
## there and then; anything of that kind waits for the next decision cycle.
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
## Damage pool assumed for a contact whose class is not yet known, for battle damage assessment.
const GENERIC_HEALTH := 100.0  # GAMEPLAY

## Factions that are not at war with anyone. Their ships classify as NEUTRAL rather than HOSTILE,
## which is what makes identification a decision rather than a formality.
var neutral_factions: PackedStringArray = []
## Authored recognition briefing, scoped by observing faction and platform catalogue id.
## A signature-library match can apply this intelligence; missing IFF never means hostile.
var recognition_affiliations: Dictionary = {}

var _tracks: Dictionary = {}  # faction -> Array[Track]
var _by_target: Dictionary = {}  # picture key -> reported target association -> Track
var _local_keys: Dictionary = {}
var _track_ids: Dictionary = {}
var _next_number: Dictionary = {}  # faction -> int


func configure_recognition(brief: Dictionary) -> void:
	recognition_affiliations = brief.duplicate(true)

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
	if u == null:
		return null
	var key: String = u.faction if u.datalink_connected() else _local_keys.get(u, "")
	return find_track(key, target)


func find_track(faction: String, target: Unit) -> Track:
	var index: Dictionary = _by_target.get(faction, {})
	if index.has(target):
		return index[target]
	# Legacy fixture/debug pictures may be supplied directly; normal observations maintain index.
	for t: Track in get_tracks(faction):
		if t.truth == target:
			index[target] = t
			_by_target[faction] = index
			return t
	return null


## Convenience path for a firm circular plot, such as radar.
func observe(faction: String, target: Unit, observed_pos: Vector2, quality: float, classify_rate: float, now: float, dt: float, range_nm: float) -> void:
	observe_contact(faction, SensorContact.make(target, observed_pos, BASE_ERROR_NM + ERROR_PER_NM * range_nm, quality, classify_rate, range_nm), now, dt)


func observe_contact(faction: String, c: SensorContact, now: float, dt: float) -> void:
	if c.observer != null:
		if not _local_keys.has(c.observer):
			_local_keys[c.observer] = "local:%s" % _unit_key(c.observer)
		_observe_picture(_local_keys[c.observer], faction, c, now, dt, false)
	if c.observer == null or c.observer.datalink_connected():
		_observe_picture(faction, faction, c, now, dt, true)


## Picture and track-number keys use the unit's id, which a saved engagement restores; an instance
## id differs from one session to the next. A unit never added to a UnitManager (a test's) has no
## id yet and keeps the instance id, so two such units never share a picture.
static func _unit_key(u: Unit) -> String:
	return str(u.id) if u.id >= 0 else "i%d" % u.get_instance_id()


## A contact report from outside the force (a shore array, an allied patrol aircraft, a signals
## intercept) relayed to the side's networked plot. It is a datum to go and look at and nothing
## more: the position carries the report's own error, nothing is classified from it, the solution
## quality stays at nothing, the firm-plot clock is not started and no velocity is fitted, so no
## weapon, strike or attack can be laid on it. A contact the plot already holds is left alone,
## because the plot's own history is better founded than the report. Returns the new track or null.
func report_intel(faction: String, target: Unit, reported_pos: Vector2, error_nm: float, now: float, source_name: String) -> Track:
	if target == null or find_track(faction, target) != null:
		return null
	var t := _new_track(faction, faction, target, reported_pos, now)
	t.reported = true
	t.networked = true
	t.last_seen_time = now
	t.error_major_nm = error_nm
	t.error_minor_nm = error_nm
	t.position_error_nm = error_nm
	t.source = "intel"
	t.source_sensor = source_name
	_record_history(t, now)
	track_added.emit(faction, t)
	return t


func _new_track(key: String, faction: String, target: Unit, position: Vector2, now: float) -> Track:
	var t := Track.new()
	t.owner_faction = faction
	t.truth = target
	var identity_key := "%s:%s" % [faction, _unit_key(target)]
	if not _track_ids.has(identity_key):
		_track_ids[identity_key] = "T%d" % _next_id(faction)
	t.id = _track_ids[identity_key]
	t.position = position
	t.first_seen_time = now
	if not _tracks.has(key):
		_tracks[key] = []
	_tracks[key].append(t)
	var index: Dictionary = _by_target.get(key, {})
	index[target] = t
	_by_target[key] = index
	return t


func _observe_picture(key: String, faction: String, c: SensorContact, now: float, dt: float, shared: bool) -> void:
	var target := c.target
	var t := find_track(key, target)
	var is_new := t == null
	if is_new:
		t = _new_track(key, faction, target, c.position, now)
	var already_this_cycle := (not is_new) and is_equal_approx(t.last_seen_time, now)
	if not already_this_cycle:
		var reacquired := not is_new and t.age_s(now) > Track.STALE_AFTER_S
		# The side's own first look at a reported contact replaces the report outright: neither its
		# position nor its age is evidence the sensor should be blended with.
		var from_report := t.reported
		t.reported = false
		t._cycle_start_position = t.position
		t._cycle_snap = is_new or reacquired or from_report
		t._cycle_has_plot = false
		t._cycle_firm = false
		t._cycle_error = INF
		t._cycle_observation_gain = 0.0
		t._cycle_signature_gain = 0.0
		t._cycle_tma_start = t.tma_quality
		t._cycle_tma_gain = 0.0
		if reacquired or from_report:
			_reset_kinematics(t)
	# Sensor order must not change classification speed, or multiply elapsed time.
	var gain := dt * (0.5 + c.quality) * maxf(c.classify_rate, 0.1)
	t.observation_time_s += maxf(gain - t._cycle_observation_gain, 0.0)
	t._cycle_observation_gain = maxf(t._cycle_observation_gain, gain)
	if c.observer != null:
		t.contributors[c.observer] = now
	t.networked = shared
	if c.altitude_m >= 0.0:
		t.altitude_m = c.altitude_m
	t.status = Track.Status.ACTIVE
	t.last_seen_time = now
	_update_classification(faction, t, c, gain)
	if c.bearing_only and c.bearing_key != "":
		BearingSolution.add(t.bearing_history, c, now)
		if not t.bearing_observers.has(c.bearing_key):
			t.bearing_solution_at = -1.0e9
			t.bearing_observers[c.bearing_key] = true
	if c.bearing_only and not is_new and now - t.last_firm_time <= FIRM_HOLD_S:
		# Something is holding this contact firmly. A bearing, or a convergence-zone ring, from
		# another sensor confirms it is there but must not drag a good plot toward a worse guess.
		return
	if c.bearing_only and c.bearing_key != "":
		# A crew updates its TMA every ten seconds, and immediately when another listener
		# joins. Firm radar/active reports above need no redundant range fit at all.
		if now - t.bearing_solution_at >= BearingSolution.SAMPLE_INTERVAL_S:
			t.bearing_solution_cache = BearingSolution.estimate(t.bearing_history, now)
			t.bearing_solution_at = now
		var solution := t.bearing_solution_cache.duplicate()
		if not solution.is_empty():
			var age := maxf(now - t.bearing_solution_at, 0.0)
			solution["position"] += (solution.get("velocity", Vector2.ZERO) as Vector2) * age
			solution["major"] += Track.ERROR_GROWTH_NM_PER_S * age
			solution["quality"] = maxf(float(solution["quality"]) - TMA_DECAY_PER_S * age, 0.0)
		c = _resolved_contact(c, solution)
	var error := maxf(c.error_major_nm, c.error_minor_nm)
	var firm := not c.bearing_only
	if t._cycle_has_plot:
		if (t._cycle_firm and not firm) or (t._cycle_firm == firm and error >= t._cycle_error):
			return
	if (firm or c.solution_quality >= 0.6) and t.is_bearing_only():
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
	# A measured range is firm; a passive solution carries only its geometry-derived quality.
	t.tma_quality = 1.0 if not c.bearing_only else c.solution_quality
	t.bearing_only = c.bearing_only
	t.error_major_nm = c.error_major_nm
	t.error_minor_nm = c.error_minor_nm
	t.error_axis_deg = c.error_axis_deg
	t.position_error_nm = maxf(c.error_major_nm, c.error_minor_nm)
	t.source = c.source
	t.source_platform = c.observer.spec.short_name if c.observer != null and c.observer.spec != null else ""
	t.source_sensor = c.sensor_name
	t.source_sensor_id = c.sensor_id
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
				if _by_target.has(faction):
					_by_target[faction].erase(t.truth)
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


## Battle damage assessment. A hit by this side's own weapon on the unit one of its held tracks
## follows raises that track's estimate by the round's damage over the class's catalogue health
## when the class is known, else over a generic pool. Only the shooter's side learns anything,
## and it learns it from its own hit, not from the target's true health.
func record_hit(faction: String, spec: WeaponSpec, target: Unit) -> void:
	if spec == null or target == null:
		return
	var t := find_track(faction, target)
	if t == null or t.status == Track.Status.LOST:
		return
	t.damage_estimate = minf(t.damage_estimate + 100.0 * spec.damage / assessed_health(t, spec.id), 100.0)


## The damage pool a side assumes for a contact: the catalogue health of the class its track
## reports, else GENERIC_HEALTH. `hint_id` picks between catalogues that share a class name.
static func assessed_health(t: Track, hint_id := "") -> float:
	if t.classification >= Track.Classification.CLASS_KNOWN and t.known_class != "":
		var spec := DataDB.platform_by_short_name(t.known_class, hint_id)
		if spec != null and spec.health > 0.0:
			return spec.health
	return GENERIC_HEALTH


## A kill the plot sees: every picture still holding a track on the unit marks it destroyed, as
## the radio already reports it under that track's label.
func record_kill(target: Unit) -> void:
	for key in _by_target:
		var index: Dictionary = _by_target[key]
		var t: Track = index.get(target)
		if t != null and t.status != Track.Status.LOST:
			t.damage_estimate = 100.0


func on_weapon_impact(faction: String, spec: WeaponSpec, target: Unit, hit: bool) -> void:
	if hit:
		record_hit(faction, spec, target)


func on_unit_destroyed(target: Unit, _killer_faction: String) -> void:
	record_kill(target)


func _any_contributor_linked(t: Track) -> bool:
	for u: Unit in t.contributors:
		if u.datalink_connected():
			return true
	return false


func _resolved_contact(raw: SensorContact, solution: Dictionary) -> SensorContact:
	if solution.is_empty():
		return raw
	var c := SensorContact.new()
	for field in ["target", "observer", "source", "sensor_id", "sensor_name", "quality", "classify_rate", "range_nm"]:
		c.set(field, raw.get(field))
	c.position = solution["position"]
	c.error_major_nm = solution["major"]
	c.error_minor_nm = solution["minor"]
	c.error_axis_deg = solution["axis"]
	c.bearing_only = true
	c.solution_quality = solution["quality"]
	return c


func _update_classification(faction: String, t: Track, c: SensorContact, gain: float) -> void:
	var previous := [t.classification, t.identity]
	if t.observation_time_s >= Track.CLASS_TIMES_S[1]:
		t.classification = maxi(t.classification, Track.Classification.SURFACE) as Track.Classification
		t.domain = c.target.spec.domain
	# Emission/acoustic signature libraries give a probable class, not a hull name or proof of
	# intent. A generic radar range/velocity plot cannot identify an exact platform by waiting.
	if c.source in ["esm", "sonar_passive", "sonar_active", "sonar_cz", "sonobuoy"]:
		t.signature_time_s += maxf(gain - t._cycle_signature_gain, 0.0)
		t._cycle_signature_gain = maxf(gain, t._cycle_signature_gain)
		if t.signature_time_s >= Track.CLASS_TIMES_S[2] and t.classification < Track.Classification.IDENTIFIED:
			t.classification = Track.Classification.CLASS_KNOWN
			t.known_class = c.target.spec.short_name
			t.known_category = c.target.spec.category
			t.class_is_probable = true
			t.class_evidence = "Emitter library match" if c.source == "esm" else "Acoustic library match"
			var brief: Dictionary = recognition_affiliations.get(faction, {})
			var affiliation := String(brief.get(c.target.spec.id, ""))
			if t.identity == "UNKNOWN" and affiliation in ["HOSTILE", "NEUTRAL", "FRIENDLY"]:
				t.identity = affiliation
				t.identity_evidence = "Scenario recognition brief"
	if c.visual_identification:
		t.classification = Track.Classification.IDENTIFIED
		t.domain = c.target.spec.domain
		t.known_class = c.target.spec.short_name
		t.known_category = c.target.spec.category
		t.known_callsign = c.target.callsign
		t.class_is_probable = false
		t.class_evidence = "Visual recognition"
		# Markings provide positive affiliation, independently of a library's probable class.
		t.identity = "NEUTRAL" if neutral_factions.has(c.target.faction) else ("FRIENDLY" if c.target.faction == faction else "HOSTILE")
		t.identity_evidence = "Visual markings"
	if previous != [t.classification, t.identity] and t.networked:
		track_classified.emit(faction, t)


## Attribute a visibly originating hostile weapon only when the launcher is held locally,
## accurately and freshly. Seeing a distant incoming missile does not reveal its hidden source.
func observe_hostile_launch(observer: Unit, weapon: Weapon, now: float) -> void:
	if observer == null or weapon.shooter == null or weapon.is_interceptor() or weapon.time_alive_s > 3.0:
		return
	var local := find_track(_local_keys.get(observer, ""), weapon.shooter)
	if local == null or local.is_bearing_only() or local.age_s(now) > 2.0 or local.position_error_nm > 1.0:
		return
	if local.position.distance_to(weapon.position) > 1.5:
		return
	var toward := Geo.bearing_deg(weapon.position, observer.position)
	if absf(Geo.heading_delta(weapon.heading_deg, toward)) > 30.0:
		return
	for key in [_local_keys.get(observer, ""), observer.faction if observer.datalink_connected() else ""]:
		var t := find_track(key, weapon.shooter)
		if t != null and t.identity != "HOSTILE":
			t.identity = "HOSTILE"
			t.identity_evidence = "Observed hostile launch"
			if t.networked:
				track_classified.emit(observer.faction, t)


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
	_by_target.clear()
	_tracks.clear()
	_local_keys.clear()
	_track_ids.clear()
	_next_number.clear()
