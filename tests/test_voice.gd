extends TestCase
## The crew you can hear: phrase table, spoken track numbers, pacing (alerts pre-empt, stale and
## compressed routine lines are dropped), interface advice that is never spoken or journaled, the
## ambient bed and the preferences file. No test here may reach the operating system's speech.

const SCRATCH_SETTINGS := "user://test_voice_settings.cfg"

var _now := 100.0
var _speed := 1.0
var _speaking := false
var _heard: Array[Dictionary] = []


func _voice() -> CrewVoice:
	_now = 100.0
	_speed = 1.0
	_speaking = false
	_heard.clear()
	var v := CrewVoice.new()
	v.clock = func() -> float: return _now
	v.compression = func() -> float: return _speed
	v.busy = func() -> bool: return _speaking
	v.sink = func(line: Dictionary) -> void: _heard.append(line)
	v.enabled = true
	return v


func _ship(id: int, callsign := "USS Bulkeley (DDG 84)") -> Unit:
	var u := Unit.new()
	u.id = id
	u.spec = DataDB.platform("usn_ddg_burke_iii")
	u.faction = "BLUE"
	u.callsign = callsign
	return u


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


func test_phrase_table_has_two_variants_for_every_event() -> void:
	var table := CrewVoice.load_phrases()
	for event: String in CrewVoice.EVENTS:
		var variants: Array = table.get(event, [])
		assert_true(variants.size() >= 2, "%s has at least two variants" % event)
		var plain := variants.filter(func(v: String) -> bool: return not v.contains("{"))
		assert_true(not plain.is_empty(), "%s can be spoken without a track or a name" % event)
		for v: String in variants:
			assert_true(v.strip_edges() != "", "%s has no empty variant" % event)
	for event: String in table:
		assert_true(CrewVoice.EVENTS.has(event), "the table holds only known events (%s)" % event)
	for event: String in CrewVoice.ALERT_EVENTS:
		assert_true(CrewVoice.EVENTS.has(event))


func test_track_numbers_are_spoken_digit_by_digit() -> void:
	assert_eq(CrewVoice.spoken_digits("1003"), "one zero zero three")
	assert_eq(CrewVoice.spoken_digits("0917"), "zero niner one seven")
	assert_eq(CrewVoice.spoken_digits(""), "")
	var t := Track.new()
	t.id = "T1003"
	var v := _voice()
	var heard_numbers := 0
	for i in 6:
		var line := v.compose("new_contact", null, {"track": t})
		assert_true(not str(line["text"]).contains("1003"), "never the numerals")
		if str(line["text"]).contains("track one zero zero three"):
			heard_numbers += 1
	assert_true(heard_numbers > 0, "the track is named digit by digit")
	var bare := v.compose("new_contact", null, {"track": null})
	assert_true(not str(bare["text"]).contains("{") and not str(bare["text"]).contains("track ."), "an unknown track falls back to a plain phrase")
	v.free()


func test_speaker_names_and_character_are_stable_per_unit() -> void:
	assert_eq(CrewVoice.spoken_name("USS Bulkeley (DDG 84)"), "Bulkeley")
	assert_eq(CrewVoice.spoken_name("HMS Iron Duke (F234)"), "Iron Duke")
	assert_eq(CrewVoice.spoken_name("Admiral Gorshkov"), "Admiral Gorshkov")
	var v := _voice()
	var a := v.compose("missile_away", _ship(3))
	var b := v.compose("missile_away", _ship(3))
	assert_eq(a["pitch"], b["pitch"], "a ship keeps its pitch")
	assert_eq(a["rate"], b["rate"], "and its rate")
	assert_true(str(a["text"]).begins_with("Bulkeley, "), "the unit that acts is the speaker")
	var characters := {}
	for id in 12:
		var line := v.compose("order_ack", _ship(id))
		characters["%.2f/%.2f" % [line["pitch"], line["rate"]]] = true
	assert_true(characters.size() >= 4, "ships sound different (%d characters)" % characters.size())
	v.free()


func test_alert_preempts_routine() -> void:
	var v := _voice()
	v.say("order_ack", _ship(1))
	assert_eq(_heard.size(), 1, "a routine line goes out when the net is clear")
	assert_true(not bool(_heard[0]["interrupt"]), "routine never interrupts")
	_speaking = true
	_now += 2.5
	v.say("new_contact", null, {"track": "1004"})
	assert_eq(_heard.size(), 1, "routine waits while someone is speaking")
	assert_true(not v.pending().is_empty(), "one line pending")
	v.say("torpedo_inbound", _ship(2))
	assert_eq(_heard.size(), 2, "an alert goes out at once")
	assert_eq(_heard[1]["event"], "torpedo_inbound")
	assert_true(bool(_heard[1]["interrupt"]), "and cuts off the routine line")
	assert_true(v.pending().is_empty(), "the waiting routine line is discarded")
	v.say("torpedo_inbound", _ship(2))
	assert_eq(_heard.size(), 2, "a repeated alert inside the window is one call")
	v.free()


func test_routine_lines_queue_one_deep_and_pace_themselves() -> void:
	var v := _voice()
	v.say("order_ack", _ship(1))
	v.say("missile_away", _ship(1))
	v.say("fire_out", _ship(1))
	assert_eq(_heard.size(), 1, "at most one routine line every two seconds")
	assert_eq(v.pending()["event"], "fire_out", "only the newest waits")
	_now += 1.0
	v._process(0.016)
	assert_eq(_heard.size(), 1)
	_now += 1.1
	v._process(0.016)
	assert_eq(_heard.size(), 2, "the waiting line goes out after the gap")
	assert_eq(_heard[1]["event"], "fire_out")
	v.free()


func test_stale_routine_line_is_dropped() -> void:
	var v := _voice()
	_speaking = true
	v.say("new_contact", null, {"track": "1001"})
	assert_true(_heard.is_empty())
	_now += CrewVoice.STALE_S + 0.5
	_speaking = false
	v._process(0.016)
	assert_true(_heard.is_empty(), "a line older than four seconds is not spoken")
	assert_eq(v.dropped_stale, 1)
	assert_true(v.pending().is_empty())
	v.free()


func test_time_compression_speaks_alerts_only() -> void:
	var v := _voice()
	_speed = 5.0
	v.say("order_ack", _ship(1))
	v.say("new_contact", null, {"track": "1002"})
	assert_true(_heard.is_empty(), "routine traffic is muted above 1x")
	assert_true(v.pending().is_empty())
	v.say("inbound_missile", _ship(1))
	assert_eq(_heard.size(), 1, "alerts still come through")
	v.say("mission_won")
	assert_eq(_heard.size(), 2, "and so does the end of the mission")
	v.free()


func test_disabled_voice_and_missing_sink_are_silent() -> void:
	var v := _voice()
	v.enabled = false
	v.say("inbound_missile", _ship(1))
	assert_true(_heard.is_empty(), "voice off says nothing")
	v.enabled = true
	v.muted = func() -> bool: return true
	v.say("inbound_missile", _ship(1))
	assert_true(_heard.is_empty(), "muted sound (Ctrl+M) silences the crew too")
	v.muted = Callable()
	v.sink = Callable()
	v.say("inbound_missile", _ship(1))
	assert_true(v.spoken.is_empty(), "no sink, nothing composed for it")
	v.free()


func test_advise_is_never_spoken_or_journaled() -> void:
	var radio := RadioNet.new()
	var map := TacticalMap.new()
	radio.map = map
	var v := _voice()
	radio.logged.connect(func(_text: String, _severity: String) -> void: v.say("order_ack"))
	radio.advise("Select a shooter before you engage")
	assert_true(radio.journal.is_empty(), "advice is not in the debrief journal")
	assert_true(radio.history.is_empty(), "nor on the comms history")
	assert_eq(radio.last_advice, "Select a shooter before you engage")
	assert_true(_heard.is_empty(), "advice is never spoken")
	assert_eq(map._radio.entries.size(), 1, "it shows on the radio line")
	assert_eq(map._radio.entries[0]["severity"], RadioNet.ADVICE, "as advice, drawn dimmer")
	assert_true(TacticalMap.COL_RADIO_ADVICE.a < 1.0, "the advice colour is dimmer than crew traffic")
	radio.flash("Radio check")
	assert_eq(radio.journal.size(), 1, "crew traffic still journals")
	map.free()
	v.free()


func test_the_sink_is_never_the_os_in_tests() -> void:
	assert_true(CrewVoice.automated_run(), "a test run is an automated run")
	assert_true(CrewVoice.os_speech_blocker(true) != "", "the OS is blocked even when asked for")
	_with_scratch_settings(func() -> void:
		var v := CrewVoice.new()
		v.configure_from_settings()
		assert_true(not v.os_speech, "configuring from settings never installs the OS sink here")
		assert_true(not v.sink.is_valid(), "and leaves no sink at all")
		v.toggle()
		assert_true(not v.os_speech and not v.sink.is_valid(), "toggling on does not reach the OS either")
		v.free())


func test_preferences_persist_under_user_only() -> void:
	_with_scratch_settings(func() -> void:
		assert_eq(UserSettings.get_value("audio", "voice", "unset"), "unset")
		assert_true(UserSettings.set_value("audio", "voice", true))
		assert_true(UserSettings.has_value("audio", "voice"))
		assert_eq(UserSettings.get_value("audio", "voice", false), true)
		var v := CrewVoice.new()
		v.set_enabled(false)
		assert_eq(UserSettings.get_value("audio", CrewVoice.SETTINGS_KEY, true), false, "the voice choice is saved")
		v.free()
		UserSettings.writable = false
		assert_true(not UserSettings.set_value("audio", "voice", true), "a scripted run never saves")
		UserSettings.writable = true
		UserSettings.path = "res://work/should_not_exist.cfg"
		assert_true(not UserSettings.set_value("audio", "voice", true), "never under res://")
		UserSettings.path = SCRATCH_SETTINGS)


func test_menus_offer_the_voice_and_ambient_toggles() -> void:
	var items := CdsMenus.cds_items({"voice": true, "ambient": false, "sound": true})
	var voice := _find(items, "Crew voice")
	var ambient := _find(items, "Ambient sea and machinery")
	assert_eq(voice["action"]["id"], "voice")
	assert_eq(int(voice["checked"]), 1)
	assert_eq(ambient["action"]["id"], "ambient")
	assert_eq(int(ambient["checked"]), 0)


func test_ambient_bed_follows_sea_state_pause_and_mute() -> void:
	var fx: Node = SoundFx
	var sea: AudioStreamWAV = fx._ambient["sea"]
	assert_eq(sea.loop_mode, AudioStreamWAV.LOOP_FORWARD, "the sea wash loops")
	assert_eq(sea.loop_end, sea.data.size() / 2)
	for hum: String in ["engine", "rotor", "jet"]:
		assert_true(fx._ambient.has(hum), "a %s hum is generated" % hum)
	var saved_paused := SimClock.paused
	var saved_enabled: bool = fx.enabled
	var saved_ambient: bool = fx.ambient_enabled
	fx.enabled = true
	fx.ambient_enabled = true
	SimClock.paused = false
	fx.set_ambient(true, 0, "engine")
	var calm: Vector2 = fx.ambient_targets()
	fx.set_ambient(true, 6, "rotor")
	var rough: Vector2 = fx.ambient_targets()
	assert_true(rough.x > calm.x + 10.0, "a high sea is louder than a calm one")
	assert_true(calm.y > fx.SILENT_DB, "a hooked ship hums")
	SimClock.paused = true
	assert_eq(fx.ambient_targets(), Vector2(fx.SILENT_DB, fx.SILENT_DB), "silent while paused")
	SimClock.paused = false
	fx.enabled = false
	assert_eq(fx.ambient_targets(), Vector2(fx.SILENT_DB, fx.SILENT_DB), "Ctrl+M silences the bed")
	fx.enabled = true
	fx.ambient_enabled = false
	assert_eq(fx.ambient_targets(), Vector2(fx.SILENT_DB, fx.SILENT_DB), "and so does its own toggle")
	fx.ambient_enabled = true
	fx.set_ambient(false, 3, "")
	assert_eq(fx.ambient_targets(), Vector2(fx.SILENT_DB, fx.SILENT_DB), "and off the command screen")
	assert_eq(fx.hum_for(null), "")
	assert_eq(fx.hum_for(_ship(1)), "engine")
	fx._stop_ambient()
	SimClock.paused = saved_paused
	fx.enabled = saved_enabled
	fx.ambient_enabled = saved_ambient


static func _find(items: Array, text: String) -> Dictionary:
	for it: Dictionary in items:
		if str(it.get("text", "")) == text:
			return it
		if it.has("children"):
			var inner := _find(it["children"], text)
			if not inner.is_empty():
				return inner
	return {}
