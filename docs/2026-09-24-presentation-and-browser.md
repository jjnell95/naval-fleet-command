# M22: Command deck redesign, debugging pass and browser delivery

The game now plays in any modern desktop browser from GitHub Pages at
[jjnell95.github.io/naval-fleet-command](https://jjnell95.github.io/naval-fleet-command/). The whole
interface was redesigned around the chart, and a debugging pass fixed twelve defects in the
simulation and the command deck, plus a set of smaller ones. Each of the twelve has a regression test or an interface check.

![Command deck, Norwegian Sea carrier watch](2026-09-24-command-deck.jpg)

## Design system

`scripts/ui/ui_theme.gd` defines one quiet system. Every screen uses it.

- **Surfaces.** Four navy-graphite elevation steps. Docked panels are flush and borderless, and one-pixel gaps between them read as hairline dividers. Floating panels over the chart are rounded and cast a soft shadow.
- **Colour means something.** Teal is the interface's own voice: selection, focus and the one primary action on a screen. Blue is own force, red is hostile or damage, amber is unknown or caution, and green is neutral or good news. Brass is used only for the wordmark and hero titles. Section labels are small tracked capitals in a muted tone, not coloured text.
- **Type.** Barlow Condensed is used for titles, IBM Plex Sans for reading, and IBM Plex Mono for time, coordinates and keycaps, on a fixed scale (11, 12, 13, 15, 26 and 44 px). Barlow falls back to Plex, so arrows and check marks never render as boxes in the browser.
- **Controls.** There are primary, secondary, quiet, segmented, tab, and danger buttons. Focus rings are visible, and scrollbars are thin. Tabs are underlined rather than boxed.
- **Icons.** `scripts/ui/ui_icons.gd` holds 39 original icons drawn on a 24-unit grid. They are rasterised at three times their size, so they stay sharp on high-density displays. Keyboard shortcuts moved from button labels into tooltips.

## Command deck

At 1600 × 900 the chart went from about 36% of the screen to over half of it.

- **Top bar.** The wordmark and operation sit on the left, the live objective above the latest event in the middle, then the clock with an explicit PAUSED or RUNNING state. The play/pause control turns amber while paused. Time compression is a single segmented control, and the utilities are icon buttons.
- **Status rail.** The five tall watch cards became one 38 px line: orders, contacts (hostile and unknown counts), threats, air and wide chart. The threat segment turns red while anything is inbound.
- **Chart chrome.** Zoom and framing move to a floating cluster on the right. Plot Move and the overlay toggles move to a toolbar at the bottom left. A chart footer carries the source note, a live cursor position with depth and layer, and the scale bar, which the old toolbar used to cover. The contact solution, hover card and symbol key are floating cards.
- **Command dock.** Controls are a compact 32–34 px. The command chain reads as a sentence ("USS Elrod (FFG 55) → T1001 · unknown surface"). A MIXED selection shows in amber text instead of tinting the whole button. ENGAGE is primary only once there is something to engage.
- **Actions palette.** Each row has its label, a state chip and a keycap. An unavailable command shows its reason on a second line.
- **Other screens.** The operations desk, briefing, air operations, recognition library and after-action report use the same system. The report leads with four tiles: rounds stopped, hits taken, hits scored and units lost.

The design size is now 1600 × 900 with `expand` stretch. Wider windows get a wider chart, and browsers are never letterboxed. Browser text renders about 11% larger than before on 16:9 laptops.

## Defects fixed

**Simulation.** These were found by review and reproduced with scratch scripts. Seven of the eight tests in `tests/test_regressions.gd` fail on the previous code.

| Defect | Effect | Fix |
|---|---|---|
| A round killed earlier in the same tick was still stepped | A missile reported INTERCEPTED could still hit the ship. In one geometry, 27 of 94 intercepted rounds also rolled an impact | `WeaponManager._step` ignores dead rounds |
| Terminal homing never re-checked the target | A SAM followed a landing helicopter into its hangar | The seeker loses a target that leaves its medium |
| Editor "reach area" objectives had no faction | Custom missions using them could never be won | Unscoped area objectives mean the player's force; the editor writes the faction |
| Area objectives counted stowed aircraft | One carrier with two helicopters aboard counted as three arrivals | Whole-force counts use flying aircraft and ships |
| Aircraft that flew home off the chart counted as destroyed | "Neutralize the raiders" could be won when they simply went home | `Unit.departed`; loss objectives require an actual loss |
| Dipping sonar skipped the hover rule on two paths | Helicopters in cruise heard pinging ships and running torpedoes | Both paths require the hover |
| The AI booked its re-attack cooldown before the order was accepted | A refused shot blocked retrying that target for 200 s or more | The cooldown is set only for a shot actually taken |

**Command deck:**

| Defect | Effect | Fix |
|---|---|---|
| Space also pressed whichever button had focus | Pausing just after clicking ENGAGE fired a second salvo | Space is taken before the GUI sees it, except in text fields |
| A deck aircraft could become the reference unit | Selecting a stowed helicopter blanked the picture and silenced contact and threat alerts | A stowed airframe sees through its ship |
| Arming Plot Move mid-drag latched the drag | The chart kept panning with no button held | Changing mode releases any drag |
| Hooking a contact moved keyboard focus to the weapon list | WASD panning and zoom keys stopped working | Focus moves only on an explicit request |
| Altitude and depth presets used the first unit's values | An S-3A sent to "cruise" went to a helicopter's 400 m | One order per airframe or boat |

**Smaller fixes:**

- Ctrl/⌘-K now works from inside search fields, and Escape closes the library from its search box.
- F10 and the restart button ask for a second press.
- Air Operations opens on a host that has aircraft aboard.
- F1 opens on orders, and "Return to chart" only appears once command has been taken.
- The chart says OBJECTIVE AREA rather than RENDEZVOUS. The platform status chip no longer calls radar-off "EMCON SILENT" while EMCON is free.
- Clipped labels and cards now wrap or end in an ellipsis, and the symbol key fits its card.
- Glyphs missing from the bundled fonts (⌘, ★, ●, ▸) are gone.

## Browser delivery

- **Download size.** Art textures now import as lossy WebP (quality 0.82) instead of lossless, and build tools are excluded from the pack. The pack fell from 81 MB to 33 MB, and a first visit from 119 MB to 71 MB (binary megabytes, as the loader counts them).
- **Loader.** `docs/play/index.html` is a new branded loader with real progress, megabytes and rotating tips. If WebGL 2 is missing it explains in plain language. On a phone it states the download size and that a keyboard is needed before spending the data.
- **Landing page.** `docs/index.html` was rebuilt with the game's own fonts (Latin subsets, about 105 KB in `docs/fonts/`) and fresh screenshots. The favicon 404 is fixed.
- **Build script.** `tools/web/build_web.sh` rebuilds the pack and writes its size into the loader.
- **CI.** `.github/workflows/tests.yml` runs the regression tests and both native interface suites on every pull request.

## Validation

- 319 regression tests pass, 11 of them new.
- The 29 command-deck checks pass at both 1600 × 1000 and 1600 × 900, including a new check that Space toggles pause exactly once with a button focused. The 19 air-operations checks pass.
- All 15 missions run 7,200 simulated seconds at seeds 2 and 7 with the AI commanding both sides: 30 of 30 runs exit cleanly with no errors or warnings.
- In headless Chromium, the rebuilt browser build loads, takes command, pauses, cycles contacts and opens the palette, air operations, library and symbol key. It runs at 60× and arms the restart confirmation with no console errors or page navigations, at 1440 × 800 and 1920 × 1080.

## Not changed

- The Northern Convoy can still be won without player input, because ship self-defence handles the corvette's salvo. Teaching identify-then-engage there is a mission-design change, not a fix.
- Time compression still drops to real time on each new contact. That is by design.
