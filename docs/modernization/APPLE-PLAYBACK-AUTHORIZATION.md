# Apple playback: token renewal, revocation, interruptions and route changes

This covers stories 12, 14 and 34 on the shared Apple player (`apple/Playback/ApplePlayback.swift`), which both the iPhone/iPad app and the TV app use. All of it was checked locally against the synthetic `verification/fixture.py` server on an owned simulator, "Audiobookshelf PlaybackFinal iPhone QA" (iOS 27). No hardware, live server or owner data was involved, and no physical or live-server gate is closed by this work.

## Behaviour

- **Token renewal while streaming (story 12).** Streams carry a bearer token fixed when each file loads. If the server stops accepting that token, the next file fails with HTTP 401. The player now:
  - pauses;
  - asks the server who is signed in, which renews the login through the client's single shared refresh;
  - reloads the file with the new token at the same position, or at the latest position the listener asked for while the renewal waited.
  
  The renewed token is saved, and listening continues under the same account. The renewal is attempted only once per failed file. If the token did not change, the old "Audio could not be played" error is kept.

  While a renewal waits, the failed file is not treated as the position: a seek records its target and shows it, and the reload starts there. Pausing during the wait reloads without playing.
- **Revocation (story 14).** If the server no longer accepts the login, including its refresh, the player:
  - stops audio, whether streamed or downloaded;
  - sets `needsSignIn`;
  - keeps the open media.

  `resume()`, `seek(autoplay:)` and an interruption ending with `shouldResume` cannot start audio again until someone signs in.
  - **On iPhone/iPad.** The app now asks "Sign in again", in an alert over the mini player or a button in the full player. This opens sign-in for that server and username, with the recovery message. The TV already had its own prompt (`RootView`, `SignInView(reauthenticating:)`).
  - **Listening.** Unsent listening stays in the per-account journal. If another account signs in, it does not send that listening. It is sent when the revoked account signs in again.
- **Interruptions and route changes (story 34).** The handlers were already correct, so no production change was made. The observations are below.

## Regressions, written before the fixes

Run them with `apple/scripts/verify-playback-authorization.sh`. The script:
- refuses to start if port 51769 is taken;
- runs the fixture unit tests;
- starts the fixture;
- creates the simulator on first use;
- restores the regenerated pbxproj when it exits.

New fixture controls:
- `POST /__fixture__/expire-access` makes the server reject the current access tokens. Refresh then issues `fresh-rN`. With `{"refreshDelay": seconds}`, each refresh is held back that long.
- `POST /__fixture__/revoke {"username"}` rejects that account's access token and refresh until it signs in again.
- `configure {"mode": "long-audio"}` lengthens the synthetic book to 120 s (files of 8 s and 112 s). Only the revocation journey uses it; every other mode keeps the 20 s book.
- Every observed request now records the status it was answered with.

`configure` resets all of them, and revocations are listed in the observations.

| Check | Before the fix (base `000ea3c8`) | After |
| --- | --- | --- |
| `verification.test_fixture` `MidSessionTokenJourney` (3) | 3 errors, no such controls (`/tmp/abs-playback-final-fixture-red.log`) | 8/8 OK (`/tmp/abs-playback-final-fixture-green.log`) |
| `MidSessionTokenJourney` long-audio and request status (2) | 1 error (mode rejected), 1 failure (no status) (`/tmp/abs-playback-final-longaudio-fixture-red.log`) | 10/10 OK (`/tmp/abs-playback-final-longaudio-fixture-green.log`) |
| `MidSessionTokenJourney` refresh delay (1) | Failed: refresh answered at once (`/tmp/abs-playback-final-refresh-delay-fixture-red.log`) | 11/11 OK (`/tmp/abs-playback-final-refresh-delay-fixture-green.log`) |
| `PlaybackAuthorizationTests.testExpiredAccessDuringStreamingRenewsOnceAndPlaybackContinuesIntoTheNextFile` | Failed: stuck at 8.0 s with "Audio could not be played" | Passed |
| `PlaybackAuthorizationTests.testRevocationDuringDownloadedPlaybackStopsAudioAtTheNextSync` | Failed: audio kept playing, and `resume()` restarted it | Passed |
| `PlaybackAuthorizationTests.testRevocationDuringStreamingStopsAudioAsksToSignInAndKeepsListeningForThatAccount` | Passed at base, see below | Passed |
| `PlaybackAuthorizationTests.testSeekDuringDelayedRenewalIsWhereTheReloadedFileStarts`, on `84a9047e` | Failed: stalled seeking at 8.0 s, latest seek to 14 s lost (`/tmp/abs-playback-final-latest-seek-red.log`) | Passed |
| `PlaybackAuthorizationJourney.testRevokedLoginStopsPlaybackAndSigningInAgainDeliversItsListening` (app UI), first version | Failed: "No way to sign in again" (`/tmp/abs-playback-final-journey-red.log`) | Replaced, see below |
| The same journey on the 120 s book. RED applies `evidence/playback-final/revocation-handling-removed.patch` to the final source. | Failed: prompt shown but still "Playing", book position 24 s to 27 s in 3 s (`/tmp/abs-playback-final-journey-long-red.log`) | Passed on the final source: "Paused" at 23 s of 120 (`/tmp/abs-playback-final-journey-long-green.log`) |

Logs after the fixes:
- the four unit tests, three iterations each, 12/12 on the final source (`/tmp/abs-playback-final-latest-seek-green.log`);
- the full NativeTests suite, 68/68 (`/tmp/abs-playback-final-nativetests-full-3.log`).

The first fixed version renewed the token, but in the full suite it stalled. A seek started by the file change was still waiting on the failed item, and the reload joined it. Cancelling that item's pending seeks fixed it. The failed full run is in `/tmp/abs-playback-final-diag1.log`.

Independent review of `84a9047e` then found that a seek made while the renewal waited went to the failed item. The reload joined that stuck seek, so playback stalled at the failure position and the requested one was lost. The fixture shows the renewal succeeding and `/audio/1` never being requested again (`/tmp/abs-playback-final-latest-seek-red-requests.txt`). That red run was stopped by its process ID after both assertion failures were printed, because the stuck seek also held the runner.

### Revocation journey

The first journey revoked during a 20 s book. In one run, the UI steps took 3.5 s, so the revocation landed after the last file was buffered and the book ended at 20 s before a sync (`/tmp/abs-playback-final-journey-green2.log`). Paused at the end of a book proves nothing, so the journey now:
- configures `long-audio`, a 120 s book;
- checks the full player says "Playing" and its elapsed time advances before revoking;
- reads the elapsed time right after the revocation;
- expects the "Sign in again" button and "Paused" within the server-contact contract: the 15 s sync interval plus 3 s for the one-second tick, the rejected request's round trip and whole-second display;
- asserts the stop is at most that far past the revocation, and more than 60 s before the book ends;
- asserts the fixture answered a request after the revocation with 401;
- asserts that 3 s of waiting and the play control both leave audio paused at the same second;
- opens sign-in and checks the server address and username are the revoked account's, with the recovery message;
- signs in, then asserts no audio file is requested, nothing plays, and the held listening is delivered for `qa` within 2 s of the stopped position.

In the passing run, the requests after the revocation were a realtime socket (401), the periodic `local-all` sync (401) and `/auth/refresh` (401). Audio was "Paused" at 23 s, in the 112 s file, after which sign-in requested nothing from `/audio/` (`/tmp/abs-playback-final-journey-long-green-observations.json`; its reports were cleared by the journey's teardown `configure`). The passing assertion ties the delivered `local-all` report for `qa` to within 2 s of the stop.

Notes on how the evidence was produced:
- The first version of the long journey read `playback-elapsed`, which is the chapter's time, so its comparison with the delivered book position failed although audio had stopped correctly. It now reads `total-elapsed`. The RED and GREEN results above both use this final journey.
- An earlier RED, with the first long journey on `84a9047e`, failed the same way and is superseded.
- One RED attempt did not reach the simulator, because the host briefly refused loopback connections (`Errno 49`) in the fixture pre-check (`/tmp/abs-playback-final-journey-long-red-host-errno49.log`). It was rerun once that cleared.
- The xcodebuild runs that hung after their tests finished were stopped by their own process ID; the test results had already been printed.

Screenshots, kept local and showing synthetic data only: `/tmp/abs-playback-final-evidence/revoked-login-while-listening.png` and `sign-in-again.png`. While sign-in is open, the mini player stays visible, and its play button does nothing until a sign-in.

The streaming revocation test passed at base only by accident, and its log is `/tmp/abs-playback-final-auth-red.saved.log`. At base:
1. the next file failed with a generic error;
2. the following sync then set `needsSignIn`;
3. nothing in the UI let the listener act on it, which the journey shows.

The unit tests use real decoding of fixture audio through `AVPlayer`, the production `APIClient` with in-memory credentials, and the production listening journal.

### Account A to B to A

The streaming revocation test does the following:
1. Revokes `qa` mid-stream.
2. Uses the connection screen's order to sign in `qa-other`: `suspendForConnectionChange`, then login, then `restoreListening`. It asserts that no report is sent as `qa-other`.
3. Signs `qa` in again and asserts that the held listening is delivered with `userId` `qa` at the stopped position, within 0.6 s.

The renewal test asserts:
- exactly one `/auth/refresh` after the expiry;
- the renewed token was saved;
- the delivered report belongs to `qa` and lies past 9.5 s.

## Interruption and route probe (story 34)

`evidence/playback-final/InterruptionRouteProbe.swift` was compiled into the NativeTests runner only for the observation. It is kept as evidence and is not part of the test target.
- It posts `AVAudioSession.interruptionNotification` and `routeChangeNotification` to the production handlers while downloaded synthetic audio actually decodes.
- Log: `/tmp/abs-playback-final-interruption-probe.log`, 9/9 passed. Recorded positions are in seconds.

| Event | Observed |
| --- | --- |
| Interruption began, then ended with `shouldResume` | Paused at 6.02, the position held for 2 s, then resumed from 6.02 (7.00 one second later) |
| Ended without `shouldResume` | Stayed paused at 6.03 |
| Began with reason `appWasSuspended`, ended with `shouldResume` | Stayed paused at 6.02 |
| The listener paused before the interruption | Not started by its end |
| The listener resumed and then paused during the interruption | Not started by its end (6.46) |
| Stopped during the interruption | Nothing resumed, no session |
| Interruption of 11 s, ended with `shouldResume` | Resumed 3 s earlier (held 6.04, resumed at 3.04), like a manual resume after a long pause |
| Route `oldDeviceUnavailable` (headphones removed) | Paused at 6.02; `newDeviceAvailable` did not resume; 6.02 delivered to the server |
| Route reasons 1, 3, 4 and 8 | Kept playing |

## Limits

- **Simulated system events.** The probe posts the notifications itself. It does not show whether real calls, Siri, alarms, CarPlay or Bluetooth produce those notifications on hardware. `mediaServicesWereReset` is not handled. Physical interruption, headset and Bluetooth checks remain open.
- **When revocation is noticed.** Revocation is detected only at the next server contact: the periodic sync (every 15 s), a file load, or a pause. Fully buffered streaming audio, or downloaded audio, can play until then, up to about 15 s.
- **After signing in again.** The connection change closes the player, so the listener reopens the book. Its listening is delivered, and the server position follows from it.
- **Fixture tokens.** They are opaque strings. Renewal is triggered by the server rejecting a token before the client expects expiry. The client's own JWT `exp` pre-check is unchanged and is covered elsewhere.
- **TV.** It shares the player change and builds (`/tmp/abs-playback-final-tv-build-2.log`, BUILD SUCCEEDED with the final player). The TV UI journeys were not rerun, and `tvos/QA.md` check 9 (login expiry) remains open.
- **Compatibility gate, still failing.** `verification/test_upgrade_gate.py` fails at the base commit and here, so final combined readiness is not met (`/tmp/abs-playback-final-upgrade-gate-base.log`). The exact reason, from a detached checkout of `000ea3c8` (`/tmp/abs-playback-final-upgrade-gate-diagnosis.log`):
  - both Swift `client-journey` runs pass, legacy and modern auth, TVCore, all seven workflows;
  - `node verification/realtime/journey.mjs baseline` exits 1 with `ERR_MODULE_NOT_FOUND: Cannot find package 'socket.io-client' imported from plugins/server.js`, because these worktrees have no `node_modules`;
  - `verification/compatibility.py` catches the resulting parse error, prints its generic "could not complete" report on stdout and exits 2, so the test shows an empty stderr.

  No packages were installed here. Root will address it when integrating the final source.
