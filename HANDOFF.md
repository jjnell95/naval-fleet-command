# Handoff: the presentation pass (Milestone 10)

## What this is

A modern naval tactical simulation in Godot 4.7.2, GDScript, 2D. The player commands a task force
over a nautical-mile ocean: search, detect, classify, position, engage, assess. Nine milestones of
simulation are finished and tested. Nothing has been done to make it look good. That is your job.

Read `PROJECT.md` for the design intent, `ARCHITECTURE.md` for how the code is laid out, and
`CURRENT_STATE.md` for where things stand. This file is the short version aimed at visual work.

## Run it

```bash
G=~/Applications/Godot.app/Contents/MacOS/Godot
$G --path .                                   # play it
$G --headless --path . --import               # after adding any script with a class_name
$G --headless --path . --script tests/run_tests.gd    # 136 tests, all should pass
```

To reach a specific tactical picture without playing to it, use the dev harness. Every flag goes
after a bare `--`, and they are all documented at the top of `scripts/core/dev_harness.gd`.

```bash
$G --path . -- --scenario=res://data/scenarios/northern_sentry.json --seed=2 \
  --autopilot --fastforward=9000 --select --form --hold=1.5 --screenshot=/tmp/shot.png
```

That loads the aviation scenario, pins the random seed, lets the AI command both sides, jumps
9000 seconds in, selects and forms up the player's ships, waits a second and a half, and saves a
PNG. It is how every screenshot in this project was taken and it is the fastest way to see a
change. **Screenshots only work in a window.** Headless runs must use `--dump` instead, which
prints state and quits without touching the renderer.

## The one rule

Simulation and presentation are separate, and the separation is load-bearing.

- Simulation runs on fixed 0.25 s ticks from the `SimClock` autoload. It never reads a UI object.
- Presentation runs per frame, reads simulation state, and sends commands back only as `Order`
  objects through `UnitManager.issue_order()`.

You can rewrite anything under `scripts/ui/` freely. If you find yourself editing something under
`scripts/simulation/` or `scripts/systems/` to make a visual change, stop: there is almost
certainly a read-only way to get what you need.

## Where things are

**Yours to rework.**

| File | What it does |
|---|---|
| `scripts/ui/tactical_map.gd` | the whole map: ocean, grid, symbols, rings, input. One `_draw()`. |
| `scripts/ui/map_symbols.gd` | the symbol vocabulary, drawn with primitives |
| `scripts/ui/ui_theme.gd` | the interface theme, built in code, no `.tres` |
| `scripts/ui/top_bar.gd` | title, objective, event flashes, clock, speed, mission buttons |
| `scripts/ui/unit_panel.gd` | left panel, everything about the selection |
| `scripts/ui/contact_panel.gd` | right panel, the track picture |
| `scripts/ui/orders_panel.gd` | bottom panel, four rows of controls |
| `scripts/ui/briefing_panel.gd` | briefing and live mission status |
| `scripts/ui/scenario_menu.gd` | scenario picker |
| `scenes/main/Main.tscn` | the layout tree |
| `assets/` | empty; see its README before putting anything there |

**Read from, do not change.** `scripts/simulation/`, `scripts/systems/`, `scripts/entities/`,
`scripts/data/`, `data/`.

**The seam.** `scripts/core/main.gd` (432 lines) wires the two halves together: it owns the
selection, routes orders, and turns simulation signals into flashes. You will touch it, but keep
it to wiring. The command-line scaffolding used to live here and now sits in
`scripts/core/dev_harness.gd`, which is not gameplay and can be ignored.

## What is on screen and what it means

Layout is top bar, then left panel / map / right panel, then the orders panel. 1600x900 default.

Colours as they stand, all in `tactical_map.gd`:

| Element | Colour | Meaning |
|---|---|---|
| ocean | very dark blue `0.024, 0.055, 0.086` | background |
| own units | blue `0.36, 0.72, 1.0` | tinted toward red as damage accumulates |
| hostile tracks | red `1.0, 0.36, 0.36` | identity confirmed hostile |
| unknown tracks | amber `1.0, 0.85, 0.3` | detected but not identified |
| waypoints | green `0.55, 0.95, 0.75` | ordered route |
| radar ring | blue, grey when silent | own sensor reach |
| sonar rings | green, brighter when pinging | passive and active |
| ESM ring | violet `0.85, 0.7, 1.0` | passive listening reach |
| weapon envelope | orange `1.0, 0.72, 0.35` | selected weapon's range |
| own weapons in flight | yellow `1.0, 0.85, 0.35` | missiles and torpedoes |
| hostile weapons | orange-red, circled | only drawn once detected |
| sonobuoys | green dots | dropped and left behind |
| debug truth | translucent red | true enemy positions, F3 only |

Symbols are original, NATO-flavoured, drawn at a fixed 7 px radius regardless of zoom:
circle for a friendly surface unit, diamond for a hostile track, square for an unknown, a tick for
heading, a small arc **below** for subsurface and **above** for air.

Track labels carry state in text: `BRG ONLY`, `ESM`, `OFF LINK`, `STALE`. Own-unit labels carry
`[EMCON]`, `[PINGING]`, `[DIPPING]`, `[RTB]`, `[CAVITATING]`, `[OFF LINK]`, `[ST]`, `[HOLD]`, plus
depth for boats and altitude and fuel for aircraft.

## The punch list

In the order I would do it.

1. **Decluttering.** Units stack on top of each other constantly, and their labels overlap into
   an unreadable smear whenever a group is close. This is the single worst thing about the display.
   Some combination of label offsetting, collision avoidance, and hiding labels below a zoom
   threshold.
2. **Symbol legibility at every zoom.** Fixed 7 px symbols vanish against the grid when zoomed out
   and look lost when zoomed in. The subsurface and air arcs are nearly invisible at a glance.
3. **State without text.** Nine bracketed suffixes on a label is a spreadsheet, not a display.
   Most of that should be shape, colour or a small glyph.
4. **A legend.** Nothing on screen explains any symbol. A collapsible key would carry a lot.
5. **The panels.** Three columns of monospaced-feeling label text. They are informative and ugly.
   Grouping, weight and spacing would do most of the work without changing content.
6. **Menu and mission flow.** The scenario picker and briefing are two full-screen overlays bolted
   onto the play screen. A real front end belongs here.
7. **Sound.** None exists. Sonar ping, missile launch, radar warning, impact, and restrained
   acknowledgements, per the design brief. Nothing recreated from any existing game.
8. **Tooltips and a reference.** Sensors, weapons and orders all have data-driven descriptions
   available; none of it is surfaced on hover.
9. **Accessibility.** Red against amber against green is the entire identity language right now,
   which is the worst possible choice for colour blindness. Shape needs to carry identity too.
   Text size is fixed. Not every control has a keyboard path.
10. **After-action summary.** The data exists in the managers; nothing reports it at mission end
    beyond a one-line banner.

## Constraints that will bite you

- **Every label showing variable-length text needs `clip_text = true`.** Without it a long mission
  name or event message widens the whole window and pushes the side panels off screen. This has
  happened twice.
- **Full-screen overlays need `set_anchors_and_offsets_preset`, not `set_anchors_preset`.** The
  latter sets anchors only and the panel collapses to its minimum size.
- **The orders panel is four rows and already 190 px tall.** Rows hide themselves based on what is
  selected, in `OrdersPanel._refresh_row_visibility()`. Adding a fifth row will clip off the bottom
  of a 900 px window unless the map gives up height.
- **The theme is built in code** in `ui_theme.gd` and applied to the root. There is no theme
  resource to edit in the editor.
- **The map is one `_draw()` call**, not a node per unit. Hit testing is manual, nearest symbol
  within 14 px. If you move to nodes, selection and the box-select rectangle both need rewriting.
- **Original assets only.** See `assets/README.md`.

## Traps found the hard way

- **Verify that a text edit actually applied.** Four separate patches in this project silently did
  nothing because a search string did not match, and each was only discovered later in a
  screenshot. One left the build label reading "M6" three milestones after M6.
- **GDScript lambdas capture locals by value.** A signal handler that increments a captured `int`
  does nothing. Use an array or another reference type.
- **A parse error in a test used to hang the runner forever** rather than failing. The runner now
  checks `can_instantiate()` and exits. If a headless run produces no output at all, that is the
  shape of the problem.
- **macOS has no `timeout`.** Clear stuck runs with `pkill -9 -f Godot`.

## Before you call it done

```bash
$G --headless --path . --script tests/run_tests.gd     # 136 pass
```

Then walk the six scenarios and confirm each still loads, runs and reaches a result:

```bash
for sc in north_atlantic_shadow_line northern_shield baltic_sentinel \
          atlantic_gate giuk_passage northern_sentry; do
  $G --headless --path . -- --scenario=res://data/scenarios/$sc.json \
     --seed=2 --autopilot --fastforward=30000 --dump
done
```

The tests cover the simulation, not the interface, so they will pass even if the display is
broken. Take screenshots. Nothing else will tell you.

## Not under version control

This directory is not a git repository. Initialising one before a large visual refactor would be
worth the minute it takes.
