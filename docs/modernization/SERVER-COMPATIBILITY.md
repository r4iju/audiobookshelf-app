# Local server compatibility gate

The deployed server inspected on 2026-10-01 is Audiobookshelf **2.30.0**, image digest `ghcr.io/advplyr/audiobookshelf@sha256:6fbd7dc95d53c6e168ce69e760b87c334e3b9ba88bf7b8531ed5a116d5d6da03`, with Socket.IO **4.7.4**. The installed legacy app is **0.14.2-beta** at upstream `7014e04e`. The user confirmed trusted HTTPS access from the installed TV, iPhone, and iPad. This confirms connection to that deployed version; it does not certify every playback, download, or reader workflow against it.

The automated matrix below tests synthetic contracts drawn from the existing clients. It must not be presented as testing an actual historical or proposed server release. No live deployment or live account is changed by these commands.

| Client and contract | Local verification | Coverage |
| --- | --- | --- |
| Production TVCore, legacy `user.token` | baseline gate | Login, restored account, 61-item pagination, expanded metadata, book and podcast session identity, two-file timeline, authenticated byte ranges, close report and resumed server progress |
| Production TVCore, `user.accessToken` + refresh | aligned candidate gate | Same journey, with initial 401, `x-refresh-token`, saved replacement credentials and continued requests |
| Production legacy `plugins/server.js` | both gates | `/abs/socket.io` WebSocket path, `auth` bearer event, `init`, `user_item_progress_updated` payload data, store update, dropped transport and re-authentication |
| Permission boundary | fixture and production client | Fresh bearer required for API/media; HTTP failure rejects a request. The synthetic account permits playback/download and denies upload/delete. Per-action restricted accounts remain part of each client's later permission acceptance. |
| Controlled incompatible catalog | candidate gate | Replacing `results` with `items` blocks TVCore at `library-pagination`, identifying the client needing alignment |
| Controlled incompatible realtime progress | candidate gate | Renaming `user_item_progress_updated` blocks the legacy client at `realtime-progress` |

The legacy-to-refresh authentication candidate demonstrates an aligned client: the same shipped TVCore accepts both supported authentication response shapes and persists the refreshed credentials. Unrecognized catalog/event changes deliberately block adoption. They are fault injection, not invented adapters for hypothetical upstream changes.

## Combined 2.30.0 server candidate (local, not deployed)

The deployed server stays on the pinned 2.30.0 image. Two locally packaged candidates replace server files to fix defects that the native clients found against it: Apple's user-cache race and Android's first progress from a local session. Promotion is the owner's decision; `SERVER-CANDIDATE-RUNBOOK.md` is the reviewable procedure. Every row ran on a synthetic server and synthetic accounts.

| Client | `candidate` `c649a2bd` (**held**) | `session` `cd703e87` | Evidence |
| --- | --- | --- | --- |
| Apple: affected native cases (`test1`, `test4a`, `test4d`, `test4e`, migration probe) | 5/5 | not run yet | `evidence/apple-real-server/server-combined/` |
| Android: `RealServerJourney` a-d, emulator | 4/4 | 4/4 (client `4bbbacde`: `a23db59b` plus localization, progress code unchanged) | `evidence/android-real-server/server-combined/`; for `session`, the Android lane's private artifacts |
| Server checks: first progress from local sessions (8), seams (3), cold-cache race (10) | 8/8, 3/3, 0/10 stale | 8/8, 3/3, 0/10 stale | Android and Apple evidence; `evidence/web-real-server/server-combined/` for `session` |
| Server checks: first progress through PATCH and batch PATCH (20), streamed sessions (5) | **10/20 (regression)**, 5/5 | 20/20, 5/5 | `evidence/web-real-server/server-combined/` |
| Next.js production client: Chromium, every spec except the nginx deployment (77) | **75/77**: two podcast episode journeys fail | 77/77 | `evidence/web-real-server/server-combined/` |
| Next.js production client: Firefox + WebKit, connect/session/playback/podcasts (50) | not run | 50/50 | `evidence/web-real-server/server-combined/` |

`c649a2bd` is held because it stores progress first created through `PATCH /api/me/progress` within 10 s of the end as finished. Stock 2.30.0 keeps what the client sent. `cd703e87` applies the finished rule at creation only to playback-session syncs. Its Apple row must still be rerun on that image; the `c649a2bd` pass does not carry over. Physical devices, owner libraries and owner acceptance remain open for every client.

## Reproduce on the Studio

```sh
npm ci --prefix verification/realtime --ignore-scripts --no-audit --no-fund
python3 -m unittest verification.test_fixture verification.test_compatibility verification.test_upgrade_gate
npm test --prefix verification/realtime
python3 -m verification.compatibility --candidate modern-auth
python3 -m verification.compatibility --candidate library-schema-change
python3 -m verification.compatibility --candidate progress-event-change
```

The aligned candidate exits 0. The two incompatible candidates exit 1 with affected workflows and clients. Infrastructure errors exit 2 and also block adoption. JSON is emitted without credentials. Swift compiles the runner locally against the production TVCore package; Node imports the production legacy socket plugin directly. Only loopback synthetic credentials are accepted by the HTTP runner.

These fixtures exercise request/response, media and server-observed persisted outcomes; they do not simulate AVPlayer output, reader rendering, or OS controls. The signed TV and existing native build commands are in `BASELINE.md`; all builds, dependencies, tests and packages stay local. Neither a cloud runner nor a hosted authentication/intermediary service is required. No store submission is part of this gate.

## Gate an actual upgrade

1. Record the candidate's exact server version and image digest. Review its upstream HTTP/authentication, realtime, permission, media and progress changes against the recorded baseline. Unknown releases require this review.
2. Run the current contract matrix, then the platform acceptance journeys for **every completed client**, against an isolated local candidate server with a synthetic library and accounts. Extend this matrix as native Apple, Android and Next.js clients land; clients that have not landed cannot be marked supported.
3. For each mismatch, record the affected workflow, adjust the actual client using a failing public-boundary regression, and repeat its baseline and candidate journeys. Authentication changes must preserve restored accounts; media/progress changes must retain file identities, offsets and saved progress. Verify restricted accounts and realtime recovery explicitly.
4. Obtain complete evidence for physical-device playback/background controls, downloads/offline storage and readers where that client implements them. A green synthetic report alone does **not** approve a real server release.
5. Adopt the candidate only after every completed client's real-server matrix is green. Keep the exact previous server image and a configuration/database backup for rollback. This ticket does not authorize a live upgrade.

Internal installation remains direct signed Apple-device installation, local Android APK installation, and self-hosted browser deployment. Paid cloud builds, TestFlight, App Store and Play Store releases are unnecessary.
