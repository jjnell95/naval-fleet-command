class_name WeaponPresentation
## Consistent role names, chart colours and uncertainty language. Identity colours on NTDS
## contact frames remain unchanged; only own weapon overlays use these role colours.

const ROLES := ["all", "air", "surface", "subsurface", "land", "gun"]
const LABELS := ["ALL SYSTEMS", "AIR DEFENCE", "ANTI-SHIP", "ASW", "LAND STRIKE", "GUNS / CIWS"]


static func role_key(spec: WeaponSpec) -> String:
	if spec.type in ["gun", "ciws"]:
		return "gun"
	if spec.type in ["torpedo", "asw_rocket"]:
		return "subsurface"
	if spec.type in ["sam", "aam"]:
		return "air"
	return "land" if spec.target_types.has("land") and not spec.target_types.has("surface") else "surface"


static func role_name(spec: WeaponSpec) -> String:
	if spec.type == "bomb":
		return "BOMB"
	if spec.type == "asw_rocket":
		return "ASW ROCKET"
	if spec.type == "ciws":
		return "CIWS"
	return {"gun": "GUN", "subsurface": "TORPEDO", "air": "AAM" if spec.type == "aam" else "SAM", "surface": "ANTI-SHIP", "land": "LAND STRIKE"}[role_key(spec)]


static func matches(spec: WeaponSpec, role: String) -> bool:
	return role == "all" or (role == "gun" and spec.type in ["gun", "ciws"]) or spec.target_types.has(role)


static func color(spec: WeaponSpec) -> Color:
	return role_color(role_key(spec))


static func role_color(role: String) -> Color:
	return {"air": Color("79bfff"), "surface": Color("f5bf68"), "subsurface": Color("67d3c4"), "land": Color("d4a0ed"), "gun": Color("eeeead")}.get(role, Color.WHITE)


static func track_quality(track: Track, now: float, spec: WeaponSpec = null, shooter: Unit = null, held_tracks: Array = []) -> String:
	if track == null:
		return "Hook a contact to inspect the firing solution."
	var text := "BEARING ONLY: range unresolved. Torpedoes can search the estimated bearing; a missile needs a ranged plot." if track.is_bearing_only() else "%s | last fix %ds | uncertainty +/-%.1f nm" % [track.status_text(now), int(track.age_s(now)), track.position_error_nm]
	if not track.has_kinematics:
		text += " | course / speed unresolved"
	if spec != null and track.position_error_nm > spec.acquisition_radius_nm():
		text += " | WARNING: uncertainty exceeds seeker basket"
	elif track.status == Track.Status.STALE:
		text += " | WARNING: extrapolated solution"
	if spec != null:
		text += " | " + ("supported midcourse updates" if spec.supports_midcourse_updates() else "launch solution retained")
		var traffic := protected_contact_warning(shooter, spec, track, held_tracks)
		if traffic != "":
			text += "\n" + traffic
	return text


## Conservative traffic advisory from the shooter's held picture only. The prediction combines
## reported traffic uncertainty with the terminal search area; it never consults Track.truth.
## This is an advisory, not perfect identification inside the real weapon's seeker.
static func protected_contacts_at_risk(shooter: Unit, spec: WeaponSpec, target: Track, held_tracks: Array) -> Array[Track]:
	var risks: Array[Track] = []
	if shooter == null or spec == null or target == null or spec.seeker_range_nm <= 0.0:
		return risks
	var reported := SubmarineComms.reported_position(shooter)
	var aim := Combat.intercept_point(reported, spec.speed_kn, target.position, target.course_deg, target.speed_kn, target.has_kinematics)
	if not aim.is_finite():
		return risks
	var path := aim - reported
	var length := path.length()
	if length <= 0.001:
		return risks
	var radius := spec.acquisition_radius_nm()
	var search_from := reported + path.normalized() * maxf(length - radius, 0.0)
	# Along this final leg a forward seeker can find traffic ahead or to either side of the
	# intended plot. Expanding by reported uncertainty errs toward a useful warning.
	for contact: Track in held_tracks:
		if contact == target or contact.status == Track.Status.LOST or not contact.visible_to(shooter):
			continue
		if contact.identity not in ["NEUTRAL", "FRIENDLY"] or not Combat.suits_track(spec, contact):
			continue
		var uncertainty := maxf(contact.position_error_nm, 0.0) + maxf(target.position_error_nm, 0.0)
		var risk_radius := radius + uncertainty
		if WeaponManager._segment_distance_squared(search_from, aim, contact.position) <= risk_radius * risk_radius:
			risks.append(contact)
	return risks


static func protected_contact_warning(shooter: Unit, spec: WeaponSpec, target: Track, held_tracks: Array) -> String:
	var risks := protected_contacts_at_risk(shooter, spec, target, held_tracks)
	if risks.is_empty():
		return ""
	var ids: PackedStringArray = []
	for contact: Track in risks:
		ids.append(contact.id)
	return "TRAFFIC RISK: %s reported in terminal search area. Confirm geometry before firing." % ", ".join(ids)
