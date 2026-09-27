# 2027 theatres: source ledger and model limits

Research checked 27 September 2026 against public references. This ledger records where each class,
weapon and sensor identity in the Pacific, Gulf and Mediterranean catalogue comes from, and what the
game deliberately does not claim. Every performance number in `data/platforms/theatres`,
`data/weapons/pla_*`, `jmsdf_*`, `jasdf_*`, `jgsdf_*`, `irn_*`, `rfn_48n6_sam` and the matching sensors is a
`GAMEPLAY_ESTIMATE` on the catalogue's existing scale (Harpoon 70 nm at 480 kn, SM-2 45 nm, SPY-1D(V)
200 nm against air, a Virginia at acoustic signature 0.08, a Kilo at 0.05). Nothing here is a
capability assessment, and the six operations are fictional situations on real charts.

## Rules that kept the catalogue honest

- Only systems the public record associates with a class are fitted, and only in roles the game
  represents. A cell count is physical; the missiles loaded into it are a scenario allocation.
- Where a variant matters to play it is a separate record (Type 039A rather than "Chinese
  submarine"; the Izumo after its F-35B conversion rather than as commissioned). Where it does not,
  a class stands for its variants and the service note says so (Type 052D includes the lengthened
  052DL hull; Mogami's later hulls have a vertical launcher that is left empty).
- Anything not fitted by 2027 in open reporting is left out or named as omitted: the extended-range
  Type 12, the 40N6 round for the S-400, Constellation-class frigates, an F-35B Izumo air group
  larger than a detachment.
- Ordering claims are made only where public assessments agree on the ordering, never on the
  numbers: the Type 093B is placed between the first 093 boats and current Western designs on the
  acoustic scale, and nowhere more precise than that.

## People's Liberation Army Navy

| Record | Public identity used | Notes on the fit |
|---|---|---|
| `pla_ddg_type055` | Type 055 (NATO Renhai), about 180 m, 12,000–13,000 t, 112 universal cells, Type 346B arrays, two helicopters | Cells shared by HHQ-9B, YJ-18, YJ-21, CJ-10 and Yu-8; the allocation loaded is 88 of 112. HHQ-10 and an eleven-barrel close-in mount. Rated a destroyer by the PLAN and a cruiser by most Western navies. |
| `pla_ddg_type052d` | Type 052D (Luyang III), about 157 m, 7,500 t, 64 cells, Type 346A | One Z-9C. The 052DL hull is not distinguished. |
| `pla_ffg_type054a` | Type 054A (Jiangkai II), 134 m, about 4,000 t, 32 cells, eight YJ-83, four MR-90 illuminators | HHQ-16 and Yu-8 share the cells. The Type 366 (Mineral-ME derivative) gives over-the-horizon targeting only while it radiates. |
| `pla_fsg_type056a` | Type 056A (Jiangdao), about 90 m, 1,500 t, four YJ-83, HHQ-10, 76 mm, towed array | Landing pad, no hangar. |
| `pla_pgg_type022` | Type 022 (Houbei) wave-piercing catamaran, about 43 m, 220 t, eight YJ-83 | Depends on an external picture; fast and expendable. |
| `pla_cv_shandong` | Type 002, about 305 m, 66,000 t, ski-jump STOBAR deck, J-15 air group | Represented by the game's new STOBAR facility: two launch positions, one recovery. The embarked detachment is a scenario allocation, not the full air group. |
| `pla_ssn_type093b` | Type 093B (Shang II), about 110 m, 7,000 t, YJ-18 from torpedo tubes, Yu-6 | Acoustic value placed by public ordering only. |
| `pla_ssk_type039a` | Type 039A/B (Yuan), about 78 m, 3,600 t, Stirling AIP, Yu-6, YJ-82 | Quiet on AIP; noisy on a sprint, like any boat. |
| `pla_bomber_h6j` | H-6J, YJ-12 carrier with six wing stations | Four YJ-12 loaded so a regiment's raid stays inside the game's defensive scale. |
| `pla_fighter_j15` | J-15, ski-jump carrier fighter, PL-15, PL-10, YJ-83K, buddy refuelling | Endurance is the ski-jump penalty. `launch_requirement = stobar`. |
| `pla_fighter_j16` | J-16 multirole fighter, active-array radar | Land-based counter-air and anti-ship. |
| `pla_aew_kj500` | KJ-500, fixed three-array rotodome | Raid direction; classification bonus. |
| `pla_mpa_y8q` | Y-8Q (KQ-200) maritime patrol, MAD boom | Sonobuoys stand in for its acoustics and MAD. |
| `pla_helo_z9c`, `pla_helo_z20f`, `pla_helo_z18f`, `pla_aew_z18j` | Z-9C, Z-20F, Z-18F ASW and Z-18J early-warning helicopters | Detachment sizes are scenario choices. |
| `pla_aor_type903a` | Type 903A (Fuchi II) replenishment ship | Unarmed in the representation. |
| `pla_battery_yj12b` | YJ-12B coastal anti-ship battery | A transporter-erector-launcher battery with a surveillance radar on high ground. |
| `pla_sam_hq9b_site` | HQ-9B long-range SAM site with HT-233 engagement radar | Defends everything within reach as a ship's air defence does. |
| `pla_asbm_df21d` | DF-21D anti-ship ballistic missile battery | No sensors; fires on a classified track over the network. Interceptable by SM-3, SM-6 and 48N6 (`ballistic` target type). |

Weapons: YJ-18 (subsonic cruise, supersonic terminal, represented by a single blended speed and a raised defensive difficulty), YJ-83 and YJ-83K, YJ-12 and YJ-12B (high supersonic profile), YJ-21 and DF-21D (ballistic profile, `ballistic` threat class), CJ-10 (land attack only; `land` target type), HHQ-9B/HQ-9B, HHQ-16, HHQ-10, H/PJ-11, H/PJ-12 (Type 730) and H/PJ-13 mounts, H/PJ-45A 130 mm and H/PJ-26 76 mm guns, Yu-6, Yu-7 and Yu-8, YJ-82, PL-15 and PL-10. Sensors: Type 346A/B, Type 518, Type 382, Type 366, Type 364, Type 362, H/SJD-9 bow sonar, H/SJG-311 and H/SJG-206 towed arrays, the Type 093B and Type 039A suites, a helicopter dipping sonar, the H-6J, J-15, J-16, KJ-500, Y-8Q, Z-9C, Z-20F and Z-18J radars, a coastal surveillance radar and the HT-233.

## Japan Maritime, Air and Ground Self-Defense Forces

| Record | Public identity used | Notes on the fit |
|---|---|---|
| `jmsdf_ddg_maya` | Maya class (27DDG), 170 m, 10,250 t, Aegis Baseline J7 with cooperative engagement, 96 cells, SM-3 Block IIA, SM-6, ESSM, Type 17 SSM, Type 07 VLA, Mk 45 Mod 4, Phalanx, SH-60K | Shares the game's SPY-1D(V) record. |
| `jmsdf_dd_akizuki` | Akizuki class (19DD), 151 m, 6,800 t, FCS-3A, 32 cells (ESSM quad-packed, Type 07), Type 90 SSM | Built to cover the Aegis ships during ballistic missile defence; that is its scenario role. |
| `jmsdf_ffm_mogami` | Mogami class FFM, 133 m, 5,500 t full, OPY-2, unified mast, SeaRAM, Type 17 SSM, Mk 45, OQQ-25 | The vertical launcher fitted to later hulls is left empty. |
| `jmsdf_ddh_izumo` | Izumo class after the F-35B deck modification, 248 m, 27,000 t, OPS-50, SeaRAM and Phalanx | STOVL facility; the F-35Bs are an Air Self-Defense Force detachment. |
| `jmsdf_ssk_taigei` | Taigei class, 84 m, lithium-ion batteries, Type 18 torpedo, sub-launched Harpoon | Very quiet at patrol speed; the Harpoon uses the surface round's numbers. |
| `jmsdf_mpa_p1` | Kawasaki P-1, HPS-106 active-array radar, Type 97 torpedo, Harpoon | Sonobuoys stand in for its acoustics. |
| `jmsdf_helo_sh60k` | SH-60K, HPS-104 radar, HQS-104 dipping sonar, Type 97 | |
| `jasdf_fighter_f35b` | F-35B of the Air Self-Defense Force | Same airframe as the Royal Navy record; JSM on order for Japan's F-35s. |
| `jasdf_fighter_f2` | Mitsubishi F-2, J/APG-2, ASM-3, AAM-4B, AAM-5 | The baseline ASM-3, not the extended-range ASM-3A. |
| `jgsdf_type12_battery` | Type 12 surface-to-ship missile battery | Baseline range; the extended-range version being fielded is not represented. |

## Islamic Republic of Iran Navy and IRGC Navy

| Record | Public identity used | Notes on the fit |
|---|---|---|
| `irn_ffg_moudge` | Moudge class (Sahand standard), about 95 m, 1,500 t, Qader, Mehrab, 76 mm, Kamand | Named hulls in the scenario are class-consistent; the landing deck is empty. |
| `irn_ffg_alvand` | Alvand class (Vosper Mk 5), 94.5 m, 1,540 t, Noor, 4.5-inch Mk 8, 35 mm | No missile air defence since the Seacat was landed. |
| `irn_ssk_kilo_877ekm` | Project 877EKM export Kilo, 72.6 m, TEST-71ME and 53-65KE torpedoes | The 1990s deliveries; no cruise missiles. |
| `irn_ssm_ghadir` | Ghadir midget submarine, about 29 m, 120 t, two 533 mm tubes | Shallow, short-ranged, numerous. |
| `irn_fac_peykaap3` | Peykaap III (IPS-16 Mod) fast attack craft, two Nasr-1 | Fifty knots; a dozen are a defensive problem. |
| `irn_pgg_houdong` | Houdong (Thondor) missile boat, four Noor, Square Tie radar | |
| `irn_uav_mohajer6` | Mohajer-6, electro-optical turret | Spotter for batteries and boats. |
| `irn_battery_qader` | Qader and Noor coastal battery | |
| `irn_asbm_khalij_fars` | Khalij Fars anti-ship ballistic missile battery | Fires on the drone and coastal-radar picture. |
| `irn_drone_site_shahed` | One-way attack drone launch site | Uses the catalogue's existing generic one-way attack drone record. |
| `irn_sam_bavar373` | Bavar-373 with Sayyad-4 and the Meraj-4 radar | |

## Russian coastal additions

`rfn_battery_bastion` (K-300P Bastion-P with P-800 Oniks, the same round the Gorshkov record carries, and the Monolit-B radar) and `rfn_sam_s400_site` (S-400 with 48N6 and the 91N6 acquisition radar; the 40N6 round is omitted). Both are used in the Mediterranean operation and available to the editor.

## Civilian

`civ_tanker_vlcc`: a generic very large crude carrier, 333 m, laden displacement about 330,000 t, invented names. Hard to sink, easy to set alight, impossible to hide.

## Simulation rules added for these theatres

- **Installations ashore fight.** A land unit with weapons engages from the faction picture without moving; a battery's round climbs out over its own coast before the low-flyer terrain rule applies; a round aimed at a target ashore crosses the beach instead of dying on it. Installations stand on their ground: radar horizon, ESM horizon and terrain masking all use plateau height plus mast, so a battery a mile behind a headland sees the sea it faces and is hidden from the other side.
- **Land attack.** Tomahawk Block V, NSM, JSM and CJ-10 (and the existing JASSM-ER) carry the `land` target type. Harpoon, LRASM, Kalibr (the anti-ship record) and YJ-18 do not. A shore station or battery can therefore be struck, and the AI will strike an airfield it has classified if it has a land-attack round.
- **STOBAR decks.** A ski-jump carrier launches two at a time and recovers one; it flies its own ski-jump aircraft and jump jets; a catapult deck can also recover a ski-jump aircraft; a STOVL deck cannot.
- **Regional charts.** Four Natural Earth regions (North Atlantic, Western Pacific, Arabian Sea and Red Sea, Mediterranean), each with its own bathymetry raster, chosen by the scenario anchor. The reclaimed Spratly outposts are added to the Natural Earth coastline as approximate footprints because the 1:10m dataset predates them.

## What remains simplified

Datalink latency and topology, continuous illumination, mechanical launcher conflicts and some weapon trajectories are simplified as before. The YJ-18's two-stage flight is one blended speed. Ballistic anti-ship missiles fly the game's `ballistic` profile with a single seeker abstraction and no mid-course update from a satellite picture. Drone swarms are the existing one-way attack drone record fired in salvos of six. The Type 12 battery, the S-400 site and the HQ-9B site are single installations, not brigades. The AIP and lithium-ion boats are quiet at patrol speed by a single acoustic number, not by an endurance model. Mine warfare, electronic attack from the shore, coast guard and maritime militia traffic, and logistics remain outside the game.

## Scenario identities

Ship names are real, publicly listed hulls of the classes shown, placed in fictional situations: USS Ronald Reagan, Robert Smalls, Rafael Peralta, Higgins, Vermont, Dewey and Paul Ignatius; JS Maya, Akizuki, Kumano, Izumo and Taigei; Nanchang, Xi'an, Xuzhou, Hengshui and Qiandaohu; Varyag, Marshal Shaposhnikov, Gremyashchiy, Petropavlovsk-Kamchatsky, Admiral Grigorovich, Vyshny Volochyok and Krasnodar; HMS Duncan; FS Languedoc, Provence, Suffren, Mistral and Charles de Gaulle; ITS Andrea Doria; Dena, Alborz and Tareq. Type 093B, Type 039A, Type 056A, Type 022, Peykaap, Thondor and Ghadir contacts carry class labels because individual hulls were not established. Squadron identities (VFA-27, VFA-102, VFA-147, VAQ-141, VAW-125, HSM-77, HSC-12, VP-47, VP-45, VP-8, 14th FS, 301 Sqn, 3rd Sqn, 903 EAW, 120 Sqn, Flottilles 11F, 4F, 33F and 36F, Fleet Air Wings 2 and 21) are real units used as callsign families; PLAN, Russian and Iranian regiments are given generic names. Civilian names are invented. Airfields are real: Clark, Kadena, Huian, Zhangzhou, Fiery Cross Reef, Puerto Princesa, Hachinohe, Misawa, Kamenny Ruchey, Al Dhafra, Bandar Abbas, RAF Akrotiri and Khmeimim. The 1990 Sea of Japan sortie uses the period catalogue and its own ledger's rules; Carl Vinson's 1990 fighters were F-14A rather than the F-14A+ the catalogue's Tomcat record names, and USS Fife is represented by the class's VLS-refit record without a claim about the date of her own refit.
