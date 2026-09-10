class_name ScenarioMenu
extends PanelContainer
## Full-screen scenario picker. Built from ScenarioIndex, so dropping a new JSON file into
## data/scenarios is enough to make it appear here.

signal scenario_chosen(path: String)
signal dismissed()

var _list: ItemList
var _detail: Label
var _play: Button
var _close: Button
var _entries: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 90)
	margin.add_theme_constant_override("margin_right", 90)
	margin.add_theme_constant_override("margin_top", 50)
	margin.add_theme_constant_override("margin_bottom", 50)
	add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	var title := Label.new()
	title.text = "NAVAL FLEET COMMAND"
	title.add_theme_font_size_override("font_size", 24)
	v.add_child(title)

	var sub := Label.new()
	sub.text = "Select a scenario. All situations are fictional."
	sub.modulate = Color(0.55, 0.68, 0.78)
	v.add_child(sub)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(330, 0)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.focus_mode = Control.FOCUS_NONE
	_list.item_selected.connect(_on_selected)
	_list.item_activated.connect(func(_i: int) -> void: _on_play())
	body.add_child(_list)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_detail)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	v.add_child(buttons)
	_play = Button.new()
	_play.text = "BRIEF AND DEPLOY"
	_play.focus_mode = Control.FOCUS_NONE
	_play.pressed.connect(_on_play)
	buttons.add_child(_play)
	_close = Button.new()
	_close.text = "BACK"
	_close.focus_mode = Control.FOCUS_NONE
	_close.pressed.connect(func() -> void: dismissed.emit())
	buttons.add_child(_close)

	refresh()


func refresh(current_path := "") -> void:
	_entries = ScenarioIndex.list_all()
	_list.clear()
	var select := 0
	for i in _entries.size():
		var e: Dictionary = _entries[i]
		_list.add_item(e["name"])
		if e["path"] == current_path:
			select = i
	if not _entries.is_empty():
		_list.select(select)
		_on_selected(select)


func allow_back(can_go_back: bool) -> void:
	_close.visible = can_go_back


func _on_selected(i: int) -> void:
	if i < 0 or i >= _entries.size():
		return
	var e: Dictionary = _entries[i]
	_detail.text = "%s\n\n%s\n\n%s" % [e["name"], e["forces"], e["description"]]


func _on_play() -> void:
	var i := _list.get_selected_items()
	if i.is_empty():
		return
	scenario_chosen.emit(_entries[i[0]]["path"])
