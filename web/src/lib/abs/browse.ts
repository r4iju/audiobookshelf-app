import type { StringKey } from "@/i18n/i18n";
import type { Library } from "./schemas";

// Library browsing state lives in the address bar so a reload, back button or shared link restores it exactly.

export const bookSorts = [
  ["media.metadata.title", "LabelTitle"],
  ["media.metadata.authorName", "LabelAuthorFirstLast"],
  ["media.metadata.authorNameLF", "LabelAuthorLastFirst"],
  ["media.metadata.publishedYear", "LabelPublishYear"],
  ["addedAt", "LabelAddedAt"],
  ["size", "LabelSize"],
  ["media.duration", "LabelDuration"],
  ["birthtimeMs", "LabelFileBirthtime"],
  ["mtimeMs", "LabelFileModified"],
  ["progress", "LabelLibrarySortByProgress"],
  ["progress.createdAt", "LabelLibrarySortByProgressStarted"],
  ["progress.finishedAt", "LabelLibrarySortByProgressFinished"],
  ["random", "LabelRandomly"],
] as const satisfies ReadonlyArray<readonly [string, StringKey]>;

export const podcastSorts = [
  ["media.metadata.title", "LabelTitle"],
  ["media.metadata.author", "LabelAuthor"],
  ["addedAt", "LabelAddedAt"],
  ["size", "LabelSize"],
  ["media.numTracks", "LabelNumberOfEpisodes"],
  ["birthtimeMs", "LabelFileBirthtime"],
  ["mtimeMs", "LabelFileModified"],
  ["random", "LabelRandomly"],
] as const satisfies ReadonlyArray<readonly [string, StringKey]>;

const knownSorts = new Set<string>([...bookSorts, ...podcastSorts].map(([key]) => key));

export function sortsFor(mediaType: Library["mediaType"]) {
  return mediaType === "podcast" ? podcastSorts : bookSorts;
}

export interface BrowseState {
  sort: string;
  desc: boolean;
  filter: string | null;
  /** 1-based, as shown to people. */
  page: number;
}

export const defaultBrowse: BrowseState = { sort: "addedAt", desc: true, filter: null, page: 1 };

function base64Utf8(value: string) {
  let binary = "";
  for (const byte of new TextEncoder().encode(value)) binary += String.fromCharCode(byte);
  return btoa(binary);
}

/** The server reads `group.<urlencoded base64 of UTF-8 value>`. */
export function encodeFilter(group: string, value: string) {
  return `${group}.${encodeURIComponent(base64Utf8(value))}`;
}

export function decodeFilter(filter: string): { group: string; value: string } | null {
  const dot = filter.indexOf(".");
  if (dot < 1) return null;
  try {
    const binary = atob(decodeURIComponent(filter.slice(dot + 1)));
    const value = new TextDecoder().decode(Uint8Array.from(binary, (char) => char.charCodeAt(0)));
    return { group: filter.slice(0, dot), value };
  } catch {
    return null;
  }
}

const newestFirst = new Set([
  "addedAt",
  "birthtimeMs",
  "mtimeMs",
  "progress",
  "progress.createdAt",
  "progress.finishedAt",
]);

/** The direction a sort starts in when the address does not say: dates newest first, everything else A to Z. */
export function naturalDesc(sort: string) {
  return newestFirst.has(sort);
}

export function browseFromParams(params: URLSearchParams): BrowseState {
  const sort = params.get("sort");
  const page = Number(params.get("page"));
  const filter = params.get("filter");
  return {
    sort: sort && knownSorts.has(sort) ? sort : defaultBrowse.sort,
    desc: params.has("desc")
      ? params.get("desc") === "1"
      : naturalDesc(sort && knownSorts.has(sort) ? sort : defaultBrowse.sort),
    filter: filter && decodeFilter(filter) ? filter : null,
    page: Number.isInteger(page) && page >= 1 ? page : 1,
  };
}

export function browseToParams(state: BrowseState) {
  const params = new URLSearchParams();
  if (state.sort !== defaultBrowse.sort) params.set("sort", state.sort);
  if (state.desc !== naturalDesc(state.sort)) params.set("desc", state.desc ? "1" : "0");
  if (state.filter) params.set("filter", state.filter);
  if (state.page > 1) params.set("page", String(state.page));
  return params.toString();
}

export function itemsQuery(state: BrowseState, options: { limit: number; collapseSeries: boolean }) {
  const params = new URLSearchParams({
    sort: state.sort,
    desc: state.desc ? "1" : "0",
    limit: String(options.limit),
    page: String(state.page - 1),
    minified: "1",
    include: "rssfeed,numEpisodesIncomplete",
  });
  if (state.filter) params.set("filter", state.filter);
  params.set("collapseseries", options.collapseSeries && !state.filter ? "1" : "0");
  return params.toString();
}
