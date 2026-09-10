# Data Sources

Concise source log for real platforms/weapons/sensors in `data/`. Research only what the current
milestone needs. Uncertain performance values are tagged `GAMEPLAY_ESTIMATE` in data files and are
tuning parameters, not claimed real-world measurements.

## Source priority
1. Official navy / MoD material  2. Manufacturer docs  3. Government reports
4. Reputable defense references  5. Quality secondary sources

## Platforms (M1: dimensions, displacement, speed band only)
| id | Public figures used | Source class | Gameplay estimates |
|---|---|---|---|
| usn_ddg_arleigh_burke_iia | ~155 m, ~9,200 t, 30+ kn | US Navy fact file; public references | cruise 18 kn, turn 3°/s, accel 0.25 kn/s |
| rnon_ffg_fridtjof_nansen | ~134 m, ~5,290 t, 26 kn | Norwegian Armed Forces; public references | cruise 16, turn 3, accel 0.22 |
| rfn_ffg_admiral_gorshkov | ~135 m, ~5,400 t full, ~29 kn | Public defense references | cruise 14, turn 3, accel 0.22 |
| rfn_fsg_steregushchiy | ~104.5 m, ~2,200 t, 27 kn | Public defense references | cruise 14, turn 3.5, accel 0.25 |

Hull callsigns in scenarios use real, publicly listed ship names; engagements are fictional.

## Sensors (M2: designation and role only; all ranges/heights are GAMEPLAY_ESTIMATE)
| id | System | Fitted to | Game values |
|---|---|---|---|
| an_spy_1d_v | AN/SPY-1D(V) | Arleigh Burke IIA | surface 40 nm (horizon-capped ~22), air 200, antenna 20 m |
| an_spy_1f | AN/SPY-1F | Fridtjof Nansen | surface 35, air 150, antenna 18 m |
| poliment_5p20 | Poliment 5P-20 | Admiral Gorshkov | surface 35, air 150, antenna 20 m |
| furke_2 | Furke-2 | Steregushchiy | surface 30, air 80, antenna 22 m |

Radar signature factors (1.0 Burke, 0.85 Nansen/Gorshkov, 0.7 Steregushchiy) and mast heights are
gameplay abstractions of publicly discussed shaping, not measured RCS.

## Weapons (M3: family, role and broad public range band only)
Every numeric field in `data/weapons/*.tres` is a GAMEPLAY_ESTIMATE tuning parameter. Guidance is
recorded as an abstraction label; no seeker logic, countermeasure response or engagement doctrine
is modelled.

| id | Family | Carrier | Game values (range nm / speed kn / damage / pk) |
|---|---|---|---|
| rgm_84_harpoon | Harpoon | Arleigh Burke IIA | 70 / 480 / 40 / 0.80 |
| nsm_strike_missile | NSM | Fridtjof Nansen | 100 / 500 / 45 / 0.85 |
| p800_oniks | Oniks | Admiral Gorshkov | 130 / 1100 / 65 / 0.82 |
| kh35_uran | Kh-35 | Steregushchiy | 70 / 480 / 35 / 0.78 |
| mk45_mod4_gun | Mk 45 127 mm | Arleigh Burke IIA | 13 / 1600 / 10 / 0.55 |
| oto_76mm_gun | 76 mm | Nansen, Steregushchiy | 8 / 1600 / 6 / 0.50 |
| a190_100mm_gun | A-190 100 mm | Admiral Gorshkov | 10 / 1600 / 8 / 0.52 |

Health pools (Burke 110, Nansen 85, Gorshkov 90, Steregushchiy 60) are abstract damage capacity
chosen so a frigate takes two to three missile hits, not a displacement or survivability claim.
Loadouts are scenario configuration, not a statement about how any real hull is armed.

## Defensive weapons (M4)
Same discipline as the strike weapons: family and role are public, every number is a
GAMEPLAY_ESTIMATE. No countermeasure logic, fire-control behaviour or engagement doctrine is
modelled; interception is a single probability roll per interceptor.

| id | Family | Carrier | Game values (range nm / speed kn / pk) |
|---|---|---|---|
| sm2_family | Standard Missile | Arleigh Burke IIA | 45 / 2000 / 0.72 |
| essm_family | ESSM | Arleigh Burke IIA, Fridtjof Nansen | 25 / 2400 / 0.78 |
| phalanx_ciws | Phalanx | Arleigh Burke IIA | 1.2 / 3000 / 0.55 |
| redut_family | Poliment-Redut | Admiral Gorshkov, Steregushchiy | 40 / 2000 / 0.70 |
| ak630_ciws | AK-630 | Admiral Gorshkov, Steregushchiy | 2.0 / 2600 / 0.50 |

Interceptor effectiveness was retuned in Milestone 5 (SM-2 0.50, ESSM 0.55, Redut 0.48, Phalanx
0.40, AK-630 0.35) together with engagement allowances, so that a small salvo is usually stopped
but a concentrated one is not. Close-in magazines count engagement bursts, not rounds.
`fire_control_channels` (Burke 6, Nansen 4, Gorshkov 4, Steregushchiy 2) is a gameplay
abstraction of how many simultaneous engagements a ship can guide, not a published figure.

Anti-ship rounds carry three added abstractions: `signature_factor` (how small a radar target the
round is), `altitude_m` (sets the detection horizon, 8-12 m for sea-skimming profiles), and
`soft_kill_resistance`. Decoy counts and effectiveness are per platform. Loadouts are scenario
configuration and are not a claim about how any real hull is fitted. The Fridtjof Nansen is given
no close-in layer deliberately, to create an escort dependency worth playing around.

## Platforms and weapons added in Milestone 6
Same discipline throughout: class names, rough dimensions and role are public; every performance
number is a GAMEPLAY_ESTIMATE tuning parameter.

| id | Class | Nation | Public figures used |
|---|---|---|---|
| dnk_ffg_iver_huitfeldt | Iver Huitfeldt-class frigate | Denmark | ~138.7 m, ~6,645 t, 28 kn |
| deu_fsg_braunschweig | Braunschweig-class corvette (K130) | Germany | ~89 m, ~1,840 t, 26 kn |
| rnon_aux_maud | Maud-class logistics support vessel | Norway | ~183 m, ~27,500 t, 18 kn |
| rfn_fsg_buyan_m | Buyan-M-class corvette (Project 21631) | Russia | ~74 m, ~950 t, 25 kn |
| civ_merchant_bulk | Merchant bulk carrier | Civil | generic commercial hull, not a military platform |

| id | Family | Carrier | Game values (range nm / speed kn / damage / pk) |
|---|---|---|---|
| rbs15_mk3 | RBS-15 | Braunschweig | 85 / 480 / 42 / 0.80 |
| kalibr_asm | Kalibr (anti-ship) | Buyan-M | 110 / 500 / 50 / 0.80 |
| ram_block2 | RAM | Braunschweig | 5 / 2200 / interceptor pk 0.60 |

Sensors added: TRS-3D, APAR/SMART-L suite, Pozitiv-ME1, and a civil navigation radar for merchant
and auxiliary hulls. All ranges are gameplay estimates.

Ship names used in scenarios are real, publicly listed hull names; every situation, engagement and
loadout is fictional.

## Submarines, sonar and torpedoes (Milestone 7)
The same discipline, and it matters more here than anywhere else: real acoustic signatures, diving
depths and sonar detection ranges are not public. Nothing in this section is a claim about any real
platform. Class names, rough dimensions, propulsion type and role are public; every number below is
a tuning parameter chosen to make the game work.

| id | Class | Nation | Public figures used |
|---|---|---|---|
| usn_ssn_virginia | Virginia-class attack submarine | USA | ~115 m, ~7,900 t submerged, "25+ knots" |
| rfn_ssk_kilo | Improved Kilo-class (Project 636.3) | Russia | ~73.8 m, ~3,950 t submerged, ~20 knots submerged |

| id | System | Fitted to | Game values (passive nm / active nm) |
|---|---|---|---|
| an_bqq_10 | AN/BQQ-10 suite | Virginia | 30 / 14 |
| mgk_400em | MGK-400EM suite | Improved Kilo | 22 / 10 |
| an_sqs_53c | AN/SQS-53C hull sonar | Arleigh Burke | 13 / 12 |
| captas_mk2 | CAPTAS Mk2 towed array | Fridtjof Nansen | 24 / 9 |

Passive figures are the range against a noisy surface combatant; against a quiet boat at a crawl
they fall to a few miles, which is the whole point.

| id | Family | Carrier | Game values (range nm / speed kn / damage / pk) |
|---|---|---|---|
| mk48_adcap | Mk 48 family | Virginia | 25 / 55 / 90 / 0.75 |
| ugst_torpedo | UGST family | Improved Kilo | 22 / 50 / 85 / 0.72 |
| mk54_lwt | Mk 54 lightweight torpedo | Fridtjof Nansen | 6 / 40 / 55 / 0.70 |
| rgm_139_vla | Vertical-launch ASROC | Arleigh Burke | 12 / 240 / 55 / 0.68 |

Rocket delivery for the ship-launched weapon is abstracted into its speed rather than modelled as a
separate flight phase. Acoustic signatures, cavitation thresholds, self-noise penalties and target
motion analysis rates are all invented gameplay constants.

## Aviation (Milestone 8)
Class names, rough dimensions, maximum take-off mass, broad speed and altitude bands and role are
public. Endurance, signature, health, deck cycle times and every sensor and weapon value are
GAMEPLAY_ESTIMATE.

| id | Class | Nation | Public figures used |
|---|---|---|---|
| usn_helo_mh60r | MH-60R Seahawk | USA | ~19.8 m, ~10 t MTOW, ASW/ASuW role |
| usn_mpa_p8a | P-8A Poseidon | USA | ~39.5 m, ~85 t MTOW, maritime patrol role |
| rfn_strike_su30sm | Su-30SM | Russia | ~21.9 m, ~34 t MTOW, strike role |
| shore_air_station | none | none | an abstraction, not a real installation |

| id | System | Fitted to | Game values |
|---|---|---|---|
| an_aqs_22 | AN/AQS-22 dipping sonar | MH-60R | passive 38 nm, active 11 nm, hover required |
| an_aps_153 | AN/APS-153 radar | MH-60R | surface 25 nm, air 60 nm |
| an_apy_10 | AN/APY-10 radar | P-8A | surface 120 nm, air 200 nm |
| bars_radar | N011M Bars | Su-30SM | surface 80 nm, air 120 nm |

Sonobuoy sensitivity, count and life are gameplay values. The shore air station is a fixed point
that land-based aircraft fly from; it does not represent any real base and carries no equipment.
Interceptor warheads were given non-zero damage in this milestone so that surface-to-air weapons
can engage aircraft as well as intercept missiles.

## Electronic support (Milestone 9)
System designation and role are public. Gain, bearing accuracy and classification rate are
GAMEPLAY_ESTIMATE, and the generic NATO entry stands in for a modern support suite where the exact
fit differs by ship.

| id | System | Fitted to | Game values |
|---|---|---|---|
| an_slq_32 | AN/SLQ-32 | Arleigh Burke | gain 2.0, bearing 2.0 deg |
| an_alq_240 | AN/ALQ-240 | P-8A | gain 2.2, bearing 1.5 deg |
| mp_405 | MP-405 | Gorshkov, Steregushchiy, Buyan-M | gain 1.8, bearing 2.5 deg |
| nato_esm_suite | generic NATO suite | Nansen, Iver Huitfeldt, Braunschweig | gain 1.9, bearing 2.2 deg |

Gain multiplies the emitter's radar power to give a detection range, then the radio horizon caps
it. Component damage thresholds, formation station offsets and rules-of-engagement behaviour are
all gameplay constructs with no source beyond the design.
