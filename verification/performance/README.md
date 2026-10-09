# Apple performance workload

`run.py ios|tv --source <commit> --simulator <leased-udid> --output /tmp/<new-private-directory>` archives the specified commit and overlays a debug-only measurement probe into that disposable copy. The normal projects and distributed apps contain no probe or benchmark journey. Lease a pool device first with `sim acquire iphone|tv`, then release it afterward. Run each comparison alone, with the same device and no device-panel stream or profiler attached.

The synthetic 61-title library serves generated 4,000-pixel square and portrait JPEGs. iOS streams a 120-second synthetic book while a native timer scrolls the real library UIScrollView down and back, without XCTest accessibility queries during measurement. The report requires 16 steps and at least 1,000 points of movement. TV receives repeated native remote down/up presses. XCTest measures CPU time and physical memory over two iterations after warmup. No owner account, media, or screenshots are used.

`frames.json` records main-run-loop CADisplayLink callback gaps at a requested 60 Hz. It does not measure rendered GPU frames or prove physical 4K/60 presentation. `frame-budget.py` checks p95/p99 callback budgets; simulator load and profiling can change these results. Inspect the native driver validity and memory metrics too. Physical-device Animation Hitches/GPU verification remains distinct.
