# Explicitly requested private owner installation

The user requested “Ship it to my devices” after the incomplete release status was reported. This authorizes private installation before full release acceptance. It does not waive the remaining requirements, authorize a merge or public Apple upload, or constitute written upstream permission.

Exact B64 signed Release candidates were independently rehashed against all 46 phone and 36 TV files and deep/strict signature verification passed. Existing profiles cover the actual target devices. Existing app IDs and signing were retained; no uninstall, account reset or owner-data migration was performed. The operating system reports different data-container paths after both in-place installations. No uninstall or reset was requested, but retained account/data integrity has not been verified by an owner journey. A changed path alone does not establish data loss.

- iPhone: install succeeded, Audiobook Loft 1.0.0/build 1 is listed afterward, and native launch succeeded.
- Living-room Apple TV: install succeeded and Audiobook Loft 1.0.0/build 1 is listed afterward. Foreground launch was refused because the system is asleep; no wake or system-setting change was attempted.
- iPad: listed unavailable; an actual bounded installation attempt was rejected with CoreDeviceError4016. It was not installed.

Raw device-specific JSON remains private in `/tmp/audiobook-loft-owner-install-b64`. Sanitized [installation proof](installation.json) records the outcomes. No screenshots/video, owner credentials, TestFlight/App Store submission, source changes or release merge occurred. Strict contrast, full spoken accessibility and original-minimum mobile verification remain unresolved. Tickets239/240 remain incomplete and PR241 stays draft. The previous candidate reports retain their historical NOT INSTALLED state; this later explicit installation supersedes that state for phone and TV only.
