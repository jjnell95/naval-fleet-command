class_name AfterAction
extends Control
## End-of-mission report: the result, the objectives, and what the magazines and the defences
## actually did. Reads a statistics dictionary that Main accumulates from simulation signals.
## A grey in-mission dialog over the final chart.

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
	shade.color = UITheme.DIALOG_SHADE
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = "JfcDialog"
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
	var eyebrow := Label.new()
	eyebrow.text = "AFTER-ACTION REPORT"
	eyebrow.add_theme_font_override("font", UITheme.data_font())
	eyebrow.add_theme_font_size_override("font_size", 14)
	eyebrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(eyebrow)
	_time = Label.new()
	_time.add_theme_font_override("font", UITheme.data_font())
	_time.add_theme_font_size_override("font_size", 12)
	_time.add_theme_color_override("font_color", UITheme.INK_DIM)
	head.add_child(_time)
	_title = Label.new()
	_title.add_theme_font_override("font", UITheme.title_font())
	_title.add_theme_font_size_override("font_size", 52)
	v.add_child(_title)
	_subtitle = Label.new()
	_subtitle.add_theme_font_override("font", UITheme.data_font())
	_subtitle.add_theme_font_size_override("font_size", 14)
	_subtitle.add_theme_color_override("font_color", UITheme.INK)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_subtitle)

	# The grade first, then four numbers that say how the fight went, before any of the detail.
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 10)
	v.add_child(tiles)
	for entry in [["effectiveness", "Mission effectiveness"], ["defended", "Rounds stopped"], ["hits_taken", "Hits taken"], ["hits_scored", "Hits scored"], ["losses", "Units lost"]]:
		var tile := PanelContainer.new()
		tile.theme_type_variation = "CardPanel"
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tiles.add_child(tile)
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", 0)
		tile.add_child(tv)
		var tile_title := UITheme.eyebrow(entry[1])
		tile_title.add_theme_color_override("font_color", UITheme.INK_BLUE)
		tv.add_child(tile_title)
		var value := Label.new()
		value.add_theme_font_override("font", UITheme.data_font())
		value.add_theme_font_size_override("font_size", 30)
		tv.add_child(value)
		var note := Label.new()
		note.add_theme_font_size_override("font_size", 11)
		note.add_theme_color_override("font_color", UITheme.INK_FAINT)
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
	for entry in [["REVIEW THE PICTURE", review_pressed, true, "eye", "Close the report and look over the final chart  [Esc]"], ["RESTART", restart_pressed, false, "restart", "Run this operation again  [Ctrl+F10]"], ["ALL OPERATIONS", menu_pressed, false, "menu", "Choose another operation  [M]"]]:
		var b := Button.new()
		b.text = entry[0]
		b.tooltip_text = entry[4]
		if entry[2]:
			b.theme_type_variation = "PrimaryButton"
			_review = b
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size.y = 36
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
	var col := UITheme.INK
	if value > 0:
		col = UITheme.INK_GREEN if good_when_high else UITheme.INK_RED
	(tile["value"] as Label).add_theme_color_override("font_color", col)
	(tile["note"] as Label).text = note


## `assessment` is MissionManager.assessment() at the end; `log_entry` what CommanderLog.record
## returned for it. Both optional, so the harness's direct calls keep working.
## Where a logged result leaves the operation's campaign, or "" when it is in none.
static func campaign_line(scenario_id: String, log: Dictionary) -> String:
	var found := CampaignBook.find(scenario_id, log)
	if found.is_empty():
		return ""
	var c: Dictionary = found["campaign"]
	var step: Dictionary = found["step"]
	var next := ""
	for e: Dictionary in ScenarioIndex.list_all():
		if e["id"] == step["next_id"]:
			next = str(e["name"]).replace(" — ", " / ")
	var head := "%s, operation %d of %d" % [str(c.get("name", "")), int(step["step"]), int(step["total"])]
	if step["state"] == CampaignBook.WON:
		var tail := ("%s is open on the Campaigns shelf." % next) if next != "" else "The campaign is complete, averaging %d%%." % int(CampaignBook.progress(c, log)["average"])
		return "[color=%s]%s: cleared. %s[/color]" % [UITheme.HEX_INK_GREEN, _safe(head), _safe(tail)]
	var then := ("to open %s" % next) if next != "" else "to complete the campaign"
	return "[color=%s]%s: win at %d%% or better %s.[/color]" % [UITheme.HEX_INK_AMBER, _safe(head), int(step["gate_percent"]), _safe(then)]


func show_report(result: String, summary: String, stats: Dictionary, objectives: Array, losses: Array, kills: Array, elapsed_s: float, timeline: Array[String] = [], civilian_incidents: PackedStringArray = [], loss_objectives: Array = [], omitted_events := 0, assessment: Dictionary = {}, log_entry: Dictionary = {}, scenario_id := "") -> void:
	var victory := result == "VICTORY"
	_title.text = result
	_title.add_theme_color_override("font_color", UITheme.INK_GREEN if victory else UITheme.INK_RED)
	_subtitle.text = summary
	_time.text = "MISSION TIME  %s" % Geo.format_duration(elapsed_s)
	var percent := int(assessment.get("percent", -1))
	var grade: Dictionary = _tiles["effectiveness"]
	if percent >= 0:
		(grade["value"] as Label).text = "%d%%" % percent
		(grade["value"] as Label).add_theme_color_override("font_color", UITheme.INK_GREEN if percent >= 50 else (UITheme.INK_AMBER if percent >= 25 else UITheme.INK_RED))
		var note := "best %d%%" % int(log_entry.get("best_percent", percent)) if not log_entry.is_empty() and not bool(log_entry.get("improved", true)) else ("a new best" if not log_entry.is_empty() and int(log_entry.get("attempts", 1)) > 1 else "graded result")
		(grade["note"] as Label).text = note
	else:
		(grade["value"] as Label).text = "—"
		(grade["note"] as Label).text = "not graded"
	var inbound := int(stats.get("hostile_rounds", 0))
	var stopped := int(stats.get("intercepted", 0)) + int(stats.get("decoyed", 0))
	_set_tile("defended", stopped, "of %d inbound detected" % inbound if inbound > 0 else "none inbound", true)
	_set_tile("hits_taken", int(stats.get("hits_taken", 0)), "on your force", false)
	_set_tile("hits_scored", int(stats.get("hits_scored", 0)), "from %d rounds fired" % int(stats.get("own_rounds", 0)), true)
	_set_tile("losses", losses.size(), "%d enemy destroyed" % kills.size(), false)

	var lines := PackedStringArray()
	if percent >= 0:
		lines.append(UITheme.section_bb("Mission effectiveness", true))
		lines.append(_safe(MissionManager.assessment_text(assessment)))
		var attempts := int(log_entry.get("attempts", 0))
		if attempts > 1:
			lines.append("[color=%s]Attempt %d · best %d%% (%s), set %s[/color]" % [UITheme.HEX_INK_DIM, attempts, int(log_entry.get("best_percent", percent)), str(log_entry.get("result", result)).to_lower(), _safe(str(log_entry.get("date", "")))])
		elif attempts == 1:
			lines.append("[color=%s]First attempt, entered in the commander's log[/color]" % UITheme.HEX_INK_DIM)
		if not log_entry.is_empty():
			var line := campaign_line(scenario_id, CommanderLog.load_all())
			if line != "":
				lines.append(line)
		lines.append("")
	lines.append(UITheme.section_bb("Objectives", true))
	for o in objectives:
		var mo: MissionObjective = o
		lines.append("%s   %s" % ["[color=%s][font_size=12]DONE[/font_size][/color]" % UITheme.HEX_INK_GREEN if mo.complete else "[color=%s][font_size=12]OPEN[/font_size][/color]" % UITheme.HEX_INK_AMBER, _safe(mo.text)])
	for mo: MissionObjective in loss_objectives:
		lines.append("[color=%s]%s[/color]   %s" % [UITheme.HEX_INK_RED if mo.complete else UITheme.HEX_INK_DIM, "FAILED" if mo.complete else "AVOIDED", _safe(mo.text)])
	lines.append("\n" + UITheme.section_bb("Civilian incidents", true))
	lines.append("No neutral vessels sunk by your force" if civilian_incidents.is_empty() else "[color=%s]%d neutral vessel(s) sunk by your force: %s[/color]" % [UITheme.HEX_INK_RED, civilian_incidents.size(), _safe(", ".join(civilian_incidents))])
	lines.append("\n" + UITheme.section_bb("The shield", true))
	lines.append("%d hostile rounds detected inbound · %d intercepted · %d decoyed · %d hits taken" % [inbound, stats.get("intercepted", 0), stats.get("decoyed", 0), stats.get("hits_taken", 0)])
	lines.append("[color=%s]%d interceptors expended · %d decoys[/color]" % [UITheme.HEX_INK_DIM, stats.get("launched", 0), stats.get("decoys_used", 0)])
	lines.append("\n" + UITheme.section_bb("The sword", true))
	lines.append("%d rounds fired by your force · %d hits scored" % [stats.get("own_rounds", 0), stats.get("hits_scored", 0)])
	lines.append("[color=%s]%s[/color]" % [UITheme.HEX_INK_DIM, "No enemy units destroyed" if kills.is_empty() else "Destroyed: " + _safe(", ".join(kills))])
	lines.append("\n" + UITheme.section_bb("Losses", true))
	lines.append("None" if losses.is_empty() else _safe(", ".join(losses)))
	lines.append("\n[color=%s]Contacts held %d  ·  classified hostile %d  ·  aircraft sorties %d[/color]" % [UITheme.HEX_INK_FAINT, stats.get("contacts", 0), stats.get("classified", 0), stats.get("sorties", 0)])
	lines.append("\n" + UITheme.section_bb("Observed event timeline", true))
	if omitted_events > 0:
		lines.append("%d earlier messages omitted; showing the latest %d." % [omitted_events, timeline.size()])
	if timeline.is_empty():
		lines.append("No observed events recorded")
	for event: String in timeline:
		lines.append(_safe(event))
	_body.text = "\n".join(lines)
	show()
	if _review != null:
		_review.call_deferred("grab_focus")


static func _safe(value: String) -> String:
	return value.replace("[", "[lb]")
