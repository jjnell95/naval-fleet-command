# Handoff

Latest: M38, [sensor coverage, air combat and air tasking](docs/2026-10-03-sensor-coverage-air-combat-and-air-tasking.md).
- **Coverage shading.** `SensorCoverage.discs` builds up to 48 Vector4 discs (kind in w). `ChartLayer.sensor_coverage` / `sensor_coverage_on` drive `coverage_mode` 1 in `chart_palette.gdshaderinc`; the regional map still uses mode 0. Map layer "coverage" (Shift+F4).
- **Air combat.** `Combat.air_escape_factor` and `closing_on` gate shots at aircraft on current range. Track manager: radar recognition of aircraft within `RADAR_RECOGNITION_NM` after `RADAR_RECOGNITION_S`. In the AI: `_air_reach`, `_enemy_air_reach`, `AIR_ROUNDS_IN_FLIGHT`, `_guiding_rounds`. Hits on aircraft are fatal (`WeaponManager._resolve_impact`).
- **Quick air.** `AirMissionManager.quick_type`, `quick_order`, `quick_deck`, `recall_all`. `CdsMenus.air_contact_items` and `air_deck_items`; Main's `_quick_air` pick state.
- **Air board.** `TacticalMap.air_board_lines` / `_draw_air_board` / `_click_air_board`; layer "air_board".
- **Harness flags.** `--silence=CALLSIGN|all` and `--quick-cap`, for coverage and air board screenshots.

Latest: M37, [integrated air defence, weapon fixes and flight operations](docs/2026-10-03-integrated-air-defence-and-flight-ops.md).
- **Defence cycle.** `AirDefence.run_cycle` is now two passes over the raid, ranked by `_rank_defenders`. The per-layer lifetime allowance is keyed by `AirDefence.layer_key` (layer and ship).
- **Networked guidance.** It lives in `WeaponManager.guidance_available`, `network_guide` and `network_track_guide`, gated by `PlatformSpec.cooperative_engagement` on both ships. Interceptors no longer take the shooter-radar check at the top of `_step`; `_step_interceptor` checks guidance itself.
- **Weapons Free against aircraft.** `AirDefence.engage_hostile_aircraft` runs only for a player side with no AI controller.
- **Holds.** `Movement.enter_hold` lays a racetrack and marks it (`Unit.hold_active`/`hold_point`). Anything deciding whether a unit is idle must use `Unit.has_route()`, not `waypoints.is_empty()`; the AI search did the latter and stalled until it was changed.
- **Marshal.** `AviationManager.deck_can_recover`, `in_marshal` and `marshal_point`.
- **Ready alert.** `Unit.ready_alert`, `Order.set_ready_alert` (a new `SET_READY_ALERT` order type, appended to the enum) and `AirMissionManager._scramble_alerts`.
- **Generators.** They need `shapely`. Even with it, the generator sequence did not reproduce `data/` byte for byte in the cloud container, so data was edited by hand to match the generator output, and the generator carries the same change.

Latest art pass: 22 aircraft and all 14 submarine catalogue entries have revised original geometry, matching portraits/map plans and a shared `submarine_coating` world finish. `tools/art/build_air_subs.py` overrides the old builders; regenerate with `tools/art/rebuild_air_subs.sh` (copies donor derivatives last). Do not regenerate these entries with the legacy Blender source. `tools/recognition_playtest.gd` checks every revised entry through the real Reference viewer, including all three camera presets. See [the combined art and command review](docs/2026-10-02-aircraft-submarines-and-integration.md).

Latest deeper pass: [Classic, uncertainty and guided command](docs/2026-10-02-deep-command-review.md). `CommandGuide` observes accepted player orders and held reports; progress is saved in Main's presentation dictionary, not simulation fields. Briefing F1 can resume it. New native coverage: `tools/deep_command_playtest.gd`. Classic is now [1, 2, 4, 8], manual SAMs, auto-attack off. Explicit saved values always win; legacy 4×/auto-attack remains Custom. `WorldPresentation.plotted_entry` must never read a hidden specification: class representatives come from `MapSymbols.platform_for_class`, altitude from the Track. Visual sightings now also check terrain. Known sensor-only models are tinted, and captions distinguish SIGHTED, SENSOR ESTIMATE and BEARING ONLY/NO CURRENT FIX.

Latest UI pass: [command-screen refinement](docs/2026-10-02-command-screen-refinement.md). `CommandBar` now routes `orders_menu` through the same `CdsMenus.orders_items` used on own-platform right-click. Patrol/route live there; 3D Swap remains in its pane, and next contact is under Chart. Contact menu weapon options are nested, but valid finite salvos stay at root. `DataDisplay.plot_text` is shared with hover and Track File; zero assessed damage reads “not assessed.” The mouse suites were updated to use the new visible paths.

Latest: M36 (branch `claude/naval-fleet-command-improvements-pij1lv`, PR 31) adds standing stations (`Unit.station_*`, `Order.origin` "player"/"crew", `RETURN_TO_STATION`, generation counters), air missions (`AirMissionManager`, `AirMission`, `Order.air_mission`), saved engagements (`SimSnapshot`, `SaveGame`; every new simulation field must be saved or listed in `MANAGER_TRANSIENT`, or `tests/test_save.gd` fails), coordinated attacks (`GroupAttackManager`), enemy mission plans (`ai_plans`, `AIPlan`, `AIController._plan_cycle`), gameplay options (`GameOptions`, `SimClock.speeds()`, `Unit.auto_air_defence`, `INTERCEPT`, `UnitManager.engage_on_hostile_id`), the `OperationDirector` and `Simulation.variation_seed`, and the optimised sensor cycle (`CycleFacts`, `SensorManager.reference_path`, `Terrain._clears_every_hill`) with a 50 ms per-frame clock budget. Read [the M36 note](docs/2026-10-02-m36-missions-saves-and-an-enemy-with-a-plan.md). The full suite takes about four minutes. `tools/verify_save_continuation.py` checks saves across processes; `tools/measure_sensor_cycle.gd -- --paths=reference,optimized` measures the sensor cycle; `tools/opening_plans.py` flies scripted openings (not in CI); `tools/web/browser_check.cjs` boots the browser build and checks that a save survives a reload. Test harnesses must clear global world state they rely on (`Terrain.clear()`, `Detection.set_environment({})`): the suite's order is not a contract.

Previously: M35 cuts the missions to nine through the generators (run the five builders in the order below; they reproduce `data/` byte for byte), adds `CampaignBook` over `data/campaigns.json` and the commander's log, caches `ScenarioIndex` summaries (`forget(path)` after writing a mission), indexes landmasses in `Terrain` (`_land_span_exhaustive` is the reference the test compares against), and merges `CrewVoice`, `RadioNet.advise`, the ambient beds, the contact readout (`Track.source_*`, `damage_estimate`, `DataDisplay.source_readout`) and the far-reaching Action camera (`WorldCamera` pursuit and impact hold, an origin that re-centres on the Action subject, `WorldPresentation.witness_point` still deciding what may be shown). Voice on Linux needs speech-dispatcher, and enabling `audio/general/text_to_speech` prints one `libspeechd.so.2` line at start-up where it is missing; that line is not an engine error. Read [the M35 note](docs/2026-10-01-m35-nine-missions-a-crew-and-campaigns.md).

Before that: M34 adds the standing attack, `Order.attack(track, weapon := "")`, stepped by `UnitManager._step_attack` and ended through `UnitManager.attack_ended`; `UnitManager` now holds `weapon_manager` and is ticked with `tick(dt, now)`. A bare right-click decides from `TacticalMap.default_contact_verb(track)` (attack a HOSTILE, investigate an unclassified UNKNOWN, otherwise the menu); Shift+right-click is the contact menu. `MissionManager.assessment()` grades a finished mission and `CommanderLog` keeps best results beside the custom-mission directory; Main logs only missions the player took command of and the AI did not play. The desk opens on the `operations` shelf. Read [the research note and the remaining gaps](docs/2026-10-01-fleet-command-command-loop.md) before choosing the next milestone. `tests/run_tests.gd -- --only=test_attack.gd,...` runs a few test files.

Previously: M33 restores the inspected-contact focus without dropping command selection, adds persistent `Order.investigate(track)`, direct finite shots, Chart/time menus and mouse camera controls. Read [the source comparison and behavioral limits](docs/2026-09-30-fleet-command-intent.md). The contact inspection API is `TacticalMap.inspection_track()`; use it for presentation, keep `selected` for orders. Investigation uses held tracks only and reports completion through `UnitManager.investigation_ended`. Optional scenario `cloud_cover`, `rain_intensity` and `cloud_base_m` affect the live view only.

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
godot --path . --script tools/air_mission_playtest.gd -- --output-dir=res://work/air # missions, stations, saves
python3 tools/verify_save_continuation.py "$GODOT" /tmp/saves   # save, reload in a new process, compare
godot --headless --path . --script tools/measure_sensor_cycle.gd -- --paths=reference,optimized --repeats=3
python3 tools/opening_plans.py "$GODOT" --seeds=2,13          # two scripted openings per operation (slow)
NODE_PATH=/opt/node-tools/node_modules node tools/web/browser_check.cjs  # boot, save, reload, load, delete
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
| `scripts/core/commander_log.gd` | the commander's record of best mission results, read by the operations desk |
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
- **Never reach `DisplayServer.tts_*` unless `CrewVoice.use_os_speech()` has set `os_speech`.** On Linux without
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
- **Data that a generator writes is regenerated, not edited.** From `tools/scenarios/`, run
  `build_scenarios.py`, `build_northern_passage.py`, `build_cold_war.py`, `build_theatres.py`, then
  `operation_design.py`; that reproduces `data/` byte for byte (checked in M35). The 1990 and 2027
  catalogues' platforms and weapons (short names, torpedo countermeasures, the Perry's shared Mk 13
  launcher and the Type 07's rocket delivery included) live in those scripts. Change the script and
  run the sequence, or the next rebuild undoes a hand edit. M35 found three hand edits from earlier
  pull requests that a rebuild would have reverted, and moved them into the scripts.
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
