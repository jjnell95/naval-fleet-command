# Naval Fleet Command — Aegis Command II

[Play in your browser](https://jjnell95.github.io/naval-fleet-command/play/) · [Launch page](https://jjnell95.github.io/naval-fleet-command/)

A modern naval command simulation in Godot 4.7.2. Command a task group through an Aegis-inspired combat information display: build an uncertain picture, manage emissions, hold the screen together and decide when to shoot. Original vector graphics, procedural sound and fictional scenarios; no Jane's assets or affiliation.

## Play

Desktop/laptop with keyboard and mouse, WebGL 2 browser. The initial engine download is approximately 38 MB. Pick **Aegis Bastion** for the first watch and **Arctic Shield** for the regimental raid, then **Brief and Deploy** and **Take Command**. The game starts at real time. Space pauses; 1–6 changes time speed. Combat events drop acceleration to real time.

- Select a friendly symbol; right-click water to order movement. Shift appends waypoints. Wheel zooms; middle/right drag pans. Hover over any symbol for a quick card.
- Select the carrier and press **Launch** to launch the next ready aircraft (E-2D first, then the fighters and the Growler). Select an airborne aircraft to direct it.
- Select a friendly shooter, then a contact; choose an appropriate weapon and salvo, and **Engage**. Unknown contact classification matters, and neutral traffic is out there.
- Ship missile defence is automatic, subject to detection, weapon range, channels, ammunition, damage and weapons-hold settings. Ballistic rounds are only met by interceptors built for them.
- R toggles radar; P sonar; E emissions control. F2 toggles the symbol key; F4 sensor rings; F5 trails; M sound. F1 briefing; F9 missions; F10 restart. F3 is an explicitly optional debug truth overlay.
- The event log lives under the unit panel. The defence board on the right is the threat-evaluation view: inbound rounds, their targets, time to impact, interceptors up and channel load per ship.

## What is implemented

Nine missions including a free-play sandbox; 30 platform types, 30 weapon families and 34 sensor definitions. Arctic Shield deploys 28 actors across air, surface, subsurface and neutral traffic in a sea state 4.

Radar horizon, passive/active sonar, ESM bearings, uncertain tracks, classification, stale tracks, target-motion analysis, layered missile interception, decoys, fire-control channel limits, gunfire, torpedoes, component damage, ROE, emissions control, datalinks, formations, aircraft launch/recovery/fuel, sonobuoys and opposing AI.

This release adds four systems and eleven actors:

- **Ballistic missile defence.** Rounds carry a flight profile; an aero-ballistic Kinzhal is a different defensive problem from a sea-skimmer and only interceptors that list `ballistic` (SM-3, and SM-6 as a terminal fallback) can meet it. The exoatmospheric interceptor gets the better shot.
- **Electronic attack.** A jammer set on the EA-18G Growler degrades every hostile radar within its reach against targets lying in its direction, and is itself the loudest emitter on the air for ESM. The display marks jammed bearings with a `J`.
- **Environment.** Scenarios declare a sea state. A rough sea shortens passive sonar and hides small and sea-skimming radar targets in clutter. The briefing, the header strip and the sonar readouts show it.
- **Damage control.** Ships restore knocked-out subsystems over time to a cap; the hull is not patched. Repair shows as a lamp on the map and a mark on the readiness bars.

New actors: Ticonderoga-class cruiser (Aegis BMD, SM-3, Tomahawk), Constellation-class frigate (SPY-6(V)3), Type 45 (SAMPSON, Aster 30), EA-18G Growler, Slava-class cruiser (Vulkan, Fort), Udaloy-class destroyer, Yasen-M SSN (Kalibr, Zircon), Tu-22M3 with Kh-32, MiG-31K with Kinzhal, Su-35S with R-77, Tu-142 maritime patrol.

The visual layer was rebuilt: APP-6/NTDS-style frames with platform glyphs, own-ship-centred range rings, animated radar sweeps and sonar pulses, plot histories and trails, engagement and threat vectors with time to impact, transient impact and intercept effects, hover cards, a threat-evaluation defence board, readiness bars, a redesigned front end with an own-force disposition chart, and an after-action report. All sound is synthesised at start-up.

## Realism boundary

An ambitious game foundation, not a high-fidelity replica of real Aegis software. Public names and broad roles are sourced in DATA_SOURCES.md; numerical performance and loadouts are estimates. Carrier air group capacity is deliberately compressed. Carrier sensors are simplified. The map is a local nautical-mile grid, not a geographic chart. Jamming, ballistic flight and sea-state effects are abstractions with no claim to any real system's behaviour.

Still absent: terrain/coastline masking, detailed radar scheduling/illumination, logistics/replenishment, save games, weather beyond sea state. Datalink isolation is incomplete: player tracks and automatic defence still use a faction-wide picture. Aircraft SAM shots do not share the complete automatic interceptor channel accounting. No claim of operational fidelity or calibrated combat probability is made.

## Develop

Open `project.godot` in Godot **4.7.2**. Source and web build are committed together.

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script tests/run_tests.gd
godot --path .
```

Install the official matching web export templates, then run `godot --headless --path . --export-release Web`. Pages serves `main:/docs`. Commit the updated `docs/play` build after changes. The engine uses Compatibility rendering, no web threads, and text resources to preserve all sensor/target arrays during export. Any script that declares a new `class_name` needs the import step before a headless run will see it.

## Validation

145 tests pass, including ballistic-vs-BMD interceptor selection, directional jamming, sea-state effects, damage-control repair and full actor resolution for the new scenario. Nine scenarios were advanced 30,000 simulated seconds with AI on both sides, seed 2, without script failures. Aegis Bastion reaches victory; Arctic Shield is a defeat when the AI commands the player's side, which is where the hardest mission should sit. This is a regression smoke test, not a balance study.

Godot engine licensing is in `docs/play/GODOT-LICENSE.txt`. Source ownership remains with the project author; no new license grant is inferred.
