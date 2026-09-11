class_name AfterAction
extends Control
## End-of-mission report: the result, the objectives, and what the magazines and the defences
## actually did. Reads a statistics dictionary that Main accumulates from simulation signals.

signal review_pressed()
signal restart_pressed()
signal menu_pressed()

var _title: Label
var _subtitle: Label
var _body: RichTextLabel
var _review: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 180
	accessibility_name = "After-action report"
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.025, 0.04, 0.88)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = "CardPanel"
	card.custom_minimum_size = Vector2(760.0, 500.0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	var eyebrow := Label.new()
	eyebrow.text = "AFTER-ACTION REPORT"
	eyebrow.theme_type_variation = "HeaderLabel"
	v.add_child(eyebrow)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 34)
	v.add_child(_title)
	_subtitle = Label.new()
	_subtitle.theme_type_variation = "DimLabel"
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_subtitle)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = false
	_body.scroll_active = true
	_body.focus_mode = Control.FOCUS_ALL
	_body.accessibility_name = "After-action report details"
	_body.accessibility_description = "Scrollable mission results. Use arrow keys, Page Up, or Page Down while focused."
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_body)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	v.add_child(buttons)
	var focus_buttons: Array[Button] = []
	for entry in [["REVIEW THE PICTURE", review_pressed, true], ["RESTART  F10", restart_pressed, false], ["MISSIONS  F9", menu_pressed, false]]:
		var b := Button.new()
		b.text = entry[0]
		if entry[2]:
			b.theme_type_variation = "PrimaryButton"
			_review = b
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size.y = 44
		b.pressed.connect(func() -> void: entry[1].emit())
		buttons.add_child(b)
		focus_buttons.append(b)
	var focus_controls: Array[Control] = [_body]
	focus_controls.append_array(focus_buttons)
	for i in focus_controls.size():
		focus_controls[i].focus_next = focus_controls[i].get_path_to(focus_controls[(i + 1) % focus_controls.size()])
		focus_controls[i].focus_previous = focus_controls[i].get_path_to(focus_controls[posmod(i - 1, focus_controls.size())])
	hide()


func show_report(result: String, summary: String, stats: Dictionary, objectives: Array, losses: Array, kills: Array, elapsed_s: float) -> void:
	_title.text = result
	_title.add_theme_color_override("font_color", UITheme.COL_GREEN if result == "VICTORY" else UITheme.COL_RED)
	_subtitle.text = summary
	var lines := PackedStringArray()
	lines.append("[color=%s]Mission time %s[/color]" % [UITheme.HEX_DIM, Geo.format_duration(elapsed_s)])
	lines.append("\n[color=%s][b]OBJECTIVES[/b][/color]" % UITheme.HEX_ACCENT)
	for o in objectives:
		var mo: MissionObjective = o
		lines.append("  %s  %s" % ["[color=%s]DONE[/color]" % UITheme.HEX_GREEN if mo.complete else "[color=%s]OPEN[/color]" % UITheme.HEX_AMBER, mo.text])
	lines.append("\n[color=%s][b]THE SHIELD[/b][/color]" % UITheme.HEX_ACCENT)
	var inbound := int(stats.get("hostile_rounds", 0))
	lines.append("  %d hostile rounds detected inbound · %d intercepted · %d decoyed · %d hits taken" % [inbound, stats.get("intercepted", 0), stats.get("decoyed", 0), stats.get("hits_taken", 0)])
	lines.append("  %d interceptors expended · %d decoys" % [stats.get("launched", 0), stats.get("decoys_used", 0)])
	lines.append("\n[color=%s][b]THE SWORD[/b][/color]" % UITheme.HEX_ACCENT)
	lines.append("  %d rounds fired by your force · %d hits scored" % [stats.get("own_rounds", 0), stats.get("hits_scored", 0)])
	if kills.is_empty():
		lines.append("  no enemy units destroyed")
	else:
		lines.append("  destroyed: %s" % ", ".join(kills))
	lines.append("\n[color=%s][b]LOSSES[/b][/color]" % UITheme.HEX_ACCENT)
	lines.append("  %s" % ("none" if losses.is_empty() else ", ".join(losses)))
	lines.append("\n[color=%s]Contacts held: %d · classified hostile: %d · aircraft sorties: %d[/color]" % [UITheme.HEX_DIM, stats.get("contacts", 0), stats.get("classified", 0), stats.get("sorties", 0)])
	_body.text = "\n".join(lines)
	show()
	if _review != null:
		_review.call_deferred("grab_focus")
