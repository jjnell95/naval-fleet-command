class_name Unit
extends RefCounted
## Ground-truth simulation entity. Not a Node: owned by UnitManager, rendered by TacticalMap.
## Enemy units are never shown to the player directly; they are perceived via Tracks.

const PERISCOPE_DEPTH_M := 20.0
const HOVER_SPEED_KN := 12.0  # at or below this a helicopter counts as stopped
const HOVER_ALTITUDE_M := 200.0

## STOWED is fit to fly. TURNAROUND is aboard but useless: fuelling, rearming and respotting an
## airframe that has just landed takes longer than the sortie in many cases, and pretending
## otherwise is what lets a single deck fly an unlimited war.
enum FlightState { STOWED, LAUNCHING, AIRBORNE, RECOVERING, TURNAROUND, RESERVE }
enum Emcon { FREE, SILENT }
## What a unit may do without being told. FREE fights, TIGHT defends itself only, HOLD does
## nothing automatically at all.
enum Roe { HOLD, TIGHT, FREE }

const COMPONENTS := ["propulsion", "sensors", "weapons"]
## Weapon choice. A shot inside this fraction of a weapon's reach, and beyond this multiple of its
## minimum range, is one it makes with margin. A surface contact whose reported class is no
## stronger than SMALL_CRAFT_HEALTH is small craft, for the gun. A missile that strikes ashore from
## beyond LAND_ATTACK_REACH_NM is a land-attack cruise missile. GAMEPLAY.
const WEAPON_REACH_MARGIN := 0.9
const WEAPON_MIN_RANGE_MARGIN := 1.1
const SMALL_CRAFT_HEALTH := 30.0
const LAND_ATTACK_REACH_NM := 150.0

var id := -1
var callsign := ""
var faction := ""
var spec: PlatformSpec
var position := Vector2.ZERO  # nm, +x east, +y north
var heading_deg := 0.0
var speed_kn := 0.0
var ordered_heading_deg := 0.0
var ordered_speed_kn := 0.0
var waypoints: Array[Vector2] = []
## Player's repeating circuit, independent of the AI's scenario patrol_route.
var patrol_active := false
var patrol_legs_completed := 0
## The reported contact remains the destination as fresh sensor plots arrive. No truth lookup.
var investigation_track: Track
var investigation_track_id := ""
var investigation_result := ""
var investigation_speed_kn := 0.0
## The investigation only identifies: it never turns into an attack when the contact proves
## hostile (a reconnaissance airframe's look, or a patrol whose mission decides that itself).
var investigation_identify_only := false
## The standing attack: close to weapon range on the held plot, fire, keep firing. UnitManager
## steps it; the fields are the task as the crew would report it. No truth lookup here either.
var attack_track: Track
var attack_track_id := ""
var attack_weapon_id := ""  # a named weapon, or "" for the best one aboard with rounds left
var attack_phase := ""  # "Intercept track", "Engaging track" ... for the ORDERS line
var attack_result := ""  # how the last attack ended, readable until other navigation
var attack_speed_kn := 0.0
var attack_standoff_nm := 0.0  # where the shooter holds once inside the envelope
var attack_rounds_fired := 0
var attack_assess_until_s := -1.0  # a pause between salvos to read the plot again
var attack_stall_s := 0.0  # time held unable to fire; past UnitManager.ATTACK_STALL_S the task ends
var attack_stale_s := 0.0  # uninterrupted time without a fresh plot, even while closing
## The commander gave a speed while the attack ran: it stands for the closing leg and the hold alike.
var attack_speed_ordered := false
## Settled in the range band rather than closing. The band is wider to leave than to enter, so a
## platform at its edge does not hunt between the two.
var attack_holding := false
## Where the platform was at the last attack step, to tell a hull that is making way toward its
## firing point from one that is pressed against a coast with its engines turning.
var attack_progress_pos := Vector2.INF
## What a temporary task interrupted, remembered once when the task takes the steering: the route
## and the ordered speed. Until then an attack fires from wherever the platform's own orders take
## it. A formation or patrol station is not copied here; the station fields keep it.
var plan_kept := false
var plan_waypoints: Array[Vector2] = []
var plan_speed_kn := 0.0
## Where the way a task has laid round a coast ends: the firing point or the plot it was planned
## for. The route stands while the task's goal stays near this, so the search is run again when
## the picture changes and not every tick. Vector2.INF while the platform steers straight.
var nav_goal := Vector2.INF
## How long a hull has been held by a coast without making the way its engines ask for, and
## whether it has stopped and reported it. The report is made once: the mark clears when the hull
## is given somewhere else to go or makes way again.
var coast_blocked_s := 0.0
var coast_blocked := false
## The standing assignment: where this platform belongs when no temporary task holds it. A patrol
## circuit (an air station is one too) or a formation station on a guide. Attack, Investigate,
## evasion and air-to-air refuelling suspend it; an explicit replacement order from the commander (a
## new transit, course, stop, clear, break or landing order) ends it. RETURN_TO_STATION resumes it.
var station_kind := ""  # "" | "patrol" | "formation"
var station_route: Array[Vector2] = []  # the circuit as ordered
var station_leader: Unit  # the guide a formation station is kept on
var station_offset := Vector2.ZERO  # in the guide's frame, as formation_offset
var station_label := ""  # how the orders line names it: "PATROL", "SCREEN STATION", "CAP STATION"
var station_speed_kn := 0.0  # the speed the circuit was ordered at; a return resumes it
var station_note := ""  # why the last return to station could not be made, until the next order
## The air mission that owns this airframe's station, or -1. Cleared with the station, so an order
## from the commander that replaces the station also releases the airframe from the mission.
var station_mission_id := -1
## The station is a reconnaissance mission's: while it holds it, nothing this platform identifies
## is attacked on the crew's initiative (engagement after identification), even on a look the
## commander ordered. Cleared with the station.
var station_identify_only := false
## Go back to the station by itself once an identification, interception or attack ends. Off, the
## platform carries on from where the task ended until it is ordered back.
var auto_return := true
## Bumped by every order that changes where this platform is going. A temporary task remembers the
## generation it started under and hands back to the station only if nothing newer has arrived, so
## a task that completes late can never overwrite a newer order.
var order_generation := 0
var task_generation := -1
## The same count for the commander's orders alone: a crew order (an air mission's) does not move
## it, so a mission can tell when the commander has taken an airframe in hand.
var player_order_generation := 0
var alive := true
## Left the chart for a base off the map. Not alive for the simulation, but not lost either.
var departed := false
## A scenario's own value for this unit on the effectiveness balance sheet; 0 means the
## catalogue default for its category (MissionManager.platform_points).
var points := 0
var sensors: Array[SensorSpec] = []  # resolved from spec.sensor_ids at spawn
var radar_on := true
var active_sonar_on := false
## Saved handling phase and simulation-time countdown for a helicopter dipping set.
var dip_phase := DippingSonar.Phase.STOWED
var dip_timer_s := 0.0
var dip_listen_s := 0.0
## Saved handling state for a ship's streamed array; crew search orders own the cycle.
var array_phase: int = 0
var array_timer_s := 0.0
var array_search_active := false
## Optional submarine communications. Pending orders are plain dictionaries for save continuity.
var comms_enabled := false
var comms_interval_s := 7200.0
var comms_next_check_s := -1.0
var comms_last_report_s := -1.0
var comms_window_until_s := -1.0
var comms_return_depth_m := -1.0
var comms_phase := "submerged"
var comms_pending: Array[Dictionary] = []
var comms_report: Dictionary = {}
var comms_note := ""
## What the crew did on its own initiative while out of touch, held for the next check-in; and the
## last such report the commander has received.
var comms_initiative: Array[String] = []
var comms_initiative_report := ""
## The standing emissions policy. The AI follows it; the player sets it directly. Radiating is
## what gets you found, so this is a real decision rather than a formality.
var emcon: Emcon = Emcon.FREE
var roe: Roe = Roe.FREE
## Battle damage beyond the hull pool. Each runs 1.0 down to 0.0 and degrades what it governs.
var components: Dictionary = {"propulsion": 1.0, "sensors": 1.0, "weapons": 1.0}
## Casualties still being fought, each 0..1. See Damage. A ship can survive a hit and still be lost
## to what the hit started.
var fire := 0.0
var flooding := 0.0
var casualty_time_s := 0.0  # since the parties were last disorganised by a hit
var dc_fortune := 1.0  # how this particular fight is going: drawn per hit, see Damage
var last_attacker := ""  # faction credited if fire or flooding finishes the ship
var formation_leader: Unit
var formation_offset := Vector2.ZERO  # x starboard, y ahead, in nm, in the leader's frame
var formation_axis_deg := -1.0  # negative follows the guide's heading; otherwise a fixed threat axis
var station_axis_deg := -1.0
var depth_m := 0.0
var ordered_depth_m := 0.0
## Diesel-electric boats only (SubmarinePower.fitted). The charge left, 1.0 full; the seconds of
## air-independent running used; whether the snorkel is ordered up; and the depth the boat goes
## back to when the charge is done or the snorkel is secured (negative: none remembered).
var battery := 1.0
var aip_used_s := 0.0
var snorkel_on := false
var snorkel_return_depth_m := -1.0
## How the last snorkel ended ("charged", "secured: evading"), for the data display.
var snorkel_note := ""
## A boat's habit of clearing its baffles: every this many seconds on a steady course it swings off
## it for a look astern (Movement). Zero is no habit. The AI's captains set it while they patrol or
## search; the clock runs with the boat.
var baffle_clear_interval_s := 0.0
var baffle_clock_s := 0.0
## Water under the hull, cached by Acoustics.bottom_m() until the unit moves or the chart changes.
var bottom_depth_m := -1.0
var bottom_sampled_at := Vector2.INF
var bottom_generation := -1
var health := 100.0
var weapons: Array[WeaponSpec] = []  # resolved from spec.weapon_loadout at spawn
var magazines: Dictionary = {}  # weapon id -> rounds remaining
var sortie_loadout: Dictionary = {}  # authored aircraft fit, retained on every turnaround
var aviation_stores: Dictionary = {}  # host reload rounds, separate from its own launchers
var aviation_buoys := 0
var decoys := 0
var auto_countermeasures := true
## Area and point SAMs engage inbound missiles by themselves. Off (manual missile defence), they
## fire only at rounds the commander has ordered intercepted (Weapon.intercept_cleared); the
## close-in guns, chaff and flares keep their own rules either way.
var auto_air_defence := true
var defence_policy := "balanced"  # balanced | conserve | saturation
var defence_priority := 0
## A fixed-wing aircraft flying a hold that Movement laid because it had nowhere to go (see
## Movement.enter_hold), and the point the hold is through. The hold is not a route of its own.
var hold_active := false
var hold_point := Vector2.ZERO
## Fighters this deck holds on ready alert, launched by the deck itself into a CAP toward a hostile
## raid when one appears (AirMissionManager). 0 is no alert. Spent by the scramble.
var ready_alert := 0
var countermeasure_kind := ""
var countermeasure_generation := 0
var countermeasure_remaining_s := 0.0
var countermeasure_reload_s := 0.0
var evasion_remaining_s := 0.0
var evasion_course_deg := 0.0
var evasion_start_heading_deg := 0.0
var formation_speed_cap_kn := INF
var torpedo_decoys := 0  # expendable acoustic decoys left
var patrol_route: Array[Vector2] = []  # standing orders from the scenario, used by the AI
## How the AI is meant to play this ship. "standard" fights and withdraws on its own judgement.
## "breakout" has somewhere to be: it presses on down its patrol route, shooting as it goes, and
## does not break off because its magazines are empty.
var ai_posture := "standard"
## The scenario's opposing-force plan this unit belongs to (AIPlan.id), and the part it plays in it
## when not the plan's default. Authored, so a reinforcement wave can join a plan already running.
var ai_plan_id := ""
var ai_role := ""

## Aviation. An aircraft exists from scenario load but sits in its hangar until launched, so the
## player can see what is available without those airframes being on the board.
var flight_state: FlightState = FlightState.STOWED
var altitude_m := 0.0
var ordered_altitude_m := 0.0
var fuel_s := 0.0
var home_callsign := ""
var home: Unit
## Chosen landing destination, reserved while returning; home changes only after touchdown.
var recovery_base: Unit
var state_timer_s := 0.0
var sonobuoys := 0
var returning := false
var completed_sorties := 0
var completed_sorties_by_facility: Dictionary = {}
## Squadron or detachment the airframe belongs to, for the roster and the recognition panel.
var squadron := ""
## The tanker this aircraft is currently joining on, if any. Set by the aviation layer when a
## receiver decides it can reach a basket instead of the deck.
var tanking_on: Unit
var tanker_offload_s := 0.0  # give remaining, in receiver endurance-seconds


## Flying a hold Movement laid for want of orders, not a route anyone gave it.
func holding() -> bool:
	return hold_active and not waypoints.is_empty() and waypoints.back() == hold_point


## Has somewhere to go that someone chose: a hold laid for want of orders does not count, so
## whatever is deciding the next leg (the AI, a stalled task) still sees this unit as idle.
func has_route() -> bool:
	return not waypoints.is_empty() and not holding()


func is_aircraft() -> bool:
	return spec.domain == "air"


func airborne() -> bool:
	return is_aircraft() and flight_state == FlightState.AIRBORNE


## Physical flight includes final approach, while airborne() means available for mission orders.
func in_flight() -> bool:
	return is_aircraft() and flight_state in [FlightState.AIRBORNE, FlightState.RECOVERING]


## Fit to be sent off the deck right now. An airframe still being turned round is aboard and
## alive but is not a sortie you have.
func ready_to_launch() -> bool:
	return alive and is_aircraft() and flight_state == FlightState.STOWED


## Carries give for someone else, and still has some left.
func is_tanker() -> bool:
	return spec.tanker_offload_s > 0.0 and tanker_offload_s > 0.0


## An airframe whose whole contribution is what it can see: early warning aircraft, maritime
## patrol drones, the small shipboard machines with a camera and nothing else. These are worth
## launching before anything is wrong, which is the opposite of how an armed airframe is used.
func is_sensor_aircraft() -> bool:
	return is_aircraft() and weapons.is_empty() and not sensors.is_empty()


## On the board: something a sensor could find or a weapon could hit. An aircraft in a hangar is
## none of those things.
func is_engageable() -> bool:
	return alive and (not is_aircraft() or in_flight())


func is_hovering() -> bool:
	return airborne() and spec.can_hover and speed_kn <= HOVER_SPEED_KN and altitude_m <= HOVER_ALTITUDE_M


func fuel_fraction() -> float:
	return clampf(fuel_s / maxf(spec.endurance_s, 1.0), 0.0, 1.0)


## Aircraft still in the hangar and fit to fly. An airframe in turnaround is deliberately not
## here: it is aboard, but it is not something you can launch.
func stowed_aircraft() -> Array[Unit]:
	var out: Array[Unit] = []
	for a in embarked:
		if a.ready_to_launch():
			out.append(a)
	return out


## Airframes aboard being refuelled, rearmed and respotted. The deck cycle made visible.
func turnaround_aircraft() -> Array[Unit]:
	var out: Array[Unit] = []
	for a in embarked:
		if a.alive and a.flight_state == FlightState.TURNAROUND:
			out.append(a)
	return out


## Airframes off this deck and on the board right now.
func airborne_aircraft() -> Array[Unit]:
	var out: Array[Unit] = []
	for a in embarked:
		if a.alive and a.flight_state in [FlightState.LAUNCHING, FlightState.AIRBORNE, FlightState.RECOVERING]:
			out.append(a)
	return out


## Spots in use at each end of the cycle, which is what bounds how fast a deck can work.
func launch_spots_busy() -> int:
	var n := 0
	for a in embarked:
		if a.alive and a.flight_state == FlightState.LAUNCHING:
			n += 1
	return n


func recovery_spots_busy() -> int:
	var n := 0
	for a in embarked:
		if a.alive and a.flight_state == FlightState.RECOVERING and (a.recovery_base == null or a.recovery_base == self):
			n += 1
	for a in inbound_aircraft:
		if a.alive and a.home != self and a.recovery_base == self and a.flight_state == FlightState.RECOVERING:
			n += 1
	return n


var inbound_aircraft: Array[Unit] = []  # landing reservations from other decks or fields
var embarked: Array[Unit] = []  # aircraft that call this unit home


func component(name: String) -> float:
	return float(components.get(name, 1.0))


## A damaged plant still turns the screws, just not as fast, and water aboard slows her further.
func effective_max_speed() -> float:
	return spec.max_speed_kn * (0.35 + 0.65 * component("propulsion")) * (1.0 - Damage.FLOOD_SPEED_LOSS * flooding)


## Damaged arrays and antennas shorten every sensor aboard.
func sensor_efficiency() -> float:
	return 0.25 + 0.75 * component("sensors")


## Below this the launchers and directors are too badly knocked about to fire.
func can_fire() -> bool:
	return component("weapons") > 0.25


func magazine_count(weapon_id: String) -> int:
	return int(magazines.get(weapon_id, 0))


func consume_magazine(weapon_id: String, rounds: int) -> void:
	magazines[weapon_id] = maxi(magazine_count(weapon_id) - rounds, 0)


func get_weapon(weapon_id: String) -> WeaponSpec:
	for w in weapons:
		if w.id == weapon_id:
			return w
	return null


func offensive_weapons() -> Array[WeaponSpec]:
	var out: Array[WeaponSpec] = []
	for w in weapons:
		if w.target_types.has("surface"):
			out.append(w)
	return out


## Whether anything aboard could engage a contact in this domain, magazines aside. An ASW
## helicopter has no business chasing a jet, and this is what stops it.
func can_engage_domain(domain: String) -> bool:
	if domain == "":
		return true  # an unidentified contact is worth closing on to find out what it is
	for w in weapons:
		if w.target_types.has(domain):
			return true
	return false


## Weapons with rounds left that can engage a given track, in the order a captain would reach
## for them, judged from the plot alone: the reported class (through it the catalogue's hull
## strength), the domain and the range. A weapon that reaches with margin comes before one that
## does not; among those, the kind meant for the target comes first, and the cheapest of a kind,
## which is the shortest-ranged round, before a dearer one. A gun leads against small craft inside
## its reach. Out of reach, the longest reach leads, so the platform closes for the nearest shot.
## Against aircraft the outer layer leads, as before, so the inner one keeps a second chance.
func weapons_for_track(t: Track) -> Array[WeaponSpec]:
	var out: Array[WeaponSpec] = []
	for w in weapons:
		if magazine_count(w.id) > 0 and Combat.suits_track(w, t):
			out.append(w)
	if t.domain == "air" or out.size() < 2:
		out.sort_custom(func(a: WeaponSpec, c: WeaponSpec) -> bool:
			if a.is_gun() != c.is_gun():
				return c.is_gun()
			return a.max_range_nm > c.max_range_nm)
		return out
	var range_nm := position.distance_to(t.position) if t.position.is_finite() else INF
	var small := t.domain == "surface" and TrackManager.assessed_health(t) <= SMALL_CRAFT_HEALTH
	var keys := {}
	for w in out:
		var reaches := weapon_reaches(w, range_nm)
		var reach := Combat.effective_range_nm(self, w)
		keys[w] = [0 if reaches else 1, _weapon_tier(w, t.domain, small and reaches), reach if reaches else -reach, w.damage, w.id]
	out.sort_custom(func(a: WeaponSpec, c: WeaponSpec) -> bool:
		var ka: Array = keys[a]
		var kc: Array = keys[c]
		for i in ka.size():
			if ka[i] != kc[i]:
				return ka[i] < kc[i]
		return false)
	return out


## Whether a round reaches this range with margin: inside the fraction of its reach a captain
## trusts and clear of its minimum range.
func weapon_reaches(w: WeaponSpec, range_nm: float) -> bool:
	var reach := Combat.effective_range_nm(self, w)
	return range_nm <= reach * WEAPON_REACH_MARGIN and range_nm >= Combat.minimum_range_nm(w) * WEAPON_MIN_RANGE_MARGIN


## How well a kind of weapon suits a kind of target, best first. WeaponSpec carries no role, so it
## is read from what the data does say: a missile that strikes inland from beyond
## LAND_ATTACK_REACH_NM is a land-attack cruise missile, which a ship gets only after a ship-killer;
## a lightweight torpedo and an ASW rocket are anti-submarine weapons, which a ship gets last.
func _weapon_tier(w: WeaponSpec, domain: String, gun_on_small_craft: bool) -> int:
	if w.is_gun():
		return 0 if gun_on_small_craft else 3
	match domain:
		"surface":
			if w.is_anti_radiation():
				return 2
			if w.is_torpedo():
				return 1 if w.is_heavyweight_torpedo() else 4
			if w.type == "asw_rocket":
				return 4
			if w.target_types.has("land") and w.max_range_nm >= LAND_ATTACK_REACH_NM:
				return 2
			return 1
	return 1


## The rounds the standing attack sends at a contact with this weapon: enough to finish what the
## plot says is left of it, never more than the weapon's default salvo or the magazine holds. What
## is left is the catalogue strength of the reported class (a generic hull when the class is not
## known) less this side's own damage estimate, so a nearly dead ship gets one more round, not a
## full salvo. Against aircraft the weapon's own doctrine salvo stands: a miss there is the risk.
func salvo_for_track(spec: WeaponSpec, t: Track) -> int:
	var most := mini(maxi(spec.salvo_default, 1), magazine_count(spec.id))
	if most <= 1 or t.domain == "air":
		return most
	var range_nm := position.distance_to(t.position) if t.position.is_finite() else -1.0
	var per_round := spec.damage * expected_hit_chance(spec, t, range_nm)
	if per_round <= 0.0:
		return most
	var remaining := TrackManager.assessed_health(t, spec.id) * (1.0 - clampf(t.damage_estimate, 0.0, 99.0) / 100.0)
	return clampi(ceili(remaining / per_round), 1, most)


## The chance one round hits, as the shooter can judge it from the plot: the weapon's rated figure;
## for a missile, times the chance it lives through the close-in defences the reported class is
## fitted with (none assumed for a contact not yet classified), so a defended ship is still sent
## rounds enough to get one through; for gunfire, the fall with range and with the plotted speed
## of the target (Combat's model).
func expected_hit_chance(spec: WeaponSpec, t: Track, range_nm := -1.0) -> float:
	if not spec.is_gun():
		return clampf(spec.base_pk * _reported_defence_leak(spec, t), 0.0, 1.0)
	var range_factor := 1.0
	if range_nm >= 0.0 and spec.max_range_nm > 0.0:
		range_factor = lerpf(1.0, Combat.GUN_PK_AT_MAX_RANGE, clampf(range_nm / spec.max_range_nm, 0.0, 1.0))
	var speed := t.speed_kn if t.has_kinematics else 0.0
	return clampf(spec.base_pk * range_factor / (1.0 + maxf(speed, 0.0) / Combat.GUN_SPEED_HALVING_KN), 0.0, 1.0)


## The chance a missile is not shot down by the point and area defences in the catalogue fit of
## the class the plot reports: each layer that engages missiles gets its own chance at it.
func _reported_defence_leak(spec: WeaponSpec, t: Track) -> float:
	if spec.is_torpedo() or t.classification < Track.Classification.CLASS_KNOWN or t.known_class == "":
		return 1.0
	var platform := DataDB.platform_by_short_name(t.known_class, spec.id)
	if platform == null:
		return 1.0
	var leak := 1.0
	var ids: Array = platform.weapon_loadout.keys()
	ids.sort()
	for wid: String in ids:
		var defence := DataDB.weapon(wid)
		if defence != null and defence.is_interceptor() and defence.target_types.has("missile"):
			leak *= 1.0 - Combat.intercept_probability(defence, spec)
	return leak


## Interceptors with rounds left, longest reach first, so defence engages in layers.
func defensive_weapons() -> Array[WeaponSpec]:
	var out: Array[WeaponSpec] = []
	for w in weapons:
		if w.is_interceptor() and magazine_count(w.id) > 0:
			out.append(w)
	out.sort_custom(func(a: WeaponSpec, b: WeaponSpec) -> bool: return a.max_range_nm > b.max_range_nm)
	return out


func has_radar() -> bool:
	for s in sensors:
		if s.kind == "radar":
			return true
	return false


func radar_emitting() -> bool:
	if is_aircraft() and flight_state != FlightState.AIRBORNE:
		return false
	return radar_on and has_radar() and not submerged()


func has_jammer() -> bool:
	for s in sensors:
		if s.kind == "jammer":
			return true
	return false


## An electronic-attack set follows the radar switch: silent means silent for every emitter aboard.
func jamming() -> bool:
	return is_engageable() and radar_on and has_jammer() and not submerged()


func has_esm() -> bool:
	for s in sensors:
		if s.kind == "esm":
			return true
	return false


## A submerged boat has no aerial out of the water, so it is off the network and knows only what
## it hears for itself.
func datalink_connected() -> bool:
	if is_submarine() and comms_enabled:
		return alive and spec.has_datalink and SubmarineComms.connected(self)
	return alive and spec.has_datalink and not submerged() and not (is_aircraft() and not in_flight())


func has_sonar() -> bool:
	for s in sensors:
		if s.kind == "sonar":
			return true
	return false


func active_sonar_emitting() -> bool:
	if not active_sonar_on or not is_engageable():
		return false
	for sensor in sensors:
		if sensor.kind == "sonar" and sensor.active_range_nm > 0.0 and (not sensor.requires_hover or DippingSonar.listening(self)) and TowedArray.sensor_ready(self, sensor):
			return true
	return false


func is_submarine() -> bool:
	return spec.domain == "subsurface"


## Anything that has to stay in the water. Aircraft overfly a coast and a shore installation is
## standing on one, so neither can run aground; a hull and a boat can.
func needs_sea_room() -> bool:
	return spec.domain == "surface" or spec.domain == "subsurface"


## Deep enough that masts and antennas are under water. A boat at periscope depth is not
## submerged for this purpose: it can look and be seen.
func submerged() -> bool:
	return depth_m > PERISCOPE_DEPTH_M


func at_periscope_depth() -> bool:
	return depth_m > 0.5 and depth_m <= PERISCOPE_DEPTH_M


## Orders that change where the platform is going. Each advances order_generation.
const NAVIGATION_ORDERS := [Order.Type.MOVE, Order.Type.SET_COURSE, Order.Type.STOP, Order.Type.CLEAR_WAYPOINTS, Order.Type.FORM_UP, Order.Type.BREAK_FORMATION, Order.Type.PATROL, Order.Type.INVESTIGATE, Order.Type.ATTACK, Order.Type.RETURN_TO_STATION, Order.Type.RETURN_TO_BASE]
## Orders from the commander that end the standing assignment rather than interrupt it. PATROL and
## FORM_UP end it too, by setting a new one; BREAK_FORMATION ends only a formation station. A
## RETURN_TO_BASE reaches here only once UnitManager has checked the landing can be made.
const STATION_REPLACING_ORDERS := [Order.Type.MOVE, Order.Type.SET_COURSE, Order.Type.STOP, Order.Type.CLEAR_WAYPOINTS, Order.Type.RETURN_TO_BASE]
## Steering orders that take a consort out of its formation: it cannot keep station and go there.
## They interrupt a formation station rather than end it: an escort sent to look at something on
## the bow is still part of the screen, and Return to Station takes her back. Only BREAK_FORMATION
## or a new assignment ends it.
const DETACHING_ORDERS := [Order.Type.MOVE, Order.Type.SET_COURSE, Order.Type.STOP]


func apply_order(order: Order) -> void:
	DippingSonar.on_order(self, order)
	TowedArray.on_order(self, order)
	SubmarinePower.on_order(self, order)
	if order.type in NAVIGATION_ORDERS:
		order_generation += 1
		if order.origin != "crew":
			player_order_generation += 1
		station_note = ""
		coast_blocked = false
		coast_blocked_s = 0.0
		nav_goal = Vector2.INF
	# Repeating an attack keeps its rounds and assessment, but the commander's confirmation
	# takes ownership of a crew-issued pursuit (including the CAP boundary override).
	if order.type == Order.Type.ATTACK and attack_track != null and attack_track == order.track:
		attack_weapon_id = order.weapon_id
		task_generation = order_generation
		return
	var keeping_station := in_formation()
	# A task that replaces a task hands on the plan the first one interrupted.
	var carrying := plan_kept and order.type in [Order.Type.INVESTIGATE, Order.Type.ATTACK]
	# The crew going back to station is the end of a task, not a new instruction: what the task
	# found stays on the read-out until the commander sends the platform somewhere.
	var crew_return := order.type == Order.Type.RETURN_TO_STATION and order.origin == "crew"
	if order.type in DETACHING_ORDERS:
		formation_leader = null
	if order.origin != "crew":
		# Clearing the route of a consort that is keeping station changes nothing; it has none.
		var interrupts_formation := order.type in DETACHING_ORDERS and station_kind == "formation"
		if order.type in STATION_REPLACING_ORDERS and not (order.type == Order.Type.CLEAR_WAYPOINTS and keeping_station) and not interrupts_formation:
			clear_station()
		elif order.type == Order.Type.BREAK_FORMATION and station_kind == "formation":
			clear_station()
	if order.type in [Order.Type.MOVE, Order.Type.SET_COURSE, Order.Type.SET_SPEED, Order.Type.STOP, Order.Type.PATROL, Order.Type.INVESTIGATE, Order.Type.ATTACK]:
		evasion_remaining_s = 0.0
	# The commander's return ends an evasion; the crew's own return lets the turn-away run its
	# course and takes up the station after it, as RESUME PLAN would.
	if order.type == Order.Type.RETURN_TO_STATION and order.origin != "crew":
		evasion_remaining_s = 0.0
	# A task leaves the circuit when it takes the steering: an investigation at once, an attack
	# only when it has to close, which UnitManager decides.
	if order.type in [Order.Type.MOVE, Order.Type.SET_COURSE, Order.Type.STOP, Order.Type.CLEAR_WAYPOINTS, Order.Type.FORM_UP, Order.Type.BREAK_FORMATION, Order.Type.RETURN_TO_STATION]:
		patrol_active = false
	if order.type in [Order.Type.MOVE, Order.Type.SET_COURSE, Order.Type.STOP, Order.Type.CLEAR_WAYPOINTS, Order.Type.FORM_UP, Order.Type.BREAK_FORMATION, Order.Type.PATROL, Order.Type.INVESTIGATE, Order.Type.ATTACK, Order.Type.RETURN_TO_STATION]:
		var found := [investigation_track_id, investigation_result, attack_track_id, attack_result]
		clear_investigation(true)
		clear_attack(true)
		if not carrying:
			forget_plan()
		if crew_return:
			investigation_track_id = found[0]
			investigation_result = found[1]
			attack_track_id = found[2]
			attack_result = found[3]
	match order.type:
		Order.Type.INVESTIGATE:
			# A temporary task: the route, formation or patrol is suspended, not forgotten.
			take_steering()
			task_generation = order_generation
			investigation_track = order.track
			investigation_track_id = order.track.id
			investigation_identify_only = order.identify_only
			if not steer_for(order.track.position):
				waypoints.assign([order.track.position])  # UnitManager ends the task on its first step
			investigation_speed_kn = task_speed_kn(false)
			ordered_speed_kn = investigation_speed_kn
		Order.Type.ATTACK:
			task_generation = order_generation
			attack_track = order.track
			attack_track_id = order.track.id
			attack_weapon_id = order.weapon_id
			attack_phase = "Intercept track"
			attack_speed_kn = task_speed_kn(true)
			# In reach, nothing else changes: the platform fires from where its orders have it.
			# Out of reach, the intercept leg is plotted at once, so a paused order already shows
			# where the platform will go; UnitManager refines it every tick as the plot moves.
			var reach := attack_reach_nm(order.track, order.weapon_id)
			if reach > 0.0 and position.distance_to(order.track.position) > reach / UnitManager.ATTACK_STANDOFF_FRACTION and not DippingSonar.holds_bearing(self, order.track):
				take_steering()
				var firing_point := Combat.standoff_point(position, order.track.position, reach)
				if not steer_for(firing_point):
					waypoints.assign([firing_point])  # UnitManager ends the task on its first step
				ordered_speed_kn = attack_speed_kn
		Order.Type.PATROL:
			formation_leader = null
			patrol_active = true
			patrol_legs_completed = 0
			waypoints.assign(sea_legs_through(order.route))
			if ordered_speed_kn <= 0.0:
				ordered_speed_kn = spec.cruise_speed_kn
			set_station("patrol", order.station_label if order.station_label != "" else "PATROL")
			station_route.assign(order.route)
			station_speed_kn = ordered_speed_kn
			station_mission_id = order.mission_id
			station_identify_only = order.identify_only
		Order.Type.RETURN_TO_STATION:
			_resume_station()
		Order.Type.SET_AUTO_RETURN:
			auto_return = order.automatic
		Order.Type.SET_READY_ALERT:
			ready_alert = clampi(order.aircraft_count, 0, AirMissionManager.MAX_READY_ALERT)
		Order.Type.MOVE:
			# A hull is given the way round whatever land lies on the straight course; UnitManager
			# has already refused a destination with no way to it.
			var leg_from := waypoints.back() as Vector2 if order.append and not waypoints.is_empty() else position
			if not order.append:
				waypoints.clear()
			waypoints.append_array(sea_legs(leg_from, order.target_pos))
			if ordered_speed_kn <= 0.0:
				ordered_speed_kn = spec.cruise_speed_kn
		Order.Type.SET_COURSE:
			waypoints.clear()
			ordered_heading_deg = fposmod(order.heading_deg, 360.0)
			# A course is somewhere to go. Lying stopped she has no rudder, so she gets way on to
			# steer it, as she does for a move.
			if ordered_speed_kn <= 0.0:
				ordered_speed_kn = spec.cruise_speed_kn
		Order.Type.SET_SPEED:
			ordered_speed_kn = clampf(order.speed_kn, 0.0, effective_max_speed())
			if patrol_active and station_kind == "patrol":
				station_speed_kn = ordered_speed_kn  # the circuit's speed, not an intercept's
			if investigation_track != null:
				investigation_speed_kn = ordered_speed_kn
			if attack_track != null:
				attack_speed_kn = ordered_speed_kn
				attack_speed_ordered = true
		Order.Type.STOP:
			waypoints.clear()
			ordered_speed_kn = 0.0
		Order.Type.CLEAR_WAYPOINTS:
			waypoints.clear()
			ordered_heading_deg = heading_deg
		Order.Type.ACTIVATE_RADAR:
			radar_on = true
		Order.Type.SILENCE_RADAR:
			radar_on = false
		Order.Type.ENGAGE:
			pass  # routed to WeaponManager by Simulation
		Order.Type.SET_DEPTH:
			ordered_depth_m = clampf(order.depth_m, 0.0, spec.max_depth_m)
		Order.Type.ACTIVE_SONAR:
			active_sonar_on = true
		Order.Type.PASSIVE_SONAR:
			active_sonar_on = false
		Order.Type.SET_ROE:
			roe = order.roe as Roe
		Order.Type.SET_DEFENCE_POLICY:
			defence_policy = order.defence_policy
		Order.Type.SET_AUTO_COUNTERMEASURES:
			auto_countermeasures = order.automatic
		Order.Type.SET_AIR_DEFENCE_MODE:
			auto_air_defence = order.automatic
		Order.Type.INTERCEPT:
			pass  # Simulation clears the rounds with the threat picture it owns.
		Order.Type.RESUME_PLAN:
			evasion_remaining_s = 0.0
		Order.Type.CANCEL_FIRE:
			# Cancelling fire on the contact under attack ends the attack too; otherwise the task
			# would simply fire again after its assessment. Rounds already away continue.
			if attack_track != null and (order.track == null or order.track == attack_track):
				var number := attack_track_id
				# The interrupted plan is kept: UnitManager hands the platform back to it.
				clear_attack(true)
				attack_track_id = number
				attack_result = "Fire cancelled"
				order.stopped_attack = true
		Order.Type.DEPLOY_COUNTERMEASURES, Order.Type.EVADE:
			pass  # Simulation owns inventory and detected-threat checks.
		Order.Type.FORM_UP:
			formation_leader = order.leader
			formation_offset = order.offset_nm
			formation_axis_deg = order.formation_axis_deg
			waypoints.clear()
			set_station("formation", order.station_label if order.station_label != "" else "FORMATION STATION")
			station_leader = order.leader
			station_offset = order.offset_nm
			station_axis_deg = order.formation_axis_deg
		Order.Type.BREAK_FORMATION:
			formation_leader = null
			waypoints.clear()
		Order.Type.SET_EMCON:
			emcon = Emcon.SILENT if order.emcon_silent else Emcon.FREE
			if emcon == Emcon.SILENT:
				radar_on = false
				active_sonar_on = false
			else:
				radar_on = has_radar()
		Order.Type.SET_ALTITUDE:
			ordered_altitude_m = clampf(order.altitude_m, minf(min_altitude_m(), spec.max_altitude_m), spec.max_altitude_m)
		Order.Type.LAUNCH_AIRCRAFT, Order.Type.RETURN_TO_BASE, Order.Type.DEPLOY_SONOBUOY:
			pass  # routed to AviationManager by Simulation
		Order.Type.AIR_MISSION, Order.Type.CANCEL_AIR_MISSION:
			pass  # routed to AirMissionManager by Simulation
		Order.Type.GROUP_ATTACK, Order.Type.CANCEL_GROUP_ATTACK:
			pass  # routed to GroupAttackManager by Simulation; the group never steers its members
		Order.Type.SNORKEL:
			pass  # SubmarinePower.on_order has already raised or secured the mast


func set_station(kind: String, label: String) -> void:
	clear_station()
	station_kind = kind
	station_label = label


## The standing assignment ends: an explicit replacement order, a landing, or a lost guide.
func clear_station() -> void:
	station_kind = ""
	station_route.clear()
	station_leader = null
	station_offset = Vector2.ZERO
	station_axis_deg = -1.0
	station_label = ""
	station_speed_kn = 0.0
	station_mission_id = -1
	station_identify_only = false


func has_station() -> bool:
	return station_kind != ""


## On the standing assignment now, rather than away on a task or holding it in reserve.
func on_station() -> bool:
	match station_kind:
		"patrol":
			return patrol_active
		"formation":
			return in_formation() and formation_leader == station_leader
	return false


## Where a return to station would steer first: the nearest corner of the circuit, or the guide's
## present station point. INF when there is nowhere to go.
func station_point() -> Vector2:
	match station_kind:
		"patrol":
			if station_route.is_empty():
				return Vector2.INF
			return station_route[nearest_station_corner()]
		"formation":
			if station_leader == null or not station_leader.alive:
				return Vector2.INF
			var axis := station_axis_deg if station_axis_deg >= 0.0 else station_leader.heading_deg
			var ahead := Geo.heading_to_vector(axis)
			var starboard := Geo.heading_to_vector(axis + 90.0)
			return station_leader.position + ahead * station_offset.y + starboard * station_offset.x
	return Vector2.INF


## The speed the station was taken at: an intercept at flank does not carry over to the circuit.
func station_speed() -> float:
	return station_speed_kn if station_speed_kn > 0.0 else spec.cruise_speed_kn


func nearest_station_corner() -> int:
	var best := 0
	var best_d := INF
	for i in station_route.size():
		var d := position.distance_squared_to(station_route[i])
		if d < best_d:
			best_d = d
			best = i
	return best


## The circuit re-entered at its nearest corner, so a platform that broke off to investigate does
## not sail back past half the box to start where it first began.
func station_circuit_from_here() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var start := nearest_station_corner()
	for i in station_route.size():
		out.append(station_route[(start + i) % station_route.size()])
	return out


## UnitManager has already checked the station is still there to return to.
func _resume_station() -> void:
	station_note = ""
	match station_kind:
		"patrol":
			formation_leader = null
			patrol_active = true
			patrol_legs_completed = 0
			waypoints.assign(sea_legs_through(station_circuit_from_here()))
			ordered_speed_kn = station_speed()
		"formation":
			formation_leader = station_leader
			formation_offset = station_offset
			formation_axis_deg = station_axis_deg
			waypoints.clear()


## The legs to steer from `from` to `to`: the point itself for anything that flies, and for a hull
## the way by sea, round whatever coast lies on the straight course. Never empty: with no way by
## sea the straight leg is returned, for the callers that have nothing better to do with it.
func sea_legs(from: Vector2, to: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if needs_sea_room():
		out.assign(Terrain.sea_route(from, to))
	if out.is_empty():
		out.append(to)
	return out


## A route taken up from where the platform is now: the way by sea to its first point, then the
## rest as given. The points added on the way to a patrol circuit are not corners of it, and
## Movement drops them once passed instead of sailing them round again.
func sea_legs_through(route: Array[Vector2]) -> Array[Vector2]:
	if route.is_empty():
		return route.duplicate()
	var out := sea_legs(position, route[0])
	out.append_array(route.slice(1))
	return out


## Lays the way to where a task wants the platform, for a goal that moves from tick to tick. A
## straight leg whenever the water is open. With land in the way a hull takes the sea route, and
## keeps the one it has while the goal has not moved far from where that route ends, so the
## search is not run again until the picture has changed. False when a hull has no way there.
const NAV_REPLAN_NM := 1.0
const NAV_REPLAN_FRACTION := 0.05


func steer_for(goal: Vector2) -> bool:
	if not needs_sea_room() or Terrain.is_empty() or Terrain.sea_leg_clear(position, goal):
		waypoints.assign([goal])
		nav_goal = Vector2.INF
		return true
	if on_sea_route() and nav_goal.distance_to(goal) <= maxf(NAV_REPLAN_NM, position.distance_to(goal) * NAV_REPLAN_FRACTION):
		return true
	var route := Terrain.sea_route(position, goal)
	if route.is_empty():
		return false
	waypoints.assign(route)
	nav_goal = goal
	return true


## Following a way a task laid round a coast, rather than steering straight for its goal.
func on_sea_route() -> bool:
	return nav_goal.is_finite() and not waypoints.is_empty() and waypoints.back() == nav_goal


## The speed a task is carried out at. An attack that has to close does not dawdle at convoy
## speed: a ship goes at most of what her plant will give, a boat at the cruise she can still hear
## at, and an aircraft never flies either task slower than its cruise (a helicopter ordered off a
## hover would otherwise creep away at the hover's knot or two). A speed order given while the task
## runs replaces it.
func task_speed_kn(attacking: bool) -> float:
	var speed := ordered_speed_kn if ordered_speed_kn > 0.0 else spec.cruise_speed_kn
	if is_aircraft() or is_submarine():
		speed = maxf(speed, spec.cruise_speed_kn)
	elif attacking:
		speed = maxf(speed, UnitManager.ATTACK_CLOSING_FRACTION * effective_max_speed())
	return minf(speed, effective_max_speed())


## A temporary task takes the steering. What it interrupts is remembered once, so a task that
## follows a task still hands back to the first one's plan, and the platform leaves its formation
## or circuit; whatever is streamed or lowered comes in before it moves off.
func take_steering() -> void:
	# A dome cannot be flown off in the water; a towed array is steered with, at its own speed.
	DippingSonar.recover_announced(self)
	if not plan_kept:
		plan_kept = true
		plan_waypoints.clear()
		# The station fields already hold a circuit or a formation station, and a hold laid for
		# want of orders is not a route anyone chose.
		if not on_station() and not holding():
			plan_waypoints.assign(waypoints)
		plan_speed_kn = ordered_speed_kn
		waypoints.clear()
		nav_goal = Vector2.INF
	formation_leader = null
	patrol_active = false
	hold_active = false


func forget_plan() -> void:
	plan_kept = false
	plan_waypoints.clear()
	plan_speed_kn = 0.0


## Back to what the task interrupted, once it is over and UnitManager has found no station to go
## back to: the route at the speed it was being sailed at. With no route, a hull holds the course
## the task left her on at the speed she had before it, a helicopter hovers where it is, and a
## fixed-wing aircraft holds where it is rather than flying on until its fuel runs out.
func resume_plan() -> void:
	var route := plan_waypoints.duplicate()
	var speed := plan_speed_kn
	forget_plan()
	hold_active = false
	nav_goal = Vector2.INF
	# The task may have ended on the far side of a headland from the route it interrupted.
	waypoints.assign(sea_legs_through(route))
	if not waypoints.is_empty():
		ordered_speed_kn = speed if speed > 0.0 else spec.cruise_speed_kn
		return
	ordered_heading_deg = heading_deg
	if Movement.must_keep_flying(self):
		Movement.enter_hold(self, position)
	elif is_aircraft():
		ordered_speed_kn = 0.0
	else:
		ordered_speed_kn = speed


## Other navigation replaces this task; a completed task may keep a readable result until then.
## The interrupted plan goes with it unless the caller is handing the platform back to that plan.
func clear_investigation(keep_plan := false) -> void:
	if investigation_track != null:
		waypoints.clear()
		nav_goal = Vector2.INF
	if not keep_plan:
		forget_plan()
	investigation_track = null
	investigation_track_id = ""
	investigation_result = ""
	investigation_speed_kn = 0.0
	investigation_identify_only = false


## The standoff distance the attack closes to: a fraction of the reach of the named weapon, or
## of the best suitable weapon with rounds left. Zero when nothing aboard suits the contact.
func attack_reach_nm(track: Track, weapon_id := "") -> float:
	var spec: WeaponSpec = get_weapon(weapon_id) if weapon_id != "" else null
	if spec == null:
		var suitable := weapons_for_track(track)
		if suitable.is_empty():
			return 0.0
		spec = suitable[0]
	var reach := Combat.effective_range_nm(self, spec)
	if track.domain == "air":
		reach = Combat.air_no_escape_range_nm(spec, track, position, reach)
	return UnitManager.ATTACK_STANDOFF_FRACTION * reach


## Other navigation replaces the attack as well; a finished attack keeps its result readable.
## Only an attack that took the steering has a route of its own to drop.
func clear_attack(keep_plan := false) -> void:
	if attack_track != null and plan_kept:
		waypoints.clear()
		nav_goal = Vector2.INF
	if not keep_plan:
		forget_plan()
	attack_speed_ordered = false
	attack_holding = false
	attack_progress_pos = Vector2.INF
	attack_track = null
	attack_track_id = ""
	attack_weapon_id = ""
	attack_phase = ""
	attack_result = ""
	attack_speed_kn = 0.0
	attack_standoff_nm = 0.0
	attack_rounds_fired = 0
	attack_assess_until_s = -1.0
	attack_stall_s = 0.0
	attack_stale_s = 0.0


## The lowest altitude over the sea this airframe will be ordered to: a helicopter can work
## just above the waves, a fixed-wing aircraft needs room to recover from a gust. GAMEPLAY_ESTIMATE.
const MIN_ALTITUDE_ROTARY_M := 15.0
const MIN_ALTITUDE_FIXED_WING_M := 30.0


func min_altitude_m() -> float:
	return MIN_ALTITUDE_ROTARY_M if spec.can_hover else MIN_ALTITUDE_FIXED_WING_M


func in_formation() -> bool:
	return formation_leader != null and formation_leader.alive and formation_leader != self


func status_line() -> String:
	var base := "HDG %s  SPD %.1f kn" % [Geo.format_bearing(heading_deg), speed_kn]
	if is_submarine():
		base += "  DEP %.0f m" % depth_m
		return base + "  BATT %d%%" % int(round(battery * 100.0)) if SubmarinePower.fitted(self) else base
	if is_aircraft():
		return base + "  ALT %.0f m  FUEL %.0f%%" % [altitude_m, fuel_fraction() * 100.0]
	return base


# --- Missile defence state ------------------------------------------------------------------------

## Manual missile defence: the simulation time until which the commander's clearance to engage the
## raid stands (AirDefence.order_intercept with no round named), or -1 with none given. While it
## stands the ship's area missiles engage inbound rounds as they arrive.
var raid_clearance_until_s := -1.0


## When a ship ordered radar silent last held fire at a round it could otherwise have engaged, or
## -1: it says so once a raid, not every cycle.
var silent_hold_reported_s := -1.0


func cleared_for_raid(now: float) -> bool:
	return raid_clearance_until_s >= 0.0 and now <= raid_clearance_until_s


# --- Radar lit by the crew for self-defence -----------------------------------------------------

## A radar the commander had off that the crew lit to fight a round coming at the ship: the last
## time a round was still inbound on her, or -1 when the radar is as the commander set it.
var radar_lit_for_defence_s := -1.0
