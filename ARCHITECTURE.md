# Architecture

Status: Milestone 9 (operational depth). Emissions, the network, posture and damage all cost something.

Presentation work should start from `HANDOFF.md`, which says what may be changed and what may not.

## Layers
```
SIMULATION  (scripts/simulation, scripts/systems, scripts/entities)  — tick-based, no rendering
DATA        (data/)                                                  — Resources / JSON, no logic
PRESENTATION(scripts/ui, scenes/)                                    — frame-based, reads sim state
```

## Directory map
```
scenes/main/Main.tscn     root scene (Control). Hosts UI + Simulation nodes from M1 on.
scripts/core/             main.gd (wiring only), dev_harness.gd (command-line scaffolding),
                          order.gd, geo.gd, debug.gd
scripts/simulation/       SimulationClock, World, UnitManager, SensorManager, TrackManager,
                          WeaponManager, MissionManager
scripts/entities/         Unit → SurfaceShip / Submarine / Aircraft; Weapon
scripts/systems/          Movement, Detection, Combat, Damage, AI
scripts/ui/               TacticalMap, UnitPanel, ContactPanel, OrdersPanel, TimeControls
data/platforms/{surface,submarines,aircraft,helicopters}/   platform specs (nation is a field,
                          not a directory)
data/sensors/  data/weapons/  data/scenarios/
tests/                    headless GDScript tests (run via Godot --headless --script)
```

## Runtime tree (Main.tscn)
```
Main (Control, main.gd)            theme = UITheme.build(); global hotkeys; routes orders.
                                   Owns a DevHarness, which is scaffolding, not gameplay.
├── Simulation (Node)               loads scenario, forwards SimClock.tick → managers
│   ├── UnitManager (Node)          Array[Unit]; tick() → Movement.step(); issue_order()
│   ├── TrackManager (Node)         per-faction Array[Track]; observe(), tick() (stale/DR/drop)
│   ├── SensorManager (Node)        1 s sensor cycles: Detection → TrackManager.observe
│   ├── ThreatManager (Node)        per-faction picture of detected incoming rounds
│   ├── WeaponManager (Node)        salvos, weapons in flight, seeker acquisition, hits, intercepts
│   └── MissionManager (Node)       victory / loss evaluation
└── Layout (VBox)
    ├── TopBar (PanelContainer)     time, pause, 1x-60x, objective readout, brief/restart/menu
    ├── Middle (HBox)
    │   ├── UnitPanel               selected unit(s) detail
    │   ├── TacticalMap (Control)   custom _draw(); zoom/pan/select; emits order requests
    │   └── ContactPanel            track list + detail (reads Tracks only)
    └── OrdersPanel                 speed/course/weapon controls -> emits Order
Overlays (children of Main, above the layout): ScenarioMenu, BriefingPanel, mission banner.
Autoloads: SimClock (fixed 0.25 s ticks × speed), Debug (F3 flag).
```

## Key conventions
- **Coordinates:** world space in nautical miles (float, Vector2), y-up north. Speeds in knots,
  bearings in degrees true (0 = north, clockwise). Altitude ft, depth m.
- **Time:** `SimulationClock` owns sim time and acceleration (1/2/5/10/30/60x). Systems subscribe
  to `tick(dt_sim_seconds)`. Auto-drop to 1x on combat events.
- **Units vs Tracks:** `Unit` = ground truth. `Track` = a faction's perception of a unit. UI and AI
  operate on Tracks for enemies; only DEBUG mode exposes Units.
- **Orders:** command objects (`Order` resources) queued on units; UI never mutates units directly.
- **Data:** platform/sensor/weapon specs as Godot `Resource` (.tres) referencing shared sensor and
  weapon resources by id. Scenarios as JSON.
- **Signals:** managers emit sim events (`unit_destroyed`, `weapon_launched`, `track_updated`);
  UI listens. No UI references inside simulation code.
- **Debug:** single `Debug` autoload flag gate; all debug draw behind `Debug.enabled`.

## Current classes
| Class | File | Role |
|---|---|---|
| Geo | scripts/core/geo.gd | static nm/knots/bearing math + formatting |
| Order | scripts/core/order.gd | command object: MOVE, SET_COURSE, SET_SPEED, STOP, CLEAR_WAYPOINTS |
| PlatformSpec | scripts/data/platform_spec.gd | Resource: platform data (.tres in data/platforms) |
| SensorSpec | scripts/data/sensor_spec.gd | Resource: radar ranges, antenna height (GAMEPLAY) |
| DataDB | scripts/data/data_db.gd | static id → PlatformSpec / SensorSpec index (scans data/) |
| Detection | scripts/systems/detection.gd | radar horizon, effective range, detection quality |
| Track | scripts/simulation/track.gd | perceived contact: pos ± error, est course/speed, class, status |
| TrackManager | scripts/simulation/track_manager.gd | per-faction tracks; classification, LSQ kinematics, stale/DR |
| SensorManager | scripts/simulation/sensor_manager.gd | sensor cycle orchestration + plot noise (seeded RNG) |
| ContactPanel | scripts/ui/contact_panel.gd | contact list/detail; track_chosen |
| WeaponSpec | scripts/data/weapon_spec.gd | Resource: range, speed, seeker radius, damage, pk |
| Weapon | scripts/entities/weapon.gd | RefCounted round in flight; CRUISE → TERMINAL → DEAD |
| Combat | scripts/systems/combat.gd | intercept point, envelope check, hit probability |
| Damage | scripts/systems/damage.gd | hit-point pool, destroyed state, condition text |
| WeaponManager | scripts/simulation/weapon_manager.gd | launch/tick/impact; weapon_launched, weapon_impact, unit_destroyed |
| MissionManager | scripts/simulation/mission_manager.gd | mission_ended(result, summary) |
| ThreatManager | scripts/simulation/threat_manager.gd | detected inbound rounds per faction; threat_detected |
| AirDefence | scripts/systems/air_defence.gd | CPA geometry, threat assignment, layered engagement, decoys |
| AIController | scripts/systems/ai_controller.gd | opposing-force commander: state machine, engagement scoring, orders |
| MissionObjective | scripts/simulation/mission_objective.gd | one scenario predicate, built from JSON |
| ScenarioIndex | scripts/simulation/scenario_index.gd | lists data/scenarios for the menu |
| ScenarioMenu | scripts/ui/scenario_menu.gd | scenario picker; scenario_chosen |
| SensorContact | scripts/simulation/sensor_contact.gd | one observation, firm plot or bearing, handed to TrackManager |
| AviationManager | scripts/simulation/aviation_manager.gd | deck cycle, fuel, return to base, sonobuoys |
| Sonobuoy | scripts/simulation/sonobuoy.gd | a passive listener dropped in the water and left behind |
| Formation | scripts/systems/formation.gd | station keeping in the leader's frame, and the named patterns |
| BriefingPanel | scripts/ui/briefing_panel.gd | briefing and live mission-status board |
| Unit | scripts/entities/unit.gd | RefCounted ground truth: pos, hdg, spd, orders, waypoints |
| Movement | scripts/systems/movement.gd | static kinematics per tick (turn rate, accel, waypoints) |
| SimClock | scripts/simulation/sim_clock.gd | autoload clock; tick/speed_changed/paused_changed |
| UnitManager | scripts/simulation/unit_manager.gd | owns units; unit_added, order_issued |
| ScenarioLoader | scripts/simulation/scenario_loader.gd | JSON → units |
| Simulation | scripts/simulation/simulation.gd | sim root node |
| TacticalMap | scripts/ui/tactical_map.gd | map render + input; selection_changed, move_order_requested |
| MapSymbols | scripts/ui/map_symbols.gd | symbol drawing helpers |
| UITheme | scripts/ui/ui_theme.gd | programmatic dark theme |
| TopBar / UnitPanel / OrdersPanel | scripts/ui/*.gd | HUD panels (children built in code) |
| TestCase | tests/test_case.gd | assertion base; runner tests/run_tests.gd |

## Sensor / track pipeline
1. `SensorManager.run_cycle(now)` every 1 s sim: for each emitting observer × enemy unit,
   `Detection.radar_quality()` (range × signature, capped by radar horizon
   `2.23·(√h1+√h2)` nm). Detected → noisy plot → `TrackManager.observe()`.
2. `Track` accumulates observation time → classification UNKNOWN(0 s) → SURFACE(30 s) →
   CLASS_KNOWN(180 s, identity HOSTILE, `known_class`) → IDENTIFIED(600 s, `known_callsign`).
   Thresholds scale with quality and sensor `classify_rate`.
3. Kinematics: least-squares fit over a 300 s plot window (needs ≥45 s span), refreshed every 20 s.
4. `TrackManager.tick()`: unobserved > 60 s → STALE (dead-reckoned, error grows); > 30 min → LOST.
5. UI/AI read only `TrackManager.get_tracks(faction)`. `Track.truth` is for association/debug.
6. Events: `track_added` / `track_classified` (player faction → SimClock.drop_to_realtime + flash).

## Weapon pipeline
1. UI builds `Order.engage(track, weapon_id, salvo)`. `UnitManager.issue_order` emits
   `order_issued`; `Simulation._on_order_issued` routes ENGAGE to `WeaponManager.launch()`.
   The player and (from M5) the AI share this one command path.
2. `Combat.check_engagement` gates on magazine, track status and min/max range. The whole salvo
   is deducted at launch; rounds ripple off at `launch_interval_s`.
3. A round is aimed at a **Track**, never at a Unit. The aim point is
   `Combat.intercept_point()` from the track's estimated course and speed. Mid-course updates
   happen only while the track is ACTIVE, so firing at a stale track flies to stale water.
4. Within `seeker_range_nm` of the aim point the seeker looks for a real enemy Unit inside the
   acquisition radius. Found → TERMINAL homing on truth. Not found → NO ACQUISITION, round wasted.
   Guns have `seeker_range_nm = 0` and use a 0.5 nm radius, so gunnery accuracy is track accuracy.
5. Impact rolls `Combat.hit_probability` (base pk × target size). Hit → `Damage.apply`.
   Exceeding `max_range_nm` kills the round (RANGE EXHAUSTED).
6. `MissionManager.tick()` ends the mission when a side has no units left.

## Sonar and the underwater picture
A second sensing channel, deliberately unlike radar.

- **Noise.** `Detection.acoustic_noise()` takes a platform's `acoustic_signature` at a crawl and
  raises it quadratically with speed, then multiplies it again if the screw cavitates. The
  cavitation threshold moves with depth, so a shallow boat gives itself away at a speed a deep one
  gets away with. Every constant here is a GAMEPLAY_ESTIMATE.
- **Listening.** Passive range is `sensitivity * sqrt(noise)`, scaled down by the listener's own
  speed through `self_noise_factor`. Slowing down to hear is a real lever, and a towed array
  tolerates own speed better than a hull set.
- **Bearing only.** A passive contact reports a bearing and a guess at range. `Track` carries an
  uncertainty ellipse (`error_major_nm` along `error_axis_deg`, `error_minor_nm` across it) rather
  than a circle, so a sonar contact draws as a long sliver down the bearing line.
- **Target motion analysis.** `tma_quality` climbs with observation time and much faster while the
  listener is turning, which is how the sliver collapses into a position. This is an abstraction of
  the real problem, not a model of it. At high quality the estimate converges on the truth and
  kinematics fitting is allowed to run.
- **Active sonar.** Returns a firm plot immediately and sets `tma_quality` to 1, at the cost of
  being audible to everyone else at roughly 1.8x its own reach.
- **Radar cannot see under water.** `radar_signature_of()` returns zero for a submerged boat and a
  fraction for one at periscope depth.

## Aviation
An aircraft is an ordinary `Unit` with `domain = "air"`. It exists from scenario load but sits in
its hangar until launched, so the player can see what is available without those airframes being
detectable or shootable. `Unit.is_engageable()` is the single gate for that: sensors, weapons and
force-strength objectives all use it.

```
STOWED --launch--> LAUNCHING --launch_time_s--> AIRBORNE --bingo/order--> returning
   ^                                                                          |
   +---------------- recovery_time_s <-- RECOVERING <-- within 2.5 nm of home -+
```

- **Fuel is the constraint.** `endurance_s` is time at cruise; burn scales quadratically with
  speed, so a dash costs more than the clock suggests. At `BINGO_FRACTION` the aircraft turns for
  home on its own. Running dry loses the airframe. If the deck it came from has been sunk it
  diverts to the nearest friendly deck rather than being written off automatically.
- **Height is the whole point.** `Detection.observer_height_m()` returns the aircraft's altitude
  instead of a mast height, so an airborne radar's horizon is enormous. A Poseidon at eight
  kilometres sees ships several times further than the frigate below it.
- **Dipping sonar** is a `SensorSpec` with `requires_hover`. It contributes nothing unless the
  aircraft is slow and low, which is what makes the helicopter cycle fly, stop, listen, move on.
- **Sonobuoys** are dropped and left behind. One buoy says only that something noisy is inside its
  circle; two or more overlapping cross into a position. They expire.
- **Land.** A shore station uses `domain = "land"`. No weapon in the inventory lists `land` as a
  target type, so bases are currently un-attackable and the AI ignores them instead of emptying
  its magazines into a runway.

## Electronic support
An ESM set hears a radar transmit. It needs the signal one way where the radar needs it out and
back, so it does not care how small the emitter is: a ship radar could barely see switches on and
is heard at the full horizon. What it gives back is a bearing, so ESM contacts reuse the M7
bearing-only track machinery, and it classifies unusually fast because a radar type is a
fingerprint.

Line of sight still binds. Two ships hear each other at about twenty miles whatever the gain, which
is why ESM is not a longer-ranged radar. Its value is that it is passive, and that altitude lifts
the horizon: an aircraft with ESM hears a radiating warship from well over a hundred miles without
transmitting anything itself.

## The network
Sharing a contact is no longer assumed. A `Track` records which of our units contributed to it and
whether any of them is on the datalink.

- `Unit.datalink_connected()` is false for a submerged boat, an aircraft in a hangar, and anything
  whose platform has `has_datalink = false`, such as civil traffic.
- `Track.visible_to(unit)` is true if that unit found it, or if the track is networked and the unit
  is on the network.
- `TrackManager.tracks_for(unit)` is the picture one unit actually has, and the AI reasons from it.
- A sonobuoy report has no observing unit and is always relayed.

The consequence worth knowing: a deep submarine cannot cue anyone. What it hears is its own until
it comes shallow.

## Posture
Three standing orders, all per unit and all honoured by the AI as well as the player.

| Order | Effect |
|---|---|
| `SET_EMCON` | silent turns off radar and active sonar together; free switches the radar back on |
| `SET_ROE` | HOLD refuses every engagement including automatic defence; TIGHT defends only; FREE fights |
| `FORM_UP` / `BREAK_FORMATION` | station keeping on a leader, or steering for yourself again |

`AIController._manage_emissions()` makes emissions a decision rather than a default: a ship with
electronic support patrols and searches silently, and switches on only to classify, close or shoot.

## Damage
The hull is still a pool, and on top of it a hit can knock out one of three subsystems.
`propulsion` caps speed, `sensors` shortens every sensor aboard, and `weapons` below a quarter
stops the ship firing at all. The chance and severity scale with how much of the hull the hit took,
and `Damage.rng` follows the scenario seed like everything else.

## Torpedoes
Torpedoes reuse the `Weapon` flight loop. They run out to `run_to_enable_nm` before the seeker
comes on, then search the whole way in rather than only near the aim point, which is why a shot
down a rough bearing is still worth taking. `WeaponManager.can_target()` gates every seeker by
medium: an anti-ship missile cannot find a submerged boat and a torpedo is no use against
something out of the water. `Combat.suits_track()` applies the same rule at order time, so a
contact whose domain is not yet known cannot be engaged at all.

Nothing lists `torpedo` in its `target_types`, so a torpedo cannot be shot down. Decoys and
manoeuvre are the only answers, and manoeuvre genuinely helps: torpedo hit probability falls with
the target's speed, so a ship that has heard the weapon and is running is a much harder problem.

## Air defence pipeline
1. `SensorManager._detect_weapons()` runs in the same 1 s cycle. A round is seen when an emitting
   radar is inside `Detection.weapon_detection_range_nm()`, which is the lesser of radar power
   against a small target and the horizon at the round's flight altitude. Sea-skimming rounds
   therefore appear late (~17 nm); high-flying ones appear far out.
2. `ThreatManager` holds the picture per faction and is rebuilt every cycle, so a round that
   drops back below the horizon vanishes again. Detection is shared across a faction, standing in
   for a task-force air picture until datalinks arrive in Milestone 9. A faction whose ships are
   all silent sees nothing.
3. `AirDefence.run_cycle()` runs on a 1 s cadence from `Simulation._on_tick`. For each faction it
   works out which friendly ship each detected round is going for
   (`threatened_unit`: the locked-on ship, else closest point of approach within 3 nm), sorts by
   time to impact, and lets **any** ship in range engage. Escorts defend consorts, not just
   themselves.
4. `Unit.defensive_weapons()` returns interceptors longest-reach first, so layering is a property
   of the data rather than hard-coded tiers. At most two interceptors are committed per round at
   any moment; when they miss, the next layer gets its turn.
5. Interceptors are ordinary `Weapon` entities with `intercept_target` set, launched through
   `WeaponManager.launch_interceptor()`. On contact they roll
   `Combat.intercept_probability()` = interceptor pk / threat `defensive_difficulty`.
6. Soft kill: inside 2.5 nm the locked-on ship spends one decoy salvo, once per round, rolling
   platform `decoy_effectiveness` against the round's `soft_kill_resistance`.
7. `weapon_defeated` removes the round from every threat picture. No player order is involved
   anywhere in this pipeline.

### Engagement allowances
Defence is deliberately finite, so a large enough salvo gets through a good escort:
- `fire_control_channels` per platform caps how many rounds one ship can guide against at once.
- Two guided interceptors per round over its whole flight (shoot-shoot-look), and at most two in
  the air at any moment.
- Close-in weapons are exempt from channels and the guided allowance, since they are
  self-contained, but get their own allowance of two bursts. One burst is modelled as a single
  engagement, so a close-in magazine counts bursts rather than rounds.

## Missions
Objectives are data. A scenario carries two lists and every entry is a predicate that latches once
true, so the same shape means opposite things in each list: RED reaching a point is a loss for a
picket, BLUE reaching one is a victory for an escort.
```json
"objectives": {
  "text": "...",
  "victory": [ { "type": "reach_area", "faction": "BLUE", "callsigns": ["HNoMS Maud"],
                 "center_nm": [-45,-32], "radius_nm": 14, "text": "..." } ],
  "loss":    [ { "type": "unit_lost", "callsigns": ["HNoMS Maud"], "text": "..." } ]
}
```
Predicate types: `force_destroyed` (with optional `max_alive`), `unit_lost`, `reach_area`
(optionally scoped to named ships, needs `count` arrivals), `time_elapsed`. `MissionManager`
checks the loss list first, so a simultaneous win and loss resolves as a loss. Victory needs every
entry in the victory list. An unrecognised type never completes, so a typo fails loudly in tests
rather than silently handing out a win.

Other scenario-level fields: `neutral_factions` (their ships classify as NEUTRAL instead of
HOSTILE, no AI controller is built for them, and the AI leaves them alone), `seed` (pins the RNG;
otherwise every run differs), `order` and `forces` (menu presentation), and per unit `patrol_nm`
and `ai_posture`.

## AI
`AIController` is created per non-player faction by `Simulation._build_ai()` and ticked every 2 s.
It reads `unit_manager.get_faction_units(its own faction)`, `track_manager.get_tracks(its own
faction)` and `threat_manager`. It never reads an enemy `Unit` and never reads `Track.truth`, so
it can be surprised, decoyed, and made to shoot at water exactly like the player.

State priority each cycle, highest first:
```
WITHDRAW    health below 35 percent, or no anti-ship rounds left while hostiles are known
DEFEND      a detected round is closing on this ship
ENGAGE      a confirmed hostile is in envelope and worth a salvo
SHADOW      a confirmed hostile exists but no shot is worth taking
INVESTIGATE an unidentified contact exists; close to classify it
SEARCH      contact was held recently and has been lost; go to the last known position
PATROL      standing route from the scenario, else hold course
```
`ai_posture` on a unit changes that ladder. `standard` is the above. `breakout` means the ship has
somewhere to be: it presses along its patrol route at full speed, shoots what it can on the way,
does not stop to shadow, does not turn away from inbound rounds, and never withdraws for empty
magazines. Its automatic air defence still runs. This is how a scenario gives the opposing force a
mission of its own rather than a generic willingness to fight.
Engagement is refused when the track is stale, when identity is not yet confirmed hostile, while
a salvo fired at that track is still being assessed, or when enough rounds are already in the air
against it. Two further rules keep it honest underwater: a weapon whose time of flight exceeds
`MAX_TIME_OF_FLIGHT_S` is not fired at all, which stops a 50 knot torpedo being launched across
twenty miles without needing a torpedo special case, and a bearing-only track needs a real range
solution before anything is fired at it. The assessment window itself scales with time of flight,
so a slow weapon is given time to arrive before the shot is judged a failure. Shadow standoff is bounded by radar range rather than weapon range, because a
track that is not being observed cannot receive mid-course updates. Every decision leaves through
`UnitManager.issue_order()`, the same path the player's UI uses, so nothing the AI does is
mechanically privileged.

## Rendering approach
TacticalMap draws everything in one `_draw()` (no per-unit nodes). Hit-testing is manual
(nearest symbol within 14 px). Symbol sizes are fixed in pixels; world→screen via
`center_nm` + `ppn` (pixels per nm), y flipped.
