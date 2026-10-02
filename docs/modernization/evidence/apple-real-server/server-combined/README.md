# Apple native cases against the combined server candidate

The two reviewed 2.30.0 server candidates together, Apple's user-cache patch (`../server-usercache/`) then Android's
first-progress patch (`../../android-real-server/server-first-progress/`), in the owned diagnostic container only. Only the
Apple cases the two patches affect are run, against a freshly seeded synthetic library:

| Case | Why it is affected | Exit |
|------|--------------------|------|
| `test1` stream | its local-session sync creates the book's first progress, the create branch the Android patch changes | 0 |
| `test4a` download | the offline finish needs the download | 0 |
| `test4d` finish offline, server stopped | from `test1`'s unfinished 37.4 s position to the end | 0 |
| `test4e` finish reconnect | publishes the finish to the existing row right after a server start, the user-cache race | 0 |
| `migration` | its downloaded Volume 01 session creates first progress | 0 |

`run-combined-native.sh` exited 0. Each case's own `xcodebuild` status is in `combined-native-results.txt`.

What the server shows (`combined-native-server-long-tide.txt`, `combined-native-migration-rows.txt`):

- The Long Tide's first row is created by `test1` and now takes the session's `lastUpdate` ("Manually setting updatedAt"
  right after "Creating new media progress"). The `3ef58609`-only run's create has no such line
  (`../server-usercache/native-candidate-3ef58609-test1-tested.txt`).
- The finish updates that row from 37.428 s to 90.2008 s, finished, and the server returns it finished after the
  reconnect and after a further restart.
- The migration's local Volume 01 session (3.5 s of 4.08 s) creates its first row, and the create branch now marks it
  finished (0.58 s remaining). On the pinned server the created row would stay unfinished. The adoption probe checks
  the uploaded sessions and positions, not the finished flag, and passed unchanged (`local=3/3.5`).

A single native pass does not show the user-cache race was hit in this run; the seam checks and race runs are the proof
of each patch. The first finished row created by an offline session is covered by the Android track's checks, so no
Apple case was added for it. Nothing here is deployed: the owner's server is unchanged and the finish-sync gate stays open.
