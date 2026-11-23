extends TestCase
## The Strait of Hormuz briefing tells the commander to kill the Mohajer drones early, because the
## Khalij Fars battery fires on what they report. Doing so has to score at least as well as letting
## the fire mission come and killing them afterwards: the bonus for both drones is on offer from
## the first second, an early kill still calls off the fire mission, and the fire mission still
## comes on its roll while the drones are up.

const HORMUZ := "res://data/scenarios/gulf_01_hormuz.json"
const DRONES := ["Mohajer 81", "Mohajer 82"]


func _open(seed_value: int) -> Simulation:
	SimClock.set_paused(true)
	var sim := Simulation.new()
	sim.seed_override = seed_value
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	assert_true(sim.load_scenario(HORMUZ), HORMUZ)
	return sim


func _close(sim: Simulation) -> void:
	sim.unit_manager.clear()
	sim.get_parent().remove_child(sim)
	sim.free()


func _named(sim: Simulation, callsign: String) -> Unit:
	for u: Unit in sim.unit_manager.units:
		if u.callsign == callsign:
			return u
	return null


func _shoot_down(sim: Simulation) -> void:
	for name: String in DRONES:
		var drone := _named(sim, name)
		assert_true(drone != null, "%s is in the engagement" % name)
		if drone != null:
			Damage.apply(drone, drone.spec.health * 10.0, "", "BLUE")


func _drone_tasks(sim: Simulation) -> Array:
	return sim.mission_manager.victory_objectives.filter(func(o: MissionObjective) -> bool: return o.id == "drones_down")


## A seed whose fire mission comes up on its roll, or whose roll fails, so each case is tested on
## the draw it needs rather than on a seed number that a change to the event list would move.
func _seed_where_fire_mission(happens: bool) -> int:
	for seed_value: int in range(1, 40):
		var sim := _open(seed_value)
		var drawn: Dictionary = sim.director.variant.get("fire_mission", {})
		_close(sim)
		if bool(drawn.get("happens", false)) == happens:
			return seed_value
	return -1


func test_the_drone_bonus_is_offered_from_the_start() -> void:
	var sim := _open(2)
	SimClock.advance(1.0)
	var tasks := _drone_tasks(sim)
	assert_eq(tasks.size(), 1, "shooting down both drones is a task from the first second")
	if tasks.size() == 1:
		var task: MissionObjective = tasks[0]
		assert_true(task.optional, "and a bonus, never needed for the win")
	assert_eq(int(sim.mission_manager.assessment()["bonus_total"]), 1, "the assessment counts it before any shot is fired")
	var orders := " ".join(PackedStringArray(sim.scenario.get("first_orders", [])))
	assert_true(orders.contains("bonus"), "the first orders say that the drones are a bonus: %s" % orders)
	_close(sim)


## Following the briefing: both drones down well before the ballistic battery can come out. The
## fire mission is called off, as it always was, and the bonus is credited, which it never was.
func test_killing_the_drones_early_cancels_the_fire_mission_and_earns_the_bonus() -> void:
	var seed_value := _seed_where_fire_mission(true)
	assert_true(seed_value > 0, "some seed draws the fire mission")
	var sim := _open(seed_value)
	SimClock.advance(120.0)
	_shoot_down(sim)
	SimClock.advance(3200.0)  # past the ballistic battery's latest moment
	assert_true(sim.director.fired.has("ballistic_battery_up"), "the ballistic battery has come out")
	assert_eq(str(sim.director.skipped.get("fire_mission", "")), "unless", "the early kill called off the fire mission")
	var tasks := _drone_tasks(sim)
	assert_eq(tasks.size(), 1, "the drone task is listed once")
	if tasks.size() == 1:
		assert_true((tasks[0] as MissionObjective).complete, "and it is done")
	var a := sim.mission_manager.assessment()
	assert_eq(int(a["bonus_done"]), 1, "the early kill is credited")
	assert_eq(int(a["bonus_total"]), 1, "against the one bonus on offer")
	_close(sim)


## The drones left alone: the fire mission still comes on its roll once the ballistic battery is
## out, its order no longer offers a bonus the commander already holds, and killing the drones
## afterwards still earns the same one bonus.
func test_the_fire_mission_still_comes_while_the_drones_are_up() -> void:
	var seed_value := _seed_where_fire_mission(true)
	var sim := _open(seed_value)
	SimClock.advance(60.0)
	assert_true(_named(sim, DRONES[0]).alive and _named(sim, DRONES[1]).alive, "the drones are up")
	# The battery's own trigger is the enemy plot; standing it up now keeps the drones alive
	# through the moment the fire mission is decided, whatever the escorts' radars do.
	sim.director.fired["ballistic_battery_up"] = SimClock.sim_time
	SimClock.advance(5.0)
	assert_true(sim.director.fired.has("fire_mission"), "the fire mission comes on its roll (seed %d)" % seed_value)
	var message := str(sim.director.event("fire_mission").get("message", ""))
	assert_true(not message.contains("bonus task"), "the fire mission does not announce a bonus already on offer: %s" % message)
	assert_true(message.contains("ballistic fire"), "it still warns of the fire: %s" % message)
	var logged := sim.mission_manager.tasking_updates.filter(func(t: Dictionary) -> bool: return str(t["text"]).contains("Khalij Fars"))
	assert_eq(logged.size(), 1, "and stands in the briefing's tasking updates")
	_shoot_down(sim)
	SimClock.advance(5.0)
	assert_eq(_drone_tasks(sim).size(), 1, "the drone task is still listed once")
	var a := sim.mission_manager.assessment()
	assert_eq(int(a["bonus_done"]), 1, "a late kill earns the bonus")
	assert_eq(int(a["bonus_total"]), 1, "and the same single bonus as an early one")
	_close(sim)


## A roll that does not come up leaves no fire mission, and the drones still pay.
func test_without_the_fire_mission_the_drones_still_pay() -> void:
	var seed_value := _seed_where_fire_mission(false)
	assert_true(seed_value > 0, "some seed draws no fire mission")
	var sim := _open(seed_value)
	SimClock.advance(60.0)
	_shoot_down(sim)
	SimClock.advance(5.0)
	assert_eq(int(sim.mission_manager.assessment()["bonus_done"]), 1, "seed %d: the kill is credited" % seed_value)
	_close(sim)
