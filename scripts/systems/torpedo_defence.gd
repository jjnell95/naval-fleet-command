class_name TorpedoDefence
## A ship's answer to a torpedo, which is not the answer to a missile. A missile is seen on radar and
## shot down or seduced by chaff; a torpedo is heard, and fought with noise. Two layers, both
## automatic, both only against a torpedo the ship can hear (itself or through the link):
##
##  - Hard kill. A weapon whose targets include "torpedo" (the Russian Paket-NK's anti-torpedo
##    round) is fired at a torpedo homing on the ship once it is inside the round's reach, through
##    the same interceptor path as a SAM: it runs out to the torpedo and the intercept is rolled.
##  - Soft kill. Once a torpedo homing on the ship is inside DefensiveResponse.ACOUSTIC_RANGE_NM,
##    the towed decoy (if streamed, which takes way on the ship) has one try at pulling it off;
##    while it is still running at her she then lays expendable acoustic pulses, one each time
##    the launcher has reloaded (DefensiveResponse.RELOAD_SECONDS), until she has none left. Each
##    pulse covers nearby compatible seekers and gets its own try, and uses the same reload as a
##    manual deployment. A torpedo pulled off searches on along its heading, and may find another
##    ship; that ship's countermeasures then get their own try (WeaponManager.seduce).
##
## A ship fitted with a torpedo-defence system has that system's own short-range warning
## (TDS_WARNING_NM), sonar or none. On automatic countermeasures a surface ship turns away and
## runs from a torpedo she holds coming at her as soon as she holds it, homing or not, and keeps
## running while it does. The AI's ships do the same through AIController. Effectiveness is a
## GAMEPLAY_ESTIMATE, divided by the torpedo's `soft_kill_resistance` as a missile's is.

## An anti-torpedo round is launched no further out than this, whatever its reach as an ASW weapon.
const HARD_KILL_RANGE_NM := 1.6
const MAX_HARD_KILL_SHOTS := 2  # per torpedo, across the force
const MAX_DECOY_CHANCE := 0.9
## A towed body streamed from a ship that is barely moving hangs down and trails nothing useful.
const TOWED_MIN_SPEED_KN := 4.0
## A torpedo-defence fit hears a running torpedo this close, whatever the ship's hull sonar can do.
## GAMEPLAY_ESTIMATE.
const TDS_WARNING_NM := 3.0


## One cycle for every ship. Returns the number of countermeasures used (decoys and rounds).
static func run_cycle(unit_manager: UnitManager, threat_manager: ThreatManager, weapon_manager: WeaponManager, now: float) -> int:
	var used := 0
	if not _warn(unit_manager, threat_manager, weapon_manager, now):
		return 0  # nothing in the water
	var pictures := {}
	var running := {}
	for u in unit_manager.units:
		if not u.is_engageable() or u.in_flight():
			continue
		if not pictures.has(u.faction):
			pictures[u.faction] = DefensiveResponse.acquired_threats(threat_manager, u.faction, true)
			running[u.faction] = _torpedoes_inbound(unit_manager, threat_manager, u.faction)
		# A torpedo held coming at her, homing or still searching its way in: she runs from it now,
		# not once it has her, and keeps running while it does.
		if u.auto_countermeasures and not u.is_submarine() and u.evasion_remaining_s <= 0.0:
			for w: Weapon in running[u.faction].get(u, []):
				if w.phase != Weapon.Phase.DEAD and threat_manager.visible_to(u, w):
					DefensiveResponse.start_evasion(u, unit_manager, threat_manager, "away")
					break
		for w: Weapon in pictures[u.faction].get(u, []):
			if w.phase == Weapon.Phase.DEAD or w.is_interceptor() or not w.spec.is_torpedo() or w.acquired != u:
				continue
			if not threat_manager.visible_to(u, w):
				continue
			w.heard_by[u.id] = true
			used += _hard_kill(u, w, weapon_manager, now)
			if w.phase != Weapon.Phase.DEAD:
				used += _soft_kill(u, w, weapon_manager)
			DefensiveResponse.update_acquired_threat(pictures[u.faction], w, u)
	return used


## Whether this unit carries a torpedo-defence system: decoys, towed or expendable, or an
## anti-torpedo weapon.
static func fitted(u: Unit) -> bool:
	if u.spec.torpedo_decoy != "" or u.spec.towed_torpedo_decoy or u.spec.torpedo_decoy_count > 0:
		return true
	for spec in u.weapons:
		if spec.target_types.has("torpedo"):
			return true
	return false


## Torpedoes this side holds running at each of its units, homing or not: unit -> [Weapon].
static func _torpedoes_inbound(unit_manager: UnitManager, threat_manager: ThreatManager, faction: String) -> Dictionary:
	var by_target := {}
	for entry: Dictionary in AirDefence.inbound_threats(unit_manager, threat_manager, faction):
		var w: Weapon = entry["weapon"]
		if not w.spec.is_torpedo():
			continue
		var u: Unit = entry["target"]
		if not by_target.has(u):
			by_target[u] = []
		by_target[u].append(w)
	return by_target


## The fit's own warning: any other side's torpedo running inside TDS_WARNING_NM of a fitted ship
## is held by her side, as her sonar would hold it, for this cycle. Whether any torpedo is running.
static func _warn(unit_manager: UnitManager, threat_manager: ThreatManager, weapon_manager: WeaponManager, now: float) -> bool:
	var torpedoes: Array[Weapon] = []
	for w: Weapon in weapon_manager.in_flight:
		if w.phase != Weapon.Phase.DEAD and not w.is_interceptor() and w.spec.is_torpedo():
			torpedoes.append(w)
	if torpedoes.is_empty():
		return false
	for u: Unit in unit_manager.units:
		if not u.is_engageable() or u.in_flight() or not fitted(u):
			continue
		for w: Weapon in torpedoes:
			if w.faction == u.faction or u.position.distance_squared_to(w.position) > TDS_WARNING_NM * TDS_WARNING_NM:
				continue
			if not Detection.terrain_hides_weapon(u, w):
				threat_manager.mark_detected(u.faction, w, now, u)
	return true


## The ship's anti-torpedo weapon, if it has one with rounds left.
static func hard_kill_weapon(u: Unit) -> WeaponSpec:
	for spec in u.weapons:
		if spec.target_types.has("torpedo") and u.magazine_count(spec.id) > 0:
			return spec
	return null


static func _hard_kill(u: Unit, w: Weapon, weapon_manager: WeaponManager, now: float) -> int:
	# Weapons hold is an order not to attack; the ship still shoots at a torpedo homing on it.
	if not u.can_fire() or w.hard_kill_shots >= MAX_HARD_KILL_SHOTS:
		return 0
	var spec := hard_kill_weapon(u)
	if spec == null:
		return 0
	var d := u.position.distance_to(w.position)
	if d > minf(spec.max_range_nm, HARD_KILL_RANGE_NM) or d < spec.min_range_nm:
		return 0
	if Detection.terrain_hides_weapon(u, w):
		return 0  # heard over the datalink, but the round cannot run through the land between
	var fired := weapon_manager.launch_interceptor(u, spec, w, 1, now)
	w.hard_kill_shots += fired
	return fired


static func _soft_kill(u: Unit, w: Weapon, weapon_manager: WeaponManager) -> int:
	if not u.auto_countermeasures or u.position.distance_to(w.position) > DefensiveResponse.ACOUSTIC_RANGE_NM:
		return 0
	# Noise is no use against a seeker that is not listening: a wake-homer follows the bubbles.
	if w.spec.seeker_band() != "acoustic":
		return 0
	var active := u.countermeasure_kind == "acoustic" and u.countermeasure_remaining_s > 0.0
	var towed := u.spec.towed_torpedo_decoy and u.speed_kn >= TOWED_MIN_SPEED_KN
	if not towed and u.torpedo_decoys <= 0 and not active:
		return 0
	if not w.acoustic_decoy_tried.has(u.id):
		w.acoustic_decoy_tried[u.id] = true
		if towed and weapon_manager.rng.randf() < decoy_chance(u.spec, w.spec):
			weapon_manager.seduce(w, u)
			return 0
	# Manual and automatic expendables share a pulse, its reload and its attempt record. While the
	# torpedo is still running at her she lays another each time the launcher has reloaded; each
	# pulse gets its own try (DefensiveResponse.try_active keys them by generation).
	var used := 0
	if not active:
		if not DefensiveResponse.deploy(u, "acoustic", weapon_manager):
			return 0
		used = 1
	DefensiveResponse.try_active(u, w, weapon_manager)
	return used


## The chance one acoustic decoy pulls this torpedo off this ship.
static func decoy_chance(ship: PlatformSpec, torpedo: WeaponSpec) -> float:
	return clampf(ship.torpedo_decoy_effectiveness / maxf(torpedo.soft_kill_resistance, 0.1), 0.0, MAX_DECOY_CHANCE)
