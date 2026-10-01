import type { AbsClient } from "@/lib/abs/client";
import { usePlayerStore } from "@/lib/player/store";
import { deliveriesSettled, outboxFor } from "./sync";

export interface DiscardTarget {
  progressId: string;
  itemId: string;
  episodeId: string | null;
}

/** Discards a book's or episode's progress on the server and on this device, for the client's own account. */
export async function discardProgress(client: AbsClient, { progressId, itemId, episodeId }: DiscardTarget) {
  // Nothing may report the old position after the server forgets it: the player and the unsent listening let go first,
  // then deliveries already sent are answered before the server is asked. Listening recorded meanwhile waits until
  // the delete is done, so it is not deleted with the old position.
  const release = outboxFor(client.connection.id).hold(itemId, episodeId);
  try {
    await usePlayerStore.getState().startOver({ connectionId: client.connection.id, itemId, episodeId });
    await deliveriesSettled(client.connection.id);
    await client.command("DELETE", `/api/me/progress/${progressId}`);
  } finally {
    release();
  }
}
