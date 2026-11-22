class_name CommanderPicture
extends RefCounted
## What the force commander is shown: the side's networked plot, always, together with the private
## picture of every own unit that is off the link but can still talk to him (a boat running deep
## under the Normal rules, a ship with no datalink). A comms-restricted boat that is out of contact
## adds nothing until its window opens. Which unit is hooked never changes any of it: the hook
## serves range and bearing read-outs only.
##
## Reads simulation state and nothing else, so the chart, the boards and the radio line can all ask
## the same question and get the same answer.

## The floor for a fitted force view: one ship alone still gets water round her to read.
const FORCE_VIEW_MIN_NM := 40.0


## Whether this unit's reports reach the commander now.
static func receives_report(u: Unit) -> bool:
	return u != null and (not SubmarineComms.restricted(u) or SubmarineComms.connected(u))


## Off the link, but still reporting what it holds by voice.
static func reports_privately(u: Unit) -> bool:
	return u != null and u.is_engageable() and not u.datalink_connected() and receives_report(u)


## The networked plot's own track on a unit, when the force's sensors hold it. A bare intelligence
## datum is a place to go and look, not a holding: a boat's own track on the same contact is worth
## more than it, and is the one the commander can lay a weapon on.
static func plotted(track_manager: TrackManager, faction: String, truth: Unit) -> Track:
	var t := track_manager.find_track(faction, truth)
	return t if t != null and not t.reported else null


## Every contact the commander holds, each shown once. A contact the networked plot holds is the
## plot's own track; one held only aboard an off-link unit is shown from that unit's picture.
## Returns the plot's own array when nothing is added to it: callers must not modify the result.
static func tracks(track_manager: TrackManager, unit_manager: UnitManager, faction: String) -> Array:
	if track_manager == null:
		return []
	var plot: Array = track_manager.get_tracks(faction)
	if unit_manager == null:
		return plot
	var out: Array = plot
	var added := {}
	for u: Unit in unit_manager.units:
		if u.faction != faction or not reports_privately(u):
			continue
		for t: Track in track_manager.tracks_for(u):
			if t.status == Track.Status.LOST or added.has(t.id) or plotted(track_manager, faction, t.truth) != null:
				continue
			if added.is_empty():
				out = plot.duplicate()
			added[t.id] = true
			# Whatever datum the plot had on it gives way to the boat's own track.
			out.erase(track_manager.find_track(faction, t.truth))
			out.append(t)
	return out


## Whether one track is part of that picture. A networked track stays the commander's after it is
## lost, so its last plot can still be reported.
static func holds(track_manager: TrackManager, unit_manager: UnitManager, faction: String, t: Track) -> bool:
	if t == null or t.owner_faction != faction:
		return false
	if t.networked:
		return true
	if track_manager == null or unit_manager == null:
		return false
	return tracks(track_manager, unit_manager, faction).has(t)


## The track the commander is shown on the contact a track follows: the same track, or the one
## that stands for the same contact in his picture (every picture gives a contact one number).
## Null when nobody he hears from holds it.
static func track_on(track_manager: TrackManager, unit_manager: UnitManager, faction: String, t: Track) -> Track:
	if t == null or track_manager == null:
		return null
	var shown: Array = tracks(track_manager, unit_manager, faction)
	if shown.has(t):
		return t
	if t.id != "":
		for held: Track in shown:
			if held.id == t.id:
				return held
	return null


## Whether the commander has been told of this inbound weapon: some unit he hears from holds it,
## on the link or by its own sensors.
static func sees_threat(unit_manager: UnitManager, threat_manager: ThreatManager, faction: String, w: Weapon) -> bool:
	if unit_manager == null or threat_manager == null or not threat_manager.is_detected(faction, w):
		return false
	for u: Unit in unit_manager.units:
		if u.faction == faction and u.alive and receives_report(u) and threat_manager.visible_to(u, w):
			return true
	return false


## Inbound weapons on the commander's picture, most urgent first (AirDefence's ordering).
static func inbound(unit_manager: UnitManager, threat_manager: ThreatManager, faction: String) -> Array:
	if unit_manager == null or threat_manager == null:
		return []
	return AirDefence.inbound_threats(unit_manager, threat_manager, faction).filter(func(e: Dictionary) -> bool:
		return sees_threat(unit_manager, threat_manager, faction, e["weapon"]))


## A warship on the link: the kind of unit a commander rides and reads ranges from. Never a
## merchant (no datalink), an airframe or a shore installation.
static func is_linked_combatant(u: Unit) -> bool:
	return u != null and u.alive and u.needs_sea_room() and u.spec.max_speed_kn > 0.0 and u.datalink_connected() and not u.weapons.is_empty()


## The first warship on the link, in the force's own order, or null.
static func first_linked_combatant(unit_manager: UnitManager, faction: String) -> Unit:
	if unit_manager == null:
		return null
	for u: Unit in unit_manager.units:
		if u.faction == faction and is_linked_combatant(u):
			return u
	return null


## The unit a fresh watch opens on: a warship on the link if the force has one, otherwise anything
## on the link that is up and working (an aircraft in the air, a shore station), otherwise an armed
## unit that still reports (a boat running deep). Never a merchant and never an airframe on deck;
## null when the force has nothing of the kind, and the watch then opens with nothing hooked.
static func default_hook(unit_manager: UnitManager, faction: String) -> Unit:
	var flag := first_linked_combatant(unit_manager, faction)
	if flag != null or unit_manager == null:
		return flag
	for u: Unit in unit_manager.units:
		if u.faction == faction and u.is_engageable() and u.datalink_connected():
			return u
	for u: Unit in unit_manager.units:
		if u.faction == faction and u.is_engageable() and not u.weapons.is_empty() and receives_report(u):
			return u
	return null


## The ships and boats the commander manoeuvres, where he last heard of them: not the air base two
## hundred miles behind, nor the aircraft over it.
static func force_points(unit_manager: UnitManager, faction: String) -> PackedVector2Array:
	var points := PackedVector2Array()
	if unit_manager == null:
		return points
	for u: Unit in unit_manager.units:
		if u.faction == faction and u.alive and u.needs_sea_room() and u.spec.max_speed_kn > 0.0:
			points.append(SubmarineComms.reported_position(u))
	return points


## The chart view that frames those points with sea room round them: Vector3(centre x, centre y,
## extent in nautical miles), or Vector3.ZERO with a zero extent when there is no force afloat.
static func force_view(unit_manager: UnitManager, faction: String) -> Vector3:
	var points := force_points(unit_manager, faction)
	if points.is_empty():
		return Vector3.ZERO
	var lo := points[0]
	var hi := points[0]
	for p in points:
		lo = lo.min(p)
		hi = hi.max(p)
	var centre := (lo + hi) * 0.5
	return Vector3(centre.x, centre.y, maxf(maxf(hi.x - lo.x, hi.y - lo.y) * 1.5 + 12.0, FORCE_VIEW_MIN_NM))
