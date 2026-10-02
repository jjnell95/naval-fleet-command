extends TestCase
## The gameplay options: the Normal and Classic presets and their persistence, the time ladder and
## its ceiling, manual missile defence and the commander's intercept, engagement after hostile
## identification, the 1990 campaign's start, and the clock that drops to real time only for what
## the player's side could see. Preferences go to a scratch file, never the player's own.

const SCRATCH_SETTINGS := "user://test_game_options_settings.cfg"
const CARRIER_QUAL := "res://data/scenarios/carrier_qualification.json"


func _with_scratch_settings(fn: Callable) -> void:
	var saved_path := UserSettings.path
	var saved_writable := UserSettings.writable
	UserSettings.path = SCRATCH_SETTINGS
	UserSettings.writable = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_SETTINGS))
	fn.call()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_SETTINGS))
	UserSettings.path = saved_path
	UserSettings.writable = saved_writable


# --- Presets and persistence -------------------------------------------------------------

func test_normal_is_the_game_as_it_was_and_classic_is_the_late_nineties_rule_set() -> void:
	var normal := GameOptions.normal()
	assert_eq(normal.preset(), GameOptions.NORMAL)
	assert_eq(Array(normal.time_scales), Array(SimClock.SPEEDS), "Normal keeps the whole ladder to 60x")
	assert_eq(normal.missile_defence, GameOptions.DEFENCE_AUTO)
	assert_true(not normal.engage_on_hostile_id)
	assert_eq(GameOptions.normal(true, false).preset(), GameOptions.NORMAL, "Normal leaves sound as the player set it")
	var classic := GameOptions.classic()
	assert_eq(classic.preset(), GameOptions.CLASSIC)
	assert_eq(Array(classic.time_scales), [1.0, 2.0, 4.0], "Classic stops at 4x")
	assert_eq(classic.ceiling(), 4.0)
	assert_true(classic.manual_missile_defence())
	assert_true(classic.engage_on_hostile_id)
	assert_true(classic.voice and classic.ambient, "Classic has the crew and the sea audible")
	assert_eq(classic.label(), "CLASSIC 4×")
	assert_eq(normal.label(), "NORMAL")


func test_changing_any_one_option_makes_the_preset_custom() -> void:
	var changes := {
		"time": func(o: GameOptions) -> void: o.time_scales = GameOptions.scales_to(10.0),
		"defence": func(o: GameOptions) -> void: o.missile_defence = GameOptions.DEFENCE_AUTO,
		"engage": func(o: GameOptions) -> void: o.engage_on_hostile_id = false,
		"voice": func(o: GameOptions) -> void: o.voice = false,
		"ambient": func(o: GameOptions) -> void: o.ambient = false,
	}
	for key: String in changes:
		var o := GameOptions.classic()
		changes[key].call(o)
		assert_eq(o.preset(), GameOptions.CUSTOM, "Classic with %s changed" % key)
	var manual_normal := GameOptions.normal()
	manual_normal.missile_defence = GameOptions.DEFENCE_MANUAL
	assert_eq(manual_normal.preset(), GameOptions.CUSTOM)
	assert_eq(manual_normal.label(), "CUSTOM 60×")
	var engage_normal := GameOptions.normal()
	engage_normal.engage_on_hostile_id = true
	assert_eq(engage_normal.preset(), GameOptions.CUSTOM)


func test_each_option_toggles_on_its_own_and_the_classic_ladder_is_one_constant() -> void:
	var o := GameOptions.normal(false, true)
	for key: String in GameOptions.OPTION_KEYS:
		if key == "":
			continue
		var flipped := o.toggled(key)
		assert_true(flipped.option_on(key) != o.option_on(key), "%s switches" % key)
		for other: String in GameOptions.OPTION_KEYS:
			if other != "" and other != key:
				assert_eq(flipped.option_on(other), o.option_on(other), "%s leaves %s alone" % [key, other])
		assert_true(flipped.toggled(key).equals(o), "%s switches back" % key)
	# Every Classic number is read from CLASSIC_SCALES, so a different ceiling is a one-line edit.
	assert_eq(GameOptions.CLASSIC_CEILING, GameOptions.CLASSIC_SCALES[GameOptions.CLASSIC_SCALES.size() - 1])
	assert_true(GameOptions.valid_scales(GameOptions.CLASSIC_SCALES))
	assert_eq(Array(o.toggled("ceiling").time_scales), Array(GameOptions.CLASSIC_SCALES), "the ceiling option is the Classic ladder")
	assert_eq(GameOptions.option_text("ceiling"), "Time ceiling 4× (1×, 2×, 4×)")
	assert_true(GameOptions.preset_description(GameOptions.CLASSIC).begins_with("4× time ceiling"))
	var classic := GameOptions.classic()
	assert_eq(classic.summary(), "4× ceiling · manual missile defence · engage after identification")
	assert_eq(GameOptions.normal().summary(), "60× ceiling · automatic missile defence · attack on orders")
	assert_eq(classic.toggled("engage_on_id").toggled("engage_on_id").preset(), GameOptions.CLASSIC)


func test_options_round_trip_and_tolerate_damaged_data() -> void:
	var classic := GameOptions.classic()
	var copy := GameOptions.from_dict(classic.to_dict())
	assert_true(copy.equals(classic), "a saved engagement restores exactly the options it was fought under")
	assert_eq(copy.preset(), GameOptions.CLASSIC)
	assert_eq(int(classic.to_dict()["version"]), GameOptions.VERSION)
	var junk := GameOptions.from_dict({"time_scales": [2.0, 1.0], "missile_defence": "sometimes", "engage_on_hostile_id": "yes", "voice": 1, "ambient": null})
	assert_eq(Array(junk.time_scales), Array(SimClock.SPEEDS), "a ladder that does not start at real time is refused")
	assert_eq(junk.missile_defence, GameOptions.DEFENCE_AUTO)
	assert_true(not junk.engage_on_hostile_id, "only a real true turns engagement on")
	assert_true(not junk.voice)
	assert_true(junk.ambient)
	assert_eq(GameOptions.from_dict({}).preset(), GameOptions.NORMAL, "nothing stored is Normal")
	for bad: Array in [[], [1.0, 2.0, 2.0], [1.0, 120.0], [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0]]:
		assert_true(not GameOptions.valid_scales(bad), "refused ladder %s" % [bad])
	assert_eq(Array(GameOptions.from_dict({"time_scales": [1, 2, 4]}).time_scales), [1.0, 2.0, 4.0], "whole numbers from a config file are read")


func test_the_preference_persists_in_the_gameplay_section_and_only_where_writable() -> void:
	_with_scratch_settings(func() -> void:
		assert_eq(GameOptions.load_preferred().preset(), GameOptions.NORMAL, "a fresh player starts on Normal")
		assert_true(GameOptions.save_preferred(GameOptions.classic()))
		var back := GameOptions.load_preferred()
		assert_eq(back.preset(), GameOptions.CLASSIC, "Classic survives a restart")
		assert_eq(str(UserSettings.get_value("gameplay", "missile_defence", "")), "manual")
		assert_eq(bool(UserSettings.get_value("audio", "voice", CrewVoice.default_on())), true, "voice keeps its own key")
		assert_eq(bool(UserSettings.get_value("audio", "ambient", true)), true, "ambient keeps its own key")
		var quiet := GameOptions.classic()
		quiet.ambient = false
		GameOptions.save_preferred(quiet)
		assert_eq(UserSettings.get_value("audio", "ambient", true), false, "a changed ambient choice is written where SoundFx reads it")
		assert_eq(GameOptions.load_preferred().preset(), GameOptions.CUSTOM)
		GameOptions.save_preferred(GameOptions.classic())
		var custom := GameOptions.classic()
		custom.missile_defence = GameOptions.DEFENCE_AUTO
		GameOptions.save_preferred(custom)
		assert_eq(GameOptions.load_preferred().preset(), GameOptions.CUSTOM)
		UserSettings.writable = false
		assert_true(not GameOptions.save_preferred(GameOptions.normal()), "a scripted run never saves")
		assert_eq(GameOptions.load_preferred().preset(), GameOptions.CUSTOM, "and the stored preference is untouched")
		UserSettings.writable = true)


func test_choosing_normal_does_not_make_a_platform_voice_default_explicit() -> void:
	_with_scratch_settings(func() -> void:
		GameOptions.save_preferred(GameOptions.normal(CrewVoice.default_on(), true))
		assert_true(not UserSettings.has_value("audio", "voice"), "an unchanged default stays a default")
		assert_true(not UserSettings.has_value("audio", "ambient"))
		assert_true(UserSettings.has_value("gameplay", "time_scales")))


# --- The time ladder ---------------------------------------------------------------------

func test_menus_and_the_key_board_offer_only_the_ladder_in_use() -> void:
	var saved := SimClock.speeds()
	var saved_index := SimClock.speed_index
	SimClock.set_ceiling(4.0)
	var items := CommandBar.time_items()
	assert_eq(items.size(), 3, "1x, 2x and 4x")
	assert_true(str(items[2]["text"]).begins_with("4×") and str(items[2]["text"]).contains("Ceiling"), items[2]["text"])
	assert_eq(items[2]["action"]["id"], "speed_2")
	var rows := " | ".join(KeyCommands.all_rows())
	assert_true(rows.contains("1 - 3: Time scale 1x, 2x, 4x (the ceiling)"), rows)
	assert_true(not rows.contains("60x"))
	SimClock.set_speeds(saved)
	SimClock.set_speed_index(saved_index)
	assert_eq(CommandBar.time_items().size(), 6, "Normal: six steps again")
	assert_true(" | ".join(KeyCommands.all_rows()).contains("1 - 6: Time scale 1x, 2x, 5x, 10x, 30x, 60x"))
