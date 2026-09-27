class_name KeyCommands
extends Control
## H: every keyboard command on one grey board over the chart, the way the old games listed them.
## The game pauses while it is up; any key or click puts it away. The table is also the one place
## the command screen's bindings are written down, so the board cannot drift from the code in
## Main that it describes without a test noticing (tests/test_cds.gd).

signal closed

## [section, [[keys, what it does], ...]]
const COMMANDS := [
	["TIME", [
		["Space", "Pause or resume"],
		["1 - 6", "Time scale 1x, 2x, 5x, 10x, 30x, 60x"],
	]],
	["CHART", [
		["Left-click", "Hook a platform or contact; Shift adds"],
		["Right-click", "Water: transit there. Platform: orders. Contact: engage"],
		["Right-drag, arrows", "Pan"],
		["Wheel, + / -", "Zoom"],
		["Home / C / F", "Fit force / centre / follow"],
		["W", "Plot a route; Shift chains waypoints"],
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
		["R / P / E", "Radar / active sonar / emission control"],
		["A", "Status boards: orders, task group, track file, comms"],
		["F3", "Air operations"],
		["F1", "Orders and briefing"],
		["F7", "Reference"],
		["Ctrl+K", "Actions"],
		["M / Ctrl+E", "Missions / scenario editor"],
		["Ctrl+F10 twice", "Restart the mission"],
		["Ctrl+M", "Sound on or off"],
		["H", "This board"],
	]],
]

var _panel: PanelContainer


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
	title.theme_type_variation = "DialogTitle"
	box.add_child(title)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	box.add_child(columns)
	var left := VBoxContainer.new()
	var right := VBoxContainer.new()
	columns.add_child(left)
	columns.add_child(right)
	for i in COMMANDS.size():
		_add_section(left if i == 1 else right, COMMANDS[i])
	var hint := Label.new()
	hint.text = "Any key or click to close"
	hint.theme_type_variation = "DialogHint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)


func _add_section(parent: VBoxContainer, section: Array) -> void:
	var head := Label.new()
	head.text = str(section[0])
	head.theme_type_variation = "DialogSection"
	parent.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 2)
	parent.add_child(grid)
	for row: Array in section[1]:
		var keys := Label.new()
		keys.text = str(row[0])
		keys.theme_type_variation = "DialogKey"
		grid.add_child(keys)
		var what := Label.new()
		what.text = str(row[1])
		grid.add_child(what)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	parent.add_child(gap)


func open() -> void:
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
	for section: Array in COMMANDS:
		for row: Array in section[1]:
			out.append(str(row[0]))
	return out
