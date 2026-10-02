import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { useAbs } from "@/lib/session/store";
import { type BrowseState, itemsQuery } from "./browse";
import { AbsError } from "./client";
import {
  authorDetailSchema,
  authorsResponseSchema,
  collectionSchema,
  librariesResponseSchema,
  libraryItemSchema,
  libraryWithFilterDataSchema,
  listeningStatsSchema,
  loginResponseSchema,
  mediaProgressSchema,
  pagedCollectionsSchema,
  pagedItemsSchema,
  pagedPlaylistsSchema,
  pagedSeriesSchema,
  personalizedSchema,
  playlistSchema,
  podcastFeedSchema,
  podcastSearchResultsSchema,
  recentEpisodesSchema,
  searchResultsSchema,
  seriesSchema,
  serverYearStatsSchema,
  userSchema,
  yearStatsSchema,
} from "./schemas";

// Every key starts with the connection id so two saved servers or accounts never share cached data.
export const keys = {
  all: (connectionId: string) => [connectionId] as const,
  libraries: (connectionId: string) => [connectionId, "libraries"] as const,
  me: (connectionId: string) => [connectionId, "me"] as const,
  heldDeliveries: (connectionId: string) => [connectionId, "held-deliveries"] as const,
  listeningStats: (connectionId: string) => [connectionId, "stats", "listening"] as const,
  yearStats: (connectionId: string, year: number) => [connectionId, "stats", "year", year] as const,
  serverYearStats: (connectionId: string, year: number) =>
    [connectionId, "stats", "server-year", year] as const,
  library: (connectionId: string, libraryId: string) => [connectionId, "library", libraryId] as const,
  personalized: (connectionId: string, libraryId: string) =>
    [connectionId, "library", libraryId, "personalized"] as const,
  items: (connectionId: string, libraryId: string, query: string) =>
    [connectionId, "library", libraryId, "items", query] as const,
  item: (connectionId: string, itemId: string) => [connectionId, "item", itemId] as const,
  ereaderDevices: (connectionId: string) => [connectionId, "ereader-devices"] as const,
  itemProgress: (connectionId: string, itemId: string) => [connectionId, "item-progress", itemId] as const,
  ebook: (connectionId: string, path: string) => [connectionId, "ebook", path] as const,
  filterData: (connectionId: string, libraryId: string) =>
    [connectionId, "library", libraryId, "filterdata"] as const,
  search: (connectionId: string, libraryId: string, q: string, limit: number) =>
    [connectionId, "library", libraryId, "search", q, limit] as const,
  seriesList: (connectionId: string, libraryId: string, page: number) =>
    [connectionId, "library", libraryId, "series", page] as const,
  series: (connectionId: string, libraryId: string, seriesId: string) =>
    [connectionId, "library", libraryId, "series", "one", seriesId] as const,
  authors: (connectionId: string, libraryId: string) =>
    [connectionId, "library", libraryId, "authors"] as const,
  author: (connectionId: string, libraryId: string, authorId: string) =>
    [connectionId, "library", libraryId, "author", authorId] as const,
  recentEpisodes: (connectionId: string, libraryId: string, page: number) =>
    [connectionId, "library", libraryId, "recent-episodes", page] as const,
  // Collections and playlists share a prefix so one socket event or mutation refreshes every list view.
  lists: (connectionId: string) => [connectionId, "lists"] as const,
  collections: (connectionId: string, libraryId: string) =>
    [connectionId, "lists", "collections", libraryId] as const,
  collection: (connectionId: string, collectionId: string) =>
    [connectionId, "lists", "collection", collectionId] as const,
  playlists: (connectionId: string, libraryId: string) =>
    [connectionId, "lists", "playlists", libraryId] as const,
  playlist: (connectionId: string, playlistId: string) =>
    [connectionId, "lists", "playlist", playlistId] as const,
  podcastFeed: (connectionId: string, feedUrl: string) => [connectionId, "podcast-feed", feedUrl] as const,
  podcastSearch: (connectionId: string, term: string) => [connectionId, "podcast-search", term] as const,
};

export function useLibraries() {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.libraries(connection.id),
    queryFn: ({ signal }) => client.get("/api/libraries", librariesResponseSchema, signal),
    select: (data) => [...data.libraries].sort((a, b) => a.displayOrder - b.displayOrder),
  });
}

export function useMe() {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.me(connection.id),
    queryFn: ({ signal }) => client.get("/api/me", userSchema, signal),
  });
}

export function useListeningStats() {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.listeningStats(connection.id),
    queryFn: ({ signal }) => client.get("/api/me/listening-stats", listeningStatsSchema, signal),
  });
}

export function useYearStats(year: number) {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.yearStats(connection.id, year),
    queryFn: ({ signal }) => client.get(`/api/me/stats/year/${year}`, yearStatsSchema, signal),
  });
}

/** Only administrators may read the server's year; the server refuses everyone else. */
export function useServerYearStats(year: number) {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.serverYearStats(connection.id, year),
    queryFn: ({ signal }) => client.get(`/api/stats/year/${year}`, serverYearStatsSchema, signal),
  });
}

export function usePersonalized(libraryId: string) {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.personalized(connection.id, libraryId),
    queryFn: ({ signal }) =>
      client.get(
        `/api/libraries/${libraryId}/personalized?include=rssfeed,numEpisodesIncomplete`,
        personalizedSchema,
        signal,
      ),
  });
}

/** Progress for whole items (not episodes), keyed by library item id. */
export function useItemProgress() {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.me(connection.id),
    queryFn: ({ signal }) => client.get("/api/me", userSchema, signal),
    select: (user) =>
      new Map(
        user.mediaProgress.filter((entry) => !entry.episodeId).map((entry) => [entry.libraryItemId, entry]),
      ),
  });
}

export function useEpisodeProgress(itemId: string) {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.me(connection.id),
    queryFn: ({ signal }) => client.get("/api/me", userSchema, signal),
    select: (user) =>
      new Map(
        user.mediaProgress.flatMap((entry) =>
          entry.libraryItemId === itemId && entry.episodeId ? [[entry.episodeId, entry] as const] : [],
        ),
      ),
  });
}

/** Read fresh on open so a place saved by another client is where reading resumes. */
export function useServerItemProgress(itemId: string) {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.itemProgress(connection.id, itemId),
    queryFn: ({ signal }) =>
      client.get(`/api/me/progress/${itemId}`, mediaProgressSchema, signal).catch((error: unknown) => {
        if (error instanceof AbsError && error.kind === "not-found") return null;
        throw error;
      }),
    staleTime: 0,
  });
}

export function useEbookFile(path: string) {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.ebook(connection.id, path),
    queryFn: ({ signal }) => client.blob(path, signal),
    staleTime: Number.POSITIVE_INFINITY,
    gcTime: 60_000,
    retry: false,
  });
}

export const PAGE_SIZE = 24;

export function useItems(libraryId: string, state: BrowseState, collapseSeries: boolean) {
  const { client, connection } = useAbs();
  const query = itemsQuery(state, { limit: PAGE_SIZE, collapseSeries });
  return useQuery({
    queryKey: keys.items(connection.id, libraryId, query),
    queryFn: ({ signal }) =>
      client.get(`/api/libraries/${libraryId}/items?${query}`, pagedItemsSchema, signal),
    placeholderData: keepPreviousData,
  });
}

export function useFilterData(libraryId: string) {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.filterData(connection.id, libraryId),
    queryFn: ({ signal }) =>
      client.get(`/api/libraries/${libraryId}?include=filterdata`, libraryWithFilterDataSchema, signal),
    staleTime: 5 * 60_000,
  });
}

/**
 * Up to `limit` matches of each kind, with the limit they were found under. The server has no paging, so one more
 * than that is asked for: `more` says some kind returned it, and a larger limit would show further matches.
 */
export function useSearch(libraryId: string, q: string, limit: number) {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.search(connection.id, libraryId, q, limit),
    queryFn: async ({ signal }) => {
      const found = await client.get(
        `/api/libraries/${libraryId}/search?${new URLSearchParams({ q, limit: String(limit + 1) })}`,
        searchResultsSchema,
        signal,
      );
      const kinds = [
        found.book,
        found.podcast,
        found.series,
        found.authors,
        found.narrators,
        found.tags,
        found.genres,
      ];
      return {
        book: found.book.slice(0, limit),
        podcast: found.podcast.slice(0, limit),
        series: found.series.slice(0, limit),
        authors: found.authors.slice(0, limit),
        narrators: found.narrators.slice(0, limit),
        tags: found.tags.slice(0, limit),
        genres: found.genres.slice(0, limit),
        limit,
        more: kinds.some((matches) => matches.length > limit),
      };
    },
    enabled: q.trim().length > 0,
    placeholderData: keepPreviousData,
  });
}

export function useItem(itemId: string) {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.item(connection.id, itemId),
    queryFn: ({ signal }) =>
      client.get(`/api/items/${itemId}?expanded=1&include=rssfeed,downloads`, libraryItemSchema, signal),
  });
}

/** The e-readers this account may send ebooks to; the server filters them by each device's availability. */
export function useEreaderDevices() {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.ereaderDevices(connection.id),
    queryFn: async ({ signal }) =>
      (await client.send("POST", "/api/authorize", undefined, loginResponseSchema, signal)).ereaderDevices,
  });
}

export function useSeriesList(libraryId: string, page: number) {
  const { client, connection } = useAbs();
  const query = new URLSearchParams({
    sort: "name",
    limit: String(PAGE_SIZE),
    page: String(page - 1),
    minified: "1",
  });
  return useQuery({
    queryKey: keys.seriesList(connection.id, libraryId, page),
    queryFn: ({ signal }) =>
      client.get(`/api/libraries/${libraryId}/series?${query}`, pagedSeriesSchema, signal),
    placeholderData: keepPreviousData,
  });
}

export function useSeries(libraryId: string, seriesId: string) {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.series(connection.id, libraryId, seriesId),
    queryFn: ({ signal }) =>
      client.get(`/api/libraries/${libraryId}/series/${seriesId}?include=progress`, seriesSchema, signal),
  });
}

export function useAuthors(libraryId: string) {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.authors(connection.id, libraryId),
    queryFn: ({ signal }) => client.get(`/api/libraries/${libraryId}/authors`, authorsResponseSchema, signal),
    select: (data) => [...data.authors].sort((a, b) => a.name.localeCompare(b.name)),
  });
}

export function useAuthor(libraryId: string, authorId: string) {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.author(connection.id, libraryId, authorId),
    queryFn: ({ signal }) =>
      client.get(
        `/api/authors/${authorId}?include=items,series&library=${libraryId}`,
        authorDetailSchema,
        signal,
      ),
  });
}

export function useRecentEpisodes(libraryId: string, page: number) {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.recentEpisodes(connection.id, libraryId, page),
    queryFn: ({ signal }) =>
      client.get(
        `/api/libraries/${libraryId}/recent-episodes?limit=${PAGE_SIZE}&page=${page - 1}`,
        recentEpisodesSchema,
        signal,
      ),
    placeholderData: keepPreviousData,
  });
}

export function useCollections(libraryId: string) {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.collections(connection.id, libraryId),
    queryFn: ({ signal }) =>
      client.get(`/api/libraries/${libraryId}/collections`, pagedCollectionsSchema, signal),
    select: (data) => data.results,
  });
}

export function useCollection(collectionId: string) {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.collection(connection.id, collectionId),
    queryFn: ({ signal }) => client.get(`/api/collections/${collectionId}`, collectionSchema, signal),
  });
}

export function usePlaylists(libraryId: string) {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.playlists(connection.id, libraryId),
    queryFn: ({ signal }) =>
      client.get(`/api/libraries/${libraryId}/playlists`, pagedPlaylistsSchema, signal),
    select: (data) => data.results,
  });
}

export function usePlaylist(playlistId: string) {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.playlist(connection.id, playlistId),
    queryFn: ({ signal }) => client.get(`/api/playlists/${playlistId}`, playlistSchema, signal),
  });
}

/** Reads a feed through the server (administrators only); the browser never contacts the feed itself. */
export function usePodcastFeed(feedUrl: string | null) {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.podcastFeed(connection.id, feedUrl ?? ""),
    queryFn: ({ signal }) =>
      client.send("POST", "/api/podcasts/feed", { rssFeed: feedUrl }, podcastFeedSchema, signal),
    enabled: !!feedUrl,
    retry: false,
  });
}

export function usePodcastSearch(term: string | null) {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.podcastSearch(connection.id, term ?? ""),
    queryFn: ({ signal }) =>
      client.get(
        `/api/search/podcast?${new URLSearchParams({ term: term ?? "" })}`,
        podcastSearchResultsSchema,
        signal,
      ),
    enabled: !!term,
    retry: false,
  });
}
