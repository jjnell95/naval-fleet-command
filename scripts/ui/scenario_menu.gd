class_name ScenarioMenu
extends PanelContainer
## Operations desk. Scenario files supply the briefing and period, including custom missions.
## Drawn as a late-1990s front end: the dusk backdrop, one translucent grey-metal panel, the
## wordmark, big bevelled shelf buttons, a starred mission list beside its map, the orders in a
## text box below, and ACCEPT / CANCEL captions beside their buttons.

signal scenario_chosen(path: String)
signal dismissed()
signal editor_requested()
signal library_requested()
## The commander chose a preset or changed one option in the GAMEPLAY row; Main applies and saves
## it, then shows the result back with set_options.
signal options_requested(options: GameOptions)

const RowList = preload("res://scripts/ui/tactical_row_list.gd")
## Difficulty as green stars, the way mission lists showed it.
const STARS := {"Introductory": "★", "Intermediate": "★★", "Advanced": "★★★"}
const INTRO_PATH := "res://data/scenarios/northern_passage.json"

var _list: RowList
var _detail: RichTextLabel
var _preview: ScenarioPreview
var _play: Button
var _close: Button
var _close_pair: Control
var _entries: Array = []
var _all_entries: Array = []
## The shelf on view. The authored operations are the front door, as the mission list was in
## the late-1990s fleet-command games; the player's own missions have their own shelf.
var _era := "operations"
var _filters: Dictionary = {}
var _mission_title: Label
var _mission_meta: Label
var _intent: Label
var _count: Label
var _portrait: PlatformPortrait
var _ship_caption: Label
var _margin: MarginContainer
var _left: VBoxContainer
var _rail: VBoxContainer
var _title: TitleMark
var _initial_refresh := true
var _layout: VBoxContainer
var _subtitle: Label
var _mast_note: Label
var _panel: PanelContainer
var _top: HBoxContainer
var _intro: Button
## The options the desk shows: Main's, set by set_options. The desk never saves them itself.
var _options := GameOptions.normal()
var _style_buttons: Dictionary = {}  # preset name -> Button
var _options_menu: MenuButton
var _options_summary: Label
var _options_box: VBoxContainer


func _ready() -> void:
	theme_type_variation = "OverlayPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UITheme.backdrop())
	_margin = MarginContainer.new()
	add_child(_margin)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = "MenuPanel"
	_margin.add_child(_panel)
	var v := VBoxContainer.new()
	_layout = v
	v.add_theme_constant_override("separation", 12)
	_panel.add_child(v)

	var masthead := HBoxContainer.new()
	masthead.add_theme_constant_override("separation", 18)
	v.add_child(masthead)
	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", -4)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	masthead.add_child(brand)
	_title = TitleMark.new("NAVAL FLEET COMMAND", 54)
	brand.add_child(_title)
	_subtitle = _label("Build the picture. Protect the force. Control the sea.", 14, UITheme.MENU_INK)
	brand.add_child(_subtitle)
	# GAMEPLAY: the preset and its options, chosen here once and kept between sessions.
	_options_box = VBoxContainer.new()
	_options_box.add_theme_constant_override("separation", 2)
	_options_box.size_flags_vertical = Control.SIZE_SHRINK_END
	masthead.add_child(_options_box)
	_mast_note = _label("Choose an operation and read its orders. The clock waits for you.", 13, UITheme.MENU_INK)
	_mast_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_options_box.add_child(_mast_note)
	var style_row := HBoxContainer.new()
	style_row.add_theme_constant_override("separation", 6)
	style_row.alignment = BoxContainer.ALIGNMENT_END
	_options_box.add_child(style_row)
	var style_caption := UITheme.caption("Gameplay")
	style_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	style_row.add_child(style_caption)
	for entry in [[GameOptions.NORMAL, "NORMAL", GameOptions.preset_description(GameOptions.NORMAL)], [GameOptions.CLASSIC, "CLASSIC", "The late-1990s way of playing: " + GameOptions.preset_description(GameOptions.CLASSIC)]]:
		var preset: String = entry[0]
		var b := _button(entry[1])
		b.theme_type_variation = "MenuBigButton"
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(96, 32)
		b.add_theme_font_size_override("font_size", 15)
		b.tooltip_text = entry[2]
		b.pressed.connect(func() -> void: _choose_preset(preset))
		style_row.add_child(b)
		_style_buttons[preset] = b
	_options_menu = MenuButton.new()
	_options_menu.text = "OPTIONS ▾"
	_options_menu.flat = false
	_options_menu.focus_mode = Control.FOCUS_ALL
	_options_menu.custom_minimum_size = Vector2(0, 32)
	_options_menu.add_theme_font_size_override("font_size", 15)
	_options_menu.tooltip_text = "Choose the options one at a time; any change from a preset is CUSTOM"
	var popup := _options_menu.get_popup()
	for i in GameOptions.OPTION_KEYS.size():
		var key: String = GameOptions.OPTION_KEYS[i]
		if key == "":
			popup.add_separator()
		else:
			popup.add_check_item(GameOptions.option_text(key), i)
			popup.set_item_tooltip(popup.get_item_index(i), GameOptions.option_tooltip(key))
	popup.id_pressed.connect(_toggle_option)
	style_row.add_child(_options_menu)
	_options_summary = _label("", 12, UITheme.INK_BLUE)
	_options_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_options_summary.clip_text = true
	_options_summary.custom_minimum_size.x = 380
	_options_box.add_child(_options_summary)

	# The shelves, as the big bevelled menu buttons; the open shelf is pressed in.
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 10)
	v.add_child(filter_row)
	_intro = _button("START NORTHERN PASSAGE")
	_intro.theme_type_variation = "MenuBigButton"
	_intro.custom_minimum_size = Vector2(0, 44)
	_intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_intro.add_theme_font_size_override("font_size", 19)
	_intro.tooltip_text = "Start here: protect a freighter, launch reconnaissance and identify contacts. Opens the briefing with time paused."
	_intro.pressed.connect(func() -> void: scenario_chosen.emit(INTRO_PATH))
	filter_row.add_child(_intro)
	for entry in [["operations", "OPERATIONS", "Seven authored operations, one 2027 operation in each of four theatres and three from 1990, with stars for difficulty and your best result"], ["campaigns", "CAMPAIGNS", "The same operations as two campaigns, 1990 and 2027, taken in order: win each at 60% or better to open the next"], ["training", "TRAINING", "Two missions to learn on: the screen and the contact picture, then the air-operations cycle"], ["custom", "MY MISSIONS", "Missions you built or imported"]]:
		var key: String = entry[0]
		var button := _button(entry[1])
		button.theme_type_variation = "MenuBigButton"
		button.custom_minimum_size = Vector2(0, 44)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 19)
		button.toggle_mode = true
		button.tooltip_text = entry[2]
		button.pressed.connect(func() -> void: _set_era(key))
		filter_row.add_child(button)
		_filters[key] = button

	# The list and its map, side by side, as on a mission-selection screen.
	_top = HBoxContainer.new()
	_top.add_theme_constant_override("separation", 16)
	v.add_child(_top)
	_left = VBoxContainer.new()
	_left.add_theme_constant_override("separation", 4)
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top.add_child(_left)
	var list_head := HBoxContainer.new()
	_left.add_child(list_head)
	var caption := UITheme.caption("Operations")
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_head.add_child(caption)
	_count = _label("", 12, UITheme.MENU_INK)
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	list_head.add_child(_count)
	_list = RowList.new()
	_list.theme_type_variation = "MenuList"
	_list.single_line = true
	_list.badge_width = 46.0
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.focus_mode = Control.FOCUS_ALL
	_list.accessibility_name = "Available operations"
	_list.accessibility_description = "Choose a mission to read its task and first orders. Enter opens the briefing."
	_list.max_columns = 1
	_list.configure_rows(14, 12, 20)
	_list.add_theme_constant_override("v_separation", 3)
	_list.item_selected.connect(_on_selected)
	_list.item_activated.connect(func(_i: int) -> void: _on_play())
	_left.add_child(_list)
	_preview = ScenarioPreview.new()
	_top.add_child(_preview)
	_rail = VBoxContainer.new()
	_rail.add_theme_constant_override("separation", 6)
	_top.add_child(_rail)
	_portrait = PlatformPortrait.new()
	_portrait.show_captions = false
	_portrait.framed = true
	_portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rail.add_child(_portrait)
	_ship_caption = _label("", 12, UITheme.MENU_INK)
	_ship_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rail.add_child(_ship_caption)

	# The orders, in a text box below the list and the map.
	var detail_card := _card()
	detail_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(detail_card)
	var operation := VBoxContainer.new()
	operation.add_theme_constant_override("separation", 4)
	detail_card.add_child(operation)
	_mission_title = _label("", 26, UITheme.MENU_INK)
	_mission_title.add_theme_font_override("font", UITheme.caption_font())
	_mission_title.clip_text = true
	operation.add_child(_mission_title)
	_mission_meta = _label("", 11, UITheme.INK_BLUE)
	_mission_meta.add_theme_font_override("font", UITheme.eyebrow_font())
	_mission_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	operation.add_child(_mission_meta)
	_intent = _label("", 15, UITheme.MENU_INK)
	_intent.add_theme_font_override("font", UITheme.data_font())
	_intent.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intent.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	operation.add_child(_intent)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.fit_content = false
	_detail.scroll_active = true
	_detail.focus_mode = Control.FOCUS_ALL
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.accessibility_name = "Selected operation plan"
	_detail.add_theme_color_override("default_color", UITheme.MENU_INK)
	_detail.add_theme_constant_override("line_separation", 4)
	operation.add_child(_detail)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	v.add_child(buttons)
	var edit := _button("BUILD A FLEET / EDIT MISSION")
	edit.theme_type_variation = "MenuBigButton"
	edit.add_theme_font_size_override("font_size", 18)
	edit.tooltip_text = "Build or modify a mission  [Ctrl+E]"
	edit.pressed.connect(func() -> void: editor_requested.emit())
	buttons.add_child(edit)
	var library := _button("REFERENCE")
	library.theme_type_variation = "MenuBigButton"
	library.add_theme_font_size_override("font_size", 18)
	library.tooltip_text = "Reference library of every platform and weapon  [F7]"
	library.pressed.connect(func() -> void: library_requested.emit())
	buttons.add_child(library)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	_play = Button.new()
	_play.focus_mode = Control.FOCUS_ALL
	_play.tooltip_text = "Read the briefing for the selected operation  [Enter]"
	_play.pressed.connect(_on_play)
	buttons.add_child(UITheme.caption_pair("Accept", _play))
	_close = Button.new()
	_close.focus_mode = Control.FOCUS_ALL
	_close.tooltip_text = "Close this desk and return to the operation already loaded  [Esc]"
	_close.pressed.connect(func() -> void: dismissed.emit())
	_close_pair = UITheme.caption_pair("Cancel", _close)
	buttons.add_child(_close_pair)
	var note := _label("Historical equipment, fictional operations. Performance and detection values are simulation estimates.", 11, Color(UITheme.MENU_INK, 0.75))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	resized.connect(_apply_layout)
	_apply_layout()
	refresh()


func _apply_layout() -> void:
	if _margin == null:
		return
	var viewport_size := get_viewport_rect().size
	var compact := viewport_size.x < 1300.0 or viewport_size.y < 850.0
	var side := 24 if compact else maxi(int((viewport_size.x - 1320.0) * 0.5), 40)
	var edge := 16 if compact else 26
	for key in ["left", "right"]:
		_margin.add_theme_constant_override("margin_" + key, side)
	for key in ["top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + key, edge)
	var map_side := 200.0 if compact else 262.0
	_preview.custom_minimum_size = Vector2(map_side, map_side)
	_rail.custom_minimum_size.x = 0.0 if compact else 250.0
	_rail.visible = not compact and _portrait.spec_override != null
	_subtitle.visible = not compact
	_mast_note.visible = not compact
	_options_summary.custom_minimum_size.x = 300.0 if compact else 380.0
	_layout.add_theme_constant_override("separation", 8 if compact else 12)
	_intent.max_lines_visible = 2
	_mission_title.add_theme_font_size_override("font_size", 22 if compact else 26)
	_title.set_font_size(38 if compact else 54)


## `played` says the current operation was actually commanded, not merely loaded at start-up:
## coming back from it, the desk opens on the shelf that holds it. Otherwise the front door
## stays the authored operations.
func refresh(current_path := "", played := false) -> void:
	_all_entries = ScenarioIndex.list_all()
	if current_path != "" and not _initial_refresh:
		for entry: Dictionary in _all_entries:
			if entry["path"] == current_path:
				# A custom mission is always shown on My Missions, played or only saved; a shipped
				# one moves the desk only once it was actually commanded.
				var in_campaign: bool = not entry["custom"] and not CampaignBook.find(str(entry["id"])).is_empty()
				var keep_campaigns: bool = _era == "campaigns" and in_campaign
				if _era in ["operations", "training", "custom", "campaigns"] and (played or entry["custom"]) and not keep_campaigns:
					_era = shelf_for(entry)
				break
	_initial_refresh = false
	_populate(current_path)


# --- Gameplay options --------------------------------------------------------------------

## Shows the options Main is playing under: the preset pressed in (none for CUSTOM), each
## option ticked, and a one-line summary.
func set_options(o: GameOptions) -> void:
	_options = o.duplicate_options()
	if _options_menu == null:
		return
	var preset := _options.preset()
	for key: String in _style_buttons:
		(_style_buttons[key] as Button).set_pressed_no_signal(key == preset)
	var popup := _options_menu.get_popup()
	for i in GameOptions.OPTION_KEYS.size():
		var key: String = GameOptions.OPTION_KEYS[i]
		if key != "":
			popup.set_item_checked(popup.get_item_index(i), _options.option_on(key))
	# The pressed preset button says which preset it is; with neither pressed, the menu says CUSTOM.
	_options_menu.text = "OPTIONS ▾" if preset != GameOptions.CUSTOM else "CUSTOM ▾"
	_options_summary.text = _options.summary()
	_options_summary.tooltip_text = "\n".join(_options.summary_lines())


func _choose_preset(preset: String) -> void:
	SoundFx.play("click")
	options_requested.emit(GameOptions.preset_named(preset, _options.voice, _options.ambient))


func _toggle_option(index: int) -> void:
	SoundFx.play("click")
	options_requested.emit(_options.toggled(str(GameOptions.OPTION_KEYS[index])))


## Opens My Missions on a mission just saved in the editor.
func show_saved(path: String) -> void:
	_era = "custom"
	_populate(path)


## Which of the three front shelves an entry lives on.
static func shelf_for(entry: Dictionary) -> String:
	if entry["custom"]:
		return "custom"
	return "training" if str(entry.get("collection", "operations")) == "exercises" else "operations"


func _set_era(era: String) -> void:
	_era = era
	_populate()


func _populate(current_path := "") -> void:
	_entries.clear()
	_list.clear_rows()
	for key: String in _filters:
		var button: Button = _filters[key]
		button.set_pressed_no_signal(key == _era)
	if _era == "campaigns":
		_entries = _campaign_entries()
	for entry: Dictionary in ([] if _era == "campaigns" else _all_entries):
		if _era == "custom":
			if not entry["custom"]:
				continue
		elif _era in ["operations", "training"]:
			if entry["custom"] or shelf_for(entry) != _era:
				continue
		elif _era == "templates":
			if entry["custom"]:
				continue
		elif _era == "modern":
			if _is_cold_war(entry) or entry["custom"]:
				continue
		elif _era != "all" and (entry["custom"] or _shelf_of(entry) != _era):
			continue
		_entries.append(entry)
	if _era == "operations":
		# The contemporary operations first, as the headlines of the day; the 1990 pack after.
		_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["year"]) != int(b["year"]):
				return int(a["year"]) > int(b["year"])
			return int(a["order"]) < int(b["order"]))
	var log := CommanderLog.load_all()
	var selected := 0
	for i in _entries.size():
		var e: Dictionary = _entries[i]
		var period := "CUSTOM" if e["custom"] else (str(e["year"]) if int(e["year"]) > 0 else "MODERN")
		var mission_name := str(e["name"]).replace(" — ", " / ")
		if not e["custom"] and str(e.get("theatre", "")) != "" and not mission_name.to_upper().contains(str(e["theatre"]).to_upper()):
			mission_name += "  ·  " + str(e["theatre"])
		var record = log.get(str(e["id"]), {})
		if typeof(record) == TYPE_DICTIONARY and not record.is_empty():
			period = "%d%%" % int(record.get("best_percent", 0))
		if e.has("campaign_state"):
			mission_name = "%s  %d/%d   %s" % [e["campaign_short"], int(e["campaign_step"]), int(e["campaign_total"]), mission_name]
			if e["campaign_state"] == CampaignBook.LOCKED:
				period = "LOCKED"
			elif e["campaign_state"] == CampaignBook.OPEN and record is Dictionary and record.is_empty():
				period = "OPEN"
		_list.add_row(mission_name, period, Color.TRANSPARENT, stars(str(e.get("difficulty", ""))))
		_list.set_item_tooltip(i, "%s\n%s  ·  %s\n%s" % [e["name"], e.get("role", "Task force command"), e.get("difficulty", "Open command"), e["description"]])
		if e["path"] == current_path:
			selected = i
	_count.text = "%d OPERATIONS  /  %s" % [_entries.size(), SHELF_NAMES.get(_era, "ALL ERAS + CUSTOM")]
	if _era == "campaigns":
		var parts := PackedStringArray()
		for c: Dictionary in CampaignBook.load_all():
			var done := CampaignBook.progress(c, log)
			parts.append("%s  %d OF %d WON" % [str(c.get("short_name", c.get("name", ""))), int(done["won"]), int(done["total"])])
		_count.text = "   ·   ".join(parts)
	_play.disabled = _entries.is_empty()
	if not _entries.is_empty():
		_list.select(selected)
		_on_selected(selected)
	else:
		_mission_title.text = "CREATE YOUR FIRST MISSION"
		_mission_meta.text = "Choose BUILD A FLEET / EDIT MISSION to begin."
		_intent.text = ""
		_detail.text = "Generate both fleets from a seed, then edit platforms, weapons, air wings, routes, objectives and reinforcement waves. Saved missions appear here. Optional templates are available on the other shelf."
		_preview.set_scenario({})
		_portrait.spec_override = null
		_rail.visible = false
		_ship_caption.text = ""


## The campaign shelf: every campaign's operations in order, each a copy of its desk entry with
## the campaign's name, the step and whether the commander's log has opened it.
func _campaign_entries() -> Array:
	var by_id := {}
	for entry: Dictionary in _all_entries:
		if not entry["custom"]:
			by_id[str(entry["id"])] = entry
	var log := CommanderLog.load_all()
	var out: Array = []
	for c: Dictionary in CampaignBook.load_all():
		for step: Dictionary in CampaignBook.steps(c, log):
			if not by_id.has(step["id"]):
				continue
			var e: Dictionary = by_id[step["id"]].duplicate()
			e["campaign_name"] = str(c.get("name", ""))
			e["campaign_short"] = str(c.get("short_name", c.get("name", "")))
			e["campaign_summary"] = str(c.get("summary", ""))
			e["campaign_step"] = step["step"]
			e["campaign_total"] = step["total"]
			e["campaign_state"] = step["state"]
			e["campaign_gate"] = step["gate_percent"]
			e["campaign_previous"] = _entry_name(by_id, step["previous_id"])
			e["campaign_next"] = _entry_name(by_id, step["next_id"])
			e["campaign_average"] = int(CampaignBook.progress(c, log)["average"])
			out.append(e)
	return out


static func _entry_name(by_id: Dictionary, id: String) -> String:
	return str(by_id[id]["name"]).replace(" — ", " / ") if by_id.has(id) else ""


## The campaign paragraph at the head of a campaign step's orders, and whether it may be played.
static func campaign_note(e: Dictionary) -> String:
	if not e.has("campaign_state"):
		return ""
	var gate := int(e["campaign_gate"])
	var best: Dictionary = CommanderLog.best(str(e["id"]))
	var text := ""
	match str(e["campaign_state"]):
		CampaignBook.LOCKED:
			text = "[b]LOCKED.[/b] Win %s at %d%% or better to open this operation." % [_safe(str(e["campaign_previous"])), gate]
			if CampaignBook.cleared(best, gate):
				text += " Your %d%% win here already counts once the campaign reaches it." % int(best.get("best_percent", 0))
		CampaignBook.WON:
			if str(e["campaign_next"]) != "":
				text = "Cleared at %d%%. %s is open." % [int(best.get("best_percent", 0)), _safe(str(e["campaign_next"]))]
			else:
				text = "Cleared at %d%%. Campaign complete, averaging %d%% across its operations." % [int(best.get("best_percent", 0)), int(e["campaign_average"])]
		_:
			var then := ("to open %s" % _safe(str(e["campaign_next"]))) if str(e["campaign_next"]) != "" else "to complete the campaign"
			text = "Win at %d%% or better %s." % [gate, then]
			if not best.is_empty():
				text = "Best so far %d%%, %s. " % [int(best.get("best_percent", 0)), str(best.get("result", "")).to_lower()] + text
	return "%s\n[color=%s]%s Nothing carries between operations: each is a different force in a different sea.[/color]\n" % [text, UITheme.HEX_INK_DIM, _safe(str(e["campaign_summary"]))]


## Green stars for a mission's difficulty: one for an introduction, three for the hardest.
static func stars(difficulty: String) -> String:
	return STARS.get(difficulty, "★★")


static func _is_cold_war(entry: Dictionary) -> bool:
	return int(entry.get("year", 0)) == 1990


const SHELF_NAMES := {"operations": "2027, THEN 1990", "campaigns": "IN ORDER", "training": "TRAINING & SHORT ENGAGEMENTS", "custom": "YOUR MISSIONS", "templates": "EVERY AUTHORED MISSION", "cold_war": "1990", "atlantic": "NORTH ATLANTIC 2027", "pacific": "WESTERN PACIFIC 2027", "gulf_med": "GULF & MEDITERRANEAN 2027", "modern": "CONTEMPORARY", "exercises": "TRAINING & SHORT ENGAGEMENTS"}


## Which shelf a built-in operation sits on: the 1990 pack, or a modern theatre by chart region.
static func _shelf_of(entry: Dictionary) -> String:
	if entry.get("collection", "operations") == "exercises":
		return "exercises"
	if _is_cold_war(entry):
		return "cold_war"
	match str(entry.get("region", "north_atlantic")):
		"west_pacific":
			return "pacific"
		"arabian_sea", "mediterranean":
			return "gulf_med"
	return "atlantic"


func allow_back(can_go_back: bool) -> void:
	_close.visible = can_go_back
	_close_pair.visible = can_go_back


func focus_default() -> void:
	if visible and _list != null:
		_list.grab_focus()


func _on_selected(i: int) -> void:
	if i < 0 or i >= _entries.size():
		return
	var e: Dictionary = _entries[i]
	var sc := ScenarioLoader.load_file(e["path"])
	_preview.set_scenario(sc)
	_mission_title.text = str(e["name"]).replace(" — ", " / ").to_upper()
	var details := PackedStringArray()
	var date := str(sc.get("start_time_utc", ""))
	if date.length() >= 10:
		details.append(date.substr(0, 10))
	if str(e.get("theatre", "")) != "":
		details.append(str(e["theatre"]))
	details.append(str(e.get("role", "Task force command")))
	details.append(str(e.get("difficulty", "Open command")))
	var duration := int(e.get("duration_minutes", 0))
	if duration > 0:
		details.append("about %d min" % duration)
	var best := CommanderLog.best(str(e["id"]))
	if not best.is_empty():
		details.append("best %d%% %s on %s" % [int(best.get("best_percent", 0)), str(best.get("result", "")).to_lower(), str(best.get("date", "")).substr(0, 10)])
	if e.has("campaign_state"):
		details.insert(0, "%s, operation %d of %d" % [str(e["campaign_name"]), int(e["campaign_step"]), int(e["campaign_total"])])
	_mission_meta.text = "  ·  ".join(details).to_upper()
	var locked := str(e.get("campaign_state", "")) == CampaignBook.LOCKED
	_play.disabled = locked
	_play.tooltip_text = "Win the operation before it to open this one" if locked else "Read the briefing for the selected operation  [Enter]"
	var objective: Dictionary = sc.get("objectives", {})
	_intent.text = sc.get("commander_intent", objective.get("text", "Read the situation and establish your command priorities."))
	var lines := PackedStringArray()
	if e.has("campaign_state"):
		lines.append(_section("CAMPAIGN"))
		lines.append(campaign_note(e))
	var first_orders: Array = sc.get("first_orders", [])
	if not first_orders.is_empty():
		lines.append(_section("YOUR FIRST ORDERS"))
		for n in first_orders.size():
			lines.append("[color=%s][b]%02d[/b][/color]   %s" % [UITheme.HEX_INK_BLUE, n + 1, _safe(str(first_orders[n]))])
		lines.append("")
	lines.append(_section("FORCE UNDER YOUR COMMAND"))
	lines.append(_safe(str(e["forces"])) + "\n")
	var own_surface := 0
	var air := 0
	var subs := 0
	var representative: PlatformSpec = null
	var ship_name := ""
	var player: String = sc.get("player_faction", "BLUE")
	for ud: Dictionary in sc.get("units", []):
		if ud.get("faction", "") != player:
			continue
		var spec := DataDB.platform(ud.get("platform", ""))
		if spec == null:
			continue
		if spec.domain == "air":
			air += 1
		elif spec.domain == "subsurface":
			subs += 1
		elif spec.domain == "surface":
			own_surface += 1
			if representative == null:
				representative = spec
				ship_name = ud.get("callsign", spec.short_name)
		if spec.aircraft_capacity > 0:
			var capacity := spec.aircraft_capacity
			for placed: Dictionary in sc.get("units", []):
				if placed.get("home", "") == ud.get("callsign", spec.short_name):
					capacity -= 1
			var wing: Array = ud.get("air_wing", ScenarioLoader._default_wing(spec))
			for entry: Dictionary in wing:
				var aircraft := DataDB.platform(str(entry.get("platform", "")))
				if aircraft != null and spec.can_operate(aircraft):
					var added := mini(maxi(int(entry.get("count", 1)), 0), maxi(capacity, 0))
					air += added
					capacity -= added
	_portrait.spec_override = representative
	_ship_caption.text = "%s\n%s" % [ship_name, representative.short_name] if representative != null else ""
	lines.append("[color=%s]%d surface  ·  %d submarine%s  ·  %d aircraft[/color]\n" % [UITheme.HEX_INK_FAINT, own_surface, subs, "" if subs == 1 else "s", air])
	lines.append(_section("SITUATION"))
	lines.append(_safe(str(e["description"])) + "\n")
	if not sc.get("operation_plan", []).is_empty():
		lines.append(_section("OPERATION SEQUENCE"))
		for phase: Dictionary in sc["operation_plan"]:
			lines.append("[b]%s[/b]  %s\n" % [_safe(str(phase["title"])), _safe(str(phase["task"]))])
	if sc.has("learning"):
		lines.append(_section("COMMAND CHALLENGE"))
		lines.append(_safe(str(sc["learning"])) + "\n")
	if sc.has("historical_note"):
		lines.append(_section("HISTORICAL CONTEXT"))
		lines.append("[color=%s]%s[/color]" % [UITheme.HEX_INK_DIM, _safe(str(sc["historical_note"]))])
	elif sc.has("setting_note"):
		lines.append(_section("SETTING"))
		lines.append("[color=%s]%s[/color]" % [UITheme.HEX_INK_DIM, _safe(str(sc["setting_note"]))])
	elif sc.has("force_note"):
		lines.append("[color=%s]%s[/color]" % [UITheme.HEX_INK_DIM, _safe(str(sc["force_note"]))])
	_detail.text = "\n".join(lines)
	_detail.scroll_to_line(0)
	_apply_layout()


func _on_play() -> void:
	var selected := _list.get_selected_items()
	if selected.is_empty() or selected[0] >= _entries.size():
		return
	if str(_entries[selected[0]].get("campaign_state", "")) == CampaignBook.LOCKED:
		return
	SoundFx.play("click")
	scenario_chosen.emit(_entries[selected[0]]["path"])


static func _safe(value: String) -> String:
	return value.replace("[", "[lb]")


static func _section(value: String) -> String:
	return UITheme.section_bb(value, true)


static func _label(value: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result


static func _button(value: String, primary := false) -> Button:
	var result := Button.new()
	result.text = value
	result.focus_mode = Control.FOCUS_ALL
	result.custom_minimum_size.y = 40
	if primary:
		result.theme_type_variation = "PrimaryButton"
	return result


static func _card() -> PanelContainer:
	var result := PanelContainer.new()
	result.theme_type_variation = "CardPanel"
	return result
