# M18: the sea floor, the water column and the fight for the ship

M18 adds two things the simulation lacked: an ocean with a bottom and a layer, and damage that goes on after the hit. Everything numeric below is a `GAMEPLAY_ESTIMATE` unless it says otherwise. The shapes follow public physics and history; the values are tuning.

## The sea floor

**Source.** Natural Earth 1:10m physical vectors, bathymetry, version 5.1.1, public domain. These are the same data family and release as the coastlines. The layers used are the nested depth polygons at 0, 200, 1,000, 2,000, 3,000, 4,000 and 5,000 m, taken from the `v5.1.1` tag of `github.com/nvkelso/natural-earth-vector` (byte-identical to master for these files). `data/bathymetry/north_atlantic_depth.json` records the SHA-256 of every shapefile.

**Build.** `tools/scenarios/import_bathymetry.py` does the following:

1. Clips each depth band to the coastline region (46°W–55°E, 52°–81°N).
2. Rasterizes the bands at 1 nm in an oblique stereographic plane, so distances are the same north–south and east–west.
3. Interpolates depth between contours by relative distance: `D = Dk + (Dk+1 − Dk) · d_up / (d_up + d_down)`. The coastline is the 0 m contour, and a deeper contour more than 40 nm away is treated as 40 nm away.
4. Smooths the result with a 2 nm Gaussian.
5. Resamples it to a 1/30° × 1/60° latitude/longitude grid.

It writes three files:

| File | Use |
|---|---|
| `north_atlantic_depth.png` | Simulation. 8-bit, square-root encoded (a metre or two of resolution near the surface, about 30 m in the abyss), imported as a raw `Image` so it loads headless and in the web export. |
| `north_atlantic_chart.exr` | Chart shader only. Half-float metres at half resolution. |
| `north_atlantic_relief.png` | Chart shader only. Hill-shade baked from the full-precision field, lit from 315° at 45°, 24× vertical exaggeration. |

Two notes on the chart files. The half-float copy exists because 8-bit steps made contours wander by a pixel or two on gentle slopes. The relief is baked offline because computing it in the shader from quantized depth shows every encoding step as a terrace.

**Reach.** The game's local projection is equirectangular about each scenario's anchor, so world miles map to latitude and longitude by a scale and an offset. One raster therefore serves every chart, including custom missions saved from a built-in one. Without an anchor, or with the anchor outside the raster, the floor is *unknown*, and every consumer treats unknown as "no effect". `environment.bottom_m` sets a uniform floor instead.

**Accuracy.** The contours honor the source. Everything between them is interpolation. Spot checks through the game's own lookup:

| Place | Game | Commonly cited |
|---|---|---|
| Gotland Deep | 242 m | 249 m (maximum) |
| Central Baltic, 56.5°N 18.5°E | 78 m | mostly 50–150 m |
| Lofoten Basin, 70°N 5°E | 3,545 m | about 3,000–3,300 m |
| Norwegian Basin, 66°N 0°E | 2,956 m | about 3,000–3,600 m |
| Iceland Basin, 60°N 20°W | 2,604 m | about 2,500–3,000 m |
| Bear Island Trough | 505 m | about 400–500 m |
| Central Barents, 73°N 35°E | 195 m | sea averages about 230 m |
| **North Sea, 56°N 3°E** | **155 m** | **averages about 95 m: too deep** |
| **Faroe–Shetland Channel, 61°N 3°W** | **719 m** | **over 1,000 m at its deepest: too shallow** |

The two misses have one cause. A wide shelf far from any 200 m contour deepens toward the cap. Natural Earth's generalized 1,000 m polygon does not reach up the Faroe–Shetland Channel. **This is a 1:10 million chart, never a navigation chart.** It tells a shelf from a basin and a ridge from a trough. It says nothing about shoals, channels, wrecks or under-keel clearance, and surface ships do not ground on it.

## The water column

`scripts/systems/acoustics.gd` owns the path between a noise and an array. `Detection` still owns how loud things are and how good an array is. Each rule below takes the textbook shape from Urick, *Principles of Underwater Sound* (3rd ed., 1983), and a game-tuned size.

- **Bottom.** A submarine's depth is capped at the floor less 25 m, whatever its order says. A boat that runs onto the shelf comes up with it. Where the water is too shallow to submerge, the boat is forced up to periscope depth, where it has a radar signature again.
- **Layer.** Each mission sets a layer depth and strength. Sound crossing the layer loses up to 60% of its range. Hull sets ride 8 m below the keel, always above the layer. Variable-depth bodies (CAPTAS-2/-4, Sonar 2087) and dipping sets are lowered 40 m below the layer when the cable and the water allow. Sonobuoys take the shallowest of the 27, 120 and 300 m settings that clears the layer. A submarine listens from its own depth. A layer deeper than the floor is no layer.
- **Shelf.** Below 200 m of water, ranges shrink toward 70% of deep-water passive range and 55% of active range at 40 m, because reverberation hurts a ping more than it hurts listening.
- **Convergence zones.** Where the mission has them and the water is at least 2,000 m deep the whole way, a large array can hear a loud source in rings at 1× and 2× the zone range. Those arrays are the AN/SQS-53C, the variable-depth sets and the big submarine suites. The first zone needs a source the array could hear directly at 35% of the zone range, and the second at 60%. Zone contacts are bearing tracks with a range bracketed to ±8% of the zone.
- **Fused tracks.** A bearing, or a zone ring, no longer drags a track that radar or active sonar is holding firmly toward a worse guess.

**Per-mission water.** All missions are set in March. The layer depths are rounded game estimates informed by the general pattern of winter mixed-layer climatology (for example de Boyer Montégut et al., *JGR Oceans* 2004). Deep convective mixing puts the layer low in the Norwegian Sea and Iceland Basin, the Barents shelf is close to isothermal, and the Baltic has a strong permanent halocline.

| Mission | Layer | Strength | CZ range |
|---|---|---|---|
| GIUK Passage | 300 m | 0.6 | 32 nm |
| Shadow Line, Northern Shield | 200 m, 220 m | 0.6 | 30 nm |
| Northern Vigil | 250 m | 0.6 | 30 nm |
| Atlantic Gate | 350 m | 0.8 | none |
| Northern Sentry, Sandbox | 120 m, 100 m | 0.5 | none |
| Baltic Sentinel | 65 m (halocline) | 0.9 | none |
| Aegis Bastion, Arctic Shield | none | | none |

One consequence is deliberate: with a deep winter layer, a Kilo (240 m) cannot get under it anywhere in the shipped missions, while a Yasen-M can in Northern Shield. The AI submarine hides under the layer on patrol, when searching and when a torpedo is on it. It returns to patrol depth to hold a surface contact, and comes to 45 m only for a missile shot. The player gets the same choice as an **UNDER LAYER** depth order.

**One misassignment fixed.** In GIUK Passage, USS Delaware started 1–2 nm off Iceland's south coast, ordered to 120 m in about 20 m of water. She now starts at 63.3°N 16.2°W, in about 1,000 m, west of the Kilo's breakout lane.

## The fight for the ship

`Damage` keeps the hull pool and the component hits, and adds casualties that outlive the hit.

- **Starting casualties.** Missiles usually start fires (unspent fuel and warhead). Torpedoes nearly always flood. Guns rarely do either. Submarines flood and do not burn.
- **Fire.** Intensity grows or shrinks as `(0.0015 − 0.004·dc)·f` per second, so damage control above 0.375 wins and below it the fire spreads. The fire burns hull the whole time, so a crippled crew can lose a fire it could have held.
- **Flooding.** Pumped and shored down, and it runs away only when damage control has collapsed. Water aboard costs up to 40% of top speed.
- **Damage control.** Grows with the square root of ship size and falls with hull condition, but never below 35%, because most of a crew survives a hit. It runs at 65% for the first eight minutes while the parties organize and is split when a ship has both fire and flooding. Each hit draws a fortune between 0.55 and 1.2, standing for a cut fire main, an unreachable space, or luck. A friendly ship within 1 nm adds hoses and pumps.
- **Repair order.** Knocked-out systems are not worked on while the ship is burning or flooding.
- **Credit.** A ship lost this way is reported as lost to fire and flooding, and credited to the faction that hit it.

Calibration, 60 trials each, no consort, three hours after the hit:

| Hit | Lost | Survivors' hull |
|---|---|---|
| 1 × Harpoon on a Flight IIA Burke | 0% | 59% |
| 2 × Harpoon on a Flight IIA Burke | 63% | 17% |
| 1 × P-800 on a Flight IIA Burke | 33% | 28% |
| 1 × Mk 48 on a Flight IIA Burke | 98% | 2% |
| 1 × Harpoon on a Gorshkov | 17% | 48% |
| 1 × NSM on a Steregushchiy | 97% | 14% |
| 1 × LRASM on a Slava | 3% | 41% |
| 2 × P-800 on a Nimitz | 0% | 65% |

The intended shape comes from the public record: USS *Stark* survived two Exocets in 1987 after a long damage-control fight, HMS *Sheffield* was lost to fire after one in 1982, and *Moskva* was lost in 2022. These are anchors for the shape, not for the numbers.

**Decoys move a missile rather than deleting it.** When chaff beats a lock, the seeker flies on. Half the time it takes the nearest other ship within its basket and 35° of its heading, at most twice per round. Otherwise it is spent in the cloud. This is the commonly told story of *Atlantic Conveyor* in 1982: an escort's chaff is a hazard to the ship behind it, and station-keeping has to account for the threat axis.

## Presentation

The chart is a shader on a child node drawn behind the plot. It shows depth tint, baked relief (faded out at close zoom, where 2 nm cells would show) and only Natural Earth's own contours, drawn anti-aliased from a B-spline-filtered half-float texture. Nothing shallower than 200 m is drawn as a line, because it would be interpolation dressed as an isobath.

Beyond the scenario's coastline polygons, the raster's coarser coast continues, dimmed, behind a neatline marked *Limit of charted coast*, instead of stopping at a straight clip line. The overview inset uses the same tint. Burning ships trail smoke downwind, and fire and flooding have their own lamps and panel chips.

## Limits

- One layer depth per mission, the same everywhere and constant in time. There's no surface-duct gain, bottom bounce, frequency dependence or Arctic half-channel.
- Convergence zones are a single range per mission. The deep-water test is a line of samples, not a ray trace.
- Array and buoy depths are chosen automatically. The player cannot set a variable-depth body shallow to hunt a boat above the layer.
- Damage is still a hull pool with casualties on top: no compartments, magazine detonation, abandon-ship or towing.
- A seduced seeker ignores its own side's ships. Blue-on-blue is not modeled.
