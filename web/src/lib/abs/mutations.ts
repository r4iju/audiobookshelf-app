import { useMutation, useQueryClient } from "@tanstack/react-query";
import { z } from "zod";
import { type DiscardTarget, discardProgress } from "@/lib/progress/discard";
import {
  changeProgress,
  discardAnyway,
  type IssuedChange,
  issueChange,
  keepProgress,
  sendChange,
} from "@/lib/progress/sync";
import { useAbs } from "@/lib/session/store";
import type { AbsClient } from "./client";
import { feedSchema } from "./feeds";
import { keys } from "./queries";
import {
  bookmarkSchema,
  collectionSchema,
  libraryItemSchema,
  type PodcastFeed,
  playlistSchema,
} from "./schemas";

export function useCreateBookmark() {
  const { client, connection } = useAbs();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ itemId, time, title }: { itemId: string; time: number; title: string }) =>
      client.send(
        "POST",
        `/api/me/item/${itemId}/bookmark`,
        { time: Math.floor(time), title },
        bookmarkSchema,
      ),
    onSettled: () => queryClient.invalidateQueries({ queryKey: keys.me(connection.id) }),
  });
}

export function useUpdateBookmark() {
  const { client, connection } = useAbs();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ itemId, time, title }: { itemId: string; time: number; title: string }) =>
      client.send("PATCH", `/api/me/item/${itemId}/bookmark`, { time, title }, bookmarkSchema),
    onSettled: () => queryClient.invalidateQueries({ queryKey: keys.me(connection.id) }),
  });
}

export function useDeleteBookmark() {
  const { client, connection } = useAbs();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ itemId, time }: { itemId: string; time: number }) =>
      client.command("DELETE", `/api/me/item/${itemId}/bookmark/${time}`),
    onSettled: () => queryClient.invalidateQueries({ queryKey: keys.me(connection.id) }),
  });
}

export function useSetFinished() {
  const { client, connection } = useAbs();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({
      itemId,
      episodeId,
      finished,
    }: {
      itemId: string;
      episodeId?: string | null;
      finished: boolean;
    }) =>
      changeProgress(
        client,
        { libraryItemId: itemId, episodeId: episodeId ?? null },
        { isFinished: finished },
      ),
    onSettled: () => queryClient.invalidateQueries({ queryKey: keys.me(connection.id) }),
  });
}

export function useDiscardProgress() {
  const { client, connection } = useAbs();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (target: DiscardTarget) => discardProgress(client, target),
    onSettled: () => queryClient.invalidateQueries({ queryKey: keys.me(connection.id) }),
  });
}

/** Settles a discard left unconfirmed (see discardProgress) the way the user chose. */
function useDiscardChoice(choose: typeof keepProgress) {
  const { client, connection } = useAbs();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ itemId, episodeId }: { itemId: string; episodeId: string | null }) =>
      choose(client, itemId, episodeId),
    onSettled: () => queryClient.invalidateQueries({ queryKey: keys.me(connection.id) }),
  });
}

/** Gives up the discard: nothing is deleted, unless its delete was issued meanwhile. */
export const useKeepProgress = () => useDiscardChoice(keepProgress);

/** Deletes anyway, accepting that the unconfirmed listening may bring the old place back. */
export const useDiscardAnyway = () => useDiscardChoice(discardAnyway);

export interface PlaylistEntry {
  libraryItemId: string;
  episodeId: string | null;
}

const toServerEntry = ({ libraryItemId, episodeId }: PlaylistEntry) =>
  episodeId ? { libraryItemId, episodeId } : { libraryItemId };

function useListMutation<Variables, Result>(
  run: (client: AbsClient, variables: Variables) => Promise<Result>,
) {
  const { client, connection } = useAbs();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (variables: Variables) => run(client, variables),
    onSettled: () => queryClient.invalidateQueries({ queryKey: keys.lists(connection.id) }),
  });
}

export function useCreatePlaylist() {
  return useListMutation(
    (client, { libraryId, name, entry }: { libraryId: string; name: string; entry: PlaylistEntry }) =>
      client.send(
        "POST",
        "/api/playlists",
        { libraryId, name, items: [toServerEntry(entry)] },
        playlistSchema,
      ),
  );
}

export function useAddToPlaylist() {
  return useListMutation((client, { playlistId, entry }: { playlistId: string; entry: PlaylistEntry }) =>
    client.send(
      "POST",
      `/api/playlists/${playlistId}/batch/add`,
      { items: [toServerEntry(entry)] },
      playlistSchema,
    ),
  );
}

/** The server deletes a playlist when its last entry is removed; the returned playlist then has no items. */
export function useRemoveFromPlaylist() {
  return useListMutation((client, { playlistId, entry }: { playlistId: string; entry: PlaylistEntry }) =>
    client.send(
      "DELETE",
      `/api/playlists/${playlistId}/item/${entry.libraryItemId}${entry.episodeId ? `/${entry.episodeId}` : ""}`,
      undefined,
      playlistSchema,
    ),
  );
}

export function useDeletePlaylist() {
  return useListMutation((client, playlistId: string) =>
    client.command("DELETE", `/api/playlists/${playlistId}`),
  );
}

export function useCreateCollection() {
  return useListMutation(
    (client, { libraryId, name, itemId }: { libraryId: string; name: string; itemId: string }) =>
      client.send("POST", "/api/collections", { libraryId, name, books: [itemId] }, collectionSchema),
  );
}

export function useAddToCollection() {
  return useListMutation((client, { collectionId, itemId }: { collectionId: string; itemId: string }) =>
    client.send("POST", `/api/collections/${collectionId}/book`, { id: itemId }, collectionSchema),
  );
}

export function useRemoveFromCollection() {
  return useListMutation((client, { collectionId, itemId }: { collectionId: string; itemId: string }) =>
    client.send("DELETE", `/api/collections/${collectionId}/book/${itemId}`, undefined, collectionSchema),
  );
}

export function useDeleteCollection() {
  return useListMutation((client, collectionId: string) =>
    client.command("DELETE", `/api/collections/${collectionId}`),
  );
}

export interface NewPodcast {
  libraryId: string;
  folderId: string;
  path: string;
  autoDownloadEpisodes: boolean;
  metadata: {
    title: string;
    author: string;
    description: string;
    feedUrl: string;
    imageUrl: string;
    genres: string[];
    language: string;
    itunesPageUrl?: string;
    itunesId?: string;
    itunesArtistId?: string;
    releaseDate?: string;
  };
}

export function useCreatePodcast() {
  const { client, connection } = useAbs();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ metadata, autoDownloadEpisodes, ...placement }: NewPodcast) =>
      client.send(
        "POST",
        "/api/podcasts",
        { ...placement, media: { metadata, autoDownloadEpisodes } },
        libraryItemSchema,
      ),
    onSettled: (_data, _error, podcast) =>
      queryClient.invalidateQueries({ queryKey: keys.library(connection.id, podcast.libraryId) }),
  });
}

export function useDownloadEpisodes() {
  const { client, connection } = useAbs();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ itemId, episodes }: { itemId: string; episodes: PodcastFeed["podcast"]["episodes"] }) =>
      client.command("POST", `/api/podcasts/${itemId}/download-episodes`, episodes),
    onSettled: (_data, _error, { itemId }) =>
      queryClient.invalidateQueries({ queryKey: keys.item(connection.id, itemId) }),
  });
}

export function useClearDownloadQueue() {
  const { client, connection } = useAbs();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (itemId: string) => client.command("GET", `/api/podcasts/${itemId}/clear-queue`),
    onSettled: (_data, _error, itemId) =>
      queryClient.invalidateQueries({ queryKey: keys.item(connection.id, itemId) }),
  });
}

/**
 * Deletes the episode's audio file too; the server also drops it from playlists and removes its progress.
 * `onRemoved` runs even if the episode's page has already gone, as it does when the server's update arrives first.
 */
export function useRemoveEpisode(onRemoved: (itemId: string) => void) {
  const { client, connection } = useAbs();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ itemId, episodeId }: { itemId: string; episodeId: string }) =>
      client.command("DELETE", `/api/podcasts/${itemId}/episode/${episodeId}?hard=1`),
    onSuccess: (_data, { itemId }) => onRemoved(itemId),
    onSettled: (_data, _error, { itemId }) =>
      Promise.all([
        queryClient.invalidateQueries({ queryKey: keys.item(connection.id, itemId) }),
        queryClient.invalidateQueries({ queryKey: keys.me(connection.id) }),
        queryClient.invalidateQueries({ queryKey: keys.lists(connection.id) }),
      ]),
  });
}

export interface EbookPlace {
  ebookLocation: string;
  ebookProgress?: number;
}

export function useSaveEbookPlace(itemId: string) {
  const { client, connection } = useAbs();
  const queryClient = useQueryClient();
  const mutation = useMutation({
    ...ebookPlaceSaves(client, itemId),
    onSettled: () => queryClient.invalidateQueries({ queryKey: keys.itemProgress(connection.id, itemId) }),
  });
  return {
    error: mutation.error,
    save: (place: EbookPlace) =>
      mutation.mutate(issueChange(client, { libraryItemId: itemId, episodeId: null }, place)),
  };
}

/** How a book's reading places are sent: one at a time, so a quick run of page turns lands on the server in order. */
export const ebookPlaceSaves = (client: AbsClient, itemId: string) => ({
  scope: { id: `ebook-place-${itemId}` },
  mutationFn: (issued: IssuedChange) => sendChange(client, issued),
});

function useItemMutation<Variables, Result>(
  itemId: string,
  run: (client: AbsClient, variables: Variables) => Promise<Result>,
) {
  const { client, connection } = useAbs();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (variables: Variables) => run(client, variables),
    onSettled: () => queryClient.invalidateQueries({ queryKey: keys.item(connection.id, itemId) }),
  });
}

export function useOpenFeed(itemId: string) {
  return useItemMutation(
    itemId,
    async (
      client,
      metadata: { slug: string; preventIndexing: boolean; ownerName: string; ownerEmail: string },
    ) => {
      const { slug, ...metadataDetails } = metadata;
      const { feed } = await client.send(
        "POST",
        `/api/feeds/item/${itemId}/open`,
        { serverAddress: client.connection.serverUrl, slug, metadataDetails },
        z.object({ feed: feedSchema }),
      );
      return feed;
    },
  );
}

export function useCloseFeed(itemId: string) {
  return useItemMutation(itemId, (client, feedId: string) =>
    client.command("POST", `/api/feeds/${feedId}/close`),
  );
}

export function useSendEbook() {
  const { client } = useAbs();
  return useMutation({
    mutationFn: ({ itemId, deviceName }: { itemId: string; deviceName: string }) =>
      client.command("POST", "/api/emails/send-ebook-to-device", { libraryItemId: itemId, deviceName }),
  });
}
