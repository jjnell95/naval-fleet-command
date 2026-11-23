class_name SensorManager
extends Node
## Runs sensor cycles at SENSOR_DT and feeds observations to the TrackManager.
## Every faction is processed the same way: the AI reads the same track picture the player does.
##
## Two independent channels. Radar gives a firm plot but cannot see under water and announces the
## sender. Sonar hears everything that makes noise, but passively it gives a bearing and only a
## guess at range until the listener has manoeuvred enough to work up a solution.
##
## In play a cycle is spread over the ticks of its second: each tick takes every SLICES-th
## observer, and the last also files the buoys, ages the plots and finds the rounds in flight, so
## no one tick carries the whole cycle. Every report in it is filed as part of the cycle that began
## at the first slice (TrackManager.cycle_at), so a contact several observers hold is merged once a
## cycle, as when they all looked at once. run_cycle runs a whole cycle in one go, as tests and the
## measuring tools want it.

const SENSOR_DT := 1.0
const SLICES := 4
const SLICE_DT := SENSOR_DT / SLICES
const OBS_SIGMA_BASE_NM := 0.05  # GAMEPLAY: radar plot error
const OBS_SIGMA_PER_NM := 0.003
const ACTIVE_SONAR_SIGMA_NM := 0.12
const INITIAL_RANGE_FRACTION := 0.55  # what an operator assumes before working the problem
## How far past the reach it was heard at a contact's worked-out range may lie before the solution
## is thrown out as impossible.
const REACH_MARGIN := 1.5
const ESM_CLASSIFY_BONUS := 2.2  # a radar type is a fingerprint
const CZ_BEARING_PENALTY := 1.5  # a zone bearing is blurred by the long refracted path
const CZ_QUALITY := 0.25
const CZ_CLASSIFY_FACTOR := 0.5
## An emitter at height is heard far past the nominal line: a crossed fix out to here is believed.
const ESM_SOLUTION_LIMIT_NM := 400.0

var unit_manager: UnitManager
var track_manager: TrackManager
var threat_manager: ThreatManager
var weapon_manager: WeaponManager
var aviation_manager: AviationManager
var rng := RandomNumberGenerator.new()
var _accum := 0.0  # time towards the next slice
## The slice of the cycle that runs next, and when the cycle it belongs to began.
var _slice := 0
var _cycle_at := 0.0
## Development switch: run the original pair-by-pair passes (REFERENCE_PASSES) instead of the
## ones that work out each unit's figures once per cycle. Both make the same reports in the same
## order with the same random draws, so the tracks come out identical (tests/test_sensor_cycle.gd
## checks it), and tools/measure_sensor_cycle.gd times one against the other. Never set in play:
## the reference is a development tool and is not exported with the game.
var reference_path := false
const REFERENCE_PASSES := "res://tools/measure_sensor_cycle_reference.gd"
## Work counters for tests and the measuring tools: sonar pairs the acoustic model was run for, and
## pairs close enough for a lookout to weigh. Never read in play.
var sonar_pairs_weighed := 0
var lookout_pairs_weighed := 0


## What every unit presents to the radar and ESM passes this cycle, worked out once instead of once
## per observer-target pair. Nothing moves, switches a set or takes damage inside a sensor cycle,
## so each figure is exactly what the Detection function it replaces returns for that pair.
class CycleFacts:
	extends RefCounted
	var units: Array[Unit] = []
	var others: Dictionary = {}  # faction -> engageable units of every other side, in unit order
	var emitters: Dictionary = {}  # faction -> those of them with a radar transmitting, in unit order
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
	var submerged := PackedByteArray()
	## Square root of Detection.acoustic_noise for a unit a passive sonar can hear at all, else 0.
	var noise_root := PackedFloat64Array()
	var pinging := PackedByteArray()  # Unit.active_sonar_emitting
	## Units whose sea-floor sample a sonar pair has already asked for this cycle. A pair let go
	## before the acoustic model still asks for what the model would have, so the sample under
	## every unit is refreshed on the same cycles as when every pair ran it.
	var floor_asked := PackedByteArray()

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
		submerged.resize(n)
		noise_root.resize(n)
		pinging.resize(n)
		floor_asked.resize(n)
		floor_asked.fill(0)
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
			submerged[i] = 1 if u.submerged() else 0
			pinging[i] = 1 if u.active_sonar_emitting() else 0
			if not u.is_aircraft() and u.spec.domain != "land":
				noise_root[i] = sqrt(maxf(Detection.acoustic_noise(u), 0.0))
		for faction in factions:
			var list_for := PackedInt32Array()
			var emitting_for := PackedInt32Array()
			for i in engageable:
				if list[i].faction != faction:
					list_for.append(i)
					if emitting[i]:
						emitting_for.append(i)
			others[faction] = list_for
			emitters[faction] = emitting_for

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


## A new engagement starts a new cycle.
func reset() -> void:
	_accum = 0.0
	_slice = 0
	_cycle_at = 0.0


func tick(dt: float) -> void:
	_accum += dt
	while _accum >= SLICE_DT - 1e-6:
		_accum -= SLICE_DT
		run_slice(SimClock.sim_time)


## The next slice of the cycle: every SLICES-th observer, from the slice's own index.
func run_slice(now: float) -> void:
	if _slice == 0:
		_cycle_at = now
	_run(now, _cycle_at, _slice, SLICES, _slice == SLICES - 1)
	_slice = (_slice + 1) % SLICES


## A whole cycle at once: every observer in unit order, then the buoys, the plots and the rounds.
func run_cycle(now: float) -> void:
	_run(now, now, 0, 1, true)


func _run(now: float, cycle: float, first: int, stride: int, closes: bool) -> void:
	track_manager.cycle_at = cycle
	var setup := Time.get_ticks_usec()
	Detection.refresh_jammers(unit_manager.units)
	Detection.begin_jamming_batch()
	var spent := [0, 0, 0, 0]  # radar, sonar, ESM and lookout time, in microseconds
	var reference: GDScript = load(REFERENCE_PASSES) if reference_path else null
	var facts: CycleFacts = null if reference != null else CycleFacts.new(unit_manager.units)
	var cz_outer := _cz_outer_nm()
	Debug.time_add("sensors/setup", Time.get_ticks_usec() - setup)
	for i in range(first, unit_manager.units.size(), stride):
		var observer := unit_manager.units[i]
		if not observer.is_engageable():
			continue
		# One observer at a time, radar then sonar then ESM then the lookouts, whichever path runs:
		# that order is the order of the random draws, and so of every seeded outcome.
		if reference != null:
			reference.run_observer(self, observer, cz_outer, now, spent)
			continue
		var at := Time.get_ticks_usec()
		_radar_pass_indexed(facts, i, now)
		var mid := Time.get_ticks_usec()
		_sonar_pass_indexed(facts, i, cz_outer, now)
		var late := Time.get_ticks_usec()
		_esm_pass_indexed(facts, i, now)
		var seen := Time.get_ticks_usec()
		_visual_pass_indexed(facts, i, now)
		spent[0] += mid - at
		spent[1] += late - mid
		spent[2] += seen - late
		spent[3] += Time.get_ticks_usec() - seen
	Debug.time_add("sensors/radar", spent[0])
	Debug.time_add("sensors/sonar", spent[1])
	Debug.time_add("sensors/esm", spent[2])
	Debug.time_add("sensors/visual", spent[3])
	if closes:
		var step := Time.get_ticks_usec()
		_buoy_pass(now)
		Debug.time_add("sensors/buoys", Time.get_ticks_usec() - step)
		step = Time.get_ticks_usec()
		track_manager.tick(now, SENSOR_DT)
		Debug.time_add("sensors/tracks", Time.get_ticks_usec() - step)
		step = Time.get_ticks_usec()
		_detect_weapons(now)
		Debug.time_add("sensors/weapons", Time.get_ticks_usec() - step)
		track_manager.cycle_at = NAN
	Detection.end_jamming_batch()


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
	var highest_root := 0.0
	for s in observer.sensors:
		if s.kind == "radar":
			sets.append(s)
			air_reach.append(s.range_air_nm)
			surface_reach.append(s.range_surface_nm)
			# The radar range functions take a height below zero to mean the antenna's own.
			var height := Detection.observer_height_m(observer, s)
			height_root.append(sqrt(maxf(height if height >= 0.0 else s.antenna_height_m, 0.0)))
			highest_root = maxf(highest_root, height_root[-1])
	var from := facts.position[oi]
	for ti: int in facts.others[observer.faction]:
		var signature := facts.signature[ti]
		if signature <= 0.0:
			continue
		var target_root := facts.mast_root[ti]
		# Beyond the highest antenna's horizon no set can reach, and clutter and jamming only
		# shorten a reach: let the pair go before weighing every set.
		var d := from.distance_to(facts.position[ti])
		if d > Detection.HORIZON_K * (highest_root + target_root) * efficiency:
			continue
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


## The outer edge of the last convergence zone, 0 with none.
func _cz_outer_nm() -> float:
	var cz_outer := 0.0
	for z: Dictionary in Acoustics.zones():
		cz_outer = maxf(cz_outer, float(z["range_nm"]) + float(z["half_width_nm"]))
	return cz_outer


## The sonar pass over the cycle's list of other sides' units. The water is left to the same
## Detection and Acoustics calls, in the same order, as the reference, but only for a pair that
## could be in some reach: the furthest anything could be heard is worked out from the listener's
## sets and the target's noise before the acoustic model runs, since the water only ever shortens it.
func _sonar_pass_indexed(facts: CycleFacts, oi: int, cz_outer: float, now: float) -> void:
	var observer := facts.units[oi]
	if not observer.has_sonar():
		return
	var rate := Detection.sonar_classify_rate(observer)
	var active_ceiling := Detection.best_active_sonar_nm(observer)
	# Each set's direct-path figure less the target's noise, and its share of an active
	# transmission heard: Detection.passive_sonar_range_nm and active_sonar_detection_nm before the
	# baffles and the water.
	var efficiency := observer.sensor_efficiency()
	var environment := Detection.sonar_environment_factor()
	var passive_k := 0.0
	var emission_k := 0.0
	var all_round := false  # some set that hears has no baffles
	var baffled_set: SensorSpec = null  # a set that hears, with the hull's arc astern
	var zones := false
	for s in observer.sensors:
		if s.kind != "sonar":
			continue
		if s.cz_capable:
			zones = true
		if s.passive_sensitivity_nm <= 0.0 or not Detection.sonar_sensor_ready(observer, s):
			continue
		var self_noise := Detection.self_noise_factor(observer, s)
		passive_k = maxf(passive_k, s.passive_sensitivity_nm * self_noise * efficiency * environment)
		emission_k = maxf(emission_k, s.passive_sensitivity_nm * 1.8 * self_noise)
		if Detection.has_baffles(observer, s):
			baffled_set = s
		else:
			all_round = true
	emission_k *= environment * efficiency
	var listens := all_round or baffled_set != null
	var cz_reach := cz_outer if zones else 0.0
	var from := facts.position[oi]
	for ti: int in facts.others[observer.faction]:
		var target := facts.units[ti]
		var airborne := target.is_aircraft()
		if airborne and facts.pinging[ti] == 0:
			continue
		var d := from.distance_to(facts.position[ti])
		var bound := passive_k * facts.noise_root[ti]
		if facts.pinging[ti] == 1:
			bound = maxf(bound, emission_k)
		if d > active_ceiling and d > bound * (1.0 + 1e-9) + 1e-9 and not _in_zone_band(d, cz_reach):
			# Out of every reach. The model would still have sampled the floor under both ends of a
			# path it weighed, and that sample is kept, so take it as the model would have.
			if listens and facts.noise_root[ti] > 0.0 and (facts.floor_asked[oi] == 0 or facts.floor_asked[ti] == 0):
				if all_round or not Detection.baffled(observer, baffled_set, facts.position[ti]):
					Acoustics.bottom_m(observer)
					Acoustics.bottom_m(target)
					facts.floor_asked[oi] = 1
					facts.floor_asked[ti] = 1
			continue
		sonar_pairs_weighed += 1
		var active_reach := Detection.active_sonar_reach_nm(observer, target) if active_ceiling > 0.0 and d <= active_ceiling and not airborne else 0.0
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
		var emission := Detection.active_sonar_detection_nm(observer, target) if facts.pinging[ti] == 1 else 0.0
		if emission > reach:
			reach = emission
			if sensor == null:
				sensor = _first_sonar(observer)
		var in_passive_reach := sensor != null and reach > 0.0 and d <= reach
		if d <= active_reach or in_passive_reach:
			if Detection.acoustic_path_blocked(observer, target):
				continue  # sound does not go through rock, pinging or listening
			if d <= active_reach:
				_report_active(observer, target, d, active_reach, rate, now)
			else:
				_report_passive(observer, target, d, reach, sensor, rate, now)
		elif d <= cz_reach:
			_try_convergence_zone(observer, target, d, rate, now)


## Whether a range falls inside a convergence-zone annulus that reaches no further than `outer`.
func _in_zone_band(d: float, outer: float) -> bool:
	if outer <= 0.0 or d > outer:
		return false
	for z: Dictionary in Acoustics.zones():
		if absf(d - float(z["range_nm"])) <= float(z["half_width_nm"]):
			return true
	return false


## Out of direct-path reach, a loud enough source can still be heard where its sound comes back up
## in a convergence zone, provided no land lies between and the water is deep the whole way.
## Checked after everything cheaper has failed, because both of those walk the path.
func _try_convergence_zone(observer: Unit, target: Unit, d: float, rate: float, now: float) -> void:
	for s in observer.sensors:
		if s.kind != "sonar" or not s.cz_capable:
			continue
		var direct := Detection.passive_sonar_range_nm(observer, s, target, false)
		var zone := Acoustics.cz_zone_for(s, d, direct)
		if zone.is_empty():
			continue
		# The annulus first and the walks after: both are dear, and either bars the zone.
		if Detection.acoustic_path_blocked(observer, target) or not Acoustics.deep_water_path(observer.position, target.position):
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


## A bearing report is a line as long as the reach the contact was heard at: a quiet boat heard at
## all is close, whatever the set's catalogue range against a loud one. Range and confidence come
## only from crossing measurements in TrackManager, never the target's range.
func _report_passive(observer: Unit, target: Unit, d: float, reach: float, sensor: SensorSpec, rate: float, now: float) -> void:
	var bearing := Geo.bearing_deg(observer.position, target.position) + rng.randfn(0.0, sensor.bearing_accuracy_deg)
	var c := _bearing_contact(target, observer, bearing, sensor.bearing_accuracy_deg, reach, "sonar_passive", sensor)
	c.quality = clampf(1.0 - d / reach, 0.0, 1.0)
	c.classify_rate = rate
	track_manager.observe_contact(observer.faction, c, now, SENSOR_DT)


## `search_range` is how far along the bearing the contact can be: the line's length.
## `key`, when given, is the listener's bearing key for `source`, worked out once for a pass.
func _bearing_contact(target: Unit, observer: Unit, bearing: float, accuracy: float, search_range: float, source: String, sensor: SensorSpec, key := "") -> SensorContact:
	var c := SensorContact.new()
	var estimate := maxf(search_range * INITIAL_RANGE_FRACTION, 0.3)
	c.range_nm = estimate
	c.target = target
	c.observer = observer
	c.bearing_origin = observer.position
	c.bearing_key = key if key != "" else _bearing_key(observer, source)
	c.bearing_accuracy_deg = accuracy
	c.bearing_range_limit_nm = search_range * REACH_MARGIN
	c.bearing_speed_limit_kn = 1200.0 if source == "esm" else 70.0
	c.position = observer.position + Geo.heading_to_vector(bearing) * estimate
	c.error_minor_nm = maxf(estimate * tan(deg_to_rad(accuracy * 2.0)), 0.2)
	c.error_major_nm = maxf(search_range * 0.5, c.error_minor_nm)
	c.error_axis_deg = bearing
	c.bearing_only = true
	c.source = source
	c.set_sensor(sensor)
	return c


static func _bearing_key(observer: Unit, source: String) -> String:
	return "unit:" + TrackManager._unit_key(observer) + ":" + source


## A convergence-zone ring contributes its measured propagation band, not an exact range.
func _report_cz(observer: Unit, target: Unit, _d: float, zone: Dictionary, sensor: SensorSpec, rate: float, now: float) -> void:
	var accuracy := sensor.bearing_accuracy_deg * CZ_BEARING_PENALTY
	var bearing := Geo.bearing_deg(observer.position, target.position) + rng.randfn(0.0, accuracy)
	var zone_range: float = zone["range_nm"]
	var half_width: float = zone["half_width_nm"]
	var c := _bearing_contact(target, observer, bearing, accuracy, zone_range, "sonar_cz", sensor)
	c.bearing_range_limit_nm = (zone_range + half_width) * REACH_MARGIN
	c.range_nm = zone_range
	c.position = observer.position + Geo.heading_to_vector(bearing) * zone_range
	c.error_minor_nm = maxf(zone_range * tan(deg_to_rad(accuracy * 2.0)), 0.3)
	c.error_major_nm = maxf(half_width, c.error_minor_nm)
	c.quality = CZ_QUALITY / float(zone["index"])
	c.classify_rate = rate * CZ_CLASSIFY_FACTOR
	track_manager.observe_contact(observer.faction, c, now, SENSOR_DT)


## Anything that transmits can be heard transmitting. ESM gives a bearing and a very good idea of
## what kind of ship is at the other end, without the listener radiating at all. It is the reason
## turning a radar off is a decision rather than a handicap.
##
## The pass works on the cycle's figures: Detection.best_esm's arithmetic in its order, with each
## emitter's power and antenna height taken once a cycle instead of once per listener.
func _esm_pass_indexed(facts: CycleFacts, oi: int, now: float) -> void:
	var observer := facts.units[oi]
	var sets: Array[SensorSpec] = []
	var gains := PackedFloat64Array()
	var height_root := PackedFloat64Array()
	var lines := PackedFloat64Array()  # each set's nominal reach, the length of the line it reports
	for s in observer.sensors:
		if s.kind == "esm":
			sets.append(s)
			gains.append(s.esm_gain)
			height_root.append(sqrt(maxf(Detection.observer_height_m(observer, s), 0.0)))
			lines.append(Detection.nominal_esm_range_nm(observer, s))
	if sets.is_empty() or observer.submerged():
		return
	var key := _bearing_key(observer, "esm")
	var efficiency := observer.sensor_efficiency()
	var highest_root := 0.0
	for root in height_root:
		highest_root = maxf(highest_root, root)
	var from := facts.position[oi]
	for ti: int in facts.emitters[observer.faction]:
		# No set hears past the line of sight from its own height to the emitter's.
		var d := from.distance_to(facts.position[ti])
		if d > Detection.HORIZON_K * (highest_root + facts.emitter_root[ti]) * efficiency:
			continue
		var power := facts.power[ti]
		var reach := 0.0
		var best := -1
		for k in sets.size():
			var r := 0.0
			if power > 0.0:
				r = minf(power * gains[k], Detection.HORIZON_K * (height_root[k] + facts.emitter_root[ti]))
			r *= efficiency
			if r > reach:
				reach = r
				best = k
		if best < 0 or reach <= 0.0:
			continue
		if d > reach:
			continue
		if facts.masked(oi, ti):
			continue  # the horizon this set already respects is not the only thing in the way
		_report_esm(observer, facts.units[ti], d, reach, sets[best], now, lines[best], key)


## The line is as long as the set's nominal reach against a ship's search radar. The reach against
## this emitter is not used for it: that follows the emitter's own height, which an intercept does
## not measure.
## `line`, when given, is Detection.nominal_esm_range_nm for the set and `key` the listener's ESM
## bearing key: both are the same for every intercept the listener makes in a cycle.
func _report_esm(observer: Unit, emitter: Unit, d: float, reach: float, sensor: SensorSpec, now: float, line := -1.0, key := "") -> void:
	var bearing := Geo.bearing_deg(observer.position, emitter.position) + rng.randfn(0.0, sensor.bearing_accuracy_deg)
	var length := line if line >= 0.0 else Detection.nominal_esm_range_nm(observer, sensor)
	var c := _bearing_contact(emitter, observer, bearing, sensor.bearing_accuracy_deg, length, "esm", sensor, key)
	c.bearing_range_limit_nm = maxf(c.bearing_range_limit_nm, ESM_SOLUTION_LIMIT_NM)
	c.quality = clampf(1.0 - d / reach, 0.0, 1.0)
	c.classify_rate = sensor.classify_rate * ESM_CLASSIFY_BONUS
	track_manager.observe_contact(observer.faction, c, now, SENSOR_DT)


## The lookout pass on the cycle's figures: the other sides' units only, and none further than the
## longest look the light and the weather allow before anything else is worked out for it. The
## same tests in the same order as the reference's pair-by-pair pass, so the same reports and the
## same draws.
func _visual_pass_indexed(facts: CycleFacts, oi: int, now: float) -> void:
	if facts.submerged[oi] == 1:
		return
	var observer := facts.units[oi]
	var light := Detection.visual_light_factor()
	var visibility := float(Detection.environment.get("visibility_nm", 12.0))
	var furthest := minf(6.0 * light, visibility) + 1e-9
	var furthest_squared := furthest * furthest
	var own_height := facts.mast[oi]
	var from := facts.position[oi]
	for ti: int in facts.others[observer.faction]:
		if facts.submerged[ti] == 1 or from.distance_squared_to(facts.position[ti]) > furthest_squared:
			continue
		lookout_pairs_weighed += 1
		var target := facts.units[ti]
		var d := from.distance_to(facts.position[ti])
		var limit := 3.0 if target.is_aircraft() else 6.0
		var height := facts.mast[ti]
		var error := 0.08
		if target.is_submarine() and target.at_periscope_depth():
			limit = (SNORKEL_SIGHTING_NM if SubmarinePower.snorkelling(target) else PERISCOPE_SIGHTING_NM) * clampf(1.0 - 0.12 * Detection.sea_state, 0.25, 1.0)
			height = PERISCOPE_HEIGHT_M
			error = 0.3
		limit = minf(limit * light, visibility)
		var slant := Vector2(d, (own_height - height) / METRES_PER_NM).length()
		if slant > limit:
			continue
		if d > Detection.radar_horizon_nm(own_height, height):
			continue
		if facts.masked(oi, ti):
			continue  # the same sight line, mast to mast, as a radar's: one walk serves both
		_report_visual(observer, target, d, slant, limit, error, now)


## Recognition needs a close, unobscured look. This is separate from radar, so an EMCON patrol
## can identify a ship. These distances are conservative gameplay optical recognition limits.
const PERISCOPE_SIGHTING_NM := 1.5  # GAMEPLAY_ESTIMATE
const SNORKEL_SIGHTING_NM := 3.0
const PERISCOPE_HEIGHT_M := 1.0
## A class is recognised at the limit of a look; a name is read at this fraction of it.
const VISUAL_NAME_FRACTION := 0.5
const METRES_PER_NM := 1852.0


func _report_visual(observer: Unit, target: Unit, d: float, slant: float, limit: float, error: float, now: float) -> void:
	var c := SensorContact.make(target, target.position + Vector2(rng.randfn(0.0, error), rng.randfn(0.0, error)) if error > 0.1 else target.position, error, 1.0, 1.0, d, "visual", observer)
	c.visual_identification = true
	c.visual_named = slant <= limit * VISUAL_NAME_FRACTION
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
		var reach := maxf(b.reach_against(target), 0.5)
		var estimate := reach * INITIAL_RANGE_FRACTION
		c.range_nm = estimate
		c.target = target
		c.classify_rate = 0.8
		c.source = "sonobuoy"
		c.sensor_id = "sonobuoy"
		c.sensor_name = "Sonobuoy field" if buoys.size() >= 2 else "Sonobuoy"
		c.bearing_origin = b.position
		c.bearing_key = "buoy:%d" % b.id
		c.bearing_accuracy_deg = 1.5
		c.bearing_range_limit_nm = reach * REACH_MARGIN
		c.bearing_only = true
		c.position = b.position + Geo.heading_to_vector(bearing) * estimate
		c.error_axis_deg = bearing
		c.error_major_nm = reach * 0.5
		c.error_minor_nm = maxf(estimate * tan(deg_to_rad(3.0)), 0.2)
		c.quality = 0.5
		track_manager.observe_contact(faction, c, now, SENSOR_DT)


## Incoming rounds are found by radar above the water and by sonar below it. A sea-skimming
## missile stays below the horizon until it is close; a torpedo is heard, not seen. A ship keeping
## radar silence is not blind for it: an ESM set hears a missile's own radar seeker once that is
## searching, out to the radio horizon, and anyone on the surface or in the air sees a round that
## is nearly on top of them.
const WEAPON_SIGHTING_NM := 3.0  # GAMEPLAY_ESTIMATE: a lookout, a close-in mount's own director
## A radar seeker is switched on this many seeker ranges short of where it was sent.
const SEEKER_ON_FACTOR := 1.5


## Whether the round is transmitting: one that homes on its own radar, once it is locked on,
## searching, or near enough its aim point to have switched the seeker on. A round riding someone
## else's illumination, or homing on heat or on a radar, sends nothing.
static func seeker_radiating(w: Weapon) -> bool:
	var guidance := w.spec.guidance
	if w.spec.is_torpedo() or not guidance.contains("active") or guidance.contains("semi"):
		return false
	if w.phase == Weapon.Phase.TERMINAL or w.searching_on:
		return true
	var seeker := w.spec.seeker_range_nm * SEEKER_ON_FACTOR
	return seeker > 0.0 and w.position.distance_squared_to(w.aim_point) <= seeker * seeker


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
	var radiating := PackedByteArray()
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
		radiating.append(1 if seeker_radiating(w) else 0)
	var sighting := minf(WEAPON_SIGHTING_NM * Detection.visual_light_factor(), float(Detection.environment.get("visibility_nm", 12.0)))
	# What each group presents, the same for every observer: Detection.weapon_detection_range_nm's
	# share of the round's height and size, the clutter it rides in, and a torpedo's noise.
	var group_root := PackedFloat64Array()
	var group_signature := PackedFloat64Array()
	var group_clutter := PackedFloat64Array()
	var group_noise := PackedFloat64Array()
	var torpedoes := false
	for group in group_specs.size():
		var spec := group_specs[group]
		var altitude := group_altitudes[group]
		group_root.append(sqrt(maxf(spec.altitude_m if altitude < 0.0 else altitude, 0.0)))
		group_signature.append(spec.signature_factor)
		group_clutter.append(Detection.weapon_clutter_factor(spec, altitude))
		group_noise.append(sqrt(maxf(spec.acoustic_signature, 0.01)))
		torpedoes = torpedoes or group_torpedoes[group]
	var water := Detection.sonar_environment_factor()
	for observer in unit_manager.units:
		if not observer.is_engageable():
			continue
		var radar_up := observer.radar_emitting()
		var sonar_up := observer.has_sonar()
		var surfaced := not observer.submerged()
		if not radar_up and not sonar_up and not surfaced:
			continue
		var esm_root := -1.0
		if surfaced:
			for s in observer.sensors:
				if s.kind == "esm":
					esm_root = maxf(esm_root, sqrt(maxf(Detection.observer_height_m(observer, s), 0.0)))
		var esm_efficiency := observer.sensor_efficiency()
		# The observer's sets, once: Detection.best_weapon_detection_nm and torpedo_detection_nm
		# weigh each of them against every group in the same order with the same arithmetic.
		var radar_air := PackedFloat64Array()
		var radar_root := PackedFloat64Array()
		if radar_up:
			for s in observer.sensors:
				if s.kind == "radar":
					var height := Detection.observer_height_m(observer, s)
					radar_air.append(s.range_air_nm)
					radar_root.append(sqrt(maxf(s.antenna_height_m if height < 0.0 else height, 0.0)))
		var sonar_gain := PackedFloat64Array()
		if sonar_up and torpedoes:
			for s in observer.sensors:
				if s.kind == "sonar" and s.passive_sensitivity_nm > 0.0 and Detection.sonar_sensor_ready(observer, s):
					sonar_gain.append(s.passive_sensitivity_nm)
					sonar_gain.append(Detection.self_noise_factor(observer, s))
		var reaches := PackedFloat64Array()
		var passive := PackedFloat64Array()  # the eye, and an intercept of a seeker that is transmitting
		var intercept := PackedFloat64Array()
		var furthest := 0.0
		for group in group_specs.size():
			var altitude := group_altitudes[group]
			var reach := 0.0
			if group_torpedoes[group] and sonar_up:
				for k in range(0, sonar_gain.size(), 2):
					reach = maxf(reach, sonar_gain[k] * group_noise[group] * sonar_gain[k + 1])
				reach = reach * water * esm_efficiency
			if not group_torpedoes[group] and radar_up:
				for k in radar_air.size():
					reach = maxf(reach, minf(radar_air[k] * group_signature[group], Detection.HORIZON_K * (radar_root[k] + group_root[group])))
				reach = reach * esm_efficiency * group_clutter[group]
			reaches.append(reach)
			var above_water := surfaced and not group_torpedoes[group]
			passive.append(sighting if above_water else 0.0)
			intercept.append(Detection.HORIZON_K * (esm_root + sqrt(maxf(altitude, 0.0))) * esm_efficiency if above_water and esm_root >= 0.0 else 0.0)
			furthest = maxf(furthest, maxf(reach, maxf(passive[group], intercept[group])))
		if furthest <= 0.0:
			continue
		var furthest_squared := furthest * furthest
		for i in weapons.size():
			var w := weapons[i]
			if w.faction == observer.faction or w.phase == Weapon.Phase.DEAD:
				continue
			var d_squared := observer.position.distance_squared_to(w.position)
			if d_squared > furthest_squared:
				continue
			var group := group_indices[i]
			var reach := reaches[group]
			var held := reach > 0.0 and d_squared <= reach * reach
			if held and not group_torpedoes[group]:
				reach *= Detection.jam_penalty(observer, w.position)
				held = reach > 0.0 and d_squared <= reach * reach
			if not held:
				# Neither needs the ship to transmit, and a jammer blinds neither.
				held = d_squared <= passive[group] * passive[group]
				if not held and radiating[i] == 1:
					held = d_squared <= intercept[group] * intercept[group]
			if not held:
				continue
			if Detection.terrain_hides_weapon(observer, w):
				continue
			threat_manager.mark_detected(observer.faction, w, now, observer)
			if track_manager != null:
				track_manager.observe_hostile_launch(observer, w, now)
