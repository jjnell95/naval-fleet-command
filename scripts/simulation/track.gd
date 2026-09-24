class_name Track
extends RefCounted
## A faction's perception of one enemy unit. This is what the UI and AI see; the ground-truth
## `truth` link exists only for observation association and DEBUG display.

enum Classification { UNKNOWN, SURFACE, CLASS_KNOWN, IDENTIFIED }
enum Status { ACTIVE, STALE, LOST }

const STALE_AFTER_S := 60.0
const LOST_AFTER_S := 1800.0
const CLASS_TIMES_S: Array[float] = [0.0, 30.0, 180.0, 600.0]  # cumulative observation time
const ERROR_GROWTH_NM_PER_S := 0.004  # ~14 nm/h uncertainty growth while unobserved (GAMEPLAY)

var id := ""
var owner_faction := ""
var truth: Unit  # association/debug only — never read from UI unless Debug.enabled
var position := Vector2.ZERO
var position_error_nm := 1.0  # circular equivalent, kept for panels and legacy callers
## Uncertainty is an ellipse, because a passive sonar bearing is precise across the line of sight
## and almost worthless along it. `error_axis_deg` is the bearing the major axis lies on.
var error_major_nm := 1.0
var error_minor_nm := 1.0
var error_axis_deg := 0.0
var bearing_only := false
var tma_quality := 0.0  # 0 = bearing only, 1 = a range solution worth shooting at
var domain := ""  # "surface" or "subsurface", known once the contact is classified
var source := "radar"  # sensor that last held it
## Which of our own units have contributed to this track, and whether any of them is on the
## network. A contact held only by something off the link is ours alone until it reconnects.
var contributors: Dictionary = {}
var networked := true
var course_deg := 0.0
var speed_kn := 0.0
var has_kinematics := false
var classification := Classification.UNKNOWN
var identity := "UNKNOWN"  # UNKNOWN | HOSTILE (FRIENDLY / NEUTRAL later)
var status := Status.ACTIVE
var known_class := ""  # filled when classification reaches CLASS_KNOWN
var known_callsign := ""  # filled when IDENTIFIED
var observation_time_s := 0.0
var first_seen_time := 0.0
var last_seen_time := 0.0
## When a firm plot (radar, active sonar, crossed buoys) last held this track. A bearing heard in
## the same moment adds nothing to the geometry, so it is not allowed to blur it.
var last_firm_time := -1.0e9
var _obs_times := PackedFloat64Array()  # sliding observation window for kinematics fit
var _obs_pos := PackedVector2Array()
var _last_est_time := -1.0


func age_s(now: float) -> float:
	return maxf(now - last_seen_time, 0.0)


func class_short() -> String:
	match classification:
		Classification.UNKNOWN:
			return "UNK"
		Classification.SURFACE:
			return "SUB" if domain == "subsurface" else ("AIR" if domain == "air" else "SURF")
	return known_class


## True when the contact is held on sound alone, with no usable range.
func is_bearing_only() -> bool:
	return bearing_only and tma_quality < 0.6


## Classification wording on its own, for panels that already show the track id.
func description() -> String:
	match classification:
		Classification.IDENTIFIED:
			return known_callsign
		Classification.CLASS_KNOWN:
			return known_class
		Classification.SURFACE:
			return "SUBSURFACE CONTACT" if domain == "subsurface" else ("AIR CONTACT" if domain == "air" else "SURFACE CONTACT")
	return "UNKNOWN CONTACT"


## Map label: track id plus the shortest useful description.
func label() -> String:
	match classification:
		Classification.IDENTIFIED:
			return known_callsign
		Classification.CLASS_KNOWN:
			return "%s %s" % [id, known_class]
		Classification.SURFACE:
			return "%s %s" % [id, "SUB" if domain == "subsurface" else ("AIR" if domain == "air" else "SURF")]
	return "%s UNK" % id


## Whether this unit knows about the contact: because it found it, or because someone on the
## network did and this unit is on the network too.
func visible_to(u: Unit) -> bool:
	if u == null or (owner_faction != "" and u.faction != owner_faction):
		return false
	if not networked:
		return contributors.has(u)
	return u.datalink_connected()


func status_short(now: float) -> String:
	match status:
		Status.STALE:
			return "STL %s" % _fmt_age(age_s(now))
		Status.LOST:
			return "LOST"
	return "ACT"


func status_text(now: float) -> String:
	match status:
		Status.STALE:
			return "STALE %s" % _fmt_age(age_s(now))
		Status.LOST:
			return "LOST"
	return "ACTIVE"


static func _fmt_age(s: float) -> String:
	if s < 60.0:
		return "%ds" % int(s)
	return "%dm" % int(s / 60.0)
