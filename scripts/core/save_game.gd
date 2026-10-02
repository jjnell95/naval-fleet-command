class_name SaveGame
extends RefCounted
## Saved engagements on disk: a quicksave, a short history of autosaves and the files' headers for
## the list. Each file holds a small header (for listing without decoding the whole engagement) and
## a SimSnapshot plus the screen's own record (the observed journal, the after-action counters).
## user:// is the player's storage on the desktop and the browser's persistent storage on the web;
## nothing here is a mission definition, and nothing is written into the custom-mission library,
## which would list it as a mission.
##
## The layout is plain and checked before anything is decoded: the magic, a format byte, a SHA-256
## of everything after it, then the header and the zstd-compressed engagement, each behind its
## length. A damaged file fails the checksum; it never reaches a decoder that could read a garbage
## length, and it never loads as a different battle.

const EXTENSION := "nfcsave"
const MAGIC := "NFC-ENGAGEMENT"
## The file layout's own version (the engagement inside has SimSnapshot.VERSION).
const FILE_FORMAT := 2
## No engagement decompresses to more than this; a larger claim is damage, not a battle.
const MAX_ENGAGEMENT_BYTES := 256 * 1024 * 1024
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
	var raw := var_to_bytes(payload)
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var body := StreamPeerBuffer.new()
	var header_bytes := var_to_bytes(header)
	body.put_u32(header_bytes.size())
	body.put_data(header_bytes)
	body.put_u32(raw.size())
	body.put_u32(packed.size())
	body.put_data(packed)
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Cannot write the save (%s)" % error_string(FileAccess.get_open_error())
	file.store_buffer(MAGIC.to_utf8_buffer())
	file.store_8(FILE_FORMAT)
	file.store_buffer(_digest(body.data_array))
	file.store_buffer(body.data_array)
	file.close()  # on the web this is what commits the file to persistent storage
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var err := DirAccess.rename_absolute(temporary, path)
	return "" if err == OK else "Cannot finish the save (%s)" % error_string(err)


## The header alone, for a list of saves. Empty when the file is not a readable save.
static func read_header(path: String) -> Dictionary:
	var parts := _open(path)
	return parts["header"] if str(parts["error"]) == "" else {}


## {"header", "payload", "error"}. A damaged, truncated or foreign file reports why instead of
## reaching the simulation; objects are never decoded from a file (bytes_to_var, not
## bytes_to_var_with_objects).
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "No saved engagement there"}
	var parts := _open(path)
	if str(parts["error"]) != "":
		return {"error": parts["error"]}
	var raw := (parts["packed"] as PackedByteArray).decompress(int(parts["raw_size"]), FileAccess.COMPRESSION_ZSTD)
	if raw.size() != int(parts["raw_size"]):
		return {"error": "The save file is damaged (does not decompress)"}
	var payload: Variant = bytes_to_var(raw)
	if typeof(payload) != TYPE_DICTIONARY or not (payload as Dictionary).has("simulation"):
		return {"error": "The save file is damaged (incomplete)"}
	return {"header": parts["header"], "payload": payload, "error": ""}


## Checks a file's magic, format and checksum, then splits it into its header and the still
## compressed engagement. {"error", "header", "packed", "raw_size"}.
static func _open(path: String) -> Dictionary:
	var out := {"error": "", "header": {}, "packed": PackedByteArray(), "raw_size": 0}
	var bytes := FileAccess.get_file_as_bytes(path)
	var magic := MAGIC.to_utf8_buffer()
	var lead := magic.size() + 1 + 32
	if bytes.size() < lead or bytes.slice(0, magic.size()) != magic:
		out["error"] = "Not a saved engagement"
		return out
	var format := bytes[magic.size()]
	if format > FILE_FORMAT:
		out["error"] = "Saved by a newer version of the game"
		return out
	if format < FILE_FORMAT:
		out["error"] = "The save file is from an earlier test build and cannot be read"
		return out
	var body := bytes.slice(lead)
	if _digest(body) != bytes.slice(magic.size() + 1, lead):
		out["error"] = "The save file is damaged (checksum does not match)"
		return out
	# The checksum matched, so the lengths are the ones written; they are still bounded, because a
	# file can be complete and consistent and still not be one of ours.
	var at := 0
	var header_size := _u32(body, at)
	at += 4
	if header_size < 0 or at + header_size > body.size():
		out["error"] = "The save file is damaged (header)"
		return out
	var header: Variant = bytes_to_var(body.slice(at, at + header_size))
	at += header_size
	var raw_size := _u32(body, at)
	var packed_size := _u32(body, at + 4)
	at += 8
	if typeof(header) != TYPE_DICTIONARY or raw_size <= 0 or raw_size > MAX_ENGAGEMENT_BYTES or packed_size <= 0 or at + packed_size != body.size():
		out["error"] = "The save file is damaged (incomplete)"
		return out
	out["header"] = header
	out["packed"] = body.slice(at)
	out["raw_size"] = raw_size
	return out


## A little-endian u32 at `at`, or -1 past the end.
static func _u32(bytes: PackedByteArray, at: int) -> int:
	return bytes.decode_u32(at) if at >= 0 and at + 4 <= bytes.size() else -1


static func _digest(bytes: PackedByteArray) -> PackedByteArray:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish()


## Deletes a save. On the web a deletion alone never reaches the browser's storage: the engine
## writes its file system back only after a file opened for writing closes, so one is written.
static func remove(path: String) -> void:
	DirAccess.remove_absolute(path)
	if OS.has_feature("web"):
		var marker := FileAccess.open(root().path_join(".sync"), FileAccess.WRITE)
		if marker != null:
			marker.store_8(0)
			marker.close()


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
		remove(str(autos[i]["path"]))


## A number that orders saves newest first across sessions: wall-clock seconds, then a counter
## within the second.
static var _last_serial := 0


static func next_serial() -> int:
	_last_serial = maxi(_last_serial + 1, int(Time.get_unix_time_from_system() * 1000.0))
	return _last_serial
