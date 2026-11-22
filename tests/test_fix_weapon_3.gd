extends TestCase
## Torpedoes that hunt for what they were sent at, and decoys that do what decoys do.

const DT := 0.25


func _platform(domain := "surface", max_speed := 30.0) -> PlatformSpec:
	var p := PlatformSpec.new()
	p.short_name = "Test %s" % domain
	p.domain = domain
	p.max_speed_kn = max_speed
	p.cruise_speed_kn = 15.0
	p.health = 100.0
	p.decoy_count = 0
	return p


func _unit(faction: String, pos: Vector2, domain := "surface", uid := 0) -> Unit:
	var u := Unit.new()
	u.spec = _platform(domain)
	u.faction = faction
	u.callsign = "%s %s" % [faction, domain]
	u.position = pos
	u.health = 100.0
	u.id = uid
	if domain == "subsurface":
		u.depth_m = 100.0
	return u


func _track(owner: Unit, pos: Vector2, domain := "surface") -> Track:
	var t := Track.new()
	t.id = "T1"
	t.owner_faction = owner.faction
	t.identity = "HOSTILE"
	t.domain = domain
	t.status = Track.Status.ACTIVE
	t.has_kinematics = true
	t.position = pos
	t.networked = false
	t.contributors[owner] = true
	return t


func _harness(units: Array, seed_value := 11) -> WeaponManager:
	var um := UnitManager.new()
	for u: Unit in units:
		um.add_unit(u)
	var wm := WeaponManager.new()
	wm.unit_manager = um
	wm.rng.seed = seed_value
	return wm


func _cleanup(wm: WeaponManager) -> void:
	wm.clear()
	wm.unit_manager.free()
	wm.free()


## Runs one round until it locks `target`, ends, or `limit_s` passes. Returns what it did.
func _run_round(wm: WeaponManager, round: Weapon, target: Unit, limit_s := 3000.0) -> Dictionary:
	var now := 0.0
	var acquired := false
	while now < limit_s and round.phase != Weapon.Phase.DEAD:
		now += DT
		wm.tick(DT, now)
		if round.acquired == target:
			acquired = true
			break
	return {"acquired": acquired, "time": now, "reason": round.dead_reason}


# --- c-weapons#4: wire, and a search that covers more than one lane ----------------------------

## A boat's first plot of a ship fifteen miles off is two miles out across the line of fire and does
## not improve. The heavyweight runs down the wire to the plot and weaves as it searches: it finds
## the ship on either side. A straight run passed two miles abeam with nothing in its cone.
func test_a_heavyweight_finds_a_ship_two_miles_off_its_plot() -> void:
	Terrain.clear()
	var wired := DataDB.weapon("mk48_adcap")
	# The same fish with its wire cut at the tube: the weave alone has to find the ship.
	var free_running: WeaponSpec = wired.duplicate()
	free_running.id = "mk48_no_wire"
	free_running.midcourse_updates = false
	free_running.wire_guidance = 0
	for case: Array in [[wired, 1.0], [wired, -1.0], [free_running, 1.0], [free_running, -1.0]]:
		var spec: WeaponSpec = case[0]
		var side: float = case[1]
		var boat := _unit("BLUE", Vector2.ZERO, "subsurface", 1)
		boat.weapons.append(spec)
		boat.magazines[spec.id] = 4
		var ship := _unit("RED", Vector2(0.0, 15.0), "surface", 2)
		var wm := _harness([boat, ship])
		var t := _track(boat, ship.position + Vector2(2.0 * side, 0.0))
		var check := wm.engagement_check(boat, spec, t, 0.0)
		assert_true(wm.launch(boat, spec, t, 1, 0.0), "the boat fires on its plot (%s)" % check["reason"])
		if wm.in_flight.is_empty():
			_cleanup(wm)
			continue
		var result := _run_round(wm, wm.in_flight[0], ship)
		assert_true(result["acquired"], "%s, plot 2 nm to the %s: the Mk 48 acquires the ship (ended %s)" % ["wired" if spec == wired else "no wire", "east" if side > 0.0 else "west", result["reason"]])
		_cleanup(wm)


## Wire guidance is a rule, not a list: an acoustic heavyweight is on a wire unless the data says it
## is not, a wake-homer and a lightweight are not, and the data's word wins either way.
func test_wire_guidance_is_inferred_for_heavyweights_and_the_data_can_overrule_it() -> void:
	var fish := WeaponSpec.new()
	fish.type = "torpedo"
	fish.guidance = "acoustic_homing"
	fish.max_range_nm = 20.0
	fish.damage = 90.0
	assert_true(fish.wire_guided(), "an acoustic heavyweight is wire guided by default")
	fish.wire_guidance = 0
	assert_true(not fish.wire_guided() and not fish.supports_midcourse_updates(), "the data can say it has no wire")
	var light := WeaponSpec.new()
	light.type = "torpedo"
	light.guidance = "acoustic_homing"
	light.max_range_nm = 6.0
	light.damage = 55.0
	assert_true(not light.wire_guided(), "a lightweight runs on its own")
	light.wire_guidance = 1
	assert_true(light.wire_guided(), "unless the data puts it on a wire")
	assert_true(not DataDB.weapon("cw90_53_65").wire_guided(), "a wake-homer is not on a wire")
	assert_true(DataDB.weapon("mk48_adcap").wire_guided(), "the Mk 48 is")


## The wire runs back to a tube. A heavyweight an aircraft put in the water takes no updates, and
## neither does one whose firing boat has lost the contact.
func test_the_wire_needs_a_tube_and_a_firer_that_holds_the_contact() -> void:
	var spec := DataDB.weapon("mk48_adcap")
	var boat := _unit("BLUE", Vector2.ZERO, "subsurface", 1)
	var plane := _unit("BLUE", Vector2.ZERO, "air", 3)
	plane.flight_state = Unit.FlightState.AIRBORNE
	plane.altitude_m = 300.0
	var ship := _unit("RED", Vector2(0.0, 10.0), "surface", 2)
	var wm := _harness([boat, plane, ship])
	var t := _track(boat, ship.position)
	t.contributors[plane] = true
	var w := Weapon.new()
	w.spec = spec
	w.target_track = t
	w.shooter = boat
	assert_true(wm.takes_updates(w), "a boat holding the contact steers its fish")
	w.shooter = plane
	assert_true(not wm.takes_updates(w), "an aircraft's torpedo has no wire")
	w.shooter = boat
	t.status = Track.Status.LOST
	assert_true(not wm.takes_updates(w), "a lost contact gives the wire nothing to send")
	_cleanup(wm)


# --- p-undersea#5: no shot inside the enable run, and a bounded search at the aim point --------

## A torpedo's seeker stays off until it has run out to its enable point. A shot from inside that
## run passes the target blind, so the launcher calls it too close, whatever the minimum range in
## the data says.
func test_a_torpedo_is_refused_inside_its_enable_run() -> void:
	var spec: WeaponSpec = DataDB.weapon("cw90_mk48").duplicate()
	spec.id = "short_fish"
	spec.min_range_nm = 0.4
	spec.run_to_enable_nm = 0.7
	var boat := _unit("BLUE", Vector2.ZERO, "subsurface", 1)
	boat.weapons.append(spec)
	boat.magazines[spec.id] = 4
	var ship := _unit("RED", Vector2(0.0, 0.8), "surface", 2)
	var wm := _harness([boat, ship])
	var t := _track(boat, ship.position)
	assert_eq(wm.engagement_check(boat, spec, t, 0.0)["reason"], "TOO CLOSE", "0.8 nm is inside the 0.7 nm run and its margin")
	t.position = Vector2(0.0, 1.2)
	ship.position = t.position
	assert_true(wm.engagement_check(boat, spec, t, 0.0)["ok"], "1.2 nm leaves the seeker room to look")
	_cleanup(wm)


## A plot eight miles off with nothing there. The fish runs to the plot, circles it for a bounded
## time and shuts down there; it does not run on down the bearing for the rest of its battery while
## the attack waits on it.
func test_a_torpedo_that_finds_nothing_circles_the_plot_and_then_shuts_down() -> void:
	Terrain.clear()
	var spec := DataDB.weapon("mk48_adcap")
	var boat := _unit("BLUE", Vector2.ZERO, "subsurface", 1)
	boat.weapons.append(spec)
	boat.magazines[spec.id] = 4
	var ship := _unit("RED", Vector2(40.0, 0.0), "surface", 2)
	var wm := _harness([boat, ship])
	var plot := Vector2(0.0, 8.0)
	var t := _track(boat, plot)
	assert_true(wm.launch(boat, spec, t, 1, 0.0), "the boat fires on the plot")
	var round: Weapon = wm.in_flight[0]
	var result := _run_round(wm, round, ship)
	var to_plot_s := Combat.time_of_flight_s(spec, 8.0) / WeaponManager.SNAKE_PROGRESS
	assert_eq(result["reason"], "NO ACQUISITION")
	assert_true(result["time"] <= to_plot_s + WeaponManager.CIRCLE_SEARCH_S + 10.0, "it gives up %.0f s after launch, not at the end of its run" % result["time"])
	assert_true(round.position.distance_to(plot) < 1.0, "it searched about the plot (ended %.2f nm from it)" % round.position.distance_to(plot))
	assert_true(round.distance_flown_nm < spec.max_range_nm * 0.6, "with most of its run unused (%.1f of %.1f nm)" % [round.distance_flown_nm, spec.max_range_nm])
	_cleanup(wm)


## The circle about the plot reaches as far either side of it: a ship at the very edge of the
## seeker's range from the plot, on either beam, is found there.
func test_the_search_about_the_plot_finds_a_ship_on_either_side() -> void:
	Terrain.clear()
	var spec := DataDB.weapon("cw90_mk48")
	for side: float in [1.0, -1.0]:
		var boat := _unit("BLUE", Vector2.ZERO, "subsurface", 1)
		boat.weapons.append(spec)
		boat.magazines[spec.id] = 4
		var ship := _unit("RED", Vector2(0.0, 12.0), "surface", 2)
		var wm := _harness([boat, ship])
		var t := _track(boat, ship.position + Vector2(spec.seeker_range_nm * side, 0.0))
		assert_true(wm.launch(boat, spec, t, 1, 0.0), "the boat fires on its plot")
		var result := _run_round(wm, wm.in_flight[0], ship)
		assert_true(result["acquired"], "ship %.1f nm to the %s of the plot is found (ended %s)" % [spec.seeker_range_nm, "west" if side > 0.0 else "east", result["reason"]])
		_cleanup(wm)


# --- c-weapons#9: running from a torpedo, not merely being fast -------------------------------

## Fires a stock Mk 48 into a 27 kn frigate from astern or abeam and reports the chance its
## impact was rolled at, the way WeaponManager rolls it.
func _impact_pk(heard: bool, target_heading: float) -> float:
	var spec := DataDB.weapon("mk48_adcap")
	var ship := _unit("RED", Vector2(0.0, 0.0), "surface", 2)
	ship.spec.max_speed_kn = 30.0
	ship.speed_kn = 27.0
	ship.heading_deg = target_heading
	var w := Weapon.new()
	w.spec = spec
	w.heading_deg = 0.0  # running north up the ship's wake, or across her bow
	w.acquired = ship
	if heard:
		w.heard_by[ship.id] = true
	return Combat.hit_probability(spec, ship, 5.0, WeaponManager.running_from(w, ship))


## A fast ship that has not heard the torpedo, or one that heard it and is crossing its track, is
## as easy to hit as a stopped one; only one running from a torpedo it heard is harder.
func test_only_a_ship_running_from_a_torpedo_it_heard_is_harder_to_hit() -> void:
	var spec := DataDB.weapon("mk48_adcap")
	var stopped := _unit("RED", Vector2.ZERO, "surface", 2)
	var base := Combat.hit_probability(spec, stopped, 5.0)
	assert_near(_impact_pk(false, 0.0), base, 0.001, "unalerted at 27 kn: the torpedo's full chance")
	assert_near(_impact_pk(true, 90.0), base, 0.001, "heard it, but crossing its track at 27 kn: no help")
	assert_true(_impact_pk(true, 20.0) < base * 0.7, "heard it and running from it: much harder (%.2f against %.2f)" % [_impact_pk(true, 20.0), base])


## The defence cycle is what tells a crew the torpedo is there: a ship that hears one homing on
## her is marked as having heard it.
func test_a_ship_that_hears_a_torpedo_homing_on_her_is_aware_of_it() -> void:
	var ship := _unit("BLUE", Vector2.ZERO, "surface", 5)
	ship.auto_countermeasures = false
	var deaf := _unit("BLUE", Vector2(0.0, 20.0), "surface", 6)
	var wm := _harness([ship, deaf])
	var tm := ThreatManager.new()
	var heard := Weapon.new()
	heard.id = 901
	heard.spec = DataDB.weapon("mk48_adcap")
	heard.faction = "RED"
	heard.position = Vector2(0.0, -1.5)
	heard.acquired = ship
	heard.phase = Weapon.Phase.TERMINAL
	var unheard := Weapon.new()
	unheard.id = 902
	unheard.spec = heard.spec
	unheard.faction = "RED"
	unheard.position = Vector2(0.0, 18.0)
	unheard.acquired = deaf
	unheard.phase = Weapon.Phase.TERMINAL
	wm.in_flight.append_array([heard, unheard])
	tm.mark_detected("BLUE", heard, 0.0, ship)
	TorpedoDefence.run_cycle(wm.unit_manager, tm, wm, 0.0)
	assert_true(heard.heard_by.has(ship.id), "the ship that heard it knows")
	assert_true(not unheard.heard_by.has(deaf.id), "a ship nobody has heard it near does not")
	tm.free()
	_cleanup(wm)
