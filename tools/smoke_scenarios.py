"""Exercise the real game entrypoint, AI, and scenario lifecycle with deterministic seeds.
Usage: python3 tools/smoke_scenarios.py /path/to/godot /path/to/results-directory

The per-run timeout is generous because the large scenarios are large: a two-carrier task force
with both air wings up is around eighty actors, and 6,000 simulated seconds of that takes a few
minutes of wall clock on a modest machine. A run that hits the cap is reported as a failure, so
this is a ceiling to notice a hang, not a performance budget.
"""
import json
import re
import subprocess
import time
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = Path(sys.argv[2]).resolve()
out.mkdir(parents=True, exist_ok=True)
RUN_TIMEOUT_S = 420
results = []
for seed in (2, 13):
    for scenario in sorted((root / 'data/scenarios').glob('*.json')):
        command = [sys.argv[1], '--headless', '--path', str(root), '--',
                   '--autopilot', f'--seed={seed}', '--fastforward=6000',
                   f'--scenario=res://data/scenarios/{scenario.name}', '--dump']
        started = time.monotonic()
        try:
            run = subprocess.run(command, capture_output=True, text=True, timeout=RUN_TIMEOUT_S)
        except subprocess.TimeoutExpired:
            print(json.dumps(dict(scenario=scenario.stem, seed=seed, ok=False,
                                  error="timed out after %d s" % RUN_TIMEOUT_S)), flush=True)
            results.append(dict(scenario=scenario.stem, seed=seed, ok=False, seconds=0,
                                result=None, aground=0, wall_s=RUN_TIMEOUT_S))
            continue
        wall = round(time.monotonic() - started, 1)
        log = run.stdout + run.stderr
        (out / f'{scenario.stem}-{seed}.log').write_text(log)
        final = re.search(r'weapons in flight=(\d+)  mission=(\d+)  sim_time=([\d.]+)', log)
        grounded = re.search(r'terrain: \d+ landmasses, (\d+) aground', log)
        ok = (run.returncode == 0 and final is not None
              and 'SCRIPT ERROR' not in log and 'Parse Error' not in log
              and 'has no home' not in log
              and (grounded is None or int(grounded[1]) == 0))
        row = dict(scenario=scenario.stem, seed=seed, ok=ok,
                   seconds=float(final[3]) if final else 0,
                   result=int(final[2]) if final else None,
                   aground=int(grounded[1]) if grounded else 0,
                   wall_s=wall)
        results.append(row)
        print(json.dumps(row), flush=True)
(out / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
sys.exit(0 if all(r['ok'] for r in results) else 1)
