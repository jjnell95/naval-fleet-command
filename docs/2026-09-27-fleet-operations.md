# Fleet operations and combat constraints

Built on `495ac7d`, the September 27 command-screen release. The Jane's-style CDS layout, chart, 3D window, right-click orders and existing key bindings are preserved. Original code and art remain independent of Jane's Fleet Command.

## What changes in play

The operation desk now separates **14 expanded operations** from **eight exercises and short engagements**. Every existing mission remains available under All Missions. The operation sequence appears both on the desk and in the in-game F1 briefing. The Cold War shelf contains five operations, Atlantic three, Pacific four, and Gulf/Mediterranean two.

Expanded operations begin with five continuous minutes on a named opening station. The station is marked on the chart; leaving it resets the clock. This enables the main task without itself winning the scenario. Convoy, resupply and amphibious missions require a five-minute hold in their destination box after arrival. Carrier Watch, Taiwan Strait, North Cape, Arctic Shield and Northern Vigil also require an aircraft recovery. Loss conditions retain priority over victory.

The Cold War carrier raid and Taiwan bomber raid arrive in separate elements. Other opposing shore-based attack wings prepare follow-on sections after 40 simulated minutes. Those aircraft already exist aboard their bases and share their fate. Reinforcements receive no free tracks, and the player receives no automatic report of their hidden location. The original charts, sides, terrain and period boundaries remain in use.

## Missile defence

The former fleet-wide lifetime allowance of two guided interceptors could leave an entire inner SAM layer unused. Area and point defence now retain separate two-shot budgets per inbound threat. At most two SAMs may be committed simultaneously against one threat. These are bounded game doctrine choices, not actual naval firing doctrine. Each defending ship retains its own two close-in bursts; CIWS does not consume missile guidance channels or the SAM shot allowance.

Defensive SAMs leave one at a time at the weapon's authored launch interval. Changing targets cannot bypass the same launcher's interval. CIWS ammunition remains represented as short bursts. This cadence is per weapon family aboard a ship, not a complete simulation of shared physical launchers.

Command/semi-active SAMs require an emitting, functioning parent radar. Losing that support causes the in-flight round to fail. Against incoming weapons, local radar horizon and terrain masking also apply: another ship's detection cannot illuminate through the earth or an island. Autonomous seekers and self-contained CIWS retain their existing independence. Continuous support throughout flight is a conservative abstraction; detailed terminal illumination scheduling and radar beam allocation are still outside the model.

## Aviation

Modern U.S. carriers in the expanded operations carry a **fictional 59-aircraft wing**: 36 fighters, five electronic-attack aircraft, four airborne-warning aircraft, eight ASW helicopters and six utility helicopters. This is a representative game force, not an assertion about any named carrier's actual deployment. Only a limited section of each type is ready initially. Reserve preparation takes 20 or 30 simulated minutes; prepared aircraft still require normal launch slots.

Super Hornet CAP sections carry air-to-air weapons. Maritime-strike sections carry a lighter air-to-air fit and the catalogue's anti-ship weapon. Turnaround preserves the authored fit rather than silently reverting to a universal loadout. The 1990 carriers instead field 24 aircraft in a fleet-defence detachment: Tomcats, Hawkeyes, Vikings and Sea Kings. Intruder, Hornet and Prowler strike squadrons are still omitted, so these are explicitly not complete historical carrier air wings.

Bases have finite weapon reloads and sonobuoy stocks, separate from their own shipboard launchers. The default budget supplies two further loads for the embarked wing, in addition to what aircraft initially carry. Scenario authors can override the budget or provide exact weapon stocks. Sections share each weapon's stock. A diversion base can refuel an aircraft but cannot invent weapons it does not have. Aircraft can launch with a partial or empty weapon load; the roster exposes their actual ordnance, and the launch panel displays base reload stocks.

Significant fire or severe weapons-system damage suspends launching. Recovery continues to use compatibility, deck occupancy, capacity, fuel and the moving approach. No new claim is made about realistic flight-deck casualty modelling.

## Sources and fidelity boundary

Checked September 27, 2026. Public roles are grounded in the Navy's [ESSM Block 1 fact file](https://www.navy.mil/Resources/Fact-Files/Display-FactFiles/Article/2168978/evolved-seasparrow-missile-block-1-essm-rim-162d/lang/evolved-seasparrow-missile-block-1-essm-rim-162d/), [Phalanx fact file](https://www.navy.mil/resources/fact-files/display-factfiles/article/2167831/mk-15-phalanx-close-in-weapon-system-ciws/), [E-2 Hawkeye fact file](https://www.navy.mil/Resources/Fact-Files/Display-FactFiles/Article/2382134/e-2-hawkeye-airborne-command-and-control-aircraft/), and [Carrier Air Wing 2's aircraft roster](https://www.airpac.navy.mil/Organization/Carrier-Air-Wing-CVW-2/About-Us/). Existing period sources remain in [Cold War 1990](COLD_WAR_1990.md).

Ranges, probabilities, reserve delays, magazine budgets, the 59-aircraft composition and scenario scheduling are game estimates. They are not calibrated operational performance. Aircraft fuel still uses endurance units rather than a mass/drag model, reload fuel is not finite, the 1990 strike wing is incomplete, and ballistic trajectories remain abstract. The intended result is more credible command decisions while retaining accessible Fleet Command pacing.

## Authoring and verification

`tools/scenarios/operation_design.py` is the shared, idempotent operation pass, invoked by the modern and Cold War scenario builders. It can also reapply the pass to the shipped JSON. `operation_plan` supplies briefing stages; `events` schedules reinforcements and authored messages; objective `after` links dependencies; `phase_only` prevents enabling tasks from independently ending an any-mode mission; `hold_area` records continuous presence. Aircraft wing entries accept `loadout` and `ready_after_s`. Bases accept `aviation_reload_cycles`, `aviation_stores` and `aviation_buoys`.

Validation results and limits are recorded in [validation-m25.json](validation-m25.json). The source and browser package are prepared locally. Publication requires a separate approval.
