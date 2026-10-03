class_name AIController
extends Node
## Opposing-force commander for one faction.
##
## The AI is bound by exactly the same information limits as the player. It reads its own units,
## its own faction's TrackManager picture and its own ThreatManager picture. It never touches
## enemy Unit objects and never reads Track.truth, so it can be surprised, can be decoyed by a
## stale track, and can shoot at water. Everything it does leaves through
## UnitManager.issue_order(), the same path the player's UI uses.

## The last five belong to plan members (AIPlan) and are appended so stored values keep meaning.
enum State { PATROL, SEARCH, INVESTIGATE, SHADOW, ENGAGE, DEFEND, WITHDRAW, HOLD, APPROACH, SCOUT, SCREEN, GUARD }

const STATE_NAMES := ["PATROL", "SEARCH", "INVESTIGATE", "SHADOW", "ENGAGE", "DEFEND", "WITHDRAW", "HOLD", "APPROACH", "SCOUT", "SCREEN", "GUARD"]

const WITHDRAW_HEALTH_FRACTION := 0.35
const ENGAGE_COOLDOWN_S := 200.0  # wait and assess before re-attacking the same track
## Rounds flying or queued at one contact, across the side, before anyone adds more: enough for a
## group to mass a saturating salvo on one target, and no more.
const MAX_ROUNDS_IN_FLIGHT_PER_TRACK := 8
## The same limit for an aircraft, and the shortest wait before shooting at one again. GAMEPLAY_ESTIMATE.
const AIR_ROUNDS_IN_FLIGHT := 2
const AIR_REENGAGE_MIN_S := 15.0
## A fighter with air-to-air weapons holds this share of its longest one's reach from an air contact:
## inside its own envelope, not two hundred miles away behind its anti-ship stand-off.
const AIR_STANDOFF_FRACTION := 0.5
## Outranged (the known enemy reaches this much further): commit and hold at this share instead.
const OUTRANGED_FACTOR := 1.15
const OUTRANGED_STANDOFF_FRACTION := 0.8
const ORDER_REFRESH_S := 30.0
const GOAL_TOLERANCE_NM := 3.0
const COURSE_TOLERANCE_DEG := 8.0
const SPEED_TOLERANCE_KN := 1.5
const CLASSIFY_STANDOFF_FRACTION := 0.55  # close inside radar range to speed up classification
const ENGAGE_STANDOFF_FRACTION := 0.80  # sit inside the weapon envelope, not on its edge
const CONTACT_MEMORY_S := 1200.0
const ASM_SALVO := 4
const TORPEDO_SALVO := 2
## Paket-NK rounds the AI keeps back from an attack for torpedoes coming at its own ship.
const ANTI_TORPEDO_RESERVE := 2
## A weapon that takes too long to arrive is shooting at where the target used to be. This one
## rule keeps the AI from firing a 50 knot torpedo across twenty miles of ocean without needing a
## special case for torpedoes. It is about targets that move: a shore installation is where it was
## when the round left, so a land-attack round may take as long as it needs (`_is_fixed_target`).
const MAX_TIME_OF_FLIGHT_S := 480.0
## Above this a land track is taken to be moving, and the flight-time limit applies to it again.
const FIXED_TARGET_MAX_KN := 1.0
const MIN_SOLUTION_FOR_SLOW_WEAPON := 0.5  # a bearing with no range is not a firing solution
const BREAKOUT_TORPEDO_NM := 8.0  # a boat breaking out shoots only at what is in its way
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
const SHIP_ASW_WORK_RADIUS_NM := 6.0  # gameplay estimate: near a held submarine datum
const PATROL_ARRIVAL_NM := 4.0
## A ship at 30 kn turning at 3 deg/s eats a quarter of a mile getting ninety degrees round, so an
## avoidance bearing has to look further ahead than that or it orders a turn that cannot be made.
const COAST_LOOKAHEAD_S := 120.0  # GAMEPLAY_ESTIMATE
## Plans (AIPlan). Every one of these is a GAMEPLAY_ESTIMATE.
const ASSEMBLY_RADIUS_NM := 6.0  # a striker this close to the assembly point has joined
const IP_ARRIVAL_NM := 6.0  # ...and this close to its point on its attack axis is in position
const HOLD_TOLERANCE_NM := 2.0  # drift a ship holding a point lets go before closing it again
const ORBIT_RADIUS_NM := 8.0  # an aircraft holding a point flies legs this far round it
const SCREEN_TOLERANCE_NM := 1.5  # an escort this close to its screen station keeps the guide's course
const SCREEN_GAIN_KN_PER_NM := 4.0  # extra speed an escort uses per mile it is off station
const SCOUT_AREA_MARGIN := 1.5  # scouts look at contacts out to this multiple of the search radius
const SWEEP_FRACTION := 0.6  # a scout with nothing to look at sweeps legs this far into the area
const SLOW_CONTACT_KN := 20.0  # an unclassified contact slower than this might be a merchant
const SLOW_CONTACT_BONUS_NM := 15.0  # ...and is looked at as if this much nearer
const RECON_RETRY_S := 600.0  # before a finished air reconnaissance is asked for again
## How strongly a plan's preference outweighs range when choosing between contacts to shoot at.
const PLAN_BUCKET_NM := 1000.0
## The preference band of a contact the plan does not want, engaged only because it came too close.
const THREAT_BUCKET := 50

var faction := ""
var unit_manager: UnitManager
var track_manager: TrackManager
var threat_manager: ThreatManager
var weapon_manager: WeaponManager
## Airframes flying an air mission are the mission's to steer, whichever side owns them.
var air_mission_manager: AirMissionManager
var enabled := true
## The scenario's mission plans for this side (configure_plans), in the order they are written.
var plans: Array[AIPlan] = []

var _bb: Dictionary = {}  # Unit -> blackboard Dictionary
var _plan_checked: Dictionary = {}  # Unit.id -> true once its plan membership is settled


func state_name(u: Unit) -> String:
	if not _bb.has(u):
		return ""
	return STATE_NAMES[_bb[u]["state"]]


func describe(u: Unit) -> String:
	if not _bb.has(u):
		return ""
	var b: Dictionary = _bb[u]
	var target: Track = b["target"]
	var text := "%s%s" % [STATE_NAMES[b["state"]], "  -> %s" % target.id if target != null else ""]
	var p := plan_for(u)
	if p != null:
		text += "  [%s %s %s]" % [p.id, p.phase_name(), p.role_of(u)]
	return text


var _cycle_inbound: Array = []
var _cycle_committed: Dictionary = {}
var _cycle_torpedoes: Array[Weapon] = []
var _in_decision_cycle := false


func tick(now: float) -> void:
	if not enabled or unit_manager == null:
		return
	# Victim geometry is the same for every ship in this decision cycle. Observer visibility
	# remains a per-unit check, including any emissions changes made by preceding orders.
	_cycle_inbound = AirDefence.inbound_threats(unit_manager, threat_manager, faction) if threat_manager != null else []
	_cycle_committed = {}
	_cycle_torpedoes.clear()
	if weapon_manager != null:
		# Flying and queued rounds alike, by track id. A salvo ordered during this cycle is counted
		# in full the moment it is accepted, so the next ship in the loop sees all of it.
		_cycle_committed = weapon_manager.rounds_committed_by_track_id(faction)
		weapon_manager.weapon_launched.connect(_on_cycle_salvo)
	if threat_manager != null:
		for w: Weapon in threat_manager.get_threats(faction):
			if w.spec.is_torpedo() and not w.is_interceptor():
				_cycle_torpedoes.append(w)
	_in_decision_cycle = true
	# The commander decides what each plan is after before any captain decides what to do.
	if not plans.is_empty():
		_plan_cycle(now)
	for u in unit_manager.get_faction_units(faction):
		_update_unit(u, now)
	_in_decision_cycle = false
	if weapon_manager != null:
		weapon_manager.weapon_launched.disconnect(_on_cycle_salvo)
	_cycle_inbound.clear()
	_cycle_committed = {}
	_cycle_torpedoes.clear()


## A salvo accepted during the decision cycle: the round that left and the ones queued behind it.
func _on_cycle_salvo(shooter: Unit, _spec: WeaponSpec, track: Track, rounds: int) -> void:
	if shooter.faction == faction and track != null:
		_cycle_committed[track.id] = int(_cycle_committed.get(track.id, 0)) + rounds


func clear() -> void:
	_bb.clear()


## The scenario has given one of this side's units a new standing route or posture (an operation
## event deciding for this side). It starts the new route from its first leg and forgets where the
## old one was taking it, so the next cycle steers by the new orders rather than finishing the old.
func route_changed(u: Unit) -> void:
	if not _bb.has(u):
		return
	var b: Dictionary = _bb[u]
	b["patrol_index"] = 0
	b["goal"] = Vector2.INF
	b.erase("on_patrol_station")


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
	if u.is_aircraft() and (u.returning or u.tanking_on != null):
		return  # heading home or to the tanker on its own; leave it alone
	if u.is_aircraft() and air_mission_manager != null and air_mission_manager.mission_for(u) != null:
		return  # flying a mission: the mission steers it, under the same ROE and fuel rules
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
		# A hostile the side has seen go down is nothing to close on, shadow or shoot at.
		if t.identity == "HOSTILE" and t.damage_estimate >= 100.0:
			continue
		var mine := u.can_engage_domain(t.domain) or (t.domain == "subsurface" and TowedArray.capable(u))
		if t.identity == "HOSTILE":
			all_hostiles.append(t)
			if mine:
				hostiles.append(t)
				b["last_contact"] = t.position
				b["last_contact_time"] = now
				b["last_contact_domain"] = t.domain
		elif t.identity == "UNKNOWN" and t.status == Track.Status.ACTIVE:
			all_unknowns.append(t)  # a contact identified as neutral is left alone
			if mine:
				unknowns.append(t)

	_note_torpedo_datum(u, b, now)
	# A plan member does its part of the plan; everything else, and every unit of a side without
	# a plan, decides exactly as it always has.
	var task: Dictionary = _plan_task(u) if not plans.is_empty() else {}
	if task.is_empty():
		_consider_launch(u, b, all_hostiles, all_unknowns, now)
	else:
		_plan_launch(u, b, task, all_hostiles, now)
	# A ship breaking out and an installation ashore keep their own judgement: the plan is about
	# them, and their decks launch for it, but they are not steered by it.
	if AIPlan.SELF_DIRECTED_ROLES.has(task.get("role", "")):
		task = {}
	if u.spec.max_speed_kn <= 0.0:
		_do_shore_fires(u, b, hostiles, unknowns, now, task)  # a battery shoots; an airfield sends aircraft up
		return
	var inbound := _inbound_on(u)
	var new_state := _choose_state(u, b, hostiles, unknowns, inbound, now) if task.is_empty() else _choose_plan_state(u, b, hostiles, unknowns, inbound, now, task)
	if u.array_search_active and new_state not in [State.SEARCH, State.INVESTIGATE, State.SHADOW, State.ENGAGE]:
		unit_manager.issue_order(u, Order.recover_towed_array())
		unit_manager.issue_order(u, Order.set_speed(u.spec.cruise_speed_kn))
	if new_state != b["state"]:
		b["state"] = new_state
		b["since"] = now
	if task.is_empty():
		_act(u, b, hostiles, unknowns, inbound, now)
	else:
		_act_plan(u, b, hostiles, unknowns, inbound, now, task)


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
	for w: Weapon in (_cycle_torpedoes if _in_decision_cycle else threat_manager.get_threats(faction)):
		if w.phase != Weapon.Phase.DEAD and w.spec.is_torpedo() and not w.is_interceptor() and threat_manager.visible_to(u, w):
			b["last_contact"] = w.position
			b["last_contact_time"] = now
			b["last_contact_domain"] = "subsurface"
			return


func _inbound_on(u: Unit) -> Array:
	if threat_manager == null:
		return []
	var out: Array = []
	var picture := _cycle_inbound if _in_decision_cycle else AirDefence.inbound_threats(unit_manager, threat_manager, faction, u)
	for entry: Dictionary in picture:
		if entry["target"] == u and threat_manager.visible_to(u, entry["weapon"]):
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



## Rounds this side already has flying or queued at the contact, whoever fired them.
func _rounds_already_committed(t: Track) -> int:
	if _in_decision_cycle:
		return int(_cycle_committed.get(t.id, 0))
	if weapon_manager == null:
		return 0
	return int(weapon_manager.rounds_committed_by_track_id(faction).get(t.id, 0))


## Returns {track, weapon, salvo}, or an empty Dictionary when there is no shot worth taking.
## Deliberately refuses the shots a thoughtful player would also regret: unclassified contacts,
## stale position data, and targets that already have enough rounds heading their way.
## Without a plan the nearest acceptable shot wins. A plan member (`task`) shoots only at what its
## plan is after, in the plan's order of preference, or at what has come close enough to threaten
## it; within the plan's round budget, and never while the plan is assessing its last volley.
func _pick_engagement(u: Unit, b: Dictionary, hostiles: Array, now: float, task := {}) -> Dictionary:
	if u.roe != Unit.Roe.FREE:
		return {}  # tight or hold: it will defend itself but will not start anything
	var plan: AIPlan = task.get("plan")
	var engaged: Dictionary = b["engaged"]
	var best: Dictionary = {}
	var best_range := INF
	for t: Track in hostiles:
		var bucket := 0
		if plan != null:
			bucket = _plan_bucket(u, t, task)
			if bucket < 0:
				continue  # neither the plan's business nor close enough to be a threat
		if t.status != Track.Status.ACTIVE or t.damage_estimate >= 100.0:
			continue  # never shoot at a stale track, nor at one the side has already seen go down
		if t.classification < Track.Classification.CLASS_KNOWN:
			continue  # not confirmed hostile yet
		if now - float(engaged.get(t.id, -10000.0)) < float(b.get("cooldown_%s" % t.id, ENGAGE_COOLDOWN_S)):
			continue  # a salvo is already on its way; assess before spending more
		var cap := MAX_ROUNDS_IN_FLIGHT_PER_TRACK
		if t.domain == "air":
			cap = AIR_ROUNDS_IN_FLIGHT  # an aircraft is one airframe, not a ship's defences to saturate
		if plan != null:
			if plan.assessing(t.id, now):
				continue  # the whole group waits to see what its last volley did
			# The budget is for what the plan is after. A contact shot at only because it came too
			# close gets no more than the side would put on it anyway.
			cap = plan.budget if bucket < THREAT_BUCKET else mini(plan.budget, MAX_ROUNDS_IN_FLIGHT_PER_TRACK)
			if t.domain == "air":
				cap = mini(cap, AIR_ROUNDS_IN_FLIGHT)
		var committed := _rounds_already_committed(t)
		if committed >= cap:
			continue
		for spec: WeaponSpec in u.weapons_for_track(t):
			# A boat breaking out does not announce itself. A missile launch fixes its position for
			# everyone listening, so it keeps its missiles and holds its torpedoes for whatever is
			# close enough to be in its way.
			var quiet_transit := u.ai_posture == "breakout" and u.is_submarine()
			if quiet_transit and not spec.is_torpedo():
				continue
			if _offensive_rounds(u, spec) <= 0:
				continue
			var check := Combat.check_engagement(u, spec, t)
			if not check["ok"]:
				continue
			if quiet_transit and check["range_nm"] > BREAKOUT_TORPEDO_NM:
				continue
			var long_flight := Combat.time_of_flight_s(spec, check["range_nm"]) > MAX_TIME_OF_FLIGHT_S
			if long_flight and not _is_fixed_target(t):
				continue
			# A distant installation will keep. A round that can also sink ships (Tomahawk) keeps its
			# last salvo for ships rather than spend it on an airfield two hundred miles inland.
			var spare := _offensive_rounds(u, spec) - (ASM_SALVO if long_flight and spec.target_types.has("surface") else 0)
			if spare <= 0:
				continue
			if t.bearing_only and t.tma_quality < MIN_SOLUTION_FOR_SLOW_WEAPON:
				continue
			var score: float = check["range_nm"] + bucket * PLAN_BUCKET_NM
			if score < best_range:
				best_range = score
				var rounds := mini(_salvo_for(u, spec, t), spare)
				if t.domain == "air":
					rounds = mini(rounds, maxi(cap - committed, 1))
				if plan != null:
					if plan.salvo > 0 and not spec.is_gun():
						rounds = mini(plan.salvo, spare)
					rounds = mini(rounds, cap - committed)  # never past the plan's budget
				best = {"track": t, "weapon": spec, "salvo": rounds}
			break
	return best


func _salvo_for(u: Unit, spec: WeaponSpec, t: Track = null) -> int:
	var rounds := _offensive_rounds(u, spec)
	if spec.is_gun():
		return mini(spec.salvo_default, rounds)
	# An aircraft is one airframe, not a ship's defences to saturate: the weapon's own doctrine
	# salvo (two, typically), not the four-round anti-ship volley.
	if spec.type in ["sam", "aam"] and t != null and t.domain == "air":
		return clampi(spec.salvo_default, 1, rounds)
	if spec.is_torpedo():
		return clampi(TORPEDO_SALVO, 1, rounds)
	return clampi(ASM_SALVO, 1, rounds)


## A target that will still be where the round is sent: a shore installation the picture shows
## standing still. Every installation in the catalogue is dug in; the speed check is for a mobile
## launcher, which is a moving target like any other.
static func _is_fixed_target(t: Track) -> bool:
	return t.domain == "land" and (not t.has_kinematics or t.speed_kn <= FIXED_TARGET_MAX_KN)


## Rounds a weapon can spend on an attack: all of them, less what a launcher that also answers
## torpedoes (Paket-NK) keeps back for one coming at the ship.
static func _offensive_rounds(u: Unit, spec: WeaponSpec) -> int:
	var rounds := u.magazine_count(spec.id)
	return rounds - ANTI_TORPEDO_RESERVE if spec.target_types.has("torpedo") else rounds


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


## The longest reach this aircraft has against this air contact, or 0 with nothing that suits it.
func _air_reach(u: Unit, t: Track) -> float:
	var best := 0.0
	for spec: WeaponSpec in u.weapons_for_track(t):
		if spec.type in ["aam", "sam"]:
			best = maxf(best, spec.max_range_nm)
	return best


## The longest air-to-air reach the plot's reported class carries, or 0 when the class is not known.
## Read from the catalogue entry for the reported class, never from the contact itself.
static func _enemy_air_reach(t: Track) -> float:
	if t.classification < Track.Classification.CLASS_KNOWN:
		return 0.0
	var pid := MapSymbols.platform_for_class(t.known_class, t.known_category)
	var spec := DataDB.platform(pid) if pid != "" else null
	if spec == null:
		return 0.0
	var best := 0.0
	for wid: String in spec.weapon_loadout:
		var w := DataDB.weapon(wid)
		if w != null and w.type == "aam" and w.target_types.has("air"):
			best = maxf(best, w.max_range_nm)
	return best


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
	if u.dip_phase != DippingSonar.Phase.STOWED:
		return
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
	var t: Track = plan["track"]
	_manage_emissions(u, true)  # shooting is worth being seen for
	# A refused shot (fire control saturated, out of the envelope after all) fired nothing, so it
	# must not start the re-attack cooldown on that target.
	if unit_manager.issue_order(u, Order.engage(t, plan["weapon"].id, plan["salvo"])):
		b["target"] = t
		b["engaged"][t.id] = now
		# Wait until the salvo would actually have arrived before deciding it did not work.
		var flight := Combat.time_of_flight_s(plan["weapon"], u.position.distance_to(t.position))
		# An aircraft is shot at, looked at once the rounds have had time to arrive, and shot at
		# again; a ship gets the long assessment its damage needs.
		b["cooldown_%s" % t.id] = maxf(flight * 1.2, AIR_REENGAGE_MIN_S) if t.domain == "air" else maxf(ENGAGE_COOLDOWN_S, flight * 1.5)
	if u.ai_posture == "breakout":
		_do_patrol(u, b, now)  # keep running the route while shooting
	else:
		# Hold station inside the envelope rather than charging in after shooting.
		_do_close(u, b, hostiles, _shadow_standoff(u), now)
	# Last, so the shot's depth outranks whatever the follow-on movement asked for.
	var weapon: WeaponSpec = plan["weapon"]
	_manage_depth(u, DepthIntent.TRACK if weapon.is_torpedo() else DepthIntent.MISSILE_SHOT)


## An installation ashore cannot manoeuvre, so its whole decision is whether to radiate and
## whether to shoot. A coastal battery or a missile site fires on the same picture, with the same
## reluctance about stale and unclassified contacts, as a ship; it simply never moves afterwards.
## A battery without a radar of its own shoots on whatever the network hands it, which is the
## operational problem such a battery poses and the one it has.
func _do_shore_fires(u: Unit, b: Dictionary, hostiles: Array, unknowns: Array, now: float, task := {}) -> void:
	if u.weapons.is_empty():
		return
	# Radiate only when there is something to look at: a silent battery is a battery not found.
	_manage_emissions(u, not hostiles.is_empty() or not unknowns.is_empty())
	var plan := _pick_engagement(u, b, hostiles, now, task)
	if plan.is_empty():
		b["state"] = State.PATROL
		return
	var t: Track = plan["track"]
	b["state"] = State.ENGAGE
	b["target"] = t
	if unit_manager.issue_order(u, Order.engage(t, plan["weapon"].id, plan["salvo"])):
		b["engaged"][t.id] = now
		var flight := Combat.time_of_flight_s(plan["weapon"], u.position.distance_to(t.position))
		b["cooldown_%s" % t.id] = maxf(ENGAGE_COOLDOWN_S, flight * 1.5)
		if not task.is_empty():
			var mission: AIPlan = task["plan"]
			mission.note_salvo(t.id, flight, now)


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
	# An aircraft with a missile on it breaks hard, as the commander's own can be ordered to: the
	# same manoeuvre, the same benefit against the seeker.
	if u.is_aircraft() and u.evasion_remaining_s <= 0.0:
		DefensiveResponse.start_evasion(u, unit_manager, threat_manager)
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
	if u.array_search_active and t.domain != "subsurface":
		unit_manager.issue_order(u, Order.recover_towed_array())
	_manage_depth(u, DepthIntent.TRACK)
	_manage_emissions(u, true)
	var range_nm := u.position.distance_to(t.position)
	if t.domain == "subsurface" and _work_ship_array(u, b, t.position, now):
		return
	if u.is_aircraft() and _is_asw_airframe(u):
		_prosecute(u, b, t, range_nm, now)  # sonar work happens over the contact or not at all
		return
	if u.is_aircraft():
		# A strike aircraft holds outside the envelope of what it is shooting at. Flying overhead
		# to look at the ship it just fired a two-hundred-mile missile at is how a wing is spent.
		_manage_altitude(u, false)
		if t.domain == "air":
			var air_reach := _air_reach(u, t)
			if air_reach > 0.0:
				# A fighter presses into its own missile envelope against another aircraft, at dash,
				# rather than turning away at its anti-ship stand-off the moment it sees one; but
				# not into a known enemy's longer reach, where it would be shot before it could shoot.
				standoff_nm = AIR_STANDOFF_FRACTION * air_reach
				# Outranged by a known enemy: hanging about outside its reach only means never
				# shooting. Commit at dash and shoot from the outer part of the own envelope.
				if _enemy_air_reach(t) > air_reach * OUTRANGED_FACTOR:
					standoff_nm = OUTRANGED_STANDOFF_FRACTION * air_reach
				if range_nm > standoff_nm:
					_move_to(u, b, _standoff_point(u, t.position, standoff_nm), now)
					unit_manager.issue_order(u, Order.set_speed(u.spec.flight_speed("dash")))
					return
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
	if u.dip_phase != DippingSonar.Phase.STOWED:
		return
	# Resume the next leg once, after the dip. Issuing it before stopping cleared the
	# waypoint again on the following tick and trapped helicopters at their first station.
	if b.has("after_dip"):
		var next_leg: Vector2 = b["after_dip"]
		b.erase("after_dip")
		_manage_altitude(u, false)
		_move_to(u, b, next_leg, now)
		return
	if u.has_route():
		return  # already on the way to the next search point
	var index := int(b.get("search_index", 0))
	b["search_index"] = index + 1
	var bearing := fmod(float(index) * SEARCH_STEP_DEG, 360.0)
	var leg := anchor + Geo.heading_to_vector(bearing) * _search_radius(u, has_datum)
	if index > 0:
		_lay_search_buoy(u, b, now)
	if index > 0 and unit_manager.issue_order(u, Order.deploy_dipping_sonar(DIP_DURATION_S)):
		b["after_dip"] = leg
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
	if over_water and DippingSonar.capable(u) and range_nm <= DIP_STANDOFF_NM:
		if u.dip_phase == DippingSonar.Phase.STOWED:
			unit_manager.issue_order(u, Order.deploy_dipping_sonar(DIP_DURATION_S))
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
	if b.get("last_contact_domain", "") == "subsurface" and _work_ship_array(u, b, last, now):
		return
	_move_to(u, b, last, now)


## A fitted ship works a nearby submarine datum quietly, with a crossing listening leg. It does
## not tow at full transit speed or endlessly cancel deployment with the normal course refresh.
## Distant contacts, breakout routes and formation assignments keep their existing priorities;
## their navigation/evasion orders recover the array through the same Unit handling as the player.
func _work_ship_array(u: Unit, b: Dictionary, datum: Vector2, now: float) -> bool:
	if not TowedArray.capable(u) or u.ai_posture == "breakout" or u.in_formation():
		return false
	if u.position.distance_to(datum) > SHIP_ASW_WORK_RADIUS_NM or not TowedArray.safe_water(u) or u.component("sensors") <= 0.0:
		return false
	if u.array_phase == TowedArray.Phase.RECOVERING:
		return false  # finish the deliberate recovery before starting another listening leg
	if u.array_search_active:
		return true
	if TowedArray.rejection(u) != "":
		return false
	_command(u, b, Geo.bearing_deg(u.position, datum) + 90.0, TowedArray.QUIET_SPEED_KN, now)
	var order := Order.asw_search()
	order.origin = "crew"
	return unit_manager.issue_order(u, order)


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


# --- Mission plans -----------------------------------------------------------------------
#
# A plan (AIPlan) turns a group of units into a formation with a purpose: find the carrier and
# strike it from several directions at once, get at the convoy's merchants past its escorts, screen
# a ship breaking out, hold the water round an installation. The commander's pass runs before the
# units decide. It reads this side's own picture, never anyone else's, and the positions of its
# own units; what it learns about a contact is only what the contact's track reports.

## The scenario's plans for this side, from the raw "ai_plans" entries. A malformed entry is
## reported and skipped; a side with no plans plays exactly as it did before plans existed.
func configure_plans(defs) -> void:
	plans = AIPlan.parse_all(defs, faction)
	_plan_checked.clear()


func plan_for(u: Unit) -> AIPlan:
	for p in plans:
		if p.has_member(u):
			return p
	return null


func _plan_cycle(now: float) -> void:
	_adopt_plan_members()
	for p in plans:
		_step_plan(p, now)


## Units join a plan once, the first cycle they are alive in: from the scenario's lists, from their
## own tag, or with the deck they fly from. A reinforcement tagged for a plan joins it on arrival.
func _adopt_plan_members() -> void:
	for u in unit_manager.get_faction_units(faction):
		if _plan_checked.has(u.id):
			continue
		_plan_checked[u.id] = true
		for p in plans:
			var role := p.role_for(u)
			if role != "":
				p.add_member(u, role)
				break


func _step_plan(p: AIPlan, now: float) -> void:
	if now < p.start_s:
		p.set_phase(AIPlan.Phase.WAITING, now)
		return
	var was := "%s %s %s" % [p.phase_name(), p.target_track_id, p.weapons_free]
	_launch_scouts(p, now)
	match p.kind:
		AIPlan.Kind.PROTECT_BREAKOUT:
			p.set_phase(AIPlan.Phase.SCREEN, now)
			_assign_screen(p)
		AIPlan.Kind.DEFEND_INSTALLATION:
			p.set_phase(AIPlan.Phase.DEFEND, now)
			_assign_guard(p)
		_:
			_step_strike_plan(p, now)
	_request_air_recon(p, now)
	if was != "%s %s %s" % [p.phase_name(), p.target_track_id, p.weapons_free]:
		Debug.event("[AI plan] %s %s: %s%s%s" % [faction, p.id, p.phase_name(), " on " + p.target_track_id if p.target_track_id != "" else "", ", weapons free" if p.weapons_free else ""])


## Reconnaissance, assembly, attack. Until a contact the plan wants is classified the strikers hold
## (at the assembly point, if there is one) while the scouts look; nothing about a contact's real
## identity reaches the plan except through its track.
func _step_strike_plan(p: AIPlan, now: float) -> void:
	if not p.own_side.is_finite():
		p.own_side = p.assembly if p.assembly.is_finite() else _strike_centre(p)
	var target := _plan_target(p)
	if target == null:
		p.target = null
		p.target_track_id = ""
		p.weapons_free = false
		p.axes.clear()
		p.set_phase(AIPlan.Phase.RECON, now)
	elif target.id != p.target_track_id:
		# Found, or something higher on the list has been classified: the strike forms up on it.
		p.target = target
		p.target_track_id = target.id
		p.weapons_free = false
		p.window_since = now
		p.axes.clear()
		var side := p.own_side if p.own_side.is_finite() else _strike_centre(p)
		p.base_axis_deg = Geo.bearing_deg(target.position, side) if side.is_finite() and side.distance_to(target.position) > 0.1 else 0.0
		if p.phase == AIPlan.Phase.WAITING or p.phase == AIPlan.Phase.RECON:
			p.set_phase(AIPlan.Phase.ASSEMBLE if p.assembly.is_finite() else AIPlan.Phase.ATTACK, now)
	else:
		p.target = target
	if p.phase == AIPlan.Phase.ASSEMBLE and _assembled(p, now):
		p.set_phase(AIPlan.Phase.ATTACK, now)
		p.window_since = now
	if p.phase == AIPlan.Phase.ATTACK:
		_assign_attack(p, now)
		return
	# Waiting: at the assembly point if there is one; otherwise each holds where it is (or where the
	# last attack left it), and one with a route of its own keeps to it (_strike_move).
	for u in p.members_in("strike"):
		if p.assembly.is_finite():
			p.goals[u.id] = p.assembly
		elif not p.goals.has(u.id) and (not u.is_aircraft() or u.airborne()):
			p.goals[u.id] = u.position


## The contact the strike is for: the classified hostile highest on the plan's list, nearest the
## objective among equals. The present target is kept unless something strictly higher appears,
## so two carriers do not have the strike swinging between them. A contact this side's own plot
## shows destroyed is no longer wanted.
func _plan_target(p: AIPlan) -> Track:
	var reference := p.objective if p.objective.is_finite() else p.own_side
	var best: Track = null
	var best_rank := 1 << 30
	var best_d := INF
	var current: Track = null
	var current_rank := 1 << 30
	for t: Track in track_manager.get_tracks(faction):
		if t.status == Track.Status.LOST or t.identity != "HOSTILE" or t.damage_estimate >= 100.0:
			continue
		var rank := p.priority_rank(t)
		if rank < 0:
			continue
		if t.id == p.target_track_id:
			current = t
			current_rank = rank
		var d := t.position.distance_to(reference) if reference.is_finite() else 0.0
		if rank < best_rank or (rank == best_rank and d < best_d):
			best = t
			best_rank = rank
			best_d = d
	if current != null and current_rank <= best_rank:
		return current
	return best


func _strike_centre(p: AIPlan) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for u in p.members_in("strike"):
		sum += u.position
		n += 1
	return sum / float(n) if n > 0 else Vector2.INF


## A striker that can take part in this attack at all: armed against the target and, for an
## aircraft, not committed to the deck cycle or to going home. Installations cannot manoeuvre to
## an assembly point or an axis, so they fire from where they are and are not waited for.
func _could_strike(u: Unit, t: Track) -> bool:
	if not u.alive or u.spec.max_speed_kn <= 0.0 or t == null or u.weapons_for_track(t).is_empty():
		return false
	if u.is_aircraft():
		return u.flight_state in [Unit.FlightState.STOWED, Unit.FlightState.LAUNCHING, Unit.FlightState.AIRBORNE] and not u.returning
	return true


## On the chart and free to go where the plan sends it.
static func _in_hand(u: Unit) -> bool:
	return not u.is_aircraft() or (u.airborne() and not u.returning and u.tanking_on == null)


static func _package_needed(p: AIPlan, potential: int) -> int:
	return mini(p.package if p.package > 0 else potential, potential)


func _assembled(p: AIPlan, now: float) -> bool:
	if now - p.phase_since >= p.assembly_window_s:
		return true  # the window has closed: go with what has arrived
	var potential := 0
	var ready := 0
	for u in p.members_in("strike"):
		if not _could_strike(u, p.target):
			continue
		potential += 1
		if _in_hand(u) and u.position.distance_to(_sea_room(u, p.assembly)) <= ASSEMBLY_RADIUS_NM:
			ready += 1
	return potential > 0 and ready >= _package_needed(p, potential)


## Each striker approaches on its own bearing from the target, so the rounds arrive from several
## directions at once. Weapons are free once enough shooters are on their axes, or once the window
## closes. Each uses the target as its own picture holds it; one that has lost the link keeps the
## last point it was given.
func _assign_attack(p: AIPlan, now: float) -> void:
	var strikers: Array[Unit] = []
	for u in p.members_in("strike"):
		if u.spec.max_speed_kn > 0.0:
			strikers.append(u)  # an installation shoots from where it stands; it takes no bearing
	for u in strikers:
		if not p.axes.has(u.id):
			p.axes[u.id] = fposmod(p.base_axis_deg + p.axis_offset(p.axes.size(), strikers.size()), 360.0)
	var potential := 0
	var ready := 0
	for u in strikers:
		var view := _held_track(u, p.target_track_id)
		if view == null:
			continue
		var ip := _attack_point(u, view, float(p.axes[u.id]))
		p.goals[u.id] = ip
		if not _could_strike(u, view):
			continue
		potential += 1
		# A ship whose point is ashore is in position at the water nearest it.
		if _in_hand(u) and u.position.distance_to(_sea_room(u, ip)) <= maxf(IP_ARRIVAL_NM, 0.15 * view.position.distance_to(ip)):
			ready += 1
	if not p.weapons_free and (now - p.window_since >= p.assembly_window_s or (potential > 0 and ready >= _package_needed(p, potential))):
		p.weapons_free = true


## A point on the attack bearing inside the shooter's best weapon envelope. A slow missile that
## would take longer than MAX_TIME_OF_FLIGHT_S to reach a moving ship is brought in closer.
func _attack_point(u: Unit, t: Track, axis_deg: float) -> Vector2:
	var weapons := u.weapons_for_track(t)
	var standoff := _shadow_standoff(u)
	if not weapons.is_empty():
		var spec: WeaponSpec = weapons[0]
		standoff = ENGAGE_STANDOFF_FRACTION * Combat.effective_range_nm(u, spec)
		if not _is_fixed_target(t) and spec.speed_kn > 0.0:
			standoff = minf(standoff, 0.9 * Geo.knots_to_nm_per_s(spec.speed_kn) * MAX_TIME_OF_FLIGHT_S)
	return t.position + Geo.heading_to_vector(axis_deg) * standoff


## Escorts keep stations round the ship they protect: ahead first, then the bows and the quarters.
func _assign_screen(p: AIPlan) -> void:
	var g := p.guard()
	for u in p.members_in("escort"):
		if not p.axes.has(u.id):
			p.axes[u.id] = AIPlan.SCREEN_AXES_DEG[p.axes.size() % AIPlan.SCREEN_AXES_DEG.size()]
		if g != null:
			p.goals[u.id] = g.position + Geo.heading_to_vector(g.heading_deg + float(p.axes[u.id])) * p.screen_nm


## Defenders hold stations spread round the installation, inside the defended area.
func _assign_guard(p: AIPlan) -> void:
	p.anchor = p.objective
	if not p.anchor.is_finite():
		for u in p.members_in("installation"):
			p.anchor = u.position
			break
	if not p.anchor.is_finite():
		return
	var defenders: Array[Unit] = []
	for u in p.members_in("defender"):
		if u.spec.max_speed_kn > 0.0:
			defenders.append(u)
	var ring := minf(p.area_radius_nm * 0.5, p.leash_nm * 0.8)
	for u in defenders:
		if not p.axes.has(u.id):
			p.axes[u.id] = fposmod(360.0 * float(p.axes.size()) / float(defenders.size()), 360.0)
		p.goals[u.id] = p.anchor + Geo.heading_to_vector(float(p.axes[u.id])) * ring


## Scouts go first. A designated scout aircraft is launched from wherever it is stowed; a
## surveillance airframe the plan has only because it owns the deck goes up one at a time.
func _launch_scouts(p: AIPlan, now: float) -> void:
	for a in p.members_in("recon"):
		if not a.is_aircraft() or not a.ready_to_launch() or a.home == null or not a.home.alive:
			continue
		var host := a.home
		if not p.recon_callsigns.has(a.callsign) and _has_airborne(host, func(x: Unit) -> bool: return p.role_of(x) == "recon"):
			continue
		if _flown_by_recon_mission(p, a):
			continue  # the plan's air reconnaissance from this deck flies these, with its own relief
		var hb := _board(host)
		if now - float(hb.get("last_launch", -10000.0)) < LAUNCH_INTERVAL_S / float(maxi(host.spec.launch_capacity(), 1)):
			continue
		_send(host, hb, a.callsign, 1, now)


## An air reconnaissance mission over the objective, flown by the deck's own mission machinery
## under the same fuel, deck and identification rules as the player's. A strike plan asks only
## while it is still looking; asked again if the mission has ended and nothing has been found.
func _request_air_recon(p: AIPlan, now: float) -> void:
	if p.recon_air.is_empty() or not p.objective.is_finite():
		return
	if p.is_strike_kind() and p.phase != AIPlan.Phase.RECON:
		return
	for i in p.recon_air.size():
		var entry: Dictionary = p.recon_air[i]
		var last: float = p.recon_requested[i]
		if last > AIPlan.UNSET_TIME and (now - last < RECON_RETRY_S or _recon_aloft(entry)):
			continue
		var base := _own_unit(str(entry["base"]))
		if base == null:
			continue
		p.recon_requested[i] = now
		unit_manager.issue_order(base, Order.air_mission(AirMission.Kind.RECON, str(entry["platform"]), int(entry["count"]), p.objective, p.area_radius_nm, null, true))


## An airframe of a type the plan has asked its deck to fly a reconnaissance mission with. Sent up
## as a scout as well, it would fly the same search twice and leave the mission short of a relief.
static func _flown_by_recon_mission(p: AIPlan, a: Unit) -> bool:
	for entry: Dictionary in p.recon_air:
		if a.home != null and str(entry["base"]) == a.home.callsign and str(entry["platform"]) == a.spec.id:
			return true
	return false


func _recon_aloft(entry: Dictionary) -> bool:
	if air_mission_manager == null:
		return true  # nobody to ask; do not keep re-ordering
	for m in air_mission_manager.active_missions(faction):
		if m.kind == AirMission.Kind.RECON and m.base_callsign == str(entry["base"]) and m.platform_id == str(entry["platform"]):
			return true
	return false


func _own_unit(callsign: String) -> Unit:
	for u in unit_manager.get_faction_units(faction):
		if u.callsign == callsign:
			return u
	return null


## The track with this id in the unit's own picture: the shared plot on the link, its own off it.
func _held_track(u: Unit, track_id: String) -> Track:
	if track_id == "":
		return null
	for t: Track in track_manager.tracks_for(u):
		if t.id == track_id and t.status != Track.Status.LOST:
			return t
	return null


## {plan, role} for a plan member once its plan is running, else empty.
func _plan_task(u: Unit) -> Dictionary:
	for p in plans:
		if not p.has_member(u):
			continue
		if not p.running():
			return {}
		var role := p.role_of(u)
		if role == "strike" and not p.is_strike_kind():
			return {}  # a screen or a defence has no strike to join: it fights on its own judgement
		if role == "escort" and p.guard() == null:
			return {}  # nothing left to screen: the escort fights as it would on its own
		if role == "defender" and not p.anchor.is_finite():
			return {}  # nothing to defend: no objective and no installation left
		return {"plan": p, "role": role}
	return {}


## A deck the plan owns launches for the plan. Scouts go up through _launch_scouts; armed
## airframes go only at what the plan is after, never at whatever contact happens to be held.
func _plan_launch(u: Unit, b: Dictionary, task: Dictionary, hostiles: Array, now: float) -> void:
	if u.spec.aircraft_capacity <= 0:
		return
	var ready := u.stowed_aircraft()
	if ready.is_empty():
		return
	var spots := maxi(u.spec.launch_capacity(), 1)
	if now - float(b.get("last_launch", -10000.0)) < LAUNCH_INTERVAL_S / float(spots):
		return
	var p: AIPlan = task["plan"]
	if _has_airborne(u, func(x: Unit) -> bool: return x.spec.can_refuel):
		for a: Unit in ready:
			if a.spec.tanker_offload_s > 0.0 and not _has_airborne(u, func(x: Unit) -> bool: return x.is_tanker()):
				_send(u, b, a.callsign, 1, now)
				return
	for t: Track in _plan_air_targets(p, hostiles):
		var wanted := 1 if t.domain == "subsurface" else mini(spots, PACKAGE_MAX)
		if p.is_strike_kind() and p.package > 0:
			wanted = mini(wanted, p.package - _plan_aircraft_aloft(p))
			if wanted <= 0:
				return  # the package is up
		for a: Unit in ready:
			var role := p.role_of(a)
			if role == "" or role == "recon":
				continue
			if a.can_engage_domain(t.domain) and not a.weapons_for_track(t).is_empty():
				_send(u, b, a.callsign, wanted, now)
				return


## What a plan's armed aircraft are launched at: the strike's target once it is found, contacts
## inside a defended area, contacts closing on the ship a screen protects.
func _plan_air_targets(p: AIPlan, hostiles: Array) -> Array:
	var out: Array = []
	match p.kind:
		AIPlan.Kind.PROTECT_BREAKOUT:
			for t: Track in hostiles:
				if t.status == Track.Status.ACTIVE and p.near_protected(t.position, p.engage_within_nm):
					out.append(t)
		AIPlan.Kind.DEFEND_INSTALLATION:
			if p.anchor.is_finite():
				for t: Track in hostiles:
					if t.status == Track.Status.ACTIVE and t.position.distance_to(p.anchor) <= p.area_radius_nm:
						out.append(t)
		_:
			if p.target != null and (p.phase == AIPlan.Phase.ASSEMBLE or p.phase == AIPlan.Phase.ATTACK):
				out.append(p.target)
	return out


func _plan_aircraft_aloft(p: AIPlan) -> int:
	var n := 0
	for a in p.members:
		if a.alive and a.is_aircraft() and p.role_of(a) == "strike" and a.flight_state in [Unit.FlightState.LAUNCHING, Unit.FlightState.AIRBORNE] and not a.returning:
			n += 1
	return n


## Where a contact stands for a plan member deciding whether to shoot: 0 for what the plan exists
## for, higher for lesser targets, THREAT_BUCKET for something the plan does not want that has come
## within threat_nm of this member, and -1 for anything else, however near.
func _plan_bucket(u: Unit, t: Track, task: Dictionary) -> int:
	var p: AIPlan = task["plan"]
	var threat := u.position.distance_to(t.position) <= p.threat_nm
	match task["role"]:
		"strike":
			if p.phase == AIPlan.Phase.ATTACK and p.weapons_free:
				if t.id == p.target_track_id:
					return 0
				var rank := p.priority_rank(t)
				if rank >= 0:
					return 1 + rank
		"escort":
			if p.near_protected(t.position, p.engage_within_nm):
				return 0
		"defender":
			if p.anchor.is_finite() and t.position.distance_to(p.anchor) <= p.area_radius_nm:
				return 0
	return THREAT_BUCKET if threat else -1


func _choose_plan_state(u: Unit, b: Dictionary, hostiles: Array, unknowns: Array, inbound: Array, now: float, task: Dictionary) -> State:
	var p: AIPlan = task["plan"]
	var role: String = task["role"]
	if _plan_should_withdraw(u, hostiles, role):
		return State.WITHDRAW
	if not inbound.is_empty():
		return State.DEFEND
	if not _pick_engagement(u, b, hostiles, now, task).is_empty():
		return State.ENGAGE
	match role:
		"strike":
			if _strike_searching(u, p, now):
				return State.SCOUT
			return State.APPROACH if p.phase == AIPlan.Phase.ATTACK else State.HOLD
		"recon":
			return State.SCOUT
		"escort":
			return State.SCREEN
		"defender":
			if _intruder(p, hostiles) != null:
				return State.SHADOW
			if _intruder(p, unknowns) != null:
				return State.INVESTIGATE
			return State.GUARD
	return State.HOLD


## A striker leaves when it is crippled or has nothing left for what is out there, as any ship
## would. A scout, an escort and a defender stay while they float: an empty launcher does not end
## a screen or a search.
func _plan_should_withdraw(u: Unit, hostiles: Array, role: String) -> bool:
	if role == "strike":
		return _should_withdraw(u, hostiles)
	return not u.is_aircraft() and Damage.health_fraction(u) < WITHDRAW_HEALTH_FRACTION


func _act_plan(u: Unit, b: Dictionary, hostiles: Array, unknowns: Array, inbound: Array, now: float, task: Dictionary) -> void:
	match b["state"]:
		State.DEFEND:
			_do_defend(u, b, inbound, now)
		State.WITHDRAW:
			_do_withdraw(u, b, hostiles, now)
		State.ENGAGE:
			# Shoot, and stay where the plan wants the ship: on its axis, on the screen, on guard.
			var weapon := _plan_fire(u, b, hostiles, now, task)
			_plan_move(u, b, task, hostiles, unknowns, now, true)
			if weapon != null:
				_manage_depth(u, DepthIntent.TRACK if weapon.is_torpedo() else DepthIntent.MISSILE_SHOT)
		_:
			_plan_move(u, b, task, hostiles, unknowns, now, false)


func _plan_fire(u: Unit, b: Dictionary, hostiles: Array, now: float, task: Dictionary) -> WeaponSpec:
	var pick := _pick_engagement(u, b, hostiles, now, task)
	if pick.is_empty():
		return null
	var t: Track = pick["track"]
	var weapon: WeaponSpec = pick["weapon"]
	_manage_emissions(u, true)
	if not unit_manager.issue_order(u, Order.engage(t, weapon.id, pick["salvo"])):
		return null  # refused: nothing left, so no cooldown and no volley
	b["target"] = t
	b["engaged"][t.id] = now
	var flight := Combat.time_of_flight_s(weapon, u.position.distance_to(t.position))
	b["cooldown_%s" % t.id] = maxf(ENGAGE_COOLDOWN_S, flight * 1.5)
	var p: AIPlan = task["plan"]
	p.note_salvo(t.id, flight, now)
	return weapon


func _plan_move(u: Unit, b: Dictionary, task: Dictionary, hostiles: Array, unknowns: Array, now: float, engaging: bool) -> void:
	match task["role"]:
		"strike":
			_strike_move(u, b, task, now, engaging)
		"recon":
			_scout(u, b, task, now)
		"escort":
			_screen(u, b, task, now)
		"defender":
			_guard(u, b, task, hostiles, unknowns, now, engaging)


## A striker goes where the plan has put it: while the target is sought, the assembly point, or
## where it was (keeping to a route of its own if it has one); once found, its point on its attack
## axis. It keeps quiet until it shoots.
func _strike_move(u: Unit, b: Dictionary, task: Dictionary, now: float, engaging: bool) -> void:
	var p: AIPlan = task["plan"]
	if _strike_searching(u, p, now):
		_scout(u, b, task, now)
		return
	_manage_emissions(u, engaging)
	if not engaging:
		_manage_depth(u, DepthIntent.HIDE)
	if p.phase == AIPlan.Phase.ATTACK:
		var view := _held_track(u, p.target_track_id)
		b["target"] = view
		# An aircraft that has spent everything it carried for this target is done; home it goes.
		var engaged: Dictionary = b["engaged"]
		if u.is_aircraft() and view != null and not engaged.is_empty() and u.weapons_for_track(view).is_empty():
			unit_manager.issue_order(u, Order.return_to_base())
			return
	elif not p.assembly.is_finite() and not u.patrol_route.is_empty():
		if not engaging:
			_do_patrol(u, b, now)  # its own standing route, until there is something to attack
		return
	var goal: Vector2 = p.goals.get(u.id, Vector2.INF)
	if goal.is_finite():
		_hold_point(u, b, goal, now)


## The search has run out its window with nothing the plan wants classified, so this striker
## stops holding and searches the objective area itself. One keeping to a route of its own (with no
## assembly point to hold) stays on it: the author's route is already where it is meant to look.
func _strike_searching(u: Unit, p: AIPlan, now: float) -> bool:
	return p.searching_in_force(now) and (p.assembly.is_finite() or u.patrol_route.is_empty())


## A scout keeps the plan's target in sight once it is found, so the strike's rounds get their
## mid-course updates; until then it closes on the unclassified contact likeliest to be what the
## plan wants, and with nothing to look at it sweeps the area.
func _scout(u: Unit, b: Dictionary, task: Dictionary, now: float) -> void:
	var p: AIPlan = task["plan"]
	_manage_emissions(u, true)
	_manage_depth(u, DepthIntent.TRACK)
	var look := _held_track(u, p.target_track_id)
	if look == null:
		look = _scout_pick(u, p)
	if look != null:
		_scout_close(u, b, look, _scout_standoff(u), now)
		return
	b["target"] = null
	# With no objective authored, round its own deck, else round the strike's own side: a fixed
	# centre, so the legs do not wander off with the unit flying them.
	var centre := p.objective
	if not centre.is_finite():
		centre = u.home.position if u.home != null else p.own_side
	if not centre.is_finite():
		centre = u.position
	_sweep(u, b, centre, p.area_radius_nm * SWEEP_FRACTION, now)


## The unclassified contact a scout should look at first. Only what the plot holds: where it is
## against the expected area, whether it is on the surface, how fast it goes. Never what it is.
func _scout_pick(u: Unit, p: AIPlan) -> Track:
	var best: Track = null
	var best_score := INF
	for t: Track in track_manager.tracks_for(u):
		if t.status != Track.Status.ACTIVE or t.identity != "UNKNOWN" or t.classification >= Track.Classification.CLASS_KNOWN or t.is_bearing_only():
			continue
		if p.is_strike_kind() and not _surface_candidate(t):
			continue
		var score := 0.5 * u.position.distance_to(t.position)
		if p.objective.is_finite():
			var off := t.position.distance_to(p.objective)
			if off > p.area_radius_nm * SCOUT_AREA_MARGIN:
				continue
			score += off
		if p.kind == AIPlan.Kind.ATTACK_SHIPPING and t.has_kinematics and t.speed_kn < SLOW_CONTACT_KN:
			score -= SLOW_CONTACT_BONUS_NM
		if score < best_score:
			best = t
			best_score = score
	return best


## A ship target as far as the plot can tell: on the surface, or not yet placed in any medium and
## not seen at altitude.
static func _surface_candidate(t: Track) -> bool:
	if t.domain != "":
		return t.domain == "surface"
	return t.altitude_m <= AirMissionManager.AIRBORNE_ALTITUDE_M


## Close enough to classify, or to hold: a scout's radar ring, not its weapons, sets the distance.
func _scout_standoff(u: Unit) -> float:
	var ring := Detection.nominal_passive_ring_nm(u) if u.is_submarine() else Detection.nominal_radar_ring_nm(u)
	if ring <= 0.0:
		return _shadow_standoff(u)
	return maxf(CLASSIFY_STANDOFF_FRACTION * ring, 8.0)


func _scout_close(u: Unit, b: Dictionary, t: Track, standoff_nm: float, now: float) -> void:
	# A patrol aircraft with buoys is not sent over a ship to drop them on it: that is for a boat.
	if u.is_aircraft() and not (t.domain == "subsurface" and _is_asw_airframe(u)):
		b["target"] = t
		_manage_altitude(u, false)
		if u.position.distance_to(t.position) <= standoff_nm:
			_command(u, b, Geo.vector_to_heading(u.position - t.position), u.spec.cruise_speed_kn, now)
			return
		_move_to(u, b, _standoff_point(u, t.position, standoff_nm), now)
		return
	_do_close(u, b, [t], standoff_nm, now)


## Legs through an area: its centre first, then round it.
func _sweep(u: Unit, b: Dictionary, centre: Vector2, radius_nm: float, now: float) -> void:
	_manage_altitude(u, false)
	if u.has_route() and b.has("sweep_leg") and b["sweep_leg"] == b["goal"]:
		return  # still on the way to the last sweep leg
	var index := int(b.get("sweep_index", 0))
	b["sweep_index"] = index + 1
	var leg := centre
	if index > 0:
		leg = centre + Geo.heading_to_vector(fmod(float(index - 1) * SEARCH_STEP_DEG, 360.0)) * radius_nm
	_move_to(u, b, leg, now)
	b["sweep_leg"] = b["goal"]


## Keep station on the ship being protected. Contacts are engaged from the screen (_plan_bucket);
## a distraction off to one side is not chased, because the screen is where the escort is needed.
func _screen(u: Unit, b: Dictionary, task: Dictionary, now: float) -> void:
	var p: AIPlan = task["plan"]
	_manage_emissions(u, true)  # the screen's radar is part of what it lends the ship it guards
	_manage_depth(u, DepthIntent.TRACK)
	var g := p.guard()
	var point: Vector2 = p.goals.get(u.id, Vector2.INF)
	if g == null or not point.is_finite():
		return
	b["target"] = null
	if u.is_aircraft():
		_orbit(u, b, point, ORBIT_RADIUS_NM, now)
		return
	var gap := u.position.distance_to(point)
	if gap <= SCREEN_TOLERANCE_NM:
		_command(u, b, g.heading_deg, g.speed_kn, now)
		return
	# Gain on a guide still under way without overshooting the station.
	var speed := clampf(g.speed_kn + gap * SCREEN_GAIN_KN_PER_NM, u.spec.cruise_speed_kn, u.effective_max_speed())
	_command(u, b, _open_bearing(u, Geo.bearing_deg(u.position, point)), speed, now)


## Hold a station round the installation; close on what comes into the defended area, but never
## further from the installation than the leash; and come back once past it, whatever is out there.
func _guard(u: Unit, b: Dictionary, task: Dictionary, hostiles: Array, unknowns: Array, now: float, engaging: bool) -> void:
	var p: AIPlan = task["plan"]
	var station: Vector2 = p.goals.get(u.id, Vector2.INF)
	if not p.anchor.is_finite() or not station.is_finite():
		return
	var intruder := _intruder(p, hostiles)
	var stranger: Track = _intruder(p, unknowns) if intruder == null else null
	_manage_emissions(u, engaging or intruder != null or stranger != null)
	var close_on: Track = intruder if intruder != null else stranger
	if close_on == null or u.position.distance_to(p.anchor) > p.leash_nm:
		b["target"] = null
		_manage_depth(u, DepthIntent.HIDE)
		_hold_point(u, b, station, now)
		return
	b["target"] = close_on
	_manage_depth(u, DepthIntent.TRACK)
	var standoff := _shadow_standoff(u) if intruder != null else _scout_standoff(u)
	var point := _standoff_point(u, close_on.position, standoff)
	_hold_point(u, b, p.anchor + (point - p.anchor).limit_length(p.leash_nm), now)


## The contact nearest the installation inside the defended area, or null.
func _intruder(p: AIPlan, tracks: Array) -> Track:
	if not p.anchor.is_finite():
		return null
	var best: Track = null
	var best_d := INF
	for t: Track in tracks:
		var d := t.position.distance_to(p.anchor)
		if d <= p.area_radius_nm and d < best_d:
			best = t
			best_d = d
	return best


## Go to a point and stay there: a ship stops on it, an aircraft flies legs round it. A point
## ashore is held from the water nearest it; judged against the point itself, a ship sitting off
## the beach would never have arrived and would be sent there again every cycle.
func _hold_point(u: Unit, b: Dictionary, point: Vector2, now: float) -> void:
	if u.is_aircraft():
		_orbit(u, b, point, ORBIT_RADIUS_NM, now)
		return
	if u.position.distance_to(_sea_room(u, point)) <= HOLD_TOLERANCE_NM:
		if u.waypoints.is_empty() and u.ordered_speed_kn > 0.5:
			_command(u, b, u.heading_deg, 0.0, now)
		return
	_move_to(u, b, point, now)


func _orbit(u: Unit, b: Dictionary, centre: Vector2, radius_nm: float, now: float) -> void:
	_manage_altitude(u, false)
	if u.has_route() and u.waypoints[-1].distance_to(centre) <= radius_nm + GOAL_TOLERANCE_NM:
		return
	var index := int(b.get("orbit_index", 0))
	b["orbit_index"] = index + 1
	_move_to(u, b, centre + Geo.heading_to_vector(fmod(float(index) * 90.0, 360.0)) * radius_nm, now)


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
	if u.in_formation():
		return  # a consort keeps its station; a steering order would take it out of the formation
	var goal := _sea_room(u, wanted)
	var previous: Vector2 = b["goal"]
	# Re-task only when the destination has actually moved, or when the ship has arrived and is
	# sitting there with nothing to do. Anything else fills the order log with noise.
	if previous != Vector2.INF and previous.distance_to(goal) < GOAL_TOLERANCE_NM and u.has_route():
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
	return Combat.standoff_point(u.position, target_pos, standoff_nm)


func _open_bearing(u: Unit, wanted_deg: float) -> float:
	if not u.needs_sea_room() or Terrain.is_empty():
		return wanted_deg
	return Terrain.open_bearing_deg(u.position, wanted_deg, maxf(u.spec.max_speed_kn, 10.0) * COAST_LOOKAHEAD_S / 3600.0)


func _command(u: Unit, b: Dictionary, course_deg: float, speed_kn: float, now: float) -> void:
	if u.in_formation():
		return  # as _move_to: the formation steers a consort
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
## Rounds of this unit's still flying that its own radar guides: switching it off would kill them.
func _guiding_rounds(u: Unit) -> bool:
	if weapon_manager == null:
		return false
	for w: Weapon in weapon_manager.in_flight:
		if w.shooter == u and w.phase != Weapon.Phase.DEAD and w.spec.requires_radar_support():
			return true
	return false


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
	var want := need_radar or not u.has_esm() or _guiding_rounds(u)
	if want != u.radar_on:
		unit_manager.issue_order(u, Order.activate_radar() if want else Order.silence_radar())
