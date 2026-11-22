# Developing Naval Fleet Command

How the code is laid out, how to run and test it, and what to check before calling a change done. What the game is and how to play it is in [README.md](README.md); what changed is in [CHANGELOG.md](CHANGELOG.md).

## The one rule

Simulation and presentation are separate, and the separation is load-bearing.

- The simulation runs on fixed 0.25 s ticks from the `SimClock` autoload. It never reads a UI object.
- The presentation runs per frame, reads simulation state, and sends commands back only as `Order` objects through `UnitManager.issue_order()`.
- The presentation shows the player only what the plot holds: own units at truth, everyone else as `Track`s. Nothing under `scripts/ui/` reads `Track.truth` except to associate a track with the unit it holds. `Debug.enabled` (the harness's `--debug`) is the one sanctioned exception, and it is off in play.

Anything under `scripts/ui/`, plus `scripts/core/main.gd` (the wiring), is presentation and can be reworked freely. `scripts/simulation/`, `scripts/systems/`, `scripts/entities/`, `scripts/data/` and `data/` are the model: change them for a model reason, with a test.

## Layers and directories

```
SIMULATION    scripts/simulation, scripts/systems, scripts/entities   tick-based, no rendering
DATA          data/, scripts/data                                     Resources and JSON, no logic
PRESENTATION  scripts/ui, scenes/                                     frame-based, reads sim state
```

```
scenes/main/Main.tscn   the root scene (Control): the CDS screen layout and the Simulation node
scripts/core/           main.gd (the wiring), order.gd, geo.gd, debug.gd, game_options.gd,
                        save_game.gd, commander_log.gd, campaign_book.gd, dev_harness.gd and the
                        interface suites it starts (*_smoke.gd)
scripts/simulation/     Simulation and its managers, SimClock, Track, SensorContact, the scenario
                        loader, index and workshop, SimSnapshot, AirMission, GroupAttack
scripts/systems/        static rules and the AI: Movement, Detection, Combat, Damage, AirDefence,
                        TorpedoDefence, DefensiveResponse, Acoustics, Bathymetry, Terrain, Landmass,
                        Formation, BearingSolution, SubmarinePower, TowedArray, DippingSonar,
                        AIController, AIPlan
scripts/entities/       Unit (ground truth for every platform) and Weapon (a round in flight)
scripts/data/           PlatformSpec, SensorSpec, WeaponSpec and DataDB, which scans data/
scripts/ui/             the chart and its layers, the regional map, the 3D view, the data display,
                        the boards, menus and dialogs, the front end, the theme and the sound
data/platforms/         platform specs in aircraft/, cold_war/, helicopters/, submarines/,
                        surface/ and theatres/ (the nation is a field, not a directory)
data/sensors/ data/weapons/   sensor and weapon specs (.tres), referenced by id
data/scenarios/         the eleven missions (JSON); data/campaigns.json orders them into campaigns
data/bathymetry/        the regional sea-floor and land-height rasters
data/voice/             the crew's phrases
assets/                 models, renders, icons, fonts and audio (see assets/README.md)
tests/                  the headless regression suite
tools/                  interface suites, verification scripts, the data builders (scenarios/),
                        the art pipeline (art/, blender/), audio (audio/) and the browser build (web/)
docs/                   the GitHub Pages site: the landing page, docs/play/ (the browser build)
                        and the notes the pages and the catalogue cite
```

## The runtime tree

```
Main (Control, main.gd)              theme = UITheme.build(); global keys; routes orders
│                                    owns a DevHarness, which is scaffolding, not gameplay
├── Simulation (Node)                loads a scenario, forwards SimClock.tick to the managers
│   ├── UnitManager                  the units; issue_order(), movement and tasks each tick
│   ├── TrackManager                 each side's tracks: observe, classify, age, drop
│   ├── ThreatManager                each side's picture of detected inbound rounds
│   ├── SensorManager                the 1 s sensor cycle: Detection to TrackManager.observe
│   ├── WeaponManager                launches, rounds in flight, seekers, hits, intercepts
│   ├── AviationManager              decks, fuel, recovery, sonobuoys
│   ├── AirMissionManager            CAP, reconnaissance, ASW search and strike missions
│   ├── GroupAttackManager           attacks shared across several ships
│   ├── MissionManager               objectives, victory and defeat, effectiveness
│   ├── OperationDirector            the operation's events and seeded variations
│   └── AI_<faction> (AIController)  one per computer-commanded side
└── Layout (VBox)                    the CDS screen
    ├── Upper                        the top 68%: the chart, or the 3D view when G has swapped them
    │   ├── TacticalMap              chart layers behind one custom _draw(); zoom, pan, hook, input
    │   └── StatusBoards             the boards on A: OrdersPanel, UnitPanel, ContactPanel, comms
    ├── MapEdge                      the bevel under the chart
    └── BottomStrip                  the bottom 32%, each pane in a BevelFrame
        ├── RegionalFrame            RegionalMap, built in code: the whole battle space
        ├── ViewFrame                WorldView, built in code: the 3D view of the hooked item
        └── DataFrame → DataDisplay  the hooked item's data, watch time, time scale, message lamp
```

The managers under Simulation are created in `simulation.gd`, not in the scene. Main also creates in code the radio traffic (`RadioNet`), the right-click menus (`CdsMenus`), the key board (`KeyCommands`), the crew voice and the full-screen overlays: operations desk, editor, briefing, after-action report, Actions palette, Air Operations and Reference. The autoloads are `SimClock`, `Debug` and `SoundFx`.

Units are in nautical miles on a flat plane with y north; speeds in knots, bearings in degrees true, altitude in feet and depth in metres. The scenario's map anchor ties the plane to latitude and longitude.

## Where things are

| File | What it does |
|---|---|
| `scripts/core/main.gd` | the seam: wires simulation signals to the screen, owns the hook, routes orders, the key map and the screens |
| `scripts/ui/tactical_map.gd` | the chart: one `_draw()` for symbols, leaders, labels, routes, readouts and the radio line, and its input |
| `scripts/ui/chart_floor.gd`, `chart_land.gd`, `chart_relief.gd`, `chart_palette.gdshaderinc` | the relief chart under it: sea-floor bands, land heights and hill shading |
| `scripts/ui/map_symbols.gd`, `chart_labels.gd`, `chart_readout.gd`, `sensor_coverage.gd` | NTDS and graphic symbols, track-number placement, the readout's formats, coverage shading |
| `scripts/ui/radio_net.gd`, `radio_line.gd` | message traffic: the radio line, the comms board and the data display's lamp |
| `scripts/ui/commander_picture.gd` | the force's picture the chart and warnings show, whatever is hooked |
| `scripts/ui/world_view.gd`, `world_scene.gd`, `world_camera.gd`, `world_presentation.gd` | the 3D view: what may be shown (`WorldPresentation`), the cameras and the scene |
| `scripts/ui/world_materials.gd`, `world_*.gdshader` | how models look in the 3D view: finishes by navy, waterline, wakes, lights, rotors, plotted and underwater looks |
| `scripts/ui/data_display.gd`, `readout_window.gd` | the data display, bottom right, and its expanded readout |
| `scripts/ui/status_boards.gd` | the boards on A, hosting `orders_panel.gd`, `unit_panel.gd`, `contact_panel.gd`, `defence_board.gd` and the comms history |
| `scripts/ui/cds_menus.gd`, `key_commands.gd`, `command_palette.gd`, `command_bar.gd` | right-click menus, the H board, Ctrl+K and the command strip |
| `scripts/ui/fleet_operations.gd`, `fleet_roster.gd` | task-group readiness, selection, formation and defence orders; the roster and its search |
| `scripts/ui/air_operations.gd`, `weapon_control.gd`, `briefing_panel.gd`, `after_action.gd` | in-mission dialogs |
| `scripts/ui/scenario_menu.gd`, `scenario_editor.gd`, `platform_library.gd`, `saved_engagements.gd` | the front end: operations desk, editor, Reference and saves |
| `scripts/ui/ui_theme.gd`, `jfc_style.gd`, `ui_icons.gd`, `interface_scale.gd` | the theme (built in code, no `.tres`), bevels and lamps, icons, interface size |
| `scripts/ui/sound_fx.gd`, `crew_voice.gd`, `user_settings.gd` | sound cues and the ambient bed, the bundled crew radio clips, preferences in `user://settings.cfg` |
| `scripts/simulation/sim_snapshot.gd`, `scripts/core/save_game.gd` | saved engagements: the whole simulation state, and the files on disk |
| `scripts/simulation/scenario_workshop.gd` | seeded custom fleets, authoring validation and reinforcement export |
| `scripts/systems/ai_controller.gd`, `ai_plan.gd` | the opposing commander: it works from its own tracks and follows the scenario's plan |
| `scripts/core/commander_log.gd`, `campaign_book.gd` | best results per mission, and the campaigns over `data/campaigns.json` |

## Run the game

Godot 4.7.2 is the engine. The commands below say `godot`; use the path to your binary (on the cloud container it is `~/godot/godot`).

```sh
godot --headless --path . --import --quit    # once after cloning, and after adding a class_name
godot --path .                               # the operations desk
```

## Tests

```sh
godot --headless --path . --script tests/run_tests.gd                                  # the whole suite
godot --headless --path . --script tests/run_tests.gd -- --only=test_attack.gd,test_cds.gd   # a few files
python3 tools/test_runner_self_check.py "$(command -v godot)"                         # the runner fails on a runtime error
```

The runner discovers every `tests/test_*.gd` file in name order, so a new test file needs no registration. Each file extends `TestCase` (`tests/test_case.gd`) and each `test_*` method is a test. The runner resets the static world state (terrain, sea floor, weather, light, jammers) before each file, so a file starts from open ocean in daylight; within a file, a test that loads a coast or sets the environment should clear it again. An engine error during a test fails it. The full suite takes several minutes. It ends with `N tests, 0 failed`.

## Interface suites

`.github/workflows/tests.yml` runs these on every pull request and on pushes to `main`, after the regression tests. The two Python scripts run headless; the rest drive the real game window with mouse and keyboard and need a display, so on a server wrap each in `xvfb-run -a -s "-screen 0 1280x720x24"` with the screen size matching `--resolution`. `$GODOT` is the path to the Godot binary.

```sh
python3 tools/verify_northern_passage.py "$GODOT"                       # Northern Passage outcomes and deterministic replay
python3 tools/verify_save_continuation.py "$GODOT" work/save-continuation --quick   # a save continues identically in a new process
godot --path . --resolution 1280x720 --script tools/passage_playtest.gd -- --policy=escort --seed=31 --capture          # also at 1920x1080
godot --audio-driver Dummy --path . --resolution 1280x720 --script tools/command_watch_playtest.gd -- --seed=31 --capture   # also at 1920x1080
godot --path . --resolution 1600x900 -- --cold-war-smoke                                                                # command deck
godot --audio-driver Dummy --path . --resolution 1280x720 --script tools/fleet_command_playtest.gd -- --seed=31 --capture   # also at 1920x1080
godot --audio-driver Dummy --path . --resolution 1280x720 --script tools/deep_command_playtest.gd -- --seed=31 --capture
godot --audio-driver Dummy --path . --resolution 1280x720 --script tools/recognition_playtest.gd -- --capture --output-dir=res://work/ci-recognition
godot --audio-driver Dummy --path . --resolution 1280x720 --script tools/air_mission_playtest.gd -- --output-dir=res://work/ci-air-1280   # also at 1920x1080
godot --audio-driver Dummy --path . --resolution 1280x720 --script tools/command_priorities_playtest.gd -- --seed=31 --capture --output-dir=res://work/ci-priorities-720   # also at 1920x1080
godot --audio-driver Dummy --path . --resolution 1280x720 --script tools/readout_playtest.gd -- --seed=31 --capture --output-dir=res://work/ci-readout
godot --audio-driver Dummy --path . --resolution 1280x720 --script tools/command_training_playtest.gd -- --seed=31 --capture --output-dir=res://work/ci-command-training
godot --audio-driver Dummy --path . --resolution 1280x720 --script tools/fidelity_playtest.gd -- --seed=31 --ui-scale=125 --capture --output-dir=res://work/ci-fidelity
godot --audio-driver Dummy --path . --resolution 1280x720 --script tools/operational_fittings_playtest.gd -- --output-dir=res://work/ci-operational-fittings
godot --path . --resolution 1600x1000 -- --aviation-smoke                                                               # air operations
godot --path . --resolution 1600x900 -- --fleet-workshop-smoke --scenario-storage=res://work/ci-workshop-1600           # also at 1280x720
godot --path . --resolution 1600x900 -- --weapon-control-smoke --scenario-storage=res://work/ci-weapons-1600            # also at 1280x720
```

`--scenario-storage=res://work/<name>` gives a run its own custom-mission library, so it neither reads nor writes yours. Screenshots and results go under `work/`, which is not committed.

Slower checks that CI does not run:

```sh
python3 tools/smoke_scenarios.py "$GODOT" work/sweep                     # every operation on two seeds, the AI on both sides
python3 tools/opening_plans.py "$GODOT" --seeds=2,13 --jobs=4            # scripted openings against the AI, tabulated (about 20 minutes on four cores)
godot --headless --path . --script tools/measure_sensor_cycle.gd -- --paths=reference,optimized --repeats=3
NODE_PATH=/opt/node-tools/node_modules node tools/web/browser_check.cjs  # boot the browser build, save, reload, load, delete
```

`tools/measure_sensor_cycle.gd` times the shipped sensor cycle against the original pair-by-pair passes in `tools/measure_sensor_cycle_reference.gd`, which `SensorManager` runs instead of its own while its development switch `reference_path` is on. `tests/test_sensor_cycle.gd` uses the same switch to check that both make the same reports in the same order. The sound mix has its own playback check, `tools/audio/audio_playtest.gd`, described with the audio build in `assets/audio/README.md`; `tools/web/audio_check.cjs` checks sound in the browser build.

## Data builders

The Python builders in `tools/scenarios/` write every scenario, the 1990 catalogue (`data/platforms/cold_war/` and the `cw90_*` weapons and sensors, listed in `data/cold_war_1990_manifest.json`) and the 2027 theatres catalogue (`data/platforms/theatres/` and the entries listed in `data/theatres_2027_manifest.json`). The rest of the catalogue is hand-written resources. Change a builder and rebuild; a hand edit to a generated file is undone by the next rebuild.

```sh
pip install -r tools/scenarios/requirements.txt       # shapely and pyshp
python3 tools/scenarios/rebuild_all.py                # regenerate data/ in dependency order
python3 tools/scenarios/rebuild_all.py --check        # regenerate, then fail if git sees a change
```

`--check` is the test that `data/` is exactly what the builders write. Run it before committing any change under `data/` or `tools/scenarios/`. The regional coastlines, sea floor and land heights come from `import_coastlines.py`, `import_bathymetry.py` and `import_relief.py` over the Natural Earth and GMTED2010 downloads named in `regions.py`; their output is committed, so playing and rebuilding scenarios need no network access. `operation_design.py` and `build_command_training.py` apply the recognition briefs in `recognition_brief.py`.

Models and recognition art are built without Blender by `tools/art/` (`rebuild_air_subs.sh` for the revised aircraft and submarines, `render_assets.gd` for the renders); `tools/blender/` is the earlier pipeline, and must not be used to rebuild the entries `tools/art/` maintains. `assets/README.md` and `assets/audio/README.md` describe both pipelines and the audio build.

## The dev harness

To reach a tactical picture without playing to it, pass flags after a bare `--`. All of them are listed at the top of `scripts/core/dev_harness.gd`.

```sh
godot --path . --resolution 1600x900 -- --scenario=res://data/scenarios/gulf_01_hormuz.json \
  --seed=2 --fastforward=1800 --pick="USS Paul Ignatius (DDG 117)" --hold=2.5 --screenshot=work/shot.png
godot --path . --resolution 1600x900 -- --scenario=res://data/scenarios/pacific_02_taiwan_strait.json \
  --seed=2 --fastforward=2400 --run --perf=8               # the frame budget, printed as [Perf] lines
godot --headless --path . -- --scenario=res://data/scenarios/northern_passage.json --seed=2 --autopilot --fastforward=600 --dump   # state report after ten minutes
```

The ones used most: `--scenario=`, `--seed=` (pins every generator), `--fastforward=S`, `--autopilot` (the AI commands the player's side too), `--no-ai`, `--preset=classic`, `--pick=CALLSIGN`, `--run[=N]`, `--hold=S --screenshot=PATH`, `--dump`, `--perf=S`, `--debug` (the truth overlay), `--open-menu[=SHELF]`, `--boards[=N]`, `--world-view=full|swap` and `--world-camera=NAME`. Screenshots need a window; headless runs use `--dump`. A driven run plays under Normal rules unless `--preset=classic` is given, and never reads or saves the player's own options.

## The browser build

`docs/play/` is the browser build that GitHub Pages serves from `main:/docs`, so merging to `main` publishes it. The engine runtime there (`index.js`, `index.wasm` and the audio worklets) is the official Godot 4.7.2 web build and does not change with the game; only the data pack does.

```sh
tools/web/build_web.sh                       # rebuild docs/play/index.pck and record its size in the loader page
GODOT=/path/to/godot tools/web/build_web.sh
```

Exporting needs the 4.7.2 web export templates (the `web_*.zip` files and `version.txt` from the official `export_templates.tpz`) in `~/.local/share/godot/export_templates/4.7.2.stable/`. `export_presets.cfg` keeps the tests, tools, docs and the two smoke suites that only their flags load (`fleet_workshop_smoke.gd`, `weapon_control_smoke.gd`) out of the pack, and a test checks that nothing a shipped script names or preloads is left out.

## Conventions that bite

- **Order an action, do not perform it.** The presentation never sets a unit's fields; it issues an `Order`.
- **Every new simulation field is saved, or listed as transient.** `SimSnapshot` saves the whole simulation; a field that is neither saved nor listed in `SimSnapshot.MANAGER_TRANSIENT` fails `tests/test_save.gd`. `tools/verify_save_continuation.py` checks that a save continues byte for byte in a new process.
- **A kill is `Track.confirmed_destroyed`.** It is set only on an active track with a current fix. Do not infer a kill from `damage_estimate`; hit estimates stop at 99.
- **Use `Unit.has_route()` to ask whether a unit is idle**, not `waypoints.is_empty()`: a holding pattern or a station has no waypoints.
- **Every label that shows variable-length text needs `clip_text = true`**, or a long name widens the window and pushes panes off screen.
- **Full-screen overlays use `set_anchors_and_offsets_preset`**, not `set_anchors_preset`.
- **The theme is built in code** in `ui_theme.gd`: grey chrome from `build()`, the navy data family from `data_theme()`. A panel of data calls `UITheme.use_data_surface(self)`; a label on the wrong surface is unreadable.
- **The chart is one `_draw()`**, not a node per unit, and hit testing is manual. Track numbers are queued while symbols are drawn and placed afterwards by `ChartLabels`, so a new mark should go through `_queue_label`, not draw its own text.
- **The chart redraws on a simulation tick, a view change or a live animation, otherwise at `TacticalMap.IDLE_REFRESH_S`.** A new chart animation must be added to that condition or it will stutter. Hidden boards do not rebuild, so a test that reads a board's rows must show it first.
- **GDScript lambdas capture locals by value.** Use an array or another reference type.
- **The event log is quiet in release builds.** `Debug.event()` prints only in debug builds and scripted runs; a `print()` in gameplay code reaches a player's browser console.
- **Shader globals are declared in `project.godot`** (`[shader_globals]`, the `world_*` values). A shader that reads an undeclared `global uniform` fails to compile, in the browser as well.
- **No `instance uniform` in the 3D view's shaders.** Each instance that has them takes 16 of the renderer's 4096 slots (the WebGL uniform-block limit, on the desktop build too), and pooled models keep theirs while hidden. Use shared material variants, as `WorldMaterials.set_way` does; a test fails if one comes back.
- **The 3D view dresses models by material name.** `WorldMaterials.TABLE` maps each glTF material name to a finish; an unknown name keeps its flat authored colour.
- **Original assets only.** See `assets/README.md`.
- **Verify that a text edit applied.** More than one patch in this project's history silently matched nothing.
- **A headless run with no output at all** is usually a parse error in a script it loads; run the import step to see it.

## Before you call a change done

1. The full regression suite ends `0 failed`.
2. A change under `data/` or `tools/scenarios/` passes `python3 tools/scenarios/rebuild_all.py --check`.
3. The interface suites that cover what you touched pass (all of them run in CI).
4. A change to the model: the operations still play to an end with `tools/smoke_scenarios.py`, and a change that could move balance is flown with `tools/opening_plans.py` and compared with `main`.
5. A change to the screen: take a screenshot with the dev harness in at least one operation per theatre and look at it. The tests cover the model and the text of the screen; only a screenshot shows the chart.
6. A change that ships: rebuild the browser build, boot it with `tools/web/browser_check.cjs`, and commit `docs/play/index.pck` with its size in the loader page.
7. Say what changed in [CHANGELOG.md](CHANGELOG.md).

Design notes that still describe the game: [the CDS screen](docs/2026-09-27-cds-screen.md) and [the command loop](docs/2026-10-01-fleet-command-command-loop.md). The catalogue's source ledgers are listed in [DATA_SOURCES.md](DATA_SOURCES.md).
