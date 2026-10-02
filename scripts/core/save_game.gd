class_name SaveGame
extends RefCounted
## Saved engagements on disk: a quicksave, a short history of autosaves and the files' headers for
## the list. Each file is a small header (for listing without reading the whole engagement) and a
## SimSnapshot plus the screen's own record (the observed journal, the after-action counters),
## written with store_var into a zstd-compressed file. user:// is the player's storage on the
## desktop and the browser's persistent storage on the web; nothing here is a mission definition,
## and nothing is written into the custom-mission library, which would list it as a mission.

const EXTENSION := "nfcsave"
const MAGIC := "NFC-ENGAGEMENT"
const QUICKSAVE := "quicksave"
const AUTOSAVE_PREFIX := "autosave-"
## Autosaves kept per engagement history, oldest dropped first, and how often one is taken in
## simulated time. GAMEPLAY: frequent enough to lose little, few enough to stay small.
const AUTOSAVE_KEEP := 5
const AUTOSAVE_INTERVAL_S := 600.0

## Tests and validation runs point this at a scratch directory so a run never touches a player's
## saves.
static var root_override := ""


## user://saves in play. A session with its own mission storage (--scenario-storage=res://work/x)
## keeps its saves beside it in res://work/x.saves, as the commander's log does.
static func root() -> String:
	if root_override != "":
		return root_override
	var library := ScenarioIndex.user_root().trim_suffix("/")
	if library == ScenarioIndex.USER_ROOT:
		return "user://saves"
	return library + ".saves"


static func slot_path(slot: String) -> String:
	return root().path_join(slot + "." + EXTENSION)


## Writes atomically: a temporary file first, renamed over the old one only once it is complete,
## so a save interrupted part-way never destroys the previous one. Returns "" or the reason.
static func write(path: String, header: Dictionary, payload: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var temporary := path + ".tmp"
	var file := FileAccess.open_compressed(temporary, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return "Cannot write the save (%s)" % error_string(FileAccess.get_open_error())
	file.store_pascal_string(MAGIC)
	file.store_var(header, false)
	file.store_var(payload, false)
	file.close()  # on the web this is what commits the file to persistent storage
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var err := DirAccess.rename_absolute(temporary, path)
	return "" if err == OK else "Cannot finish the save (%s)" % error_string(err)


## The header alone, for a list of saves. Empty when the file is not a readable save.
static func read_header(path: String) -> Dictionary:
	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null or file.get_pascal_string() != MAGIC:
		return {}
	var header: Variant = file.get_var(false)
	return header if typeof(header) == TYPE_DICTIONARY else {}


## {"header", "payload", "error"}. A damaged, truncated or foreign file reports why instead of
## reaching the simulation; objects are never decoded from a file (get_var(false)).
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "No saved engagement there"}
	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return {"error": "The save file is damaged or is not a saved engagement"}
	if file.get_length() < MAGIC.length() or file.get_pascal_string() != MAGIC:
		return {"error": "Not a saved engagement"}
	var header: Variant = file.get_var(false)
	var payload: Variant = file.get_var(false)
	if typeof(header) != TYPE_DICTIONARY or typeof(payload) != TYPE_DICTIONARY or not (payload as Dictionary).has("simulation"):
		return {"error": "The save file is damaged (incomplete)"}
	return {"header": header, "payload": payload, "error": ""}


## Every readable save, newest first, as headers with their "path" added.
static func list_saves() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(root())
	if dir == null:
		return out
	for name in dir.get_files():
		if not name.ends_with("." + EXTENSION):
			continue
		var path := root().path_join(name)
		var header := read_header(path)
		if header.is_empty():
			continue
		header["path"] = path
		header["slot"] = name.get_basename()
		out.append(header)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("serial", 0)) > int(b.get("serial", 0)))
	return out


## The slot for the next autosave, dropping the oldest beyond AUTOSAVE_KEEP once it is written.
static func next_autosave_slot() -> String:
	var serial := 0
	for header in list_saves():
		if str(header.get("slot", "")).begins_with(AUTOSAVE_PREFIX):
			serial = maxi(serial, int(str(header["slot"]).trim_prefix(AUTOSAVE_PREFIX)))
	return AUTOSAVE_PREFIX + str(serial + 1)


static func prune_autosaves() -> void:
	var autos: Array[Dictionary] = []
	for header in list_saves():
		if str(header.get("slot", "")).begins_with(AUTOSAVE_PREFIX):
			autos.append(header)
	autos.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(str(a["slot"]).trim_prefix(AUTOSAVE_PREFIX)) > int(str(b["slot"]).trim_prefix(AUTOSAVE_PREFIX)))
	for i in range(AUTOSAVE_KEEP, autos.size()):
		DirAccess.remove_absolute(str(autos[i]["path"]))


## A number that orders saves newest first across sessions: wall-clock seconds, then a counter
## within the second.
static var _last_serial := 0


static func next_serial() -> int:
	_last_serial = maxi(_last_serial + 1, int(Time.get_unix_time_from_system() * 1000.0))
	return _last_serial
