extends TestCase


func _fleet(manager: UnitManager) -> Array[WeakRef]:
	var carrier := Unit.new()
	var aircraft := Unit.new()
	carrier.embarked.append(aircraft)
	aircraft.home = carrier
	aircraft.formation_leader = carrier
	aircraft.tanking_on = carrier
	manager.add_unit(carrier)
	manager.add_unit(aircraft)
	Detection.jammers.append(carrier)
	return [weakref(carrier), weakref(aircraft)]


func test_scenario_clear_releases_carrier_and_air_wing_cycles() -> void:
	var manager := UnitManager.new()
	for i in 5:
		var references := _fleet(manager)
		manager.clear()
		for reference in references:
			assert_true(reference.get_ref() == null, "restarting must release the previous fleet")
	assert_true(Detection.jammers.is_empty(), "retired jammers cannot survive into another scenario")
	manager.free()


func test_manager_destruction_also_releases_the_fleet() -> void:
	var manager := UnitManager.new()
	var references := _fleet(manager)
	manager.free()
	for reference in references:
		assert_true(reference.get_ref() == null, "shutdown must break the same ownership cycles")
