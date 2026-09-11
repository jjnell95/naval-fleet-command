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
