# Handoff

Latest: M33 restores the inspected-contact focus without dropping command selection, adds persistent `Order.investigate(track)`, direct finite shots, Chart/time menus and mouse camera controls. Read [the source comparison and behavioral limits](docs/2026-09-30-fleet-command-intent.md). The contact inspection API is `TacticalMap.inspection_track()`; use it for presentation, keep `selected` for orders. Investigation uses held tracks only and reports completion through `UnitManager.investigation_ended`. Optional scenario `cloud_cover`, `rain_intensity` and `cloud_base_m` affect the live view only.

The combined build also preserves the combat cleanup from `7e1d7a2`: Attack/Defence controls, authoritative firing, queued-fire cancellation and live missile tracking. Receipts measure `WeaponManager.committed_rounds()` deltas; the solar cache honors weather invalidation even while paused. Use [validation-m33-merge.json](docs/validation-m33-merge.json) for the current package hash and integration evidence.

The new real-input suite is `godot --path . --resolution 1280x720 --script tools/fleet_command_playtest.gd -- --seed=31 --capture` (also run at 1920x1080). It checks contact inspection, context menus, investigation, finite salvos and chart/time/camera controls. On the retained cloud workspace, source `/workspace/.cloud-onboarding/naval-fleet-command/activate.sh` to use the matching Godot 4.7.2 runtime and export templates; the base image's `godot` is older.

The short version for whoever picks this up next. `README.md` says what the game is and how to
play it, `ARCHITECTURE.md` how the code is laid out, `CURRENT_STATE.md` where the last milestone
left things, and `docs/` holds the dated notes and validation records for each milestone.

## Run it

```sh
godot --headless --path . --import --quit                  # once, and after adding a class_name
godot --path .                                             # Start Northern Passage, then Take Command
godot --headless --path . --script tests/run_tests.gd      # regression tests
godot --path . -- --cold-war-smoke                         # command-screen checks
godot --path . -- --aviation-smoke                         # air-operations checks
godot --path . -- --weapon-control-smoke                   # finite mixed salvos and firing board
godot --path . -- --fleet-workshop-smoke --scenario-storage=res://work/test-library
python3 tools/smoke_scenarios.py "$GODOT" /tmp/sweep       # every operation, two seeds, AI both sides
python3 tools/verify_northern_passage.py "$GODOT"             # ordinary-order outcomes and replay
godot --path . --script tools/command_watch_playtest.gd -- --seed=31 --capture # mouse/patrol/3D checks
tools/web/build_web.sh                                     # rebuild docs/play/index.pck
```

The interface suites need a window (`xvfb-run -a -s "-screen 0 1600x900x24"` on a server).
`.github/workflows/tests.yml` runs the tests and command, aviation, workshop, weapon-control, passage, Command Watch and contact-intent suites on every pull request. The
workshop suite also runs at 1280 × 720. Use `--scenario-storage=res://work/<name>` after `--`
when a validation run should have its own mission library.

To reach a tactical picture without playing to it, use the dev harness. Every flag goes after a
bare `--`, and they are all documented at the top of `scripts/core/dev_harness.gd`:

```sh
godot --path . --resolution 1600x900 -- --scenario=res://data/scenarios/gulf_01_hormuz.json \
  --seed=2 --fastforward=1800 --pick="USS Paul Ignatius (DDG 117)" --hold=2.5 --screenshot=/tmp/shot.png
godot --path . --resolution 1600x900 -- --scenario=res://data/scenarios/pacific_02_taiwan_strait.json \
  --seed=2 --fastforward=2400 --run --perf=8               # the frame budget, printed as [Perf] lines
godot --headless --path . -- --scenario=... --seed=2 --autopilot --fastforward=6000 --dump
```

Screenshots need a window; headless runs use `--dump`. `--perf` is how the frame budget in the
validation records was measured.

## The one rule

Simulation and presentation are separate, and the separation is load-bearing.

- Simulation runs on fixed 0.25 s ticks from the `SimClock` autoload. It never reads a UI object.
- Presentation runs per frame, reads simulation state, and sends commands back only as `Order`
  objects through `UnitManager.issue_order()`.
- The presentation shows the player only what the plot holds: own units at truth, everyone else
  as `Track`s. Nothing under `scripts/ui/` reads `Track.truth` except to associate a track with
  the unit it holds. `Debug.enabled` is the one sanctioned exception, and it is off in play.

Anything under `scripts/ui/` and `scripts/core/main.gd` (the wiring) is presentation and can be
reworked freely. `scripts/simulation/`, `scripts/systems/`, `scripts/entities/`, `scripts/data/`
and `data/` are the model: change them for a model reason, with a test.

## Where things are

The command screen is the late-1990s CDS layout: the chart across the top two-thirds, and below it
the regional map, the 3D view and the data display. `docs/2026-09-27-cds-screen.md` describes it.

| File | What it does |
|---|---|
| `scripts/core/main.gd` | the seam: wires simulation signals to the screen, owns the hook, routes orders, the key map, the screens |
| `scripts/ui/tactical_map.gd` | the chart: one `_draw()`; symbols, leaders, labels, routes, readouts, the radio line, input |
| `scripts/ui/chart_floor.gd`, `chart_land.gd`, `chart_relief.gd`, `*.gdshader` | the relief chart under it: sea floor bands, land heights, hill shading |
| `scripts/ui/map_symbols.gd`, `chart_labels.gd`, `chart_readout.gd` | NTDS symbols and graphic symbols; track-number placement; the readout's formats |
| `scripts/ui/radio_net.gd`, `radio_line.gd` | the message traffic: radio line, comms board, the data display's lamp |
| `scripts/ui/regional_map.gd` | the regional display, bottom left |
| `scripts/ui/world_view.gd`, `world_scene.gd`, `world_camera.gd`, `world_effects.gd`, `world_land.gd`, `world_presentation.gd` | the 3D view: what may be drawn (`WorldPresentation`), the cameras, the scene |
| `scripts/ui/world_materials.gd`, `world_hull.gdshader`, `world_swell.gdshaderinc`, `world_bow/light/rotor/tint/xray.gdshader` | how models look in the 3D view: finishes by navy, the waterline, bow waves, lights, rotor discs, plotted and underwater looks |
| `scripts/systems/torpedo_defence.gd` | acoustic decoys and anti-torpedo rounds; chaff is `air_defence.gd`'s and only works on missiles |
| `scripts/systems/defensive_response.gd` | finite manual/automatic countermeasure pulses, temporary evasion and resumption |
| `scripts/simulation/scenario_workshop.gd` | seeded custom fleets, strict authoring validation and reinforcement export |
| `scripts/ui/fleet_operations.gd` | task-group readiness, selections, formation and defence orders |
| `scripts/ui/data_display.gd` | the data display, bottom right, built from rows of coloured spans |
| `scripts/ui/status_boards.gd` | the boards on A, hosting `orders_panel.gd`, `unit_panel.gd`, `contact_panel.gd` (+ `defence_board.gd`) and the comms history |
| `scripts/ui/cds_menus.gd`, `key_commands.gd`, `command_palette.gd` | right-click menus, the H board, Ctrl-K |
| `scripts/ui/air_operations.gd`, `briefing_panel.gd`, `after_action.gd` | in-mission dialogs |
| `scripts/ui/scenario_menu.gd`, `scenario_editor.gd`, `platform_library.gd` | the front end: operations desk, editor, reference |
| `scripts/ui/ui_theme.gd`, `jfc_style.gd`, `ui_icons.gd`, `sound_fx.gd` | the theme (built in code, no `.tres`), bevels and lamps, icons, procedural sound and the ambient bed |
| `scripts/ui/crew_voice.gd`, `data/voice/phrases.json`, `user_settings.gd` | spoken crew phrases through an injectable text-to-speech sink; preferences in `user://settings.cfg` |
| `scripts/core/dev_harness.gd`, `cold_war_smoke.gd`, `aviation_smoke.gd`, `fleet_workshop_smoke.gd` | scaffolding: flags and three interface suites |
| `tests/` | the regression suite; `run_tests.gd` lists the files |
| `tools/scenarios/` | the scenario builders and the Natural Earth and GMTED2010 extractions |
| `tools/art/` | models and recognition art without Blender (`build_flattops.py` for the carriers and amphibious ships); `tools/blender/` is the earlier pipeline |
| `tools/web/build_web.sh` | the browser build; `docs/play/` is what GitHub Pages serves |

## Conventions that bite

- **Every label showing variable-length text needs `clip_text = true`**, or a long name widens the
  window and pushes panes off screen.
- **Full-screen overlays use `set_anchors_and_offsets_preset`**, not `set_anchors_preset`.
- **The theme is built in code** in `ui_theme.gd`: grey chrome from `build()`, the navy data family
  from `data_theme()`. A panel of data calls `UITheme.use_data_surface(self)`; a label on the wrong
  surface is unreadable.
- **The chart is one `_draw()`**, not a node per unit. Hit testing is manual. Track numbers are
  queued while symbols are drawn and placed afterwards by `ChartLabels`, so a new mark on the
  chart should go through `_queue_label`, not draw its own text.
- **GDScript lambdas capture locals by value.** Use an array or another reference type.
- **A parse error in a test used to hang the runner**; it now reports and exits. A headless run
  with no output at all is that shape of problem.
- **Verify that a text edit applied.** More than one patch in this project's history silently
  matched nothing.
- **The event log is quiet by default in release builds.** `Debug.event()` prints only in debug
  builds and scripted runs; `print()` in gameplay code would reach a player's browser console.
- **Never call `DisplayServer.tts_*` outside `CrewVoice.use_os_speech()`.** On Linux without
  speech-dispatcher each call is an engine error, which fails the tests and the interface suites.
  Tests inject a sink Callable. Interface-only lines go through `RadioNet.advise`, not `flash`.
- **Original assets only.** See `assets/README.md`. No Jane's assets, names or copied art.
- **The 3D view dresses models by material name.** `WorldMaterials.TABLE` maps each glTF material name
  to a finish; a model with a material name it does not know keeps its flat authored colour in the 3D
  view. The gallery and the renders always use the authored materials.
- **Shader globals are declared in `project.godot`** (`[shader_globals]`, the `world_*` values). A shader
  that reads a `global uniform` nobody declared fails to compile, in the browser as well.
- **No `instance uniform` in the world view's shaders.** Each instance that has them takes 16 of the 4096
  slots the renderer allows (the WebGL uniform-block limit, on the desktop build too), so about 255 instances
  in all, and pooled models keep theirs while hidden. Past that Godot prints "Too many instances using shader
  instance variables" and the values go wrong. Use shared material variants instead, as
  `WorldMaterials.set_way` and `WorldScene._lamp_material` do; a test fails if one comes back.
- **Data that a generator writes is regenerated, not edited.** `tools/scenarios/build_northern_passage.py` owns the introductory escort. `build_cold_war.py`, then
  `build_theatres.py`, then `operation_design.py` reproduce `data/` byte for byte; the 1990 and 2027
  catalogues' platforms and weapons (short names and torpedo countermeasures included) live in those
  scripts. Change the script and run the three, or the next rebuild undoes a hand edit.
- **The browser build needs the web export templates**: the `web_*.zip` files and `version.txt` from the
  official 4.7.2 `export_templates.tpz`, in `~/.local/share/godot/export_templates/4.7.2.stable/`. The
  1.3 GB download resumes with `curl -C -` if the connection drops.
- **`tools/art/render_backdrop.gd` hangs under Xvfb in the cloud container** (the committed backdrop is
  M24's); the same happens on M27, so it is the environment, not the scene.

## Before you call it done

Run the tests, the interface suites, passage policies and the scenario sweep; take screenshots of the command screen
in at least one operation per theatre and look at them. The tests cover the model and the text of
the screen; only a screenshot shows the chart. Then rebuild the browser build, boot it in a
browser, and record the numbers in a dated note and a `validation-*.json` under `docs/`.
