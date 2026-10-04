# Air combat: the regressions M38 left behind

This is an entertainment simulation with gameplay-estimate numbers. Nothing here describes a real system's performance or doctrine.

M38 made air combat two-sided, but its pull request listed four results that were worse than before:
- F/A-18E against J-15 from 40 nm: the F/A-18 lost 17 of 20 and the J-15 3, where the original build traded evenly.
- The same matchup from 80 nm: 18 to 4.
- The PL-15 outranged the AMRAAM by 80 nm to 45.
- SM-2's first shot at a bomber flying straight in came about 9 nm later than before.

All four are fixed here. Two causes were behaviour, one was the range rule, and one was data.

## What was wrong

**The fighter turned tail inside its own envelope.** The AI's air-to-air stand-off was a share of the fighter's reach: half of it, or 80% when a known enemy outranged it. Inside that stand-off the fighter turned away at cruise speed, the movement a strike aircraft uses after firing at a ship. Outranged at 40 nm, the F/A-18 held at 36 nm, but the range rule only let it fire inside about 27 nm. So it turned away before it ever had a shot, and fired 10 AMRAAMs in 20 fights. The J-15 did the same at 40 nm, but its PL-15 could already reach.

**The range rule used one flat margin.** M38 limited a shot at an aircraft to the share of the missile's range it could still fly if the target ran at its type's top speed from the instant of launch: (missile speed − top speed) / missile speed. That share was floored at 60%, or 80% for a target flying straight in. This charged a Tu-22M3, which needs a minute to turn round, the same as a fighter that turns in twenty seconds. SM-2 therefore waited until 35 nm to fire at a bomber it could have reached from 43.

**A missile that lost its updates died at an empty aim point.** From 80 nm the J-15 fired first. The F/A-18 got its AMRAAMs away at 35 nm while the J-15 was turning, and was shot down 20 seconds later. Its rounds had no more updates, so they flew to the last predicted intercept point, found nothing within six miles, and ended there. That happened to 32 of 46 AMRAAMs.

**The AMRAAM was outranged by 35 nm.** No tactic closes that gap for an aircraft that cannot see a missile coming until its seeker goes active. In the 80 nm case the F/A-18 was almost always dead before it could reach its own envelope.

## The fixes

**No-escape range** (`Combat.air_no_escape_range_nm`). A shot at an aircraft is allowed out to the range from which it could still be caught if it turned and ran the moment it saw the shot. The calculation assumes the target:
1. holds its course for five seconds (`AIR_REACTION_S`);
2. turns until the shooter is dead astern, at its type's turn rate (coming straight in, the turn gains it time but no distance);
3. runs, accelerating at its type's rate up to its top speed, while the missile flies its whole reach.

The performance figures come from the catalogue entry for the reported class, never from the aircraft itself. A type the plot does not know turns like a fighter (6°/s) and runs at the plot's speed. The 60% floor stays.

| Shot, target at about 500 kn | Coming straight in | Already running | Before (either way) |
|---|---|---|---|
| SM-2 (45 nm) at a Tu-22M3, 3°/s turn | 43.3 nm | 29.7 nm | 36 nm / 27 nm |
| SM-2 at a Su-35S, 8°/s turn | 34.7 nm | 27.0 nm | 36 nm / 27 nm |
| AMRAAM (now 60 nm) at a J-15 | 49.1 nm | 41.0 nm | 36 nm / 27 nm at 45 nm reach |
| PL-15 (80 nm) at an F/A-18E | 64.7 nm | 56.2 nm | 64 nm / 49 nm |

**Fighters press, then crank** (`AIController._fight_air`). Against another aircraft, a fighter with air-to-air rounds left:
- With no round of its own on the way, closes at dash until it is inside 90% of its no-escape range, whatever the other side carries.
- Once it has rounds on the way, or is inside its shot and waiting, flies 50° off the bearing (`AIR_CRANK_DEG`). The contact stays on its radar to guide the rounds while the range closes far more slowly.
- With a missile actually coming at it, still breaks and runs, as before (DEFEND).

A fighter with no air-to-air rounds left still turns away as a strike aircraft does.

**A round at an aircraft searches on** (`WeaponManager.searches_on`, `Weapon.searching_on`). A round fired at an aircraft that reaches its aim point with nothing in its seeker now holds its heading with the seeker on until its fuel runs out. It ends as NO ACQUISITION only if it never finds anything. Rounds fired at ships and submarines still end at the aim point.

**Data: the 2027 AIM-120 and R-77 families reach 60 nm, up from 45.** Public estimates for the AIM-120C-7 and the R-77-1 are both around 105–110 km (57–60 nm), and the AIM-120D, standard on US Navy Super Hornets, reaches further. At 45 nm the AMRAAM sat below the JASDF's AAM-4B (54 nm) in this catalogue. Both families move together so the F/A-18 against Su-35 matchup stays even. The PL-15 stays at 80 nm, so it still outranges both, by a third rather than three-quarters; the Meteor stays at 65. The 1990 Cold War catalogue uses its own weapons and is unchanged. Each change is a one-line edit to `data/weapons/aim120_family.tres` or `r77_family.tres` if the owner wants a different balance.

## Validation

The regression suite has 1,039 tests, 0 failed. `tests/test_air_combat.gd` was rewritten for the new rule and gained six tests:
- a slow-turning bomber is shot from further out than a fighter;
- the no-escape range reads the plot, not the aircraft;
- a fighter closes at dash until it has a shot;
- a fighter with rounds on the way cranks instead of turning tail;
- a round at an aircraft searches on past an empty aim point and finds it;
- a round that never finds anything ends as NO ACQUISITION at the end of its fuel.

The three behaviour tests fail on the old code. M38's assertions on the removed escape factor were restated against the no-escape range, its source check on the outranged stand-off was replaced by the dash test, and one edge case moved from 35 nm to 34 nm.

**Synthetic engagements.** The M38 measurement harness was re-run on `main` and on this branch with the AI on both sides: 20 trials per case, the same seeds, starting head-on at 480 kn. Losses are blue / red.

| Case | main | This branch |
|---|---|---|
| F/A-18E vs J-15, 40 nm | 17 / 3, 10 AMRAAMs fired | 11 / 18, 46 fired |
| F/A-18E vs J-15, 80 nm | 18 / 4, 32 of 46 AMRAAMs found nothing | 17 / 15, 2 found nothing |
| F/A-18E vs J-15, 2v2 | 36 / 25 | 34 / 31 |
| Typhoon vs J-15, 80 nm | 16 / 17 | 18 / 14 |
| F/A-18E vs Su-35S, 60 nm | 17 / 16 | 17 / 15 |
| F/A-18E vs Su-35S, 40 nm | 17 / 15 | 15 / 16 |
| F/A-18E vs Su-35S, 20 nm | 11 / 17 | 10 / 14 |
| Player attack order vs Su-35S, 80 nm | 15 / 14 | 17 / 16 |
| SM-2 vs Tu-22M3 straight in: first shot, kill time | 34.9 nm, 641 s | 42.1 nm, 602 s |
| SM-2 vs Su-35S straight in | 34.9 nm, 364 s | 33.6 nm, 371 s |
| ESSM vs Su-34, scripted at 20 nm | 15 kills of 30 | 15 kills of 30 |

No AMRAAM, R-77, PL-15 or Meteor ran out of fuel in any synthetic case on this branch.

The original build traded evenly from 40 nm, 31 against 29 over 40 trials. The branch now favours the F/A-18 in that one case. Both sides classify each other at about the same moment, and the AMRAAM was decoyed slightly less often over these seeds. From 80 nm the J-15 still fires first, at 53 nm against 44, which is the PL-15's remaining edge.

**Operations.** Five operations were flown for 6,000 simulated seconds with the AI on both sides, three seeds each, on `main` and on this branch. Kills scored are by each side, counting every unit destroyed.

| Operation | main, blue / red kills | Branch, blue / red kills | Air-to-air rounds |
|---|---|---|---|
| Taiwan Strait | 28 / 25 | 34 / 20 | AMRAAM out of fuel 17 → 0; rounds per hit 4.3 → 3.4. PL-15s fired 72 → 58 |
| Aegis Bastion | 21 / 15 | 22 / 12 | AMRAAMs finding nothing 13 → 5; R-77 now fired at 40 nm, rounds per hit 2.8 → 4.0 |
| Tartus | 17 / 29 | 15 / 26 | Meteor rounds per hit 4.1 → 3.2 |
| Hormuz | 26 / 6 | 26 / 6 | No air-to-air; ship and shore SAMs unchanged |
| Northern Passage | 5 / 1 | 5 / 1 | Unchanged |

None of the runs had a script error. Three seeds per operation is a direction and stability check, not a balance study. The blue side scores a little more in Taiwan Strait and Aegis Bastion, mostly because its AMRAAMs no longer run out of fuel.

## Not changed

- **Aircraft still get no missile launch warning.** An aircraft defends only once it sees the missile, usually when the seeker goes active. Its own no-escape calculation assumes the target reacts within five seconds, so the rule errs toward holding a shot.
- **SM-2 at a fighter fires about a mile later than before.** The Su-35's 8°/s turn earns it a bigger margin than M38's flat 80% floor gave it, and it dies seven seconds later. Kills hold at 20 of 20.
- **The browser build was not rebuilt.**
