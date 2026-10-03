extends TestCase
## Command gestures and firing-board accounting use the real synchronous simulation route.


func _unit(weapon: WeaponSpec, rounds := 8) -> Unit:
	var u := Unit.new()
	u.spec = PlatformSpec.new()
	u.spec.has_datalink = true
	u.spec.fire_control_channels = 4
	u.faction = "BLUE"
	u.callsign = "Test platform"
	u.health = 100
	if weapon != null:
		u.weapons.append(weapon)
		u.magazines[weapon.id] = rounds
	return u


func _fixture() -> Dictionary:
	Terrain.clear()
	var spec := DataDB.weapon("tomahawk_block_v")
	var u := _unit(spec)
	var t := Track.new()
	t.id = "T1981"
	t.owner_faction = "BLUE"
	t.identity = "HOSTILE"
	t.domain = "surface"
	t.position = Vector2(0, 20)
	var simulation := Simulation.new()
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(simulation)
	simulation.unit_manager.add_unit(u)
	simulation.track_manager._tracks["BLUE"] = [t]
	var panel := OrdersPanel.new()
	panel.weapon_manager = simulation.weapon_manager
	root.add_child(panel)
	panel.set_units([u], true)
	panel.set_target_track(t)
	panel.unit_orders_requested.connect(func(pairs: Array) -> void:
		for pair: Array in pairs:
			pair[1].execution_accepted = simulation.unit_manager.issue_order(pair[0], pair[1]))
	return {"simulation": simulation, "panel": panel, "unit": u, "track": t, "spec": spec}


func _board(fixture: Dictionary) -> WeaponControl:
	var board := WeaponControl.new()
	board.simulation = fixture.simulation
	(Engine.get_main_loop() as SceneTree).root.add_child(board)
	board.open_for([fixture.unit], fixture.track)
	return board


func _clean(fixture: Dictionary) -> void:
	fixture.panel.free()
	fixture.simulation.weapon_manager.clear()
	fixture.simulation.free()


func test_quick_engage_rechecks_posture_at_the_gesture() -> void:
	var f := _fixture()
	assert_true(not f.panel._engage_btn.disabled)
	f.unit.roe = Unit.Roe.HOLD
	assert_true(not f.panel.try_engage(), "an enabled button from the previous refresh cannot fire through a new HOLD order")
	assert_eq(f.simulation.weapon_manager.in_flight.size(), 0)
	_clean(f)


func test_quick_engage_reports_a_downstream_refusal() -> void:
	var f := _fixture()
	f.simulation.unit_manager.order_issued.connect(func(_u: Unit, order: Order) -> void: order.execution_accepted = false)
	assert_true(not f.panel.try_engage(), "success comes from the synchronous execution result")
	_clean(f)


func test_group_engagement_sends_only_eligible_carriers_and_clamps_each_salvo() -> void:
	var f := _fixture()
	f.unit.magazines[f.spec.id] = 1
	var other := _unit(f.spec, 4)
	var unarmed := _unit(null)
	f.simulation.unit_manager.add_unit(other)
	f.simulation.unit_manager.add_unit(unarmed)
	f.panel.set_units([f.unit, other, unarmed], true)
	f.panel._salvo.value = 3
	var issued: Array = []
	f.simulation.unit_manager.order_issued.connect(func(u: Unit, order: Order) -> void:
		if order.type == Order.Type.ENGAGE:
			issued.append([u, order.salvo]))
	assert_true(f.panel.try_engage())
	assert_eq(issued, [[f.unit, 1], [other, 3]], "SALVO means rounds per eligible platform, clamped before routing")
	assert_eq(unarmed.magazines.size(), 0)
	_clean(f)


func test_reserved_and_airborne_rounds_remain_visible_after_the_magazine_empties() -> void:
	var f := _fixture()
	f.unit.magazines[f.spec.id] = 2
	f.panel._rebuild_weapons()
	f.panel._salvo.value = 2
	assert_true(f.panel.try_engage())
	assert_eq(f.unit.magazine_count(f.spec.id), 0)
	assert_eq(f.panel.current_weapon_spec(), f.spec, "spending the last available rounds does not switch systems")
	assert_true(f.panel._engage_btn.disabled)
	assert_true(f.panel._envelope.text.contains("1 queued / 1 away"))
	assert_true(f.panel._envelope.tooltip_text.contains("MAGAZINE EMPTY"))
	_clean(f)


func test_defence_summary_marks_mixed_doctrine_and_disables_stationary_evasion() -> void:
	var f := _fixture()
	var other := _unit(f.spec)
	other.defence_policy = "conserve"
	other.auto_countermeasures = false
	f.panel.set_units([f.unit, other], true, false)
	assert_true(f.panel._defence_summary.text.contains("MIXED / CM MIXED"))
	assert_true(f.panel._defence_buttons["evade"].disabled)
	assert_true(f.panel._defence_buttons["away"].disabled, "Run Away has the same movement requirement as Evade")
	assert_true(f.panel._defence_buttons["resume"].disabled, "Resume Plan needs an active evasion")
	_clean(f)


func test_firing_plan_clamps_hidden_systems_and_removes_invalid_solutions() -> void:
	var f := _fixture()
	var board := _board(f)
	board.set_salvo(f.unit, f.spec, 8)
	board._role_option.select(1)
	f.unit.magazines[f.spec.id] = 3
	board.refresh()
	assert_eq(board._plan[WeaponControl.plan_key(f.unit, f.spec)], 3)
	assert_true(board._plan_summary.text.begins_with("3 rounds planned"))
	f.unit.roe = Unit.Roe.HOLD
	board.refresh()
	assert_true(board._plan.is_empty(), "hidden plans are validated even when their rows are filtered out")
	assert_true(board._commit.disabled)
	board.free()
	_clean(f)


func test_firing_board_explanations_keep_readable_height_when_clipped() -> void:
	var f := _fixture()
	var board := _board(f)
	board.set_salvo(f.unit, f.spec, 2)
	for label: Label in [board._quality, board._detail, board._plan_summary, board._receipt]:
		assert_true(label.get_combined_minimum_size().y > 0.0, "solution, plan and receipt lines must reserve visible height")
	var contact_label := board._target_option.get_parent().get_child(0) as Label
	assert_true(contact_label.get_combined_minimum_size().x > 0.0, "the fixed CONTACT caption must keep its width")
	board.free()
	_clean(f)


func test_cancellation_receipt_counts_only_rounds_actually_refunded() -> void:
	var f := _fixture()
	f.simulation.weapon_manager.launch(f.unit, f.spec, f.track, 3, 0)
	var board := _board(f)
	board._cancel_pending()
	assert_true(board._receipt.text.contains("0 unfired rounds"), "an unhandled cancellation cannot claim a refund")
	assert_true(board._receipt.text.contains("2 remain queued"))
	board.unit_orders_requested.connect(func(pairs: Array) -> void:
		for pair: Array in pairs:
			pair[1].execution_accepted = f.simulation.unit_manager.issue_order(pair[0], pair[1]))
	board._cancel_pending()
	assert_true(board._receipt.text.contains("2 unfired rounds"))
	assert_true(board._receipt.text.contains("0 remain queued"))
	assert_eq(f.simulation.weapon_manager.in_flight.size(), 1, "already launched weapons are never recalled")
	board.free()
	_clean(f)


func test_firing_board_receipt_counts_reserved_rounds_after_a_quantity_change() -> void:
	var f := _fixture()
	var board := _board(f)
	board.set_salvo(f.unit, f.spec, 8)
	board.unit_orders_requested.connect(func(pairs: Array) -> void:
		f.unit.magazines[f.spec.id] = 2
		for pair: Array in pairs:
			pair[1].execution_accepted = f.simulation.unit_manager.issue_order(pair[0], pair[1]))
	board._commit_plan()
	# This fixture changes availability in the routing seam; the accepted order still requests
	# eight, but only two can be reserved. Receipts must use the manager's actual commitment.
	assert_true(board._receipt.text.begins_with("2 rounds committed"))
	board.free()
	_clean(f)


func test_defence_menu_exposes_readiness_and_marks_only_unanimous_settings() -> void:
	var first := _unit(null)
	var second := _unit(null)
	first.decoys = 2
	second.decoys = 2
	second.countermeasure_reload_s = 10
	second.defence_policy = "conserve"
	second.auto_countermeasures = false
	var items := CdsMenus.defence_items([first, second], false)
	assert_true(items[0].tooltip.begins_with("1 of 2 platforms ready"))
	assert_true(not items[0].disabled, "only the ready platform needs to deploy")
	assert_true(items[2].disabled, "no acoustic stores means acoustic deployment is unavailable")
	assert_true(items[3].disabled and items[4].disabled, "both evade actions need mobility")
	assert_true(items[5].disabled, "Resume Plan needs an active evasion")
	for policy: Dictionary in items[6].children:
		assert_eq(policy.checked, 0, "mixed interceptor policies do not show a misleading check")
	for automatic: Dictionary in items[7].children:
		assert_eq(automatic.checked, 0, "mixed automatic/manual countermeasure settings are unmarked")


func test_engage_menu_uses_live_fire_control_readiness_and_explains_group_salvos() -> void:
	var f := _fixture()
	var sam := DataDB.weapon("sm2_family")
	f.unit.weapons.clear()
	f.unit.weapons.append(sam)
	f.unit.magazines = {sam.id: 4}
	f.unit.radar_on = false
	f.track.domain = "air"
	f.track.position = Vector2(0, 10)
	var entries := CdsMenus.engage_weapon_items([f.unit], f.track, f.simulation.weapon_manager)
	assert_eq(entries.size(), 1)
	assert_true(entries[0].disabled, "a radar-guided SAM with radar silenced cannot appear ready")
	assert_true(entries[0].tooltip.to_upper().contains("RADAR GUIDANCE UNAVAILABLE"))
	f.unit.weapons.clear()
	f.unit.weapons.append(f.spec)
	f.unit.magazines = {f.spec.id: 4}
	f.track.domain = "surface"
	var other := _unit(f.spec)
	entries = CdsMenus.engage_weapon_items([f.unit, other], f.track, f.simulation.weapon_manager)
	assert_true(entries[0].children[0].text.contains("per platform"))
	_clean(f)


func test_protected_traffic_warning_stays_visible_for_a_filtered_firing_plan() -> void:
	var f := _fixture()
	var civilian := Track.new()
	civilian.id = "CIV42"
	civilian.owner_faction = "BLUE"
	civilian.domain = "surface"
	civilian.identity = "NEUTRAL"
	civilian.position = f.track.position + Vector2(1, 0)
	f.simulation.track_manager._tracks["BLUE"].append(civilian)
	var board := _board(f)
	board.set_salvo(f.unit, f.spec, 2)
	assert_true(board._traffic.visible and board._traffic.text.contains("CIV42"), "protected traffic receives a dedicated visible warning, not a clipped third detail line")
	board._role_option.select(1)  # air defence filter hides this surface weapon
	board.refresh()
	assert_true(board._traffic.visible and board._traffic.text.contains("CIV42"), "hiding a planned system does not hide its traffic risk")
	assert_eq(board._plan.size(), 1, "advisory does not silently delete the commander's plan")
	civilian.position = Vector2(500, 500)
	board.refresh()
	assert_true(not board._traffic.visible, "updated held geometry clears the warning")
	board.free()
	_clean(f)


func test_disconnected_submarine_board_does_not_expose_private_contacts_or_ammunition() -> void:
	var f := _fixture()
	f.unit.spec.domain = "subsurface"
	f.unit.comms_enabled = true
	f.unit.depth_m = 150.0
	SubmarineComms.initialize(f.unit, 0.0)
	var private_track := Track.new()
	private_track.id = "PRIVATE"
	private_track.owner_faction = "BLUE"
	private_track.networked = false
	private_track.contributors = {f.unit: 0.0}
	private_track.position = Vector2(0, 10)
	f.simulation.track_manager._local_keys[f.unit] = "private_blue"
	f.simulation.track_manager._tracks["private_blue"] = [private_track]
	var board := _board(f)
	assert_true(not board._targets.has(private_track))
	assert_true(board._targets.has(f.track), "the faction's shared plot remains available to inspect")
	var row: TreeItem = board._items[0]
	assert_eq(row.get_text(2), "--")
	assert_eq(row.get_text(3), "--")
	assert_eq(row.get_text(4), "--")
	assert_true(row.get_text(7).contains("CHECK-IN"))
	assert_true(not row.is_editable(8))
	board.set_salvo(f.unit, f.spec, 2)
	assert_true(board._plan.is_empty(), "a live firing solution must wait for a check-in")
	board.free()
	_clean(f)
