# Naval Fleet Command — Aegis Command

[Play in your browser](https://jjnell95.github.io/naval-fleet-command/play/) · [Launch page](https://jjnell95.github.io/naval-fleet-command/)

A modern naval command simulation in Godot 4.7.2. Command a task group through an Aegis-inspired combat information display. Original vector graphics and fictional scenarios; no Jane's assets or affiliation.

## Play

Desktop/laptop with keyboard and mouse, WebGL 2 browser. The initial engine download is approximately 38 MB. Select **Aegis Bastion**, **Brief and Deploy**, then **Take Command**. The game starts at real time. Space pauses; 1–6 changes time speed. Combat events drop acceleration to real time.

- Select a friendly symbol; right-click water to order movement. Shift appends waypoints. Wheel zooms; middle/right drag pans.
- Select Carrier Resolute and press **Launch** to launch the next ready aircraft (E-2D first, then the fighters). Select an airborne aircraft to direct it.
- Select a friendly shooter, then a contact; choose an appropriate weapon and salvo, and **Engage**. Unknown contact classification matters.
- Ship missile defence is automatic, subject to detection, weapon range, channels, ammunition, damage and weapons-hold settings.
- R toggles radar; P sonar; E emissions control. F2 toggles the symbol key; F4 sensor rings. F1 briefing; F9 missions; F10 restart. F3 is an explicitly optional debug truth overlay.
- Hover over the top event message for the timestamped event history. Scroll selected-unit details to see the complete inventory.

## What is implemented

Eight missions including a free-play sandbox; 19 platform types, 21 weapon families and 23 sensor definitions. Aegis Bastion deploys 19 actors across air, surface, subsurface and neutral traffic.

Radar horizon, passive/active sonar, ESM bearings, uncertain tracks, classification, stale tracks, target-motion analysis, layered missile interception, decoys, fire-control channel limits, gunfire, torpedoes, component damage, ROE, emissions control, datalinks, formations, aircraft launch/recovery/fuel, sonobuoys and opposing AI.

This upgrade adds Flight III / SPY-6, a Nimitz-class carrier abstraction, E-2D / APY-9, F/A-18E / APG-79, SM-6 and AIM-120. Aircraft can attack air tracks using the existing track-based engagement model. The live defence board reads detected inbound threats and friendly readiness rather than hidden enemies.

## Realism boundary

An ambitious game foundation, not a high-fidelity replica of real Aegis software. Public names and broad roles are sourced in DATA_SOURCES.md; numerical performance and loadouts are estimates. Carrier air group capacity is deliberately compressed. Carrier sensors are simplified. The map is a local nautical-mile grid, not a geographic chart.

Still absent: active jamming, weather/sea-state propagation, terrain/coastline masking, ballistic missile trajectories/BMD, detailed radar scheduling/illumination, damage control/repair, logistics/replenishment and save games. Datalink isolation is incomplete: player tracks and automatic defence still use a faction-wide picture. Aircraft SAM shots do not share the complete automatic interceptor channel accounting. No claim of operational fidelity or calibrated combat probability is made.

## Develop

Open `project.godot` in Godot **4.7.2**. Source and web build are committed together. The first commit preserves the supplied project.

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script tests/run_tests.gd
godot --path .
```

Install the official matching web export templates, then run `godot --headless --path . --export-release Web`. Pages serves `main:/docs`. Commit the updated `docs/play` build after changes. The engine uses Compatibility rendering, no web threads, and text resources to preserve all sensor/target arrays during export.

The export preset accepts optional custom template paths through the Godot editor; the committed preset uses the standard installed templates. `docs/.gdignore` keeps generated web assets out of the source import process.

## Validation

139 tests pass, including new actor/loadout/home validation, air-weapon target filtering and an actual aircraft-to-aircraft missile damage test. The test runner now waits for autoload initialization instead of falsely reporting success after script failures. Eight scenarios were advanced 30,000 simulated seconds with AI on both sides, seed 2, without script failures. Aegis Bastion, Shadow Line and Northern Sentry reached victory; Atlantic Gate reached defeat. Baltic Sentinel, GIUK Passage and Northern Shield remained undecided in that automated run; the sandbox is free play. This is a regression smoke test, not a balance study.

The packaged PCK was separately checked for all 19 actors and 31 sensor installations. Desktop visual and browser checks cover deployment, selection, aviation launch, clock controls, and the tactical display. The full console is intended for a desktop screen; the landing page is responsive, but touch-only phone gameplay is not supported.

Godot engine licensing is in `docs/play/GODOT-LICENSE.txt`. Source ownership remains with the project author; no new license grant is inferred.
