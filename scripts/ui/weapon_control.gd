class_name WeaponControl
extends Control
## A CDS-style firing board. Keeps a separate salvo quantity for each platform and weapon.
## Enemy information comes exclusively from observer-held tracks. Commands return through Main.
##
## With several platforms hooked it also commits a group attack: one round budget the platforms
## share, allocated by the simulation to the shooters that hold a solution. A SALVO plan, when
## there is one, is the group's first volley and sets its volley size. COMMIT SALVO stays the
## individual control: one independent order per platform and weapon.

signal closed()
signal unit_orders_requested(pairs: Array)
## A group attack or its cancellation, for one member (the lead) rather than for each platform.
signal group_order_requested(lead: Unit, order: Order)
signal target_selected(track: Track)
signal weapon_selected(spec: WeaponSpec)
signal range_role_selected(role: String)

var simulation: Simulation
var units: Array = []
var target: Track
var _targets: Array = []
var _target_option: OptionButton
var _role_option: OptionButton
var _tree: Tree
var _quality: Label
var _detail: Label
var _receipt: Label
var _commit: Button
var _plan_summary: Label
var _plan: Dictionary = {}
var _items: Array = []
var _building := false
var _group_row: HBoxContainer
var _budget: SpinBox
var _group_commit: Button
var _group_cancel: Button
var _group_status: Label
## The commander has set the budget by hand; until then it follows the plan or one salvo each.
var _budget_set := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = UITheme.DIALOG_SHADE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "JfcDialog"
	margin.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var heading := HBoxContainer.new()
	box.add_child(heading)
	var title := _label(heading, "WEAPON CONTROL")
	title.theme_type_variation = "TitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(heading, "RETURN TO CHART [Shift+E]", func() -> void: closed.emit())
	var selectors := HBoxContainer.new()
	box.add_child(selectors)
	_label(selectors, "CONTACT")
	_target_option = OptionButton.new()
	_target_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_option.clip_text = true
	_target_option.item_selected.connect(_choose_target)
	selectors.add_child(_target_option)
	_role_option = OptionButton.new()
	for name: String in WeaponPresentation.LABELS:
		_role_option.add_item(name)
	_role_option.item_selected.connect(func(i: int) -> void:
		range_role_selected.emit(WeaponPresentation.ROLES[i])
		refresh())
	selectors.add_child(_role_option)
	_quality = _wrapped_label(box, "")
	_tree = Tree.new()
	_tree.columns = 9
	_tree.hide_root = true
	_tree.column_titles_visible = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.add_theme_constant_override("v_separation", 9)
	var titles := ["PLATFORM / SYSTEM", "ROLE", "LEFT", "QUEUED", "AWAY", "RANGE nm", "TOF", "SOLUTION", "SALVO"]
	var widths := [185, 110, 45, 60, 45, 90, 55, 160, 65]
	for i in titles.size():
		_tree.set_column_title(i, titles[i])
		_tree.set_column_custom_minimum_width(i, widths[i])
		_tree.set_column_expand(i, i in [0, 7])
	_tree.item_edited.connect(_edit_quantity)
	_tree.item_selected.connect(_select_weapon)
	box.add_child(_tree)
	_detail = _wrapped_label(box, "Select a system for its solution. Set SALVO quantities, then commit the selected weapons together.")
	var actions := HBoxContainer.new()
	box.add_child(actions)
	_commit = _button(actions, "COMMIT SALVO", _commit_plan)
	_commit.theme_type_variation = "PrimaryButton"
	_button(actions, "CLEAR PLAN", func() -> void: _plan.clear(); refresh())
	_button(actions, "CANCEL QUEUED FOR CONTACT", _cancel_pending)
	_plan_summary = _wrapped_label(actions, "")
	_plan_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_group_row = HBoxContainer.new()
	box.add_child(_group_row)
	_label(_group_row, "GROUP BUDGET")
	_budget = SpinBox.new()
	_budget.min_value = 1
	_budget.max_value = 999
	_budget.step = 1.0
	_budget.suffix = "rds"
	_budget.custom_minimum_size = Vector2(92, 28)
	_budget.accessibility_name = "Rounds the group attack may fire in all"
	_budget.tooltip_text = "Rounds the hooked platforms may fire between them, queued rounds included."
	_budget.value_changed.connect(func(_v: float) -> void:
		if not _building:
			_budget_set = true
			_update_group_status())
	_group_row.add_child(_budget)
	_group_commit = _button(_group_row, "GROUP ATTACK", _commit_group)
	_group_commit.tooltip_text = "One shared budget: the rounds go to the platforms that hold a solution, and the group assesses each volley before spending more. A SALVO plan is the first volley."
	_group_cancel = _button(_group_row, "CANCEL GROUP", _cancel_group)
	_group_cancel.tooltip_text = "End the group attack on this contact: queued group rounds return to the magazines; rounds already away fly on."
	_group_status = _wrapped_label(_group_row, "")
	_group_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wrapped_label(box, "LEFT excludes reserved rounds. AWAY includes payloads already delivered. TOF is flight time; queued launches add delay. Automatic missile defence remains active after you return to the chart.")
	_receipt = _wrapped_label(box, "")


func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label


## Clipped labels have no content minimum size. Reserve two lines explicitly so a wrapped
## solution or receipt remains readable without its text widening the firing board.
func _wrapped_label(parent: Node, text: String) -> Label:
	var label := _label(parent, text)
	label.clip_text = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.y = ceilf(label.get_theme_font("font").get_height(label.get_theme_font_size("font_size")) * 2.0)
	return label


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


## `group_budget` opens the board ready for a group attack of that many rounds, as the contact
## menu's Group attack item does.
func open_for(selection: Array, contact: Track, group_budget := 0) -> void:
	units = selection.filter(func(u: Unit) -> bool: return u.faction == simulation.player_faction and u.is_engageable())
	target = contact
	_plan.clear()
	_receipt.text = ""
	_budget_set = group_budget > 0
	if group_budget > 0:
		_building = true
		_budget.value = group_budget
		_building = false
	_targets.clear()
	_target_option.clear()
	_target_option.add_item("No contact hooked")
	for u: Unit in units:
		for t: Track in simulation.track_manager.tracks_for(u):
			if not _targets.has(t) and t.status != Track.Status.LOST:
				_targets.append(t)
	for i in _targets.size():
		var t: Track = _targets[i]
		_target_option.add_item("%s  %s  %s" % [t.id, t.identity, t.description()])
		if t == target:
			_target_option.select(i + 1)
	if not _targets.has(target):
		target = null
	refresh()
	show()
	if group_budget > 0 and not _group_commit.disabled:
		_group_commit.grab_focus()
	else:
		_tree.grab_focus()


func _choose_target(index: int) -> void:
	target = _targets[index - 1] if index > 0 else null
	_plan.clear()
	target_selected.emit(target)
	refresh()


static func plan_key(u: Unit, spec: WeaponSpec) -> String:
	return "%d:%s" % [u.get_instance_id(), spec.id]


func refresh() -> void:
	_building = true
	_validate_plan()
	_tree.clear()
	_items.clear()
	var root := _tree.create_item()
	var wm := simulation.weapon_manager
	var role: String = WeaponPresentation.ROLES[_role_option.selected]
	for u: Unit in units:
		var parent := _tree.create_item(root)
		parent.set_text(0, u.callsign)
		parent.set_text(7, "F/C %d / %d" % [wm.channel_targets(u).size(), u.spec.fire_control_channels])
		parent.set_tooltip_text(0, u.spec.display_name)
		for spec in u.weapons:
			if not WeaponPresentation.matches(spec, role):
				continue
			var item := _tree.create_item(parent)
			item.set_metadata(0, [u, spec])
			_items.append(item)
			var check := wm.engagement_check(u, spec, target, SimClock.sim_time)
			var queued := wm.committed_rounds(u, spec, target, true)
			item.set_text(0, spec.compact_name())
			item.set_tooltip_text(0, spec.display_name + "\n" + spec.source_status)
			item.set_text(1, WeaponPresentation.role_name(spec))
			item.set_text(2, str(u.magazine_count(spec.id)))
			item.set_text(3, str(queued))
			item.set_text(4, str(wm.committed_rounds(u, spec, target) - queued))
			item.set_text(5, "%.1f - %s" % [spec.min_range_nm, Geo.format_nm(Combat.effective_range_nm(u, spec))])
			item.set_text(6, "%ds" % int(check.get("flight_time_s", 0.0)) if check.has("flight_time_s") else "--")
			var state: String = str(check.reason)
			if check.ok:
				var delay := wm.ready_in_s(u, spec, SimClock.sim_time)
				state = "READY" if delay <= 0.0 else "QUEUE +%ds" % int(ceil(delay))
			item.set_text(7, state)
			item.set_tooltip_text(7, state + "\n" + WeaponPresentation.track_quality(target, SimClock.sim_time, spec))
			item.set_custom_color(7, Color("245a36") if check.ok else Color("8e3434"))
			item.set_cell_mode(8, TreeItem.CELL_MODE_RANGE)
			item.set_range_config(8, 0, u.magazine_count(spec.id), 1)
			item.set_editable(8, check.ok)
			var key := plan_key(u, spec)
			item.set_range(8, int(_plan.get(key, 0)))
	_quality.text = WeaponPresentation.track_quality(target, SimClock.sim_time)
	_update_plan_summary()
	_building = false


func _edit_quantity() -> void:
	if _building:
		return
	var item := _tree.get_edited()
	if item == null or item.get_metadata(0) == null:
		return
	var data: Array = item.get_metadata(0)
	set_salvo(data[0], data[1], int(item.get_range(8)))


func set_salvo(u: Unit, spec: WeaponSpec, count: int) -> void:
	if not units.has(u) or u.get_weapon(spec.id) == null or not simulation.weapon_manager.engagement_check(u, spec, target, SimClock.sim_time).ok:
		return
	var key := plan_key(u, spec)
	count = clampi(count, 0, u.magazine_count(spec.id))
	if count > 0:
		_plan[key] = count
	else:
		_plan.erase(key)
	_update_plan_summary()


## The role filter changes only the view, so validate every planned system before summarizing
## or firing. A hidden system must not retain an old quantity after its available rounds change.
func _validate_plan() -> void:
	var valid := {}
	for u: Unit in units:
		if not u.is_engageable():
			continue
		for spec: WeaponSpec in u.weapons:
			var key := plan_key(u, spec)
			if not _plan.has(key):
				continue
			if not simulation.weapon_manager.engagement_check(u, spec, target, SimClock.sim_time).ok:
				continue
			var count := clampi(int(_plan[key]), 0, u.magazine_count(spec.id))
			if count > 0:
				valid[key] = count
	_plan = valid


func _update_plan_summary() -> void:
	_commit.disabled = _plan.is_empty() or target == null
	var rounds := 0
	var hidden_systems := _plan.size()
	for count: int in _plan.values():
		rounds += count
	for item: TreeItem in _items:
		var data: Array = item.get_metadata(0)
		if _plan.has(plan_key(data[0], data[1])):
			hidden_systems -= 1
	_plan_summary.text = "%d rounds planned across %d systems" % [rounds, _plan.size()]
	if hidden_systems > 0:
		_plan_summary.text += " (%d systems hidden by filter)" % hidden_systems
	_update_group_status()


func _planned_rounds() -> int:
	var rounds := 0
	for count: int in _plan.values():
		rounds += count
	return rounds


## The platform a group order is given to: the first hooked one still able to fight.
func _group_lead() -> Unit:
	for u: Unit in units:
		if u.alive and u.is_engageable():
			return u
	return null


## The board's plan as the group's first volley: [platform, weapon, contact index, rounds] rows.
func _group_plan() -> Array:
	var rows: Array = []
	for u: Unit in units:
		for spec: WeaponSpec in u.weapons:
			var count := int(_plan.get(plan_key(u, spec), 0))
			if count > 0:
				rows.append([u, spec.id, 0, count])
	return rows


func _group_order() -> Order:
	var planned := _planned_rounds()
	return Order.group_attack(units, [target], int(_budget.value), planned, [], _group_plan())


## The group row shows the attack already running on this contact, or what one would do now.
func _update_group_status() -> void:
	if _group_row == null:
		return
	_group_row.visible = units.size() >= 2
	if not _group_row.visible:
		return
	var manager := simulation.group_attack_manager
	var running: Array[GroupAttack] = []
	if target != null:
		running = manager.groups_on(simulation.player_faction, target)
	_group_cancel.disabled = running.is_empty()
	if not _budget_set:
		var was_building := _building
		_building = true
		var suggested := _planned_rounds()
		if suggested <= 0 and target != null:
			suggested = GroupAttackManager.default_budget(units, target, simulation.weapon_manager)
		_budget.value = maxi(suggested, 1)
		_building = was_building
	var lead := _group_lead()
	# One attack at a time for the same platforms on a contact; the running one is cancelled first.
	_group_commit.disabled = target == null or lead == null or manager.overlapping(simulation.player_faction, units, [target]) != null
	if not running.is_empty():
		_group_status.text = manager.summary(running[0])
	elif target == null:
		_group_status.text = "Hook a contact for a group attack."
	else:
		var preview := manager.preview(lead, _group_order()) if lead != null else ""
		_group_status.text = ("First volley: " + preview) if preview != "" else "No hooked platform holds a solution."
	_group_status.tooltip_text = _group_status.text


func _select_weapon() -> void:
	var item := _tree.get_selected()
	if item == null or item.get_metadata(0) == null:
		return
	var data: Array = item.get_metadata(0)
	var u: Unit = data[0]
	var spec: WeaponSpec = data[1]
	weapon_selected.emit(spec)
	_detail.text = "%s / %s | %s | %s\n%s" % [u.callsign, spec.display_name, spec.guidance.replace("_", " "), spec.profile.replace("_", " "), WeaponPresentation.track_quality(target, SimClock.sim_time, spec)]


func _commit_plan() -> void:
	if target == null:
		return
	_validate_plan()
	var pairs: Array = []
	var committed_before: Array[int] = []
	for u: Unit in units:
		for spec in u.weapons:
			var count := int(_plan.get(plan_key(u, spec), 0))
			if count > 0:
				var order := Order.engage(target, spec.id, count)
				order.execution_accepted = false
				pairs.append([u, order])
				committed_before.append(simulation.weapon_manager.committed_rounds(u, spec, target))
	if pairs.is_empty():
		refresh()
		_receipt.text = "No planned rounds have a valid solution. Review the contact, weapons posture and magazines."
		return
	unit_orders_requested.emit(pairs)
	var accepted := 0
	var rounds := 0
	for i in pairs.size():
		var pair: Array = pairs[i]
		if pair[1].execution_accepted:
			accepted += 1
			var spec := (pair[0] as Unit).get_weapon(pair[1].weapon_id)
			rounds += maxi(simulation.weapon_manager.committed_rounds(pair[0], spec, target) - committed_before[i], 0)
	_plan.clear()
	refresh()
	_receipt.text = "%d rounds committed across %d systems; %d orders refused. Return to the chart to advance time." % [rounds, accepted, pairs.size() - accepted]


func _commit_group() -> void:
	var lead := _group_lead()
	if target == null or lead == null:
		return
	_validate_plan()
	var order := _group_order()
	order.execution_accepted = false
	group_order_requested.emit(lead, order)
	if order.execution_accepted:
		_plan.clear()
		_budget_set = false
	refresh()
	_receipt.text = order.receipt if order.receipt != "" else "Group attack refused."


func _cancel_group() -> void:
	if target == null:
		return
	for g: GroupAttack in simulation.group_attack_manager.groups_on(simulation.player_faction, target):
		var by: Unit = null
		for u: Unit in g.members:
			if u.alive:
				by = u
				break
		if by == null:
			continue
		var order := Order.cancel_group_attack(g.id)
		order.execution_accepted = false
		group_order_requested.emit(by, order)
		_receipt.text = order.receipt
	refresh()


func _cancel_pending() -> void:
	if target == null:
		_receipt.text = "Select a contact to cancel its queued rounds."
		return
	var pairs: Array = []
	var queued_before := 0
	for u: Unit in units:
		for spec: WeaponSpec in u.weapons:
			queued_before += simulation.weapon_manager.committed_rounds(u, spec, target, true)
		var order := Order.cancel_fire(target)
		order.execution_accepted = false
		pairs.append([u, order])
	unit_orders_requested.emit(pairs)
	var queued_after := 0
	for u: Unit in units:
		for spec: WeaponSpec in u.weapons:
			queued_after += simulation.weapon_manager.committed_rounds(u, spec, target, true)
	refresh()
	_receipt.text = "%d unfired rounds for %s returned to the magazines; %d remain queued. Weapons already away continue their engagement." % [maxi(queued_before - queued_after, 0), target.id, queued_after]
