# Current State — M17 Command Deck UX

56 platform types, 58 weapon definitions, 65 sensors, 114 inspectable models and ten missions.

The core watch flow is now **notice → focus → act → acknowledge**. The map has an explicit Plot Move mode with route/terrain preview, a clickable theatre overview, follow and fit controls, trackpad gestures, differentiated command/target brackets, and a synchronized display toolbar. The track file prioritizes and cycles contacts. The command dock keeps high-frequency, stateful actions visible, opens the engagement solution when a target is hooked, and reports partial group-order acceptance.

Command-K / Control-K opens a searchable context-aware action palette with shortcuts, current states, disabled reasons and full keyboard navigation. Primary controls have keyboard focus and visible focus treatment, modal screens block background hotkeys, and menu, briefing, gallery and palette closures restore the prior simulation pause state.

All ten charts derive from public-domain Natural Earth 5.1.1 land polygons, with separate islands and straits. Latitude/longitude graticules, geographic labels, a north arrow, mission areas and a theatre control make the chart readable. The renderer caches triangulation in world space, preventing zoom-dependent land-fill failures.

Mission conditions now match the task: escort merchants or Maud, deny a breakout, neutralize named surface combatants or a submarine, and preserve carriers through finite defensive watches. Airborne supporting units do not silently become extra hunt targets. Passage-denial missions support either elapsed time or neutralized targets; loss still wins any simultaneous evaluation.

Corrected class fits include Flight IIA, Type 45, Nansen, Udaloy, Slava, Gorshkov and Project 20380; Project 877 is separate from 636.3. Standard missions remove speculative frigates and MQ-25 detachments, correct Norwegian aviation and the Kola base location, and give the sandbox the correct Flight IIA hull identity. Ship turns now account for hull length and speed.

Read [M16 corrections and public sources](docs/REALISM_M16.md) for the detailed ledger and limits. Natural Earth is 1:10 million cartography, not a hydrographic chart. Bathymetry, measured terrain heights, real acoustic propagation and precise technical ship models remain outside this pass.

Validation: 224 tests pass, including 16 new UX regressions. Native captures at 1,600 × 1,000 and a 1,152 × 720 scaled laptop window verify that the full command deck remains present; a separate rendered capture verifies the Actions palette. Twenty-four native integration checks cover gallery lifecycle, mission-menu focus isolation, palette focus and briefing pause restoration. Existing reference-cycle cleanup warnings remain at native shutdown. See [M17 UX notes](docs/UX_M17.md) and the prior [M16 validation report](docs/VALIDATION_M16.md).

The source and browser package are prepared locally for review. GitHub has not been updated by this pass.
