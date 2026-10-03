# Sensor coverage, air combat and one-click air tasking

This is an entertainment simulation with gameplay-estimate numbers. Nothing here describes a real system's performance or doctrine.

The owner's report had four parts:
- Switching sensors on and off made no visible difference.
- Air-to-air and surface-to-air combat were poor.
- The chart should go dark where radar or sonar does not reach.
- Launching and managing aircraft should be much easier.

## Sensors you can see

**Why switching made no difference.** Sensor rings were off by default and drawn only for hooked platforms. Consorts on the link kept the shared picture full when one ship went silent. A contact no longer seen stayed on the chart, only slightly faded, for up to 30 minutes.

**Coverage shading** (`SensorCoverage`, `chart_palette.gdshaderinc` coverage mode 1). The chart is lit where the commander's own sensors reach and dark beyond them:

| Coverage | How the chart looks |
|---|---|
| Inside a radiating radar's surface reach | Full light |
| Inside air-search reach only (aircraft seen, ships not) | About half light |
| Sonar only | A sea-green cast |
| Beyond every sensor | About 30% brightness |

- Each disc has a faint rim, so you can see where one ship's reach ends.
- Switching a radar off takes its light away on the next frame.
- The regional map keeps its translucent green discs.
- Shift+F4, or Chart ▸ Sensor coverage shading, turns the shading off.
- The shader holds 48 discs; surface radar is kept first, then sonar, then air search.

**Feedback on a switch.** The R and sonar toggles now say on the radio what changed: how many radars still light the chart, that contacts only the silenced ship held go stale in a minute, and that the force's emissions can be heard when radiating.

**Stale contacts fade.** A stale contact fades from 55% to 22% opacity over ten minutes, so a picture nobody refreshes visibly decays.

## Air combat

A measurement harness flew fighter-vs-fighter, ship SAM-vs-aircraft and full-scenario engagements, and logged every round from launch to resolution. These were the root causes:

| Problem | Cause | Fix |
|---|---|---|
| AI fighters turned away from every air contact | Their stand-off was 0.8 × their longest **anti-ship** weapon, 160 nm for an F/A-18 with LRASM | They hold half their air-to-air reach and close at dash. Outranged by more than 15%, they commit to 80% of their own reach |
| Most AI-vs-AI shots ran out of fuel | Fired at the edge of range against targets that then turned and ran | A shot at an aircraft must fit inside the range left after the target turns away (`Combat.air_escape_factor`, floored at 60%, or 80% for a target flying straight in) |
| Russian fighters never fired | Without electronic sensors they could never classify an aircraft, and the AI needs a class | A firm radar plot of an aircraft within 60 nm gives a probable type after 60 s. Ships are still not classified by radar alone |
| Hits on aircraft did not kill | Warhead damage below the airframe's health pool | Any hit on an aircraft brings it down |
| A third of AIM-120s went at aircraft already dead | The AI ignored recorded kills, allowed 8 rounds in flight per air track, and kept chasing dead tracks | Recorded kills leave the AI picture; 2 rounds in flight per aircraft; re-engage after the rounds arrive, not 200 s later |
| Ship SAMs lost guidance seconds after launch | The AI switched the ship's radar off on its next cycle | The radar stays on while the ship's own radar-guided rounds fly |
| SAMs fired at aircraft plotted from bearings, 55–74 nm wrong | A bearing-derived position counted as a fix | An air plot worked up from bearings is no firing solution |
| Aircraft decoys never worked against ship SAMs | Command guidance had no seeker band | Command and semi-active guidance are decoyable at half effectiveness; AI aircraft break hard when a missile is on them |
| Ships fired SAMs at missiles chasing friendly fighters | Any detected round with a friendly victim counted | A missile chasing an aircraft is the aircraft's to beat |
| Your rounds failed in silence | Only hits and misses at the target were reported | The radio says why: out of fuel, nothing found, target lost, guidance lost, decoyed |

Your own attack orders on aircraft are flown at dash. A round keeps mid-course updates from the shared picture after its shooter is lost.

Three rounds of measurement shaped these fixes. The validation section below gives the before and after numbers.

## Air tasking in one gesture

- **Right-click a deck ▸ Air tasking.** CAP over a point, Search an area and ASW search each take one chart click. The deck launches its best type for the job with a sensible count, radius and relief (`AirMissionManager.quick_order`). The clock keeps running and no dialog opens. Recall all aircraft cancels the deck's missions and brings everything home.
- **Right-click a contact.** "Intercept with fighters", "Air strike now" and "Send aircraft to identify" fly from the nearest deck that can do the job. Each item names the deck, type and number before you choose it.
- **L**, or Return to deck on an aircraft's menu, sends every hooked airborne aircraft home.
- **Air board.** A live list in the chart's top-right corner shows every mission's state, its lowest fuel and any deck alert. Clicking a line hooks those aircraft and frames them.

## Validation

See the pull request for the suite, interface checks and measurement tables.
