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

Measurements are being added.
