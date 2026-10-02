/** Seconds to step back when playback resumes after a pause of the given length, as in the Android app. */
export function resumeRewind(pausedMs: number) {
  if (pausedMs < 10_000) return 0;
  if (pausedMs < 60_000) return 3;
  if (pausedMs < 300_000) return 10;
  if (pausedMs < 1_800_000) return 20;
  return 29.5;
}
