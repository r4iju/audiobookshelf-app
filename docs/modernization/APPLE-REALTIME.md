# Apple realtime parity

Scope: the `upstream-realtime` parity row for iPhone/iPad. Baseline: `plugins/server.js` and its consumers (`layouts/default.vue`, `LazyBookshelf.vue`, `pages/playlist/_id.vue`, `EpisodesTable.vue`). Server semantics come from the local 2.30 source (`server/SocketAuthority.js`, `PlaybackSessionManager.js`, `MeController.js`, `PlaylistController.js`).

## Design

- **One stream per sign-in.** `apple/App/NativeRealtime.swift` owns the only `ServerEvents` connection (the existing Engine.IO 4 / Socket.IO websocket client in TVCore; no proxy or new service). It is keyed by the canonical `AccountIdentity` plus `APIClient.authorizationRevision`, so a switch, sign-out, re-login or credential restore replaces the stream. Token refresh does not, because the revision is unchanged by refresh. The root reconnects on `ConnectionStore.signInRevision`, which changes even when a new sign-in opens the same account.
- **Own echoes dropped.** The server echoes this device's syncs as progress events carrying its session id. The coordinator drops progress events from the local playback session, so visible screens refetch only for other clients' changes.
- **No previous-account events.** A change is published only while its generation is current and `api.credentials` still resolve to the pinned account and revision. `RealtimeChange` additionally rejects payloads addressed to another user: `init` and `user_updated` ids, progress `data.userId`, and playlist `userId`.
- **Typed changes.** `tvos/Core/Sources/TVCore/RealtimeChange.swift` maps the supported server events. It is shared, so the TV can adopt it.

| Server event | Change | Native consumer |
| --- | --- | --- |
| `init` (first) | `authenticated(resumed: false)` | Podcast queue clears a stream rejection and retries saving results |
| `init` after a dropped or restarted stream | `authenticated(resumed: true)` | Catalog reloads in place (or reopens if it had failed), details and groups reload |
| `user_item_progress_updated` from another session | `progress(item, episode, session)` | Catalog refreshes user progress and Continue Listening; matching book details and open group details reload |
| `user_updated` (REST progress, bookmarks, permissions) | `user` | Same as progress, for any item |
| `item_updated`, `items_updated` | `itemsUpdated` | Catalog replaces items in place; matching details reload |
| `item_added`, `items_added` | `itemsAdded(libraryIDs)` | Catalog of that library reloads its first page |
| `item_removed` | `itemRemoved` | Catalog removes the item |
| `playlist_*`, `collection_*` | `group(kind, id, removed)` | Group lists reload; open details reload, or close when removed |
| `episode_download_finished` | `episodeDownloadFinished` | Podcast queue (unchanged behaviour) |

Refreshes are in place. A visible screen keeps its content when a refresh fails and retries on the next change, reconnection or manual refresh. A progress refresh leaves loaded and loading pages alone. A refresh after additions or reconnection returns the catalog to its first page, matching the existing progress-filter refresh. An item updated elsewhere is replaced where it is listed, even if it no longer matches the active filter or sort until the next reload. Queued listening progress is not touched; `ListeningSync` remains the only owner of unsent progress.

## Verification

Commands (local only, owned ports 26765 and 26769, simulator `Audiobookshelf Realtime QA`):

```bash
(cd tvos/Core && swift test)                       # includes RealtimeChangeTests
bash apple/scripts/verify-realtime.sh              # RealtimeJourney against real Socket.IO 4.7.4
ABS_QA_SIMULATOR="Audiobookshelf Realtime iPad QA" bash apple/scripts/verify-realtime.sh
```

The fixture adds `/__fixture__/remote-change`. It mutates server state as another client would and queues the 2.30 event to the affected user's room. It also supports a socket drop that permits the client's own reconnect, plus `/__fixture__/realtime-connections`, which reports open authenticated sockets per user. `configure` restores everything a remote change altered.

Red first:

- `RealtimeChangeTests` (7 cases) failed to compile before `RealtimeChange` existed.
- The first four `RealtimeJourney` cases failed on their behavioural assertions against the unchanged app: Continue Listening, card percentage and open details ignored another client's progress; shelf titles and playlist list/details ignored edits and deletion; a dropped socket refreshed nothing; and the newly selected account's progress never appeared. The account-switch assertion that the old stream closes already held, because the podcast queue closed its own socket. It now guards the single shared stream.
- Review then found that signing in again to the same account left realtime silent until the next foreground. `testSigningInAgainToTheSameAccountKeepsRealtimeUpdates` failed on that before `signInRevision` was added.

Results are recorded in [the handoff](../handoff/APPLE-REALTIME.md).

## Remaining gates

- Physical iPhone/iPad against the live server: a second client (web or TV) changes progress, playlists and item metadata while the app is visible, and the app recovers after Wi-Fi loss and background suspension.
- Events missed while the app is suspended or terminated are covered only by the reconnection refresh of visible screens. Screens opened later load fresh data. No replay exists in server 2.30.
- A stream connects once `api.credentials.userID` is known. Legacy credentials without a stored user id connect after `ConnectionStore.openLibraries` resolves the account (`activeAccount` change). Changes made in the first instant after launch, before the first `init`, are not replayed.
- Baseline `layouts/default.vue` also moves a paused player to another session's position, and its player re-syncs after a long disconnection. `ApplePlayback` is owned by the paused-player worker; see the handoff.
- Changes are not proven against queued unsent progress during reconnection; refreshes only read, and `ListeningSync` is untouched.
- TV adoption of `RealtimeChange` is not part of this slice.
