import { useQuery } from "@tanstack/react-query";
import { useAbs } from "@/lib/session/store";
import { librariesResponseSchema, personalizedSchema, userSchema } from "./schemas";

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
