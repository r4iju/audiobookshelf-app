# Apple realtime handoff

Lane: Apple realtime parity (`upstream-realtime`, iPhone/iPad). Base `origin/fork/native-tv` at `ed3463d5`. Design and gates: [APPLE-REALTIME.md](../modernization/APPLE-REALTIME.md).

## What this branch commits

- `apple/App/NativeRealtime.swift`: the account-scoped coordinator, which is new.
- `tvos/Core/Sources/TVCore/RealtimeChange.swift` and `tvos/Core/Tests/TVCoreTests/RealtimeChangeTests.swift`: the shared, typed, owner-checked event mapping.
- `apple/UITests/RealtimeJourney.swift` and `apple/scripts/verify-realtime.sh`: five journeys on owned ports 26765/26769.
- Fixture additions in `verification/fixture.py` (`/__fixture__/remote-change`, restored by `configure`) and `verification/realtime/native-fixture.mjs` (per-user rooms, a socket drop control, `/__fixture__/realtime-connections`). Existing events without `userId` still go to every authenticated socket.
- `apple-realtime-wiring.patch`, kept next to this file: every edit to existing files that the root and presentation lanes own.

On its own, this commit builds without the patch. `NativeRealtime` is unused until it is wired, and `RealtimeJourney` fails until the patch is applied.

## Root steps

```bash
git apply --check docs/handoff/apple-realtime-wiring.patch
git apply docs/handoff/apple-realtime-wiring.patch
xcodegen generate --spec apple/project.yml   # adds NativeRealtime.swift, RealtimeChange.swift, RealtimeJourney.swift
xcodegen generate --spec tvos/project.yml    # TVCore gains RealtimeChange.swift (unused by the TV for now)
bash apple/scripts/verify-realtime.sh
```

The patch edits these files:

| File | Change |
| --- | --- |
| `AudiobookshelfNativeApp.swift` | Creates `NativeRealtime(api:localSession:)` with `{ playback.session?.id }` and injects `.environmentObject(realtime)`. Calls `realtime.connect()` on appear, when the scene becomes active, and on `connection.signInRevision` change. `serverQueue.connect()` is removed. |
| `ConnectionStore.swift` | New `@Published signInRevision: UUID?`, set with `activeAccount` in `openLibraries` and cleared on sign-out. It changes on re-login to the same account. |
| `NativePodcastQueue.swift` | `init(api:realtime:)` now subscribes to `realtime.events` and `realtime.signInRejected` instead of opening a second socket. The stream-rejection message is scoped to the rejected account. `connect()` is removed. |
| `CatalogStore.swift` | `receive(_ change:) async`: an in-place progress refresh of user and Continue Listening (no page loss), a first-page reload on additions or reconnection, and in-place item replacement and removal. |
| `CatalogViews.swift` | `CatalogShelf` `.onReceive(realtime.events)` calls `catalog.receive`. |
| `BookDetails.swift` | `.onReceive`: reloads on own-item progress, `user_updated`, own-item update or reconnection. |
| `AudioGroupViews.swift` | The list reloads on its kind's group events and on reconnection. Details reload on their own group change, progress, user change or reconnection, and dismiss when their group is removed. |
| `verification/parity.json` | `upstream-realtime.replacementEvidence.apple-mobile`, marked as simulator/fixture evidence only. |

Public API for other consumers: subscribe to `NativeRealtime.events` (`Event { account, change: RealtimeChange }`). An event is sent only while its account and sign-in revision are current. Call `connect()` whenever the sign-in may have changed; it is idempotent.

## Paused-player follow (owned elsewhere)

Baseline `layouts/default.vue` moves a paused player to another session's position on `user_item_progress_updated`. The paused-player worker (`681b5b5b`, base `6ac3f2ee`) owns that in `ApplePlayback`. It can subscribe to `NativeRealtime.events` for `.progress(itemID, episodeID, sessionID)`; this device's own echo is already dropped. This branch does not touch playback.

## Evidence (Studio, local only, simulators `Audiobookshelf Realtime QA` iPhone 17 / `Audiobookshelf Realtime iPad QA`, iOS 27)

- Red first:
  - `RealtimeChangeTests` failed to compile before the type existed.
  - Four journeys failed on their behavioural assertions against the unchanged app.
  - The re-login journey, added after review, failed before `signInRevision`.
- Green:
  - `swift test` in `tvos/Core`: 34 tests.
  - RealtimeJourney: 4/4 on iPhone and on iPad before review, then 5/5 on iPhone after review fixes.
  - Regression: Podcast (9), Collection (6), SavedConnections (3) and DurableProgress (4) pass with the patch applied. They were run with an uncommitted temporary remap of their hardcoded 19765/19766/19769 ports and the legacy seed address to 2676x, to respect port ownership.
  - Typechecks with 0 warnings: iOS 14 minimum source for the app plus TVCore, and tvOS 17 for TVCore.
  - Node realtime gate/journey (2) and Python fixture/compatibility/upgrade (8) pass.

## Remaining gates

- Physical iPhone/iPad against the live server with a second client (web/TV): progress, playlist and metadata edits while visible; Wi-Fi loss; background suspension and return.
- Paused-player position follow (paused-player worker, above).
- Events missed while suspended or terminated, or before the first `init`, are not replayed; server 2.30 has no replay.
- TV adoption of `RealtimeChange`.

## Item feeds and the gap before `init` (base `315183c1`)

The item page ignored `rss_feed_open` and `rss_feed_closed`, and only a resumed `init` refreshed visible screens. Server 2.30 emits to the `authenticated` room only and keeps no replay, so changes made between a screen's HTTP load and the first `init` stayed hidden.

- `RealtimeChange.itemFeed(itemID:feed:)` decodes `Feed.toOldJSONMinified` for `libraryItem` feeds. `authenticated` no longer carries `resumed`, and `NativeRealtime` no longer tracks it.
- `ItemServerActions.feedChanged(_:)` applies a feed change for the current sign-in. A load that started before a change does not undo it. `ItemServerActionsSection` subscribes through `catalog.owns(event)` and reloads on `init`.
- Catalog, book details, group list and details, and the root's `refreshPausedProgress` call now run on every `init`. The paused-player call site keeps its `event.isCurrent(on:)` guard, and `followPausedProgress` still skips unacknowledged listening.
- A catalog whose first load is superseded by an `init` refresh that fails now shows the failure instead of loading forever.
- `verify-realtime.sh` serves `apple/scripts/item_actions_fixture.py` on 26769. That Python backend's listen backlog is raised to 128 (`server.socket.listen(128)` in `apple/scripts/item_actions_fixture.py`, committed in `9223f97c`). The change is in the Python backend, not in `native-fixture.mjs`. An `init` refresh bursts about seven requests, and item reads loop back into the same server. With the default backlog of five, the backend refused part of the burst, and the Node proxy turned each refused connection into a 503. A failing iPad run traced to an `item-action-error` showing HTTP 503. A 40-request burst through the proxy reproduced 503s before the change and none after; that burst check was an uncommitted `/tmp` script. No production behaviour was changed for it.

Evidence, simulators `Audiobookshelf Realtime Sync QA` (iPhone 17) and `Audiobookshelf Realtime Sync iPad QA` (iPad Pro 11-inch M5), iOS 27, logs in `/tmp/realtime-sync-qa/`:

- Red first, all on behaviour:
  - Core: the feed event was not recognised, a feed change was ignored, and an older load reopened a closed feed. The sign-in guard case passed vacuously against the stub and stays as a guard.
  - NativeTests: `testAnInitDuringTheFirstLoadThatFailsShowsTheFailure` stayed loading.
  - Journeys on the unchanged app (iPhone): the feed opened elsewhere never appeared; the playlist list and Continue Listening missed changes made before the first `init`; open details missed progress and the feed.
  - `testUnsentListeningSurvivesAReconnectionRefresh` passed before the fix as intended, since it is a guard.
- Green:
  - `swift test` in `tvos/Core`: all pass.
  - NativeTests: 51/51 on iPhone and on iPad.
  - RealtimeJourney 9/9 plus PausedRealtimeJourney 2/2: iPhone 11/11 twice, iPad 11/11 twice after the backlog fix.
  - iOS 14 minimum source typecheck of the app, Playback, packages and TVCore: 0 errors.
  - Python fixture and item actions fixture tests pass.
- Not run: `verification/realtime` Node tests need the root `socket.io-client`, which is not installed in this worktree. They do not load `native-fixture.mjs`.

Remaining gates: a live-server feed opened and closed by another client (needs owner approval); physical iPhone/iPad realtime with a second client, Wi-Fi loss and suspension; and TV adoption of `itemFeed`.

## Review corrections to `9223f97c`

- **Own feed mutations against remote feed events.** `openFeed` and `closeFeed` applied their HTTP result whenever the sign-in was still current. A delayed open could restore a feed another client had closed since, and a delayed close could clear a replacement another client had opened. Each mutation now captures the feed-change count before its request and applies its result only if no realtime feed change arrived meanwhile. Activity and error still complete through `perform`, and the admin check, disabled state and sign-in (account ABA) guards are unchanged.
- **Progress during the first catalog load.** A `.progress` or `.user` refresh of an unfiltered catalog fetched only user and shelves. If those finished while the first load was still in flight, there was no content to update, so the refresh returned, and the slower first load then published its older user and shelves. This happens when a library opens after the socket has already authenticated, so the `init` resync can't repair it. Any refresh that runs while the catalog is still `.loading` is now a full reload that supersedes the first load. It goes through the same one-at-a-time queue, sign-in and account checks, and in-flight item-change merge as other reloads. A failure shows `.failed` rather than loading forever, and nothing re-triggers it, so it can't loop.

RED first: `testAnOpenAnsweredAfterAnotherClientClosedTheFeedKeepsItClosed` and `testACloseAnsweredAfterAnotherClientOpenedAReplacementKeepsTheReplacement` (Core) failed on the feed only. Activity and error already completed. `testProgressDuringTheFirstLoadIsNotLostToTheOlderLoad` (NativeTests) kept the first load's `["book-0"]` instead of `["book-0", "book-5"]`.

Green after the corrections, same simulators, logs in `/tmp/realtime-sync-qa/`:

- `swift test` in `tvos/Core`: all pass (`core-mutation-green.log`).
- NativeTests: 52/52 on iPhone (`native-mutation-green-iphone.log`) and on iPad (`native-fix2-ipad.log`).
- RealtimeJourney 9/9 plus PausedRealtimeJourney 2/2: 11/11 on iPhone and on iPad (`journeys-fix2-*.log`).
- iOS 14 source typecheck: 0 errors (`ios14-typecheck-fix2.log`).
- `ItemServerActionsJourney` was not rerun: its runner uses port 27765, which is outside this worker's 26765/26769. The Core tests above cover the open and close paths.

