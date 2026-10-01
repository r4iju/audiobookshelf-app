import type { MediaProgress } from "./schemas";

export interface ListEntry {
  libraryItemId: string;
  episodeId: string | null;
  playable: boolean;
}

/** Like the server's own clients: playing a list starts its first playable entry that is not finished. */
export function nextToPlay<T extends ListEntry>(entries: T[], progress: MediaProgress[]): T | null {
  const finished = new Set(
    progress
      .filter((entry) => entry.isFinished)
      .map((entry) => `${entry.libraryItemId}/${entry.episodeId ?? ""}`),
  );
  return (
    entries.find(
      (entry) => entry.playable && !finished.has(`${entry.libraryItemId}/${entry.episodeId ?? ""}`),
    ) ?? null
  );
}
