# Fleet presentation assets

All meshes are original procedural game art. They show public recognition features and approximate class proportions; they are not engineering models or exact representations of an individual hull, airframe or weapon variant. No Jane's assets, downloaded military meshes or technical drawings are included.

## Runtime assets

| File | Purpose |
| --- | --- |
| `platforms/<id>_beauty.png` | Lit three-quarter model in the unit card and mission menu |
| `platforms/<id>_plan.png` | Colour plan view on the tactical map; bow right, 1.10 framing margin |
| `platforms/<id>_profile.png` | Original monochrome recognition drawing retained as a fallback |
| `weapons/<id>_beauty.png` | Weapon-family recognition render |
| `platforms/<id>_thumb.png`, `weapons/<id>_thumb.png` | 240 × 128 gallery and loadout thumbnails |
| `models/<id>.glb` | Interactive inspection model; centred, longest dimension normalised to 10 units |
| `models/manifest.json` | Model type and triangle count for each asset |

The presentation set contains 139 platform and 141 weapon models (`models/manifest.json` is the authoritative list; the totals include the 1990 and 2027 catalogues). Ships have separate paint, non-skid deck, radar, glazing, metal and underwater-hull finishes. The Burke models have revised proportions, individually modelled VLS hatches, bridge windows, railings, life rafts and flight-deck markings. Carriers have recovery-lane markings and parked aircraft. Aircraft have curved canopies and class-specific wings, tails and rotor arrangements. Ordnance has family silhouettes, seeker/radome zones, fins, boosters, torpedo propellers and gun mounts.

The air-operations expansion adds 18 dedicated platform silhouettes and 12 weapon models. Charles de Gaulle has a compact angled flight deck and parked Rafales; America has a straight STOVL deck; Juan Carlos I has a ski jump and Harriers; Mistral has helicopter landing spots and Panthers. The smaller combatants retain their different mast, gun and deckhouse arrangements, while Suffren and Gotland have X-shaped stern controls. The aircraft set includes separate Harrier, Typhoon, Gripen, F-16, Atlantic 2, Su-34, Panther and Hawkeye shapes. The Panther has an open enclosed tail rotor; the missile additions include the external ramjet ducts on Meteor and Kh-31. These are visual recognition cues at game scale, not dimensionally authoritative reference material.

The recognition geometry is in `tools/blender/build_platform_art.py`. The additional geometry, materials, colour renders, thumbnails and GLB export are in `tools/blender/build_presentation_assets.py`. Blender is an authoring dependency only. The committed assets load directly in Godot and the exported web game.

```sh
blender --background --python-exit-code 1 --python tools/blender/build_presentation_assets.py --
# Regenerate one model, or just the lightweight thumbnails:
blender --background --python-exit-code 1 --python tools/blender/build_presentation_assets.py -- usn_ddg_burke_iii
blender --background --python-exit-code 1 --python tools/blender/build_presentation_assets.py -- --thumbs
godot --headless --path . --editor --import --quit
```

The pipeline was verified with Blender 5.2.1 and Godot 4.7.2. `ModelStage` uses a single visible SubViewport, simple studio lighting and a low-resolution procedural reflection sky. It stops viewport updates when hidden. Lists use thumbnails instead of loading all full-resolution portraits. The largest current model is under 24,000 triangles; the asset test limits each model to 20 material surfaces.

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

## Fonts and licences

The game bundles Barlow Condensed, IBM Plex Sans and IBM Plex Mono from the Google Fonts repository. Their SIL Open Font License files are included beside the fonts in `fonts/`. Font sources: [Barlow Condensed](https://github.com/google/fonts/tree/main/ofl/barlowcondensed), [IBM Plex Sans](https://github.com/google/fonts/tree/main/ofl/ibmplexsans), [IBM Plex Mono](https://github.com/google/fonts/tree/main/ofl/ibmplexmono).
