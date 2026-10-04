import type { AbsClient } from "./client";
import type { Library, LibraryItem } from "./schemas";

export type CoverShape = "book" | "square";

/** The server's library setting: 1 is square covers, anything else the standard 1:1.6 book shape. */
export function coverShapeOf(library: Pick<Library, "settings" | "mediaType"> | undefined): CoverShape {
  if (!library || library.mediaType === "podcast") return "square";
  return library.settings?.coverAspectRatio === 1 ? "square" : "book";
}

export function coverUrl(client: AbsClient, item: Pick<LibraryItem, "id" | "updatedAt" | "media">) {
  if (!item.media.coverPath) return null;
  return authenticatedCoverUrl(client, item.id, item.updatedAt ?? 0);
}

export function authenticatedCoverUrl(client: AbsClient, itemId: string, updatedAt = 0) {
  // Image elements cannot attach headers, so use the same current-token contract as playback media.
  const url = new URL(client.url(`/api/items/${itemId}/cover`));
  url.searchParams.set("ts", String(updatedAt));
  url.searchParams.set("token", client.bearer);
  return url.toString();
}

export function authorImageUrl(
  client: AbsClient,
  author: { id: string; imagePath?: string | null; updatedAt?: number | null },
) {
  return author.imagePath ? client.url(`/api/authors/${author.id}/image?ts=${author.updatedAt ?? 0}`) : null;
}

export function authorLine(item: Pick<LibraryItem, "media" | "mediaType">) {
  const metadata = item.media.metadata;
  return (
    (item.mediaType === "podcast" ? metadata.author : metadata.authorName) ??
    metadata.authors?.map((author) => author.name).join(", ") ??
    ""
  );
}

export function formatDuration(seconds: number | null | undefined) {
  if (!seconds || !Number.isFinite(seconds)) return "";
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  if (hours > 0) return `${hours}h ${minutes}m`;
  return minutes > 0 ? `${minutes}m` : `${Math.round(seconds)}s`;
}

/** Clock-style time for players: 1:02:03 or 2:03. */
export function formatClock(seconds: number) {
  const total = Math.max(0, Math.floor(Number.isFinite(seconds) ? seconds : 0));
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const secs = String(total % 60).padStart(2, "0");
  return hours > 0 ? `${hours}:${String(minutes).padStart(2, "0")}:${secs}` : `${minutes}:${secs}`;
}
