class_name SensorManager
extends Node
## Runs sensor cycles at SENSOR_DT and feeds observations to the TrackManager.
## Every faction is processed the same way: the AI reads the same track picture the player does.
##
## Two independent channels. Radar gives a firm plot but cannot see under water and announces the
## sender. Sonar hears everything that makes noise, but passively it gives a bearing and only a
## guess at range until the listener has manoeuvred enough to work up a solution.

const SENSOR_DT := 1.0
const OBS_SIGMA_BASE_NM := 0.05  # GAMEPLAY: radar plot error
const OBS_SIGMA_PER_NM := 0.003
const ACTIVE_SONAR_SIGMA_NM := 0.12
const TMA_BASE_PER_S := 0.005  # a still listener needs several minutes for a solution
const TMA_MANOEUVRE_GAIN := 1.6
const MANOEUVRE_FULL_DEG := 3.0  # heading change per cycle that counts as fully manoeuvring
const INITIAL_RANGE_FRACTION := 0.55  # what an operator assumes before working the problem
const RANGE_GUESS_NOISE := 0.15
const ESM_CLASSIFY_BONUS := 2.2  # a radar type is a fingerprint

var unit_manager: UnitManager
var track_manager: TrackManager
var threat_manager: ThreatManager
var weapon_manager: WeaponManager
var aviation_manager: AviationManager
var rng := RandomNumberGenerator.new()
var _accum := 0.0
var _last_heading: Dictionary = {}  # Unit -> float
var _manoeuvre: Dictionary = {}  # Unit -> 0..1


func tick(dt: float) -> void:
	_accum += dt
	while _accum >= SENSOR_DT - 1e-6:
		_accum -= SENSOR_DT
		run_cycle(SimClock.sim_time)


func run_cycle(now: float) -> void:
	_update_manoeuvre()
	Detection.refresh_jammers(unit_manager.units)
	for observer in unit_manager.units:
		if not observer.is_engageable():
			continue
		_radar_pass(observer, now)
		_sonar_pass(observer, now)
		_esm_pass(observer, now)
	_buoy_pass(now)
	track_manager.tick(now, SENSOR_DT)
	_detect_weapons(now)


## How hard each unit is turning, which is what lets a passive listener resolve range.
func _update_manoeuvre() -> void:
	for u in unit_manager.units:
		var previous: float = _last_heading.get(u, u.heading_deg)
		var delta := absf(Geo.heading_delta(previous, u.heading_deg))
		_last_heading[u] = u.heading_deg
		_manoeuvre[u] = clampf(delta / MANOEUVRE_FULL_DEG, 0.0, 1.0)


func _radar_pass(observer: Unit, now: float) -> void:
	if not observer.radar_emitting():
		return
	var rate := Detection.classify_rate(observer)
	for target in unit_manager.units:
		if target == observer or not target.is_engageable() or target.faction == observer.faction:
			continue
		var q := Detection.radar_quality(observer, target)
		if q <= 0.0:
			continue
		var d := observer.position.distance_to(target.position)
		var sigma := OBS_SIGMA_BASE_NM + OBS_SIGMA_PER_NM * d
		var obs := target.position + Vector2(rng.randfn(0.0, sigma), rng.randfn(0.0, sigma))
		var c := SensorContact.make(target, obs, TrackManager.BASE_ERROR_NM + TrackManager.ERROR_PER_NM * d, q, rate, d, "radar", observer)
		track_manager.observe_contact(observer.faction, c, now, SENSOR_DT)


func _sonar_pass(observer: Unit, now: float) -> void:
	if not observer.has_sonar():
		return
	var rate := Detection.sonar_classify_rate(observer)
	var active_reach := Detection.best_active_sonar_nm(observer)
	for target in unit_manager.units:
		if target == observer or not target.is_engageable() or target.faction == observer.faction or target.is_aircraft():
			continue
		var d := observer.position.distance_to(target.position)
		if active_reach > 0.0 and d <= active_reach:
			_report_active(observer, target, d, rate, now)
			continue
		var passive := Detection.best_passive_sonar(observer, target)
		var reach: float = passive["range_nm"]
		var sensor: SensorSpec = passive["sensor"]
		# An active transmitter is a loud noise in its own right, heard well past its own reach.
		var emission := Detection.active_sonar_detection_nm(observer, target)
		if emission > reach:
			reach = emission
			if sensor == null:
				sensor = _first_sonar(observer)
		if sensor == null or reach <= 0.0 or d > reach:
			continue
		_report_passive(observer, target, d, reach, sensor, rate, now)


func _first_sonar(u: Unit) -> SensorSpec:
	for s in u.sensors:
		if s.kind == "sonar":
			return s
	return null


func _report_active(observer: Unit, target: Unit, d: float, rate: float, now: float) -> void:
	var obs := target.position + Vector2(rng.randfn(0.0, ACTIVE_SONAR_SIGMA_NM), rng.randfn(0.0, ACTIVE_SONAR_SIGMA_NM))
	var c := SensorContact.make(target, obs, ACTIVE_SONAR_SIGMA_NM * 3.0, clampf(1.0 - d / maxf(Detection.best_active_sonar_nm(observer), 0.1), 0.0, 1.0), rate, d, "sonar_active", observer)
	track_manager.observe_contact(observer.faction, c, now, SENSOR_DT)


## A bearing, and a guess at range that only firms up as the listener manoeuvres against it.
func _report_passive(observer: Unit, target: Unit, d: float, reach: float, sensor: SensorSpec, rate: float, now: float) -> void:
	var existing := track_manager.find_track(observer.faction, target)
	var tma: float = existing.tma_quality if existing != null else 0.0
	var bearing := Geo.bearing_deg(observer.position, target.position) + rng.randfn(0.0, sensor.bearing_accuracy_deg)
	var guess := reach * INITIAL_RANGE_FRACTION
	var est_range := lerpf(guess, d, tma)
	est_range += rng.randfn(0.0, (1.0 - tma) * d * RANGE_GUESS_NOISE)
	est_range = clampf(est_range, 0.3, reach * 1.5)

	var c := SensorContact.new()
	c.target = target
	c.position = observer.position + Geo.heading_to_vector(bearing) * est_range
	c.error_minor_nm = maxf(est_range * tan(deg_to_rad(sensor.bearing_accuracy_deg * 2.0)), 0.2)
	c.error_major_nm = maxf((1.0 - tma) * est_range * 0.7, c.error_minor_nm)
	c.error_axis_deg = bearing
	c.bearing_only = true
	c.quality = clampf(1.0 - d / reach, 0.0, 1.0)
	c.classify_rate = rate
	c.range_nm = d
	c.source = "sonar_passive"
	c.observer = observer
	var manoeuvre: float = _manoeuvre.get(observer, 0.0)
	c.tma_gain = TMA_BASE_PER_S * SENSOR_DT * (0.4 + TMA_MANOEUVRE_GAIN * manoeuvre)
	track_manager.observe_contact(observer.faction, c, now, SENSOR_DT)


## Anything that transmits can be heard transmitting. ESM gives a bearing and a very good idea of
## what kind of ship is at the other end, without the listener radiating at all. It is the reason
## turning a radar off is a decision rather than a handicap.
func _esm_pass(observer: Unit, now: float) -> void:
	if not observer.has_esm():
		return
	for emitter in unit_manager.units:
		if emitter == observer or not emitter.is_engageable() or emitter.faction == observer.faction:
			continue
		if not emitter.radar_emitting():
			continue
		var best := Detection.best_esm(observer, emitter)
		var reach: float = best["range_nm"]
		var sensor: SensorSpec = best["sensor"]
		if sensor == null or reach <= 0.0:
			continue
		var d := observer.position.distance_to(emitter.position)
		if d > reach:
			continue
		_report_esm(observer, emitter, d, reach, sensor, now)


func _report_esm(observer: Unit, emitter: Unit, d: float, reach: float, sensor: SensorSpec, now: float) -> void:
	var existing := track_manager.find_track(observer.faction, emitter)
	var tma: float = existing.tma_quality if existing != null else 0.0
	var bearing := Geo.bearing_deg(observer.position, emitter.position) + rng.randfn(0.0, sensor.bearing_accuracy_deg)
	var est_range := lerpf(reach * INITIAL_RANGE_FRACTION, d, tma)
	est_range += rng.randfn(0.0, (1.0 - tma) * d * RANGE_GUESS_NOISE)
	est_range = clampf(est_range, 0.3, reach * 1.5)

	var c := SensorContact.new()
	c.target = emitter
	c.observer = observer
	c.position = observer.position + Geo.heading_to_vector(bearing) * est_range
	c.error_minor_nm = maxf(est_range * tan(deg_to_rad(sensor.bearing_accuracy_deg * 2.0)), 0.2)
	c.error_major_nm = maxf((1.0 - tma) * est_range * 0.7, c.error_minor_nm)
	c.error_axis_deg = bearing
	c.bearing_only = true
	c.quality = clampf(1.0 - d / reach, 0.0, 1.0)
	# A radar type is a fingerprint, so ESM identifies what it is hearing unusually quickly.
	c.classify_rate = sensor.classify_rate * ESM_CLASSIFY_BONUS
	c.range_nm = d
	c.source = "esm"
	var manoeuvre: float = _manoeuvre.get(observer, 0.0)
	c.tma_gain = TMA_BASE_PER_S * SENSOR_DT * (0.4 + TMA_MANOEUVRE_GAIN * manoeuvre)
	track_manager.observe_contact(observer.faction, c, now, SENSOR_DT)


## A single buoy tells you something noisy is inside its circle. Two or more overlapping tell you
## roughly where it is, which is the whole reason to lay a field rather than drop one.
func _buoy_pass(now: float) -> void:
	if aviation_manager == null or aviation_manager.sonobuoys.is_empty():
		return
	var holds: Dictionary = {}  # faction -> {target -> Array[Sonobuoy]}
	for b in aviation_manager.sonobuoys:
		if not b.alive_at(now):
			continue
		for target in unit_manager.units:
			if target.faction == b.faction or not target.is_engageable() or target.is_aircraft():
				continue
			var reach := b.reach_against(target)
			if reach <= 0.0 or b.position.distance_to(target.position) > reach:
				continue
			if not holds.has(b.faction):
				holds[b.faction] = {}
			if not holds[b.faction].has(target):
				holds[b.faction][target] = []
			holds[b.faction][target].append(b)
	for faction in holds:
		for target: Unit in holds[faction]:
			var buoys: Array = holds[faction][target]
			_report_buoys(faction, target, buoys, now)


func _report_buoys(faction: String, target: Unit, buoys: Array, now: float) -> void:
	var nearest: Sonobuoy = buoys[0]
	for b: Sonobuoy in buoys:
		if b.position.distance_to(target.position) < nearest.position.distance_to(target.position):
			nearest = b
	var reach := nearest.reach_against(target)
	var c := SensorContact.new()
	c.target = target
	c.classify_rate = 0.8
	c.range_nm = nearest.position.distance_to(target.position)
	c.source = "sonobuoy"
	if buoys.size() >= 2:
		# Overlapping circles cross: that is a position, not a guess.
		var sigma := 0.35
		c.position = target.position + Vector2(rng.randfn(0.0, sigma), rng.randfn(0.0, sigma))
		c.error_major_nm = 0.8
		c.error_minor_nm = 0.8
		c.quality = 0.9
	else:
		var sigma := reach * 0.35
		c.position = target.position + Vector2(rng.randfn(0.0, sigma), rng.randfn(0.0, sigma))
		c.error_major_nm = maxf(reach * 0.5, 1.0)
		c.error_minor_nm = c.error_major_nm
		c.quality = 0.5
	track_manager.observe_contact(faction, c, now, SENSOR_DT)


## Incoming rounds are found by radar above the water and by sonar below it. A sea-skimming
## missile stays below the horizon until it is close; a torpedo is heard, not seen.
func _detect_weapons(now: float) -> void:
	if threat_manager == null or weapon_manager == null:
		return
	threat_manager.begin_cycle()
	if weapon_manager.in_flight.is_empty():
		return
	for observer in unit_manager.units:
		if not observer.is_engageable():
			continue
		var radar_up := observer.radar_emitting()
		var sonar_up := observer.has_sonar()
		if not radar_up and not sonar_up:
			continue
		for w in weapon_manager.in_flight:
			if w.faction == observer.faction or w.phase == Weapon.Phase.DEAD:
				continue
			var r := 0.0
			if w.spec.is_torpedo():
				if sonar_up:
					r = Detection.torpedo_detection_nm(observer, w.spec)
			elif radar_up:
				r = Detection.best_weapon_detection_nm(observer, w.spec) * Detection.weapon_clutter_factor(w.spec) * Detection.jam_penalty(observer, w.position)
			if r > 0.0 and observer.position.distance_to(w.position) <= r:
				threat_manager.mark_detected(observer.faction, w, now)
