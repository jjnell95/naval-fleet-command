class_name GameOptions
extends RefCounted
## The gameplay options: how fast the watch may run, whether ships shoot down inbound missiles by
## themselves, whether a ship that identifies a contact as hostile goes on to attack it, and the
## crew voice and ambient sound. Plain data, so a saved engagement can carry the options it was
## fought under (to_dict / from_dict) without touching the player's own preference.
##
## Two presets. NORMAL is this game as it has always played: the full time ladder to 60×,
## automatic missile defence and no engagement without an order; it says nothing about sound, which
## stays as the player set it. CLASSIC is the late-1990s rule set: a 4× ceiling, missile defence
## left to the commander, ships that engage what they identify as hostile (within their rules of
## engagement), and the crew and the sea audible. Any other combination is CUSTOM. The preset is
## worked out from the values, never stored on its own, so it cannot disagree with them.
##
## The simulation never sees this object. Main copies what the simulation needs into it as orders
## and plain data, and the preferences live in UserSettings, which is presentation.

const VERSION := 1
const NORMAL := "normal"
const CLASSIC := "classic"
const CUSTOM := "custom"
const DEFENCE_AUTO := "auto"
const DEFENCE_MANUAL := "manual"
## The UserSettings section for the gameplay options. Voice and ambient keep their own keys in
## "audio", where CrewVoice and SoundFx have always kept them.
const SECTION := "gameplay"
const AUDIO_SECTION := "audio"
const NORMAL_SCALES: Array[float] = [1.0, 2.0, 5.0, 10.0, 30.0, 60.0]  # SimClock.SPEEDS
## The Classic time ladder, slowest first; its last step is the ceiling, and every menu, key board
## and description reads it from here, so another ceiling (an earlier brief also proposed 8×) is
## the one-line change [1.0, 2.0, 4.0, 8.0].
const CLASSIC_SCALES: Array[float] = [1.0, 2.0, 4.0]
const CLASSIC_CEILING: float = CLASSIC_SCALES[-1]
## The single options, in menu order; "" is a separator. Shared by the desk's OPTIONS menu, the
## chip's menu and the CDS Gameplay submenu; option_text and option_tooltip give their words.
const OPTION_KEYS := ["ceiling", "manual_defence", "engage_on_id", "", "voice", "ambient"]

var time_scales: Array[float] = NORMAL_SCALES.duplicate()
var missile_defence := DEFENCE_AUTO
var engage_on_hostile_id := false
var voice := false
var ambient := true


static func normal(voice_on := false, ambient_on := true) -> GameOptions:
	var o := GameOptions.new()
	o.voice = voice_on
	o.ambient = ambient_on
	return o


static func classic() -> GameOptions:
	var o := GameOptions.new()
	o.time_scales = CLASSIC_SCALES.duplicate()
	o.missile_defence = DEFENCE_MANUAL
	o.engage_on_hostile_id = true
	o.voice = true
	o.ambient = true
	return o


## A preset by name, with the sound the player has now where the preset leaves sound alone.
static func preset_named(name: String, voice_now: bool, ambient_now: bool) -> GameOptions:
	if name == CLASSIC:
		return classic()
	return normal(voice_now, ambient_now)


## What a preset is, in one line, for the desk's buttons, the menus and the Actions palette. Rules
## only, never a year: Classic is a way of playing any operation, not a period.
static func preset_description(name: String) -> String:
	if name == CLASSIC:
		return "%s time ceiling, missile defence on your orders (X), ships that engage contacts they identify as hostile within the rules of engagement, crew voice and ambient sound on" % _times(CLASSIC_CEILING)
	return "The full time ladder to %s, automatic missile defence, ships that attack only when ordered" % _times(NORMAL_SCALES[-1])


## The menu text of a single option.
static func option_text(key: String) -> String:
	match key:
		"ceiling":
			return "Time ceiling %s (%s)" % [_times(CLASSIC_CEILING), ladder_text(CLASSIC_SCALES)]
		"manual_defence":
			return "Manual missile defence (X engages inbound)"
		"engage_on_id":
			return "Engage after hostile identification"
		"voice":
			return "Crew voice"
		"ambient":
			return "Ambient sea and machinery"
	return ""


## What a single option does, for its tooltip.
static func option_tooltip(key: String) -> String:
	match key:
		"ceiling":
			return "Only %s; off, the ladder runs to %s." % [ladder_text(CLASSIC_SCALES), _times(NORMAL_SCALES[-1])]
		"manual_defence":
			return "SAMs engage inbound missiles only when ordered (X or right-click the round); close-in guns, chaff and flares keep their own settings."
		"engage_on_id":
			return "A ship or aircraft whose investigation finds a hostile attacks it, within its rules of engagement. Never a neutral or an unknown; reconnaissance never fires."
		"voice":
			return "Spoken crew reports through the system's text-to-speech."
		"ambient":
			return "Sea wash by sea state and the hooked platform's engine or rotor."
	return ""


## Whether a single option is on.
func option_on(key: String) -> bool:
	match key:
		"ceiling":
			return ceiling() <= CLASSIC_CEILING + 1e-6
		"manual_defence":
			return manual_missile_defence()
		"engage_on_id":
			return engage_on_hostile_id
		"voice":
			return voice
		"ambient":
			return ambient
	return false


## A copy with one option switched; the preset follows from the values.
func toggled(key: String) -> GameOptions:
	var o := duplicate_options()
	match key:
		"ceiling":
			o.time_scales = NORMAL_SCALES.duplicate() if option_on("ceiling") else CLASSIC_SCALES.duplicate()
		"manual_defence":
			o.missile_defence = DEFENCE_AUTO if manual_missile_defence() else DEFENCE_MANUAL
		"engage_on_id":
			o.engage_on_hostile_id = not engage_on_hostile_id
		"voice":
			o.voice = not voice
		"ambient":
			o.ambient = not ambient
	return o


## NORMAL, CLASSIC or CUSTOM, from the values.
func preset() -> String:
	var rules_normal := _same_scales(time_scales, NORMAL_SCALES) and missile_defence == DEFENCE_AUTO and not engage_on_hostile_id
	if rules_normal:
		return NORMAL
	if _same_scales(time_scales, CLASSIC_SCALES) and missile_defence == DEFENCE_MANUAL and engage_on_hostile_id and voice and ambient:
		return CLASSIC
	return CUSTOM


func ceiling() -> float:
	return time_scales[time_scales.size() - 1] if not time_scales.is_empty() else 1.0


func manual_missile_defence() -> bool:
	return missile_defence == DEFENCE_MANUAL


## The chip on the command bar: "NORMAL", "CLASSIC 4×" or "CUSTOM 10×".
func label() -> String:
	match preset():
		NORMAL:
			return "NORMAL"
		CLASSIC:
			return "CLASSIC %d×" % int(ceiling())
	return "CUSTOM %d×" % int(ceiling())


## "4× ceiling · manual missile defence · engage after identification" and the like: the rules in
## one line, for the desk and the radio (the preset's name is shown beside it).
func summary() -> String:
	var parts := PackedStringArray()
	parts.append("%s ceiling" % _times(ceiling()))
	parts.append("manual missile defence" if manual_missile_defence() else "automatic missile defence")
	parts.append("engage after identification" if engage_on_hostile_id else "attack on orders")
	return " · ".join(parts)


## One line per option, for the chip's tooltip, the desk and the briefing.
func summary_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("Time: up to %d× (%s)" % [int(ceiling()), ", ".join(_scale_names())])
	out.append("Missile defence: %s" % ("manual — ships fire SAMs only when ordered (X); close-in guns stay automatic" if manual_missile_defence() else "automatic"))
	out.append("Engage after hostile identification: %s" % ("on, within the rules of engagement" if engage_on_hostile_id else "off"))
	out.append("Crew voice %s · ambient sound %s" % ["on" if voice else "off", "on" if ambient else "off"])
	return out


func duplicate_options() -> GameOptions:
	return GameOptions.from_dict(to_dict())


func equals(other: GameOptions) -> bool:
	return other != null and to_dict() == other.to_dict()


func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"preset": preset(),
		"time_scales": Array(time_scales),
		"missile_defence": missile_defence,
		"engage_on_hostile_id": engage_on_hostile_id,
		"voice": voice,
		"ambient": ambient,
	}


## Tolerant of anything missing or damaged: each value falls back to Normal's, and a time ladder
## the clock would refuse (see SimClock.valid_ladder) is the Normal one. A
## stored "preset" is informational; the values decide.
static func from_dict(d: Dictionary) -> GameOptions:
	var o := GameOptions.new()
	var scales = d.get("time_scales", [])
	if typeof(scales) in [TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY]:
		var clean: Array[float] = []
		for v in scales:
			if typeof(v) in [TYPE_INT, TYPE_FLOAT]:
				clean.append(float(v))
		if valid_scales(clean):
			o.time_scales = clean
	var defence := str(d.get("missile_defence", DEFENCE_AUTO))
	o.missile_defence = defence if defence in [DEFENCE_AUTO, DEFENCE_MANUAL] else DEFENCE_AUTO
	o.engage_on_hostile_id = _flag(d, "engage_on_hostile_id", false)
	o.voice = _flag(d, "voice", false)
	o.ambient = _flag(d, "ambient", true)
	return o


## A switch is a real bool or its fallback: "yes", 1 or null never turns anything on.
static func _flag(d: Dictionary, key: String, fallback: bool) -> bool:
	var v = d.get(key, fallback)
	return v if typeof(v) == TYPE_BOOL else fallback


## The clock's own rule: real time first, rising, at most one step per number key (1 to 6).
static func valid_scales(list: Array) -> bool:
	return SimClock.valid_ladder(list)


## The Normal ladder up to a ceiling, with the ceiling as its last step: 4 gives 1×, 2×, 4×.
static func scales_to(ceiling_x: float) -> Array[float]:
	return SimClock.ladder_to(ceiling_x)


# --- The player's preference ---------------------------------------------------------------

## The player's stored options. Sound comes from the keys CrewVoice and SoundFx already use, with
## their defaults: voice on where the system speaks out of the box, ambient on.
static func load_preferred() -> GameOptions:
	var d := {
		"time_scales": UserSettings.get_value(SECTION, "time_scales", NORMAL_SCALES),
		"missile_defence": UserSettings.get_value(SECTION, "missile_defence", DEFENCE_AUTO),
		"engage_on_hostile_id": UserSettings.get_value(SECTION, "engage_on_hostile_id", false),
		"voice": UserSettings.get_value(AUDIO_SECTION, CrewVoice.SETTINGS_KEY, CrewVoice.default_on()),
		"ambient": UserSettings.get_value(AUDIO_SECTION, SoundFx.AMBIENT_SETTINGS_KEY, true),
	}
	return from_dict(d)


## Saves these options as the player's preference. A scripted run's settings are read-only
## (UserSettings.writable) and nothing is written. Voice and ambient are written only where they
## differ from what is stored, so choosing a preset never turns a platform default into an
## explicit choice it was not.
static func save_preferred(o: GameOptions) -> bool:
	if not UserSettings.writable:
		return false
	var ok := UserSettings.set_value(SECTION, "version", VERSION)
	ok = UserSettings.set_value(SECTION, "preset", o.preset()) and ok
	ok = UserSettings.set_value(SECTION, "time_scales", Array(o.time_scales)) and ok
	ok = UserSettings.set_value(SECTION, "missile_defence", o.missile_defence) and ok
	ok = UserSettings.set_value(SECTION, "engage_on_hostile_id", o.engage_on_hostile_id) and ok
	if bool(UserSettings.get_value(AUDIO_SECTION, CrewVoice.SETTINGS_KEY, CrewVoice.default_on())) != o.voice:
		ok = UserSettings.set_value(AUDIO_SECTION, CrewVoice.SETTINGS_KEY, o.voice) and ok
	if bool(UserSettings.get_value(AUDIO_SECTION, SoundFx.AMBIENT_SETTINGS_KEY, true)) != o.ambient:
		ok = UserSettings.set_value(AUDIO_SECTION, SoundFx.AMBIENT_SETTINGS_KEY, o.ambient) and ok
	return ok


func _scale_names() -> PackedStringArray:
	var out := PackedStringArray()
	for v in time_scales:
		out.append(_times(v))
	return out


## "1×, 2×, 4×".
static func ladder_text(list: Array) -> String:
	var out := PackedStringArray()
	for v in list:
		out.append(_times(float(v)))
	return ", ".join(out)


static func _times(v: float) -> String:
	return "%d×" % int(v)


static func _same_scales(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not is_equal_approx(float(a[i]), float(b[i])):
			return false
	return true
