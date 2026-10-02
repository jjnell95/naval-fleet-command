class_name AirMission
extends RefCounted
## An air tasking: what a deck has been told to keep in the air, where, and with what. The mission
## owns no aircraft and no ammunition. It asks the deck for real airframes of one type as the deck
## can send them, gives each one a station or a target through ordinary crew orders, and follows
## them until they land. AirMissionManager steps it; this is the record the boards read.

enum Kind { CAP, RECON, ASW, STRIKE }

const KIND_NAMES := ["CAP", "RECON", "ASW", "STRIKE"]
const KIND_LABELS := ["Combat air patrol", "Reconnaissance / identification", "ASW search", "Strike"]
const STATION_LABELS := ["CAP STATION", "RECON AREA", "ASW SEARCH", "STRIKE"]

## What each airframe on the mission is doing, in the order a sortie goes through them.
const QUEUED := "QUEUED"
const LAUNCHING := "LAUNCHING"
const TRANSITING := "TRANSITING"
const ON_STATION := "ON STATION"
const INVESTIGATING := "INVESTIGATING"
const ENGAGING := "ENGAGING"
const REFUELLING := "REFUELLING"
const HOLDING := "HOLDING"
const RETURNING := "RETURNING"
const RECOVERING := "RECOVERING"

var id := -1
var kind: Kind = Kind.CAP
var faction := ""
var base: Unit
var base_callsign := ""
var platform_id := ""
## Airframes the commander wants on the mission at once.
var requested := 1
var station := Vector2.INF
var radius_nm := 15.0
var target: Track
var target_id := ""
## Launch ready reserve airframes to relieve any that leave station for fuel, ammunition or loss.
var relief := false
## Back to station by themselves after an identification or interception.
var auto_return := true
## Launches still owed: the first wave, then any relief. Never more than airframes that exist.
var pending_launches := 0
var aircraft: Array[Unit] = []
## Airframe -> what the mission last told it and when, for the board and the generation guard.
var tasks: Dictionary = {}
var launched_total := 0
var completed_sorties := 0
var active := true
var ended_reason := ""
## The last thing worth telling the commander about this mission: a refusal, a partial launch,
## a queued deck, a target lost.
var note := ""
var created_at_s := 0.0


func kind_name() -> String:
	return KIND_NAMES[kind]


func label() -> String:
	return KIND_LABELS[kind]


func station_label() -> String:
	return STATION_LABELS[kind]


static func kind_from_name(name: String) -> int:
	return KIND_NAMES.find(name.to_upper())


## The airframes on the mission and what each is doing, plus a line for launches still queued.
func board_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in aircraft:
		out.append({"aircraft": a, "state": state_of(a)})
	for i in pending_launches:
		out.append({"aircraft": null, "state": QUEUED})
	return out


func state_of(a: Unit) -> String:
	return str(tasks.get(a, {}).get("state", QUEUED))


func count_in(state: String) -> int:
	var n := 0
	for a in aircraft:
		if state_of(a) == state:
			n += 1
	if state == QUEUED:
		n += pending_launches
	return n


## One line for the board: "CAP · 2 on station · 1 queued".
func summary() -> String:
	if not active:
		return "%s · %s" % [kind_name(), ended_reason.to_lower()]
	var parts := PackedStringArray()
	for state in [ON_STATION, TRANSITING, INVESTIGATING, ENGAGING, LAUNCHING, REFUELLING, HOLDING, RETURNING, RECOVERING, QUEUED]:
		var n := count_in(state)
		if n > 0:
			parts.append("%d %s" % [n, state.to_lower()])
	return "%s · %s" % [kind_name(), ", ".join(parts) if not parts.is_empty() else "no aircraft assigned"]
