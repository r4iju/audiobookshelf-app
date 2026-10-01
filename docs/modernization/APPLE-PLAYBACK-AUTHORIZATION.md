# Apple playback: token renewal, revocation, interruptions and route changes

This covers stories 12, 14 and 34 on the shared Apple player (`apple/Playback/ApplePlayback.swift`), which both the iPhone/iPad app and the TV app use. All of it was checked locally against the synthetic `verification/fixture.py` server on an owned simulator, "Audiobookshelf PlaybackFinal iPhone QA" (iOS 27). No hardware, live server or owner data was involved, and no physical or live-server gate is closed by this work.

## Behaviour

- **Token renewal while streaming (story 12).** Streams carry a bearer token fixed when each file loads. If the server stops accepting that token, the next file fails with HTTP 401. The player now:
  - pauses;
  - asks the server who is signed in, which renews the login through the client's single shared refresh;
  - reloads the file with the new token at the same position.
  
  The renewed token is saved, and listening continues under the same account. The renewal is attempted only once per failed file. If the token did not change, the old "Audio could not be played" error is kept.
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
- `POST /__fixture__/expire-access` makes the server reject the current access tokens. Refresh then issues `fresh-rN`.
- `POST /__fixture__/revoke {"username"}` rejects that account's access token and refresh until it signs in again.

Both are reset by `configure`, and revocations are listed in the observations.

| Check | Before the fix (base `000ea3c8`) | After |
| --- | --- | --- |
| `verification.test_fixture` `MidSessionTokenJourney` (3) | 3 errors, no such controls (`/tmp/abs-playback-final-fixture-red.log`) | 8/8 OK (`/tmp/abs-playback-final-fixture-green.log`) |
| `PlaybackAuthorizationTests.testExpiredAccessDuringStreamingRenewsOnceAndPlaybackContinuesIntoTheNextFile` | Failed: stuck at 8.0 s with "Audio could not be played" | Passed |
| `PlaybackAuthorizationTests.testRevocationDuringDownloadedPlaybackStopsAudioAtTheNextSync` | Failed: audio kept playing, and `resume()` restarted it | Passed |
| `PlaybackAuthorizationTests.testRevocationDuringStreamingStopsAudioAsksToSignInAndKeepsListeningForThatAccount` | Passed at base, see below | Passed |
| `PlaybackAuthorizationJourney.testRevokedLoginStopsPlaybackAndSigningInAgainDeliversItsListening` (app UI) | Failed: "No way to sign in again" (`/tmp/abs-playback-final-journey-red.log`) | Passed (`/tmp/abs-playback-final-journey-green3.log`), stopped at 8 s of 20 |

Logs after the fix:
- the three unit tests, three iterations each, 9/9 (`/tmp/abs-playback-final-auth-fix-iter.log`);
- the full NativeTests suite, 67/67 (`/tmp/abs-playback-final-nativetests-full-2.log`).

The first fixed version renewed the token, but in the full suite it stalled. A seek started by the file change was still waiting on the failed item, and the reload joined it. Cancelling that item's pending seeks fixed it. The failed full run is in `/tmp/abs-playback-final-diag1.log`.

The journey's timing depends on the UI:
- In one run, the revocation landed after the 8 s file boundary because the UI steps took 3.5 s. The last file was already buffered, so audio stopped only at the end-of-book sync, at 20 s (`/tmp/abs-playback-final-journey-green2.log`).
- The journey therefore asserts only that audio is paused and stays paused. The unit tests pin the stop to the next server contact.
- Screenshots, kept local and showing synthetic data only: `/tmp/abs-playback-final-evidence/revoked-login-while-listening.png` and `sign-in-again.png`.
- While sign-in is open, the mini player stays visible, and its play button does nothing until a sign-in.

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
- **When revocation is noticed.** Revocation is detected only at the next server contact: the periodic sync (every 15 s), a file load, or a pause. Fully buffered streaming audio, or downloaded audio, can play until then. The journey revokes while the first file plays, so the next file load stops it.
- **After signing in again.** The connection change closes the player, so the listener reopens the book. Its listening is delivered, and the server position follows from it.
- **Fixture tokens.** They are opaque strings. Renewal is triggered by the server rejecting a token before the client expects expiry. The client's own JWT `exp` pre-check is unchanged and is covered elsewhere.
- **TV.** It shares the player change and builds (`/tmp/abs-playback-final-tv-build-2.log`, BUILD SUCCEEDED with the final player). The TV UI journeys were not rerun, and `tvos/QA.md` check 9 (login expiry) remains open.
- **Pre-existing failure.** `verification/test_upgrade_gate.py` already fails at the base commit (`/tmp/abs-playback-final-upgrade-gate-base.log`). It is unrelated to this change.
