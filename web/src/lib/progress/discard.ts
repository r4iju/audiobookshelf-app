import type { AbsClient } from "@/lib/abs/client";
import { usePlayerStore } from "@/lib/player/store";
import { type DiscardResult, finishDiscard, outboxFor } from "./sync";

export interface DiscardTarget {
  progressId: string;
  itemId: string;
  episodeId: string | null;
}

/**
 * Discards a book's or episode's progress on the server and on this device, for the client's own account. Unless the
 * server confirms the delete here, the discard stays recorded and the item page shows where it stands.
 */
export async function discardProgress(
  client: AbsClient,
  { progressId, itemId, episodeId }: DiscardTarget,
): Promise<DiscardResult> {
  // Nothing may report the old position after the server forgets it. The hold keeps every tab from sending listening
  // for the book from now on, and this device lets go of the old position, before finishDiscard deletes.
  const connectionId = client.connection.id;
  const outbox = outboxFor(connectionId);
  const hold = outbox.hold(itemId, episodeId, progressId);
  try {
    await usePlayerStore.getState().startOver({ connectionId, itemId, episodeId });
  } catch (error) {
    // Nothing was sent, so the server is unchanged and there is nothing to finish.
    hold.settle();
    throw error;
  }
  let result: DiscardResult;
  try {
    result = await finishDiscard(client, { id: hold.id, libraryItemId: itemId, episodeId, progressId }, {});
  } catch (error) {
    hold.abandon();
    throw error;
  }
  if (result === "done") {
    hold.settle();
  } else {
    // Any tab finishes it once the listening is answered.
    outbox.markUnconfirmed(hold.id, true);
    hold.abandon();
  }
  return result;
}
