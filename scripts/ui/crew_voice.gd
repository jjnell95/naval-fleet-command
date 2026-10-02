class_name CrewVoice
extends Node
## The crew you can hear. Command-screen events (an order acknowledged, a missile away, a torpedo
## in the water) become short spoken naval phrases through the operating system's text-to-speech.
## It never reads the radio line aloud: every spoken line is composed here from an event key and a
## few fields (a track number, a platform's name), with the wording in data/voice/phrases.json.
##
## Pacing: alerts (inbound missile, torpedo, own ship hit, unit lost) interrupt anything routine;
## routine lines wait their turn with at most one pending, at most one every ROUTINE_GAP_S, and are
## dropped once older than STALE_S of real time; above `routine_ceiling` time compression (1x
## unless the time ladder stops at 4x) only alerts are spoken.
##
## Safety: the speech sink is a Callable. Nothing here touches DisplayServer.tts_* unless
## use_os_speech() installed the operating system's sink, and Main only does that where speech is
## expected to work (web, macOS, Windows) or after the player turned voice on elsewhere. On Linux
## without speech-dispatcher every tts_* call logs an engine error, so a headless, scripted or test
## run never installs it at all.

signal line_spoken(line: Dictionary)

const PHRASES_PATH := "res://data/voice/phrases.json"
const EVENTS := [
	"order_ack", "attack_ack", "investigate_ack", "order_refused",
	"missile_away", "torpedo_away", "inbound_missile", "torpedo_inbound",
	"interceptor_kill", "target_destroyed", "attack_broken_off", "own_ship_hit", "unit_lost",
	"new_contact", "contact_hostile", "aircraft_rtb", "fire_out",
	"mission_won", "mission_lost",
]
## Spoken at once, cutting off anything routine.
const ALERT_EVENTS := ["inbound_missile", "torpedo_inbound", "own_ship_hit", "unit_lost"]
## The end of the mission is said whatever the time compression, but it does not cut anyone off.
const FINAL_EVENTS := ["mission_won", "mission_lost"]
const STALE_S := 4.0
const ROUTINE_GAP_S := 2.0
## The same alert inside this window is one call, not a stutter (a salvo is several detections).
const ALERT_REPEAT_S := 3.0
const MAX_SPOKEN_LOG := 24
const DIGITS := ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "niner"]
## Where speech-dispatcher's client library lives on the common Linux layouts. Godot loads it at
## start-up when text-to-speech is enabled; without it every tts_* call is an engine error.
const SPEECHD_LIBRARIES := [
	"/usr/lib/x86_64-linux-gnu/libspeechd.so.2", "/usr/lib/aarch64-linux-gnu/libspeechd.so.2",
	"/usr/lib64/libspeechd.so.2", "/usr/lib/libspeechd.so.2", "/usr/local/lib/libspeechd.so.2",
]
const SETTINGS_SECTION := "audio"
const SETTINGS_KEY := "voice"

## event -> Array[String]
var phrases: Dictionary = {}
## The player's choice. Nothing is spoken while it is off, and nothing reaches a sink that is not set.
var enabled := false
## func(line: Dictionary) -> void. `line` carries text, voice, volume, pitch, rate, interrupt.
var sink := Callable()
## func() -> bool: whether the sink is still speaking the last line.
var busy := Callable()
## func() -> void: silence the sink.
var stop_sink := Callable()
## func() -> float: real seconds. Tests drive it by hand.
var clock := Callable()
## func() -> float: the time-compression multiplier.
var compression := Callable()
## func() -> bool: true while the game's sound is muted (Ctrl+M); the crew falls silent with it.
var muted := Callable()
## Routine lines are spoken at this time compression or slower; faster, only alerts. 1x by
## default: at 5x and beyond a routine line is stale before it is finished. Main raises it to the
## ceiling when the ladder stops at 4x, where a watch is still slow enough to listen to.
var routine_ceiling := 1.0
## True only once use_os_speech() has installed the operating system as the sink.
var os_speech := false
## The newest lines handed to the sink, oldest first.
var spoken: Array[Dictionary] = []
var dropped_stale := 0
## Voice identifiers to choose from (English first). Filled lazily from the OS, or by a test.
var voices: PackedStringArray = []

var _pending: Dictionary = {}
var _last_spoken_s := -1000.0
var _last_alert_s: Dictionary = {}
var _counters: Dictionary = {}
var _voices_checked_s := -1000.0


func _init() -> void:
	phrases = load_phrases()


func _process(_delta: float) -> void:
	if not _pending.is_empty():
		_pump()


# --- Platform and availability ------------------------------------------------------------

## Voice starts on where the operating system is expected to speak without extra software.
static func default_on() -> bool:
	return OS.has_feature("web") or OS.get_name() in ["macOS", "Windows"]


## A test, a tool script or a scripted smoke run: nothing may reach the operating system.
static func automated_run() -> bool:
	var args := OS.get_cmdline_args()
	return DisplayServer.get_name() == "headless" or args.has("--script") or args.has("-s")


static func speech_dispatcher_installed() -> bool:
	for path: String in SPEECHD_LIBRARIES:
		if FileAccess.file_exists(path):
			return true
	return false


## Why the operating system's speech cannot be used here, or "" when it can. `explicit` is the
## player having turned voice on; without it only the platforms where it is on by default qualify.
static func os_speech_blocker(explicit: bool) -> String:
	if automated_run():
		return "Crew voice is silent in automated runs"
	if not bool(ProjectSettings.get_setting("audio/general/text_to_speech", false)):
		return "Text-to-speech is disabled in this build"
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return "This system offers no text-to-speech"
	if default_on():
		return ""
	if not explicit:
		return "Crew voice is off by default on this system"
	if OS.get_name() in ["Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD"] and not speech_dispatcher_installed():
		return "Crew voice needs speech-dispatcher on this system"
	return ""


## Installs the operating system's text-to-speech as the sink. Call only after os_speech_blocker()
## returned "".
func use_os_speech() -> void:
	os_speech = true
	sink = func(line: Dictionary) -> void:
		DisplayServer.tts_speak(line["text"], line["voice"], int(line["volume"]), float(line["pitch"]), float(line["rate"]), 0, bool(line["interrupt"]))
	busy = func() -> bool:
		return DisplayServer.tts_is_speaking()
	stop_sink = func() -> void:
		DisplayServer.tts_stop()


## Reads the player's stored choice (or the platform default) and installs the OS sink when that is
## safe. Returns the reason voice stayed silent, or "".
func configure_from_settings() -> String:
	var explicit := UserSettings.has_value(SETTINGS_SECTION, SETTINGS_KEY)
	enabled = bool(UserSettings.get_value(SETTINGS_SECTION, SETTINGS_KEY, default_on()))
	if not enabled or sink.is_valid():
		return ""
	var blocker := os_speech_blocker(explicit)
	if blocker == "":
		use_os_speech()
	return blocker


## The Actions palette and the CDS menu toggle. Returns the line for the radio's advice.
func toggle() -> String:
	if enabled:
		set_enabled(false)
		return "Crew voice off"
	if not sink.is_valid():
		var blocker := os_speech_blocker(true)
		if blocker == "":
			use_os_speech()
		elif not automated_run():
			return blocker
	set_enabled(true)
	return "Crew voice on"


func set_enabled(on: bool, persist := true) -> void:
	enabled = on
	if not on:
		stop()
	if persist:
		UserSettings.set_value(SETTINGS_SECTION, SETTINGS_KEY, on)


func stop() -> void:
	_pending = {}
	if stop_sink.is_valid():
		stop_sink.call()


# --- Phrases ------------------------------------------------------------------------------

static func load_phrases(path := PHRASES_PATH) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("CrewVoice: no phrase table at %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not (parsed as Dictionary).get("events") is Dictionary:
		push_warning("CrewVoice: phrase table %s is malformed" % path)
		return {}
	var out := {}
	var events: Dictionary = parsed["events"]
	for key: String in events:
		var variants: Array[String] = []
		for v: Variant in events[key]:
			variants.append(str(v))
		out[key] = variants
	return out


## "1003" -> "one zero zero three": track numbers are read digit by digit, as on a real net.
static func spoken_digits(number: String) -> String:
	var words := PackedStringArray()
	for ch in number:
		if ch >= "0" and ch <= "9":
			words.append(DIGITS[int(ch)])
	return " ".join(words)


## How a platform is named on the voice net: "USS Bulkeley (DDG 84)" -> "Bulkeley". The hull
## number and a leading upper-case prefix (USS, HMS, FS ...) are dropped.
static func spoken_name(callsign: String) -> String:
	var s := callsign
	var paren := s.find("(")
	if paren > 0:
		s = s.substr(0, paren)
	var words := s.strip_edges().split(" ", false)
	if words.size() > 1 and words[0].length() <= 5 and words[0] == words[0].to_upper() and words[0] != words[0].to_lower():
		words.remove_at(0)
	return " ".join(words)


## A stable number per speaker, so each ship keeps its own voice from run to run.
static func speaker_seed(speaker: Variant) -> int:
	if speaker is Unit:
		return ((speaker as Unit).id * 2654435761 + 97) & 0x7fffffff
	return 0


## Pitch, rate and volume for a speaker. The combat information centre (no speaker) is level.
static func voice_character(seed_value: int, alert: bool, has_speaker: bool) -> Dictionary:
	var pitch := 1.0
	var rate := 1.05
	if has_speaker:
		pitch = 0.88 + float(seed_value % 7) * 0.04
		rate = 1.0 + float(floori(seed_value / 7.0) % 4) * 0.05
	if alert:
		rate += 0.12
	return {"pitch": pitch, "rate": rate, "volume": 80 if alert else 65}


static func _track_text(value: Variant) -> String:
	if value is Track:
		return MapSymbols.track_number((value as Track).id)
	return str(value) if value != null else ""


## Builds the spoken line for an event without speaking it. Variants whose placeholders cannot be
## filled are skipped, and the choice rotates deterministically per event and speaker.
func compose(event: String, speaker: Variant = null, fields := {}) -> Dictionary:
	var variants: Array = phrases.get(event, [])
	if variants.is_empty():
		return {}
	var subs := {
		"track": spoken_digits(_track_text(fields.get("track"))),
		"name": spoken_name(str(fields.get("name", ""))),
	}
	var usable: Array = []
	for v: String in variants:
		var ok := true
		for key: String in subs:
			if v.contains("{%s}" % key) and str(subs[key]) == "":
				ok = false
		if ok:
			usable.append(v)
	if usable.is_empty():
		return {}
	var seed_value := speaker_seed(speaker)
	var n := int(_counters.get(event, 0))
	_counters[event] = n + 1
	var template: String = usable[(n + seed_value) % usable.size()]
	var phrase := template.format(subs)
	var who := spoken_name((speaker as Unit).callsign) if speaker is Unit else ""
	var text := phrase if who == "" or template.contains("{name}") else "%s, %s" % [who, phrase]
	var alert := event in ALERT_EVENTS
	var line := voice_character(seed_value, alert, speaker is Unit)
	line["event"] = event
	line["text"] = text
	line["alert"] = alert
	line["voice"] = _voice_for(seed_value)
	line["interrupt"] = alert
	return line


func _voice_for(seed_value: int) -> String:
	if os_speech and voices.is_empty() and _now() - _voices_checked_s > 5.0:
		# The browser fills its voice list a moment after start-up, so look again now and then.
		_voices_checked_s = _now()
		voices = DisplayServer.tts_get_voices_for_language("en")
	return voices[seed_value % voices.size()] if not voices.is_empty() else ""


# --- Speaking -----------------------------------------------------------------------------

## The one entry point Main uses. `speaker` is the own Unit that acts (or null for the combat
## information centre); `fields` may carry "track" (a Track or its number) and "name".
func say(event: String, speaker: Variant = null, fields := {}) -> void:
	if not enabled or not sink.is_valid() or (muted.is_valid() and bool(muted.call())):
		return
	var priority := event in ALERT_EVENTS or event in FINAL_EVENTS
	if not priority and _compression() > routine_ceiling + 1e-6:
		return
	var now := _now()
	if priority:
		if now - float(_last_alert_s.get(event, -1000.0)) < ALERT_REPEAT_S:
			return
		var line := compose(event, speaker, fields)
		if line.is_empty():
			return
		_last_alert_s[event] = now
		if event in ALERT_EVENTS:
			_pending = {}
		_emit(line)
		return
	var routine := compose(event, speaker, fields)
	if routine.is_empty():
		return
	routine["t"] = now
	_pending = routine  # at most one waits; the newest is the most relevant
	_pump()


func pending() -> Dictionary:
	return _pending


func _pump() -> void:
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
	if compression.is_valid():
		return float(compression.call())
	return SimClock.multiplier()
