# iPad custom sleep timer: first Start tap

On iPad, the custom sleep timer journeys typed a duration and tapped Start timer, but the Sleep panel stayed open. The same
journeys passed on iPhone. Branch `fork/apple-ipad-sleep-timer` from `8123a742`. Simulator evidence only.

## Result

- `7a6eeaeb` changes `apple/UITests/ListeningControlsJourney.swift` only. After typing, the three timer journeys press
  Return, wait for the software keyboard to hide, then tap Start timer once.
- No assertion, duration, threshold or server report check changed. The helper adds one assertion (the keyboard hides).
- No production change. Nothing found justifies one.
- This does not show that a person on a physical iPad, with the software keyboard open, gets Start on the first tap. It
  also does not show that the original failure is XCTest-only. That path is physically unverified.

Cases:

- `testTimerAdjustmentChangesActualStopAndResetKeepsOriginalDuration`
- `testDisablingAnActiveSleepFadeRestoresActualAudioVolume`
- `testShortSleepTimerActuallyStopsAndPersistsPositionAfterLeavingPlayer`

## Cause observed in the simulator

Own simulators, iOS 27 (24A434), Xcode 27:

- `ABS iPad Sleep Timer QA 4276x`, iPad Pro 11-inch (M5), `AE9CBE4E-2DF2-43DF-88B7-E4601FDA4E5D`.
- `ABS iPhone Sleep Timer QA 4276x`, iPhone 17 Pro, `0A01CC75-30B6-4E8E-BC4C-C18C5BC77660`.

Fixtures ran on 42765/42766/42767/42769 through a local port remap. That remap is not committed.

| What | Before the Start tap | After the Start tap |
| --- | --- | --- |
| Software keyboard height | 282 | 0 |
| Sleep navigation bar y | 115 | 285 |
| Start timer | hittable, enabled, field value `3` | panel still open, no timer |

Findings:

- Entering the digit by tapping the software keyboard's `3` key fails the same way as `typeText`.
- Inside the app, `GCKeyboard.coalesced` is non-nil during the journey, so a hardware keyboard is attached.
- When the keyboard hides, the stack shows UIKit minimizing it from the touch itself, not from SwiftUI or the button:
  `_UIRemoteKeyboardsEventObserver _trackTouch` → `_endTrackingForTouch` → `_UIRemoteKeyboards _updateEventSource:options:responder:`
  → `UIKeyboardImpl _suppressSoftwareKeyboardStateChangedIgnoringPolicyDelegate:` → `hideKeyboardWithoutPreflightChecks`
  → `UIKeyboard setMinimized:`.
- The form sheet then re-centres under the touch, so touch-up no longer lands on Start. On iPhone the sheet does not move.
- With an empty field, taps on a button, an `onTapGesture`, a `simultaneousGesture` and a keyboard toolbar button all
  acted on the first tap, and the keyboard stayed up.
- After typing, a plain text row left the keyboard up. The first button tap minimized it and was lost.

Ruled out as the cause:

- Start's `.disabled` switch (removed: same failure).
- Re-rendering the Form on each keystroke (moving the field and Start into a child view with their own state: same failure).
- `.focusable(false)` (same failure).

All of these experiments were reverted.

A "Hide keyboard" key alternative was rejected: XCUITest reports that key at y 1479, outside the 1210 pt window, and cannot
tap it. That attempt left `AutomaticMinimizationEnabled = true` in the simulator's `com.apple.keyboard.preferences`
(written 07:41:05). With that state the software keyboard stays minimized, and even the unmodified journeys passed 3/3
(`/tmp/abs-ipad-timer-red-ipad-3cases.log`). The Return helper does not set it: the key was absent after each erased run.

## Runs

Every iPad result below that counts as RED or GREEN comes from a simulator erased just before the run.

| Run | Result |
| --- | --- |
| Unmodified `8123a742` journeys, fresh simulator (`/tmp/abs-ipad-timer-red1.log`) | `testTimerAdjustment…` fails at line 10, the panel does not close |
| Unmodified journey, erased simulator (`/tmp/abs-ipad-timer-cycle-without-helper-testTimerAdjustment…-1.log`) | Fails at line 10 (`waitForPanelToClose`) |
| Helper, erased simulator, one run per case (`/tmp/abs-ipad-timer-cycle-*with-helper*-1.log`) | All 3 pass. The first `testDisablingAnActiveSleepFade…` attempt failed before any test ran ("Simulator device failed to install the application" after the erase). The retry passed |
| Helper, iPad, not erased, after 07:41 (`green-ipad`, `green-ipad-x5`) | 3/3 and 15/15. Run with `AutomaticMinimizationEnabled` set, so these do not prove the helper on their own |
| Helper, iPhone, batch 1, 3 iterations (`/tmp/abs-ipad-timer-green-iphone-x3.log`) | 8/9. Iteration 3 of `testTimerAdjustment…` failed at line 13 ("Add 5 minutes" absent), and the app crashed (below) |
| Helper, iPhone, batch 2, 5 iterations (`/tmp/abs-ipad-timer-green-iphone-x5.log`) | 15/15 |

The iPhone crash:

- Report: `AudiobookshelfNative-2026-10-02-080035.ips`, from my iPhone simulator.
- Signal: SIGSEGV on a background dispatch queue.
- Frames: entirely Apple frameworks (`AssistantServices` `AFAnalytics logEventWithType` → `_os_log_error_impl` →
  `objc_msgSend`), no app frames.
- Timing: the timer had been started about 2 s earlier with playback paused. The countdown does not run while paused.
- Its cause and any relation to the helper are not determined. It did not recur in the next 15 iPhone runs.

Results in `/tmp/abs-ipad-timer/*.xcresult`.

## Remaining

On a physical iPad with only the software keyboard:

1. Type a custom duration.
2. Tap Start timer once, with the keyboard still open.
3. Check that the panel closes and the timer starts.

Then repeat with a hardware keyboard attached.
