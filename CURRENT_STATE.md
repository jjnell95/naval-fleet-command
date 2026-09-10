# Current State

**Milestone:** 9 — Operational Depth (complete). Cleaned and organised for handoff.
**Next milestone:** 10 — Presentation. Start from `HANDOFF.md`.

## What works
Nine milestones of simulation, all tested. In brief:

- Tactical map in nautical miles with zoom, pan, selection and orders; fixed-step clock with
  1x to 60x acceleration that drops to real time on combat events.
- Radar, sonar and electronic support as three separate channels. Contacts are Tracks, distinct
  from Units, and carry classification, staleness and an uncertainty ellipse. Passive sonar and
  ESM give a bearing rather than a position until target motion analysis resolves the range.
- Anti-ship missiles, torpedoes and guns fired at Tracks, not at Units, so stale data misses.
  Layered automatic air defence with fire-control channels, shoot-look-shoot allowances, close-in
  guns and decoys.
- Submarines with depth and acoustics; aviation with a deck cycle, fuel, dipping sonar and
  sonobuoys; a land domain for shore bases.
- An opposing-force AI under the same information limits as the player, issuing ordinary orders.
- Data-driven missions with typed objectives, briefing, scenario menu and in-process restart.
  Six scenarios plus a free-play sandbox.
- Datalinks, emissions control, rules of engagement, component damage and formations.

Tests: 136 pass. Scenario sweep with the AI commanding both sides at seed 2 gives victories in
Shadow Line and Northern Sentry, a defeat in Atlantic Gate, and undecided elsewhere.

## Cleanup done in this pass
- `main.gd` split: 636 lines down to 432 of wiring, with the command-line scaffolding moved to
  `scripts/core/dev_harness.gd` and documented there.
- Removed three functions nothing called, and the unused `data/nations/` tree. Nation is a field
  on a platform, not a directory.
- Fixed the build label, which had read "M6" since Milestone 6 because three separate edits to it
  silently failed to apply.
- Fixed two roadmap rows still marked TODO for finished work.
- Added `assets/README.md` and `HANDOFF.md`.

## Known bugs / limitations
- **Presentation is unstarted.** Symbols and labels overlap into an unreadable smear whenever units
  are close, unit state is carried by up to nine bracketed text suffixes, there is no legend, no
  sound, no tooltips, and identity is signalled almost entirely by red against amber against green,
  which is the worst available choice for colour blindness. The full list is in `HANDOFF.md`.
- ESM rarely wins first contact against surface ships, because passive sonar already detects a
  noisy warship at a similar range and the horizon caps both. Its distinct value is against
  aircraft and anything radiating that radar would struggle to see.
- No jamming or active electronic attack; electronic warfare here is listening only.
- The player's map shows every faction track, marked off link, rather than strictly filtering to
  what is shared. Only the AI is gated per unit.
- Automatic self-defence still uses a faction-wide threat picture regardless of datalink.
- The AI never forms up on its own and has no screening doctrine.
- Component damage cannot be repaired and there is no damage control.
- No air-to-air weapons, so an aircraft standing off beyond missile range cannot be stopped.
- Not under version control.

## Immediate next task (M10)
See `HANDOFF.md` for the ordered punch list, the rules about what may be changed, the visual
vocabulary as it stands, and the constraints that will bite. In short: declutter the map, make the
symbols carry state instead of the labels, add a legend and a front end, then sound and
accessibility.

## Implementation decisions
- Godot 4.7.2 at `~/Applications/Godot.app`. `G=~/Applications/Godot.app/Contents/MacOS/Godot`
  `$G --headless --path . --import` · `$G --headless --path . --script tests/run_tests.gd`
  `$G --headless --path . -- --scenario=<res path> --seed=2 --autopilot --fastforward=30000 --dump`
  macOS has no `timeout`; clear stale runs with `pkill -9 -f Godot`.
- Screenshots need a window. Headless runs must use `--dump`, which never waits on the renderer.
- Every dev flag is documented at the top of `scripts/core/dev_harness.gd`. That file is the only
  place that reads the command line.
- Applying edits by text replacement fails silently when the anchor does not match. It has happened
  four times here. Always grep for a distinctive token from the inserted text afterwards.
- GDScript lambdas capture locals by value, so a signal handler counting into an `int` does nothing.
