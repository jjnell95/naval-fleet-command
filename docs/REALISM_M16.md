# M16 — Geographic charts and mission fidelity

The standard missions remain fictional 2027 encounters. Their platform configurations are representative baseline fits, not claims of current deployments, readiness, inventories or future availability. This review supersedes conflicting equipment and geography statements in earlier milestone notes.

## What changed

- All ten charts use Natural Earth 5.1.1 land geometry. Separate islands, fjords and straits replace hand-drawn polygons. The same rings drive drawing and land collision. Stable, cached world-space triangulation replaces screen-space polygon simplification, which caused disappearing land at some zoom levels.
- Latitude/longitude graticules, named geographic features, geographic cursor coordinates, a north arrow, rendezvous/exit areas and a theatre-view button replace the oversized scope compass. Range rings are optional. The coast casing is a screen-space outline, not an invented depth contour.
- Mission success now follows the briefing: escort to a rendezvous, deny an exit for a limited watch, neutralize named combatants, or preserve carriers through an air-defence watch. The passage-denial missions accept either holding the watch or neutralizing the breakout group. Loss conditions take precedence. Missing named targets cannot count as destroyed.
- The alleged Kola base in Norway moves to Olenya. Norwegian P-8s operate from Evenes; US Tritons are explicitly attached US aircraft. VFA-34 uses F/A-18E rather than F-35C. Unsupported Russian squadron assignments become fictional detachment labels. Standard missions no longer assume MQ-25 detachments, Constellation or Type 26 service; prospective platforms remain available in the editor.
- Flight IIA Burkes lose deck Harpoons and embark MH-60Rs. The sandbox uses DDG 81 rather than calling DDG 51 a Flight IIA. Type 45 uses Aster 15/30 and the 114 mm Mk 8 gun, with its legacy Harpoon fit explicitly identified. Nansen uses Sting Ray; automatic Norwegian NH90 detachments are removed.
- Project 877 is separate from Improved Kilo 636.3. Udaloy uses short-range naval Kinzhal and Rastrub-B rather than Redut/Uran. Slava gets AK-130 and a twin-barrel model; Gorshkov gets A-192M; post-lead-ship Project 20380 gets A-190 and a Ka-27. Constellation's prospective gun is Mk 110. Seven added weapon families and the additional submarine variant have generated gallery assets.
- Ship turning is constrained by hull length and forward speed. This is a game approximation, not measured maneuvering data.

## Geographic build and limits

`tools/scenarios/coastlines.json` contains the regional Natural Earth extraction, its original download SHA-256, version and license. `import_coastlines.py` reproduces the extraction from the official ZIP. `geography.py` projects, clips outside the authored theatre, and simplifies at 0.2 nm with topology preservation. `build_scenarios.py` rebuilds every scenario offline from those inputs.

Build dependencies: Python, `shapely==2.1.2`; importing the upstream shapefile additionally needs `pyshp==3.1.6`. Runtime and ordinary Godot exports have no network or Python dependency.

**1:10m means 1:10 million map scale, not 10-metre resolution.** Natural Earth is generalized cartography. Small skerries and harbor details may be absent. Inland lake holes are filled for this maritime chart. The local equirectangular projection uses 60 nm per latitude degree and a longitude scale fixed at the anchor; scale distortion grows away from it. The earlier claim of sub-mile accuracy across a several-hundred-mile chart was incorrect. No bathymetry, tidal model, under-keel clearance or measured terrain elevation was added. Terrain masking still uses uniform estimated plateaus and a coarse raster.

## Public source ledger

Sources establish geographic provenance, identity, broad fit and role. Weapon range, hit probability, damage, acoustics, fire-control channels, deck cycles and magazine allocations remain GAMEPLAY_ESTIMATE. Historical sources establish baseline configurations; they do not establish 2027 readiness.

| Correction | Public evidence |
|---|---|
| Geographic land and islands | [Natural Earth land 1:10m](https://www.naturalearthdata.com/downloads/10m-physical-vectors/10m-land/) and [public-domain terms](https://www.naturalearthdata.com/about/terms-of-use/) |
| Burke Flight I/II Harpoon association | [NAVSEA Harpoon test announcement](https://www.navsea.navy.mil/Media/News/Article/855024/navy-conducts-first-lcs-harpoon-missile-test-at-rimpac/) distinguishes the Flight I/II deck-Harpoon population |
| Type 45 Aster baseline | [UK MoD Sea Viper description](https://www.gov.uk/government/news/royal-navy-fires-sea-viper-from-type-45-destroyer) |
| Type 45 Mk 8 gun | [Royal Navy equipment visit](https://www.royalnavy.mod.uk/news/2018/august/07/180807-university-students-meet-the-navy-big-guns-at-hms-collingwood) identifies the 4.5-inch Mk 8 fitted to Type 45 |
| Type 45 modernization is a distinct configuration | [Royal Navy Sea Ceptor program](https://www.royalnavy.mod.uk/news/2021/july/06/20210706-sea-ceptor) |
| Norway's NH90 withdrawal | [Norwegian government termination notice, June 2022](https://www.regjeringen.no/en/whats-new/norge-leverer-tilbake-nh90-helikopteret/id2918079/) |
| Nansen Sting Ray / ESSM / NSM | [Norwegian defence budget, platform armament](https://www.regjeringen.no/no/dokumenter/prop.-1-s-fd-20152016/id2455797/?ch=2) |
| P-8 / 333 Squadron at Evenes | [Norwegian Armed Forces](https://www.forsvaret.no/en/news/articles/first-p-8) |
| VFA-34 F/A-18E | [Squadron's official website](https://www.airlant.usff.navy.mil/vfa34/) |
| Older Project 877 family | [Rubin design bureau](https://www.ckb-rubin.ru/en/projects/naval_engineering/conventional_submarines/project_877/) |
| Udaloy / Kulakov baseline systems | [CSIS research report, Moscow's War in Syria, naval force appendix](https://csis-website-prod.s3fs-public/publication/Jones_MoscowsWarinSyria_WEB_update.pdf?J1rQM6.th1g6DA034fNCT_DmxTFYpJPx=) lists Rastrub, Kinzhal and AK-100 |
| Gorshkov's A-192M | [Rostec / Rosoboronexport shipbuilding presentation](https://www.rostec.ru/en/media/news/rosoboronexport-to-present-latest-russian-shipbuilding-products-to-foreign-partners-at-imds-2021/) |
| Mk 110 family identity | [US Navy fact file](https://www.navy.mil/Resources/Fact-Files/Display-FactFiles/Article/2167940/mk-110-57-mm-gun/) |
| Russian class recognition context | [ONI public recognition posters](https://www.oni.navy.mil/ONI-Reports/Threat-Recce-Posters/) |

## Remaining fidelity work

Detailed class-specific combat modeling remains incomplete. In particular, Russian torpedo fits and close-in guns use family abstractions; Rastrub uses the existing compressed rocket-torpedo mechanic and lacks its surface mode. Most gallery models remain illustrative rather than precise replicas. The simulation does not model real tactical doctrine, classified signatures, electronic waveforms, realistic acoustic propagation, replenishment or a damage-control engineering model.
