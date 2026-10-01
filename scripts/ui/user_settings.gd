class_name UserSettings
extends RefCounted
## The player's interface preferences (crew voice, ambient sound), kept in one ConfigFile under
## user://, never under res://. Tests point `path` at a scratch file so a run cannot change what a
## player chose, and `writable` lets scripted runs read preferences without ever saving them.

const DEFAULT_PATH := "user://settings.cfg"

static var path := DEFAULT_PATH
static var writable := true


static func get_value(section: String, key: String, fallback: Variant) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return fallback
	return cfg.get_value(section, key, fallback)


static func has_value(section: String, key: String) -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(path) == OK and cfg.has_section_key(section, key)


static func set_value(section: String, key: String, value: Variant) -> bool:
	if not writable or not path.begins_with("user://"):
		return false
	var cfg := ConfigFile.new()
	cfg.load(path)  # a missing file is an empty one
	cfg.set_value(section, key, value)
	return cfg.save(path) == OK
