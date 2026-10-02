import type { StringKey } from "@/i18n/i18n";
import type { Settings } from "@/lib/settings/store";
import type { MediaProgress, PodcastEpisode } from "./schemas";

export const episodeSorts = [
  ["publishedAt", "LabelPubDate"],
  ["title", "LabelTitle"],
  ["season", "LabelSeason"],
  ["episode", "LabelEpisode"],
  ["filename", "LabelFilename"],
] as const satisfies ReadonlyArray<readonly [string, StringKey]>;
export type EpisodeSort = (typeof episodeSorts)[number][0];

export const episodeFilters = [
  ["all", "LabelAll"],
  ["incomplete", "LabelIncomplete"],
  ["inProgress", "LabelInProgress"],
  ["complete", "LabelComplete"],
] as const satisfies ReadonlyArray<readonly [string, StringKey]>;
export type EpisodeFilter = (typeof episodeFilters)[number][0];

export interface EpisodeListState {
  sort: EpisodeSort;
  desc: boolean;
  filter: EpisodeFilter;
}

/** The saved choice applies to every podcast; without one, only episodic podcasts list newest first, as in the legacy client. */
export function episodeListState(
  saved: Pick<Settings, "podcastEpisodesOrderBy" | "podcastEpisodesOrderDesc" | "podcastEpisodesFilterBy">,
  podcastType: string | null | undefined,
): EpisodeListState {
  return {
    sort: saved.podcastEpisodesOrderBy,
    desc: saved.podcastEpisodesOrderDesc ?? podcastType === "episodic",
    filter: saved.podcastEpisodesFilterBy,
  };
}

export const episodeDuration = (episode: Pick<PodcastEpisode, "duration" | "audioFile">) =>
  episode.duration ?? episode.audioFile?.duration ?? 0;

type EpisodeLike = Pick<PodcastEpisode, "id" | "title"> &
  Partial<Pick<PodcastEpisode, "publishedAt" | "season" | "episode" | "audioFile">>;

function sortValue(episode: EpisodeLike, sort: EpisodeSort): string | number {
  switch (sort) {
    case "publishedAt":
      return episode.publishedAt ?? Number.NEGATIVE_INFINITY;
    case "filename":
      return episode.audioFile?.metadata.filename ?? "";
    default:
      return episode[sort] ?? "";
  }
}

const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });

export function visibleEpisodes<T extends EpisodeLike>(
  episodes: T[],
  progressOf: Map<string, MediaProgress>,
  state: EpisodeListState,
): T[] {
  const keep: Record<EpisodeFilter, (progress: MediaProgress | undefined) => boolean> = {
    all: () => true,
    incomplete: (progress) => !progress?.isFinished,
    inProgress: (progress) => !!progress && !progress.isFinished,
    complete: (progress) => !!progress?.isFinished,
  };
  const shown = episodes.filter((episode) => keep[state.filter](progressOf.get(episode.id)));
  const direction = state.desc ? -1 : 1;
  return shown.sort((a, b) => {
    const left = sortValue(a, state.sort);
    const right = sortValue(b, state.sort);
    const order =
      typeof left === "number" && typeof right === "number"
        ? left === right
          ? 0
          : left < right
            ? -1
            : 1
        : collator.compare(String(left), String(right));
    return order * direction;
  });
}

const MAX_FILENAME_LENGTH = 240;

/** Mirrors the folder naming of the server's own clients so podcasts added here land where they would there. */
export function sanitizeFilename(input: string) {
  const sanitized = input
    .replace(":", " - ")
    .replace(/[/?<>\\:*|"]/g, "")
    // biome-ignore lint/suspicious/noControlCharactersInRegex: control characters are what this removes
    .replace(/[\x00-\x1f\x80-\x9f]/g, "")
    .replace(/^\.+$/, "")
    .replace(/[\n\r]/g, "")
    .replace(/^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\..*)?$/i, "")
    .replace(/[. ]+$/, "");
  return sanitized.slice(0, MAX_FILENAME_LENGTH);
}

export function podcastFolderPath(folder: string, title: string) {
  const name = sanitizeFilename(title);
  return name ? `${folder.replace(/\/+$/, "")}/${name}` : null;
}

interface FeedEpisodeLike {
  title?: string | null;
  publishedAt?: number | null;
  enclosure?: { url: string } | null;
}

/** Feed episodes, newest first, marking those the podcast already has (matched by enclosure address). */
export function newFeedEpisodes<T extends FeedEpisodeLike>(
  feed: T[],
  existing: Array<{ enclosure?: { url: string } | null }>,
) {
  const have = new Set(existing.flatMap((episode) => (episode.enclosure ? [episode.enclosure.url] : [])));
  return [...feed]
    .sort((a, b) => (b.publishedAt ?? 0) - (a.publishedAt ?? 0))
    .map((episode) => ({ episode, downloaded: !!episode.enclosure && have.has(episode.enclosure.url) }));
}
