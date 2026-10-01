class_name ScenarioIndex
## Lists the scenarios in data/scenarios, plus any the player has built in the editor and saved
## under user://scenarios, so the menu does not need a hard-coded table.

const ROOT := "res://data/scenarios"
const USER_ROOT := "user://scenarios"


## Test/dev sessions can isolate storage from a player's missions. Release sessions retain the
## browser's persistent user:// filesystem; JSON imports cannot change this command-line value.
static func user_root() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario-storage="):
			return arg.trim_prefix("--scenario-storage=")
	return USER_ROOT


## Returns [{path, id, name, description, forces, order, custom}], built-ins first by their
## `order` field, then custom scenarios by name.
static func list_all() -> Array:
	var out: Array = []
	_scan(ROOT, false, out)
	_scan(user_root(), true, out)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["custom"] != b["custom"]:
			return not a["custom"]
		if a["order"] != b["order"]:
			return a["order"] < b["order"]
		return a["name"] < b["name"])
	return out


## Desk summaries by path, so returning to the desk does not re-parse megabytes of coastline.
## Shipped missions cannot change while the game runs. A custom one is read again when its
## modified time or length changes, or when the editor saves it (see forget()).
static var _cache: Dictionary = {}
## How many files the index has parsed this session; tests read it to prove the cache holds.
static var parses := 0


static func _scan(root: String, custom: bool, out: Array) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		if not custom:
			push_error("ScenarioIndex: cannot open %s" % root)
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".json") and not name.ends_with(CommanderLog.FILE_NAME):
			var entry := _entry(root.path_join(name), name, custom)
			if not entry.is_empty():
				out.append(entry)
		name = dir.get_next()
	dir.list_dir_end()


static func _entry(path: String, name: String, custom: bool) -> Dictionary:
	var stamp := _stamp(path) if custom else "shipped"
	var hit: Dictionary = _cache.get(path, {})
	if not hit.is_empty() and hit["stamp"] == stamp:
		return hit["entry"].duplicate()
	parses += 1
	var d := ScenarioLoader.load_file(path)
	var entry := {}
	if not d.is_empty():
		entry = {
			"path": path,
			"id": d.get("id", name),
			"name": d.get("name", name),
			"description": d.get("description", ""),
			"order": int(d.get("order", 999)),
			"forces": d.get("forces", ""),
			"custom": custom,
			"era": d.get("era", "Modern"),
			"collection": d.get("collection", "operations"),
			"year": int(d.get("year", str(d.get("start_time_utc", "0")).substr(0, 4))),
			"difficulty": d.get("difficulty", "Open command"),
			"duration_minutes": int(d.get("duration_minutes", 0)),
			"role": d.get("role", "Task force command"),
			"theatre": d.get("theatre", ""),
			"region": str(d.get("map", {}).get("chart_region", "north_atlantic")),
		}
	# An unreadable file is remembered too, so a broken import is not re-parsed on every refresh.
	_cache[path] = {"stamp": stamp, "entry": entry}
	return entry.duplicate()


static func _stamp(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	var length := f.get_length() if f != null else -1
	return "%d:%d" % [FileAccess.get_modified_time(path), length]


## Drops a remembered summary; the editor calls it after writing a mission, because two saves
## within the same second at the same length would otherwise look unchanged.
static func forget(path: String) -> void:
	_cache.erase(path)


## Where a custom scenario with this id lives.
static func custom_path(id: String) -> String:
	return user_root().path_join("%s.json" % id.validate_filename())


static func ensure_user_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(user_root()))
