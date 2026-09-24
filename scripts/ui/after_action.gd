class_name AfterAction
extends Control
## End-of-mission report: the result, the objectives, and what the magazines and the defences
## actually did. Reads a statistics dictionary that Main accumulates from simulation signals.

signal review_pressed()
signal restart_pressed()
signal menu_pressed()

var _title: Label
var _subtitle: Label
var _time: Label
var _body: RichTextLabel
var _review: Button
var _tiles: Dictionary = {}  # key -> {value: Label, note: Label}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 180
	accessibility_name = "After-action report"
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.025, 0.04, 0.82)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = "FloatingPanel"
	card.custom_minimum_size = Vector2(800.0, 580.0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(card)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	card.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	var eyebrow := UITheme.eyebrow("After-action report")
	eyebrow.add_theme_color_override("font_color", UITheme.COL_BRASS)
	eyebrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(eyebrow)
	_time = Label.new()
	_time.add_theme_font_override("font", UITheme.mono_font())
	_time.add_theme_font_size_override("font_size", 12)
	_time.add_theme_color_override("font_color", UITheme.COL_MUTED)
	head.add_child(_time)
	_title = Label.new()
	_title.add_theme_font_override("font", UITheme.heading_font())
	_title.add_theme_font_size_override("font_size", 56)
	v.add_child(_title)
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 15)
	_subtitle.add_theme_color_override("font_color", UITheme.COL_DIM)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_subtitle)

	# Four numbers that say how the fight went, before any of the detail.
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 10)
	v.add_child(tiles)
	for entry in [["defended", "Rounds stopped"], ["hits_taken", "Hits taken"], ["hits_scored", "Hits scored"], ["losses", "Units lost"]]:
		var tile := PanelContainer.new()
		tile.theme_type_variation = "CardPanel"
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tiles.add_child(tile)
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", 0)
		tile.add_child(tv)
		tv.add_child(UITheme.eyebrow(entry[1]))
		var value := Label.new()
		value.add_theme_font_override("font", UITheme.heading_font())
		value.add_theme_font_size_override("font_size", 34)
		tv.add_child(value)
		var note := Label.new()
		note.add_theme_font_size_override("font_size", 11)
		note.add_theme_color_override("font_color", UITheme.COL_MUTED)
		note.clip_text = true
		tv.add_child(note)
		_tiles[entry[0]] = {"value": value, "note": note}

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = false
	_body.scroll_active = true
	_body.focus_mode = Control.FOCUS_ALL
	_body.accessibility_name = "After-action report details"
	_body.accessibility_description = "Scrollable mission results. Use arrow keys, Page Up, or Page Down while focused."
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("line_separation", 5)
	v.add_child(_body)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	v.add_child(buttons)
	var focus_buttons: Array[Button] = []
	for entry in [["REVIEW THE PICTURE", review_pressed, true, "eye", "Close the report and look over the final chart  [Esc]"], ["RESTART", restart_pressed, false, "restart", "Run this operation again  [F10]"], ["ALL OPERATIONS", menu_pressed, false, "menu", "Choose another operation  [F9]"]]:
		var b := Button.new()
		b.text = entry[0]
		b.tooltip_text = entry[4]
		if entry[2]:
			b.theme_type_variation = "PrimaryButton"
			_review = b
		UIIcons.apply(b, entry[3], 16)
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size.y = 42
		var sig: Signal = entry[1]
		b.pressed.connect(func() -> void: sig.emit())
		buttons.add_child(b)
		focus_buttons.append(b)
	var focus_controls: Array[Control] = [_body]
	focus_controls.append_array(focus_buttons)
	for i in focus_controls.size():
		focus_controls[i].focus_next = focus_controls[i].get_path_to(focus_controls[(i + 1) % focus_controls.size()])
		focus_controls[i].focus_previous = focus_controls[i].get_path_to(focus_controls[posmod(i - 1, focus_controls.size())])
	hide()


func _set_tile(key: String, value: int, note: String, good_when_high: bool) -> void:
	var tile: Dictionary = _tiles[key]
	(tile["value"] as Label).text = str(value)
	var col := UITheme.COL_TEXT
	if value > 0:
		col = UITheme.COL_GREEN if good_when_high else UITheme.COL_RED
	(tile["value"] as Label).add_theme_color_override("font_color", col)
	(tile["note"] as Label).text = note


func show_report(result: String, summary: String, stats: Dictionary, objectives: Array, losses: Array, kills: Array, elapsed_s: float) -> void:
	var victory := result == "VICTORY"
	_title.text = result
	_title.add_theme_color_override("font_color", UITheme.COL_GREEN if victory else UITheme.COL_RED)
	_subtitle.text = summary
	_time.text = "MISSION TIME  %s" % Geo.format_duration(elapsed_s)
	var inbound := int(stats.get("hostile_rounds", 0))
	var stopped := int(stats.get("intercepted", 0)) + int(stats.get("decoyed", 0))
	_set_tile("defended", stopped, "of %d inbound detected" % inbound if inbound > 0 else "none inbound", true)
	_set_tile("hits_taken", int(stats.get("hits_taken", 0)), "on your force", false)
	_set_tile("hits_scored", int(stats.get("hits_scored", 0)), "from %d rounds fired" % int(stats.get("own_rounds", 0)), true)
	_set_tile("losses", losses.size(), "%d enemy destroyed" % kills.size(), false)

	var lines := PackedStringArray()
	lines.append(UITheme.section_bb("Objectives"))
	for o in objectives:
		var mo: MissionObjective = o
		lines.append("%s   %s" % ["[color=%s][font_size=12]DONE[/font_size][/color]" % UITheme.HEX_GREEN if mo.complete else "[color=%s][font_size=12]OPEN[/font_size][/color]" % UITheme.HEX_AMBER, mo.text])
	lines.append("\n" + UITheme.section_bb("The shield"))
	lines.append("%d hostile rounds detected inbound · %d intercepted · %d decoyed · %d hits taken" % [inbound, stats.get("intercepted", 0), stats.get("decoyed", 0), stats.get("hits_taken", 0)])
	lines.append("[color=%s]%d interceptors expended · %d decoys[/color]" % [UITheme.HEX_DIM, stats.get("launched", 0), stats.get("decoys_used", 0)])
	lines.append("\n" + UITheme.section_bb("The sword"))
	lines.append("%d rounds fired by your force · %d hits scored" % [stats.get("own_rounds", 0), stats.get("hits_scored", 0)])
	lines.append("[color=%s]%s[/color]" % [UITheme.HEX_DIM, "No enemy units destroyed" if kills.is_empty() else "Destroyed: " + ", ".join(kills)])
	lines.append("\n" + UITheme.section_bb("Losses"))
	lines.append("None" if losses.is_empty() else ", ".join(losses))
	lines.append("\n[color=%s]Contacts held %d  ·  classified hostile %d  ·  aircraft sorties %d[/color]" % [UITheme.HEX_MUTED, stats.get("contacts", 0), stats.get("classified", 0), stats.get("sorties", 0)])
	_body.text = "\n".join(lines)
	show()
	if _review != null:
		_review.call_deferred("grab_focus")
