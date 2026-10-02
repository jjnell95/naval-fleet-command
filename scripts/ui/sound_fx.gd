extends Node
## Procedural sound. Every cue is synthesised at start-up into a small PCM buffer, so nothing is
## downloaded, nothing is lifted from anywhere, and the whole set costs a few hundred kilobytes
## of memory. Restrained by design: a console beeps, it does not score a film.

const RATE := 22050
const VOICES := 6
## The ambient bed is low-passed sea and machinery, so half the cue rate is plenty.
const AMBIENT_RATE := 11025
const SILENT_DB := -80.0
## Sea wash from a flat calm to a high sea (Detection.sea_state 0..6).
const SEA_DB_CALM := -38.0
const SEA_DB_HIGH := -17.0
## Machinery under the hooked platform, by kind of hum.
const HUM_DB := {"engine": -27.0, "boat": -33.0, "rotor": -24.0, "jet": -29.0}
## How far the bed drops while a cue plays, and how fast levels move (dB per second).
const DUCK_DB := 9.0
const SLEW_DB_S := 36.0
const AMBIENT_SETTINGS_KEY := "ambient"

var enabled := true
## The ambient bed's own switch, under `enabled` (Ctrl+M silences everything).
var ambient_enabled := true
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_played: Dictionary = {}
var _ambient: Dictionary = {}  # name -> looping AudioStreamWAV
var _sea_player: AudioStreamPlayer
var _hum_player: AudioStreamPlayer
var _ambient_active := false
var _sea_state := 0
var _hum := ""


func _ready() -> void:
	_streams["ping"] = _make(func(t: float, d: float) -> float:
		return sin(TAU * 1450.0 * t) * exp(-t * 6.0) * 0.5 + sin(TAU * 1430.0 * t) * exp(-t * 3.0) * 0.2, 1.4)
	_streams["launch"] = _make(func(t: float, d: float) -> float:
		var env := minf(t * 12.0, 1.0) * exp(-t * 4.0)
		return (randf() * 2.0 - 1.0) * env * 0.55, 1.0)
	_streams["alarm"] = _make(func(t: float, d: float) -> float:
		var f := 880.0 if fmod(t, 0.36) < 0.18 else 660.0
		return sin(TAU * f * t) * 0.32 * (1.0 if fmod(t, 0.36) < 0.16 else 0.0), 1.1)
	_streams["torpedo"] = _make(func(t: float, d: float) -> float:
		var f := 520.0 + 260.0 * fmod(t * 2.0, 1.0)
		return sin(TAU * f * t) * 0.3 * (1.0 if fmod(t, 0.5) < 0.42 else 0.0), 1.5)
	_streams["impact"] = _make(func(t: float, d: float) -> float:
		var env := exp(-t * 5.0)
		return (sin(TAU * 60.0 * t) * 0.6 + (randf() * 2.0 - 1.0) * 0.35) * env, 1.3)
	_streams["intercept"] = _make(func(t: float, d: float) -> float:
		var env := exp(-t * 9.0)
		return (sin(TAU * 220.0 * t) * 0.35 + (randf() * 2.0 - 1.0) * 0.3) * env, 0.6)
	_streams["contact"] = _make(func(t: float, d: float) -> float:
		var f := 1200.0 if t < 0.09 else 1600.0
		return sin(TAU * f * t) * 0.28 * (1.0 if fmod(t, 0.09) < 0.075 else 0.0), 0.18)
	_streams["classified"] = _make(func(t: float, d: float) -> float:
		return sin(TAU * 980.0 * t) * 0.25 * exp(-t * 8.0), 0.35)
	_streams["click"] = _make(func(t: float, d: float) -> float:
		return sin(TAU * 2200.0 * t) * 0.22 * exp(-t * 60.0), 0.08)
	_streams["victory"] = _make(func(t: float, d: float) -> float:
		var notes := [523.0, 659.0, 784.0, 1046.0]
		var f: float = notes[mini(int(t / 0.22), 3)]
		return sin(TAU * f * t) * 0.3 * exp(-fmod(t, 0.22) * 6.0), 0.95)
	_streams["defeat"] = _make(func(t: float, d: float) -> float:
		var notes := [392.0, 349.0, 311.0]
		var f: float = notes[mini(int(t / 0.3), 2)]
		return sin(TAU * f * t) * 0.3 * exp(-fmod(t, 0.3) * 4.0), 0.95)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		add_child(p)
		_players.append(p)
	_build_ambient()
	ambient_enabled = bool(UserSettings.get_value("audio", AMBIENT_SETTINGS_KEY, true))


func _make(fn: Callable, seconds: float) -> AudioStreamWAV:
	var n := int(RATE * seconds)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var v: float = clampf(fn.call(t, seconds), -1.0, 1.0)
		# A short fade at both ends keeps the buffer from clicking.
		var fade := minf(minf(float(i) / 200.0, float(n - i) / 400.0), 1.0)
		var s := int(v * fade * 32767.0)
		bytes.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav


## Plays a cue. Identical cues inside `min_gap_s` are dropped so a salvo does not stutter.
func play(cue: String, min_gap_s := 0.15) -> void:
	if not enabled or not _streams.has(cue):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(cue, -10.0)) < min_gap_s:
		return
	_last_played[cue] = now
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[cue]
	p.play()


func toggle() -> bool:
	enabled = not enabled
	if not enabled:
		for p in _players:
			p.stop()
		_stop_ambient()
	return enabled


# --- Ambient bed ----------------------------------------------------------------------------
# A sea-and-wind wash whose level follows the sea state, and under it the hum of whatever the
# player has hooked: a ship's machinery, a boat's quieter plant, a helicopter's rotor or a jet.
# Two looping players, ducked while a cue plays, silent while the clock is paused.

## Main reports the scene every half second: whether a mission is on the command screen, the sea
## state and the hum for the hooked platform ("", engine, boat, rotor, jet).
func set_ambient(active: bool, sea_state: int, hum: String) -> void:
	_ambient_active = active
	_sea_state = clampi(sea_state, 0, 6)
	_hum = hum if HUM_DB.has(hum) else ""


func toggle_ambient() -> bool:
	set_ambient_enabled(not ambient_enabled)
	return ambient_enabled


## `persist` saves the choice; a saved engagement's sound is played without becoming the preference.
func set_ambient_enabled(on: bool, persist := true) -> void:
	ambient_enabled = on
	if persist:
		UserSettings.set_value("audio", AMBIENT_SETTINGS_KEY, ambient_enabled)
	if not ambient_enabled:
		_stop_ambient()


## The hum for a hooked platform, from what the player already sees of their own unit.
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


## Target levels in dB for the sea (x) and the hum (y); SILENT_DB when that part should be quiet.
func ambient_targets() -> Vector2:
	if not enabled or not ambient_enabled or not _ambient_active or SimClock.paused:
		return Vector2(SILENT_DB, SILENT_DB)
	var duck := DUCK_DB if _cue_playing() else 0.0
	var sea := lerpf(SEA_DB_CALM, SEA_DB_HIGH, float(_sea_state) / 6.0) - duck
	var hum: float = float(HUM_DB[_hum]) - duck if _hum != "" else SILENT_DB
	return Vector2(sea, hum)


func ambient_playing() -> bool:
	return (_sea_player != null and _sea_player.playing) or (_hum_player != null and _hum_player.playing)


func _process(delta: float) -> void:
	if _sea_player == null:
		return
	var target := ambient_targets()
	if target.x <= SILENT_DB and target.y <= SILENT_DB and not ambient_playing():
		return
	_slew(_sea_player, target.x, delta)
	var hum_stream: String = "engine" if _hum == "boat" else _hum
	if _hum != "" and _hum_player.stream != _ambient[hum_stream]:
		_hum_player.stop()
		_hum_player.stream = _ambient[hum_stream]
		_hum_player.volume_db = SILENT_DB
	_hum_player.pitch_scale = 0.7 if _hum == "boat" else 1.0
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
	for p in _players:
		if p.playing:
			return true
	return false


func _build_ambient() -> void:
	# A private generator: the bed must not move the global random state the cues share.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1990
	var sea := _loop(3.0, rng, func(t: float, low: float, high: float) -> float:
		var swell := 0.55 + 0.3 * sin(TAU * t / 3.0) + 0.15 * sin(TAU * t * 2.0 / 3.0)
		return (low * 0.75 + high * 0.35) * swell)
	var engine := _loop(1.0, rng, func(t: float, low: float, _high: float) -> float:
		var shaft := 0.85 + 0.15 * sin(TAU * 4.0 * t)
		return (sin(TAU * 48.0 * t) * 0.5 + sin(TAU * 96.0 * t) * 0.28 + sin(TAU * 144.0 * t) * 0.12) * shaft + low * 0.25)
	var rotor := _loop(1.0, rng, func(t: float, low: float, _high: float) -> float:
		var blade := pow(0.5 + 0.5 * sin(TAU * 18.0 * t), 6.0)
		return (low * 0.6 + sin(TAU * 72.0 * t) * 0.2) * (0.35 + 0.65 * blade) + sin(TAU * 36.0 * t) * 0.15)
	var jet := _loop(1.0, rng, func(t: float, low: float, high: float) -> float:
		return (high - low) * 0.8 + low * 0.3 + sin(TAU * 1700.0 * t) * 0.03)
	_ambient = {"sea": sea, "engine": engine, "rotor": rotor, "jet": jet}
	_sea_player = AudioStreamPlayer.new()
	_hum_player = AudioStreamPlayer.new()
	for p: AudioStreamPlayer in [_sea_player, _hum_player]:
		p.volume_db = SILENT_DB
		add_child(p)
	_sea_player.stream = sea


## A seamless loop of `seconds`. `fn(t, low, high)` shapes two low-passed noises (a dark one near
## 300 Hz and a brighter one near 1.5 kHz); the tail is cross-faded into the head so the seam is
## inaudible. Periodic terms should complete whole cycles in `seconds`.
func _loop(seconds: float, rng: RandomNumberGenerator, fn: Callable) -> AudioStreamWAV:
	var n := int(AMBIENT_RATE * seconds)
	var xf := int(AMBIENT_RATE * minf(0.25, seconds * 0.25))
	var raw := PackedFloat32Array()
	raw.resize(n + xf)
	var low := 0.0
	var high := 0.0
	var a_low := 1.0 - exp(-TAU * 300.0 / AMBIENT_RATE)
	var a_high := 1.0 - exp(-TAU * 1500.0 / AMBIENT_RATE)
	var peak := 0.0001
	for i in n + xf:
		var white := rng.randf() * 2.0 - 1.0
		low += (white - low) * a_low
		high += (white - high) * a_high
		var v: float = fn.call(float(i % n) / AMBIENT_RATE, low * 3.0, high * 1.5)
		raw[i] = v
		peak = maxf(peak, absf(v))
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var gain := 0.8 / peak
	for i in n:
		var v := raw[i]
		if i < xf:
			var w := float(i) / xf
			v = raw[i] * w + raw[n + i] * (1.0 - w)
		bytes.encode_s16(i * 2, int(clampf(v * gain, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = AMBIENT_RATE
	wav.stereo = false
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav
