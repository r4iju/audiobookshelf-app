# Server candidate: first progress from a local session (Audiobookshelf 2.30.0)

A candidate only. It has not been applied to any owner server and nothing here is resolved on one.

## Defect in pinned 2.30.0

Image `ghcr.io/advplyr/audiobookshelf@sha256:6fbd7dc95d53c6e168ce69e760b87c334e3b9ba88bf7b8531ed5a116d5d6da03`, `server/models/User.js` SHA-256 `2174eec7b50b43ed3e0da55c4e54edaa90f9f98c30cefb9b4819430b744f6a1d`.

`POST /api/session/local-all` passes only `duration`, `currentTime`, `progress` and `lastUpdate` (`PlaybackSession.mediaProgressObject`) to `User.createUpdateMediaProgressFromPayload`. The session JSON cannot carry a completion field: `PlaybackSession.construct` copies fixed fields only.

- **Existing progress:** `MediaProgress.applyProgressUpdate` marks the title finished when less than `markAsFinishedTimeRemaining` (default 10 s) is left, or past `markAsFinishedPercentComplete`. It then stamps the row with the session's `lastUpdate`. `syncLocalSession` skips a session older than the stored row, which is what protects newer listening from another device.
- **First progress:** the create branch skips both steps. It takes `isFinished` only from the payload, which is never set on this path. It also stamps the row with the server's time, not the session's.
- **Effect on a book finished offline:** the book reaches the server at its end but not finished. Sending the session again is skipped as older, because the row carries the server's later time.
- **Effect on newer sessions:** a genuinely newer session from another device, recorded before that server time, is also rejected.

The Android, Apple/tvOS and legacy Android clients all send this same session shape.

## Candidate

`first-progress-candidate.patch` (SHA-256 `6313948fcce74d83ad7b320da1db0b587bb81557892cabdaad1207237cdf7367`). After creating the row, the create branch runs the same `applyProgressUpdate` used for existing progress. New progress therefore gets the same finished rule and the payload's `lastUpdate`. Session syncs also pass the library's thresholds. Patched `User.js` SHA-256: `e3cfa99a946b1c61c039407f50f9d6e1ba81c196d01e01bac732439a6bfbff10`.

The patch also changes progress first created through the other callers of the same function. These are `PATCH /api/me/progress` (and its batch form) and the sync of a streamed session (`syncSession`). Such progress now follows the rules an update already follows:
- A position within 10 s of the end is finished.
- A supplied `lastUpdate` is kept.
- With no `lastUpdate`, the row is stamped with the server's time, as before. A streamed session sends no `lastUpdate`.
- As for an update, an item shorter than the 10 s threshold is finished by its first progress.
- As for an update, a PATCH that creates progress within 10 s of the end is finished even if it sends `isFinished: false`. PATCH payloads carry no library thresholds, so 10 s applies there; the library's thresholds apply only to session syncs.
- `applyProgressUpdate` sets the payload's raw values on the row, as an update does. A `null` or string `currentTime` that create would have cleaned up can now be stored.
- First progress now carries the session's time. A device whose clock runs ahead future-dates the row, and older-looking session syncs from other devices are then skipped until that time, as already happens for existing progress.
- `createdAt` and `finishedAt` are still the server's time of the sync, not of the listening, so `finishedAt` of a book finished offline is its sync date.
- The insert and the update are separate writes without a transaction, as elsewhere in this function. If the update fails, the row exists without the in-memory list holding it.
- Reading-only progress has no duration and is never finished by the rule.

Applying it after the earlier Apple user-cache candidate `usercache-candidate-569a673a.patch` (SHA-256 `1c541a0b…8507`) was tried: both apply and the combined file passes `node --check`. The combination with Apple's final patch (`b59ea8c8`) has not been tried, and no combination has run against a server.

## Checks

`run-check.sh baseline|candidate|down` runs `first-progress-check.mjs` in this lane's own throwaway container (`abs-android-qa`, 127.0.0.1:28870). The container is freshly seeded with the synthetic library and the synthetic `qa` account by the unmodified `web/qa/server.mjs`. For the candidate, the patch is applied to the container's `User.js` before a restart. Before starting anything, `android-native/scripts/require-local-image.sh` stops unless the exact pinned image is already cached and `server.mjs` still runs that same reference, because `server.mjs`'s `docker run` would pull a missing image. `android-native/scripts/verify-real-server.sh` uses the same guard.

The check covers eight cases:
- a first session at its end is finished and keeps its own time;
- the same session sent again changes nothing;
- a first session part way through is not finished and keeps its own time;
- a first session from another device keeps its own time;
- an older offline session does not replace newer listening from another device;
- a newer offline session that reached the end finishes the title;
- a podcast episode's first session at its end is finished, at the episode's own duration;
- reading progress created through PATCH is not finished. This passes on both servers: it sends no duration, so it only guards against a regression.

| Server | `first-progress-check.mjs` | Android `RealServerJourney` (client at f583677a) |
| --- | --- | --- |
| Pinned 2.30.0 | RED, 7 of 8 fail | a-c pass, d fails (evidence `real-server-6-d`) |
| 2.30.0 + candidate | 8 of 8 pass | a-d pass, 4 of 4 |

The evidence is outside the repository, under `/Volumes/ai-ssd/developer-caches/abs-android-native-claude/artifacts/`:
- `completion-contract/`: the first check outputs `red-baseline-2.30.0.txt` and `green-candidate.txt`, and the script runs `script-baseline.txt` and `script-candidate.txt`.
- `candidate-first-progress-realserver/`: the Android run on the candidate, with its server log.

Not covered:
- an actual owner server or library;
- the combination with the Apple user-cache candidate on a running server;
- `markAsFinishedPercentComplete`, invalid or future `lastUpdate` values, streamed sessions and PATCH-created audio progress are not covered by `first-progress-check.mjs`. Streaming is exercised only by `RealServerJourney` a, whose first sync is far from the end.
