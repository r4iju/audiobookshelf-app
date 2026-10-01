# Apple parity gaps before cutover

Reconciled on October 2, 2026, against `937f7936` (PR #80 merged on `fork/native-tv`), the unmerged worker branches named
below, the Apple docs in this directory, `tvos/QA.md` and the local logs they cite. Per-row evidence is in
`verification/parity.json`.

Nearly all evidence comes from simulators, unit tests, or signed local builds and installs against synthetic fixtures.
No row has hardware, iOS 14 runtime, live-server or owner acceptance. No row is claimed complete, and the Apple apps are
not claimed to be at full parity.

## Integrated so far

| PR | Merge | What is verified | What it does not close |
| --- | --- | --- | --- |
| #76 | `e875498d` | Legacy export through Files for the separate-identity preview: the actual legacy app, with synthetic data, writes reader-generated WebView settings and cache, exports Settings, saves to Files, and the native app imports the archive | Owner-device migration, rollback, and the in-place route (gap 3) |
| #79 | `000ea3c8` | Durable progress reset at `56990f46`: final iPhone and iPad reset suites 4/4. The signed Release build was verified and installed on the owner's paired iPhone and iPad without launching (`APPLE-PROGRESS-RESET.md`) | Interactive device acceptance. The publication-ordering blocker found afterward (gap 1) |
| #80 | `937f7936` | TV diagnostics, accessibility and localization, source `8444b02d` (integrated as `1652c305`): the complete TV suite passes 38/38 (13 app unit tests, 25 remote-driven journeys), and a signed local tvOS Release build passes strict verification without a new provisioning call (`APPLE-TV-READINESS.md`) | TV hardware use: not installed, VoiceOver and readability from the sofa not checked |

Earlier, at `315183c1`, the TV suite passed 20/20 journeys and 12/12 app unit tests, and the signed iPhone/iPad Release
build was installed on both devices without launching. That TV result is superseded by the 38/38 at PR #80.

## In progress, not integrated

These are worker states seen locally on October 2. None is merged, and none closes its gap until it is reviewed and
integrated, and its suite passes on the integration commit.

| Work | Branch and SHA | State |
| --- | --- | --- |
| Publication safety (progress writes against reset) | `fork/apple-native-publication-safety` at `99780f35` (RED `971ccaa9`) | Under independent review, **not complete**. New concern: after an unresolved original write, `ListeningSync.flush` retries with the same cumulative session ID, and later listening can be sent meanwhile. So an older original could still land a smaller `timeListening` or `currentTime` after a newer cumulative write was accepted. Server 2.30 replaces rather than linearizes. Review also found that restart confirmation clears attempts issued after the actual restart; both blockers remain under correction. The issuing hook is invoked again on a recursive 401 resend |
| Realtime feeds, pre-`init` changes, overlapping item-action loads | `fork/apple-realtime-sync` at `837cafc1` | Independent review cleared. NativeTests 52/52; RealtimeJourney 9/9 plus PausedRealtimeJourney 2/2: 11/11 on iPhone and 11/11 on iPad (`APPLE-REALTIME.md` on that branch, `/tmp/realtime-sync-qa/`) |
| Root realtime integration | `fork/apple-final-realtime-integration` at `87215563` (over `937f7936`) | Core 72/72 (`/tmp/abs-root-realtime-final-core.log`). NativeTests 66/66 and iPhone realtime plus paused-player journeys 11/11 also pass (`/tmp/abs-root-realtime-final-native-unit.log`, `/tmp/abs-root-realtime-final-ui.log`). Socket contracts 2/2, item-actions fixtures 4/4, and iOS 14 source typecheck pass. This is an incremental integration, not the final combined mobile suite |
| Token renewal, revocation, interruption and route probe | `fork/apple-playback-final-qa` at `84a9047e` | Under correction. Review blocker: `mediaFailed` captures the position before awaiting `api.me`, so a same-track seek during a delayed renewal can be lost and the older position restored. The revocation journey's 20-second book can pause at its natural end, so its pass does not prove revocation. A long synthetic audio mode, a RED with handling removed, and a GREEN are being added |
| Full iPhone and iPad suites | `fork/apple-final-mobile-qa` and `fork/apple-final-mobile-ipad-qa` at `56990f46` | The full journey suites are running on both devices, with corrections to tests whose elapsed-time assumptions were wrong. Uncommitted test edits are in both worktrees. **No final combined-suite pass is claimed** |
| Collections, downloads and contrast | `fork/apple-remaining-local-qa` at `fab95910` | Source review cleared `b405a805`; the storage classification correction is `553fd012` (RED `63ed02cf`). NativeTests 67/67, iPhone and iPad contrast audits and collection-denial journeys pass. Completed audio remains playable when a PDF fails. Evidence and remaining local gaps are recorded in `APPLE-REMAINING-QA.md`; this is not final combined-suite acceptance |

## Open gaps, in priority order

1. **Publication ordering (blocks whole-platform replacement).** A replay acknowledgment cannot prove that a timed-out
   original server write has finished on server 2.30. An original listening sync or primary-reading PATCH can then
   complete after a progress reset and recreate discarded progress. Ordinary cumulative listening history must also never
   regress or duplicate. Earlier passing reset tests cover their documented failure paths, not this case. Correction:
   `99780f35`, under review (above).
2. **Token renewal during playback (story-12) and server-side revocation (story-14).** At `937f7936`, only contract tests
   and the existing rows in `parity.json` cover these. `84a9047e` adds fixture expire and revoke modes, renewal and
   revocation handling, and journeys, but it has the open latest-seek blocker and the weak revocation proof (above).
3. **Migration, in-place alternative (story-58).** The delivered preview uses the separate-identity route: export from the
   legacy app through Files, then import (PR #76). These checks apply only if the in-place alternative identity is
   adopted instead:
   - a compatible-identity build (legacy bundle ID, team and Keychain group);
   - reading a Realm written by an actual legacy 0.14.2-beta build;
   - reading the old WebView store directly during an upgrade.

   Owner-device migration and rollback remain unproven on either route.
4. **Combined iPhone and iPad rerun.** Most journeys passed on the slice that introduced them. The full suites must pass
   once on the final integration commit, which includes the publication-safety, playback-authorization, realtime and
   remaining-QA work. The runs at `56990f46` predate those. Presentation journeys have not been confirmed on iPad in a
   combined run.
5. **Realtime (`upstream-realtime`).** At `937f7936`:
   - the item page ignores `rss_feed_open` and `rss_feed_closed`;
   - changes made before the first `init` stay hidden until the next one, because server 2.30 keeps no replay.

   `837cafc1` addresses both by resyncing visible screens on every `init` and following item feeds. It is cleared, but
   its integration at `87215563` passes the 11 iPhone realtime and paused-player journeys. Queued unsent listening through a reconnection is guarded only
   against the synthetic fixture on simulators. Changes missed while suspended are recovered only by that resync.
6. **Interruptions and route changes (story-34).** No recorded observation at `937f7936`. The probe in `84a9047e` posts
   interruption and route notifications to the production handlers while synthetic audio decodes on a simulator, and
   passes 9/9. It lands with gap 2's branch. Real calls, Siri, alarms, CarPlay and Bluetooth on hardware remain
   unobserved.
7. **Collections and playlists (story-22).**
   - The refused-edit case is fixed on the remaining-QA branch, not integrated.
   - Still open: partial membership failure and retry, unavailable or deleted members, collection editing, and podcast
     playlist membership editing.
   - `CollectionJourney.testCreateReorderRemoveAndDeletePlaylistThroughRelaunch` failed in 3 of 4 runs on the
     pre-correction realtime wiring, with no cause found. It needs a clean result in the combined rerun.
8. **Downloads (story-42, 43).**
   - Out-of-space handling is fixed on the remaining-QA branch, not integrated.
   - A later PDF failure making downloaded audio unplayable offline has a RED only.
   - Still untested: background transfer interruption, device restart, and actual cellular transitions.
9. **Accessibility (story-53).**
   - Mobile text contrast is fixed on the remaining-QA branch, not integrated.
   - Not checked: VoiceOver walkthroughs and reduced motion on iPhone and iPad.
   - On TV, the audit passes on six screens in the simulator. Hardware VoiceOver, contrast and readability checks are
     open (`APPLE-TV-READINESS.md`).
10. **Localization (story-54).**
    - Non-English mobile coverage at `315183c1` was 15–21%. Untranslated text falls back to English.
    - Cellular consent uses the shared lookup and generated English templates.
    - The TV uses only legacy translations, and its Language screen says the rest stays English. On TV, the author and
      series pages, `ApplePlayback` messages and TVCore error descriptions remain English.
    - No new translations are claimed.
11. **iOS 14 runtime.** Only typechecking has been done, because Xcode 27 needs a build-only iOS 15 override. The app must
    run on an older runtime or SDK before the supported audience is confirmed.

## Physical, live-server and owner gates (none performed)

- **iPhone and iPad:**
  - lock screen, headset and Bluetooth controls
  - background playback and the background sleep timer
  - audio interruptions
  - real codecs
  - offline listening in airplane mode
  - PDF on a device
  - cross-device progress
  - realtime with a second client
  - year image sharing and Save Image
  - haptic vibration

  The installs from PR #79 were not launched.
- **Live server, with owner approval:**
  - an OpenID provider
  - an RSS feed opened and closed by another client
  - sending an ebook through SMTP
  - large libraries
  - authors with more than 60 titles
- **Migration on devices:**
  - a legacy export saved through Files and imported
  - adopted audio playing offline
  - a PDF reopening on the same page
  - pending sessions accepted by the server
  - rollback to the legacy app
- **Apple TV:**
  - the ten checks in `tvos/QA.md`;
  - the four readiness checks in `APPLE-TV-READINESS.md`.

  The PR #80 build was not installed on the TV.

## Deferred, not gating Apple readiness

- Remaining EPUB acceptance, including hardware volume navigation, and the MOBI, AZW3, CBZ and CBR readers, are deferred
  until after Phase 2 (#65, `scopeAmendments`). Migration must keep their files and locations.
- The auto-sleep window, shake reset, chime and the local folder workflow are Android-only in the baseline.

## Remaining local QA evidence

`APPLE-REMAINING-QA.md` records the contrast audits, collection editing and recovery probes, full-volume storage failure, permission-based write-error classification, and partial audio/PDF preservation. Background transfer reattachment after system relaunch, actual device restart/cellular changes, VoiceOver and unaudited screens remain unverified. A possible truncated download without Content-Length and an admin delete-permission question still need contract investigation.
