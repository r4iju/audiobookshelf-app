# Next.js client against the packaged 2.30.0 server candidates

Candidates only. Neither image runs on any owner server, and nothing here is resolved on one.

The production Next.js client was run against the actual packaged candidate image, not a `User.js` copied into a container. It found a regression in that image: progress first created through `PATCH /api/me/progress` within 10 s of the end is stored finished. That image is **held**. This folder contains the RED check, the fix and the replacement image's results.

## Images

All three images were verified in the running container before and after each run (`docker inspect` image ID, `sha256sum` of every replaced file):

| Name | Image ID | Replaced files (SHA-256) |
| --- | --- | --- |
| `stock` | `ghcr.io/advplyr/audiobookshelf@sha256:6fbd7dc95d53c6e168ce69e760b87c334e3b9ba88bf7b8531ed5a116d5d6da03` (2.30.0) | none: `User.js` `2174eec7…a1d`, `PlaybackSessionManager.js` `e196eea6…5428` |
| `candidate` (held) | `abs-server-candidate:2.30.0-usercache-firstprogress`, `sha256:c649a2bd3bd177a79e414a08729009f9f1a50156271d008c35a4bb52e81d9abd` | `User.js` `15ee2c33…ac4` (Apple `b59ea8c8`, then Android `6313948f`) |
| `session` | `abs-server-candidate:2.30.0-usercache-firstprogress-session`, `sha256:cd703e87399f76f4e887282ca219013f99eeb7b7f24cc028990b07b71b39eba4` | `User.js` `d36db80057337ae071a436a7753cb3aa024e97373e8d4cc9e805d1c048486097`, `PlaybackSessionManager.js` `a140b5679a81e8b48b3485f6bd7e2bee0c20fb6bd79819a61279e465c8f685ae` (Apple `b59ea8c8`, then `first-progress-session-candidate.patch` `ed88f5e00834a1aa99e80eee001a71ec906a42d205db0137c9e3f904f56d8fcb`) |

Both candidates are the pinned base's 9 layers plus their own. They were built with `DOCKER_BUILDKIT=0 docker build --pull=false --network none`, and were never pulled or pushed. The `session` build context, saved image and inspect output are kept privately with the original candidate package. The original package is unchanged.

## The regression

`6313948f` made the create branch of `User.createUpdateMediaProgressFromPayload` run `applyProgressUpdate`. It did this for every caller, so the update's finished rule also applied to progress a client creates directly. The Android README listed this as a side effect. No check covered it until these journeys. Minimal case on the synthetic server:

| `PATCH /api/me/progress/<book or item/episode>`, no existing progress | `stock` | `candidate` |
| --- | --- | --- |
| `{currentTime: duration - 9, duration, progress}` | 200, stored as sent, not finished | 200, stored `progress: 1, isFinished: true` |
| the same, without `progress` | 200, `progress: 0`, not finished | 200, finished |
| the same body again, now on existing progress | finished (update rule) | finished |
| `{currentTime: 1, duration, progress: 0.01}` (far from the end) | not finished | not finished |

The browser saw this in `e2e/podcasts.spec.ts:171` and `:194`. Both seed episode 3 at 3 s with `duration: 12` (9 s left), then expect it under Continue Listening and the episode list at 25 %. On `candidate` the episode was finished and hidden, and both journeys timed out. On `stock`, `podcasts.spec.ts` passed 9 of 9.

## The fix

`first-progress-session-candidate.patch` replaces `6313948f` and applies after Apple's patch. `createUpdateMediaProgressFromPayload(payload, { fromPlaybackSession })` runs `applyProgressUpdate` on a new row only when the flag is set. `PlaybackSessionManager` sets it at its three callers: `syncLocalSession`, in both branches, and `syncSession` for streamed sessions. Thresholds still come from the payload. PATCH and the batch PATCH create progress exactly as stock does. The Android author agreed to this shape and confirmed Android does not depend on PATCH-created progress being finished.

## Results

`run-matrix.sh` holds every step. Each `progress` and `browser` run starts from a fresh synthetic seed on stock. It then replaces only the owned main container with the named image, keeping its volumes, ports, extra host, env and library mount, and restarts the owned fixtures on the new container's network (`swap-to-candidate.mjs`).

| Check | `stock` | `candidate` | `session` |
| --- | --- | --- | --- |
| `patch-first-progress-check.mjs`: PATCH and batch, book and episode, 20 cases | 20/20, exit 0 | **10/20, exit 1** | 20/20, exit 0 |
| `streamed-first-progress-check.mjs`: streamed sessions, 5 cases | 4/5, exit 1 (first sync near the end not finished) | 5/5, exit 0 | 5/5, exit 0 |
| Android `first-progress-check.mjs`: local-all and reading, 8 cases | 1/8, exit 1 | 8/8, exit 0 | 8/8, exit 0 |
| Apple seam checks inside the image, 3 | 3 fail | 3 pass | 3 pass |
| Cold-cache race, `run-combined.sh` `37f191de` `race()`, 10 tries | not rerun (7/10 stale in the Android evidence) | not rerun (0/10 in the Android evidence) | **0/10 stale, every request 200, exit 0** |
| Production client, Chromium: all specs except `deployment.spec.ts` (77) | not rerun here (86/86 in the client's own final QA on stock) | 75/77, exit 1 (main 51/51; rest 24/26) | **77/77, exit 0** |
| Production client, Firefox + WebKit: connect, session, playback, podcasts (50) | not rerun here | not run | **50/50, exit 0** |

The browser runs drove `next build` + `next start` of `a23db59b` on `127.0.0.1:3191`. The server's `allowedOrigins` gained `http://127.0.0.1:3191` and `http://localhost:3191`, set as `qa-admin` on the synthetic server only. The journeys cover the main flows:

- sign-in, refresh and reconnect;
- browsing and search;
- first progress from playback, and listening sent after the server was unreachable;
- reload and resume, finishing and discarding;
- realtime progress from another device;
- bookmarks;
- PDF, EPUB and comic readers;
- download permission;
- podcast episode progress.

`deployment.spec.ts` was not run: it needs the nginx same-origin deployment on other ports. The T3 preview could sign in and reach the library on `candidate`, but its snapshot tool failed, so it captured no screenshot.

Raw outputs, Playwright traces and failure screenshots, container inspects and logs are kept privately, outside the repository.

## Reproduce

Requires cached images only. With the production client on 3191 (`npm run build && npx next start --port 3191 -H 127.0.0.1` in `web`):

```sh
R=docs/modernization/evidence/web-real-server/server-combined/run-matrix.sh
$R progress stock candidate session
$R seams
TRIES=10 $R race                    # against the image the last step left running
$R browser session $(cd web && ls e2e/*.spec.ts | grep -v deployment)
ABS_WEB_ENGINES=firefox,webkit $R browser session e2e/connect.spec.ts e2e/session.spec.ts e2e/playback.spec.ts e2e/podcasts.spec.ts
```

`progress` and `seams` exit 1 because they include the expected REDs of `stock` and `candidate`.

## Not covered

- Apple's affected native cases on `session` (they passed on `candidate`, which does not carry over). The Android lane ran `RealServerJourney` a-d on `session`, with the image ID and both file hashes checked in the container: 4 of 4 passed, exit 0, client `4bbbacde` (`a23db59b` plus localization only);
- owner servers, libraries and accounts;
- physical devices;
- `markAsFinishedPercentComplete` through sessions, and a streamed session closed with sync data (`closeSession` calls the same `syncSession`).
