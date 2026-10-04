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

Tickets #151–160 are complete. The sections below track subsequent slices and their remaining acceptance. Realtime, full migration, administration, legacy removal, final deployment and store acceptance still require the remaining tickets. Existing deployment examples still describe the superseded two-server configuration until the deployment and cleanup tickets replace them.

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

All four unchanged Android RealServerJourney assertions subsequently passed on the replacement image: cross-file playback, PDF page persistence, offline reconnect and first offline completion. Evidence: `/tmp/leafwake-native-real-journeys-clean.log`. A reused synthetic PDF fixture initially resumed its saved page 2; resetting only synthetic progress restored the required initial state. Assertions were unchanged. #156 is complete; podcast integration remains #163 and final device/release acceptance remains #174–177.

## #152 search authorization completion

Search matches and counts only media already permitted by current library, explicit-content and tag restrictions. Unauthorized libraries return 404 without media metadata. Browser search consumes the compatible grouped result shape. The More control and URL/API limits now share a bounded maximum and request refinement when reached. Author/series destination pages and the remaining discovery contracts stay under #161.

Both missing search and the large More request were demonstrated red before fixes. Production search-policy and progress regression journeys passed. Browser search rendered a scanned item. Typecheck, lint and 119 browser units passed. Independent catalog review cleared authorization and the coordinated limit. Evidence: `/tmp/leafwake-search-policy-red.log`, `/tmp/leafwake-search-more-red.log`, `/tmp/leafwake-search-policy-final-green.log`, `/tmp/leafwake-search-progress-regression.log`. Image `leafwake:search-152` config digest `sha256:494fb0797fc94409dc2f977ebd9c24347db01923e971a52535744cde62812c0c`.


## #153 read-only account migration and backup recovery

Fresh setup can inspect a consistent SQLite source copy, report unsupported password hashes, policies, account fields and configured external authentication, and atomically import supported accounts. Original IDs, supported bcrypt passwords, active state, restrictions and archived fields survive. Inspection and commit pin the read-only source, verify its digest and reject changed or out-of-root copies. Repeated import returns the original completion record. This account stage explicitly does not authorize full cutover: remaining media, progress, lists and settings are reported for later stages.

Owner-only product backups preserve SQLite data and migration records. Restore validates the snapshot and replaces data in one transaction, clears session authority and deactivates playback sessions. Restored accounts must sign in again. Media mounts and the original data folder need separate retention.

Production HTTP import, failure atomicity, safe retry, original-source digest, backup/restore and revoked-session checks passed. Imported identifiers, original passwords and completion records survived restart. Shared browser inspection/import, backup creation, restore and fresh sign-in passed. Preview screenshot capture remained unavailable; interaction and DOM evidence was available. Typecheck, lint and 119 existing browser units passed. Fresh independent source review cleared backend and UI after inventory and session-revival fixes. Tests for missing operations, malformed archived fields, unknown account columns, default external-auth settings and session revival were observed red before fixes.

Evidence: `/tmp/leafwake-import-red.log`, `/tmp/leafwake-import-inventory-red.log`, `/tmp/leafwake-import-unknown-fields-red.log`, `/tmp/leafwake-import-default-auth-red.log`, `/tmp/leafwake-import-session-restore-red.log`, `/tmp/leafwake-import-green.log`, `/tmp/leafwake-import-restart.log`. Production image `leafwake:import-153` config digest `sha256:7243c8ee9f9fbea2a29ce5c43f98e09889f65d79130b94318526afaaa5e3e723`. All test sources and volumes were synthetic; owner media and credentials were not used.


## #157 authenticated realtime on the product listener

Socket.IO uses the same port as HTTP and Next.js. The custom entry warms the public health route before enabling socket handshakes. Native auth/init payloads use current persisted session authority. Post-commit notifications deliver account-scoped progress/user updates and policy-filtered catalog changes. Reset generations emit scoped item updates even when no progress exists. Shared catalog snapshots avoid rebuilding unchanged catalogs for routine account progress. Reconnect/init refreshes browser queries; current authority is checked at every dispatch and expiry/revocation checks bound idle credentials. Anonymous connections have a fixed authentication deadline and bounded capacity, message size and auth attempts.

Production blackbox checks passed for WebSocket and polling auth, committed progress, catalog rescan, account/library isolation, revocation, reauthentication, reconnect, empty reset generation updates and the raw Apple/TV wire rejection payload. Missing sockets, absent reset events and malformed native rejection payloads were observed red before implementation/fixes. Repeated invalid authentication could not extend the anonymous deadline in manual production verification. Typecheck, lint and 119 browser units passed. Independent review cleared startup, reconnect, anonymous deadline, generation and snapshot-cost fixes. Browser another-client update and restart acceptance are recorded with PR evidence.

Evidence: `/tmp/leafwake-realtime-red.log`, `/tmp/leafwake-realtime-native-wire-red.log`, `/tmp/leafwake-realtime-empty-reset-red.log`, `/tmp/leafwake-realtime-final-green.log`, `/tmp/leafwake-realtime-idle-check.log`. Image `leafwake:realtime-157` config digest `sha256:70f05644a1ff9dcee2d5f7c1988518299467ee1d89648c09c588a3175f74bb0b`. List, podcast and RSS-specific domain events will be connected as those domain tickets land; final native/store QA remains required.

## #158 media, history and reader migration

The owner can inspect and import the same read-only source snapshot used for accounts, mapping original folders onto confined mounted media. Original library/item/media/file identities, author/series relationships, reader positions, manual progress fractions, bookmarks and cumulative listening records survive import. Composite file keys permit original file identifiers shared by distinct items. Rescanning retains imported media and file identities. Live responses use explicit projections; full source rows remain in a private migration archive. Inspection reports unknown tables, malformed records and unconsumed identities. This stage always reports that full cutover is incomplete until the remaining settings/list/domain stages finish.

Missing bookmark support, numeric progress flags, shared file identifiers and unmapped known records were observed red before their fixes. The reviewed production image passed digest mismatch atomicity, retry identity, original-source digest preservation, streaming original file IDs, rescan identity and cumulative history checks. Restart retained original progress, bookmarks and listening totals. The shared browser inspected the source, displayed unmapped identities and committed two original items. Snapshot capture failed; DOM and interaction evidence was available. Typecheck, lint and 119 existing browser units passed. Fresh independent review cleared private-field projection, malformed relationship and ownership/path findings.

Evidence: `/tmp/leafwake-media-import-red.log`, `/tmp/leafwake-media-import-progress-flag-red.log`, `/tmp/leafwake-media-import-compound-red.log`, `/tmp/leafwake-media-import-unmapped-red.log`, `/tmp/leafwake-media-import-reviewed-green.log`, `/tmp/leafwake-media-import-restart.log`. Image `leafwake:media-import-158` config digest `sha256:b47f886ad6cbb7b306e38d005a9b277413b46070f059bf3dafaf40c79cf54975`. All sources and volumes are synthetic. Podcast native downloads are exercised when podcast integration lands in #163; final migration rehearsal remains #172.

## #159 authenticated on-demand HLS transcoding

Unsupported codecs negotiate a single supported HLS track on the product listener. A static seekable VOD manifest requests six-second AAC/MPEG-TS segments on demand. Each segment selects the required source portions, including multi-file boundaries, without encoding an entire audiobook before a seek. Token and current account/session/catalog authority gate manifests and segments. The worker pins confined source descriptors, forces known demuxers, uses argument arrays without a shell, limits two concurrent jobs and 32 outstanding jobs, and bounds individual output, threads, allocation size and execution time. SQLite retains jobs across restart; cache reconciliation removes abandoned partials and files left by account cascades or restore. Session close terminates active work and removes its cached output.

The first-written HTTP journey failed on the previous image’s 422 negotiation response. The reviewed production image passed automatic/forced HLS negotiation, token rejection, cross-account denial, AAC decoding, segment durations, the expected two tones across a source-file boundary, and closed-session denial. A simulated interrupted running job regenerated valid AAC after restart; injected orphan output disappeared. Closing during an active segment request denied the request and left no session cache files. Browser unsupported-codec negotiation played all segments to completion without a media error. Typecheck, lint and 119 existing units passed. Fresh independent review cleared cache-cascade and cancellation-publication races.

FFmpeg/FFprobe and Debian copyright/license texts are present in the image. Public notices include exact Debian source-package versions and FFmpeg copyright. Corresponding source archive bundling remains a mandatory final artifact check in #174 before public distribution.

Evidence: `/tmp/leafwake-transcode-red.log`, `/tmp/leafwake-transcode-reviewed-green.log`, `/tmp/leafwake-transcode-restart.log`, `/tmp/leafwake-transcode-cancel.log`. Image `leafwake:transcode-159` config digest `sha256:1f7f3c7271adb4e74879077d8abec9113bab2923a2f89db269e56116c313729f`. Synthetic media only; final native/device acceptance remains #174.

## #160 reader documents and authorized downloads

Primary and supplementary ebook routes serve actual mounted documents through the same confined descriptor reader as native files. Scans preserve a previous primary document’s identity and mark other documents supplementary. Document MIME types cover PDF, EPUB, MOBI/AZW3 and comics. A single-file item download retains HEAD and byte ranges; multiple files stream a ZIP64 archive with bounded buffering, sequential descriptors and four concurrent archives. Generated archives do not support resumption ranges; individual file downloads do. Missing media and denied download permissions return compatible errors. Archive source/output failures and cancellation close streams and release capacity.

First-written production checks failed on absent supplementary flags before implementation. The reviewed image passes real PDF/EPUB/comic files, primary/supplementary routes, ranges, invalid ranges, missing files, ZIP64 integrity and denied downloads while retaining reading access. Browser PDF resumed at page 4, saved page 5, rendered EPUB chapter text and opened/turned two comic pages. Supplementary PDF opened at page 1, turned to page 2 and left the primary saved page at 5. A real 32 MiB EPUB asset passed exact tail-range verification. All four unchanged Android RealServerJourney cases passed on this image: multi-file listening, primary PDF page persistence, offline reconnect and first offline finish. Typecheck, lint and 119 existing browser units pass; HLS output regression also passes. Fresh independent review reproduced archive error crashes before their fixes and cleared both error/cleanup paths afterward.

Earlier mobile deferral remains unchanged: PDF is required; remaining EPUB acceptance and MOBI/AZW3/CBZ/CBR mobile opening/resume stay deferred as recorded in modernization/SPEC.md. These files and locations remain preserved, but this backend slice does not claim their native acceptance. Final physical-device/release QA remains #174–177.

Evidence: `/tmp/leafwake-readers-downloads-red.log`, `/tmp/leafwake-readers-green.log`, `/tmp/leafwake-large-download.log`, `/tmp/leafwake-native-readers-160.log`, `/tmp/leafwake-readers-transcode-regression.log`. Image `leafwake:readers-160` config digest `sha256:e0e69e8a6ca69465817351748f712fd70f18a119d9735de08fff1ea588b91cb5`. All data and media are synthetic.

## #161 discovery and stable imported metadata

Permission-filtered author/series detail, associations, numeric series ordering, pagination, publisher/filter data, stable daily random order and collapsed-series pages use the replacement catalog. Personalized listening/reading and completion shelves use committed user progress; realtime progress/account hints invalidate library queries. Scans reuse existing identities across libraries. Canonical imported metadata and tags persist separately from extracted filesystem metadata and win subsequent rescans. Schema 8 seeds managed metadata for previously imported records. Encoded author/series URLs preserve older name-based identifiers, and server pages decode the installed Next version's encoded params once before querying.

The first-written production discovery journey failed on the absent author route. It now passes 40 real scanned audio items, filtered author counts, series sequence, page boundaries, collapsed counts, progress/completion changes and restricted-account denial. New imported author/series rescan assertions failed before canonical metadata preservation and pass on a fresh import. Restart retained the imported catalog and discovery state. Browser author cards and detail rendered 39 related books and two series, and the series grid rendered twelve ordered books after a first-written consumed sequence-sort assertion failed 400 and then passed; a double-encoded page parameter caused an observed 404 before the page-boundary fix, then the API returned 200 and the detail rendered. Typecheck, lint and 119 existing units pass. Fresh independent review cleared identity, encoding and count findings. Synthetic sources/media only; final native device acceptance remains #174.

Evidence: `/tmp/leafwake-discovery-red.log`, `/tmp/leafwake-discovery-import-identity-red.log`, `/tmp/leafwake-discovery-final-green.log`, `/tmp/leafwake-discovery-import-reviewed-green.log`. Image `leafwake:discovery-161` config digest `sha256:222496be4f1005896868365defc2fec4dba7b20ce1211dbed16c1be5c6a335b9`.
