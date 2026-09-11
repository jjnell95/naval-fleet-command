# M16 validation — 11 September 2026

## Results

- **208 regression tests passed, 0 failed**, using Godot 4.7.2 and the real project autoload configuration.
- **20 / 20 scenario smoke runs passed:** all ten missions with seeds 2 and 13, each advanced 6,000 simulated seconds. No script/parse errors, unresolved aircraft homes or grounded hulls were reported.
- Every authored chart triangulated, every ship started in water, every base started on land, and authored surface routes and rendezvous/exit areas passed the geographic checks.
- Native 1,600 × 1,000 captures verified the Gotland and Lofoten charts, island geometry, geographic grid, unit labels and chart controls.
- The rebuilt browser package was exercised in the Codex in-app browser: mission menu, briefing, take command, pause, zoom, gallery search and weapon inspection. No browser console warnings or errors were observed. A final check launched the packaged copy from `outputs`, opened the Baltic briefing, took command and paused successfully.
- All 56 platform and 58 weapon presentation assets are present and importable. `git diff --check` passed.

## What these checks establish

The regression suite specifically checks escort success while hostile forces remain, protected-ship and civilian losses, both-merchant arrival, named-target ASW objectives, either-condition passage denial, exit-loss precedence, missing targets, geographic round trips, class weapon/deck fits, hull turning and all ten charts. The smoke runs exercise the real game entrypoint, AI and simulation lifecycle.

The 6,000-second checks are shorter than four-to-eight-hour defensive watches; they establish stable simulation through that interval, not successful completion of every mission. The native test runner still emits pre-existing ObjectDB/resource cleanup messages at shutdown (561 instances and 132 resources in this run), despite zero failed assertions. The browser playthrough did not reproduce runtime errors.

## Build and reproduction

```sh
/path/to/Godot --headless --path . --script tests/run_tests.gd
python3 tools/smoke_scenarios.py /path/to/Godot /tmp/naval-m16-smoke
/path/to/Godot --headless --path . --export-pack Web docs/play/index.pck
```

The Web pack was rebuilt against the matching Godot 4.7.2 JavaScript/WASM runtime already tracked in the repository. The loader's `fileSizes["index.pck"]` was updated to the resulting file size. Full export templates were not available locally; this is an updated pack with its existing compatible runtime. The final browser check used that package.

Double-click `Launch Preview.command` on macOS (Python 3 required), or run `python3 tools/preview.py`. The launcher serves only localhost on a free port. The UI is intended for a desktop-sized window and letterboxes in narrow panels.

See [machine-readable results](validation-m16.json) for every seed/scenario result and the pack checksum. See [fidelity review and sources](REALISM_M16.md) for the distinction between public equipment facts and modeled performance, and the remaining geography/combat-model limitations.
