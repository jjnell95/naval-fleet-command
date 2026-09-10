# Current State — M12 Coastlines

The current setup, controls, validation and limitations are documented in README.md.

Completed since M11: coastlines and land masking. `Terrain` and `Landmass` (scripts/systems) hold a
scenario's land as closed polygons with a height, exact for point and course queries and rasterised
to an elevation grid for the sensor cycle. Land stops hulls (Movement slides them along a shore
rather than grounding them), masks radar, ESM and sonar above the sight line, refuses a shot that
has to stay low, kills a sea-skimmer or torpedo that meets ground, and steers the AI off a lee shore.
Seven scenarios are charted; the five shore air stations now stand on land. The tactical map, the
mission-menu disposition chart and the scenario editor all draw it, and the editor has a COAST mode
that traces, names and validates a coastline. F6 toggles the land layer.

Completed in M11: ballistic missile defence (flight profiles, SM-3, Kinzhal), electronic attack
(directional jamming, EA-18G Growler, ESM hears jammers), scenario environment (sea state affects
sonar and clutter), damage control (subsystem repair to a cap), eleven new platforms, nine new
weapons, eleven new sensors and the Arctic Shield mission. The visual layer was rebuilt: APP-6/NTDS
symbology with glyphs, own-ship-centred range rings, sweeps and pulses, histories and trails,
threat vectors, effects, hover cards, TEWA defence board, readiness bars, event log, new front end
with disposition chart, after-action report, and procedural sound.

Platform recognition art is rendered from original Blender models (`tools/blender/build_platform_art.py`,
PNGs under `assets/platforms`, loaded through `PlatformArt`): a tinted profile on the unit panel's card and
a plan-view silhouette on the map at close zoom, with the code-drawn shapes kept as the fallback for any
platform without a file. `tests/test_art.gd` keeps the art in step with `data/platforms`. The art also appears on the map's
hover card for own units and as a preview under the scenario editor's platform palette.

An in-game scenario editor (F8) places platforms, routes, objectives and environment, saves to
user://scenarios, imports and exports JSON and plays the result; custom missions appear in the menu.
A second graphics pass adds procedural water, curved weapon trails, hull silhouettes at close zoom,
an air-search ring, a firing-solution marker and a hit flash.

174 tests pass. Nine scenario smoke runs pass without script failures and with no unit aground; every
outcome matches the same sweep run on the pre-coastline commit. Aegis Bastion and
Arctic Shield reach victory under AI-vs-AI at seed 2, with the Kinzhal / SM-3 exchange exercised.

Known limitations: no bathymetry, no routing around a peninsula, no seeker or interceptor terrain
masking, no radar scheduling, replenishment or save games. Datalink and
engagement-channel accounting remain simplified. Jamming, ballistic flight and sea state are
abstractions. Engine/test shutdown reports reference-cycle leaks; no recurring gameplay script
failures were observed. See README.md for the full boundary.

HANDOFF.md is an archived M9 presentation brief; it is no longer the current task specification.
