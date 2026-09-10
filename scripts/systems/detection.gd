class_name Detection
## Sensor geometry. Pure static functions; no randomness here.
##
## Radar: surface detection is capped by the radar horizon, ~2.23 * (sqrt(h1_m) + sqrt(h2_m)) nm,
## the standard 1.23 * sqrt(h_ft) 4/3-earth approximation converted to metres.
##
## Sonar: an entirely separate channel. Radiated noise rises steeply with speed and jumps again
## when a screw cavitates, which happens sooner in shallow water. Passive range scales with the
## square root of that noise, and is degraded by the listener's own speed. All acoustic constants
## here are GAMEPLAY_ESTIMATE tuning values, not claims about any real platform.

const HORIZON_K := 2.23
const BASELINE_TARGET_HEIGHT_M := 25.0

const NOISE_AT_REST := 0.30  # fraction of full radiated noise when barely moving
const NOISE_SPEED_GAIN := 2.70  # added quadratically up to full speed
const CAVITATION_MULTIPLIER := 2.5
const CAVITATION_SHALLOW_FRACTION := 0.35  # speed fraction where a shallow boat starts cavitating
const CAVITATION_DEEP_FRACTION := 0.75
const CAVITATION_DEPTH_M := 200.0  # depth at which the deep threshold applies
const SELF_NOISE_EXPONENT := 1.5
const RADAR_PERISCOPE_SIGNATURE := 0.05  # a raised mast is a very small radar target

## Environment. Sea state is the one weather variable that touches every sensor at once: a rough
## sea is loud, which shortens passive sonar, and it throws back clutter that hides small and
## low-flying radar targets. All coefficients are GAMEPLAY_ESTIMATE.
const SEA_STATE_NAMES := ["calm", "smooth", "slight", "moderate", "rough", "very rough", "high"]
const SONAR_LOSS_PER_SEA_STATE := 0.07
const CLUTTER_LOSS_PER_SEA_STATE := 0.05
const SKIMMER_CLUTTER_LOSS_PER_SEA_STATE := 0.06
const SMALL_TARGET_SIGNATURE := 0.5
const SKIMMER_ALTITUDE_M := 60.0
static var sea_state := 0
static var environment: Dictionary = {}

## Electronic attack. A jammer degrades every hostile radar within its reach, but only against
## targets lying roughly in the jammer's direction: the noise comes down one bearing.
const JAM_CONE_DEG := 35.0
static var jammers: Array = []


static func set_environment(env: Dictionary) -> void:
	environment = env.duplicate()
	sea_state = clampi(int(env.get("sea_state", 0)), 0, SEA_STATE_NAMES.size() - 1)


static func sea_state_name() -> String:
	return SEA_STATE_NAMES[clampi(sea_state, 0, SEA_STATE_NAMES.size() - 1)]


static func sonar_environment_factor() -> float:
	return clampf(1.0 - SONAR_LOSS_PER_SEA_STATE * sea_state, 0.4, 1.0)


## Clutter loss against a surface target: a small craft in a big sea is hard to pick out.
static func clutter_factor(target_signature: float) -> float:
	if target_signature >= SMALL_TARGET_SIGNATURE:
		return 1.0
	return clampf(1.0 - CLUTTER_LOSS_PER_SEA_STATE * sea_state, 0.5, 1.0)


## Clutter loss against a round in flight: a sea-skimmer rides in the wave returns.
static func weapon_clutter_factor(wspec: WeaponSpec) -> float:
	if wspec.altitude_m > SKIMMER_ALTITUDE_M:
		return 1.0
	return clampf(1.0 - SKIMMER_CLUTTER_LOSS_PER_SEA_STATE * sea_state, 0.5, 1.0)


## Called once per sensor cycle so the per-lookup cost of jamming stays small.
static func refresh_jammers(units: Array) -> void:
	jammers.clear()
	for u: Unit in units:
		if u.jamming():
			jammers.append(u)


## Multiplier on an observer's radar reach toward `target_pos`, 1.0 when unjammed.
static func jam_penalty(observer: Unit, target_pos: Vector2) -> float:
	if jammers.is_empty():
		return 1.0
	var factor := 1.0
	var brg_target := Geo.bearing_deg(observer.position, target_pos)
	for j: Unit in jammers:
		if j.faction == observer.faction:
			continue
		var d := observer.position.distance_to(j.position)
		for s in j.sensors:
			if s.kind != "jammer" or s.jam_range_nm < d:
				continue
			if absf(Geo.heading_delta(brg_target, Geo.bearing_deg(observer.position, j.position))) > JAM_CONE_DEG:
				continue
			factor = minf(factor, 1.0 / (1.0 + s.jam_strength))
	return factor


## Whether a radar's picture toward that point is currently degraded, for the display.
static func is_jammed_toward(observer: Unit, target_pos: Vector2) -> bool:
	return jam_penalty(observer, target_pos) < 0.999


static func radar_horizon_nm(h1_m: float, h2_m: float) -> float:
	return HORIZON_K * (sqrt(maxf(h1_m, 0.0)) + sqrt(maxf(h2_m, 0.0)))


## How high the sensor actually is. For a ship that is its mast; for an aircraft it is however
## high the aircraft is flying, which is why maritime patrol sees so much further than a frigate.
static func observer_height_m(observer: Unit, sensor: SensorSpec) -> float:
	return observer.altitude_m if observer.airborne() else sensor.antenna_height_m


static func radar_range_vs_surface_nm(sensor: SensorSpec, target_signature: float, target_height_m: float, observer_height := -1.0) -> float:
	var height := sensor.antenna_height_m if observer_height < 0.0 else observer_height
	return minf(sensor.range_surface_nm * target_signature, radar_horizon_nm(height, target_height_m))


## Best emitting radar range of an observer against a surface target. 0 if silent or no radar.
static func best_radar_range_nm(observer: Unit, target_signature: float, target_height_m: float) -> float:
	if not observer.radar_on:
		return 0.0
	var best := 0.0
	for s in observer.sensors:
		if s.kind == "radar":
			best = maxf(best, radar_range_vs_surface_nm(s, target_signature, target_height_m, observer_height_m(observer, s)))
	return best * observer.sensor_efficiency()


## Range the observer's radar would have against a baseline target (for range rings), ignoring
## the on/off state.
static func nominal_radar_ring_nm(observer: Unit) -> float:
	var best := 0.0
	for s in observer.sensors:
		if s.kind == "radar":
			best = maxf(best, radar_range_vs_surface_nm(s, 1.0, BASELINE_TARGET_HEIGHT_M, observer_height_m(observer, s)))
	return best


## Radar range against an in-flight weapon. A sea-skimming round hides below the horizon until
## it is close; a high-flying round is seen much further out but is still a small radar target.
static func weapon_detection_range_nm(sensor: SensorSpec, wspec: WeaponSpec, observer_height := -1.0) -> float:
	var height := sensor.antenna_height_m if observer_height < 0.0 else observer_height
	var by_power := sensor.range_air_nm * wspec.signature_factor
	var by_horizon := radar_horizon_nm(height, wspec.altitude_m)
	return minf(by_power, by_horizon)


## Best range at which an emitting observer can see a given weapon type. 0 if silent.
static func best_weapon_detection_nm(observer: Unit, wspec: WeaponSpec) -> float:
	if not observer.radar_on:
		return 0.0
	var best := 0.0
	for s in observer.sensors:
		if s.kind == "radar":
			best = maxf(best, weapon_detection_range_nm(s, wspec, observer_height_m(observer, s)))
	return best


## Radar signature actually presented by a unit. A submerged boat presents nothing at all; at
## periscope depth it presents almost nothing.
static func radar_signature_of(target: Unit) -> float:
	if target.is_aircraft():
		return target.spec.signature_factor if target.airborne() else 0.0
	if target.submerged():
		return 0.0
	if target.at_periscope_depth():
		return target.spec.signature_factor * RADAR_PERISCOPE_SIGNATURE
	return target.spec.signature_factor


## Radar against something in the air. Altitude buys enormous horizon, so aircraft are seen from
## much further off than ships, limited instead by how small a target they are.
static func radar_air_range_nm(sensor: SensorSpec, target_signature: float, altitude_m: float, observer_height := -1.0) -> float:
	var height := sensor.antenna_height_m if observer_height < 0.0 else observer_height
	return minf(sensor.range_air_nm * target_signature, radar_horizon_nm(height, altitude_m))


static func best_radar_air_range_nm(observer: Unit, target_signature: float, altitude_m: float) -> float:
	if not observer.radar_on:
		return 0.0
	var best := 0.0
	for s in observer.sensors:
		if s.kind == "radar":
			best = maxf(best, radar_air_range_nm(s, target_signature, altitude_m, observer_height_m(observer, s)))
	return best * observer.sensor_efficiency()


## Detection quality in [0,1] (0 = not detected, →1 = very close).
static func radar_quality(observer: Unit, target: Unit) -> float:
	var signature := radar_signature_of(target)
	if signature <= 0.0:
		return 0.0
	var r := best_radar_air_range_nm(observer, signature, target.altitude_m) if target.airborne() \
		else best_radar_range_nm(observer, signature, target.spec.mast_height_m) * clutter_factor(signature)
	r *= jam_penalty(observer, target.position)
	if r <= 0.0:
		return 0.0
	var d := observer.position.distance_to(target.position)
	if d > r:
		return 0.0
	if terrain_masks(observer, target):
		return 0.0  # in range, but there is a hill in the way
	return clampf(1.0 - d / r, 0.0, 1.0)


## Best classification rate among the observer's emitting radars.
static func classify_rate(observer: Unit) -> float:
	var best := 0.0
	for s in observer.sensors:
		if s.kind == "radar":
			best = maxf(best, s.classify_rate)
	return best


# --- Acoustics ---------------------------------------------------------------------------

## Speed at which this unit begins to cavitate, as a fraction of its maximum. Deeper is quieter.
static func cavitation_fraction(u: Unit) -> float:
	var depth_ratio := clampf(u.depth_m / CAVITATION_DEPTH_M, 0.0, 1.0)
	return lerpf(CAVITATION_SHALLOW_FRACTION, CAVITATION_DEEP_FRACTION, depth_ratio)


## Radiated noise, relative to a noisy surface combatant at full speed being 1.0-ish.
static func acoustic_noise(u: Unit) -> float:
	var frac := clampf(u.speed_kn / maxf(u.spec.max_speed_kn, 1.0), 0.0, 1.0)
	var noise := u.spec.acoustic_signature * (NOISE_AT_REST + NOISE_SPEED_GAIN * frac * frac)
	if frac > cavitation_fraction(u):
		noise *= CAVITATION_MULTIPLIER
	return noise


static func is_cavitating(u: Unit) -> bool:
	var frac := clampf(u.speed_kn / maxf(u.spec.max_speed_kn, 1.0), 0.0, 1.0)
	return frac > cavitation_fraction(u)


## How well a listener hears anything at all while making its own noise. Slowing down to listen
## is one of the few levers a submarine commander has, so it matters.
static func self_noise_factor(observer: Unit, sensor: SensorSpec) -> float:
	var frac := clampf(observer.speed_kn / maxf(observer.spec.max_speed_kn, 1.0), 0.0, 1.0)
	var penalty := pow(frac, SELF_NOISE_EXPONENT) * (1.0 - sensor.self_noise_tolerance)
	return clampf(1.0 - penalty, 0.15, 1.0)


## Range at which `observer` can hear `target` on this array. Zero if it cannot.
static func passive_sonar_range_nm(observer: Unit, sensor: SensorSpec, target: Unit) -> float:
	if sensor.passive_sensitivity_nm <= 0.0 or target.is_aircraft() or target.spec.domain == "land":
		return 0.0
	if sensor.requires_hover and not observer.is_hovering():
		return 0.0  # a dipping set has to be in the water
	var noise := acoustic_noise(target)
	if noise <= 0.0:
		return 0.0
	return sensor.passive_sensitivity_nm * sqrt(noise) * self_noise_factor(observer, sensor) * observer.sensor_efficiency() * sonar_environment_factor()


## Best passive range across the observer's arrays, with the sensor that achieved it.
static func best_passive_sonar(observer: Unit, target: Unit) -> Dictionary:
	var best_range := 0.0
	var best_sensor: SensorSpec = null
	for s in observer.sensors:
		if s.kind != "sonar":
			continue
		var r := passive_sonar_range_nm(observer, s, target)
		if r > best_range:
			best_range = r
			best_sensor = s
	return {"range_nm": best_range, "sensor": best_sensor}


## Active sonar reach. Firm range and bearing, at the cost of telling everyone where you are.
static func best_active_sonar_nm(observer: Unit) -> float:
	if not observer.active_sonar_emitting():
		return 0.0
	var best := 0.0
	for s in observer.sensors:
		if s.kind != "sonar":
			continue
		if s.requires_hover and not observer.is_hovering():
			continue
		best = maxf(best, s.active_range_nm)
	return best * observer.sensor_efficiency()


## Nominal passive reach against a baseline noisy surface ship, for drawing sensor rings.
static func nominal_passive_ring_nm(observer: Unit) -> float:
	var best := 0.0
	for s in observer.sensors:
		if s.kind == "sonar" and s.passive_sensitivity_nm > 0.0:
			if s.requires_hover and not observer.is_hovering():
				continue
			best = maxf(best, s.passive_sensitivity_nm * self_noise_factor(observer, s))
	return best


## An active transmitter is itself a loud noise in the water, heard well beyond its own reach.
static func active_sonar_detection_nm(listener: Unit, emitter: Unit) -> float:
	if not emitter.active_sonar_emitting():
		return 0.0
	var best := 0.0
	for s in listener.sensors:
		if s.kind == "sonar" and s.passive_sensitivity_nm > 0.0:
			best = maxf(best, s.passive_sensitivity_nm * 1.8 * self_noise_factor(listener, s))
	return best


## Best classification rate among the observer's sonars.
static func sonar_classify_rate(observer: Unit) -> float:
	var best := 0.0
	for s in observer.sensors:
		if s.kind == "sonar":
			best = maxf(best, s.classify_rate)
	return best


## A running torpedo is loud. This is how a ship gets any warning at all of one.
static func torpedo_detection_nm(listener: Unit, wspec: WeaponSpec) -> float:
	var best := 0.0
	for s in listener.sensors:
		if s.kind == "sonar" and s.passive_sensitivity_nm > 0.0:
			best = maxf(best, s.passive_sensitivity_nm * sqrt(maxf(wspec.acoustic_signature, 0.01)) * self_noise_factor(listener, s))
	return best * sonar_environment_factor()


# --- Electronic support -------------------------------------------------------------------

## How high the emitter's antenna is, for the line-of-sight limit on hearing it.
static func emitter_height_m(emitter: Unit) -> float:
	if emitter.airborne():
		return emitter.altitude_m
	var best := 0.0
	for s in emitter.sensors:
		if s.kind == "radar":
			best = maxf(best, s.antenna_height_m)
	return maxf(best, 5.0)


## The strongest radar the emitter is actually transmitting on, as a power proxy.
static func emitted_radar_power(emitter: Unit) -> float:
	var best := 0.0
	if emitter.radar_emitting():
		for s in emitter.sensors:
			if s.kind == "radar":
				best = maxf(best, s.range_surface_nm)
	if emitter.jamming():
		for s in emitter.sensors:
			if s.kind == "jammer":
				best = maxf(best, s.jam_range_nm)  # a jammer is the loudest thing on the air
	return best


## Range at which this ESM set hears that emitter. Line of sight still applies, but nothing about
## how small the emitter is does: a stealthy ship that switches on is as loud as any other.
static func esm_detection_nm(listener: Unit, sensor: SensorSpec, emitter: Unit) -> float:
	if sensor.kind != "esm":
		return 0.0
	var power := emitted_radar_power(emitter)
	if power <= 0.0:
		return 0.0
	var horizon := radar_horizon_nm(observer_height_m(listener, sensor), emitter_height_m(emitter))
	return minf(power * sensor.esm_gain, horizon)


## Best ESM reach across the listener's sets, with the set that achieved it.
static func best_esm(listener: Unit, emitter: Unit) -> Dictionary:
	var best_range := 0.0
	var best_sensor: SensorSpec = null
	for s in listener.sensors:
		if s.kind != "esm":
			continue
		var r := esm_detection_nm(listener, s, emitter) * listener.sensor_efficiency()
		if r > best_range:
			best_range = r
			best_sensor = s
	return {"range_nm": best_range, "sensor": best_sensor}


## Nominal ESM reach against a ship radiating a typical search radar, for drawing a ring.
static func nominal_esm_ring_nm(listener: Unit) -> float:
	var best := 0.0
	for s in listener.sensors:
		if s.kind != "esm":
			continue
		var horizon := radar_horizon_nm(observer_height_m(listener, s), BASELINE_TARGET_HEIGHT_M)
		best = maxf(best, minf(30.0 * s.esm_gain, horizon))
	return best


# --- Terrain ------------------------------------------------------------------------------

## How high something stands above the sea, for terrain masking: an aircraft's altitude, nothing
## at all for a submerged boat, otherwise the masthead. The same number serves for both ends of a
## path, because a ship's antennas sit on the mast it is measured by.
static func mast_or_altitude_m(u: Unit) -> float:
	if u.airborne():
		return u.altitude_m
	if u.submerged():
		return 0.0
	return maxf(u.spec.mast_height_m, 1.0)


## True when the ground between two units blocks a radar or ESM path. This is what makes a
## corvette in the lee of an island disappear while the aircraft above it stays in view.
static func terrain_masks(observer: Unit, target: Unit) -> bool:
	if Terrain.is_empty():
		return false
	return Terrain.masks_line_of_sight(observer.position, mast_or_altitude_m(observer), target.position, mast_or_altitude_m(target))


## True when land lies between two units on an acoustic path. Sound does not climb a hill, so
## depth and altitude are irrelevant here: either the water is continuous or it is not.
static func acoustic_path_blocked(observer: Unit, target: Unit) -> bool:
	if Terrain.is_empty():
		return false
	return Terrain.blocks_path(observer.position, target.position)


## Whether the ground hides a round in flight. A torpedo is an acoustic path; anything above the
## water is a sight line flown at the round's own cruise altitude, which is why a sea-skimmer
## vanishes behind a headland and a round at 8000 m does not.
static func terrain_hides_weapon(observer: Unit, w: Weapon) -> bool:
	if Terrain.is_empty():
		return false
	if w.spec.is_torpedo():
		return Terrain.blocks_path(observer.position, w.position)
	return Terrain.masks_line_of_sight(observer.position, mast_or_altitude_m(observer), w.position, w.spec.altitude_m)
