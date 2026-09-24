# Roadmap

| # | Milestone | Status |
|---|---|---|
| 0 | Bootstrap — project, dirs, memory files, Main scene, launches | **DONE** |
| 1 | Tactical Sandbox — map, zoom/pan, coords, 4 ships, select, move, speed/heading, time accel | **DONE** |
| 2 | Contacts & Radar — radar, tracks, classification, stale tracks, sensor rings, contact panel | **DONE** |
| 3 | Surface Combat — ASMs, flight, envelopes, attack order, damage, ammo, victory (2v2 "Shadow Line") | **DONE** |
| 4 | Defensive Combat — incoming detection, SAM, CIWS, countermeasures, auto self-defense | **DONE** |
| 5 | Enemy AI — search, detect, approach, fire, defend, retreat (state machine, imperfect info) | **DONE** |
| 6 | Mission Framework — scenario loader, objectives, win/loss, briefing, restart, 3 scenarios | **DONE** |
| 7 | Submarines & Sonar — depth, passive/active sonar, torpedoes, ASW | **DONE** |
| 8 | Aviation — aircraft, launch/recovery, fuel, roles, MPA, helicopters | **DONE** |
| 9 | Operational Depth — ESM, datalinks, EMCON, radar horizon, EW, formations, ROE, damage | **DONE** |
| 10 | Presentation — graphics, audio, menus, briefings, tooltips, polish | **DONE** |
| 11 | Aegis Command II — BMD, electronic attack, sea state, damage control, 11 actors, visual rebuild | **DONE** |
| 12 | Coastlines — land polygons, terrain masking, grounding, coastal AI, chart rendering, editor | **DONE** |

Initial platforms (M1–M5 only): Arleigh Burke DDG, Fridtjof Nansen FFG, Admiral Gorshkov FFG,
Steregushchiy corvette. P-8A deferred until aviation/off-map sensor support is needed.

## M20 air operations

Aircraft-type selection, explicit carrier/airfield landing, recovery reservations, visible approach and complete sortie turnaround are implemented. A no-opposition qualification exercise teaches the workflow. The roster adds 18 platforms and 12 weapon families with full recognition art. See the [M20 guide](docs/2026-09-23-air-operations.md) and [validation record](docs/validation-m20.json).

Further aviation work should prioritize finite base stores, sustained sortie planning and weather/deck constraints before adding more nominal airframe variants. These are future features, not claims about the present model.

## M19 follow-on

Contact fidelity and stability are locally implemented and validated; see [M19 notes](docs/2026-09-23-contact-fidelity.md). Remaining priorities are an observability-based passive tracker, full-duration mission balance runs, and measured rendering/simulation performance budgets. Publication and deployment are separate from local validation.
