class_name AfterAction
extends PanelContainer
## End-of-mission report: the result, the objectives, and what the magazines and the defences
## actually did. Reads a statistics dictionary that Main accumulates from simulation signals.

signal review_pressed()
signal restart_pressed()
signal menu_pressed()

var _title: Label
var _subtitle: Label
var _body: RichTextLabel


func _ready() -> void:
	theme_type_variation = "CardPanel"
	set_anchors_preset(Control.PRESET_CENTER)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -380.0
	offset_right = 380.0
	offset_top = -250.0
	offset_bottom = 250.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
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
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_body)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	v.add_child(buttons)
	for entry in [["REVIEW THE PICTURE", review_pressed, true], ["RESTART  F10", restart_pressed, false], ["MISSIONS  F9", menu_pressed, false]]:
		var b := Button.new()
		b.text = entry[0]
		if entry[2]:
			b.theme_type_variation = "PrimaryButton"
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: entry[1].emit())
		buttons.add_child(b)
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
