# Current State — M14 Fleet Presentation

42 platforms, 41 weapon definitions, 51 sensors and ten missions. Northern Vigil fields 34 actors.

M14 adds 83 original runtime 3D models, 83 beauty renders, lightweight gallery thumbnails, colour tactical plan views and an interactive fleet/ordnance gallery. The new stage supports drag/orbit, wheel zoom, profile and plan presets, reset and auto rotation. Ship loadout cards lead to weapon inspection; weapon entries link back to carrying platforms. The gallery preserves the prior pause state and stops rendering when hidden.

The command screen has a new font system, rendered selected-unit cards, weapon previews, inspection buttons, a revised watch overview, clearer readiness bars and map controls. The menu has a large fleet-art hero. Map zoom extends far enough to see aircraft silhouettes; ship wakes and missile/torpedo treatments are visual only. Weapon trails retain only observed positions and reset when the console changes. Fleet and track lists preserve their scroll position.

M13 simulation and catalogue work is retained: independent local/shared tracks, observer-aware defence, manual/automatic SAM channels, protected neutral identities, deck compatibility/cycles/diversions, BMD altitude gates, VLS metadata and the expanded joint task group.

Validation: 190 tests and 18 native UI checks pass; the exported package also passes all 18 UI checks. Details are recorded in [VISUALS.md](docs/VISUALS.md). See [REALISM.md](docs/REALISM.md) for public sources and model limitations. Existing shutdown reference-cycle warnings remain. New work is on a review branch until merged.
