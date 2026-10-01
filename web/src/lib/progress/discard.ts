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
  // then deliveries already sent are answered before the server is asked. Listening recorded meanwhile is held until
  // the delete is confirmed, so it is not deleted with the old position; a delete that fails is finished later.
  const outbox = outboxFor(client.connection.id);
  const hold = outbox.hold(itemId, episodeId, progressId);
  try {
    await usePlayerStore.getState().startOver({ connectionId: client.connection.id, itemId, episodeId });
  } catch (error) {
    // Nothing was sent, so the server is unchanged and there is nothing to finish.
    hold.settle();
    throw error;
  }
  try {
    await deliveriesSettled(client.connection.id);
    await client.command("DELETE", `/api/me/progress/${progressId}`);
  } catch (error) {
    hold.abandon();
    throw error;
  }
  hold.settle();
}
