#!/usr/bin/env python3
"""Fly each operation's opening plans headless against the AI, over seeds, and tabulate them.

Usage:
  python3 tools/opening_plans.py GODOT [--seeds=2,13] [--only=cold_war_03_carrier,...]
                                       [--jobs=N] [--out=FILE.jsonl]

Every trial is one Godot process running tools/opening_plans.gd: the plan's real orders through
UnitManager.issue_order, the AI flying the other side, to the end of the mission or its watch or
deadline. The table gives the result and MissionManager.assessment() for each trial, and what the
operation drew for that seed (event variants, windows, chances), so the same plan can be compared
across draws. Not part of CI: the full sweep (seven operations, two plans, two seeds) is about two
hours of simulation on one core. A plan counts as viable when it wins, or holds a reasonable
effectiveness, on both seeds.
"""
import json
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TIMEOUT_S = 3600


def trial(godot, scenario, plan, seed):
    started = time.time()
    cmd = [godot, '--headless', '--path', str(ROOT), '--script', 'tools/opening_plans.gd', '--',
           '--scenario=' + scenario, '--plan=' + plan, '--seed=%d' % seed]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT_S).stdout
    except subprocess.TimeoutExpired:
        return dict(scenario=scenario, plan=plan, seed=seed, result='TIMEOUT')
    for line in out.splitlines():
        if line.startswith('[plan] {'):
            d = json.loads(line[len('[plan] '):])
            d['wall_s'] = round(time.time() - started)
            return d
    return dict(scenario=scenario, plan=plan, seed=seed, result='ERROR', tail=out.splitlines()[-5:])


def draws(d):
    """What the operation drew for this seed, compactly: variant ids, drawn times, chances."""
    parts = []
    for event, drawn in sorted(d.get('variants', {}).items()):
        bits = []
        if 'variant' in drawn:
            bits.append(drawn['variant'])
        for key in ('at_s', 'latest_s'):
            if key in drawn:
                bits.append('%s %d' % (key.replace('_s', ''), drawn[key]))
        if 'happens' in drawn:
            bits.append('yes' if drawn['happens'] else 'no')
        fired = d.get('fired', {}).get(event)
        if fired is not None and fired > 1:
            bits.append('fired %d' % fired)
        parts.append('%s: %s' % (event, ', '.join(bits)))
    return '; '.join(parts)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    godot = sys.argv[1]
    opts = dict(a[2:].split('=', 1) for a in sys.argv[2:] if a.startswith('--') and '=' in a)
    seeds = [int(s) for s in opts.get('seeds', '2,13').split(',')]
    only = set(opts['only'].split(',')) if 'only' in opts else None
    listing = subprocess.run([godot, '--headless', '--path', str(ROOT), '--script', 'tools/opening_plans.gd', '--', '--list'],
                             capture_output=True, text=True, timeout=300).stdout
    plans = [tuple(l.split()) for l in listing.splitlines() if l.count(' ') == 1 and not l.startswith('Godot')]
    jobs = [(s, p, seed) for s, p in plans if only is None or s in only for seed in seeds]
    with ThreadPoolExecutor(max_workers=int(opts.get('jobs', '1'))) as pool:
        results = list(pool.map(lambda j: trial(godot, *j), jobs))
    if 'out' in opts:
        Path(opts['out']).write_text(''.join(json.dumps(r, ensure_ascii=False) + '\n' for r in results))
    print('| Operation | Plan | Seed | Result | End | Effectiveness | Task / Force / Attrition / Bonus | Losses (BLUE / RED) | Draws |')
    print('|---|---|---|---|---|---|---|---|---|')
    for r in results:
        if 'percent' not in r:
            print('| %s | %s | %s | %s | | | | | |' % (r['scenario'], r['plan'], r['seed'], r['result']))
            continue
        losses = r.get('losses', {})

        def side(f):
            s = losses.get(f, {})
            return '%d ships, %d aircraft' % (len(s.get('ships', [])), s.get('aircraft', 0))
        print('| %s | %s | %d | %s | %d s | %d%% | %.0f / %.0f / %.0f / %.0f | %s / %s | %s |' % (
            r['scenario'], r['plan'], r['seed'], r['result'], r['end_s'], r['percent'], r['task'], r['force'],
            r['attrition'], r['bonus'], side('BLUE'), side('RED'), draws(r)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
