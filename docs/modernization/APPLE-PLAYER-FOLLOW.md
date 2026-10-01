# Paused Apple player follows other clients

The baseline player (`layouts/default.vue`, `AudioPlayerContainer.vue`) moves a paused player to progress another session saved for the open media, and refreshes paused local media after a long socket disconnect. The shared Apple player now exposes the same behavior as two root-callable hooks on `ApplePlayback`. They take plain values, not `NativeRealtime` types, so the TV target compiles unchanged.

```swift
// RealtimeChange.progress(itemID, episodeID, session) for the event's account
await playback.followRemoteProgress(account: account, itemID: itemID, episodeID: episodeID, sessionID: session)
// authenticated(resumed: true) after a reconnect, for the signed-in account
await playback.refreshPausedProgress(account: account)
```

Both return whether the player moved. They never report errors: a skipped follow leaves the player and journal exactly as they were.

## Rules

- Only the open item and episode follow. A different item, episode or account returns without a request. An event whose session is this player's stream session or listening record is ignored, in addition to the realtime worker's own echo filtering.
- Playback intent wins. Nothing moves while the player wants playback, is playing, preparing, seeking or closing, or has a queued seek.
- The hook never publishes. Server 2.30 `syncLocalSession` keeps server progress only when it is strictly newer than the incoming session (`PlaybackSessionManager.js`), so syncing a stale paused position first could erase the other device's movement. If the journal holds unacknowledged listening for this account and media, the follow is skipped and the regular sync and recovery own publication.
- Progress comes from `GET /api/me`. A remote position moves the player only if its `lastUpdate` is later than every cached local position for the media (`cachedPosition(newerThan: lastUpdate.nextUp)`).
- After the request, the hook checks again that the account, `authorizationRevision`, `playbackIntent`, session, media and position are unchanged and the journal is still clean. Any local seek, play, sign-in change or new listening wins.
- The move is a normal `seek(autoplay: false)`. It writes the followed position to the durable journal before the regular sync publishes it. It never starts audio.

The pending check lives in `ListeningSync.hasLocalListening`, a read-only journal query. This is the only change outside `ApplePlayback.swift`: the journal's pending state is not otherwise visible to the player.

## Root wiring

Call `followRemoteProgress` for each `RealtimeChange.progress` of the active account, and `refreshPausedProgress` on `authenticated(resumed: true)`. Root owns those call sites and the `NativeRealtime` stream. Because the follow skips while own listening is unacknowledged, an event arriving right after a pause can be skipped. The reconnect refresh, or the next event once sync has acknowledged, will apply it.

## Verification

Run the focused tests with:

```sh
xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme NativeTests -destination 'platform=iOS Simulator,name=Audiobookshelf PlayerFollow QA' CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 -only-testing:NativeTests/PausedProgressFollowTests test
```

`PausedProgressFollowTests` drives the production `ApplePlayback` and journal with a real 20-second WAV through `AdoptionHarness`, against the in-process stub with 2.30 `/api/me` and `/api/session/local-all` shapes. No network port is bound.

- With no-op hooks, four tests failed: no move to the remote position, no reconnect refresh, and no progress request while the user seeked or pressed play.
- An eager-flush version then passed all eight. A ninth test written for the no-publish rule failed against it: the follow posted the pending paused position (`local-all` 5 → 6 requests) and moved over it to 14. This test first passed by accident because its flush joined an already failed shared transfer. Settling the fixture's journal made the failure reproducible.
- With the final implementation, 9/9 passed in five consecutive runs. The full NativeTests suite passed 43/43 (34 existing). Mutations confirmed the guards: removing the journal checks failed three tests, and removing the playback-state guard failed the intent test. The explicit `playbackIntent` comparison is defense in depth, and no current test distinguishes it alone.
- iOS 14 simulator source typechecking of all app sources passed with no warnings. The TV simulator build passed. Builds used the Xcode 27 build-only iOS 15 override; the source minimum remains iOS 14.

The test file is new under `apple/NativeTests`. Regenerating with `xcodegen generate --spec apple/project.yml` adds it to the project. The project file was not changed in this commit.

This is simulator and fixture evidence only. It does not establish physical cross-device acceptance or live-server behavior, and it makes no exactly-once claim.

## Integrated event delivery

Root applied the reviewed realtime consumer patch and forwards current-sign-in progress events, reconnects and user updates to the player hooks in `AudiobookshelfNativeApp`. The event ownership guard runs inside the queued Task, then the hook pins its own authorization and playback intent through the request.

`PausedRealtimeJourney` passed both cases in the combined checkout: remote progress moves the paused player across files to total position 14 without starting audio; reconnection refreshes a missed total position 16. Evidence: `/tmp/abs-root-paused-realtime-green-total.log`, `apple/build-paused-realtime/Logs/Test/Test-AudiobookshelfNative-2026.10.02_03-55-10-+0900.xcresult`. The assertions use `total-elapsed`, because the main elapsed label is chapter-relative by default. The first post-wiring run wrongly asserted total time against the chapter label; its journal and screenshot showed the correct total position and no app workaround was made. Removing just the root event forwarding then failed the corrected remote-progress test (`/tmp/abs-root-paused-realtime-mutation.log`), and the production source was restored exactly. The combined NativeTests suite passed 50/50 (`/tmp/abs-apple-final-wired-stores.log`). Physical acceptance remains open.
