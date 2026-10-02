class_name WorldPresentation
## What the world view may show, where, and as what. Pure static functions over the simulation's
## managers that return plain Dictionaries, so every rule can be tested headless without a viewport.
##
## The rule is the game's rule: no perfect information. Own units are drawn as they are. Anything
## else appears for exactly one of two reasons: a lookout could see it (VISUAL), or the plot holds
## it (PLOTTED). A plotted contact is built from the Track alone and the public class catalogue.
## `Track.truth` is used only to associate a sighted unit with its held contact.
##
## Axes: 1 world unit is 1 metre, the focus sits at the origin, +X is east, +Y is up and north is
## -Z. Models have their bow along +X, so heading h (degrees true) is a rotation of 90° - h about
## +Y. Nautical miles convert at 1852 m.

const NM_TO_M := 1852.0
const DEFAULT_VISIBILITY_NM := 10.0
const MAX_RANGE_NM := 40.0
const MAX_ENTITIES := 48
const LAND_RANGE_NM := 60.0
const MODEL_UNITS := 10.0  # every GLB is normalised so its longest dimension spans this
const WATERLINE_FRACTION := 1.0 - PlatformArt.WATERLINE  # of a hull's height sits below the water
const WEAPON_LENGTH_M := 6.0
const TRACER_LENGTH_M := 28.0  # a shell is drawn as its tracer streak
const TORPEDO_DEPTH_M := 6.0
const PERISCOPE_MAST_M := 1.5
const SINK_DURATION_S := 90.0
const FALL_DURATION_S := 12.0
const FALLBACK_LENGTH_M := {"surface": 150.0, "air": 15.0, "subsurface": 80.0, "land": 150.0}
## Size of the generic contact marker for a plotted contact whose class is not yet known.
const MARKER_LENGTH_M := {"surface": 120.0, "air": 24.0, "subsurface": 70.0, "": 60.0}
## Where a plotted contact is put in the water column when the plot says nothing more.
const PLOTTED_AIR_HEIGHT_M := 2500.0
const PLOTTED_SUB_DEPTH_M := 60.0
const BALLISTIC_APEX_MIN_M := 3000.0
const BALLISTIC_APEX_MAX_M := 45000.0
const BALLISTIC_APEX_PER_NM_M := 220.0
const INTERCEPTOR_CLIMB_S := 20.0
## How the force-centre focus is framed: its nominal length spans the group, within these limits.
const FORCE_MIN_FRAME_M := 350.0
const FORCE_MAX_FRAME_M := 2500.0
## How close to a held contact an unseen event must fall to be drawn at that contact.
const WITNESS_PLOT_NM := 1.0


# --- Environment -------------------------------------------------------------------------

static func visibility_nm(env: Dictionary) -> float:
	return maxf(float(env.get("visibility_nm", DEFAULT_VISIBILITY_NM)), 0.1)


## The height a lookout has to see over: a periscope is a periscope, whatever mast the class has.
static func sighting_height_m(u: Unit) -> float:
	if u.is_submarine() and u.at_periscope_depth():
		return PERISCOPE_MAST_M
	return Detection.mast_or_altitude_m(u)


## Range at which someone aboard `observer` could see `target` with the naked eye: the weather's
## visibility or the geometric horizon between the two heights, whichever is shorter.
static func visual_range_nm(observer: Unit, target: Unit, env: Dictionary) -> float:
	return minf(visibility_nm(env), Detection.radar_horizon_nm(sighting_height_m(observer), sighting_height_m(target)))


## Whether any of `observers` can see `target`. A submerged boat cannot be seen at any range.
static func in_visual_range(observers: Array, target: Unit, env: Dictionary) -> bool:
	if target.submerged():
		return false
	for o: Unit in observers:
		if not o.is_engageable() or o.submerged():
			continue  # a stowed aircraft or a boat below periscope depth has no lookout above water
		if o.position.distance_to(target.position) <= visual_range_nm(o, target, env) and not Terrain.masks_line_of_sight(o.position, sighting_height_m(o), target.position, sighting_height_m(target)):
			return true
	return false


# --- Units and contacts ------------------------------------------------------------------

## Everything that may be drawn as a hull, an airframe or a contact, as plain dictionaries:
##   kind        "own" | "visual" | "plotted"
##   key         stable identity for pooling: "u:<unit id>" or "t:<track id>"
##   model       GLB id under assets/models, or "" for a generic marker
##   position    Vector2 nm on the chart
##   heading_deg, has_heading
##   height_m    metres above the sea (+) or below it (-)
##   domain      surface | air | subsurface | land
##   length_m    the real length the model is scaled to
##   label, sublabel, color
##   unit        the Unit for own and visual presentations, else null
##   track       the Track for plotted (and labelled visual) presentations, else null
static func unit_entries(unit_manager: UnitManager, track_manager: TrackManager, player_faction: String, env: Dictionary, neutral_factions := PackedStringArray()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if unit_manager == null:
		return out
	var own: Array[Unit] = []
	for u: Unit in unit_manager.units:
		if u.faction == player_faction and u.is_engageable():
			own.append(u)
	var tracks: Array = track_manager.get_tracks(player_faction) if track_manager != null else []
	for u in own:
		out.append(own_entry(u))
	var sighted: Dictionary = {}
	for u: Unit in unit_manager.units:
		if u.faction == player_faction or not u.is_engageable():
			continue
		if in_visual_range(own, u, env):
			out.append(visual_entry(u, _track_holding(tracks, u), neutral_factions.has(u.faction)))
			sighted[u] = true
	for t: Track in tracks:
		if not plottable(t):
			continue
		if t.truth != null and sighted.has(t.truth):
			continue  # a sighted unit is shown once, as what it is
		out.append(plotted_entry(t))
	return out


## A track the view may draw: held now, with a range to put it somewhere.
static func plottable(t: Track) -> bool:
	return t != null and t.status == Track.Status.ACTIVE and not t.is_bearing_only()


## The track associated with a sighted unit, for its label. Association is what `truth` is for;
## nothing else is read through it here.
static func _track_holding(tracks: Array, u: Unit) -> Track:
	for t: Track in tracks:
		if t.truth == u and t.status != Track.Status.LOST:
			return t
	return null


static func domain_of(u: Unit) -> String:
	if u.is_aircraft():
		return "air"
	if u.is_submarine():
		return "subsurface"
	return u.spec.domain


static func length_of(spec: PlatformSpec) -> float:
	if spec != null and spec.length_m > 0.0:
		return spec.length_m
	return float(FALLBACK_LENGTH_M.get(spec.domain if spec != null else "surface", 150.0))


static func height_of(u: Unit) -> float:
	if u.is_aircraft():
		return u.altitude_m
	if u.is_submarine():
		return -u.depth_m
	return 0.0


static func identity_color(identity: String) -> Color:
	match identity:
		"HOSTILE":
			return TacticalMap.COL_HOSTILE
		"NEUTRAL":
			return TacticalMap.COL_NEUTRAL
		"FRIENDLY":
			return TacticalMap.COL_FRIENDLY
	return TacticalMap.COL_UNKNOWN


static func motion_text(heading_deg: float, speed_kn: float, height_m: float, domain: String) -> String:
	var text := "%03d° · %d kn" % [int(roundf(fposmod(heading_deg, 360.0))) % 360, int(roundf(speed_kn))]
	if domain == "air":
		text += " · %s m" % _thousands(height_m)
	elif domain == "subsurface":
		text += " · %.0f m" % absf(height_m)
	return text


static func _thousands(v: float) -> String:
	var n := int(roundf(v))
	if n < 1000:
		return str(n)
	return "%d %03d" % [n / 1000, n % 1000]


static func own_entry(u: Unit) -> Dictionary:
	var domain := domain_of(u)
	var height := height_of(u)
	return {
		"kind": "own", "key": "u:%d" % u.id, "model": u.spec.id,
		"position": u.position, "heading_deg": u.heading_deg, "has_heading": true,
		"height_m": height, "domain": domain, "length_m": length_of(u.spec),
		"label": u.callsign, "sublabel": motion_text(u.heading_deg, u.speed_kn, height, domain),
		"color": TacticalMap.COL_FRIENDLY, "unit": u, "track": null,
	}


## A unit inside visual range: its real model, where it really is. The label is whatever the plot
## knows about it; eyes alone do not give a callsign.
static func visual_entry(u: Unit, held: Track, neutral: bool) -> Dictionary:
	var domain := domain_of(u)
	var height := height_of(u)
	var label := "SIGHTED"
	var sub := ("NEUTRAL " if neutral else "") + domain.to_upper()
	var color := TacticalMap.COL_NEUTRAL if neutral else TacticalMap.COL_UNKNOWN
	if held != null:
		label = held.id
		sub = held.description()
		color = identity_color(held.identity)
	return {
		"kind": "visual", "key": "u:%d" % u.id, "model": u.spec.id,
		"position": u.position, "heading_deg": u.heading_deg, "has_heading": true,
		"height_m": height, "domain": domain, "length_m": length_of(u.spec),
		"label": label, "sublabel": sub, "color": color, "unit": u, "track": held,
	}


## A contact from the plot: the estimated position and, if the fit has one, the estimated course.
## The class model appears only once the class is known; below that the contact is a marker.
static func plotted_entry(t: Track) -> Dictionary:
	var model := ""
	var length := float(MARKER_LENGTH_M.get(t.domain, MARKER_LENGTH_M[""]))
	var height := 0.0
	if t.classification >= Track.Classification.CLASS_KNOWN:
		model = MapSymbols.platform_for_class(t.known_class, t.known_category)
		if model != "":
			length = length_of(DataDB.platform(model))
	match t.domain:
		"air":
			height = t.altitude_m if t.altitude_m >= 0.0 else PLOTTED_AIR_HEIGHT_M
		"subsurface":
			height = -PLOTTED_SUB_DEPTH_M  # schematic water column; the plot has no depth measurement
	return {
		"kind": "plotted", "key": "t:%s" % t.id, "model": model,
		"position": t.position, "heading_deg": t.course_deg if t.has_kinematics else 0.0, "has_heading": t.has_kinematics,
		"height_m": height, "domain": t.domain, "length_m": length,
		"label": t.id, "sublabel": t.description(), "color": identity_color(t.identity), "unit": null, "track": t,
	}


## The camera describes the evidence behind the picture, including why no model can be placed.
static func contact_caption(t: Track, sighted: bool) -> String:
	var subject := "%s · %s" % [t.id, t.description()]
	if sighted:
		return "SIGHTED · " + subject
	if t.status != Track.Status.ACTIVE:
		return "NO CURRENT FIX · %s · %s" % ["STALE" if t.status == Track.Status.STALE else "LOST", subject]
	if t.is_bearing_only():
		return "BEARING ONLY · range unresolved · " + subject
	var qualifier := ""
	if t.domain == "subsurface":
		qualifier = " · depth unmeasured"
	elif t.domain == "air" and t.altitude_m < 0.0:
		qualifier = " · altitude unmeasured"
	return "SENSOR ESTIMATE · " + subject + qualifier


# --- Weapons and buoys -------------------------------------------------------------------

## Rounds in flight: our own always; anyone else's only when the reference unit's picture holds
## it. With no reference unit there is no picture, so only our own rounds show.
static func weapon_entries(weapon_manager: WeaponManager, threat_manager: ThreatManager, player_faction: String, reference: Unit) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if weapon_manager == null:
		return out
	for w: Weapon in weapon_manager.in_flight:
		if w.phase == Weapon.Phase.DEAD:
			continue
		var own := w.faction == player_faction
		if not own and (reference == null or threat_manager == null or not threat_manager.visible_to(reference, w)):
			continue
		var torpedo := w.spec.is_torpedo()
		var gun := w.spec.type == "gun" or w.spec.type == "ciws"
		var color := TacticalMap.COL_MISSILE if own else TacticalMap.COL_MISSILE_HOSTILE
		if w.is_interceptor():
			color = TacticalMap.COL_INTERCEPTOR
		out.append({
			"kind": "weapon", "key": "w:%d" % w.id, "model": w.spec.id,
			"position": w.position, "heading_deg": w.heading_deg, "has_heading": true,
			"height_m": weapon_height_m(w), "domain": "weapon", "length_m": TRACER_LENGTH_M if gun else WEAPON_LENGTH_M,
			"label": "", "sublabel": "", "color": color, "unit": null, "track": null,
			"weapon": w, "own": own, "torpedo": torpedo, "gun": gun, "interceptor": w.is_interceptor(),
			"ballistic": w.spec.profile == "ballistic" and not w.is_interceptor(),
		})
	return out


## Where a round is in the vertical. A torpedo runs a few metres down; a ballistic round arcs to
## an apex halfway along its reach; an interceptor climbs toward what it is chasing; everything
## else flies at the altitude its detection geometry already assumes.
static func weapon_height_m(w: Weapon) -> float:
	if w.spec.is_torpedo():
		return -TORPEDO_DEPTH_M
	if w.intercept_target != null:
		var goal := maxf(weapon_height_m(w.intercept_target), 0.0) if w.intercept_target.spec != null else 0.0
		var climb := clampf(w.time_alive_s / INTERCEPTOR_CLIMB_S, 0.0, 1.0)
		return maxf(w.spec.altitude_m, lerpf(w.spec.altitude_m, goal, climb))
	if w.spec.profile == "ballistic":
		return ballistic_height_m(w.distance_flown_nm, w.spec.max_range_nm)
	return w.flight_altitude_m()


static func ballistic_height_m(distance_flown_nm: float, max_range_nm: float) -> float:
	var f := clampf(distance_flown_nm / maxf(max_range_nm, 0.1), 0.0, 1.0)
	var apex := clampf(max_range_nm * BALLISTIC_APEX_PER_NM_M, BALLISTIC_APEX_MIN_M, BALLISTIC_APEX_MAX_M)
	return apex * sin(PI * f)


static func buoy_entries(aviation_manager: AviationManager, player_faction: String, now: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if aviation_manager == null:
		return out
	for b: Sonobuoy in aviation_manager.sonobuoys:
		if b.faction != player_faction or not b.alive_at(now):
			continue
		out.append({
			"kind": "buoy", "key": "b:%d" % b.id, "model": "", "position": b.position,
			"heading_deg": 0.0, "has_heading": false, "height_m": 0.0, "domain": "buoy", "length_m": 2.0,
			"label": "", "sublabel": "", "color": TacticalMap.COL_BUOY, "unit": null, "track": null,
		})
	return out


# --- Events ------------------------------------------------------------------------------

## Where the player could witness an event at `pos`, or Vector2.INF when they could not.
##
## With the `target` it happened to (a hit, a miss or a kill), the flash is seen where it happens
## when the target is one of ours, or when a lookout of ours could see it: within visual range and
## over the horizon, and never when it is a boat running deep. Failing that it is drawn where a
## held track of that target is plotted, because the plot is all the player has of it. Nothing
## else is read through the target.
##
## With no target, within the weather's visibility of one of their own units the flash is seen
## where it happens; failing that, an event close to a held contact is drawn at the contact's
## plotted position. Only own units and the player's tracks are read.
static func witness_point(pos: Vector2, own_units: Array, tracks: Array, env: Dictionary, target: Unit = null) -> Vector2:
	if target != null:
		if own_units.has(target):
			return pos
		# The same lookouts the view sights contacts with: our units at sea or in the air.
		var lookouts: Array = own_units.filter(func(u: Unit) -> bool: return u != null and u.is_engageable())
		if in_visual_range(lookouts, target, env):
			return pos
		for t: Track in tracks:
			if t.truth == target and plottable(t):
				return t.position
		return Vector2.INF
	var vis := visibility_nm(env)
	for u: Unit in own_units:
		if u != null and u.is_engageable() and not u.submerged() and u.position.distance_to(pos) <= vis:
			return pos
	var best := Vector2.INF
	var best_d := INF
	for t: Track in tracks:
		if not plottable(t):
			continue
		var d := t.position.distance_to(pos)
		if d <= maxf(WITNESS_PLOT_NM, t.position_error_nm * 1.5) and d < best_d:
			best_d = d
			best = t.position
	return best


## Whether the player's side could know a combat event happened to (or was fired by) `subject`:
## one of its own units was involved, or the same witness rule as the 3D view's says it was seen
## or is on a held contact. Main drops the watch to real time only for these, so the clock never
## announces a salvo, a hit or a kill the plot does not hold.
static func combat_observed(subject: Unit, own_involved: bool, own_units: Array, tracks: Array, env: Dictionary) -> bool:
	if own_involved:
		return true
	if subject == null:
		return false
	return witness_point(subject.position, own_units, tracks, env, subject) != Vector2.INF


# --- Focus and culling -------------------------------------------------------------------

## What the camera is looking at: the hooked own unit (a deck-bound airframe stands for its
## ship), else the hooked contact as the plot holds it, else the centre of the player's force.
## Returns {} when there is nothing at all.
static func choose_focus(selected: Array, selected_track: Track, own_units: Array) -> Dictionary:
	for u: Unit in selected:
		if u != null and u.alive and u.is_engageable():
			return _unit_focus(u)
	for u: Unit in selected:
		if u != null and u.home != null and u.home.alive:
			return _unit_focus(u.home)
	if plottable(selected_track):
		return {"key": "t:%s" % selected_track.id, "position": selected_track.position, "unit": null, "track": selected_track, "name": selected_track.id, "detail": selected_track.description()}
	return force_focus(own_units)


## The force centre: the mean position of the player's ships, or of whatever is left when only
## aircraft remain, with a heading from their mean course and a nominal length that frames the
## whole group. Only own units are read.
static func force_focus(own_units: Array) -> Dictionary:
	var ships: Array[Unit] = []
	var everything: Array[Unit] = []
	for u: Unit in own_units:
		if u == null or not u.is_engageable():
			continue
		everything.append(u)
		if not u.is_aircraft():
			ships.append(u)
	var group := ships if not ships.is_empty() else everything
	if group.is_empty():
		return {}
	var centre := Vector2.ZERO
	var course := Vector2.ZERO
	for u in group:
		centre += u.position
		course += Geo.heading_to_vector(u.heading_deg) * maxf(u.speed_kn, 0.1)
	centre /= float(group.size())
	var spread := 0.0
	for u in group:
		spread = maxf(spread, u.position.distance_to(centre))
	return {
		"key": "force", "position": centre, "unit": null, "track": null, "name": "Force centre",
		"detail": "%d platforms" % group.size(), "heading_deg": Geo.vector_to_heading(course) if course.length_squared() > 1e-9 else 0.0,
		"length_m": clampf(spread * NM_TO_M * 0.7, FORCE_MIN_FRAME_M, FORCE_MAX_FRAME_M),
	}


## The entry key the camera should follow for a focus. A hooked contact that a lookout can also
## see is drawn once, as the sighted unit, so the camera follows that; nothing else changes.
static func resolve_focus_key(entries: Array, focus: Dictionary) -> String:
	var key: String = focus.get("key", "")
	var track: Track = focus.get("track")
	if track == null or not key.begins_with("t:"):
		return key
	for e: Dictionary in entries:
		if e["kind"] == "visual" and e.get("track") == track:
			return e["key"]
	return key


static func _unit_focus(u: Unit) -> Dictionary:
	return {"key": "u:%d" % u.id, "position": u.position, "unit": u, "track": null, "name": u.callsign, "detail": u.spec.display_name}


## The nearest entries to `focus_nm` (the floating origin), inside `max_range_nm`, at most `cap`
## of them. The entries that carry `focus_key` (the hooked subject) and `keep_key` (what the
## Action camera follows, which may be far from the hook) are always kept, in that order.
static func cull(entries: Array, focus_nm: Vector2, focus_key := "", max_range_nm := MAX_RANGE_NM, cap := MAX_ENTITIES, keep_key := "") -> Array:
	var kept: Array = []
	for e in entries:
		var d: float = (e["position"] as Vector2).distance_to(focus_nm)
		if d <= max_range_nm or e["key"] == focus_key or (keep_key != "" and e["key"] == keep_key):
			kept.append(e)
	kept.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["key"] == focus_key:
			return true
		if b["key"] == focus_key:
			return false
		if keep_key != "":
			if a["key"] == keep_key:
				return true
			if b["key"] == keep_key:
				return false
		return (a["position"] as Vector2).distance_squared_to(focus_nm) < (b["position"] as Vector2).distance_squared_to(focus_nm))
	if kept.size() > cap:
		kept.resize(cap)
	return kept


# --- Axes and scale ----------------------------------------------------------------------

## Chart position to world metres about the floating origin: east is +X, north is -Z.
static func to_world(pos_nm: Vector2, origin_nm: Vector2, height_m := 0.0) -> Vector3:
	var d := (pos_nm - origin_nm) * NM_TO_M
	return Vector3(d.x, height_m, -d.y)


## Unit vector along a heading in world axes.
static func heading_vector(heading_deg: float) -> Vector3:
	var h := Geo.heading_to_vector(heading_deg)
	return Vector3(h.x, 0.0, -h.y)


## Rotation about +Y that points a model's +X bow down `heading_deg`.
static func heading_to_yaw(heading_deg: float) -> float:
	return deg_to_rad(90.0 - heading_deg)


## Uniform scale for a normalised model standing in for something `length_m` long.
static func model_scale(length_m: float) -> float:
	return maxf(length_m, 0.5) / MODEL_UNITS


## How far a hull model, centred on its bounding box, has to be lifted so that the bottom
## WATERLINE_FRACTION of its height sits below the water. `height_units` is the model's unscaled
## height and `scale` the factor it is drawn at.
static func hull_lift_m(height_units: float, scale: float) -> float:
	return (0.5 - WATERLINE_FRACTION) * height_units * scale


# --- Swell -------------------------------------------------------------------------------

## Two long swell trains, the same in the ocean shader and here, so hulls, wakes and rings ride
## the same water. Returns {amplitude1, length1, amplitude2, length2} in metres.
static func swell_params(sea_state: int) -> Vector4:
	var s := clampf(float(sea_state), 0.0, 6.0)
	return Vector4(0.05 + 0.17 * s, 45.0 + 26.0 * s, 0.03 + 0.09 * s, 28.0 + 14.0 * s)


## Downwind unit direction in world xz for the scenario's wind.
static func wind_direction(env: Dictionary) -> Vector2:
	var from_deg := float(env.get("wind_from_deg", TacticalMap.DEFAULT_WIND_FROM_DEG))
	var v := heading_vector(from_deg + 180.0)
	return Vector2(v.x, v.z)


## Height of the swell at a point (world metres about the origin, plus the origin offset the
## shader is given) at time `t` seconds. Deep-water dispersion sets the period of each train.
static func swell_height(p: Vector2, t: float, params: Vector4, dir1: Vector2, dir2: Vector2) -> float:
	var k1 := TAU / maxf(params.y, 1.0)
	var k2 := TAU / maxf(params.w, 1.0)
	var w1 := sqrt(9.81 * k1)
	var w2 := sqrt(9.81 * k2)
	return params.x * sin(p.dot(dir1) * k1 - w1 * t) + params.z * sin(p.dot(dir2) * k2 - w2 * t + 1.7)


# --- Sun ---------------------------------------------------------------------------------

## Solar elevation and azimuth (degrees; azimuth clockwise from north) for a UTC unix time at a
## latitude and longitude. NOAA's declination and equation-of-time series, which is the standard
## low-precision approximation and is good to a fraction of a degree here.
static func sun_angles(unix_time: float, lat_deg: float, lon_deg: float) -> Vector2:
	var d := Time.get_datetime_dict_from_unix_time(int(floorf(unix_time)))
	var jan1 := Time.get_unix_time_from_datetime_dict({"year": d["year"], "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0})
	var since := unix_time - float(jan1)
	var day_of_year := floorf(since / 86400.0) + 1.0
	var hour := fmod(since / 3600.0, 24.0)
	var g := TAU / 365.0 * (day_of_year - 1.0 + (hour - 12.0) / 24.0)
	var eqtime := 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g) - 0.014615 * cos(2.0 * g) - 0.040849 * sin(2.0 * g))
	var decl := 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2.0 * g) + 0.000907 * sin(2.0 * g) - 0.002697 * cos(3.0 * g) + 0.00148 * sin(3.0 * g)
	var solar_minutes := hour * 60.0 + eqtime + 4.0 * lon_deg
	var ha := deg_to_rad(solar_minutes / 4.0 - 180.0)
	var lat := deg_to_rad(lat_deg)
	var sin_el := sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(ha)
	var el := rad_to_deg(asin(clampf(sin_el, -1.0, 1.0)))
	var az := fposmod(rad_to_deg(atan2(sin(ha), cos(ha) * sin(lat) - tan(decl) * cos(lat))) + 180.0, 360.0)
	return Vector2(el, az)


## Unit vector toward the sun in world axes (+X east, +Y up, -Z north).
static func sun_direction(unix_time: float, lat_deg: float, lon_deg: float) -> Vector3:
	return sun_direction_from_angles(sun_angles(unix_time, lat_deg, lon_deg))


## Uses an already-computed solar position when the caller needs both elevation and direction.
static func sun_direction_from_angles(a: Vector2) -> Vector3:
	var el := deg_to_rad(a.x)
	var az := deg_to_rad(a.y)
	return Vector3(cos(el) * sin(az), sin(el), -cos(el) * cos(az)).normalized()


## The chart position's latitude and longitude from the scenario's map anchor.
static func latlon_of(pos_nm: Vector2, chart: Dictionary) -> Vector2:
	if chart.has("anchor_lat") and chart.has("anchor_lon"):
		return Geo.world_to_latlon(pos_nm, float(chart["anchor_lat"]), float(chart["anchor_lon"]))
	return Vector2(60.0, 0.0)
