# Leafwake candidate verification, October 4, 2026

This historical candidate report is superseded for the replacement release by [RELEASE-STATUS.md](RELEASE-STATUS.md). The current QA runner uses the new unified image. The stock-server results below describe the earlier unmodified 2.30.0 run, not the replacement backend.

This is preparation evidence, not public release clearance.

## Stock server

The Cast-free Android variant was exercised on an API 36 emulator against the isolated, unmodified Audiobookshelf 2.30.0 image used by the historical version of `android-native/scripts/verify-real-server.sh`. Synthetic accounts/media only; the owner's server was not modified.

The existing `RealServerJourney` assertions produced three passes and one failure:

- Password sign-in, catalog browsing, streaming into the second file, and server position agreement: passed.
- PDF page turn stored on the server: passed.
- Downloaded audio played with networking disabled, then progress sent after reconnect: passed.
- A title's first progress created by listening to its end offline: failed. The server stored the final position but did not set `isFinished`. This reproduces the existing 2.30.0 defect recorded in `android-native/HANDOFF.md`; no assertion was removed or marked ignored.

Two harness corrections precede these results: scroll the sign-in button into view above the keyboard, and select the whole-book clock before comparing positions across files. The automation helper was closed while instrumentation owned UiAutomation.

## Device and build scope

The previous owner-signed candidate (`f605f9c437f87d340d23121bdc5dd65635159113`) installed on the emulator and on an Android 16 OnePlus phone. Manual emulator checks covered pre-login privacy access, sign-in, browsing, streaming, and Cast controls being absent. The physical phone was locked, so no physical playback acceptance is claimed.

A narrow emulator screen exposed a wrapped Bookmarks label. The tool row now uses `FlowRow`; the scoped source review found no blockers. Preview core/unit tests and preview instrumentation compilation pass after the Cast journey was moved to its preview-only source set. No new tests were added.

Public publication remains held on the stock-server/product acceptance gates. A signed artifact or a Play draft is not a completed release. Apple and Chromecast licensing approval is pending in upstream discussion #2051.

## Store setup

Leafwake (`com.forkzed.leafwake`) is registered as free, with English (United Kingdom) as its default language, in the existing Barbellry developer account. Automatic installer protection is disabled. Service-account read access and reversible edit creation/deletion pass. No artifact has been uploaded or rolled out.

Play created a Google-managed signing identity when the app record was created. The local signing key is separate. Direct APKs with the local signer cannot update a Play-signed installation in place; resolve signing/distribution strategy before distributing direct APKs.

The personal account requires 12 opted-in closed testers for 14 continuous days before applying for production access.
