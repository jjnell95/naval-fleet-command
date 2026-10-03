# Integrated air defence, weapon fixes and flight operations

This is an entertainment simulation using public platform families and estimated combat parameters. It does not reproduce Aegis software, any real combat system's behaviour, classified performance or doctrine. "Networked fire control" below is a game rule, described only in game terms.

The owner's complaint was specific: weapons systems don't work, there is no integrated air-defence network, and flight operations are clunky and unrealistic. Three read-only audits traced the weapon path, the shared air picture and the deck cycle end to end before anything was changed. Their findings are summarised under each heading. The fixes are listed in the order a player feels them.

## Weapons

**Refusals now say why.** An ENGAGE order from the contact menu, the dock, Ctrl+right-click or the Weapon Control board was refused with "Order refused by 1 selected platform" and no reason. `UnitManager.engage_rejection` gives the reason the order was refused, such as weapons hold, out of range, wrong weapon for the contact or no line of fire. The radio line and the firing board's receipt now carry it.

**A standing attack no longer parks on a stale plot.** It held fire, correctly, while the plot was stale, but it never gave up: a plot goes stale after 60 s and is not dropped for 30 minutes. After `ATTACK_STALE_S` (240 s) of closing on a plot nobody refreshes, the attack now ends and reports "Contact stale: no fresh plot to fire on".

**Rounds still queued at a sunk ship go back in the magazine.** Once the plot records the contact as destroyed, queued rounds are cancelled with "TARGET DESTROYED" and refunded.

**Air-to-air and anti-air "direct" rounds are not sea-skimmers.** AIM-9X, ASRAAM, IRIS-T, AAM-5, PL-10 and Mistral shared the `direct` profile with Hellfire and were treated as low flyers. A shot across a headland was refused and a round over land died. Those weapon types now fly at height. Air-to-surface `direct` weapons still meet the ground.

**Weapons Free fights.** The player's ships never fired at hostile aircraft unless ordered, though the rules said Free "fights". `AirDefence.engage_hostile_aircraft` now has a commander's ship on Weapons Free, with automatic air defence on, engage an identified hostile aircraft in its envelope.
- It fires one round at a time, with at most two in the air at an aircraft across the side.
- It keeps the last four rounds of each missile type for missiles.
- Weapons Tight, Hold, manual missile defence (Classic) and anything not identified hostile are untouched.
- The AI's sides already did this through their own controllers.

**The AI fires two SAMs at a fighter, not four.** Its salvo size for every missile was the four-round anti-ship volley, so it spent four long-range SAMs per aircraft. Anti-air weapons at an air contact now use the weapon's own salvo.

## The integrated air-defence network

Before this change the shared plot existed, but the defence cycle worked through inbound rounds one at a time and nearest ship first. In a raid, the two nearest ships both shot the first round while the second waited for a launcher to come free. A seeded Taiwan Strait run fired 46 interceptors at 16 detected rounds.

**One allocation for the force.** `AirDefence.run_cycle` now makes two passes over the raid:
1. Every inbound round gets one interceptor from the best-placed ship. A ship with a guidance channel free is asked before a nearer, saturated one.
2. Budgets are topped up, and the close-in guns get their turn.

One time-to-impact, to the ship the round is going for, decides the budget. Before, two checks used two different clocks, so the conserve policy could pass one and fail the other for the same shot.

**Each ship keeps its own inner layer.** The lifetime allowance per layer was shared by the whole force. Two escort point-defence missiles at a round aimed at the carrier left the carrier unable to fire its own point-defence missiles at it. The allowance is now kept per layer and per ship (`AirDefence.layer_key`).

**Networked fire control.** A new platform field, `cooperative_engagement`, is set on these hulls:
- Arleigh Burke IIA and III, Ticonderoga, Nimitz, Ford and Constellation (2027 catalogue).
- Maya, through its generator.
- Not on the 1990 Ticonderoga.

Between two fitted ships on the link, a radar-guided interceptor can be launched at a round or aircraft below the shooter's own radar horizon. The consort's emitting radar must hold the target inside its own horizon, with no land in between. The shot fails if that support goes: the consort's radar switching off, either ship dropping off the link, or the target leaving the consort's horizon. An unfitted consort's plot is still only a cue. Weapons with their own active seeker never needed this and are unchanged.

**What the player sees.**
- The Air Defence board names the ship engaging each inbound round, and how many more are on it.
- Its channel line reads "NETWORKED FIRE CONTROL n SHIPS" when two or more fitted ships are linked.
- A fitted ship's unit panel shows a NETWORKED FIRE CONTROL chip.

## Flight operations

**Jets no longer stop in the air.** A fixed-wing aircraft that reached its last waypoint, was ordered to stop, or finished an investigation with auto-return off sat at 0 kn. On the 0 kn floor of its fuel curve it burned less fuel than one on CAP. It now flies a 6 by 3 nm racetrack through that point at patrol speed (`Movement.enter_hold`). Helicopters still hover.

**A launch without a mission no longer flies off the chart.** An aircraft launched from the LAUNCH tab used to fly the ship's heading at transit speed until bingo. It now holds 6 nm ahead of its ship until it is given orders.

**Marshal.** Aircraft back at a deck that could not take them flew at the ship at transit speed and transit fuel burn, all at one point, overflying it each second. They now hold in a stack 5 nm astern at patrol speed: 1,500 m for fixed-wing, 150 m for helicopters. A deck counts as unable to take them when:
- the recovery spot is busy, or
- launches are in progress, or
- the flight deck is on fire.

They are called down when the deck clears. The mission board shows MARSHAL. Mission launches now wait for aircraft in marshal, not only those within 3.5 nm, so recoveries come first.

**No landing on a burning deck.** Launches were already refused at fire 0.35 or worse. Recoveries now are too, until the fire is under control.

**A helicopter aboard a carrier is not turned round like a strike fighter.** Turnaround was the base's figure for every type, so an MH-60R took 45 minutes on a Nimitz. A helicopter now takes no longer than it would on a helicopter deck (30 minutes).

**Air missions:**
- A CAP or ASW mission with "Back to station" off kept working after its first look, rather than holding with nothing to do until bingo. It now still intercepts the hostile it has just identified.
- A CAP intercept is flown at dash speed. The mission sets an airframe's speed when its state changes, not every second, so a dash the commander orders on station stands.
- A reconnaissance aircraft without sonar or buoys no longer flies to a submarine contact it can never identify and circles there until bingo.
- A strike whose launches were all called off ends "Strike called off", not "Strike complete".
- Bingo on a mission airframe, routine CAP rotation, no longer drops time compression to 1×. Bingo on any other aircraft still does.

**Ready alert.** A deck with fighters can hold 2 or 4 on alert, from the right-click menu under Ready alert. When a hostile air contact comes within 60 nm, or within 120 nm and closing, the deck scrambles them itself. They go into a CAP laid toward the raid at half its range, at most 40 nm out, and the radio reports "ALERT LAUNCH". The alert is spent by the scramble. A deck already flying its own CAP keeps its alert for the next raid. The unit panel shows READY ALERT n. This is the "launch alert states" item from the M36 list of missing features, in a simplified form; there are no Alert 5/15/30 tiers.

## Not changed, deliberately

- **Ballistic rounds still fly at one altitude.** A test pins that every ballistic round in the catalogue has an interceptor whose window covers it. A descending trajectory is a model change, not a fix.
- **The Air Operations dialog still opens on the LAUNCH tab.** Two native interface suites in CI drive that tab by default. With the departure hold, a plain launch is no longer a trap.
- **Tanker give is still counted in the receiver's endurance-seconds**, as documented. The tanker's own fuel is debited in the same units, which is inconsistent but low impact.
- **Manual and queued ENGAGE rounds can still be fired at a stale plot.** The standing attack and group attack refuse one. Changing the ENGAGE path changes what the firing board offers and needs its own pass.

## Validation

The regression suite grew from 977 to 1,004 tests, with new files `tests/test_integrated_defence.gd` (15 tests) and `tests/test_flight_deck.gd` (8 tests), plus additions to the attack and air-mission suites. Two existing assertions were updated deliberately:
- An investigating jet now holds when its task ends, instead of flying straight on.
- A CAP fighter on its way back from an intercept, flown at dash, counts as working its station.

Four operations were flown headless for 6,000 simulated seconds with the AI commanding both sides (`--autopilot --seed=2`), on `main` and on this branch. None had a script error.

| Operation | Interceptors fired | Rounds intercepted | Leakers | Offensive rounds fired | Hits scored |
|---|---|---|---|---|---|
| Taiwan Strait, main | 46 | 12 | 6 | 43 | 2 |
| Taiwan Strait, this branch | 57 | 14 | 4 | 37 | 2 |
| Aegis Bastion, main | 0 | 0 | 0 | 40 | 5 |
| Aegis Bastion, this branch | 0 | 0 | 0 | 24 | 5 |
| Carrier Watch (1990), main | 60 | 15 | 1 | 16 | 0 |
| Carrier Watch (1990), this branch | 66 | 15 | 1 | 8 | 0 |
| Hormuz, main | 77 | 29 | 5 | 26 | 3 |
| Hormuz, this branch | 79 | 29 | 5 | 35 | 3 |

Reading the table:
- In Taiwan Strait the raid is answered more completely: two more rounds stopped and two fewer leakers, for eleven more interceptors.
- Aegis Bastion scores the same five kills with 24 rounds instead of 40, because the AI no longer fires four long-range SAMs at each fighter. Carrier Watch's Tomcats likewise fire two Phoenix each instead of four.
- Hormuz's extra offensive rounds come from the other weapon-path changes; the outcome is unchanged.

These runs have the AI playing the player's side, so they do not exercise Weapons Free against aircraft, which applies only to a side with no AI commander. A single seed per operation is a stability and direction check, not a balance study.

One defect was found and fixed during validation. The first version of the jet hold made an AI search aircraft that reached a search point look busy, so it never took its next leg; in that build Carrier Watch's Tomcats fired nothing. A hold is now marked (`Unit.holding`, `Unit.has_route`), and the AI and the stalled-attack check treat a hold as no route. A test pins it.

The scenario generators were not re-run for the data change: in this environment the sequence does not reproduce the committed scenario files byte for byte. The one generated platform file that changed (Maya) was edited by hand to match the generator output exactly, and the generator carries the same change. The browser build was not rebuilt.
