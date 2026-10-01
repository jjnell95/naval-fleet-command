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

## M35 Nine missions, a crew and campaigns

The mission list cut from 23 to nine, one distinct command problem each, through the generators (which now reproduce `data/` byte for byte). The seven operations also run as two campaigns gated on the commander's log. The crew speaks, an ambient bed plays, contacts read out with source and estimated damage, and the Action camera follows a strike to its impact anywhere the plot witnessed it. A landmass index cuts the heaviest chart's sight-line cost. See [the M35 note](docs/2026-10-01-m35-nine-missions-a-crew-and-campaigns.md).

Next: the sensor cycle's cost still grows with radiating aircraft (about 8 ms a tick early in the Taiwan Strait, 22 ms forty minutes in), so high time compression cannot keep up late in the largest battle. Report unchanged held pairs less often, then re-baseline the sweep. After that, the M34 note's remaining ranked gaps: global options with a Classic preset, tasking that arrives during the fight, and launching a mission rather than an airframe.

## M34 The command loop

The standing Attack order, right-click defaults with cursor feedback, the authored operations back on the front door, mission effectiveness and the commander's log. See [the research note](docs/2026-10-01-fleet-command-command-loop.md), which ranks what is still missing against the 1999 original. In order: a crew you can hear (spoken acknowledgements and an ambient bed, with interface advice moved off the radio line); global game options with a Classic preset (player-managed missile defence, a 4× time ceiling); tasking and intelligence that arrive mid-mission, with hidden objectives and seeded random starts; aircraft launched to a mission (CAP stations, identification sweeps, strikes, rally points, Return to Station); a campaign with effectiveness gates, after mid-mission save; an Action camera that reaches the whole battle; a fuller contact readout (sensor and platform source, estimated damage, hover-to-read, F7 to the contact's entry); stations and group attack; tutorials taught by doing; and a debrief replay of the truth.

## M32 Command Watch

Repeating player patrol areas, a persistent command strip, a more legible relief chart, maritime daylight and three original escort models improve the fleet-command experience. Patrols integrate with movement, emissions, fuel, recovery, formation and evasion. See the [M32 guide](docs/2026-09-30-command-watch.md).

## M31 Northern Passage and the next playability milestone

An original escort is accessible directly from the operations desk. Standing convoy orders, player-attributed neutral-loss objectives and an observed-event debrief complete a tested first-operation loop on the existing simulation. See the [M31 guide](docs/2026-09-30-northern-passage.md).

Next: versioned mid-engagement save/load, including simulation time, PRNG state, units, orders, formation and aviation references, sensor/track history, weapons and launch queues, cooldowns, objectives and the observed journal. Validate save/reload continuation against an uninterrupted seeded run before expanding campaign scope. Current custom-mission JSON saves only scenario definitions.

## M30 weapon control and catalogue accuracy

Mixed salvos across selected units, visible launch queues, role-specific envelopes and observer-held firing solutions retain the classic CDS workflow. ASW rockets now deliver a separate underwater payload; aircraft altitude and several national weapon fits are corrected. See [the M30 guide](docs/2026-09-29-weapon-control.md) and [validation record](docs/validation-m30.json).

The next fidelity gap is the loading model: aircraft station restrictions and individual launcher modules remain abstracted. The current catalogue describes representative scenario fits, not every certified configuration.

## M28 the live view, deep strike and torpedo defence

The 3D view's ships, aircraft and submarines dressed in their navies' finishes, lit by a sky and sea
hemisphere with shadows when the view is large, sitting wet in the water with bow waves and continuous
wakes, and showing navigation lights on their arcs after dark; the seven flat-tops in the operations
rebuilt; MdCN on the French FREMM and Suffren; torpedoes fought with acoustic decoys and Paket-NK
instead of chaff; the data display's weapons in columns; and the browser build rebuilt. See the
[M28 notes](docs/2026-09-28-live-view.md).

The most useful next steps are torpedo countermeasures for the navies no public source fits yet (the
PLAN and Japanese hulls are the ones that matter in the operations), class-specific geometry for the
next most-seen hulls (the Burke's older Blender model is the weakest in the view now the carriers are
rebuilt), and an underwater view for a submerged subject; the camera stays above the water.

## M27 ship fits and the reach line

A weapon-fit audit of the whole fleet: seven hulls corrected to their public fits, two weapons added, the hulls that are thin in service left thin and pinned by test, and the reach of each hull's weapons stated on the data display. See the [M27 notes](docs/2026-09-28-ship-fits.md).

The most useful next steps are a torpedo-defence system (a towed decoy, a hard-kill rocket) once torpedo fights matter in the operations, the MdCN cruise missile for the French hulls, and a layout that fits the largest hulls' weapon lists on the data display.

## M26 final QC and optimisation

Every screen reviewed, the frame budget measured (`--perf`) and the chart's script cost roughly halved in the largest operations, the surviving screen defects fixed with tests, and the console, the test runner, the code and the docs cleared of noise. See the [M26 notes](docs/2026-09-28-final-qc.md).

The most useful next steps are a per-view mesh for the coastline stroke (the last few milliseconds of the chart's frame in Norway), a frame budget measured on real GPUs in the browser, and a look at the sensor cycle's cost in the 115-unit operations at full time compression.

## M24 the CDS screen

The command screen rebuilt in the manner of the late-1990s fleet-command games: an edge-to-edge relief chart, regional map, always-on 3D view and data display; right-click orders, status boards, a radio line and the CDS key map; a 1999 grey skin on every dialog and screen. See the [M24 notes](docs/2026-09-27-cds-screen.md).

The most useful next steps are a measured frame budget for the always-on 3D view on real browsers and GPUs, an allied identity in the track model so the orange symbols have something to mean, and higher-resolution land heights for close-in coastal work.

## M23 world theatres, shore batteries and the world view

Four Natural Earth chart regions, a 2027 Pacific, Gulf and Mediterranean catalogue of 45 platforms with art and models, installations ashore that fight and can be struck, ski-jump carriers, seven new operations (22 in all) with full briefing cards on every mission, theatre shelves on the operations desk, and a 3D world view that obeys the information model. See the [M23 notes](docs/2026-09-27-world-theatres.md).

The most useful next steps are a campaign thread across a theatre with persistent losses and magazines, replenishment at sea, mine warfare for the Gulf, and coast-guard and maritime-militia traffic for the South China Sea.

## M22 command deck redesign and browser release

The interface was rebuilt around the chart on a code-defined design system. Twelve defects were fixed, each with a test, and a lighter browser build (71 MB first load) now publishes through GitHub Pages. CI runs the tests on every pull request. See the [M22 notes](docs/2026-09-24-presentation-and-browser.md).

The most useful next steps are an introductory mission that requires the player to identify and engage, and keyboard-free touch controls if phone play ever matters.

## M20 air operations

Aircraft-type selection, explicit carrier/airfield landing, recovery reservations, visible approach and complete sortie turnaround are implemented. A no-opposition qualification exercise teaches the workflow. The roster adds 18 platforms and 12 weapon families with full recognition art. See the [M20 guide](docs/2026-09-23-air-operations.md) and [validation record](docs/validation-m20.json).

Further aviation work should prioritize finite base stores, sustained sortie planning and weather/deck constraints before adding more nominal airframe variants. These are future features, not claims about the present model.

## M19 follow-on

Contact fidelity and stability are locally implemented and validated; see [M19 notes](docs/2026-09-23-contact-fidelity.md). Remaining priorities are an observability-based passive tracker, full-duration mission balance runs, and measured rendering/simulation performance budgets. Publication and deployment are separate from local validation.
