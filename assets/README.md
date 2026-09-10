# assets

Everything on screen is drawn in code except one thing: the platform recognition art under
`platforms/`, which is rendered from original 3D models built in Blender by
`tools/blender/build_platform_art.py`. The tactical symbols live in `scripts/ui/map_symbols.gd`,
the map in `TacticalMap._draw()` and the interface theme in `scripts/ui/ui_theme.gd`.

## platforms/

Two PNGs per platform id in `data/platforms`:

| file | view | used by |
|---|---|---|
| `<id>_profile.png` | elevated side view, bow right, waterline at 80% of the height (ships); three-quarter view from ahead and above (aircraft, the air station) | the recognition card in the unit panel |
| `<id>_plan.png` | straight down, bow right, hull spanning 1/1.10 of the width | the close-zoom silhouette on the tactical map |

Every image is greyscale on alpha: mid-grey shaded faces with a white Freestyle outline. The
game tints it with the identity or damage colour at draw time (`PlatformArt` in
`scripts/ui/platform_art.gd`), which keeps the command-display look. A platform without a file
falls back to the code-drawn category shape; `tests/test_art.gd` fails when a data file has no
art so the two stay in step.

To rebuild after changing a model or adding a platform (needs the Blender Python module, CPU
Cycles, no GUI):

```sh
python3 -m pip install bpy==4.2.0
python3 tools/blender/build_platform_art.py              # all platforms, about a minute
python3 tools/blender/build_platform_art.py rn_ddg_type45  # one platform
godot --headless --path . --editor --import --quit         # refresh the .import files
```

Two rules hold for anything added here.

1. **Original work only.** The models are stylised shapes that evoke a class from public
   proportions; nothing is traced from a blueprint, downloaded, or lifted from another game.
2. **Keep it small and vector-like.** The look is a command display, not a painting. The
   renders are monochrome line-and-shade for exactly that reason, and a file here should be
   justified by something that genuinely cannot be drawn in code.

Anything added must load through Godot's importer and be referenced by `res://assets/...`.
