# Independent Android Chromecast route

Request: fix the Chromecast permission blocker without violating licensing or Google terms.

Baseline: upstream discussion2051 has zero comments/replies on October9,2026, unchanged from October5. No written permission exists. This implementation must not claim otherwise or grant rights for upstream contributors.

## Required behavior and release inputs

1. Remove actual inherited translations and copied launcher artwork from every native Android runtime source/resource root. Keep independently maintained English/drafts with explicit partial coverage and English fallback; do not move inherited text into new files. Keep migration wire compatibility and test-only legacy fixtures outside the grant.
2. Add a scope-specific MIT grant for owner-controlled replacement Android source/tooling. Preserve repository GPL, legacy licenses, vendor/source notices and origin disclosure. Compare frozen production inputs against upstream; record limits rather than claim clean-room certification.
3. Replace upstream receiverFD1F76C5 with Google's documented Default Media Receiver constant, shared by CastOptions and route selection. Use the official SDK, standard media playback messages and explicit user receiver selection; never reverse engineer or circumvent registration.
4. Keep the public Cast-free variant the default. An explicit leafwakeCast=true selects Cast Kotlin, metadata, dependency graph and Cast privacy/notices together. Both variants use independent branding; no copied assets in either.
5. Inventory exact resolved runtime artifacts and their hashes/licenses. Reject unknown proprietary SDK versions. Retain Google embedded third-party license text/index and permissive notices in the in-app licenses screen. Treat Google binaries as proprietary, not MIT/GPL.
6. Describe receiver URL/token and network/certificate requirements, Google's required SDK analytics, local data and user server handling. Existing Cast-free public policy and shipped beta remain unchanged. Public Cast rollout requires updated Play Data safety and published Cast policy.
7. Run generator regression checks (red observed before implementation), core/app unit tests, both variant builds, compiled-input/package audit and emulator Cast/handover checks. No screenshots. A real receiver test must prove remote playback/control, return-to-phone and progress; unavailable hardware is an external execution blocker, not a passed test.

## Sources and scope

- https://github.com/advplyr/audiobookshelf-app/discussions/2051 (read-only; no maintainer contact)
- https://developers.google.com/cast/docs/web_receiver and /registration explicitly document the default-receiver no-registration route. Additional SDK terms still apply; a custom/styled receiver requires separate registration.
- https://developers.google.com/cast/docs/terms and https://developer.android.com/studio/terms govern SDK usage. Do not redistribute a standalone SDK or modify it.
- https://developers.google.com/cast/docs/android_sender/data_disclosure governs sender SDK telemetry; verify against the current SDK version.

This is Android only. It neither enables Apple Cast nor waives Apple/store/testing gates. No automatic public rollout without the listed checks.
