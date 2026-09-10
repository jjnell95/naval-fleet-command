class_name Geo
## Geometry and unit helpers.
## World space: Vector2 in nautical miles, +x east, +y north.
## Headings/bearings: degrees true, 0 = north, clockwise. Speeds: knots.


static func heading_to_vector(deg: float) -> Vector2:
	var r := deg_to_rad(deg)
	return Vector2(sin(r), cos(r))


static func vector_to_heading(v: Vector2) -> float:
	return fposmod(rad_to_deg(atan2(v.x, v.y)), 360.0)


static func bearing_deg(from: Vector2, to: Vector2) -> float:
	return vector_to_heading(to - from)


static func distance_nm(a: Vector2, b: Vector2) -> float:
	return a.distance_to(b)


static func knots_to_nm_per_s(kn: float) -> float:
	return kn / 3600.0


## Signed shortest rotation from one heading to another, in (-180, 180].
static func heading_delta(from_deg: float, to_deg: float) -> float:
	return wrapf(to_deg - from_deg, -180.0, 180.0)


static func format_bearing(deg: float) -> String:
	return "%03d" % (int(roundf(fposmod(deg, 360.0))) % 360)


static func format_nm(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return "%d" % int(roundf(v))
	return "%.1f" % v


## Signed coordinate with cardinal prefix, e.g. "E 12.5" / "W 40".
static func format_axis(v: float, positive: String, negative: String) -> String:
	if absf(v) < 0.05:
		return "0"
	return "%s %s" % [positive if v > 0.0 else negative, format_nm(absf(v))]


static func format_duration(seconds: float) -> String:
	var s := int(seconds)
	@warning_ignore("integer_division")
	var d := s / 86400
	@warning_ignore("integer_division")
	var h := (s % 86400) / 3600
	@warning_ignore("integer_division")
	var m := (s % 3600) / 60
	return "D+%d %02d:%02d:%02d" % [d, h, m, s % 60]
