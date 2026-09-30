# QC and performance fixes

The September 29 review's import, geography, test-runner, profiler and guidance defects are repaired. The 274-actor massed-fleet benchmark now runs at roughly 64 FPS rather than roughly 21 FPS and keeps nominal 1x simulation time. Measured 95th-percentile frame intervals are about 30 ms; the longest remaining intervals are 114–118 ms. The proposed 100 ms worst-frame target remains a tuning target, not an achieved guarantee.

## Behavior

- Open-water builder recipes use a uniform 2,000 m synthetic ocean. Regional raster land no longer contradicts empty simulated terrain. Previously saved recipes with coastlines disabled receive the same behavior.
- Nested map-label positions/text and objective scalar fields are validated before replacing editor contents. Bad imports produce an authoring error and preserve the current mission.
- Manual directed/semi-active SAMs check the shooter's own radar, local horizon and terrain against held track altitude. Radar observations supply that altitude; targeting does not read hidden target height. Unknown height uses a conservative sea-level estimate. Loss of radar or guidance geometry ends the shot.
- The Cold War Perry's SM-1 and Harpoon share Mk 13 launch service across manual salvos, reservations and automatic defensive shots. Magazines remain distinct. Eight seconds is a gameplay service interval, not a verified real mechanical cycle.

## Cost and timing

Sensor weapon ranges are grouped by exact weapon resource and flight altitude, then evaluated per observer. Jammer lobes, guidance channels and AI commitments are cached only during their decision cycles. Newly fired rounds immediately update reservations. Track association lookup is indexed within each independent local/network picture; loss/restart removes the index entries.

Sensors, defence and AI retain their simulation frequencies but start on different fixed ticks. Defensive geometry reuses unit velocities and prunes ships without a layer in reach. Defensive and torpedo systems build faction weapon lists once per cycle. Chart ordnance and trails use batched line commands, offscreen culling and wider trail spacing for unhooked rounds in dense salvos; selected engagements keep the detailed plot.

The clock measures elapsed wall time rather than relying on the engine's clamped frame delta. Fixed simulation steps remain 0.25 s. Pause and combat slowdown discard their previous backlog; an OS suspension can enqueue at most one second of catch-up. The development profiler also uses monotonic frame intervals and reports simulated seconds per wall second.

## Verification

The real test runner registers Godot's [Logger error hook](https://docs.godotengine.org/en/4.5/classes/class_logger.html). Unexpected runtime, script and shader errors fail their test. An intentionally expected engine error must be declared with `expect_engine_error(message)` and must actually occur. CI runs an isolated null-call fixture and verifies a failed test plus a nonzero exit code before trusting the regression suite.

Commands:

```sh
Godot --headless --path . --script tests/run_tests.gd
python3 tools/test_runner_self_check.py /path/to/Godot
Godot --path . --resolution 1600x900 -- --autopilot --scenario=res://path/to/scenario.json --seed=2 --fastforward=180 --run=0 --perf=15
```

Native benchmark results are hardware-, renderer- and workload-specific. Actors include stowed aircraft. Both-side AI stress tests differ from normal player-commanded browser play, and weapon counts may change when guidance and scheduling are corrected. Compare actual frame intervals and simulation throughput, rather than treating FPS alone as a universal capacity claim. Time-separated desktop runs can also vary with system load and presentation pacing.
