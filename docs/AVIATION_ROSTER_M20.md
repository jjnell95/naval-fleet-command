# M20 aviation and fleet catalogue

Source review: 23 September 2026. This expansion adds 18 selectable platforms, 12 weapon families and 16 sensor resources. The catalogue grows to 74 platforms, 70 weapons and 81 sensors. Every addition is available through the same data scan used by the scenario editor and equipment gallery; none requires a special-case registration list.

## What the extra platforms change

The new decks deliberately support different aircraft. Charles de Gaulle can launch a Rafale or a Hawkeye. Juan Carlos I can launch a Harrier but cannot launch a Hawkeye. Mistral can support a mixed helicopter detachment but cannot operate those jets. All of the new aircraft can operate from the game's friendly shore-air-station abstraction. Deck compatibility is a first screening of a fictional sortie, not a certification claim about every aircraft/ship pairing.

| Platform ID | Model and playable role | Facility or basing |
|---|---|---|
| `fra_cvn_charles_de_gaulle` | French carrier with Rafale M, E-2C, NH90 and Panther choices | CATOBAR; 2 concurrent launches / 1 recovery |
| `usn_lha_america` | Aviation-oriented amphibious ship with F-35B and helicopters | STOVL; 2 launches / 2 recoveries |
| `esp_lhd_juan_carlos_i` | Harrier and helicopter aviation ship; depends on escorts for missile defence | STOVL; 2 launches / 2 recoveries |
| `fra_lhd_mistral` | Helicopter base with separate surveillance and ASW aircraft | Helicopter; 3 launches / 2 recoveries |
| `ita_ddg_horizon` | Area-air-defence destroyer with Aster, Otomat and MU90 | One NH90 |
| `deu_ffg_sachsen` | APAR/SMART-L escort with SM-2, ESSM and RAM | Helicopter deck; reduced NH90 scenario detachment |
| `swe_fsg_visby` | Small, fast littoral ASW corvette with a 57 mm gun and Torpedo 47 | No resident air wing |
| `rfn_ffg_admiral_grigorovich` | Project 11356-family escort with Kalibr, Shtil-1 and Ka-27 | One helicopter |
| `fra_ssn_suffren` | Nuclear submarine with F21 heavyweight torpedoes | Undersea |
| `swe_ssk_gotland` | Compact AIP submarine with heavy and lightweight torpedoes | Undersea |
| `usmc_fighter_av8b` | Legacy AV-8B+ airframe with AMRAAM and Maverick | STOVL / CATOBAR game abstraction / runway |
| `raf_fighter_typhoon` | Air-superiority fighter with Meteor and ASRAAM | Runway |
| `swe_fighter_gripen_c` | Mixed air-defence / maritime-strike fit with Meteor, IRIS-T and RBS15F | Runway |
| `usaf_fighter_f16c` | F-16C with a representative APG-83 upgrade and defensive fighter load | Runway |
| `fra_mpa_atlantic2` | Long-endurance maritime patrol with Exocet, MU90 and 48 game sonobuoys | Runway |
| `rfn_strike_su34` | Strike aircraft with a fictional Kh-31A maritime load | Runway |
| `fra_helo_panther` | Light surface-search helicopter with ORB-32 radar | Helicopter-capable deck / runway |
| `fra_aew_e2c` | French E-2C with APS-145 early-warning radar | CATOBAR / runway |

Deck concurrency, turnaround times, capacities used for gameplay, weapon quantities and mixed detachments are tuning values. The `rn_` prefix of the existing F-35B resource does not make America's fictional air detachment British. The shared AV-8B+, NH90 and MH-60 resources similarly avoid duplicating airframes for every operator. The service notes make this explicit. A default wing never exceeds its host's capacity, and every airframe in it passes the host's compatibility check.

## New weapon choices

Every row below is installed on at least one playable platform. Combat performance is deliberately expressed only by the estimated data in its `.tres` resource; the catalogue does not convert promotional claims into verified hit probabilities.

| Weapon ID | Family / game role | Example carrier |
|---|---|---|
| `meteor_aam` | Long-range radar air-to-air missile | Typhoon, Gripen C |
| `asraam_aam` | Short-range infrared air-to-air missile | Typhoon |
| `iris_t_aam` | Short-range infrared air-to-air missile | Gripen C |
| `agm65e_maverick` | Short-range surface attack | AV-8B+ |
| `rbs15f` | Air-launched anti-ship missile | Gripen C |
| `kh31a` | Legacy high-speed anti-ship family | Fictional Su-34 mission fit |
| `otomat_mk2` | Ship-launched anti-ship missile | Andrea Doria |
| `mistral_naval` | Short-range naval self-defence missile | Charles de Gaulle, Mistral |
| `shtil1` | Medium-range naval air defence | Admiral Grigorovich |
| `f21_torpedo` | Heavyweight surface / subsurface weapon | Suffren |
| `torpedo62` | Heavyweight surface / subsurface weapon | Gotland |
| `torpedo47` | Lightweight littoral ASW weapon | Visby, Gotland |

Kalibr's existing resource now declares one round per VLS cell, so the new Grigorovich fit accounts for its eight strike rounds as well as 24 Shtil rounds. The new Sachsen fit uses 24 SM-2 cells plus eight cells holding 32 ESSM rounds. Horizon's 48-cell fit stays within its catalogue capacity. Separate launcher types are still simplified into a total-cell constraint.

## Source ledger

These are primary navy, government or manufacturer sources reviewed for identity, broad role and public system associations. Dates describe the source where relevant; this is not a current fleet readiness report. Marketing claims about effectiveness are not accepted as measured performance.

| Source | Public fact used | Limits applied in game |
|---|---|---|
| [French Navy: Charles de Gaulle](https://www.defense.gouv.fr/marine/forces-surface/porte-avions), [French Navy's carrier systems illustration](https://archives.defense.gouv.fr/content/download/599331/10109914/La%20Charles%20de%20Gaulle%20-%20Un%20concentr%C3%A9%20de%20puissance.pdf) | Carrier identity, aviation role, Aster/Sadral family association | Search/fire-control radars combined into an explicitly abstract suite |
| [French Navy: E-2C Hawkeye](https://www.defense.gouv.fr/marine/force-laeronautique-navale/e2c-hawkeye) | French carrier early warning; APS-145 radar | E-2C is retained; no assumed French E-2D delivery or current deployment |
| [US Navy: amphibious assault ships](https://www.navy.mil/Resources/Fact-Files/Display-FactFiles/Article/2169814/amphibious-assault-ships-lhdlhar/) | America-family aviation/STOVL role and Flight 0 distinction | No amphibious landing, troop lift or well-deck simulation |
| [Spanish Navy: Juan Carlos I](https://armada.defensa.gob.es/ArmadaPortal/page/Portal/ArmadaEspannola/buquessuperficie/prefLang-en/02lhd-juan-carlos-i) | Harrier/helicopter operations and LANZA-N; planned space for future missile defence | Unfitted future CIWS is not granted to the ship |
| [French Ministry of Armed Forces: Jeanne d'Arc 2025 press kit](https://www.defense.gouv.fr/sites/default/files/operations/2025_MPAR_PAO_DOSSIER_DE_PRESSE_JDA25_v7.pdf) | Mistral dimensions and helicopter aviation role | Fictional naval ASW detachment; not a claim of its actual army-helicopter wing |
| [Italian Navy: Andrea Doria](https://www.marina.difesa.it/EN/thefleet/home/Pagine/AndreaDoria.aspx), [MBDA: Teseo family and Horizon association, 2021](https://www.mbda-systems.com/mbda-supply-new-teseo-mk2e-anti-ship-system-italian-navy) | Horizon class, Aster/PAAMS, 48 cells, MU90, helicopter and legacy Teseo association | Uses established Mk2 family; does not silently grant future Mk2/E |
| [Bundeswehr: Sachsen class](https://www.bundeswehr.de/de/ausruestung-technik-bundeswehr/seesysteme-bundeswehr/sachsen-klasse-f124-fregatte) | F124 air-defence escort and weapon families | NH90 detachment is fictional; not a claim of a specific ship's current helicopter |
| [Saab: Visby](https://www.saab.com/products/visby-class-corvette) | Class, broad size/speed and littoral role | Reduced ASW fit; RBS15 and future SAM upgrades omitted |
| [Rosoboronexport: Project 11356 family](https://roe.ru/pdfs/pdf_6211.pdf) | Family's Kalibr/Club, Shtil-1 and A-190 roles | Export-family source does not establish every Russian domestic modification |
| [French Ministry: Suffren fact sheet](https://www.defense.gouv.fr/sites/default/files/ministere-armees/SNA%20de%20type%20Suffren%20Barracuda%20-%20Suffren%20class%20nuclear%20attack%20submarine.pdf), [French Ministry: F21 trial](https://www.defense.gouv.fr/actualites/succes-dun-tir-torpille-lourde-f21-cible-realiste) | Submarine family and F21 armament | Missile, mine and special-forces capabilities omitted |
| [Saab: Gotland MLU, 2018](https://www.saab.com/newsroom/press-releases/2018/sea-trials-commence-of-upgraded-gotland-submarine) | MLU dimensions, AIP propulsion, torpedo role; displacement is surfaced | No claimed acoustic signature, operating depth or AIP endurance model |
| [NAVAIR: AV-8B](https://www.navair.navy.mil/product/AV-8B-Harrier), [USMC: AV-8B Maverick firing, 2017](https://www.marines.mil/News/Marines-TV/videoid/544749/dvpTag/Harrier/), [USMC amphibious capability reference](https://www.hqmc.marines.mil/Portals/61/Docs/Amphibious_Capability.pdf?pid=corpsHighlights_amphib) | STOVL role, Plus variant APG-65 and Maverick/AMRAAM associations | Legacy family; no assertion that every present operator has the same fit |
| [RAF: Typhoon FGR4](https://www.raf.mod.uk/aircraft/current-aircraft/typhoon-fgr41/) | Fighter role, ECR-90, Meteor and ASRAAM | Defensive fighter mission load; other stores omitted |
| [Saab: Gripen C stores illustration](https://www.saab.com/globalassets/products/aeronautics/gripen-c-series/gripen_c_packing-iron), [Saab: PS-05/A](https://www.saab.com/products/ps-05a-fighter-radar) | Gripen C radar and broad Meteor/IRIS-T/RBS15 associations | Manufacturer stores illustration is not operator-specific certification; quantities are fictional |
| [USAF: F-16](https://www.af.mil/About-Us/Fact-Sheets/Display/Article/104505/f-16-fighting-falcon/), [USAF: APG-83 upgrade, 2023](https://www.acc.af.mil/News/Article-Display/Article/3413729/20th-fw-performs-mission-critical-f-16-modernization/) | F-16C identity, fighter armament family, existence of an APG-83 fit | Does not apply the radar upgrade to every real F-16C |
| [French Navy: Atlantique 2](https://www.defense.gouv.fr/marine/force-laeronautique-navale/atlantique-2-atl-2), [Dassault: ATL2 upgrade](https://www.dassault-aviation.com/en/group/news/delivery-of-a-third-upgraded-atl2/) | Maritime patrol/ASW, Searchmaster and mixed torpedo/anti-ship role | Sonobuoy inventory, endurance and sensor envelopes are game estimates |
| [UAC: Su-34](https://uacrussia.ru/en/aircraft/lineup/lineup/su-34/), [Rosoboronexport 2005 catalogue, pages 13 and 123, archived](https://web.archive.org/web/20071030213111if_/http://www.rusarm.ru/cataloque/air_craft/aircraft.pdf) | Su-34 surface-attack role; historical Su-32-family Kh-31A association and missile identity | Historical export association is not evidence of a present domestic Su-34 loadout; that mission fit is explicitly fictional |
| [French Navy: Panther](https://www.defense.gouv.fr/marine/force-laeronautique-navale/panther) | AS565 surface surveillance and ORB-32 | No invented torpedo or dipping sonar; door gun below game scale |
| [MBDA: Otomat Mk2](https://www.mbda-systems.com/products/deep-strike/teseootomat-family/otomat-mk2-block-iv), [MBDA: naval Mistral](https://www.mbda-systems.com/products/force-protection/mistral-family/mistral-simbad-rc) | Weapon-family identities and broad ship roles | Family abstraction does not reproduce launcher control, seeker logic or targeting procedures |
| [Saab: Torpedo 62 delivery, 2001](https://www.saab.com/newsroom/press-releases/2001/torpedo-delivery-in-motala), [Saab: Torpedo 47 delivery, 2022](https://www.saab.com/sv/newsroom/press-releases/2022/saab-levererar-ny-latt-torped-till-fmv) | Heavyweight submarine weapon and lightweight submarine/Visby weapon associations | Simplified autonomous acoustic weapons; wire guidance and depth control are not reproduced |

Eight new sensor resources retain sourced public designations: APG-65, Captor-M/ECR-90, PS-05/A, APG-83, Searchmaster, ORB-32, APS-145 and LANZA-N. Eight others explicitly describe abstract composite suites. This avoids representing another navy's sonar as the exact system on a new hull. Existing generic ESM resources are reused as gameplay abstractions.

## Fidelity boundaries

This is a command-level fictional simulator. All numeric weapon, radar, sonar, endurance, signature, probability, damage, maintenance and deck-processing fields are `GAMEPLAY_ESTIMATE`. Public names and associations make the decisions recognizable; they do not validate the combat outcome. AAM types remain distinct from ship-launched interceptors, but missile energy, seeker physics and real engagement doctrine are not modeled.

Aircraft-type choice depends on airframes actually available at a host. The catalogue does not manufacture a replacement aircraft or create a new wing when a player selects a type. Recovery is constrained by facility compatibility and capacity. Sustained hovering, aerial-refuelling connector compatibility, aircraft damage inspection, finite base stockpiles, crew qualification, runway length, weather minima and deck geometry are outside this resource expansion. The AV-8B is STOVL-capable but does not inherit helicopter hovering/dipping behavior. Panther has a surveillance role, so it is useful without an invented weapon loadout.

## Validation

`tests/test_roster_m20.gd` contains six catalogue integration tests covering all new resource references and discovery; weapons fitted to playable platforms; mixed-wing capacity and compatibility; CATOBAR/STOVL/runway distinctions; VLS limits; and real scenario-loader spawning of each new carrier's mixed wing with recoverable home links. The focused suite passed all six tests. The full M20 validation record covers the combined simulation, UI and graphics changes separately.
