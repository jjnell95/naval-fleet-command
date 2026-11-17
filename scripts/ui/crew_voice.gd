class_name CrewVoice
extends Node
## Short, complete radio performances, bundled with the game. Playback has the same timing and
## timbre on every platform; it never depends on an installed speech voice or a network service.
## Detailed ship names, track numbers and refusal reasons remain in the on-screen radio report.
## Alerts interrupt routine traffic. One routine line waits, and expires after four real seconds.

signal line_spoken(line: Dictionary)
signal speaking_changed(active: bool)

const PHRASES_PATH := "res://data/voice/phrases.json"
const CLIP_ROOT := "res://assets/audio/crew"
const PROFILES := ["watch", "bridge"]
const EVENTS := [
	"order_ack", "attack_ack", "investigate_ack", "order_refused",
	"missile_away", "torpedo_away", "inbound_missile", "torpedo_inbound",
	"interceptor_kill", "target_destroyed", "attack_broken_off", "own_ship_hit", "unit_lost",
	"new_contact", "contact_hostile", "aircraft_rtb", "fire_out", "mission_won", "mission_lost",
]
const ALERT_EVENTS := ["inbound_missile", "torpedo_inbound", "own_ship_hit", "unit_lost"]
const FINAL_EVENTS := ["mission_won", "mission_lost"]
const STALE_S := 4.0
const ROUTINE_GAP_S := 2.0
const ALERT_REPEAT_S := 3.0
const MAX_SPOKEN_LOG := 24
const SETTINGS_SECTION := "audio"
const SETTINGS_KEY := "voice"

var phrases: Dictionary = {}
var enabled := false
## Injectable playback and clock keep tests and scripted runs silent.
var sink := Callable()
var busy := Callable()
var stop_sink := Callable()
var clock := Callable()
var compression := Callable()
var muted := Callable()
var routine_ceiling := 1.0
var spoken: Array[Dictionary] = []
var dropped_stale := 0
var speaking := false

var _player: AudioStreamPlayer
var _clips: Dictionary = {}
var _pending: Dictionary = {}
var _final_pending: Dictionary = {}
var _last_spoken_s := -1000.0
var _last_alert_s: Dictionary = {}
var _counters: Dictionary = {}


func _init() -> void:
	phrases = load_phrases()


func _process(_delta: float) -> void:
	if not enabled or (muted.is_valid() and bool(muted.call())):
		if speaking or not _pending.is_empty() or not _final_pending.is_empty():
			stop()
		return
	if not _pending.is_empty() or not _final_pending.is_empty():
		_pump()


static func default_on() -> bool:
	return true  # The recordings work on Linux too, with no speech-dispatcher dependency.


static func automated_run() -> bool:
	var args := OS.get_cmdline_args()
	return DisplayServer.get_name() == "headless" or args.has("--script") or args.has("-s")


## Explicitly installed by a player session (or by the dedicated audio playback check).
## Merely constructing CrewVoice in a test never starts playback.
func use_recordings() -> void:
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.name = "CrewRadio"
		add_child(_player)
		_player.finished.connect(_on_playback_finished)
	sink = _play_recording
	busy = func() -> bool: return _player.playing
	stop_sink = func() -> void:
		_player.stop()
		_set_speaking(false)


func configure_from_settings() -> String:
	enabled = bool(UserSettings.get_value(SETTINGS_SECTION, SETTINGS_KEY, default_on()))
	if enabled and not sink.is_valid():
		if automated_run():
			return "Crew voice is silent in automated runs"
		use_recordings()
	return ""


func toggle(persist := true) -> String:
	if enabled:
		set_enabled(false, persist)
		return "Crew voice off"
	if not sink.is_valid() and not automated_run():
		use_recordings()
	set_enabled(true, persist)
	return "Crew voice on"


func set_enabled(on: bool, persist := true) -> void:
	enabled = on
	if not on:
		stop()
	if persist:
		UserSettings.set_value(SETTINGS_SECTION, SETTINGS_KEY, on)


func stop() -> void:
	_pending = {}
	_final_pending = {}
	if stop_sink.is_valid():
		stop_sink.call()
	_set_speaking(false)


func _exit_tree() -> void:
	stop()


func _play_recording(line: Dictionary) -> void:
	var path: String = line["clip"]
	if not _clips.has(path):
		_clips[path] = load(path) as AudioStream
	var stream: AudioStream = _clips[path]
	if stream == null:
		return
	_player.stop()
	_player.stream = stream
	_player.pitch_scale = 1.0
	_player.volume_db = -2.0 if bool(line["alert"]) else -5.0
	_set_speaking(true)
	_player.play()


func _on_playback_finished() -> void:
	_set_speaking(false)
	_pump()


func _set_speaking(active: bool) -> void:
	if speaking != active:
		speaking = active
		speaking_changed.emit(active)


static func load_phrases(path := PHRASES_PATH) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("CrewVoice: no phrase table at %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not (parsed as Dictionary).get("events") is Dictionary:
		push_warning("CrewVoice: phrase table %s is malformed" % path)
		return {}
	return parsed["events"]


static func spoken_name(callsign: String) -> String:
	var s := callsign
	var paren := s.find("(")
	if paren > 0:
		s = s.substr(0, paren)
	var words := s.strip_edges().split(" ", false)
	if words.size() > 1 and words[0].length() <= 5 and words[0] == words[0].to_upper() and words[0] != words[0].to_lower():
		words.remove_at(0)
	return " ".join(words)


static func speaker_seed(speaker: Variant) -> int:
	if speaker is Unit:
		return ((speaker as Unit).id * 2654435761 + 97) & 0x7fffffff
	return 0


## Metadata identifies the reporting unit/track; the audible text is the complete performance.
func compose(event: String, speaker: Variant = null, fields := {}) -> Dictionary:
	var variants: Array = phrases.get(event, [])
	if variants.is_empty():
		return {}
	var profile: String = PROFILES[speaker_seed(speaker) % PROFILES.size()]
	var key := "%s/%s" % [profile, event]
	var index := int(_counters.get(key, 0)) % variants.size()
	_counters[key] = index + 1
	var track: Variant = fields.get("track")
	var track_id := (track as Track).id if track is Track else str(track) if track != null else ""
	var alert := event in ALERT_EVENTS
	return {
		"event": event, "text": variants[index], "alert": alert, "interrupt": alert,
		"voice": profile, "pitch": 1.0, "rate": 1.0,
		"speaker": spoken_name((speaker as Unit).callsign) if speaker is Unit else str(fields.get("name", "")),
		"track": track_id, "clip": "%s/%s/%s_%d.ogg" % [CLIP_ROOT, profile, event, index],
	}


func say(event: String, speaker: Variant = null, fields := {}) -> void:
	if not enabled or not sink.is_valid() or (muted.is_valid() and bool(muted.call())):
		return
	var priority := event in ALERT_EVENTS or event in FINAL_EVENTS
	if not priority and (_compression() > routine_ceiling + 1e-6 or not _final_pending.is_empty()):
		return
	var now := _now()
	if priority:
		if now - float(_last_alert_s.get(event, -1000.0)) < ALERT_REPEAT_S:
			return
		var line := compose(event, speaker, fields)
		if line.is_empty():
			return
		_last_alert_s[event] = now
		_pending = {}
		if event in FINAL_EVENTS and busy.is_valid() and bool(busy.call()):
			_final_pending = line  # Finish the current transmission, then the mission result.
			return
		_emit(line)
		return
	var routine := compose(event, speaker, fields)
	if routine.is_empty():
		return
	routine["t"] = now
	_pending = routine
	_pump()


func pending() -> Dictionary:
	return _pending


func _pump() -> void:
	if not enabled or not sink.is_valid() or (muted.is_valid() and bool(muted.call())):
		stop()
		return
	if not _final_pending.is_empty():
		if busy.is_valid() and bool(busy.call()):
			return
		var final_line := _final_pending
		_final_pending = {}
		_emit(final_line)
		return
	if _pending.is_empty():
		return
	var now := _now()
	if now - float(_pending["t"]) > STALE_S:
		_pending = {}
		dropped_stale += 1
		return
	if _compression() > routine_ceiling + 1e-6:
		_pending = {}
		return
	if now - _last_spoken_s < ROUTINE_GAP_S:
		return
	if busy.is_valid() and bool(busy.call()):
		return
	var line := _pending
	_pending = {}
	_emit(line)


func _emit(line: Dictionary) -> void:
	_last_spoken_s = _now()
	spoken.append(line)
	if spoken.size() > MAX_SPOKEN_LOG:
		spoken.pop_front()
	sink.call(line)
	line_spoken.emit(line)


func _now() -> float:
	return float(clock.call()) if clock.is_valid() else Time.get_ticks_msec() / 1000.0


func _compression() -> float:
	return float(compression.call()) if compression.is_valid() else SimClock.multiplier()
