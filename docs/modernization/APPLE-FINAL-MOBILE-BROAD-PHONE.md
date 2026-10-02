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
| 17 | Local files and opening modes | Preferences legacy import, Reader supplementary PDF (broad) | No local-folder or external-opening journey; non-PDF formats deferred |
| 18 | EPUB | Not in scope | Deferred after Phase 2 |
| 19 | PDF | Reader PDF journeys (broad) | Representative real PDFs |
| 20 | MOBI | None | Deferred |
| 21 | Comics | None | Deferred |
| 22 | Preferences, statistics, diagnostics | Preferences ×11 (broad); Diagnostics package 21/21; contrast audits; Presentation and ProgressReset (iPad) | Reduced motion and VoiceOver on device; translation parity |
| 23 | Migrate account and listening | Migration package 39/39; Preferences legacy import (broad); NativeTests adoption | Physical: real legacy data on owner devices |
| 24 | Migrate media and reading locations | NativeTests adoption; Reader upgrade journey (broad) | Physical: real migrated downloads and locations |
| 25 | Replacement readiness | All of the above | Physical acceptance, real server matrix, owner devices |

Suggested closure on simulator scope: #6, #10, #13, #14, #16 and #19 have no remaining simulator gap (only real-library or real-media confirmation). #4, #5, #7, #8, #11, #12, #15, #22, #23 and #24 are simulator-complete with physical criteria open. #9 and #25 need physical acceptance. #17 has a coverage gap. #18, #20 and #21 are deferred.
