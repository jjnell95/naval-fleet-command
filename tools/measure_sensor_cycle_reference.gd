extends RefCounted
## The sensor cycle's original pair-by-pair passes: for every observer, every unit of every other
## side is weighed in full by the Detection functions themselves, with nothing worked out once a
## cycle and nothing let go early. SensorManager runs these instead of its own passes while its
## development switch `reference_path` is on, so tests/test_sensor_cycle.gd can check that the
## shipped cycle makes the same reports in the same order from the same random draws, and
## tools/measure_sensor_cycle.gd can time one against the other. Never used in play, and not
## exported with the game.


## One observer's radar, sonar, ESM and lookout passes, in the order the shipped cycle runs them,
## each pass's time added to the totals in `spent` (radar, sonar, esm, visual, in microseconds).
static func run_observer(sm: SensorManager, observer: Unit, cz_outer: float, now: float, spent: Array) -> void:
	var at := Time.get_ticks_usec()
	_radar_pass(sm, observer, now)
	var mid := Time.get_ticks_usec()
	_sonar_pass(sm, observer, cz_outer, now)
	var late := Time.get_ticks_usec()
	_esm_pass(sm, observer, now)
	var seen := Time.get_ticks_usec()
	_visual_pass(sm, observer, now)
	spent[0] += mid - at
	spent[1] += late - mid
	spent[2] += seen - late
	spent[3] += Time.get_ticks_usec() - seen


static func _radar_pass(sm: SensorManager, observer: Unit, now: float) -> void:
	if not observer.radar_emitting():
		return
	var rate := Detection.classify_rate(observer)
	for target in sm.unit_manager.units:
		if target == observer or not target.is_engageable() or target.faction == observer.faction:
			continue
		var q := Detection.radar_quality(observer, target)
		if q <= 0.0:
			continue
		var d := observer.position.distance_to(target.position)
		var sigma := SensorManager.OBS_SIGMA_BASE_NM + SensorManager.OBS_SIGMA_PER_NM * d
		var obs := target.position + Vector2(sm.rng.randfn(0.0, sigma), sm.rng.randfn(0.0, sigma))
		var c := SensorContact.make(target, obs, TrackManager.BASE_ERROR_NM + TrackManager.ERROR_PER_NM * d, q, rate, d, "radar", observer, Detection.radar_sensor_for(observer, target))
		sm.track_manager.observe_contact(observer.faction, c, now, SensorManager.SENSOR_DT)


static func _sonar_pass(sm: SensorManager, observer: Unit, cz_outer: float, now: float) -> void:
	if not observer.has_sonar():
		return
	var rate := Detection.sonar_classify_rate(observer)
	var active_ceiling := Detection.best_active_sonar_nm(observer)  # before the water has its say
	for target in sm.unit_manager.units:
		if target == observer or not target.is_engageable() or target.faction == observer.faction:
			continue
		# An aircraft is nothing to a sonar except while its dipping set is pinging in the water.
		var airborne := target.is_aircraft()
		if airborne and not target.active_sonar_emitting():
			continue
		var d := observer.position.distance_to(target.position)
		var active_reach := Detection.active_sonar_reach_nm(observer, target) if active_ceiling > 0.0 and d <= active_ceiling and not airborne else 0.0
		var passive := Detection.best_passive_sonar(observer, target)
		var reach: float = passive["range_nm"]
		var sensor: SensorSpec = passive["sensor"]
		# An active transmitter is a loud noise in its own right, heard well past its own reach.
		var emission := Detection.active_sonar_detection_nm(observer, target)
		if emission > reach:
			reach = emission
			if sensor == null:
				sensor = sm._first_sonar(observer)
		var in_passive_reach := sensor != null and reach > 0.0 and d <= reach
		if d > active_reach and not in_passive_reach and d > cz_outer:
			continue
		if Detection.acoustic_path_blocked(observer, target):
			continue  # sound does not go through rock, pinging or listening
		if d <= active_reach:
			sm._report_active(observer, target, d, active_reach, rate, now)
			continue
		if in_passive_reach:
			sm._report_passive(observer, target, d, reach, sensor, rate, now)
		elif d <= cz_outer:
			sm._try_convergence_zone(observer, target, d, rate, now)


static func _esm_pass(sm: SensorManager, observer: Unit, now: float) -> void:
	if not observer.has_esm() or observer.submerged():
		return  # an aerial under water hears nothing
	for emitter in sm.unit_manager.units:
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
			continue
		sm._report_esm(observer, emitter, d, reach, sensor, now)


static func _visual_pass(sm: SensorManager, observer: Unit, now: float) -> void:
	if observer.submerged():
		return
	for target in sm.unit_manager.units:
		if target == observer or target.faction == observer.faction or not target.is_engageable() or target.submerged():
			continue
		var d := observer.position.distance_to(target.position)
		var limit := 3.0 if target.is_aircraft() else 6.0
		var height := Detection.mast_or_altitude_m(target)
		var error := 0.08
		if target.is_submarine() and target.at_periscope_depth():
			limit = (SensorManager.SNORKEL_SIGHTING_NM if SubmarinePower.snorkelling(target) else SensorManager.PERISCOPE_SIGHTING_NM) * clampf(1.0 - 0.12 * Detection.sea_state, 0.25, 1.0)
			height = SensorManager.PERISCOPE_HEIGHT_M
			error = 0.3
		limit = minf(limit * Detection.visual_light_factor(), float(Detection.environment.get("visibility_nm", 12.0)))
		var slant := Vector2(d, (Detection.mast_or_altitude_m(observer) - height) / SensorManager.METRES_PER_NM).length()
		if slant > limit:
			continue
		if d > Detection.radar_horizon_nm(Detection.mast_or_altitude_m(observer), height):
			continue
		if Detection.terrain_masks(observer, target):
			continue
		sm._report_visual(observer, target, d, slant, limit, error, now)
