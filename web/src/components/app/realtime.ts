"use client";

import { type QueryClient, useQueryClient } from "@tanstack/react-query";
import { useEffect } from "react";
import { io } from "socket.io-client";
import { z } from "zod";
import type { AbsClient } from "@/lib/abs/client";
import { keys } from "@/lib/abs/queries";
import { mediaProgressSchema, type User, userSchema } from "@/lib/abs/schemas";
import { useAbs } from "@/lib/session/store";

const progressEventSchema = z.looseObject({ id: z.string(), data: mediaProgressSchema });

function applyProgress(queryClient: QueryClient, connectionId: string, payload: unknown) {
  const parsed = progressEventSchema.safeParse(payload);
  if (!parsed.success) return;
  const progress = parsed.data.data;
  queryClient.setQueryData<User>(keys.me(connectionId), (user) =>
    user
      ? {
          ...user,
          mediaProgress: [...user.mediaProgress.filter((entry) => entry.id !== progress.id), progress],
        }
      : user,
  );
}

/** The server's socket.io endpoint sits under the same base path as its HTTP API. */
export function socketTarget(client: AbsClient) {
  const url = new URL(client.connection.serverUrl);
  return { origin: url.origin, path: `${url.pathname.replace(/\/+$/, "")}/socket.io` };
}

export function useRealtime() {
  const { client, connection } = useAbs();
  const queryClient = useQueryClient();

  // External system: the server's socket.io channel pushes changes made on other devices and by the server.
  useEffect(() => {
    const { origin, path } = socketTarget(client);
    const socket = io(origin, { path, transports: ["websocket"], reconnectionDelayMax: 30_000 });
    const authenticate = () => socket.emit("auth", client.bearer);
    socket.on("connect", authenticate);
    // An expired access token is renewed by any API call; then the socket is authenticated again.
    socket.on("auth_failed", () => {
      client
        .get("/api/me", userSchema)
        .then(authenticate)
        .catch(() => {});
    });
    socket.on("user_item_progress_updated", (payload: unknown) =>
      applyProgress(queryClient, connection.id, payload),
    );
    socket.on("user_updated", (payload: unknown) => {
      const parsed = userSchema.safeParse(payload);
      if (parsed.success) queryClient.setQueryData(keys.me(connection.id), parsed.data);
    });
    const refreshLibrary = () => {
      void queryClient.invalidateQueries({ queryKey: [connection.id, "library"] });
      void queryClient.invalidateQueries({ queryKey: [connection.id, "item"] });
    };
    for (const event of [
      "item_added",
      "item_updated",
      "item_removed",
      "items_added",
      "items_updated",
      "episode_added",
    ]) {
      socket.on(event, refreshLibrary);
    }
    for (const event of [
      "collection_added",
      "collection_updated",
      "collection_removed",
      "playlist_added",
      "playlist_updated",
      "playlist_removed",
    ]) {
      socket.on(event, () => void queryClient.invalidateQueries({ queryKey: [connection.id, "lists"] }));
    }
    return () => {
      socket.disconnect();
    };
  }, [client, connection.id, queryClient]);
}
