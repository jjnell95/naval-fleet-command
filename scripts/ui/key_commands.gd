class_name KeyCommands
extends Control
## H: every keyboard command on one grey board over the chart, the way the old games listed them.
## The game pauses while it is up; any key or click puts it away. The table is also the one place
## the command screen's bindings are written down, so the board cannot drift from the code in
## Main that it describes without a test noticing (tests/test_cds.gd).

signal closed

## [section, [[keys, what it does], ...]]. The number-key row of TIME is written from the time
## ladder in use when the board opens (commands()), so a 4x ceiling is what the board says.
const COMMANDS := [
	["TIME", [
		["Space", "Pause or resume"],
		["1 - 6", "Time scale 1x, 2x, 5x, 10x, 30x, 60x"],
	]],
	["CHART", [
		["Left-click", "Hook a platform or contact; Shift adds"],
		["Right-click", "Water: transit there. Own platform: orders. Hostile: attack. Unknown: investigate. Inbound weapon: intercept"],
		["Shift+right-click", "Contact menu: weapons, salvos, investigate, cancel fire"],
		["Right-drag, arrows", "Pan"],
		["Wheel, + / -", "Zoom"],
		["Home / C / F", "Fit force / centre / follow"],
		["W", "Plot a route; Shift chains waypoints"],
		["Shift+W", "Patrol area: click two opposite corners"],
		["S", "Return to station after a task or refuelling"],
		["N / Shift+N", "Next / previous priority contact"],
		[".", "Hook the next own platform"],
		["B", "Range circle from the hooked platform"],
		["Tab", "NTDS or graphic symbols"],
		["Shift+V / K / I", "Velocity leaders / track numbers / tags"],
		["F2 / F4 / F5 / F6", "Symbol key / sensor rings / trails / relief"],
		["Ctrl+L / S / W", "Lat-long readout / scale / radar coverage"],
	]],
	["3D VIEW", [
		["G", "Swap the chart and the 3D view"],
		["F10", "3D view full screen"],
		["T", "Cycle cameras"],
		["F9 / F11 / F12 / F8", "Tether / fly-by / action / detached"],
	]],
	["COMMAND", [
		["J", "Fleet Operations: task groups and fleet orders"],
		["D / V", "Radar countermeasures / evasive maneuver"],
		["X", "Engage inbound weapons with interceptors (manual missile defence)"],
		["Ctrl+1..9 / Alt+1..9", "Save / recall a fleet selection group"],
		["Shift+E / Shift+R", "Weapon control / weapon ranges by role"],
		["R / P / E", "Radar / active sonar / emission control"],
		["A", "Status boards: orders, task group, track file, comms"],
		["F3", "Air operations"],
		["F1", "Orders and briefing"],
		["F7", "Reference; opens on a classified contact's class"],
		["Ctrl+K", "Actions"],
		["M / Ctrl+E", "Missions / scenario editor"],
		["Ctrl+F10 twice", "Restart the mission"],
		["Ctrl+M", "Sound on or off"],
		["H", "This board"],
	]],
]

var _panel: PanelContainer
var _left: VBoxContainer
var _right: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.15)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = "JfcDialog"
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	var title := Label.new()
	title.text = "KEY COMMANDS"
	title.theme_type_variation = "HeaderLabel"
	box.add_child(title)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	box.add_child(columns)
	_left = VBoxContainer.new()
	_right = VBoxContainer.new()
	columns.add_child(_left)
	columns.add_child(_right)
	_fill()
	var hint := Label.new()
	hint.text = "Any key or click to close"
	hint.theme_type_variation = "DimLabel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)


func _fill() -> void:
	for column: VBoxContainer in [_left, _right]:
		for child in column.get_children():
			column.remove_child(child)
			child.queue_free()
	var sections := commands()
	for i in sections.size():
		_add_section(_left if i == 1 else _right, sections[i])


## The board's rows with the number keys written for the time ladder in use.
static func commands() -> Array:
	var out: Array = COMMANDS.duplicate(true)
	var time_rows: Array = out[0][1]
	time_rows[1] = time_row(SimClock.speeds())
	return out


## "1 - 3", "Time scale 1x, 2x, 4x (the ceiling)" for a short ladder; the Normal ladder as before.
static func time_row(ladder: Array) -> Array:
	var scales := PackedStringArray()
	for v in ladder:
		scales.append("%dx" % int(v))
	var text := "Time scale " + ", ".join(scales)
	if ladder.size() < SimClock.SPEEDS.size():
		text += " (the ceiling)"
	return ["1 - %d" % ladder.size() if ladder.size() > 1 else "1", text]


func _add_section(parent: VBoxContainer, section: Array) -> void:
	var head := Label.new()
	head.text = str(section[0])
	head.theme_type_variation = "HeaderLabel"
	parent.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 2)
	parent.add_child(grid)
	for row: Array in section[1]:
		var keys := Label.new()
		keys.text = str(row[0])
		keys.theme_type_variation = "ValueLabel"
		grid.add_child(keys)
		var what := Label.new()
		what.text = str(row[1])
		grid.add_child(what)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	parent.add_child(gap)


func open() -> void:
	if _left != null:
		_fill()
	show()
	grab_focus()


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		close()
		accept_event()


## Every key (and only once) is listed somewhere on the board.
static func all_keys() -> PackedStringArray:
	var out := PackedStringArray()
	for section: Array in commands():
		for row: Array in section[1]:
			out.append(str(row[0]))
	return out


## Every row as "keys: what it does", for tests of the board's wording.
static func all_rows() -> PackedStringArray:
	var out := PackedStringArray()
	for section: Array in commands():
		for row: Array in section[1]:
			out.append("%s: %s" % [row[0], row[1]])
	return out
