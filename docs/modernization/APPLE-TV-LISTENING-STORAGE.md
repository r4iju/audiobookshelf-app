# Shared Apple TV listening storage

The TV uses a bounded UserDefaults journal instead of relying on its purgeable file journal for new listening. iPhone/iPad retain their atomic protected file store. The journal contains account-scoped listening and resume positions, never access or refresh tokens.

A TV write is limited to 256,000 bytes. Old cached server positions can be evicted to fit; positions associated with retained listening records and all unacknowledged records are preserved. If pending listening itself exceeds the limit, a new recording fails before replacing durable or in-memory state. The player pauses and presents progress recovery. Synchronization acknowledges exact sent revisions, retaining newer changes.

On first upgrade, the existing file is read only when no persistent journal exists. A valid oversized file enters recovery mode: it can finish and synchronize existing sessions through atomic file writes, but cannot accept new listening. Once acknowledgments reduce it enough, it switches to the persistent store. The source remains intact; while this oversized recovery is still draining, it retains the previous file-storage limitation. A corrupt persistent journal does not fall back to a stale file and replay it. Duplicate record IDs and invalid record invariants are rejected without changing the source.

`ApplePlayback.isProgressFailure` exposes the existing error origin so the TV can offer progress retry for a journal/server failure and media recovery for an audio failure. The TV UI worker owns that wiring. Its Debug-only synthetic reset must clear `NativeListeningJournal` as well as the file; Release installation does not reset either.

## Verification

Three initial tests failed against the existing file-only behavior: deleting the file lost pending listening, the requested capacity limit was ignored, and corrupt persistent bytes did not take precedence over a stale file. They passed after implementation. Two later tests first failed with `storageFull` for a growing server cache and an oversized existing journal; both passed after cache compaction and recovery mode. A duplicate-ID test then genuinely failed because loading accepted the corrupt document, before the validation fix.

All 21 core tests pass. Minimum iOS 14 source typechecking, the TV simulator target and the existing production iPhone unsent-listening/termination/server-recovery journey pass. Source review found no remaining blocker. The integrated TV remote journeys and physical storage-pressure/background acceptance remain open until run against this change; simulator and isolated UserDefaults suites do not establish physical TV persistence under every system failure.
