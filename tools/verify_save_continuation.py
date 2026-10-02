"""Save in one process, load in another, and check the battle carries on exactly as it would have.

For each operation: process A runs straight to t2; process B runs to t1 and writes a save; process
C loads that save with a different seed and runs to t2. The whole tactical state at t2 (every unit,
track, weapon, mission, random stream and cycle phase) must be byte-identical between A and C.
Separate processes catch static state an in-process test cannot (the damage stream, the chart and
sea-floor caches). Both sides are flown by the AI so every system is exercised.

Usage: python3 tools/verify_save_continuation.py /path/to/godot [results-directory] [--quick]
(--quick runs the two smaller operations, for CI.)
"""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
quick = "--quick" in sys.argv
positional = [a for a in sys.argv[1:] if not a.startswith("--")]
out = Path(positional[1] if len(positional) > 1 else root / "work/save-continuation").resolve()
out.mkdir(parents=True, exist_ok=True)
CASES = [
    ("cold_war_03_carrier", 31, 601.75, 1500.0),
    ("northern_passage", 31, 500.75, 900.0),
    ("gulf_01_hormuz", 45, 900.25, 1500.0),
    ("pacific_02_taiwan_strait", 42, 1200.75, 1800.0),
]


def leg(name, mode, scenario, seed, t1, t2, save, result):
    command = [positional[0], "--headless", "--path", str(root), "--script", "tools/save_continuation.gd", "--",
               f"--mode={mode}", f"--scenario=res://data/scenarios/{scenario}.json", f"--seed={seed}",
               f"--t1={t1}", f"--t2={t2}", f"--save={save}", f"--out={result}"]
    with (out / f"{name}-{mode}.log").open("w") as log:
        run = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=900)
    if run.returncode:
        raise SystemExit(f"{name} {mode}: failed (exit {run.returncode}); see {out / (name + '-' + mode + '.log')}")


summary = {}
for scenario, seed, t1, t2 in (CASES[:2] if quick else CASES):
    save = out / f"{scenario}.nfcsave"
    straight = out / f"{scenario}-straight.bin"
    resumed = out / f"{scenario}-resumed.bin"
    leg(scenario, "straight", scenario, seed, t1, t2, save, straight)
    leg(scenario, "save", scenario, seed, t1, t2, save, straight.with_suffix(".unused"))
    leg(scenario, "resume", scenario, seed, t1, t2, save, resumed)
    a = straight.read_bytes()
    c = resumed.read_bytes()
    same = a == c
    summary[scenario] = {"seed": seed, "save_at_s": t1, "compare_at_s": t2, "state_bytes": len(a),
                         "save_file_bytes": save.stat().st_size, "identical": same,
                         "sha256": hashlib.sha256(a).hexdigest()}
    print(f"{scenario}: save at {t1}s, compare at {t2}s, {len(a)} state bytes, save file {save.stat().st_size} bytes: "
          f"{'IDENTICAL' if same else 'DIFFERENT'}", flush=True)
(out / "results.json").write_text(json.dumps(summary, indent=2) + "\n")
if not all(v["identical"] for v in summary.values()):
    raise SystemExit("continuation differs after a reload in another process")
print("Every operation carries on identically after a save and a reload in a separate process.")
