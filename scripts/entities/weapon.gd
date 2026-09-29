class_name Weapon
extends RefCounted
## A weapon in flight. Created by WeaponManager, advanced on simulation ticks.
##
## Lifecycle: CRUISE (fly to the aim point derived from the TRACK, not the real unit)
##          → TERMINAL (seeker acquires a real unit within acquisition radius)
##          → hit roll → IMPACT or MISS.
## Mid-course aim updates only happen while the track is ACTIVE. Firing at a stale track means
## flying to where the enemy was believed to be, which is how misses happen.

enum Phase { CRUISE, TERMINAL, DEAD }

var id := -1
var spec: WeaponSpec
var faction := ""
var shooter: Unit
var target_track: Track
var acquired: Unit
var intercept_target: Weapon  # set when this round is a SAM or close-in round
var decoy_attempted := false
## Ships whose acoustic countermeasures have had their try at this torpedo: unit id -> true. A
## torpedo decoyed onto another ship meets that ship's own.
var acoustic_decoy_tried: Dictionary = {}
## Anti-torpedo rounds ever fired at this torpedo, by any ship.
var hard_kill_shots := 0
var seductions := 0  # times decoys have pulled this round off a lock
var guided_interceptors_committed := 0  # SAMs ever fired at this round
var defence_commitments: Dictionary = {}  # defensive layer -> reserved shots
var close_in_commitments: Dictionary = {}  # defending unit id -> bursts
var close_in_bursts_committed := 0  # close-in engagements; a round is only in that envelope briefly
var position := Vector2.ZERO
var heading_deg := 0.0
var aim_point := Vector2.ZERO
var phase: Phase = Phase.CRUISE
var distance_flown_nm := 0.0
var time_alive_s := 0.0
var dead_reason := ""
## Fired from a battery ashore: the round climbs out over its own coast before the ordinary rule
## that a low-flying weapon ends at the first ground it meets applies to it.
var launched_ashore := false


func speed_nm_per_s() -> float:
	return Geo.knots_to_nm_per_s(spec.speed_kn)



## What kind of defensive problem this round poses: a torpedo is heard and outrun, a missile is
## shot down, a ballistic round needs an interceptor built for the job.
func threat_class() -> String:
	if spec.is_torpedo():
		return "torpedo"
	return "ballistic" if spec.profile == "ballistic" else "missile"


func is_interceptor() -> bool:
	return intercept_target != null


## Seconds until this round reaches a point, ignoring manoeuvre.
func time_to_reach_s(target_pos: Vector2) -> float:
	var v := speed_nm_per_s()
	return position.distance_to(target_pos) / v if v > 0.0 else INF
