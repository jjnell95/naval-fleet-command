extends TestCase
## A conventional boat lives on its battery. These pin what that means: speed is paid for with
## the cube, an air-independent plant covers a crawl and nothing more, a flat battery stops the
## boat, charging means diesels, and diesels are loud and visible.

const DT := 0.25


func _boat(sprint_h := 1.0, hotel_h := 200.0, aip_h := 0.0, aip_kn := 0.0) -> Unit:
	var p := PlatformSpec.new()
	p.short_name = "SSK Test"
	p.domain = "subsurface"
	p.max_speed_kn = 20.0
	p.cruise_speed_kn = 6.0
	p.accel_kn_s = 1.0
	p.turn_rate_deg_s = 3.0
	p.acoustic_signature = 0.05
	p.signature_factor = 0.25
	p.max_depth_m = 240.0
	p.patrol_depth_m = 90.0
	p.depth_rate_m_s = 2.0
	p.health = 45.0
	p.battery_sprint_h = sprint_h
	p.battery_hotel_h = hotel_h
	p.battery_charge_h = 3.0
	p.aip_endurance_h = aip_h
	p.aip_speed_kn = aip_kn
	var u := Unit.new()
	u.spec = p
	u.faction = "RED"
	u.callsign = "KILO"
	u.depth_m = 90.0
	u.ordered_depth_m = 90.0
	u.health = p.health
	return u


func _run(u: Unit, seconds: float, speed := -1.0) -> void:
	if speed >= 0.0:
		u.ordered_speed_kn = speed
	var t := 0.0
	while t < seconds:
		Movement.step(u, DT)
		t += DT


func _before() -> void:
	Terrain.clear()
	Detection.set_environment({})
	SubmarinePower.take_events()


func test_a_nuclear_boat_has_no_battery_to_run_down() -> void:
	_before()
	var u := _boat(0.0)
	_run(u, 3600.0, 20.0)
	assert_true(not (SubmarinePower.fitted(u)), "no sprint figure means no battery model")
	assert_near(u.battery, 1.0, 0.0001, "untouched")
	assert_near(u.speed_kn, 20.0, 0.01, "and no speed limit")


func test_an_hour_flat_out_empties_the_battery_and_a_crawl_barely_touches_it() -> void:
	_before()
	var sprint := _boat()
	_run(sprint, 1800.0, 20.0)
	assert_true(sprint.battery < 0.55 and sprint.battery > 0.4, "half an hour at 20 kn costs about half: %.2f" % sprint.battery)
	var crawl := _boat()
	_run(crawl, 1800.0, 4.0)
	assert_true(crawl.battery > 0.99, "half an hour at 4 kn costs under one percent: %.3f" % crawl.battery)
	# The cube: twice the speed, eight times the propulsion load.
	var spec := sprint.spec
	var hotel := 1.0 / spec.battery_hotel_h
	assert_near((SubmarinePower.drain_per_hour(spec, 16.0) - hotel) / (SubmarinePower.drain_per_hour(spec, 8.0) - hotel), 8.0, 0.001, "cube law")


func test_a_flat_battery_leaves_steerage_way_only_and_reports_on_the_way_down() -> void:
	_before()
	var u := _boat()
	u.battery = 0.32
	_run(u, 3600.0, 20.0)
	assert_near(u.battery, 0.0, 0.0001, "flat")
	assert_true(u.speed_kn <= SubmarinePower.EXHAUSTED_SPEED_KN + 0.01, "held to steerage way, making %.1f" % u.speed_kn)
	var seen: Array = SubmarinePower.take_events().map(func(e: Dictionary) -> String: return e["event"])
	assert_eq(seen, ["battery_low", "battery_critical", "battery_flat"], "each threshold reported once, in order")


func test_an_air_independent_plant_carries_a_crawl_but_not_a_sprint() -> void:
	_before()
	var u := _boat(1.0, 200.0, 240.0, 5.0)
	_run(u, 3600.0, 5.0)
	assert_near(u.battery, 1.0, 0.0001, "the battery is not touched at AIP speed")
	assert_near(SubmarinePower.aip_left_s(u), 239.0 * 3600.0, 30.0, "an hour of the plant is used")
	_run(u, 900.0, 18.0)
	assert_true(u.battery < 0.9, "above AIP speed the battery takes the load: %.2f" % u.battery)


func test_snorkelling_charges_is_loud_shows_on_radar_and_is_slow() -> void:
	_before()
	var u := _boat()
	u.battery = 0.2
	u.ordered_speed_kn = 12.0
	var quiet := Detection.acoustic_noise(u)
	assert_true(UnitManager.can_accept_order(u, Order.snorkel(true)), "a boat with a low battery may snorkel")
	u.apply_order(Order.snorkel(true))
	assert_near(u.ordered_depth_m, SubmarinePower.SNORKEL_DEPTH_M, 0.01, "comes up to snorkel depth")
	assert_true(not (SubmarinePower.on_diesels(u)), "not charging until the mast is out of the water")
	_run(u, 120.0)
	assert_true(SubmarinePower.snorkelling(u), "snorkelling at %.0f m" % u.depth_m)
	assert_true(u.speed_kn <= SubmarinePower.SNORKEL_SPEED_KN + 0.01, "held to snorkel speed, making %.1f" % u.speed_kn)
	var before := u.battery
	_run(u, 1800.0)
	assert_near(u.battery - before, 1800.0 / (3.0 * 3600.0), 0.002, "a three-hour charge puts back a sixth in half an hour")
	u.speed_kn = 0.0
	var loud := Detection.acoustic_noise(u)
	u.snorkel_on = false
	assert_near(loud / Detection.acoustic_noise(u), SubmarinePower.DIESEL_NOISE, 0.001, "diesels multiply radiated noise")
	assert_true(quiet > 0.0, "sanity")
	var periscope := Detection.radar_signature_of(u)
	u.snorkel_on = true
	assert_near(Detection.radar_signature_of(u) / periscope, SubmarinePower.SNORKEL_RADAR_SIGNATURE / Detection.RADAR_PERISCOPE_SIGNATURE, 0.001, "a snorkel head is a bigger radar target than a periscope")


func test_the_crew_secures_when_charged_and_goes_back_to_depth() -> void:
	_before()
	var u := _boat()
	u.battery = 0.97
	u.apply_order(Order.snorkel(true))
	_run(u, 900.0, 5.0)
	assert_true(not (u.snorkel_on), "secured when the charge is complete")
	assert_near(u.battery, 1.0, 0.03, "charged, less what the run back down has cost")
	assert_near(u.ordered_depth_m, 90.0, 0.01, "ordered back to the depth it came up from")
	assert_eq(u.snorkel_note, "charged", "and says why")
	assert_true(SubmarinePower.take_events().any(func(e: Dictionary) -> bool: return e["event"] == "battery_charged"), "reported")
	assert_true(not (UnitManager.can_accept_order(u, Order.snorkel(true))), "a full battery has nothing to charge")


func test_evasion_and_a_deep_order_both_bring_the_mast_down() -> void:
	_before()
	var u := _boat()
	u.battery = 0.5
	u.apply_order(Order.snorkel(true))
	_run(u, 120.0, 5.0)
	u.evasion_remaining_s = 60.0
	u.evasion_course_deg = 90.0
	_run(u, 1.0)
	assert_true(not (u.snorkel_on), "a boat turning away from a weapon stops charging")
	assert_near(u.ordered_depth_m, 90.0, 0.01, "and goes back down")
	u.evasion_remaining_s = 0.0
	u.apply_order(Order.snorkel(true))
	u.apply_order(Order.set_depth(150.0))
	assert_true(not (u.snorkel_on), "an order deep secures the snorkel")
	assert_near(u.ordered_depth_m, 150.0, 0.01, "and the ordered depth stands")
	u.apply_order(Order.snorkel(true))
	u.apply_order(Order.set_depth(10.0))
	assert_true(u.snorkel_on, "a shallower depth does not")


func test_the_catalogue_gives_every_conventional_boat_a_battery_and_no_nuclear_boat_one() -> void:
	var conventional := 0
	for spec: PlatformSpec in DataDB.all_platforms():
		if spec.domain != "subsurface":
			continue
		var diesel := spec.category.contains("diesel") or spec.category.contains("midget")
		assert_eq(spec.battery_sprint_h > 0.0, diesel, "%s: battery fitted exactly when conventional" % spec.id)
		if diesel:
			conventional += 1
			assert_true(spec.battery_hotel_h > 0.0 and spec.battery_charge_h > 0.0, "%s: complete figures" % spec.id)
			var at_cruise := 1.0 / SubmarinePower.drain_per_hour(spec, spec.cruise_speed_kn)
			assert_true(at_cruise > 8.0 and 1.0 / SubmarinePower.drain_per_hour(spec, spec.max_speed_kn) < 3.0, "%s: hours at cruise %.0f, far more than at full speed" % [spec.id, at_cruise])
	assert_eq(conventional, 7, "seven conventional boats in the catalogue")
