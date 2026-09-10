class_name ScenarioIndex
## Lists the scenarios in data/scenarios, plus any the player has built in the editor and saved
## under user://scenarios, so the menu does not need a hard-coded table.

const ROOT := "res://data/scenarios"
const USER_ROOT := "user://scenarios"


## Returns [{path, id, name, description, forces, order, custom}], built-ins first by their
## `order` field, then custom scenarios by name.
static func list_all() -> Array:
	var out: Array = []
	_scan(ROOT, false, out)
	_scan(USER_ROOT, true, out)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["custom"] != b["custom"]:
			return not a["custom"]
		if a["order"] != b["order"]:
			return a["order"] < b["order"]
		return a["name"] < b["name"])
	return out


static func _scan(root: String, custom: bool, out: Array) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		if not custom:
			push_error("ScenarioIndex: cannot open %s" % root)
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".json"):
			var path := root.path_join(name)
			var d := ScenarioLoader.load_file(path)
			if not d.is_empty():
				out.append({
					"path": path,
					"id": d.get("id", name),
					"name": d.get("name", name),
					"description": d.get("description", ""),
					"order": int(d.get("order", 999)),
					"forces": d.get("forces", ""),
					"custom": custom,
				})
		name = dir.get_next()
	dir.list_dir_end()


## Where a custom scenario with this id lives.
static func custom_path(id: String) -> String:
	return USER_ROOT.path_join("%s.json" % id)


static func ensure_user_dir() -> void:
	DirAccess.make_dir_recursive_absolute(USER_ROOT)
