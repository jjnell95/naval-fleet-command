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

### Weapons and seekers

- Seekers take the designated contact or the unit nearest the aim point, never their own side, and look before they lock. A shot with a held neutral or ally in the seeker basket is refused, and automatic anti-air fire holds with an own aircraft in the basket.
- A round whose target is gone searches a few seeker radii on, then ends TARGET LOST. A missile at an aircraft coasts through a short break in guidance.
- Heavyweight torpedoes from tubes are wire-guided and follow the plot their boat keeps working. Every torpedo's minimum range is beyond its enable run. Torpedo decoy resistance is rated by seeker generation, and the Rastrub and Yu-8 fly out as rocket-thrown weapons.
- Gun shells are on the missiles' damage scale by calibre, gun accuracy depends on range and target speed, and guns that bombard can be laid on a contact ashore.
- Ballistic missiles dive and can miss. The shared launcher timer is split into salvo spacing and a short cell service, so interceptors are not held behind a queued strike.

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

### Submarines

- Under Classic rules a boat out of touch turns away from a torpedo she hears and snorkels by herself at a critical battery, reporting it at her next check-in. Evade and decoy orders are never queued. A snorkel order delivered in a check-in window keeps her up to charge.
- A boat on a breakout route gets out of the way of a torpedo running at her, then takes up the route again; a boat already found may shoot back beyond the transit's torpedo range.
- A boat holding only a bearing works legs either side of it for a solution, and a wire-guided torpedo goes on a rough range well inside its reach.

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

### Speed

- The sensor cycle weighs a sonar or lookout pair only inside some reach, files a linked unit's reports once in the shared plot, finds bearing samples through a per-track index and trims crossed fixes; the profiler shows its set-up and lookout pass.
- Each per-tick unit step runs only for units it applies to. Seeded state dumps of two scenarios are byte-identical before and after.

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
