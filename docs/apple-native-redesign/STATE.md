# Native Apple redesign integration state

Integration branch: `feature/apple-native-redesign`, based on `77c154b1` on `fork/native-tv`. Spec #230 and historical spec #222 remain unchanged. Source, Android, web and backend scope boundaries follow SPEC.md. One shared source writer runs at a time.

| Ticket | Integration | Evidence / remaining work |
| --- | --- | --- |
| #231 | Source `0894eb04`, evidence `f1116e66`, verified integrated | [Actual phone/tablet slice and checks](evidence/231/RESULT.md). Functional final-source phone 3/3, iPad shell 1/1 and bookmark 1/1. Full design acceptance remains #233. |
| #232 | Ready after #231 | Bounded TV shell and remote design slice. |
| #233 | Blocked by #232 | Fresh independent rendered phone/tablet/TV review. Check actual Search placement against Apple's current conventions. |
| #234–237 | Pending dependency graph | Complete mobile screens and localization. |
| #238 | Blocked by #233 | Complete TV screens and remote journeys. |
| #239 | Blocked by #237/#238 | Required adaptive, accessibility, fallback and full-screen acceptance. |
| #240 | Blocked by #239 | Final review, merge, merged-source QA and private device candidates. |

## Acceptance capability findings, October 8

- Actual desktop input/capture is available through agent-device's macOS desktop surface, but the host was locked during the compact-window probe. No actual resized-window interactions passed. Frozen probe evidence is `/tmp/native-compact-probe/RESULT.md`.
- Physical iPhone VoiceOver state can be queried; no verified spoken-audio capture/listening seam was established. Accessibility snapshots do not substitute for spoken traversal.
- Xcode 27 rejects iOS14 deployment builds before compilation. Full current Swift source typechecks targeting14, but that does not prove a supported binary or execution. The local host has no older supported toolchain/runtime.
- A possible macOS14/Xcode15 CI runtime-import experiment remains unverified. Apple's Xcode compatibility matrix and legacy runtime catalog host limits conflict. No Mac CI is configured; this is not proof that installing a CI workflow cannot work. Official iOS14 runtime downloads are accessible. Older-SDK compilation would also require compiler guards around newer SDK symbols.
- tvOS17 deployment builds succeed. Exact official runtime download queries for17.0/21J353 returned unavailable; the legacy tvOS package URL redirected to unauthorized in both CLI and shared browser. No runtime was downloaded. Installed TV runtime/device is27.

These are pending requirements, not accepted skips. Finish independent implementation and available verification before declaring any final blocker. Keep the integration PR draft until required gates pass. Public Apple uploads and Cast remain outside this work and rights-gated.
