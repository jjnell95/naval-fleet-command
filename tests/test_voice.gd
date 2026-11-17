extends TestCase
## The crew you can hear: complete performances, report metadata, pacing (alerts pre-empt, stale and
## compressed routine lines are dropped), interface advice that is never spoken or journaled, the
## ambient bed and the preferences file. Audio playback is explicitly exercised by audio_playtest.gd.

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


func test_complete_performances_keep_contact_details_as_metadata() -> void:
	var t := Track.new()
	t.id = "T1003"
	var v := _voice()
	for i in 6:
		var line := v.compose("new_contact", null, {"track": t})
		assert_eq(line["track"], "T1003", "report metadata keeps the exact track")
		assert_true(not str(line["text"]).contains("1003"), "no digits spliced into a performance")
		assert_true(v.phrases["new_contact"].has(line["text"]), "the caption matches the whole clip")
	var bare := v.compose("new_contact")
	assert_eq(bare["track"], "")
	assert_true(not str(bare["text"]).contains("{"))
	v.free()


func test_speakers_keep_their_recorded_voice_without_pitch_or_speed_shifts() -> void:
	assert_eq(CrewVoice.spoken_name("USS Bulkeley (DDG 84)"), "Bulkeley")
	assert_eq(CrewVoice.spoken_name("HMS Iron Duke (F234)"), "Iron Duke")
	var v := _voice()
	var a := v.compose("missile_away", _ship(3))
	var b := v.compose("missile_away", _ship(3))
	assert_eq(a["voice"], b["voice"], "a ship keeps the same performer")
	assert_true(a["clip"] != b["clip"], "successive calls have alternate takes")
	assert_eq(a["speaker"], "Bulkeley")
	var characters := {}
	for id in 12:
		var line := v.compose("order_ack", _ship(id))
		characters[line["voice"]] = true
		assert_eq(line["pitch"], 1.0)
		assert_eq(line["rate"], 1.0)
		assert_true(not str(line["text"]).contains("Bulkeley"), "no arbitrary name splicing")
	assert_eq(characters.size(), CrewVoice.PROFILES.size())
	v.free()


func test_every_performance_is_bundled_playable_and_non_looping() -> void:
	var table := CrewVoice.load_phrases()
	for profile: String in CrewVoice.PROFILES:
		for event: String in CrewVoice.EVENTS:
			for index in table[event].size():
				var path := "%s/%s/%s_%d.ogg" % [CrewVoice.CLIP_ROOT, profile, event, index]
				assert_true(ResourceLoader.exists(path), path)
				var clip := load(path) as AudioStreamOggVorbis
				assert_true(clip != null, path + " decodes")
				if clip != null:
					assert_true(clip.get_length() > 0.25 and clip.get_length() < 6.0, path + " is a short transmission")
					assert_true(not clip.loop, path + " ends")


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


func test_automated_runs_never_install_playback_implicitly() -> void:
	assert_true(CrewVoice.automated_run())
	_with_scratch_settings(func() -> void:
		var v := CrewVoice.new()
		v.configure_from_settings()
		assert_true(not v.sink.is_valid(), "settings do not install an audio sink in tests")
		v.set_enabled(false, false)
		v.toggle(false)
		assert_true(v.enabled and not v.sink.is_valid(), "toggling on stays silent in a driven run")
		assert_true(v._player == null)
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
	var sea: AudioStreamOggVorbis = fx._ambient["sea"]
	assert_true(sea.loop, "the sea wash loops")
	assert_true(sea.get_length() >= 15.0, "the sea is not a short repeating pulse")
	for hum: String in ["engine", "boat", "rotor", "jet"]:
		assert_true(fx._ambient.has(hum), "a %s bed is bundled" % hum)
		assert_true(fx._ambient[hum].get_length() >= 9.0)
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


func test_mission_result_waits_for_the_transmission_without_getting_stale() -> void:
	var v := _voice()
	v.say("inbound_missile", _ship(1))
	_speaking = true
	v.say("mission_lost")
	assert_eq(_heard.size(), 1, "a result does not cut the warning off")
	_now += CrewVoice.STALE_S + 1.0
	_speed = 8.0
	v._process(0.016)
	assert_eq(_heard.size(), 1)
	_speaking = false
	v._process(0.016)
	assert_eq(_heard.size(), 2, "the mission result survives compression and the routine timeout")
	assert_eq(_heard[1]["event"], "mission_lost")
	assert_true(not bool(_heard[1]["interrupt"]))
	v.free()


func test_muting_discards_waiting_reports_and_mission_results() -> void:
	var v := _voice()
	_speaking = true
	v.say("order_ack", _ship(1))
	v.say("mission_won")
	v.muted = func() -> bool: return true
	v._process(0.016)
	v.muted = Callable()
	_speaking = false
	_now += 3.0
	v._process(0.016)
	assert_true(_heard.is_empty(), "unmuting does not release old traffic")
	assert_true(v.pending().is_empty() and v._final_pending.is_empty())
	v.free()


func test_speech_ducks_the_bed_and_effects_but_preserves_the_warning() -> void:
	var fx: Node = SoundFx
	var was_paused := SimClock.paused
	var was_enabled: bool = fx.enabled
	var was_ambient: bool = fx.ambient_enabled
	SimClock.paused = false
	fx.enabled = true
	fx.ambient_enabled = true
	fx.set_ambient(true, 3, "engine")
	fx.set_crew_speaking(false)
	var before: Vector2 = fx.ambient_targets()
	var launch_db: float = fx.cue_volume("launch")
	var warning_db: float = fx.cue_volume("alarm")
	fx.set_crew_speaking(true)
	var during: Vector2 = fx.ambient_targets()
	assert_near(before.x - during.x, fx.DUCK_DB)
	assert_near(before.y - during.y, fx.DUCK_DB)
	assert_near(launch_db - fx.cue_volume("launch"), 6.0)
	assert_near(warning_db - fx.cue_volume("alarm"), 2.0)
	fx.set_crew_speaking(false)
	assert_eq(fx.ambient_targets(), before, "the bed returns after the report")
	fx.set_ambient(false, 0, "")
	fx._stop_ambient()
	fx.enabled = was_enabled
	fx.ambient_enabled = was_ambient
	SimClock.paused = was_paused


func test_weapon_classes_use_distinct_launch_effects() -> void:
	var spec := WeaponSpec.new()
	var cues := {}
	for kind: String in ["missile", "torpedo", "gun", "bomb"]:
		spec.type = kind
		cues[SoundFx.launch_cue(spec)] = true
	assert_eq(cues.size(), 4, "a torpedo tube, gun, rocket and bomb rack do not sound alike")
	spec.type = "ciws"
	assert_eq(SoundFx.launch_cue(spec), "gun")
	for cue: String in SoundFx.CUE_DB:
		for stream: AudioStream in SoundFx._streams[cue]:
			assert_true(stream != null and stream.get_length() > 0.02, "%s is bundled and decodes" % cue)


static func _find(items: Array, text: String) -> Dictionary:
	for it: Dictionary in items:
		if str(it.get("text", "")) == text:
			return it
		if it.has("children"):
			var inner := _find(it["children"], text)
			if not inner.is_empty():
				return inner
	return {}
