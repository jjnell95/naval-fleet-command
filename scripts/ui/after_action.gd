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
## The observed events, beside the results rather than under them, so the results read whole
## and only the log, which can be long, scrolls.
var _timeline: RichTextLabel
var _review: Button
var _card: PanelContainer
var _stack: VBoxContainer
var _tiles: Dictionary = {}  # key -> {value: Label, note: Label}

const TILE_NOTE_WIDTH := 96.0
## A half-line of space before a section heading, where a whole blank line cost a line of results.
const GAP := "[font_size=6] [/font_size]\n"
## The neutrals the debrief names one by one, and the strikes it lists for each, before it counts the rest.
const MAX_NAMED_NEUTRALS := 5
const MAX_HITS_NAMED := 3


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
	_card = card
	card.theme_type_variation = "JfcDialog"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(card)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	card.add_child(margin)
	var v := VBoxContainer.new()
	_stack = v
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	# CLOSE in the header is the way back to the final chart, as every dialog closes.
	var head := UITheme.dialog_header("After-action report", func() -> void: review_pressed.emit(), "Esc / F1")
	v.add_child(head)
	_review = head.get_node("Close") as Button
	_review.tooltip_text = "Close the report and look over the final chart  [Esc]  ·  F1 brings it back"
	_time = Label.new()
	_time.add_theme_font_override("font", UITheme.data_font())
	_time.add_theme_font_size_override("font_size", 12)
	_time.add_theme_color_override("font_color", UITheme.INK_DIM)
	_time.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_time)
	head.move_child(_time, 1)
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
		# Wraps within the tile: a clipped note lost its last word ("of 6 inbound detecte").
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size.x = TILE_NOTE_WIDTH
		tv.add_child(note)
		_tiles[entry[0]] = {"value": value, "note": note}

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(columns)
	_body = _report_text("After-action report details", "Mission results. Use arrow keys, Page Up, or Page Down while focused.")
	_body.size_flags_stretch_ratio = 1.25
	columns.add_child(_body)
	columns.add_child(UITheme.hairline(true))
	_timeline = _report_text("Observed event timeline", "What your force saw and did, latest last. Use arrow keys, Page Up, or Page Down while focused.")
	columns.add_child(_timeline)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	v.add_child(buttons)
	var focus_buttons: Array[Button] = [_review]
	for entry in [["RESTART", restart_pressed, false, "restart", "Run this operation again  [Ctrl+F10]"], ["ALL OPERATIONS", menu_pressed, false, "menu", "Choose another operation  [M]"]]:
		var b := Button.new()
		b.text = entry[0]
		b.tooltip_text = entry[4]
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size.y = 36
		var sig: Signal = entry[1]
		b.pressed.connect(func() -> void: sig.emit())
		buttons.add_child(b)
		focus_buttons.append(b)
	var focus_controls: Array[Control] = [_body, _timeline]
	focus_controls.append_array(focus_buttons)
	for i in focus_controls.size():
		focus_controls[i].focus_next = focus_controls[i].get_path_to(focus_controls[(i + 1) % focus_controls.size()])
		focus_controls[i].focus_previous = focus_controls[i].get_path_to(focus_controls[posmod(i - 1, focus_controls.size())])
	resized.connect(_fit_to_screen)
	_fit_to_screen()
	hide()


## The card takes most of the screen rather than a fixed 800 x 580, so the results read whole.
func _fit_to_screen() -> void:
	if _card == null:
		return
	var screen := get_viewport_rect().size
	_card.custom_minimum_size = card_size(screen)
	# A short screen takes a smaller title and figures, so the results keep their room.
	var compact := screen.y < 850.0
	_title.add_theme_font_size_override("font_size", 40 if compact else 52)
	for key: String in _tiles:
		(_tiles[key]["value"] as Label).add_theme_font_size_override("font_size", 24 if compact else 30)
	# Tighter spacing there too, so a results column whose grade and incidents wrap to a second
	# line still reads whole at 1280 x 720.
	_stack.add_theme_constant_override("separation", 6 if compact else 10)
	for column: RichTextLabel in [_body, _timeline]:
		column.add_theme_constant_override("line_separation", 1 if compact else 3)


static func card_size(screen: Vector2) -> Vector2:
	var w := clampf(screen.x * 0.72, minf(760.0, screen.x - 24.0), 1280.0)
	var h := clampf(screen.y * 0.86, minf(540.0, screen.y - 24.0), 980.0)
	return Vector2(w, h)


static func _report_text(title: String, description: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = false
	r.scroll_active = true
	r.focus_mode = Control.FOCUS_ALL
	r.accessibility_name = title
	r.accessibility_description = description
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_constant_override("line_separation", 3)
	return r


func _set_tile(key: String, value: int, note: String, good_when_high: bool) -> void:
	var tile: Dictionary = _tiles[key]
	(tile["value"] as Label).text = str(value)
	var col := UITheme.INK
	if value > 0:
		col = UITheme.INK_GREEN if good_when_high else UITheme.INK_RED
	(tile["value"] as Label).add_theme_color_override("font_color", col)
	(tile["note"] as Label).text = note


## Where a logged result leaves the operation's campaign, or "" when it is in none.
static func campaign_line(scenario_id: String, log: Dictionary) -> String:
	var found := CampaignBook.find(scenario_id, log)
	if found.is_empty():
		return ""
	var c: Dictionary = found["campaign"]
	var step: Dictionary = found["step"]
	var names := {}
	for e: Dictionary in ScenarioIndex.list_all():
		names[str(e["id"])] = str(e["name"]).replace(" — ", " / ")
	var next := str(names.get(step["next_id"], ""))
	var gate := int(step["gate_percent"])
	var head := "%s, operation %d of %d" % [str(c.get("name", "")), int(step["step"]), int(step["total"])]
	if step["state"] == CampaignBook.WON:
		var tail := ("%s is open on the Campaigns shelf." % next) if next != "" else "The campaign is complete, averaging %d%%." % int(CampaignBook.progress(c, log)["average"])
		return "[color=%s]%s: cleared. %s[/color]" % [UITheme.HEX_INK_GREEN, _safe(head), _safe(tail)]
	if step["state"] == CampaignBook.LOCKED:
		# Flown from the Operations shelf ahead of the campaign: say what the campaign waits on.
		var waiting := "Win %s at %d%% or better first" % [str(names.get(step["frontier_id"], "the operation before it")), gate]
		if CampaignBook.cleared(step["record"], gate):
			waiting += "; this %d%% win counts once the campaign reaches it" % int(step["record"].get("best_percent", 0))
		return "[color=%s]%s is not open yet. %s.[/color]" % [UITheme.HEX_INK_AMBER, _safe(head), _safe(waiting)]
	var then := ("to open %s" % next) if next != "" else "to complete the campaign"
	return "[color=%s]%s: win at %d%% or better %s.[/color]" % [UITheme.HEX_INK_AMBER, _safe(head), gate, _safe(then)]


## `assessment` is MissionManager.assessment() at the end; `log_entry` what CommanderLog.record
## returned for it. Both optional, so the harness's direct calls keep working.
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
	lines.append((GAP if not lines.is_empty() else "") + UITheme.section_bb("Objectives", true))
	for o in objectives:
		var mo: MissionObjective = o
		lines.append("%s   %s%s" % ["[color=%s][font_size=12]DONE[/font_size][/color]" % UITheme.HEX_INK_GREEN if mo.complete else "[color=%s][font_size=12]OPEN[/font_size][/color]" % UITheme.HEX_INK_AMBER, _safe(mo.text), "  (bonus)" if mo.optional else ""])
	for mo: MissionObjective in loss_objectives:
		lines.append("[color=%s]%s[/color]   %s" % [UITheme.HEX_INK_RED if mo.complete else UITheme.HEX_INK_DIM, "FAILED" if mo.complete else "AVOIDED", _safe(mo.text)])
	lines.append(GAP + UITheme.section_bb("Civilian incidents", true) + "   " + civilian_text(civilian_incidents, assessment.get("civilian_incidents", [])))
	lines.append(UITheme.section_bb("Losses", true) + "   " + ("None" if losses.is_empty() else "[color=%s]%s[/color]" % [UITheme.HEX_INK_RED, _safe(", ".join(losses))]))
	_body.text = "\n".join(lines)
	# The exchange and the log share the second column: the exchange heads it, and the log under
	# it is the part that may run long and scroll.
	var record := PackedStringArray()
	record.append(UITheme.section_bb("The shield", true))
	record.append("%d hostile rounds detected inbound · %d intercepted · %d decoyed · %d hits taken" % [inbound, stats.get("intercepted", 0), stats.get("decoyed", 0), stats.get("hits_taken", 0)])
	record.append("[color=%s]%d interceptors expended · %d decoys[/color]" % [UITheme.HEX_INK_DIM, stats.get("launched", 0), stats.get("decoys_used", 0)])
	record.append(GAP + UITheme.section_bb("The sword", true))
	record.append("%d rounds fired by your force · %d hits scored" % [stats.get("own_rounds", 0), stats.get("hits_scored", 0)])
	record.append("[color=%s]%s[/color]" % [UITheme.HEX_INK_DIM, "No enemy units destroyed" if kills.is_empty() else "Destroyed: " + _safe(", ".join(kills))])
	record.append("[color=%s]Contacts held %d  ·  classified hostile %d  ·  aircraft sorties %d[/color]" % [UITheme.HEX_INK_FAINT, stats.get("contacts", 0), stats.get("classified", 0), stats.get("sorties", 0)])
	record.append(GAP + UITheme.section_bb("Observed event timeline", true))
	if omitted_events > 0:
		record.append("[color=%s]%d earlier messages omitted; showing the latest %d.[/color]" % [UITheme.HEX_INK_DIM, omitted_events, timeline.size()])
	if timeline.is_empty():
		record.append("No observed events recorded")
	for event: String in timeline:
		record.append("[font_size=12]%s[/font_size]" % _safe(event))
	_timeline.text = "\n".join(record)
	_fit_to_screen()
	show()
	# The results take the focus, not a button: a stray Space or Enter must not close the debrief
	# before it is read. The arrow keys scroll them; Tab reaches the buttons.
	default_focus().call_deferred("grab_focus")


func default_focus() -> Control:
	return _body


## The civilian incidents the grade charges for: every hit the force landed on a neutral, by
## vessel in the order first struck, with the weapon and the mission minute of each (a salvo's
## rounds that struck together counted as one entry), and the neutrals sunk. `hits` is the
## assessment's record ({time_s, callsign, weapon}); a report from an older build has none and
## names only the sinkings.
static func civilian_text(sunk: PackedStringArray, hits: Array) -> String:
	if sunk.is_empty() and hits.is_empty():
		return "No hits on neutral vessels by your force"
	var parts := PackedStringArray()
	if not hits.is_empty():
		var order := PackedStringArray()
		var by_vessel := {}  # callsign -> [[weapon, minute, count], ...]
		for h: Dictionary in hits:
			# What the plot called her when she was struck; a record from before that was kept
			# carries only her callsign.
			var name := str(h.get("name", h.get("callsign", "")))
			if name == "":
				name = "unidentified neutral"
			if not by_vessel.has(name):
				order.append(name)
				by_vessel[name] = []
			var entries: Array = by_vessel[name]
			var weapon := str(h.get("weapon", ""))
			var minute := int(float(h.get("time_s", 0.0)) / 60.0)
			if not entries.is_empty() and entries[-1][0] == weapon and entries[-1][1] == minute:
				entries[-1][2] += 1
			else:
				entries.append([weapon, minute, 1])
		var named := PackedStringArray()
		for i in mini(order.size(), MAX_NAMED_NEUTRALS):
			var entries: Array = by_vessel[order[i]]
			var shown := PackedStringArray()
			for e: Array in entries.slice(0, MAX_HITS_NAMED):
				var what := ("%s ×%d" % [e[0], e[2]] if e[2] > 1 else str(e[0])) if e[0] != "" else ("%d hits" % e[2] if e[2] > 1 else "hit")
				shown.append("%s at %d min" % [what, e[1]])
			if entries.size() > MAX_HITS_NAMED:
				shown.append("%d more" % (entries.size() - MAX_HITS_NAMED))
			named.append("%s (%s)" % [order[i], ", ".join(shown)])
		if order.size() > MAX_NAMED_NEUTRALS:
			named.append("%d other vessels" % (order.size() - MAX_NAMED_NEUTRALS))
		parts.append("%d %s on a neutral: %s" % [hits.size(), "hit" if hits.size() == 1 else "hits", ", ".join(named)])
	if not sunk.is_empty():
		parts.append("%d neutral %s sunk: %s" % [sunk.size(), "vessel" if sunk.size() == 1 else "vessels", ", ".join(sunk)])
	return "[color=%s]%s[/color]" % [UITheme.HEX_INK_RED, _safe(" · ".join(parts))]


static func _safe(value: String) -> String:
	return value.replace("[", "[lb]")
