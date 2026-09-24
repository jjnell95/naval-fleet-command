class_name AIController
extends Node
## Opposing-force commander for one faction.
##
## The AI is bound by exactly the same information limits as the player. It reads its own units,
## its own faction's TrackManager picture and its own ThreatManager picture. It never touches
## enemy Unit objects and never reads Track.truth, so it can be surprised, can be decoyed by a
## stale track, and can shoot at water. Everything it does leaves through
## UnitManager.issue_order(), the same path the player's UI uses.

enum State { PATROL, SEARCH, INVESTIGATE, SHADOW, ENGAGE, DEFEND, WITHDRAW }

const STATE_NAMES := ["PATROL", "SEARCH", "INVESTIGATE", "SHADOW", "ENGAGE", "DEFEND", "WITHDRAW"]

const WITHDRAW_HEALTH_FRACTION := 0.35
const ENGAGE_COOLDOWN_S := 200.0  # wait and assess before re-attacking the same track
const MAX_ROUNDS_IN_FLIGHT_PER_TRACK := 8  # lets a group mass a saturating salvo on one target
const ORDER_REFRESH_S := 30.0
const GOAL_TOLERANCE_NM := 3.0
const COURSE_TOLERANCE_DEG := 8.0
const SPEED_TOLERANCE_KN := 1.5
const CLASSIFY_STANDOFF_FRACTION := 0.55  # close inside radar range to speed up classification
const ENGAGE_STANDOFF_FRACTION := 0.80  # sit inside the weapon envelope, not on its edge
const CONTACT_MEMORY_S := 1200.0
const ASM_SALVO := 4
const TORPEDO_SALVO := 2
## A weapon that takes too long to arrive is shooting at where the target used to be. This one
## rule keeps the AI from firing a 50 knot torpedo across twenty miles of ocean without needing a
## special case for torpedoes.
const MAX_TIME_OF_FLIGHT_S := 480.0
const MIN_SOLUTION_FOR_SLOW_WEAPON := 0.5  # a bearing with no range is not a firing solution
const DIP_STANDOFF_NM := 1.2  # a dipping helicopter wants to be overhead, not at arm's length
const BUOY_DROP_RANGE_NM := 9.0
const BUOY_INTERVAL_S := 150.0
const BUOY_SPACING_NM := 4.0
const HOVER_ALTITUDE_M := 50.0
const MISSILE_LAUNCH_DEPTH_M := 45.0  # GAMEPLAY_ESTIMATE: a submerged missile shot is a shallow one
## Time between launch decisions on one deck, divided by how many spots that deck works. A
## frigate gets an airframe off every four minutes; a carrier with four catapults gets a section
## off every minute, which is the difference a big deck is supposed to make.
const LAUNCH_INTERVAL_S := 240.0
const PACKAGE_MAX := 4  # largest section the AI will commit to one target at once
const SEARCH_RADIUS_NM := 11.0  # around a datum: the thing is near there
const WIDE_SEARCH_MAX_NM := 260.0  # the most a surveillance aircraft will range on a blank plot
const SEARCH_STEP_DEG := 55.0
const DIP_DURATION_S := 180.0
const PATROL_ARRIVAL_NM := 4.0
## A ship at 30 kn turning at 3 deg/s eats a quarter of a mile getting ninety degrees round, so an
## avoidance bearing has to look further ahead than that or it orders a turn that cannot be made.
const COAST_LOOKAHEAD_S := 120.0  # GAMEPLAY_ESTIMATE
const STANDOFF_ARC_DEG: Array[float] = [0.0, 25.0, 50.0, 75.0, 100.0, 130.0, 160.0]

var faction := ""
var unit_manager: UnitManager
var track_manager: TrackManager
var threat_manager: ThreatManager
var weapon_manager: WeaponManager
var enabled := true

var _bb: Dictionary = {}  # Unit -> blackboard Dictionary


func state_name(u: Unit) -> String:
	if not _bb.has(u):
		return ""
	return STATE_NAMES[_bb[u]["state"]]


func describe(u: Unit) -> String:
	if not _bb.has(u):
		return ""
	var b: Dictionary = _bb[u]
	var target: Track = b["target"]
	return "%s%s" % [STATE_NAMES[b["state"]], "  -> %s" % target.id if target != null else ""]


func tick(now: float) -> void:
	if not enabled or unit_manager == null:
		return
	for u in unit_manager.get_faction_units(faction):
		_update_unit(u, now)


func clear() -> void:
	_bb.clear()


# --- Per-unit decision cycle -------------------------------------------------------------

func _board(u: Unit) -> Dictionary:
	if not _bb.has(u):
		_bb[u] = {
			"state": State.PATROL,
			"since": 0.0,
			"target": null,
			"goal": Vector2.INF,
			"goal_time": -1000.0,
			"course": -1.0,
			"speed": -1.0,
			"cmd_time": -1000.0,
			"engaged": {},  # track id -> time of last salvo
			"last_contact": Vector2.INF,
			"last_contact_time": -1.0e9,
			"patrol_index": 0,
		}
	return _bb[u]


func _update_unit(u: Unit, now: float) -> void:
	if u.is_aircraft() and not u.airborne():
		return  # in the hangar or on the deck cycle; the aviation layer owns it
	if u.is_aircraft() and u.returning:
		return  # heading home on its own; leave it alone
	var b := _board(u)
	var hostiles_scan: Array = []
	var hostiles: Array = hostiles_scan
	var unknowns: Array = []
	# The faction's whole picture drives launch decisions: a shore station carries no weapons of
	# its own, so filtering by what it could shoot would leave it with nothing to react to.
	var all_hostiles: Array = []
	var all_unknowns: Array = []
	for t: Track in track_manager.tracks_for(u):
		if t.status == Track.Status.LOST:
			continue
		var mine := u.can_engage_domain(t.domain)
		if t.identity == "HOSTILE":
			all_hostiles.append(t)
			if mine:
				hostiles.append(t)
				b["last_contact"] = t.position
				b["last_contact_time"] = now
		elif t.identity == "UNKNOWN" and t.status == Track.Status.ACTIVE:
			all_unknowns.append(t)  # a contact identified as neutral is left alone
			if mine:
				unknowns.append(t)

	_note_torpedo_datum(u, b, now)
	_consider_launch(u, b, all_hostiles, all_unknowns, now)
	if u.spec.max_speed_kn <= 0.0:
		return  # a shore station has nothing to do but send aircraft up
	var inbound := _inbound_on(u)
	var new_state := _choose_state(u, b, hostiles, unknowns, inbound, now)
	if new_state != b["state"]:
		b["state"] = new_state
		b["since"] = now
	_act(u, b, hostiles, unknowns, inbound, now)


## What a deck puts up, and when. Four separate reasons, in the order a duty officer would work
## through them, because they are genuinely different decisions:
##   * an airframe with a standing route flies it;
##   * early warning and surveillance go up before anything is wrong, which is the point of them;
##   * a tanker follows receivers into the air, because give is useless on the deck;
##   * armed airframes go when there is something to prosecute, as a section rather than singly.
func _consider_launch(u: Unit, b: Dictionary, hostiles: Array, unknowns: Array, now: float) -> void:
	if u.spec.aircraft_capacity <= 0:
		return
	var ready := u.stowed_aircraft()
	if ready.is_empty():
		return
	var spots := maxi(u.spec.launch_capacity(), 1)
	if now - float(b.get("last_launch", -10000.0)) < LAUNCH_INTERVAL_S / float(spots):
		return

	for a: Unit in ready:
		if a.patrol_route.is_empty():
			continue
		# A raid or a barrier is flown by a formation. Send as many of that type as the deck can
		# work at once, rather than trickling them out one at a time down the same route.
		var same := 0
		for other: Unit in ready:
			if other.spec.id == a.spec.id and not other.patrol_route.is_empty():
				same += 1
		_send(u, b, a.callsign, mini(mini(same, spots), PACKAGE_MAX), now)
		return

	# Eyes first. An early warning aircraft that is still in the hangar when the raid arrives was
	# never worth carrying, so one goes up as a matter of course and is replaced as it comes back.
	for a: Unit in ready:
		if a.is_sensor_aircraft() and not _has_airborne(u, func(x: Unit) -> bool: return x.is_sensor_aircraft()):
			_send(u, b, a.callsign, 1, now)
			return

	# Give follows the receivers. A tanker on the deck does nothing for an aircraft at bingo.
	var receivers := _has_airborne(u, func(x: Unit) -> bool: return x.spec.can_refuel)
	if receivers:
		for a: Unit in ready:
			if a.spec.tanker_offload_s > 0.0 and not _has_airborne(u, func(x: Unit) -> bool: return x.is_tanker()):
				_send(u, b, a.callsign, 1, now)
				return

	# Something to prosecute. A submarine contact gets whatever can hunt it; anything else gets a
	# section sized to the deck, because a single aircraft against a defended ship is a gift.
	for t: Track in hostiles + unknowns:
		if t.domain != "subsurface" and t.identity != "HOSTILE":
			continue
		var wanted := 1 if t.domain == "subsurface" else mini(spots, PACKAGE_MAX)
		var pick := ""
		for a: Unit in ready:
			if a.can_engage_domain(t.domain):
				pick = a.callsign
				break
		if pick == "":
			continue
		_send(u, b, pick, wanted, now)
		return


func _send(u: Unit, b: Dictionary, callsign: String, count: int, now: float) -> void:
	b["last_launch"] = now
	if count <= 1:
		unit_manager.issue_order(u, Order.launch_aircraft(callsign))
		return
	unit_manager.issue_order(u, Order.launch_flight(callsign, count))


func _has_airborne(host: Unit, predicate: Callable) -> bool:
	for a: Unit in host.embarked:
		if a.alive and a.flight_state in [Unit.FlightState.LAUNCHING, Unit.FlightState.AIRBORNE] and predicate.call(a):
			return true
	return false


## A torpedo running through the water is the best clue anyone gets about where a submarine is.
## Treating the weapon's position as a search datum is what turns an attack into a prosecution.
func _note_torpedo_datum(u: Unit, b: Dictionary, now: float) -> void:
	if threat_manager == null:
		return
	for w: Weapon in threat_manager.get_threats(faction):
		if w.spec.is_torpedo() and threat_manager.visible_to(u, w):
			b["last_contact"] = w.position
			b["last_contact_time"] = now
			return


func _inbound_on(u: Unit) -> Array:
	if threat_manager == null:
		return []
	var out: Array = []
	for entry: Dictionary in AirDefence.inbound_threats(unit_manager, threat_manager, faction, u):
		if entry["target"] == u:
			out.append(entry)
	return out


func _choose_state(u: Unit, b: Dictionary, hostiles: Array, unknowns: Array, inbound: Array, now: float) -> State:
	# A ship with somewhere to be does not stop to shadow, and does not turn away from a missile
	# it has already decided to accept. Its own air defence still fires automatically.
	if u.ai_posture == "breakout":
		if not _pick_engagement(u, b, hostiles, now).is_empty():
			return State.ENGAGE
		return State.PATROL
	if _should_withdraw(u, hostiles):
		return State.WITHDRAW
	if not inbound.is_empty():
		return State.DEFEND
	if not _pick_engagement(u, b, hostiles, now).is_empty():
		return State.ENGAGE
	if not hostiles.is_empty():
		return State.SHADOW
	if not unknowns.is_empty():
		return State.INVESTIGATE
	if b["last_contact"] != Vector2.INF and now - float(b["last_contact_time"]) < CONTACT_MEMORY_S:
		return State.SEARCH
	return State.PATROL


func _should_withdraw(u: Unit, hostiles: Array) -> bool:
	if u.is_aircraft():
		return false  # fuel, not damage, is what sends an aircraft home, and aviation owns that
	if Damage.health_fraction(u) < WITHDRAW_HEALTH_FRACTION:
		return true
	return not hostiles.is_empty() and _strike_rounds_left(u, hostiles) == 0


func _strike_rounds_left(u: Unit, hostiles: Array) -> int:
	var total := 0
	for w in u.weapons:
		if w.type not in ["asm", "torpedo", "sam"]:
			continue
		for t: Track in hostiles:
			if Combat.suits_track(w, t):
				total += u.magazine_count(w.id)
				break
	return total


# --- Engagement decision -----------------------------------------------------------------



func _rounds_already_committed(t: Track) -> int:
	var n := 0
	for w: Weapon in weapon_manager.in_flight:
		if w.faction == faction and w.target_track == t:
			n += 1
	return n


## Returns {track, weapon, salvo}, or an empty Dictionary when there is no shot worth taking.
## Deliberately refuses the shots a thoughtful player would also regret: unclassified contacts,
## stale position data, and targets that already have enough rounds heading their way.
func _pick_engagement(u: Unit, b: Dictionary, hostiles: Array, now: float) -> Dictionary:
	if u.roe != Unit.Roe.FREE:
		return {}  # tight or hold: it will defend itself but will not start anything
	var engaged: Dictionary = b["engaged"]
	var best: Dictionary = {}
	var best_range := INF
	for t: Track in hostiles:
		if t.status != Track.Status.ACTIVE:
			continue  # never shoot at a stale track: the aim point would be old
		if t.classification < Track.Classification.CLASS_KNOWN:
			continue  # not confirmed hostile yet
		if now - float(engaged.get(t.id, -10000.0)) < float(b.get("cooldown_%s" % t.id, ENGAGE_COOLDOWN_S)):
			continue  # a salvo is already on its way; assess before spending more
		if _rounds_already_committed(t) >= MAX_ROUNDS_IN_FLIGHT_PER_TRACK:
			continue
		for spec: WeaponSpec in u.weapons_for_track(t):
			var check := Combat.check_engagement(u, spec, t)
			if not check["ok"]:
				continue
			if Combat.time_of_flight_s(spec, check["range_nm"]) > MAX_TIME_OF_FLIGHT_S:
				continue
			if t.bearing_only and t.tma_quality < MIN_SOLUTION_FOR_SLOW_WEAPON:
				continue
			if check["range_nm"] < best_range:
				best_range = check["range_nm"]
				best = {"track": t, "weapon": spec, "salvo": _salvo_for(u, spec)}
			break
	return best


func _salvo_for(u: Unit, spec: WeaponSpec) -> int:
	var rounds := u.magazine_count(spec.id)
	if spec.is_gun():
		return mini(spec.salvo_default, rounds)
	if spec.is_torpedo():
		return clampi(TORPEDO_SALVO, 1, rounds)
	return clampi(ASM_SALVO, 1, rounds)


# --- Behaviour ---------------------------------------------------------------------------

func _act(u: Unit, b: Dictionary, hostiles: Array, unknowns: Array, inbound: Array, now: float) -> void:
	match b["state"]:
		State.ENGAGE:
			_do_engage(u, b, hostiles, now)
		State.DEFEND:
			_do_defend(u, b, inbound, now)
		State.WITHDRAW:
			_do_withdraw(u, b, hostiles, now)
		State.SHADOW:
			_do_close(u, b, hostiles, _shadow_standoff(u), now)
		State.INVESTIGATE:
			_do_close(u, b, unknowns, CLASSIFY_STANDOFF_FRACTION * Detection.nominal_radar_ring_nm(u), now)
		State.SEARCH:
			_do_search(u, b, now)
		State.PATROL:
			_do_patrol(u, b, now)


## Standoff for holding a hostile. Weapon reach is not the binding constraint: a missile can
## outrange the radar many times over, and a track that is not being observed cannot receive
## mid-course updates. So the AI closes far enough to keep the contact, and no further.
func _shadow_standoff(u: Unit) -> float:
	var by_weapon := ENGAGE_STANDOFF_FRACTION * _best_strike_range(u)
	# A strike aircraft does not need its own radar on the target: it is shooting on the group's
	# picture, and closing to where it could see the ship for itself means closing to where the
	# ship can shoot it. Its stand-off is set by the weapon alone.
	if u.is_aircraft() and not _is_asw_airframe(u):
		return maxf(by_weapon, 8.0)
	var by_sensor := 0.85 * (Detection.nominal_passive_ring_nm(u) if u.is_submarine() else Detection.nominal_radar_ring_nm(u))
	if by_sensor <= 0.0:
		return maxf(by_weapon, 8.0)
	return maxf(minf(by_weapon, by_sensor), 8.0)


## An airframe whose sensors only work over the contact: a dipping set has to be in the water and
## a sonobuoy has to be dropped on top of the datum. Everything else is better off standing off.
func _is_asw_airframe(u: Unit) -> bool:
	return u.spec.sonobuoy_count > 0 or (u.spec.can_hover and u.has_sonar())


## Aircraft climb for reach and drop down to work. A dipping set has to be in the water, so the
## helicopter comes down and stops.
func _manage_altitude(u: Unit, working: bool) -> void:
	if not u.airborne():
		return
	var wanted := u.spec.cruise_altitude_m
	if working and u.spec.can_hover:
		wanted = HOVER_ALTITUDE_M
	if absf(u.ordered_altitude_m - wanted) > 5.0:
		unit_manager.issue_order(u, Order.set_altitude(wanted))


## Submarines stay quiet and use the water. Loitering, searching or being hunted, a boat goes under
## the layer if the water here lets it, because a hull sonar above it then hears very little. To
## hold a surface contact it comes back to patrol depth, where its own arrays can hear what is on
## top. A torpedo goes from any depth; a cruise missile leaves from near the surface, which is the
## one shot that makes a boat expose itself. The floor bounds all of it.
enum DepthIntent { HIDE, TRACK, MISSILE_SHOT }


func _manage_depth(u: Unit, intent: DepthIntent) -> void:
	if not u.is_submarine():
		return
	var wanted := u.spec.patrol_depth_m
	match intent:
		DepthIntent.HIDE:
			wanted = maxf(wanted, Acoustics.below_layer_depth_m(u))
		DepthIntent.MISSILE_SHOT:
			wanted = minf(u.spec.patrol_depth_m, MISSILE_LAUNCH_DEPTH_M)
	wanted = minf(wanted, Acoustics.max_operating_depth_m(u))
	# The floor changes under a moving boat; order in 5 m steps rather than chasing every metre.
	wanted = floorf(wanted / 5.0) * 5.0
	if absf(u.ordered_depth_m - wanted) > 1.0:
		unit_manager.issue_order(u, Order.set_depth(wanted))


func _best_strike_range(u: Unit) -> float:
	var best := 0.0
	for w in u.offensive_weapons():
		if u.magazine_count(w.id) > 0:
			best = maxf(best, w.max_range_nm)
	return maxf(best, 10.0)


func _do_engage(u: Unit, b: Dictionary, hostiles: Array, now: float) -> void:
	var plan := _pick_engagement(u, b, hostiles, now)
	if plan.is_empty():
		return
	_manage_emissions(u, true)
	var t: Track = plan["track"]
	b["target"] = t
	b["engaged"][t.id] = now
	# Wait until the salvo would actually have arrived before deciding it did not work.
	var flight := Combat.time_of_flight_s(plan["weapon"], u.position.distance_to(t.position))
	b["cooldown_%s" % t.id] = maxf(ENGAGE_COOLDOWN_S, flight * 1.5)
	_manage_emissions(u, true)  # shooting is worth being seen for
	unit_manager.issue_order(u, Order.engage(t, plan["weapon"].id, plan["salvo"]))
	if u.ai_posture == "breakout":
		_do_patrol(u, b, now)  # keep running the route while shooting
	else:
		# Hold station inside the envelope rather than charging in after shooting.
		_do_close(u, b, hostiles, _shadow_standoff(u), now)
	# Last, so the shot's depth outranks whatever the follow-on movement asked for.
	var weapon: WeaponSpec = plan["weapon"]
	_manage_depth(u, DepthIntent.TRACK if weapon.is_torpedo() else DepthIntent.MISSILE_SHOT)


## Turn away from the incoming bearing at speed. Opening the geometry buys the ship's own
## interceptors more time; the interception itself is automatic and needs no order.
func _do_defend(u: Unit, b: Dictionary, inbound: Array, now: float) -> void:
	_manage_emissions(u, true)
	_manage_depth(u, DepthIntent.HIDE)  # a boat with a torpedo on it goes deep as well as away
	if inbound.is_empty():
		return
	var mean := Vector2.ZERO
	for entry: Dictionary in inbound:
		var w: Weapon = entry["weapon"]
		mean += (w.position - u.position).normalized()
	var away := Geo.vector_to_heading(-mean) if mean.length() > 0.001 else u.heading_deg
	_command(u, b, _open_bearing(u, away), u.spec.max_speed_kn, now)


func _do_withdraw(u: Unit, b: Dictionary, hostiles: Array, now: float) -> void:
	_manage_emissions(u, true)  # still needs its own picture to defend itself while running
	var from: Vector2 = b["last_contact"]
	if not hostiles.is_empty():
		from = _nearest(u, hostiles).position
	if from == Vector2.INF:
		return
	_command(u, b, _open_bearing(u, Geo.vector_to_heading(u.position - from)), u.spec.max_speed_kn, now)


func _do_close(u: Unit, b: Dictionary, targets: Array, standoff_nm: float, now: float) -> void:
	if targets.is_empty():
		return
	var t: Track = _nearest(u, targets)
	b["target"] = t
	_manage_depth(u, DepthIntent.TRACK)
	_manage_emissions(u, true)
	var range_nm := u.position.distance_to(t.position)
	if u.is_aircraft() and _is_asw_airframe(u):
		_prosecute(u, b, t, range_nm, now)  # sonar work happens over the contact or not at all
		return
	if u.is_aircraft():
		# A strike aircraft holds outside the envelope of what it is shooting at. Flying overhead
		# to look at the ship it just fired a two-hundred-mile missile at is how a wing is spent.
		_manage_altitude(u, false)
		if range_nm <= standoff_nm:
			_command(u, b, Geo.vector_to_heading(u.position - t.position), u.spec.cruise_speed_kn, now)
			return
		_move_to(u, b, _standoff_point(u, t.position, standoff_nm), now)
		return
	if standoff_nm <= 0.0 or range_nm <= standoff_nm:
		_command(u, b, u.heading_deg, u.spec.cruise_speed_kn, now)  # on station, hold
		return
	# Approach along the bearing, stopping at the standoff distance.
	_move_to(u, b, _standoff_point(u, t.position, standoff_nm), now)


## The reach an aircraft searching open water should be using. Around a datum — a torpedo heard,
## a contact lost — a tight pattern is right, because the thing is near there. With no datum at
## all, a surveillance aircraft is looking for something that could be anywhere, and an eleven-mile
## ring around its own airfield finds nothing on a four-hundred-mile chart. So the sweep is sized
## to the airframe: a quarter of how far it could fly before it has to come back.
func _search_radius(u: Unit, has_datum: bool) -> float:
	if has_datum or _is_asw_airframe(u):
		return SEARCH_RADIUS_NM
	var reach := 0.25 * u.spec.cruise_speed_kn * (u.spec.endurance_s / 3600.0)
	return clampf(reach, SEARCH_RADIUS_NM, WIDE_SEARCH_MAX_NM)


## With nothing to prosecute, an ASW aircraft flies a search rather than orbiting its parent.
## Fly to a point, stop and dip if it can, lay a buoy if it carries them, then move on. The anchor
## is the last place anything was heard, or the parent ship if nothing has been.
func _do_air_search(u: Unit, b: Dictionary, now: float) -> void:
	var anchor: Vector2 = b["last_contact"]
	var has_datum := anchor != Vector2.INF
	if not has_datum:
		anchor = u.home.position if u.home != null else u.position
	if now < float(b.get("dip_until", -1.0)):
		_manage_altitude(u, true)
		_command(u, b, u.heading_deg, 0.0, now)
		return
	# Resume the next leg once, after the dip. Issuing it before stopping cleared the
	# waypoint again on the following tick and trapped helicopters at their first station.
	if b.has("after_dip"):
		var next_leg: Vector2 = b["after_dip"]
		b.erase("after_dip")
		_manage_altitude(u, false)
		_move_to(u, b, next_leg, now)
		return
	if not u.waypoints.is_empty():
		return  # already on the way to the next search point
	var index := int(b.get("search_index", 0))
	b["search_index"] = index + 1
	var bearing := fmod(float(index) * SEARCH_STEP_DEG, 360.0)
	var leg := anchor + Geo.heading_to_vector(bearing) * _search_radius(u, has_datum)
	if index > 0:
		_lay_search_buoy(u, b, now)
	if u.spec.can_hover and u.has_sonar() and index > 0 and not Terrain.is_land(u.position):
		b["dip_until"] = now + DIP_DURATION_S
		b["after_dip"] = leg
		_manage_altitude(u, true)
		_command(u, b, u.heading_deg, 0.0, now)
		return
	_manage_altitude(u, false)
	_move_to(u, b, leg, now)


## Search stores are laid over the patrol area, with enough separation to add coverage.
func _lay_search_buoy(u: Unit, b: Dictionary, now: float) -> void:
	if u.sonobuoys <= 0 or Terrain.is_land(u.position):
		return
	if now - float(b.get("last_buoy", -10000.0)) <= BUOY_INTERVAL_S:
		return
	var previous: Vector2 = b.get("last_buoy_position", Vector2.INF)
	if previous != Vector2.INF and u.position.distance_to(previous) < BUOY_SPACING_NM:
		return
	b["last_buoy"] = now
	b["last_buoy_position"] = u.position
	unit_manager.issue_order(u, Order.deploy_sonobuoy())


## An aircraft closes right over the contact, then either stops to dip or lays a buoy field.
func _prosecute(u: Unit, b: Dictionary, t: Track, range_nm: float, now: float) -> void:
	var over_water := not Terrain.is_land(u.position)
	if over_water and u.sonobuoys > 0 and range_nm <= BUOY_DROP_RANGE_NM and now - float(b.get("last_buoy", -10000.0)) > BUOY_INTERVAL_S:
		b["last_buoy"] = now
		unit_manager.issue_order(u, Order.deploy_sonobuoy())
	if over_water and u.spec.can_hover and u.has_sonar() and range_nm <= DIP_STANDOFF_NM:
		_manage_altitude(u, true)
		_command(u, b, u.heading_deg, 0.0, now)  # stop and listen
		return
	_manage_altitude(u, false)
	_move_to(u, b, t.position, now)


func _do_search(u: Unit, b: Dictionary, now: float) -> void:
	_manage_emissions(u, false)  # listening is how you find someone without being found
	_manage_depth(u, DepthIntent.HIDE)
	var last: Vector2 = b["last_contact"]
	if last == Vector2.INF:
		_do_patrol(u, b, now)
		return
	if u.is_aircraft():
		_do_air_search(u, b, now)
		return
	_move_to(u, b, last, now)


func _do_patrol(u: Unit, b: Dictionary, now: float) -> void:
	_manage_depth(u, DepthIntent.HIDE)
	_manage_altitude(u, false)
	# Breakout fixes the route, not the sensor state. Silencing an already active radar here
	# left a sprinting ship unable to firm up ESM bearings or defend itself, even after firing.
	# An authored silent transit stays silent until its own picture provides a reason to radiate.
	var transit_picture := false
	if u.ai_posture == "breakout" and not u.is_submarine():
		transit_picture = u.radar_on or not _inbound_on(u).is_empty()
		for t: Track in track_manager.tracks_for(u):
			if t.status != Track.Status.LOST and t.identity in ["UNKNOWN", "HOSTILE"]:
				transit_picture = true
	_manage_emissions(u, transit_picture)
	if u.is_aircraft() and u.patrol_route.is_empty():
		_do_air_search(u, b, now)
		return
	if u.patrol_route.is_empty():
		if u.waypoints.is_empty() and u.ordered_speed_kn <= 0.1:
			_command(u, b, u.heading_deg, u.spec.cruise_speed_kn, now)
		return
	# A surface group racing for a gate uses everything it has. A submarine doing the same thing
	# would simply announce itself, so it transits at a quiet speed instead.
	var wanted_speed := u.spec.cruise_speed_kn
	if u.ai_posture == "breakout" and not u.is_submarine():
		wanted_speed = u.spec.max_speed_kn
	if absf(u.ordered_speed_kn - wanted_speed) > 0.5:
		unit_manager.issue_order(u, Order.set_speed(wanted_speed))
	var idx: int = b["patrol_index"] % u.patrol_route.size()
	# A leg an author placed ashore is stood off into the nearest water, and arrival is judged
	# against that point. Judging it against the original would leave the route stuck on a leg
	# the ship can never reach, and the unit steaming at the coast for the whole scenario.
	var leg := _sea_room(u, u.patrol_route[idx])
	if u.position.distance_to(leg) < PATROL_ARRIVAL_NM:
		b["on_patrol_station"] = true
		b["patrol_index"] = idx + 1
		leg = _sea_room(u, u.patrol_route[(idx + 1) % u.patrol_route.size()])
	if u.is_aircraft() and _is_asw_airframe(u) and bool(b.get("on_patrol_station", false)):
		_lay_search_buoy(u, b, now)
	_move_to(u, b, leg, now)


# --- Order plumbing ----------------------------------------------------------------------

func _nearest(u: Unit, tracks: Array) -> Track:
	var best: Track = tracks[0]
	var best_d := u.position.distance_to(best.position)
	for t: Track in tracks:
		var d := u.position.distance_to(t.position)
		if d < best_d:
			best = t
			best_d = d
	return best


## Issues a MOVE only when the destination has meaningfully changed, so the order log stays
## readable and units are not re-tasked every cycle.
func _move_to(u: Unit, b: Dictionary, wanted: Vector2, now: float) -> void:
	var goal := _sea_room(u, wanted)
	var previous: Vector2 = b["goal"]
	# Re-task only when the destination has actually moved, or when the ship has arrived and is
	# sitting there with nothing to do. Anything else fills the order log with noise.
	if previous != Vector2.INF and previous.distance_to(goal) < GOAL_TOLERANCE_NM and not u.waypoints.is_empty():
		return
	b["goal"] = goal
	b["goal_time"] = now
	b["course"] = -1.0
	unit_manager.issue_order(u, Order.move(goal))
	if u.ordered_speed_kn < u.spec.cruise_speed_kn:
		unit_manager.issue_order(u, Order.set_speed(u.spec.cruise_speed_kn))


## A destination a hull cannot reach is no destination at all: a MOVE onto land is refused, and a
## refused MOVE leaves the waypoint list empty, which defeats the re-task guard above and has the
## AI issuing the same rejected order every cycle while the ship sits still. So the goal is moved
## into the water before it is ordered, never after. Tracks carry position error, so a contact
## hugging a coast routinely produces a datum a mile inland; that is normal traffic, not a fault.
func _sea_room(u: Unit, goal: Vector2) -> Vector2:
	if not u.needs_sea_room():
		return goal
	return Terrain.nearest_water(goal, u.position)


## A shadower wants to sit at a set range from its contact. When the point on its own bearing is
## ashore, the range is what matters, so the point slides around the ring rather than in towards
## the beach.
func _standoff_point(u: Unit, target_pos: Vector2, standoff_nm: float) -> Vector2:
	var offset := (u.position - target_pos).normalized() * standoff_nm
	if Terrain.is_empty():
		return target_pos + offset
	for step: float in STANDOFF_ARC_DEG:
		for side: float in [1.0, -1.0]:
			var candidate := target_pos + offset.rotated(deg_to_rad(step * side))
			if not Terrain.is_land(candidate):
				return candidate
	return target_pos + offset


func _open_bearing(u: Unit, wanted_deg: float) -> float:
	if not u.needs_sea_room() or Terrain.is_empty():
		return wanted_deg
	return Terrain.open_bearing_deg(u.position, wanted_deg, maxf(u.spec.max_speed_kn, 10.0) * COAST_LOOKAHEAD_S / 3600.0)


func _command(u: Unit, b: Dictionary, course_deg: float, speed_kn: float, now: float) -> void:
	var course_changed := float(b["course"]) < 0.0 or absf(Geo.heading_delta(float(b["course"]), course_deg)) > COURSE_TOLERANCE_DEG
	var speed_changed := absf(float(b["speed"]) - speed_kn) > SPEED_TOLERANCE_KN
	if not course_changed and not speed_changed and now - float(b["cmd_time"]) < ORDER_REFRESH_S:
		return
	b["course"] = course_deg
	b["speed"] = speed_kn
	b["cmd_time"] = now
	b["goal"] = Vector2.INF
	unit_manager.issue_order(u, Order.set_course(course_deg))
	unit_manager.issue_order(u, Order.set_speed(speed_kn))


## Emissions. A submerged boat stays quiet because it has no choice. A ship with electronic
## support has a choice worth making: it can listen for the other side's radar instead of
## transmitting, and only switch on when it actually needs the picture.
func _manage_emissions(u: Unit, need_radar: bool) -> void:
	if u.is_aircraft():
		if u.has_radar() and not u.radar_on:
			unit_manager.issue_order(u, Order.activate_radar())
		return
	if u.is_submarine():
		if u.active_sonar_on:
			unit_manager.issue_order(u, Order.passive_sonar())
		return
	if not u.has_radar():
		return
	var want := need_radar or not u.has_esm()
	if want != u.radar_on:
		unit_manager.issue_order(u, Order.activate_radar() if want else Order.silence_radar())
