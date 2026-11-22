extends TestCase
## What the chart costs per frame: a flash, a pulsing ring or a fading radio line moves on a layer
## of its own every frame, while the plot under it is drawn on simulation ticks, view changes and
## the idle rate only.

const FRAME_S := 1.0 / 60.0
## One second of frames redraws the plot at most this often: the idle rate, and the first frame.
const PLOT_DRAWS_PER_SECOND := int(1.0 / TacticalMap.IDLE_REFRESH_S)


func _map() -> TacticalMap:
	var map := TacticalMap.new()
	map.size = Vector2(1200, 600)
	(Engine.get_main_loop() as SceneTree).root.add_child(map)
	map._begin_plot_draw()
	return map


## Steps `frames` display frames the way the engine would, drawing whatever falls due, and counts
## the draws of the plot and of the marks layer. `plot_draw` stands for what a plot draw puts on
## the marks layer.
func _run_frames(map: TacticalMap, frames: int, plot_draw := Callable()) -> Dictionary:
	var plot := 0
	var marks := 0
	for i in frames:
		map._process(FRAME_S)
		if map.plot_redraw_due():
			plot += 1
			map._begin_plot_draw()
			if plot_draw.is_valid():
				plot_draw.call()
		if map.marks_redraw_due():
			marks += 1
			map._marks_shown = map.marks_animating()
	return {"plot": plot, "marks": marks}


func test_one_flash_redraws_its_own_layer_not_the_plot() -> void:
	var map := _map()
	map.add_effect(map.center_nm, "refused", true)
	var counts := _run_frames(map, 60)
	assert_true(int(counts["plot"]) <= PLOT_DRAWS_PER_SECOND, "the plot is drawn at the idle rate under a flash, not every frame (%d of 60)" % counts["plot"])
	assert_eq(int(counts["marks"]), 60, "the flash itself moves every frame")
	counts = _run_frames(map, 120)
	assert_true(map._effects.is_empty(), "the flash runs out on its own, drawn or not")
	var after := _run_frames(map, 60)
	assert_eq(int(after["marks"]), 0, "with the flash gone the marks layer stops redrawing")
	map.free()


func test_a_ring_round_a_ship_under_attack_and_a_hit_pulse_without_the_plot() -> void:
	var map := _map()
	var ring := func() -> void: map._threat_ring_points.append(Vector2(600, 300))
	ring.call()
	var counts := _run_frames(map, 60, ring)
	assert_true(int(counts["plot"]) <= PLOT_DRAWS_PER_SECOND, "an inbound round's ring does not redraw the plot every frame (%d of 60)" % counts["plot"])
	assert_eq(int(counts["marks"]), 60, "the ring pulses every frame")
	map._begin_plot_draw()  # the plot draws again with the round gone: no ring
	map.add_effect(map.center_nm, "hit", true)
	counts = _run_frames(map, 60)
	assert_true(map._hit_flash > 0.0, "a hit on one of ours reddens the chart's edge")
	assert_true(int(counts["plot"]) <= PLOT_DRAWS_PER_SECOND, "the red edge does not redraw the plot every frame (%d of 60)" % counts["plot"])
	assert_eq(int(counts["marks"]), 60)
	map.free()


func test_a_fading_radio_line_fades_on_the_marks_layer() -> void:
	var map := _map()
	map.post_message("Contact bearing 045, closing")
	_run_frames(map, int(RadioLine.HOLD_S * 60.0) + 6)
	assert_true(map._radio.is_fading(map._anim), "the line is fading")
	var counts := _run_frames(map, 30)
	assert_true(int(counts["plot"]) <= PLOT_DRAWS_PER_SECOND / 2, "the fade does not redraw the plot every frame (%d of 30)" % counts["plot"])
	assert_eq(int(counts["marks"]), 30, "the fade itself is smooth")
	map.free()


func test_the_plot_still_follows_the_view_at_display_speed() -> void:
	var map := _map()
	var plot := 0
	for i in 30:
		map.center_nm += Vector2(0.1, 0.0)
		map._process(FRAME_S)
		if map.plot_redraw_due():
			plot += 1
			map._begin_plot_draw()
	assert_eq(plot, 30, "a pan redraws the plot every frame it moves")
	map.free()


# --- The coast -----------------------------------------------------------------------------------

func test_the_coast_is_stroked_when_the_view_moves_not_with_every_plot_draw() -> void:
	var map := _map()
	assert_true(map._coast_layer != null and map._coast_layer.show_behind_parent, "the coast has a layer of its own, under the plot")
	var still := map.coast_view_key()
	var was := SimClock.sim_time
	SimClock.sim_time = was + 0.25
	map._begin_plot_draw()
	assert_eq(map.coast_view_key(), still, "a simulation tick redraws the plot and leaves the coast as it was")
	SimClock.sim_time = was
	map.center_nm += Vector2(3.0, 0.0)
	assert_true(map.coast_view_key() != still, "a pan moves the coast")
	map.free()


func test_a_panned_coast_lands_where_a_fresh_projection_puts_it() -> void:
	var map := TacticalMap.new()
	map.size = Vector2(1200, 600)
	map.ppn = 7.5
	map.center_nm = Vector2(10.0, -4.0)
	var coast := PackedVector2Array([Vector2(0, 0), Vector2(12.3, 4.7), Vector2(20.1, -9.6), Vector2(31.7, 2.2)])
	map._coast_origin = map.center_nm
	var projected := map._project_coast(coast, map._coast_origin)
	map.center_nm = Vector2(-37.25, 18.5)
	var shift := map.coast_shift()
	for i in coast.size():
		var fresh := map.world_to_screen(coast[i])
		assert_true((projected[i] + shift).distance_to(fresh) < 0.001, "vertex %d drawn at %s, a fresh projection puts it at %s" % [i, projected[i] + shift, fresh])
	map.free()


# --- Air missions laid on a contact --------------------------------------------------------------

const CARRIER_WATCH := "res://data/scenarios/cold_war_03_carrier.json"
const IKE := "USS Dwight D. Eisenhower (CVN 69)"


func test_an_intercept_is_drawn_as_a_line_to_its_contact_with_no_station_to_drag() -> void:
	SimClock.set_paused(true)
	var sim := Simulation.new()
	sim.seed_override = 7
	(Engine.get_main_loop() as SceneTree).root.add_child(sim)
	assert_true(sim.load_scenario(CARRIER_WATCH))
	sim.ai_enabled = false
	var cv: Unit = null
	for u in sim.unit_manager.units:
		if u.callsign == IKE:
			cv = u
	var raid := Track.new()
	raid.id = "T1950"
	raid.owner_faction = "BLUE"
	raid.position = cv.position + Vector2(0, 120)
	raid.altitude_m = 8000.0
	raid.last_seen_time = SimClock.sim_time
	raid.domain = "air"
	raid.identity = "HOSTILE"
	raid.classification = Track.Classification.CLASS_KNOWN
	if not sim.track_manager._tracks.has("BLUE"):
		sim.track_manager._tracks["BLUE"] = []
	sim.track_manager._tracks["BLUE"].append(raid)
	var o := sim.air_mission_manager.quick_order(cv, AirMission.Kind.CAP, raid.position, raid)
	assert_true(o != null and sim.unit_manager.issue_order(cv, o), "the intercept is ordered")
	var m: AirMission = sim.air_mission_manager.active_missions("BLUE")[0]
	assert_true(m.intercept)
	assert_true(TacticalMap.mission_on_contact(m), "an intercept goes for its contact, as a strike does")
	assert_eq(TacticalMap.contact_mission_caption(m), "INTERCEPT %d" % m.id)
	var map := TacticalMap.new()
	map.size = Vector2(1200, 600)
	map.simulation = sim
	map.unit_manager = sim.unit_manager
	map.track_manager = sim.track_manager
	map.player_faction = "BLUE"
	map.center_nm = m.station
	map.ppn = 100.0 / maxf(m.radius_nm, 1.0)
	var handle := map.world_to_screen(m.station) + Vector2(m.radius_nm * map.ppn, 0.0)
	assert_true(map.station_handle_at(handle).is_empty(), "an intercept has no hold ring to drag")
	map.free()
	sim.unit_manager.clear()
	sim.free()


# --- Weapon envelopes ------------------------------------------------------------------------------

func test_a_torpedo_envelope_starts_where_the_shot_is_refused_as_too_close() -> void:
	var fish := WeaponSpec.new()
	fish.id = "test_fish"
	fish.display_name = "Test fish"
	fish.type = "torpedo"
	fish.min_range_nm = 0.2
	fish.run_to_enable_nm = 1.0
	fish.max_range_nm = 10.0
	assert_near(Combat.minimum_range_nm(fish), 1.3, 0.001)
	assert_true(TacticalMap.envelope_legend(null, fish).contains("1.3-"), "the legend gives the enable run, not the stated minimum: %s" % TacticalMap.envelope_legend(null, fish))
