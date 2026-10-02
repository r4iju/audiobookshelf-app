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

`first-progress-candidate.patch` (SHA-256 `6313948fcce74d83ad7b320da1db0b587bb81557892cabdaad1207237cdf7367`). After creating the row, the create branch runs the same `applyProgressUpdate` used for existing progress. New progress therefore gets the same finished rule, the library's thresholds and the payload's `lastUpdate`. Patched `User.js` SHA-256: `e3cfa99a946b1c61c039407f50f9d6e1ba81c196d01e01bac732439a6bfbff10`.

The patch also changes progress first created through the other callers of the same function. These are `PATCH /api/me/progress` (and its batch form) and the sync of a streamed session (`syncSession`). Such progress now follows the rules an update already follows:
- A position within 10 s of the end is finished.
- A supplied `lastUpdate` is kept.
- With no `lastUpdate`, the row is stamped with the server's time, as before. A streamed session sends no `lastUpdate`.
- As for an update, an item shorter than the 10 s threshold is finished by its first progress.
- Reading-only progress has no duration and is never finished by the rule.

It applies cleanly after the Apple user-cache candidate (`apple-real-server/server-usercache/usercache-candidate-569a673a.patch`, SHA-256 `1c541a0b…8507`), which changes other parts of the same file. The combined file passes `node --check`. The combination has not been run against a server.

## Checks

`run-check.sh baseline|candidate|down` runs `first-progress-check.mjs` in this lane's own throwaway container (`abs-android-qa`, 127.0.0.1:28870). The container is freshly seeded with the synthetic library and the synthetic `qa` account by the unmodified `web/qa/server.mjs`. For the candidate, the patch is applied to the container's `User.js` before a restart.

The check covers eight cases:
- a first session at its end is finished;
- a first session part way through is not finished;
- the same session sent again changes nothing;
- an older offline session does not replace newer listening from another device;
- a newer offline session that reached the end finishes the title;
- a podcast episode is finished at its own duration;
- reading progress created through PATCH is not finished;
- each row keeps its session's own `lastUpdate`.

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
- streamed sessions and PATCH-created audio progress are not covered by `first-progress-check.mjs`. Streaming is exercised only by `RealServerJourney` a, whose first sync is far from the end.
