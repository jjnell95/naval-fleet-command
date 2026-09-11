class_name Combat
## Engagement geometry and probability. Pure static functions, no state, no randomness.

const LEAD_MAX_ITER := 4
const AIR_TARGET_BONUS := 1.5
const TORPEDO_EVASION_BENEFIT := 0.45
const BMD_INTERCEPTOR_ADVANTAGE := 0.45  # GAMEPLAY_ESTIMATE


## Lead intercept point against a track's estimated motion. Falls back to the raw track position
## when kinematics are not yet estimated.
static func intercept_point(launch_pos: Vector2, weapon_speed_kn: float, track_pos: Vector2, course_deg: float, target_speed_kn: float, has_kinematics: bool) -> Vector2:
	if not has_kinematics or target_speed_kn <= 0.1 or weapon_speed_kn <= 0.0:
		return track_pos
	var vel := Geo.heading_to_vector(course_deg) * Geo.knots_to_nm_per_s(target_speed_kn)
	var w := Geo.knots_to_nm_per_s(weapon_speed_kn)
	var aim := track_pos
	for i in LEAD_MAX_ITER:
		var t := launch_pos.distance_to(aim) / w
		aim = track_pos + vel * t
	return aim


## Flight profiles that have to get there over the water. A sea-skimmer, a gun round on a flat
## trajectory and a torpedo all stop at a coastline; a cruise missile at 8000 m, a ballistic round
## and an exoatmospheric interceptor do not. GAMEPLAY_ESTIMATE: the split is by profile alone,
## because a round carries no altitude of its own — the simplification is that every "high"
## weapon clears every hill.
const SURFACE_BOUND_PROFILES := ["sea_skimming", "direct", "subsurface"]


static func profile_is_surface_bound(spec: WeaponSpec) -> bool:
	return SURFACE_BOUND_PROFILES.has(spec.profile)


## Whether the path a round would actually fly crosses land. Tested against the lead point rather
## than the track, so the check and the firing solution drawn on the map agree.
static func crosses_land(shooter: Unit, spec: WeaponSpec, track: Track) -> bool:
	if Terrain.is_empty() or not profile_is_surface_bound(spec):
		return false
	var aim := intercept_point(shooter.position, spec.speed_kn, track.position, track.course_deg, track.speed_kn, track.has_kinematics)
	return Terrain.blocks_path(shooter.position, aim)


## Whether `shooter` may fire `spec` at `track` right now. Returns {ok, reason, range_nm}.
static func check_engagement(shooter: Unit, spec: WeaponSpec, track: Track) -> Dictionary:
	var out := {"ok": false, "reason": "", "range_nm": 0.0}
	if shooter == null or spec == null or track == null:
		out["reason"] = "NO TARGET"
		return out
	out["range_nm"] = shooter.position.distance_to(track.position)
	if not shooter.alive:
		out["reason"] = "UNIT LOST"
		return out
	if shooter.magazine_count(spec.id) <= 0:
		out["reason"] = "MAGAZINE EMPTY"
		return out
	if not shooter.can_fire():
		out["reason"] = "LAUNCHERS DAMAGED"
		return out
	if shooter.roe == Unit.Roe.HOLD:
		out["reason"] = "WEAPONS HOLD"
		return out
	if track.status == Track.Status.LOST:
		out["reason"] = "TRACK LOST"
		return out
	if not track.visible_to(shooter):
		out["reason"] = "TRACK NOT HELD / OFF LINK"
		return out
	if track.identity in ["NEUTRAL", "FRIENDLY"]:
		out["reason"] = "PROTECTED IDENTITY"
		return out
	if shooter.roe == Unit.Roe.TIGHT and track.identity != "HOSTILE":
		out["reason"] = "IDENTIFY CONTACT / WEAPONS TIGHT"
		return out
	if not suits_track(spec, track):
		out["reason"] = "WRONG WEAPON FOR CONTACT"
		return out
	var d := shooter.position.distance_to(track.position)
	out["range_nm"] = d
	if d > spec.max_range_nm:
		out["reason"] = "OUT OF RANGE"
		return out
	if d < spec.min_range_nm:
		out["reason"] = "TOO CLOSE"
		return out
	if crosses_land(shooter, spec, track):
		out["reason"] = "NO LINE OF FIRE"
		return out
	out["ok"] = true
	out["reason"] = "IN ENVELOPE"
	return out


## Probability that one interceptor destroys one incoming round. Fast, low-flying or stealthy
## rounds carry a higher `defensive_difficulty` and are correspondingly harder to stop.
static func intercept_probability(interceptor: WeaponSpec, threat: WeaponSpec) -> float:
	if interceptor.base_pk <= 0.0:
		return 0.0  # a weapon with no listed effectiveness cannot intercept
	var difficulty := threat.defensive_difficulty
	# A ballistic round is a very hard problem for a missile built for the atmosphere, and a
	# tractable one for an interceptor built to meet it outside it.
	if threat.profile == "ballistic" and interceptor.profile == "exoatmospheric":
		difficulty *= BMD_INTERCEPTOR_ADVANTAGE
	# The floor keeps very difficult rounds from becoming outright immune.
	return clampf(interceptor.base_pk / maxf(difficulty, 0.1), 0.05, 0.95)


## Hit probability once the seeker has acquired a real unit. Milestone 4 will subtract the
## effect of hard-kill and soft-kill defences here.
static func hit_probability(spec: WeaponSpec, target: Unit) -> float:
	if spec.is_torpedo():
		# A ship that has heard the torpedo and is running gives the weapon a much harder problem.
		# Turning away and opening the range is the only hard answer a surface ship has.
		var evasion := clampf(target.speed_kn / maxf(target.spec.max_speed_kn, 1.0), 0.0, 1.0)
		return clampf(spec.base_pk * (1.0 - TORPEDO_EVASION_BENEFIT * evasion), 0.05, 0.99)
	if target.airborne():
		# An aircraft is a far easier thing to hit than a sea-skimming missile, and these weapons
		# are rated against the harder job.
		return clampf(spec.base_pk * AIR_TARGET_BONUS, 0.0, 0.90)
	var size_mod := clampf(0.75 + target.spec.signature_factor * 0.25, 0.6, 1.1)
	return clampf(spec.base_pk * size_mod, 0.0, 0.99)


## How long this weapon would take to cover a given range.
static func time_of_flight_s(spec: WeaponSpec, range_nm: float) -> float:
	if spec.speed_kn <= 0.0:
		return INF
	return range_nm / spec.speed_kn * 3600.0


## Whether this weapon is the right kind for what the track is believed to be. A contact whose
## domain is not yet known cannot be matched to a weapon, which is another reason to classify
## before shooting.
static func suits_track(spec: WeaponSpec, track: Track) -> bool:
	if track.domain == "subsurface":
		return spec.target_types.has("subsurface")
	if track.domain == "surface":
		return spec.target_types.has("surface")
	if track.domain == "air":
		return spec.target_types.has("air")
	if track.domain == "land":
		return spec.target_types.has("land")  # nothing in the current inventory does
	return false
