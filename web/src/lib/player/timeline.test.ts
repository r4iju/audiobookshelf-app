import { describe, expect, it } from "vitest";
import { chapterIndexAt, locate, nextChapterStart, previousChapterStart } from "./timeline";

const tracks = [
  { startOffset: 0, duration: 30 },
  { startOffset: 30, duration: 30.1 },
  { startOffset: 60.1, duration: 30.1 },
];
const chapters = [
  { id: 0, start: 0, end: 30, title: "One" },
  { id: 1, start: 30, end: 60.1, title: "Two" },
  { id: 2, start: 60.1, end: 90.2, title: "Three" },
];

describe("book timeline across files", () => {
  it("maps a book time to the file that contains it and the offset inside that file", () => {
    expect(locate(tracks, 45)).toEqual({ index: 1, offset: 15 });
    expect(locate(tracks, 30)).toEqual({ index: 1, offset: 0 });
    expect(locate(tracks, 0)).toEqual({ index: 0, offset: 0 });
  });

  it("clamps times before the start and after the end", () => {
    expect(locate(tracks, -5)).toEqual({ index: 0, offset: 0 });
    expect(locate(tracks, 500)).toEqual({ index: 2, offset: 30.1 });
  });
});

describe("chapters", () => {
  it("finds the chapter playing at a time", () => {
    expect(chapterIndexAt(chapters, 0)).toBe(0);
    expect(chapterIndexAt(chapters, 59.9)).toBe(1);
    expect(chapterIndexAt(chapters, 90.2)).toBe(2);
    expect(chapterIndexAt([], 10)).toBe(-1);
  });

  it("goes to the previous chapter only when within four seconds of the current chapter's start", () => {
    expect(previousChapterStart(chapters, 45)).toBe(30);
    expect(previousChapterStart(chapters, 33)).toBe(0);
    expect(previousChapterStart(chapters, 2)).toBe(0);
  });

  it("goes to the next chapter's start, or nowhere from the last chapter", () => {
    expect(nextChapterStart(chapters, 10)).toBe(30);
    expect(nextChapterStart(chapters, 70)).toBeNull();
  });
});
