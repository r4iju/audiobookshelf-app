# Apple TV diagnostics, accessibility and localization

Stories 52, 53 and 54 for the TV (`verification/parity.json`). The audit in `APPLE-PARITY-GAPS.md` found no TV evidence
for them. This slice adds them where they apply to a remote-only, streaming-only client, and records what does not apply.

Branch `fork/tv-readiness` from `315183c1`. Local builds and simulator evidence only. Nothing was installed on a TV, and
nothing here is hardware acceptance.

## Before this slice

| Area | Already present | Missing |
| --- | --- | --- |
| Diagnostics | Recovery text on sign-in, catalog and playback failures; `ServerAddress` rejects credentials, queries and fragments | No record of failures, nowhere to look after the message was gone, no status summary |
| Accessibility | System focus engine, `focusSection`s, Back restores focus to a home tile, readable type sizes | Progress bars without labels or spoken values, decorative images read aloud, a sign-in placeholder the audit reported as clipped, focus lost after a failed sign-in |
| Localization | None: English literals, durations and dates in the device locale | No language choice, no legacy translations, no right-to-left layout |

## What the TV now does

**Diagnostics** (`tvos/App/TVDiagnostics.swift`), with the shared `NativeDiagnostics` package compiled into the TV target:

- Sign-in, catalog, details, search, mark finished, playback, restart and sign-out failures are recorded in the bounded
  `DiagnosticLog` (200 events, repeats counted). They are redacted before saving: credentials, tokens and query values are
  removed. The message is the English wording of what the screen showed, so the log reads the same whatever the interface
  language.
- Diagnostics opens from Settings and also from the sign-in screen, since a failed first connection happens before
  Settings exists. It shows recent events (newest first), a toggle to show server addresses (masked as
  `http://[server]/abs` by default), Clear with confirmation, and status: version, system, language, masked server,
  account, playback state, and listening saved on the TV that the server has not acknowledged.
- Events stay on the device. tvOS has no share sheet or pasteboard, so there is no export. The file is in Caches.
  Losing old events under storage pressure is acceptable, and the Debug `--reset-tv-state` argument clears it.

**Accessibility**:

- Progress bars on Now Playing are single elements with labels (Book progress, Chapter progress) and spoken values
  ("1 hour, 2 minutes remaining"). The elapsed and remaining clocks keep their visible text. Covers and the headphones artwork are
  hidden from VoiceOver.
- Interval menus read as "Skip back: 10 seconds". The server address reads as "Server address" with its value. Language
  rows report Selected or Not selected, so the choice is not conveyed only by a checkmark.
- Back from Language and Diagnostics returns focus to the link that opened them. Without this, the screen rebuilt by a
  language change left nothing focused. A failed sign-in hands focus back to Connect. Connect keeps the same views while
  connecting, because replacing the focused button's content left the remote with nothing focused.
- The sign-in server field has a short placeholder and the example sits below it, because the long placeholder was
  reported clipped.
- Diagnostics events and status rows are focusable, so the remote can scroll a long list, and VoiceOver reads each entry as
  one element.

**Localization** (`tvos/App/TVLanguage.swift`), with the shared `NativeLocalization` package and its tables:

- Settings has a Language screen: System default or any of the 30 legacy languages. The choice is stored under the same key
  as the mobile app (`previewLanguage`). It applies immediately, including to the tab bar and sheets, and survives
  relaunch.
- Every TV screen in `tvos/App` goes through `l10n("English text")`. `generate.py` now scans `tvos/App`, and translations
  come only from mapped legacy keys (`legacy-equivalents.json`, 18 mappings added for TV texts such as Home, Account and
  Continue Listening). Texts without a legacy equivalent stay English, and the Language screen says so.
- Durations, spoken durations and publication dates follow the chosen language. Arabic and other right-to-left languages
  mirror the layout.

## Not applicable or not included

- Dynamic Type: tvOS has no user text size setting. Type sizes are the system TV styles.
- Reduced motion: the TV app adds no custom animation. Focus motion and transitions are the system's, which follow the
  Apple TV's Reduce Motion setting.
- Downloads, readers and their diagnostics categories: not part of the TV (README, Not included).
- Single sign-on (OpenID): unsupported on the TV. The sign-in text explains it, unchanged.
- Export or sharing of diagnostics: no share sheet or pasteboard on tvOS.

## Strings still English

Each of these is owned elsewhere, so this slice did not edit it:

- `tvos/App/RelatedAuthorSeries.swift` (story #21 owner).
- Messages produced by `apple/Playback/ApplePlayback.swift` and shown on Now Playing.
- `TVCore` error descriptions that fall through `CatalogStore.recovery`. The known `APIError` cases and `URLError`s are
  localized in the app.

They can adopt `NativeStrings.current("…")` or `l10n(…)` the same way, followed by `python3 apple/Localization/generate.py`.

## Shared files touched

- `apple/Localization/generate.py`: `tvos/App` added to the scanned sources.
- `apple/Localization/legacy-equivalents.json` (18 mappings appended), `dynamic-keys.json` (2 entries), the regenerated
  tables and `COVERAGE.md`. Integrating this after another slice that changes the tables needs `generate.py` again;
  `--check` reports stale output.
- `verification/parity.json`: `replacementEvidence.tv` for stories 52, 53 and 54.
- `tvos/project.yml` compiles `apple/Localization/Sources/NativeLocalization` and
  `apple/Diagnostics/Sources/NativeDiagnostics` into the TV app. The packages themselves are unchanged.

`apple/Playback`, `tvos/Core` and the related author/series files were not edited.

## Evidence

All on the Studio, Xcode 27, own simulator `Audiobookshelf TV Readiness QA` (`0D7C1DBC-E266-4F62-AC6D-F68222A8706A`,
Apple TV 4K 2nd generation, tvOS 27) and synthetic fixtures on ports 30765/30767. `verify-ui.sh` now takes
`ABS_TV_HTTP_PORT` and `ABS_TV_HTTPS_PORT` (defaults 20765/20767 unchanged).

| Step | Commit | Result |
| --- | --- | --- |
| Port selection for parallel runs | `20ce2961` | `CatalogJourney` and `RelatedJourney` journeys passed on the new ports before any other change |
| RED | `a64f655b` | All 5 `ReadinessJourney` journeys failed: no `language-setting`, `diagnostics-setting` or `sign-in-diagnostics`, and the audit reported the sign-in placeholder clipped. `FormatTests.testDurationsAndDatesFollowTheChosenLanguage` failed with `1 h 30 min` and `Oct 1, 2026` under German |
| GREEN | `8444b02d` | All 5 journeys and the Format test pass; the complete TV suite passes (below) |

Journeys (`tvos/UITests/ReadinessJourney.swift`), remote presses only:

| Journey | Proves |
| --- | --- |
| `testFailedSignInIsDiagnosedWithoutCredentials` | A sign-in address with `qa:synthetic-secret@` and `?token=synthetic-token`, then an unreachable server after relaunch. Diagnostics from the sign-in screen lists exactly those two events with masked addresses. Neither secret appears anywhere in the accessibility tree, even with addresses shown (`?token=[redacted]`). The audit passes. Back focuses Diagnostics |
| `testCatalogFailureIsRecordedAndClearedFromSettings` | A server 503 while loading libraries is recorded. Status shows the masked server, the account and pending listening. Clear asks first, then empties the list. Back focuses the Settings entry |
| `testGermanLocalizesTheInterfaceAndPersists` | Tab bar, Settings, Home shelf (Weiterhören) and details (Als beendet markieren) use the legacy German, and the choice survives relaunch. The Language screen discloses partial translation, passes the audit and reports Selected. Back focuses Language. System default returns to English |
| `testArabicMirrorsTheInterface` | Arabic tab labels; Settings section titles start on the right |
| `testMainScreensPassTheAccessibilityAudit` | `performAccessibilityAudit` with no issues on sign-in, home, details, Now Playing, Settings and Search. Progress bars have labels and spoken remaining time |

Audit exceptions, stated in the test:

- `.hitRegion` is not audited. tvOS has no touch, and the only findings were the non-interactive progress bars.
- On Search only, `.textClipped` is not audited. The system search field reports its prompt as clipped while showing it
  in full (`tvos/evidence/readiness-search-prompt.png`).

Results at `8444b02d`:

- `./tvos/scripts/verify-ui.sh` with no filter: 13 `TVAppTests` and 25 journeys passed, 0 failed (899 s): Catalog, Playback,
  Podcast, Recovery, Related and Readiness. Local result `tvos/build/Readiness-FINAL-8444b02d.xcresult`.
- `swift test`: `tvos/Core` 63, `apple/Localization` 13, `apple/Diagnostics` 21, all passed.
  `python3 apple/Localization/generate.py --check` is clean.
- Local signed Release build: `xcodebuild` Release for `generic/platform=tvOS` with the already installed development
  profile `83e7542b-3334-4638-acc3-2ce86b2b6894`, team `C7X9BCC7LP`. `codesign --verify --deep --strict` passes, the
  binary has no `--reset-tv-state`, and the 30 `NativeStrings.strings` tables are bundled. The only warning is the known
  `appWasSuspended` deprecation in `ApplePlayback.swift`. `deploy.sh --build-only` was not used because its
  `provision.py` creates a new profile in App Store Connect. Nothing was installed on a TV.

Two regressions found by the complete suite were fixed before `8444b02d`:
- Spoken labels on the Now Playing clocks broke the existing playback journeys, which read the clocks as `0:08`. The
  clocks keep their visible text, and the progress bars carry the spoken values.
- The audit journey paused through a focus walk, which proved flaky. It now uses the remote's Play/Pause button, like
  `PlaybackJourney`.

The iOS app was not rebuilt. Its tables changed only by additional English keys and translations, and the
`NativeLocalization` code is unchanged.

Screenshots: `tvos/evidence/readiness-diagnostics-sign-in.png`, `readiness-settings-german.png`,
`readiness-settings-arabic.png`, `readiness-search-prompt.png`.

## Remaining physical acceptance

Not performed. On the Living Room TV with the Siri Remote and the real server:

1. VoiceOver on: sign-in, Home, details, Now Playing (progress values), Settings, Language and Diagnostics read in a
   sensible order.
2. Readability from the sofa in German and Arabic, including long translations and the Diagnostics list.
3. Reduce Motion and Increase Contrast on the TV: focus remains visible.
4. A real failed sign-in and a real server outage appear in Diagnostics without credentials.

## Root composition verification

The integrated root source `1652c305` passes all 13 app unit tests and 25 remote-driven journeys, including the five new readiness journeys (`/tmp/abs-root-tv-readiness-final-ui.log`, `tvos/build/TVJourneys-20261002-051935.xcresult`). Existing browsing, related pages, podcast and multi-file playback cases remain intact. NativeLocalization passes 13/13 (`/tmp/abs-root-tv-localization-tests.log`); localization generation check and iOS 14 mobile source typecheck pass. Independent review cleared the exact source `8444b02d`, and generated conflicts were resolved by regenerating the project and language tables from their merged source.

This closes local TV UI readiness verification, not whole-platform replacement. A separately identified publication-uncertainty issue in shared listening/reading reset ordering is under correction. Physical and live-server gates remain open.
