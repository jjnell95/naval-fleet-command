# Current State: M28 The Live View, Deep Strike and Torpedo Defence

The 3D view's ships, aircraft and submarines look different now, most of them without any change to their models. Each surface is dressed at runtime in a finish that knows what it is: the navy's own paint (U.S. haze grey, the Royal Navy's lighter grey, Russian blue-grey, the PLA Navy's pale grey), plating seams, grime and rust, mottled decks, airframe panel lines, a submarine's rubber tiles. It is lit by a sky-and-sea hemisphere instead of the flat lavender ambient that washed every face to the same pale grey, with sun shadows when the view is swapped or full screen. Hulls are wet and foam-edged where the swell meets them, throw a bow wave under way, and a carrier's wake is continuous: it used to break into patches because its samples fell one swell wavelength apart. Ships show navigation lights on their proper arcs after dark, helicopters a turning rotor disc, and a submerged boat is drawn through the water with its form kept. The seven flat-tops in the operations (Nimitz, Ford, the 1990 Nimitz, Queen Elizabeth, Charles de Gaulle, America, Mistral) are rebuilt with their islands, angled decks, lifts, sponsons, markings and deck parks.

France's MdCN land-attack cruise missile is on the Aquitaine-class FREMM (8) and Suffren (4); in Tartus it answers the Bastion battery from outside its reach once the battery shows itself. Torpedoes are fought with acoustic decoys (Nixie, Sonar 2170, CANTO, submarine countermeasures) and the Russian Paket-NK anti-torpedo round instead of chaff, which now works only on missiles. The data display lays a ship's weapons out as a grid of short names and rounds, in job order, so the largest loadouts fit with the air-wing line; it never drops a system silently.

The browser build is rebuilt (57.1 MB) and runs in headless Chromium with no console errors.

Validation: 514 regression tests (483 before), 47 command-screen checks and 19 aviation checks pass. A before-and-after sweep of the 22 scenarios at two seeds runs clean with every outcome unchanged; 42 of 44 cases fire the same rounds and lose the same units, and the two that change are Hormuz, where Languedoc's MdCN opening leaves the IRGC swarm uncued and the battle quieter. The AI's eight-minute flight-time limit no longer applies to fixed targets, so it now uses MdCN on the Tartus battery and Tomahawk on airfields at their real ranges, keeping the last Tomahawk salvo for ships. A sweep of all 44 cases with that change leaves every outcome as it was; 72 rounds go past the old limit, four shore installations fall where two did, and the kept Tomahawks go at the Russian frigates when they come into reach. The frame budget under the chart is unchanged within a few tenths of a millisecond; full screen with shadows costs 17 more draw calls.

See [the M28 notes](docs/2026-09-28-live-view.md), [validation](docs/validation-m28.json) and [the source ledger](DATA_SOURCES.md#deep-strike-and-torpedo-defence-28-september-2026-later-the-same-day).

## Previous: M27 Ship Fits and the Reach Line

Every ship and submarine loadout was audited against its class's public fit. Seven hulls were missing weapons the real ship carries and were corrected: Tomahawk on the Arleigh Burke IIA and III, the Virginia and the Astute; Kalibr on the Improved Kilo (Project 636.3, not the 877); SM39 Exocet on the Suffren; a 35 mm CIWS, MU90 and a full Harpoon fit on the Iver Huitfeldt; RBS15 on the Visby. Two weapons are new (`millennium_35mm`, `sm39_exocet`), with generated models and renders. The hulls that are thin in service are left thin and are pinned by test with the reason: the Queen Elizabeth has no missile defence of her own, Juan Carlos I carries light guns only, the Type 26 has no anti-ship missile yet.

The data display's WEAPONS line now states each hull's reach, one figure per job (`STRIKE 250  AAW 100  CIWS 1.2  GUN 13  TORP 12 NM`), so a ship with a single close-in gun reads as exactly that. The unit panel no longer rounds a Phalanx's 1.2 nm to "1 nm".

Validation: 483 regression tests (466 before), 46 command-screen checks and 19 aviation checks pass. A before-and-after scenario sweep of all 22 operations at two seeds passed 44 of 44 on each side with no grounded hulls, and changed the outcome in one case of 44 (Bashi Channel at seed 13, running to a win, by ordinary divergence: no Tomahawk was fired in it). The browser build was not rebuilt.

See [the M27 notes](docs/2026-09-28-ship-fits.md) and [the source ledger](DATA_SOURCES.md#ship-fit-review-28-september-2026).

## Previous: M26 Final QC and Optimisation

A pass over the whole game as it stands, on the M24 CDS screen and the M25 operations. Every screen was screenshotted and reviewed; the frame budget was measured with a new `--perf` dev flag and the chart's script cost roughly halved in the largest operations; the defects that survived (track numbers smearing in a formation, objective labels printing over each other, the track file board overflowing its panel, readouts peeking out from under the boards, the desk's area chart printing sea names over land names) are fixed with tests; the console, the test runner, the code and the docs were cleared of noise. Nothing in the model changed except the order of two checks in the sonar pass.

Validation: 466 regression tests, 46 command-screen checks and 19 aviation checks pass, with a clean shutdown. The scenario sweep of all 22 operations at two seeds passed. The browser build was rebuilt and booted in headless Chromium with no console errors.

See [the M26 notes](docs/2026-09-28-final-qc.md) and [validation record](docs/validation-m26.json).

## Previous: M25 Fleet Operations

Fourteen expanded operations and eight exercises now share the preserved M24 CDS interface. Operations have staged objectives, continuous station and destination holds, reserve aircraft, follow-on raids and finite aviation reload stocks. Modern U.S. carrier operations field fictional 59-aircraft wings with separate CAP and maritime-strike fits. Cold War carriers retain an explicitly partial, period-correct fleet-defence detachment.

Missile defence has separate area and point-layer budgets, per-ship close-in allowances, launcher cadence and radar-support loss. A remote cue cannot give radar-dependent interceptors line of sight through terrain or below their own horizon. Performance remains a game model, not operational fidelity.

Validation: 461 regression tests, 46 command-screen checks and 19 aviation workflow checks pass. All 22 scenarios passed the stability sweep; extended Northern Convoy and Carrier Watch runs reached victory. Browser deployment and air planning were checked with no console warnings or errors. Baseline shutdown resource warnings remain documented.

See [the M25 change and source notes](docs/2026-09-27-fleet-operations.md) and [validation record](docs/validation-m25.json). The browser package is included in `docs/play` for GitHub Pages publication from `main`.

## Previous: M24 The CDS Screen

The command screen was rebuilt as a late-1990s fleet-command CDS screen, matched against that era's manual and screenshots and rendered at modern quality, with original code and art. A relief-shaded tactical chart runs edge to edge across the top two-thirds of the window. Below it are a square regional map, an always-on 3D view of the hooked platform with tether, fly-by, action and detached cameras, and a navy data display with the watch time, time scale and a message lamp. The top bar, status rail and side panels are gone: orders go through right-click menus, hotkeys and grey pop-up dialogs, and the old dock, task group and track file panels live on the status boards (A). The radio line at the foot of the chart carries each unit's traffic, and another side's units are named only by the track the plot holds.

The chart is a hypsometric relief map: land heights from GMTED2010 (USGS, public domain) on each region's sea-floor grid, the sea in stepped blue bands, NTDS symbols with white track numbers and velocity leaders, and graphic symbols on Tab. Dialogs, menus and the front end wear a 1999 grey skin over an original dusk render from the game's own 3D scene. Several keys moved to make room for the CDS bindings (G swap, F8–F12 cameras, F10 full-screen 3D, A boards, H key commands); H lists them all. See the [M24 notes](docs/2026-09-27-cds-screen.md).

Validation: 445 regression tests; 42 command-screen checks at 1600 × 900 and 19 air-operations checks under Xvfb; a 44-case scenario sweep at 6000 s per case through the new screen, all clean, 0 grounded hulls, with the same outcomes as M23; an adversarial review whose 20 confirmed findings are all fixed; the browser build driven through the desk, briefing, command screen, boards, swap and full-screen 3D in headless Chromium. See [validation-m24.json](docs/validation-m24.json).

## Previous: M23 World Theatres, Shore Batteries and the World View

The game now spans four chart regions and twenty-two operations. Global Natural Earth land and bathymetry were extracted into regional charts for the North Atlantic, the Western Pacific, the Arabian Sea and Red Sea, and the Mediterranean; the runtime picks the region from the scenario anchor, so every mission has a continuous sea floor under it. A generated 2027 catalogue adds 45 platforms, 43 weapons and 58 sensors for the PLAN, the Japanese Self-Defense Forces, Iran, Russian coastal forces and civilian tankers, each with an inspectable model and recognition art built by a Blender-free pipeline.

Installations ashore fight. Coastal missile batteries, SAM sites, ballistic-missile and drone sites engage from the faction picture without moving, fire out over their own coast, stand on their ground for radar horizons and masking, and can be struck by land-attack rounds (Tomahawk, NSM, JSM, JASSM-ER, CJ-10). Ski-jump carriers have their own deck rules.

Seven operations are new: Bashi Channel, Taiwan Strait, Spratly, the Sea of Japan in 2027 and in 1990, the Strait of Hormuz and the Tartus line. All twenty-two carry a commander's intent, first orders, difficulty and play estimate, and the operations desk shelves them by theatre. The scenario builders validate every position, patrol leg and objective against the shipped coastline.

A 3D world view (T, or the plot's WORLD button) shows the sea around the selected unit from a bridge, orbit, overhead or chase camera: own ships, aircraft and submarines as models on a sun-lit ocean, contacts only as the plot holds them, weapons only when detected. The browser build carries the new models and art: a first visit downloads 91 MB (53 MB game pack, 38 MB runtime), cached after that.

Validation: 351 regression tests; 29 command-deck checks and 19 air-operations checks under Xvfb; a 44-case scenario sweep at 6000 s per case with 0 grounded hulls; full-watch AI-versus-AI runs of every new operation; the browser build booted in headless Chromium without script errors. See [validation-m23.json](docs/validation-m23.json). See the [M23 notes](docs/2026-09-27-world-theatres.md) and the [2027 theatres ledger](docs/THEATRES_2027.md).

## Previous: M22 Command Deck Redesign and Browser Release

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
