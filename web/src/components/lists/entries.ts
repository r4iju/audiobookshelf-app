import { playerMediaFor } from "@/components/item/play-media";
import type { AbsClient } from "@/lib/abs/client";
import type { LibraryItem, PlaylistItem } from "@/lib/abs/schemas";
import type { DetailEntry } from "./list-detail";

const bookPlayable = (item: LibraryItem) =>
  !item.isMissing && !item.isInvalid && (item.media.tracks?.length ?? 0) > 0;

export function bookEntry(client: AbsClient, item: LibraryItem): DetailEntry {
  return {
    key: item.id,
    libraryItemId: item.id,
    episodeId: null,
    playable: bookPlayable(item),
    href: `/item/${item.id}`,
    media: playerMediaFor(client, item),
  };
}

/** Entries whose item the server could not resolve (removed since) are left out. */
export function playlistEntries(client: AbsClient, items: PlaylistItem[]): DetailEntry[] {
  return items.flatMap((entry) => {
    const item = entry.libraryItem;
    if (!item) return [];
    const episode = entry.episode;
    if (!episode) return [bookEntry(client, item)];
    return [
      {
        key: `${item.id}/${episode.id}`,
        libraryItemId: item.id,
        episodeId: episode.id,
        playable: !item.isMissing && !!episode.audioFile,
        href: `/item/${item.id}`,
        media: playerMediaFor(client, item, episode),
      },
    ];
  });
}
