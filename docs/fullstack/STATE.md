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
