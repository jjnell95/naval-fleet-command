extends RefCounted
## Deliberate playback through Godot's mixer, including Dummy audio in CI. Captures a reviewable
## WAV and verifies priority, ducking, mute, and return to silence with the actual Ogg players.
## godot --headless --audio-driver Dummy --path . --script tools/audio/audio_playtest.gd

var checks := {}


func run(tree: SceneTree) -> void:
	var root := tree.root
	var errors = load("res://tests/test_error_log.gd").new()
	OS.add_logger(errors)
	var fx := root.get_node("SoundFx")
	var sim_clock := root.get_node("SimClock")
	sim_clock.paused = false
	fx.enabled = true
	fx.ambient_enabled = true
	fx.set_ambient(true, 3, "engine")
	var voice := CrewVoice.new()
	root.add_child(voice)
	voice.use_recordings()
	voice.enabled = true
	voice.compression = func() -> float: return 1.0
	voice.muted = func() -> bool: return not fx.enabled
	voice.speaking_changed.connect(fx.set_crew_speaking)
	var recorder := AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	var master := AudioServer.get_bus_index("Master")
	var slot := AudioServer.get_bus_effect_count(master)
	AudioServer.add_bus_effect(master, recorder)
	recorder.set_recording_active(true)
	await tree.create_timer(0.7).timeout
	voice.say("order_ack")
	await tree.process_frame
	checks["a bundled Ogg performance plays"] = voice._player.playing and voice._player.stream is AudioStreamOggVorbis
	checks["speech ducks the background"] = voice.speaking and fx._speech_active
	checks["voice plays at its authored pitch"] = is_equal_approx(voice._player.pitch_scale, 1.0)
	await tree.create_timer(2.2).timeout
	fx.play("launch")
	voice.say("missile_away")
	await tree.create_timer(2.6).timeout
	fx.play("gun")
	await tree.create_timer(1.3).timeout
	fx.play("torpedo_launch")
	var ship := Unit.new()
	ship.id = 2
	ship.callsign = "USS Test"
	voice.say("torpedo_away", ship)
	await tree.create_timer(2.4).timeout
	voice.say("investigate_ack")
	await tree.create_timer(0.25).timeout
	var routine_stream: AudioStream = voice._player.stream
	fx.play("alarm", 0.0)
	voice.say("inbound_missile", ship)
	await tree.process_frame
	checks["an alert replaces the routine clip"] = voice._player.stream != routine_stream and voice.spoken.back()["event"] == "inbound_missile"
	var warning_stream: AudioStream = fx._alert_player.stream
	for cue: String in ["launch", "gun", "impact", "intercept", "click", "contact", "classified"]:
		fx.play(cue, 0.0)
	checks["routine effects cannot steal the warning player"] = fx._alert_player.playing and fx._alert_player.stream == warning_stream
	voice.say("mission_won")
	checks["the mission report waits for the alert"] = not voice._final_pending.is_empty()
	await tree.create_timer(6.5).timeout
	checks["the waiting mission report finishes"] = voice.spoken.back()["event"] == "mission_won" and not voice.speaking and not voice._player.playing
	checks["ducking releases after speech"] = not fx._speech_active
	voice.say("new_contact")
	await tree.create_timer(0.2).timeout
	fx.toggle()
	voice._process(0.016)
	checks["master mute stops speech and ambience"] = not voice._player.playing and not voice.speaking and not fx.ambient_playing()
	checks["master mute stops all effects"] = not fx._cue_playing()
	await tree.create_timer(0.3).timeout
	recorder.set_recording_active(false)
	var recording := recorder.get_recording()
	checks["the mixer produced audio frames"] = recording != null and recording.data.size() > 44100 * 2
	var path := "res://work/audio-authoring"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	if recording != null:
		checks["capture saved"] = recording.save_to_wav(path.path_join("audio-preview.wav")) == OK
	AudioServer.remove_bus_effect(master, slot)
	voice.queue_free()
	await tree.process_frame
	var engine_errors: Array = errors.take_errors()
	checks["no unexpected engine errors"] = engine_errors.is_empty()
	OS.remove_logger(errors)
	var file := FileAccess.open(path.path_join("playback.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "errors": engine_errors}, "\t") + "\n")
	var failed := checks.values().count(false)
	print("[Audio] %d checks, %d failed" % [checks.size(), failed])
	for key: String in checks:
		if not checks[key]:
			print("FAIL ", key)
	tree.quit(1 if failed > 0 else 0)
