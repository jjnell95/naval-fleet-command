# Current State — M15 Air Power and Real Geography

55 platforms, 51 weapon definitions, 65 sensors and ten missions. Northern Vigil fields 78 actors across two carrier air wings.

M15 sites every mission in real water. Each scenario is anchored to a latitude and longitude, and ships, bases, coastlines and patrol legs are projected from real coordinates; ships carry their pennant numbers and squadrons their designations. The conflict remains fiction. Coastlines are coarse outlines at real positions, generated from `tools/scenarios/geography.py` by `tools/scenarios/build_scenarios.py`.

Carrier aviation is now a deck cycle: parallel catapults, a single angled deck for recovery, and a turnaround that refuels, rearms and respots an airframe before it counts as a sortie again. Ships sail with their embarked detachments automatically, so a hangar is never empty by accident. Thirteen new air platforms — tankers, shipboard drones, AEW helicopters, armed UAVs — and ten new weapons including LRASM and JSM. Aircraft can be based off the chart and refuel in the air.

Three simulation defects were found and fixed along the way: threat attribution that charged unreachable rounds to ships, strike aircraft overflying what they were shooting at, and surveillance aircraft searching an eleven-mile ring around their own airfield. See [REALISM.md](docs/REALISM.md).

M14 adds 83 original runtime 3D models, 83 beauty renders, lightweight gallery thumbnails, colour tactical plan views and an interactive fleet/ordnance gallery. The new stage supports drag/orbit, wheel zoom, profile and plan presets, reset and auto rotation. Ship loadout cards lead to weapon inspection; weapon entries link back to carrying platforms. The gallery preserves the prior pause state and stops rendering when hidden.

The command screen has a new font system, rendered selected-unit cards, weapon previews, inspection buttons, a revised watch overview, clearer readiness bars and map controls. The menu has a large fleet-art hero. Map zoom extends far enough to see aircraft silhouettes; ship wakes and missile/torpedo treatments are visual only. Weapon trails retain only observed positions and reset when the console changes. Fleet and track lists preserve their scroll position.

M13 simulation and catalogue work is retained: independent local/shared tracks, observer-aware defence, manual/automatic SAM channels, protected neutral identities, deck compatibility/cycles/diversions, BMD altitude gates, VLS metadata and the expanded joint task group.

Validation: 197 tests pass, and all ten missions complete two 6,000-second AI smoke runs (seeds 2 and 13) with no grounded hulls or script errors. The two largest missions are now heavy: Northern Vigil simulates at roughly 25x realtime on a modest machine, against sub-second costs for the small ones. 18 native UI checks pass; the exported package also passes all 18 UI checks. Details are recorded in [VISUALS.md](docs/VISUALS.md). See [REALISM.md](docs/REALISM.md) for public sources and model limitations. Existing shutdown reference-cycle warnings remain. New work is on a review branch until merged.
