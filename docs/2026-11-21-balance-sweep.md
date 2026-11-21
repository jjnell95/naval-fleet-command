# Balance sweep after M43

21 November 2026 · Godot 4.7.2 · `main` at `feaa09a`

The sweep [M43](2026-11-17-commanding-a-large-fleet.md) skipped, and the first full one since [M36](2026-10-02-m36-missions-saves-and-an-enemy-with-a-plan.md). `tools/opening_plans.py` flew all seven operations, two opening plans each, on seeds 2 and 13: 28 trials, about 20 minutes with `--jobs=4` on four cores. The same 28 were then flown at the M42 commit as a baseline. The simulation is deterministic by seed, so any difference between the two columns comes from the work merged between them: the 14 November command bug review and audio, and M43.

## Result

| Operation | Plan | Seed | M42 (`58439ee`) | main (`feaa09a`) |
|---|---|---|---|---|
| Northern Convoy | close_escort | 2 | DEFEAT, 23% | DEFEAT, 23% |
| Northern Convoy | close_escort | 13 | VICTORY, 100% | VICTORY, 100% |
| Northern Convoy | scout_ahead | 2 | VICTORY, 100% | VICTORY, 100% |
| Northern Convoy | scout_ahead | 13 | VICTORY, 100% | VICTORY, 100% |
| Iceland–Faroe Barrier | forward_barrier | 2 | VICTORY, 100% | VICTORY, 100% |
| Iceland–Faroe Barrier | forward_barrier | 13 | VICTORY, 100% | VICTORY, 100% |
| Iceland–Faroe Barrier | gate_defence | 2 | VICTORY, 100% | VICTORY, 100% |
| Iceland–Faroe Barrier | gate_defence | 13 | DEFEAT, 33% | VICTORY, 94% |
| Carrier Watch | all_cap | 2 | RUNNING, 49% | RUNNING, 49% |
| Carrier Watch | all_cap | 13 | RUNNING, 47% | RUNNING, 47% |
| Carrier Watch | strike_slava | 2 | RUNNING, 49% | RUNNING, 49% |
| Carrier Watch | strike_slava | 13 | RUNNING, 47% | RUNNING, 47% |
| North Cape | forward_picket | 2 | VICTORY, 85% | VICTORY, 85% |
| North Cape | forward_picket | 13 | VICTORY, 85% | VICTORY, 85% |
| North Cape | close_screen | 2 | VICTORY, 85% | VICTORY, 85% |
| North Cape | close_screen | 13 | VICTORY, 85% | VICTORY, 85% |
| Taiwan Strait | forward_cap | 2 | VICTORY, 80% | VICTORY, 82% |
| Taiwan Strait | forward_cap | 13 | VICTORY, 80% | VICTORY, 81% |
| Taiwan Strait | strike_group | 2 | VICTORY, 81% | VICTORY, 81% |
| Taiwan Strait | strike_group | 13 | VICTORY, 81% | VICTORY, 82% |
| Strait of Hormuz | close_convoy | 2 | VICTORY, 94% | VICTORY, 93% |
| Strait of Hormuz | close_convoy | 13 | VICTORY, 86% | VICTORY, 85% |
| Strait of Hormuz | sweep_ahead | 2 | VICTORY, 95% | VICTORY, 96% |
| Strait of Hormuz | sweep_ahead | 13 | VICTORY, 87% | VICTORY, 87% |
| Tartus | direct_transit | 2 | VICTORY, 82% | VICTORY, 83% |
| Tartus | direct_transit | 13 | VICTORY, 83% | VICTORY, 83% |
| Tartus | screen_first | 2 | VICTORY, 81% | VICTORY, 83% |
| Tartus | screen_first | 13 | VICTORY, 81% | VICTORY, 82% |

**The 14 to 17 November work did not unbalance anything.** No trial moved by more than two points of effectiveness, with one exception that improved: Iceland–Faroe Barrier, gate defence, seed 13. At M42 USS Dallas was lost and the trial was a defeat at 33%; now the Victor III is sunk and Dallas survives. Hormuz is within a point of the M42 note's figures on all four trials.

Six operations have two openings that win on both seeds, once Carrier Watch is read correctly (below). Northern Convoy does not.

## Two findings that predate M43

Both were invisible because M37 to M42 re-flew only Hormuz.

**Northern Convoy, close escort, seed 2 is a defeat at 23%.** MV North Star is sunk. Flying the same trial at each merge from M36 on places the change in #42 (M40 to M42: diesel batteries, anti-radiation missiles, baffles and the seven core fixes):

| Commit | Result |
|---|---|
| `1645728` (#36) | VICTORY, 97% |
| `59b96c7` (#37) to `ce5333b` (#41) | VICTORY, 93% |
| `58439ee` (#42) and `main` | DEFEAT, 23% |

From #37 to #41 the escorts sink both corvettes. From #42 the order log shows a single attack on the first, one corvette sunk, and the merchant lost at 6,402 s. Which of the M40 to M42 changes is responsible was not determined. One seed of one plan is thin evidence of a balance problem, but it is a 70-point swing on a scripted opening and the other three Northern Convoy trials did not move.

**Carrier Watch reads RUNNING in the sweep, and that is the harness.** #36 added a second victory condition, recovering at least one aircraft after a sortie, and `opening_plans_run.gd` still stops the trial at 7,260 s. The plan keeps its CAP up with reliefs and nothing lands in time. With `--cap=12000` the same trial (strike Slava, seed 2) is a VICTORY at 79%, ending at 7,866 s when the first aircraft recovers. All four trials have read RUNNING at 47% to 49% since #36.

The trace of that trial shows two more things about the harness plan, neither settled here:

- **The strike never flies.** "Strike Slava" issues exactly the orders "all CAP" does. The Norwegian report arrives at 647 s, but the plan's Viking is never sent and no Intruder launches, so the two plans are one plan.
- **BLUE fires nothing offensive.** Slava fires all sixteen Bazalts; fifteen are intercepted and one hits Eisenhower. Each Backfire gets its Kh-22 away. No Backfire is engaged by the Tomcats and none is lost.

Whether those are the harness falling behind the reworked scenario or the game refusing orders a player could give was not determined.

## Carrier Watch, repaired the same day

The cause was in the harness, not the game. Two changes to `tools/opening_plans_run.gd`, no change to the simulation or the scenario:

- **The strike.** The plan sent its Viking only to a contact report, and struck only a surface contact already called hostile. But `TrackManager.report_intel` leaves alone a contact the plot already holds, and the Hawkeye has Slava on radar as an unidentified surface contact by 300 s, before the Norwegian report at 647 s. So no report datum ever appeared, nothing identified the cruiser, and she stayed UNKNOWN for the whole watch while firing sixteen Bazalts. The plan now does what the tasking update tells a commander to do: once the report has been read out, the Viking goes to the nearest unidentified surface contact. She is identified, and four Intruders launch.
- **The cap.** Carrier Watch stops at 9,000 s, not 7,260 s, so an all-CAP watch has time to land its first section and meet the recovery objective.

| Plan | Seed | Before | After |
|---|---|---|---|
| all_cap | 2 | RUNNING, 49% | VICTORY, 79%, at 7,866 s |
| all_cap | 13 | RUNNING, 47% | VICTORY, 77%, at 7,866 s |
| strike_slava | 2 | RUNNING, 49% | VICTORY, 100%, Slava sunk |
| strike_slava | 13 | RUNNING, 47% | VICTORY, 98%, Slava sunk, one aircraft lost |

These are close to M36's figures for the operation (77% and 78%; 92% and 100%). In the seed 2 strike, eight Harpoons were fired and four hit.

Two things a player would meet that the harness had hidden, left as they are:

- When the cruiser is already on the plot, the tasking update names her and gives a position, but nothing on the chart ties that message to the unidentified track beside it. That is `report_intel` working as written. Whether the held track should be marked as the subject of the report is a design question.
- The Tomcats never engage a Backfire. Each bomber releases its Kh-22 from outside the CAP stations the plan chose and turns away. Not investigated.

## Not done

- Finding the M40 to M42 change behind the Northern Convoy defeat.
- Re-flying the other six operations after the harness change. It touches only the Carrier Watch plan and cap, so their results stand.
- More than two seeds. Every claim here rests on seeds 2 and 13.

## Evidence

- `python3 tools/opening_plans.py GODOT --seeds=2,13 --jobs=4` at `feaa09a` and at `58439ee`, each from a fresh import.
- Northern Convoy and Carrier Watch re-flown at `1645728`, `59b96c7`, `0d5f9b9`, `11c5782` and `ce5333b`.
- Carrier Watch, strike Slava, seed 2, with `--cap=12000` and with `--trace --cap=9000`.
- The unit suite and graphical playtests were not re-run here; CI ran them on `a301791`, whose tree is identical to `feaa09a`.
