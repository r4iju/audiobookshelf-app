import type { AbsClient } from "@/lib/abs/client";
import { usePlayerStore } from "@/lib/player/store";
import { deliveriesSettled } from "./sync";

export interface DiscardTarget {
  progressId: string;
  itemId: string;
  episodeId: string | null;
}

/** Discards a book's or episode's progress on the server and on this device, for the client's own account. */
export async function discardProgress(client: AbsClient, { progressId, itemId, episodeId }: DiscardTarget) {
  // Nothing this device still holds may report the old position after the server forgets it: the player and the
  // unsent listening let go first, then any delivery already sent is answered before the server is asked.
  await usePlayerStore.getState().startOver({ connectionId: client.connection.id, itemId, episodeId });
  await deliveriesSettled();
  await client.command("DELETE", `/api/me/progress/${progressId}`);
}
