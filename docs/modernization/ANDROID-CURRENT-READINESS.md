# Android current readiness, October 2, 2026

<!-- android-current-status:start -->
**Status: scoped software finishing implemented; root review, merged-head packaging and replacement acceptance pending.**

Base: `d3152a5d`. Implementation: `125634de7da2b00bc5d59c75f860d48e8c5260ca`. This pass inspected the explicit Android parity rows and tickets #51–#54, rather than repeating the broad audit or emulator journeys.

## Confirmed gaps completed

- Retained legacy `playerSettings` now applies chapter/total timelines, speed-adjusted elapsed/remaining time and the player UI lock. Settings persists each choice; turning off one timeline keeps the other available. The lock disables screen seeking, jumps and chapter selection while play/pause and unlocking remain available. System and receiver controls are separate from this UI preference.
- New imports apply those values with the other settings. An older committed import applies only its missing player-preference step on matching account attachment, using a separate persisted `playerSettingsApplied` marker; previously applied display/device preferences are not replayed. Invalid individual booleans keep current values. The retained archive/preferences, files, sessions and positions are preserved.
- The 14 new `err_*` MissingTranslation findings have explicit resources in the six unoffered partial locales. Two exact Lithuanian texts reuse maintained Apple drafts; other missing texts use English fallback. The five player labels use valid legacy translations, with English fallback where absent. Fallback counts as untranslated and does not add offered languages. No lint suppression or severity change.

## Evidence for this implementation

- Offline Gradle `:app:compileDebugKotlin`: passed (including core compilation). A final incremental compile passed after aligning the timeline's accessibility description with its displayed chapter and scaled time.
- Offline `:app:lintDebug`: **failed, 690 errors, 116 warnings, 3 hints**. Previous `e5a904de` result: 704 errors; pre-localization baseline `a23db59b`: 690 errors. All 14 new error-resource findings are absent; baseline lint is still unresolved. This is a resource regression completion, not a clean-lint claim.
- Static resource comparison: every existing string/plural value unchanged across 40 resource sets; all 14 errors present in every emitted locale; regeneration byte-identical; 33 non-English offered languages unchanged. Coverage: 582 strings/plurals, 151 legacy-mapped rows, 578–581 translated groups per offered language. Product name and explicit English fallbacks remain outside translated coverage.
- No new tests, unit reruns, emulator journeys, physical-device access, installation or package in this lane. Existing tests do not establish the newly applied player-setting values, so they are not presented as fresh mapping/controls acceptance.
- Exact compiled app source tree: `4645c6acb9c6d6b1766d970e328e5cb0429c64fd`; core source tree: `0470dba34361d773aef64f627d9861b0c91c2b1f`; generator blob: `22fe94adffe6dc92c7612e47536823c1058a4c85`. Evidence-only commits do not change these production inputs.

## Saved evidence reused, not rerun

- `e5a904de81dd610ad9319aed8cc599cb3c5a1b02`, Android tree `7f2fee1458a231e7adf1ec6430ab94cb3fa9daaf`, identical to reviewed `4bbbacdeb0fd85d07f698d505c9f9482db68a260` and this lane's `d3152a5d` base: core 63/app 6; Localization 3/3; Migration 7/7; local package successful. This is prior evidence, not new player-preference acceptance.
- [PR #113](https://github.com/r4iju/audiobookshelf-app/pull/113) candidate APK SHA-256 `b71310d0347014448f8e231a7a9205b0600549d4f3c0116092c8fb6ece010ed7`, preview identity, local debug signature, no physical install. This remains the retained candidate until root packages the reviewed merged head.
- Android RealServerJourney 4/4 at client `4bbbacde` against the session-only server candidate `cd703e87`, [PR #119](https://github.com/r4iju/audiobookshelf-app/pull/119). Owner server unchanged. The earlier first-progress candidate was held because it marked first PATCH progress finished with less than 10 seconds remaining.
- Earlier full 88/88 at `f256272b`, postmerge 18/19 Chrome accessibility failure and the unknown bookmark/Chrome/SystemUI lookup signals remain recorded in `verification/android-evidence.json` and `android-native/HANDOFF.md`. Nine diagnostic attempts did not establish the original bookmark cause. No new reruns or closure of those signals.

## Open acceptance gates

- Root fresh source review and one local package at the reviewed merged head. This lane's new controls/mapping have compile/static evidence only.
- Native-speaker review of machine-drafted language resources, including the reused Lithuanian texts; full localization acceptance is not claimed.
- Physical casting receiver, Android Auto/car or DHU, background/lock-screen/headset/Bluetooth/route/interruption controls, shake/chime, real metered-network behavior and TalkBack. Automated accessibility and simulator evidence do not close these gates; large-text, reader/import accessibility acceptance remains incomplete.
- Owner signing/installation and real legacy export/import, including SAF downloads. The preview cannot read upstream private storage. In-place migration and owner cutover are not accepted.
- PDF remains required. EPUB/MOBI/AZW3/comic reading is deferred after #65; their files/settings/locations stay preserved. `lastLibraryId` remains retained, with library selection per account in the replacement; reader settings remain preserved for deferred readers. Legacy local listening-history/log export remains a documented migration limitation.

The scoped pass found no additional confirmed main-use-case software omission beyond the two changes above. This statement does not waive the original specification, unknown signals or baseline lint findings, and does not declare #54 complete or authorize replacement/promotion.
<!-- android-current-status:end -->
