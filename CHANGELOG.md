# Changelog

Most recent first. The earlier history is compressed to a line or two per milestone; the full notes and validation records are in git history.

## Overhaul, November 2026

A review of the whole game after M43, fixed area by area and then in rounds of repairs. Each line is one change a player or developer would notice.

### Orders and the clock

- An attack or investigation no longer stops the ship: she fires when in reach without touching her plan, closes briskly, keeps way on and goes back to the interrupted route, speed or station when the task ends. The radio says when a platform resumes its route, and task results stay on the readout after a return to station.
- The standing attack chooses the weapon a captain would: the gun at small craft inside its reach, otherwise the cheapest round meant for the target that reaches with margin.
- A salvo is sized to what the plot's reported class and damage estimate say is left of the contact, allowing for the class's close-in and area defences: a defended corvette still gets a full salvo, a badly hurt one a pair and an undefended boat one round. A group attack's default budget is sized once for the group, never more than a salvo from each ship.
- Right-click investigates any contact of unknown allegiance, and **Identify contact** is offered on all of them, including an unknown of known class.
- A contact's menu has **Designate**: the commander can enter it as hostile, neutral, friendly or unknown, and the call stands until changed.
- With land in the line of fire a ship moves to the nearest point she can reach that clears it, and a standing attack whose line of fire holds a neutral holds fire and keeps the task while the traffic clears, and says so.
- A torpedo attack begun too close first opens beyond the weapon's enable run and a margin, and Weapon Control's range column starts a torpedo at that range.
- A move routed round a coast says so instead of warning of land on the course, a refused move or group order names the platform and gives the reason, and the radio says when chaff, flares or a decoy are fired with no seeker of their kind in reach.
- The Orders board's COURSE box shows the course the hooked ship, or a group's lead, is steering, leaving alone a figure the commander is setting.
- An optional **Classic keys** layout, off by default, turned on from the Gameplay menu and kept in the user settings: P pauses, T steps the time scale, Tab hooks the next platform, B or L sends aircraft home, E arms an engage cursor, Shift+C sets emission control, Shift+1 to 3 set a third, two thirds or all of each platform's top speed, Shift+7 to 9 set height or depth, the number row recalls the groups saved with Ctrl+1 to 9, Space hooks the platform heard last on the radio, and Ctrl+click or Ctrl+right-click zooms the chart in or out on the point. The H board and the Actions shortcuts follow the layout in use.
- The command bar and the data display show the rate the clock is achieving beside the rate asked for when it falls under nine tenths of it (60x > 18x).
- Time compression drops to real time once per engagement. A new electronic-support line not held hostile is called and plotted without dropping it; inbound weapons, hits, radar, sonar and visual contacts and anything hostile still do.
- Once a mission has ended its clock stays stopped after the debrief is put away: Space, the Classic P, the pause action, the watch time button and a closing board no longer start it, and the radio says why.
- Command keys are not taken from a focused text field.

### The chart and the command screen

- The chart, the inbound warnings and the opening hook show the force's picture, whatever is hooked, and the hook stays on a contact as one picture hands it to another.
- The chart opens on the player's ships at command scale unless the scenario sets a focus, **Home** fits the same frame, and the coverage layer starts off.
- A bearing-only contact is drawn as a line from the unit that hears it, with its number at the end.
- A **Filters** submenu shows or hides hostile, allied, neutral and unknown contacts, routes and the range grid.
- A **Chart marks** submenu lays labelled marks, range circles fixed on a chosen point and corridors of a chosen width; they are kept with the saved picture.
- The radio line has a band of its own in a light wash: chart names, captions and track numbers are placed clear of it, and a number that would fall under it stands clear on a leader.
- Patrol, ring, CPA and time-to-go captions are placed with alternatives instead of printed over each other, as are the caption of a boat awaiting check-in and the label of a fixed range circle; contacts on one spot share one label, and an airframe on a mission station leaves the naming to the mission's ring. A caption whose place changes between placements is placed afresh, which ends a crash in the label placer.
- The hooked platform's number stands six pixels clear of its brackets, and chart numbers keep five pixels above and below each other, so two in neighbouring corners no longer stack between both symbols.
- An intercept is drawn as a line from the deck to its contact, as a strike is, with no hold ring to drag; a torpedo's minimum-range ring and legend give the range inside which the shot is refused.
- A right-click on the regional display sends the hooked platforms there, **Shift** adding a leg, and says why when it cannot.
- A right-click in the 3D view opens the hooked platform's menu, hooking an own ship under the cursor first as the chart does; on a contact it opens that contact's attack and investigate menu.
- Shore installations in the 3D view keep their earthworks and hardstand, stand on a graded earth platform at the highest ground under their footprint, and are drawn at the size their models are built to, an air station with a 2,400 m runway.
- Every status board on every tab docks on the foot of the chart at its content's height and fits inside it at 100, 110 and 125 percent interface size, scrolling where a page does not fit, so the plot stays in view while orders are given. The key list wraps to fit the window.
- An **Assessment** board, also offered in the chart menu and Actions, shows the running mission effectiveness, both sides' losses and each task's state.
- The air-defence board names rounds by their short names, shows as many inbound rows as it has room for, counts ballistic-capable rounds beside the SAMs and calls gunfire gunfire.
- Weapon Control, Fleet Operations, Air Operations, the status boards, Actions and the key list share one dialog header with one CLOSE at the right, and Fleet Operations and Weapon Control stand as tall as their rows.
- The weapons posture, mixed states and comms severities on the grey chrome use inks that read at 4.5:1.
- The data display credits a plot to the sensor and evidence that made it, and the readout has its own right-click menu.
- The rounds of a salvo shot down, decoyed or missed at one contact are one radio line, sent once none of that weapon from its shooters is still queued or flying at it. The salvo receipt says what is away and what is on the launcher, and the firing board keeps the running group's budget.
- Gunfire on the force is called once a shoot as UNDER GUNFIRE, without the missile alarm; the command guide then says the ship is under gunfire and how to answer it, and the **X** cue counts the rounds held waiting for clearance.
- A hit on a contact held as neutral or friendly, or an own round hitting an unidentified ship it was not fired at, is an alert naming it.
- A ship of the force on fire or flooding reports her damage-control state and hull every three minutes until the casualty is over. The coast, self-defence emission, torpedo decoy, towed array, dipping sonar and submarine initiative reports of the commander's own ships are on the radio.
- A unit that is deep or off the link reports the contacts on its own picture on the radio, once per contact, and a boat calls her own contacts without waiting for a signal.

### Sensors

- Passive contacts are ranged from the reach they were heard at and from bearing rate across a turn, with an uncertainty to match, and a contact's last range is carried forward on new bearings instead of jumping to a nominal guess.
- A lost bearing range comes back only from a solution that has stood 20 s, a marginal one is closed on at the contact's pace, giving a range up never shrinks the ellipse, and a one-listener range is withheld when the bearings show the contact has turned.
- Within one sensor cycle a bare bearing never displaces a range, a marginal first range waits five seconds before it is taken, and a plot that a range put beyond the end of a bearing line stays there, so crossed intercepts on an aircraft no longer throw the plot a hundred miles out along the line and back.
- A measured plot has its domain on the first look, so weapons can be laid on it at once; a missile-quality plot needs a sound range solution. Aircraft are fixed from intercepts only on lines taken together, and the first radar plot is taken outright.
- Lost contacts age by what they are. A contact found again where it was keeps what was known of it, one found elsewhere gets a new number, and a stale plot that is hit leaves a datum.
- Fixed sites and contacts known to stand ashore get no course or speed and are never dead-reckoned, and an estimated plot closes on a reworked solution no faster than the contact could travel.
- Lookouts recognise along the sight line, class before name. A look reads a contact's colours only close enough to read its name, or from further off once the lookout has held it in sight for 20 s, and broken cloud hides what is above its base from a lookout below. The track file says what evidence would classify a contact.
- A pinging dipping sonar can be heard, sea state and damage affect ping intercepts and sonobuoys, a submerged boat's ESM is deaf, and a contact's radiating state expires.
- A ship with her radar off is warned of inbound missiles by ESM on a searching seeker and by eye at close range.
- An aircraft with a datalink keeps no private picture, and a dipping helicopter localises its own bearing from the dip.
- The Mohajer-6's radar signature is rated by the fourth-root radar law, so a radiating destroyer holds the drone at about 60 nm instead of 16.
- The escorts carry the hull sonars they are built with, every surface ship has her own radiated noise, submarine and towed-array hearing is longer, dipping sets are shorter, and a lookout no longer out-sees a radar against boats.

### Weapons and defence

- Seekers take the designated contact or the unit nearest the aim point, never their own side, and look before they lock; a seeker that opens on the rail is range-gated on its aim point, so a merchant crossing beside the shooter is not taken.
- A shot with a held neutral or ally in the seeker basket is refused. Automatic Weapons Free SAM fire holds for an own aircraft in the basket only when she shares the hostile plot's height band.
- A missile or gun shot at a stale plot is refused with NO CURRENT FIX; torpedoes, anti-radiation rounds and sites ashore may still fire on one.
- A round whose target is gone searches a few seeker radii on, then ends TARGET LOST; a missile at an aircraft coasts through a short break in guidance; an anti-radiation round homing on an emitter that went silent ends when its range is spent.
- Every naval gun from 57 mm to 130 mm can be laid on a ship, a contact ashore or an aircraft. Shells are on the missiles' damage scale by calibre, accuracy depends on range and target speed and falls to a quarter at full reach, and a shell resolves where it passes its target instead of circling it.
- Ballistic missiles dive and can miss. The shared launcher timer is split into salvo spacing and a short cell service, so interceptors are not held behind a queued strike.
- A tube-launched heavyweight is steered down its wire on the firer's held track while the firer is afloat and holds the contact. A torpedo with nothing in its seeker weaves either side of its course, and one that reaches its aim point empty searches a figure of eight about it for 150 s and ends NO ACQUISITION instead of running out its battery.
- A torpedo shot from inside its enable run is refused as TOO CLOSE, and every torpedo's minimum range is beyond its enable run. Decoy resistance is rated by seeker generation, and the Rastrub and Yu-8 fly out as rocket-thrown weapons.
- A torpedo's hit chance falls for the target's speed only when her side has heard it and she is running from it. Decoys break an acoustic torpedo's lock instead of deleting it: it circles where it lost the ship and usually ends DECOYED. Wake-homers ignore decoys.
- A ship's torpedo-defence fit warns of a torpedo inside three miles, sonar or none. On automatic countermeasures she turns away as soon as she holds a torpedo coming at her, and lays acoustic decoys each reload while it is still homing on her.
- Missile defence limits interceptors in the air at a round across the force, not rounds ever fired: leakers are re-engaged, shoot-look-shoot, cheapest layer first, ballistic-capable rounds are kept back, and guns fire every cycle. A detected round with no lock is engaged on detection if its course brings a ship inside its seeker's reach.
- Weapons Hold stops attacks only: a holding ship still fires interceptors, guns and anti-torpedo rounds at weapons threatening the force.
- Manual missile defence leaves the point-defence missiles and guns to the crew, and its summary on the desk, the briefing and Actions says that only the area SAMs wait for the order. **X** with no round named clears the whole raid until the sky is quiet or weapons are put on hold, and goes to the whole force when no missile-defence ship is hooked.
- Weapons Free against aircraft keeps one round in the air at a track across the force, a pair only at a fast closing jet.
- The crew lights a radar the commander put out only against a round coming at that ship, says so, and puts it out again once the threat has passed unless the commander has ordered the radar since; under a silent emissions order she holds fire and says so once a raid.
- A hull with ASW rockets and tubes states one anti-submarine reach on the weapons line.

### Aircraft

- A CAP turns on a hostile coming in on it and commits on a raid closing on it or on what it covers only when it can shoot inside its leash and out of hostile ship missile cover; the same test recalls it, with a break-off. It is sent only 5 nm inside the reach it is kept to, kept on a closing raid until the raid's course opens, never sent on an air position worked up from bearings alone, and a fighter just recalled is not sent out again until it is back on station or two minutes have passed, so it no longer flaps. A fighter busy with one hostile turns to another only for one well nearer, and a CAP's look at an unknown aircraft is sent only on a radar fix.
- A CAP fighter breaks once a missile it can see coming is 40 s from it, a break called on the net as a warning, and takes up its attack again afterwards. A raid that would have its shot away first is waited for over the station instead of flown out to meet.
- A CAP circuit moved out of a ship's missile cover is laid 3 nm wider than it need be and moved again only when it is no longer clear, so a wandering plot no longer flips the airframe on it between on station and transiting.
- A CAP ordered without a pursuit may chase 60 nm past its ring, a revision that names no pursuit keeps the mission's own, and a CAP flies a square inscribed in its ring, a section on offset circuits.
- **Intercept with fighters** keeps the raid: the fighters go for that contact at dash, fire and come home, with no station ring.
- The ready alert scrambles on a raid closing inside 220 nm, with a pursuit that reaches it, even while a CAP is up that is not going for that raid.
- Reconnaissance leaves hostile contacts alone, an unarmed sensor aircraft flies at least 40 nm off any ship not known to be harmless, and a scouting or shadowing aircraft keeps outside the known missile cover of the ships it watches. A quick look at a ship goes to a helicopter or an armed jet.
- Strike aircraft hold off after release and hold where a task ends, turn for home once a fire-and-forget salvo is away, and a fixed-wing aircraft held from firing by a neutral in the line of fire or a busy launcher holds off on its own side instead of flying over the target. Aircraft fly their tasks at no less than cruise speed.
- The deck calls down the waiting aircraft with the least fuel to spare first, and a carrier lands helicopters on a spot of their own close astern, so a recall runs nobody dry. A helicopter queued behind a busy carrier deck waits for the flight deck, not the catapults.
- Fixed-wing aircraft leave the deck with flying speed and a little height on the ship's heading, and a section goes off 15 s apart, so the wingman is a second symbol. Aircraft of a section that finish a task together hold on their own patterns 2 nm apart, along the diagonal as their station circuits are.
- An aircraft keeps her terrain clearance over every raster cell of her next two minutes of track, and altitude orders are held to a per-type minimum above the sea.
- A refused launch names the deck's facility (runways, flight deck, launch spots, catapults), and a mission whose aircraft were all lost ends 'All aircraft lost'.
- The Air Operations dialog stands as tall as what it shows, with the mission plan beside the deck list, both at least six rows deep at 1600 x 900 and at 125 percent, and the order receipt in a fixed footer; on a window too narrow for both the deck goes under the plan.
- In Air Operations a mission the chosen aircraft cannot fly opens on a type on deck that can, an assigned station or target is spent with its mission, options a strike cannot use show clear as well as greyed, the button names the type after an accepted launch, and a new engagement opens on a clean receipt.

### Ships and submarines

- Ships route round the coast by sea. A hull the coast holds stops and reports it, and a line of fire is cleared against the coastline itself.
- A hull coming round with the shore on the short side of her turn comes round the other way, and one held against a coast is not laid back along it, so holding a range off Musandam no longer leaves a destroyer creeping along the beach.
- Station keeping steers for a station led by the guide's velocity, and the guide paces the group a few knots under its slowest consort.
- A screen escort fires on an attack from her station and closes only while the firing point lies within 3 nm of it, and a hull gives up a chase the plot says she cannot win, so an attack never takes her out of the screen for the rest of the mission.
- A helm order to a formation escort interrupts her station instead of ending it, so **S** takes her back and **Rejoin formation** is offered. A speed order to a consort keeping station is refused with a reason, and a consort firing from her station inherits a lost guide's route.
- A course order to a ship lying stopped gets way on, and a last waypoint inside the turning circle is reached by coming round to it, not dropped.
- A unit on a scenario's two-corner patrol line can go back to it after a task and take a new speed on it; only a circuit the commander lays needs three corners.
- A helm or task order keeps a towed array streamed; only evasion or too much speed recovers it, and an unordered recovery is reported.
- Under Classic rules a boat out of touch turns away from a torpedo she hears and snorkels by herself at a critical battery, reporting it at her next check-in. Evade and decoy orders are never queued, and a snorkel order delivered in a check-in window keeps her up to charge.
- A boat on a breakout route gets out of the way of a torpedo running at her, then takes up the route again, and a boat already found may shoot back beyond the transit's torpedo range.
- A boat holding only a bearing works legs either side of it for a solution, and a wire-guided torpedo goes on a rough range well inside its reach.

### The enemy

- An AI ship under fire answers any hostile it holds and can reach, whatever its plan is waiting for, and keeps shooting while it turns away from a round.
- The AI picks shots with the launcher's own test and falls through to the next weapon when one is refused.
- A ship patrolling with her radar off that is hit, or sees a round coming, radiates until the shooting has stopped for a while.
- The enemy fires on a range worked from bearings only while its crew's solution still gives it and once the range has stood a minute, not on one carried on after the solution fell apart.
- The enemy trims its doctrine volley when its own plot says fewer rounds will do, sizing it from the reported class and damage estimate as the player's ships do, so a crippled ship is sent a round or two.

### Missions

- Mission effectiveness grades conduct as well as outcome. A victory won with no order that put the force to work, while an enemy was at sea, earns a quarter of the task; emission, rules-of-engagement and automation settings do not count as command.
- Each hit the force lands on a neutral is a civilian incident and each on its own ships fratricide, 10 apiece whatever the damage; rounds far beyond what their targets were worth cost up to 10; and the share of the mission a formation escort spent more than 1.5 nm off her station costs up to 20.
- The debrief lists every civilian incident by vessel, as the plot knew her when she was hit, with the weapon and the mission minute, beside the neutrals sunk; such a hit is not also counted as a hit scored, and an uncommanded victory is marked "(no orders)" on the effectiveness line.
- A scenario unit can start with weapons held or tight, and an operation's event can set a side's weapons posture, so a battery can be in the battle from the start with weapons tight until an event frees it.
- Every operation opens with its guide on her route (a watch carrier on a 25 nm circuit), the escorts formed on her where the builder placed them and the pickets on their own lines, so **Return to Station** means something from the first second.
- In Hormuz the Qeshm battery comes out of its hide after 10-15 minutes and the ballistic battery after 15-25 minutes, once a drone has reported a tanker (by 40-50 minutes at the latest), so the convoy forms before the first salvo; the UKMTO fire-mission warning follows the ballistic battery.
- The Iceland-Faroe Barrier is laid out at sea scale: the Victor III opens 24 nm up one of three lanes 22 nm apart, beyond either ship's hearing, and breaks out into a broad exit inside a six-hour watch.
- Nicholas in the convoy and Spruance in the carrier watch open radiating, and the North Cape Kilo starts inside the screen, as the briefing says.

### The front end

- One shared question comes before work is thrown away: leaving or restarting a running engagement from the desk, SAVE AND PLAY in the editor, **Ctrl+F10** (one press, as the key list now says), the Actions restart and the debrief's RESTART ask first and autosave the engagement; deleting a saved engagement asks; the editor's NEW asks and is an undo step; a quickload or load autosaves the engagement it replaces.
- A question left on a screen that closes goes with it, keeping the work, and takes no keys while unseen.
- **Esc** or **F1** returns from the pre-mission briefing to the desk; the debrief stays up under **Space** and reopens with **F1**, the chart menu or Actions.
- The desk's ACCEPT and CANCEL are worded buttons, a disabled one is visibly out, a locked campaign step names the win that opens it, and the GAMEPLAY summary wraps. The operation list stands as tall as its rows and hands the spare height to the orders box.
- The Reference runs by nation and kind under headings, with the air stations of no one navy under SHORE AND SHARED after every navy, opens scrolled to the flagship, counts in words, and gives every platform a general block (speed, reach, ceiling or depth, countermeasures) and every weapon its speed, warhead and seeker in words. The 1990 merchantman stands with the other civil shipping under one heading. On a short screen it takes a compact sheet, as the desk and briefing do.
- The debrief card is sized from the screen, its results and the exchange-and-log column read side by side, tile notes wrap, the results take the focus, and a short screen's tighter spacing keeps the results whole.
- The overview map on the desk and the briefing places the own force before the place names, so a name moves a line clear of the ships instead of printing across them.
- The front end's dialogs and the confirmation share the in-mission dialog header, the briefing guide is a tick box beside its words, the editor's mission drop-down is the height of its other controls, and the F3 help line names the Air Operations dialog's real controls.

### Performance

- The sensor cycle weighs a sonar or lookout pair only inside some reach, files a linked unit's reports once in the shared plot, finds bearing samples through a per-track index, trims crossed fixes and lets pairs beyond every horizon go; the profiler shows its set-up and lookout pass.
- The sensor cycle is spread over the four ticks of its second, its observers dealt to the ticks by the reports each filed last time, heaviest first, and merged as one cycle; a cycle with little work runs whole in its first slice, and jammers are looked for only among the units fitted with one.
- A fast contact's bearings are crossed once for all the lines filed at one moment instead of once per listener, and again once half its listeners have filed since the last fix, so a raid heard by a whole force no longer costs the square of its listeners.
- The air defence step works the player's side with the rest of the defence step and the other sides half a second later, and the AI commanders think in two turns half a second apart, so neither step lands whole in one tick of a large battle.
- Each per-tick unit step runs only for the units it applies to. Seeded state dumps of two scenarios were byte-identical before and after that change.
- The chart's moving marks (threat rings, flashes, the red edge of a hit, the radio fade) are drawn on a layer of their own every frame, and the plot under them only on a simulation tick, a view change or the idle rate. The coastline is stroked on its own layer when the view moves, shifted rather than re-projected on a pan, and the own-unit list is built once per chart draw.
- The 3D view builds entries and sight-line tests only for the nearest units within its reach (a 321-unit fleet: 13.8 ms average, 77 ms worst before; 5.8 and 11 ms after), and the readiness bars and recognition card redraw only on a change.
- An autosave captures the engagement in one frame and encodes, compresses and writes it over the next ones, on a worker thread where there are threads and a stage a frame where there are none (Taiwan Strait at 1500 s: longest frame 172 ms before, 136 ms after). A capture reads each script's variable list once and copies a dictionary of plain values whole, so a 48-a-side fleet is captured in about 50 ms instead of 200.
- The `--perf` report says what rate the clock showed beside what was delivered. `--perf-autosave=S` forces an autosave inside the sample, after the harness has taken command, and says why when one is not written; `--perf-hold-rate` keeps the clock at the rate `--run` set through the sample, so an operation whose events drop it to real time can still be measured at speed.

### Measured

Before (the code ahead of the overhaul) against after (the release), on one otherwise idle 4-core machine, one process at a time, each timing taken twice (run 1 / run 2). The battles are not the same battles: the overhaul changed what ships and the AI do, so where a difference is the simulation doing different work rather than running faster, it says so. The battle counts come from the state dump of the same seeded run, and both runs of each tree dumped the same counts.

Headless, an hour from the start of each scenario (seed 2, both sides on the AI, `--fastforward=3600 --dump`), in simulated seconds per wall second:

| Scenario | Before | After | Note |
|---|---|---|---|
| aegis_bastion | 35.9 / 33.5 | 58.3 / 58.4 | Not like for like: after, the hour holds 10 weapon commits, 8 own and 8 hostile rounds against 29, 37 and 16 before (16 rounds still in flight at the end before, 2 after). Much of the gain is less fighting. |
| pacific_02_taiwan_strait | 17.2 / 17.7 | 27.4 / 29.6 | A comparable battle with more defending after (35 commits against 38, 38 own rounds against 44, but 28 hostile rounds against 18 and 28 missile-defence launches against 0), so the gain is real. |
| gulf_01_hormuz | 89.3 / 93.7 | 111.4 / 119.5 | Different work: after, 7 commits against 12, 12 own rounds against 14, 12 hostile rounds and 8 contacts against none, but 18 defence launches against 46, and the two Mohajer drones are still up where before they were shot down. Probably a real gain, not a clean one. |
| med_01_tartus | 56.6 / 63.0 | 53.4 / 59.1 | A similar battle (29 commits against 31, 27 own rounds against 25, 24 hostile each). No gain: after is a few per cent slower in both runs, about the size of the run-to-run spread. |
| cold_war_03_carrier | 86.7 / 101.3 | 141.0 / 140.7 | A similar battle, a little busier after (10 commits against 7, 7 own rounds against 5, 14 hostile against 13, 50 defence launches against 48). Real gain. |

The sensor cycle late in the Taiwan Strait (`tools/measure_sensor_cycle.gd --paths=optimized --repeats=3`: seed 42, from 2400 s; the median of three, run 1 / run 2; the after save rebuilt from the release with `--fresh`). The saves at 2400 s are different battles: after, the side's reports go into 4 shared track pictures (59 tracks) instead of 68 per-unit pictures (501 tracks), RED has 14 engageable units against 10 (8 radiating against 3), and 8 weapons are in flight against 1.

| | Before | After |
|---|---|---|
| sensor cycle mean, ms | 18.89 / 18.51 | 23.22 / 24.65 |
| sensor cycle p95, ms | 26.37 / 24.70 | 35.11 / 37.87 |
| radar / ESM / sonar / tracks / weapons, ms per cycle (run 1) | 4.10 / 6.11 / 1.71 / 0.91 / 0.19 | 4.10 / 13.97 / 0.73 / 0.09 / 0.87 |
| tick mean, ms | 16.62 / 16.18 | 11.01 / 11.68 |
| tick p95, ms | 58.96 / 58.19 | 22.21 / 23.89 |
| stepped, 600 s | 15.0x / 15.5x | 22.7x / 21.4x |
| 60x clock, frame budget on | 14.6x / 15.5x | 19.1x / 18.1x |
| 60x clock, no budget | 14.3x / 15.9x | 19.6x / 18.8x |
| order to next frame, budget on, mean ms | 66 / 64 | 58 / 58 |
| tick carrying an order batch, ms | 3.87 / 4.24 | 12.39 / 12.47 |

The cycle itself costs about a quarter to a third more in this battle and its tail is longer, almost all of it ESM, which costs more than twice as much with more than twice as many RED emitters and eight rounds in the air; radar is unchanged and sonar and the track pictures are cheaper. The tick as a whole takes about 0.7 of the time and its 95th percentile about 0.4, so the battle steps about 1.45 times faster and the 60x clock about 1.2 to 1.4 times faster. The tick that carries an order batch is dearer after (about 12 ms against 4); it is still well inside the frame budget, and the wait from an order to the next frame is shorter. Every repeat ended in the same state, and every clocked run replayed tick by tick to the same state.

The 48-a-side fleet (`tests/test_fix_perf_v.gd`, after only: the code before has no such test), two minutes tick by tick with the AI on both sides: tick mean 19.1 / 19.2 ms, median 17.2 / 17.2, p95 38.8 / 37.9, p99 50.4 / 50.1, worst 84.9 / 70.7; the capture for an autosave at 100 s takes 60.6 / 65.4 ms (against 183.9 / 199.6 ms for the generic walk) and the frame after it 5.1 / 5.7 ms. All nine tests in the file pass in both runs.

With a window (xvfb, software renderer, 1600 x 900, `--run=5 --perf=8`; the Taiwan Strait and Hormuz from 2400 s, Northern Passage from 120 s), script time per frame, run 1 / run 2:

| | Taiwan Strait before | after | Hormuz before | after | Northern Passage before | after |
|---|---|---|---|---|---|---|
| clock during the sample | 60x (10.7 / 8.8 achieved) | 60x, dropped to 1x during the sample (8.6 / 8.6 achieved) | 60x (30.5 / 25.0 achieved) | 1x throughout: dropped before the sample began (1.0 / 1.0) | 60x (52.1 / 51.1 achieved) | 60x (59.2 / 59.0 achieved) |
| chart, ms | 3.30 / 3.51 | 2.09 / 2.30 | 2.43 / 2.69 | 2.64 / 2.43 | 1.96 / 2.00 | 1.56 / 1.75 |
| data display, ms | 0.80 / 0.83 | 0.75 / 0.88 | 0.59 / 0.58 | 1.81 / 1.52 | 0.93 / 0.97 | 0.92 / 1.12 |
| 3D view, ms | 2.12 / 2.26 | 1.27 / 1.40 | 2.04 / 2.36 | 2.10 / 1.92 | 1.47 / 1.53 | 1.44 / 1.55 |
| simulation, ms | 54.98 / 54.41 | 24.64 / 29.22 | 51.00 / 50.96 | 1.58 / 1.33 | 49.45 / 49.31 | 30.86 / 34.77 |
| draw calls | 431 / 434 | 439 / 439 | 319 / 319 | 351 / 351 | 347 / 347 | 349 / 349 |

In the Taiwan Strait and at Hormuz a combat event drops the clock to real time, as the game now does; before, it stayed at 60x. In the Taiwan Strait the drop came part way through the sample; at Hormuz inbound anti-ship missiles were detected in the settling second, so the whole sample ran at 1x. Those simulation figures therefore compare a partly or wholly 1x clock with a 60x one and say nothing about speed, and at Hormuz the after picture holds contacts and rounds the before one never saw, hence its busier data display and extra draw calls. Northern Passage is the like-for-like sample: both clocks stayed at 60x through a quiet opening, the after clock kept up with it, and the simulation cost about 3.8 / 4.0 ms of script per simulated second against 5.8 / 5.8 before. The chart and the 3D view cost about the same or less after in every sample, Hormuz included, where the after chart has more to draw.

### Repository

- The test runner discovers `tests/test_*.gd` instead of keeping a list, and resets the static world state between files.
- The performance tests bound cost by ratios measured in the same run (many listeners against few, the capture against the generic walk, one quarter of the second against another, the 95th percentile tick against the median), so a busy machine cannot fail them.
- The data builders run again, `python3 tools/scenarios/rebuild_all.py --check` proves `data/` is what they write, and CI now runs that check, so a hand edit under `data/` fails the build.
- 165 dated milestone notes, screenshots and validation records (49 MB) are deleted from `docs/`; they stay in git history. Unused tools, dead code and the assets of retired weapons are gone, and tests check that every asset, tool and link is reachable.
- Weapon and sensor definitions that nothing carries are deleted, with their models and renders. An older save that names a retired Sidewinder id still loads.
- The interface suites are kept out of the browser pack, the cold-war and aviation smoke suites among them, loaded by path when their flags ask for them.
- The art loader and its tests name `tools/art` as the pipeline for the revised models, with `tools/blender` kept for the platforms only it builds.
- `tools/web/browser_check.cjs` finds whichever Chromium build is installed under the Playwright directory, and `CHROMIUM` still overrides it; it answers the question the game now asks before deleting a save.
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
