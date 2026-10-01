# Native Apple audio downloads and offline playback

Implemented on the internal SwiftUI preview identity. This is evidence for the audio slice of issues #15/#16, not replacement readiness or completion of ebook/background-device acceptance.

The app-owned background URLSession stores original audio files with authorization headers. Its serial main delegate queue moves temporary files before returning, publishes the manifest atomically, and only then acknowledges background event completion to UIKit. Download entries use canonical server/user identity and generation-scoped tasks. Cellular-policy changes replace unfinished requests; completed parts remain intact. Files live in Application Support, are excluded from cloud backup, and use protection until first unlock. Unreadable manifests remain untouched; missing completed files become retryable failures.

Local playback feeds owned file URLs into the shared multi-file player and writes positions/listening to the durable journal. Acknowledged history may retire while its account-scoped resume cache remains. Successful reconciliation also stores timestamped remote progress, allowing a newer rewind on another client to replace an older local position without redownloading media. Downloaded episodes preserve their own chapters, and the podcast episode list exposes a Downloaded filter.

## Local evidence

Tests use the production native app, actual WAV bytes and server-observed listening against the local reference contract derived from installed Audiobookshelf 2.30.0. Simulator runtime: iOS 27; source minimum remains iOS 14.

| Journey | Evidence |
| --- | --- |
| Download, server unavailable, cross-file seek, termination/relaunch, publication on reconnect | Meaningful first failure: absent download action. Passed after implementation. |
| Newer remote rewind adopted on next offline start, existing audio reused | Failed with old local position; passed after account-scoped remote reconciliation. The remote edit occurs after the last local close/termination. |
| HTTP 200 JSON error page rejected, retry completes and survives relaunch | Failed by publishing the error page as ready. A later retry failure exposed SwiftUI List row actions invoking Retry and Remove together. Passed after content-type validation and independent button actions. |
| Durable progress regression | All four journeys passed: canceled preparation, newer remote state, lost acknowledgment without duplicate listening, and unsent listening across termination. |
| iPad offline journey | Passed after correcting the test to target BackButton explicitly; the initial test accidentally tapped Hide Sidebar. |
| Resume cache | Real-file Core test passed after an observed initial failure, including retained acknowledged positions and isolation by account/episode. |

Commands:

```sh
swift test --package-path tvos/Core
python3 -m unittest verification.test_fixture verification.test_compatibility verification.test_upgrade_gate
bash apple/scripts/verify-ui.sh -only-testing:NativeJourneyTests/OfflineJourney -only-testing:NativeJourneyTests/DurableProgressJourney
ABS_QA_SIMULATOR='Audiobookshelf Native iPad QA' bash apple/scripts/verify-ui.sh -only-testing:NativeJourneyTests/OfflineJourney/testDownloadedBookPlaysAcrossFilesOfflineAfterRelaunchAndSynchronizesOnReconnect
bash apple/scripts/deploy.sh --build-only
```

The first combined milestone had six passing journeys and a failing retry journey; that retry journey then passed in a focused rerun after its UI fix. Do not describe the initial combined run as fully green. Minimum-iOS-14 source typechecking and the shared tvOS simulator build passed. Signing and packaging use the local toolchain with strict app/payload verification.

## Remaining acceptance

PDF and EPUB downloads and readers now have production simulator evidence documented in `apple/README.md`. MOBI/AZW3 and comic readers remain required. EPUB hardware volume navigation, background transfer interruption, device restart, insufficient storage, actual cellular-policy transitions, physical audio controls and live-server multi-device reconciliation still need their broader acceptance evidence. Simulator server unavailability is represented by HTTP 503 from API routes; it is not a physical airplane-mode test. Installation does not establish acceptance while a device remains locked. Xcode 27 uses a build-only iOS 15 override; iOS 14 runtime acceptance still requires an appropriate SDK/runtime.
