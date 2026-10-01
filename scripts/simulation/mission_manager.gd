class_name MissionManager
extends Node
## Evaluates scenario objectives. Victory when every objective in the scenario's `victory` list
## is complete (or any for an explicit victory_mode="any"); defeat when any loss is true.
## Both lists are data,
## so a new scenario needs no code.

signal mission_ended(result: String, summary: String)
signal objective_completed(objective: MissionObjective, is_loss: bool)

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
var player_faction := "BLUE"
var briefing := ""
var situation := ""
var victory_objectives: Array[MissionObjective] = []
var loss_objectives: Array[MissionObjective] = []
var result: Result = Result.RUNNING
var victory_mode := "all"
var neutral_factions := PackedStringArray()


func configure(scenario: Dictionary) -> void:
	result = Result.RUNNING
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
		if not o.complete and o.evaluate(unit_manager, now):
			objective_completed.emit(o, true)
			_finish(Result.DEFEAT, o.text)
			return
	var done := 0
	var terminal_count := 0
	for o in victory_objectives:
		if not o.phase_only:
			terminal_count += 1
		o.unlocked = prerequisites_complete(o.after)
		var was := o.complete
		if o.evaluate(unit_manager, now):
			if not o.phase_only:
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
		"friendly_points": 0, "friendly_lost": 0.0, "hostile_points": 0, "hostile_earned": 0.0, "neutral_hit": 0, "percent": 0}
	for o in victory_objectives:
		if o.phase_only:
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
	out["percent"] = clampi(int(round(float(out["task"]) + float(out["force"]) + float(out["attrition"]) - float(out["civilian"]))), 0, 100)
	return out


func effectiveness() -> int:
	return int(assessment()["percent"])


## One line for the debrief: "Task 60 · Force 17 · Attrition 12 · Civilian −25 = 64%".
static func assessment_text(a: Dictionary) -> String:
	var parts := PackedStringArray()
	parts.append("Task %d/%d" % [int(round(float(a["task"]))), int(TASK_WEIGHT)])
	parts.append("Force %d/%d" % [int(round(float(a["force"]))), int(FORCE_WEIGHT)])
	parts.append("Attrition %d/%d" % [int(round(float(a["attrition"]))), int(ATTRITION_WEIGHT)])
	if float(a["civilian"]) > 0.0:
		parts.append("Civilian −%d" % int(round(float(a["civilian"]))))
	return "%s = %d%%" % [" · ".join(parts), int(a["percent"])]
