import type { AbsClient } from "@/lib/abs/client";
import { authorLine, coverUrl } from "@/lib/abs/media";
import type { LibraryItem, PodcastEpisode } from "@/lib/abs/schemas";
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
    duration: (episode ? (episode.duration ?? episode.audioFile?.duration) : item.media.duration) ?? 0,
    chapters: episode ? episode.chapters : (item.media.chapters ?? []),
  };
}
