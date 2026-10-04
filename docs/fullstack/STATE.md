# Replacement implementation status

The authoritative scope is SPEC.md and GitHub issue #150. This is an incremental implementation, not the completed rewrite or a public release.

## #151: production bootstrap and persistent sign-in

The image runs Next.js and the new SQLite account/session backend on port 3000. `/data` persists the account database. Setup requires a private operator key and a transaction permits exactly one owner. No Audiobookshelf backend is needed for this journey.

Blackbox HTTP tests failed against the previous browser-only server before implementation. The production image passed fresh setup, four concurrent setup attempts, password sign-in, authorization, body limits, rejected foreign origins and readiness. After restarting the image with the same volume, the owner ID and access session survived, setup stayed closed, and refresh rotation rejected reuse. A legitimate browser-origin regression was demonstrated red and fixed before the final image run.

Evidence files for this development run are outside the repository:

- `/tmp/leafwake-first-slice-red.log`
- `/tmp/leafwake-first-slice-origin-red.log`
- `/tmp/leafwake-first-slice-final-image-test.log`
- `/tmp/leafwake-first-slice-final-image-restart.log`

Image config digest: `sha256:5b0c1f1af6c3a7a54e310a611c1cd347c1b1467f7f511e07eab7b6528e5f7ac6` (`leafwake:bootstrap-151`). Browser setup and sign-in passed through the shared preview. Preview screenshot capture failed; DOM and interaction evidence was available. Typecheck, lint, 115 existing unit tests and production Docker build passed. Independent source review cleared the bootstrap scope after the Origin fix.

## Remaining work

All remaining tickets #152–177 remain required. Empty library responses currently permit bootstrap verification only. Catalog, media, progress, realtime, administration, import, legacy removal, final deployment and store acceptance are not implemented by #151. Existing deployment examples still describe the superseded two-server configuration until the deployment and cleanup tickets replace them.

Apple and Cast permission remains pending at https://github.com/advplyr/audiobookshelf-app/discussions/2051. The backend rewrite does not relicense inherited native code. No public store artifact has been uploaded or rolled out.

## #152 account/auth portion

Account create/edit/disable/remove and session revocation now have modern UI and authenticated endpoints. Root removal and non-admin management are denied. Sparse permission patches retain existing restrictions. Login revalidates the current password hash atomically before issuing a session. Browser logout uses rotated registry credentials. Persisted sign-in attempt limits return 429 after repeated failures.

Account HTTP journeys were observed red before endpoints existed, and passed against the production image `leafwake:accounts-152` (`/tmp/leafwake-accounts-image-green.log`). Permission patch and rotated browser logout regressions were observed red before their fixes. Browser account creation passed. Fresh independent review cleared the account/auth portion. #152 remains open until catalog/search/stream policy enforcement is verified with #154/#155.

## #154 mounted catalog scanning

Administrators can create a library from mounted folders and run scans in the modern UI. The image includes FFprobe. SQLite retains library, item and file IDs across rescans and restart. Actual audio durations and chapters populate browser-compatible records. Missing items remain in the catalog. Root confinement, overlapping folder rejection, metadata symlink rejection, bounded metadata reads and nonblocking rejection of non-regular metadata protect scans. The image owns one process per data volume; interrupted scans are reported and can be rerun after restart.

The blackbox journey was observed red before implementation. Path and browse regressions were also observed red before their fixes. The final production image passed mounted-media scanning, pagination, duration sort, tag filters, stable rescan IDs, restricted/explicit-content denial and missing-item retention. Owner sessions and catalog records survived image restart. Browser library creation, scanning and browsing passed. Typecheck, lint and 116 unit tests passed. Fresh independent source review cleared the scanner scope.

Evidence: `/tmp/leafwake-catalog-image-green.log`, `/tmp/leafwake-catalog-image-restart.log`, `/tmp/leafwake-catalog-roots-red.log`, `/tmp/leafwake-catalog-metadata-red.log`, `/tmp/leafwake-catalog-browse-red.log`. Image `leafwake:catalog-154` config digest: `sha256:4da150c3a07de8607c34838e5b54974f199a21bc8e9cf2b508589e808e978262`.

The `media_progress` schema and browse readers enable progress filters; playback/progress writes remain #156. File streaming remains #155. No native playback or full migration acceptance is claimed by this slice.

## #155 secured multi-file streaming

The replacement opens durable account-bound playback sessions from scanned media, serves bounded file streams with HEAD/ranges and denies invalid ranges, unauthorized accounts, manipulated identifiers and changed symlinks. Account and session authority is rechecked after filesystem awaits. Access tokens expose native-compatible expiry while exact persisted token hashes remain authoritative. Sessions survive restart on the same volume.

The HTTP journey and native expiry regression were observed red before their fixes. Browser interaction exposed missing media authorization; regression tests were observed red for initial refresh and two later rotations before fixes. Track loads use current credentials, and successful audio playback clears the bounded recovery guard. Production image tests passed. Android emulator playback advanced across two real files and browser audio advanced with no media error. These are streaming acceptance only; durable progress remains #156.

Typecheck, lint, 118 unit tests and production image build passed. Independent source review cleared streaming and repeated browser credential renewal. Evidence: `/tmp/leafwake-streaming-final-image-green.log`, `/tmp/leafwake-native-streaming-155.log`, `/tmp/leafwake-browser-media-red.log`, `/tmp/leafwake-browser-media-renewal-red.log`. Image `leafwake:streaming-155` config digest: `sha256:aa82932d835abab05afdf1b5443f98f9f38e6d0e1b0e750c59c798f79e9fa826`.

## #156 durable progress foundation

The replacement persists account-bound cumulative listening history, ordered position/finish updates and primary reader places. First offline completion marks newly created progress finished. Session revisions survive clock rollback. Manual intents reject stale position updates. Reset generations fence old listening and reader writes while preserving listening totals. Persisted reset command IDs are idempotent even without a previous progress row.

Browser, Android and Apple capture the generation with listening/reading intents and downloads. Android retries download-manifest refresh before clearing a reset. Browser reset holds preserve offline intent and use the generation command when the cached item advertises it; legacy servers retain the existing coordination behavior.

Four production HTTP cases passed and progress/history/reader state survived restart. Browser finish/unfinish/discard passed through the shared preview. Preview snapshot capture failed; DOM and interaction evidence remains available. Typecheck, lint, 119 browser unit tests, Android core/app unit tests and instrumentation compilation, 72 Swift Core tests and an iOS simulator build passed. The simulator build explicitly used deployment target 15 because the installed SDK rejects the project’s current target 14; release target adjustment remains #177. Fresh backend and client reviews cleared fixes after reset-retry and offline-intent findings.

Evidence: `/tmp/leafwake-progress-final-green.log`, `/tmp/leafwake-progress-restart.log`, `/tmp/leafwake-progress-reset-retry-red.log`, `/tmp/leafwake-progress-browser-reset-red.log`. Image `leafwake:progress-156` config digest: `sha256:f19af47d8194f5fc1907be46bd650d8d7215b1d00fb4f71cecc54dbe4431cd19`.

#156 remains open for the unchanged complete native journeys and episode acceptance as the remaining ebook/download/podcast contracts land. These checks do not yet establish full backend migration or store readiness.
