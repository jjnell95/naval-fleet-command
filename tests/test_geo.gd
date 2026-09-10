extends TestCase


func test_heading_vectors() -> void:
	assert_near(Geo.heading_to_vector(0.0).y, 1.0)
	assert_near(Geo.heading_to_vector(90.0).x, 1.0)
	assert_near(Geo.heading_to_vector(180.0).y, -1.0)
	assert_near(Geo.heading_to_vector(270.0).x, -1.0)


func test_bearing() -> void:
	var o := Vector2.ZERO
	assert_near(Geo.bearing_deg(o, Vector2(0, 10)), 0.0)
	assert_near(Geo.bearing_deg(o, Vector2(10, 0)), 90.0)
	assert_near(Geo.bearing_deg(o, Vector2(0, -10)), 180.0)
	assert_near(Geo.bearing_deg(o, Vector2(-10, 0)), 270.0)
	assert_near(Geo.bearing_deg(o, Vector2(10, 10)), 45.0)


func test_distance() -> void:
	assert_near(Geo.distance_nm(Vector2.ZERO, Vector2(3, 4)), 5.0)


func test_heading_delta() -> void:
	assert_near(Geo.heading_delta(350.0, 10.0), 20.0)
	assert_near(Geo.heading_delta(10.0, 350.0), -20.0)
	assert_near(absf(Geo.heading_delta(0.0, 180.0)), 180.0)


func test_format_bearing() -> void:
	assert_eq(Geo.format_bearing(5.0), "005")
	assert_eq(Geo.format_bearing(359.7), "000")
	assert_eq(Geo.format_bearing(-10.0), "350")


func test_knots() -> void:
	assert_near(Geo.knots_to_nm_per_s(3600.0), 1.0)
	assert_near(Geo.knots_to_nm_per_s(10.0) * 3600.0, 10.0)


func test_format_duration() -> void:
	assert_eq(Geo.format_duration(90061.0), "D+1 01:01:01")
