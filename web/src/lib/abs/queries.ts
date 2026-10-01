import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { useAbs } from "@/lib/session/store";
import { type BrowseState, itemsQuery } from "./browse";
import {
  authorDetailSchema,
  authorsResponseSchema,
  librariesResponseSchema,
  libraryItemSchema,
  libraryWithFilterDataSchema,
  pagedItemsSchema,
  pagedSeriesSchema,
  personalizedSchema,
  searchResultsSchema,
  seriesSchema,
  userSchema,
} from "./schemas";

// Every key starts with the connection id so two saved servers or accounts never share cached data.
export const keys = {
  all: (connectionId: string) => [connectionId] as const,
  libraries: (connectionId: string) => [connectionId, "libraries"] as const,
  me: (connectionId: string) => [connectionId, "me"] as const,
  library: (connectionId: string, libraryId: string) => [connectionId, "library", libraryId] as const,
  personalized: (connectionId: string, libraryId: string) =>
    [connectionId, "library", libraryId, "personalized"] as const,
  items: (connectionId: string, libraryId: string, query: string) =>
    [connectionId, "library", libraryId, "items", query] as const,
  item: (connectionId: string, itemId: string) => [connectionId, "item", itemId] as const,
  filterData: (connectionId: string, libraryId: string) =>
    [connectionId, "library", libraryId, "filterdata"] as const,
  search: (connectionId: string, libraryId: string, q: string) =>
    [connectionId, "library", libraryId, "search", q] as const,
  seriesList: (connectionId: string, libraryId: string, page: number) =>
    [connectionId, "library", libraryId, "series", page] as const,
  series: (connectionId: string, libraryId: string, seriesId: string) =>
    [connectionId, "library", libraryId, "series", "one", seriesId] as const,
  authors: (connectionId: string, libraryId: string) =>
    [connectionId, "library", libraryId, "authors"] as const,
  author: (connectionId: string, libraryId: string, authorId: string) =>
    [connectionId, "library", libraryId, "author", authorId] as const,
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

export function useSearch(libraryId: string, q: string) {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.search(connection.id, libraryId, q),
    queryFn: ({ signal }) =>
      client.get(
        `/api/libraries/${libraryId}/search?${new URLSearchParams({ q, limit: "12" })}`,
        searchResultsSchema,
        signal,
      ),
    enabled: q.trim().length > 0,
    placeholderData: keepPreviousData,
  });
}

export function useItem(itemId: string) {
  const { client, connection } = useAbs();
  return useQuery({
    queryKey: keys.item(connection.id, itemId),
    queryFn: ({ signal }) =>
      client.get(`/api/items/${itemId}?expanded=1&include=rssfeed`, libraryItemSchema, signal),
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
