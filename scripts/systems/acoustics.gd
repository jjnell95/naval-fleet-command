class_name Acoustics
## What the water column does to sound. Detection owns how loud things are and how good an array
## is; this owns the path between them. Four effects, each a GAMEPLAY_ESTIMATE shaped by public
## textbook acoustics (Urick, "Principles of Underwater Sound") rather than by any real system:
##
## * The layer. Where the surface water is mixed, sound speed rises with depth down to the bottom
##   of the mixed layer and falls below it. Sound made on one side bends away from the other, so a
##   listener above the layer hears a boat below it badly, and the other way round. A hull array
##   sits a few metres under the keel and is always above; a variable-depth or dipping set can be
##   lowered through; a submarine listens from wherever it is. That is the whole reason a frigate
##   tows a body on a cable and a helicopter lowers one on a wire.
## * Shallow water. On a continental shelf the sound keeps meeting the bottom and the surface,
##   ambient noise is higher and active returns come back smeared with reverberation. Passive and
##   active ranges both shorten as the floor comes up.
## * Convergence zones. In deep water, sound that goes down refracts back up and reaches the
##   surface again in a ring tens of miles out. A large low-frequency array can hear a loud source
##   in that ring when it could not hear it directly at half the distance. The ring is narrow, so
##   a convergence-zone contact comes with a good idea of range and a bad one of everything else.
## * The bottom. A submarine cannot go deeper than the water under it, less a margin, which is
##   why a boat on the shelf cannot hide under a layer that sits below the sea floor.
##
## The environment comes from the scenario (`layer_depth_m`, `layer_strength`, `cz_range_nm`) and
## the floor from Bathymetry. Absent either, every factor here is 1.0 and the older behaviour is
## unchanged, which is what keeps the hand-built test worlds valid.

const HULL_ARRAY_DEPTH_M := 8.0  # a keel-mounted set is always in the surface layer
const SURFACE_SOURCE_DEPTH_M := 4.0  # screws and machinery of a surface ship
const KEEL_CLEARANCE_M := 25.0  # how close to the floor a boat will run
const ARRAY_CLEARANCE_M := 15.0  # how close to the floor a towed or dipped body is lowered
const BELOW_LAYER_MARGIN_M := 40.0  # a body streamed for the layer goes comfortably through it
const LAYER_MIN_WATER_BELOW_M := 10.0  # a layer needs water under it to have a "below"
const CROSS_LAYER_LOSS := 0.6  # at full layer strength, range across it falls to 40 percent

const SHELF_DEPTH_M := 200.0
const SHOAL_DEPTH_M := 40.0
const SHALLOW_PASSIVE_FLOOR := 0.7
const SHALLOW_ACTIVE_FLOOR := 0.55  # reverberation hurts a ping more than it hurts listening

const CZ_MIN_DEPTH_M := 2000.0  # the ray has to turn round before it meets the floor
const CZ_HALF_WIDTH_FRACTION := 0.08  # annulus half-width as a fraction of its range
const CZ_FIRST_THRESHOLD := 0.35  # direct-path reach, as a fraction of CZ range, to hear zone one
const CZ_SECOND_THRESHOLD := 0.60  # and zone two, which is wider and weaker

## Sonobuoy hydrophone settings a crew can select at drop time, shallowest first.
const BUOY_DEPTHS_M: Array[float] = [27.0, 120.0, 300.0]


# --- Environment ------------------------------------------------------------------------

static func layer_depth_m() -> float:
	return maxf(float(Detection.environment.get("layer_depth_m", 0.0)), 0.0)


static func layer_strength() -> float:
	if layer_depth_m() <= 0.0:
		return 0.0
	return clampf(float(Detection.environment.get("layer_strength", 1.0)), 0.0, 1.0)


static func cz_range_nm() -> float:
	return maxf(float(Detection.environment.get("cz_range_nm", 0.0)), 0.0)


## Whether the water here is deep enough for the layer to have an underside.
static func layer_present_at(bottom_m: float) -> bool:
	var l := layer_depth_m()
	if l <= 0.0 or layer_strength() <= 0.0:
		return false
	return bottom_m < 0.0 or bottom_m > l + LAYER_MIN_WATER_BELOW_M


# --- The floor under a unit ---------------------------------------------------------------

## Water depth under a unit, cached until it has moved half a mile or the chart has changed.
## UNKNOWN (negative) when there is no chart.
static func bottom_m(u: Unit) -> float:
	if u.bottom_generation != Bathymetry.generation or u.position.distance_squared_to(u.bottom_sampled_at) > 0.25:
		u.bottom_depth_m = Bathymetry.depth_at(u.position)
		u.bottom_sampled_at = u.position
		u.bottom_generation = Bathymetry.generation
	return u.bottom_depth_m


## Deepest a boat can go here: its hull limit, or the floor less a margin, whichever is shallower.
static func max_operating_depth_m(u: Unit) -> float:
	var limit := u.spec.max_depth_m
	var floor_m := bottom_m(u)
	if floor_m >= 0.0:
		limit = minf(limit, maxf(floor_m - KEEL_CLEARANCE_M, 0.0))
	return limit


## Depth a boat should run at to be under the layer, or -1 if it cannot get there here.
static func below_layer_depth_m(u: Unit) -> float:
	var floor_m := bottom_m(u)
	if not layer_present_at(floor_m):
		return -1.0
	var wanted := layer_depth_m() + BELOW_LAYER_MARGIN_M
	var limit := max_operating_depth_m(u)
	if limit <= layer_depth_m() + 5.0:
		return -1.0
	return minf(wanted, limit)


# --- Where things sit in the water column ---------------------------------------------------

## Depth at which a sensor listens. Hull sets ride under the keel. A variable-depth or dipping body
## is lowered through the layer when there is one and the water allows, because that is where the
## submarine it is hunting will be. A submarine's own arrays are wherever the boat is.
static func sensor_depth_m(observer: Unit, sensor: SensorSpec) -> float:
	if observer.is_submarine():
		return observer.depth_m
	if sensor.array_depth_m <= 0.0:
		return HULL_ARRAY_DEPTH_M
	return deploy_depth_m(sensor.array_depth_m, bottom_m(observer))


## Where a lowered body goes, given how far it can be lowered and how deep the water is.
static func deploy_depth_m(max_depth: float, floor_m: float) -> float:
	var limit := max_depth
	if floor_m >= 0.0:
		limit = minf(limit, maxf(floor_m - ARRAY_CLEARANCE_M, HULL_ARRAY_DEPTH_M))
	if layer_present_at(floor_m):
		return minf(layer_depth_m() + BELOW_LAYER_MARGIN_M, limit)
	return minf(60.0, limit)


## Hydrophone depth for a buoy dropped here: the shallowest setting that gets under the layer,
## or the deepest the water allows when there is no layer to get under.
static func buoy_depth_m(floor_m: float) -> float:
	var deepest_ok := BUOY_DEPTHS_M[0]
	for d in BUOY_DEPTHS_M:
		if floor_m < 0.0 or d <= floor_m - ARRAY_CLEARANCE_M:
			deepest_ok = d
	if layer_present_at(floor_m):
		for d in BUOY_DEPTHS_M:
			if d > layer_depth_m() and d <= deepest_ok:
				return d
	return deepest_ok


## Depth at which a unit's own noise is made.
static func source_depth_m(target: Unit) -> float:
	return target.depth_m if target.is_submarine() else SURFACE_SOURCE_DEPTH_M


static func is_above_layer(depth_m: float) -> bool:
	return depth_m < layer_depth_m()


# --- Path factors -------------------------------------------------------------------------

## Multiplier on range for sound crossing the layer between two depths, at a place with this floor.
static func layer_factor(listener_depth_m: float, source_depth: float, floor_m: float) -> float:
	if not layer_present_at(floor_m):
		return 1.0
	if is_above_layer(listener_depth_m) == is_above_layer(source_depth):
		return 1.0
	return 1.0 - CROSS_LAYER_LOSS * layer_strength()


## Multiplier for bottom-limited water. 1.0 at shelf depth and beyond or with no chart.
static func shallow_factor(floor_m: float, floor_factor: float) -> float:
	if floor_m < 0.0 or floor_m >= SHELF_DEPTH_M:
		return 1.0
	return lerpf(floor_factor, 1.0, clampf((floor_m - SHOAL_DEPTH_M) / (SHELF_DEPTH_M - SHOAL_DEPTH_M), 0.0, 1.0))


## The shallower floor under either end of a path. Unknown if either end is uncharted.
static func path_floor_m(a: Unit, b: Unit) -> float:
	var fa := bottom_m(a)
	var fb := bottom_m(b)
	if fa < 0.0 or fb < 0.0:
		return Bathymetry.UNKNOWN
	return minf(fa, fb)


## Everything the water does to a passive direct path between this sensor and this target.
static func passive_path_factor(observer: Unit, sensor: SensorSpec, target: Unit) -> float:
	var floor_m := path_floor_m(observer, target)
	var f := shallow_factor(floor_m, SHALLOW_PASSIVE_FLOOR)
	f *= layer_factor(sensor_depth_m(observer, sensor), source_depth_m(target), floor_m)
	return f


## The same for an active ping, which crosses the layer twice and fights reverberation.
static func active_path_factor(observer: Unit, sensor: SensorSpec, target: Unit) -> float:
	var floor_m := path_floor_m(observer, target)
	var f := shallow_factor(floor_m, SHALLOW_ACTIVE_FLOOR)
	f *= layer_factor(sensor_depth_m(observer, sensor), source_depth_m(target), floor_m)
	return f


## For a buoy, which has no Unit of its own.
static func buoy_path_factor(buoy_depth: float, buoy_floor_m: float, target: Unit) -> float:
	var target_floor := bottom_m(target)
	var floor_m := Bathymetry.UNKNOWN if buoy_floor_m < 0.0 or target_floor < 0.0 else minf(buoy_floor_m, target_floor)
	return shallow_factor(floor_m, SHALLOW_PASSIVE_FLOOR) * layer_factor(buoy_depth, source_depth_m(target), floor_m)


# --- Convergence zones ----------------------------------------------------------------------

## Whether deep-water paths are available between two points at all.
static func deep_water_path(a: Vector2, b: Vector2) -> bool:
	if cz_range_nm() <= 0.0:
		return false
	var shallowest := Bathymetry.min_depth_along(a, b)
	return shallowest >= CZ_MIN_DEPTH_M


## Annuli as {index, range_nm, half_width_nm}, first zone first. Empty when there are none.
static func zones() -> Array:
	var r := cz_range_nm()
	if r <= 0.0:
		return []
	return [
		{"index": 1, "range_nm": r, "half_width_nm": r * CZ_HALF_WIDTH_FRACTION, "threshold": CZ_FIRST_THRESHOLD},
		{"index": 2, "range_nm": r * 2.0, "half_width_nm": r * 2.0 * CZ_HALF_WIDTH_FRACTION, "threshold": CZ_SECOND_THRESHOLD},
	]


## The zone this range falls in, or an empty dictionary. `direct_reach_nm` is how far the sensor
## would hear this target on a direct path with no water effects; only a loud enough source is
## still audible after the long way round.
static func cz_zone_for(sensor: SensorSpec, d: float, direct_reach_nm: float) -> Dictionary:
	if not sensor.cz_capable:
		return {}
	for z: Dictionary in zones():
		if absf(d - float(z["range_nm"])) <= float(z["half_width_nm"]) and direct_reach_nm >= float(z["range_nm"]) * float(z["threshold"]):
			return z
	return {}


## Whether the observer is sitting somewhere it could use convergence zones at all, for the
## display: deep water under it, a capable array and an environment that has them.
static func cz_available(observer: Unit) -> bool:
	if cz_range_nm() <= 0.0:
		return false
	var capable := false
	for s in observer.sensors:
		if s.kind == "sonar" and s.cz_capable:
			capable = true
	if not capable:
		return false
	return bottom_m(observer) >= CZ_MIN_DEPTH_M


# --- Presentation ---------------------------------------------------------------------------

## One-line description of the water under a unit, for the panels. Empty with no environment.
static func column_summary(u: Unit) -> String:
	var parts := PackedStringArray()
	var floor_m := bottom_m(u)
	if floor_m >= 0.0:
		parts.append("BOTTOM %s" % Bathymetry.format_depth(floor_m))
	if layer_present_at(floor_m):
		parts.append("LAYER %d m" % int(layer_depth_m()))
	if cz_available(u):
		parts.append("CZ %d nm" % int(round(cz_range_nm())))
	return "  ·  ".join(parts)
