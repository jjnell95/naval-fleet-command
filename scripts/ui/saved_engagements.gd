class_name SavedEngagements
extends PanelContainer
## The saved engagements, as a grey dialog over the chart: the quicksave, the autosave history and
## any saves made by hand, newest first, with what each one is and when in the battle it was taken.
## Load and save go through Main, which owns the files and the screen; this only lists and asks.

signal load_requested(path: String)
signal save_requested
signal delete_requested(path: String)
signal closed

const DIALOG_SIZE := Vector2(760.0, 470.0)

var _list: Tree
var _detail: Label
var _load: Button
var _delete: Button
var _save: Button
var _headers: Array[Dictionary] = []
var _can_save := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := StyleBoxFlat.new()
	shade.bg_color = UITheme.DIALOG_SHADE
	add_theme_stylebox_override("panel", shade)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var dialog := PanelContainer.new()
	dialog.theme_type_variation = "JfcDialog"
	dialog.custom_minimum_size = DIALOG_SIZE
	center.add_child(dialog)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	dialog.add_child(page)
	var title := Label.new()
	title.text = "SAVED ENGAGEMENTS"
	title.add_theme_font_override("font", UITheme.data_font())
	title.add_theme_font_size_override("font_size", 14)
	page.add_child(title)
	var hint := Label.new()
	hint.text = "Quicksave Ctrl+Shift+S, quickload Ctrl+Shift+L. The battle is autosaved every %d minutes of simulated time; the newest %d autosaves are kept." % [int(SaveGame.AUTOSAVE_INTERVAL_S / 60.0), SaveGame.AUTOSAVE_KEEP]
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", UITheme.INK_DIM)
	page.add_child(hint)
	_list = Tree.new()
	_list.hide_root = true
	_list.columns = 4
	_list.column_titles_visible = true
	_list.select_mode = Tree.SELECT_ROW
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.accessibility_name = "Saved engagements"
	var titles := ["SAVE", "OPERATION", "BATTLE TIME", "SAVED"]
	for i in titles.size():
		_list.set_column_title(i, titles[i])
		_list.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT)
	_list.set_column_expand_ratio(0, 2)
	_list.set_column_expand_ratio(1, 4)
	_list.set_column_expand_ratio(2, 2)
	_list.set_column_expand_ratio(3, 2)
	_list.item_selected.connect(_refresh_detail)
	_list.item_activated.connect(func() -> void: _load_selected())
	page.add_child(_list)
	_detail = Label.new()
	_detail.custom_minimum_size.y = 36
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_detail)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	page.add_child(buttons)
	_load = _button("LOAD", _load_selected)
	_load.theme_type_variation = "PrimaryButton"
	buttons.add_child(_load)
	_save = _button("SAVE NOW", func() -> void: save_requested.emit())
	_save.tooltip_text = "Save the running engagement as a new entry"
	buttons.add_child(_save)
	_delete = _button("DELETE", func() -> void:
		var h := _selected()
		if not h.is_empty():
			delete_requested.emit(str(h["path"])))
	buttons.add_child(_delete)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(gap)
	buttons.add_child(_button("CLOSE", func() -> void: closed.emit()))


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(110, 28)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(action)
	return b


## `can_save` is false when no engagement is running (the desk, an ended battle).
func open(can_save: bool) -> void:
	_can_save = can_save
	show()
	refresh()
	_list.call_deferred("grab_focus")


func refresh() -> void:
	_headers = SaveGame.list_saves()
	_list.clear()
	var root := _list.create_item()
	for h in _headers:
		var item := _list.create_item(root)
		item.set_metadata(0, str(h["path"]))
		item.set_text(0, str(h.get("label", h.get("slot", ""))))
		item.set_text(1, str(h.get("scenario_name", "")))
		item.set_text(2, str(h.get("clock_text", "")))
		item.set_text(3, Time.get_datetime_string_from_unix_time(int(h.get("created_unix", 0)), true).replace("T", " ").left(16))
		for column in 4:
			item.set_tooltip_text(column, "%s\n%s" % [h.get("scenario_name", ""), h.get("note", "")])
	if _list.get_root().get_child_count() > 0:
		_list.get_root().get_child(0).select(0)
	_save.disabled = not _can_save
	_refresh_detail()


func _selected() -> Dictionary:
	var item := _list.get_selected()
	if item == null:
		return {}
	var path := str(item.get_metadata(0))
	for h in _headers:
		if str(h["path"]) == path:
			return h
	return {}


func _refresh_detail() -> void:
	var h := _selected()
	_load.disabled = h.is_empty()
	_delete.disabled = h.is_empty()
	if h.is_empty():
		_detail.text = "No saved engagements yet." if _headers.is_empty() else "Select a save."
		return
	_detail.text = "%s, %s into the battle (%s). %s" % [h.get("scenario_name", ""), h.get("elapsed_text", ""), h.get("clock_text", ""), h.get("note", "")]
	# The rules it was fought under come back with it, whatever the player's own choice is now.
	if str(h.get("gameplay", "")) != "":
		_detail.text += "\nGameplay %s: it continues under these options." % h["gameplay"]


func _load_selected() -> void:
	var h := _selected()
	if not h.is_empty():
		load_requested.emit(str(h["path"]))


func show_message(text: String, good: bool) -> void:
	_detail.text = text
	_detail.add_theme_color_override("font_color", UITheme.INK_GREEN if good else UITheme.INK_RED)
