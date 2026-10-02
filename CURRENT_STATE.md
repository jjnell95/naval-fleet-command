# Current State: M36 Missions, Saves and an Enemy with a Plan

Aircraft fly **missions** from Air Operations: a combat air patrol, a reconnaissance or ASW search area, or a strike on a held contact, chosen on the chart. The deck launches what it has ready, queues the rest and shows each airframe's state from queued to recovering. A CAP identifies unknown aircraft and intercepts only hostile ones; reconnaissance never fires; relief is opt-in per mission. Every ship and aircraft keeps its **standing station** through investigations, attacks, evasion and refuelling, and **S** sends it back. Two or more ships can share a **group attack** with one round budget and a shared assessment pause. The [M36 note](docs/2026-10-02-m36-missions-saves-and-an-enemy-with-a-plan.md) gives the design, the measurements and what was not verified.

A battle can be **saved and reloaded exactly**: Ctrl+Shift+S, Ctrl+Shift+L, Ctrl+Shift+O for the list (also from the desk), five rotating autosaves, checksummed files, in the browser too. A seeded battle saved and reloaded carries on byte for byte as if never interrupted, in one process and across processes.

The desk's **GAMEPLAY** row chooses **NORMAL** or **CLASSIC** (a 4× time ceiling, missile defence on the commander's orders with **X**, and attacks on contacts an investigation identifies as hostile), shown on a command-bar chip and kept with each save. The 1990 campaign has its own button. Combat the player could not observe no longer drops the clock to 1×.

The seven operations **react to the battle** and vary by seed: events fire on convoy progress, each side's own plot, readiness and damage; reports are datums with an error, never firing solutions; tasking changes arrive with an order. Every operation gives the enemy a **mission plan**: it scouts, holds fire until its own sensors classify what it is after, and attacks it together from several bearings. Carrier Watch adds four A-6E Intruders with Harpoons, so a strike on Slava competes with fighter cover for the deck. Six operations have two scripted openings that win on both tested seeds; Hormuz's two openings each win one seed of two.

The sensor cycle in the largest late battle costs a third of what it did with identical outcomes, and a per-frame time budget brings an order onto the screen in about 65 ms at 60× instead of about 7 s.

Validation is recorded in [validation-m36.json](docs/validation-m36.json).

# Previous: M35 Nine Missions, a Crew and Campaigns

Nine missions ship, down from 23: one 2027 operation in each chart region (North Cape, Taiwan Strait, Hormuz, Tartus), three 1990 operations and two training missions. The cut was made in the generators, which now reproduce `data/` byte for byte after three earlier hand edits were moved into them. Hormuz's neutral-loss condition now counts only the player's fire. The [M35 note](docs/2026-10-01-m35-nine-missions-a-crew-and-campaigns.md) gives the reasoning, the measurements and what was not verified.

The desk adds a **Campaigns** shelf: Northern Flank, September 1990 and Four Crises, 2027, each opened one operation at a time by a win at 60% or better in the commander's log. The crew speaks through the system's text-to-speech, interface advice has its own dimmer line, and an ambient sea and machinery bed plays. A contact's data display reads SOURCE (platform and set), %DAMAGE (estimated from your own hits) and plain COURSE and SPEED, a hovered contact reads out with nothing hooked, and F7 opens a classified contact's class. The Action camera follows an own strike round to its impact anywhere on the plot and cuts to any event the plot witnessed; the tether names an out-of-frame event without leaving the hooked ship.

Desk refreshes after the first cost about 0.1 ms instead of 30–55 ms, the shipped scenario data fell from 7.3 MB to 2.6 MB, and a landmass index cuts the Taiwan Strait's sight-line test from 61 to 21 µs. The sensor cycle's growth with radiating aircraft is the main remaining performance gap.

Validation is recorded in [validation-m35.json](docs/validation-m35.json).

# Previous: M34 The Command Loop

Research into the 1999 original's manual and reviews found that the project had rebuilt Fleet Command's screen but not its command loop; the [research note](docs/2026-10-01-fleet-command-command-loop.md) gives the sources, the diagnosis and the ranked remaining gaps.

A right-click on a hostile contact now orders a standing **Attack**: the hooked platforms close to their best weapon's range (INTERCEPT TRACK on the orders line), fire, let the salvo land and read the plot, and keep firing until the contact is destroyed or lost, the magazines are empty or weapons are put on hold, moving on to the next weapon when one runs out. A right-click on an unidentified contact investigates it, the cursor says which, and Shift+right-click opens the contact menu, which now leads with **Attack track N** and **Attack with**. The task reads only the held plot and never fires at a stale one.

The operations desk opens on the 14 authored operations again, with **Training** and **My Missions** beside them. Every mission ends with a graded mission effectiveness (task 60 on a win only, force 20, attrition 20, less 25 per neutral the player sinks and a pro-rata share for one damaged; before that penalty a victory grades 60–100% and a defeat 0–40%), and a commander's log keeps each operation's best result and date, shown on the desk.

Validation is recorded in [validation-m34.json](docs/validation-m34.json).

# Previous: M33 Command Intent

Contact inspection now drives data and 3D without discarding selected shooters. A direct contact-menu shot states its finite salvo and checks current ROE, range, guidance and ammunition. Persistent Investigate orders follow only held track positions and end on classification or unavailable/blocked contact, with attributed radio reports. Normal navigation and accepted aircraft recovery supersede them; fixed-wing aircraft retain forward flight.

The command strip exposes Chart and time menus. The live view exposes mouse camera/layout controls, captions the subject/action, frames the horizon by aspect ratio, and renders scenario-authored clouds/rain with a paused weather clock. Northern Passage's maintained generator includes its fictional weather and updated first orders. Original manual research, remaining gaps and verification are in the [M33 guide](docs/2026-09-30-fleet-command-intent.md) and [validation record](docs/validation-m33.json).

The integrated build preserves the current combat cleanup's Attack/Defence controls and missile tracking. It passes 660 regression tests and 231 native checks at 1280 × 720 and 1920 × 1080; fresh scenario results, CI evidence and the current browser-package hash are in the [combined validation record](docs/validation-m33-merge.json). The rebuilt browser package loads without page/script errors; inherited WebGL resize warnings remain. Known contacts use labeled sensor-estimate models, and aircraft cameras clear their own launch ship. The earlier M33 validation record is retained as a historical snapshot.

# Previous: M32 Command Watch

Graphics, UI and tasking now follow the supplied Fleet Command reference more closely. The chart has calmer relief, larger track numbers and a closer opening view of the convoy. A slim persistent command strip exposes routine orders. The live camera uses maritime daylight and improved framing; Nansen, Gorshkov and Steregushchiy have new original models and recognition art.

**Patrol / Shift+W** assigns a repeating circuit by clicking two corners. Validation checks platform availability, terrain, approach and turning room. Patrols use actual movement, sensors and endurance, retain evasion/resumption, and yield to navigation changes or aircraft recovery. Their task and legs remain visible while paused.

599 regression tests pass. Native interaction checks cover both 1280 × 720 and 1920 × 1080, with the existing interface suites, seeded Northern Passage outcomes, full scenario sweeps and local browser checks recorded in the [M32 guide](docs/2026-09-30-command-watch.md) and [validation record](docs/validation-m32.json). The inherited WebGL warnings on expanding the browser's 3D view remain; native checks pass. Validation was completed locally before merge; the linked records preserve that evidence.

# Previous: M31 Northern Passage

**Start Northern Passage** opens an original, paused introductory briefing directly from the existing operations desk. A Burke IIA, Nansen and one MH-60R protect Northern Light over an eight-nautical-mile dogleg. The freighter follows standing orders at its existing 15-knot cap; both escorts begin in formation. The opposing frigate closes under its own sensors and AI, among two neutral merchants. Deliver the freighter before 45 minutes; losing it or sinking a neutral with player weapons ends the operation in defeat.

Loss objectives can now filter responsibility by the firing faction, including later fire/flooding deaths. Civilian sinkings are separate from enemy kills. The after-action report retains objective results, finite ammunition expenditure, losses and a chronological journal of player-observed messages; it does not reveal hidden enemy callsigns. Weapons-free orders warn about unidentified contacts and civilian consequences.

Validation passes 587 regression tests, 115 assertions across seven ordinary-order trials, 29 graphical assertions at each requested resolution, the existing interface suites and 46 full-duration AI scenario runs. The actual-scene command driver verifies delivery, abandonment, deadline expiry and civilian-loss defeat without injecting damage or observations. The same seed is replayed and compared, and graphical checks cover 1280 × 720 and 1920 × 1080. Exact results, commands, screenshots and browser checks are in the [M31 validation note](docs/2026-09-30-northern-passage.md) and [machine-readable record](docs/validation-m31.json).

Chromium/SwiftShader emits WebGL buffer warnings when G expands the 3D view; this also reproduces in the unchanged M30 package. Native checks pass, and the normal browser command view works.

Full mid-engagement save/load remains the next playability milestone; custom scenario files are not saved games. Existing 1×/2×/5×/10×/30×/60× speeds, catalogue, geography and CDS display remain in use. This is a bounded milestone toward the supplied build brief. The milestone includes editable source and the rebuilt browser package.

# Previous: M30 Weapon Control and Track Solutions

QC follow-up: nested imports, open-water presentation, runtime-error test failures, wall-clock timing, held-track SAM guidance and shared Mk 13 service are repaired. Sensor/defence/AI scans and chart drawing are batched and indexed. See [QC_PERFORMANCE.md](docs/QC_PERFORMANCE.md) for behavior, limits and reproducible checks.

Ships and aircraft can commit multiple weapon types from one firing board, with separate per-unit quantities, launcher queues, ammunition reservations and cancellation. VLS launch service is shared with automatic defence; repeated paused orders no longer bypass launch spacing. Rounds are checked again before release, and weapons hold returns unfired reservations.

Shift+E opens Weapon Control. Shift+R shows the reference platform's role-coloured envelopes. The board and chart expose last-fix age, uncertainty, lead-intercept reach and seeker baskets without reading enemy truth. Distinct ordnance symbols and role filters extend the existing NTDS chart, right-click orders and three-pane CDS layout.

The 139-platform / 148-weapon catalogue includes corrected aircraft AAM typing, JASSM land targeting, UK/Japanese F-35B fits, Astute TLAM, airborne Russian ASW fits and a lightweight representative Orion load. ASW rockets deliver separate torpedo payloads; guided bombs depend on launch altitude. Exact performance and uncertain integrations remain labeled estimates or representative assumptions.

Validation: 564 regression tests, 47 command-screen checks, 19 aviation checks, 32 workshop checks and 24 weapon-control checks at each tested desktop size, plus 52 actual-scene battles of 6,000 seconds. The final 274-actor native sample reached 21.7 fps; frame stalls remain.

See the [operating guide and source review](docs/2026-09-29-weapon-control.md), [validation record](docs/validation-m30.json) and [catalogue audit](docs/catalogue-audit-m30.json). The release includes the editable source and browser package; GitHub Actions records test and Pages deployment status.

# Previous: M29 Fleet Workshop and Defensive Command

Custom missions are now the front door. A seeded fleet builder creates opposing 1990 or 2027 forces across four chart regions, with scalable formations and finite carrier wings. The editor adds platform search, bulk placement, undo/redo, fitted weapon and air-wing editing, reinforcement arrival times and multi-stage victory tasks. It validates files before import or play. The 22 legacy operations remain optional templates and test fixtures.

The player can deploy radar, infrared or acoustic countermeasures, order temporary evasive steering and resume the previous plan. Stores and deployment windows are finite; compatibility follows seeker type. The three interception policies coordinate guided commitments across escorts. RAM's passive RF/IR guidance no longer takes an illumination channel, and the terminal-seeker labels for JASSM-ER and LRASM are explicit.

Fleet Operations (J) exposes group readiness and orders. Selection groups use Ctrl+1–9 to store and Alt+1–9 to recall. Formations stop reusing the same five stations, respect a slower or damaged consort, and pass command to a surviving ship when their leader is lost. Shared threat geometry reduces repeated AI and chart work without sharing detections with disconnected units.

Validation: 545 regression tests, 47 command-screen checks, 19 aviation checks, and 32 exported workshop checks at each of 1600 × 900 and 1280 × 720 pass. All 52 actual-scene battles complete 6,000 simulated seconds without script errors, with no hulls grounded at the end. The 274-actor native stress sample improves from 12.4 to 20.2 fps, with noticeable large-salvo stalls still present.

See the [operating guide](docs/2026-09-29-fleet-workshop.md), [validation record](docs/validation-m29.json) and [source notes](DATA_SOURCES.md#fleet-workshop-and-defensive-responses-29-september-2026). The tested browser package is included in `docs/play` for deployment from `main`.

## Previous: M28 The Live View, Deep Strike and Torpedo Defence

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
