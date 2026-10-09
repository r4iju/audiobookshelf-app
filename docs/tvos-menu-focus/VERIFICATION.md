# TV menu continuity and presentation verification

Released baseline: e24ed0b7bfdce57074acc1790b3c55b9189b861e, internal TV build 5. Final runtime source: 050af4d8330df18f33120ae41dde58a12968df20; reviewed locale-harness repair: 48ba0b77.

The screenshot-free diagnostic archives the exact committed app and overlays a native display-link focus sampler plus the remote journey only in its disposable snapshot. During real synthetic playback, the remote holds a speed option for 20 seconds. A stationary 17.5-second interval in the released app replaced the focused native menu row 29 times across 536 samples, although the ordinary accessibility focus assertion passed. Keeping only the menu's inputs unchanged did not fix the symptom (11 replacements in 7.5 seconds). Splitting TV clock publication from presentation did (zero replacements in the same short replay).

The final frozen speed replay with native glass also passed: zero replacements across 1,043 samples over 17.48 seconds. The probe observes public focus-system UIView identity; this is not a pixel-color, GPU or hardware frame-rate measurement. Raw records stay private. The summary files below pin sources and intervals.

TV current-time and sleep-countdown changes now notify only the timeline/status observers. Chapter-index changes, timer activation/deactivation and normal session/control changes still notify presentation. Listening recording/sync and the iOS publication path retain their original behavior. Existing player properties remain available to control actions; no timer polling, paused playback or hidden time display is used to keep menus steady.

The previous TV glass helper always selected the older bordered style. Supported tvOS now uses native regular/prominent glass styles for player, browse and detail controls, with SDK/runtime/transparency/contrast fallbacks. Browse headings and artwork corners are consistent, while content uses a restrained opaque backdrop. Apple's Materials HIG keeps glass in navigation/controls and focused TV elements, rather than coating artwork/content. Source: https://developer.apple.com/design/human-interface-guidelines/materials (read October 9, 2026).

Fresh independent Standards and Spec reviews approved the bounded source patch. A normal iOS15-minimum simulator compilation passed, verifying the shared files' unaffected iOS branch. Other menu results, normal functional/accessibility replay, merged replay and delivery are recorded as completed below.

## Final menu replay

Final native source 050af4d8 passed each frozen-source probe: speed 0 replacements/1,040 samples, active sleep countdown 0/1,047, settings skip interval 0/1,046, library sort 0/1,044. Each stationary interval lasted 17.48–17.5 seconds within a 20-second remote hold. `evidence/comparison.json` records exact sources, probe/journey hashes, summaries and result paths.

The intermediate clock-only candidate still reconstructed the Settings row once during a routine 15-second progress flush. Its recovery section counted an in-flight save as unanswered. A new ledger recovery summary excludes only live in-memory transmission IDs, leaving persisted barriers and the existing all-write summary unchanged. TV Settings uses it and publishes only changed summaries. The same Settings probe then passed with zero replacements; unknown outcomes and failed durable resolution remain visible after the transmission completes, and retained writes are unanswered after relaunch. Clock setters are restricted to the owning playback file. A fresh final review approved these changes.

## Normal application acceptance

The normal production project (without the focus probe) passed 39 of 41 cases in `/tmp/loft-menu-normal.xcresult`: all 17 TV unit cases, seven catalog journeys, three layout stability journeys, six playback journeys, five readiness journeys including main-screen accessibility audits, and durable listening recovery after reauthentication. Two locale expectations failed because they referenced inherited translations removed during the independent rewrite. Both failures reproduced against released source e24ed0b7 in `/tmp/loft-menu-old-locale.xcresult`.

The existing locale journeys were repaired to assert the current declared English fallback while retaining actual German/Arabic strings, right-to-left alignment, selection, partial-translation disclosure and language persistence. A fresh independent review approved this test-only repair. Both focused cases passed on 48ba0b77 in `/tmp/loft-menu-locale-fixed.xcresult`, giving 41 distinct passing cases across the normal run and repaired locale replay, with no skipped cases. No translations or runtime lookup behavior changed.
