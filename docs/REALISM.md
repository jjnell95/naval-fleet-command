# M15: real geography, real air wings, and a deck that behaves like a deck

This is an entertainment simulation using public platform families and explicitly estimated combat parameters. It does not reproduce Aegis software, classified performance, or operational doctrine. **The conflict is fiction.** There is no NATO-Russia war, no deployment resembling these scenarios, and no operational plan behind any of them. Real place names, real pennant numbers and real squadron designations are used the way any naval wargame uses them, to name the pieces; force compositions are plausible arrangements built to make a particular tactical problem, not a claim about anybody's actual dispositions.

## What changed

### Geography is real

Scenarios are no longer stylised shapes in a coordinate box. Each one is anchored to a latitude and longitude and everything in it — ships, bases, coastlines, patrol legs — is placed by projecting real coordinates onto a local plane about that anchor (one minute of latitude is one mile; longitude is scaled by the cosine of the anchor latitude, which is accurate to well under a mile at scenario scale). The Iceland-Faroe gap is as wide as the Iceland-Faroe gap. Severomorsk is the distance from Andøya that it actually is. The Lofoten wall is where the Lofoten wall is.

Coastlines are deliberately coarse: a few dozen vertices where a survey has millions. Every vertex sits at a real position; no bathymetry, shoreline detail or elevation model is claimed, and each landmass is still one plateau at one height for masking purposes. The geography library is `tools/scenarios/geography.py` and the scenario set is generated from it by `tools/scenarios/build_scenarios.py`, so a coastline is fixed once and every scenario using it gets the fix.

Ten scenarios now cover the Iceland-Faroe ridge, the Faroe-Shetland channel, the Norwegian Sea, Vestfjorden, the Gotland basin, the North Cape and the Barents. Bases are the bases that are there: Keflavík, Lossiemouth, Andøya, Evenes, Ørland, Severomorsk-1, Olenya, Monchegorsk.

### Ships sail with their aircraft

A hangar with nothing in it was a scenario-authoring bug that had to be fixed one scenario at a time; six of the ten shipped with no embarked aviation at all. Platforms now declare a `default_air_wing`, and the loader embarks it on any ship the scenario does not explicitly give one to. Cruisers, destroyers, frigates, corvettes and the replenishment ship all sail with their detachments; the detachment takes its callsign from the ship, so *USS Truxtun (DDG 103)* puts up *Truxtun 60*.

Carrier air wings are authored per scenario as `air_wing` blocks with real squadron designations and radio callsigns rather than as dozens of individually listed airframes.

### The deck is a cycle, not a door

Previously a Ford-class carrier carried twelve aircraft and could have exactly one airframe moving at a time, the same as a frigate with one spot; anything that landed was instantly refuelled and ready. Now:

- `launch_spots` and `recovery_spots` are per-platform. A CATOBAR deck works four catapults in parallel and recovers down one angled deck; a STOVL deck does two and two; an escort does one and one. Launching and recovering contend for the same deck.
- `turnaround_s` stands between recovery and being a sortie again. An airframe that lands is struck below, fuelled, rearmed and respotted. Sortie rearming — previously listed here as unsimulated — now happens at the end of that cycle.
- Capacities are the physical figures for the class. What a scenario actually embarks is a scenario decision.
- `launch_flight` sends a section off together, for the AI and for the player (the FLIGHT button).

Spot counts, turnaround times and cycle behaviour are GAMEPLAY_ESTIMATE. They stand in for deck handling; real cyclic operations, air plans, deck spotting, pilot qualification and aircraft servicing are not modelled.

### Air-to-air refuelling

Aircraft declare `can_refuel`; tankers declare `tanker_offload_s`, counted in the receiver's own endurance-seconds. A receiver reaching bingo looks for a basket within reach before it looks for the deck, and takes it if the join costs less than the fuel it has. A tanker keeps a reserve to get itself home. One transfer rate stands in for joining, plugging and taking a load; tanker tracks, give schedules and boom-versus-basket are not modelled.

### Air and drone power

Thirteen new air platforms, drone-heavy, where before there was exactly one unarmed UAV:

| | |
|---|---|
| MQ-25A Stingray | Unmanned carrier tanker. What turns a strike radius into an operating radius. |
| MQ-8C Fire Scout | Unmanned helicopter off an escort's own deck. |
| Shipboard catapult UAS | Very small, entirely passive, a classification tool rather than a search one. |
| Skeldar V-200 | The same idea on a corvette, which is how a ship with no helicopter gets a look over the horizon. |
| F/A-18F | Two-seat airframe carrying the wing's long-range anti-ship round. |
| MH-60S | The armed half of a mixed detachment: no sonar, weapons for small craft and drones. |
| Merlin HM2 (Crowsnest) | A STOVL carrier has no fixed-wing AEW, so the radar goes up on a helicopter. |
| AW159 Wildcat | Light shipborne helicopter fitted for surface work. |
| NH90 NFH | The common European shipborne ASW helicopter. |
| Ka-31R | Shipborne AEW, the Russian equivalent problem and answer. |
| Il-38N | The maritime patrol aircraft more likely to be overhead than a Bear. |
| Orion (Inokhodets) | Slow, long-legged, armed, and cheap enough to send where a manned aircraft would not go. |
| Orlan-10 | A small drone flown to find out who is radiating. |

Ten new weapons, including the air wing's actual long-range anti-ship round (AGM-158C LRASM), the F-35's internal anti-ship option (JSM), helicopter and drone weapons (Hellfire, APKWS, Sea Venom, Martlet, Kh-38), and a generic long-range one-way attack drone modelled as a weapon rather than an aircraft: slow, easy to shoot down, launched in numbers.

### Aircraft can be based off the chart

A two-hundred-mile plot does not contain every airfield an aircraft over it flew from. A scenario aircraft with no deck on the chart now starts airborne and, at bingo, flies for the nearest map edge and leaves the board. Before this it sat stowed in a hangar that did not exist, for the whole scenario — which is what a Kola-based fighter over Vestfjorden did.

### Two defects found and fixed

- **Threat attribution ignored whether a round could reach.** `threatened_unit` charged any round whose heading geometry passed near a ship to that ship, regardless of distance. Once a lot of air-to-air fighting was happening, air-to-air rounds fired two hundred miles from the task group filled the threat board and consumed the defensive cycle while the ships never fired an interceptor. A round is now only a threat to what it can still physically reach.
- **The AI launched one airframe at a time, always armed, always reactively.** Early warning aircraft and surveillance drones sat in the hangar until something had already gone wrong, tankers never went up at all, and a deck with four catapults trickled aircraft off one per four minutes. Launch decisions are now separated by purpose: standing routes, then eyes, then give, then armed sections sized to the deck.

## Still simplified

Bathymetry and depth, sensor scheduling and illumination, seeker terrain geometry, ballistic trajectories, human classification and IFF, ordnance stocks (what a deck keeps flying is bounded by turnaround time, not a ship-side magazine count), network topology, deck spotting and pilot qualification, and save games. Friendly unit positions remain perfectly known to the player. Coastlines are coarse outlines at real positions, not survey data.


# M13: combat information center and fidelity review

This is an entertainment simulation using public platform families and explicitly estimated combat parameters. It does not reproduce Aegis software, classified performance, or operational doctrine.

## What changed

- A watch overview, selectable fleet roster, contact-domain filters, tabbed orders, and searchable recognition library (F7). Sensor overlays and the symbol key are available on demand; neither obscures the plot by default.
- 42 platforms, 41 weapon definitions, 51 sensors, and ten missions. Northern Vigil introduces 34 actors across a joint carrier group, opposing aircraft and submarines, and neutral fishing traffic.
- New actors: Ford, Queen Elizabeth, Aquitaine FREMM, prospective Type 26, Astute, F-35B/C, Rafale M, MQ-4C, Merlin HM2, Ka-27PL, and civilian fishing trawler.
- Original recognition models with differentiated fighter wing/tail geometry, Triton's long wingspan, Queen Elizabeth's twin islands and ski jump, and conventional/coaxial helicopter rotors. Corrected reversed nose taper in the original aircraft modeller and regenerated all aircraft art. Ship profiles remain stylised, and some new hulls share a parametric class-family shape.
- Independent observer track histories: a submerged submarine's local observations cannot silently refine the network picture, and network observations cannot refine its private solution. Switching the selected platform switches the contact picture. Reconnecting restores network access. The network remains one abstract faction link, without radio range, latency, relays, or real CEC protocols.
- Detected weapon reports respect observer connectivity for automatic defence, tactical display, and AI reaction. Manual SAM shots and queued salvo rounds reserve the same abstract channel budget as automatic interception. CIWS remains self-contained. Channels are game tuning values, not real director counts or radar scheduling.
- Neutral/friendly identified tracks are protected. Weapons Tight requires hostile identification for a manual shot. Weapons Free still permits a domain-known, unidentified contact.
- CATOBAR, STOVL, helicopter decks and airfields have distinct compatibility. The editor, scenario loader, launch and divert paths use that rule. Each host serialises launch/recovery operations. Cross-deck compatibility is categorical; deck dimensions, pilot qualification, airframe clearance and aircraft servicing are not simulated.
- SM-3 requires an exoatmospheric target altitude; it no longer engages the existing 40 km Kinzhal game profile. SM-6 has a terminal-altitude gate. The 100 km / 50 km gates are gameplay conventions, not claimed missile performance. Ballistic flight still uses fixed altitude and simplified horizontal motion; a synthetic high-altitude target tests the SM-3 path.
- Corrected Super Hornet radar-warning receiver association, separated AGM-84 air-launched Harpoon from the deck-launched RGM-84, added a representative carrier air-search radar, and fixed flight-level conversion (metres divided by 30.48).
- Added physical VLS capacities and ESSM quad-packing metadata. The database distinguishes allocated cells from total cells; unallocated cells are not extra rounds available in play. Type 26's CAMM launchers remain separate from its unallocated Mk 41 cells. This metadata checks catalogue fits; it is not a complete launcher compatibility or custom-loadout editor.

## Public sources and interpretation

Reviewed September 10, 2026. These establish identities, broad roles and configuration families. They do not establish the game's numerical effectiveness, signatures, detection envelopes, reaction times, loadout choices, or damage model.

| Source | Used for |
|---|---|
| [US Navy: Aegis Weapon System](https://www.navy.mil/Resources/Fact-Files/Display-FactFiles/Article/2166739/aegis-weapon-system/) | Integrated search, track, command and weapons-control concept; Flight IIA aviation and Aegis architecture. |
| [US Navy: DDG 51](https://www.navy.mil/Resources/Fact-Files/Display-FactFiles/Article/2169871/destroyers-ddg/destroyers-ddg-51/) | Flight distinctions and Flight III SPY-6(V)1 association. |
| [MDA: Sea-Based Weapon Systems](https://www.mda.mil/system/aegis_bmd.html) | SM-3 midcourse versus SM-6 terminal BMD roles. The game's altitude gates are estimates. |
| [NAVAIR: F/A-18 threat protection](https://www.navair.navy.mil/node/12551) | AN/ALR-67(V)3 on Super Hornet. |
| [NAVAIR: IDECM](https://www.navair.navy.mil/product/Integrated-Defensive-Electronic-Countermeasures-IDECM) | Distinguishes defensive countermeasures from radar-warning receivers. The game models receiver sensing and abstract decoys. |
| [Royal Navy: F-35](https://www.royalnavy.mod.uk/equipment/aircraft/f-35) | STOVL F-35B and Queen Elizabeth carrier compatibility. |
| [US Pacific Fleet: F-35C](https://www.cpf.navy.mil/newsroom/news/article/2664405/f-35c-achieves-initial-operational-capability/) | Carrier-based F-35C role. |
| [Dassault: Rafale weapons](https://www.dassault-aviation.com/en/defense/rafale/adapt-and-deliver/) | MICA and AM39 Exocet fit. |
| [French Ministry of Defence: Rafale Marine](https://www.defense.gouv.fr/en/node/1958) | Naval Rafale and RBE2 association. |
| [US Navy: MQ-4C](https://www.navy.mil/Resources/Fact-Files/Display-FactFiles/article/2160569/mq-4c-triton/) | Persistent maritime surveillance, complementary to P-8. |
| [Northrop Grumman: airborne ISR](https://www.northropgrumman.com/what-we-do/mission-solutions/airborne-isr) | Triton AN/ZPY-3 MFAS association. Its electronic support is a generic abstraction here. |
| [Royal Navy: Merlin](https://www.royalnavy.mod.uk/equipment/aircraft/merlin) and [Sting Ray](https://www.royalnavy.mod.uk/news/2024/september/13/20240913-work-begins-on-60m-next-generation-sting-ray-torpedo-to-protect-the-fleet) | ASW helicopter role and lightweight torpedo family. |
| [Naval Group: FREMM](https://www.naval-group.com/sites/default/files/2020-10/2019-06-19_pr_visite-ministre-des-armees_25_juin_vangl-vdef.pdf) | Aquitaine-family platform and Herakles association. |
| [Royal Navy: frigate construction](https://www.royalnavy.mod.uk/news/2026/february/25/20260225-future-frigate-force-forges-ahead-with-two-milestones-in-one-day) | Type 26 remains a future configuration in this catalogue; no claim of current operational availability. |

Other original platform references remain in DATA_SOURCES.md. Some broad class associations and dimensions are inherited catalogue estimates, not newly verified specifications. Historical Ticonderoga and prospective Constellation/Type 26 entries are available for fictional missions; catalogue availability does not imply current fleet availability.

## Validation and remaining limits

185 regression tests passed, including new checks for private/shared track isolation, weapons identity rules, channel reservations, deck compatibility, and catalogue consistency. All ten scenarios ran under two seeds for 6,000 simulated seconds each without script errors, unresolved aircraft homes, or grounded hulls. This is a stability check, not a calibrated balance study. Native command and library screens were rendered and inspected. Browser verification was attempted but its isolated browser launch was blocked by the automatic approval service's account usage limit; the Web export completed.

Still simplified: real geography and bathymetry, sensor scheduling/illumination, seeker terrain geometry, ballistic trajectories, human classification/IFF, fuel logistics, air refuelling, sortie rearming, network topology, and save games. Friendly unit positions remain perfectly known to the player. Some combat feedback still provides more information than a real command system would. Shutdown reference-cycle warnings existed before this milestone and remain; no recurring simulation script failures were observed in the successful checks.


## M14 presentation boundary

All 42 platforms and 41 weapons have original illustrative 3D recognition models. Geometry and painted markings communicate class, scale and role; they do not claim an exact production configuration. Runtime inspection is limited to the public catalogue and player-owned selections. It does not identify an unknown scenario track. Colour plans retain the map's length-scaling contract, and weapon trails start only when the current console observes a round. No weapon performance or guidance parameters were changed for the visual update.
