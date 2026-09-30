class_name DefensiveResponse
## Player and AI defensive commands. All times, geometry and probabilities are game tuning.
## A pulse is a short-lived opportunity to seduce a compatible seeker, not a destroyed weapon.
## Evasion temporarily overrides steering; the original route and formation survive it.

const ACTIVE_SECONDS := 20.0
const RELOAD_SECONDS := 25.0
const MISSILE_RANGE_NM := 2.5
const ACOUSTIC_RANGE_NM := 2.0
const SURFACE_EVADE_SECONDS := 60.0
const AIR_EVADE_SECONDS := 25.0


static func tick(u: Unit, dt: float) -> void:
	u.countermeasure_remaining_s = maxf(u.countermeasure_remaining_s - dt, 0.0)
	u.countermeasure_reload_s = maxf(u.countermeasure_reload_s - dt, 0.0)
	u.evasion_remaining_s = maxf(u.evasion_remaining_s - dt, 0.0)


static func can_deploy(u: Unit, kind: String) -> bool:
	if not u.is_engageable() or u.countermeasure_reload_s > 0.0:
		return false
	if kind == "acoustic":
		return u.needs_sea_room() and u.torpedo_decoys > 0
	return kind in ["radar", "infrared"] and not u.submerged() and u.decoys > 0


static func deploy(u: Unit, kind: String, wm: WeaponManager) -> bool:
	if not can_deploy(u, kind):
		return false
	if kind == "acoustic":
		u.torpedo_decoys -= 1
	else:
		u.decoys -= 1
	u.countermeasure_kind = kind
	u.countermeasure_generation += 1
	u.countermeasure_remaining_s = ACTIVE_SECONDS
	u.countermeasure_reload_s = RELOAD_SECONDS
	wm.decoys_spent.emit(u, 1)
	return true


static func try_active(u: Unit, w: Weapon, wm: WeaponManager) -> bool:
	if w.phase == Weapon.Phase.DEAD or w.acquired != u or u.countermeasure_remaining_s <= 0.0:
		return false
	var band := w.spec.seeker_band()
	if band == "none" or band != u.countermeasure_kind:
		return false
	var reach := ACOUSTIC_RANGE_NM if band == "acoustic" else MISSILE_RANGE_NM
	if u.position.distance_to(w.position) > reach:
		return false
	var key := "%d:%d" % [u.id, u.countermeasure_generation]
	if w.countermeasure_attempts.has(key):
		return false
	w.countermeasure_attempts[key] = true
	w.decoy_attempted = true
	var effectiveness := u.spec.torpedo_decoy_effectiveness if band == "acoustic" else u.spec.decoy_effectiveness
	# Imaging seekers discriminate better than a simple heat seeker in this game abstraction.
	if w.spec.guidance.contains("imaging"):
		effectiveness *= 0.6
	var chance := clampf(effectiveness / maxf(w.spec.soft_kill_resistance, 0.1), 0.0, 0.9)
	if wm.rng.randf() < chance:
		wm.seduce(w, u)
		return true
	return false


static func run_cycle(um: UnitManager, tm: ThreatManager, wm: WeaponManager) -> void:
	var pictures := {}
	for u in um.units:
		if not u.is_engageable():
			continue
		if not pictures.has(u.faction):
			pictures[u.faction] = tm.get_threats(u.faction).filter(func(w: Weapon) -> bool: return not w.is_interceptor())
		for w: Weapon in pictures[u.faction]:
			if w.phase == Weapon.Phase.DEAD:
				continue
			if w.acquired != u or not tm.visible_to(u, w) or w.is_interceptor():
				continue
			var band := w.spec.seeker_band()
			# The automatic acoustic layer retains towed-decoy-first behaviour in TorpedoDefence.
			if u.auto_countermeasures and band in ["radar", "infrared"] and not w.decoy_attempted \
					and u.position.distance_to(w.position) <= MISSILE_RANGE_NM:
				deploy(u, band, wm)
			try_active(u, w, wm)


static func start_evasion(u: Unit, um: UnitManager, tm: ThreatManager, mode := "auto") -> bool:
	if not u.is_engageable() or u.spec.max_speed_kn <= 0.0 or (u.is_aircraft() and not u.airborne()):
		return false
	var incoming: Weapon = null
	var least_time := INF
	for entry: Dictionary in AirDefence.inbound_threats(um, tm, u.faction, u):
		if entry["target"] == u and float(entry["time_s"]) < least_time:
			incoming = entry["weapon"]
			least_time = float(entry["time_s"])
	if incoming == null:
		return false  # unknown weapons cannot supply a magic bearing to the player or AI
	var bearing := Geo.bearing_deg(u.position, incoming.position)
	var run_away := mode == "away" or (mode == "auto" and incoming.spec.is_torpedo())
	var candidates: Array = [bearing + 180.0] if run_away else [bearing + 90.0, bearing - 90.0]
	var best := u.heading_deg
	var best_score := -INF
	for candidate in candidates:
		var end := u.position + Geo.heading_to_vector(candidate) * maxf(u.effective_max_speed() / 60.0, 0.5)
		if u.needs_sea_room() and Terrain.blocks_path(u.position, end):
			continue
		var score := -absf(Geo.heading_delta(u.heading_deg, candidate))
		for friend in um.get_engageable_units(u.faction):
			if friend != u and friend.spec.domain == u.spec.domain and end.distance_to(friend.position) < 0.5:
				score -= 180.0
		if score > best_score:
			best_score = score
			best = candidate
	if best_score == -INF:
		return false
	u.evasion_start_heading_deg = u.heading_deg
	u.evasion_course_deg = fposmod(best, 360.0)
	u.evasion_remaining_s = AIR_EVADE_SECONDS if u.is_aircraft() else SURFACE_EVADE_SECONDS
	return true


## No immediate invulnerability: the hull must actually turn and build speed before this helps.
static func evasion_factor(u: Unit, spec: WeaponSpec) -> float:
	if u.evasion_remaining_s <= 0.0 or spec.is_gun() or spec.profile == "ballistic":
		return 1.0
	var turn := clampf(absf(Geo.heading_delta(u.evasion_start_heading_deg, u.heading_deg)) / 60.0, 0.0, 1.0)
	var speed := clampf(u.speed_kn / maxf(u.effective_max_speed(), 1.0), 0.0, 1.0)
	var benefit := 0.28 if u.is_aircraft() else 0.12
	return 1.0 - benefit * turn * speed


static func status(u: Unit) -> String:
	var parts := PackedStringArray()
	if u.evasion_remaining_s > 0:
		parts.append("EVADING %ds" % int(ceil(u.evasion_remaining_s)))
	if u.countermeasure_remaining_s > 0:
		parts.append("%s ACTIVE %ds" % [u.countermeasure_kind.to_upper(), int(ceil(u.countermeasure_remaining_s))])
	elif u.countermeasure_reload_s > 0:
		parts.append("CM READY IN %ds" % int(ceil(u.countermeasure_reload_s)))
	return " / ".join(parts)
