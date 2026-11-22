extends TestCase
## Follow-ups from round 4 that no later stage owned: torpedo data whose wire guidance the
## weapon's own figures would infer wrongly, and a minimum range below the enable run.


func _weapon(id: String) -> WeaponSpec:
	return load("res://data/weapons/%s.tres" % id) as WeaponSpec


func test_torpedo_47_is_wire_guided_though_it_is_a_400_mm_weapon() -> void:
	var t := _weapon("torpedo47")
	assert_true(not t.is_heavyweight_torpedo(), "too light for the heavyweight inference")
	assert_eq(t.wire_guidance, 1)
	assert_true(t.wire_guided(), "the Swedish 400 mm torpedo is steered down its wire in service")


func test_paket_nk_runs_on_its_own_and_is_not_offered_inside_its_enable_run() -> void:
	var p := _weapon("paket_nk")
	assert_eq(p.wire_guidance, 0)
	assert_true(not p.wire_guided())
	assert_true(p.min_range_nm >= p.run_to_enable_nm + Combat.TORPEDO_ENABLE_MARGIN_NM - 0.001,
		"the authored minimum range is the range the launcher refuses inside")
	assert_near(p.min_range_nm, Combat.minimum_range_nm(p), 0.001)


func test_set_65_says_outright_that_it_is_not_wire_guided() -> void:
	var s := _weapon("cw90_set65")
	assert_eq(s.wire_guidance, 0)
	assert_true(not s.wire_guided())
