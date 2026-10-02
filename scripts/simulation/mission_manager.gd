class_name MissionManager
extends Node
## Evaluates scenario objectives. Victory when every objective in the scenario's `victory` list
## is complete (or any for an explicit victory_mode="any"); defeat when any loss is true.
## Both lists are data,
## so a new scenario needs no code. An operation's events can change them while it is fought
## (apply_update): a task added, moved, completed or withdrawn, always with an order that says so.

signal mission_ended(result: String, summary: String)
signal objective_completed(objective: MissionObjective, is_loss: bool)
## The tasking changed mid-operation. The order itself is the event's radio message; this is for
## the screens that list the objectives, so they read them again.
signal objectives_changed()

enum Result { RUNNING, VICTORY, DEFEAT }

## Mission effectiveness, 0 to 100, the graded result the late-1990s fleet-command games put
## on their debrief and campaign gates. Task accomplishment is most of it, credited only when
## the mission is won, so before any civilian penalty a victory grades 60 to 100 and a defeat
## 0 to 40; keeping the force and hurting the enemy are the rest; harming neutrals costs, pro
## rata for damage, and can pull a victory lower. All of it is GAMEPLAY tuning.
const TASK_WEIGHT := 60.0
const FORCE_WEIGHT := 20.0
const ATTRITION_WEIGHT := 20.0
const CIVILIAN_PENALTY := 25.0  # per neutral vessel sunk by the player's weapons, pro rata for damage
## Bonus tasks are credited on top, up to this in all, unless the mission was lost. GAMEPLAY: big
## enough to be worth a risk, small enough that skipping them still leaves a full-marks victory.
const BONUS_WEIGHT := 10.0
## What a platform is worth to the balance sheet, by catalogue category; a scenario may give a
## unit its own "points". The figures are the classic order of magnitude: a carrier a thousand,
## an escort a few hundred, an aircraft a few dozen.
const CATEGORY_POINTS := {
	"carrier": 1000, "aircraft carrier": 1000, "amphibious assault ship": 700,
	"cruiser": 450, "destroyer": 400, "frigate": 250, "corvette": 150, "fast attack craft": 80,
	"replenishment ship": 300, "auxiliary": 200, "merchant": 300, "tanker": 300, "fishing vessel": 60,
	"nuclear attack submarine": 450, "diesel-electric attack submarine": 300, "diesel-electric submarine": 300, "midget submarine": 80,
	"coastal missile battery": 200, "ballistic missile battery": 300, "surface-to-air missile site": 200, "shore base": 400, "drone launch site": 120,
	"fighter": 60, "strike fighter": 60, "STOVL fighter": 60, "strike aircraft": 60, "maritime strike bomber": 90,
	"airborne early warning": 120, "airborne early warning helicopter": 80, "maritime patrol aircraft": 90, "maritime patrol": 90, "ASW aircraft": 80,
	"electronic attack": 90, "unmanned aerial refuelling": 60, "unmanned maritime patrol": 50, "unmanned aircraft": 40,
	"ASW helicopter": 50, "surface warfare helicopter": 50, "helicopter": 40, "shipboard rotary-wing drone": 25, "small shipboard drone": 15,
	"armed unmanned aerial vehicle": 30, "small unmanned aerial vehicle": 10,
}
const DOMAIN_POINTS := {"surface": 250, "subsurface": 300, "air": 50, "land": 200}

var unit_manager: UnitManager
## Asked only by objectives about what a side's own plot holds (track_held).
var track_manager: TrackManager
var player_faction := "BLUE"
var briefing := ""
var situation := ""
var victory_objectives: Array[MissionObjective] = []
var loss_objectives: Array[MissionObjective] = []
var result: Result = Result.RUNNING
var victory_mode := "all"
var neutral_factions := PackedStringArray()
## Tasking updates received during this engagement, oldest first, as {"time_s", "text"}: the
## briefing lists them under the original orders.
var tasking_updates: Array = []


func configure(scenario: Dictionary) -> void:
	result = Result.RUNNING
	tasking_updates.clear()
	victory_mode = str(scenario.get("victory_mode", "all"))
	neutral_factions = PackedStringArray()
	for f in scenario.get("neutral_factions", []):
		neutral_factions.append(str(f))
	victory_objectives.clear()
	loss_objectives.clear()
	var obj: Dictionary = scenario.get("objectives", {})
	briefing = obj.get("text", "")
	situation = scenario.get("description", "")
	for d in obj.get("victory", []):
		victory_objectives.append(_scoped(MissionObjective.from_dict(d)))
	for d in obj.get("loss", []):
		loss_objectives.append(_scoped(MissionObjective.from_dict(d)))
	if victory_objectives.is_empty():
		push_warning("MissionManager: scenario '%s' defines no victory condition" % scenario.get("id", "?"))


## An area objective that names neither units nor a faction means the player's own force.
## Without this, one written by the scenario editor would scope to nobody and never complete.
func _scoped(o: MissionObjective) -> MissionObjective:
	if o.kind in [MissionObjective.Kind.REACH_AREA, MissionObjective.Kind.HOLD_AREA] and o.faction == "" and o.callsigns.is_empty():
		o.faction = player_faction
	return o


func tick(now: float) -> void:
	if result != Result.RUNNING or unit_manager == null:
		return
	for o in loss_objectives:
		if not o.complete and o.evaluate(unit_manager, now, track_manager):
			objective_completed.emit(o, true)
			_finish(Result.DEFEAT, o.text)
			return
	var done := 0
	var terminal_count := 0
	for o in victory_objectives:
		var counts := not o.phase_only and not o.optional
		if counts:
			terminal_count += 1
		o.unlocked = prerequisites_complete(o.after)
		var was := o.complete
		if o.evaluate(unit_manager, now, track_manager):
			if counts:
				done += 1
			if not was:
				objective_completed.emit(o, false)
	if done > 0 and (victory_mode == "any" or done == terminal_count):
		_finish(Result.VICTORY, briefing)


func prerequisites_complete(ids: PackedStringArray) -> bool:
	for id in ids:
		var found := false
		for o in victory_objectives:
			if o.id == id and o.complete:
				found = true
				break
		if not found:
			return false
	return true


## The objective with this id, victory or loss, or null.
func objective(id: String) -> MissionObjective:
	for o in victory_objectives + loss_objectives:
		if o.id == id:
			return o
	return null


## Changes the tasking from an operation event: `add` and `add_loss` new objectives, `complete`
## victory tasks, `remove` any, `update` the text, area, timing, count or bonus status of one by
## id, and replace the `briefing`. `note` is the order that announced it, kept for the briefing.
## A saved engagement replays the updates it had received without announcing them again.
func apply_update(update: Dictionary, now: float, note := "", announce := true) -> void:
	for d in update.get("add", []):
		victory_objectives.append(_scoped(MissionObjective.from_dict(d)))
	for d in update.get("add_loss", []):
		loss_objectives.append(_scoped(MissionObjective.from_dict(d)))
	for id in update.get("remove", []):
		var gone := objective(str(id))
		if gone != null:
			victory_objectives.erase(gone)
			loss_objectives.erase(gone)
	var changes: Dictionary = update.get("update", {})
	for id: String in changes:
		var o := objective(id)
		if o != null:
			_revise(o, changes[id])
	for id in update.get("complete", []):
		var o := objective(str(id))
		if o != null and victory_objectives.has(o) and not o.complete:
			o.complete = true
			o.unlocked = true
			if announce:
				objective_completed.emit(o, false)
	if update.has("briefing"):
		briefing = str(update["briefing"])
	if note != "":
		tasking_updates.append({"time_s": now, "text": note})
	if announce:
		objectives_changed.emit()


## A task moved or reworded. A hold whose area or length changes starts its clock again, because
## time spent in the old box was not time spent in the new one.
static func _revise(o: MissionObjective, d: Dictionary) -> void:
	if d.has("text"):
		o.text = str(d["text"])
	if d.has("center_nm"):
		var c: Array = d["center_nm"]
		o.center = Vector2(float(c[0]), float(c[1]))
	if d.has("radius_nm"):
		o.radius_nm = float(d["radius_nm"])
	if d.has("seconds"):
		o.seconds = float(d["seconds"])
	if d.has("count"):
		o.count = int(d["count"])
	if d.has("optional"):
		o.optional = bool(d["optional"])
	if d.has("callsigns"):
		o.callsigns = PackedStringArray()
		for c in d["callsigns"]:
			o.callsigns.append(str(c))
	if d.has("center_nm") or d.has("radius_nm") or d.has("seconds"):
		o.held_since = -1.0
		o.held_seconds = 0.0


func _finish(r: Result, summary: String) -> void:
	result = r
	mission_ended.emit("VICTORY" if r == Result.VICTORY else "DEFEAT", summary)


# --- Mission effectiveness ------------------------------------------------------------------

static func platform_points(spec: PlatformSpec, authored := 0) -> int:
	if authored > 0:
		return authored
	if spec == null:
		return 0
	if CATEGORY_POINTS.has(spec.category):
		return int(CATEGORY_POINTS[spec.category])
	return int(DOMAIN_POINTS.get(spec.domain, 100))


## The balance sheet as it stands: task share, own force kept, enemy points taken, neutrals
## harmed, and the percentage they make. The manager is the referee and reads the units at
## truth; the screen sees only what this returns, after the mission ends.
func assessment() -> Dictionary:
	var out := {"task_done": 0, "task_total": 0, "task": 0.0, "force": 0.0, "attrition": 0.0, "civilian": 0.0,
		"friendly_points": 0, "friendly_lost": 0.0, "hostile_points": 0, "hostile_earned": 0.0, "neutral_hit": 0,
		"bonus_done": 0, "bonus_total": 0, "bonus": 0.0, "percent": 0}
	for o in victory_objectives:
		if o.phase_only:
			continue
		if o.optional:
			out["bonus_total"] += 1
			if o.complete:
				out["bonus_done"] += 1
			continue
		out["task_total"] += 1
		if o.complete:
			out["task_done"] += 1
	if result == Result.DEFEAT:
		out["task"] = 0.0  # the task failed, whatever share of it was done
	elif result == Result.VICTORY and (victory_mode == "any" or out["task_total"] == 0):
		out["task"] = TASK_WEIGHT  # one way of winning was taken, which is the whole task
	elif out["task_total"] > 0:
		out["task"] = TASK_WEIGHT * float(out["task_done"]) / float(out["task_total"])
	if unit_manager != null:
		for u in unit_manager.units:
			var pts := platform_points(u.spec, u.points)
			if pts <= 0:
				continue
			var harm := 1.0 - Damage.health_fraction(u) if u.alive or u.departed else 1.0
			# An airframe still aboard a ship that has sunk went down with her, whether or not
			# aviation's once-a-second sweep has marked it yet.
			if u.alive and u.is_aircraft() and not u.in_flight() and u.home != null and not u.home.alive:
				harm = 1.0
			if u.faction == player_faction:
				out["friendly_points"] += pts
				out["friendly_lost"] += pts * harm
			elif neutral_factions.has(u.faction):
				if u.last_attacker == player_faction and harm > 0.0:
					out["civilian"] += CIVILIAN_PENALTY * harm
					if not u.alive:
						out["neutral_hit"] += 1
			else:
				out["hostile_points"] += pts
				out["hostile_earned"] += pts * harm
	out["force"] = FORCE_WEIGHT * (1.0 - float(out["friendly_lost"]) / float(out["friendly_points"])) if out["friendly_points"] > 0 else FORCE_WEIGHT
	out["attrition"] = ATTRITION_WEIGHT * clampf(float(out["hostile_earned"]) / float(out["hostile_points"]), 0.0, 1.0) if out["hostile_points"] > 0 else ATTRITION_WEIGHT
	# A bonus taken on the way to a defeat bought nothing.
	if out["bonus_total"] > 0 and result != Result.DEFEAT:
		out["bonus"] = BONUS_WEIGHT * float(out["bonus_done"]) / float(out["bonus_total"])
	out["percent"] = clampi(int(round(float(out["task"]) + float(out["force"]) + float(out["attrition"]) + float(out["bonus"]) - float(out["civilian"]))), 0, 100)
	return out


func effectiveness() -> int:
	return int(assessment()["percent"])


## One line for the debrief: "Task 60 · Force 17 · Attrition 12 · Civilian −25 = 64%".
static func assessment_text(a: Dictionary) -> String:
	var parts := PackedStringArray()
	parts.append("Task %d/%d" % [int(round(float(a["task"]))), int(TASK_WEIGHT)])
	parts.append("Force %d/%d" % [int(round(float(a["force"]))), int(FORCE_WEIGHT)])
	parts.append("Attrition %d/%d" % [int(round(float(a["attrition"]))), int(ATTRITION_WEIGHT)])
	if int(a.get("bonus_total", 0)) > 0:
		parts.append("Bonus %d/%d" % [int(round(float(a.get("bonus", 0.0)))), int(BONUS_WEIGHT)])
	if float(a["civilian"]) > 0.0:
		parts.append("Civilian −%d" % int(round(float(a["civilian"]))))
	return "%s = %d%%" % [" · ".join(parts), int(a["percent"])]
