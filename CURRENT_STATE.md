# Current State — M16 Geographic Charts and Mission Fidelity

56 platform types, 58 weapon definitions, 65 sensors, 114 inspectable models and ten missions.

All ten charts derive from public-domain Natural Earth 5.1.1 land polygons, with separate islands and straits. Latitude/longitude graticules, geographic labels, a north arrow, mission areas and a theatre control make the chart readable. The renderer caches triangulation in world space, preventing zoom-dependent land-fill failures.

Mission conditions now match the task: escort merchants or Maud, deny a breakout, neutralize named surface combatants or a submarine, and preserve carriers through finite defensive watches. Airborne supporting units do not silently become extra hunt targets. Passage-denial missions support either elapsed time or neutralized targets; loss still wins any simultaneous evaluation.

Corrected class fits include Flight IIA, Type 45, Nansen, Udaloy, Slava, Gorshkov and Project 20380; Project 877 is separate from 636.3. Standard missions remove speculative frigates and MQ-25 detachments, correct Norwegian aviation and the Kola base location, and give the sandbox the correct Flight IIA hull identity. Ship turns now account for hull length and speed.

Read [M16 corrections and public sources](docs/REALISM_M16.md) for the detailed ledger and limits. Natural Earth is 1:10 million cartography, not a hydrographic chart. Bathymetry, measured terrain heights, real acoustic propagation and precise technical ship models remain outside this pass.

Validation: 208 tests pass, including mission semantics, every coastline's triangulation, ship/base placement, patrol coastline crossings, named-objective references, equipment compatibility and hull turning. The rebuilt browser package runs and its mission, chart and gallery interactions were checked. Existing reference-cycle cleanup warnings remain at native shutdown. See [validation report](docs/VALIDATION_M16.md) for the scenario-run results and exact verification boundary.

The source and browser package are prepared locally for review. GitHub has not been updated by this pass.
