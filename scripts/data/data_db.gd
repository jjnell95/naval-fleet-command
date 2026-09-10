class_name DataDB
## Lazily scans res://data for PlatformSpec and SensorSpec resources, indexed by id.

const PLATFORM_ROOT := "res://data/platforms"
const SENSOR_ROOT := "res://data/sensors"
const WEAPON_ROOT := "res://data/weapons"

static var _platforms: Dictionary = {}
static var _sensors: Dictionary = {}
static var _weapons: Dictionary = {}
static var _loaded := false


static func platform(id: String) -> PlatformSpec:
	_ensure_loaded()
	return _platforms.get(id)


static func sensor(id: String) -> SensorSpec:
	_ensure_loaded()
	return _sensors.get(id)


static func weapon(id: String) -> WeaponSpec:
	_ensure_loaded()
	return _weapons.get(id)


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_scan(PLATFORM_ROOT)
	_scan(SENSOR_ROOT)
	_scan(WEAPON_ROOT)


static func _scan(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("DataDB: cannot open %s" % dir_path)
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var path := dir_path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				_scan(path)
		elif name.ends_with(".tres") or name.ends_with(".res"):
			var res := load(path)
			if res is PlatformSpec:
				_platforms[res.id] = res
			elif res is SensorSpec:
				_sensors[res.id] = res
			elif res is WeaponSpec:
				_weapons[res.id] = res
		name = dir.get_next()
	dir.list_dir_end()
