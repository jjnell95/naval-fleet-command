class_name AirDefence
## Automatic layered self-defence. Ships defend themselves without player orders: the player
## decides emissions, position and magazines, not individual interception shots.
##
## A ship on manual missile defence (`Unit.auto_air_defence` off, the Classic option) keeps its
## area and point SAMs for the rounds the commander orders intercepted (`order_intercept`, which
## marks them in `Weapon.intercept_cleared`); once cleared, a round is engaged by the same layers,
## budgets and fire-control channels as automatic defence would use. What stays automatic: the
## close-in guns, the last-ditch layer a crew fires at whatever leaks through (weapons hold still
## silences them), and chaff and flares, which follow `auto_countermeasures` as before. Torpedo
## defence is not affected: the option is about missiles.
##
## Layering falls out of the data. `Unit.defensive_weapons()` returns interceptors longest-reach
## first, so the outermost layer that can shoot takes the shot, and shorter-ranged layers get
## their chance only as the round closes.

const CPA_THREAT_NM := 3.0  # a round passing wider than this is not treated as inbound
const MAX_INTERCEPTORS_PER_THREAT := 2  # in the air against one round at any moment
const MAX_CLOSE_IN_BURSTS_PER_THREAT := 2  # a round crosses the close-in envelope in seconds
const DECOY_RANGE_NM := 2.5


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


## True when this round is closing on this ship rather than merely nearby.
static func is_inbound(u: Unit, w: Weapon) -> bool:
	if w.faction == u.faction or w.phase == Weapon.Phase.DEAD or w.is_interceptor():
		return false
	if w.acquired == u:
		return true
	if not WeaponManager.can_target(w.spec, u):
		return false
	if not within_reach(u, w):
		return false
	var cpa := closest_approach(u, w)
	return cpa["time_s"] > 0.0 and cpa["cpa_nm"] <= CPA_THREAT_NM


## Which friendly ship a detected round is actually going for, or null if it threatens nobody.
static func threatened_unit(unit_manager: UnitManager, faction: String, w: Weapon, candidates: Array = [], velocities: Dictionary = {}) -> Unit:
	if w.faction == faction or w.phase == Weapon.Phase.DEAD or w.is_interceptor():
		return null
	if w.acquired != null and w.acquired.alive and w.acquired.faction == faction:
		return w.acquired
	var best: Unit = null
	var best_cpa := CPA_THREAT_NM
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
	for w in threat_manager.get_threats(faction):
		if observer != null and not threat_manager.visible_to(observer, w):
			continue
		var victim := threatened_unit(unit_manager, faction, w, candidates, velocities)
		if victim != null:
			out.append({"weapon": w, "target": victim, "time_s": w.time_to_reach_s(victim.position)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		# Imminent arrivals win first. Within one short arrival band, protect high-value units.
		var a_band := floori(float(a["time_s"]) / 15.0)
		var b_band := floori(float(b["time_s"]) / 15.0)
		if a_band != b_band:
			return a_band < b_band
		var a_target: Unit = a["target"]
		var b_target: Unit = b["target"]
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
## round gets one interceptor from the best-placed ship that can take it; only then, on the second,
## are budgets topped up and the close-in guns given their turn. Working one round at a time let
## the two nearest ships both shoot the first round while the second was not answered at all until
## a launcher came free. Within a pass a ship with a guidance channel to spare is asked before a
## nearer one that is saturated, so a raid spreads across the screen instead of queuing on one hull.
static func run_cycle(unit_manager: UnitManager, threat_manager: ThreatManager, weapon_manager: WeaponManager, now: float) -> int:
	weapon_manager.begin_channel_batch()
	var fits := {}
	var reaches := {}
	var launched := 0
	var committed := _count_committed(weapon_manager)
	var by_faction: Dictionary = {}
	for u in unit_manager.units:
		if not u.is_engageable():
			continue
		if not by_faction.has(u.faction):
			by_faction[u.faction] = []
		by_faction[u.faction].append(u)
		fits[u] = u.defensive_weapons()
		var reach := DECOY_RANGE_NM
		for spec: WeaponSpec in fits[u]:
			reach = maxf(reach, spec.max_range_nm)
		reaches[u] = reach * reach
	for faction: String in by_faction:
		var inbound := inbound_threats(unit_manager, threat_manager, faction)
		if inbound.is_empty():
			continue
		for pass_index in 2:
			var first_pass := pass_index == 0
			for entry in inbound:
				var w: Weapon = entry["weapon"]
				if w.phase == Weapon.Phase.DEAD:
					continue
				var tti := float(entry["time_s"])
				var shot_this_pass := false
				for u: Unit in _rank_defenders(by_faction[faction], w, reaches, weapon_manager):
					if w.phase == Weapon.Phase.DEAD or not threat_manager.visible_to(u, w):
						continue
					if first_pass:
						_try_decoy(u, w, weapon_manager)
					# A missile chasing an aircraft is the aircraft's to beat with countermeasures and a
					# hard turn; a ship spending interceptors on it is shooting at the wrong thing.
					if (entry["target"] as Unit).is_aircraft():
						continue
					if w.phase == Weapon.Phase.DEAD or u.roe == Unit.Roe.HOLD or not u.can_fire():
						continue
					var already: int = committed.get(w.id, 0)
					var limit := guided_budget(u, tti)
					if first_pass:
						limit = mini(limit, 1)
					var guided_allowed := not shot_this_pass and already < limit and engages_guided(u, w)
					if not guided_allowed and first_pass:
						continue  # the guns wait for the second pass; nothing else to offer here
					var before := w.guided_interceptors_committed
					var fired := _engage_threat(u, w, weapon_manager, guided_allowed, now, fits[u], tti, not first_pass)
					if fired > 0:
						# Increment the shared assignment, rather than rescanning every weapon twice
						# after every shot. Each launcher still validates its own guidance support.
						var guided := w.guided_interceptors_committed - before
						committed[w.id] = int(committed.get(w.id, 0)) + guided
						if guided > 0:
							shot_this_pass = true
						launched += fired
	weapon_manager.end_channel_batch()
	return launched


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


## The key a layer's lifetime allowance is kept under: per layer and per ship. Each ship's inner
## layer keeps its own shots at a round, so an escort's point-defence missiles fired at a round
## aimed at the carrier cannot use up the carrier's own last-ditch missiles.
static func layer_key(spec: WeaponSpec, shooter: Unit) -> String:
	return "%s:%d" % [spec.defensive_layer(), shooter.id if shooter != null else -1]


## Rounds a side keeps in the air at one hostile aircraft before another ship adds more, and the
## rounds of each missile type a ship keeps back for missiles rather than spend on aircraft.
## GAMEPLAY_ESTIMATE.
const AIRCRAFT_ROUNDS_IN_FLIGHT := 2
const SAM_RESERVE_FOR_MISSILES := 4


## Weapons free means the ship fights: a commander's ship on Weapons Free with automatic air
## defence engages identified hostile aircraft that come inside its missile envelope, one round at
## a time (shoot, look, shoot), without waiting for an attack order. The AI's sides already do this
## through their own controllers, so only the sides named here are stepped. Weapons Tight, Hold,
## manual missile defence (Classic) and anything not identified hostile are left to the commander.
## Reads only the ship's own picture; every shot goes through the ordinary envelope checks.
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
			if t.domain != "air" or t.identity != "HOSTILE" or t.status != Track.Status.ACTIVE or t.is_bearing_only() or t.damage_estimate >= 100.0:
				continue
			if weapon_manager.faction_commitment(u.faction, t) >= AIRCRAFT_ROUNDS_IN_FLIGHT:
				continue
			for spec: WeaponSpec in u.weapons_for_track(t):
				if spec.type != "sam" or u.magazine_count(spec.id) <= SAM_RESERVE_FOR_MISSILES:
					continue
				if not bool(weapon_manager.engagement_check(u, spec, t, now).get("ok", false)):
					continue
				if weapon_manager.launch(u, spec, t, 1, now):
					fired += 1
				break
	weapon_manager.end_channel_batch()
	return fired


## Whether this ship's area and point SAMs may engage this round now: always on automatic
## defence; on manual only once the commander has ordered it intercepted.
static func engages_guided(u: Unit, w: Weapon) -> bool:
	return u.auto_air_defence or w.intercept_cleared.has(u.id)


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
## every inbound round its picture holds against the force, and takes the first shot now when a
## layer has the round in reach and a channel free. Later shots come from the defence cycle, with
## the usual layering and budgets. Returns {cleared, fired, reason}: how many rounds were cleared,
## how many interceptors left now, and why nothing was cleared.
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
	var fired := 0
	var committed := _count_committed(weapon_manager)
	var victims := {}
	for entry: Dictionary in inbound_threats(unit_manager, threat_manager, u.faction, u):
		victims[entry["weapon"]] = float(entry["time_s"])
	for w: Weapon in targets:
		if not w.intercept_cleared.has(u.id):
			w.intercept_cleared.append(u.id)
		var tti := float(victims.get(w, w.time_to_reach_s(u.position)))
		var guided_allowed := int(committed.get(w.id, 0)) < guided_budget(u, tti)
		var before := w.guided_interceptors_committed
		var shot := _engage_threat(u, w, weapon_manager, guided_allowed, now, [], tti)
		if shot > 0:
			committed[w.id] = int(committed.get(w.id, 0)) + w.guided_interceptors_committed - before
			fired += shot
	return {"cleared": targets.size(), "fired": fired, "reason": ""}


static func guided_budget(u: Unit, tti_s: float) -> int:
	if u.defence_policy == "saturation":
		return 3
	if u.defence_policy == "conserve" and tti_s > 45.0:
		return 1
	return MAX_INTERCEPTORS_PER_THREAT


static func _count_committed(weapon_manager: WeaponManager) -> Dictionary:
	var out: Dictionary = {}
	for w in weapon_manager.in_flight:
		if w.phase != Weapon.Phase.DEAD and w.intercept_target != null and w.spec.type == "sam":
			out[w.intercept_target.id] = int(out.get(w.intercept_target.id, 0)) + 1
	return out


## Distinct rounds each ship currently has interceptors in the air against. A ship cannot guide
## more simultaneous engagements than it has fire-control channels, which is what lets a large
## enough salvo get through a good escort.
static func _channels_in_use(weapon_manager: WeaponManager) -> Dictionary:
	return weapon_manager.channel_loads()



## Data decides what an interceptor can shoot at. The air-defence layers list "missile" and
## "ballistic"; the one weapon that lists "torpedo" (Paket-NK) is fired by TorpedoDefence, not here.
static func _can_intercept(spec: WeaponSpec, threat: Weapon) -> bool:
	return spec.target_types.has(threat.threat_class()) and threat.flight_altitude_m() >= spec.intercept_min_altitude_m and threat.flight_altitude_m() <= spec.intercept_max_altitude_m


## Close-in weapons are the last-ditch layer: self-contained, so they neither consume a guidance
## channel nor count against the missile allowance, and whatever leaks past always gets a final
## engagement. They get their own small burst allowance, because a round crosses that envelope in
## seconds rather than minutes.
static func _engage_threat(u: Unit, threat: Weapon, weapon_manager: WeaponManager, guided_allowed: bool, now: float, fit: Array = [], tti_s := -1.0, close_in_allowed := true) -> int:
	var d := u.position.distance_to(threat.position)
	# One time-to-impact for the whole decision: the round's time to the ship it is going for,
	# as the cycle ranked it. Budgeting on the time to this defender instead let the conserve
	# policy pass one check and fail the other for the same shot.
	var tti := tti_s if tti_s >= 0.0 else threat.time_to_reach_s(u.position)
	var budget := guided_budget(u, tti)
	for spec: WeaponSpec in (u.defensive_weapons() if fit.is_empty() else fit):
		if not _can_intercept(spec, threat):
			continue
		if d > spec.max_range_nm or d < spec.min_range_nm:
			continue
		var is_close_in := spec.type == "ciws"
		var spent := int(threat.defence_commitments.get(layer_key(spec, u), 0))
		if is_close_in:
			if not close_in_allowed or int(threat.close_in_commitments.get(u.id, 0)) >= MAX_CLOSE_IN_BURSTS_PER_THREAT:
				continue
		elif not guided_allowed or spent >= budget:
			continue
		var allowance := spec.salvo_default if is_close_in else budget - spent
		var rounds := mini(mini(spec.salvo_default, u.magazine_count(spec.id)), allowance)
		if rounds <= 0:
			continue
		var fired := weapon_manager.launch_interceptor(u, spec, threat, rounds, now)
		if fired > 0:
			return fired
	return 0


## Chaff and flares against a missile's seeker. A torpedo's is acoustic, and chaff does nothing to
## it: TorpedoDefence answers torpedoes with noise.
static func _try_decoy(u: Unit, threat: Weapon, weapon_manager: WeaponManager) -> void:
	if threat.acquired != u or threat.spec.is_torpedo():
		return
	if u.position.distance_to(threat.position) > DECOY_RANGE_NM:
		return
	if u.auto_countermeasures and not threat.decoy_attempted:
		DefensiveResponse.deploy(u, threat.spec.seeker_band(), weapon_manager)
	DefensiveResponse.try_active(u, threat, weapon_manager)
