class_name RadioNet
extends RefCounted
## The command screen's message traffic. Everything the deck used to flash in its top bar now
## comes over the radio, the way it did in the late-1990s fleet-command games: one line at the
## bottom of the chart ("USS Bulkeley (DDG 84): Missile away"), a white ring round whoever is
## talking, a lamp on the data display for anything that needs attention, and the full history on
## the comms board.
##
## Keeps the old TopBar surface (flash, set_alert, set_objective_text, set_scenario_name, history,
## logged) so the wiring in Main reads the same.

signal logged(text: String, severity: String)

const MAX_HISTORY := 60

var map: TacticalMap
var display: DataDisplay
var boards: StatusBoards
## Newest first, each "<time>  <text>".
var history: Array[String] = []
var scenario_name := ""
var objective_text := ""


## Puts a message on the net. `speaker` is the unit or track talking, if any: the line reads
## "<callsign>: <text>" and the speaker's symbol is ringed while the line shows.
func flash(msg: String, severity := "info", speaker: RefCounted = null) -> void:
	var line := format_line(msg, speaker)
	history.push_front("%s  %s" % [SimClock.datetime_string(), line])
	if history.size() > MAX_HISTORY:
		history.resize(MAX_HISTORY)
	if map != null and map.has_method("post_message"):
		map.post_message(line, severity, speaker)
	if boards != null:
		boards.add_message(line, severity)
	if display != null and severity in ["alert", "warn"] and (boards == null or not boards.showing_comms()):
		display.unread_alerts += 1
	logged.emit(line, severity)


static func format_line(msg: String, speaker: RefCounted) -> String:
	var who := speaker_name(speaker)
	if who == "" or msg.begins_with(who):
		return msg
	return "%s: %s" % [who, msg]


static func speaker_name(speaker: RefCounted) -> String:
	if speaker is Unit:
		return (speaker as Unit).callsign
	if speaker is Track:
		return "Track %s" % DataDisplay.track_number_for_track(speaker as Track)
	return ""


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
	objective_text = ""
	if display != null:
		display.unread_alerts = 0
		display.threat_text = ""
	if boards != null:
		boards.clear_messages()
