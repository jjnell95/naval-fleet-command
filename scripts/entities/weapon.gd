class_name Weapon
extends RefCounted
## A weapon in flight. Created by WeaponManager, advanced on simulation ticks.
##
## Lifecycle: CRUISE (fly to the aim point derived from the TRACK, not the real unit)
##          → TERMINAL (seeker acquires a real unit within acquisition radius)
##          → hit roll → IMPACT or MISS.
## Authored update-capable weapons accept aim updates only while the shooter holds an ACTIVE track.
## Launch-and-leave weapons keep the launch solution. Firing at a stale track means
## flying to where the enemy was believed to be, which is how misses happen.

enum Phase { CRUISE, TERMINAL, DEAD }

var id := -1
var spec: WeaponSpec
var faction := ""
var shooter: Unit
var target_track: Track
## The coordinated group attack this round was fired for (GroupAttack.id), or -1 for a round fired
## on a platform's own order. The group counts its expenditure by this tag, never by shooter.
var group_id := -1
var launch_altitude_m := -1.0
var launch_range_nm := 0.0
var delivery_spec: WeaponSpec  # launcher identity retained after a torpedo enters the water
var acquired: Unit
var intercept_target: Weapon  # set when this round is a SAM or close-in round
var decoy_attempted := false
var countermeasure_attempts: Dictionary = {}  # one roll per unit and deployed pulse
## Ships whose acoustic countermeasures have had their try at this torpedo: unit id -> true. A
## torpedo decoyed onto another ship meets that ship's own.
var acoustic_decoy_tried: Dictionary = {}
## Anti-torpedo rounds ever fired at this torpedo, by any ship.
var hard_kill_shots := 0
var seductions := 0  # times decoys have pulled this round off a lock
var guided_interceptors_committed := 0  # SAMs ever fired at this round
var defence_commitments: Dictionary = {}  # AirDefence.layer_key (layer and ship) -> shots fired at this round
var close_in_commitments: Dictionary = {}  # defending unit id -> bursts
var close_in_bursts_committed := 0  # close-in engagements; a round is only in that envelope briefly
## Ids of the units the commander has ordered to intercept this round (Order.intercept). A ship
## on manual missile defence engages only rounds it is cleared for; one on automatic needs none.
var intercept_cleared: Array[int] = []
var position := Vector2.ZERO
var heading_deg := 0.0
var aim_point := Vector2.ZERO
var phase: Phase = Phase.CRUISE
var distance_flown_nm := 0.0
var time_alive_s := 0.0
var dead_reason := ""
## A round fired at an aircraft that reached its aim point with nothing in its seeker flies on along
## its heading, still searching, until its fuel runs out (`WeaponManager._try_acquire`).
var searching_on := false
## An interceptor: seconds it has flown its endgame without guidance. It coasts on its last
## solution for a moment before it is lost (WeaponManager.INTERCEPT_COAST_S).
var unguided_s := 0.0
## The unit this round was locked on sank, dived or landed, and it has found nothing since: it is
## searching on down its heading and ends as TARGET LOST if its range runs out first.
var lost_lock := false
## Fired from a battery ashore: the round climbs out over its own coast before the ordinary rule
## that a low-flying weapon ends at the first ground it meets applies to it.
var launched_ashore := false
## Anti-radiation rounds. Where the emitter was when it was last heard, and whether it has since
## gone silent: the round then flies to that point on memory, with a poorer chance of a hit and
## none at all if the emitter has moved off it.
var emitter_point := Vector2.INF
var emitter_silent := false


## A ballistic round holds its height until the last part of its flight and then comes down on
## its target: the final BALLISTIC_DIVE_FRACTION of the launch range, and never less than
## BALLISTIC_DIVE_MIN_NM of ground covered. What can engage it changes on the way down: an
## interceptor built for space loses it as it re-enters, and the upper-atmosphere ones get their
## turn only then. GAMEPLAY_ESTIMATE.
const BALLISTIC_DIVE_FRACTION := 0.15
const BALLISTIC_DIVE_MIN_NM := 30.0


func flight_altitude_m() -> float:
	if spec.is_torpedo():
		return 0.0
	if spec.type == "bomb" and launch_range_nm > 0.0:
		return maxf(launch_altitude_m, 0.0) * clampf(1.0 - distance_flown_nm / launch_range_nm, 0.0, 1.0)
	if spec.type in ["aam", "bomb"] and launch_altitude_m >= 0.0:
		return launch_altitude_m
	if spec.profile == "ballistic" and launch_range_nm > 0.0:
		return spec.altitude_m * clampf(distance_to_go_nm() / ballistic_dive_nm(), 0.0, 1.0)
	return spec.altitude_m


## Ground distance over which a ballistic round comes down from its cruise height.
func ballistic_dive_nm() -> float:
	return minf(maxf(launch_range_nm * BALLISTIC_DIVE_FRACTION, BALLISTIC_DIVE_MIN_NM), maxf(launch_range_nm, 0.001))


## Distance from the round to what it is going for: the unit it has locked, else its aim point.
func distance_to_go_nm() -> float:
	return position.distance_to(acquired.position if acquired != null else aim_point)


func speed_nm_per_s() -> float:
	return Geo.knots_to_nm_per_s(spec.speed_kn)



## What kind of defensive problem this round poses: a torpedo is heard and outrun, a missile is
## shot down, a ballistic round needs an interceptor built for the job. A gun's shell is none of
## these: nothing aboard shoots shells down and chaff means nothing to one.
func threat_class() -> String:
	if spec.is_torpedo():
		return "torpedo"
	if spec.is_gun():
		return "shell"
	return "ballistic" if spec.profile == "ballistic" else "missile"


func is_interceptor() -> bool:
	return intercept_target != null


## Seconds until this round reaches a point, ignoring manoeuvre.
func time_to_reach_s(target_pos: Vector2) -> float:
	var v := speed_nm_per_s()
	return position.distance_to(target_pos) / v if v > 0.0 else INF
