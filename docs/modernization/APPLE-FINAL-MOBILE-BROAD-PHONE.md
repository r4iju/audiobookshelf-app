# Final broad iPhone acceptance at 6b59eda0

Simulator acceptance of the production native app on iPhone, against the synthetic local fixtures. No owner server, data or device was used. Physical criteria are listed per ticket and remain open.

## Source and setup

- 6b59eda0 (root's integration of the QA corrections). App source equals b1a82fea and 9e46bc19; everything after them changes only `apple/UITests`, `verification`, `apple/scripts` and docs.
- Leased pool simulator "Pool iPhone 1 (iOS 27.0)" (`75FA9768-B15C-40B6-ACC7-790D7FCAD29C`), released afterwards.
- Derived data on the external SSD: `/Volumes/ai-ssd/developer-caches/xcode/agents/final-mobile-qa-iphone/acceptance-derived` (through ignored links under `apple/build`) and each runner's own ignored build folder in this worktree, which resolves to `/Volumes/ai-ssd/code`.

## Results

| Run | Runner | Result | Evidence (worktree `audiobookshelf-final-mobile-qa/apple/`) |
| --- | --- | --- | --- |
| Broad NativeJourneyTests | `verify-ui.sh`, ports 19765 to 19769 | 90 passed, 0 failed, 0 skipped (2818 s) | `build-qa/broad-6b59eda0.{log,xcresult}` |
| Accessibility contrast audits and group permissions | `verify-remaining-qa.sh`, ports 57765/57769 | 5 passed, 0 failed, 0 skipped | `build-qa/gated/remaining-qa.log`, `build-remaining-qa/results/Pool-iPhone-1-(iOS-27.0)-20261002-151426.xcresult` |
| Playback authorization journey | `verify-playback-authorization.sh`, port 51769 | 1 passed | `build-qa/gated/playback-auth-journey.{log,xcresult}` |
| Diagnostics package | `swift test` | 21 passed | `build-qa/gated/package-Diagnostics.log` |
| Migration package | `swift test` | 39 passed | `build-qa/gated/package-Migration.log` |

The broad run excludes, with `-skip-testing`, the classes that need their own fixture: Presentation (12), Realtime (9), PausedRealtime (2), RelatedAuthorSeries (4), ItemServerActions (4), ProgressReset (4), RemainingQA accessibility and group (5), PublicationRecovery (1) and PlaybackAuthorization (1). None of the 90 was skipped at runtime.

A first broad attempt found no device (the pool name includes "(iOS 27.0)") and ran no tests: `build-qa/broad-6b59eda0-destination-error.log`.

Not rerun on iPhone, because they are green on the same production source and root asked not to repeat them: NativeTests 92/92 and PublicationRecovery 1/1 (root), and the iPad dedicated suites Presentation 12, Realtime 11, Related 4, ItemServerActions 4, ProgressReset 4. Those dedicated suites therefore have iPad, not iPhone, evidence at this source. Earlier main-use-case runs on this source: iPhone A 17/17 and B 4/4 (`APPLE-MAIN-USE-CASE-ACCEPTANCE-PHONE.md`), iPad 21/21.

No product defect was found, so no app code changed.

## Ticket acceptance map

Simulator scope means these synthetic-fixture runs on b1a82fea app source. "Physical" items have no simulator substitute and stay open.

| # | Ticket | Simulator evidence at this source | Still open |
| --- | --- | --- | --- |
| 4 | Connect and sign in | Connection, SavedConnections, CatalogRecovery (broad); PlaybackAuthorization journey | Real server CA trust and reverse proxy on owner devices |
| 5 | OpenID and multiple servers | OpenID ×4, SavedConnections ×3 (broad); Realtime account switch (iPad) | Real OpenID provider, owner servers |
| 6 | Browse and inspect books | Connection, Artwork, CatalogRecovery, Preferences layout, Search (broad); Related (iPad) | Real large library |
| 7 | Stream multi-file books | Playback ×8 (broad) | Real server media on device |
| 8 | Durable progress | DurableProgress ×4 (broad); PublicationRecovery (root); NativeTests | Real server and second real client |
| 9 | Background and system controls | NativeTests ChapterMediaControls only | Physical: lock screen, headset, calls, routes, real background |
| 10 | Chapters, speed, bookmarks | ListeningControls (broad); Presentation chapter track (iPad) | None stated beyond device check |
| 11 | Sleep timers and preferences | ListeningControls timers and resume rewind (broad) | Physical: background timers and interruptions |
| 12 | Search and discovery | Search ×3 (broad); contrast audits 3/3 (iPhone); Related (iPad) | VoiceOver and keyboard navigation on device |
| 13 | Collections and playlists | Collection ×6 (broad); RemainingQA group ×2 (iPhone); Realtime playlist (iPad) | None stated |
| 14 | Podcasts | Podcast ×9 (broad) | Real feeds and server |
| 15 | Downloads | Offline, Podcast download failures (broad); NativeTests download storage | Physical: device restart, cellular, real low storage |
| 16 | Offline and reconnection | Offline ×3, Collection offline, Reader offline PDF (broad) | Real network loss on device |
| 17 | Local files and opening modes | Supported iOS workflows green: downloads list, offline audio play, offline and supplementary PDF (Offline, Collection, Reader in broad; Groups A and B); legacy import screen reachable (Preferences ×2) | Local folders and external opening do not exist in the baseline iOS app (unsupported, not missing). Unverified: Files-picker import, revoked Files access (manual checks) |
| 18 | EPUB | Not in scope | Deferred after Phase 2 |
| 19 | PDF | Reader PDF journeys (broad) | Representative real PDFs |
| 20 | MOBI | None | Deferred |
| 21 | Comics | None | Deferred |
| 22 | Preferences, statistics, diagnostics | Preferences ×11 (broad); Diagnostics package 21/21; contrast audits; Presentation and ProgressReset (iPad) | Reduced motion and VoiceOver on device; translation parity |
| 23 | Migrate account and listening | Migration package 39/39; Preferences legacy import (broad); NativeTests adoption | Physical: real legacy data on owner devices |
| 24 | Migrate media and reading locations | NativeTests adoption; Reader upgrade journey (broad) | Physical: real migrated downloads and locations |
| 25 | Replacement readiness | All of the above | Physical acceptance, real server matrix, owner devices |

Suggested closure on simulator scope: #6, #10, #13, #14, #16 and #19 have no remaining simulator gap (only real-library or real-media confirmation). #4, #5, #7, #8, #11, #12, #15, #22, #23 and #24 are simulator-complete with physical criteria open. #9 and #25 need physical acceptance. #17 is simulator-complete for its supported iOS workflows; local folders and external opening are unsupported upstream on iOS, and the Files-picker import checks remain manual. #18, #20 and #21 are deferred.

## #17 audit: local files and opening modes

Bounded audit of the production source (b1a82fea app files) against the baseline iOS app in this repository.

What the baseline offers on iOS:

- Local folders, folder permissions and folder scanning: none. `ios/App/App/plugins/AbsFileSystem.swift` answers `selectFolder`, `checkFolderPermission` and `scanFolder` with "Not available on iOS". `BASELINE.md` says to keep the downloaded and local opening workflows without inventing folder support.
- External opening: none for media or ebooks. The baseline Info.plist registers only the `audiobookshelf` URL scheme, which is the OpenID callback (covered by OpenIDJourney). It declares no document types, and the readers have no open-elsewhere action.

Supported iOS local workflows (the inventory this ticket is judged against): downloaded audio, downloaded and supplementary PDF, the downloads list kept apart from server content, and importing previous app data from Files. Unsupported upstream on iOS, so neither missing nor promised: local folder selection, folder permissions and scanning, and opening media or ebooks in or from another app.

What production has, and how it is verified:

| Route | Where | Verification |
| --- | --- | --- |
| Downloads list, separate from server content (`offline-<item>`) | `DownloadsView.swift` | Broad: Offline ×3, Collection offline, Podcast downloads |
| Play a download with no server | Downloads, "Play offline" | Broad: Offline, Collection offline (Group A too) |
| Open a downloaded or supplementary PDF offline | Reader | Broad: Reader offline PDF (Group B too) |
| Import previous app data from Files (document picker, security-scoped access) | Connect screen and Settings, "Import previous app data" | Screen reachability only (Preferences ×2). Picking a file goes through the system picker. The import itself is #23 (Migration package 39/39). |
| Files app visibility of the app's Documents folder (`UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`) | `project.yml` | Not verified; it exists so a legacy export can be placed for the import above |
| Missing downloaded file on launch: entry fails with "A downloaded file is missing. Retry to restore it; existing files are retained." | `NativeDownloads.swift` init | **No test**: no journey or NativeTests case removes a downloaded file |

Findings:

- Missing feature: none. No local audio or PDF import and no external opening is a baseline match on iOS, not a regression. "Moved files" can happen only to downloads, which live in Application Support and are excluded from backup (so iOS does not purge them, and a restore to a new device restores neither manifest nor files).
- Missing verification, by decision not extended: the missing-file recovery above is a rare path and is left without a test. The Files-picker import and revoked Files access remain unverified manual checks.
- Simulator limits, recorded rather than claimed: the system document picker and the Files app are out of process, so picking a legacy export, revoking Files permission and a moved security-scoped file need a device or a manual picker session. Unavailable external handlers do not apply, since the app hands no media or ebook to another app.
