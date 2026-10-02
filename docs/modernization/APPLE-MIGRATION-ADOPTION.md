# Native adoption of the legacy migration outcome

Status: implemented on `fork/apple-native-adoption` with simulator unit evidence (see Evidence).
Not complete: physical-device and live-server gates remain open, and listening that cannot be
shown to be on the server exactly once is retained as unconfirmed rather than resolved (see the
end).

`apple/Adoption` turns a committed `MigrationOutcome` (see `APPLE-MIGRATION.md`) into actual native
data: entries in the `NativeDownloads` manifest, `ReadingStore` positions, preview preferences and a
durable, account-scoped queue of unsent legacy listening. It never edits migrator files under
`<root>/Files`, never moves or converts them, and never writes Keychain profiles.

## Interface

```swift
@MainActor final class NativeMigrationAdoption {
    init(downloads: NativeDownloads, reading: ReadingStore, api: APIClient,
         defaults: UserDefaults = .standard,
         directory: URL = NativeMigrationAdoption.directory,   // Application Support/NativeMigrationAdoption
         session: URLSession = .shared)
    var onProgress: ((AdoptionProgress) -> Void)?             // file work: completed of total
    func apply(outcome: MigrationOutcome, migrator: LegacyMigrator) async throws -> AdoptionReport
    func sync() async -> AdoptionSyncReport
}
```

- Call `apply` after the migrator committed (`migrate` or `committedOutcome`). It is idempotent and
  reconciles by content: run it on every launch that has a committed outcome, and after every
  repair, even when the fingerprint is unchanged.
- `apply` reads, checks, links, copies and hashes files in a detached task, so the main actor (UI,
  audio controls) stays free on large libraries; `onProgress` is called on the main actor after
  each entry's file work. That task writes only under the adoption directory (`Staging/apply`,
  `Awaiting`), never at a native download path. Only the main actor moves staged files into
  `NativeDownloads` and publishes to it, `ReadingStore` and the preferences. Cancelling the
  calling task stops the file work between entries; nothing is published then.
- `apply` throws only when the ledger cannot be read or written, or `ReadingStore` cannot be
  written. A download the store refuses is reported on its own row and does not hold back the
  others, the listening queue, settings or reading positions. A retry continues safely.
- Call `sync()` on foreground and after account changes. It only acts for the signed-in account
  and never throws; failures are in `AdoptionSyncReport.failures` and the work stays queued.

`AdoptionReport` is for the import UI:

- `summary: String`: one paragraph that separates downloads ready offline from retained, deferred,
  unresolved and waiting data, and states unsent listening and accounts that need sign-in. It never
  says everything is usable unless it is.
- `issues: [String]`: one line for each artifact that is not natively usable yet, then every module
  issue message.
- Details: `downloads` (status `ready`, `partial`, `waitingForServer`, `keptNative`,
  `removedByUser`, `inProgress`, `deferredFormat`, `unattached`, `unavailable`), `reading`
  (`adopted`, `keptNative`, `deferredFormat`, `invalid`, `unattached`), `settings` (`applied`,
  `keptNative`, `retained`), `listening` (per account: pending and acknowledged sessions, pending
  positions, unconfirmed sessions), `unsendableSessions`, `accountsRequiringSignIn`,
  `moduleIssues` (the outcome's issues, unchanged).

`AdoptionSyncReport` has `sessionsAcknowledged`, `sessionsPending`, `sessionsUnconfirmed`,
`progressSent`, `progressPending`, `downloadsCompleted` and `failures`.

Concurrency contract (state lives on the main actor):

- `sync()` calls that overlap share one run and get the same report; nothing is sent twice.
- `apply` calls run one at a time, in call order.
- `apply` and `sync()` may overlap. Both change the ledger only by reloading it, changing their
  own records and writing it back with no suspension in between, so neither overwrites what the
  other recorded. `apply` never replaces an awaiting record `sync()` resolved, and only adds
  listening records that are absent.
- `apply` plans against the stores as they are and stages files off the main actor. For each
  staged file it records what the native path held when staging began (no file, or that file's
  stamp). Back on the main actor, with no suspension until the manifest is written, it checks
  each entry against the store: an existing entry must still have the generation, state and
  finished parts it was planned with (else it is left as it is, or reported as removed); a new
  entry must still have no entry with its id or item and must not be one the user removed. Each
  path must still hold what it held; a path something else wrote meanwhile keeps that file and
  adoption gives up the part. Only then are the staged files renamed into place and the entries
  published with `publishAdopted`, which checks the same again. A user's Retry or removal, or a
  part the native downloader finished during the file work, is therefore never overwritten.
- `sync()` completes a download that waited for the server the same way: the item is fetched
  and the account checked, the staged files are linked or copied and verified off the main
  actor, then on the main actor, with no suspension, the signed-in account, the store and the
  paths are checked again before the rename and the manifest write.
- The signed-in account is checked before every request, before publishing a completed download
  and after fetching the user. A change stops the run; a session already in flight is
  acknowledged for its own account only if the server accepted it. The rest waits for that
  account.
- Interrupting `apply` after any step (`AdoptionStep`: `planRecorded`, `filesPublished`,
  `manifestWritten`, `ledgerWritten`, `settingsWritten`, `readingWritten`) and running it again
  converges on the uninterrupted result. The ledger records the queued listening, and each staged
  file as pending beside the part's current file, before any file moves (`planRecorded`). Until
  the ledger names the moved file (`ledgerWritten`), both files count as adoption's: after a stop
  the part is whichever of the two is at the path, so a damaged part is never handed to the
  native app and a moved one is never mistaken for the native app's. A part whose rename fails
  leaves `finished` unless its current file was intact, so a damaged part is never published as
  ready; the next `apply` places it again. Provenance lives in the native manifest itself: `publishAdopted` adds
  the ids of adopted entries to the manifest's `adopted` list in the same atomic write as the
  entries, and `NativeDownloads` keeps that list when the user removes an entry. An entry absent
  from the manifest but listed there was removed by the user and is never added again; there is
  no window between two writes in which a stop could turn a removal into a re-add.

Root keeps showing accounts that need sign-in and quarantined rows itself. Adoption attaches data
to `AccountIdentity(server, userID)` only; data of an account that is not signed in becomes visible
once that exact account signs in. Quarantined (`accountMismatch`) and unscoped rows stay in the
outcome and are never attached.

## Contract decisions

Evidence for the server behaviour below is the installed server 2.30.0 source, read from a
throwaway container with no network: `managers/PlaybackSessionManager.js` (`syncLocalSession`,
`play_local_` remap at lines 153-162), `controllers/SessionController.js` (`sync`),
`controllers/MeController.js` (`getMediaProgress`, listening-sessions paging, 0-based),
`models/MediaProgress.js` (`applyProgressUpdate`, lines 186-256) and
`objects/PlaybackSession.js` (`date`/`dayOfWeek` derived from `updatedAt` when absent, lines 163-166).

- `local-all` with an existing session id **replaces** `timeListening`; `/api/session/<id>/sync`
  **adds** `timeListened` and only works while the session is open in server memory (404 otherwise).
  `local-all` updates progress only when the session's `updatedAt` is not older than the progress;
  `/sync` always overwrites progress.
- Downloaded-media sessions (`sessionTotal`) are sent through `local-all` one per request with their
  total, legacy id and `updatedAt`, so retrying is idempotent and older listening never overwrites
  newer progress.
- Streamed sessions (`sinceLastSync`) are never sent through `local-all` as a delta (the server would
  replace its total with the delta and lose listening). The invariant is that their unsent
  listening reaches the server at most once and never replaces listening the device does not
  know about; when that cannot be shown, the session is kept as unconfirmed instead:
  - open session (`GET /api/session/<id>` 200): adoption records that it is attempting, then
    `/sync` with the delta and, when the server's progress is newer than the legacy row, the
    server's own position. Only a 200 answer acknowledges it. A 404 (not open after all), or an
    error after which the request certainly did not leave the device (no connection, host not
    found, TLS failure, sign-in or account change), clears the attempt and the session is tried
    again. Any other outcome (lost answer, another status, the app stopping mid-request) leaves it
    unconfirmed: the server's total grows for every device listening to that session, so a larger
    total does not show whether this addition landed, and sending again could count it twice.
  - closed or unknown (404): read the stored row from `GET /api/me/item/listening-sessions/...`.
    An existing row updates unconditionally through `local-all` (total, position and time), so
    a row whose `updatedAt` is later than the legacy session's has history this device lacks
    (2.30 stamps each `/sync` with the server clock, `objects/PlaybackSession.js`
    `addListeningTime`) and the session becomes unconfirmed. Otherwise record the row (total `S`,
    `currentTime`, `updatedAt`) and `S + delta` once, then `local-all` with `S + delta`. Every
    retry reads the row again and resends only while it is exactly as read, or exactly as sent
    (`S + delta` with the legacy position and time; replacing it with itself is idempotent). Any
    other state, including the same total with a later position or time, means another writer
    changed it, and the session becomes unconfirmed rather than overwriting it.
- Unconfirmed sessions stay in the ledger with their reason, are never sent again automatically,
  and are counted separately from pending ones (`AdoptionReport.Listening.unconfirmedSessions`,
  `AdoptionSyncReport.sessionsUnconfirmed`, a `summary` sentence and an `issues` line). Resolving
  one needs a decision this module does not make.
- A session is acknowledged only when the server accepted that exact payload (`success: true` for
  that id, or `/sync` 200), or holds exactly it (below). Everything else stays queued with its
  error, or unconfirmed.
- Acknowledgements are version scoped: a session is marked delivered, and a position resolved,
  only if the ledger record still holds the exact payload that was sent.
- Sessions carry no `date` or `dayOfWeek`: like the legacy client, the server derives both from
  `updatedAt`, so no client calendar or time zone is involved. A session or position whose time is
  not finite, positive and within JavaScript's `Date` range (8.64e15 ms) is kept, not sent; a body
  `JSONSerialization` cannot encode is refused before it is built.
- Downloaded-media sessions with legacy `play_local_` ids: the legacy app posted them while they
  were open, and the server stored each under a random id of its own (the remap lives in memory
  only), keeping `startedAt`. The session is sent under a stable UUID derived from the legacy id,
  so retries, even across server restarts, stay on one row. Before every attempt adoption pages
  through the item's listening sessions and looks for the row holding it: one with the stable id
  (an earlier attempt here), else a single row with the same `startedAt` (the legacy app's post).
  The server stores the posted `timeListening`, `currentTime` and `updatedAt` as sent
  (`syncLocalSession` and `models/PlaybackSession.js` `updateFromOld`, `silent: true`), so:
  - a row with exactly this session's total and position, and no later `updatedAt`, already holds
    it: acknowledged without sending;
  - a row with a larger total or a later `updatedAt` has listening this device does not know
    about: nothing is sent (`local-all` would replace it and could rewind its position) and the
    session is kept as unconfirmed;
  - a row with less, and not later, is the legacy app's earlier post: the whole total replaces it
    under that row's id;
  - no row: sent under the stable id.
  Two or more candidate rows are not guessed between: the session stays queued with that reason.
- Positions: `GET /api/me/progress/...` is read right before each change, not taken from an older
  snapshot. A legacy row is sent (`PATCH` with `lastUpdate`) only when the server has nothing
  newer; older ones are resolved as superseded. If the server has the item finished and the
  legacy row is unfinished, `{isFinished: false, lastUpdate: legacy - 1 ms}` is sent first,
  because the server keeps a finished item finished and un-finishing resets its position. Stamped
  just before the legacy row, that reset never looks newer than it: after a failed second request
  or a lost response the next sync still sends the position, while listening anywhere after the
  reset is newer and wins. Reading locations go through `ReadingStore`'s own pending sync.
- An open streamed session's `/sync` carries the server's current position when that is newer
  than the legacy row, read right before the request.

## How data is carried over

- Downloads: each migrated book becomes one native entry (tracks plus a PDF or EPUB ebook); each
  podcast episode with a track becomes its own entry. Entry ids are UUIDs derived from the
  account and legacy item, so a rerun finds its own entries. Files are hard links to the
  migrator's adopted files when the volume allows, else copies, placed under a temporary
  `adopting-` name and renamed into place. A copy is always verified by SHA-256; a link is trusted
  without reading only while the file keeps the stamp (device, inode, size, modification time) it
  had right after the migrator confirmed its content, and rehashed otherwise. Empty files are not
  adopted. Removing a native download unlinks only the native name. Missing parts keep their
  server track so Retry downloads only those.
- Placement: files are staged under `Staging/apply` (or `Staging/sync`) and renamed into the native
  path on the main actor only after the checks above; staging is cleared before and after each run.
  A staged file's content digest and stamp become the part's ownership record only once its rename
  succeeded (see the concurrency contract).
- Ownership: the ledger keeps, per adopted part, its content digest and the placed file's stamp.
  On every `apply` a part that is still that file with that stamp is intact. The same file with
  another stamp is rehashed: changed bytes mean damage, and the part is placed again from an
  intact migrated source or else marked missing for Retry. A missing part is placed again the
  same way. A different file at the path was written by the native app (for example by Retry) and
  is no longer adoption's: it is left as it is and never replaced.
- Native wins: another native entry for the same account, item and episode is kept
  (`keptNative`); an adopted entry the user removed, before or during an import, is not added
  again (`removedByUser`, from the manifest's provenance); an entry the native app is downloading
  is left alone (`inProgress`); an entry the native app changed during the import is left as it
  is. A repair adds parts that became
  available and replaces a carried-over part only when it is still adoption's file and its
  migrated content changed.
- Deferred formats (MOBI, AZW3, CBZ, CBR) and their reader positions stay in the outcome,
  unconverted, reported as `deferredFormat`.
- Supplementary PDFs and EPUBs, and finished parts of downloads the upgrade interrupted, need the
  server's file ids. `apply` stages them under `Awaiting/` (links or verified copies) and `sync()`
  publishes them once the server's item matches them by filename.
- Reading: the newest legacy row of a book wins. PDF pages and EPUB CFIs go to `ReadingStore` as
  pending positions with the legacy
  `lastUpdate` and revision `legacy:<id>`, only where the book has no native position yet.
  `ReadingStore.sync` then publishes them unless the server has a newer one.
- Settings, only where the native key is unset (`previewDownloadsNetwork` also counts the older
  `previewDownloadCellular`): skip intervals (5, 10, 15, 30, 45 or 60 s), haptics, cellular
  policies, rewind after pause, media-control seeking, sleep fade, playback speed (0.5 to 10),
  theme, list layout, EPUB reader preferences (all nine native keys, each range checked) and the
  device id. Everything else is listed as retained and stays in the outcome, including
  `languageCode` (see the handoff).
- Player display, from the legacy player's `playerSettings` JSON in `preferences`
  (`components/app/AudioPlayer.vue`): `useChapterTrack` to `previewChapterTrack`, `useTotalTrack`
  to `previewTotalTrack`, `scaleElapsedTimeBySpeed` to `previewScaleElapsedBySpeed`, `lockUi` to
  `previewLockPlayerControls`, each only where the native key is unset. The JSON is the choice
  the user made in the player. The Realm `settings.player.chapterTrack` is only the copy the
  legacy player handed to the iOS player, so it is used only when the JSON has no valid
  `useChapterTrack`; otherwise it is listed as retained. Only JSON booleans are used; other values
  and unknown fields are retained as `playerSettings.<field>`, and JSON that cannot be read as
  `playerSettings`. A choice that would leave the chapter and total tracks both off, counting
  native values already set, is not written and is retained; the legacy player never allows that.
- Running services: the two network policies are written to the standard defaults and announced
  through `AppleNetworkPolicy.changed` with the key, as the settings screen does, so
  `NativeDownloads` supersedes queued work and resets consent, and `ApplePlayback` revokes stream
  consent. With injected defaults other than `UserDefaults.standard` (tests) nothing is announced,
  because no running service reads them. The other keys are only written; services that read them
  once at launch do not change until root sets them (see the handoff).

## Evidence

Unit tests in `apple/NativeTests` (scheme `NativeTests`, no host app) use the production
`LegacyMigrator`, a synthetic legacy installation exported as an archive (real WAV and PDF files),
the real `NativeDownloads` and `ReadingStore` on private storage, and an in-process stub with the
2.30 request and response shapes. They never read owner data, Keychain items or real tokens.

Every test in the suite was observed failing before the behaviour it covers was implemented.
Tests that were not are no longer in it (see below).

- `50cf9887`: 14 tests written against the published stub interface, RED with 79 failures.
- Review round 1 (in `a49f1e9e`), each run RED against the earlier implementation first (logs
  `abs-adoption-review-red*.log`): one unusable download blocking the import; a stop after the
  manifest turning into a re-add after removal; a part the native app wrote again being dropped;
  a missing adopted copy and a copy damaged in place left as ready while the source was intact;
  the summary for accounts not signed in; a `play_local_` session the server already holds; a
  reopened position lost after a failed update or a lost response.
- Review round 2 (this change), RED first (log `abs-adoption-r2-red-saved.log`, 19 failures in 8
  tests), then GREEN:
  - `testARemovalOrANativeFileArrivingWhileAnImportPlacesFilesIsNeverOverwritten`: the user
    removes one download, and the native downloader writes a part of another, while the import
    works off the main actor. RED: a file was placed into the removed entry's folder and the
    native file was overwritten.
  - `testADownloadRemovedAfterAnInterruptedImportIsNotAddedAgain`: unchanged, but
    `manifestWritten` now fires right after the actual manifest write, before the ledger write.
    RED: the removed entry was added again.
  - `testAPostedSessionTheServerHoldsWithMoreOrNewerListeningIsNotReplaced`: rows with a larger
    total, a later `updatedAt` and position, and exactly the same session. RED: all three were
    replaced through `local-all`.
  - `testAStreamedSessionStillOpenOnTheServerGetsItsUnsentListeningAddedAtMostOnce` (replaces
    the earlier open-session test, which accepted a grown total as proof): RED, the lost `/sync`
    was acknowledged on the next sync.
  - `testAStreamedSessionTheServerClosedIsNotOverwrittenOnceSomethingElseChangedIt`: RED, the
    total another writer set was replaced twice more.
  - `testAStreamedSessionTheServerClosedIsSentAsItsStoredTotalPlusTheUnsentListening`: its request
    count now expects the row to be read before every attempt. RED: read once.
  - `testALegacyNetworkSettingReachesTheRunningDownloadsThroughTheirChangeNotice`: production
    boundary (standard defaults, saved and restored around the test). RED: the queued download
    kept the old policy and generation.
  - `testAStagedDownloadIsPlacedOffTheMainActor`: RED, the staged PDF was placed on the main
    thread.
- Removed from the suite because they were written with or after the code they cover, or were
  only RED with a broken fixture: the off-main progress test of the first async `apply`, the two
  concurrency tests (overlapping syncs; account switch during a sync), the session without a
  usable time, the `date`/`dayOfWeek` assertions, the newest of several reading rows, a copy
  damaged together with its source, a source changed after its check, and the position compared
  at send time. The behaviour stays implemented; for those, the evidence is the manual
  verification below, not a test.
- Manual local verification (mutations, each run once against the tests named, then reverted;
  not part of the suite): first round: no verification after a link, a native-written part
  treated as damaged, no `play_local_` lookup, the reopen without `lastUpdate`, oldest reading
  row first, removing `sync()` coalescing, a stale ledger snapshot written at the end of a sync,
  no account check before requests. This round: no check that a path is still empty, no
  provenance check, no change notice, ignoring a later `updatedAt`, resending a changed closed
  total, each failing its test. Ignoring the recorded `/sync` attempt is not caught by any test:
  the lost answer is now resolved on the spot, so the marker only matters if the app stops
  during the request, which no test simulates.
- Review round 3, RED first, then GREEN:
  - `testARepairThatCannotBeMovedIntoPlaceIsLeftForRetryAndRepairedLater`: a damaged part whose
    repair cannot be renamed into place (the entry's folder refuses new names). RED (log
    `abs-adoption-r3-red-saved.log`): the entry was published ready with the damaged bytes, and
    the next `apply` treated the damaged file as the native app's and never repaired it.
  - `testAnImportStoppedBeforeARepairMovedIntoPlaceRepairsItNextTime`: a stop at the new
    `planRecorded` step, between the ledger write and the rename. RED (same log): the damaged
    part was never repaired.
  - `testAStreamedSessionTheServerClosedKeepsLaterPositionsAndTimesOfItsRow`: a lost first
    `local-all` after which another writer moves the row to the same total with a later position
    and time, and a row written after the legacy session. RED (log
    `abs-adoption-r3-red-closed.log`): both rows were replaced, the later one on every attempt.
    After the fix, one assertion still failed because the fixture's `600` was an `Int` in a
    `[String: Any]`; it was changed to `600.0`, the value the RED run had shown replaced.
  - Manual mutations, each failing its test: a failed rename keeping a part whenever a file is
    at the path; recording the staged stamp before the rename; comparing only totals of the
    closed row; no check of a later first-read row. Not caught by any test: a stop after the
    rename but before `ledgerWritten`, which the pending record covers, is not simulated.
- Round 4 (player display settings), RED first, then GREEN:
  - `testLegacyPlayerDisplayChoicesBecomeNativeOnlyWhereUnsetAndValid`: a JSON chapter choice
    against a different Realm copy, an explicit native `previewLockPlayerControls`, an unknown
    field; non-boolean values with a native total track already off; unreadable JSON with only the
    Realm copy. RED (log `abs-adoption-r4-red-saved.log`): 11 failures, nothing was mapped.
  - The first GREEN run crashed the test process ("Fatal access conflict detected"): the mapping
    took the report `inout` while the `offer` closure it was given also wrote to it. It now
    returns its choices and retained names to the caller, as the EPUB preferences do.
  - Manual mutations, each failing the test: the Realm copy winning over the JSON; accepting any
    JSON number as a boolean; no both-tracks-off check; that check ignoring native values.
- Final run: `NativeTests`, 31 tests, 0 failures, on the "Audiobookshelf Adoption QA" simulator
  (iOS 27, build-only `IPHONEOS_DEPLOYMENT_TARGET=15.0`). App target `AudiobookshelfNative`
  builds. The adoption sources, both native stores, Playback, TVCore and the migration core
  typecheck for `arm64-apple-ios14.0-simulator`.

## Remaining gates

1. Pending sessions against a live 2.30 server (synthetic account) for each path, including a
   server restart between the legacy app's last `/sync` and adoption.
2. Physical device: adopted audio plays offline, PDF reopens on the same page, the native removal of
   an adopted download leaves the migrator file.
3. Route 2 with the legacy app still in use: the legacy app keeps its rows and may send them again
   (`local-all` replace), which the native app cannot prevent.
4. Open by design, each retained and reported rather than resolved:
   - Unconfirmed sessions (above) wait for a decision; nothing sends them.
   - A `play_local_` session matching more than one server row stays queued with that reason.
   - A part damaged in place together with its migrated source (one file under two names, where
     links are used) cannot be repaired from that source; it is marked for Retry, and the
     migrator's own check reports the source.
   - Staged supplementary files and interrupted parts wait until the server's item lists a file
     with the same name.
   - Ledgers written by `a49f1e9e` recorded publication in the ledger; that field is no longer
     read. Discard integration ledgers and manifests made with that build.

## Handoff to root

- `await apply(outcome:migrator:)` after `migrate` or `committedOutcome`, on every launch that
  has a committed outcome and after every repair. Show `summary` and `issues`; `onProgress` can
  drive a progress view. The call can be cancelled with its task.
- Call `sync()` on foreground and after sign-in or account changes. It is safe to call while
  `apply` or another `sync()` is in progress.
- `NativeMigrationAdoption` takes the app's `NativeDownloads`, `ReadingStore` and `APIClient`;
  `defaults`, `directory` and `session` have production defaults. Keep `defaults` as
  `UserDefaults.standard` in the app, or the network policies are not announced.
  `previewLibrary` is not written (root's migrated-connection flow owns it).
- API changes since `a49f1e9e`: `AdoptionStep` gained `planRecorded` and `ledgerWritten`, and `manifestWritten` now
  fires right after the manifest write; `AdoptionReport.Listening.unconfirmedSessions`;
  `AdoptionSyncReport.sessionsUnconfirmed`; `beforePlacing` (test seam) now receives the native
  path; `NativeDownloads.adoptedIDs` (read only).
- Running playback: `ApplePlayback` copies these keys at init and adoption does not update the
  running instance. After `apply`, for each key in `report.settings.applied`, set the running
  player's property to the stored value (each property's `didSet` writes the same value back and
  updates the remote commands where needed): `previewSkipForward` to `forwardInterval`,
  `previewSkipBackward` to `backwardInterval`, `previewResumeRewind` to `rewindAfterPause`,
  `previewMediaSeeking` to `allowMediaSeeking`, `previewSleepFade` to `fadeSleepTimer`. For
  `previewPlaybackSpeed`, set `speed` (a `Float`) and call `changeSpeed()`, which applies the rate;
  `speed` has no `didSet`. `previewTheme` and `previewListLayout` are read through `@AppStorage`,
  and `previewHaptic` on every impact, so they update by themselves. `previewEPUBPreferences` is read when the EPUB reader opens (a reader
  open during the import keeps its own and writes it back). `nativeDeviceID` is read when needed.
- Player display: adoption writes `previewChapterTrack`, `previewTotalTrack`,
  `previewScaleElapsedBySpeed` and `previewLockPlayerControls` (see "How data is carried over")
  and does not touch `ApplePlayback` or presentation. For each of these keys in
  `report.settings.applied`, root applies the runtime setter (for `previewChapterTrack`, the
  running player's chapter track) the same way as the keys above, for any of them the running
  app reads only once.
- Language: `languageCode` stays retained in the outcome (`MigratedSettings.device`). Once
  presentation is integrated, root calls `NativeLanguage.adoptLegacy(settings.device?.languageCode)`
  after `apply`; it writes `previewLanguage` only when that key is absent, for any supported legacy
  code (`en-us` included), and ignores unknown codes, so an explicit native choice is never
  overwritten. Adoption keeps no copy of that rule.
