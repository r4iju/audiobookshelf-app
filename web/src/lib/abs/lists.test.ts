import { describe, expect, it } from "vitest";
import { nextToPlay } from "./lists";

const finished = (libraryItemId: string, episodeId: string | null = null) => ({
  id: `${libraryItemId}-${episodeId}`,
  libraryItemId,
  episodeId,
  duration: 10,
  progress: 1,
  currentTime: 10,
  isFinished: true,
  lastUpdate: 0,
});

describe("playing a playlist or collection", () => {
  const entries = [
    { libraryItemId: "a", episodeId: null, playable: true },
    { libraryItemId: "b", episodeId: null, playable: false },
    { libraryItemId: "p", episodeId: "e1", playable: true },
    { libraryItemId: "p", episodeId: "e2", playable: true },
  ];

  it("starts the first playable entry the listener has not finished", () => {
    expect(nextToPlay(entries, [finished("a")])).toEqual(entries[2]);
    expect(nextToPlay(entries, [])).toEqual(entries[0]);
  });

  it("tells episodes of the same podcast apart", () => {
    expect(nextToPlay(entries, [finished("a"), finished("p", "e1")])).toEqual(entries[3]);
    expect(nextToPlay(entries, [finished("a"), finished("p", "e1"), finished("p", "e2")])).toBeNull();
  });
});
