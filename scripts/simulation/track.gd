class_name Track
extends RefCounted
## A faction's perception of one enemy unit. This is what the UI and AI see; the ground-truth
## `truth` link exists only for observation association and DEBUG display.

enum Classification { UNKNOWN, SURFACE, CLASS_KNOWN, IDENTIFIED }
enum Status { ACTIVE, STALE, LOST }

const STALE_AFTER_S := 60.0
## An aircraft not seen for this long is no longer where the plot has it.
const STALE_AFTER_AIR_S := 20.0
## The longest any contact is kept unseen: a submarine, a fixed site, or a report from outside.
const LOST_AFTER_S := 1800.0
const CLASS_TIMES_S: Array[float] = [0.0, 30.0, 180.0, 600.0]  # cumulative observation time
const ERROR_GROWTH_NM_PER_S := 0.004  # ~14 nm/h for a contact not yet known to be anything (GAMEPLAY)
## How long a lost contact is worth keeping depends on how far it can have gone. GAMEPLAY.
const LOST_AFTER_FAST_AIR_S := 120.0
const LOST_AFTER_SLOW_AIR_S := 300.0
const LOST_AFTER_SURFACE_S := 600.0
const SLOW_AIR_KN := 200.0
## The speed a contact is assumed able to wander at while nobody watches it, by what it is. The
## ellipse grows at the faster of this and the speed the plot last measured.
const DRIFT_AIR_KN := 300.0
const DRIFT_SURFACE_KN := 20.0
const DRIFT_SUBSURFACE_KN := 8.0
## Faster than any ship: a plot moving like this is an aircraft whatever else is known of it.
const FASTEST_SHIP_KN := 70.0
## Below this solution quality a bearing-held contact has no range worth plotting.
const RANGE_HELD_QUALITY := 0.2
## The solution quality at which a range worked from bearings is good enough to shoot a missile at.
const FIRE_CONTROL_SOLUTION_QUALITY := 0.5
## Once the ellipse of an unseen contact is this long, moving the plot along its last course is
## no better than leaving it where it is.
const COAST_LIMIT_NM := 5.0
## A unit this close to where a bearing was taken from is the unit that took it.
const BEARING_UNIT_NM := 0.5

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
## When a range last came in: a measured plot, or a solution worked from bearings. A contact then
## held on bearings alone keeps that range, dead-reckoned, for as long as it would be kept unseen.
var range_time := -1.0e9
## Where the unit holding the contact on a bearing was when it took the last one: the near end of
## the line on the chart. Not finite for a contact that is not held on a bearing.
var bearing_origin := Vector2.INF
## Whose line the plot is following while there is no solution, and when it last reported. One
## listener's line is kept until it loses the contact; taking each in turn would swing the plot
## between them.
var bearing_holder := ""
var bearing_holder_time := -1.0e9
var domain := ""  # "surface" or "subsurface", known once the contact is classified
var altitude_m := -1.0  # held radar altitude; -1 means not measured
var source := "radar"  # sensor that last held it
## Who made the plot the track last took its position from, as this side's own records have it:
## the observing platform's class short name (own units are no secret to their own side) and the
## sensor's display name and catalogue id. The platform is empty for a buoy report, which names
## the buoys as its sensor, and both are empty for a plot that came in from nothing we operate.
var source_platform := ""
var source_sensor := ""
var source_sensor_id := ""
## True while the plot rests only on a contact report from outside the force (a shore array, an
## allied patrol aircraft): a datum to go and look at, never a firing solution. The first plot
## from the side's own sensors replaces it and clears this.
var reported := false
## Battle damage assessment, 0..100: what this side's own hits on the contact suggest, and 100
## once the plot sees it destroyed. Never a read of the target's true condition; see
## TrackManager.record_hit.
var damage_estimate := 0.0
## A recorded destruction on this picture. Earlier saves could estimate 100 on a surviving unit.
var confirmed_destroyed := false
## Which of our own units have contributed to this track, and whether any of them is on the
## network. A contact held only by something off the link is ours alone until it reconnects.
var contributors: Dictionary = {}
## Unit -> [time, position, error] of the last measured plot each own unit made of the contact,
## kept on the shared plot for a unit that has no picture of its own (TrackManager.keeps_own_picture).
var firm_looks: Dictionary = {}
var networked := true
var course_deg := 0.0
var speed_kn := 0.0
var has_kinematics := false
var classification := Classification.UNKNOWN
var identity := "UNKNOWN"  # UNKNOWN | HOSTILE (FRIENDLY / NEUTRAL later)
var status := Status.ACTIVE
var known_class := ""  # filled when classification reaches CLASS_KNOWN
var known_category := ""  # reported classification, never a UI lookup through truth
var known_callsign := ""  # only positive identification, never a timed signature match
var class_is_probable := false
var class_evidence := ""
var identity_evidence := ""
var signature_time_s := 0.0
var _cycle_signature_gain := 0.0
## Close-range radar observation of an aircraft toward a probable type (TrackManager).
var radar_recognition_s := 0.0
var _cycle_radar_gain := 0.0
## Saved bearing measurements, with observer positions and times, for deterministic TMA.
var bearing_history: Array = []
## Each listener's newest report in bearing_history (key -> that report), so a new look finds its
## sample without searching the history. Rebuilt from the history when empty.
var _bearing_latest: Dictionary = {}
var bearing_observers: Dictionary = {}
var bearing_solution_at := -1.0e9
var bearing_solution_cache: Dictionary = {}
var observation_time_s := 0.0
var first_seen_time := 0.0
var last_seen_time := 0.0
## When a measured plot (radar, active sonar, visual) last held this track. A bearing heard in
## the same moment adds nothing to the geometry, so it is not allowed to blur it.
var last_firm_time := -1.0e9
## When this side's own ESM last heard the contact transmit. See `radiating`.
var last_esm_time := -1.0e9
var _obs_times := PackedFloat64Array()  # sliding observation window for kinematics fit
var _obs_pos := PackedVector2Array()
## True once a position worked from bearings has gone into the window: a fit through those is
## thrown away when a measured plot arrives, a fit through measured plots is not.
var _obs_estimated := false
var _last_est_time := -1.0
var _cycle_start_position := Vector2.ZERO
var _cycle_start_major := 1.0
var _cycle_range_held := false
var _cycle_bearing_held := false
var _cycle_snap := false
var _cycle_has_plot := false
var _cycle_firm := false
var _cycle_error := INF
var _cycle_observation_gain := 0.0
var _cycle_tma_start := 0.0
## Decimated reported positions for the chart. Separate from the velocity-fit window.
var history_positions := PackedVector2Array()
var history_times := PackedFloat64Array()


func range_text_from(origin: Vector2) -> String:
	if is_bearing_only():
		return "RANGE UNRESOLVED"
	return "~%.1f nm ±%.1f" % [origin.distance_to(position), position_error_nm]


func age_s(now: float) -> float:
	return maxf(now - last_seen_time, 0.0)


func class_short() -> String:
	match classification:
		Classification.UNKNOWN:
			return "UNK"
		Classification.SURFACE:
			return _domain_short()
	return known_class


func _domain_short() -> String:
	match domain:
		"subsurface":
			return "SUB"
		"air":
			return "AIR"
		"land":
			return "SHORE"
	return "SURF"


## Whether the contact was heard radiating about when it was last held at all: what this side knows
## of its emissions, never a read of the unit's radar switch. An anti-radiation shot needs it.
const EMITTER_MEMORY_S := 120.0


func radiating() -> bool:
	return status != Status.LOST and last_esm_time >= last_seen_time - EMITTER_MEMORY_S


## True when the contact is held on a bearing alone, with no usable range.
func is_bearing_only() -> bool:
	return bearing_only and tma_quality < RANGE_HELD_QUALITY


## The own unit whose bearing the plot is following: the contributor still where the last bearing
## was taken from. Null for a line from a buoy, or once that unit has moved on or been lost.
func bearing_unit() -> Unit:
	if not bearing_origin.is_finite():
		return null
	for u: Unit in contributors:
		if u != null and u.alive and u.position.distance_to(bearing_origin) <= BEARING_UNIT_NM:
			return u
	return null


## What the contact moves like, from what the plot itself holds: its domain once that is known,
## else an aircraft if it has height or more speed than any ship. Empty when nothing says.
func mover() -> String:
	if domain != "":
		return domain
	if altitude_m > 0.0 or (has_kinematics and speed_kn > FASTEST_SHIP_KN):
		return "air"
	return ""


## How long after it was last held the plot stops counting as current.
func stale_after_s() -> float:
	return STALE_AFTER_AIR_S if mover() == "air" else STALE_AFTER_S


## Whether a weapon that needs a position (anything but a torpedo, or a missile that rides a
## radar's own beam) may be laid on this plot: this side's own sensors are holding it now, and its
## range is measured or soundly worked out. A stale plot is where the contact was, a report from
## outside was never a fire-control solution and a loose estimate is a place to search; a missile
## sent to any of them finds empty sea, or whatever else is there.
func fire_control_quality() -> bool:
	if status != Status.ACTIVE or reported or confirmed_destroyed:
		return false
	return not bearing_only or tma_quality >= FIRE_CONTROL_SOLUTION_QUALITY


## How long the contact is kept after it was last held, and how long a range is trusted once only
## bearings are coming in: two minutes for a jet, ten for a ship, half an hour for a submarine,
## a fixed site or an outside report.
func lost_after_s() -> float:
	if reported:
		return LOST_AFTER_S
	match mover():
		"air":
			return LOST_AFTER_SLOW_AIR_S if has_kinematics and speed_kn < SLOW_AIR_KN else LOST_AFTER_FAST_AIR_S
		"subsurface", "land":
			return LOST_AFTER_S
	return LOST_AFTER_SURFACE_S


## How fast the uncertainty grows while the contact is not being ranged, in nm a second.
func error_growth_nm_per_s() -> float:
	var known := speed_kn if has_kinematics else 0.0
	match mover():
		"land":
			return 0.0
		"air":
			return Geo.knots_to_nm_per_s(maxf(known, DRIFT_AIR_KN))
		"surface":
			return Geo.knots_to_nm_per_s(maxf(known, DRIFT_SURFACE_KN))
		"subsurface":
			return Geo.knots_to_nm_per_s(maxf(known, DRIFT_SUBSURFACE_KN))
	return ERROR_GROWTH_NM_PER_S


## Classification wording on its own, for panels that already show the track id.
func description() -> String:
	match classification:
		Classification.IDENTIFIED:
			return known_callsign
		Classification.CLASS_KNOWN:
			return known_class
		Classification.SURFACE:
			match domain:
				"subsurface":
					return "SUBSURFACE CONTACT"
				"air":
					return "AIR CONTACT"
				"land":
					return "SHORE INSTALLATION"
			return "SURFACE CONTACT"
	return "UNKNOWN CONTACT"


## Map label: track id plus the shortest useful description.
func label() -> String:
	match classification:
		Classification.IDENTIFIED:
			return known_callsign
		Classification.CLASS_KNOWN:
			return "%s %s" % [id, known_class]
		Classification.SURFACE:
			return "%s %s" % [id, _domain_short()]
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


func class_confidence_text() -> String:
	if classification == Classification.IDENTIFIED:
		return "VISUALLY CONFIRMED"
	if classification >= Classification.CLASS_KNOWN:
		return "PROBABLE CLASS" if class_is_probable else "CLASS CONFIRMED"
	if classification == Classification.SURFACE:
		return "DOMAIN CLASSIFIED"
	return "UNCLASSIFIED"


func solution_text() -> String:
	if reported:
		return "REPORTED DATUM"
	if is_bearing_only():
		return "BEARING ONLY"
	return "ESTIMATED FIX" if bearing_only else "MEASURED FIX"
