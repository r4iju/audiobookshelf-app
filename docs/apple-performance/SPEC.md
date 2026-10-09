# Apple UI performance patch

The owner reports jerky iOS scrolling, slow button response and TV motion that feels far below 60 Hz. Scope is the native iOS/iPadOS and tvOS apps, followed by new internal TestFlight builds. Preserve native glass, focus, layout, account isolation, playback and durable listening. No screenshots or owner confirmation gate.

Measure the real native library UI with large loaded covers, including iOS scrolling during playback. Separate accessibility automation and profiler overhead from app timing. Fix demonstrated causes and replay the same workload. Keep measurement instrumentation outside the normal app source; distributed builds must not contain it. Review, merge, replay functional journeys, archive exact committed source and verify Apple's processed builds and existing internal tester group assignment.

Hardware refresh, GPU presentation and subjective responsiveness are separate acceptance evidence. A simulator CADisplayLink callback report cannot establish physical 4K/60. Record unresolved hardware measurements honestly; do not turn unavailable profiling into an assurance of smoothness.
