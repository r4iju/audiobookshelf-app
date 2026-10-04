# Leafwake full-stack replacement and public release

## Problem Statement

The delivered Next.js application replaces only the browser interface. The owner expected the Audiobookshelf backend to be replaced too. Running an old server alongside the new UI leaves deployment, database behavior, authentication, administration and media processing on the legacy implementation. Known server defects still affect native clients. The owner wants the replacement completed independently, with one image serving both the browser application and its backend, no obsolete implementation left in the delivered product, and Google Play/App Store publication following the rewrite.

## Solution

Deliver Leafwake as a self-hosted full-stack Next.js product. One versioned image starts the browser UI, replacement API/realtime service and durable media jobs on one externally exposed port, with persistent data and media mounts. It can initialize a fresh server or import a supported Audiobookshelf installation without losing accounts, media identities, listening/reading progress or lists. Existing Leafwake native apps connect directly to this backend. Retire the legacy server dependency and the obsolete Vue/Nuxt/Capacitor implementation after replacement acceptance. Publish reproducible source and images, deploy the accepted product, then take the independent free native apps through Google Play and Apple review within the permissions and licensing actually obtained.

## User Stories

1. As a self-hosting owner, I want one image serving the UI and backend, so that deployment has one product lifecycle.
2. As a new owner, I want an initial setup wizard, so that I can securely create the first administrator.
3. As an owner, I want setup to close after initialization, so that an unauthenticated visitor cannot take over my server.
4. As an owner, I want persistent data outside the image, so that upgrades do not erase my library.
5. As an owner, I want health and readiness checks, so that I know when the whole product is usable.
6. As an owner, I want graceful shutdown and restart recovery, so that active jobs and saved progress survive maintenance.
7. As a migrating owner, I want a dry-run report, so that unsupported or inconsistent data is identified before cutover.
8. As a migrating owner, I want a consistent backup and verified import, so that my original server can be restored.
9. As a migrating owner, I want original account and media identities preserved, so that existing downloads and clients still associate their data correctly.
10. As a migrating owner, I want accounts and supported password hashes preserved, so that users can continue signing in.
11. As a migrating owner, I want library permissions preserved, so that migration does not expose restricted content.
12. As a migrating owner, I want listening and reading places preserved, so that users resume where they stopped.
13. As a migrating owner, I want sessions, bookmarks, collections and playlists preserved, so that history and organization remain useful.
14. As a migrating owner, I want podcast subscriptions, episodes and download associations preserved, so that my podcast library remains complete.
15. As a migrating owner, I want metadata, images and configuration retained or explicitly reported, so that migration never silently drops information.
16. As a migrating owner, I want repeatable import with a completion record, so that retries cannot duplicate users or listening history.
17. As a listener, I want password sign-in, sign-out and renewable sessions, so that my account remains secure and usable.
18. As a listener, I want supported browser and native OpenID sign-in, so that I can use my existing identity provider.
19. As an administrator, I want session revocation, so that a removed account or lost device loses access promptly.
20. As an administrator, I want account creation, role changes and library access controls, so that I can safely share the server.
21. As a listener, I want only authorized libraries and explicit content shown, so that access policy is consistent across clients.
22. As an owner, I want folders scanned for books, podcasts and companion documents, so that my mounted files become a usable library.
23. As an owner, I want incremental scans, so that repeated scans preserve stable identities and user progress.
24. As an owner, I want readable scan errors and missing-file handling, so that problems do not silently remove my data.
25. As an administrator, I want to edit metadata and covers, so that I can correct my library.
26. As an administrator, I want authorized uploads and intentional deletion, so that library maintenance is available in the new UI.
27. As an administrator, I want bounded metadata matching and provider errors, so that enrichment is optional and failures are understandable.
28. As a listener, I want paginated browsing, search, sort and filters, so that a large library remains navigable.
29. As a listener, I want authors, series and related items, so that I can discover what to listen to next.
30. As a listener, I want personalized shelves and Continue Listening, so that my next action is easy to find.
31. As a listener, I want direct streaming with byte ranges, so that seeking and native playback work correctly.
32. As a listener, I want chapters and file offsets preserved across multi-file books, so that navigation and resume are accurate.
33. As a listener, I want supported audio transcoded when necessary, so that clients can play media outside their direct codec support.
34. As an owner, I want bounded transcode resource use and cleanup, so that abandoned streams cannot exhaust my server.
35. As a listener, I want completion saved when I first finish a downloaded title offline, so that reconnect marks it finished correctly.
36. As a listener, I want retries to save listening exactly once, so that lost acknowledgments do not inflate statistics.
37. As a listener, I want older reports prevented from overwriting newer progress, so that concurrent devices agree on resume.
38. As a listener, I want progress reset coordinated with pending writes, so that old requests cannot recreate discarded progress.
39. As a listener, I want durable sessions and progress after server restart, so that maintenance does not lose listening.
40. As a listener, I want bookmarks created, renamed and removed, so that I can return to meaningful passages.
41. As a reader, I want primary and supplementary ebooks served securely, so that all existing reader workflows continue.
42. As a reader, I want document places preserved in the supported format, so that PDF, EPUB and browser reader resume remain accurate.
43. As a listener, I want permitted downloads and offline resume, so that unreliable networking does not prevent listening.
44. As a listener, I want collections and playlists, so that I can organize books and podcast episodes.
45. As a podcast listener, I want to subscribe to a feed and inspect episodes, so that new shows are usable without another backend.
46. As a podcast listener, I want episode downloads, retries, cancellation and queue status, so that subscriptions remain usable after failures.
47. As an owner, I want download schedules recovered after restart, so that automation does not depend on an always-live process.
48. As a podcast listener, I want discovery and feed validation, so that I can safely add the show I intended.
49. As an administrator, I want RSS publishing with intentional public access, so that I can share only the media I choose.
50. As an administrator, I want RSS slug collisions and feed closure handled, so that published links have a clear lifecycle.
51. As a reader, I want permitted SMTP delivery to my e-reader, so that the new backend preserves this workflow.
52. As a listener, I want listening statistics and year summaries, so that history remains accurate after migration.
53. As an administrator, I want server-wide statistics constrained to my role, so that private activity is not exposed.
54. As a listener, I want realtime item, progress, list and podcast updates, so that other-device changes appear without manual reload.
55. As a native-app user, I want the existing HTTP and realtime contracts maintained, so that the backend rewrite does not force me to lose a working app.
56. As a native-app user, I want the server identity and version reported accurately, so that compatibility failures can be diagnosed.
57. As a remote user, I want TLS termination and subpath deployment supported, so that my existing reverse proxy can serve the product.
58. As a local user, I want supported LAN HTTP and explicit origin rules, so that self-hosting remains practical without unsafe wildcard settings.
59. As an administrator, I want credentials and private paths excluded from logs, so that diagnostics can be shared safely.
60. As an owner, I want configured filesystem boundaries enforced, so that API requests cannot read unrelated host files.
61. As an owner, I want jobs and externally fetched content constrained, so that malicious feeds or media do not become host-network or filesystem access.
62. As an owner, I want backups and documented restore, so that a failed upgrade has a tested recovery path.
63. As a user, I want accessible, responsive and localized new administration flows, so that the full-stack product matches the modern client.
64. As an owner, I want obsolete runtimes, duplicate dependencies and launch scripts removed, so that the final image and active source have one implementation.
65. As a maintainer, I want license notices and corresponding source for every release, so that the rewrite and distribution respect inherited rights.
66. As an owner, I want a verified live deployment, so that published readiness refers to the deployed product rather than a local build alone.
67. As an Android user, I want Leafwake free to download from Google Play, so that I can use the accepted backend with an independently maintained native client.
68. As an Apple user, I want an independently named iPhone/iPad app through Apple review, so that installation is straightforward once distribution rights are cleared.
69. As an Apple TV user, I want the TV release verified with its actual remote and playback routes, so that store publication does not overclaim desktop or simulator results.
70. As an owner, I want store status to distinguish uploaded, submitted, approved and publicly available, so that completion claims are truthful.

## Implementation Decisions

- This amendment supersedes the previous client-only scope and its exclusion of backend replacement. Native apps and the delivered modern browser features remain in scope; earlier deferred mobile reader formats retain their explicit deferral unless the owner changes it.
- Deliver a TypeScript modular backend inside the Next.js product. REST/auth/media handlers use the Next.js Node runtime where appropriate. A thin product-owned Node entry point attaches Socket.IO and starts durable job processing on the same HTTP listener. It is new transport wiring, not a wrapper around the old Express server.
- Keep domain modules for accounts/policy, libraries/catalog, media delivery, progress/history, lists, podcasts/jobs, feeds/mail and migration. Domain writes use explicit transactional services; API and realtime transport share those services rather than duplicate their state.
- Use a versioned SQLite database for a single-server deployment, with transactional writes, foreign keys and tested backups. Preserve importable source identifiers. Persist refresh-session hashes, listening session revisions, progress generations and job state. Store secrets outside images and retain existing media mounts as data, not copied source.
- Maintain the consumed Audiobookshelf HTTP, status-code, response-shape, token and Socket.IO contracts across web, Android, Apple mobile and TV. Extend the protocol with explicit idempotency/revision/reset semantics when needed; continue existing supported clients without silently relaxing authorization. API compatibility is not retaining the old implementation.
- Build one image with the new UI, backend, realtime service, required media tools and worker entry points. Expose one port and mount persistent configuration/data/media. No old server image, second required backend, external mandatory database, or mandatory hosted identity service is part of the final deployment.
- Replace the existing standalone-only browser packaging with packaging that explicitly includes the product entry point and its runtime dependencies. Next.js standalone output does not trace a custom server, so do not silently rely on its generated server for the unified product. See the official custom-server guide in Further Notes.
- New installation has a one-time owner bootstrap and full server administration in the modern UI. Every functional slice includes its required UI/contract behavior rather than leaving a backend with no administrator interface.
- Media scanning/probing/transcoding and feed/mail operations use bounded, restartable jobs persisted in the database. Avoid shell interpolation of user filenames/URLs. Restrict filesystem access to configured mounts; define intentional local-feed exceptions without unrestricted SSRF or path traversal.
- Authentication includes password-hash import where supported, rotating refresh tokens, library/role policy, exact OpenID redirect allowlists and trusted-proxy configuration. Unrecognized imported auth configurations block cutover with an actionable report.
- Progress updates and aggregate listening totals commit atomically. Duplicate sessions/revisions cannot double-count; first offline completion works; resets cannot be undone by pre-reset reports. Realtime events are emitted after committed writes, not from stale per-request account snapshots.
- Migration is an explicit versioned operation against a consistent source copy. Inventory source schema/settings/media relationships, preserve supported identities, validate counts and semantic invariants, report unmapped data, then commit import. Never point mutation-based tests at the owner's live server or delete original media/database during implementation.
- Keep old runtime temporarily only as reference and migration input during expand/migrate. Final contract phase deletes obsolete Vue/Nuxt/Capacitor runtime, old server patches/launch dependencies and stale active deployment paths after replacements pass. Retain current native clients, indispensable migration readers, required third-party notices and useful history in Git. "No leftover code" means no obsolete active implementation, not deletion of user data, licensing notices or Git history.
- The default public native app remains Leafwake, independent and free on Google Play, initially without proprietary Cast. A new backend does not relicense inherited native code. Apple/Cast permissions remain factual external release gates and cannot be assumed from a rewrite.
- Run builds/tests locally with synthetic migration datasets and the existing account tooling. Keep signing material and account credentials outside committed source/images/logs. Store submissions follow accepted rewrite deployment, source/notice verification and applicable account testing/review requirements.

## Testing Decisions

- Primary seam: the production image's public HTTP/realtime boundary, driven by existing browser and native journeys, plus visible fresh-install/import/admin flows. Test observable results and persistent state across restarts rather than private helper behavior.
- Before implementing a new behavior, run its failing contract/journey first. Existing fixture journeys and schema validators provide prior art; fixture servers remain test doubles and do not count as replacement-backend acceptance.
- Use isolated synthetic source snapshots covering accounts, restrictions, books with multiple files, podcasts, all progress/reader formats, duplicate/late sessions, lists, feeds and configuration. Compare semantic before/after state and restart the imported product. Original source files must remain unchanged.
- At the same network seam, exercise authorization failures, range/HEAD/media responses, token rotation/revocation, redirect validation, path traversal, origin/subpath behavior, cancelled jobs, duplicate and out-of-order reports, concurrent auth/progress and disk-write failures. Add lower-level tests only for behavior that cannot be reliably demonstrated at this seam.
- Reuse the existing browser deployment and Apple/Android real-server cases against the replacement image. Include first offline completion and restart/cold-cache concurrency as required passes, not documented failures that count as clearance.
- Verify from the built image that no old server process/source or legacy UI assets are present. Start without any old server container; demonstrate sign-in, scanning, media delivery and progress through the real replacement.
- Retain distinct evidence for simulator/emulator, physical hardware, owner-data acceptance, migration, accessibility/localization and stores. Installation, source review or an upload alone is not acceptance.

## Out of Scope

- Building a new hosted audiobook subscription/media catalog, supplying copyrighted books, changing the owner's identity provider or requiring a cloud relay.
- Retaining the old backend behind a proxy as the final solution, maintaining duplicate active server implementations, or shipping a second backend container as a requirement.
- Unilaterally relicensing inherited code, treating maintainer silence as permission, or bypassing store policies/testing requirements.
- Erasing original server data, secrets, existing installed apps or historical Git records to satisfy source cleanup.
- Requiring feature parity with unused upstream extensions without an inventory decision. All currently consumed client contracts, owner administration/migration workflows and source-inventoried server data must be implemented or explicitly rejected by migration before cutover; silent data loss is never accepted.

## Further Notes

Authorized by the owner on October 4, 2026. The owner explicitly requested independent execution and waived seam/ticket confirmation; proceed from the dependency frontier without interviews or ticket approval rounds. This spec is a new parent, not a modification or closure of the previous modernization parent.

Current baseline has a Cast-free Android candidate and free Play app record but no public native rollout. Apple distribution permission is pending upstream. Existing native software evidence involving a patched Audiobookshelf image must not be described as acceptance of this replacement backend.

Architecture reference: [Next.js custom server guide](https://nextjs.org/docs/app/guides/custom-server) explains the custom-server/standalone packaging constraint. [Node SQLite documentation](https://nodejs.org/download/release/latest-v24.x/docs/api/sqlite.html) documents the available transaction/storage primitives; pin and verify the selected runtime/driver during implementation. GitHub native issue dependencies will represent ticket blockers where available.
