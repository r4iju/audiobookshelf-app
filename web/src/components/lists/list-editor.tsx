"use client";
import { useQueryClient } from "@tanstack/react-query";
import { useActionState } from "react";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { TextField } from "@/components/ui/field";
import { Alert } from "@/components/ui/status";
import { keys } from "@/lib/abs/queries";
import { type Collection, collectionSchema, type Playlist, playlistSchema } from "@/lib/abs/schemas";
import { useAbs } from "@/lib/session/store";

const editSchema = z.object({ name: z.string().trim().min(1).max(256), description: z.string().max(16384) });
type Result = { kind: "idle" } | { kind: "saved" } | { kind: "error"; message: string };
export function ListEditor({ kind, list }: { kind: "collection" | "playlist"; list: Collection | Playlist }) {
  const { client, connection } = useAbs();
  const queries = useQueryClient();
  const [result, submit, pending] = useActionState<Result, FormData>(
    async (_previous, form) => {
      try {
        const input = editSchema.parse({ name: form.get("name"), description: form.get("description") });
        if (kind === "collection")
          await client.send("PATCH", `/api/collections/${list.id}`, input, collectionSchema);
        else await client.send("PATCH", `/api/playlists/${list.id}`, input, playlistSchema);
        await queries.invalidateQueries({ queryKey: keys.lists(connection.id) });
        return { kind: "saved" };
      } catch (error) {
        return {
          kind: "error",
          message: error instanceof Error ? error.message : "Could not save the list.",
        };
      }
    },
    { kind: "idle" },
  );
  return (
    <details className="rounded-[var(--radius-card)] border border-line p-4">
      <summary className="cursor-pointer font-medium">Edit list</summary>
      <form action={submit} className="mt-4 space-y-4">
        <TextField name="name" label="Name" defaultValue={list.name} required />
        <TextField name="description" label="Description" defaultValue={list.description ?? ""} />
        {result.kind === "error" ? <Alert>{result.message}</Alert> : null}
        {result.kind === "saved" ? <p role="status">List saved.</p> : null}
        <Button type="submit" disabled={pending} variant="primary">
          Save list
        </Button>
      </form>
    </details>
  );
}
