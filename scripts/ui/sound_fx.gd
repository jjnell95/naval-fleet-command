extends Node
## A pre-rendered, layered effects bank. No random synthesis in the simulation's process and no
## one-second machinery oscillators. Radio speech stays in front of restrained console/sea audio.

const ROOT := "res://assets/audio"
const VOICES := 6
const SILENT_DB := -80.0
const SEA_DB_CALM := -32.0
const SEA_DB_HIGH := -17.0
const HUM_DB := {"engine": -20.0, "boat": -26.0, "rotor": -22.0, "jet": -23.0}
const DUCK_DB := 9.0
const SLEW_DB_S := 36.0
const AMBIENT_SETTINGS_KEY := "ambient"
const ALERT_CUES := ["alarm", "torpedo"]
const VARIANTS := {"launch": 3, "gun": 3, "torpedo_launch": 3, "impact": 3, "intercept": 3}
const CUE_DB := {
	"ping": -17.0, "launch": -11.0, "gun": -11.0, "torpedo_launch": -13.0,
	"release": -18.0, "impact": -10.0, "intercept": -13.0,
	"alarm": -9.0, "torpedo": -9.0, "contact": -20.0, "classified": -21.0,
	"click": -19.0, "victory": -20.0, "defeat": -20.0,
}

var enabled := true
var ambient_enabled := true
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _alert_player: AudioStreamPlayer
var _last_played: Dictionary = {}
var _variants: Dictionary = {}
var _ambient: Dictionary = {}
var _sea_player: AudioStreamPlayer
var _hum_player: AudioStreamPlayer
var _ambient_active := false
var _speech_active := false
var _sea_state := 0
var _hum := ""


func _ready() -> void:
	for cue: String in CUE_DB:
		var bank: Array[AudioStream] = []
		var stem := "complete" if cue in ["victory", "defeat"] else cue
		for index in int(VARIANTS.get(cue, 1)):
			bank.append(load("%s/effects/%s_%d.ogg" % [ROOT, stem, index]) as AudioStream)
		_streams[cue] = bank
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	# A full salvo must never steal an incoming-threat warning's playback slot.
	_alert_player = AudioStreamPlayer.new()
	add_child(_alert_player)
	for hum: String in ["sea", "engine", "boat", "rotor", "jet"]:
		var stream := load("%s/ambient/%s.ogg" % [ROOT, hum]) as AudioStreamOggVorbis
		stream.loop = true
		_ambient[hum] = stream
	_sea_player = AudioStreamPlayer.new()
	_hum_player = AudioStreamPlayer.new()
	for p: AudioStreamPlayer in [_sea_player, _hum_player]:
		p.volume_db = SILENT_DB
		add_child(p)
	_sea_player.stream = _ambient["sea"]
	ambient_enabled = bool(UserSettings.get_value("audio", AMBIENT_SETTINGS_KEY, true))


static func launch_cue(spec: WeaponSpec) -> String:
	if spec == null:
		return "release"
	if spec.is_torpedo():
		return "torpedo_launch"
	if spec.is_gun() or spec.type == "ciws":
		return "gun"
	if spec.type == "bomb":
		return "release"
	return "launch"


## Cues rotate between authored takes without touching the simulation's RNG. Limit simultaneous
## copies as well as repetitions in time, so several weapons don't become a wall of white noise.
func play(cue: String, min_gap_s := 0.15) -> void:
	if not enabled or not _streams.has(cue):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(cue, -10.0)) < min_gap_s:
		return
	var player: AudioStreamPlayer = _alert_player if cue in ALERT_CUES else _available_player(cue)
	if player == null:
		return
	_last_played[cue] = now
	var bank: Array = _streams[cue]
	var index := int(_variants.get(cue, 0)) % bank.size()
	_variants[cue] = index + 1
	player.stream = bank[index]
	player.set_meta("cue", cue)
	player.volume_db = cue_volume(cue)
	player.pitch_scale = 1.0
	player.play()


func _available_player(cue: String) -> AudioStreamPlayer:
	var available: AudioStreamPlayer
	var copies := 0
	for p in _players:
		if not p.playing:
			if available == null:
				available = p
		elif str(p.get_meta("cue", "")) == cue:
			copies += 1
	return available if copies < 2 else null


func cue_volume(cue: String) -> float:
	var duck := (2.0 if cue in ALERT_CUES else 6.0) if _speech_active else 0.0
	return float(CUE_DB.get(cue, -20.0)) - duck


func set_crew_speaking(active: bool) -> void:
	_speech_active = active


func toggle() -> bool:
	enabled = not enabled
	if not enabled:
		for p in _players:
			p.stop()
		_alert_player.stop()
		_stop_ambient()
	return enabled


func set_ambient(active: bool, sea_state: int, hum: String) -> void:
	_ambient_active = active
	_sea_state = clampi(sea_state, 0, 6)
	_hum = hum if HUM_DB.has(hum) else ""


func toggle_ambient() -> bool:
	set_ambient_enabled(not ambient_enabled)
	return ambient_enabled


func set_ambient_enabled(on: bool, persist := true) -> void:
	ambient_enabled = on
	if persist:
		UserSettings.set_value("audio", AMBIENT_SETTINGS_KEY, ambient_enabled)
	if not ambient_enabled:
		_stop_ambient()


static func hum_for(u: Unit) -> String:
	if u == null or u.spec == null:
		return ""
	if u.is_aircraft():
		if not u.in_flight():
			return "engine" if u.home != null else ""
		return "rotor" if u.spec.can_hover else "jet"
	match u.spec.domain:
		"surface":
			return "engine"
		"subsurface":
			return "boat"
	return ""


func ambient_targets() -> Vector2:
	if not enabled or not ambient_enabled or not _ambient_active or SimClock.paused:
		return Vector2(SILENT_DB, SILENT_DB)
	var duck := DUCK_DB if _speech_active or _cue_playing() else 0.0
	var sea := lerpf(SEA_DB_CALM, SEA_DB_HIGH, float(_sea_state) / 6.0) - duck
	var hum: float = float(HUM_DB[_hum]) - duck if _hum != "" else SILENT_DB
	return Vector2(sea, hum)


func ambient_playing() -> bool:
	return (_sea_player != null and _sea_player.playing) or (_hum_player != null and _hum_player.playing)


func _process(delta: float) -> void:
	for p in _players + [_alert_player]:
		if p != null and p.playing:
			p.volume_db = move_toward(p.volume_db, cue_volume(str(p.get_meta("cue", ""))), 80.0 * delta)
	if _sea_player == null:
		return
	var target := ambient_targets()
	_slew(_sea_player, target.x, delta)
	var desired: AudioStream = _ambient.get(_hum)
	if _hum_player.stream != desired:
		_slew(_hum_player, SILENT_DB, delta)
		if not _hum_player.playing:
			_hum_player.stream = desired
	else:
		_slew(_hum_player, target.y, delta)


func _slew(p: AudioStreamPlayer, target_db: float, delta: float) -> void:
	p.volume_db = move_toward(p.volume_db, target_db, SLEW_DB_S * delta)
	if target_db <= SILENT_DB and p.volume_db <= SILENT_DB + 30.0:
		p.stop()
		p.volume_db = SILENT_DB
	elif target_db > SILENT_DB and not p.playing and p.stream != null:
		p.play()


func _stop_ambient() -> void:
	for p: AudioStreamPlayer in [_sea_player, _hum_player]:
		if p != null:
			p.stop()
			p.volume_db = SILENT_DB


func _cue_playing() -> bool:
	if _alert_player != null and _alert_player.playing:
		return true
	for p in _players:
		if p.playing:
			return true
	return false
