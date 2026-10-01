# Apple legacy migration (issues #23, #24)

Status: migration module implemented and verified against synthetic fixtures. Not wired into the
native target. Apple readiness is **not** complete; the physical gates at the end remain open.

This document is the integration handoff for the Apple coordinator, who owns `apple/App`,
`apple/Playback`, `apple/project.yml` and `tvos/Core`. Nothing in those paths was edited.

## What it preserves

From a legacy Capacitor/Realm installation (Realm 10.54.6, schema 21):

| Legacy data | Migrated as |
| --- | --- |
| `ServerConnectionConfig` rows, active index | `MigratedAccount` per canonical server and user (duplicates merged, active one marked) |
| `ServerConnectionConfig.token`, Keychain `AudiobookshelfRefreshTokens` / `refresh_token_<id>` | `LegacyAccountSecret`, handed only to `MigrationSecretSink.adopt`; never written to disk by the module |
| `DeviceSettings`, `PlayerSettings`, Capacitor Preferences (`CapacitorStorage.*`, allowlisted) | `MigratedSettings` |
| WebView `ereaderSettings`, `ebookLocations-<id>`, `absDeviceId` (allowlisted; archives leave out `absDeviceId`) | `MigratedSettings.webStorage` |
| `LocalLibraryItem` and every one of its `LocalFile`s (audio, PDF, EPUB, MOBI, AZW3, CBZ, CBR, covers, podcast episodes, supplementary files) | Hard link or verified copy under `<root>/Files/<account digest>/<item digest>/<legacy path digest>/<file name>`; `MigratedDownload` with tracks, chapters, ebook, episodes, a `files` record of every legacy file with its role (`track`, `episodeTrack`, `ebook`, `cover`, `supplementary`) and the unchanged credential-free `legacyItem` (full metadata, tags, `isInvalid`, episode details) |
| `LocalMediaProgress` (audio position, finished state, `ebookLocation`, `ebookProgress`) | `MigratedProgress`, with `MigratedReadingLocation` (`page` for PDF/CBZ/CBR, `cfi` for EPUB, `opaque` for MOBI/AZW3; the raw legacy value is always kept) |
| `PlaybackSession` rows (unsynced listening), with chapters, media metadata and cover path | `MigratedSession` with `sessionTotal` (local playback) or `sinceLastSync` (streamed) semantics |
| `DownloadItem` rows (interrupted downloads) and their `DownloadItemPart`s | `MigratedInterruptedDownload` plus a `downloadInterrupted` issue; parts that finished and were moved into Documents are adopted, so they are not downloaded again |

Not read, deliberately: `DownloadItemPart.uri` (the legacy downloader put the access token in
its query string), `LogEntry` (diagnostics), the server caches `LibraryItem`, `User` and embedded
`MediaProgress`, `DownloadItem.media` (a server copy of the item), and `LocalPodcastEpisode`
(declared in the legacy schema but never written by the legacy app).

No file is converted, re-encoded or deleted. Nothing needs to be downloaded again unless the legacy
file itself is missing or damaged, and those cases are listed as issues.

Unresolved data is never dropped. It is kept in the outcome and listed in `MigrationOutcome.issues`
with a plain-language message: `reauthenticationRequired`, `fileMissing`, `fileIncomplete`,
`fileCorrupt`, `unsafePath`, `unscopedData`, `accountMismatch`, `invalidReadingLocation`,
`unreadableConnection`, `downloadInterrupted`.

## Migration boundary

The preview bundle `com.forkzed.audiobookshelf.native.preview` cannot read the legacy
`com.forkzed.audiobookshelf` sandbox, Keychain or WebView storage. The legacy `Info.plist` has no
`UIFileSharingEnabled`, so the Files app cannot reach legacy Documents either. Two supported routes:

1. **In-place upgrade (compatible identity).** The native app ships under the legacy bundle
   identifier, team and Keychain access group. `LegacyInstallation.source(...)` reads its own
   `Documents/default.realm` (through a private copy), Documents files, `CapacitorStorage.*`
   UserDefaults and the legacy refresh tokens. Credentials are adopted through the sink.
2. **Export archive (separate identity, such as the preview).** The legacy app runs
   `LegacyArchiveExporter.export(...)`, which writes a credential-free directory archive. The user
   moves it with the Files app. The native app opens it with `LegacyArchive.open(_:)`. Every
   account comes back as `reauthenticationRequired`; the user signs in again, and the migrated data
   becomes usable once the same server user is signed in. The WebView `device` blob and
   `refresh_token_*` entries are excluded from the archive.

There is no automatic cross-sandbox import.

## Module layout

```
apple/Migration/
  Package.swift                     LegacyMigration (Foundation + CryptoKit only), iOS 14, macOS 12
  Sources/LegacyMigration/          snapshot, plan, migrator, archive, outcome
  Tests/LegacyMigrationTests/       37 tests, synthetic Documents tree and fault-injecting file system
  LegacyRealm/Package.swift         LegacyRealmExport (RealmSwift 10.54.6 exact)
  LegacyRealm/Sources/...           schema-21 mirror classes, Realm reader, installation source,
                                    archive exporter, read-only legacy Keychain reader
  LegacyRealm/Tests/...             7 tests against Realm files written with the mirror schema
  scripts/prepare-realm-core.sh     local prebuilt realm-core mirror (see Build)
```

The mirror classes keep the legacy Realm class names through `_realmObjectName()` and opt out of
the default schema, so they cannot collide with any other Realm schema in either app.

## Migrator contract

`LegacyMigrator(root:)`, with `root` = `<Application Support>/LegacyMigration`:

- `preflight(source)` writes nothing. It returns accounts, adoptable files, required bytes,
  available capacity and the issues the migration would report.
- `migrate(source, secrets:)` stages under `root/Staging`, records progress in `root/state.json`
  (atomic writes), verifies every adopted file by SHA-256 against its source and commits by writing
  `root/outcome.json` and then the committed journal. Staging is removed after commit.
- Retrying after interruption resumes; files already staged with a matching hash are kept.
  Credentials are adopted once and recorded in the journal.
- A committed migration returns the same outcome on every later call after verifying every adopted
  file by SHA-256. A deleted or replaced adopted file is repaired from the untouched source. A file
  whose source no longer matches the digest it was committed with (for example changed in place
  through a hard link) is reported `fileCorrupt` and dropped from the outcome instead of being
  adopted again; this holds when the repair itself is interrupted and resumed. An adopted file
  whose legacy original is gone but whose adopted copy still has its committed content is kept.
  A repair never uncommits: a failed repair leaves the migration committed to its source and
  reported damaged.
- A different legacy source after commit throws `differentSourceAlreadyCommitted`. This holds when
  `state.json` is lost or unreadable: a readable `outcome.json` is then the commit record, only the
  same source continues (credentials it recorded as adopted are not adopted again), and records
  that cannot be read are moved aside, never deleted.
- Every committed file, whether read at launch, handed out or checked by a repair, must be a
  regular file inside `<root>/Files` reached through real directories only: a committed path that
  is absolute or holds `.`, `..` or empty components, a symbolic link at the file or at any
  directory above it, or anything other than a regular file is damage, even when it leads to
  matching bytes. A repair removes such a link (never what it points at) and adopts the file
  again from the legacy source.
- `committedOutcome()` is the launch-time read. It checks that journal and outcome agree and that
  every adopted file has its committed size and SHA-256. Content is rehashed unless the file's
  stamp (device, inode, size, modification and change time, kept in `verified.json`) is unchanged
  since its content was last confirmed: writing content moves the change time, which cannot be
  set back, and replacing a file changes its inode, so a same-size change is always rehashed and
  caught. A hash only counts when the file's stamp is the same before and after reading and the
  path still names that file afterwards, so a write landing behind the read position during
  hashing is reported, never recorded as verified. The first check after a migration hashes everything; later launches only stat. It
  returns nil when nothing was committed and throws `committedMigrationDamaged` when the record
  no longer holds; the app then runs `migrate` with the source to repair. `migrate` itself always
  rehashes. If the source is gone (an archive the user deleted),
  ask for a new export: the same legacy data repairs, changed legacy data is refused, and starting
  over means deleting `root` (an explicit user action; the legacy data is untouched).
- Destinations are `<account digest>/<digest of the legacy item or download id>/<digest of the
  legacy path>/<file name>`. Legacy identifiers and directory names never become path components,
  legacy paths are rejected if absolute or if they contain `.`, `..` or empty components, and no
  destination is assigned twice, compared case-insensitively. Archives store each file the same
  way (`files/<legacy path digest>/<file name>`, mapped by `storedPaths` in `archive.json`), so
  paths differing only by case survive export to a case-insensitive volume.
- Ownership: every item, progress row, session and interrupted download must corroborate the
  connection it was saved under. When the row's own recorded user or server differs from that
  connection's, the row is quarantined (`account` nil, `accountMismatch`) and kept, never
  attributed to the connection's current user. The legacy app updates a connection's address and
  user in place under the same id, so data from before a server move is quarantined rather than
  guessed. A matching user id alone does not prove the same server: early Audiobookshelf servers
  gave the root user the literal id `root`. Decision for the coordinator: offer a user-confirmed
  "attach to this account" action for quarantined rows (their legacy records are in the outcome:
  `legacyItem`, `MigratedProgress.legacyID`, `MigratedSession.session`), rather than attaching
  automatically.
- The source fingerprint covers the whole credential-free snapshot. A repair therefore needs the
  same legacy data; if legacy rows changed in between (or a caller passes different WebView
  storage), the repair is refused as a different source. Recovery is then a new export plus
  deleting `root`, an explicit user action.
- A corrupt journal is moved aside (`state.corrupt-<timestamp>-<id>.json`) and the migration
  restarts from the untouched legacy source.
- Copy fallback checks free space before copying (`insufficientSpace`).
- Schema other than 21 throws `unsupportedLegacySchema` and touches nothing. An unreadable
  database throws `legacyDatabaseUnreadable`.
- `committedOutcome()` and `fileURL(for: MigratedFile)` are the read side for the app.
  `fileURL(for:)` applies the same check to the one file and throws `committedMigrationDamaged`
  instead of returning a path to a missing, changed, linked or escaping file. Call it right before
  each use rather than caching the URL; the check cannot stop a process that can already write
  the app's container from swapping the file between the check and the open.

The legacy installation is never modified: the Realm is read from a copy, files are linked or
copied, Keychain items and UserDefaults are read only. The Realm work copy holds access tokens;
it is deleted after reading, and copies left by an interrupted read are deleted by the next read.

Rollback. Route 2 keeps both apps installed, so the legacy app stays usable unchanged. Route 1
replaces the legacy binary, but its Realm, Documents files, UserDefaults and Keychain items are
left as they were, so reinstalling the legacy build restores it with its pre-upgrade data.
Listening and downloads made in the native app after the upgrade are not visible to the restored
legacy app (except through the server). Story-60 ("current app remains available") is therefore
met by route 2 only; route 1 must not ship to the audience until the rollback reinstall is proven
(gate 8).

Hard links share storage with the legacy file. Neither app modifies downloaded media in place, so
this is safe, but deleting a download in the native app must remove only the native link. Files
under `<root>/Files` belong to the migrator: link or copy them into native storage, never move or
modify them, or `committedOutcome()` reports the migration damaged.
Legacy download folders are excluded from backup (`isExcludedFromBackup`); the coordinator should
apply the same flag to `<root>/Files` so backup behaviour is unchanged.

## Build

### Core module (no dependencies)

```
cd apple/Migration && swift test
```

To compile it into the native target, add to `apple/project.yml` under the
`AudiobookshelfNative` target's `sources`:

```yaml
      - path: Migration/Sources/LegacyMigration
```

The core is plain Swift; it compiles into the app module the same way `tvos/Core/Sources/TVCore`
does. Deployment target stays iOS 14.0 (the Xcode 27 simulator override to 15 does not change
the audience).

### Realm adapter

RealmSwift 10.54.6 needs realm-core 14.14.0, which no longer compiles from source with Xcode 27's
libc++. `scripts/prepare-realm-core.sh` wraps Realm's own prebuilt `realm-monorepo.xcframework`
(the binary the legacy CocoaPods install already uses, taken from the local CocoaPods cache or
`REALM_CORE_XCFRAMEWORK`) as a local `realm-core` package tagged 14.14.0, and sets a SwiftPM mirror
for `LegacyRealm` only. It downloads nothing unless `ABS_REALM_CORE_DOWNLOAD=1` is set explicitly.

```
apple/Migration/scripts/prepare-realm-core.sh
cd apple/Migration/LegacyRealm && swift test
```

`Vendor/`, `.build/`, `.swiftpm/` and `LegacyRealm/Package.resolved` are ignored; the mirror's
commit hash is machine-specific.

The adapter is needed only by a build that reads a legacy installation in place (route 1) or by
the legacy app's export (route 2). The preview app importing an archive needs only the core.
For route 1, add to `project.yml`:

```yaml
packages:
  RealmSwift:
    url: https://github.com/realm/realm-swift.git
    exactVersion: 10.54.6
targets:
  AudiobookshelfNative:
    sources:
      - path: Migration/LegacyRealm/Sources/LegacyRealmExport
    dependencies:
      - package: RealmSwift
        product: RealmSwift
```

and configure the same realm-core mirror for the Xcode workspace
(`-clonedSourcePackagesDirPath` with a `mirrors.json`, or Xcode's package mirror setting).

## Native integration

Run migration **before** the stores are constructed in `AudiobookshelfNativeApp.init`:
`NativeDownloads`, `ReadingStore` and the listening journal read their files once in `init` and
become read-only on decode failure.

Suggested shape (coordinator-owned, not applied):

```swift
let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("LegacyMigration", isDirectory: true)
let migrator = LegacyMigrator(root: root)
do {
    if let outcome = try migrator.committedOutcome() {
        MigrationImport.apply(outcome, files: migrator)   // idempotent, see mapping below
    } else if let source = pendingSource() {              // archive picked by the user, or in-place
        let outcome = try migrator.migrate(source, secrets: KeychainMigrationSink(vault))
        MigrationImport.apply(outcome, files: migrator)
    }
} catch LegacyMigrationError.committedMigrationDamaged {
    // Expose no migrated file. Repair with `migrate(source)` when the source is available,
    // otherwise ask the user for a new export.
}
```

`MigrationImport.apply` should record which outcome fingerprint it already applied (for example
in UserDefaults), so it runs once per outcome.

### Mapping outcome to native stores

| Outcome | Native store |
| --- | --- |
| `MigratedAccount` + adopted secret | `KeychainCredentials` `Document.connections` (`Connection(id:credentials:libraryID:)`, `Credentials(server, accessToken, refreshToken, userID, username)`); active account from `wasActive`. The sink implements `MigrationSecretSink` over `KeychainCredentials`, so secrets stay in Keychain. `lastLibraryId` preference seeds `libraryID`. |
| `reauthenticationRequired` | Show the account in the sign-in list with its server prefilled; attach migrated data when `AccountIdentity(server, userID)` matches after sign-in. |
| `MigratedDownload` (book) | One `NativeDownloads.Entry`: `id` and `generation` new UUIDs, `account`, `media` (`ListeningMedia(itemID: libraryItemID, episodeID: nil, title, author, mediaType, duration: sum of finite track durations, startTime: progress currentTime)`), `tracks`, `chapters`, `ebook`, `serverPosition`/`serverUpdatedAt` from the matching `MigratedProgress` (else 0), `finished` = indices of adopted parts. Link or copy `fileURL(for:)` into `NativeDownloads.directory` with the native names `audio-<index>.<ext>` and `ebook.<format>`, then write the manifest. The native manifest rejects the whole file when a `.ready` entry has unfinished parts or a non-finite duration, so use `state: .ready` only when `complete`, else `.failed` with the issue's message in `error`. Items with no `libraryItemID` stay out of the manifest and in the issue list. |
| `MigratedDownload` (podcast) | One `Entry` per `MigratedEpisode` with an adopted track (`ListeningMedia.episodeID` = episode id), since an entry holds one `ListeningMedia`. |
| `MigratedDownload.files` (`supplementary`) | No native field yet. Keep them reachable through `fileURL(for:)` and list them on the item until native storage has a place for them. |
| `MigratedInterruptedDownload` | Offer "Resume download" on the item. Adopted parts are linked or copied in under their native part names (`audio-<trackIndex>.<ext>`, `ebook.<format>`) with an `Entry` in `.failed` state whose `finished` lists them, so the native downloader fetches only the rest. |
| `legacyItem.metadata`, `legacyItem.tags` | Offline display (subtitle, narrators, series, description) until the server copy is fetched. |
| `MigratedDownload.cover` | No native field yet. The adopted cover stays at `fileURL(for:)` until `Entry` gains cover storage; the native app otherwise loads the server cover. |
| `MigratedProgress` (audio, finished flags, reading) | Upload, not a journal entry: `ListeningJournal.rememberRemotePosition` records a server position and uploads nothing. For each account, compare with the server's `mediaProgress` by `lastUpdate`, as the legacy `syncLocalSessionsWithServer` did; where the local value is newer, `PATCH /api/me/progress/<item>[/<episode>]` with `currentTime`, `duration`, `progress`, `isFinished`, `finishedAt`, `ebookLocation`, `ebookProgress` (the legacy `updateMediaProgress` route). The native app has no such path today; the coordinator adds it. Until uploaded, keep the outcome as the source. |
| `MigratedProgress.reading` | `ReadingStore.Position(account, itemID, format, fileID, location, fraction, updatedAt, revision, pending: true, rotation: 0)`. PDF uses the page string; EPUB keeps the CFI; MOBI/AZW3/CBZ/CBR keep the raw value for their deferred readers. |
| `webStorage["ebookLocations-<id>"]` | EPUB location cache for the native EPUB reader when it exists; otherwise keep in the outcome. |
| `MigratedSession` | Upload through the native `api/session/local-all` path (`APIClient.swift`), as the legacy app did on reconnect for every pending row. `sessionTotal` rows match what the server expects. For `sinceLastSync` rows (streamed, `localLibraryItemId == nil`) the server already holds the session id; whether `local-all` adds or replaces their `timeListening` is unverified (gate 9), and the alternative is the legacy streamed route `POST /api/session/<id>/sync` with `timeListened` = the stored value. Sessions with no account are not sent. |
| `LegacyDeviceSettings` | `previewSkipForward` (`jumpForwardTime`), `previewSkipBackward` (`jumpBackwardsTime`), `previewHaptic` (`hapticFeedback` lowercased), `previewResumeRewind` (`!disableAutoRewind`), `previewMediaSeeking` (`allowSeekingOnMediaControls`), `previewSleepFade` (`!disableSleepTimerFadeOut`), `previewDownloadCellular` (`downloadUsingCellular != "NEVER"`) |
| `LegacyPlayerSettings` | `previewPlaybackSpeed` (`playbackRate`) |
| Preferences `theme`, `bookshelfListView`, `lastLibraryId` | `previewTheme`, `previewListLayout` (Bool, `"1"` is true; the legacy app stores `'1'`/`'0'`), `previewLibrary` |
| `webStorage["ereaderSettings"]` | `previewEPUBPreferences` (font scale, theme, spacing where equivalent) |
| `webStorage["absDeviceId"]` (route 1 only; archives exclude it) | `nativeDeviceID`, so the server sees the same device |
| `issues` | A "Migration needs attention" list in Settings, grouped by account with an "Other" group for issues with no account (`unscopedData`, `accountMismatch`, `unreadableConnection`), each showing its `message`. |

Kept in the outcome without a native target yet (the coordinator decides when a native setting
exists): `languageCode` and `lang`, `lockOrientation`, `streamingUsingCellular`, `chapterTrack`,
`enableAltView`, and the `userSettings` preference blob (plus `serverSettings` on route 1;
archives exclude it and the native app fetches it again at sign-in).

Media duration for `ListeningMedia` is `legacyItem.mediaDuration` when finite, else the sum of
finite track durations; the native manifest rejects non-finite durations.

## Legacy export route (route 2), built into the legacy app

The legacy app in this worktree carries the export. Signing, team, bundle identifiers and
entitlements are unchanged; the iOS 14 minimum is unchanged.

- `apple/Migration/LegacyMigration.podspec` and `LegacyRealmExport.podspec`: local pods, consumed
  by path from `ios/App/Podfile`, so the export links against the app's own RealmSwift 10.54.6
  pod (no second Realm binary).
- `ios/App/App/LegacyMigrationExport/LegacyMigrationExportPlugin.swift`, registered in
  `MyViewController.capacitorDidLoad`. Methods:
  - `exportArchive({ webStorage })`: `LegacyExportJob.run` takes `Realm().writeCopy(toFile:)` of
    the open database into a work directory in `tmp`, reads the copy, writes
    `tmp/LegacyMigrationExport/Audiobookshelf Export <yyyy-MM-dd HHmm>.absmigration` and removes
    the work directory (with the credential-bearing database copy) whatever the outcome. Earlier
    exports are discarded first; a failed export leaves no package. Emits `exportProgress`
    (`copyingDatabase`, `readingDatabase`, `copyingFiles` with file and byte counts). Rejects with
    `LegacyExportJob.message(for:)`: out of space, unreadable database, unsupported version, or a
    generic failure, none carrying a path or detail. Only counts are logged.
  - `saveArchive()`: presents `UIDocumentPickerViewController(forExporting: [package], asCopy:
    true)`; resolves `{ saved }`. No share sheet, no upload on the app's behalf.
  - `discardArchive()`: removes the prepared package.
- Source Realm and Documents are only read: the database through Realm's own consistent copy,
  downloads through `copyItem` (an APFS clone) into the package.
- `ios/App/App/Info.plist` exports the type `org.audiobookshelf.legacy-migration` (extension
  `absmigration`, conforming to `com.apple.package` and `public.composite-content`), so Files and
  the document picker treat the package directory as one document.
- `plugins/legacyMigrationExport.js`: plugin binding (the web build rejects as unavailable),
  `collectReaderStorage` (only `ereaderSettings` and `ebookLocations-*` leave the WebView; the
  native allowlist applies again), progress fraction and label.
- `components/settings/LegacyMigrationExport.vue`, shown on iOS at the end of Settings: export with
  a progress bar, then Save to Files or Remove export, errors shown with Try again. Copy tells the
  user that passwords and sign-in tokens are not included, to choose On My iPhone to stay off cloud
  storage, and that the app and its downloads stay as they are.

The package carries no access or refresh token, Keychain item, `device` WebView blob, tokenized
part URL, log, cached `serverSettings` or `absDeviceId`. The new app signs in again.

### Native import (coordinator-owned, not applied)

1. Declare the type under `UTImportedTypeDeclarations` in the native Info.plist with the same
   identifier, conformance and extension, so the picker offers the package as one item.
2. Present `UIDocumentPickerViewController(forOpeningContentTypes: [UTType("org.audiobookshelf.legacy-migration")!], asCopy: true)`,
   then `LegacyArchive.open(url)` and `migrate` (the archive is copied into the migration root,
   so the picked copy can be deleted afterwards).
3. Every account in an archive arrives as `reauthenticationRequired`; `nativeDeviceID` is not
   seeded from an archive.

## Verification evidence (this machine, synthetic data only)

Tests were written first and failed before implementation. The first round was observed locally
(tests and code were committed together):

- Core: 16 tests with 18 failures against neutral stubs, then 17 of 17 passing.
- Realm adapter: 5 tests, 5 failures against neutral stubs, then 5 of 5 passing.

The review round is committed red first, then fixed, so it can be checked from history:

- Core: 3 new tests failing (non-finite legacy numbers aborted the commit; progress and sessions
  without an account raised no issue; a file shared by two accounts was adopted into only one
  account's scope), then 20 of 20 passing.
- Realm adapter: 1 new test failing (a credential-bearing work copy left by an interrupted read
  survived), then 6 of 6 passing.

Covered failure and recovery cases: interruption after N file transfers then resume, interruption
between outcome and journal commit, repeated runs, corrupt journal, tampered staged file, corrupt
and incomplete archives, unsupported schema, unreadable database, different source after commit,
copy fallback without space, path traversal, NaN and infinite legacy numbers, shared files across
accounts, stale credential copies, hostile or colliding item identifiers, journal loss after
commit, deleted, replaced and in-place-changed adopted files (including an interrupted repair),
journal/outcome disagreement, owner conflicts on items, progress, sessions and interrupted
downloads, supplementary files, finished parts of interrupted downloads, the tokenized part URL, missing and truncated files, account mismatch,
unscoped items, interrupted downloads, invalid reader locations, credential absence from every
file written by the migration.

Fixtures use synthetic accounts and `SYNTHETIC-*` token markers; no real Realm, Keychain item or
credential was read.

Third round (coordinator review findings plus an independent audit of the preservation
contract), committed red first at `7edf085e`:

- Core: 8 new tests failing for their defects (an item id `a/b` and `a_b` overwrote each other and
  `..` escaped the account directory; a lost or corrupt journal let another source replace the
  committed outcome; deleted, replaced or changed adopted files stayed reported as migrated; a
  journal/outcome fingerprint disagreement went unnoticed; rows recorded for another user or
  server were scoped to the connection's current account; supplementary files vanished from the
  outcome; finished parts of interrupted downloads were orphaned).
- Realm adapter: 1 new test failing (full metadata, tags, `isInvalid`, episode details, session
  chapters and metadata, download parts not read).
- One more core test, written after the audit found that an interrupted repair lost the committed
  digests and re-adopted a file changed in place, failed before its fix.
- Then core 29 of 29 and Realm adapter 7 of 7 passing.

iOS 14 source minimum: Xcode 27 refuses simulator builds below 15, so the core was typechecked
directly with availability enforced (`xcrun --sdk iphoneos swiftc -typecheck -target
arm64-apple-ios14.0 ...` and the `-simulator` variant): no errors or warnings. The Realm adapter
was not typechecked for iOS 14 (it needs the RealmSwift module for that target); it uses no API
newer than iOS 13 by inspection, which is not evidence.

Fourth round (an adversarial review of the third), committed red first at `d4593e5f`: 3 new core
tests failing (a repair interrupted midway uncommitted the migration, after which a different
source was accepted; a repair dropped an intact adopted file whose legacy original was gone; paths
differing only by case shared a destination on a case-insensitive volume and broke archive
export), then core 32 of 32 and Realm adapter 7 of 7 passing. The iOS 14 typecheck was repeated
with no errors or warnings.

Fifth round (a focused review of committed-file integrity), committed red first at `28abf51b`:
4 new core tests with 13 assertion failures against the previous code. A same-size change with
its modification date restored was reported valid at launch and handed out by `fileURL(for:)`; an
adopted file replaced by a symbolic link to matching bytes was handed out and passed the repair's
full check, so the repair never replaced it; a directory above adopted files replaced by a
symbolic link passed both checks; an `outcome.json` path of `../../decoy.pdf` leading to matching
bytes passed both checks and was returned by `migrate`. Then core 36 of 36 and Realm adapter 7 of
7 passing, with the legacy tree, the symbolic link targets and the original fingerprint unchanged
through a failed repair. The iOS 14 device and simulator typecheck of the core was repeated with
no errors or warnings.

Sixth round (final re-review of `497e3cc0`), committed red first at `ffb979a4`: 1 new core test
with 3 assertion failures. Through a read seam on `MigrationFileSystem`, it writes to an adopted
file right after its first chunk was hashed; the old code handed out the changed file, and the
seam was never reached because hashing read the file directly. Then core 37 of 37 and Realm
adapter 7 of 7 passing, the legacy tree and fingerprint unchanged, and the iOS 14 device and
simulator typecheck with no errors or warnings.

Seventh round (the export route), each part committed red first:

- `5410d46b`: 2 core tests (5 assertion failures: the server settings cache and device identity
  were archived; no progress was reported) and Realm tests failing against neutral stubs (the
  database copy survived a failed export; no export progress). `LegacyAppCompatibilityTests`
  compiles the legacy app's own Realm model sources (`ios/App/Shared/models`, by symlink) next to
  the export, seeds them with a synthetic token, a tokenized part URL and a log entry, exports
  through `Realm().writeCopy` in the same process, and checks the archive holds none of them,
  the downloads are untouched, the app's own classes still work, and the archive migrates with
  accounts, settings, reader storage, files, the EPUB CFI and the interrupted part. Fixed in
  `bb60b567`.
- `c3d1ee64`: 3 `LegacyExportJob` failures (one dated package, earlier exports replaced, a failed
  export leaves nothing, distinct detail-free messages). Fixed in `96f15a13`.
- `3dfd03fb`: 3 web bridge tests failing (module missing). Fixed in `d69f261b`.

At `d69f261b`: core 39 of 39, Realm adapter 10 of 10, legacy app compatibility 1 of 1, web bridge
3 of 3 (`node --test apple/Migration/LegacyExportWebTests/`). `nuxt generate` succeeded with the
component in the bundle. `npx cap sync ios` ran `pod install`, which resolved both local pods;
the only tracked change was `Podfile.lock` (CocoaPods 1.17.0 wrote its version). Unsigned
`xcodebuild -workspace App.xcworkspace -scheme App -destination 'generic/platform=iOS Simulator'
CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0 build` succeeded with no warning in the
new sources; the built app carries the exported type, both frameworks and the plugin, with bundle
identifier `com.audiobookshelf.app.dev` unchanged. Xcode 27 refuses any target below 15 for device
and simulator, so the iOS 14 minimum was checked by typechecking `LegacyRealmExport` and the
plugin against the built pods with `-target arm64-apple-ios14.0-simulator -Xfrontend
-disable-target-os-checking`: no errors (a control file calling an iOS 15 API fails at that target,
so availability is enforced).

Not run: the legacy app does not launch when built with the iOS 27 SDK ("UIScene life cycle is
required for apps built with this SDK"; master has no scene manifest either), so the export was
not exercised through the UI on a simulator. No export of owner data was run.

## Remaining physical gates (open)

1. A Realm written by an actual legacy app build (0.14.2-beta, schema 21) on device, read by
   `LegacyRealmReader`. Fixtures were written with the mirror schema, not by the legacy app.
2. Compatible-identity build: legacy bundle identifier, team, Keychain access group and
   entitlements, reading `AudiobookshelfRefreshTokens` through `LegacyKeychainRefreshTokens`
   (untested here by design: tests never touch the real Keychain).
3. WebView localStorage in place: the native app cannot read the legacy WKWebView store; route 1
   carries no reader settings or EPUB location caches unless a reader for the WebKit store is
   added and proven on device.
4. The export run from Settings in a legacy build on a device (or on a simulator with an SDK the
   legacy app still launches under), saved to On My iPhone with the document picker, and the
   package seen as one item by Files and the native picker (directory packages through
   `forExporting` are expected to work for a declared package type; not observed here). Needs a
   signed legacy build, which is the root's to install after review.
5. After coordinator wiring: offline playback of adopted audio, same-page PDF resume, EPUB/MOBI/
   AZW3/CBZ/CBR files present and associated, settings and accounts visible, pending sessions
   accepted by a server.
6. iOS 14 runtime on a device or simulator (builds here target the iOS 14 minimum but run on the
   Xcode 27 toolchain).
7. Free-space and hard-link behaviour on a real device volume with a large library.
8. Route 1 rollback: reinstall the legacy build over the upgraded app on a device and confirm it
   opens with its pre-upgrade accounts, downloads and progress.
9. Server handling of streamed (`sinceLastSync`) sessions posted through `local-all` when the
   server already holds the session id, against the supported server versions.
10. Native import of a real `.absmigration` once the coordinator declares the imported type and
    wires the picker.
