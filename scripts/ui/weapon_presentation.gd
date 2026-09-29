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


static func track_quality(track: Track, now: float, spec: WeaponSpec = null) -> String:
	if track == null:
		return "Hook a contact to inspect the firing solution."
	if track.is_bearing_only():
		return "BEARING ONLY: range unresolved. Torpedoes can search the estimated bearing; a missile needs a ranged plot."
	var text := "%s | last fix %ds | uncertainty +/-%.1f nm" % [track.status_text(now), int(track.age_s(now)), track.position_error_nm]
	if not track.has_kinematics:
		text += " | course / speed unresolved"
	if spec != null and track.position_error_nm > spec.acquisition_radius_nm():
		text += " | WARNING: uncertainty exceeds seeker basket"
	elif track.status == Track.Status.STALE:
		text += " | WARNING: extrapolated solution"
	return text
