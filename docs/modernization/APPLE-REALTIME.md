# Apple realtime parity

Scope: the `upstream-realtime` parity row for iPhone/iPad. Baseline: `plugins/server.js` and its consumers (`layouts/default.vue`, `LazyBookshelf.vue`, `pages/playlist/_id.vue`, `EpisodesTable.vue`). Server semantics come from the local 2.30 source (`server/SocketAuthority.js`, `PlaybackSessionManager.js`, `MeController.js`, `PlaylistController.js`).

## Design

- **One stream per sign-in.** `apple/App/NativeRealtime.swift` owns the only `ServerEvents` connection (the existing Engine.IO 4 / Socket.IO websocket client in TVCore; no proxy or new service). It is keyed by the canonical `AccountIdentity` plus `APIClient.authorizationRevision`, so a switch, sign-out, re-login or credential restore replaces the stream. Token refresh does not, because the revision is unchanged by refresh. The root reconnects on `ConnectionStore.signInRevision`, which changes even when a new sign-in opens the same account.
- **Own echoes dropped.** The server echoes this device's syncs as progress events carrying its session id. The coordinator drops progress events from the local playback session, so visible screens refetch only for other clients' changes.
- **No previous-account events.** Every `NativeRealtime.Event` carries the `SignIn` (account and authorization revision) that received it, and is published only while that sign-in is current. `RealtimeChange` additionally rejects payloads addressed to another user: `init` and `user_updated` ids, progress `data.userId`, and playlist `userId`.
- **Ownership reaches the consumers.** `CatalogStore.owns(event)` is true only while the event's sign-in is current and its account is the one the catalog was loaded for, including the server. The catalog, book details and group screens check it before acting on a change and again before publishing results or errors. `APIClient` already discards any single response whose sign-in changed while it was in flight.
- **Typed changes.** `tvos/Core/Sources/TVCore/RealtimeChange.swift` maps the supported server events. It is shared, so the TV can adopt it.

| Server event | Change | Native consumer |
| --- | --- | --- |
| `init`, first or after a dropped or restarted stream | `authenticated` | Catalog reloads in place (or reopens if it had failed), details, item feed and groups reload, the paused player refreshes, and the podcast queue clears a stream rejection and retries saving results |
| `user_item_progress_updated` from another session | `progress(item, episode, session)` | Catalog refreshes user progress and Continue Listening; matching book details and open group details reload |
| `user_updated` (REST progress, bookmarks, permissions) | `user` | Same as progress, for any item |
| `item_updated`, `items_updated` | `itemsUpdated` | Catalog replaces items in place; matching details reload |
| `item_added`, `items_added` | `itemsAdded(libraryIDs)` | Catalog of that library reloads its first page |
| `item_removed` | `itemRemoved` | Catalog removes the item |
| `playlist_*`, `collection_*` | `group(kind, id, removed)` | Group lists reload; open details reload, or close when removed |
| `rss_feed_open`, `rss_feed_closed` for a `libraryItem` | `itemFeed(item, feed or nil)` | The open item's feed action shows the feed or hides it, like `pages/item/_id/index.vue` |
| `episode_download_finished` | `episodeDownloadFinished` | Podcast queue (unchanged behaviour) |

Every `init` resyncs, not only one after a reconnection. Screens load over HTTP before the socket authenticates, and server 2.30 emits only to sockets already in the `authenticated` room and keeps no replay (`SocketAuthority.js`), so a change made between a screen's load and the first `init` would otherwise stay hidden. The cost is one extra read of each visible screen per sign-in or launch. Feed events are broadcast without a user id (`RssFeedManager.js`), so they are accepted for any item the open screen shows. Item actions publish only the latest load's result or error, so the load started on appear cannot overwrite the `init` refresh that overtook it. A feed change received while a load or this device's own open or close is in flight wins over that older response; this device's own successful open or close counts as such a change, so a load that read the item before it keeps its other capabilities but not its feed. Every request still completes its activity and error state.

Refreshes are in place. The catalog owns one realtime refresh at a time; a change arriving during it queues the next, and a queued first-page reload is never downgraded to a progress refresh. A visible screen keeps its content when a refresh fails and retries on the next change, reconnection or manual refresh. Any realtime refresh that runs while the catalog is still on its first load becomes a full reload that supersedes it, because that load may have read the server before the change and there is no content to refresh in place. This covers a library opened after the socket already authenticated. If that reload fails, the catalog shows the failure instead of loading forever. A progress refresh leaves loaded and loading pages alone, except under a progress filter, whose first page reloads because membership follows progress. A refresh after additions or reconnection returns the catalog to its first page, matching the existing progress-filter refresh. Item updates and removals are applied in place and also to every catalog response that was in flight when they arrived, so an older page cannot restore a removed book or stale metadata. Removing a listed book while later pages are unloaded reloads the first page, because server pages are offsets. An item updated elsewhere is replaced where it is listed, even if it no longer matches the active filter or sort until the next reload. Queued listening progress is not touched; `ListeningSync` remains the only owner of unsent progress.

## Verification

Commands (local only, owned ports 26765 and 26769, simulator `Audiobookshelf Realtime QA`):

```bash
(cd tvos/Core && swift test)                       # includes RealtimeChangeTests
xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme NativeTests \
  -destination "platform=iOS Simulator,name=Audiobookshelf Realtime QA" IPHONEOS_DEPLOYMENT_TARGET=15.0 \
  -only-testing:NativeTests/CatalogRealtimeTests test   # production CatalogStore against held responses
bash apple/scripts/verify-realtime.sh              # RealtimeJourney against real Socket.IO 4.7.4
ABS_QA_SIMULATOR="Audiobookshelf Realtime iPad QA" bash apple/scripts/verify-realtime.sh
```

`verify-realtime.sh` serves `apple/scripts/item_actions_fixture.py` on 26769, which adds `/__actions__/remote-feed` (opens or closes a feed elsewhere and queues `rss_feed_open` or `rss_feed_closed`). The Socket.IO proxy adds `/__fixture__/realtime-hold`, which holds authentication so changes land between a screen's load and `init`. The fixture adds `/__fixture__/remote-change`. It mutates server state as another client would and queues the 2.30 event to the affected user's room. It also supports a socket drop that permits the client's own reconnect, plus `/__fixture__/realtime-connections`, which reports open authenticated sockets per user. `configure` restores everything a remote change altered.

Red first:

- `RealtimeChangeTests` (7 cases) failed to compile before `RealtimeChange` existed.
- The first four `RealtimeJourney` cases failed on their behavioural assertions against the unchanged app: Continue Listening, card percentage and open details ignored another client's progress; shelf titles and playlist list/details ignored edits and deletion; a dropped socket refreshed nothing; and the newly selected account's progress never appeared. The account-switch assertion that the old stream closes already held, because the podcast queue closed its own socket. It now guards the single shared stream.
- Review then found that signing in again to the same account left realtime silent until the next foreground. `testSigningInAgainToTheSameAccountKeepsRealtimeUpdates` failed on that before `signInRevision` was added.

- Root review then found ownership and pagination races in the catalog consumer. `CatalogRealtimeTests` drives the production `CatalogStore` against an in-process server that holds chosen responses, and its seven cases failed on behaviour before the fixes:
  - a progress event during a reconnection reload dropped the reload and left paging blocked
  - an older page restored stale metadata
  - an older page restored a removed book and left paging incomplete
  - an earlier sign-in's change was applied
  - another server's equal user id refreshed the catalog
  - another account's change reached a catalog loaded for the first
  - a progress-filtered shelf kept a book whose progress changed
- Opening book details and renaming the book elsewhere showed the rename in details. On return, the shelf still showed the old title: `LibraryItem` equality compares ids only, so the cards skipped redrawing. The extended item journey failed on that before the cards held their visible metadata.

- Feeds and the gap before `init` (base `315183c1`): `testAFeedOpenedOrClosedElsewhereUpdatesTheOpenItem` failed because the open item ignored a feed opened elsewhere. `testChangesBeforeTheFirstInitAppearOnceAuthenticated` failed on the playlist list and Continue Listening, and `testChangesBeforeTheFirstInitAppearOnTheOpenItem` failed on details progress and the feed, because only a resumed `init` refreshed. The Core feed tests and `testAnInitDuringTheFirstLoadThatFailsShowsTheFailure` failed on behaviour before the fix. `testUnsentListeningSurvivesAReconnectionRefresh` is a guard and passed before and after: listening the server refused stays queued through a remote progress event and a reconnection, and is published once the server accepts it.

Results are recorded in [the handoff](../handoff/APPLE-REALTIME.md).

## Remaining gates

- Physical iPhone/iPad against the live server: a second client (web or TV) changes progress, playlists and item metadata while the app is visible, and the app recovers after Wi-Fi loss and background suspension.
- Server 2.30 has no replay. Events missed before the first `init`, while the stream is down or while the app is suspended are covered by the `init` refresh of visible screens. Screens opened later load fresh data. This is proven on simulators with a held synthetic socket, not on a device.
- A stream connects once `api.credentials.userID` is known. Legacy credentials without a stored user id connect after `ConnectionStore.openLibraries` resolves the account (`activeAccount` change).
- Baseline `layouts/default.vue` also moves a paused player to another session's position, and its player re-syncs after a long disconnection. `ApplePlayback` is owned by the paused-player worker; see the handoff.
- Queued unsent listening through a reconnection is proven only against the synthetic fixture on simulators.
- Opening and closing an RSS feed from another client against the live server needs owner approval.
- TV adoption of `RealtimeChange` is not part of this slice.
