# Bounded Android migration runtime attempt, October 3, 2026

Checked production source: `4ef1a06b9e8e427dfdc4c5375dd406743f8ae786`.
Issue #52 remains open. No production implementation changed.

- One offline debug build passed. The merged UI/UX smoke completed on the
  synthetic API 36 emulator at 320 dp/150% text: Library card → Play → neutral
  localized lock/unlock toggle → minimize → mini overflow “Stop and close
  player”. Actual combined player screenshot inspected; final XML has no mini
  player. Pending control commands completed during cleanup.
- Inspected `MigrationJourney`, its exported archive provider, and the separate
  `settingsApplied`/`playerSettingsApplied` mapping. The existing journey does
  not establish the PR #123 player-boolean/older-marker invariants. A scoped
  manual synthetic archive was selected, but no migration data was installed
  or changed before the transport blocked this attempt.
- Targeted ADB commands temporarily stopped responding. `get-state` and one
  targeted reconnect each timed out after eight seconds. Later cleanup commands
  succeeded. Diagnosis stopped at the authorized one-pass/one-correction cap;
  no emulator restart, repeated migration attempt or product defect claim.
- Fresh import, older committed-import completion, persisted values after
  relaunch, repeat attachment preserving user changes, and device/display
  preservation remain **unverified**. The PR #123 mapping's compile-only gap
  is not closed by this attempt.

Private screenshot/XML, build/fixture/emulator logs, prior app-data backup and
outcome manifest are retained in the central coordination directory under
`migration-runtime-evidence`. Display-restoration commands succeeded; owned
fixture/emulator stopped. No wipe, broad migration suite, baseline lint,
translation sweep, owner interaction or release rebuild. Real export/import,
in-place/upstream sandbox, physical, accessibility and other #52 gates remain.

## Recovered-infrastructure continuation

On October 3, a separate bounded attempt used the installed debug APK with
SHA-256 `3b6f7204609b029c1ec87b60b9846d53d028d82b1551d67518688ed1fd1b46f6`.
It matches the retained combined build at `4ef1a06b9e8e427dfdc4c5375dd406743f8ae786`;
checkout `5b25546e5e40aebe6c3b0f802c6c29152fc4b4a3` has identical Android source.
The earlier control smoke was not repeated.

ADB remained responsive. The installed legacy test package did not register
`com.audiobookshelf.journeys.archives`, confirmed by package inventory and
“Failed to find provider info” in the emulator log. Opening the synthetic
preferences-only archive through that URI displayed the unreadable-file
message before preflight. One correction opened the same archive from the
synthetic app's own cache using a file URI; it also displayed that message.
The cause of that second refusal was not established. No further correction,
fixture rebuild, test run or product change was made.

Execution/diagnosis stopped after 126 seconds. Neither fresh import nor the
older committed-import player-preference step started; their runtime outcomes
remain **unverified**. This does not close the PR #123 compile-only gap or any
original #52 acceptance criterion. A future attempt needs a verified registered
archive provider or supported document-picker fixture before importing.

Private source/APK identity, minimal archive, preflight XML, package/log evidence,
script, fresh app-data backup and result are retained under
`android-migration-coldboot/preference-proof` in the central coordination area.
The previous app-data tar is preserved. The synthetic app was stopped, backup
restored, and persisted settings equality confirmed. Owned cache fixtures and
reverse mapping were removed; targeted emulator shutdown succeeded and the
owned server fixture stopped. No global ADB restart, wipe, owner operation,
package build, broad suite, lint or localization sweep occurred.
