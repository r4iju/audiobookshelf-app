# Actual paused-player VoiceOver attempt

Original cached login test passed1/1 with no rebuild/source changes, synthetic accepted:true. Installed47 resources matched verified f922 cache (mobile production equivalent465) and strict/deep signature passed. Initial VOOff queried.

Native book0→Play→compact Pause succeeded before expansion. Compact mini-resume-playback attrs: Play/enabledtrue/hittabletrue. Expanded resume-playback likewise Play/enabledtrue/hittabletrue, exact attrs in paused-expanded-attrs.json. Thus paused intent was measured, not inferred from end-of-book.

Enabled VoiceOver only after expanded paused player. Existing system onboarding already dismissed in prior owned setup. One process-only16-second clip recorded with verified ownvot PID, output-onlyzero-input hardware clock, tap-onlyaggregateinput2. WAV hash and nonzero342444 samples in clips.json. Both requested native playback-position/playback-elapsed focus actions failed with explicit runner AX watchdog-busy status (actions JSON preserves diagnostics). No completed focus/values query, no selected-speed/disabled/readers assessment. Any automatic actual speech is independently assessed by parent local ASR. No full speech acceptance claim.

The same watchdog occurs with confirmed paused intent, so ongoing-playing progress invalidation alone is insufficient explanation. This does not establish a tool-only or product-hang diagnosis. Stopped after this finite paired attempt, no snapshot/fallback/retry or image/video generation.

Cleanup: VOOff explicitly restored and queried; QA app terminated; only owned fixture PID groups stopped; owned phone DAF19749 panel closed+shutdown and lease released. No keyboard/content-size/appearance/defaultaudio/mic settings changed. Installed app retained. No shared source/index/GH/Actions/owner apps/accounts/server changes. No builds/new tests.
