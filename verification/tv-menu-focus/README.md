# Native TV menu continuity probe

Lease a TV simulator with `sim acquire tv --hours 4`, install realtime fixture dependencies if missing, then run:

```sh
python3 verification/tv-menu-focus/run.py --source <committed-sha> --simulator <leased-udid> --output /tmp/new-private-run --menu speed
```

Menus: speed, sleep (an active countdown), settings (skip back), sort (library). The tool archives the requested source and overlays a UIKit CADisplayLink sampler and a remote journey only in that disposable snapshot. Normal apps contain neither. No screenshots, owner media, owner credentials, or private APIs are used. Release the simulator afterwards.

The remote focuses an option and waits 20 seconds while real synthetic audio plays. The sampler records the public focus system's UIView identity every display-link callback. The checker excludes navigation/dismissal and requires at least 17 seconds and 200 samples of a stationary native context-menu row with zero replacements. It identifies native context menu cells by their runtime class name; an OS that changes that implementation must fail the missing-menu check rather than report a pass. This is a diagnostic continuity seam, not a GPU, pixel-color or hardware refresh measurement.

An ordinary accessibility assertion can pass while the native row is repeatedly replaced. The original build did exactly that. The source-pinned row-continuity report is the regression verdict. Raw focus records stay in the private output directory; publish only the summary and source SHA.
