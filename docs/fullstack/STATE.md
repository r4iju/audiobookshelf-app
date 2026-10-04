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
