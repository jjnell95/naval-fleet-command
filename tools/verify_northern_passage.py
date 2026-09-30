"""Run the actual-scene passage policies and compare deterministic replay evidence.

Usage: python3 tools/verify_northern_passage.py /path/to/godot [results-directory]
"""
import json
import subprocess
import sys
from pathlib import Path


root = Path(__file__).resolve().parents[1]
out = Path(sys.argv[2] if len(sys.argv) > 2 else root / "work/m31/policies").resolve()
out.mkdir(parents=True, exist_ok=True)
reports = {}
for policy, seed, suffix in [("escort", 31, ""), ("escort", 31, "-repeat"),
                             ("escort", 13, ""), ("abandon", 31, ""),
                             ("abandon", 13, ""), ("deadline", 31, ""),
                             ("civilian", 31, "")]:
    name = f"{policy}-{seed}{suffix}"
    target = out / f"{name}.json"
    command = [sys.argv[1], "--headless", "--path", str(root), "--script",
               "tools/passage_playtest.gd", "--", f"--policy={policy}",
               f"--seed={seed}", f"--out={target}"]
    with (out / f"{name}.log").open("w") as log:
        run = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=300)
    if run.returncode:
        raise SystemExit(f"{name}: failed (exit {run.returncode}); see {out / (name + '.log')}")
    report = json.loads(target.read_text())
    assert report["checks"] and all(report["checks"].values()), name
    reports[name] = report
    print(f"{name}: {len(report['checks'])} checks passed; result={report['result']}, "
          f"time={report['sim_time_s']}s", flush=True)

assert reports["escort-31"] == reports["escort-31-repeat"], "seed 31 replay differs"
print("Seed 31 replay matches: outcomes, commands, observations, positions, health, fuel and magazines.")
(out / "results.json").write_text(json.dumps({"replay_identical": True, "runs": reports}, indent=2) + "\n")
