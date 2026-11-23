extends TestCase
## The 3D pane at the scale of a large fleet, its right-click, and the panels beside it that
## redraw only when what they show changes.

const ENV := {"visibility_nm": 10.0}


func _unit(pid: String, faction: String, pos: Vector2, callsign := "") -> Unit:
	var spec := DataDB.platform(pid)
	var u := Unit.new()
	u.spec = spec
	u.faction = faction
	u.callsign = callsign if callsign != "" else "%s %s" % [faction, pid]
	u.position = pos
	u.health = spec.health
	return u


func _hold(tm: TrackManager, id: String, truth: Unit, position: Vector2) -> Track:
	var t := Track.new()
	t.id = id
	t.owner_faction = "BLUE"
	t.truth = truth
	t.position = position
	t.status = Track.Status.ACTIVE
	t.classification = Track.Classification.SURFACE
	t.domain = "surface"
	t.identity = "HOSTILE"
	var list: Array = tm._tracks.get("BLUE", [])
	list.append(t)
	tm._tracks["BLUE"] = list
	return t


func _keys(entries: Array) -> Array:
	var out: Array = []
	for e: Dictionary in entries:
		out.append(e["key"])
	out.sort()
	return out


## 100 own ships, 60 of them massed round the middle, and 200 others spread over a theatre
## several times the pane's reach, half of the others held as contacts a little off where they
## really are.
func _fleet(um: UnitManager, tm: TrackManager) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in 100:
		var spread := 25.0 if i < 60 else 120.0
		um.add_unit(_unit("cw90_ticonderoga", "BLUE", Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread)), "BLUE %d" % i))
	for i in 200:
		var red := _unit("cw90_slava", "RED", Vector2(rng.randf_range(-150.0, 150.0), rng.randf_range(-150.0, 150.0)))
		um.add_unit(red)
		if i % 2 == 0:
			_hold(tm, "T%04d" % (1000 + i), red, red.position + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5)))


func test_a_300_unit_fleet_builds_no_more_entries_than_the_view_keeps() -> void:
	var um := UnitManager.new()
	var tm := TrackManager.new()
	_fleet(um, tm)
	assert_eq(um.units.size(), 300)
	for centre: Vector2 in [Vector2.ZERO, Vector2(60, -40), Vector2(-110, 95)]:
		var built := WorldPresentation.unit_entries(um, tm, "BLUE", ENV, PackedStringArray(), centre, WorldPresentation.MAX_RANGE_NM, WorldPresentation.MAX_ENTITIES)
		var kept := WorldPresentation.cull(built, centre)
		if centre == Vector2.ZERO:
			assert_eq(kept.size(), WorldPresentation.MAX_ENTITIES, "the massed force fills the view's budget")
		assert_true(built.size() <= kept.size(), "round %s the view builds %d entries and keeps %d" % [centre, built.size(), kept.size()])
		var everything := WorldPresentation.unit_entries(um, tm, "BLUE", ENV)
		assert_true(everything.size() > 3 * kept.size(), "the theatre holds far more than the view shows")
		assert_eq(_keys(kept), _keys(WorldPresentation.cull(everything, centre)), "and it shows exactly what building everything and culling would have shown, round %s" % centre)
	um.free()
	tm.free()


func test_the_hook_and_the_action_subject_are_built_however_far_off() -> void:
	var um := UnitManager.new()
	var tm := TrackManager.new()
	_fleet(um, tm)
	var far_own := _unit("cw90_ticonderoga", "BLUE", Vector2(400, 0), "FAR")
	um.add_unit(far_own)
	var far_red := _unit("cw90_slava", "RED", Vector2(-400, 0))
	um.add_unit(far_red)
	_hold(tm, "T9999", far_red, Vector2(-399, 1))
	var keep := PackedStringArray(["u:%d" % far_own.id, "t:T9999"])
	var built := WorldPresentation.unit_entries(um, tm, "BLUE", ENV, PackedStringArray(), Vector2.ZERO, WorldPresentation.MAX_RANGE_NM, WorldPresentation.MAX_ENTITIES, keep)
	var kept := WorldPresentation.cull(built, Vector2.ZERO, "u:%d" % far_own.id, WorldPresentation.MAX_RANGE_NM, WorldPresentation.MAX_ENTITIES, "t:T9999")
	assert_eq(kept[0]["key"], "u:%d" % far_own.id, "the hooked ship 400 nm off is still the subject")
	assert_eq(kept[1]["key"], "t:T9999", "and the contact Action follows is still drawn")
	assert_eq(kept[0]["label"], "FAR", "with its label")
	var alone := WorldPresentation.unit_entries(um, tm, "BLUE", ENV, PackedStringArray(), Vector2.ZERO, -1.0, 0, PackedStringArray(["t:T9999"]))
	assert_eq(_keys(alone), ["t:T9999"], "asked for one subject alone, only that is built")
	um.free()
	tm.free()


func test_a_contact_seen_beyond_the_view_is_not_drawn_as_its_plot_inside_it() -> void:
	var um := UnitManager.new()
	var tm := TrackManager.new()
	var own := _unit("cw90_ticonderoga", "BLUE", Vector2(36, 0))
	var red := _unit("cw90_slava", "RED", Vector2(42, 0))
	um.add_unit(own)
	um.add_unit(red)
	_hold(tm, "T1001", red, Vector2(39, 0))
	var built := WorldPresentation.unit_entries(um, tm, "BLUE", ENV, PackedStringArray(), Vector2.ZERO, WorldPresentation.MAX_RANGE_NM, WorldPresentation.MAX_ENTITIES)
	assert_eq(_keys(WorldPresentation.cull(built, Vector2.ZERO)), _keys(WorldPresentation.cull(WorldPresentation.unit_entries(um, tm, "BLUE", ENV), Vector2.ZERO)), "a sighted unit is shown once, as itself, even when that is past the edge")
	assert_true(_keys(built).find("t:T1001") < 0, "so its plot does not stand in for it")
	um.free()
	tm.free()
