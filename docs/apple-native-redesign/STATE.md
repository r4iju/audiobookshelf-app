# Native Apple redesign integration state

Integration branch: `feature/apple-native-redesign`, based on `77c154b1` on `fork/native-tv`. [Draft integration PR #241](https://github.com/r4iju/audiobookshelf-app/pull/241). Spec #230 and historical spec #222 remain unchanged. Source, Android, web and backend scope boundaries follow SPEC.md. One shared source writer runs at a time.

| Ticket | Integration | Evidence / remaining work |
| --- | --- | --- |
| #231 | Source `0894eb04`, evidence `f1116e66`, verified integrated | [Actual phone/tablet slice and checks](evidence/231/RESULT.md). Functional final-source phone 3/3, iPad shell 1/1 and bookmark 1/1. Full design acceptance remains #233. |
| #232 | Source `cb8ebda8` + `5acca8c1`, evidence `5f48fdd0`, verified integrated | [Bounded TV shell, remote checks and focused/unfocused captures](evidence/232/RESULT.md). Final source 4/4; earlier 10/10. |
| #233 | Corrections integrated `da05a80a` + `8739a7b4`, evidence `a8e2e6d0`; independent round2 PASS | [Fresh rendered review](evidence/233/review-round-2.md) resolved D1–D3 and permits broad migration. [Actual corrected renders/checks](evidence/233/corrections-round-1/RESULT.md): final phone6/6 and wide-iPad Shell1/1. [TV portrait focus pair](evidence/233/corrections-round-1/tv-portrait/RESULT.md) captured. [Asset provenance](evidence/233/assets-provenance.md) identifies stale incremental resource sealing; clean separately verified candidates remain required. |
| #234 | Ready frontier | Complete mobile catalog/search/related hierarchy and acceptance. |
| #235–237 | Pending dependency graph | Complete listening, readers/downloads/groups and utilities/localization. |
| #238 | Ready frontier, queued behind sole mobile writer | Complete TV screens and remote journeys. |
| #239 | Blocked by #237/#238 | Required adaptive, accessibility, fallback and full-screen acceptance. |
| #240 | Blocked by #239 | Final review, merge, merged-source QA and private device candidates. |

## Acceptance capability findings, October 8

- Actual desktop input/capture is available through agent-device's macOS desktop surface, but the host was locked during the compact-window probe. No actual resized-window interactions passed. Frozen probe evidence is `/tmp/native-compact-probe/RESULT.md`.
- A device-only native iPadOS Windowed Apps/resize-handle probe is prepared at `/tmp/native-compact-device-probe-plan.md`; installed screenshot-grounded taps/pans may avoid desktop access. No actual window bounds or compact interactions have passed yet. Public scene size constraints are a separate nondeterministic probe, not a substitute for real geometry/actions.
- Physical iPhone VoiceOver state can be queried. The documented `devicectl device capture screen-record --device 'iPhone xiv' --destination /tmp/vo-probe.mp4 --duration 15` can record video, but default audio inclusion remains unknown. A bounded synthetic-screen recording and speech-assessment probe is still required. QuickTime supports connected-device audiovisual recording but does not establish VoiceOver routing; this iPhone currently connects via localNetwork, not USB. Installed whisper-cli has no verified model. `afplay` does not establish agent listening. Accessibility snapshots do not substitute for spoken traversal.
- Xcode 27 rejects iOS14 deployment builds before compilation. Full current Swift source typechecks targeting14, but that does not prove a supported binary or execution. The local host has no older supported toolchain/runtime.
- A possible macOS14/Xcode15 CI runtime-import experiment remains unverified. Apple's Xcode compatibility matrix and legacy runtime catalog host limits conflict. No Mac CI is configured; this is not proof that installing a CI workflow cannot work. Official iOS14 runtime downloads are accessible. Older-SDK compilation would also require compiler guards around newer SDK symbols.
- Concrete runtime-only CI files are prepared at `/tmp/native-ios14-probe/ci-experiment/`, selecting Xcode15.0.1 and the official14.5/18E182 package. No workflow was committed or triggered, runtime downloaded, or execution claimed.
- tvOS17 deployment builds succeed. Exact official runtime download queries for17.0/21J353 returned unavailable; the legacy tvOS package URL redirected to unauthorized in both CLI and shared browser. No runtime was downloaded. Installed TV runtime/device is27.
- Further managed official requests for17.2/21K364 and17.5/21L569, including universal and exact-build queries, also returned unavailable. Both catalog-listed package URLs redirected to Apple authorization. Disk space was sufficient; no download/import/device change occurred.

These are pending requirements, not accepted skips. Finish independent implementation and available verification before declaring any final blocker. Keep the integration PR draft until required gates pass. Public Apple uploads and Cast remain outside this work and rights-gated.
