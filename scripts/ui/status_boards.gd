class_name StatusBoards
extends PanelContainer
## The ASTABs: automated status boards over the chart, opened with A. They hold everything the
## command screen does not keep on display: the full orders board, the task group with its roster
## and event log, the track file with the air-defence board, and the comms history. The game keeps
## running while they are open; they are a window onto the watch, not a pause screen.
##
## The panels themselves are the same ones the deck has always used, re-hosted here. They keep
## refreshing while hidden where other controls depend on them (the track file's filtered rows
## drive N and Shift+N).

signal closed

const BOARD_ORDERS := 0
const BOARD_TASK_GROUP := 1
const BOARD_TRACKS := 2
const BOARD_COMMS := 3
const TITLES := ["ORDERS", "TASK GROUP", "TRACK FILE", "COMMS"]
const MAX_MESSAGES := 120
const SEVERITY_COLORS := {"alert": "#c01818", "warn": "#9a5a00", "good": "#0a6a1a"}

var _tabs: TabContainer
var _comms: RichTextLabel
var _messages: Array[String] = []


func _ready() -> void:
	theme_type_variation = "JfcDialog"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.text = "STATUS BOARDS"
	title.theme_type_variation = "HeaderLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "CLOSE  [A]"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_boards)
	header.add_child(close)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	_comms = RichTextLabel.new()
	_comms.name = "Comms"
	_comms.bbcode_enabled = true
	_comms.scroll_following = false


## Moves a panel onto a board. Panels arrive from the scene in board order. A board page is
## always the full height of the boards; `fill` false keeps a panel at its own height at the top of
## the page instead (the orders panel was laid out as a one-row dock, and stretched it falls apart).
func host(panel: Control, board: int, fill := true) -> void:
	if panel.get_parent() != null:
		panel.get_parent().remove_child(panel)
	while _tabs.get_tab_count() < board:
		var spacer := Control.new()
		_tabs.add_child(spacer)
	var page: Control = panel
	if not fill:
		page = VBoxContainer.new()
		page.name = "%sPage" % panel.name
		page.add_child(panel)
		panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	else:
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.add_child(page)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, TITLES[board])


## Adds the comms board last, after the panels.
func finish_boards() -> void:
	if _comms.get_parent() == null:
		_tabs.add_child(_comms)
		_tabs.set_tab_title(_tabs.get_tab_count() - 1, TITLES[BOARD_COMMS])


func open_board(board: int) -> void:
	show()
	_tabs.current_tab = clampi(board, 0, _tabs.get_tab_count() - 1)


func toggle(board := -1) -> void:
	if visible and (board < 0 or _tabs.current_tab == board):
		close_boards()
	else:
		open_board(_tabs.current_tab if board < 0 else board)


func close_boards() -> void:
	if not visible:
		return
	hide()
	closed.emit()


func current_board() -> int:
	return _tabs.current_tab if _tabs != null else -1


func showing_comms() -> bool:
	return visible and current_board() == BOARD_COMMS


func add_message(text: String, severity := "info") -> void:
	var stamp := DataDisplay.clock_text()
	var colour: String = SEVERITY_COLORS.get(severity, "")
	var body := text.replace("[", "[lb]")
	_messages.push_front("[b]%s[/b]   %s" % [stamp, body if colour == "" else "[color=%s]%s[/color]" % [colour, body]])
	if _messages.size() > MAX_MESSAGES:
		_messages.resize(MAX_MESSAGES)
	if _comms != null:
		_comms.text = "\n".join(_messages)


func clear_messages() -> void:
	_messages.clear()
	if _comms != null:
		_comms.text = ""


func message_count() -> int:
	return _messages.size()
