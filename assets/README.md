# Fleet presentation assets

All meshes are original procedural game art. They show public recognition features and approximate class proportions; they are not engineering models or exact representations of an individual hull, airframe or weapon variant. No Jane's assets, downloaded military meshes or technical drawings are included.

## Runtime assets

| File | Purpose |
| --- | --- |
| `platforms/<id>_beauty.png` | Lit three-quarter model in the unit card and mission menu |
| `platforms/<id>_plan.png` | Colour plan view for the tactical map's graphic symbols; bow right, 1.10 framing margin. Imported no larger than 384 px (`process/size_limit=384` in its `.import`; a new platform needs it too) |
| `platforms/<id>_profile.png` | Original monochrome recognition drawing retained as a fallback |
| `weapons/<id>_beauty.png` | Weapon-family recognition render |
| `platforms/<id>_thumb.png`, `weapons/<id>_thumb.png` | 240 × 128 gallery and loadout thumbnails |
| `models/<id>.glb` | Interactive inspection model; centred, longest dimension normalised to 10 units |
| `models/manifest.json` | Model type and triangle count for each asset |

The presentation set contains 140 platform and 149 weapon models (`models/manifest.json` is the authoritative list; the totals include the 1990 and 2027 catalogues). Ships have separate paint, non-skid deck, radar, glazing, metal and underwater-hull finishes. The Burke models have revised proportions, individually modelled VLS hatches, bridge windows, railings, life rafts and flight-deck markings. Carriers have recovery-lane markings and parked aircraft. Aircraft have curved canopies and class-specific wings, tails and rotor arrangements. Ordnance has family silhouettes, seeker/radome zones, fins, boosters, torpedo propellers and gun mounts.

The air-operations expansion adds 18 dedicated platform silhouettes and 12 weapon models. Charles de Gaulle has a compact angled flight deck and parked Rafales; America has a straight STOVL deck; Juan Carlos I has a ski jump and Harriers; Mistral has helicopter landing spots and Panthers. The smaller combatants retain their different mast, gun and deckhouse arrangements, while Suffren and Gotland have X-shaped stern controls. The aircraft set includes separate Harrier, Typhoon, Gripen, F-16, Atlantic 2, Su-34, Panther and Hawkeye shapes. The Panther has an open enclosed tail rotor; the missile additions include the external ramjet ducts on Meteor and Kh-31. These are visual recognition cues at game scale, not dimensionally authoritative reference material.

The earlier recognition geometry is in `tools/blender/build_platform_art.py`. Its additional geometry, materials, colour renders, thumbnails and GLB export are in `tools/blender/build_presentation_assets.py`. Revised models listed below are maintained in `tools/art/`; rebuilding them with the older Blender builders would overwrite their improvements. Blender is an authoring dependency only. The committed assets load directly in Godot and the exported web game.

```sh
blender --background --python-exit-code 1 --python tools/blender/build_presentation_assets.py --
# Regenerate one model, or just the lightweight thumbnails:
blender --background --python-exit-code 1 --python tools/blender/build_presentation_assets.py -- usn_ddg_burke_iii
blender --background --python-exit-code 1 --python tools/blender/build_presentation_assets.py -- --thumbs
godot --headless --path . --editor --import --quit
```

The pipeline was verified with Blender 5.2.1 and Godot 4.7.2. `ModelStage` uses a single visible SubViewport, simple studio lighting and a low-resolution procedural reflection sky. It stops viewport updates when hidden. Lists use thumbnails instead of loading all full-resolution portraits. The largest current model is under 24,000 triangles; the asset test limits each model to 20 material surfaces.

## Aircraft and submarines (2 October 2026)

`tools/art/build_air_subs.py` is the authoritative builder for 22 aircraft entries and all 14
submarine entries, including the two donor copies. Its registry overrides the earlier builders in
`build_models.py`. Aircraft use elliptical body sections, tapered airfoil sections, framed canopies,
recessed intakes and open exhaust lips. The F-35C retains its wider carrier wing, the Tomcat its wing
glove and swept flight pose, the delta fighters their canards, and the S-3 its T-tail. Patrol aircraft
have curved cockpit glazing; E-2C and E-2D show four- and eight-blade propellers respectively.

Submarines have rounded sonar bows, faired sails, class-specific hull proportions, bow or sail planes,
cruciform or X stern controls, and open pump-jet shrouds or exposed screws. The Virginia, Astute and
Kilo families no longer inherit another class's sail planes. Retracted mast heads and a clean flight
pose avoid implying current sensor or weapon state. `submarine_coating` is a dark matte material with
its matching shared world-view finish. Small fittings and poses remain illustrative; geometry does
not change detection, loadouts, performance, or the held-report visibility rules.

Regenerate models, portraits, thumbnails, profiles and plans together:

```sh
tools/art/rebuild_air_subs.sh
```

The script requires Python with numpy/trimesh/Pillow, Godot 4.7.2 and Xvfb. Set `GODOT` to select the
engine. It imports before rendering and copies the Japanese F-35B and Iranian Kilo **after** their
donor renders are refreshed. Preserve each plan texture's 384-pixel import limit. The render sidecar
marks this set with `recognition_revision: "2026-10-02"`; `tools/recognition_playtest.gd` opens every
marked entry in the actual Reference viewer and checks three camera presets and frame containment.

## Blender-free pipeline (2027 theatre catalogue)

The 45 platforms and 43 weapons of `data/theatres_2027_manifest.json` were built without Blender.
`tools/art/build_models.py` (Python 3.11, `trimesh`, `numpy`) ports the recognition vocabulary of the
Blender scripts (hull loft, deckhouses, masts, arrays, VLS grids, guns, canisters, fuselages, wings,
rotors, the revolve-profile ordnance) to numpy meshes, splits the hull into the same paint / non-skid /
antifouling / boot-topping finishes, merges parts by material (one glTF mesh per material, at most 12
surfaces per model) and writes each GLB centred with its longest dimension normalised to ten units.
Every model stays under 12,000 triangles. Fixed sites (domain `land`) are a compact installation on a
flat earth base with launchers in revetments, roads and a radar mast, so their plan reads as an
installation rather than a hull. Ordnance uses six family silhouettes chosen from the spec's type, range
band, speed band and launch profile; they are gallery icons, not dimensional data. The Air Self-Defense
Force F-35B and the Iranian Kilo reuse the Royal Navy F-35B and Project 877 geometry and renders.

`tools/art/render_assets.gd` renders the pictures in Godot itself (it needs a GL context, hence Xvfb):
each GLB is placed in a transparent SubViewport with the `ModelStage` environment plus three suns that
reproduce the studio of the Blender renders, framed with the same camera directions, the 1.16 beauty
margin and the 1.10 plan margin (bow to the right, port at the top). The profile is drawn from a grey
pass, a normal pass and a depth pass: `tools/art/compose_renders.py` (Pillow, numpy) keys out the sea
plane so a hull is cut at the waterline sitting at 80% of the image height, adds the white outline on
silhouettes, creases and depth steps, and downsamples every view with a premultiplied Lanczos filter.
`tools/art/render_manifest.json` carries the per-model domain and waterline height from the build to
the renderer. Regenerate everything with two commands, then let Godot import the new files:

```sh
python3 tools/art/build_models.py                      # or a list of ids
xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --script tools/art/render_assets.gd -- --all-new
godot --headless --path . --import --quit
```

`render_assets.gd` also accepts ids, `--out=<dir>` to write elsewhere and `--keep-raw`; the raw passes
land in `user://art_raw`. The pipeline was verified with Godot 4.7.2 (GL Compatibility, llvmpipe under
Xvfb), trimesh 5.1 and Pillow.

## Flat-tops (M28)

The seven flat-tops that sail in the operations (Nimitz, Ford, the 1990 Nimitz, Queen Elizabeth, Charles
de Gaulle, America and Mistral) came from the Blender pipeline as a slab of hull under a slab of deck and
are rebuilt in the Blender-free pipeline by `tools/art/build_flattops.py`, which `build_models.py`
registers. One `FlatTop` class lofts a flared hull up to an overhanging flight deck with a thick gallery
edge and catwalks along the sides; the deck outline is given per class as (station, half-breadth) pairs,
so an angled deck, a port sponson or a ski-jump bow is data. On it: deck-edge lifts let into the deck
edge over dark hangar openings in the hull, weapons sponsons (Phalanx, RAM, box launchers), the landing
area's edge lines and dashed centreline, catapult tracks, helicopter spots, and islands in tiers with
glazed bridges, masts and radars; the Nimitz's tripod mast, the Ford's island further aft with its flat
arrays, Queen Elizabeth's two islands. The deck parks use new parked shapes (Super Hornet, Tomcat with
its wings swept back, Hawkeye, Rafale, a naval helicopter) beside the pipeline's Lightning. Concave deck
outlines are ear-clipped (`slab`), since `Model.plate` fans from the first corner and only suits convex
ones. Every model stays under 15,000 triangles and 13 surfaces.

## Command Watch escorts (M32)

The Nansen, Gorshkov and Steregushchiy use class-specific builders in `tools/art/build_models.py`.
Nansen has one broad array tower, a separated funnel and a long flight deck; Gorshkov has a tapered
integrated mast, two foredeck launcher banks and paired aft close-in mounts; the compact corvette
has a spherical mast cap, inclined amidships launchers and a lower continuous deckhouse. Each has
bridge glazing, hangar doors, flight-deck markings, railings, boats/davits, capstans and life rafts.
The raised level flight decks sit above the loft's centreline camber so their markings remain visible.
These are original game interpretations of recognition features, not dimensional reference models.
The three models have 6,164–7,040 triangles and 12 merged material surfaces each.

```sh
python3 tools/art/build_models.py rnon_ffg_fridtjof_nansen rfn_ffg_admiral_gorshkov rfn_fsg_steregushchiy
godot --headless --path . --import --quit
xvfb-run -a godot --audio-driver Dummy --path . --script tools/art/render_assets.gd -- rnon_ffg_fridtjof_nansen rfn_ffg_admiral_gorshkov rfn_fsg_steregushchiy
```

## How the world view dresses a model

The GLBs keep their flat, named PBR colours, which the gallery and the renders use as authored. The
world view's model pool hands each instance to `WorldMaterials.dress`, which swaps every named surface
for a shared ShaderMaterial on `scripts/ui/world_hull.gdshader`: the navy's paint, plating seams, grime
and rust, a wet waterline with foam that follows the swell, and a hemisphere of sky and sea light in
place of the environment's flat ambient. A new material name needs a row in `WorldMaterials.TABLE` or
it keeps its authored look in the world view.

## Fonts and licences

Every font is a permissively licensed family, subset to Latin, Latin-1 and Latin Extended-A plus the
punctuation, arrows, geometric shapes and dingbats the interface draws (`pyftsubset`, hinting dropped;
Godot hints at runtime). Licence files sit beside the fonts in `fonts/`.

| File | Family | Used for | Licence | Source |
|---|---|---|---|---|
| `DejaVuSans-Bold.ttf` | DejaVu Sans Bold | the data face: data display, chart readouts, track numbers, table figures | Bitstream Vera licence with the DejaVu changes in the public domain (`DejaVu-LICENSE.txt`); the subset keeps the DejaVu name, which the licence allows (it restricts only the names "Bitstream" and "Vera") | npm `dejavu-fonts-ttf` 2.37.3 |
| `DejaVuSansCondensed-Bold.ttf` | DejaVu Sans Condensed Bold | the interface face: dialogs, menus, lists, buttons, briefings | as above | as above |
| `BarlowSemiCondensed-BlackItalic.ttf` | Barlow Semi Condensed Black Italic | the wordmark, NAVAL FLEET COMMAND | SIL Open Font License 1.1, no Reserved Font Name (`Barlow-OFL.txt`) | [google/fonts](https://github.com/google/fonts/tree/main/ofl/barlowsemicondensed) |
| `BarlowCondensed-ExtraBoldItalic.ttf` | Barlow Condensed ExtraBold Italic | yellow front-end captions, the big menu buttons, dialog titles | as above | [google/fonts](https://github.com/google/fonts/tree/main/ofl/barlowcondensed) |

The web page under `docs/` keeps its own woff2 copies of Barlow Condensed and IBM Plex with their
licences in `docs/fonts/`; the game no longer ships Plex.

## Front-end backdrop

`ui/frontend_backdrop.jpg` (1600 x 900) is rendered from the game's own 3D world, not painted or
photographed: `tools/art/render_backdrop.gd` loads a scenario, poses the player's task group in a
close formation, sets the sun a few degrees above the evening horizon, renders the WorldView pane at
full window, then darkens, softly blurs and vignettes it. Regenerate with

```
xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --resolution 1600x900 \
    --script tools/art/render_backdrop.gd -- --scenario=res://data/scenarios/aegis_bastion.json \
    "--subject=USS Truxtun (DDG 103)" --spacing=0.2 --sun-side=22 --range=1.25 --pitch=4
godot --headless --path . --import --quit
```
