import { describe, expect, it } from "vitest";
import { resumeRewind } from "./rewind";

describe("resumeRewind", () => {
  it("steps back further the longer playback was paused, as the native apps do", () => {
    expect(resumeRewind(9_999)).toBe(0);
    expect(resumeRewind(10_000)).toBe(3);
    expect(resumeRewind(59_999)).toBe(3);
    expect(resumeRewind(60_000)).toBe(10);
    expect(resumeRewind(299_999)).toBe(10);
    expect(resumeRewind(300_000)).toBe(20);
    expect(resumeRewind(1_799_999)).toBe(20);
    expect(resumeRewind(1_800_000)).toBe(29.5);
    expect(resumeRewind(86_400_000)).toBe(29.5);
  });
});
