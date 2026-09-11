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

The presentation set contains 42 platforms and 41 weapons. Ships have separate paint, non-skid deck, radar, glazing, metal and underwater-hull finishes. The Burke models have revised proportions, individually modelled VLS hatches, bridge windows, railings, life rafts and flight-deck markings. Carriers have recovery-lane markings and parked aircraft. Aircraft have curved canopies and class-specific wings, tails and rotor arrangements. Ordnance has family silhouettes, seeker/radome zones, fins, boosters, torpedo propellers and gun mounts.

The recognition geometry is in `tools/blender/build_platform_art.py`. The additional geometry, materials, colour renders, thumbnails and GLB export are in `tools/blender/build_presentation_assets.py`. Blender is an authoring dependency only. The committed assets load directly in Godot and the exported web game.

```sh
blender --background --python-exit-code 1 --python tools/blender/build_presentation_assets.py --
# Regenerate one model, or just the lightweight thumbnails:
blender --background --python-exit-code 1 --python tools/blender/build_presentation_assets.py -- usn_ddg_burke_iii
blender --background --python-exit-code 1 --python tools/blender/build_presentation_assets.py -- --thumbs
godot --headless --path . --editor --import --quit
```

The pipeline was verified with Blender 5.2.1 and Godot 4.7.2. `ModelStage` uses a single visible SubViewport, simple studio lighting and a low-resolution procedural reflection sky. It stops viewport updates when hidden. Lists use thumbnails instead of loading all full-resolution portraits. The largest current model is under 24,000 triangles; the asset test limits each model to 20 material surfaces.

## Fonts and licences

The game bundles Barlow Condensed, IBM Plex Sans and IBM Plex Mono from the Google Fonts repository. Their SIL Open Font License files are included beside the fonts in `fonts/`. Font sources: [Barlow Condensed](https://github.com/google/fonts/tree/main/ofl/barlowcondensed), [IBM Plex Sans](https://github.com/google/fonts/tree/main/ofl/ibmplexsans), [IBM Plex Mono](https://github.com/google/fonts/tree/main/ofl/ibmplexmono).
