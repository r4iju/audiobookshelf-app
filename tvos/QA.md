# Apple TV verification

Last verified October 1, 2026 (after the review fixes) on the Studio with Xcode 27.0 (27A266a), the tvOS 27 simulator `Audiobookshelf TV QA` (`00DD108F-2435-4FEC-9C37-3E62861A0EF6`, Apple TV 4K 2nd generation, 1080p) and the synthetic fixture `verification/fixture.py`, which reports server version `2.30.0-fixture`. Fixture titles, accounts and audio are synthetic; no live library or credentials were used.

## Automated evidence

| Check | Command | Result |
| --- | --- | --- |
| TV core contracts | `swift test --package-path tvos/Core` | 15 passed |
| Remote-driven journeys | `./tvos/scripts/verify-ui.sh` | 13 passed, 0 failed (338 s) |
| Signed device build and install | `./tvos/scripts/deploy.sh --no-launch a5ef39a5001ef59dec9c2fa15838447215252137` | Release build signed by team `C7X9BCC7LP`, `codesign --verify --deep --strict` passes, installed on Living Room TV (tvOS 18.6) |

The journeys run the Debug app with no test-only code paths beyond the launch-time reset. They operate it only through `XCUIRemote` presses (directions, Select, Menu, Play/Pause) and keyboard entry. They then assert what the screen shows and what the fixture server observed. Every journey was written first. The red run on October 1, 2026 against the previous TV app failed all 13 journeys before any implementation.

| Story | Journey | Proves |
| --- | --- | --- |
| #26 | `CatalogJourney.testContinueListeningOpensDetailsAndBackRestoresFocus` | Home shelf → details with narrator and server progress → Back returns focus to the same tile |
| #26 | `CatalogJourney.testLibraryLoadsNextPageAsFocusMovesDown` | Moving down loads page 2 (61st title) with no Load more button; server saw pages 0 and 1 |
| #26 | `CatalogJourney.testServerSearchFindsTitlesOutsideLoadedPage` | Search keyboard → server search → a title outside the first page → details |
| #26 | `CatalogJourney.testFilterAndSortAreAppliedByTheServer` | Genre filter and Z–A sort are applied by the server through the menus |
| #26, #28 | `CatalogJourney.testCatalogFailureRecoversWithRetry` | Server outage shows a recovery message; Try again recovers after the server returns |
| #26 | `CatalogJourney.testTrustedHTTPSServerAndLongMetadata` | HTTPS through a CA trusted by the device only, reverse-proxy path, very long title, missing cover placeholder, supported sign-in explanation |
| #27 | `PlaybackJourney.testResumeShowsChapterAndTotalProgressAndRemoteToggles` | Resume at server position, chapter title/number, remote Play/Pause pauses and resumes the same session |
| #27 | `PlaybackJourney.testNextChapterCrossesFilesAndLeavingThePlayerKeepsPlaying` | Chapter list seek into the second audio file; leaving Now Playing for Home keeps listening |
| #27 | `PlaybackJourney.testSpeedSelectionAndExplicitStopClosesTheSession` | Speed menu; Stop closes the server session |
| #27 | `PlaybackJourney.testNaturalEndShowsFinished` | Multi-file book plays to its natural end and reports Finished at 0:20 |
| #28 | `RecoveryJourney.testUnsentListeningSurvivesTerminationAndSyncsOnRelaunch` | With the server rejecting progress, listen, pause and terminate. Relaunch sends the saved listening once; details show the new server position; a second relaunch sends nothing more |
| #29 | `PodcastJourney.testEpisodesSortAndPlaySeparatelyFromBooks` | Newest/oldest episode order, episode details, playback, server listening recorded for the episode only |
| #29 | `PodcastJourney.testMarkEpisodeFinishedUpdatesOnlyThatEpisode` | Mark as finished sends `PATCH /api/me/progress/podcast/episode-morning`; only that episode shows Finished |

Screenshots captured by those journeys:

![Details](evidence/detail.png)
![Library after automatic pagination](evidence/library-end.png)
![Search](evidence/search.png)
![Filtered and sorted](evidence/filtered.png)
![Long title and missing cover over HTTPS](evidence/long-title.png)
![Catalog failure](evidence/catalog-error.png)
![Now Playing](evidence/now-playing.png)
![Episodes](evidence/episodes.png)

## Remaining physical-TV acceptance

Installing the build is not acceptance. These checks need a person using the Siri Remote on the paired Living Room TV, against the real server (2.30.0) over the trusted homelab CA. None of them has been performed for this build:

1. Sign in with the remote; confirm the HTTPS connection, and confirm that a wrong password or an unreachable address shows the recovery text.
2. Across-room readability: titles, focus highlight, progress bars and the Now Playing timeline from the sofa; long real titles and missing covers.
3. Browse Home, each library (sort, filter, scroll a large library to its end), Search and details; Back from every screen returns to the expected focus.
4. Audiobook playback of real codecs (for example m4b/mp3) including a multi-file book: file transitions, rapid skips, chapter list and previous/next chapter, speed changes, natural end.
5. System controls: the Siri Remote Play/Pause on other tabs, the TV Control Center Now Playing card, and any AirPlay/HomePod route change act on the same session.
6. Podcast episode chosen with the remote plays real audio; the server shows that episode's progress only.
7. Durability on hardware: listen, force-quit from the app switcher, relaunch, then confirm server progress and resume on the iPhone without double-counted listening time. Repeat with the network disconnected while listening, then reconnected.
8. Leaving with the TV/Home button pauses and saves; the screen saver and Control Center keep listening.
9. Login expiry: after server-side token revocation, the TV asks for the password and then sends the saved listening.

These behaviours have no simulator journey yet and rely on the physical checks above: rapid skips across file boundaries (check 4), login expiry (check 9), progress bars on podcast tiles, and Home/Search when one of several libraries fails. The synthetic fixture has no mode that fails a single library or revokes a token.

See [HANDOFF.md](HANDOFF.md) for the hardware storage caveat that affects check 7.
