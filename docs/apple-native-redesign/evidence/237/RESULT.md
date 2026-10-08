# Ticket 237 — native settings, accounts and utilities

Settings now groups Account, Listening, Reading, Appearance, Utilities and About. Playback preferences are available before listening through the existing bindings and keys. Settings and EPUB share one authoritative preference store; reader changes, import changes, relaunch and the existing bridge/awake/volume lifecycle are preserved. Saved connections identify the actual selected account by vault UUID and display its server and user. Initial, opening-library and failed/expired authentication retain independent Downloads access. Suitable existing native network, diagnostics, statistics/year, language and import Forms remain integrated rather than duplicated.

Runtime sources: `d7c337590d4aab89ad25e30cc6b712a3bff9bfa2`; test routes `0193c4a103b831bed6f44c85175e9aad4bf74a3b`; import correction `2e2cd52f1165cceee3f5799f416da301f443eabc`; final runtime/tests **`4524ee1635057f581174b4e770339fe995a093cb`**. The final correction holds the native picker selection until dismissal and completes through the original migration store token contract. Selecting an incomplete export, Cancel, swipe-dismiss, reopening and selecting a complete synthetic export all have actual evidence. IDs, numerical ranges, permissions, credentials, preference keys, domain/data/API contracts and player/reader bridges are unchanged. No TV, Android, web or backend source was edited. Origin, source URL and GPL disclosures are preserved.

## Actual red/green and regression scopes

[checks.json](checks.json) retains exact xcodebuild invocations, original log hashes, observed results and `/tmp` xcresult paths. Raw logs/videos/UUID exports stay outside Git. New behavior was tested at the installed-app XCTest seam first:

* Independent Playback preferences: genuine missing Settings destination red, then the existing progress-track invariant and relaunch pass.
* Shared Reading preferences: genuine missing Settings destination red, then Settings → reader → Settings → relaunch values pass.
* Incomplete native export selection: genuine d7 red (no error after selecting the owned incomplete Documents folder), then 2e green retaining the error/retry assertions.
* Native picker swipe-dismissal: genuine 2e red (second Choose could not reopen the picker), then final completion-contract green. A discarded binding-cancel attempt passed dismissal but failed chosen-file error, so it was not retained.

Existing account-menu entry, sidebar cell/button, lazy Form controls, Appearance routing and native switch locators were adapted only after observed reds. No assertions, account isolation, redaction, persistence, payload or recovery expectations were excluded.

| Actual replay | Precise scope |
| --- | --- |
| settings-accounts-green | 10/10: seven Preferences and three SavedConnections, including new preference journeys, network/theme/year/import and same-server account isolation/library/unsent listening. Pre-freeze runtime matches d7 behavior; final unused Settings haptic property removal followed this run. |
| presentation-sidebar | 2/2 German language persistence and actual Arabic RTL navigation. Earlier wide sidebar button-only routes were real reds. Pre-freeze scope as above. |
| presentation-actions-green | Chosen/off haptic cases pass; diagnostics immediate empty visibility fails. Subsequent native List scrolling retains clear/persistence assertions and resolves that locator. |
| diagnostics-scroll-final | 1/1 exact d7/0193: address toggle, secret exclusion/redacted report, share, clear and relaunch persistence. |
| recovery-reader-green | Connection restoration, multi-file offline/relaunch/sync and EPUB volume preference/relaunch pass. Awake test failed after natural short-fixture playback completion, with a later real inner-switch locator red. |
| reader-awake-scroll | 1/1: awake, reading/audio and reopen preferences after actual switch-thumb and scroll-to-hittable connection input correction. Pre-freeze scope. |
| auth-final | 1/1 exact d7: real owned revoked authorization stops decoding, retains pending listening, requires reauthentication and delivers it under the original user. |
| ipad-connect-final | 1/1 exact d7/0193: selected-library restoration and relaunch. |
| import-final-green-2 | 2/2 final implementation before commit/comment: incomplete error/retry and swipe/reopen. |
| import-frozen | **4/4 exact4524**, 78.109s selected suite: dismissal/reopen, incomplete error/retry and both unchanged import-before-auth/export/reauth guidance cases. |

The qualified LAN trust case failed fixture preflight because `dev.nginx.lan` was not mapped to owned loopback. Its original test/assertions remain unchanged; host/DNS/NAS configuration was not altered. Loopback auth/recovery is separate evidence, not a substitute. Failed intermediate compiler/locator/tool runs remain identified in checks rather than counted as passes. No broad unchanged suite was replayed for totals.

## Frozen builds and resource provenance

[builds-d7.json](builds-d7.json), [builds-2e.json](builds-2e.json) and [builds-4524.json](builds-4524.json) record each source's fresh isolated phone/Pad DerivedData products, Info.plist, strict signature output, installed check timestamps and all **47 file hashes**, including executable, debug dylib, Assets.car, CodeResources, reader resources and localization tables. No bundle was re-signed to conceal a resource mismatch. Final products:

* `/tmp/native237-phone-capture-current/Build/Products/Debug-iphonesimulator/AudiobookshelfNative.app`
* `/tmp/native237-ipad-capture-current/Build/Products/Debug-iphonesimulator/AudiobookshelfNative.app`

Both final products and installed bundles pass `codesign --verify --deep --strict --verbose=2`; every installed file matches before and after final capture. Frozen import XCTest installed a separate test product, so the phone capture product was reinstalled and verified before later captures. Pad capture product was likewise restored after its connection replay. Earlier source records certify their historical installed checks, not an earlier installed bundle after replacement. Parent independently checked all six frozen products and both current4524 installed bundles: eight strict signature scopes, zero resource mismatches; [independent record](parent-product-verification.json).

App version 1.0.0/build1, SDK iOS simulator27.0, binary build minimum15.0. Project/source minimum stays14.0. Full76-file Swift5 typecheck against `arm64-apple-ios14.0-simulator` passed at d7, 2e and4524 (empty logs); [exact argv](source14-arguments.txt). Generic iOS device build at4524 passed with the SDK27 build-only15.0 override. These diagnostics are not an actual iOS14 binary/runtime pass. [Commands](commands.md) preserve the build/test/capture seams.

## Original screen and interaction coverage

[captures.json](captures.json) is a list of **142 original PNG records**: **64 current4524**, **75 explicitly earlier237 source**, **two observed import defects before their corrections**, and **one historical236 before screen**. Each record has file/device/product/source/SHA256/time where available/title/category/state/phase/scope. Earlier unchanged utility composition is not relabeled final-candidate proof. Every listed original hash was verified; cleanup/debug, failed, misnamed and transition frames were excluded. No image was composited or altered.

| Covered family | Actual screen/state records |
| --- | --- |
| Connection/accounts | Phone/wide native form, actual password keyboard, wrong credentials, opening-library with Downloads, connection failure with Downloads, selected saved account, current import recovery sign-in and restored library chooser. |
| Settings/Listening/Reading | Normal phone/wide purpose groups; exact progress settings and skip-interval menus; all reader navigation/display/typography/PDF fields and volume options. Largest Playback total switch actually turned off while chapter stayed enabled and was restored; largest Reading Mirror was selected through its native menu. Existing reader audio/passage/relaunch assertions remain meaningful. |
| Appearance/language/network/notices | System/light-context, dark and black choices; haptic choices; phone/wide language lists, actual German/Arabic Settings and preference screens; cellular policies and actual largest Ask selection; preserved long source/GPL notices. |
| Diagnostics | Address/status, redacted preview, native share, clear confirmation and empty history; largest Preview actually opens its report. Owned Pad diagnostic-file obstruction produces a visible storage error; original file was restored and a successful subsequent event clears that error. No owner files were touched. |
| Statistics/year | Phone/wide normal/recent, empty/loading/failure and Retry, year selection, rankings, user/server sharing distinction, native share/Photos permission and refusal, all four user card styles and three server styles, largest year view. |
| Import | Initial/signed-in instructions, native root/folder picker, Cancel/reopen, swipe/reopen, actual incomplete-export error, complete synthetic preflight (one account/zero files), saved account reconciliation, needs-attention/reauth route and successful owned account sign-in. Folder-picker frames are captioned as picker states rather than preflight. |

Only owned synthetic fixtures on35765/35769 were used for captures, with stock generated covers from `/tmp/234-covers`. [Capture adapter](capture-fixture.py) documents explicit statistics/year empty/loading/failure/admin states; the normal fixture API/domain data is otherwise unchanged. [Synthetic complete export](synthetic-export-manifest.json) contains invented QA connection metadata and no credentials/files. Server share data intentionally omits optional totalBooksDuration, so its decoder-default zero-total/added-hours caption is synthetic missing-metadata context, not acceptance of a production dataset.

T3 used exact returned device/session/config flags. Covered-node false negatives, sheet transitions, AX runner watchdogs and hardware-keyboard visibility intermittently complicated manual capture. Fresh snapshots, screenshot-grounded native taps and actual XCTest were used; failed actions were not claimed successful. Both owned simulators unexpectedly became Shutdown during capture; only those devices were rebooted, frozen products restored, and provenance rechecked. Actual software keyboards are included where visible; focused frames with no software keyboard are not keyboard-clearance evidence.

## Localization, cleanup and remaining gates

Localization generation/check passes across30 native tables:737 distinct texts,171 legacy equivalents. German/Arabic cover729/737 (98%;8 English-only); most other non-English tables cover696/737 (94%;41 fallbacks). Maintained translations remain drafts pending native-speaker review. [New localized keys](new-localized-keys.json) includes Playback/Reading preferences, Current chapter, Custom speed, Navigation/Display/Typography, Progress display, Playback controls, Utilities, feed/device explanations, Page actions, Current account and notices. This is quantified fallback, not all-language completion or full239 acceptance.

Cleanup details are recorded in [cleanup.json](cleanup.json). Only owned capture fixtures and synthetic export artifacts were removed; diagnostic storage was restored. System text was restored to large, appearance remained light, orientation restored to portrait. Both owned T3 sessions were closed/shutdown and leases released. Keyboard persistence values are retained in [cleanup-keyboard-record.json](cleanup-keyboard-record.json): both LastUsed values are original Japanese Roman, but Pad CurrentAndNext still reports English JIS. After reboot the software keyboard did not appear, so full current keyboard selection restoration could not be visually verified; no global hardware-keyboard configuration or external lease was changed.

Truthful current Settings renders show a Search drawer below the title even while Settings is selected. This remains a ticket239 ownership/clearance regression case alongside the independently confirmed iOS26 compact mini-player/search defects; no query/action behavior is inferred from that image. Ticket239 must still establish actual compact window interactions, spoken VoiceOver, older OS execution, combined modes/contrast/transparency, final-source whole-app durability and fresh visual review. Largest action activations, RTL images, source14 typecheck and AX labels do not waive those gates. Extreme-size native sidebar labels may break; universal navigation legibility is not claimed.

Personal context/preferences and repository guidance, TDD and frontend skills were applied. React/TypeScript grep rules do not apply to these SwiftUI views; no mirrored constants/modifier tests or backfilled green tests were added.
