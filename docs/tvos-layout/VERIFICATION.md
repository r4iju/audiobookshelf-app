# Verification

Synthetic pooled TV: tvOS 27, Siri Remote through XCTest. No screenshots or owner data.

Before the fix, a delayed successful save moved the title by 39.5 points (`/tmp/loft-tv-flicker-red5.xcresult`). Excluding live transmissions from the unanswered-save presentation made that test pass with zero movement (`/tmp/loft-tv-flicker-green1.xcresult`). A genuine unknown outcome still changed the centered hero from y=250 to y=286 (`/tmp/loft-tv-flicker-recovery-red2.xcresult`), before adding the top anchor.

The final combined run is `/tmp/loft-tv-flicker-green2.xcresult`: all TV app unit tests, the three layout journeys, unsent-listening relaunch, and requested/confirmed server restart recovery. Final results and deployment are recorded on the patch PR after completion.

The patch leaves the persisted ledger schema and `unresolved` ordering barrier unchanged. The new in-memory active set is presentation state; retained writes after relaunch remain unanswered. Internal archive selection accepts `all`, `ios`, or `tv`, and defaults to both products as before.
