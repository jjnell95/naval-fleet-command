# M40: Diesel boats, anti-radiation missiles and a review of the core

9 November 2026 · local development build · Godot 4.7.2

Two things the simulation got physically wrong or left out, and seven defects found by reading the core. Every figure below is a GAMEPLAY_ESTIMATE in the shape of public descriptions; none is a claim about a real system.

## Diesel-electric submarines

A Kilo could hold 20 knots submerged for the whole battle, exactly like a nuclear boat. The catalogue's own Gotland entry said so: "Batteries, diesel snorkeling and AIP energy accounting are not modelled." That removed the whole character of the type: silent while it waits, unable to chase, and forced to expose itself after a sprint.

`SubmarinePower` (`scripts/systems/submarine_power.gd`) models it for the seven conventional boats.

- **Battery.** Drain per hour is `1 / battery_hotel_h + (speed / top speed)³ / battery_sprint_h`. A Kilo has about an hour at 20 knots, about five at 12 and more than a day at 6.
- **Air-independent plant.** Gotland (5 kn) and the Type 039A (4 kn) run at or below that speed without touching the battery. Above it the battery takes the load.
- **Snorkelling.** The boat comes to 15 m and runs its diesels: a full charge in two to three hours. While it does, its radiated noise is four times as great (twice the passive detection range), its radar signature is a snorkel head (three times a periscope's), and it is held to 8 knots. A boat on the surface is on diesels too.
- **A flat battery** leaves 3 knots of steerage way until the boat charges.
- **The crew** secures the snorkel by itself when the charge is complete or the boat turns away from a weapon, and goes back to the depth it came up from. An order deeper than periscope depth secures it too.

| Boat | Hotel (h) | Sprint (h) | Charge (h) | AIP |
|---|---|---|---|---|
| Kilo 636.3 | 200 | 1.0 | 3.0 | none |
| Kilo 877 / 877EKM | 180 | 0.9 | 3.2 | none |
| Gotland | 200 | 1.0 | 3.0 | 336 h at 5 kn |
| Type 039A/B | 200 | 1.0 | 3.0 | 240 h at 4 kn |
| Taigei (lithium-ion) | 400 | 2.5 | 2.0 | none |
| Ghadir | 60 | 1.0 | 2.5 | none |

**Commanding it.** The data display has a `%BATTERY` row with what the boat is running on and how long it lasts at its present speed. The Orders menu has **Snorkel and charge** and **Secure snorkel** (`Order.snorkel`, a new `SNORKEL` order type appended to the enum). The boat reports on the radio at 30%, at 10%, when flat and when charged. A scenario can start a boat part-charged with `"battery": 0.6` on the unit.

**The enemy.** An AI captain (`AIController._manage_battery`) charges at 30% when nothing on his own plot is within 15 nm, breaks the charge off when something closes, and below 4% charges regardless, because the alternative is to stop. `_manage_depth` leaves a charging boat where it is unless it has to hide.

## Anti-radiation missiles

Emission control cost a side only detection: a radar that was on could be heard, and that was all. The weapon that makes radiating dangerous was missing.

- **Three weapons.** AGM-88 (80 nm) on the EA-18G, Kh-31P (60 nm) on the Su-34 and YJ-91 (60 nm) on the J-16, two each, added to the existing fits. `WeaponSpec.is_anti_radiation()` is `guidance == "passive_radar_homing"`.
- **It needs only a bearing.** It is the one weapon besides a torpedo that can be fired at a bearing-only contact, and the only one that can be fired at an intercept with no domain yet. The contact must have been heard radiating: `Track.last_esm_time`, set by this side's own ESM, within two minutes of the contact last being held at all (`Track.radiating()`). Otherwise the order is refused with CONTACT NOT RADIATING. Nothing reads the target's radar switch.
- **In flight.** The seeker listens from the rail and takes the first hostile emitter in a 45° cone within its seeker range. It does not take its own side's radars or a neutral's. With nothing at the aim point it flies on down the bearing until its fuel runs out.
- **Switching off.** The round flies to where it last heard the radar. If the emitter is still within a quarter of a mile of that point the hit chance is 40% of normal; if it has moved off, the round is lost. A radar that comes back on is a target again. So a shore site that shuts down is suppressed, and a ship that shuts down and keeps moving escapes, which is the real bargain: the missile wins either way for as long as the radar stays off.
- **A hit** does a small warhead's damage and takes 0.75 off the target's sensors. Chaff and flares do nothing to a passive seeker; SAMs and guns engage it like any other round.
- **The enemy.** An AI radar with no SAM aboard goes silent when an anti-radiation round it knows of is coming its way inside 1.5 seeker ranges, and comes back up when the round is gone. A ship that can shoot at the round keeps its picture.

**Art.** The Kh-31P and YJ-91 share the Kh-31A's airframe, as the real missiles do, and use its model and renders. The AGM-88 uses the AIM-120's as a stand-in; it needs its own model.

**What is not done.** The player gets no named warning that an inbound round is an anti-radiation one. The AI does not plan suppression: an AI aircraft fires the weapon only when its ordinary weapon choice reaches it, which in practice means the EA-18G, or a strike fighter whose longer-ranged missiles are gone. Aircraft radars cannot be targeted.

## Defects found reading the core

A read of the fifteen core simulation files found seven defects. Each is fixed and pinned in `tests/test_review_fixes.gd` except the periscope sighting, which changed constants only.

| Defect | Was | Now |
|---|---|---|
| ASW torpedo against a shallow boat | A boat at 20 m or less could not be acquired by any torpedo listing only "subsurface", and rising to 20 m shook off one already homing | `WeaponManager.can_target` follows a submarine to any depth |
| Torpedo down a bearing | Died at the plot's guessed range: a Mk 48 with a 25 nm run stopped after 8 nm with the boat at 12 | Runs on down its heading, seeker on, to the end of its run |
| Periscope sighting | Any hull within 6 nm identified a boat at periscope depth in one cycle, with an exact position | 1.5 nm (3 nm snorkelling), less in a sea, horizon from a 1 m mast, 0.3 nm error |
| Fixed-wing speed | A jet with a waypoint could be ordered to 10 knots and stay airborne, burning less fuel | Held to 60% of patrol speed |
| Waypoint inside the turning circle | Orbited for ever: an F/A-18E at 480 kn never reached a point 1.1 nm ahead and 0.3 nm abeam | Counted as passed when it lies inside either full-rudder circle; a point close astern is still reached by coming round |
| Sensor damage and incoming weapons | Missile and torpedo warning ranges ignored sensor damage | Scaled by `sensor_efficiency()` like every other range |
| SAM guidance on a coasting track | The illuminator horizon used the last plotted altitude indefinitely | A track that is not ACTIVE is assumed to be at sea level |

The first attempt at the waypoint fix (anything abaft the beam within two radii) stopped a formation's ships short of waypoints they could reach and failed two seeded AI-raid tests; it was replaced with the exact two-circle geometry, under which the whole suite passes unchanged.

## Evidence

- `tests/run_tests.gd`: 1,064 tests, 0 failed (1,039 before).
- `tools/verify_northern_passage.py` and `tools/verify_save_continuation.py --quick`: outcomes, replay and save continuation unchanged or identical.
- New: `tests/test_submarine_power.gd` (8), `tests/test_anti_radiation.gd` (11), `tests/test_review_fixes.gd` (6).

## Next

- Balance: nothing was re-swept. Hormuz, where the Kilo was already the open question, now has a boat that cannot sprint for long; validate over seeds before touching torpedo effectiveness.
- A suppression role for the AI plan (anti-radiation shots timed ahead of the strike), and a named warning for the player.
- An AGM-88 model.
- The hold racetrack is narrower than the turn diameter of the largest aircraft; they now pass its corners instead of orbiting the first, but the pattern should scale with the airframe.
