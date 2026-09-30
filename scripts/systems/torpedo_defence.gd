class_name TorpedoDefence
## A ship's answer to a torpedo, which is not the answer to a missile. A missile is seen on radar and
## shot down or seduced by chaff; a torpedo is heard, and fought with noise. Two layers, both
## automatic, both only against a torpedo the ship can hear (itself or through the link):
##
##  - Hard kill. A weapon whose targets include "torpedo" (the Russian Paket-NK's anti-torpedo
##    round) is fired at a torpedo homing on the ship once it is inside the round's reach, through
##    the same interceptor path as a SAM: it runs out to the torpedo and the intercept is rolled.
##  - Soft kill. Once a torpedo homing on the ship is inside DECOY_RANGE_NM, the towed decoy (if
##    streamed, which takes way on the ship) has one try at pulling it off, then, if that fails, one
##    expendable acoustic decoy. A torpedo pulled off searches on along its heading, and may find
##    another ship; that ship's countermeasures then get their own try (WeaponManager.seduce).
##
## Manoeuvre is the AI's business (AIController turns away and runs); the player's ships get these
## two layers and the player's own orders. Effectiveness is a GAMEPLAY_ESTIMATE, divided by the
## torpedo's `soft_kill_resistance` as a missile's is.

const DECOY_RANGE_NM := 2.0
## An anti-torpedo round is launched no further out than this, whatever its reach as an ASW weapon.
const HARD_KILL_RANGE_NM := 1.6
const MAX_HARD_KILL_SHOTS := 2  # per torpedo, across the force
const MAX_DECOY_CHANCE := 0.9
## A towed body streamed from a ship that is barely moving hangs down and trails nothing useful.
const TOWED_MIN_SPEED_KN := 4.0


## One cycle for every ship. Returns the number of countermeasures used (decoys and rounds).
static func run_cycle(unit_manager: UnitManager, threat_manager: ThreatManager, weapon_manager: WeaponManager, now: float) -> int:
	var used := 0
	var pictures := {}
	for u in unit_manager.units:
		if not u.is_engageable() or u.in_flight():
			continue
		if not pictures.has(u.faction):
			pictures[u.faction] = threat_manager.get_threats(u.faction).filter(func(w: Weapon) -> bool: return w.spec.is_torpedo() and not w.is_interceptor())
		for w: Weapon in pictures[u.faction]:
			if w.phase == Weapon.Phase.DEAD or w.is_interceptor() or not w.spec.is_torpedo() or w.acquired != u:
				continue
			if not threat_manager.visible_to(u, w):
				continue
			used += _hard_kill(u, w, weapon_manager, now)
			if w.phase != Weapon.Phase.DEAD:
				used += _soft_kill(u, w, weapon_manager)
	return used


## The ship's anti-torpedo weapon, if it has one with rounds left.
static func hard_kill_weapon(u: Unit) -> WeaponSpec:
	for spec in u.weapons:
		if spec.target_types.has("torpedo") and u.magazine_count(spec.id) > 0:
			return spec
	return null


static func _hard_kill(u: Unit, w: Weapon, weapon_manager: WeaponManager, now: float) -> int:
	if u.roe == Unit.Roe.HOLD or not u.can_fire() or w.hard_kill_shots >= MAX_HARD_KILL_SHOTS:
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
	if not u.auto_countermeasures or (u.countermeasure_kind == "acoustic" and u.countermeasure_remaining_s > 0):
		return 0
	if w.acoustic_decoy_tried.has(u.id) or u.position.distance_to(w.position) > DECOY_RANGE_NM:
		return 0
	var towed := u.spec.towed_torpedo_decoy and u.speed_kn >= TOWED_MIN_SPEED_KN
	if not towed and u.torpedo_decoys <= 0:
		return 0
	w.acoustic_decoy_tried[u.id] = true
	var chance := decoy_chance(u.spec, w.spec)
	var used := 0
	if towed:
		if weapon_manager.rng.randf() < chance:
			weapon_manager.seduce(w, u)
			return used
	if u.torpedo_decoys > 0:
		u.torpedo_decoys -= 1
		used += 1
		weapon_manager.decoys_spent.emit(u, 1)
		if weapon_manager.rng.randf() < chance:
			weapon_manager.seduce(w, u)
	return used


## The chance one acoustic decoy pulls this torpedo off this ship.
static func decoy_chance(ship: PlatformSpec, torpedo: WeaponSpec) -> float:
	return clampf(ship.torpedo_decoy_effectiveness / maxf(torpedo.soft_kill_resistance, 0.1), 0.0, MAX_DECOY_CHANCE)
