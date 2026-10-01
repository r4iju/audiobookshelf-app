import type { AbsClient } from "@/lib/abs/client";
import { episodeDuration } from "@/lib/abs/episodes";
import { authorLine, coverUrl } from "@/lib/abs/media";
import type { EpisodeWithPodcast, LibraryItem, PodcastEpisode } from "@/lib/abs/schemas";
import type { PlayerMedia } from "@/lib/player/store";

export function playerMediaFor(client: AbsClient, item: LibraryItem, episode?: PodcastEpisode): PlayerMedia {
  return {
    itemId: item.id,
    episodeId: episode?.id ?? null,
    libraryId: item.libraryId,
    mediaType: item.mediaType,
    title: episode ? episode.title : item.media.metadata.title,
    author: episode ? item.media.metadata.title : authorLine(item),
    coverUrl: coverUrl(client, item),
    duration: episode ? episodeDuration(episode) : (item.media.duration ?? 0),
    chapters: episode ? episode.chapters : (item.media.chapters ?? []),
  };
}

/** Episodes listed across podcasts arrive with their podcast's metadata rather than the whole library item. */
export function playerMediaForEpisode(
  client: AbsClient,
  episode: EpisodeWithPodcast & { libraryId: string },
): PlayerMedia {
  return {
    itemId: episode.libraryItemId,
    episodeId: episode.id,
    libraryId: episode.libraryId,
    mediaType: "podcast",
    title: episode.title,
    author: episode.podcast?.metadata.title ?? "",
    coverUrl: episodeCoverUrl(client, episode),
    duration: episodeDuration(episode),
    chapters: episode.chapters,
  };
}

export function episodeCoverUrl(client: AbsClient, episode: EpisodeWithPodcast) {
  return episode.podcast?.coverPath ? client.url(`/api/items/${episode.libraryItemId}/cover`) : null;
}
