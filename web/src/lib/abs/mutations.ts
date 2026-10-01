import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useAbs } from "@/lib/session/store";
import { keys } from "./queries";
import { bookmarkSchema } from "./schemas";

export function useCreateBookmark() {
  const { client, connection } = useAbs();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ itemId, time, title }: { itemId: string; time: number; title: string }) =>
      client.send(
        "POST",
        `/api/me/item/${itemId}/bookmark`,
        { time: Math.floor(time), title },
        bookmarkSchema,
      ),
    onSettled: () => queryClient.invalidateQueries({ queryKey: keys.me(connection.id) }),
  });
}

export function useUpdateBookmark() {
  const { client, connection } = useAbs();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ itemId, time, title }: { itemId: string; time: number; title: string }) =>
      client.send("PATCH", `/api/me/item/${itemId}/bookmark`, { time, title }, bookmarkSchema),
    onSettled: () => queryClient.invalidateQueries({ queryKey: keys.me(connection.id) }),
  });
}

export function useDeleteBookmark() {
  const { client, connection } = useAbs();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ itemId, time }: { itemId: string; time: number }) =>
      client.command("DELETE", `/api/me/item/${itemId}/bookmark/${time}`),
    onSettled: () => queryClient.invalidateQueries({ queryKey: keys.me(connection.id) }),
  });
}

export function useSetFinished() {
  const { client, connection } = useAbs();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({
      itemId,
      episodeId,
      finished,
    }: {
      itemId: string;
      episodeId?: string | null;
      finished: boolean;
    }) =>
      client.command("PATCH", `/api/me/progress/${itemId}${episodeId ? `/${episodeId}` : ""}`, {
        isFinished: finished,
      }),
    onSettled: () => queryClient.invalidateQueries({ queryKey: keys.me(connection.id) }),
  });
}

export function useDiscardProgress() {
  const { client, connection } = useAbs();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (progressId: string) => client.command("DELETE", `/api/me/progress/${progressId}`),
    onSettled: () => queryClient.invalidateQueries({ queryKey: keys.me(connection.id) }),
  });
}
