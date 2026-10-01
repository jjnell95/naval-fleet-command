class_name CampaignBook
extends RefCounted
## The campaigns: shipped operations taken in order, each opened by winning the one before it
## well enough. The commander's log is the only state, so a campaign needs no save file and an
## operation won from the Operations shelf counts here too. Nothing carries between operations:
## each is a different force in a different sea, so the gate is the whole linkage.

const PATH := "res://data/campaigns.json"

## A step's state: WON cleared the gate; OPEN may be played (perhaps already, below the gate);
## LOCKED waits on the step before it.
const WON := "won"
const OPEN := "open"
const LOCKED := "locked"


## Every campaign as written in data/campaigns.json, in shelf order. A missing or damaged file
## reads as no campaigns rather than an error on the desk.
static func load_all() -> Array:
	if not FileAccess.file_exists(PATH):
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("campaigns")) != TYPE_ARRAY:
		push_warning("CampaignBook: %s is not a campaign list" % PATH)
		return []
	var out: Array = []
	for c in parsed["campaigns"]:
		if typeof(c) == TYPE_DICTIONARY and typeof(c.get("operations")) == TYPE_ARRAY and not c["operations"].is_empty():
			out.append(c)
	return out


## True when a commander's-log entry clears a gate: a victory at the gate percentage or better.
## A victory graded below it (a neutral sunk on the way) must be flown again.
static func cleared(record: Dictionary, gate_percent: int) -> bool:
	return str(record.get("result", "")) == "VICTORY" and int(record.get("best_percent", -1)) >= gate_percent


## The campaign's operations with their state, read from the log:
## [{id, step, total, state, record, gate_percent, previous_id, next_id, frontier_id}]. The
## frontier is the first operation not yet won: the one the campaign is waiting on.
static func steps(campaign: Dictionary, log: Dictionary) -> Array:
	var ids: Array = campaign.get("operations", [])
	var gate := int(campaign.get("gate_percent", 60))
	var out: Array = []
	var open := true
	for i in ids.size():
		var id := str(ids[i])
		var record = log.get(id, {})
		if typeof(record) != TYPE_DICTIONARY:
			record = {}
		var state := LOCKED
		if open:
			state = WON if cleared(record, gate) else OPEN
		out.append({"id": id, "step": i + 1, "total": ids.size(), "state": state, "record": record, "gate_percent": gate,
			"previous_id": str(ids[i - 1]) if i > 0 else "", "next_id": str(ids[i + 1]) if i + 1 < ids.size() else ""})
		open = state == WON
	var frontier := ""
	for s: Dictionary in out:
		if s["state"] == OPEN:
			frontier = s["id"]
	for s: Dictionary in out:
		s["frontier_id"] = frontier
	return out


## How far a campaign has come: {won, total, average}, the average taken over every step so an
## unplayed operation counts as nothing.
static func progress(campaign: Dictionary, log: Dictionary) -> Dictionary:
	var all := steps(campaign, log)
	var won := 0
	var sum := 0
	for s: Dictionary in all:
		if s["state"] == WON:
			won += 1
		sum += maxi(int(s["record"].get("best_percent", 0)), 0)
	return {"won": won, "total": all.size(), "average": roundi(float(sum) / maxf(all.size(), 1))}


## The campaign an operation belongs to, and its step there, or {} when it is in none.
static func find(scenario_id: String, log: Dictionary = {}) -> Dictionary:
	for c: Dictionary in load_all():
		for s: Dictionary in steps(c, log):
			if s["id"] == scenario_id:
				return {"campaign": c, "step": s}
	return {}
