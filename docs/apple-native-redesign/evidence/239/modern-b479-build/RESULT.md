# b479 modern TV build-only preflight

Exact source b479b897219426421e73f50b392e84e938669702. Fresh private git archive: 2203 original files, full hashes/archive hash in provenance.json. No disposable test-helper changes were needed because no UI tests execute. Only two xcodegen-derived project/scheme outputs differ from the archive; exact generated-project-deltas.json and diffs retained. No other executed source changes or added files.

Generic tvOS Simulator Debug build-for-testing passed (exit 0, 11.846 seconds), normal Xcode ad-hoc signing, deployment minimum17.0. Exact command/build log/toolchain retained. Product strict/deep signature exit0 and all40 resource hashes recorded in products.json. Mach-O minimum observations retained separately. Current toolchain Xcode27/SDK27, so this does not prove older Swift6.0.3 compilation or native Back behavior.

Generated scheme automatic attachment lifetime keepNever passed before build; effective AudiobookshelfTV_appletvsimulator27.0-arm64-x86_64.xctestrun keepNever guard passed afterward. No test-without-building invocation, UI test, installation, device lease, fixture, screenshot, video, render, or snapshot. Historical modern8c82 three-case passes remain attributed to8c82, not this source.

No shared repository/index/GH/Actions changes. No owned processes/devices/fixtures left to clean. Private proof only; root controls older frozen-source execution.
