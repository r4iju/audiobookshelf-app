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
| WebView `ereaderSettings`, `ebookLocations-<id>`, `absDeviceId` (allowlisted) | `MigratedSettings.webStorage` |
| `LocalLibraryItem` files (audio, PDF, EPUB, MOBI, AZW3, CBZ, CBR, covers, podcast episodes) | Hard link or verified copy under `<root>/Files/<account scope>/<local item>/...`, `MigratedDownload` with tracks, chapters, ebook and episodes |
| `LocalMediaProgress` (audio position, finished state, `ebookLocation`, `ebookProgress`) | `MigratedProgress`, with `MigratedReadingLocation` (`page` for PDF/CBZ/CBR, `cfi` for EPUB, `opaque` for MOBI/AZW3; the raw legacy value is always kept) |
| `PlaybackSession` rows (unsynced listening) | `MigratedSession` with `sessionTotal` (local playback) or `sinceLastSync` (streamed) semantics |
| `DownloadItem` rows (interrupted downloads) | `downloadInterrupted` issue; finished parts already in `LocalLibraryItem` are adopted |

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
  Tests/LegacyMigrationTests/       17 tests, synthetic Documents tree and fault-injecting file system
  LegacyRealm/Package.swift         LegacyRealmExport (RealmSwift 10.54.6 exact)
  LegacyRealm/Sources/...           schema-21 mirror classes, Realm reader, installation source,
                                    archive exporter, read-only legacy Keychain reader
  LegacyRealm/Tests/...             5 tests against Realm files written with the mirror schema
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
- A committed migration returns the same outcome on every later call. A different legacy source
  after commit throws `differentSourceAlreadyCommitted`.
- A corrupt journal is moved aside (`state.corrupt-<timestamp>-<id>.json`) and the migration
  restarts from the untouched legacy source.
- Copy fallback checks free space before copying (`insufficientSpace`).
- Schema other than 21 throws `unsupportedLegacySchema` and touches nothing. An unreadable
  database throws `legacyDatabaseUnreadable`.
- `committedOutcome()` and `fileURL(for: MigratedFile)` are the read side for the app.

The legacy installation is never modified: the Realm is read from a copy, files are linked or
copied, Keychain items and UserDefaults are read only. The legacy app's data remains available
for rollback until the user removes it.

Hard links share storage with the legacy file. Neither app modifies downloaded media in place, so
this is safe, but deleting a download in the native app must remove only the native link.
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
if let outcome = try? migrator.committedOutcome() {
    MigrationImport.apply(outcome, files: migrator)   // idempotent, see mapping below
} else if let source = pendingSource() {              // archive picked by the user, or in-place
    let outcome = try migrator.migrate(source, secrets: KeychainMigrationSink(vault))
    MigrationImport.apply(outcome, files: migrator)
}
```

`MigrationImport.apply` should record which outcome fingerprint it already applied (for example
in UserDefaults), so it runs once per outcome.

### Mapping outcome to native stores

| Outcome | Native store |
| --- | --- |
| `MigratedAccount` + adopted secret | `KeychainCredentials` `Document.connections` (`Connection(id:credentials:libraryID:)`, `Credentials(server, accessToken, refreshToken, userID, username)`); active account from `wasActive`. The sink implements `MigrationSecretSink` over `KeychainCredentials`, so secrets stay in Keychain. `lastLibraryId` preference seeds `libraryID`. |
| `reauthenticationRequired` | Show the account in the sign-in list with its server prefilled; attach migrated data when `AccountIdentity(server, userID)` matches after sign-in. |
| `MigratedDownload` | `NativeDownloads.Entry` (`account`, `media`, `tracks`, `chapters`, `ebook`, `finished`, `state: .ready`). Move or link `fileURL(for:)` into `NativeDownloads.directory` with the native names `audio-<index>.<ext>` and `ebook.<format>`, then write the manifest. Entries with `complete == false` stay visible with their issue. |
| `MigratedProgress` (audio) | `ListeningSync` remembered position (`rememberRemotePosition`) per account and item/episode, compared by `lastUpdate`. |
| `MigratedProgress.reading` | `ReadingStore.Position(account, itemID, format, fileID, location, fraction, updatedAt, revision, pending: true, rotation: 0)`. PDF uses the page string; EPUB keeps the CFI; MOBI/AZW3/CBZ/CBR keep the raw value for their deferred readers. |
| `webStorage["ebookLocations-<id>"]` | EPUB location cache for the native EPUB reader when it exists; otherwise keep in the outcome. |
| `MigratedSession` | Listening journal entries for upload. `sessionTotal` goes through `/api/session/local-all`; `sinceLastSync` is reported as the unsynced delta. |
| `LegacyDeviceSettings` | `previewSkipForward` (`jumpForwardTime`), `previewSkipBackward` (`jumpBackwardsTime`), `previewHaptic` (`hapticFeedback` lowercased), `previewResumeRewind` (`!disableAutoRewind`), `previewMediaSeeking` (`allowSeekingOnMediaControls`), `previewSleepFade` (`!disableSleepTimerFadeOut`), `previewDownloadCellular` (`downloadUsingCellular != "NEVER"`) |
| `LegacyPlayerSettings` | `previewPlaybackSpeed` (`playbackRate`) |
| Preferences `theme`, `bookshelfListView`, `lastLibraryId` | `previewTheme`, `previewListLayout` (Bool, from the `"true"`/`"false"` string), `previewLibrary` |
| `webStorage["ereaderSettings"]` | `previewEPUBPreferences` (font scale, theme, spacing where equivalent) |
| `webStorage["absDeviceId"]` | `nativeDeviceID`, so the server sees the same device |
| `issues` | A "Migration needs attention" list in Settings, grouped by account, with each `message`. |

## Legacy export adapter (route 2), integration patch

The legacy app (`ios/App`, reference only, not edited) needs a Capacitor plugin to produce the
archive. Patch for the legacy owner:

1. Add `apple/Migration/Sources/LegacyMigration` and
   `apple/Migration/LegacyRealm/Sources/LegacyRealmExport` to the `App` target (the app already
   links RealmSwift 10.54.6 through CocoaPods; the mirror classes are excluded from its default
   schema).
2. Add a plugin `AbsMigrationExport` with one method `exportForNativeApp`:
   - read `ereaderSettings`, `ebookLocations-*` and `absDeviceId` from WebView `localStorage` in
     JavaScript and pass them as the call's `webStorage` argument;
   - `try Realm().writeCopy(toFile: tmp/legacy.realm)` for a consistent copy of the open database;
   - `LegacyArchiveExporter.export(documents:realmCopy:defaults:.standard, webStorage:workDirectory:to:)`
     to `tmp/Audiobookshelf Migration.absmigration`;
   - present `UIDocumentPickerViewController(forExporting:)` so the user saves it in Files.
3. The native app presents `UIDocumentPickerViewController(forOpeningContentTypes: [.folder])`,
   starts security-scoped access and calls `LegacyArchive.open(url)` then `migrate`.

## Verification evidence (this machine, synthetic data only)

Tests were written first and failed before implementation:

- Core: 16 tests with 18 failures against neutral stubs, then 17 of 17 passing.
- Realm adapter: 5 tests, 5 failures against neutral stubs, then 5 of 5 passing.

Covered failure and recovery cases: interruption after N file transfers then resume, interruption
between outcome and journal commit, repeated runs, corrupt journal, tampered staged file, corrupt
and incomplete archives, unsupported schema, unreadable database, different source after commit,
copy fallback without space, path traversal, missing and truncated files, account mismatch,
unscoped items, interrupted downloads, invalid reader locations, credential absence from every
file written by the migration.

Fixtures use synthetic accounts and `SYNTHETIC-*` token markers; no real Realm, Keychain item or
credential was read.

## Remaining physical gates (open)

1. A Realm written by an actual legacy app build (0.14.2-beta, schema 21) on device, read by
   `LegacyRealmReader`. Fixtures were written with the mirror schema, not by the legacy app.
2. Compatible-identity build: legacy bundle identifier, team, Keychain access group and
   entitlements, reading `AudiobookshelfRefreshTokens` through `LegacyKeychainRefreshTokens`
   (untested here by design: tests never touch the real Keychain).
3. WebView localStorage in place: the native app cannot read the legacy WKWebView store; route 1
   carries no reader settings or EPUB location caches unless a reader for the WebKit store is
   added and proven on device.
4. The legacy export plugin built into the legacy app, and the archive moved through the Files app
   between two installed apps on a device.
5. After coordinator wiring: offline playback of adopted audio, same-page PDF resume, EPUB/MOBI/
   AZW3/CBZ/CBR files present and associated, settings and accounts visible, pending sessions
   accepted by a server.
6. iOS 14 runtime on a device or simulator (builds here target the iOS 14 minimum but run on the
   Xcode 27 toolchain).
7. Free-space and hard-link behaviour on a real device volume with a large library.
