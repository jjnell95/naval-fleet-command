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
