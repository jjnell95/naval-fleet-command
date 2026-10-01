class_name Unit
extends RefCounted
## Ground-truth simulation entity. Not a Node: owned by UnitManager, rendered by TacticalMap.
## Enemy units are never shown to the player directly; from Milestone 2 they are perceived via Tracks.

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
var alive := true
## Left the chart for a base off the map. Not alive for the simulation, but not lost either.
var departed := false
## A scenario's own value for this unit on the effectiveness balance sheet; 0 means the
## catalogue default for its category (MissionManager.platform_points).
var points := 0
var sensors: Array[SensorSpec] = []  # resolved from spec.sensor_ids at spawn
var radar_on := true
var active_sonar_on := false
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
var depth_m := 0.0
var ordered_depth_m := 0.0
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
var defence_policy := "balanced"  # balanced | conserve | saturation
var defence_priority := 0
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


## Weapons with rounds left that can engage a given track, best reach first and guns last.
func weapons_for_track(t: Track) -> Array[WeaponSpec]:
	var out: Array[WeaponSpec] = []
	for w in weapons:
		if magazine_count(w.id) > 0 and Combat.suits_track(w, t):
			out.append(w)
	out.sort_custom(func(a: WeaponSpec, c: WeaponSpec) -> bool:
		if a.is_gun() != c.is_gun():
			return c.is_gun()
		return a.max_range_nm > c.max_range_nm)
	return out


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
	return alive and spec.has_datalink and not submerged() and not (is_aircraft() and not in_flight())


func has_sonar() -> bool:
	for s in sensors:
		if s.kind == "sonar":
			return true
	return false


func active_sonar_emitting() -> bool:
	return active_sonar_on and has_sonar()


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


func apply_order(order: Order) -> void:
	# A second attack order on the contact already under attack keeps the task, its round count
	# and its assessment pause; only the chosen weapon can change.
	if order.type == Order.Type.ATTACK and attack_track != null and attack_track == order.track:
		attack_weapon_id = order.weapon_id
		return
	if order.type in [Order.Type.MOVE, Order.Type.SET_COURSE, Order.Type.SET_SPEED, Order.Type.STOP, Order.Type.PATROL, Order.Type.INVESTIGATE, Order.Type.ATTACK]:
		evasion_remaining_s = 0.0
	if order.type in [Order.Type.MOVE, Order.Type.SET_COURSE, Order.Type.STOP, Order.Type.CLEAR_WAYPOINTS, Order.Type.FORM_UP, Order.Type.BREAK_FORMATION, Order.Type.INVESTIGATE, Order.Type.ATTACK]:
		patrol_active = false
	if order.type in [Order.Type.MOVE, Order.Type.SET_COURSE, Order.Type.STOP, Order.Type.CLEAR_WAYPOINTS, Order.Type.FORM_UP, Order.Type.BREAK_FORMATION, Order.Type.PATROL, Order.Type.INVESTIGATE, Order.Type.ATTACK]:
		clear_investigation()
		clear_attack()
	match order.type:
		Order.Type.INVESTIGATE:
			formation_leader = null
			investigation_track = order.track
			investigation_track_id = order.track.id
			waypoints.assign([order.track.position])
			if ordered_speed_kn <= 0.0:
				ordered_speed_kn = spec.cruise_speed_kn
			investigation_speed_kn = ordered_speed_kn
		Order.Type.ATTACK:
			formation_leader = null
			attack_track = order.track
			attack_track_id = order.track.id
			attack_weapon_id = order.weapon_id
			attack_phase = "Intercept track"
			if ordered_speed_kn <= 0.0:
				ordered_speed_kn = spec.cruise_speed_kn
			attack_speed_kn = ordered_speed_kn
			# Out of range, the intercept leg is plotted at once, so a paused order already shows
			# where the platform will go; UnitManager refines it every tick as the plot moves.
			waypoints.clear()
			var reach := attack_reach_nm(order.track, order.weapon_id)
			if reach > 0.0 and position.distance_to(order.track.position) > reach / UnitManager.ATTACK_STANDOFF_FRACTION:
				waypoints.append(Combat.standoff_point(position, order.track.position, reach))
		Order.Type.PATROL:
			formation_leader = null
			patrol_active = true
			patrol_legs_completed = 0
			waypoints.assign(order.route)
			if ordered_speed_kn <= 0.0:
				ordered_speed_kn = spec.cruise_speed_kn
		Order.Type.MOVE:
			if not order.append:
				waypoints.clear()
			waypoints.append(order.target_pos)
			if ordered_speed_kn <= 0.0:
				ordered_speed_kn = spec.cruise_speed_kn
		Order.Type.SET_COURSE:
			waypoints.clear()
			ordered_heading_deg = fposmod(order.heading_deg, 360.0)
		Order.Type.SET_SPEED:
			ordered_speed_kn = clampf(order.speed_kn, 0.0, effective_max_speed())
			if investigation_track != null:
				investigation_speed_kn = ordered_speed_kn
			if attack_track != null:
				attack_speed_kn = ordered_speed_kn
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
		Order.Type.RESUME_PLAN:
			evasion_remaining_s = 0.0
		Order.Type.CANCEL_FIRE:
			# Cancelling fire on the contact under attack ends the attack too; otherwise the task
			# would simply fire again after its assessment. Rounds already away continue.
			if attack_track != null and (order.track == null or order.track == attack_track):
				var number := attack_track_id
				clear_attack()
				attack_track_id = number
				attack_result = "Fire cancelled"
				order.stopped_attack = true
		Order.Type.DEPLOY_COUNTERMEASURES, Order.Type.EVADE:
			pass  # Simulation owns inventory and detected-threat checks.
		Order.Type.FORM_UP:
			formation_leader = order.leader
			formation_offset = order.offset_nm
			waypoints.clear()
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
			ordered_altitude_m = clampf(order.altitude_m, 0.0, spec.max_altitude_m)
		Order.Type.LAUNCH_AIRCRAFT, Order.Type.RETURN_TO_BASE, Order.Type.DEPLOY_SONOBUOY:
			pass  # routed to AviationManager by Simulation


## Other navigation replaces this task; a completed task may keep a readable result until then.
func clear_investigation() -> void:
	if investigation_track != null:
		waypoints.clear()
	investigation_track = null
	investigation_track_id = ""
	investigation_result = ""
	investigation_speed_kn = 0.0


## The standoff distance the attack closes to: a fraction of the reach of the named weapon, or
## of the best suitable weapon with rounds left. Zero when nothing aboard suits the contact.
func attack_reach_nm(track: Track, weapon_id := "") -> float:
	var spec: WeaponSpec = get_weapon(weapon_id) if weapon_id != "" else null
	if spec == null:
		var suitable := weapons_for_track(track)
		if suitable.is_empty():
			return 0.0
		spec = suitable[0]
	return UnitManager.ATTACK_STANDOFF_FRACTION * Combat.effective_range_nm(self, spec)


## Other navigation replaces the attack as well; a finished attack keeps its result readable.
func clear_attack() -> void:
	if attack_track != null:
		waypoints.clear()
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


func in_formation() -> bool:
	return formation_leader != null and formation_leader.alive and formation_leader != self


func status_line() -> String:
	var base := "HDG %s  SPD %.1f kn" % [Geo.format_bearing(heading_deg), speed_kn]
	if is_submarine():
		return base + "  DEP %.0f m" % depth_m
	if is_aircraft():
		return base + "  ALT %.0f m  FUEL %.0f%%" % [altitude_m, fuel_fraction() * 100.0]
	return base
