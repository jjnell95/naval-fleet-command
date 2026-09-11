"""Exercise the real game entrypoint, AI, and scenario lifecycle with deterministic seeds.
Usage: python3 tools/smoke_scenarios.py /path/to/godot /path/to/results-directory
"""
import json
import re
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = Path(sys.argv[2]).resolve()
out.mkdir(parents=True, exist_ok=True)
results = []
for seed in (2, 13):
    for scenario in sorted((root / 'data/scenarios').glob('*.json')):
        command = [sys.argv[1], '--headless', '--path', str(root), '--',
                   '--autopilot', f'--seed={seed}', '--fastforward=6000',
                   f'--scenario=res://data/scenarios/{scenario.name}', '--dump']
        run = subprocess.run(command, capture_output=True, text=True, timeout=120)
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
                   aground=int(grounded[1]) if grounded else 0)
        results.append(row)
        print(json.dumps(row), flush=True)
(out / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
sys.exit(0 if all(r['ok'] for r in results) else 1)
