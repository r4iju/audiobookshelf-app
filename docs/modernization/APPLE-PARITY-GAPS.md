# Apple parity gaps before cutover

Reconciled October 2, 2026 against merged `a77d7114` (PR #82) and root publication/authorization integration `da6460ef`. Evidence is local and synthetic unless expressly stated otherwise. These checks do not establish owner-device, live-server, iOS 14 runtime, or whole-platform acceptance.

## Integrated evidence

| Work | Source / merge | Verified | Remaining limits |
| --- | --- | --- | --- |
| Legacy export/import | PR #76, `e875498d` | Actual legacy app exports reader-generated WebView settings/cache and native imports synthetic archive through Files | Owner migration, rollback and optional in-place identity route |
| Durable reset | PR #79, `000ea3c8` | Final phone and tablet reset suites 4/4, signed Release installed without launching | Subsequent publication gate changes require combined UI rerun |
| TV readiness | PR #80, `937f7936` | 13 unit tests and 25 remote journeys; signed local TV Release verified | Hardware acceptance; latest TV recovery integration pending |
| Realtime | PR #81, `39609d08` | Root Core 72, Native 66, phone realtime9 plus paused2; worker tablet 11. Every init resyncs visible screens; item feed changes and delayed action responses are guarded | Final combined tablet suite; server has no event replay |
| Contrast, permissions and downloads | PR #82, `a77d7114` | Root Native 70, Core 72, UI 5, fixture 10; full owned storage volume, listed-size audio validation, completed audio preserved on PDF failure | Whole-device exhaustion, force-quit background behavior and physical transitions |
| Publication gate | Root `8bce55b2`, from worker `8b544ef4` | Independent review clear. Per-transmission issued records retain unanswered writes, newer same-title writes wait durably, two-step restart retires only the requested snapshot. Other titles continue | TV remote recovery under implementation; final mobile recovery journey |
| Playback authorization | Root `1f03c796`, from reviewed `2e70f1d` | Latest seek/pause intent survives renewal; revoked login blocks resumed audio. Combined native suite below includes all four decoded authorization cases | Root long-book UI journey passes; TV authorization acceptance remains |

Root combined source `8bce55b2`: all 85 NativeTests pass, zero skipped, with the full-volume and real-audio synthetic fixtures active (`/tmp/abs-root-publication-auth-native-all.log`; `apple/build-remaining-qa/results/storage-Audiobookshelf-Root-Related-QA-20261002-065758.xcresult`). Core 72 and fixture 12 pass. Earlier invocation skipped five fixture-dependent tests and is superseded by this run. Later `ad502e5d` and `f08e3e1c` correct whole-book time assertions and the iPad account-menu selector; `da6460ef` keeps the new recovery notice on the adaptive contrast palette.

Root long-book revocation UI journey also passes 1/1 at `da6460ef`, result `apple/build-remaining-qa/derived/Logs/Test/Test-AudiobookshelfNative-2026.10.02_06-59-20-+0900.xcresult`, log `/tmp/abs-root-publication-auth-ui.log`. iOS14 source typecheck passes all 69 actual target sources (`/tmp/abs-root-publication-auth-minimum.log`).

Root reset journeys pass 4/4 at `da6460ef`, result `apple/build-reset/Root-Publication-Reset-20261002-070046.xcresult`, log `/tmp/abs-root-publication-auth-reset-ui.log`. The baseline/modern-auth compatibility invocation and `verification.test_upgrade_gate` both pass after supplying the matching local dependency tree through a read-only symlink. This resolves the worker checkout’s missing `socket.io-client` dependency; it is not live-server certification.

## Remaining local gates

1. **Final combined phone and tablet suites.** Initial broad runs predate the integrated source. Whole-book time assertions and iPad duplicate menu selection are corrected without relaxing their numeric thresholds. Account-switch restoration is still intermittent in the phone slice; the iPad timer interaction is still under diagnosis. No final full-suite pass is claimed.
2. **TV unanswered-save recovery.** Shared gating is integrated, but the TV needs a remote-operable request-before-restart / confirm-after-restart flow. This is in a separate worktree, including meaningful RED/GREEN and remote journeys.
3. **Combined reset/recovery and authorization UI.** Unit safety passes; run the journeys on the final source, including preservation of held listening and no automatic playback after sign-in.
4. **Collections and playlists.** Permission-denial journeys pass. Worker probes cover partial membership retry, unavailable members, editing through relaunch and podcast playlist membership. The formerly intermittent collection relaunch journey must pass the final suite on corrected realtime wiring.
5. **Localization.** Existing native coverage is approximately 15–21% for non-English languages, with explicit English fallback. A fresh mapping audit is in progress. No full translation claim is made. TV author/series pages and shared playback/error text retain documented English gaps.
6. **Accessibility.** Targeted contrast audits pass, including tablet worker evidence. Full VoiceOver walkthroughs, reduced-motion checks and unaudited screens remain unverified.
7. **iOS14 runtime.** Source typechecks alone do not establish runtime support. Current Xcode requires the documented iOS15 build override; an older runtime/SDK remains necessary for actual iOS14 acceptance.
8. **Interruption and route behavior.** The production-handler simulator probe passed 9/9 while decoding audio. Real calls, Siri, alarms, CarPlay/Bluetooth and media-services-reset recovery remain unverified.

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

`APPLE-REMAINING-QA.md` records the contrast audits, collection editing and recovery probes, full-volume storage failure, permission-based write-error classification, and partial audio/PDF preservation. An owned simulator probe observed completed transfer parts after app termination and successful reattachment on relaunch, without extra HTTP requests. It cannot establish whether delivery happened during a background launch or only the explicit relaunch, and does not prove user force-quit or hardware behavior. Actual device restart/cellular changes, VoiceOver and unaudited screens remain unverified. The truncated-download and admin delete-permission questions were confirmed against server2.30 and corrected in `a39281f1` and `2d0154c8`.

## Final TV integration run

The first root run at `8123a742` was intentionally interrupted after catalog, playback, podcast and Arabic readiness cases passed. Its retry fixture still answered `offline-progress` with gateway HTTP503, which the new publication ledger correctly treats as an unanswered write. Worker correction `c761acb7` distinguishes a positively answered synthetic handler failure (HTTP500, no write) from the separate `held-sync` HTTP504 case whose handler remains active. The root rerun uses that correction; the interrupted run is partial evidence, not a full pass. Logs: `/tmp/abs-root-final-client-tv-ui.log` and `/tmp/abs-root-final-client-tv-ui-corrected.log`.

The corrected root TV run passes all39 cases at `f2cdf7ad`:13 app unit tests and26 remote-driven journeys, zero failures (`tvos/build/Root-Final-Client-20261002-071302.xcresult`, `/tmp/abs-root-final-client-tv-ui-corrected.log`). Separate unchanged-code remote authorization probes at `c596be47` pass expired-token renewal with one refresh and long-book revocation stopping at23/120seconds, blocked resume, same-account reauthentication and delivery without autoplay (`/tmp/abs-tv-auth-evidence/`). The probe also exposes a clipped reauthentication sheet, now under correction. A newly identified corrupt-ledger startup storage failure also needs the reviewed copy-before-atomic-replacement correction before device updates; neither gap is hidden by these passing normal-state cases.
