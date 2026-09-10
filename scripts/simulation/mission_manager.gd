class_name MissionManager
extends Node
## Evaluates scenario objectives. Victory when every objective in the scenario's `victory` list
## is complete; defeat when any objective in its `loss` list becomes true. Both lists are data,
## so a new scenario needs no code.

signal mission_ended(result: String, summary: String)
signal objective_completed(objective: MissionObjective, is_loss: bool)

enum Result { RUNNING, VICTORY, DEFEAT }

var unit_manager: UnitManager
var player_faction := "BLUE"
var briefing := ""
var situation := ""
var victory_objectives: Array[MissionObjective] = []
var loss_objectives: Array[MissionObjective] = []
var result: Result = Result.RUNNING


func configure(scenario: Dictionary) -> void:
	result = Result.RUNNING
	victory_objectives.clear()
	loss_objectives.clear()
	var obj: Dictionary = scenario.get("objectives", {})
	briefing = obj.get("text", "")
	situation = scenario.get("description", "")
	for d in obj.get("victory", []):
		victory_objectives.append(MissionObjective.from_dict(d))
	for d in obj.get("loss", []):
		loss_objectives.append(MissionObjective.from_dict(d))
	if victory_objectives.is_empty():
		push_warning("MissionManager: scenario '%s' defines no victory condition" % scenario.get("id", "?"))


func tick(now: float) -> void:
	if result != Result.RUNNING or unit_manager == null:
		return
	for o in loss_objectives:
		if not o.complete and o.evaluate(unit_manager, now):
			objective_completed.emit(o, true)
			_finish(Result.DEFEAT, o.text)
			return
	var done := 0
	for o in victory_objectives:
		var was := o.complete
		if o.evaluate(unit_manager, now):
			done += 1
			if not was:
				objective_completed.emit(o, false)
	if done > 0 and done == victory_objectives.size():
		_finish(Result.VICTORY, briefing)


func _finish(r: Result, summary: String) -> void:
	result = r
	mission_ended.emit("VICTORY" if r == Result.VICTORY else "DEFEAT", summary)
