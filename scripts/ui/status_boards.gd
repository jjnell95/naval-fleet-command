class_name StatusBoards
extends PanelContainer
## The ASTABs: automated status boards over the chart, opened with A. They hold everything the
## command screen does not keep on display: the full orders board, the task group with its roster
## and event log, the track file with the air-defence board, and the comms history. The game keeps
## running while they are open; they are a window onto the watch, not a pause screen.
##
## The Track File renders when its tab is visible. Chart shortcuts and palette counts read its
## filtered reports directly while the boards are closed.

signal closed
## The comms history came on screen, by any route: the lamp, A, or a click on the COMMS tab.
signal comms_shown
signal report_located(position: Vector2)

const BOARD_ORDERS := 0
const BOARD_TASK_GROUP := 1
const BOARD_TRACKS := 2
const BOARD_COMMS := 3
const BOARD_ASSESSMENT := 4
const TITLES := ["ORDERS", "TASK GROUP", "TRACK FILE", "COMMS", "ASSESSMENT"]
## How often the battle assessment is read again while it is on screen.
const ASSESSMENT_REFRESH_S := 1.0
const MAX_MESSAGES := 120
## Inks for grey chrome, each at least 4.5:1 on the lightest button face.
const SEVERITY_COLORS := {"alert": UITheme.HEX_FACE_INK_ALERT, "warn": UITheme.HEX_FACE_INK_WARN, "good": UITheme.HEX_FACE_INK_GOOD}
## The boards dock at the foot of the chart and stand only as tall as their content, so the plot
## above stays in view while orders are given. They never reach higher than this below the top.
const TOP_CLEARANCE := 18.0
const BOTTOM_CLEARANCE := 12.0
## The comms history has no natural height; it gets this much, or all there is.
const COMMS_HEIGHT := 320.0

var _tabs: TabContainer
var _comms: RichTextLabel
var _messages: Array[Dictionary] = []
var _fit_queued := false
var _assessment: RichTextLabel
var _assessment_accum := 0.0
## Returns the running battle assessment: {"assessment": MissionManager.assessment(),
## "objectives": [MissionObjective], "kills": [String], "losses": [String]}. Main supplies it.
var assessment_source: Callable


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
	_tabs.tab_changed.connect(func(_tab: int) -> void:
		_announce_comms()
		_queue_fit())
	visibility_changed.connect(_announce_comms)
	visibility_changed.connect(_queue_fit)
	_comms = RichTextLabel.new()
	_comms.name = "Comms"
	_comms.bbcode_enabled = true
	_comms.scroll_following = false
	_comms.meta_clicked.connect(func(position: Variant) -> void:
		if position is Vector2 and position.is_finite():
			report_located.emit(position))
	_assessment = RichTextLabel.new()
	_assessment.name = "Assessment"
	_assessment.bbcode_enabled = true
	_assessment.fit_content = true
	_assessment.scroll_active = false
	_assessment.selection_enabled = false
	_assessment.minimum_size_changed.connect(_queue_fit)


## Moves a panel onto a board. Panels arrive from the scene in board order. Every page scrolls, so
## no board ever needs more height than the chart has; `fill` false keeps a panel at its own height
## at the top of the page (the orders panel was laid out as a one-row dock, and stretched it falls
## apart).
func host(panel: Control, board: int, fill := true) -> void:
	if panel.get_parent() != null:
		panel.get_parent().remove_child(panel)
	while _tabs.get_tab_count() < board:
		var spacer := Control.new()
		_tabs.add_child(spacer)
	var page := ScrollContainer.new()
	page.name = "%sPage" % panel.name
	page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.follow_focus = true
	page.add_child(panel)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL if fill else Control.SIZE_SHRINK_BEGIN
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.minimum_size_changed.connect(_queue_fit)
	_tabs.add_child(page)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, TITLES[board])


func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED:
		var parent := get_parent() as Control
		if parent != null and not parent.resized.is_connected(_queue_fit):
			parent.resized.connect(_queue_fit)


func _queue_fit() -> void:
	if not _fit_queued:
		_fit_queued = true
		_fit.call_deferred()


## Stands the boards on the foot of the chart at the height the open board's content asks for,
## and no taller than the chart; a board with more than that scrolls.
func _fit() -> void:
	_fit_queued = false
	var parent := get_parent() as Control
	if parent == null or not visible:
		return
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_bottom = -BOTTOM_CLEARANCE
	var room := maxf(0.0, parent.size.y - TOP_CLEARANCE - BOTTOM_CLEARANCE)
	var wanted := get_combined_minimum_size().y + content_height()
	offset_top = offset_bottom - minf(wanted, room)


## The height the open board's content would take with nothing scrolled.
func content_height() -> float:
	var page := _tabs.get_current_tab_control()
	if page == _comms:
		return COMMS_HEIGHT
	if page != null and page.name == "AssessmentPage":
		return _assessment.get_content_height() + 8.0
	if page is ScrollContainer and page.get_child_count() > 0:
		return (page.get_child(0) as Control).get_combined_minimum_size().y
	return 0.0


## Adds the comms board and the battle assessment last, after the panels.
func finish_boards() -> void:
	if _comms.get_parent() == null:
		_tabs.add_child(_comms)
		_tabs.set_tab_title(_tabs.get_tab_count() - 1, TITLES[BOARD_COMMS])
	if _assessment.get_parent() == null:
		var page := ScrollContainer.new()
		page.name = "AssessmentPage"
		page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		page.add_child(_assessment)
		_assessment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tabs.add_child(page)
		_tabs.set_tab_title(_tabs.get_tab_count() - 1, TITLES[BOARD_ASSESSMENT])


func open_board(board: int) -> void:
	_tabs.current_tab = clampi(board, 0, _tabs.get_tab_count() - 1)
	show()
	_fit()


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


func _announce_comms() -> void:
	if showing_comms():
		_render_messages()
		comms_shown.emit()
	if showing_assessment():
		render_assessment()


func _process(delta: float) -> void:
	if not showing_assessment():
		return
	_assessment_accum += delta
	if _assessment_accum >= ASSESSMENT_REFRESH_S:
		render_assessment()


func showing_assessment() -> bool:
	return visible and current_board() == BOARD_ASSESSMENT


## The battle as it stands: mission effectiveness and its parts, the enemy and own losses, and
## each task with whether it is done. Read again every second while it is on screen.
func render_assessment() -> void:
	_assessment_accum = 0.0
	if not assessment_source.is_valid():
		return
	var d: Dictionary = assessment_source.call()
	var a: Dictionary = d.get("assessment", {})
	var lines := PackedStringArray()
	if a.is_empty():
		lines.append("No operation is running.")
	else:
		lines.append("[b]MISSION EFFECTIVENESS  %d%%[/b]" % int(a.get("percent", 0)))
		lines.append(MissionManager.assessment_text(a).replace("[", "[lb]"))
	var kills: Array = d.get("kills", [])
	var losses: Array = d.get("losses", [])
	lines.append("")
	lines.append("[b]ENEMY LOSSES  %d[/b]" % kills.size())
	lines.append(_listing(kills, "None confirmed"))
	lines.append("[b]OWN LOSSES  %d[/b]" % losses.size())
	lines.append(_listing(losses, "None"))
	lines.append("")
	var tasks: Array = d.get("objectives", [])
	var done := 0
	var task_lines := PackedStringArray()
	for o: MissionObjective in tasks:
		if o.phase_only:
			continue
		done += int(o.complete)
		var state := "[color=%s]DONE[/color]" % SEVERITY_COLORS["good"] if o.complete else ("OPEN" if o.unlocked else "LATER")
		task_lines.append("%s   %s%s" % [state, o.text.replace("[", "[lb]"), "  (bonus)" if o.optional else ""])
	lines.append("[b]TASKS  %d OF %d DONE[/b]" % [done, task_lines.size()])
	if task_lines.is_empty():
		task_lines.append("No set tasks")
	lines.append_array(task_lines)
	_assessment.text = "\n".join(lines)


func _listing(names: Array, none: String) -> String:
	if names.is_empty():
		return none
	var out := PackedStringArray()
	for n in names:
		out.append(str(n).replace("[", "[lb]"))
	return ", ".join(out)


func current_board() -> int:
	return _tabs.current_tab if _tabs != null else -1


func showing_comms() -> bool:
	return visible and current_board() == BOARD_COMMS


func add_message(text: String, severity := "info", reported_position := Vector2.INF) -> void:
	var stamp := DataDisplay.clock_text()
	var colour: String = SEVERITY_COLORS.get(severity, "")
	var body := text.replace("[", "[lb]")
	var report := {"line": "[b]%s[/b]   %s" % [stamp, body if colour == "" else "[color=%s]%s[/color]" % [colour, body]]}
	if reported_position.is_finite():
		report["position"] = reported_position
	_messages.push_front(report)
	if _messages.size() > MAX_MESSAGES:
		_messages.resize(MAX_MESSAGES)
	if showing_comms():
		_render_messages()


func restore_messages(saved: Array) -> void:
	_messages.clear()
	for entry in saved.slice(0, MAX_MESSAGES):
		if entry is String:
			_messages.append({"line": entry}) # Earlier saves kept only formatted text.
		elif entry is Dictionary and entry.get("line") is String:
			_messages.append(entry)
	if showing_comms():
		_render_messages()


func _render_messages() -> void:
	_comms.clear()
	for index in _messages.size():
		var report := _messages[index]
		if index > 0:
			_comms.newline()
		var position: Variant = report.get("position")
		if position is Vector2 and position.is_finite():
			_comms.push_meta(position, RichTextLabel.META_UNDERLINE_ALWAYS, "Center the chart on this report’s recorded position")
			_comms.add_text("Locate")
			_comms.pop()
			_comms.add_text("   ")
		_comms.append_text(report.line)


func clear_messages() -> void:
	_messages.clear()
	if _comms != null:
		_comms.text = ""


func message_count() -> int:
	return _messages.size()
