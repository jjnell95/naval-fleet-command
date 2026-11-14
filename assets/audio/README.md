# Command audio

The game ships 76 short crew performances in two stable voices, 23 effect takes and five ambient
loops (104 Ogg Vorbis clips, about 1.6 MB). Playback is local on desktop and web: no operating-system
speech voice, audio service, model download or Python installation is needed by a player.

The crew uses complete, concise phrases at the original render speed. A 180–4,200 Hz communications
band and a quiet switch transient provide a restrained radio character. Pitch is never shifted to
invent another speaker. Ship names, contact numbers and detailed refusal reasons stay in the visual
radio log, instead of being spliced into speech. Reports do not claim that an incoming threat is
already being engaged, or that every return to base is a fuel emergency.

Effects are authored sound design, not field recordings or samples from Jane's Fleet Command.
Layered, filtered noise, transients and resonances distinguish missile ignition, guns, torpedo tubes,
impacts and console switches. Combat effects have three takes. Sea and machinery loops run for
10–18 seconds with overlapping seams. Sonar and threat warnings retain their recognisable tones;
there are no musical mission-result jingles. Backgrounds and routine effects duck under speech.

## Voice source and licence

The voices are synthesized offline with the stock `am_michael` and `am_fenrir` profiles from
[Kokoro-82M v1.0](https://huggingface.co/hexgrad/Kokoro-82M), whose weights are Apache-2.0 licensed.
These are generated performances, not recordings of hired actors or clones made for this project.
Kokoro is by hexgrad / rzvzn, based on StyleTTS 2 and ISTFTNet. A copy of its Apache licence is in
[Kokoro-APACHE-2.0.txt](Kokoro-APACHE-2.0.txt). No model weights or third-party source code ship in
this directory. The dialogue, processing, sound-effect synthesis and integration are authored for
this game. No third-party sound-effect recordings are included.

The authoring tool uses [kokoro-onnx](https://github.com/thewh1teagle/kokoro-onnx) (MIT) and its
[model-files-v1.1 release](https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.1):

| Authoring input | SHA-256 |
|---|---|
| `kokoro-v1.0.onnx` | `beb0d1848dee9a49da392cc3df26958d46cfa35d321edf434f52949153f0df3a` |
| `voices-v1.0.bin` | `bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d` |

## Rebuild

Install authoring dependencies in a virtual environment and put those two model files in
`work/audio-authoring/` (ignored by Git):

```sh
python3 -m venv work/audio-authoring/venv
work/audio-authoring/venv/bin/pip install -r tools/audio/requirements.txt
work/audio-authoring/venv/bin/python tools/audio/build_audio.py
# Effects alone need no model or inference runtime:
work/audio-authoring/venv/bin/python tools/audio/build_audio.py --effects-only
godot --headless --path . --import --quit
```

The phrase table is `data/voice/phrases.json`. Rebuild the crew bank whenever its audible wording
changes. `bank.json` records each output's duration, decoded peak and hash. The model stays in the
ignored authoring directory; the game loads only `.ogg` clips.

`tools/audio/audio_playtest.gd` deliberately exercises real playback and captures the mix, even with
the Dummy audio driver. Normal tests and scripted game walkthroughs still do not install crew
playback. The existing voice preferences, Ctrl-M mute, alert priority and time-compression rules
are retained.
