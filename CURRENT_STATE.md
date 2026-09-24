# Current State: M22 Command Deck Redesign and Browser Release

The game plays in any modern desktop browser from [GitHub Pages](https://jjnell95.github.io/naval-fleet-command/). A first visit downloads 71 MB (down from 119 MB) behind a branded loader. Phones are told what they are getting into before the download.

The interface was redesigned around the chart. A quiet design system reserves colour for meaning, uses original vector icons and moves shortcuts into tooltips. The top bar has a segmented time control, and a one-line status rail replaces the watch cards. Floating chart controls and a chart footer (source note, cursor position, scale bar) free the chart to take over half the screen at 1600 × 900. The design size is now 1600 × 900 with expand stretch, so browsers are never letterboxed.

A debugging pass fixed twelve defects, each with a regression test or interface check. The worst were a missile already shot down still hitting its target, and Space firing whichever button had focus. Others: a deck aircraft blanking the contact picture, unwinnable editor objectives, and departed raiders counting as destroyed. See the [M22 notes](docs/2026-09-24-presentation-and-browser.md).

Validation: 319 regression tests; 29 command-deck checks at 1600 × 1000 and 1600 × 900; 19 air-operations checks; a scripted browser session in headless Chromium with no console errors. CI now runs the tests and both interface suites on every pull request.

## Previous: M21 Cold War 1990

Four alternate-history 1990 operations now open through a mission desk with era filters, period artwork, command intent and first orders. Briefings separate orders, situation and controls. The clickable watch strip connects mission status, filtered contacts, detected threats, air operations and a wider chart; readable two-line mission/contact rows preserve keyboard navigation.

The separate period catalogue adds 20 platforms, 28 weapons and 25 sensors. The full game now has 15 missions, 94 platforms, 98 weapons, 106 sensors and 192 inspectable models. Historical sources distinguish dated fits from combat estimates, including Perry's shared magazine, Spruance's VLS refit, F-14A+ and separate hull/towed sonars.

AI submarines recognize usable torpedo ammunition; routed ASW aircraft lay spaced buoy fields on station; actual dipping helicopters resume their search. Breakout ships retain their routes and build their own contact picture. See the [M21 release and validation](docs/2026-09-24-cold-war-1990.md), [period source ledger](docs/COLD_WAR_1990.md) and [complete scenario runs](docs/validation-cold-war-scenarios.json).

## Previous: M20 Air Operations


The fleet has 74 platforms, 70 weapons, 81 sensors and 144 inspectable models. Air Operations (AIR / F3) exposes aircraft-type selection, launch quantity, individual readiness, fuel and landing destination. Recovery remains visible through approach, reserves compatible base capacity, transfers ownership only at touchdown and enters a refuel/rearm cycle before relaunch. The eleventh mission, Carrier Qualification, validates shipboard and airfield landings as actual training objectives.

See the [operating guide](docs/2026-09-23-air-operations.md), [source ledger](docs/AVIATION_ROSTER_M20.md) and [current validation record](docs/validation-m20.json).

Validation: 291 regression tests, 19 native aviation workflow checks and 24 native UI checks pass. All eleven missions pass two 1,200-second stability runs, plus Northern Vigil at 6,000 seconds. Native desktop/laptop layouts and the browser launch-to-landing exercise are verified.

## Previous: M19 Contact Fidelity and Stability

M19 improves sensor-report fusion, reacquisition, time-control interruption, relative-motion plotting and fleet cleanup. The Contact Solution panel exposes observation age and uncertainty; unresolved bearings have no claimed measured range. The overview's recurrent coastline triangulation error is fixed.

Validation: 264 tests pass with clean resource shutdown; 24 native interface checks pass; all ten missions pass two 1,200-second AI runs without errors, warnings or grounded hulls. Native desktop/laptop captures and the rebuilt browser flow are verified. See [M19 notes](docs/2026-09-23-contact-fidelity.md) and [validation record](docs/validation-m19.json) for scope and limits.

## Previous: M18 Sea Floor, Water Column and Damage Control

56 platform types, 58 weapon definitions, 65 sensors, 114 inspectable models and ten missions, now over a charted sea floor.

**Chart.** Natural Earth 5.1.1 bathymetry is interpolated offline (`tools/scenarios/import_bathymetry.py`) into one regional raster read by every mission through its map anchor. A shader behind the plot (`ChartFloor`) draws depth tint, baked relief and anti-aliased Natural Earth contours from a half-float texture. Past each scenario's coastline polygons, the raster's coast continues, dimmed, behind a neatline. The Tactical Overview uses the same tint, and the cursor readout gives depth, layer and convergence-zone water.

**Water column.** `Acoustics` handles four effects:
- The floor bounds submarine depth.
- A per-mission March thermal layer cuts range across it. Hull sets sit above; variable-depth bodies, dipping sets and buoys go under.
- Shelf water shortens passive and active ranges.
- Large arrays hear loud sources in deep-water convergence zones as bearing contacts with a bracketed range.

A firm radar or active plot is no longer blurred by a bearing from another sensor. AI submarines hide under the layer and come up to hold a surface contact. The player has UNDER LAYER. The GIUK Passage Virginia no longer starts in 20 m of water.

**Damage control.** Hits start fires (missiles) and flooding (torpedoes) that grow or shrink against damage control over the next hour. Damage control depends on ship size, remaining condition, time to organize, a per-hit draw and help from a consort within a mile. Ships lost this way are credited to the attacker. Systems are repaired only once the ship is safe. Decoys seduce a missile, which may lock the next ship in its cone. Burning ships trail smoke; fire and flooding have lamps, chips and event-log lines.

Validation: 249 tests pass. They include 13 ocean tests, 10 damage-control tests and 2 AI depth tests, and the 224 earlier tests are unchanged. Northern Vigil at 6,000 simulated seconds runs within about 1% of the previous commit's wall time. See [M18 model notes](docs/REALISM_M18.md) and [validation](docs/validation-m18.json).

## Previous: M17 Command Deck UX

The core watch flow is now **notice → focus → act → acknowledge**. The map has an explicit Plot Move mode with route/terrain preview, a clickable theatre overview, follow and fit controls, trackpad gestures, differentiated command/target brackets, and a synchronized display toolbar. The track file prioritizes and cycles contacts. The command dock keeps high-frequency, stateful actions visible, opens the engagement solution when a target is hooked, and reports partial group-order acceptance.

Command-K / Control-K opens a searchable context-aware action palette with shortcuts, current states, disabled reasons and full keyboard navigation. Primary controls have keyboard focus and visible focus treatment, modal screens block background hotkeys, and menu, briefing, gallery and palette closures restore the prior simulation pause state.

All ten charts derive from public-domain Natural Earth 5.1.1 land polygons, with separate islands and straits. Latitude/longitude graticules, geographic labels, a north arrow, mission areas and a theatre control make the chart readable. The renderer caches triangulation in world space, preventing zoom-dependent land-fill failures.

Mission conditions now match the task: escort merchants or Maud, deny a breakout, neutralize named surface combatants or a submarine, and preserve carriers through finite defensive watches. Airborne supporting units do not silently become extra hunt targets. Passage-denial missions support either elapsed time or neutralized targets; loss still wins any simultaneous evaluation.

Corrected class fits include Flight IIA, Type 45, Nansen, Udaloy, Slava, Gorshkov and Project 20380; Project 877 is separate from 636.3. Standard missions remove speculative frigates and MQ-25 detachments, correct Norwegian aviation and the Kola base location, and give the sandbox the correct Flight IIA hull identity. Ship turns now account for hull length and speed.

Read [M16 corrections and public sources](docs/REALISM_M16.md) for the detailed ledger and limits. Natural Earth is 1:10 million cartography, not a hydrographic chart. Bathymetry, measured terrain heights, real acoustic propagation and precise technical ship models remain outside this pass.

Validation: 224 tests pass, including 16 new UX regressions. Native captures at 1,600 × 1,000 and a 1,152 × 720 scaled laptop window verify that the full command deck remains present; a separate rendered capture verifies the Actions palette. Twenty-four native integration checks cover gallery lifecycle, mission-menu focus isolation, palette focus and briefing pause restoration. Existing reference-cycle cleanup warnings remain at native shutdown. See [M17 UX notes](docs/UX_M17.md) and the prior [M16 validation report](docs/VALIDATION_M16.md).
