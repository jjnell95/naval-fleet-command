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
const MANOEUVRE_FULL_DEG := 3.0  # heading change per cycle that counts as fully manoeuvring
const INITIAL_RANGE_FRACTION := 0.55  # what an operator assumes before working the problem
const ESM_CLASSIFY_BONUS := 2.2  # a radar type is a fingerprint
const CZ_BEARING_PENALTY := 1.5  # a zone bearing is blurred by the long refracted path
const CZ_QUALITY := 0.25
const CZ_CLASSIFY_FACTOR := 0.5

var unit_manager: UnitManager
var track_manager: TrackManager
var threat_manager: ThreatManager
var weapon_manager: WeaponManager
var aviation_manager: AviationManager
var rng := RandomNumberGenerator.new()
var _accum := 0.0
var _last_heading: Dictionary = {}  # Unit -> float
var _manoeuvre: Dictionary = {}  # Unit -> 0..1
## Development switch: run the original pair-by-pair cycle instead of the one that works out each
## unit's figures once per cycle. Both make the same reports in the same order with the same
## random draws, so the tracks come out identical (tests/test_sensor_cycle.gd checks it), and
## tools/measure_sensor_cycle.gd times one against the other. Never set in play.
var reference_path := false


## What every unit presents to the radar and ESM passes this cycle, worked out once instead of once
## per observer-target pair. Nothing moves, switches a set or takes damage inside a sensor cycle,
## so each figure is exactly what the Detection function it replaces returns for that pair.
class CycleFacts:
	extends RefCounted
	var units: Array[Unit] = []
	var others: Dictionary = {}  # faction -> engageable units of every other side, in unit order
	var position := PackedVector2Array()
	var mast := PackedFloat64Array()  # Detection.mast_or_altitude_m, both ends of a sight line
	var mast_root := PackedFloat64Array()  # its square root, the target's share of a radar horizon
	var signature := PackedFloat64Array()  # Detection.radar_signature_of
	var in_flight := PackedByteArray()
	var clutter := PackedFloat64Array()  # Detection.clutter_factor, for a target on the surface
	var emitting := PackedByteArray()  # Unit.radar_emitting
	var power := PackedFloat64Array()  # Detection.emitted_radar_power
	var emitter_root := PackedFloat64Array()  # square root of Detection.emitter_height_m
	## Sight lines already walked this cycle, observer-major: 0 not yet, 1 clear, 2 masked. A
	## radar plot and an ESM bearing from the same unit on the same contact share one walk.
	var masks := PackedByteArray()
	var terrain := false

	func _init(list: Array[Unit]) -> void:
		units = list
		var n := list.size()
		position.resize(n)
		mast.resize(n)
		mast_root.resize(n)
		signature.resize(n)
		in_flight.resize(n)
		clutter.resize(n)
		emitting.resize(n)
		power.resize(n)
		emitter_root.resize(n)
		masks.resize(n * n)
		masks.fill(0)
		terrain = not Terrain.is_empty()
		var engageable := PackedInt32Array()
		var factions: Dictionary = {}
		for i in n:
			var u := list[i]
			if not u.is_engageable():
				continue
			engageable.append(i)
			factions[u.faction] = true
			position[i] = u.position
			mast[i] = Detection.mast_or_altitude_m(u)
			mast_root[i] = sqrt(maxf(mast[i], 0.0))
			signature[i] = Detection.radar_signature_of(u)
			in_flight[i] = 1 if u.in_flight() else 0
			clutter[i] = Detection.clutter_factor(signature[i])
			emitting[i] = 1 if u.radar_emitting() else 0
			if emitting[i]:
				power[i] = Detection.emitted_radar_power(u)
				emitter_root[i] = sqrt(maxf(Detection.emitter_height_m(u), 0.0))
		for faction in factions:
			var list_for := PackedInt32Array()
			for i in engageable:
				if list[i].faction != faction:
					list_for.append(i)
			others[faction] = list_for

	## Detection.terrain_masks for this ordered pair, walked at most once a cycle.
	func masked(observer: int, target: int) -> bool:
		if not terrain:
			return false
		var k := observer * units.size() + target
		var known := masks[k]
		if known == 0:
			known = 2 if Terrain.masks_line_of_sight(position[observer], mast[observer], position[target], mast[target]) else 1
			masks[k] = known
		return known == 2


func tick(dt: float) -> void:
	_accum += dt
	while _accum >= SENSOR_DT - 1e-6:
		_accum -= SENSOR_DT
		run_cycle(SimClock.sim_time)


func run_cycle(now: float) -> void:
	_update_manoeuvre()
	Detection.refresh_jammers(unit_manager.units)
	Detection.begin_jamming_batch()
	var radar_us := 0
	var sonar_us := 0
	var esm_us := 0
	var facts: CycleFacts = null if reference_path else CycleFacts.new(unit_manager.units)
	var cz_outer := _cz_outer_nm()
	for i in unit_manager.units.size():
		var observer := unit_manager.units[i]
		if not observer.is_engageable():
			continue
		# One observer at a time, radar then sonar then ESM, whichever path runs: that order is
		# the order of the random draws, and so of every seeded outcome.
		var at := Time.get_ticks_usec()
		if facts == null:
			_radar_pass(observer, now)
		else:
			_radar_pass_indexed(facts, i, now)
		var mid := Time.get_ticks_usec()
		if facts == null:
			_sonar_pass(observer, now)
		else:
			_sonar_pass_indexed(facts, i, cz_outer, now)
		var late := Time.get_ticks_usec()
		if facts == null:
			_esm_pass(observer, now)
		else:
			_esm_pass_indexed(facts, i, now)
		radar_us += mid - at
		sonar_us += late - mid
		esm_us += Time.get_ticks_usec() - late
		_visual_pass(observer, now)
	Debug.time_add("sensors/radar", radar_us)
	Debug.time_add("sensors/sonar", sonar_us)
	Debug.time_add("sensors/esm", esm_us)
	var step := Time.get_ticks_usec()
	_buoy_pass(now)
	Debug.time_add("sensors/buoys", Time.get_ticks_usec() - step)
	step = Time.get_ticks_usec()
	track_manager.tick(now, SENSOR_DT)
	Debug.time_add("sensors/tracks", Time.get_ticks_usec() - step)
	step = Time.get_ticks_usec()
	_detect_weapons(now)
	Debug.time_add("sensors/weapons", Time.get_ticks_usec() - step)
	Detection.end_jamming_batch()


## Legacy saved heading history; range estimation now uses measured observer positions.
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
		var c := SensorContact.make(target, obs, TrackManager.BASE_ERROR_NM + TrackManager.ERROR_PER_NM * d, q, rate, d, "radar", observer, Detection.radar_sensor_for(observer, target))
		track_manager.observe_contact(observer.faction, c, now, SENSOR_DT)


## The radar pass on the cycle's figures. The same arithmetic as Detection.radar_quality and
## radar_sensor_for, in the same order, so every range, quality and credited set is bit for bit
## what the reference computes. A pair is let go as soon as it is out of unjammed reach, because a
## jammer only ever shortens it.
func _radar_pass_indexed(facts: CycleFacts, oi: int, now: float) -> void:
	var observer := facts.units[oi]
	if not facts.emitting[oi]:
		return
	var rate := Detection.classify_rate(observer)
	var efficiency := observer.sensor_efficiency()
	var sets: Array[SensorSpec] = []
	var air_reach := PackedFloat64Array()
	var surface_reach := PackedFloat64Array()
	var height_root := PackedFloat64Array()
	for s in observer.sensors:
		if s.kind == "radar":
			sets.append(s)
			air_reach.append(s.range_air_nm)
			surface_reach.append(s.range_surface_nm)
			# The radar range functions take a height below zero to mean the antenna's own.
			var height := Detection.observer_height_m(observer, s)
			height_root.append(sqrt(maxf(height if height >= 0.0 else s.antenna_height_m, 0.0)))
	var from := facts.position[oi]
	for ti: int in facts.others[observer.faction]:
		var signature := facts.signature[ti]
		if signature <= 0.0:
			continue
		var target_root := facts.mast_root[ti]
		var airborne := facts.in_flight[ti] == 1
		var reach := air_reach if airborne else surface_reach
		var best := 0.0
		var sensor: SensorSpec = null
		for k in sets.size():
			var r := minf(reach[k] * signature, Detection.HORIZON_K * (height_root[k] + target_root))
			if r > best:
				best = r
				sensor = sets[k]
		var r := best * efficiency if airborne else best * efficiency * facts.clutter[ti]
		var d := from.distance_to(facts.position[ti])
		if r <= 0.0 or d > r:
			continue
		r *= Detection.jam_penalty(observer, facts.position[ti])
		if r <= 0.0 or d > r:
			continue
		if facts.masked(oi, ti):
			continue  # in range, but there is a hill in the way
		var q := clampf(1.0 - d / r, 0.0, 1.0)
		if q <= 0.0:
			continue
		var target := facts.units[ti]
		var sigma := OBS_SIGMA_BASE_NM + OBS_SIGMA_PER_NM * d
		var obs := target.position + Vector2(rng.randfn(0.0, sigma), rng.randfn(0.0, sigma))
		var c := SensorContact.make(target, obs, TrackManager.BASE_ERROR_NM + TrackManager.ERROR_PER_NM * d, q, rate, d, "radar", observer, sensor)
		track_manager.observe_contact(observer.faction, c, now, SENSOR_DT)


func _sonar_pass(observer: Unit, now: float) -> void:
	if not observer.has_sonar():
		return
	var rate := Detection.sonar_classify_rate(observer)
	var active_ceiling := Detection.best_active_sonar_nm(observer)  # before the water has its say
	var cz_outer := 0.0
	for z: Dictionary in Acoustics.zones():
		cz_outer = maxf(cz_outer, float(z["range_nm"]) + float(z["half_width_nm"]))
	for target in unit_manager.units:
		if target == observer or not target.is_engageable() or target.faction == observer.faction or target.is_aircraft():
			continue
		var d := observer.position.distance_to(target.position)
		var active_reach := Detection.active_sonar_reach_nm(observer, target) if active_ceiling > 0.0 and d <= active_ceiling else 0.0
		var passive := Detection.best_passive_sonar(observer, target)
		var reach: float = passive["range_nm"]
		var sensor: SensorSpec = passive["sensor"]
		# An active transmitter is a loud noise in its own right, heard well past its own reach.
		var emission := Detection.active_sonar_detection_nm(observer, target)
		if emission > reach:
			reach = emission
			if sensor == null:
				sensor = _first_sonar(observer)
		var in_passive_reach := sensor != null and reach > 0.0 and d <= reach
		if d > active_reach and not in_passive_reach and d > cz_outer:
			continue  # out of every reach: what lies between does not matter, and the land walk is the dear part
		if Detection.acoustic_path_blocked(observer, target):
			continue  # sound does not go through rock, pinging or listening
		if d <= active_reach:
			_report_active(observer, target, d, active_reach, rate, now)
			continue
		if in_passive_reach:
			_report_passive(observer, target, d, reach, sensor, rate, now)
		elif d <= cz_outer:
			_try_convergence_zone(observer, target, d, rate, now)


## The outer edge of the last convergence zone, 0 with none.
func _cz_outer_nm() -> float:
	var cz_outer := 0.0
	for z: Dictionary in Acoustics.zones():
		cz_outer = maxf(cz_outer, float(z["range_nm"]) + float(z["half_width_nm"]))
	return cz_outer


## The sonar pass over the cycle's list of other sides' units. The water is left to the same
## Detection and Acoustics calls, in the same order, as the reference: the sea-floor sample under
## a unit is taken by whichever of them first asks for it in a cycle.
func _sonar_pass_indexed(facts: CycleFacts, oi: int, cz_outer: float, now: float) -> void:
	var observer := facts.units[oi]
	if not observer.has_sonar():
		return
	var rate := Detection.sonar_classify_rate(observer)
	var active_ceiling := Detection.best_active_sonar_nm(observer)
	for ti: int in facts.others[observer.faction]:
		var target := facts.units[ti]
		if target.is_aircraft():
			continue
		var d := observer.position.distance_to(target.position)
		var active_reach := Detection.active_sonar_reach_nm(observer, target) if active_ceiling > 0.0 and d <= active_ceiling else 0.0
		# Detection.best_passive_sonar, without a dictionary for every pair.
		var reach := 0.0
		var sensor: SensorSpec = null
		for s in observer.sensors:
			if s.kind != "sonar":
				continue
			var r := Detection.passive_sonar_range_nm(observer, s, target)
			if r > reach:
				reach = r
				sensor = s
		var emission := Detection.active_sonar_detection_nm(observer, target)
		if emission > reach:
			reach = emission
			if sensor == null:
				sensor = _first_sonar(observer)
		var in_passive_reach := sensor != null and reach > 0.0 and d <= reach
		if d > active_reach and not in_passive_reach and d > cz_outer:
			continue
		if Detection.acoustic_path_blocked(observer, target):
			continue
		if d <= active_reach:
			_report_active(observer, target, d, active_reach, rate, now)
			continue
		if in_passive_reach:
			_report_passive(observer, target, d, reach, sensor, rate, now)
		elif d <= cz_outer:
			_try_convergence_zone(observer, target, d, rate, now)


## Out of direct-path reach, a loud enough source can still be heard where its sound comes back up
## in a convergence zone, provided the water is deep the whole way. Checked after everything
## cheaper has failed, because the deep-water test walks the path.
func _try_convergence_zone(observer: Unit, target: Unit, d: float, rate: float, now: float) -> void:
	for s in observer.sensors:
		if s.kind != "sonar" or not s.cz_capable:
			continue
		var direct := Detection.passive_sonar_range_nm(observer, s, target, false)
		var zone := Acoustics.cz_zone_for(s, d, direct)
		if zone.is_empty():
			continue
		if not Acoustics.deep_water_path(observer.position, target.position):
			return
		_report_cz(observer, target, d, zone, s, rate, now)
		return


func _first_sonar(u: Unit) -> SensorSpec:
	for s in u.sensors:
		if s.kind == "sonar":
			return s
	return null


func _report_active(observer: Unit, target: Unit, d: float, reach: float, rate: float, now: float) -> void:
	var obs := target.position + Vector2(rng.randfn(0.0, ACTIVE_SONAR_SIGMA_NM), rng.randfn(0.0, ACTIVE_SONAR_SIGMA_NM))
	var c := SensorContact.make(target, obs, ACTIVE_SONAR_SIGMA_NM * 3.0, clampf(1.0 - d / maxf(reach, 0.1), 0.0, 1.0), rate, d, "sonar_active", observer, Detection.active_sonar_sensor_for(observer, target))
	track_manager.observe_contact(observer.faction, c, now, SENSOR_DT)


## A bearing report uses the set's nominal search area for its chart datum. Range and
## confidence come only from crossing measurements in TrackManager, never target range.
func _report_passive(observer: Unit, target: Unit, d: float, reach: float, sensor: SensorSpec, rate: float, now: float) -> void:
	var bearing := Geo.bearing_deg(observer.position, target.position) + rng.randfn(0.0, sensor.bearing_accuracy_deg)
	var search_range := maxf(sensor.passive_sensitivity_nm, 1.0)
	var c := _bearing_contact(target, observer, bearing, sensor.bearing_accuracy_deg, search_range, "sonar_passive", sensor)
	c.quality = clampf(1.0 - d / reach, 0.0, 1.0)
	c.classify_rate = rate
	track_manager.observe_contact(observer.faction, c, now, SENSOR_DT)


func _bearing_contact(target: Unit, observer: Unit, bearing: float, accuracy: float, search_range: float, source: String, sensor: SensorSpec) -> SensorContact:
	var c := SensorContact.new()
	var estimate := maxf(search_range * INITIAL_RANGE_FRACTION, 0.3)
	c.target = target
	c.observer = observer
	c.bearing_origin = observer.position
	c.bearing_key = "unit:" + TrackManager._unit_key(observer) + ":" + source
	c.bearing_accuracy_deg = accuracy
	c.bearing_range_limit_nm = search_range * 6.0
	c.bearing_speed_limit_kn = 1200.0 if source == "esm" else 70.0
	c.position = observer.position + Geo.heading_to_vector(bearing) * estimate
	c.error_minor_nm = maxf(estimate * tan(deg_to_rad(accuracy * 2.0)), 0.2)
	c.error_major_nm = maxf(search_range * 0.8, c.error_minor_nm)
	c.error_axis_deg = bearing
	c.bearing_only = true
	c.source = source
	c.set_sensor(sensor)
	return c


## A convergence-zone ring contributes its measured propagation band, not an exact range.
func _report_cz(observer: Unit, target: Unit, _d: float, zone: Dictionary, sensor: SensorSpec, rate: float, now: float) -> void:
	var accuracy := sensor.bearing_accuracy_deg * CZ_BEARING_PENALTY
	var bearing := Geo.bearing_deg(observer.position, target.position) + rng.randfn(0.0, accuracy)
	var zone_range: float = zone["range_nm"]
	var half_width: float = zone["half_width_nm"]
	var c := _bearing_contact(target, observer, bearing, accuracy, zone_range, "sonar_cz", sensor)
	c.position = observer.position + Geo.heading_to_vector(bearing) * zone_range
	c.error_minor_nm = maxf(zone_range * tan(deg_to_rad(accuracy * 2.0)), 0.3)
	c.error_major_nm = maxf(half_width, c.error_minor_nm)
	c.quality = CZ_QUALITY / float(zone["index"])
	c.classify_rate = rate * CZ_CLASSIFY_FACTOR
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
		if Detection.terrain_masks(observer, emitter):
			continue  # the horizon this set already respects is not the only thing in the way
		_report_esm(observer, emitter, d, reach, sensor, now)


## The ESM pass on the cycle's figures: Detection.best_esm's arithmetic in its order, with each
## emitter's power and antenna height taken once a cycle instead of once per listener.
func _esm_pass_indexed(facts: CycleFacts, oi: int, now: float) -> void:
	var observer := facts.units[oi]
	var sets: Array[SensorSpec] = []
	var gains := PackedFloat64Array()
	var height_root := PackedFloat64Array()
	for s in observer.sensors:
		if s.kind == "esm":
			sets.append(s)
			gains.append(s.esm_gain)
			height_root.append(sqrt(maxf(Detection.observer_height_m(observer, s), 0.0)))
	if sets.is_empty():
		return
	var efficiency := observer.sensor_efficiency()
	var from := facts.position[oi]
	for ti: int in facts.others[observer.faction]:
		if facts.emitting[ti] == 0:
			continue
		var power := facts.power[ti]
		var reach := 0.0
		var sensor: SensorSpec = null
		for k in sets.size():
			var r := 0.0
			if power > 0.0:
				r = minf(power * gains[k], Detection.HORIZON_K * (height_root[k] + facts.emitter_root[ti]))
			r *= efficiency
			if r > reach:
				reach = r
				sensor = sets[k]
		if sensor == null or reach <= 0.0:
			continue
		var d := from.distance_to(facts.position[ti])
		if d > reach:
			continue
		if facts.masked(oi, ti):
			continue  # the horizon this set already respects is not the only thing in the way
		_report_esm(observer, facts.units[ti], d, reach, sensor, now)


func _report_esm(observer: Unit, emitter: Unit, d: float, reach: float, sensor: SensorSpec, now: float) -> void:
	var bearing := Geo.bearing_deg(observer.position, emitter.position) + rng.randfn(0.0, sensor.bearing_accuracy_deg)
	var c := _bearing_contact(emitter, observer, bearing, sensor.bearing_accuracy_deg, reach, "esm", sensor)
	c.quality = clampf(1.0 - d / reach, 0.0, 1.0)
	c.classify_rate = sensor.classify_rate * ESM_CLASSIFY_BONUS
	track_manager.observe_contact(observer.faction, c, now, SENSOR_DT)


## Recognition needs a close, unobscured look. This is separate from radar, so an EMCON patrol
## can identify a ship. These distances are conservative gameplay optical recognition limits.
func _visual_pass(observer: Unit, now: float) -> void:
	if observer.submerged():
		return
	for target in unit_manager.units:
		if target == observer or target.faction == observer.faction or not target.is_engageable() or target.submerged():
			continue
		var d := observer.position.distance_to(target.position)
		var limit := 3.0 if target.is_aircraft() else 6.0
		limit = minf(limit, float(Detection.environment.get("visibility_nm", 12.0)))
		if d > limit:
			continue
		if d > Detection.radar_horizon_nm(Detection.mast_or_altitude_m(observer), Detection.mast_or_altitude_m(target)):
			continue
		if Detection.terrain_masks(observer, target):
			continue
		var c := SensorContact.make(target, target.position, 0.08, 1.0, 1.0, d, "visual", observer)
		c.visual_identification = true
		c.sensor_id = "lookout"
		c.sensor_name = "Visual recognition"
		track_manager.observe_contact(observer.faction, c, now, SENSOR_DT)


## A directional buoy reports a bearing. A field resolves range only with useful geometry.
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
			if Terrain.blocks_path(b.position, target.position):
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
	# Each directional buoy sends a bearing. Coincident or nearly parallel bearings add
	# detection coverage but do not manufacture a precision fix.
	for b: Sonobuoy in buoys:
		var c := SensorContact.new()
		var bearing := Geo.bearing_deg(b.position, target.position) + rng.randfn(0.0, 1.5)
		var estimate := b.sensitivity_nm * INITIAL_RANGE_FRACTION
		c.target = target
		c.classify_rate = 0.8
		c.source = "sonobuoy"
		c.sensor_id = "sonobuoy"
		c.sensor_name = "Sonobuoy field" if buoys.size() >= 2 else "Sonobuoy"
		c.bearing_origin = b.position
		c.bearing_key = "buoy:%d" % b.id
		c.bearing_accuracy_deg = 1.5
		c.bearing_range_limit_nm = b.sensitivity_nm * 6.0
		c.bearing_only = true
		c.position = b.position + Geo.heading_to_vector(bearing) * estimate
		c.error_axis_deg = bearing
		c.error_major_nm = b.sensitivity_nm * 0.8
		c.error_minor_nm = maxf(estimate * tan(deg_to_rad(3.0)), 0.2)
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
	# Flatten the exact type/altitude range groups once. Do not rebuild each round's flight
	# profile and nested dictionary lookup for every radar installation in a large raid.
	var weapons: Array[Weapon] = []
	var group_indices := PackedInt32Array()
	var group_specs: Array[WeaponSpec] = []
	var group_altitudes := PackedFloat64Array()
	var group_torpedoes: Array[bool] = []
	var groups := {}
	for w: Weapon in weapon_manager.in_flight:
		if w.phase == Weapon.Phase.DEAD:
			continue
		var altitude := w.flight_altitude_m()
		var heights: Dictionary = groups.get(w.spec, {})
		if not heights.has(altitude):
			heights[altitude] = group_specs.size()
			groups[w.spec] = heights
			group_specs.append(w.spec)
			group_altitudes.append(altitude)
			group_torpedoes.append(w.spec.is_torpedo())
		weapons.append(w)
		group_indices.append(heights[altitude])
	for observer in unit_manager.units:
		if not observer.is_engageable():
			continue
		var radar_up := observer.radar_emitting()
		var sonar_up := observer.has_sonar()
		if not radar_up and not sonar_up:
			continue
		var reaches := PackedFloat64Array()
		for group in group_specs.size():
			var spec := group_specs[group]
			var altitude := group_altitudes[group]
			var reach := Detection.torpedo_detection_nm(observer, spec) if group_torpedoes[group] and sonar_up else 0.0
			if not group_torpedoes[group] and radar_up:
				reach = Detection.best_weapon_detection_nm(observer, spec, altitude) * Detection.weapon_clutter_factor(spec, altitude)
			reaches.append(reach)
		for i in weapons.size():
			var w := weapons[i]
			if w.faction == observer.faction or w.phase == Weapon.Phase.DEAD:
				continue
			var group := group_indices[i]
			var reach := reaches[group]
			if reach <= 0.0 or observer.position.distance_squared_to(w.position) > reach * reach:
				continue
			if not group_torpedoes[group]:
				reach *= Detection.jam_penalty(observer, w.position)
			if reach <= 0.0 or observer.position.distance_squared_to(w.position) > reach * reach:
				continue
			if Detection.terrain_hides_weapon(observer, w):
				continue
			threat_manager.mark_detected(observer.faction, w, now, observer)
			if track_manager != null:
				track_manager.observe_hostile_launch(observer, w, now)
