class_name CommandPalette
extends Control
## Searchable, keyboard-first launcher for context-sensitive commands.
##
## The caller owns command construction and execution. This control only presents action
## dictionaries and emits the selected action's stable id. Expected dictionary keys:
## id, label, description, shortcut, enabled, with optional state and reason.

signal action_requested(id: String)
signal closed()

const CARD_MIN_SIZE := Vector2(680.0, 540.0)
const CONTROL_MIN_HEIGHT := 44.0

var _actions: Array[Dictionary] = []
var _filtered_actions: Array[Dictionary] = []
var _search: LineEdit
var _list: ItemList
var _count: Label
var _detail: Label
var _close_button: Button
var _row_spacer: Texture2D
var _previous_focus: Control


func _ready() -> void:
	name = "CommandPalette"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 200
	accessibility_name = "Command palette"
	accessibility_description = "Search and run commands available for the current selection."
	_build_interface()
	hide()


func _build_interface() -> void:
	var shade := ColorRect.new()
	shade.name = "Backdrop"
	shade.color = Color(0.01, 0.025, 0.04, 0.88)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card := PanelContainer.new()
	card.name = "Card"
	card.theme_type_variation = "CardPanel"
	card.custom_minimum_size = CARD_MIN_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	card.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)

	var title := Label.new()
	title.text = "COMMAND PALETTE"
	title.theme_type_variation = "TitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_count = Label.new()
	_count.name = "ResultCount"
	_count.theme_type_variation = "DimLabel"
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count.accessibility_name = "Command result count"
	header.add_child(_count)

	_close_button = Button.new()
	_close_button.name = "CloseButton"
	_close_button.text = "CLOSE  ESC"
	_close_button.custom_minimum_size = Vector2(112.0, CONTROL_MIN_HEIGHT)
	_close_button.focus_mode = Control.FOCUS_ALL
	_close_button.accessibility_name = "Close command palette"
	_close_button.tooltip_text = "Close the command palette (Escape)"
	_close_button.pressed.connect(close_palette)
	header.add_child(_close_button)

	_search = LineEdit.new()
	_search.name = "Search"
	_search.placeholder_text = "Search commands, shortcuts, or states…"
	_search.clear_button_enabled = true
	_search.custom_minimum_size.y = 48.0
	_search.focus_mode = Control.FOCUS_ALL
	_search.accessibility_name = "Search commands"
	_search.accessibility_description = "Type one or more words to filter the available commands."
	_search.text_changed.connect(_filter)
	_apply_search_styles()
	column.add_child(_search)

	_list = ItemList.new()
	_list.name = "ActionList"
	_list.custom_minimum_size.y = 320.0
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.focus_mode = Control.FOCUS_ALL
	_list.select_mode = ItemList.SELECT_SINGLE
	_list.add_theme_font_size_override("font_size", 14)
	_list.add_theme_constant_override("v_separation", 12)
	_list.add_theme_constant_override("h_separation", 8)
	_list.fixed_icon_size = Vector2i(1, 32)
	_list.accessibility_name = "Available commands"
	_list.accessibility_description = "Use the arrow keys to choose a command and Enter to run it."
	_list.item_selected.connect(_on_item_selected)
	_list.item_activated.connect(_activate_index)
	_apply_list_styles()
	column.add_child(_list)

	_detail = Label.new()
	_detail.name = "CommandDetail"
	_detail.custom_minimum_size.y = 54.0
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.theme_type_variation = "DimLabel"
	_detail.accessibility_name = "Selected command details"
	column.add_child(_detail)

	var footer := Label.new()
	footer.name = "KeyboardHint"
	footer.text = "UP/DOWN  CHOOSE    ENTER  RUN    ESC  CLOSE"
	footer.theme_type_variation = "HeaderLabel"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.accessibility_name = "Keyboard controls"
	footer.accessibility_description = "Up and down choose a command. Enter runs it. Escape closes the palette."
	column.add_child(footer)

	_row_spacer = _make_row_spacer()
	_set_focus_cycle()
	_filter("")


func set_actions(actions: Array[Dictionary]) -> void:
	_actions.clear()
	for source: Dictionary in actions:
		var id := str(source.get("id", "")).strip_edges()
		var label := str(source.get("label", "")).strip_edges()
		if id == "" or label == "":
			continue
		var action := source.duplicate(true)
		action["id"] = id
		action["label"] = label
		action["description"] = str(action.get("description", ""))
		action["shortcut"] = str(action.get("shortcut", ""))
		action["enabled"] = bool(action.get("enabled", true))
		action["state"] = str(action.get("state", ""))
		action["reason"] = str(action.get("reason", ""))
		_actions.append(action)
	if _search != null:
		_filter(_search.text)


func open_palette() -> void:
	if is_inside_tree():
		_previous_focus = get_viewport().gui_get_focus_owner()
	show()
	if _search == null:
		return
	_search.clear()
	_filter("")
	call_deferred("_focus_search")


func close_palette(restore_focus := true) -> void:
	if not visible:
		return
	hide()
	if restore_focus and is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.call_deferred("grab_focus")
	_previous_focus = null
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var focus := get_viewport().gui_get_focus_owner()
	var navigating_results := focus == _search or focus == _list
	match key.keycode:
		KEY_ESCAPE:
			close_palette()
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			if navigating_results:
				_activate_selected()
				get_viewport().set_input_as_handled()
		KEY_DOWN:
			if navigating_results:
				_move_selection(1)
				get_viewport().set_input_as_handled()
		KEY_UP:
			if navigating_results:
				_move_selection(-1)
				get_viewport().set_input_as_handled()


func _filter(query: String) -> void:
	if _list == null:
		return
	_filtered_actions.clear()
	var terms := query.strip_edges().to_lower().split(" ", false)
	for action: Dictionary in _actions:
		var haystack := " ".join([
			str(action.get("id", "")),
			str(action.get("label", "")),
			str(action.get("description", "")),
			str(action.get("shortcut", "")),
			str(action.get("state", "")),
			str(action.get("reason", "")),
		]).to_lower()
		var matches := true
		for term in terms:
			if not haystack.contains(term):
				matches = false
				break
		if matches:
			_filtered_actions.append(action)
	_rebuild_list()


func _rebuild_list() -> void:
	_list.clear()
	if _filtered_actions.is_empty():
		_list.add_item("NO MATCHING COMMANDS", _row_spacer)
		_list.set_item_disabled(0, true)
		_count.text = "0 / %d" % _actions.size()
		_detail.text = "Try a broader search, a shortcut key, or a command state such as active or silent."
		return

	for action: Dictionary in _filtered_actions:
		var index := _list.item_count
		_list.add_item(_row_text(action), _row_spacer)
		_list.set_item_metadata(index, action)
		_list.set_item_tooltip(index, _tooltip_text(action))
		_list.set_item_disabled(index, not bool(action.get("enabled", true)))
	_count.text = "%d / %d" % [_filtered_actions.size(), _actions.size()]
	_list.accessibility_description = "%d commands shown. Use the arrow keys to choose and Enter to run. Unavailable commands include the reason in their row label." % _filtered_actions.size()
	var initial := _first_enabled_index()
	if initial >= 0:
		_list.select(initial)
		_list.ensure_current_is_visible()
		_update_detail(initial)
	else:
		_update_detail(0)


func _row_text(action: Dictionary) -> String:
	var enabled := bool(action.get("enabled", true))
	var state := str(action.get("state", "")).strip_edges()
	var shortcut := str(action.get("shortcut", "")).strip_edges()
	var prefix := "    " if enabled else "--  "
	var suffix := ""
	if state != "":
		suffix += "    [%s]" % state.to_upper()
	if shortcut != "":
		suffix += "    %s" % shortcut
	if not enabled:
		var reason := str(action.get("reason", "")).strip_edges()
		suffix += "    UNAVAILABLE" + (": " + reason if reason != "" else "")
	return "%s%s%s" % [prefix, str(action.get("label", "")), suffix]


func _tooltip_text(action: Dictionary) -> String:
	var lines := PackedStringArray([str(action.get("label", ""))])
	var description := str(action.get("description", "")).strip_edges()
	var state := str(action.get("state", "")).strip_edges()
	var shortcut := str(action.get("shortcut", "")).strip_edges()
	if description != "":
		lines.append(description)
	if state != "":
		lines.append("Current state: " + state)
	if shortcut != "":
		lines.append("Shortcut: " + shortcut)
	if not bool(action.get("enabled", true)):
		var reason := str(action.get("reason", "")).strip_edges()
		lines.append("Unavailable" + (": " + reason if reason != "" else ""))
	return "\n".join(lines)


func _on_item_selected(index: int) -> void:
	_update_detail(index)


func _update_detail(index: int) -> void:
	if index < 0 or index >= _filtered_actions.size():
		return
	var action := _filtered_actions[index]
	var description := str(action.get("description", "")).strip_edges()
	var state := str(action.get("state", "")).strip_edges()
	var shortcut := str(action.get("shortcut", "")).strip_edges()
	var parts := PackedStringArray()
	if description != "":
		parts.append(description)
	if state != "":
		parts.append("Current state: " + state)
	if shortcut != "":
		parts.append("Shortcut: " + shortcut)
	if not bool(action.get("enabled", true)):
		var reason := str(action.get("reason", "")).strip_edges()
		parts.append("Unavailable" + (": " + reason if reason != "" else "."))
	_detail.text = "  \u00b7  ".join(parts) if not parts.is_empty() else "Press Enter to run this command."
	_detail.accessibility_description = _detail.text


func _activate_selected() -> void:
	if _list == null:
		return
	var selected := _list.get_selected_items()
	if selected.is_empty():
		return
	_activate_index(selected[0])


func _activate_index(index: int) -> void:
	if index < 0 or index >= _filtered_actions.size():
		return
	var action := _filtered_actions[index]
	if not bool(action.get("enabled", true)):
		_update_detail(index)
		return
	var id := str(action.get("id", ""))
	if id == "":
		return
	var fallback_focus := _previous_focus
	# The invoked command owns the next focus target. Restoring the pre-palette focus here would
	# run deferred and steal focus back from actions such as Plot Move or Engagement.
	close_palette(false)
	action_requested.emit(id)
	call_deferred("_restore_focus_if_unclaimed", fallback_focus)


func _restore_focus_if_unclaimed(fallback: Control) -> void:
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null and owner.is_visible_in_tree():
		return
	if is_instance_valid(fallback) and fallback.is_visible_in_tree():
		fallback.grab_focus()


func _move_selection(direction: int) -> void:
	if _filtered_actions.is_empty():
		return
	var selected := _list.get_selected_items()
	var index := selected[0] if not selected.is_empty() else 0
	for _attempt in _filtered_actions.size():
		index = clampi(index + direction, 0, _filtered_actions.size() - 1)
		if bool(_filtered_actions[index].get("enabled", true)):
			_list.select(index)
			_list.ensure_current_is_visible()
			_update_detail(index)
			return
		if index == 0 or index == _filtered_actions.size() - 1:
			return


func _first_enabled_index() -> int:
	for i in _filtered_actions.size():
		if bool(_filtered_actions[i].get("enabled", true)):
			return i
	return -1


func _focus_search() -> void:
	if visible and _search != null:
		_search.grab_focus()


func _set_focus_cycle() -> void:
	_search.focus_next = _search.get_path_to(_list)
	_search.focus_previous = _search.get_path_to(_close_button)
	_list.focus_next = _list.get_path_to(_close_button)
	_list.focus_previous = _list.get_path_to(_search)
	_close_button.focus_next = _close_button.get_path_to(_search)
	_close_button.focus_previous = _close_button.get_path_to(_list)


func _apply_search_styles() -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("081019")
	normal.border_color = Color("527a91")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	var focused := normal.duplicate()
	focused.border_color = UITheme.COL_ACCENT
	focused.set_border_width_all(2)
	_search.add_theme_stylebox_override("normal", normal)
	_search.add_theme_stylebox_override("focus", focused)


func _apply_list_styles() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("081019")
	panel.border_color = Color("527a91")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(4)
	panel.content_margin_left = 8
	panel.content_margin_right = 8
	panel.content_margin_top = 6
	panel.content_margin_bottom = 6
	_list.add_theme_stylebox_override("panel", panel)
	var focused := StyleBoxFlat.new()
	focused.bg_color = Color.TRANSPARENT
	focused.border_color = UITheme.COL_ACCENT
	focused.set_border_width_all(2)
	focused.set_corner_radius_all(4)
	_list.add_theme_stylebox_override("focus", focused)


func _make_row_spacer() -> Texture2D:
	var image := Image.create(1, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	return ImageTexture.create_from_image(image)
