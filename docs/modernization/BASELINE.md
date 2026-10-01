# Native modernization baseline

The approved specification is GitHub issue #1. Implementation order is Apple mobile and TV, then Android, then Next.js. Android starts only after issues #25 and #30 pass; Next.js starts only after #54 passes. All builds, fixtures, signing, verification and packaging run locally. Distribution is internal: direct native installation and a self-hosted browser client. No store release, TestFlight, hosted build runner or paid cloud service is required.

## Parity inventory

`verification/parity.json` records all 65 approved stories and additional source-derived capabilities. Source references identify the baseline implementation; they are not evidence that a replacement passed. Replacement evidence starts empty and must identify the tested client/server versions, commands or UI journey, actual outcome and device. Applicable rows must all pass before cutover.

Baseline mobile version: upstream **0.14.2-beta**, commit **7014e04e**. The internal server container currently runs **2.30.0**, read from its public package metadata. Its public status response exposes authentication methods but does not expose the server version. Synthetic fixtures are marked separately as `2.30.0-fixture` and are not claims of complete server compatibility.

TV installation and HTTPS connectivity were confirmed on the physical second-generation Living Room TV running tvOS 18.6. The iPhone and iPad also connect through HTTPS after explicit trust of the current homelab root. This is connection evidence, not complete playback/remote acceptance.

## Source inventory boundaries

- Connection: password/OpenID, saved servers, local HTTP, trusted HTTPS, subpaths, current refresh tokens and legacy bearer tokens. Transient failures must not erase recoverable account/progress state.
- Discovery: libraries, Continue Listening, cover/list modes, pagination, search, sorting/filtering, series/authors, details, collections and playlists with account permissions.
- Audio: direct play/stream/transcode/local modes, multi-file offsets, chapters, skip intervals, speed, bookmarks, timer/fade/reset/rewind preferences, background/system controls and route/interruption behavior.
- Podcasts: episode identity, sorting/filtering, resume/completion, downloads and server-permitted add actions.
- Downloads: task queue, retry/cancel/recovery, storage/cellular policy, persistent files and progress. Local folder selection/scanning is Android-only in the baseline: the iOS plugin explicitly reports it unavailable. Preserve iOS downloaded/local opening workflows without inventing folder support.
- Readers: EPUB with CFI locations and generated-location cache; PDF with page/rotation/link navigation; MOBI **and AZW3**; comics **CBZ and CBR**. Preserve supplementary ebooks, external opening, settings, progress and reading during audio.
- Platform features: Android casting and Android Auto, including browse grouping/series order; Apple media routes/system controls. Do not make a capability mandatory on a platform where it did not exist.
- Preferences: the exact platform fields and web preference/storage keys are in the inventory. Android additionally has shake sensitivity/reset feedback/chime and scheduled sleep behavior. iOS stores playback rate and chapter-track preferences in Realm.
- Realtime: Socket.IO initialization/authentication, user/item-progress updates, playlist updates and reconnect state. The initial HTTP fixture does not yet emulate these and must not be reported as realtime acceptance.
- Account/statistics/logs: preserve permitted progress-management actions, diagnostics, languages, orientation/haptics, large text, contrast, assistive navigation and reduced motion.

## Migration inventory

Do not open or copy live credentials into logs or fixtures. Use synthetic datasets for migration acceptance. Do not delete old files/state until migration validates them.

| Store | Data and migration boundary |
| --- | --- |
| iOS Realm default configuration | Saved server configurations and active index, device/player settings, local books/episodes/files, local progress, playback sessions, download tasks and logs. The source uses `Realm()` without a project-defined schema version: inspect and version the actual old schema during migration. |
| iOS Documents | Downloaded files are grouped by library-item identity; preserve file associations, filenames and cover paths before adopting them. |
| iOS Keychain | Refresh tokens use service `AudiobookshelfRefreshTokens`, account `refresh_token_<connectionId>`, accessible after first unlock. Access tokens are also present in legacy server records. Access depends on the signing/access-group identity. |
| Android Paper | Books: `device`, `localLibraryItems`, `localFolders`, `downloadItems`, `localMediaProgress`, `playbackSession`, `mediaItemHistory`, `log`. Preserve storage URIs and their permission grants. |
| Android secure storage | Refresh-token preferences are encrypted with the Android Keystore alias `AudiobookshelfRefreshTokens`. Moving a preference file alone does not transfer the decrypting key. |
| Capacitor Preferences | User/server/player settings, list view, last library, theme and language. Read exact keys from the inventory. |
| WebView localStorage | Browser device data, refresh-token entries, device ID, reader settings and `ebookLocations-` caches; enumerate the real content-key scheme before conversion. EPUB cache is distinct from authoritative CFI location. |
| TV | Existing TV Keychain credentials and in-memory pending sync. Pending sync currently cannot survive termination; issue #28 must replace that behavior. |

The public upstream app and this locally signed fork may have different bundle IDs/signing/sandboxes. A separate app cannot read upstream private data by assumption. A QA app uses a distinct identity and must not replace the working installed client. In-place cutover is permitted only after a validated migration, compatible identity/entitlements and documented backup/recovery constraints.

## Local toolchains and commands

The Studio has Xcode 27, Swift, Python 3, Node/npm, Android SDK and JDK 17/27. Capacitor 7's Java sources require JDK 21; install/use a local verified JDK 21 for the legacy Gradle build. Gradle wrapper is 8.11.1; Android minimum is API 24 and compile/target SDK 36.

```sh
npm ci
npm run generate
python3 -m unittest verification.test_fixture -v
python3 -m verification.fixture --port 18765
# Synthetic account qa / qa; server address http://127.0.0.1:18765/abs
npm run dev
(cd tvos/Core && swift test)
./tvos/scripts/deploy.sh --build-only
# Android: select JDK 21 before running the wrapper.
(cd android && ./gradlew :app:assembleDebug)
```

Legacy iOS Podfile minimum is 14.0; some project configurations retain 13.0. Xcode 27's simulator SDK accepts a minimum of 15.0. A **build-only** `IPHONEOS_DEPLOYMENT_TARGET=15.0` override permits a local reference build, but does not prove iOS 14 support or authorize changing the replacement's supported audience. Use an older compatible SDK to verify those older targets before cutover. The new-client minimum remains a compatibility decision, not an implicit increase.

For legacy iOS reference verification, copy the iOS subtree into an isolated temporary checkout, link its Node dependencies, run `pod install`, and build the workspace there with code signing disabled for the simulator. This preserves the owner's existing signing, Podfile, assets and working installed app.

## Acceptance vocabulary

A journey drives production presentation and platform controls against a controlled server, observing visible results, actual media and durable state, and server requests/progress. The fixture's observations are synthetic and are available only on its loopback server. Core/API checks and direct-method smoke are useful contract evidence; they are not remote/UI or physical-media acceptance.

Initial local reference: server-address entry, password sign-in, token renewal, library selection, synthetic home shelf and item navigation. The fixture also provides 61 items, two WAV tracks (8 and 12 seconds), resume at six seconds, chapters, podcast selection and captured progress reports. Extend fixtures one workflow at a time alongside client implementation.

Before a live server upgrade, run the supported baseline and candidate locally against every completed client, classify differences in authentication/API/realtime/media/progress behavior, align affected clients and verify regressions. Never point mutation-based fixture journeys at the owner's production server.
