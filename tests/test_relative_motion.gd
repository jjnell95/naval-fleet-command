extends TestCase


func _ship() -> Unit:
	var u := Unit.new()
	u.spec = PlatformSpec.new()
	u.spec.has_datalink = true
	u.faction = "BLUE"
	u.heading_deg = 0.0
	u.speed_kn = 10.0
	return u


func _track() -> Track:
	var t := Track.new()
	t.owner_faction = "BLUE"
	t.position = Vector2(0, 5)
	t.course_deg = 180.0
	t.speed_kn = 10.0
	t.has_kinematics = true
	t.last_seen_time = 10.0
	return t


func test_head_on_cpa_uses_relative_speed() -> void:
	var result := RelativeMotion.solution(_ship(), _track(), 10.0)
	assert_true(result.valid)
	assert_near(result.time_s, 900.0, 0.01)
	assert_near(result.distance_nm, 0.0, 0.001)
	assert_near(result.closing_kn, 20.0, 0.001)


func test_parallel_and_opening_contacts_do_not_invent_future_cpa() -> void:
	var t := _track()
	t.course_deg = 0.0
	assert_eq(RelativeMotion.solution(_ship(), t, 10.0).reason, "STEADY RELATIVE POSITION")
	t.speed_kn = 20.0
	var result := RelativeMotion.solution(_ship(), t, 10.0)
	assert_true(not result.valid)
	assert_eq(result.reason, "OPENING / CPA HAS PASSED")
	assert_near(result.closing_kn, -10.0, 0.001)


func test_crossing_geometry_preserves_miss_distance() -> void:
	var ship := _ship()
	ship.speed_kn = 0.0
	var t := _track()
	t.position = Vector2(2, 3)
	var result := RelativeMotion.solution(ship, t, 10.0)
	assert_true(result.valid)
	assert_near(result.distance_nm, 2.0, 0.001)
	assert_near(result.time_s, 1080.0, 0.01)


func test_solution_withholds_unresolved_stale_and_private_tracks() -> void:
	var t := _track()
	t.bearing_only = true
	assert_true(not RelativeMotion.solution(_ship(), t, 10.0).valid)
	assert_eq(t.range_text_from(Vector2.ZERO), "RANGE UNRESOLVED")
	t.bearing_only = false
	assert_true(not RelativeMotion.solution(_ship(), t, 71.0).valid)
	t.networked = false
	assert_eq(RelativeMotion.solution(_ship(), t, 10.0).reason, "TRACK NOT HELD / OFF LINK")


func test_cpa_uses_reported_geometry_with_no_ground_truth_link() -> void:
	var t := _track()
	assert_true(t.truth == null)
	assert_true(RelativeMotion.solution(_ship(), t, 10.0).valid)
	t.position = Vector2(0, 50)
	assert_eq(RelativeMotion.solution(_ship(), t, 10.0).reason, "CPA BEYOND 30 MINUTES")
