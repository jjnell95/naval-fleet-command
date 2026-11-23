# Changelog

Most recent first. The earlier history is compressed to a line or two per milestone; the full notes and validation records are in git history.

## Overhaul, November 2026

A review of the whole game after M43, fixed area by area.

### Contacts and the plot

- Passive contacts are ranged from the reach they were heard at and from bearing rate across a turn, with an honest uncertainty. A contact's last range is carried forward on new bearings instead of jumping to a nominal guess.
- A bearing-only contact is drawn as a line from the unit that hears it, with its number at the end, instead of a placed symbol.
- A measured plot has its domain on the first look, so weapons can be laid on it at once. A missile-quality plot needs a sound range solution.
- Aircraft are fixed from intercepts only on lines taken together, and the first radar plot is taken outright.
- Lost contacts age by what they are. A contact found again where it was keeps what was known of it; one found elsewhere gets a new number. A stale plot that is hit leaves a datum.
- Fixed sites and contacts known to stand ashore get no course or speed and are never dead-reckoned. An estimated plot closes on a reworked solution no faster than the contact could travel.
- Lookouts recognise along the sight line, class before name, and the track file says what evidence would classify a contact.
- A pinging dipping sonar can be heard; sea state and damage affect ping intercepts and sonobuoys; a submerged boat's ESM is deaf; a contact's radiating state expires.
- A ship with her radar off is warned of inbound missiles by ESM on a searching seeker and by eye at close range.

### The commander's picture

- The chart, the inbound warnings and the opening hook show the force's picture, whatever is hooked.
- A unit that is deep or off the link reports the contacts it holds on its own picture on the radio, once per contact. A boat calls her own contacts without waiting for a signal.
- An aircraft with a datalink keeps no private picture.
- The hook stays on a contact as one picture hands it to another.

### Attacks, investigations and tasks

- An attack or investigation no longer stops the ship: she fires when in reach without touching her plan, closes briskly, keeps way on, and goes back to the interrupted route, speed or station when the task ends. The radio says when a platform resumes its route.
- Strike aircraft hold off after release and hold where a task ends. Aircraft fly their tasks at no less than cruise speed.
- With land in the line of fire, a ship moves to the nearest point she can reach that clears it, and a stall guard measures the way she has made.
- A standing attack whose line of fire holds a neutral holds fire and keeps the task while the traffic clears, and says so.
- Right-click investigates any contact of unknown allegiance, and **Identify contact** is offered on all of them, including an unknown of known class. A dipping helicopter localises its own bearing from the dip.
- Task results stay on the readout after a crew return to station.
- A consort firing from her station inherits a lost guide's route.
- The standing attack chooses the gun at small craft inside its reach, else the cheapest round meant for the target that reaches with margin, and sends rounds enough to finish what the plot says is left of the contact, allowing for its class's defences. A CAP's pursuit defaults to 60 nm. A torpedo attack begun too close opens beyond the enable run. A strike aircraft held from firing holds off the target.

### Weapons and seekers

- Seekers take the designated contact or the unit nearest the aim point, never their own side, and look before they lock. A shot with a held neutral or ally in the seeker basket is refused, and automatic anti-air fire holds with an own aircraft in the basket.
- A round whose target is gone searches a few seeker radii on, then ends TARGET LOST. A missile at an aircraft coasts through a short break in guidance.
- Heavyweight torpedoes from tubes are wire-guided and follow the plot their boat keeps working. Every torpedo's minimum range is beyond its enable run. Torpedo decoy resistance is rated by seeker generation, and the Rastrub and Yu-8 fly out as rocket-thrown weapons.
- Gun shells are on the missiles' damage scale by calibre, gun accuracy depends on range and target speed, and guns that bombard can be laid on a contact ashore.
- Ballistic missiles dive and can miss. The shared launcher timer is split into salvo spacing and a short cell service, so interceptors are not held behind a queued strike.
- A tube torpedo is steered down its wire only while its firer is afloat and holds the contact; a torpedo searching with nothing in its seeker weaves either side of its course, and one that reaches its aim point empty searches a figure of eight about it for 150 s and ends NO ACQUISITION instead of running out its battery. A torpedo shot from inside its enable run is refused as TOO CLOSE.
- A torpedo's hit chance falls for the target's speed only when her side has heard it and she is running from it. Decoys break an acoustic torpedo's lock instead of deleting it: it circles where it lost the ship and usually ends DECOYED; wake-homers ignore decoys. A fitted ship warns of a torpedo inside three miles and, on automatic countermeasures, turns away and runs.

### Missile defence

- The limit is on interceptors in the air at a round across the force, not rounds ever fired: leakers are re-engaged, shoot-look-shoot, cheapest layer first, ballistic-capable rounds are kept back, and guns fire every cycle.
- Weapons Hold stops attacks only: a holding ship still fires interceptors, guns and anti-torpedo rounds at weapons threatening the force.
- Manual missile defence leaves point-defence missiles and guns to the crew. **X** with no round named clears the whole raid until the sky is quiet or weapons are put on hold, and goes to the whole force when no missile-defence ship is hooked.
- A detected round with no lock is engaged on detection if its course brings a ship inside its seeker's reach.
- An escort whose only bar to defending is her own radar being off lights it and fights; under a radar-silent order she holds fire and says so once a raid.
- Weapons Free against aircraft keeps one round in the air at a track across the force, a pair only at a fast closing jet.

### Sensors and the catalogue

- The escorts carry the hull sonars they are built with, every surface ship has her own radiated noise, submarine and towed-array hearing is longer, dipping sets are shorter, and a lookout no longer out-sees a radar against boats.
- Weapon and sensor definitions that nothing carries are deleted, with their models and renders. An older save that names a retired Sidewinder id still loads.
- A hull with ASW rockets and tubes states one anti-submarine reach on the weapons line.

### Movement and stations

- Ships route round the coast by sea. A hull the coast holds stops and reports it, and a line of fire is cleared against the coastline itself.
- Station keeping steers for a station led by the guide's velocity, and the guide paces the group a few knots under its slowest consort. A helm order to a formation escort interrupts her station instead of ending it, so **S** takes her back and **Rejoin formation** is offered. A speed order to a consort keeping station is refused with a reason.
- A course order to a ship lying stopped gets way on. A last waypoint inside the turning circle is reached by coming round to it, not dropped.
- Aircraft keep a safety height over the land below them and along their next two minutes of track, and altitude orders are held to a per-type minimum above the sea.
- A helm or task order keeps a towed array streamed; only evasion or too much speed recovers it, and an unordered recovery is reported.
- Every operation opens with its guide on her route (a watch carrier on a 25 nm circuit), the escorts formed on her where the builder placed them and the pickets on their own lines, so **Return to Station** means something from the first second.

### Submarines

- Under Classic rules a boat out of touch turns away from a torpedo she hears and snorkels by herself at a critical battery, reporting it at her next check-in. Evade and decoy orders are never queued. A snorkel order delivered in a check-in window keeps her up to charge.
- A boat on a breakout route gets out of the way of a torpedo running at her, then takes up the route again; a boat already found may shoot back beyond the transit's torpedo range.
- A boat holding only a bearing works legs either side of it for a solution, and a wire-guided torpedo goes on a rough range well inside its reach.

### Air operations

- A CAP commits on a hostile inside its own missile reach and on a raid closing on it or on what it covers, pursues 60 nm by default, and flies a square inscribed in its ring. **Intercept with fighters** goes for the contact at dash, fires and comes home. The ready alert scrambles on a raid closing inside 220 nm.
- The deck recovers the aircraft with the least fuel to spare first and lands helicopters on a spot of their own, so a recall runs nobody dry. Fixed-wing aircraft leave the deck with flying speed, and a section goes off 15 s apart.
- Reconnaissance leaves hostile contacts alone, and an unarmed sensor aircraft flies at least 40 nm off any ship not known to be harmless; a strike turns for home once its fire-and-forget salvo is away. A refused launch names the facility, and a mission whose aircraft are all lost ends 'All aircraft lost'.

### Operations

- In Hormuz the Qeshm battery comes out of its hide after 10-15 minutes and the ballistic battery after 15-25 minutes, once a drone has reported a tanker (by 40-50 minutes at the latest), so the convoy forms before the first salvo; the UKMTO fire-mission warning follows the ballistic battery.
- Nicholas in the convoy and Spruance in the carrier watch open radiating, and the North Cape Kilo starts inside the screen, as the briefing says.

### The enemy

- An AI ship under fire answers any hostile it holds and can reach, whatever its plan is waiting for, and keeps shooting while it turns away from a round.
- The AI picks shots with the launcher's own test and falls through to the next weapon when one is refused.
- A ship patrolling with her radar off that is hit, or sees a round coming, radiates until the shooting has stopped for a while.

### Screen and reports

- The chart opens on the player's ships unless the scenario sets a focus, **Home** fits the same frame, and the coverage layer starts off.
- A **Filters** submenu on the chart menus shows or hides hostile, neutral and unknown contacts, routes and the range grid.
- The data display credits a plot to the sensor and evidence that made it, and the readout has its own right-click menu.
- Own rounds shot down or missed are reported one line a salvo; the salvo receipt says what is away and what is on the launcher; time compression drops once per engagement; the firing board keeps the running group's budget.
- A hit on a contact held as neutral or friendly, or an own round hitting an unidentified ship it was not fired at, is reported as an alert naming it.
- The radio says when chaff, flares or a decoy are fired with no seeker of their kind in reach, and a refused group order names the platform and the reason.
- Command keys are not taken from a focused text field. **Esc** or **F1** returns from the pre-mission briefing to the desk; the debrief stays up under **Space** and reopens with **F1**, the chart menu or Actions.
- The radio line has a band of its own: chart names and track numbers are placed clear of it, with a plate behind its rows. Patrol, ring, CPA and time-to-go captions are placed with alternatives instead of printed over each other, contacts on one spot share one label, and the hooked platform's number sits beyond its brackets.
- A right-click on the regional display sends the hooked platforms there, **Shift** adding a leg, and says why when it cannot.
- An intercept is drawn as a line from the deck to its contact, as a strike is, with no hold ring to drag; a torpedo's minimum-range ring and legend give the range inside which the shot is refused, its enable run included.
- Every status board on every tab fits inside the chart at 100, 110 and 125%, scrolling where a page does not fit; the Orders board stands on the chart's bottom edge, the key list fits the window, the weapon-state inks reach 4.5:1 contrast and the COURSE box reads the course steered.
- The desk's ACCEPT and CANCEL are worded buttons and a locked campaign step names the win that opens it; the Classic summary wraps; the Reference has a compact layout for short screens, a general block for every platform and words for every weapon's speed, warhead and seeker, and opens on the flagship; the debrief card is sized from the screen; front-end dialogs share one header.
- Leaving or restarting a running engagement from the desk, and deleting a save, ask first, and leaving or restarting autosaves; the editor's NEW asks and is an undo step.

### Speed

- The sensor cycle weighs a sonar or lookout pair only inside some reach, files a linked unit's reports once in the shared plot, finds bearing samples through a per-track index and trims crossed fixes; the profiler shows its set-up and lookout pass.
- Each per-tick unit step runs only for units it applies to. Seeded state dumps of two scenarios are byte-identical before and after.
- The chart's moving marks (threat rings, flashes, the red edge of a hit, the radio fade) are drawn on a layer of their own every frame, and the plot under them only on a simulation tick, a view change or the idle rate; the coastline is stroked on its own layer when the view moves, shifted rather than re-projected on a pan.

### Measured

Before (the code ahead of the overhaul) against after, on one otherwise idle 4-core machine, one process at a time, each timing taken twice (run 1 / run 2). The battles are not the same battles: the overhaul changed what ships and the AI do, so where a difference is the simulation doing different work rather than running faster, it says so. The battle counts come from the state dump of the same seeded run.

Headless, an hour from the start of each scenario (seed 2, both sides on the AI, `--fastforward=3600 --dump`), in simulated seconds per wall second:

| Scenario | Before | After | Note |
|---|---|---|---|
| aegis_bastion | 34.4 / 37.5 | 77.7 / 76.2 | Not like for like: after, the hour holds 5 weapon commits and 5 own rounds against 29 and 37 before (16 rounds still in flight at the end before, none after). Much of the gain is less fighting. |
| pacific_02_taiwan_strait | 17.9 / 18.2 | 31.1 / 30.6 | More fighting after (46 commits against 38, 18 missile-defence launches against 0, 30 hostile rounds against 18), so the gain is real. |
| gulf_01_hormuz | 90.8 / 91.2 | 134.3 / 130.7 | The same 12 commits; after, 26 hostile rounds against 0 and 9 contacts against 0. Real gain. |
| med_01_tartus | 60.7 / 62.0 | 66.1 / 69.6 | More fighting after (36 commits against 31, 34 hostile rounds against 24); small real gain. |
| cold_war_03_carrier | 98.4 / 102.1 | 154.8 / 149.9 | A similar battle (10 commits against 7, 54 defence launches against 48). Real gain. |

The sensor cycle late in the Taiwan Strait (`tools/measure_sensor_cycle.gd --paths=optimized --repeats=3`: seed 42, from 2400 s; the median of three, run 1 / run 2). The saves at 2400 s are different battles: after, the side's reports go into 3 shared track pictures (62 tracks) instead of 68 per-unit pictures (501 tracks), RED has 15 engageable units against 10, and 18 weapons are in flight against 1.

| | Before | After |
|---|---|---|
| sensor cycle mean, ms | 18.70 / 19.36 | 19.59 / 20.72 |
| sensor cycle p95, ms | 25.65 / 27.26 | 45.18 / 47.84 |
| radar / ESM / sonar / tracks / weapons, ms per cycle | 4.10 / 6.05 / 1.69 / 0.92 / 0.20 | 4.60 / 11.53 / 0.63 / 0.12 / 1.36 |
| tick mean, ms | 16.33 / 16.95 | 9.41 / 10.04 |
| stepped, 600 s | 15.3x / 14.7x | 26.6x / 24.9x |
| 60x clock, frame budget on | 14.7x / 14.2x | 17.4x / 16.5x |
| 60x clock, no budget | 14.5x / 13.6x | 18.4x / 17.4x |
| order to next frame, budget on, mean ms | 64 / 67 | 68 / 72 |

The cycle costs about the same per run and its tail is longer, with ESM at twice the cost in a battle with more emitters and rounds in the air; the tick as a whole takes 0.6 of the time, so the battle steps 1.7 times faster. Every repeat ended in the same state, and every clocked run replayed tick by tick to the same state.

With a window (xvfb, software renderer, 1600 x 900, `--fastforward=2400 --run=5 --perf=8`), script time per frame, run 1 / run 2:

| | Taiwan Strait before | after | Hormuz before | after |
|---|---|---|---|---|
| clock during the sample | 60x | dropped to 1x | 60x | dropped to 1x |
| chart, ms | 3.72 / 3.96 | 2.89 / 2.95 | 2.46 / 2.50 | 2.23 / 2.44 |
| data display, ms | 0.80 / 0.86 | 0.75 / 0.79 | 0.53 / 0.54 | 0.85 / 1.00 |
| 3D view, ms | 2.47 / 2.62 | 1.87 / 1.88 | 2.02 / 2.08 | 1.82 / 2.01 |
| simulation, ms | 53.5 / 56.8 | 20.1 / 20.5 | 51.4 / 51.1 | 11.0 / 11.8 |
| draw calls | 434 | 399 | 319 | 332 |

After, a combat event early in the sample (at Hormuz a cruise-missile commit) drops the clock to real time, as the game now does; before, it stayed at 60x. The simulation row therefore compares a mostly-1x clock with a 60x one and says nothing about speed. The chart and 3D view rows are like for like and a little cheaper after.

### Repository

- The test runner discovers `tests/test_*.gd` instead of keeping a list, and resets the static world state between files.
- The data builders run again, and `python3 tools/scenarios/rebuild_all.py --check` proves `data/` is what they write.
- 165 dated milestone notes, screenshots and validation records (49 MB) are deleted from `docs/`; they stay in git history. Unused tools, dead code and the assets of retired weapons are gone, and tests check that every asset, tool and link is reachable.
- The interface suites are kept out of the browser pack.
- The documentation is three files: README.md, CHANGELOG.md and DEVELOPING.md, beside DATA_SOURCES.md and assets/README.md.

## Earlier history

- **M43, commanding a large fleet:** stack pickers for overlapping symbols, roster search, Show on Chart and Locate with back and forward through chart views, clearer fleet and defence boards, kills as held reports, a starting distance for custom fleets, F7 on whatever is displayed, less rendering work per frame and saved views.
- **Command bug fixes, crew radio and sound:** attacks respect confirmed kills and close to usable air-target range; bundled radio performances replace device speech, weapons have their own firing sounds, and the sea and machinery beds duck under crew reports.
- **M42, ships against the light, fire and the baffles:** hull lighting that keeps a ship's shape on its shadowed side, relit fire and smoke, no banding on the sea; hull sonars deaf astern, shown on the chart, and AI captains who clear their baffles.
- **M41, a softer horizon, a dark night and holds that fit:** the sea pales into the sky; lookouts identify at a fraction of their daylight range at night; an inbound anti-radiation missile is named; holding patterns fit the airframe's turn.
- **M40, diesel boats, anti-radiation missiles and a core review:** conventional submarines on a battery with a snorkel and air-independent plants; the AGM-88, Kh-31P and YJ-91; seven defects found reading the simulation core.
- **M39, air combat regressions:** shots at aircraft held to a no-escape range from the reported type's performance; fighters crank instead of turning tail; rounds that miss their aim point search on.
- **M38, sensor coverage and air tasking:** the chart lit where own sensors reach; air combat measured end to end and fixed; one-click CAP, search and strike from a deck's or contact's menu; a live air board.
- **M37, integrated air defence and flight operations:** the force allocates interceptors as one, networked guidance between fitted ships, holds and marshal stacks, deck ready alerts, refused fire orders say why.
- **Command and recognition passes after M36:** revised original models for 22 aircraft and all 14 submarines; Classic at 1x, 2x, 4x and 8x with manual missile defence; a command guide in Northern Passage; movable air stations, CAP over a group, AAW and ASW screens, aircraft speed profiles, submarine check-ins, interface scaling, and the two command practice exercises.
- **M36, missions, saves and an enemy with a plan:** CAP, reconnaissance, ASW and strike missions; standing stations and return to station; exact saves and autosaves; group attacks; enemy mission plans; the Classic preset; operations that vary by seed; a sensor cycle a third of the cost.
- **M35, nine missions, a crew and campaigns:** the mission list cut from 23 through the generators; two campaigns gated on the commander's log; crew voice and an ambient bed; contact source and estimated damage; an Action camera that follows a strike to its impact.
- **M34, the command loop:** the standing attack, right-click defaults with cursor feedback, the authored operations back on the front door, mission effectiveness and the commander's log.
- **M33, command intent:** inspecting a contact keeps the shooters selected; persistent investigate orders; direct finite salvos; chart, time and camera menus; scenario clouds and rain. A combat cleanup added Attack and Defence controls and corrected interceptor guidance.
- **M32, Command Watch:** a calmer relief chart, larger track numbers, a persistent command strip, repeating patrol areas and rebuilt Nansen, Gorshkov and Steregushchiy models.
- **M31, Northern Passage:** an introductory escort mission from the desk, with civilian accountability in the debrief.
- **M30, weapon control and track solutions:** one firing board for mixed weapons with per-system quantities, launcher queues and reservations; last-fix age, uncertainty and seeker baskets on the board and chart; role-coloured weapon ranges.
- **M29, fleet workshop and defensive command:** a seeded fleet builder and a fuller editor; player-ordered countermeasures, evasion and interceptor policies.
- **M28, the live view, deep strike and torpedo defence:** runtime finishes by navy, sky lighting, wakes and bow waves; land-attack strikes; acoustic decoys and anti-torpedo rounds.
- **M27, ship fits and the reach line:** every loadout audited against its class's public fit, seven hulls corrected; each hull's reach on the data display.
- **M26, final QC and optimisation:** every screen reviewed, the frame budget measured with `--perf`, the chart's script cost roughly halved.
- **M25, fleet operations:** expanded operations with staged objectives, reserve aircraft, follow-on raids and finite reloads; area and point-defence budgets.
- **M24, the CDS screen:** the command screen rebuilt as a late-1990s CDS layout: relief chart above, regional map, 3D view and data display below, orders through right-click menus and keys.
- **M23, world theatres and shore batteries:** four chart regions from Natural Earth, a 2027 catalogue for the PLAN, Japan and Iran, coastal batteries and SAM sites ashore, and a 3D world view.
- **M22, command deck redesign and browser release:** the interface rebuilt around the chart, twelve defects fixed, and a browser build on GitHub Pages; CI on every pull request.
- **M21, Cold War 1990:** four alternate-history 1990 operations with their own period catalogue.
- **M20, air operations:** aircraft type selection, explicit landing destinations, recovery and turnaround, and the Carrier Qualification exercise.
- **M19, contact fidelity and stability:** better report fusion and reacquisition, relative-motion plotting, and the contact solution's age and uncertainty.
- **M18, sea floor, water column and damage control:** Natural Earth bathymetry under the chart, layers, shelf losses and convergence zones, and fire and flooding.
- **M17, command deck UX:** the notice, focus, act and acknowledge flow, the Actions palette, Natural Earth coastlines for every chart, and corrected class fits.
- **Between M12 and M17:** recognition art from Blender models, a CIC interface, 83 inspectable 3D models, a real air war with air wings and deck cycles, and charts and fits corrected against public sources.
- **M12, coastlines:** land polygons, terrain masking, grounding and a scenario editor.
- **M11, Aegis Command II:** ballistic missile defence, electronic attack, sea state and damage control.
- **M0 to M10:** the project, the tactical sandbox, radar contacts and tracks, surface combat, missile defence, the enemy AI, the mission framework, submarines and sonar, aviation, ESM, datalinks, EMCON, formations and rules of engagement, and a first presentation pass.
