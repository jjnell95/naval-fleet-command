extends Node
## Procedural sound. Every cue is synthesised at start-up into a small PCM buffer, so nothing is
## downloaded, nothing is lifted from anywhere, and the whole set costs a few hundred kilobytes
## of memory. Restrained by design: a console beeps, it does not score a film.

const RATE := 22050
const VOICES := 6

var enabled := true
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_played: Dictionary = {}


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
	return enabled
