class_name RadioLine
extends RefCounted
## The chart's radio line: the newest few messages, bottom-centre, each held a few seconds and then
## faded. Pure timing and text; TacticalMap draws it and rings each speaker's symbol while its
## message is up (the classic "white circle means transmitting"). Times are wall-clock seconds, so
## a message reads the same at any time compression.

const HOLD_S := 6.0
const FADE_S := 1.0
const MAX_LINES := 3

## Oldest first: {text, severity, speaker, t0}.
var entries: Array[Dictionary] = []


## Queues a line. With a speaker (a Unit, or a Track as the plot holds it) the line reads
## "<callsign>: <text>"; without one it is a bare system line.
func post(text: String, severity: String, speaker: Variant, now: float) -> void:
	entries.append({"text": format(text, speaker), "severity": severity, "speaker": speaker, "t0": now})
	while entries.size() > MAX_LINES:
		entries.remove_at(0)


## Opacity of a line of this age: full for HOLD_S, then a linear fade over FADE_S.
static func alpha_at(age: float) -> float:
	if age < 0.0:
		return 1.0
	return clampf(1.0 - (age - HOLD_S) / FADE_S, 0.0, 1.0)


## Drops lines that have faded out; returns what is still showing, oldest first.
func visible(now: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(entries.size() - 1, -1, -1):
		if alpha_at(now - float(entries[i]["t0"])) <= 0.0:
			entries.remove_at(i)
	for e in entries:
		out.append(e)
	return out


## Speakers of the lines still showing, for the transmitting ring.
func speakers(now: float) -> Array:
	var out := []
	for e in visible(now):
		if e["speaker"] != null and not out.has(e["speaker"]):
			out.append(e["speaker"])
	return out


func clear() -> void:
	entries.clear()


static func format(text: String, speaker: Variant) -> String:
	var who := speaker_name(speaker)
	if who == "" or text.begins_with(who):
		return text
	return "%s: %s" % [who, text]


## The name a speaker goes by on the radio line: an own unit's callsign, a contact's plot label
## (never more than the plot already holds).
static func speaker_name(speaker: Variant) -> String:
	if speaker is Unit:
		return (speaker as Unit).callsign
	if speaker is Track:
		return (speaker as Track).label()
	return ""
