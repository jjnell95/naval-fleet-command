class_name AirDefence
## Automatic layered self-defence. Ships defend themselves without player orders: the player
## decides emissions, position and magazines, not individual interception shots.
##
## A ship on manual missile defence (`Unit.auto_air_defence` off, the Classic option) keeps its
## area SAMs for the rounds the commander orders intercepted (`order_intercept`, which marks them
## in `Weapon.intercept_cleared`); once cleared, a round is engaged by the same layers, limits and
## fire-control channels as automatic defence would use. An intercept order that names no round is
## a clearance for the raid: it stands for the rounds that arrive later too, until the sky has been
## quiet for RAID_QUIET_S or the ship is put on weapons hold. What stays automatic: the ship's
## self-defence weapons (`WeaponSpec.is_self_defence`: the close-in guns and the point-defence
## missiles), and chaff and flares, which follow `auto_countermeasures` as before. Torpedo defence
## is not affected: the option is about missiles.
##
## Weapons hold stops a ship attacking. It does not stop it defending: interceptors are fired only
## at weapons in flight, and a ship on hold fires them at rounds threatening the force as any other
## would. Hold does withdraw the commander's clearances under manual defence, so the missiles that
## wait for an order go back to waiting.
##
## The doctrine is to defend the ship, not an allowance. What is limited is the number of
## interceptors in the air at one round across the whole force, never the rounds ever fired at it:
## a round that survives is shot at again for as long as it flies. Where time allows the force
## shoots, looks and shoots again; a second round goes up at once only when the first would leave
## no time for another look. Each ship answers with the cheapest layer that can still reach the
## round with that time in hand, so the area missiles are kept for what the point layer cannot
## cover, and rounds built for ballistic targets are kept for them while one is held or the
## magazine is low. Close-in guns fire every time they have cycled while a round is in reach.

const CPA_THREAT_NM := 3.0  # a round passing wider than this is not treated as inbound
const MAX_INTERCEPTORS_PER_THREAT := 2  # in the air against one round at any moment, across the force
## Seconds a round must still have to run, after the interceptors going for it have met it, for the
## force to see the result and get another one out to it. GAMEPLAY_ESTIMATE.
const SECOND_LOOK_S := 10.0
## Rounds of a ballistic-capable missile a ship keeps back from cruise missiles while it has
## anything else that can take them. GAMEPLAY_ESTIMATE.
const BALLISTIC_RESERVE_ROUNDS := 8
## Seconds with no inbound round held after which a clearance to engage the raid lapses.
## GAMEPLAY_ESTIMATE.
const RAID_QUIET_S := 120.0


## Closest point of approach of `w` to `u`, as {cpa_nm, time_s}. Time is negative when the round
## has already passed.
static func closest_approach(u: Unit, w: Weapon) -> Dictionary:
	var rel_pos := w.position - u.position
	var wv := Geo.heading_to_vector(w.heading_deg) * w.speed_nm_per_s()
	var uv := Geo.heading_to_vector(u.heading_deg) * Geo.knots_to_nm_per_s(u.speed_kn)
	var rel_vel := wv - uv
	return _relative_approach(rel_pos, rel_vel)


static func _relative_approach(rel_pos: Vector2, rel_vel: Vector2) -> Dictionary:
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


## Which friendly ship a detected round is actually going for, or null if it threatens nobody.
## A round with no lock yet threatens a ship its course brings inside its own seeker's reach, not
## only one it is pointed at: a seeker opening a few miles abeam finds the hull all the same.
static func threatened_unit(unit_manager: UnitManager, faction: String, w: Weapon, candidates: Array = [], velocities: Dictionary = {}) -> Unit:
	if w.faction == faction or w.phase == Weapon.Phase.DEAD or w.is_interceptor():
		return null
	if w.acquired != null and w.acquired.alive and w.acquired.faction == faction:
		return w.acquired
	var best: Unit = null
	var best_cpa := maxf(CPA_THREAT_NM, w.spec.acquisition_radius_nm())
	var weapon_velocity := Geo.heading_to_vector(w.heading_deg) * w.speed_nm_per_s()
	for u: Unit in (unit_manager.units if candidates.is_empty() else candidates):
		if not u.alive or u.faction != faction or not u.is_engageable():
			continue
		if not WeaponManager.can_target(w.spec, u):
			continue
		if not within_reach(u, w):
			continue
		var cpa := closest_approach(u, w) if not velocities.has(u) else _relative_approach(w.position - u.position, weapon_velocity - velocities[u])
		if cpa["time_s"] > 0.0 and cpa["cpa_nm"] <= best_cpa:
			best = u
			best_cpa = cpa["cpa_nm"]
	return best


## Detected rounds threatening this faction, most urgent first.
static func inbound_threats(unit_manager: UnitManager, threat_manager: ThreatManager, faction: String, observer: Unit = null) -> Array:
	var out: Array = []
	var candidates: Array[Unit] = []
	var velocities := {}
	for u: Unit in unit_manager.units:
		if u.faction == faction and u.is_engageable():
			candidates.append(u)
			velocities[u] = Geo.heading_to_vector(u.heading_deg) * Geo.knots_to_nm_per_s(u.speed_kn)
	var exposed := {}
	for w in threat_manager.get_threats(faction):
		if observer != null and not threat_manager.visible_to(observer, w):
			continue
		var victim := threatened_unit(unit_manager, faction, w, candidates, velocities)
		if victim != null:
			out.append({"weapon": w, "target": victim, "time_s": w.time_to_reach_s(victim.position)})
			if not exposed.has(victim):
				exposed[victim] = victim.defensive_weapons().is_empty()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		# Imminent arrivals win first. Within one short arrival band a ship with nothing of its own
		# to shoot with comes before one that can look after itself, then the high-value units.
		var a_band := floori(float(a["time_s"]) / 15.0)
		var b_band := floori(float(b["time_s"]) / 15.0)
		if a_band != b_band:
			return a_band < b_band
		var a_target: Unit = a["target"]
		var b_target: Unit = b["target"]
		if exposed[a_target] != exposed[b_target]:
			return exposed[a_target]
		if a_target.defence_priority != b_target.defence_priority:
			return a_target.defence_priority > b_target.defence_priority
		return a["time_s"] < b["time_s"])
	return out


## One defence cycle for every unit. Returns the number of interceptors launched.
##
## Ships defend the whole task force, not only themselves: any round closing on a consort is a
## valid target for a ship that can reach it. That is what makes an area-defence escort worth
## stationing near a thinner-skinned ship.
##
## The force allocates as one: the raid is worked through twice. On the first pass every inbound
## round with nothing in the air at it gets one interceptor from the best-placed ship that can take
## it; only then, on the second, are rounds with no time left for a look given their second, and
## the close-in guns their turn. Working one round at a time let the two nearest ships both shoot
## the first round while the second was not answered at all until a launcher came free. Within a
## pass a ship with a guidance channel to spare is asked before a nearer one that is saturated, so
## a raid spreads across the screen instead of queuing on one hull.
static func run_cycle(unit_manager: UnitManager, threat_manager: ThreatManager, weapon_manager: WeaponManager, now: float) -> int:
	weapon_manager.begin_channel_batch()
	var missiles := {}  # unit -> its missile layers with rounds left, innermost first
	var guns := {}  # unit -> its close-in weapons with rounds left
	var reaches := {}
	var launched := 0
	var by_faction: Dictionary = {}
	for u in unit_manager.units:
		if not u.is_engageable():
			continue
		if u.raid_clearance_until_s >= 0.0 and (now > u.raid_clearance_until_s or u.roe == Unit.Roe.HOLD or u.auto_air_defence):
			u.raid_clearance_until_s = -1.0
		if not by_faction.has(u.faction):
			by_faction[u.faction] = []
		by_faction[u.faction].append(u)
		var layers: Array[WeaponSpec] = []
		var close_in: Array[WeaponSpec] = []
		var reach := 0.0
		for spec: WeaponSpec in u.defensive_weapons():
			reach = maxf(reach, spec.max_range_nm)
			if spec.type == "ciws":
				close_in.append(spec)
			else:
				layers.push_front(spec)
		missiles[u] = layers
		guns[u] = close_in
		reaches[u] = reach * reach
	var airborne := interceptors_airborne(weapon_manager)
	for faction: String in by_faction:
		var inbound := inbound_threats(unit_manager, threat_manager, faction)
		if inbound.is_empty():
			continue
		var ballistic_held := false
		for entry in inbound:
			if (entry["weapon"] as Weapon).threat_class() == "ballistic":
				ballistic_held = true
		_carry_raid_clearances(by_faction[faction], inbound, threat_manager, now)
		for pass_index in 2:
			var first_pass := pass_index == 0
			for entry in inbound:
				var w: Weapon = entry["weapon"]
				if w.phase == Weapon.Phase.DEAD:
					continue
				var defenders: Array = []
				for u: Unit in _rank_defenders(by_faction[faction], w, reaches, weapon_manager):
					if w.phase == Weapon.Phase.DEAD or not threat_manager.visible_to(u, w):
						continue
					# Chaff and flares were answered by DefensiveResponse earlier in the same step.
					if first_pass:
						if not u.radar_on and not (entry["target"] as Unit).is_aircraft():
							_light_radar_to_defend(u, w, unit_manager, weapon_manager, now)
					# Weapons hold is an order not to attack. A ship holding fire still defends itself
					# and its consorts against a round on its way in.
					if u.can_fire():
						defenders.append(u)
				# A missile chasing an aircraft is the aircraft's to beat with countermeasures and a
				# hard turn; a ship spending interceptors on it is shooting at the wrong thing.
				if w.phase == Weapon.Phase.DEAD or (entry["target"] as Unit).is_aircraft():
					continue
				var tti := float(entry["time_s"])
				var up: Dictionary = airborne.get(w.id, {})
				var count := int(up.get("count", 0))
				# On the first pass the rounds nobody has answered come before any top-up.
				if count == 0 or not first_pass:
					var shot := _missile_shot(defenders, w, tti, count, float(up.get("resolve_s", 0.0)), missiles, ballistic_held, weapon_manager, now)
					if not shot.is_empty() and weapon_manager.launch_interceptor(shot["unit"], shot["spec"], w, 1, now) > 0:
						airborne[w.id] = {"count": count + 1, "resolve_s": maxf(float(up.get("resolve_s", 0.0)), float(shot["meet_s"]))}
						launched += 1
				if not first_pass:
					for u: Unit in defenders:
						launched += _close_in_burst(u, w, guns[u], weapon_manager, now)
	weapon_manager.end_channel_batch()
	return launched


## A ship with its radar off that has the round inside a missile layer guided by that radar.
## Unless the commander ordered it radar silent, the crew lights the radar and fights, as any crew
## would with a missile on its way in; under the silent order it holds fire and says so once a raid.
static func _light_radar_to_defend(u: Unit, w: Weapon, unit_manager: UnitManager, weapon_manager: WeaponManager, now: float) -> void:
	if not u.has_radar() or u.submerged() or not u.can_fire() or float(u.components.get("sensors", 1.0)) <= 0.15:
		return
	var d := u.position.distance_to(w.position)
	var wanted := false
	for spec: WeaponSpec in u.defensive_weapons():
		if spec.requires_radar_support() and _can_intercept(spec, w) and engages_guided(u, w, spec) \
				and d >= spec.min_range_nm and d <= spec.max_range_nm:
			wanted = true
			break
	if not wanted:
		return
	if u.emcon == Unit.Emcon.SILENT:
		if u.silent_hold_reported_s < 0.0 or now - u.silent_hold_reported_s > RAID_QUIET_S:
			weapon_manager.self_defence_emcon.emit(u, false)
		u.silent_hold_reported_s = now
		return
	var order := Order.activate_radar()
	order.origin = "crew"
	if unit_manager.issue_order(u, order):
		weapon_manager.self_defence_emcon.emit(u, true)


## Defenders that can reach this round, best placed first: a ship already guiding against it or
## with a guidance channel free comes before a saturated one, then the nearest. Channel state is
## read from the cycle's cache, so this costs nothing extra per shot.
static func _rank_defenders(force: Array, w: Weapon, reaches: Dictionary, weapon_manager: WeaponManager) -> Array:
	var out: Array = []
	var free := {}
	for u: Unit in force:
		if u.position.distance_squared_to(w.position) <= float(reaches[u]):
			out.append(u)
			free[u] = weapon_manager.channel_available(u, w)
	out.sort_custom(func(a: Unit, b: Unit) -> bool:
		if free[a] != free[b]:
			return free[a]
		return a.position.distance_squared_to(w.position) < b.position.distance_squared_to(w.position))
	return out


## Which ships currently have interceptors in the air against this round, nearest first. For the
## threat board: the commander sees who has the round, not only how many are up.
static func engaging_units(weapon_manager: WeaponManager, threat: Weapon) -> Array[Unit]:
	var out: Array[Unit] = []
	for w in weapon_manager.in_flight:
		if w.phase != Weapon.Phase.DEAD and w.intercept_target == threat and w.shooter != null and not out.has(w.shooter):
			out.append(w.shooter)
	return out


## The rounds of each missile type a ship keeps back for missiles rather than spend on aircraft,
## and the speed above which a closing aircraft is given a pair at once rather than one round and a
## look. GAMEPLAY_ESTIMATE.
const SAM_RESERVE_FOR_MISSILES := 4
const FAST_AIRCRAFT_KN := 400.0


## Weapons free means the ship fights: a commander's ship on Weapons Free with automatic air
## defence engages identified hostile aircraft that come inside its missile envelope without
## waiting for an attack order. The side keeps one round in the air at a track and launches nothing
## more at it until that round has done its work (shoot, look, shoot); a fast aircraft closing on
## the ship is given two together, since it will be overhead before a look and a second shot. The
## AI's sides already do this through their own controllers, so only the sides named here are
## stepped. Weapons Tight, Hold, manual missile defence (Classic) and anything not identified
## hostile are left to the commander. Reads only the ship's own picture; every shot goes through
## the ordinary envelope checks.
static func engage_hostile_aircraft(unit_manager: UnitManager, track_manager: TrackManager, weapon_manager: WeaponManager, now: float, factions: Array) -> int:
	if factions.is_empty() or track_manager == null:
		return 0
	var fired := 0
	weapon_manager.begin_channel_batch()
	for u: Unit in unit_manager.units:
		if not factions.has(u.faction) or not u.is_engageable() or u.is_aircraft():
			continue
		if u.roe != Unit.Roe.FREE or not u.auto_air_defence or not u.can_fire():
			continue
		var sams := false
		for spec: WeaponSpec in u.weapons:
			if spec.type == "sam" and spec.target_types.has("air") and u.magazine_count(spec.id) > SAM_RESERVE_FOR_MISSILES:
				sams = true
				break
		if not sams:
			continue
		for t: Track in track_manager.tracks_for(u):
			if t.domain != "air" or t.identity != "HOSTILE" or t.status != Track.Status.ACTIVE or t.is_bearing_only() or t.confirmed_destroyed:
				continue
			# Rounds already flying or queued at the track, from any ship of the side.
			if weapon_manager.faction_commitment(u.faction, t) > 0:
				continue
			var salvo := aircraft_salvo(u, t)
			for spec: WeaponSpec in u.weapons_for_track(t):
				if spec.type != "sam" or u.magazine_count(spec.id) <= SAM_RESERVE_FOR_MISSILES:
					continue
				if own_aircraft_in_basket(unit_manager, u, spec, t):
					continue
				if not bool(weapon_manager.engagement_check(u, spec, t, now).get("ok", false)):
					continue
				var rounds := mini(salvo, u.magazine_count(spec.id) - SAM_RESERVE_FOR_MISSILES)
				if weapon_manager.launch(u, spec, t, rounds, now):
					fired += rounds
				break
	weapon_manager.end_channel_batch()
	return fired


## Rounds a ship sends together at a hostile aircraft: two at a fast one closing on it, else one.
static func aircraft_salvo(u: Unit, t: Track) -> int:
	if t.speed_kn < FAST_AIRCRAFT_KN:
		return 1
	var toward_ship := (u.position - t.position).normalized()
	return 2 if Geo.heading_to_vector(t.course_deg).dot(toward_ship) > 0.5 else 1


## An own aircraft close enough to the contact to be inside the round's seeker basket when it
## opens. A crew firing on its own initiative holds a shot into a merge it cannot sort out on the
## scope; the commander may still order it. The basket is drawn round the plot, widened by the
## plot's own error.
static func own_aircraft_in_basket(unit_manager: UnitManager, shooter: Unit, spec: WeaponSpec, t: Track) -> bool:
	var reach := spec.acquisition_radius_nm() + maxf(t.position_error_nm, 0.0)
	for u: Unit in unit_manager.units:
		if u != shooter and u.faction == shooter.faction and u.in_flight() and u.position.distance_to(t.position) <= reach:
			return true
	return false


## Whether this ship may fire this missile at this round now: always on automatic defence, and
## always a self-defence missile; an area missile on manual defence only once the commander has
## ordered the round intercepted, and not while the ship is on weapons hold.
static func engages_guided(u: Unit, w: Weapon, spec: WeaponSpec) -> bool:
	if u.auto_air_defence or spec.is_self_defence():
		return true
	return u.roe != Unit.Roe.HOLD and w.intercept_cleared.has(u.id)


## A ship cleared to engage the raid is cleared for every round of it its picture comes to hold,
## and the clearance stands while rounds keep coming. Weapons hold takes back the clearances a
## ship was given round by round as well, so lifting it does not release missiles on an old order.
static func _carry_raid_clearances(force: Array, inbound: Array, threat_manager: ThreatManager, now: float) -> void:
	for u: Unit in force:
		if u.roe == Unit.Roe.HOLD and not u.auto_air_defence:
			for entry: Dictionary in inbound:
				(entry["weapon"] as Weapon).intercept_cleared.erase(u.id)
		if u.raid_clearance_until_s < 0.0:
			continue
		u.raid_clearance_until_s = now + RAID_QUIET_S
		for entry: Dictionary in inbound:
			var w: Weapon = entry["weapon"]
			if not w.intercept_cleared.has(u.id) and threat_rejection(u, w, threat_manager) == "":
				w.intercept_cleared.append(u.id)


## Inbound rounds an area missile is waiting on the commander for: held by a ship on manual
## defence that has a missile it may not fire at them unordered, and cleared for none. For the
## interface, which prompts for the intercept order while there are any.
static func awaiting_clearance(unit_manager: UnitManager, threat_manager: ThreatManager, faction: String) -> Array[Weapon]:
	var out: Array[Weapon] = []
	var manual: Array[Unit] = []
	for u: Unit in unit_manager.units:
		if u.faction == faction and u.is_engageable() and not u.auto_air_defence and intercept_rejection(u) == "":
			manual.append(u)
	if manual.is_empty():
		return out
	for entry: Dictionary in inbound_threats(unit_manager, threat_manager, faction):
		var w: Weapon = entry["weapon"]
		if (entry["target"] as Unit).is_aircraft() or not w.intercept_cleared.is_empty():
			continue
		for u: Unit in manual:
			if _waits_for_orders(u, w) and threat_manager.visible_to(u, w):
				out.append(w)
				break
	return out


static func _waits_for_orders(u: Unit, w: Weapon) -> bool:
	for spec: WeaponSpec in u.defensive_weapons():
		if not spec.is_self_defence() and _can_intercept(spec, w):
			return true
	return false


## Why this unit cannot be ordered to intercept, or "": its own state, before any round is named.
static func intercept_rejection(u: Unit) -> String:
	if u == null or not u.is_engageable():
		return "Select a deployed platform"
	if u.roe == Unit.Roe.HOLD:
		return "Weapons hold"
	var aboard := false
	for spec: WeaponSpec in u.weapons:
		if spec.is_interceptor() and (spec.target_types.has("missile") or spec.target_types.has("ballistic")):
			aboard = true
	if not aboard:
		return "No anti-missile weapons aboard"
	var loaded := false
	for spec: WeaponSpec in u.defensive_weapons():
		if spec.target_types.has("missile") or spec.target_types.has("ballistic"):
			loaded = true
	if not loaded:
		return "Interceptor magazines empty"
	if not u.can_fire():
		return "Launchers damaged"
	return ""


## Why this unit cannot be ordered to intercept this round, or "". Only rounds the unit's own
## picture holds can be named, and only ones its interceptors are built for.
static func threat_rejection(u: Unit, w: Weapon, threat_manager: ThreatManager) -> String:
	if w == null or w.phase == Weapon.Phase.DEAD:
		return "That weapon is gone"
	if w.faction == u.faction or w.is_interceptor():
		return "Not an inbound weapon"
	if threat_manager == null or not threat_manager.visible_to(u, w):
		return "That weapon is not held on this unit's picture"
	for spec: WeaponSpec in u.defensive_weapons():
		if _can_intercept(spec, w):
			return ""
	return "No interceptor aboard can engage a %s" % ("torpedo" if w.spec.is_torpedo() else w.threat_class() + " at that height")


## The commander's intercept order for one unit: clears it to engage `threat`, or with none named
## every inbound round its picture holds against the force and those of the same raid that come
## after (`Unit.raid_clearance_until_s`), and takes the first shot now when a layer has the round
## in reach and a channel free. Later shots come from the defence cycle, with the usual layering
## and limits. Returns {cleared, fired, reason}: how many rounds were cleared, how many
## interceptors left now, and why nothing was cleared.
static func order_intercept(u: Unit, threat: Weapon, unit_manager: UnitManager, threat_manager: ThreatManager, weapon_manager: WeaponManager, now: float) -> Dictionary:
	var why := intercept_rejection(u)
	if why != "":
		return {"cleared": 0, "fired": 0, "reason": why}
	var targets: Array[Weapon] = []
	if threat != null:
		why = threat_rejection(u, threat, threat_manager)
		if why != "":
			return {"cleared": 0, "fired": 0, "reason": why}
		targets.append(threat)
	else:
		for entry: Dictionary in inbound_threats(unit_manager, threat_manager, u.faction, u):
			var w: Weapon = entry["weapon"]
			if threat_rejection(u, w, threat_manager) == "":
				targets.append(w)
		if targets.is_empty():
			return {"cleared": 0, "fired": 0, "reason": "No inbound weapon this unit can engage is held"}
		if not u.auto_air_defence:
			u.raid_clearance_until_s = now + RAID_QUIET_S
	var fired := 0
	var airborne := interceptors_airborne(weapon_manager)
	var victims := {}
	var ballistic_held := false
	for entry: Dictionary in inbound_threats(unit_manager, threat_manager, u.faction, u):
		victims[entry["weapon"]] = float(entry["time_s"])
		if (entry["weapon"] as Weapon).threat_class() == "ballistic":
			ballistic_held = true
	var layers: Array[WeaponSpec] = []
	var guns: Array[WeaponSpec] = []
	for spec: WeaponSpec in u.defensive_weapons():
		if spec.type == "ciws":
			guns.append(spec)
		else:
			layers.push_front(spec)
	for w: Weapon in targets:
		if not w.intercept_cleared.has(u.id):
			w.intercept_cleared.append(u.id)
		var tti := float(victims.get(w, w.time_to_reach_s(u.position)))
		var up: Dictionary = airborne.get(w.id, {})
		var shot := _missile_shot([u], w, tti, int(up.get("count", 0)), float(up.get("resolve_s", 0.0)), {u: layers}, ballistic_held, weapon_manager, now)
		if not shot.is_empty():
			fired += weapon_manager.launch_interceptor(u, shot["spec"], w, 1, now)
		fired += _close_in_burst(u, w, guns, weapon_manager, now)
	return {"cleared": targets.size(), "fired": fired, "reason": ""}


## The most interceptors a ship's policy lets the force keep in the air at one round. Within it
## the cycle shoots, looks and shoots again while there is time to look.
static func guided_budget(u: Unit, tti_s: float) -> int:
	if u.defence_policy == "saturation":
		return 3
	if u.defence_policy == "conserve" and tti_s > 45.0:
		return 1
	return MAX_INTERCEPTORS_PER_THREAT


## Missiles in the air at each inbound round, keyed by the round's id.
static func _count_committed(weapon_manager: WeaponManager) -> Dictionary:
	var out: Dictionary = {}
	for w in weapon_manager.in_flight:
		if w.phase != Weapon.Phase.DEAD and w.intercept_target != null and w.spec.type == "sam":
			out[w.intercept_target.id] = int(out.get(w.intercept_target.id, 0)) + 1
	return out


## The same with the time the last of them needs to reach its round: id -> {count, resolve_s}.
static func interceptors_airborne(weapon_manager: WeaponManager) -> Dictionary:
	var out: Dictionary = {}
	for w in weapon_manager.in_flight:
		if w.phase == Weapon.Phase.DEAD or w.intercept_target == null or w.spec.type != "sam":
			continue
		var threat := w.intercept_target
		var entry: Dictionary = out.get(threat.id, {"count": 0, "resolve_s": 0.0})
		entry["count"] = int(entry["count"]) + 1
		entry["resolve_s"] = maxf(float(entry["resolve_s"]), meet_time_s(w.position, w.spec, threat))
		out[threat.id] = entry
	return out


## Seconds an interceptor of this type needs from `from` to meet the round on its present course.
## INF when it cannot catch it.
static func meet_time_s(from: Vector2, spec: WeaponSpec, threat: Weapon) -> float:
	var speed := Geo.knots_to_nm_per_s(spec.speed_kn)
	if speed <= 0.0:
		return INF
	var point := Combat.intercept_point(from, spec.speed_kn, threat.position, threat.heading_deg, threat.spec.speed_kn, true)
	return from.distance_to(point) / speed if point.is_finite() else INF


## Seconds until the round, held on its present course, comes within `range_nm` of `from`. Zero
## when it is inside already, INF when its course never brings it that close.
static func _time_to_enter_s(from: Vector2, range_nm: float, threat: Weapon) -> float:
	var offset := threat.position - from
	var c := offset.length_squared() - range_nm * range_nm
	if c <= 0.0:
		return 0.0
	var velocity := Geo.heading_to_vector(threat.heading_deg) * threat.speed_nm_per_s()
	var a := velocity.length_squared()
	var b := offset.dot(velocity)
	if a <= 1e-12 or b >= 0.0:
		return INF
	var disc := b * b - a * c
	return (-b - sqrt(disc)) / a if disc >= 0.0 else INF


## Distinct rounds each ship currently has interceptors in the air against. Kept for the
## defence board, which reads it; WeaponManager.channel_loads is the one source.
static func _channels_in_use(weapon_manager: WeaponManager) -> Dictionary:
	return weapon_manager.channel_loads()


## Data decides what an interceptor can shoot at. The air-defence layers list "missile" and
## "ballistic"; the one weapon that lists "torpedo" (Paket-NK) is fired by TorpedoDefence, not here.
static func _can_intercept(spec: WeaponSpec, threat: Weapon) -> bool:
	return spec.target_types.has(threat.threat_class()) and threat.flight_altitude_m() >= spec.intercept_min_altitude_m and threat.flight_altitude_m() <= spec.intercept_max_altitude_m


## The force's next missile at one round, as {unit, spec, meet_s}, or {} when none should go now.
## `up` interceptors are in the air at it and the last of them meets it in `resolve_s`. With time
## to see how those do, nothing more is sent (a saturation policy keeps a pair up regardless);
## without it the round gets its second at once. Among the ships that could shoot, one that leaves
## time for another look comes first, then a point-defence layer before an area one, then the
## best placed. An area missile waits while some ship's point layer will have the round in reach
## with time to shoot twice.
static func _missile_shot(defenders: Array, w: Weapon, tti: float, up: int, resolve_s: float, missiles: Dictionary, ballistic_held: bool, weapon_manager: WeaponManager, now: float) -> Dictionary:
	var look_pending := up > 0 and tti - resolve_s >= SECOND_LOOK_S
	var best := {}
	var best_score := -1
	var point_layer_coming := false
	for u: Unit in defenders:
		var cap := guided_budget(u, tti)
		if up >= (maxi(cap - 1, 1) if look_pending else cap):
			continue
		var plan := _ship_plan(u, w, tti, missiles[u], ballistic_held, weapon_manager, now)
		if plan.is_empty():
			continue
		if not bool(plan["now"]):
			point_layer_coming = true
			continue
		var score := (2 if bool(plan["look"]) else 0) + (0 if bool(plan["area"]) else 1)
		if score > best_score:
			best = plan
			best["unit"] = u
			best_score = score
	if best.is_empty() or (bool(best["area"]) and point_layer_coming):
		return {}
	return best


## What one ship would do about one round: {spec, now, look, area, meet_s}, or {} for nothing.
## Its layers are tried innermost first, so the cheapest missile that leaves time for another look
## takes the shot; `now` false says a point-defence layer will have the round in reach, with that
## time in hand, later on, which is what an area missile waits for. With no time for a look left
## the ship fires the cheapest thing that bears.
static func _ship_plan(u: Unit, w: Weapon, tti: float, layers: Array, ballistic_held: bool, weapon_manager: WeaponManager, now: float) -> Dictionary:
	var d := u.position.distance_to(w.position)
	var shot := {}
	var last_chance := {}
	var point_later := {}
	for spec: WeaponSpec in layers:
		if not _can_intercept(spec, w) or not engages_guided(u, w, spec):
			continue
		if d < spec.min_range_nm or _kept_for_ballistic(u, spec, w, layers, ballistic_held):
			continue
		var area := spec.defensive_layer() == "area"
		if d > spec.max_range_nm:
			if area or not point_later.is_empty() or not WeaponManager.radar_support_available(u, spec):
				continue
			# Only a round coming well inside the envelope: one that clips its edge on the way to
			# a consort gives the layer no shot worth waiting for.
			if float(closest_approach(u, w)["cpa_nm"]) > spec.max_range_nm * 0.5:
				continue
			var enters := _time_to_enter_s(u.position, spec.max_range_nm, w)
			var flight := spec.max_range_nm / maxf(Geo.knots_to_nm_per_s(spec.speed_kn) + w.speed_nm_per_s(), 1e-6)
			if tti - enters - flight >= SECOND_LOOK_S:
				point_later = {"spec": spec, "now": false, "look": true, "area": false, "meet_s": 0.0}
			continue
		var wait_s := weapon_manager.interceptor_wait_s(u, spec, w, now)
		var meet_s := meet_time_s(u.position, spec, w)
		# A round going away is met, if at all, beyond the missile's own legs.
		if is_inf(wait_s) or meet_s * Geo.knots_to_nm_per_s(spec.speed_kn) > spec.max_range_nm:
			continue
		var look := tti - wait_s - meet_s >= SECOND_LOOK_S
		if wait_s > 0.0:
			# The launcher is cycling: the layer has the round, a moment from now.
			if look and not area and point_later.is_empty():
				point_later = {"spec": spec, "now": false, "look": true, "area": false, "meet_s": 0.0}
			continue
		var plan := {"spec": spec, "now": true, "look": look, "area": area, "meet_s": meet_s}
		if look:
			shot = plan
			break
		if last_chance.is_empty():
			last_chance = plan
	if not shot.is_empty():
		return point_later if bool(shot["area"]) and not point_later.is_empty() else shot
	if not last_chance.is_empty() and not bool(last_chance["area"]):
		return last_chance
	return point_later if not point_later.is_empty() else last_chance


## A missile that can take a ballistic round is not spent on a cruise missile while the force
## holds a ballistic round or the magazine is down to its reserve, unless it is all the ship has
## that can engage the round at all: then the ship defends itself with what is aboard.
static func _kept_for_ballistic(u: Unit, spec: WeaponSpec, w: Weapon, layers: Array, ballistic_held: bool) -> bool:
	if w.threat_class() == "ballistic" or not spec.target_types.has("ballistic"):
		return false
	if not ballistic_held and u.magazine_count(spec.id) > BALLISTIC_RESERVE_ROUNDS:
		return false
	for other: WeaponSpec in layers:
		if other != spec and not other.target_types.has("ballistic") and _can_intercept(other, w):
			return true
	return false


## Close-in weapons are the last-ditch layer: self-contained, so they neither take a guidance
## channel nor count against the missiles in the air, and a mount fires every time it has cycled
## while the round is inside its envelope.
static func _close_in_burst(u: Unit, threat: Weapon, guns: Array, weapon_manager: WeaponManager, now: float) -> int:
	var d := u.position.distance_to(threat.position)
	var fired := 0
	for spec: WeaponSpec in guns:
		if threat.phase == Weapon.Phase.DEAD:
			break
		if d > spec.max_range_nm or d < spec.min_range_nm or not _can_intercept(spec, threat):
			continue
		fired += weapon_manager.launch_interceptor(u, spec, threat, mini(spec.salvo_default, u.magazine_count(spec.id)), now)
	return fired

