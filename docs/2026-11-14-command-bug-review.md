# Command and combat bug review

14 November 2026 · Godot 4.7.2

This review fixes failures in the existing Fleet Command command loop: select a platform, order an investigation or attack, and let its crew carry out that task using the held contact picture. The reference remains the original manual research recorded in the [command-loop review](2026-10-01-fleet-command-command-loop.md) and [Classic rules review](2026-10-02-deep-command-review.md).

The four-pane command screen, NTDS symbols, right-click orders, finite salvos, original 1990 catalogue and Classic defaults are retained. Classic still offers 1×/2×/4×/8× actual time, manual missile defence and attacks on orders. Platform performance, weapon specifications and scenario definitions are unchanged.

## Findings and fixes

| Problem | Player-visible correction |
|---|---|
| A contact reported destroyed still accepted a new attack or finite salvo. The launcher cancelled later queued rounds, but the first missile could already be wasted; CAP could select the same dead contact again. | The common firing check and standing-attack check both reject a held destruction report. Existing attacks also end when that report arrives. The check reads the report, not hidden target health. |
| Adding up estimated damage could produce 100% against an unclassified target that was still alive. Other systems interpreted that as destruction. | Hit-based estimates stop at 99%; 100% is reserved for the existing kill-report path. A later hit report cannot undo a confirmed kill. |
| The final salvo emptied the magazine and ended its standing attack on the next tick, allowing automatic station return while missiles were still queued or airborne. | The crew keeps its task until those rounds resolve. Weapons hold, lost contacts, destruction reports and aviation fuel priorities still take effect. |
| A stale-contact timeout ran only when all firing checks passed. Range or guidance refusals could reset it or select the wrong timeout. | A separate, saved timer limits uninterrupted stale pursuit to the existing four-minute grace period. A fresh report resets it. The crew reports that the contact stayed stale and releases the task. |
| The attack's stopping distance used nominal missile range even when the existing air-target firing rule required a closer shot. A ship could stop outside its usable envelope and eventually abandon the attack. | Both the paused intercept leg and ongoing steering use the same air-target range restriction as the firing check. Surface attack ranges retain their previous behavior. |
| Repeating a crew-issued CAP attack returned early without recording the player's new command. The CAP boundary could then cancel that explicit order. | Repeating the attack records commander ownership while preserving the salvo count and assessment pause. Automatic CAP pursuits still respect their boundary. |

## Compatibility

The stale-contact timer is included in the existing reflective save format. A regression saves a nearly expired pursuit, reloads it and verifies that the remaining grace period expires; older saves without the field load with a fresh grace period. Existing gameplay preferences and saved damage reports retain their values.

The browser data pack is rebuilt with the matching Godot runtime. These are workspace changes; this review does not publish a new live release.

## Validation

Seven newly added regression cases failed against the original command/combat implementation before the fixes. Nine new tests in total cover the corrected behavior, including estimated damage and saved pursuit state.

- **Full headless suite:** 1,048 tests, zero failures.
- **Native command screen, 1920 × 1080:** 79 checks, zero failures; actual chart selection, context menus, investigation, finite salvos, standing attacks and camera controls.
- **Native air operations, 1280 × 720:** 55 checks, zero failures; missions, recovery, stations and Classic save restoration.
- **Separate-process save continuation:** Carrier Watch (1990) and Northern Passage both resume to byte-identical tactical states compared with uninterrupted runs.
- **Rebuilt browser game, Chromium:** boot, operation entry, quicksave, page reload, save restoration, deletion and a second reload all passed. No page errors, console errors or console warnings.
- **Patch checks:** `git diff --check` passed.

Counts, save-state hashes and the rebuilt pack's hash are recorded in [the validation record](validation-2026-11-14-command-bug-review.json).

Native screenshots and machine-readable results are retained under `work/review-2026-11-14/`. The interface walkthrough exercises actual viewport input, and the browser check exercises the exported game and IndexedDB saves. These checks cover the corrected command paths and representative operations; they do not establish a new balance study or exact emulation of the original game.
