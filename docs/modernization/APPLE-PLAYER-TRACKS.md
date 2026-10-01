# Native chapter media controls

The shared Apple player publishes chapter-relative system time when `chapterTrack` is on. System scrubbing translates the chapter position into a book position and clamps it to the current valid chapter. Invalid or absent chapters fall back to the full book. The system title and chapter count follow the selected chapter while the album retains the book title.

`previewChapterTrack` persists the choice. An unset preference follows the legacy iOS default, on; TV retains whole-book system time by default. Updating the running property immediately refreshes the system information. Native display choices and locking are implemented separately in the presentation lane.

Verification used the real production player, a synthetic local 20-second WAV and two chapters, with synthetic credentials and isolated fixture storage. The remote-command path was extracted without changing its old book-relative behavior before the regressions ran.

- `/tmp/abs-chapter-controls-red.log`: two tests, four failures. System duration/time remained 20/11 instead of 12/3; scrubbing to chapter second 2 moved to book second 2 instead of 10.
- `/tmp/abs-chapter-metadata-red.log`: the newly specified metadata behavior failed four assertions before its implementation. Title stayed the book title and chapter metadata was absent.
- `/tmp/abs-chapter-controls-final.log`: all three tests pass.
- `/tmp/abs-chapter-minimum.log`: combined native app, playback, core, migration, adoption and export sources typecheck for iOS 14.

Physical lock-screen/headset scrubbing, older OS runtime behavior and final display-preference journeys remain acceptance gates. Tests exercise the production system-scrub method directly; they do not synthesize a physical remote-command event.
