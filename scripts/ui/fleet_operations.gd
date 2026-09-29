class_name FleetOperations
extends Control
## Group-level readiness and orders, derived only from the player's own force.

signal closed()
signal selection_requested(units: Array)
signal order_requested(order: Order)
signal formation_requested(pattern: String)

var simulation: Simulation
var _list: ItemList
var _summary: Label
var _receipt: Label
var _groups: Array = []
var _selected_ids: Array = []


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
		margin.add_theme_constant_override("margin_" + side, 45)
	add_child(margin)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "JfcDialog"
	margin.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var heading := HBoxContainer.new()
	box.add_child(heading)
	var title := Label.new()
	title.text = "FLEET OPERATIONS"
	title.theme_type_variation = "TitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	_button(heading, "RETURN TO CHART [J]", func() -> void: closed.emit())
	_summary = Label.new()
	_summary.clip_text = true
	box.add_child(_summary)
	var hint := Label.new()
	hint.text = "Choose a task group, then issue orders to its available hulls. Ctrl+1 to 9 saves a chart selection; Alt+1 to 9 recalls it."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	_list = ItemList.new()
	_list.select_mode = ItemList.SELECT_MULTI
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_font_override("font", UITheme.data_font())
	_list.add_theme_constant_override("v_separation", 14)
	_list.multi_selected.connect(func(_index: int, _on: bool) -> void: _choose())
	box.add_child(_list)
	var selection := HBoxContainer.new()
	box.add_child(selection)
	for entry in [["surface", "ALL SURFACE"], ["subsurface", "ALL SUBMARINES"], ["air", "ALL AIRBORNE"]]:
		var domain: String = entry[0]
		_button(selection, entry[1], func() -> void: _select_domain(domain))
	_button(selection, "EVADE", func() -> void: order_requested.emit(Order.evade()))
	_button(selection, "RADAR DECOYS", func() -> void: order_requested.emit(Order.deploy_countermeasures("radar")))
	_button(selection, "RESUME PLAN", func() -> void: order_requested.emit(Order.resume_plan()))
	var policies := HBoxContainer.new()
	box.add_child(policies)
	for policy: String in ["conserve", "balanced", "saturation"]:
		_button(policies, policy.to_upper(), func() -> void: order_requested.emit(Order.set_defence_policy(policy)))
	_button(policies, "EMCON SILENT", func() -> void: order_requested.emit(Order.set_emcon(true)))
	_button(policies, "RADIATE", func() -> void: order_requested.emit(Order.set_emcon(false)))
	var formations := HBoxContainer.new()
	box.add_child(formations)
	for pattern: String in ["screen", "column", "abreast", "wedge", "dispersed"]:
		_button(formations, pattern.to_upper(), func() -> void: formation_requested.emit(pattern); refresh())
	_button(formations, "BREAK FORMATION", func() -> void: order_requested.emit(Order.break_formation()); refresh())
	_receipt = Label.new()
	_receipt.clip_text = true
	box.add_child(_receipt)


func _button(parent: Node, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(action)
	parent.add_child(button)


static func groups_for(um: UnitManager, faction: String) -> Array:
	var by_leader: Dictionary = {}
	for u in um.get_engageable_units(faction):
		var leader := u
		var seen: Dictionary = {}
		while leader.in_formation() and not seen.has(leader):
			seen[leader] = true
			leader = leader.formation_leader
		if not by_leader.has(leader):
			by_leader[leader] = []
		by_leader[leader].append(u)
	var out: Array = []
	for leader: Unit in by_leader:
		var members: Array = by_leader[leader]
		members.erase(leader)
		members.push_front(leader)
		out.append({"leader": leader, "members": members})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["leader"].id < b["leader"].id)
	return out


func open_for(units: Array) -> void:
	_selected_ids.clear()
	for u: Unit in units:
		_selected_ids.append(u.id)
	show()
	refresh()
	_list.grab_focus()


func refresh() -> void:
	if simulation == null or _list == null:
		return
	_groups = groups_for(simulation.unit_manager, simulation.player_faction)
	_list.clear()
	var hulls := 0
	var flying := 0
	for group: Dictionary in _groups:
		var leader: Unit = group["leader"]
		var rounds := 0
		var packs := 0
		var gap := 0.0
		var casualties := 0
		var selected := false
		for u: Unit in group["members"]:
			hulls += int(not u.is_aircraft())
			flying += int(u.in_flight())
			packs += u.decoys + u.torpedo_decoys
			casualties += int(u.fire > 0.1 or u.flooding > 0.1 or u.health < u.spec.health * 0.5)
			if u.in_formation():
				gap = maxf(gap, u.position.distance_to(Formation.station_for(u)))
			for spec in u.defensive_weapons():
				rounds += u.magazine_count(spec.id)
			selected = selected or _selected_ids.has(u.id)
		var text := "%s  |  %d platforms  |  station %.1f nm  |  %d defensive rounds  |  %d CM  |  %s" % [leader.callsign, group["members"].size(), gap, rounds, packs, leader.defence_policy.to_upper()]
		if casualties > 0:
			text += "  |  %d damaged" % casualties
		_list.add_item(text)
		_list.set_item_tooltip(_list.item_count - 1, "Worst station error, usable interceptor ammunition and expendable countermeasure packs. Aircraft aboard are managed separately in Air Operations.")
		if selected:
			_list.select(_list.item_count - 1, false)
	_summary.text = "%d task groups / independent units   |   %d ships and boats   |   %d airborne aircraft" % [_groups.size(), hulls, flying]


func _choose() -> void:
	var units: Array = []
	_selected_ids.clear()
	for i in _list.get_selected_items():
		for u: Unit in _groups[i]["members"]:
			if not units.has(u):
				units.append(u)
				_selected_ids.append(u.id)
	selection_requested.emit(units)
	_receipt.text = "%d platforms selected for group orders" % units.size()


func _select_domain(domain: String) -> void:
	var units: Array = []
	_selected_ids.clear()
	for u in simulation.unit_manager.get_engageable_units(simulation.player_faction):
		if u.spec.domain == domain:
			units.append(u)
			_selected_ids.append(u.id)
	selection_requested.emit(units)
	refresh()
	_receipt.text = "%d %s platforms selected" % [units.size(), domain]
