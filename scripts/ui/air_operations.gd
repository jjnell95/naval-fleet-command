class_name AirOperations
extends PanelContainer
## Own-force air plan, drawn as the grey in-mission launch dialog. Choose a host and an aircraft
## type and quantity, then explicitly launch or assign a mission. Closing preserves the clock.
## Below, choose an airborne airframe and where it should land. Commands always go through Main
## and UnitManager.
signal closed()
signal order_requested(unit: Unit, order: Order)
signal aircraft_selected(aircraft: Unit)
## Hand the chart to the commander to pick a station or search area (false) or a strike target.
signal chart_pick_requested(contact: bool)

## The widest the dialog stands, and the least room it leaves at the window's edges.
const DIALOG_WIDTH := 1240.0
const EDGE_MARGIN := 16.0
## Each list shows at least this many entries before the dialog asks the page to scroll.
const MIN_LIST_ROWS := 6
const DECK_ROW_GAP := 3
const DECK_COLUMNS := ["AIRFRAME", "SELECTED", "TIME", "STATE", "FUEL"]
## Mission planner choices, in AirMission.Kind order.
const MISSION_CHOICES := ["Combat air patrol", "Reconnaissance / identification", "ASW search", "Strike"]
## How long the hint keeps showing an accepted launch before it goes back to the deck state.
const ACCEPTED_HINT_S := 120.0
const RECEIPT_PROMPT := "Choose a quantity, then Launch or Assign mission. Closing this window sends no orders."

var simulation: Simulation
var _base_picker: OptionButton
var _type_picker: OptionButton
var _portrait: TextureRect
var _type_detail: Label
var _count: SpinBox
var _launch: Button
var _launch_hint: Label
var _deck: GridContainer
var _deck_rows: Array[Unit] = []
var _deck_key := ""
var _selection_labels: Array[Label] = []
var _roster: Tree
var _aircraft_detail: Label
var _destination: OptionButton
var _return: Button
var _focus: Button
var _receipt: Label
## The last order this deck and type accepted, and when, so the hint can say what just happened
## instead of why the airframes it just sent cannot be sent again.
var _accepted_text := ""
var _accepted_key := ""
var _accepted_at_s := -INF
var _summary: Label
var _back: Button
var _plan_tabs: TabContainer
var _clock_hint: Label
var _bases: Array[Unit] = []
var _destinations: Array[Unit] = []
var _type_ids: Array[String] = []
var _base: Unit
var _aircraft: Unit
var _destination_aircraft: Unit
var _type_id := ""
var _accum := 0.0
var _mission_picker: OptionButton
var _station_button: Button
var _station_label: Label
var _radius: SpinBox
var _relief: CheckBox
var _auto_return: CheckBox
var _lower_tabs: TabContainer
var _missions: Tree
var _mission_detail: Label
var _cancel_mission: Button
## -1 launches airframes with no mission, as before; otherwise an AirMission.Kind.
var _mission_kind := -1
var _station := Vector2.INF
var _target: Track
var _selected_mission: AirMission
var _editing_mission: AirMission
var _edit_mission: Button
var _cancel_edit: Button
var _cap_options: HBoxContainer
var _cap_intent: OptionButton
var _anchor_picker: OptionButton
var _anchors: Array[Unit] = []
var _pursuit: SpinBox
var _airborne_page: VBoxContainer
## What the commander last ticked for relief and return to station: a mission that cannot use an
## option shows it clear and greyed, and one that can shows the choice again.
var _relief_choice := false
var _auto_return_choice := true
var _dialog: PanelContainer
var _frame: VBoxContainer
var _header: HBoxContainer
var _body: ScrollContainer
var _page: VBoxContainer
var _deck_frame: ScrollContainer
var _upper: BoxContainer
var _footer: HBoxContainer
var _fit_queued := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# The dialog sits straight over the chart, as the originals did, with the faintest shade.
	var shade := StyleBoxFlat.new()
	shade.bg_color = UITheme.DIALOG_SHADE
	add_theme_stylebox_override("panel", shade)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_dialog = PanelContainer.new()
	_dialog.theme_type_variation = "JfcDialog"
	_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_dialog)
	_frame = VBoxContainer.new()
	_frame.add_theme_constant_override("separation", 6)
	_dialog.add_child(_frame)
	_header = UITheme.dialog_header("Air operations", func() -> void: closed.emit(), "F3 / Esc")
	_frame.add_child(_header)
	var title := _header.get_node("Title") as Label
	# The title keeps its width; the readiness line beside it gives way first.
	title.clip_text = false
	title.size_flags_horizontal = Control.SIZE_FILL
	_back = _header.get_node("Close") as Button
	_summary = _label("", 11, UITheme.INK_DIM)
	_summary.clip_text = true
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_header.add_child(_summary)
	_header.move_child(_summary, 1)
	# Only a window too small for even the shortest lists scrolls the page; otherwise the dialog
	# stands as tall as what it shows.
	_body = ScrollContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.follow_focus = true
	_body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_frame.add_child(_body)
	_page = VBoxContainer.new()
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 6)
	_body.add_child(_page)
	var page := _page

	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 10)
	page.add_child(identity)
	var choice := VBoxContainer.new()
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.add_theme_constant_override("separation", 4)
	identity.add_child(choice)
	var pickers := HBoxContainer.new()
	pickers.add_theme_constant_override("separation", 10)
	choice.add_child(pickers)
	_base_picker = OptionButton.new()
	_base_picker.custom_minimum_size = Vector2(340, 28)
	_base_picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_base_picker.clip_text = true
	_base_picker.accessibility_name = "Launch carrier or airfield"
	_base_picker.tooltip_text = "The carrier, deck or airfield to launch from"
	_base_picker.item_selected.connect(func(i: int) -> void:
		_base = _bases[i] if i >= 0 and i < _bases.size() else null
		_type_id = ""
		_count.set_value_no_signal(1)
		_refresh_types()
		_count.value = mini(1, int(_count.max_value)))
	pickers.add_child(_base_picker)
	_type_picker = OptionButton.new()
	_type_picker.custom_minimum_size = Vector2(290, 28)
	_type_picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_type_picker.clip_text = true
	_type_picker.accessibility_name = "Embarked aircraft type"
	_type_picker.tooltip_text = "The aircraft type to launch, with how many are ready"
	_type_picker.item_selected.connect(func(i: int) -> void:
		if i >= 0 and i < _type_ids.size():
			_type_id = _type_ids[i]
			_count.set_value_no_signal(1)
			_refresh_launch()
			_count.value = mini(1, int(_count.max_value)))
	pickers.add_child(_type_picker)
	_type_detail = _label("", 12, UITheme.INK_DIM)
	_type_detail.clip_text = true
	choice.add_child(_type_detail)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(140, 60)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	identity.add_child(_portrait)

	# The plan on the left and the deck beside it; on a window too narrow for both, one above the other.
	_upper = BoxContainer.new()
	_upper.add_theme_constant_override("separation", 14)
	page.add_child(_upper)
	var upper := _upper
	var plan := VBoxContainer.new()
	plan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plan.size_flags_stretch_ratio = 1.5
	plan.add_theme_constant_override("separation", 6)
	upper.add_child(plan)
	_plan_tabs = TabContainer.new()
	_plan_tabs.use_hidden_tabs_for_min_size = false
	plan.add_child(_plan_tabs)
	var launch_page := VBoxContainer.new()
	launch_page.name = "LAUNCH"
	_plan_tabs.add_child(launch_page)
	var launch_help := _label("Choose a quantity below. Ready aircraft launch in deck order; assign orders after takeoff.", 13, UITheme.INK_DIM)
	launch_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	launch_page.add_child(launch_help)
	var mission_page := VBoxContainer.new()
	mission_page.name = "MISSION PLAN"
	_plan_tabs.add_child(mission_page)
	_plan_tabs.tab_changed.connect(func(i: int) -> void:
		set_mission_kind(-1 if i == 0 else _default_mission_kind()))
	# Mission planning shares the quantity and explicit primary action with a simple launch.
	var mission_row := HBoxContainer.new()
	mission_row.add_theme_constant_override("separation", 10)
	mission_page.add_child(mission_row)
	mission_row.add_child(_label("MISSION", 12))
	_mission_picker = OptionButton.new()
	_mission_picker.custom_minimum_size = Vector2(250, 28)
	_mission_picker.clip_text = true
	_mission_picker.accessibility_name = "Air mission"
	_mission_picker.tooltip_text = "Launch to a mission: the deck keeps the airframes tasked, queues what it cannot launch yet, and brings them home on fuel."
	for mission_choice: String in MISSION_CHOICES:
		_mission_picker.add_item(mission_choice)
	_mission_picker.item_selected.connect(func(i: int) -> void: set_mission_kind(i))
	mission_row.add_child(_mission_picker)
	_station_button = _button("PICK ON CHART", func() -> void: chart_pick_requested.emit(_mission_kind == AirMission.Kind.STRIKE))
	_station_button.tooltip_text = "Close this dialog and click the station or search area on the chart; a strike picks a held contact"
	mission_row.add_child(_station_button)
	var mission_options := mission_row
	mission_options.add_child(_label("RADIUS", 12))
	_radius = SpinBox.new()
	_radius.min_value = AirMissionManager.MIN_RADIUS_NM
	_radius.max_value = AirMissionManager.MAX_RADIUS_NM
	_radius.step = 1.0
	_radius.suffix = "nm"
	_radius.custom_minimum_size = Vector2(82, 28)
	_radius.accessibility_name = "Station or search radius"
	_radius.value_changed.connect(func(_v: float) -> void: _refresh_launch())
	mission_options.add_child(_radius)
	# The standing options and, for a CAP, what it guards and how far it chases, on one line.
	var standing := HBoxContainer.new()
	standing.add_theme_constant_override("separation", 8)
	mission_page.add_child(standing)
	_relief = CheckBox.new()
	_relief.text = "Relief"
	_relief.tooltip_text = "Launch a ready reserve airframe in time to take over as each one on station turns for home"
	_relief.toggled.connect(func(on: bool) -> void:
		_relief_choice = on
		_refresh_launch())
	standing.add_child(_relief)
	_auto_return = CheckBox.new()
	_auto_return.text = "Back to station"
	_auto_return.button_pressed = true
	_auto_return.tooltip_text = "After identifying or intercepting a contact, return to the station without being told"
	_auto_return.toggled.connect(func(on: bool) -> void: _auto_return_choice = on)
	standing.add_child(_auto_return)
	_cap_options = HBoxContainer.new()
	_cap_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cap_options.add_theme_constant_override("separation", 8)
	standing.add_child(_cap_options)
	_cap_intent = OptionButton.new()
	_cap_intent.add_item("Hold area")
	_cap_intent.add_item("Protect group")
	_cap_intent.accessibility_name = "CAP purpose"
	_cap_intent.fit_to_longest_item = false
	_cap_intent.clip_text = true
	_cap_intent.custom_minimum_size.x = 136
	_cap_intent.item_selected.connect(func(_i: int) -> void:
		_anchor_picker.disabled = _cap_intent.selected == 0 or _anchors.is_empty()
		_refresh_launch())
	_cap_options.add_child(_cap_intent)
	_anchor_picker = OptionButton.new()
	_anchor_picker.custom_minimum_size.x = 120
	_anchor_picker.fit_to_longest_item = false
	_anchor_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_anchor_picker.clip_text = true
	_anchor_picker.accessibility_name = "Group protected by CAP"
	_anchor_picker.tooltip_text = "The CAP station follows this platform; interceptors prioritize closing threats."
	_anchor_picker.item_selected.connect(func(_i: int) -> void: _refresh_launch())
	_cap_options.add_child(_anchor_picker)
	var pursuit_label := _label("PURSUIT", 12)
	pursuit_label.mouse_filter = Control.MOUSE_FILTER_PASS
	pursuit_label.tooltip_text = "How far beyond the station an interceptor may chase its contact"
	_cap_options.add_child(pursuit_label)
	_pursuit = SpinBox.new()
	_pursuit.min_value = 0
	_pursuit.max_value = AirMissionManager.MAX_RADIUS_NM
	_pursuit.value = AirMissionManager.COMMIT_MARGIN_NM
	_pursuit.suffix = "nm"
	_pursuit.custom_minimum_size.x = 84
	_pursuit.accessibility_name = "CAP pursuit distance beyond station"
	_pursuit.tooltip_text = "Mission interceptors return when their contact leaves this boundary."
	_cap_options.add_child(_pursuit)
	_station_label = _label("", 12, UITheme.INK_DIM)
	_station_label.clip_text = true
	mission_page.add_child(_station_label)

	var launch_row := HBoxContainer.new()
	launch_row.add_theme_constant_override("separation", 10)
	plan.add_child(launch_row)
	launch_row.add_child(_label("AIRCRAFT", 12))
	_count = SpinBox.new()
	_count.min_value = 0
	_count.max_value = 4
	_count.value = 0
	_count.custom_minimum_size = Vector2(72, 28)
	_count.accessibility_name = "Number of aircraft to launch"
	_count.tooltip_text = "How many aircraft to send; the table previews the ready airframes in deck order"
	_count.value_changed.connect(func(_v: float) -> void: _refresh_launch())
	launch_row.add_child(_count)
	_launch = _button("LAUNCH NOW", _launch_selected)
	_launch.theme_type_variation = "PrimaryButton"
	launch_row.add_child(_launch)
	_cancel_edit = _button("DISCARD EDIT", _finish_edit)
	_cancel_edit.hide()
	launch_row.add_child(_cancel_edit)
	_launch_hint = _label("", 12, UITheme.INK_DIM)
	_launch_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_launch_hint.max_lines_visible = 2
	_launch_hint.custom_minimum_size.y = 34
	plan.add_child(_launch_hint)

	# The deck: one row per airframe of the chosen type aboard the host, in the order the deck
	# will send them, with a read-only selection indicator.
	_deck_frame = ScrollContainer.new()
	_deck_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deck_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_deck_frame.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	upper.add_child(_deck_frame)
	_deck = GridContainer.new()
	_deck.columns = DECK_COLUMNS.size()
	_deck.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deck.add_theme_constant_override("h_separation", 16)
	_deck.add_theme_constant_override("v_separation", DECK_ROW_GAP)
	_deck_frame.add_child(_deck)

	_lower_tabs = TabContainer.new()
	_lower_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lower_tabs.tab_changed.connect(func(_i: int) -> void: _queue_fit())
	page.add_child(_lower_tabs)
	var airborne_page := VBoxContainer.new()
	_airborne_page = airborne_page
	airborne_page.name = "AIRBORNE & RECOVERY"
	_lower_tabs.add_child(airborne_page)
	var recovery_head := HBoxContainer.new()
	airborne_page.add_child(recovery_head)
	var recovery_title := _label("RECOVERY", 13)
	recovery_title.add_theme_font_override("font", UITheme.data_font())
	recovery_head.add_child(recovery_title)
	var recovery_hint := _label("Select an airborne airframe, choose where it lands, then Return & Land.", 12, UITheme.INK_DIM)
	recovery_hint.clip_text = true
	recovery_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recovery_head.add_child(recovery_hint)
	_roster = Tree.new()
	_roster.hide_root = true
	_roster.columns = 6
	_roster.column_titles_visible = true
	_roster.select_mode = Tree.SELECT_ROW
	_roster.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_roster.accessibility_name = "Friendly aircraft status roster"
	_roster.tooltip_text = "Double-click an airframe or press Enter to show it on the chart."
	_roster.item_activated.connect(_show_aircraft_on_chart)
	var columns := ["AIRFRAME / TYPE", "STATE", "FUEL", "BASE", "CYCLE", "MISSION"]
	for i in columns.size():
		_roster.set_column_title(i, columns[i])
		_roster.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT)
	_roster.set_column_expand_ratio(0, 4)
	_roster.set_column_expand_ratio(1, 2)
	_roster.set_column_expand_ratio(3, 3)
	_roster.set_column_custom_minimum_width(2, 64)
	_roster.set_column_custom_minimum_width(4, 64)
	_roster.set_column_expand_ratio(5, 3)
	_roster.item_selected.connect(func() -> void:
		var item := _roster.get_selected()
		_aircraft = item.get_metadata(0) as Unit if item != null else null
		_refresh_recovery())
	airborne_page.add_child(_roster)
	_aircraft_detail = _label("Select an airframe to see fuel, ordnance and landing options.", 12, UITheme.INK_DIM)
	_aircraft_detail.custom_minimum_size.y = 34
	_aircraft_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_aircraft_detail.max_lines_visible = 2
	airborne_page.add_child(_aircraft_detail)
	var recovery_row := HBoxContainer.new()
	recovery_row.add_theme_constant_override("separation", 10)
	airborne_page.add_child(recovery_row)
	recovery_row.add_child(_label("LAND AT", 12))
	_destination = OptionButton.new()
	_destination.custom_minimum_size = Vector2(220, 28)
	_destination.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_destination.clip_text = true
	_destination.accessibility_name = "Recovery carrier or airfield"
	_destination.item_selected.connect(func(_i: int) -> void: _refresh_recovery_hint())
	recovery_row.add_child(_destination)
	_return = _button("RETURN & LAND", _return_selected)
	recovery_row.add_child(_return)
	_focus = _button("SHOW ON CHART", _show_aircraft_on_chart)
	_focus.tooltip_text = "Close this dialog and hook the airframe on the chart"
	recovery_row.add_child(_focus)

	# Missions in hand: what each deck has been told to keep in the air and what each airframe on
	# it is doing now, from QUEUED to RECOVERING.
	var missions_page := VBoxContainer.new()
	missions_page.name = "MISSIONS"
	_lower_tabs.add_child(missions_page)
	_missions = Tree.new()
	_missions.hide_root = true
	_missions.columns = 4
	_missions.column_titles_visible = true
	_missions.select_mode = Tree.SELECT_ROW
	_missions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_missions.accessibility_name = "Air missions and the state of each airframe"
	var mission_columns := ["MISSION / AIRFRAME", "STATE", "FUEL", "DECK"]
	for i in mission_columns.size():
		_missions.set_column_title(i, mission_columns[i])
		_missions.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT)
	_missions.set_column_expand_ratio(0, 4)
	_missions.set_column_expand_ratio(1, 3)
	_missions.set_column_custom_minimum_width(2, 64)
	_missions.set_column_expand_ratio(3, 2)
	_missions.item_selected.connect(func() -> void:
		var item := _missions.get_selected()
		var meta: Variant = item.get_metadata(0) if item != null else null
		_selected_mission = meta as AirMission if meta is AirMission else null
		_refresh_mission_detail())
	missions_page.add_child(_missions)
	# The selected mission's account, with its own commands beside it rather than under it.
	var mission_foot := HBoxContainer.new()
	mission_foot.add_theme_constant_override("separation", 10)
	missions_page.add_child(mission_foot)
	_mission_detail = _label("Assign a mission above; its airframes and what each is doing appear here.", 12, UITheme.INK_DIM)
	_mission_detail.custom_minimum_size.y = 34
	_mission_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mission_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mission_detail.max_lines_visible = 2
	mission_foot.add_child(_mission_detail)
	_edit_mission = _button("EDIT MISSION", _edit_selected_mission)
	_edit_mission.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_edit_mission.tooltip_text = "Move or resize the station, change strength and relief; keep the assigned aircraft."
	mission_foot.add_child(_edit_mission)
	_cancel_mission = _button("CANCEL MISSION", _cancel_selected_mission)
	_cancel_mission.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cancel_mission.tooltip_text = "Strike off queued launches and bring the mission's airborne aircraft home"
	mission_foot.add_child(_cancel_mission)

	# The footer never scrolls: what became of the last order stays in sight beside the clock.
	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 14)
	_frame.add_child(_footer)
	_receipt = _label(RECEIPT_PROMPT, 12, UITheme.INK)
	_receipt.custom_minimum_size.y = 20
	_receipt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_receipt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_receipt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_receipt.max_lines_visible = 2
	_footer.add_child(_receipt)
	_clock_hint = _label("Paused while Air Operations is open.", 12, UITheme.INK_DIM)
	_clock_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_footer.add_child(_clock_hint)
	resized.connect(_queue_fit)
	# Wrapped text only knows its height once laid out, so measure again whenever the page does.
	_page.minimum_size_changed.connect(_queue_fit)
	visibility_changed.connect(_queue_fit)
	_queue_fit()


## Stands the dialog as tall as what it shows. Each list wants a row per entry; both keep at
## least MIN_LIST_ROWS rows, and what room is left goes to whichever still has rows hidden. Only
## when the window cannot hold even that does the page itself scroll.
func _queue_fit() -> void:
	if _fit_queued or not is_inside_tree():
		return
	_fit_queued = true
	_fit.call_deferred()


func _fit() -> void:
	_fit_queued = false
	if _dialog == null or size.y <= 0.0:
		return
	var dialog_width := minf(DIALOG_WIDTH, maxf(size.x - 2.0 * EDGE_MARGIN, 0.0))
	_dialog.custom_minimum_size.x = dialog_width
	var plan := _upper.get_child(0) as Control
	var gap := float(_upper.get_theme_constant("separation"))
	var inner_width := dialog_width - _dialog.get_theme_stylebox("panel").get_minimum_size().x
	var stacked := plan.get_combined_minimum_size().x + gap + _deck_frame.get_combined_minimum_size().x > inner_width
	if _upper.vertical != stacked:
		_upper.vertical = stacked
	var frame_gap := float(_frame.get_theme_constant("separation"))
	var chrome := _dialog.get_theme_stylebox("panel").get_minimum_size().y + _header.get_combined_minimum_size().y + _footer.get_combined_minimum_size().y + 2.0 * frame_gap
	var room := size.y - 2.0 * EDGE_MARGIN - chrome
	# Deck rows: a heading and an entry per airframe (or the one line saying there are none).
	var deck_row := _deck_row_height()
	var deck_want := deck_row * float(maxi(_deck_rows.size(), 1) + 1)
	var deck_floor := minf(deck_want, deck_row * float(MIN_LIST_ROWS + 1))
	var tree := _current_tree()
	var tree_want := 0.0
	var tree_floor := 0.0
	if tree != null:
		var tree_row := _tree_row_height(tree)
		var frame := tree.get_theme_stylebox("panel").get_minimum_size().y
		tree_want = frame + tree_row * float(maxi(_tree_rows(tree), 1) + 1)
		tree_floor = minf(tree_want, frame + tree_row * float(MIN_LIST_ROWS + 1))
	# Everything on the page that is not one of the two lists.
	var plan_height := plan.get_combined_minimum_size().y
	var lower_now := _lower_tabs.get_combined_minimum_size().y if _lower_tabs.visible else 0.0
	var lower_chrome := lower_now - (tree.get_combined_minimum_size().y if tree != null else 0.0)
	var fixed := _page.get_combined_minimum_size().y - _upper.get_combined_minimum_size().y - lower_now
	var deck_height := deck_floor
	var tree_height := tree_floor
	# Beside the plan, deck rows up to the plan's height cost nothing.
	if not stacked:
		deck_height = clampf(plan_height, deck_floor, deck_want)
	var spare := room - fixed - _upper_height(stacked, plan_height, deck_height, gap) - (lower_chrome + tree_height if tree != null else 0.0)
	var deck_more := maxf(deck_want - deck_height, 0.0)
	var tree_more := maxf(tree_want - tree_height, 0.0)
	if spare > 0.0 and deck_more + tree_more > 0.0:
		var share := minf(spare / (deck_more + tree_more), 1.0)
		deck_height += deck_more * share
		tree_height += tree_more * share
	deck_height = floorf(deck_height)
	tree_height = floorf(tree_height)
	_deck_frame.custom_minimum_size.y = deck_height
	for t: Tree in [_roster, _missions]:
		t.custom_minimum_size.y = tree_height if t == tree else 0.0
	var page_height := fixed + _upper_height(stacked, plan_height, deck_height, gap) + (lower_chrome + tree_height if tree != null else 0.0)
	_body.custom_minimum_size.y = minf(page_height, maxf(room, 0.0))


static func _upper_height(stacked: bool, plan_height: float, deck_height: float, gap: float) -> float:
	return plan_height + gap + deck_height if stacked else maxf(plan_height, deck_height)


func _deck_row_height() -> float:
	var font := get_theme_font("font", "Label")
	return font.get_height(13) + float(DECK_ROW_GAP)


func _current_tree() -> Tree:
	if _lower_tabs == null or not _lower_tabs.visible:
		return null
	return _roster if _lower_tabs.current_tab == 0 else _missions


## How many rows a tree shows when nothing is folded.
func _tree_rows(tree: Tree) -> int:
	var rows := 0
	var item := tree.get_root().get_first_child() if tree.get_root() != null else null
	while item != null:
		rows += 1
		item = item.get_next_in_tree()
	return rows


func _tree_row_height(tree: Tree) -> float:
	var first := tree.get_root().get_first_child() if tree.get_root() != null else null
	if first != null:
		var area := tree.get_item_area_rect(first)
		if area.size.y > 0.0:
			return area.size.y + float(tree.get_theme_constant("v_separation"))
	return tree.get_theme_font("font").get_height(tree.get_theme_font_size("font_size")) + float(tree.get_theme_constant("v_separation")) + 6.0


func set_clock_context(was_paused: bool) -> void:
	_clock_hint.text = "Paused · Resume from the command bar" if was_paused else "Paused here · Close resumes %s×" % str(SimClock.multiplier())


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 28
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(action)
	return b


func _label(text: String, font_size: int, color := UITheme.INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func open_for(selection: Array) -> void:
	_editing_mission = null
	_cancel_edit.hide()
	_mission_picker.disabled = false
	_base = null
	_aircraft = null
	_destination_aircraft = null
	_type_id = ""
	_count.set_value_no_signal(1)
	_station = Vector2.INF
	_target = null
	set_mission_kind(-1)
	for u: Unit in selection:
		if u.faction != simulation.player_faction or not u.alive:
			continue
		if u.is_aircraft():
			_aircraft = u if u.in_flight() else null
			_base = u.home
			_type_id = u.spec.id
			break
		if u.spec.aircraft_capacity > 0:
			_base = u
			break
	show()
	refresh()
	if _aircraft != null:
		_lower_tabs.current_tab = 0
		_focus_aircraft_row.call_deferred()
	else:
		_base_picker.grab_focus.call_deferred()
	_count.value = mini(1, int(_count.max_value))
	_refresh_launch()


func _focus_aircraft_row() -> void:
	# Wait for the newly populated Tree to lay out its rows and scrollbar on reopen.
	await get_tree().process_frame
	if not is_visible_in_tree():
		return
	var row := _roster.get_selected()
	if row != null:
		_roster.grab_focus()
		_roster.scroll_to_item(row, true)


## Opens on a strike at a held contact: from the contact menu's "Air strike...".
func open_strike(selection: Array, target: Track) -> void:
	open_for(selection)
	if _base == null:
		for b in _bases:
			if b.alive and not b.stowed_aircraft().is_empty():
				_base = b
				break
		refresh()
	set_mission_kind(AirMission.Kind.STRIKE)
	_target = target
	_refresh_types()


func _default_mission_kind() -> int:
	var spec := DataDB.platform(_type_id) if _type_id != "" else null
	for kind: int in [_mission_picker.selected, AirMission.Kind.ASW, AirMission.Kind.CAP, AirMission.Kind.RECON, AirMission.Kind.STRIKE]:
		if kind >= 0 and spec != null and AirMissionManager.type_suits(spec, kind): return kind
	return AirMission.Kind.CAP


## -1 launches with no mission; otherwise an AirMission.Kind. Quantity remains explicit.
func set_mission_kind(kind: int) -> void:
	if _editing_mission != null and kind != _editing_mission.kind:
		_finish_edit()
	_mission_kind = kind
	if _mission_picker == null:
		return
	# A mission the chosen type cannot fly opens on the deck's type that can, with most ready.
	if kind >= 0 and _editing_mission == null and _type_id != "" and not AirMissionManager.type_suits(DataDB.platform(_type_id), kind):
		var suited := suited_type(_base, kind)
		if suited != "":
			_type_id = suited
			_count.set_value_no_signal(1)
	_plan_tabs.set_block_signals(true)
	_plan_tabs.set_current_tab(0 if kind < 0 else 1)
	_plan_tabs.set_block_signals(false)
	if kind >= 0:
		_mission_picker.select(kind)
	_cap_options.visible = kind == AirMission.Kind.CAP
	_station_button.disabled = kind < 0
	_radius.editable = kind >= 0 and kind != AirMission.Kind.STRIKE
	var standing := kind >= 0 and kind != AirMission.Kind.STRIKE
	if kind < 0:
		_relief_choice = false
	_relief.disabled = not standing
	_auto_return.disabled = not standing
	_relief.set_pressed_no_signal(_relief_choice and standing)
	_auto_return.set_pressed_no_signal(_auto_return_choice and standing)
	_station_button.text = "PICK TARGET" if kind == AirMission.Kind.STRIKE else "PICK ON CHART"
	if kind >= 0 and kind != AirMission.Kind.STRIKE:
		_radius.set_value_no_signal(AirMissionManager.default_radius(kind))
	if kind >= 0 and int(_count.value) == 0:
		_count.set_value_no_signal(1)
	_refresh_launch()
	_queue_fit()


## The type aboard `base` best suited to a mission of `kind`: the one with most airframes ready,
## the first in the type list on a tie; "" when none can fly it.
static func suited_type(base: Unit, kind: int) -> String:
	var best := ""
	var most := -1
	for group in inventory(base):
		if AirMissionManager.type_suits(DataDB.platform(group["id"]), kind) and int(group["ready"]) > most:
			most = int(group["ready"])
			best = group["id"]
	return best


func mission_kind() -> int:
	return _mission_kind


## What the chart pick should look like: a point with the station's radius, or a held contact.
func pick_context() -> Dictionary:
	var strike := _mission_kind == AirMission.Kind.STRIKE
	var prompt := "Strike: click a held contact" if strike else "%s: click the %s" % [AirMission.KIND_LABELS[maxi(_mission_kind, 0)], "station" if _mission_kind == AirMission.Kind.CAP else "search area"]
	return {"contact": strike, "prompt": prompt, "origin": _base.position if _base != null else Vector2.INF, "radius_nm": 0.0 if strike else float(_radius.value)}


func apply_station(pos: Vector2) -> void:
	_station = pos
	_refresh_launch()


func apply_target(t: Track) -> void:
	_target = t
	_refresh_launch()


func clear_selection() -> void:
	_base = null
	_aircraft = null
	_destination_aircraft = null
	_bases.clear()
	_destinations.clear()
	_deck_rows.clear()
	_deck_key = ""
	_station = Vector2.INF
	_target = null
	_accepted_text = ""
	_accepted_key = ""
	_accepted_at_s = -INF
	if _roster != null:
		_roster.clear()
	if _receipt != null:
		_receipt.text = RECEIPT_PROMPT
		_receipt.remove_theme_color_override("font_color")


func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum >= 0.5:
		_accum = 0.0
		# Simulation is paused here. Refresh readiness without rebuilding a focused list.
		_refresh_launch()


func refresh() -> void:
	if simulation == null:
		return
	_bases.clear()
	_base_picker.clear()
	var ready := 0
	var flying := 0
	var cycling := 0
	for u: Unit in simulation.unit_manager.units:
		if not u.alive or u.faction != simulation.player_faction:
			continue
		if u.spec.aircraft_capacity > 0:
			_bases.append(u)
			_base_picker.add_item(u.callsign + " / " + u.spec.flight_facility().to_upper())
		if u.is_aircraft():
			if u.ready_to_launch():
				ready += 1
			elif u.flight_state in [Unit.FlightState.AIRBORNE, Unit.FlightState.RECOVERING]:
				flying += 1
			else:
				cycling += 1
	if not _bases.has(_base):
		_base = _bases[0] if not _bases.is_empty() else null
	_base_picker.disabled = _bases.is_empty() or _editing_mission != null
	if _base != null:
		_base_picker.select(_bases.find(_base))
	var on_mission := simulation.air_mission_manager.active_missions(simulation.player_faction).size()
	_summary.text = "%02d READY  ·  %02d IN FLIGHT  ·  %02d IN DECK CYCLE  ·  %02d MISSIONS  ·  PAUSED" % [ready, flying, cycling, on_mission]
	_refresh_anchors()
	_refresh_types()
	_refresh_roster()
	_refresh_recovery()
	_refresh_missions()
	_queue_fit()


static func inventory(base: Unit) -> Array[Dictionary]:
	var groups: Dictionary = {}
	if base == null:
		return []
	for a: Unit in base.embarked:
		if not a.alive:
			continue
		if not groups.has(a.spec.id):
			groups[a.spec.id] = {"id": a.spec.id, "ready": 0, "total": 0}
		groups[a.spec.id]["total"] += 1
		if a.ready_to_launch():
			groups[a.spec.id]["ready"] += 1
	var out: Array[Dictionary] = []
	for id: String in groups:
		out.append(groups[id])
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return DataDB.platform(a["id"]).display_name < DataDB.platform(b["id"]).display_name)
	return out


func _refresh_types() -> void:
	_type_picker.clear()
	_type_ids.clear()
	var most_ready := ""
	var most := -1
	for group in inventory(_base):
		var spec := DataDB.platform(group["id"])
		_type_ids.append(spec.id)
		_type_picker.add_item("%s  —  %d ready of %d" % [spec.short_name, group["ready"], group["total"]])
		if int(group["ready"]) > most:
			most = int(group["ready"])
			most_ready = spec.id
	# With nothing chosen, open on the type with the most airframes ready: the deck's main effort.
	if not _type_ids.has(_type_id):
		_type_id = most_ready
	_type_picker.disabled = _type_ids.is_empty() or _editing_mission != null
	_refresh_launch()


## The airframes of the chosen type aboard the host, in deck order: the order the deck sends them.
static func deck_rows(base: Unit, type_id: String) -> Array[Unit]:
	var out: Array[Unit] = []
	if base == null or type_id == "":
		return out
	for a: Unit in base.embarked:
		if a.alive and a.spec.id == type_id and not a.in_flight():
			out.append(a)
	return out


## Which ready airframes are selected when `count` aircraft will go: the first `count` ready airframes in
## deck order, which are exactly the ones the deck launches. Pure, so the rule is pinned by tests.
static func selected_rows(rows: Array[Unit], count: int) -> Array[bool]:
	var out: Array[bool] = []
	var selected_count := 0
	for a in rows:
		var on := a.ready_to_launch() and selected_count < count
		if on:
			selected_count += 1
		out.append(on)
	return out


func _refresh_launch() -> void:
	if _launch == null or simulation == null:
		return
	if _type_ids.has(_type_id) and _type_picker.selected != _type_ids.find(_type_id):
		_type_picker.select(_type_ids.find(_type_id))
	var spec := DataDB.platform(_type_id) if _type_id != "" else null
	_portrait.texture = PlatformArt.beauty(_type_id) if spec != null else null
	if _base == null or spec == null:
		_launch.disabled = true
		_count.editable = false
		_count.max_value = 0
		_type_detail.text = "No embarked aircraft. Choose another host, or load the Carrier Qualification exercise."
		_launch_hint.text = "No aircraft type selected."
		_rebuild_deck([])
		return
	_type_detail.text = "%s  ·  %s  ·  %s operations  ·  %d kn cruise  ·  %.0f min endurance" % [spec.display_name, spec.role, spec.flight_requirement().to_upper(), int(spec.cruise_speed_kn), spec.endurance_s / 60.0]
	var reloads := PackedStringArray()
	for wid: String in spec.weapon_loadout:
		var weapon := DataDB.weapon(wid)
		reloads.append("%s %d" % [weapon.display_name if weapon != null else wid, int(_base.aviation_stores.get(wid, 0))])
	_type_detail.text += "\nBASE RELOAD STOCK: %s  /  %d sonobuoys" % [", ".join(reloads) if not reloads.is_empty() else "No weapon reloads required", _base.aviation_buoys]
	var reason := simulation.aviation_manager.launch_rejection_reason(_base, _type_id)
	var ready := 0
	for a: Unit in _base.stowed_aircraft():
		if a.spec.id == _type_id:
			ready += 1
	var spots := maxi(_base.spec.launch_capacity() - _base.launch_spots_busy(), 0)
	var maximum := mini(ready, spots) if reason == "" else 0
	if _mission_kind >= 0:
		_refresh_mission_plan(spec, ready, spots, reason)
		_rebuild_deck(deck_rows(_base, _type_id))
		return
	_station_label.text = "Choose a mission to have the deck keep a station, search an area or strike a held contact."
	_count.max_value = maximum
	_count.editable = maximum > 0
	var count := int(_count.value)
	# With nothing left to send (just after a launch, say) the button names the type, not "0 ×".
	_launch.text = "LAUNCH %d × %s" % [count, spec.short_name] if count > 0 else "LAUNCH %s" % spec.short_name
	_launch.disabled = maximum <= 0 or count <= 0
	if reason != "" and _accepted_key == _launch_key() and SimClock.sim_time - _accepted_at_s <= ACCEPTED_HINT_S:
		_launch_hint.text = _accepted_text
	elif reason != "":
		_launch_hint.text = reason.capitalize()
	elif count <= 0:
		_launch_hint.text = "%d ready  ·  %d deck spot%s free. Set the aircraft quantity." % [ready, spots, "" if spots == 1 else "s"]
	else:
		_launch_hint.text = "Launch %d × %s; airborne about %.0f s after resuming." % [count, spec.short_name, spec.launch_time_s]
	_launch.tooltip_text = _launch_hint.text
	_rebuild_deck(deck_rows(_base, _type_id))


## A mission may ask for more airframes than are ready: the deck queues the rest, launching each as
## a catapult frees and an airframe comes out of turnaround or reserve. The selection indicators show the ones that
## go now.
func _refresh_mission_plan(spec: PlatformSpec, ready: int, spots: int, deck_reason: String) -> void:
	var amm := simulation.air_mission_manager
	var available := amm.available_for(_base, _type_id, _mission_kind, _target)
	if _editing_mission != null:
		available += _editing_mission.pending_launches + AirMissionManager.working_aircraft(_editing_mission).size()
	_count.max_value = available
	_count.editable = available > 0
	var count := mini(int(_count.value), available)
	_launch.text = "UPDATE %s %d" % [_editing_mission.kind_name(), _editing_mission.id] if _editing_mission != null else ("ASSIGN %s · %d" % [AirMission.KIND_LABELS[_mission_kind].to_upper(), count] if count > 0 else "ASSIGN %s" % AirMission.KIND_LABELS[_mission_kind].to_upper())
	var why := amm.revision_rejection(_base, _planned_order()) if _editing_mission != null else amm.mission_rejection(_base, _mission_kind, _type_id, _station, _target)
	if why == "":
		why = amm._intent_rejection(_base, _planned_order())
	var now := mini(count, ready if deck_reason == "" else 0)
	now = mini(now, spots)
	var where := ""
	if _mission_kind == AirMission.Kind.STRIKE:
		if _target != null:
			where = "TARGET: track %s  %s  ·  %.0f nm %s" % [_target.id, _target.description(), _base.position.distance_to(_target.position), Geo.format_bearing(Geo.bearing_deg(_base.position, _target.position))]
		else:
			where = "TARGET: none — PICK TARGET, or open Air strike from a contact's menu"
	elif _station.is_finite():
		var on_station := AirMissionManager.station_time_s(spec, _base.position.distance_to(_station))
		where = "STATION: %s  ·  %.0f nm %s  ·  radius %.0f nm  ·  about %d min on station each" % [_position_text(_station), _base.position.distance_to(_station), Geo.format_bearing(Geo.bearing_deg(_base.position, _station)), _radius.value, maxi(int(on_station / 60.0), 0)]
	else:
		where = "STATION: none — PICK ON CHART to place it"
	_station_label.text = where
	_station_label.tooltip_text = where
	_launch.disabled = why != "" or count <= 0
	if why != "":
		_launch_hint.text = why
	elif count <= 0:
		_launch_hint.text = "%d %s available to this deck. Set how many fly the mission." % [available, spec.short_name]
	elif _editing_mission != null:
		_launch_hint.text = "Update station, radius and %d-aircraft strength. Assigned aircraft keep this mission." % count
	else:
		var queued := count - now
		_launch_hint.text = "%d launch now%s%s." % [now, ", %d queued (%s)" % [queued, (deck_reason.to_lower() if deck_reason != "" else "%s committed" % AviationManager.launch_spots_name(_base)) if deck_reason != "" or spots < count else "awaiting ready aircraft"] if queued > 0 else "", ", relieved from ready reserve" if _relief.button_pressed else ""]
	_launch.tooltip_text = _launch_hint.text
	_count.set_value_no_signal(count)


## The deck previews the launch queue; quantity is the only selection control.
func _rebuild_deck(rows: Array[Unit]) -> void:
	var ids := PackedStringArray()
	for a in rows:
		ids.append(str(a.get_instance_id()))
	var key := ",".join(ids)
	if key != _deck_key or _deck.get_child_count() == 0:
		_deck_key = key
		_deck_rows = rows
		_selection_labels.clear()
		for child in _deck.get_children():
			_deck.remove_child(child)
			child.queue_free()
		for heading: String in DECK_COLUMNS:
			var h := _label(heading, 12)
			h.add_theme_font_override("font", UITheme.data_font())
			h.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if heading == "AIRFRAME" else HORIZONTAL_ALIGNMENT_CENTER
			if heading == "AIRFRAME":
				h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_deck.add_child(h)
		for i in rows.size():
			var a := rows[i]
			# Every row is the chosen type, so the callsign alone names it.
			var name_label := _label(a.callsign, 13)
			name_label.clip_text = true
			name_label.mouse_filter = Control.MOUSE_FILTER_PASS
			name_label.tooltip_text = "%s  (%s)" % [a.callsign, a.spec.display_name]
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_deck.add_child(name_label)
			var selected_label := _label("—", 13)
			selected_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_deck.add_child(selected_label)
			_selection_labels.append(selected_label)
			for _j in 3:
				var cell := _label("", 13)
				cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				cell.add_theme_font_override("font", UITheme.data_font())
				_deck.add_child(cell)
		if rows.is_empty():
			_deck.add_child(_label("No airframes of this type aboard.", 12, UITheme.INK_DIM))
		_queue_fit()
	var selected := selected_rows(_deck_rows, int(_count.value))
	for i in _deck_rows.size():
		var a := _deck_rows[i]
		var ready := a.ready_to_launch()
		_selection_labels[i].text = "NEXT" if selected[i] else "—"
		_selection_labels[i].add_theme_color_override("font_color", UITheme.INK_GREEN if selected[i] else UITheme.INK_DIM)
		var base_cell := DECK_COLUMNS.size() * (i + 1)
		var time_s := a.spec.launch_time_s if ready else a.state_timer_s
		(_deck.get_child(base_cell + 2) as Label).text = "%02d:%02d" % [int(time_s) / 60, int(time_s) % 60] if time_s > 0.0 else "--:--"
		var state := _deck.get_child(base_cell + 3) as Label
		state.text = status_text(a)
		state.add_theme_color_override("font_color", UITheme.INK_GREEN if ready else UITheme.INK_AMBER if a.returning else UITheme.INK)
		(_deck.get_child(base_cell + 4) as Label).text = "%d%%" % int(a.fuel_fraction() * 100.0)


## A chart position as the chart's own readout writes it: latitude and longitude where the scenario
## is charted, nautical miles from the origin otherwise.
func _position_text(p: Vector2) -> String:
	var m: Dictionary = simulation.scenario.get("map", {})
	if m.has("anchor_lat"):
		var ll := Geo.world_to_latlon(p, float(m["anchor_lat"]), float(m["anchor_lon"]))
		return ChartReadout.format_position(ll.x, ll.y)
	return ChartReadout.format_offset(p)


func _launch_selected() -> void:
	if _base == null or _type_id == "" or _launch.disabled or int(_count.value) <= 0:
		return
	if _mission_kind >= 0:
		var order := _planned_order()
		var missions_before := simulation.air_mission_manager.active_missions(simulation.player_faction).size()
		order_requested.emit(_base, order)
		if _editing_mission != null:
			if order.execution_accepted:
				_finish_edit()
			return
		# Clear quantity after submission to prevent an accidental duplicate assignment, and the
		# station or target with it, so the next mission is placed afresh rather than on this one's.
		_count.set_value_no_signal(0)
		if simulation.air_mission_manager.active_missions(simulation.player_faction).size() > missions_before:
			_station = Vector2.INF
			_target = null
		_lower_tabs.current_tab = 1
		refresh()
		return
	order_requested.emit(_base, Order.launch_flight(_type_id, int(_count.value)))
	_count.set_value_no_signal(0)
	refresh()


static func status_text(a: Unit) -> String:
	match a.flight_state:
		Unit.FlightState.STOWED: return "READY"
		Unit.FlightState.LAUNCHING: return "LAUNCHING"
		Unit.FlightState.RECOVERING: return "LANDING"
		Unit.FlightState.TURNAROUND: return "REFUEL / REARM"
		Unit.FlightState.RESERVE: return "RESERVE %.0f MIN" % ceilf(a.state_timer_s / 60.0)
	if a.returning:
		return "WAITING TO LAND" if AviationManager.in_marshal(a) else "RETURNING"
	if a.tanking_on != null:
		return "TANKING"
	return "AIRBORNE"


func _refresh_roster() -> void:
	_roster.clear()
	var root := _roster.create_item()
	for a: Unit in simulation.unit_manager.units:
		if not a.alive or a.faction != simulation.player_faction or not a.is_aircraft() or not a.in_flight():
			continue
		var item := _roster.create_item(root)
		item.set_metadata(0, a)
		item.set_text(0, "%s / %s" % [a.callsign, a.spec.short_name])
		item.set_text(1, status_text(a))
		item.set_text(2, "%d%%" % int(a.fuel_fraction() * 100.0))
		var destination := a.recovery_base if a.recovery_base != null else a.home
		item.set_text(3, destination.callsign if destination != null else "OFF MAP")
		item.set_text(4, "%d:%02d" % [int(a.state_timer_s) / 60, int(a.state_timer_s) % 60] if a.state_timer_s > 0.0 else "")
		item.set_tooltip_text(0, "%s\n%s\n%s" % [a.callsign, a.spec.display_name, a.squadron])
		item.set_custom_color(1, UITheme.INK_GREEN if a.ready_to_launch() else UITheme.INK_AMBER if a.returning else UITheme.INK)
		var m := simulation.air_mission_manager.mission_for(a)
		item.set_text(5, "%s · %s" % [m.kind_name(), m.state_of(a)] if m != null else "")
		if a == _aircraft:
			item.select(0)
	var has_airborne := root.get_child_count() > 0
	var has_missions := not simulation.air_mission_manager.active_missions(simulation.player_faction).is_empty()
	_lower_tabs.set_tab_hidden(0, not has_airborne)
	if not has_airborne:
		_aircraft = null
		_lower_tabs.current_tab = 1
	elif not has_missions:
		_lower_tabs.current_tab = 0
	_lower_tabs.visible = has_airborne or has_missions


func _refresh_recovery() -> void:
	var previous: Unit = _destinations[_destination.selected] if _destination_aircraft == _aircraft and _destination.selected >= 0 and _destination.selected < _destinations.size() else null
	_destination_aircraft = _aircraft
	_destination.clear()
	_destinations.clear()
	_focus.disabled = _aircraft == null or not _aircraft.is_engageable()
	if _aircraft == null or not _aircraft.alive:
		_aircraft_detail.text = "Select an airframe to see fuel, ordnance and landing options."
		_destination.add_item("Select an airframe above")
		_return.disabled = true
		_destination.disabled = true
		return
	var a := _aircraft
	var stores := PackedStringArray()
	for wid in a.magazines:
		if int(a.magazines[wid]) > 0:
			var spec := DataDB.weapon(wid)
			stores.append("%d × %s" % [int(a.magazines[wid]), spec.display_name if spec != null else wid])
	_aircraft_detail.text = "%s  /  %s  ·  %s  ·  Fuel %d%% (%.0f min at cruise)  ·  %.0f m  ·  %.0f kn\n%s" % [a.callsign, a.spec.display_name, status_text(a), int(a.fuel_fraction() * 100.0), a.fuel_s / 60.0, a.altitude_m, a.speed_kn, ", ".join(stores) if not stores.is_empty() else "No expendable weapons carried"]
	if a.flight_state == Unit.FlightState.RECOVERING:
		_destination.add_item(a.recovery_base.callsign if a.recovery_base != null else "Landing in progress")
		_destination.disabled = true
		_return.disabled = true
		_return.tooltip_text = "Landing is already in progress."
		return
	if a.airborne():
		_destinations = simulation.aviation_manager.available_recovery_bases(a)
	for base in _destinations:
		var kind := "AIRFIELD" if base.spec.flight_facility() == "airfield" else "DECK"
		_destination.add_item("%s / %s / %.0f nm" % [base.callsign, kind, a.position.distance_to(base.position)])
	var preferred := previous if _destinations.has(previous) else a.recovery_base if a.recovery_base != null else a.home
	if _destinations.has(preferred):
		_destination.select(_destinations.find(preferred))
	if _destinations.is_empty():
		_destination.add_item("No compatible destination" if a.airborne() else "Available when airborne")
	_destination.disabled = _destinations.is_empty()
	_refresh_recovery_hint()


func _refresh_recovery_hint() -> void:
	_return.disabled = _aircraft == null or not _aircraft.airborne() or _destinations.is_empty()
	if not _return.disabled:
		var base := _destinations[_destination.selected]
		var reason := simulation.aviation_manager.recovery_rejection_reason(_aircraft, base)
		_return.disabled = reason != ""
		_return.tooltip_text = reason if reason != "" else "Return to %s, land, then refuel and rearm. Replaces the aircraft's current route." % base.callsign
	else:
		_return.tooltip_text = "Select an airborne aircraft and a compatible friendly carrier or airfield."


func _show_aircraft_on_chart() -> void:
	if _aircraft != null and _aircraft.is_engageable():
		aircraft_selected.emit(_aircraft)


func _return_selected() -> void:
	if _return.disabled:
		return
	order_requested.emit(_aircraft, Order.return_to_base(_destinations[_destination.selected]))
	refresh()


func _refresh_missions() -> void:
	if _missions == null:
		return
	_missions.clear()
	var root := _missions.create_item()
	var amm := simulation.air_mission_manager
	var list := amm.active_missions(simulation.player_faction)
	if not list.has(_selected_mission):
		_selected_mission = list[0] if not list.is_empty() else null
	for m in list:
		var head := _missions.create_item(root)
		head.set_metadata(0, m)
		head.set_text(0, "%s %d  ·  %d × %s" % [m.kind_name(), m.id, m.requested, DataDB.platform(m.platform_id).short_name])
		head.set_text(1, m.summary().trim_prefix(m.kind_name() + " · "))
		head.set_text(3, m.base_callsign)
		head.set_tooltip_text(0, m.last_report())
		for row: Dictionary in m.board_rows():
			var child := _missions.create_item(head)
			child.set_metadata(0, m)
			var a: Unit = row["aircraft"]
			child.set_text(0, "   " + (a.callsign if a != null else "(awaiting launch)"))
			child.set_text(1, str(row["state"]))
			child.set_text(2, "%d%%" % int(a.fuel_fraction() * 100.0) if a != null else "")
			var state := str(row["state"])
			child.set_custom_color(1, UITheme.INK_GREEN if state == AirMission.ON_STATION else UITheme.INK_AMBER if state in [AirMission.RETURNING, AirMission.REFUELLING, AirMission.QUEUED, AirMission.HOLDING] else UITheme.INK)
		if m == _selected_mission:
			head.select(0)
	_refresh_mission_detail()


func _refresh_mission_detail() -> void:
	if _mission_detail == null:
		return
	_cancel_mission.disabled = _selected_mission == null or not _selected_mission.active
	_edit_mission.disabled = _cancel_mission.disabled or _selected_mission.cancelled or _selected_mission.kind == AirMission.Kind.STRIKE
	if _selected_mission == null:
		_mission_detail.text = "No missions. Choose a mission above, place it on the chart, then ASSIGN MISSION."
		return
	var m := _selected_mission
	var where := "track %s" % m.target_id if m.kind == AirMission.Kind.STRIKE else "%.0f nm radius · %s" % [m.radius_nm, m.intent_label()]
	_mission_detail.text = "%s from %s, %s%s%s.\nLast report: %s" % [m.label(), m.base_callsign, where, " · relief from reserve" if m.relief else "", " · back to station after a task" if m.auto_return and m.kind != AirMission.Kind.STRIKE else "", m.last_report()]


func _cancel_selected_mission() -> void:
	if _selected_mission == null or not _selected_mission.active or _selected_mission.base == null:
		return
	order_requested.emit(_selected_mission.base, Order.cancel_air_mission(_selected_mission.id))
	refresh()


func show_receipt(message: String, accepted: bool) -> void:
	if accepted:
		_accepted_text = message
		_accepted_key = _launch_key()
		_accepted_at_s = SimClock.sim_time
	var at := int(SimClock.sim_time)
	_receipt.text = "Order %02d:%02d:%02d · %s" % [at / 3600, (at / 60) % 60, at % 60, message]
	_receipt.add_theme_color_override("font_color", UITheme.INK_GREEN if accepted else UITheme.INK_RED)


func _launch_key() -> String:
	return "%d|%s" % [_base.id if _base != null else -1, _type_id]


func _refresh_anchors() -> void:
	var previous: Unit = _anchors[_anchor_picker.selected] if _anchor_picker.selected >= 0 and _anchor_picker.selected < _anchors.size() else _base
	_anchors.clear()
	_anchor_picker.clear()
	for u: Unit in simulation.unit_manager.units:
		if u.alive and u.faction == simulation.player_faction and u.spec.domain == "surface":
			_anchors.append(u)
			_anchor_picker.add_item(u.callsign)
	if _anchors.has(previous):
		_anchor_picker.select(_anchors.find(previous))
	_anchor_picker.disabled = _cap_intent.selected == 0 or _anchors.is_empty()


func _edit_selected_mission() -> void:
	if _selected_mission == null or not _selected_mission.active or _selected_mission.kind == AirMission.Kind.STRIKE:
		return
	var m := _selected_mission
	_editing_mission = m
	_base = m.base
	_type_id = m.platform_id
	set_mission_kind(m.kind)
	_station = m.station
	_radius.set_value_no_signal(m.radius_nm)
	_relief_choice = m.relief
	_auto_return_choice = m.auto_return
	_relief.set_pressed_no_signal(m.relief)
	_auto_return.set_pressed_no_signal(m.auto_return)
	_cap_intent.select(1 if m.cap_intent == "protect" else 0)
	_pursuit.set_value_no_signal(m.pursuit_nm)
	_mission_picker.disabled = true
	_cancel_edit.show()
	_count.max_value = maxi(m.requested, 1)
	_count.set_value_no_signal(m.requested)
	refresh()
	if _anchors.has(m.protected_unit):
		_anchor_picker.select(_anchors.find(m.protected_unit))
	_refresh_launch()
	_station_button.grab_focus()


func _finish_edit() -> void:
	_editing_mission = null
	_cancel_edit.hide()
	_mission_picker.disabled = false
	_count.set_value_no_signal(0)
	refresh()


func _planned_order() -> Order:
	var order := Order.air_mission(_mission_kind, _type_id, int(_count.value), _station, float(_radius.value), _target if _mission_kind == AirMission.Kind.STRIKE else null, _relief.button_pressed, _auto_return.button_pressed)
	order.cap_intent = "protect" if _mission_kind == AirMission.Kind.CAP and _cap_intent.selected == 1 else "hold"
	order.protected_unit = _anchors[_anchor_picker.selected] if order.cap_intent == "protect" and _anchor_picker.selected >= 0 and _anchor_picker.selected < _anchors.size() else null
	order.pursuit_nm = _pursuit.value
	if _editing_mission != null:
		order.mission_id = _editing_mission.id
	return order
