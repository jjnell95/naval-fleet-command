class_name WeaponControl
extends Control
## A CDS-style firing board. Keeps a separate salvo quantity for each platform and weapon.
## Enemy information comes exclusively from observer-held tracks. Commands return through Main.

signal closed()
signal unit_orders_requested(pairs: Array)
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
	_quality = _label(box, "")
	_quality.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	_detail = _label(box, "Select a system for its solution. Set SALVO quantities, then commit the selected weapons together.")
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var actions := HBoxContainer.new()
	box.add_child(actions)
	_commit = _button(actions, "COMMIT SALVO", _commit_plan)
	_commit.theme_type_variation = "PrimaryButton"
	_button(actions, "CLEAR PLAN", func() -> void: _plan.clear(); refresh())
	_button(actions, "CANCEL QUEUED FOR CONTACT", _cancel_pending)
	_plan_summary = _label(actions, "")
	_plan_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_plan_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var hint := _label(box, "LEFT excludes reserved rounds. AWAY includes payloads already delivered. TOF is flight time; queued launches add delay. Automatic missile defence remains active after you return to the chart.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_receipt = _label(box, "")
	_receipt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func open_for(selection: Array, contact: Track) -> void:
	units = selection.filter(func(u: Unit) -> bool: return u.faction == simulation.player_faction and u.is_engageable())
	target = contact
	_plan.clear()
	_receipt.text = ""
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
			if not check.ok:
				_plan.erase(key)
			item.set_range(8, mini(int(_plan.get(key, 0)), u.magazine_count(spec.id)))
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
	if not units.has(u) or not simulation.weapon_manager.engagement_check(u, spec, target, SimClock.sim_time).ok:
		return
	var key := plan_key(u, spec)
	count = clampi(count, 0, u.magazine_count(spec.id))
	if count > 0:
		_plan[key] = count
	else:
		_plan.erase(key)
	_update_plan_summary()


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
	var pairs: Array = []
	for u: Unit in units:
		for spec in u.weapons:
			var count := int(_plan.get(plan_key(u, spec), 0))
			if count > 0:
				var order := Order.engage(target, spec.id, count)
				order.execution_accepted = false
				pairs.append([u, order])
	unit_orders_requested.emit(pairs)
	var accepted := 0
	var rounds := 0
	for pair: Array in pairs:
		if pair[1].execution_accepted:
			accepted += 1
			rounds += pair[1].salvo
	_plan.clear()
	refresh()
	_receipt.text = "%d rounds committed across %d systems; %d orders refused. Return to the chart to advance time." % [rounds, accepted, pairs.size() - accepted]


func _cancel_pending() -> void:
	if target == null:
		_receipt.text = "Select a contact to cancel its queued rounds."
		return
	var pairs: Array = []
	for u: Unit in units:
		pairs.append([u, Order.cancel_fire(target)])
	unit_orders_requested.emit(pairs)
	refresh()
	_receipt.text = "Unfired rounds for %s returned to the magazines. Weapons already away continue their engagement." % target.id
