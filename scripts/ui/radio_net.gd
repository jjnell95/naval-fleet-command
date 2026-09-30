class_name RadioNet
extends RefCounted
## The command screen's message traffic. Everything the deck used to flash in its top bar now
## comes over the radio, the way it did in the late-1990s fleet-command games: one line at the
## bottom of the chart ("USS Bulkeley (DDG 84): Missile away"), a white ring round whoever is
## talking, a lamp on the data display for anything that needs attention, and the full history on
## the comms board.
##
## Keeps the surface the old top bar had (flash, set_alert, set_objective_text, set_scenario_name, history,
## logged) so the wiring in Main reads the same.

signal logged(text: String, severity: String)

const MAX_HISTORY := 60
const MAX_JOURNAL := 512

var map: TacticalMap
var display: DataDisplay
var boards: StatusBoards
## Newest first, each "<time>  <text>".
var history: Array[String] = []
## Chronological, player-observed traffic for the after-action report, separate from the short
## comms-board history. Never populate this from debug output or hidden simulation events.
var journal: Array[String] = []
var journal_omitted := 0
var scenario_name := ""
var objective_text := ""


## Puts a message on the net. `speaker` is the unit or track talking, if any: the line reads
## "<callsign>: <text>" and the speaker's symbol is ringed while the line shows.
func flash(msg: String, severity := "info", speaker: RefCounted = null) -> void:
	var line := format_line(msg, speaker)
	var stamped := "%s  %s" % [SimClock.datetime_string(), line]
	history.push_front(stamped)
	journal.append(stamped)
	if journal.size() > MAX_JOURNAL:
		journal.pop_front()
		journal_omitted += 1
	if history.size() > MAX_HISTORY:
		history.resize(MAX_HISTORY)
	if map != null:
		map.post_message(line, severity, speaker)
	if boards != null:
		boards.add_message(line, severity)
	if display != null and severity in ["alert", "warn"] and (boards == null or not boards.showing_comms()):
		display.unread_alerts += 1
	logged.emit(line, severity)


## "<callsign>: <text>", formatted exactly as the chart's radio line formats it.
static func format_line(msg: String, speaker: RefCounted) -> String:
	return RadioLine.format(msg, speaker)


## The inbound-threat banner; empty clears it.
func set_alert(text: String) -> void:
	if display != null:
		display.threat_text = text


func set_objective_text(text: String) -> void:
	objective_text = text


func set_scenario_name(name: String) -> void:
	scenario_name = name


func clear() -> void:
	history.clear()
	journal.clear()
	journal_omitted = 0
	objective_text = ""
	if display != null:
		display.unread_alerts = 0
		display.threat_text = ""
	if boards != null:
		boards.clear_messages()
