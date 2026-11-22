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
## The same two events for the picture one unit keeps to itself while it is off the link: a deep
## submarine's own contacts, which the shared plot never hears of until she reports.
signal local_track_added(observer: Unit, track: Track)
signal local_track_classified(observer: Unit, track: Track)

const BASE_ERROR_NM := 0.3
const ERROR_PER_NM := 0.01
const KINEMATICS_INTERVAL_S := 20.0
const KINEMATICS_WINDOW_S := 300.0
const KINEMATICS_MIN_SPAN_S := 45.0
const FIRM_BLEND := 0.5  # how hard a firm plot pulls the track onto itself
const BEARING_BLEND := 0.25  # a bearing estimate only nudges it
## A range worked from bearings is first plotted at this quality, and kept until it falls below
## Track.RANGE_HELD_QUALITY. The gap stops a marginal geometry flipping the plot between a fix and
## a bare bearing every time the solution is reworked.
const RANGE_ACCEPT_QUALITY := 0.3
const MIN_BEARING_RANGE_NM := 0.3
## A solution this good is plotted at the full bearing blend and feeds the course and speed fit;
## a poorer one pulls the plot less and claims no course.
const SOUND_SOLUTION_QUALITY := 0.6
const HOLDER_SILENT_S := 2.5
const LINE_LAG_S := 1.0 / BearingSolution.SMOOTH_GAIN
## How far outside a dropped track's ellipse a new plot may fall and still be the same contact.
const SAME_CONTACT_MARGIN_NM := 2.0
const TMA_DECAY_PER_S := 0.0008  # a solution goes off while contact is lost
const FIRM_HOLD_S := 1.5  # a firm plot this recent outranks any bearing
const HISTORY_INTERVAL_S := 30.0
const HISTORY_LENGTH := 48
## Damage pool assumed for a contact whose class is not yet known, for battle damage assessment.
const GENERIC_HEALTH := 100.0  # GAMEPLAY
## A radar plot this close on an aircraft accumulates toward a probable type. GAMEPLAY_ESTIMATE.
const RADAR_RECOGNITION_NM := 60.0
const RADAR_RECOGNITION_S := 60.0

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
## Contacts a side has dropped from every picture: side and unit key -> the number the track had,
## where it was last plotted and how wide its ellipse was. A new plot inside that ellipse is the
## same contact found again and takes the number back; anywhere else it is a new contact.
var _dropped_ids: Dictionary = {}
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
		var dropped: Dictionary = _dropped_ids.get(identity_key, {})
		_dropped_ids.erase(identity_key)
		if not dropped.is_empty() and position.distance_to(dropped["position"]) <= float(dropped["error"]) + SAME_CONTACT_MARGIN_NM:
			_track_ids[identity_key] = dropped["id"]
		else:
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
		var reacquired := not is_new and t.age_s(now) > t.stale_after_s()
		# The side's own first look at a reported contact replaces the report outright: neither its
		# position nor its age is evidence the sensor should be blended with.
		var from_report := t.reported
		t.reported = false
		t._cycle_start_position = t.position
		t._cycle_start_major = t.error_major_nm
		t._cycle_range_held = not is_new and not from_report and not t.is_bearing_only()
		t._cycle_bearing_held = t.bearing_only
		t._cycle_snap = is_new or reacquired or from_report
		t._cycle_has_plot = false
		t._cycle_firm = false
		t._cycle_error = INF
		t._cycle_observation_gain = 0.0
		t._cycle_signature_gain = 0.0
		t._cycle_radar_gain = 0.0
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
	if c.source == "esm":
		t.last_esm_time = now
	_update_classification(faction, t, c, gain)
	var report := {}
	if c.bearing_only and c.bearing_key != "":
		report = BearingSolution.add(t.bearing_history, c, now)
		if not t.bearing_observers.has(c.bearing_key):
			t.bearing_solution_at = -1.0e9
			t.bearing_observers[c.bearing_key] = true
	if c.bearing_only and not is_new and now - t.last_firm_time <= FIRM_HOLD_S:
		# Something is holding this contact firmly. A bearing, or a convergence-zone ring, from
		# another sensor confirms it is there but must not drag a good plot toward a worse guess.
		return
	var raw := c
	if c.bearing_only:
		c = _bearing_plot(t, c, report, _bearing_solution(t, c, now), now, dt, is_new)
		if (c.placed or is_new) and raw.bearing_key != "":
			if t.bearing_holder != raw.bearing_key and now - t.bearing_holder_time <= HOLDER_SILENT_S:
				return
			t.bearing_holder = raw.bearing_key
			t.bearing_holder_time = now
	var error := maxf(c.error_major_nm, c.error_minor_nm)
	var firm := not c.bearing_only
	if t._cycle_has_plot:
		if (t._cycle_firm and not firm) or (t._cycle_firm == firm and error >= t._cycle_error):
			return
	var ranged := firm or (not c.placed and c.solution_quality >= Track.RANGE_HELD_QUALITY)
	if firm and t._cycle_bearing_held:
		# A measured plot replaces whatever the bearings had worked out, outright: blending the two
		# would leave the track between where it is and where it was guessed to be.
		t._cycle_snap = true
		if t._obs_estimated or not t._cycle_range_held:
			_reset_kinematics(t)
	elif ranged and not t._cycle_range_held:
		# The first range on a bare bearing: the line's nominal position was never a place.
		t._cycle_snap = true
		_reset_kinematics(t)
	t._cycle_has_plot = true
	t._cycle_firm = firm
	t._cycle_error = error
	if firm:
		t.last_firm_time = now
	if ranged:
		t.range_time = now
	var blend := FIRM_BLEND
	if c.bearing_only:
		blend = BEARING_BLEND * clampf(c.solution_quality / SOUND_SOLUTION_QUALITY, 0.4, 1.0)
	t.position = c.position if t._cycle_snap or c.placed else t._cycle_start_position.lerp(c.position, blend)
	# A measured range is firm; a passive solution carries only its geometry-derived quality.
	t.tma_quality = 1.0 if firm else c.solution_quality
	t.bearing_only = c.bearing_only
	t.bearing_origin = raw.bearing_origin if raw.bearing_only and raw.bearing_key != "" else Vector2.INF
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
	if ranged and (firm or c.solution_quality >= SOUND_SOLUTION_QUALITY - 0.1):
		if not firm:
			t._obs_estimated = true
		if not t._obs_times.is_empty() and is_equal_approx(t._obs_times[-1], now):
			t._obs_pos[-1] = c.position
		else:
			t._obs_times.append(now)
			t._obs_pos.append(c.position)
		while t._obs_times.size() > 0 and now - t._obs_times[0] > KINEMATICS_WINDOW_S:
			t._obs_times.remove_at(0)
			t._obs_pos.remove_at(0)
		_update_kinematics(t, now)
	elif t.is_bearing_only():
		# No range, so no course and speed. A range still held from an earlier fix keeps its own.
		_reset_kinematics(t)
	if is_new and shared:
		track_added.emit(faction, t)
	elif is_new and raw.observer != null and not raw.observer.datalink_connected():
		local_track_added.emit(raw.observer, t)


## The range solution the crew currently has from this track's bearings, aged to `now`; empty when
## they have none. A crew reworks its TMA every ten seconds, and at once when another listener
## joins. Something that may be an aircraft is fixed only by lines taken together, so its fix is
## reworked every cycle and never carried forward on a course it does not have.
func _bearing_solution(t: Track, c: SensorContact, now: float) -> Dictionary:
	if c.bearing_key == "":
		return {}
	var limit := _speed_limit_kn(t, c)
	var interval := BearingSolution.SAMPLE_INTERVAL_S if limit <= BearingSolution.SHIP_SPEED_LIMIT_KN else 0.0
	if now - t.bearing_solution_at >= interval:
		t.bearing_solution_cache = BearingSolution.estimate(t.bearing_history, now, limit)
		t.bearing_solution_at = now
	var solution := t.bearing_solution_cache.duplicate()
	if not solution.is_empty():
		var age := maxf(now - t.bearing_solution_at, 0.0)
		solution["position"] += (solution.get("velocity", Vector2.ZERO) as Vector2) * age
		# However good the geometry, the answer is as old as the lines that made it: the plotted
		# line trails the newest look by a few seconds and the solution may be older still. A
		# ship moves nothing in that time; an aircraft moves miles.
		var growth := t.error_growth_nm_per_s()
		solution["major"] = maxf(float(solution["major"]) + growth * age, growth * (age + LINE_LAG_S))
		solution["quality"] = maxf(float(solution["quality"]) - TMA_DECAY_PER_S * age, 0.0)
	return solution


## The fastest the plot believes this contact can go: nothing for a fixed site, a ship's speed for
## anything known to be on or under the sea, otherwise whatever the reporting set allows for.
func _speed_limit_kn(t: Track, c: SensorContact) -> float:
	match t.mover():
		"land":
			return 0.0
		"surface", "subsurface":
			return minf(c.bearing_speed_limit_kn, BearingSolution.SHIP_SPEED_LIMIT_KN)
		"air":
			return maxf(c.bearing_speed_limit_kn, 1200.0)
	return c.bearing_speed_limit_kn


## What one bearing does to the plot. A good enough solution is plotted as an estimated fix.
## Without one, a range the track already holds is dead-reckoned and slid onto the new line with
## its ellipse growing, until it is too old or too loose to call a range; after that, and for a
## contact that never had one, the plot is only the line, carried at whatever range it last had.
func _bearing_plot(t: Track, raw: SensorContact, report: Dictionary, solution: Dictionary, now: float, dt: float, fresh: bool) -> SensorContact:
	var held := t._cycle_range_held
	if not solution.is_empty() and float(solution["quality"]) >= (Track.RANGE_HELD_QUALITY if held else RANGE_ACCEPT_QUALITY):
		return _resolved_contact(raw, solution)
	var c := _resolved_contact(raw, {"position": raw.position, "major": raw.error_major_nm, "minor": raw.error_minor_nm, "axis": raw.error_axis_deg, "quality": 0.0})
	if fresh:
		return c
	c.placed = true
	var start := t._cycle_start_position
	if held and t.has_kinematics:
		start += Geo.heading_to_vector(t.course_deg) * Geo.knots_to_nm_per_s(t.speed_kn) * dt
	var range_nm := raw.range_nm
	c.position = start
	if raw.bearing_key != "":
		var line := float(report.get("smooth", raw.error_axis_deg))
		var along := Geo.heading_to_vector(line)
		range_nm = clampf((start - raw.bearing_origin).dot(along), MIN_BEARING_RANGE_NM, maxf(raw.bearing_range_limit_nm, MIN_BEARING_RANGE_NM))
		c.position = start.lerp(raw.bearing_origin + along * range_nm, BEARING_BLEND)
		c.error_axis_deg = line
		c.error_minor_nm = maxf(range_nm * tan(deg_to_rad(raw.bearing_accuracy_deg * 2.0)), 0.2)
	var major := t._cycle_start_major + t.error_growth_nm_per_s() * dt
	if held:
		# The same measure a solution is graded by, taken off as the ellipse grows.
		var quality := t._cycle_tma_start - t.error_growth_nm_per_s() * dt / maxf(range_nm * 0.5, 0.5)
		if now - t.range_time > t.lost_after_s():
			quality = 0.0
		if quality >= Track.RANGE_HELD_QUALITY:
			c.solution_quality = quality
			c.error_major_nm = maxf(major, c.error_minor_nm)
			return c
	# Only the line is left. Its length is the set's to say, not the old fix's.
	c.error_major_nm = maxf(raw.error_major_nm, c.error_minor_nm)
	return c


func tick(now: float, dt: float) -> void:
	for faction in _tracks.keys():
		var list: Array = _tracks[faction]
		for i in range(list.size() - 1, -1, -1):
			var t: Track = list[i]
			var age := t.age_s(now)
			# Retain the plot through the destruction event so its radio report has a track number.
			if t.confirmed_destroyed or age > t.lost_after_s():
				t.status = Track.Status.LOST
				list.remove_at(i)
				if _by_target.has(faction):
					_by_target[faction].erase(t.truth)
				_release_number(t)
				if not t.confirmed_destroyed:
					track_lost.emit(faction, t)
				continue
			if is_equal_approx(t.last_seen_time, now):
				continue
			if age > t.stale_after_s():
				t.status = Track.Status.STALE
			# Dead reckoning is worth something while the ellipse is small. Past that the contact
			# has had time to go anywhere in it, and the plot stays where it is and fades.
			if t.has_kinematics and t.position_error_nm < Track.COAST_LIMIT_NM:
				t.position += Geo.heading_to_vector(t.course_deg) * Geo.knots_to_nm_per_s(t.speed_kn) * dt
			var growth := t.error_growth_nm_per_s() * dt
			t.error_major_nm += growth
			t.error_minor_nm += growth
			t.position_error_nm = maxf(t.error_major_nm, t.error_minor_nm)
			t.tma_quality = maxf(t.tma_quality - TMA_DECAY_PER_S * dt, 0.0)


## Battle damage assessment. A hit by this side's own weapon on the unit one of its held tracks
## follows raises that track's estimate by the round's damage over the class's catalogue health
## when the class is known, else over a generic pool. Only the shooter's side learns anything,
## and it learns it from its own hit, not from the target's true health.
func record_hit(faction: String, spec: WeaponSpec, target: Unit) -> void:
	if spec == null or target == null:
		return
	_mark_datum(faction, target)
	var t := find_track(faction, target)
	if t == null or t.status == Track.Status.LOST or t.confirmed_destroyed:
		return
	# Estimated damage cannot confirm destruction: catalogue health and actual damage can
	# differ. Reserve the 100% readout for a confirmed loss.
	t.damage_estimate = minf(t.damage_estimate + 100.0 * spec.damage / assessed_health(t, spec.id), 99.0)


## A hit on a contact nobody is holding tells the shooter's side one thing: its round found
## something where the plot was. Whatever that was is not sailing on at its old course and speed,
## so every picture of that side that holds the contact only as a stale plot keeps it as a fixed
## datum from here, until someone looks again or it ages out.
func _mark_datum(faction: String, target: Unit) -> void:
	for key in _by_target:
		var t: Track = (_by_target[key] as Dictionary).get(target)
		if t != null and t.owner_faction == faction and t.status == Track.Status.STALE:
			_reset_kinematics(t)


## The damage pool a side assumes for a contact: the catalogue health of the class its track
## reports, else GENERIC_HEALTH. `hint_id` picks between catalogues that share a class name.
static func assessed_health(t: Track, hint_id := "") -> float:
	if t.classification >= Track.Classification.CLASS_KNOWN and t.known_class != "":
		var spec := DataDB.platform_by_short_name(t.known_class, hint_id)
		if spec != null and spec.health > 0.0:
			return spec.health
	return GENERIC_HEALTH


## Record a loss only on pictures with a current fix. A stale plot, bearing or unverified
## intelligence report continues to age like any other unwitnessed contact.
func record_kill(target: Unit) -> void:
	for key in _by_target:
		var index: Dictionary = _by_target[key]
		var t: Track = index.get(target)
		if t != null and t.status == Track.Status.ACTIVE and not t.is_bearing_only() and not t.reported:
			t.confirmed_destroyed = true
			t.damage_estimate = 100.0


func on_weapon_impact(faction: String, spec: WeaponSpec, target: Unit, hit: bool) -> void:
	if hit:
		record_hit(faction, spec, target)


func on_unit_destroyed(target: Unit, _killer_faction: String) -> void:
	record_kill(target)


## Gives up a dropped track's number once no picture of its side holds the contact any longer.
## A contact confirmed destroyed keeps its number: there is nothing left to find again.
func _release_number(t: Track) -> void:
	if t.confirmed_destroyed or t.truth == null:
		return
	for key in _by_target:
		var other: Track = (_by_target[key] as Dictionary).get(t.truth)
		if other != null and other.owner_faction == t.owner_faction:
			return
	var identity_key := "%s:%s" % [t.owner_faction, _unit_key(t.truth)]
	if _track_ids.get(identity_key, "") == t.id:
		_track_ids.erase(identity_key)
		_dropped_ids[identity_key] = {"id": t.id, "position": t.position, "error": t.position_error_nm}


func _any_contributor_linked(t: Track) -> bool:
	for u: Unit in t.contributors:
		if u.datalink_connected():
			return true
	return false


func _resolved_contact(raw: SensorContact, solution: Dictionary) -> SensorContact:
	if solution.is_empty():
		return raw
	var c := SensorContact.new()
	for field in ["target", "observer", "source", "sensor_id", "sensor_name", "quality", "classify_rate", "range_nm", "altitude_m", "visual_identification"]:
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
	elif not c.bearing_only:
		# A measured plot says at once what kind of thing it is, which is all a weapon needs to
		# know to be laid on it. A bearing says nothing of the kind until it has been listened to.
		t.classification = maxi(t.classification, Track.Classification.SURFACE) as Track.Classification
		t.domain = _plot_domain(c)
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
	# Aircraft only, and only close: a firm radar plot held long enough gives a probable type from
	# the return itself. Ships are still not classified by a generic radar plot (see above).
	if c.source == "radar" and c.target.in_flight() and c.range_nm <= RADAR_RECOGNITION_NM and t.classification < Track.Classification.CLASS_KNOWN:
		t.radar_recognition_s += maxf(gain - t._cycle_radar_gain, 0.0)
		t._cycle_radar_gain = maxf(gain, t._cycle_radar_gain)
		if t.radar_recognition_s >= RADAR_RECOGNITION_S:
			t.classification = Track.Classification.CLASS_KNOWN
			t.known_class = c.target.spec.short_name
			t.known_category = c.target.spec.category
			t.class_is_probable = true
			t.class_evidence = "Radar recognition"
			var aff := String(recognition_affiliations.get(faction, {}).get(c.target.spec.id, ""))
			if t.identity == "UNKNOWN" and aff in ["HOSTILE", "NEUTRAL", "FRIENDLY"]:
				t.identity = aff
				t.identity_evidence = "Scenario recognition brief"
	if c.visual_identification:
		# A look recognises the class and the colours it wears; the name is read only close to.
		t.classification = maxi(t.classification, Track.Classification.CLASS_KNOWN) as Track.Classification
		if c.visual_named:
			t.classification = Track.Classification.IDENTIFIED
			t.known_callsign = c.target.callsign
		t.domain = c.target.spec.domain
		t.known_class = c.target.spec.short_name
		t.known_category = c.target.spec.category
		t.class_is_probable = false
		t.class_evidence = "Visual recognition"
		# Markings provide positive affiliation, independently of a library's probable class.
		t.identity = "NEUTRAL" if neutral_factions.has(c.target.faction) else ("FRIENDLY" if c.target.faction == faction else "HOSTILE")
		t.identity_evidence = "Visual markings"
	if previous != [t.classification, t.identity]:
		if t.networked:
			track_classified.emit(faction, t)
		elif c.observer != null and not c.observer.datalink_connected():
			local_track_classified.emit(c.observer, t)


## What a measured plot is, from the plot alone: something with height is an aircraft; an echo
## from below the surface is a submarine; anything else is on the sea, or ashore if it stands
## where the chart shows a fixed site.
static func _plot_domain(c: SensorContact) -> String:
	if c.altitude_m > 0.0 or (c.source == "visual" and c.target.in_flight()):
		return "air"
	if c.source == "sonar_active":
		return "subsurface" if c.target.depth_m > 0.5 else "surface"
	if c.target.spec.domain == "land":
		return "land"
	return "surface"


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
			elif not observer.datalink_connected():
				local_track_classified.emit(observer, t)


func _update_kinematics(t: Track, now: float) -> void:
	if t.domain == "land":
		# A fixed site has no course and speed; a fit through its plots would only be their scatter.
		if t.has_kinematics:
			_reset_kinematics(t)
		return
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
	t._obs_estimated = false
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
	_dropped_ids.clear()
	_next_number.clear()
