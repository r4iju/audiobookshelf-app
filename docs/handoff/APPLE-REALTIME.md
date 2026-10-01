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
