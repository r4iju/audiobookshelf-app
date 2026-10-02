# Android migration preservation (#52)

The supported migration is a locally built legacy fork's export into the separate native preview. It reads the legacy installation and archive without changing them. Account credentials are deliberately excluded; sign in again to each exported server with the same user. This completes the preservation implementation, not owner replacement acceptance (#54).

## Inventory from the legacy sources

| Store / data | Export and import behavior |
| --- | --- |
| Paper `device` | Server connection identity/order/name and device settings exported. Tokens, custom headers and `deviceInfo` excluded. Matching server/user signs in again before account data attaches. |
| SecureStorage refresh tokens | Not exported or copied. Reauthenticate. No access to the upstream sandbox or owner's credentials. |
| CapacitorStorage | `userSettings`, `playerSettings`, `bookshelfListView`, `lastLibraryId`, `theme`, `lang` exported. Device/display/player mappings apply once. Library selection uses the signed-in account; `lastLibraryId` remains preserved. Server settings are a refetchable cache. |
| Web storage | `ereaderSettings` and `ebookLocations-*` preserved for deferred readers; device identity and unrelated web cache excluded. |
| Paper `localFolders`, `localLibraryItems`, `downloadItems` | Records exported; available item files and completed/moved download parts copied with digests. Matching titles attach after sign-in; missing parts fetch again. Unscoped/foreign rows are retained in the raw snapshot, not attached. The source files and export remain available. |
| Paper `localMediaProgress` | Exported. Matching audio positions/PDF pages reconcile with newer server progress. Non-page locations and all original rows remain preserved. |
| Paper `playbackSession` | Pending listening exported, adopted under original session IDs and sent with absolute totals only for the matching account. These are listening totals, distinct from local event history. |
| Paper `mediaItemHistory` | Previously omitted. Now every readable history record is exported, including events for items no longer downloaded. Retained verbatim as JSON under `outcome.json`'s `legacySnapshot.mediaItemHistory`. Not uploaded, converted into sessions or displayed by the native history UI. |
| Paper `log` / logcat | Diagnostic records, not listening state. Not exported. `AbsLogger` stores arbitrary messages and `ApiHandler.makeRequest` logs request URLs, which can carry query credentials. Named JSON secret removal cannot sanitize these strings reliably. Logs remain accessible in the old app; `DbManager.cleanLogs` already expires Paper logs after 48 hours. |
| Server-held history/progress, finished state, collections and playlists | Follow the same server account. No server migration or owner/upstream data access in this change. |

Evidence for the local event distinction: `MediaEventManager` appends Play/Pause/Stop/Save/Finished/Seek/Sync events through `DbManager.saveMediaItemHistory`; `AbsDatabase.getMediaItemHistory` reads that local book for the legacy history screen. No history upload path exists. `AbsDatabase.syncLocalSessionsWithServer` uploads the separate playback sessions and removes acknowledged sessions. Local event history is therefore recoverable local data, not a duplicate archive of server listening totals.

## Format and recovery

Archive format remains version 1. `mediaItemHistory` is additive; older readers ignore it. New imports retain the entire exported snapshot as a JSON object in `legacySnapshot`, so unsupported fields, rejected rows and deferred-reader data survive commit, account attachment and later saves. It is recovery data and is never sent to the server. Existing archives without history still import; old committed outcomes without `legacySnapshot` still decode. A repeat import returns the committed outcome without reapplying settings or listening. An already committed older import cannot recover omitted history: keep its original legacy installation/archive. Export again for a fresh preview installation if that history is needed, rather than overwriting an existing committed import.

Interruption, digest validation, resumed staging and different-archive refusal retain their existing behavior. Keep the export and legacy app until checking the new app's account, positions and downloads. If import stops, select the same export to resume. Clearing/uninstalling the preview removes its local import, but does not undo sessions or positions already published to the server. Do not delete legacy state to recover from an import error.

The public upstream app cannot run this fork-only exporter and its private sandbox is inaccessible. Open it online to sync pending server-linked sessions/progress, then sign in to the preview and download again. Local history never uploaded by upstream remains in that old app. In-place replacement requires the owner's identity/signing key and a private-storage reader and is not implemented. Owner real-data/SAF, physical and assistive-technology acceptance stay in #54, not a claim made by this preservation fix.

## Narrow verification (2026-10-03)

Private evidence: `/Volumes/ai-ssd/code/audiobookshelf-delivery/2026-10-03/android-history-preservation/`.

- Before the fix, the legacy exporter instrumentation case failed because seeded local history was missing. The public archive/import regression also failed because commit dropped history and unknown snapshot fields. Both failures are retained.
- After the fix, the legacy exporter case passes on `emulator-5584` (Android 16), with real Paper records, exact archive contents, digest checks and credential markers excluded. The import regression passes: complete JSON equality after persistence, repeat/save preservation, old-outcome compatibility and unchanged archive bytes.
- One existing `MigrationJourney.c` attempt stopped before import: its unscrolled title lookup was below the current preflight viewport. Screenshot, semantics and log retained; it is not counted as a passing automated journey and was not looped.
- The focused production journey then completed through archive-open/import UI and actual password sign-in against the loopback synthetic 2.30.0 fixture. Three titles attached, the original 7-second session reached the fixture, book-0 was not downloaded again and only book-4's missing second track was fetched. Exact exported snapshot equality held after commit, attachment and process relaunch. Local history was not uploaded. Prior Migration7, core migration14 and seven retained-playerSettings outcomes remain retained, not rerun.
- Legacy/native debug builds and a native internal release build use offline Gradle caches on SSD. Reproduction: legacy `:app:assembleDebug :app:assembleDebugAndroidTest` (JDK 21); native `:core:test --tests '*LegacyImportTest.committedImportPreservesHistoryAndUnknownSnapshotFieldsAcrossRepeatAndSave'`, `:app:assembleDebug :app:assembleDebugAndroidTest`, `:app:assembleRelease` (JDK 17), all with `--offline`. Install only on explicit `emulator-5584`; exporter instrumentation class `com.audiobookshelf.app.migration.LegacyMigrationExportTest`.

No broad suite, lint/localization rerun, physical QA, owner server changes, hosted builds or public release. Current package/source hashes and cleanup verification are recorded with the delivery evidence and PR. Prior real-server evidence is 2.30.0 at client `4bbbacde` with candidate `cd703e87`; this narrow change does not retest or alter that server.
