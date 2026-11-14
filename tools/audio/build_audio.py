#!/usr/bin/env python3
"""Author the small, offline audio bank; no model or Python dependency ships with the game.

See assets/audio/README.md for pinned dependencies, model sources and rebuild commands.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/audio"
RATE = 24000
RNG = np.random.default_rng(1990)


def filtered(x, low=0, high=0, order=2):
    if low:
        x = sosfilt(butter(order, low, "highpass", fs=RATE, output="sos"), x, axis=0)
    if high:
        x = sosfilt(butter(order, high, "lowpass", fs=RATE, output="sos"), x, axis=0)
    return x


def noise(n, low, high):
    x = filtered(RNG.normal(size=n), low, high)
    return x / max(np.sqrt(np.mean(x * x)), 1e-6)


def fade(x, attack=0.008, release=0.04):
    x = x.copy()
    a, b = min(int(attack * RATE), len(x)), min(int(release * RATE), len(x))
    if a:
        x[:a] *= np.linspace(0, 1, a) ** 2
    if b:
        x[-b:] *= np.linspace(1, 0, b) ** 2
    return x


def level(x, rms_db=-18, peak=0.79):
    x = x - np.mean(x, axis=0)
    gain = min(10 ** (rms_db / 20) / max(np.sqrt(np.mean(x * x)), 1e-8),
               peak / max(np.max(np.abs(x)), 1e-8))
    return x * gain


def save(path, x):
    path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(path, x, RATE, format="OGG", subtype="VORBIS")


def voices(model_dir):
    import onnxruntime as ort
    from kokoro_onnx import Kokoro

    class Renderer(Kokoro):
        # v0.4.9 sends integer speed to the v1.0 float input. Use the published model's
        # actual input types, preserving its natural prosody at speed 1.0.
        def _create_audio(self, phonemes, voice, speed):
            tokens = self.tokenizer.tokenize(phonemes)
            data = {"input_ids": np.array([[0, *tokens, 0]], dtype=np.int64),
                    "style": np.array(voice[len(tokens)], dtype=np.float32),
                    "speed": np.array([speed], dtype=np.float32)}
            return self.sess.run(None, data)[0], RATE

    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    options.inter_op_num_threads = 1
    session = ort.InferenceSession(str(model_dir / "kokoro-v1.0.onnx"),
                                   sess_options=options, providers=["CPUExecutionProvider"])
    renderer = Renderer.from_session(session, str(model_dir / "voices-v1.0.bin"))
    table = json.loads((ROOT / "data/voice/phrases.json").read_text())
    for profile, voice in table["voices"].items():
        for event, variants in table["events"].items():
            for index, text in enumerate(variants):
                raw, rate = renderer.create(text, voice=voice, speed=1.0, lang="en-us")
                assert rate == RATE and len(raw) > RATE / 4
                # A broad communications band retains consonants and breath. No pitch shifting,
                # vocoder, heavy distortion, or blanket static over the performance.
                speech = filtered(raw, 180, 4200)
                speech = np.tanh(level(speech, -19) * 1.25) / 1.25
                speech = fade(speech, 0.005, 0.018)
                # A quiet switch closure, then a short tail; each utterance remains one clip.
                key = fade(noise(int(RATE * 0.025), 450, 2800), 0.002, 0.018) * 0.006
                clip = np.concatenate([key, np.zeros(int(RATE * 0.035)), speech,
                                       np.zeros(int(RATE * 0.075))])
                save(OUT / "crew" / profile / f"{event}_{index}.ogg", clip)
                print(f"{profile}/{event}_{index}: {len(clip) / RATE:.2f}s", flush=True)


def transient(kind, variant=0):
    duration = {"launch": 2.0, "gun": 1.2, "torpedo_launch": 1.5, "release": 0.22,
                "impact": 2.6, "intercept": 0.85, "ping": 1.1, "alarm": 1.05,
                "torpedo": 1.2, "contact": 0.2, "classified": 0.19,
                "click": 0.055, "complete": 0.22}[kind]
    t = np.arange(int(duration * RATE)) / RATE
    n = len(t)
    low, body, air = noise(n, 28, 180), noise(n, 110, 1500), noise(n, 750, 6500)
    if kind == "launch":
        envelope = (1 - np.exp(-t * 28)) * np.exp(-t * 2.5)
        x = (low * 0.65 + body * 0.65 + air * 0.18) * envelope
        x += body * np.exp(-t * 65) * 0.45
    elif kind == "gun":
        x = (air * 0.5 + body * 0.9) * np.exp(-t * 48)
        x += low * (1 - np.exp(-t * 110)) * np.exp(-t * 7) * 1.2
        for delay, gain in [(0.065, 0.22), (0.14, 0.1)]:
            s = int(delay * RATE)
            x[s:] += x[:-s].copy() * gain
    elif kind == "torpedo_launch":
        x = body * np.exp(-t * 28) * 0.6 + low * np.exp(-t * 4) * 0.4
        x += noise(n, 180, 2300) * (1 - np.exp(-t * 12)) * np.exp(-t * 3.8) * 0.65
    elif kind in ["impact", "intercept"]:
        decay = 2.5 if kind == "impact" else 8
        x = body * np.exp(-t * 30) * 0.7 + air * np.exp(-t * 60) * 0.3
        x += low * (1 - np.exp(-t * 65)) * np.exp(-t * decay)
        x += body * np.exp(-t * decay * 1.7) * 0.18
    elif kind == "ping":
        # Sonar is a tonal instrument. Keep its recognisable ring, soften the leading edge.
        x = np.sin(2 * np.pi * (1320 + variant * 7) * t) * np.exp(-t * 5)
        x += np.sin(2 * np.pi * 1312 * t) * np.exp(-t * 8) * 0.17
    elif kind in ["alarm", "torpedo"]:
        x = np.zeros(n)
        freq = 760 if kind == "alarm" else 540
        for start in [0.0, 0.3, 0.6]:
            pulse_t = np.arange(int(RATE * 0.17)) / RATE
            pulse = (np.sin(2 * np.pi * freq * pulse_t) +
                     0.18 * np.sin(2 * np.pi * freq * 2 * pulse_t))
            pulse = fade(pulse, 0.012, 0.028)
            begin = int(RATE * start)
            x[begin:begin + len(pulse)] += pulse
    elif kind in ["contact", "classified"]:
        x = np.sin(2 * np.pi * (880 if kind == "contact" else 720) * t) * np.exp(-t * 22)
        x += body * np.exp(-t * 70) * 0.12
    else:
        # A console/rack relay: a dry mechanical transient, not a musical chirp.
        x = noise(n, 500, 4300) * np.exp(-t * (110 if kind == "click" else 45))
        x += np.sin(2 * np.pi * 420 * t) * np.exp(-t * 85) * 0.2
    return fade(level(x, -17), 0.003, 0.06)


def bed(kind):
    seconds = {"sea": 18, "engine": 12, "boat": 12, "rotor": 10, "jet": 12}[kind]
    crossfade = int(0.7 * RATE)
    n = seconds * RATE
    t = np.arange(n + crossfade) / RATE
    count = len(t)
    slow = filtered(RNG.normal(size=count), high=0.6)
    slow /= max(np.max(np.abs(slow)), 1e-6)
    if kind == "sea":
        swell = 0.65 + 0.2 * np.sin(2 * np.pi * t / 7.3) + slow * 0.16
        x = noise(count, 65, 2100) * swell
        x += noise(count, 650, 4800) * (0.15 + 0.1 * np.sin(2 * np.pi * t / 4.7))
    elif kind in ["engine", "boat"]:
        shaft = 41 if kind == "engine" else 32
        phase = 2 * np.pi * np.cumsum(shaft + slow * 0.16) / RATE
        x = noise(count, 28, 230) * 0.7 + noise(count, 160, 1100) * 0.16
        x += (np.sin(phase) * 0.15 + np.sin(phase * 2) * 0.07) * (0.8 + slow * 0.2)
        if kind == "boat":
            x = filtered(x, high=380)
    elif kind == "rotor":
        phase = 2 * np.pi * np.cumsum(17.2 + slow * 0.12) / RATE
        blades = (0.5 + 0.5 * np.sin(phase)) ** 4
        x = noise(count, 38, 650) * (0.23 + 0.77 * blades)
        x += noise(count, 550, 2400) * 0.2
    else:
        x = noise(count, 45, 290) * 0.6 + noise(count, 600, 5500) * 0.4
        x *= 0.8 + slow * 0.12
    # Overlap the continuation into the beginning. The seam joins adjacent source samples;
    # the long, varying body has no regular one-second reset or obvious pulsing sine wave.
    w = np.linspace(0, 1, crossfade)
    x[:crossfade] = x[n:n + crossfade] * (1 - w) + x[:crossfade] * w
    return level(x[:n], -18)


def effects():
    global RNG
    RNG = np.random.default_rng(1991)  # Identical output with or without the voice-rendering pass.
    for kind in ["launch", "gun", "torpedo_launch", "impact", "intercept", "release",
                 "ping", "alarm", "torpedo", "contact", "classified", "click", "complete"]:
        for variant in range(3 if kind in ["launch", "gun", "torpedo_launch", "impact", "intercept"] else 1):
            save(OUT / "effects" / f"{kind}_{variant}.ogg", transient(kind, variant))
    for kind in ["sea", "engine", "boat", "rotor", "jet"]:
        save(OUT / "ambient" / f"{kind}.ogg", bed(kind))


def receipt():
    files = []
    for path in sorted(OUT.rglob("*.ogg")):
        x, rate = sf.read(path)
        files.append({"file": str(path.relative_to(ROOT)), "seconds": round(len(x) / rate, 4),
                      "sample_rate": rate, "peak_dbfs": round(20 * np.log10(max(np.max(np.abs(x)), 1e-8)), 2),
                      "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    (OUT / "bank.json").write_text(json.dumps({"version": 1, "files": files}, indent=2) + "\n")
    print(f"{len(files)} clips, {sum((ROOT / f['file']).stat().st_size for f in files):,} bytes")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", type=Path, default=ROOT / "work/audio-authoring")
    parser.add_argument("--effects-only", action="store_true")
    args = parser.parse_args()
    if not args.effects_only:
        voices(args.model_dir)
    effects()
    receipt()
