import { describe, expect, it } from "vitest";
import {
  episodeListState,
  newFeedEpisodes,
  podcastFolderPath,
  sanitizeFilename,
  visibleEpisodes,
} from "./episodes";
import type { PodcastEpisode } from "./schemas";

const episode = (id: string, fields: Partial<PodcastEpisode> = {}) => ({
  id,
  libraryItemId: "pod",
  title: `Episode ${id}`,
  chapters: [],
  ...fields,
});

const progress = (episodeId: string, isFinished: boolean, currentTime = 10) => ({
  id: `p-${episodeId}`,
  libraryItemId: "pod",
  episodeId,
  duration: 100,
  progress: isFinished ? 1 : 0.1,
  currentTime,
  isFinished,
  lastUpdate: 0,
});

describe("episode list state", () => {
  const saved = {
    podcastEpisodesOrderBy: "publishedAt",
    podcastEpisodesOrderDesc: null,
    podcastEpisodesFilterBy: "incomplete",
  } as const;

  it("lists unfinished episodes by publish date, newest first only for episodic podcasts", () => {
    expect(episodeListState(saved, "episodic")).toEqual({
      sort: "publishedAt",
      desc: true,
      filter: "incomplete",
    });
    expect(episodeListState(saved, "serial").desc).toBe(false);
    expect(episodeListState(saved, null).desc).toBe(false);
  });

  it("follows the saved choice whatever the podcast type", () => {
    const chosen = {
      podcastEpisodesOrderBy: "title",
      podcastEpisodesOrderDesc: false,
      podcastEpisodesFilterBy: "all",
    } as const;
    expect(episodeListState(chosen, "episodic")).toEqual({ sort: "title", desc: false, filter: "all" });
  });
});

describe("visible episodes", () => {
  const episodes = [
    episode("1", { publishedAt: 100, episode: "1" }),
    episode("2", { publishedAt: 300, episode: "10" }),
    episode("3", { publishedAt: null, episode: "2" }),
    episode("4", { publishedAt: 200, episode: "3" }),
  ];
  const progressOf = new Map([
    ["2", progress("2", true)],
    ["4", progress("4", false)],
  ]);
  const ids = (list: Array<{ id: string }>) => list.map((entry) => entry.id);

  it("filters by the listener's progress on each episode", () => {
    const all = { sort: "publishedAt", desc: false } as const;
    expect(ids(visibleEpisodes(episodes, progressOf, { ...all, filter: "incomplete" }))).toEqual([
      "3",
      "1",
      "4",
    ]);
    expect(ids(visibleEpisodes(episodes, progressOf, { ...all, filter: "complete" }))).toEqual(["2"]);
    expect(ids(visibleEpisodes(episodes, progressOf, { ...all, filter: "inProgress" }))).toEqual(["4"]);
    expect(ids(visibleEpisodes(episodes, progressOf, { ...all, filter: "all" }))).toHaveLength(4);
  });

  it("treats a missing publish date as the oldest and compares episode numbers numerically", () => {
    expect(
      ids(visibleEpisodes(episodes, new Map(), { sort: "publishedAt", desc: true, filter: "all" })),
    ).toEqual(["2", "4", "1", "3"]);
    expect(
      ids(visibleEpisodes(episodes, new Map(), { sort: "episode", desc: false, filter: "all" })),
    ).toEqual(["1", "3", "4", "2"]);
  });
});

describe("new podcasts and episodes", () => {
  it("names the podcast folder the way the server's own clients do", () => {
    expect(sanitizeFilename('Talk: "Late" Show?')).toBe("Talk -  Late Show");
    expect(podcastFolderPath("/podcasts/", "News: Daily")).toBe("/podcasts/News -  Daily");
    expect(podcastFolderPath("/podcasts", "...")).toBeNull();
  });

  it("offers only feed episodes the podcast does not already have", () => {
    const feed = [
      { title: "A", enclosure: { url: "https://feed/a.mp3" }, publishedAt: 1 },
      { title: "B", enclosure: { url: "https://feed/b.mp3" }, publishedAt: 2 },
    ];
    const offered = newFeedEpisodes(feed, [episode("x", { enclosure: { url: "https://feed/a.mp3" } })]);
    expect(offered.map((entry) => [entry.episode.title, entry.downloaded])).toEqual([
      ["B", false],
      ["A", true],
    ]);
  });
});
