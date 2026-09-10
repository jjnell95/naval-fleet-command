# Naval Fleet Command — Project Vision

Modern naval warfare tactical simulation. Spiritual successor to late-1990s fleet-command games.
Player is a task-force commander issuing orders, not a pilot. Fictional near-future NATO–Russia
conflict, Norwegian Sea / North Atlantic first. Real platform classes, gameplay-abstracted performance.

## Core loop
SEARCH → DETECT → CLASSIFY → TRACK → POSITION → ASSIGN WEAPONS → ENGAGE → ASSESS → REPOSITION

## Design principles
1. **No perfect information.** Enemies appear as uncertain sensor contacts (Tracks), never as Units.
   Tracks improve with observation time and go stale when contact is lost.
2. **Command, don't pilot.** Orders are data objects; units execute them.
3. **Information, positioning, magazines, and decisions win.** Not click speed.
4. **Plausibility, not false precision.** Real class names and public weapon/sensor families;
   uncertain performance values are `GAMEPLAY_ESTIMATE` tuning parameters (see DATA_SOURCES.md).
5. **Data-driven.** Platforms, sensors, weapons, scenarios live in `data/`, not code.
6. **Simulation ≠ presentation.** Sim runs on ticks; rendering is frame-based.
7. **Runnable after every milestone.** Gameplay > architecture > AI > depth > UI > perf > polish.

## Tech
Godot 4.x, GDScript, 2D tactical map. macOS Apple Silicon first; Windows-portable. No plugins,
no networking, no backend.

## Non-goals
Not an operational planning tool. No classified/sensitive tactics, guidance logic, or procedures.
No copyrighted assets from existing games.
