# M29: Fleet workshop and defensive command

Build the battle you want to command. The game now opens on **My Missions**; **Build a Fleet / Edit Mission** leads into a seeded force builder and the full editor. The 22 predetermined operations have moved to **Optional Templates**. They remain useful starting material and regression fixtures, but no longer occupy the main mission list.

## Responding to an attack

Hook the threatened ship or aircraft, then press **V** to order an evasive maneuver against its nearest detected inbound weapon. Surface ships receive a 60-second emergency course; aircraft receive 25 seconds. Steering and acceleration still take time. The course is screened for coastline and nearby friendly traffic. A route or formation survives the maneuver, and **Resume Plan** ends it early. A fresh navigation order also overrides it.

**D** deploys one radar countermeasure pack. The orders board's **Defence** tab also offers infrared and acoustic packs, run-away steering, and automatic/manual countermeasure control. Each deployment lasts 20 seconds, with 25 seconds between deployments. The display shows remaining stock, the active window and evasion time. One compatible threat receives one attempt against each pulse; clicking repeatedly cannot grant repeated rolls from the same deployment. Radar pulses do not seduce infrared or acoustic seekers, and acoustic pulses do not defeat wake-homing torpedoes. Weapons hold restricts weapons fire while still allowing defensive countermeasure deployment.

Conserve, Balanced and Saturation policies limit concurrent guided defensive commitments to one, two and three respectively. Conserve escalates to two when impact is within 45 seconds. Escorts coordinate against detected threats, prioritizing earlier arrival bands and then higher-value victims. Point-defence and close-in weapons retain their layer allowances. RAM now uses independent passive RF/IR guidance and does not consume a ship illumination channel. JASSM-ER and LRASM have explicit imaging-terminal representations; a generic inertial-terminal label no longer makes a drone or an unspecified missile vulnerable to flares.

These timings, stores, effectiveness values and bounded maneuver benefits are gameplay estimates. The public distinction behind RAM's independent guidance is documented by [Raytheon](https://www.rtx.com/raytheon/what-we-do/sea/ram-missile), checked September 29, 2026. JASSM infrared guidance follows [Lockheed Martin’s product history](https://www.lockheedmartin.com/en-us/news/features/history/jassm.html). LRASM’s electro-optical terminal identification follows its [2012 captive-carriage release](https://news.lockheedmartin.com/2012-07-16-Lockheed-Martin-Successfully-Completes-First-LRASM-Captive-Carriage-Test), represented here in the imaging-IR band. Both were checked September 29, 2026. The model does not claim to reproduce classified seeker logic or platform-specific countermeasure inventories. RF and IR expenditure shares the game's existing generic pack stock.

## Building the mission

1. Open **Fleet Builder**, select 1990 or 2027 and one of four chart regions, then set each side's surface ships, carriers and submarines. A seed makes the mix reproducible. Carrier counts are included in the surface total; the wing size is a finite number of embarked aircraft.
2. Generate the fleets, then edit them on the chart. Search the full platform catalogue or filter by era. Bulk placement creates independently editable hulls. Undo, redo and duplicate support iterative force design.
3. Select a platform to change heading, speed, depth, emissions, arrival time, defensive policy, installed weapon quantities and compatible air-wing composition. Weapon fits are constrained by the actual platform catalogue, magazine limits and VLS cell capacity.
4. Plot patrol legs and add victory tasks. Survive, destroy-force, reach-area, hold-area and aircraft-recovery tasks can be combined with all/any victory mode and a prerequisite on the preceding task. Set a unit's arrival minutes to create a reinforcement wave. Destroy-force tasks wait for the last scheduled hostile wave.
5. **Save and Play** validates the mission and opens its briefing. Import and export use editable JSON. Saving an opened custom mission updates that file; importing or generating the same seed creates a distinct copy rather than replacing another saved mission.

The validator rejects malformed structures, unknown platforms, impossible weapon or deck fits, duplicate callsigns, ships ashore, absent starting player forces, missing homes, late leaders, and objective/formation dependency cycles. It checks waypoints for land endpoints; safe routes around intervening coastlines still depend on the movement model. The 1990 opposing-carrier recipe uses a period Nimitz as an explicitly fictional opposing force because the period catalogue has no Soviet carrier; it never borrows a modern air wing.

The local launcher uses port 8879 consistently, so browser missions survive restarting the preview. Native missions live in Godot's application data directory. Browser missions belong to the browser's storage for that site. Export important missions as JSON before clearing site data or moving between the local preview and the public site.

## Commanding a large force

**J** opens Fleet Operations. Its groups report hull count, the worst station error, defensive ammunition, countermeasure stock and damaged members. Select task groups and issue formation, emission, defensive policy, countermeasure and maneuver orders together. Aircraft aboard ships remain in **Air Operations**, on **F3**.

Save a chart selection with **Ctrl+1 to 9** and recall it with **Alt+1 to 9**. Screen, column, abreast, wedge and dispersed formations assign distinct stations instead of recycling five offsets. Flagships pace their slowest live consorts, including propulsion damage and nested groups. A surviving consort takes over after the leader is lost. Evasion temporarily suspends station keeping and then returns to it.

The chart shows detailed guidance lines for the selected engagement and batches missile trails to reduce visual clutter. The CDS command screen and uncertain contact picture remain the core interface. Group orders use the same command validation as individual orders, and the fleet board exposes only friendly force information.

## Performance boundary

A native stress battle with 64 surface ships, six submarines and embarked air wings loaded 274 actors. At 1600 × 900 during a missile exchange, the measured frame rate rose from 12.4 fps before the new caching to 20.2 fps afterward. AI processing averaged 1.49 ms per rendered frame in the final sample; the earlier detailed profile averaged 18.40 ms. These are local eight-second samples on an Apple M5 Pro, with background validation running, not a browser hardware guarantee. Very large simultaneous salvos still produce noticeable stalls. Pause to issue group orders; this build does not claim 60 fps at that scale.

## Verification

The machine-readable record is [validation-m29.json](validation-m29.json). It records the regression suite, three native interface suites, the actual-scene battle sweep, browser checks and the included package hash. The test library is isolated with `--scenario-storage=res://work/<name>` so validation does not modify a player's missions.

The code and browser package are prepared locally. Publishing this branch and deploying GitHub Pages require the owner's approval.
