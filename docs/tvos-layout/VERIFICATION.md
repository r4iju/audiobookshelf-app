# Verification

Synthetic pooled TV: tvOS 27, Siri Remote through XCTest. No screenshots or owner data.

Before the fix, a delayed successful save moved the title by 39.5 points (`/tmp/loft-tv-flicker-red5.xcresult`). Excluding live transmissions from the unanswered-save presentation made that test pass with zero movement (`/tmp/loft-tv-flicker-green1.xcresult`). A genuine unknown outcome still changed the centered hero from y=250 to y=286 (`/tmp/loft-tv-flicker-recovery-red2.xcresult`), before adding the top anchor.

A top frame alone still let recovery text compress the hero by 7 points (`/tmp/loft-tv-flicker-green2.xcresult`). A top-aligned scroll view instead gives playback content its intrinsic height. The final layout run is `/tmp/loft-tv-flicker-green3.xcresult`: all TV app unit tests, three layout journeys, and native playback controls. Home y=284.5, successful save y=257, and unknown save y=257 remain stationary. Unsent-listening relaunch and requested/confirmed server restart recovery passed separately in the green2 bundle. Final totals and merged-source QA/deployment are recorded on the patch PR.

The patch leaves the persisted ledger schema and `unresolved` ordering barrier unchanged. The new in-memory active set is presentation state; retained writes after relaunch remain unanswered. Internal archive selection accepts `all`, `ios`, or `tv`, and defaults to both products as before.

The signed build initially failed because Apple's bundle identifier filter returned a similarly named QA registration before the exact preview identifier. The provisioner now matches identifiers exactly and uses the existing private App Store Connect proxy helper. Signed Release build4 subsequently succeeded with application-identifier `C7X9BCC7LP.com.forkzed.audiobookshelf.tv`.
