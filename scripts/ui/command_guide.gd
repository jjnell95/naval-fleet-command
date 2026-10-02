class_name CommandGuide
extends PanelContainer
## Optional Northern Passage practice. Reads own units and reported contacts, records real
## accepted orders, and opens ordinary controls. It never advances the clock or issues an order.
## Progress belongs to saved presentation, not the deterministic simulation.

signal action_requested(id: String)
signal dismissed()

const STEPS := ["launch", "patrol", "inspect", "investigate", "return"]
const TITLES := ["Put reconnaissance airborne", "Give the aircraft a station", "Read a contact report", "Investigate an unknown", "Resume the search"]
var available := false
var enabled := false
var done: Array[String] = []
var skipped: Array[String] = []
var aircraft_id := -1
var target_id := ""
var classified := false
var recovery_ordered := false
var faction := "BLUE"
var _title: Label
var _body: Label
var _action: Button
var _skip: Button
var _close: Button
var _action_id := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.x = 316
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101b35")
	style.border_color = Color("52748c")
	style.set_border_width_all(1)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 13)
	_title.add_theme_color_override("font_color", Color("91d3ea"))
	box.add_child(_title)
	_body = Label.new()
	_body.custom_minimum_size.x = 296
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", 13)
	_body.add_theme_color_override("font_color", Color("e4eaf0"))
	box.add_child(_body)
	var row := HBoxContainer.new()
	box.add_child(row)
	_action = Button.new()
	_action.pressed.connect(func() -> void: action_requested.emit(_action_id))
	row.add_child(_action)
	_skip = Button.new()
	_skip.text = "Skip step"
	_skip.tooltip_text = "Continue the guide without marking this task as practiced."
	_skip.pressed.connect(skip_step)
	row.add_child(_skip)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(space)
	_close = Button.new()
	_close.text = "Close"
	_close.tooltip_text = "Hide this guide. Resume it from the briefing (F1)."
	_close.pressed.connect(func() -> void:
		enabled = false
		hide()
		dismissed.emit())
	row.add_child(_close)
	hide()


func reset(scenario_id: String, player_faction: String) -> void:
	available = scenario_id == "northern_passage"
	enabled = available
	faction = player_faction
	done.clear()
	skipped.clear()
	aircraft_id = -1
	target_id = ""
	classified = false
	recovery_ordered = false
	hide()


func step() -> int:
	for i in STEPS.size():
		if not done.has(STEPS[i]) and not skipped.has(STEPS[i]):
			return i
	return STEPS.size()


func skip_step() -> void:
	var index := step()
	if index < STEPS.size():
		skipped.append(STEPS[index])


func _complete(key: String) -> void:
	if not done.has(key):
		done.append(key)


func record_order(u: Unit, order: Order) -> void:
	if not enabled or not available or u.faction != faction or not u.is_aircraft() or not order.execution_accepted or order.origin != "player":
		return
	if order.type == Order.Type.PATROL:
		aircraft_id = u.id
		_complete("patrol")
	elif order.type == Order.Type.INVESTIGATE and order.track != null:
		aircraft_id = u.id
		target_id = order.track.id
		classified = false
		_complete("investigate")
	elif order.type == Order.Type.RETURN_TO_BASE:
		aircraft_id = u.id
		recovery_ordered = true


func record_inspection(t: Track) -> void:
	if enabled and available and t != null and t.status != Track.Status.LOST:
		_complete("inspect")


func record_classification(u: Unit, t: Track, reason: String) -> void:
	if available and u.id == aircraft_id and t != null and t.id == target_id and reason == "Contact classified":
		classified = true


func aircraft(um: UnitManager) -> Unit:
	var fallback: Unit
	for u: Unit in um.get_faction_units(faction):
		if not u.alive or not u.is_aircraft():
			continue
		if u.id == aircraft_id:
			return u
		if fallback == null or u.airborne():
			fallback = u
	return fallback


func observe(um: UnitManager) -> void:
	if not enabled or not available:
		return
	var a := aircraft(um)
	if a == null:
		return
	if a.airborne():
		_complete("launch")
	if a.id == aircraft_id and classified and a.on_station():
		_complete("return")
	elif a.id == aircraft_id and recovery_ordered and a.flight_state == Unit.FlightState.TURNAROUND:
		_complete("return")


func refresh(um: UnitManager, options: GameOptions, inbound: bool, contact: Track = null, torpedo := false) -> void:
	observe(um)
	var index := step()
	var a := aircraft(um)
	var text := ""
	var action := ""
	_action_id = ""
	if inbound:
		_title.text = "COMMAND GUIDE · DEFEND THE CONVOY"
		text = "Inbound reported. Space pauses the watch. " + ("Manual defence: select an escort and press X to engage inbound missiles; Defence shows the threat picture." if options.manual_missile_defence() else "Automatic missile defence is on. Open Defence to review threats and remaining rounds.")
		if torpedo:
			text = "Torpedo reported. Space pauses the watch. Open Defence to review the threat and countermeasures. Missile intercept orders do not stop a torpedo."
		action = "Defence"
		_action_id = "open_defence"
	elif index == STEPS.size():
		_title.text = "COMMAND GUIDE · PRACTICE FINISHED"
		var recovery := "The aircraft is back on deck." if recovery_ordered and done.has("return") else "Recover the Seahawk before fuel runs low."
		text = "%d of %d tasks practiced. Keep the escorts with Northern Light. %s Attack only after identification and your decision to engage." % [done.size(), STEPS.size(), recovery]
		action = "Mission objectives"
		_action_id = "briefing"
	else:
		_title.text = "COMMAND GUIDE · %d / %d" % [index + 1, STEPS.size()]
		text = TITLES[index] + ". "
		match index:
			0:
				text += "Air (F3) → Truxtun → Seahawk. Set 1 aircraft, then Launch. Resume time for the deck cycle. Space pauses; you can issue orders while paused."
				action = "Air operations"
				_action_id = "air_operations"
			1:
				text += "Select the airborne Seahawk, then Orders → Assign patrol. Click two corners near the convoy. A station gives the crew somewhere to return."
				action = "Select aircraft"
				_action_id = "guide_aircraft"
			2:
				text += "Click a chart contact. Read its identity, source and report age below. An UNKNOWN is not a hostile; a sensor estimate is not a visual sighting."
				action = "Next contact"
				_action_id = "next_contact"
			3:
				text += "With Seahawk selected, right-click a positioned UNKNOWN to investigate. Keep the escorts at their convoy stations. If no suitable unknown remains, keep station and skip this step."
				if contact != null and a != null:
					var why := UnitManager.investigation_rejection(a, contact)
					if why != "":
						text = "%s. %s Keep the aircraft near the convoy; do not chase an unresolved report. You can skip this investigation and practice recovery." % [why, "A bearing gives a direction, not a firing position." if contact.is_bearing_only() else "Investigation needs an available aircraft and an unclassified contact."]
				action = "Select aircraft"
				_action_id = "guide_aircraft"
			4:
				text += "Let the investigation finish. After classification the crew returns to its patrol, if auto-return is on. Otherwise select Seahawk and use Orders → Return to station (S)."
				if recovery_ordered:
					text = "Recovery ordered. Let the crew return and land. The guide finishes when the aircraft is safely back on deck."
				elif target_id == "":
					text = "Recover reconnaissance. With Seahawk selected, open Air (F3), choose Return & Land, then close the dialog and resume time. The crew returns to its deck; fuel and recovery time still matter."
				action = "Select aircraft"
				_action_id = "guide_aircraft"
		if a == null:
			text = "No aircraft remains available. Continue protecting Northern Light with the escorts. You can skip this lesson or close the guide."
			_action_id = "briefing"
			action = "Mission objectives"
	_body.text = text
	_action.text = action
	_action.visible = action != ""
	_skip.visible = index < STEPS.size() and not inbound
	# Container minimum heights shrink as the changing instructions get shorter.
	reset_size()


func to_dict() -> Dictionary:
	return {"enabled": enabled, "done": done.duplicate(), "skipped": skipped.duplicate(), "aircraft_id": aircraft_id, "target_id": target_id, "classified": classified, "recovery_ordered": recovery_ordered}


func restore(d: Dictionary) -> void:
	# Older saves continue without introducing a guide mid-engagement.
	enabled = available and d.get("enabled", false) == true
	done.clear()
	skipped.clear()
	for key in d.get("done", []):
		if key in STEPS and not done.has(key): done.append(key)
	for key in d.get("skipped", []):
		if key in STEPS and not skipped.has(key): skipped.append(key)
	aircraft_id = int(d.get("aircraft_id", -1))
	target_id = str(d.get("target_id", ""))
	classified = d.get("classified", false) == true
	recovery_ordered = d.get("recovery_ordered", false) == true
