// Pure time arithmetic for a book made of several audio files and a chapter list, all in book seconds.

export interface TrackSpan {
  startOffset: number;
  duration: number;
}

export interface ChapterSpan {
  start: number;
  end: number;
}

/** The legacy players treat a press within this many seconds of a chapter's start as "go to the previous one". */
export const PREVIOUS_CHAPTER_GRACE = 4;

export function locate(tracks: readonly TrackSpan[], time: number): { index: number; offset: number } {
  if (tracks.length === 0) return { index: 0, offset: 0 };
  const last = tracks.length - 1;
  const lastTrack = tracks[last] as TrackSpan;
  if (time >= lastTrack.startOffset + lastTrack.duration) return { index: last, offset: lastTrack.duration };
  for (let index = last; index >= 0; index--) {
    const track = tracks[index] as TrackSpan;
    if (time >= track.startOffset) return { index, offset: round(time - track.startOffset) };
  }
  return { index: 0, offset: 0 };
}

function round(value: number) {
  return Math.round(value * 1000) / 1000;
}

export function chapterIndexAt(chapters: readonly ChapterSpan[], time: number) {
  if (chapters.length === 0) return -1;
  for (let index = chapters.length - 1; index >= 0; index--) {
    if (time >= (chapters[index] as ChapterSpan).start) return index;
  }
  return 0;
}

export function previousChapterStart(chapters: readonly ChapterSpan[], time: number) {
  const index = chapterIndexAt(chapters, time);
  if (index < 0) return 0;
  const current = chapters[index] as ChapterSpan;
  if (time - current.start > PREVIOUS_CHAPTER_GRACE || index === 0) {
    return time - current.start > PREVIOUS_CHAPTER_GRACE ? current.start : 0;
  }
  return (chapters[index - 1] as ChapterSpan).start;
}

export function nextChapterStart(chapters: readonly ChapterSpan[], time: number) {
  const next = chapters[chapterIndexAt(chapters, time) + 1];
  return next ? next.start : null;
}
