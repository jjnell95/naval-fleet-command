class_name AirDefence
## Automatic layered self-defence. Ships defend themselves without player orders: the player
## decides emissions, position and magazines, not individual interception shots.
##
## Layering falls out of the data. `Unit.defensive_weapons()` returns interceptors longest-reach
## first, so the outermost layer that can shoot takes the shot, and shorter-ranged layers get
## their chance only as the round closes.

const CPA_THREAT_NM := 3.0  # a round passing wider than this is not treated as inbound
const MAX_INTERCEPTORS_PER_THREAT := 2  # in the air against one round at any moment
const MAX_LIFETIME_INTERCEPTORS_PER_THREAT := 2  # shoot-shoot-look, then it is what it is
const MAX_CLOSE_IN_BURSTS_PER_THREAT := 2  # a round crosses the close-in envelope in seconds
const DECOY_RANGE_NM := 2.5


## Closest point of approach of `w` to `u`, as {cpa_nm, time_s}. Time is negative when the round
## has already passed.
static func closest_approach(u: Unit, w: Weapon) -> Dictionary:
	var rel_pos := w.position - u.position
	var wv := Geo.heading_to_vector(w.heading_deg) * w.speed_nm_per_s()
	var uv := Geo.heading_to_vector(u.heading_deg) * Geo.knots_to_nm_per_s(u.speed_kn)
	var rel_vel := wv - uv
	var speed2 := rel_vel.length_squared()
	if speed2 < 1e-12:
		return {"cpa_nm": rel_pos.length(), "time_s": 0.0}
	var t := -rel_pos.dot(rel_vel) / speed2
	if t < 0.0:
		return {"cpa_nm": rel_pos.length(), "time_s": t}
	return {"cpa_nm": (rel_pos + rel_vel * t).length(), "time_s": t}


## Whether a round could physically still arrive at this unit. A missile is not a threat to
## everything its current heading eventually points at: an air-to-air round fired two hundred
## miles away, at an aircraft, has neither the legs nor the intention to reach a ship, and
## treating it as inbound wastes the whole defensive cycle on it and fills the player's threat
## board with rounds that were never coming. Reach is judged from where the round is now, which
## is generous — it ignores fuel already spent — and that is deliberate.
static func within_reach(u: Unit, w: Weapon) -> bool:
	return u.position.distance_to(w.position) <= w.spec.max_range_nm


## True when this round is closing on this ship rather than merely nearby.
static func is_inbound(u: Unit, w: Weapon) -> bool:
	if w.faction == u.faction or w.phase == Weapon.Phase.DEAD or w.is_interceptor():
		return false
	if w.acquired == u:
		return true
	if not within_reach(u, w):
		return false
	var cpa := closest_approach(u, w)
	return cpa["time_s"] > 0.0 and cpa["cpa_nm"] <= CPA_THREAT_NM


## Which friendly ship a detected round is actually going for, or null if it threatens nobody.
static func threatened_unit(unit_manager: UnitManager, faction: String, w: Weapon) -> Unit:
	if w.faction == faction or w.phase == Weapon.Phase.DEAD or w.is_interceptor():
		return null
	if w.acquired != null and w.acquired.alive and w.acquired.faction == faction:
		return w.acquired
	var best: Unit = null
	var best_cpa := CPA_THREAT_NM
	for u in unit_manager.units:
		if not u.alive or u.faction != faction or not u.is_engageable():
			continue
		if not within_reach(u, w):
			continue
		var cpa := closest_approach(u, w)
		if cpa["time_s"] > 0.0 and cpa["cpa_nm"] <= best_cpa:
			best = u
			best_cpa = cpa["cpa_nm"]
	return best


## Detected rounds threatening this faction, most urgent first.
static func inbound_threats(unit_manager: UnitManager, threat_manager: ThreatManager, faction: String, observer: Unit = null) -> Array:
	var out: Array = []
	for w in threat_manager.get_threats(faction):
		if observer != null and not threat_manager.visible_to(observer, w):
			continue
		var victim := threatened_unit(unit_manager, faction, w)
		if victim != null:
			out.append({"weapon": w, "target": victim, "time_s": w.time_to_reach_s(victim.position)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["time_s"] < b["time_s"])
	return out


## One defence cycle for every unit. Returns the number of interceptors launched.
##
## Ships defend the whole task force, not only themselves: any round closing on a consort is a
## valid target for a ship that can reach it. That is what makes an area-defence escort worth
## stationing near a thinner-skinned ship.
static func run_cycle(unit_manager: UnitManager, threat_manager: ThreatManager, weapon_manager: WeaponManager, now: float) -> int:
	var launched := 0
	var committed := _count_committed(weapon_manager)
	var channels := _channels_in_use(weapon_manager)
	var by_faction: Dictionary = {}
	for u in unit_manager.units:
		if not u.is_engageable() or u.roe == Unit.Roe.HOLD or not u.can_fire():
			continue
		if not by_faction.has(u.faction):
			by_faction[u.faction] = inbound_threats(unit_manager, threat_manager, u.faction)
		var inbound: Array = by_faction[u.faction]
		for entry: Dictionary in inbound:
			var w: Weapon = entry["weapon"]
			if w.phase == Weapon.Phase.DEAD or not threat_manager.visible_to(u, w):
				continue
			_try_decoy(u, w, weapon_manager)
			if w.phase == Weapon.Phase.DEAD or not threat_manager.visible_to(u, w):
				continue
			var already: int = committed.get(w.id, 0)
			var in_use: int = channels.get(u, 0)
			var engaging_already: bool = _ship_engages(weapon_manager, u, w)
			var guided_allowed := already < MAX_INTERCEPTORS_PER_THREAT \
				and w.guided_interceptors_committed < MAX_LIFETIME_INTERCEPTORS_PER_THREAT \
				and (engaging_already or in_use < u.spec.fire_control_channels)
			var fired := _engage_threat(u, w, weapon_manager, guided_allowed, now)
			if fired > 0:
				committed[w.id] = already + fired
				if not engaging_already:
					channels[u] = in_use + 1
				launched += fired
	return launched


static func _count_committed(weapon_manager: WeaponManager) -> Dictionary:
	var out: Dictionary = {}
	for w in weapon_manager.in_flight:
		if w.intercept_target != null:
			out[w.intercept_target.id] = int(out.get(w.intercept_target.id, 0)) + 1
	return out


## Distinct rounds each ship currently has interceptors in the air against. A ship cannot guide
## more simultaneous engagements than it has fire-control channels, which is what lets a large
## enough salvo get through a good escort.
static func _channels_in_use(weapon_manager: WeaponManager) -> Dictionary:
	return weapon_manager.channel_loads()



## Data decides what an interceptor can shoot at. Nothing currently lists "torpedo" as a target
## type, so a torpedo cannot be shot down and has to be defeated by decoys or by manoeuvre.
static func _can_intercept(spec: WeaponSpec, threat: Weapon) -> bool:
	return spec.target_types.has(threat.threat_class()) and threat.spec.altitude_m >= spec.intercept_min_altitude_m and threat.spec.altitude_m <= spec.intercept_max_altitude_m


static func _ship_engages(weapon_manager: WeaponManager, u: Unit, threat: Weapon) -> bool:
	for w in weapon_manager.in_flight:
		if w.shooter == u and w.intercept_target == threat:
			return true
	return false


## Close-in weapons are the last-ditch layer: self-contained, so they neither consume a guidance
## channel nor count against the missile allowance, and whatever leaks past always gets a final
## engagement. They get their own small burst allowance, because a round crosses that envelope in
## seconds rather than minutes.
static func _engage_threat(u: Unit, threat: Weapon, weapon_manager: WeaponManager, guided_allowed: bool, now: float) -> int:
	var d := u.position.distance_to(threat.position)
	for spec in u.defensive_weapons():
		if not _can_intercept(spec, threat):
			continue
		if d > spec.max_range_nm or d < spec.min_range_nm:
			continue
		var is_close_in := spec.type == "ciws"
		if is_close_in:
			if threat.close_in_bursts_committed >= MAX_CLOSE_IN_BURSTS_PER_THREAT:
				continue
		elif not guided_allowed:
			continue
		var allowance := spec.salvo_default if is_close_in else MAX_LIFETIME_INTERCEPTORS_PER_THREAT - threat.guided_interceptors_committed
		var rounds := mini(mini(spec.salvo_default, u.magazine_count(spec.id)), allowance)
		if rounds <= 0:
			continue
		var fired := weapon_manager.launch_interceptor(u, spec, threat, rounds, now)
		if fired > 0:
			return fired
	return 0


static func _try_decoy(u: Unit, threat: Weapon, weapon_manager: WeaponManager) -> void:
	if threat.decoy_attempted or u.decoys <= 0 or threat.acquired != u:
		return
	if u.position.distance_to(threat.position) > DECOY_RANGE_NM:
		return
	threat.decoy_attempted = true
	u.decoys -= 1
	var chance := clampf(u.spec.decoy_effectiveness / maxf(threat.spec.soft_kill_resistance, 0.1), 0.0, 0.95)
	if weapon_manager.rng.randf() < chance:
		weapon_manager.defeat_weapon(threat, "DECOYED", u)
