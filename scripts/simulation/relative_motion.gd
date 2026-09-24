class_name RelativeMotion
extends RefCounted
## Constant-course relative-motion estimate from the console's track, never target truth.
## This is a planning aid. Own/target manoeuvres and track error invalidate the extrapolation.

const HORIZON_S := 1800.0
const MIN_RELATIVE_SPEED_KN := 0.1


static func solution(own: Unit, track: Track, now: float) -> Dictionary:
	var result := {"valid": false, "reason": "SELECT A REFERENCE SHIP"}
	if own == null or track == null:
		return result
	if not track.visible_to(own):
		result.reason = "TRACK NOT HELD / OFF LINK"
		return result
	if track.status != Track.Status.ACTIVE or track.age_s(now) > Track.STALE_AFTER_S:
		result.reason = "STALE CONTACT / REACQUIRE"
		return result
	if track.is_bearing_only():
		result.reason = "BEARING ONLY / RANGE UNRESOLVED"
		return result
	if not track.has_kinematics:
		result.reason = "ESTIMATING COURSE AND SPEED"
		return result
	var own_velocity := Geo.heading_to_vector(own.heading_deg) * Geo.knots_to_nm_per_s(own.speed_kn)
	var contact_velocity := Geo.heading_to_vector(track.course_deg) * Geo.knots_to_nm_per_s(track.speed_kn)
	var separation := track.position - own.position
	var velocity := contact_velocity - own_velocity
	var range_nm := separation.length()
	result["closing_kn"] = -separation.dot(velocity) / maxf(range_nm, 0.001) * 3600.0
	if velocity.length() < Geo.knots_to_nm_per_s(MIN_RELATIVE_SPEED_KN):
		result.reason = "STEADY RELATIVE POSITION"
		return result
	var time_s := -separation.dot(velocity) / velocity.length_squared()
	if time_s < 0.0:
		result.reason = "OPENING / CPA HAS PASSED"
		return result
	if time_s > HORIZON_S:
		result.reason = "CPA BEYOND 30 MINUTES"
		return result
	result["valid"] = true
	result["reason"] = "CONSTANT COURSE ESTIMATE"
	result["time_s"] = time_s
	result["own_position"] = own.position + own_velocity * time_s
	result["contact_position"] = track.position + contact_velocity * time_s
	result["distance_nm"] = (result.own_position as Vector2).distance_to(result.contact_position)
	result["uncertainty_nm"] = track.position_error_nm
	return result
