class_name ScenarioIndex
## Lists the scenarios in data/scenarios so the menu does not need a hard-coded table.

const ROOT := "res://data/scenarios"


## Returns [{path, id, name, description, difficulty}], ordered by the scenario's `order` field.
static func list_all() -> Array:
	var out: Array = []
	var dir := DirAccess.open(ROOT)
	if dir == null:
		push_error("ScenarioIndex: cannot open %s" % ROOT)
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".json"):
			var path := ROOT.path_join(name)
			var d := ScenarioLoader.load_file(path)
			if not d.is_empty():
				out.append({
					"path": path,
					"id": d.get("id", name),
					"name": d.get("name", name),
					"description": d.get("description", ""),
					"order": int(d.get("order", 999)),
					"forces": d.get("forces", ""),
				})
		name = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["order"] != b["order"]:
			return a["order"] < b["order"]
		return a["name"] < b["name"])
	return out
