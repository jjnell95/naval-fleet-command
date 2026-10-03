# Credible command: stations, evidence and crew handling

This update implements the eight priorities from the Fleet Command follow-up review. Existing tasks can be edited in place, the contact picture depends on evidence, and crews make equipment handling visible. Original art and code remain independent of Jane’s; this is an interpretation of command decisions, not a reproduction of its assets or a claim to simulate classified performance.

## What changed

| Area | Result and controls |
|---|---|
| **1. Edit standing missions** | Drag a CAP, reconnaissance or ASW station’s centre/title to move it, or its east-edge ring handle to resize it. Drag a formation station’s square to change that escort’s relative position. Release applies; Escape, right-click or releasing outside the chart cancels. Air Operations → **MISSIONS → EDIT MISSION** changes radius, strength, relief and return behavior without replacing the mission or its assigned airframes. **UPDATE** submits; **DISCARD EDIT** leaves the task unchanged. |
| **2. Readable command information** | The compact data pane wraps or deliberately shortens long fields and preserves ammunition readiness. **DETAILS** opens the complete live readout; **+N MORE** opens every weapon system. Expanded information retains warnings and shows whether the clock is running. Air Operations omits irrelevant recovery controls and duplicate ready-airframe listings. Mission receipts carry timestamps, distinguishing earlier launch reports from current station status. |
| **3. Credible missile acquisition** | Initial acquisition and reacquisition share a forward seeker cone. Segment sweeping prevents fast missiles skipping a target between ticks. Update-capable weapons use a fresh held track while their shooter remains available; launch-and-leave weapons keep their original solution. Authored surface mount sectors can delay a standing attack while the crew reports **Turning to engage**. The firing board and chart warn about held civilian traffic and uncertainty in the terminal search area. |
| **4. Evidence-based contacts** | Passive reports preserve observer positions, bearings and times. Useful maneuver geometry or separated, crossing reports can support a range estimate; a stationary observer or co-located/parallel buoys cannot gain range simply by waiting. Radar can establish domain; an acoustic/ESM library match suggests **PROBABLE CLASS**. Visual recognition and an operation’s explicit recognition brief provide separate identity evidence. A probable class alone is not a universal declaration of hostility. |
| **5. Submarine communications** | Classic enables communication-depth restrictions, queued player orders and last-report presentation. Boats continue their existing tasks while deep. **Orders → Navigation → Communications** requests a check-in or selects on-demand, hourly, two-hourly or four-hourly windows. Delivery rechecks whether each queued order is still possible. |
| **6. Purposeful defence** | CAP can **Hold area** or **Protect group**, with a friendly anchor and **PURSUIT BEYOND AREA** distance. Protecting CAP follows its moving anchor and prioritizes closing threats using held course/speed. Crew intercepts stop pursuing beyond their assigned boundary; an explicit player task remains the commander’s decision. AAW/ASW screens rank escorts by fitted capability and face a relevant held threat; Transit forms a column. The selected first unit remains the guide. |
| **7. Deliberate ship sonar** | **Orders → Sensors → ASW search** preserves the route, slows a fitted surface ship and streams its array before it can hear. **Recover towed array** and new navigation recover the cable before acceleration. Shallow water, damage and evasion interrupt operation. Hull sonar remains independent. Submarine integrated arrays retain their existing hull-relative model. Enemy ship crews stream only when working a nearby held submarine datum, retaining transit and defensive priorities. Sonobuoy range solutions now depend on geometry. |
| **8. Aircraft performance profiles** | **Patrol**, **Transit** and **Dash** separate economical station speed, normal travel and short high-speed legs. Mission stations use patrol; outbound and return legs use transit. Fuel burn rises disproportionately during a dash, while helicopter hover costs more than economical forward flight. Corrected excessive cruise settings include the Tomcat, Su-35, MiG-31 and Growler. Explicit commander speed orders remain meaningful. |

Active strike targets cannot be edited through the station editor: cancel and create a replacement strike. Reducing a mission’s strength cancels queued launches before recalling excess aircraft. Existing stations remain editable when deck damage prevents fresh launches.

## Operating-state graphics and practice

The world view now shows a dipping cable following deployment progress and an observation mast rising from the submarine’s sail crown. Supported external fits use the existing weapon models: four belly Phoenix and two glove Sidewinders on the F-14A+, two Mk 54 torpedoes on the MH-60R, and two Mk 46s on the SH-60B. Remaining magazine counts determine visible stores. Unsupported carriage, stealth internal bays and bomber bays receive no guessed external weapons.

These details appear only on owned or directly sighted platforms. Sensor estimates and disconnected submarine last reports reveal no current equipment state. Pooled model instances preserve their original mesh lists, bounds and materials; fittings do not alter subsequent recognition or camera framing.

Two **Training** exercises assess actual actions and their results:

- **Command Practice / Missile Defence:** select manual defence, authorize an interception against a detected inbound, and survive its resolution.
- **Command Practice / Deliberate Sonar:** deploy and listen, inspect a passive bearing, obtain active range, explicitly authorize a torpedo, and recover the array.

Elapsed time alone earns no command-task credit. Their opponents, recognition briefs and starting conditions are fictional controlled exercises.

## Presets, saves and estimates

**Classic** uses actual time rates **1×, 2×, 4× and 8×**, manual missile defence, attacks on orders, submarine communication windows, crew voice and ambient sound. Auto-attack after investigation remains an optional Custom rule. **Normal** keeps its 60× ceiling, automatic missile defence and immediate submarine orders. Older settings and saves default the new communication restriction off; their existing explicit rules are preserved and may therefore display as Custom rather than the new Classic preset.

The communication threshold is **150 ft / 45.72 m**, with a **60-second** window and a default **two-hour** interval. These are command-game abstractions, not universal real antenna behavior. Surface-array handling uses an **8-knot** quiet cap, **120-second** streaming time, **90-second** recovery and a **25-metre** minimum water depth. Representative Tomcat speeds are **390/480/700 knots** for patrol/transit/dash. These figures, weapon cone angles, mount sectors, fuel coefficients, recognition thresholds and hardpoint layouts are conservative gameplay estimates.

Bearing solutions use a bounded constant-velocity fit with uncertainty; they are not operational-grade target-motion analysis. Acoustic/ESM signature matching remains abstract. Recognition briefs declare opposing military families for the particular fictional conflict, contain no hidden locations or exact callsigns, and do not guarantee a listed platform is present. Civilian traffic advisories use held reports and are not a guarantee of safe target selection. Datalink topology, detailed illumination beams, per-mount damage, replenishment and mine warfare remain outside this update.

New mission, bearing-history, communication and array state is saved. Legacy units without array fields start stowed; legacy settings retain immediate submarine control. Save format 3 also supplies the authored recognition brief when loading an older built-in operation that lacked it; explicit empty briefs and custom scenarios remain unchanged. The Cold War generator carries the corrected Tomcat profiles, so regeneration preserves them. Runtime defaults supply the remaining profile behavior; graphics fittings live in code and do not modify generated base models.

## Verification

The integrated run passed **977 regression tests**. Native checks passed at 720p and 1080p, including 125% interface scaling: 78 mission-editing and submarine checks, 34 readout and lifecycle checks, 17 training checks, and 270 existing command, launch and recovery checks. Six operating-state model captures were inspected without engine errors. Carrier Watch and Northern Passage continued byte-for-byte identically after saves were loaded in separate processes.

Coverage includes station edits and CAP boundaries, classification and bearing geometry, seeker acquisition and firing arcs, submarine command queues, sonar cycles and save compatibility, aircraft fuel profiles, readout reflow, training objectives and pooled graphics. Northern Passage's opposing ships now approach for actual convoy identification before committing a coordinated attack; escorting and abandonment retain distinct outcomes without assigning hostile identity to every merchant.

The browser data pack was rebuilt with Godot 4.7.2 and its loader size verified. Runtime interaction was tested in native Godot under a virtual display; browser runtime interaction was not tested in this environment.

Useful reproducible entry points:

```sh
godot --headless --path . --script tests/run_tests.gd
godot --path . --script tools/fidelity_playtest.gd
godot --path . --script tools/readout_playtest.gd
godot --path . --script tools/command_training_playtest.gd
godot --path . --script tools/operational_fittings_playtest.gd
```

See also [weapon behavior and limitations](2026-10-02-weapon-fidelity.md) and [the previous launch, scaling and dipping-sonar update](2026-10-02-command-priorities.md).
