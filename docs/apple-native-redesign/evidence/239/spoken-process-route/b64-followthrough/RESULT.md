# Final B64 spoken-accessibility followthrough

Product source remains `b64cc462060ba9a5a54790bfc6303144fd527a87`. These are bounded private operator checks, not new production tests or full accessibility acceptance. No screenshots, video, microphone recording, global audio tap, default-route change, owner installation or public upload was performed.

## Corrected long-duration fixture

The earlier 120-second fixture could expire before speech capture. The followthrough used real 8-second and 1192-second WAV tracks with item and chapter duration 1200. Original Connection assertions and capture-policy guards were preserved.

The phone attempt passed original Connection 1/1 and installed-resource verification, then public device opening reported DEVICE_IN_USE for an existing session. No playback or VoiceOver interaction followed. The attempt stopped and released its lease. Correction to its immutable private report: `sim release` implicitly shuts down the simulator. Its earlier statement that the foreign-session device was not shut down is false; there was no explicit takeover or force-close, but release did have that side effect.

## Actual iPad playback and speech limits

On an owned iPad, original Connection 1/1 and capture guards passed. Native Play and expanded presentation succeeded. Pause was an enabled, hittable Button and progress an enabled Slider. Synthetic-fixture playback reports advanced through 136 seconds of the 1200-second item, across the capture interval. This establishes continued playback in that measured seam, not successful spoken control order.

Two private process-only 16-second clips were captured. The progress clip was nonsilent, SHA256 `b5ea6c333156fc31a19e24c017557570d748992e7b2ea75f4c321d1d3e552bcb`; root local transcription produced only “alert voiceover gestures”. The Pause clip was entirely silent and rejected as speech evidence. Both intended VoiceOver focus selectors failed. Clip names are intended targets, not evidence of actual focus. Cleanup completed in 229 seconds within the 480-second bound, with VoiceOver Off independently queried before shutdown.

A separate bounded text-only discriminator ranked a system VoiceOver gesture alert first, presentation change second, and bridge focus capability third. After the current runner's abandoned tree work had drained, one effective public `alert get` command itself timed out. No actual alert metadata was obtained, no alert accepted or dismissed, and no blind coordinates, snapshot fallback, further capture or retry followed. Cleanup completed in 223 seconds; VoiceOver Off was queried before shutdown. The system-alert cause remains a supported hypothesis, not a confirmed production defect or universal focus limitation.

Root independently rehashed all 47 files and strictly verified signatures on the retained phone and latest iPad bundles. The preceding iPad app container no longer exists after the subsequent owned reinstall; its worker-recorded verification remains historical, not a current root revalidation. See sanitized [retained-bundle proof](root-retained-bundles.json). Original reports and audio remain private under `/tmp/native239-playing-long-b64`, `/tmp/native239-playing-pad-b64`, and `/tmp/native239-playing-pad-alert-b64`.

## Actual physical TV route

Read-only CoreDevice inventory distinguishes one actual connected Apple TV from a local simulator. Advertised AudioOutput/VoiceOver capabilities do not establish usable speech capture. Bounded installed-CLI read-only audio and VoiceOver queries failed with codes 1001 and 21062 respectively; see [query proof](tv-readonly-capability.json). No TV setting, app foreground, installation or audio route was changed. The exposed capture commands provide screenshots/video without a documented audio-only route, so they were not executed under the capture stop. These are tested route constraints, not proof that physical TV VoiceOver is unavailable.

## Release status

Full spoken accessibility remains incomplete. Strict combined contrast RED2 and original-minimum mobile execution also remain unresolved. Clean modern TV 49/49, clean TV17 replay 7/7 and fresh original mobile Connection 1/1 are separate passing scopes. Tickets #239 and dependent #240 remain blocked; PR #241 remains draft. Signed private candidates remain uninstalled and unaccepted. No merge, owner release installation or Apple upload occurred. Upstream discussion #2051 still has zero replies and no written permission.
