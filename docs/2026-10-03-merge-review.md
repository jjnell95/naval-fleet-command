# Review of the credible-command merge (#36)

The merge is sound as a build: the tree on `main` is byte-identical to the pull request head that CI tested, the full CI sequence passes locally and on GitHub, and the browser release boots and plays without console errors. It shipped five behaviour regressions that the suite did not exercise, two of them serious enough that a player would notice in the first session. This change fixes those five, and lists the rest in rank order.

## How it was checked

- **CI and local runs:** CI on `main` (run 37088457635) was green on all 33 steps. Locally, Godot 4.7.2 ran every CI step, 27 of them, before and after these fixes.
- **Code review:** four independent passes covered sensors and tracking, weapons and air missions, submarine communications and saves, and the interface.
- **Confirmation:** each finding was confirmed by running code, either a probe against the merge and its parent, or the real Main scene under Xvfb.
- **Browser:** the browser build was driven in headless Chromium with SwiftShader WebGL 2, the one check the pull request said it had not done.
- **Browser pack:** `docs/play/index.pck` was rebuilt and compared entry by entry with the shipped pack.
  - A rebuild from the unmodified merge matches it, except for imported model scenes, which vary by a few bytes on every import.
  - The rebuilt pack differs from `main` only in the six game files changed here.

## Fixed in this change

| Defect | Cause | Fix | Evidence |
|---|---|---|---|
| **VL-ASROC and Type 07 never acquire a submarine on their datum** | The waterborne payload swims along the rocket's line before its seeker opens. The new forward cone then cannot see a boat it has passed. | A rocket-delivered payload searches around its entry point. Every other weapon keeps the forward cone. | A boat at the aim point, or 0.3 to 0.4 nm from it: 0 of 4 acquisitions after the merge, 4 of 4 before, 5 of 5 now. |
| **A short missile shot locks the shooter's wingman** | Friendly units became lockable. A CAP pair flies co-located, and a seeker that opens at launch takes the nearest return, which is the wingman at 0.0 nm. Own units are never tracks, so the traffic advisory cannot warn about them. | A round still inside its own minimum range of the launcher, capped at 0.5 nm, ignores returns that close to the launcher. | An AIM-9M with a wingman at 0.0 or 0.3 nm: locked and hit the wingman, now locks the bandit. An AIM-9X fired at 0.4 nm still finds its bandit. A merchant in the line of fire is still at risk. |
| **Missile Defence training cannot be completed under Classic** | Classic gives the destroyer manual defence as it spawns, before the lesson's objectives exist. The guide's instruction to "enable" manual defence then turns it off. | Objectives are configured before forces populate, as a restore already does. The guide and brief now say Classic starts in manual. | In the merged browser build the lesson stalled at 0/3 with no raid. In the rebuilt build it reaches VICTORY with all three tasks done. The native playtest gained two Classic checks, which fail on the merge. |
| **Deep player submarines queue a manual-defence order nobody gave** | The same spawn handler enabled communication windows before issuing doctrine. | Doctrine is set first. | In Aegis Bastion under Classic, USS North Dakota showed one pending order and now shows none. |
| **Chart station edits latch or steal clicks** | A drag interrupted by Alt-Tab stayed active, and the next ordinary click applied it. A quickload or new scenario carried it over. Station handles also swallowed left-clicks on contacts sitting on a CAP centre or ring. | The chart cancels a drag on focus loss and on screen reset. Handles yield to contacts as they already yielded to own units. | A new test fails on the merge and passes now. |

Six regression tests and two native playtest checks were added; the suite is now 983 tests.

- Four of the new tests, and both playtest checks, fail on the merged code.
- The other two are guards and pass on both. One protects the designed line-of-fire hazard. The other protects a short shot the weapon's own minimum range allows.

## Design question, not changed

In Northern Passage, the save-continuation test's group attack sends most of its rounds into **neutral merchants**, mostly MV Coastal Star, rather than the hostile warship:

- all 12 Tomahawk Block V locks;
- 14 of 26 NSM locks;
- overall, only 12 of 38 locks are on the warship.

- **Why it happens:**
  - The Tomahawk's 12 nm seeker basket opens about a mile after launch.
  - Terminal search takes the first return it meets in the basket.
  - So traffic near the shooter reliably beats the target at the far edge.
- **Is it intended?** Yes. The merge says seekers cannot read identities, and the firing board's traffic advisory flags anything along that final leg.
- **Why it still matters:** in an operation whose objective is to keep neutral traffic alive, a long-seeker weapon fired across traffic will hit the traffic almost every time, not occasionally.
- **To decide:** whether that is the game you want, and whether group attacks show the advisory before they fire. That second point was not verified here.

## Not fixed, in rank order

Line numbers refer to `1645728`.

| # | Finding | Where | Confirmed by |
|---|---|---|---|
| 1 | Ranging by manoeuvring the observer almost never produces a fix at shipped sonar accuracy (0.8 to 2.2°). When it does, the ellipse is too small: 6% coverage at 0.6° and 4 nm. The unweighted fit is pulled toward the observer's own track. | `scripts/systems/bearing_solution.gd:93-150` | 30-seed sweeps |
| 2 | Air missions overwrite an explicit commander speed order within a second, so Dash does nothing for mission aircraft. The crew speed order on each transit/station flip also cancels evasion and raises a dipping sonar the commander lowered. | `scripts/simulation/air_mission_manager.gd:815-818`, `scripts/entities/unit.gd:470`, `scripts/systems/dipping_sonar.gd:60` | probe |
| 3 | A close crossed fix (mean range about 1 nm or less) flaps to BEARING ONLY about 90% of the time, resetting course and speed on each flip. Quality caps at exactly the 0.6 threshold. | `scripts/systems/bearing_solution.gd:147-150`, `scripts/simulation/track_manager.gd:196` | probe |
| 4 | Dragging an under-strength mission's station is refused ("Only 1 aircraft available"), or launches an unrequested replacement when spares are aboard. The Air Operations editor instead silently lowers the requested strength. | `scripts/core/main.gd:1141`, `scripts/simulation/air_mission_manager.gd:381-383, 416`, `scripts/ui/air_operations.gd:692-695` | probe |
| 5 | A disconnected submarine's live position, course, speed and magazines feed range/bearing readouts, group rows, weapon rings and intercept times. An unwitnessed submarine loss is plotted at its true position. | `scripts/ui/data_display.gd:314, 456-460`, `scripts/ui/tactical_map.gd:503, 2075-2133` | probe |
| 6 | Evasion with the towed array out stays capped at 8 kn while the array recovers, losing about 70% of the evasion benefit. Any speed order, even a slower one, recovers the array. | `scripts/systems/towed_array.gd:63, 68`, `scripts/systems/movement.gd:57` | probe |
| 7 | An escort's formation-station handle cannot be grabbed while the escort is on station, because the escort's own symbol covers it. Fixing this means revisiting the rule that handles yield to own units. | `scripts/ui/tactical_map.gd:1114` | probe |
| 8 | A Type 26, which has an array but no anti-submarine weapon, withdraws from a HOSTILE submarine instead of tracking it. No shipped operation fields one. | `scripts/systems/ai_controller.gd:209, 372-377` | probe |
| 9 | AI ships slow and stream their arrays on a running torpedo's position. | `scripts/systems/ai_controller.gd:335, 777` | reading |
| 10 | Group attacks refuse a masked mount rather than turning the ship, so a Perry's Mk 13 never fires aft in a coordinated attack. | `scripts/simulation/group_attack_manager.gd:600` | reading |
| 11 | A direct torpedo shot between minimum range and seeker enable (about 0.4 nm for the Mk 54) cannot acquire. | forward cone with `run_to_enable_nm` | probe |
| 12 | Minor items. | see below | reading |

The minor items in row 12:

- The dash fuel penalty is unbounded (about 11.7× at an Su-35's maximum), and the landing reserve assumes transit burn.
- The Actions palette omits the new submarine-communications option (`main.gd:1314`).
- Custom scenarios with a non-dictionary `recognition_affiliations` raise typed-dictionary errors partway through loading.
- `BUILD_MILESTONE` still reads "M33 / Command Intent" and is written into save headers. This predates the merge.

The weapon-fidelity note already declares wire-guided torpedo updates out of scope. Heavyweight torpedoes therefore keep their launch solution against a manoeuvring boat. That is a declared limitation, not a defect, but it does change submarine attack outcomes.

## What was not verified

- **Browser performance:** browser runs used software WebGL at 2 to 3 frames a second, so they say nothing about frame rate on real hardware.
- **Other platforms:** macOS and Windows builds were not run.
- **Unchecked findings:** the findings marked "reading" were not reproduced.
