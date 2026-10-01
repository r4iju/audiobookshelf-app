# Presentation handoff for root-owned files

The presentation slice (#22) did not edit `project.yml`, the app root, `ConnectionViews.swift`,
`YearReviewView.swift` or the migration import. These steps finish the integration.

## 1. Register the sources in `apple/project.yml`

Add both package source folders to the `AudiobookshelfNative` target, after `../tvos/Core/Sources/TVCore`:

```yaml
      - Localization/Sources/NativeLocalization
      - Diagnostics/Sources/NativeDiagnostics
```

They compile into the app target, so app code uses them without `import`. The `Resources/*.lproj/NativeStrings.strings`
tables become localized app resources. `apple/scripts/verify-presentation.sh` makes the same insertion in a git-ignored
QA project until this lands, and skips it once `project.yml` contains the line.

## 2. Apply `handoff/root-views.patch`

The patch is against `276d0fad`. If root has since changed `YearReviewView.swift`, apply the other hunks and redo that
file by hand with the same pattern (`@Environment(\.nativeStrings) private var l10n`, `l10n("English {0}", value)`).

```sh
git apply apple/Localization/handoff/root-views.patch
python3 apple/Localization/generate.py
```

The patch:

- `AudiobookshelfNativeApp.swift`: applies `.nativeLocalization()` to the window content so the Downloads sheet and any
  later root sheet follow the chosen language and direction, and clears `NativeStrings.savedKey` and
  `NativeDiagnostics.file` under `--reset-preview-account`. Until then, `NativePresentationReset` clears both on first use,
  and `DownloadsView` applies the modifier itself.
- `ConnectionViews.swift`: localizes the connection, library chooser and saved connection screens, adds haptics for
  connect, select library, add server and sign out, and adds a Diagnostics button to the connection screen. That is the one
  place a failed first connection can be diagnosed, because the account menu exists only after sign-in.
- `YearReviewView.swift`: localizes the screen and its shared summary, and formats month names in the chosen language.

Run `generate.py` afterwards so the English table and `COVERAGE.md` include the new texts. `generate.py --check` fails
while they are stale.

## 3. Adopt the legacy language during migration

The legacy app stored the choice as `deviceSettings.languageCode`. After the adoption outcome is applied, call:

```swift
NativeLanguage.adoptLegacy(outcome.settings.device?.languageCode)
```

The preference lives in `UserDefaults.standard` under `"previewLanguage"` (`NativeStrings.savedKey`), holding the legacy
code itself (`ar` … `zh-cn`, `en-us`, `pt-br`, `vi-vn` as in `plugins/i18n.js`). `NativeLanguage.named(_:)` is the
normalizer: an exact legacy code or `nil`. An absent key means follow the device languages.

`adoptLegacy` writes any supported legacy code, `en-us` included, only when the native key is absent, so it never
overwrites a native choice. Unknown codes and `nil` are ignored, and a fresh install without a legacy value follows the device
languages.

`en-us` is not proof of a choice: the legacy app wrote it as a default (`ios/App/Shared/models/DeviceSettings.swift:19`,
the schema 15 migration in `ios/App/App/AppDelegate.swift:46`, the fallback in `ios/App/App/plugins/AbsDatabase.swift:309`),
and the first server connection could replace it with the server's default language
(`components/connection/ServerConnectForm.vue:879`). It is adopted anyway because the legacy app never followed the device
language: whatever the code's origin, it is the language the person saw, and the export carries no provenance to tell a
default from a choice.

## 4. Strings still owned elsewhere

`Playback/AppleNetworkPolicy.swift` (the cellular consent alert) and `Playback/ApplePlayback.swift` messages stay English.
They can use `NativeStrings.current("…")` the same way as `ConnectionStore`, followed by `generate.py`.

## 5. Year export copy contract

`apple/Export/Sources/YearExport` should stay a standalone English-default package: no `NativeStrings`, no bundle or
resource lookups while drawing. The app hands it an immutable copy of the selected language instead.

In the Export package (root owned), suggested shape:

```swift
public struct YearExportCopy: Sendable, Equatable {
    public static let english = YearExportCopy()
    public let locale: Locale
    private let table: [String: String]
    public init(_ table: [String: String] = [:], locale: Locale = Locale(identifier: "en_US")) {
        self.table = table; self.locale = locale
    }
    /// English template in, translation or the template itself out; `{0}`, `{1}` are replaced once, in order.
    public func callAsFunction(_ english: String, _ arguments: CustomStringConvertible...) -> String { ... }
    /// Every template the renderer, snapshot share text and composer draw. Keep in step with the `copy("…")` calls.
    public static let templates: [String] = [ ... ]
}
```

- Keep the snapshot, renderer, artwork share text and composer labels as English templates passed through a property
  or parameter named `copy`, for example `copy("{0} YEAR IN REVIEW", year)`, `copy("{0} books finished", n)` and
  `copy("{0} book finished", n)`. Whole phrases per plural form and per variant; never assemble a sentence from fragments,
  and keep numbers, bytes, durations and month names formatted with `copy.locale`.
- `generate.py` scans `apple/Export/Sources` for `copy("…")` literals, so the templates enter every language table.
  Run it after changing them; `--check` fails while tables are stale.
- App side, when the composer is presented, build the value once from the interface language and pass it down:

  ```swift
  @Environment(\.nativeStrings) private var l10n
  let copy = YearExportCopy(l10n.copy(YearExportCopy.templates), locale: l10n.language.locale)
  ```

  `NativeStrings.copy(_:)` returns only translated templates, so anything without a translation keeps the Export
  package's English. Rendering never sees a language change half way through, and the shared PNG, its accessibility
  label and the share text all use the language the person chose.

Legacy translations: the legacy year canvases (`components/stats/YearInReview.vue`, `YearInReviewServer.vue`,
`YearInReviewShort.vue`) draw hard-coded English, so there are no year canvas translations to reuse. The only legacy
keys with the same meaning in the export are general ones; add them to `legacy-equivalents.json` once the templates
exist:

| Export template | Legacy key | Note |
| --- | --- | --- |
| `Genres` (style name) | `LabelGenres` | Same word and sense |
| `Done` | none | |
| Stat, header and fact texts (`TIME LISTENING`, `TOP AUTHORS`, `books finished`, ...) | none | Legacy drew these in English only |

Everything else stays English in every language until translators add it, and the Language screen already discloses
that. Do not copy `LabelAuthors` or `LabelGenres` into `TOP AUTHORS` or `TOP GENRES`: the heading means "most listened",
which the legacy keys do not say.

## 6. Integration summary

Paths (all compile into the app target, no `import`):

- `apple/Localization/Sources/NativeLocalization/` (`NativeLanguage`, `NativeStrings`) and its
  `Resources/<lproj>/NativeStrings.strings` tables, 30 languages, generated by `apple/Localization/generate.py`.
- `apple/Diagnostics/Sources/NativeDiagnostics/` (`DiagnosticRedactor`, `DiagnosticLog`, `DiagnosticReport`).
- `apple/App/NativeLanguageSettings.swift` and `apple/App/NativeDiagnosticsView.swift`.

App API:

- `.nativeLocalization()`: sets `\.nativeStrings`, `\.locale` and `\.layoutDirection` from the saved or device language and
  updates live when the choice changes. Apply it once to the window content (the patch does) and to any separately presented
  root. Views read `@Environment(\.nativeStrings) private var l10n` and call `l10n("English {0}", value)`; non-view code uses
  `NativeStrings.current("…")`.
- `NativeLanguageSetting.shared.choose(_ code: String?)` saves a choice (`nil` returns to the device language).
- `l10n.copy(templates)` returns translated templates only, for renderers outside the app such as Year export.
- `.recordsDiagnostics()`: records failures already shown by `ApplePlayback`, `NativeDownloads`, `ReadingStore` and
  `ConnectionStore` into the on-device log. `PlaybackContainer` applies it; it needs those four environment objects.
- `ConnectionStore.recovery(for:)` records connection and server failures with a redacted description.
- `NativeDiagnostics.shared.record(_ category:_ message:detail:)` for any other failure; text is redacted before it is saved.
- Any other screen that shows events uses `event.presented(maskingAddresses:)`, which masks addresses in the message and the
  detail alike.
- `NativeDiagnosticsView()` inside a `NavigationView` or navigation stack. The account menu links it; the patch adds the
  connection screen entry, the only place a failed first connection can be diagnosed.
- `NativeDiagnostics.file` and `NativeStrings.savedKey` are cleared by `--reset-preview-account` in simulator journeys.

## 7. Player display preferences for migration

The legacy player kept these in Capacitor Preferences under `playerSettings`, a JSON object
(`plugins/localStore.js:45`, read by `components/app/AudioPlayer.vue` `loadPlayerSettings`). Map each only when the native
key is absent:

| Legacy field | Native key (`UserDefaults.standard`) | Native default | Owner |
| --- | --- | --- | --- |
| `useTotalTrack` | `previewTotalTrack` (`PlayerDisplay.totalTrackKey`) | `true` | `PlaybackViews.swift` |
| `scaleElapsedTimeBySpeed` | `previewScaleElapsedBySpeed` (`PlayerDisplay.scaleElapsedKey`) | `true` | `PlaybackViews.swift` |
| `lockUi` | `previewLockPlayerControls` (`PlayerDisplay.lockKey`) | `false` | `PlaybackViews.swift` |
| `useChapterTrack` | `previewChapterTrack` | `true` on iOS | root, `ApplePlayback.chapterTrack` |

The legacy defaults in `AudioPlayer.vue:172` are `useChapterTrack: false`, `useTotalTrack: true`,
`scaleElapsedTimeBySpeed: true`, `lockUi: false`. For the chapter track the legacy sources disagree: the Vue player starts at
`false` and saves that on first launch, the Realm `PlayerSettings.chapterTrack` (lock screen) defaults to `true`
(`ios/App/Shared/models/PlayerSettings.swift:15`), and the schema migration wrote `false` (`AppDelegate.swift:52`).
`playerSettings.useChapterTrack` is the value the person saw in the player, so prefer it when present. If both
`useChapterTrack` and `useTotalTrack` are false (not reachable through the legacy menu), set `previewTotalTrack` to `true`;
the native settings keep at least one track on.

The migration core's `LegacyPlayerSettings` currently captures only `playbackRate` and `chapterTrack` (reported by the
adoption session), so `useTotalTrack`, `scaleElapsedTimeBySpeed` and `lockUi` cannot be mapped until it also reads the
`playerSettings` JSON.

Lock is display only: it disables scrubbing, skips, chapters, bookmarks and Close playback in the native player and leaves
system media controls alone, like the legacy in-app `lockUi`.

## 8. Final state

Branch `fork/apple-presentation`, base `276d0fad`. The implementation is final at `b5e7e9f6`; later commits change only
documentation. Tests come before their fixes:

| Commit | Content |
| --- | --- |
| `73a6807c` | RED: presentation journeys and package tests |
| `8df83eb9` | Language, diagnostics, haptics, large text |
| `d51d5b91` | Root's chapter core patch (`ApplePlayback.swift` only), skip when integrating |
| `dfa76009` / `66dc7163` | RED / player display preferences |
| `2e472ef5` / `a005d888` | RED / cookies, prefixed and wrapped values, error payloads, message masking |
| `8dec7e90` / `cae46e59` / `b5e7e9f6` | RED escaped quote / RED unterminated quote / quoted values to their real closing quote |

Evidence: 12 of 12 journeys in one run at `a005d888`, the three diagnostics journeys again at `b5e7e9f6`, Localization 13 of
13, Diagnostics 20 of 20, `generate.py --check` clean, iOS 14 device and simulator typecheck clean with and without
`handoff/root-views.patch`. Details and limits are in `docs/modernization/APPLE-PRESENTATION.md`.

## Root integration

The app registers both source packages and applies nativeLocalization at its window. Connection and import screens use the selected language. Legacy language adoption refreshes the running language setting. Year review captures immutable localized copy across artwork loads and sharing. Imported player choices update the running chapter mode, and chapter display bounds use the same validated window as system media controls.

Local combined checks: NativeTests 34, localization 13, diagnostics 21, and iOS simulator YearExport 28 pass. The presentation journey suite is running separately on root-owned ports 39765/39769. Physical acceptance gates in the migration and presentation documents remain open.
