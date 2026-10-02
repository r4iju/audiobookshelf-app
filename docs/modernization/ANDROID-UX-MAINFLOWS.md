# Android everyday interactions

UX lane based on `d2d7543be26f7e9a70c9508008ba6fb6ce3f3c0c`, issue #131.
Uses the existing Material semantic colors, shapes and typography; the parallel
UI lane supplies the shared neutral surfaces and orange accent.

| Before | After |
| --- | --- |
| Accounts and settings only on Library | Available on Search and Downloads too; Back returns to the originating tab |
| Unlabelled visual close icon beside minimize; no mini-player close | Shared overflow in both modes contains “Stop and close player” |
| Prominent orange lock text competes with playback | Neutral labelled lock icon toggle exposes checked state |
| Large artwork pushes player actions down at scaled text | Artwork shrinks as text grows; transport targets remain at least 48 dp |
| Player tools and active timer compete in one row | Tools wrap; remaining time belongs to the Sleep action |
| Five speed presets squeeze into equal widths | Wrapping chips show the selected rate |
| Timer adjustments and bookmark heading squeeze horizontally | Timer actions wrap and scroll; bookmark add action sits below its heading |
| Download actions squeeze titles; retry is icon only | Title/status above wrapping actions, visible Play/Retry/Cancel labels and download percentage |
| Download folder actions can compete for width | Folder actions wrap |
| Only preference switches respond to touch | Full labelled row toggles with one switch semantic action |
| Import action between storage and car preferences | Import grouped with support tools |

Local offline debug build and instrumentation-source compilation passed.
One manual affected-flow pass inspected actual screenshots at 320 dp, with
100% and 150% text: player/tools, timer controls, bookmark heading, minimize
and close, navigation/settings, synthetic download failure/retry and local
playback. Existing journey assertions are unchanged; their close helper now
opens the overflow first. No new tests or broad suite/localization rerun.

Private screenshots, XML, fixture/build logs and APK are retained outside the
repository in the delivery coordination directory. This pass used synthetic
emulator data only. Physical-device, TalkBack, migration and existing readiness
gates remain open; merged UI/UX packaging and owner delivery belong to root.
