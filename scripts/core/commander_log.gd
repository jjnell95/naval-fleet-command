class_name CommanderLog
extends RefCounted
## The commander's record: the best result of every operation attempted, kept in the player's
## own storage and read by the operations desk. The late-1990s fleet-command games kept such a
## log of best scores and the date they were set; this is that, for this game's effectiveness
## percentage. Nothing in the simulation reads it.

const FILE_NAME := "commander_log.json"

## Tests point this at a scratch file so a run never touches a player's record.
static var path_override := ""


## In play, user://commander_log.json, beside the custom-mission library. A session with its own
## mission storage (--scenario-storage=res://work/x) keeps its own log beside that directory,
## res://work/x.commander_log.json, never inside it where the library would list it as a mission.
static func path() -> String:
	if path_override != "":
		return path_override
	var root := ScenarioIndex.user_root().trim_suffix("/")
	if root == ScenarioIndex.USER_ROOT:
		return "user://" + FILE_NAME
	return root + "." + FILE_NAME


## Every entry as typed fields. A hand-edited or damaged file never reaches the desk as a crash:
## anything that is not an entry is dropped and anything that is not a number reads as none.
static func load_all() -> Dictionary:
	if not FileAccess.file_exists(path()):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path())) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {}
	var out := {}
	for key in json.data:
		var entry = json.data[key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		out[str(key)] = {
			"best_percent": clampi(_number(entry.get("best_percent"), 0), 0, 100),
			"result": str(entry.get("result", "")),
			"date": str(entry.get("date", "")),
			"attempts": maxi(_number(entry.get("attempts"), 1), 1),
			"last_percent": clampi(_number(entry.get("last_percent"), 0), 0, 100),
			"last_result": str(entry.get("last_result", "")),
		}
	return out


static func _number(value, fallback: int) -> int:
	return int(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else fallback


## The entry for one operation: {best_percent, result, date, attempts, last_percent, last_result}
## or {} when it has never been attempted.
static func best(scenario_id: String) -> Dictionary:
	return load_all().get(scenario_id, {})


## Records a finished operation. A victory outranks any defeat; among equal results the higher
## effectiveness is the best. Returns the stored entry with "improved" set when this attempt
## became the best.
static func record(scenario_id: String, result: String, percent: int, date: String) -> Dictionary:
	if scenario_id == "":
		return {}
	var all := load_all()
	var entry: Dictionary = all.get(scenario_id, {})
	var improved := entry.is_empty() or outranks(result, percent, str(entry.get("result", "")), int(entry.get("best_percent", -1)))
	if improved:
		entry["best_percent"] = percent
		entry["result"] = result
		entry["date"] = date
	entry["attempts"] = int(entry.get("attempts", 0)) + 1
	entry["last_percent"] = percent
	entry["last_result"] = result
	all[scenario_id] = entry
	_save(all)
	var out := entry.duplicate()
	out["improved"] = improved
	return out


static func outranks(result: String, percent: int, best_result: String, best_percent: int) -> bool:
	var won := result == "VICTORY"
	var best_won := best_result == "VICTORY"
	if won != best_won:
		return won
	return percent > best_percent


static func _save(all: Dictionary) -> void:
	var target := path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		push_warning("CommanderLog: cannot write %s" % target)
		return
	file.store_string(JSON.stringify(all, "  "))
	file.close()


static func clear() -> void:
	if FileAccess.file_exists(path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path()))
