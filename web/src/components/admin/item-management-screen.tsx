"use client";
import { useQueryClient } from "@tanstack/react-query";
import { type ComponentProps, useActionState } from "react";
import { z } from "zod";
import { Button, ButtonLink } from "@/components/ui/button";
import { TextField, Toggle } from "@/components/ui/field";
import { QueryState } from "@/components/ui/query-state";
import { Section } from "@/components/ui/section";
import { Alert } from "@/components/ui/status";
import { metadataEditInput, metadataMatchesSchema } from "@/lib/abs/item-management";
import { useItem } from "@/lib/abs/queries";
import { type LibraryItem, libraryItemSchema } from "@/lib/abs/schemas";
import { useAbs } from "@/lib/session/store";

type Result = { kind: "idle" } | { kind: "error"; message: string } | { kind: "saved"; message: string };
function Notice({ result }: { result: Result }) {
  return result.kind === "error" ? (
    <Alert>{result.message}</Alert>
  ) : result.kind === "saved" ? (
    <p role="status">{result.message}</p>
  ) : null;
}
const names = (value: FormDataEntryValue | null) =>
  z
    .string()
    .parse(value)
    .split("\n")
    .map((v) => v.trim())
    .filter(Boolean);
export function ItemManagementScreen({ itemId }: { itemId: string }) {
  const item = useItem(itemId);
  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-6">
      <h1 className="text-2xl font-bold">Manage item</h1>
      <QueryState query={item}>
        {(item) => (
          <>
            <MetadataForm item={item} />
            <CoverForm item={item} />
            <MetadataMatch item={item} />
          </>
        )}
      </QueryState>
      <RemovalForm itemId={itemId} />
    </div>
  );
}
function LinesField({ label, ...props }: ComponentProps<"textarea"> & { label: string }) {
  return (
    <label className="flex flex-col gap-2 text-sm font-medium">
      {label}
      <textarea
        {...props}
        className="min-h-24 rounded border border-line bg-surface p-3 text-base focus-ring"
      />
    </label>
  );
}
function MetadataForm({ item }: { item: LibraryItem }) {
  const { client, connection } = useAbs(),
    queries = useQueryClient();
  const [result, submit, pending] = useActionState<Result, FormData>(
    async (_prior, form) => {
      try {
        const input = metadataEditInput.parse({
          metadata: {
            title: form.get("title"),
            subtitle: form.get("subtitle"),
            description: form.get("description"),
            authors: names(form.get("authors")).map((name) => ({ name })),
            series: form
              .getAll("seriesName")
              .map((value, index) => ({
                name: z.string().parse(value).trim(),
                sequence: z.string().parse(form.getAll("seriesSequence")[index]).trim() || null,
              }))
              .filter((ref) => ref.name),
            narrators: names(form.get("narrators")),
            genres: names(form.get("genres")),
            publisher: form.get("publisher"),
            publishedYear: form.get("publishedYear"),
            language: form.get("language"),
            explicit: form.get("explicit") === "on",
          },
          tags: names(form.get("tags")),
        });
        await client.send(
          "PATCH",
          `/api/items/${encodeURIComponent(item.id)}/media`,
          input,
          libraryItemSchema,
        );
        await queries.invalidateQueries({ queryKey: [connection.id] });
        return { kind: "saved", message: "Metadata saved." };
      } catch (error) {
        return {
          kind: "error",
          message: error instanceof Error ? error.message : "Metadata could not be saved",
        };
      }
    },
    { kind: "idle" },
  );
  const m = item.media.metadata;
  return (
    <Section title="Details">
      <form action={submit} className="space-y-4">
        <TextField name="title" label="Title" required defaultValue={m.title} />
        <TextField name="subtitle" label="Subtitle" defaultValue={m.subtitle ?? ""} />
        <LinesField
          name="authors"
          label="Authors, one per line"
          defaultValue={m.authors?.map((a) => a.name).join("\n") ?? ""}
        />
        <fieldset className="space-y-3">
          <legend className="text-sm font-medium">Series</legend>
          <p className="text-sm text-muted">
            Clear a name to remove its series. Use the blank row to add another.
          </p>
          {[...(m.series ?? []), { id: "new", name: "", sequence: "" }].map((ref) => (
            <div key={ref.id} className="grid grid-cols-2 gap-3">
              <TextField name="seriesName" label="Series name" defaultValue={ref.name} />
              <TextField name="seriesSequence" label="Sequence" defaultValue={ref.sequence ?? ""} />
            </div>
          ))}
        </fieldset>
        <label className="flex flex-col gap-2">
          Description
          <textarea
            name="description"
            className="min-h-32 rounded border border-line bg-surface p-3 focus-ring"
            defaultValue={m.description ?? ""}
          />
        </label>
        <LinesField
          name="narrators"
          label="Narrators, one per line"
          defaultValue={m.narrators?.join("\n") ?? ""}
        />
        <LinesField name="genres" label="Genres, one per line" defaultValue={m.genres.join("\n")} />
        <LinesField name="tags" label="Tags, one per line" defaultValue={item.media.tags.join("\n")} />
        <TextField name="publisher" label="Publisher" defaultValue={m.publisher ?? ""} />
        <TextField name="publishedYear" label="Published year" defaultValue={m.publishedYear ?? ""} />
        <TextField name="language" label="Language" defaultValue={m.language ?? ""} />
        <Toggle name="explicit" label="Explicit content" defaultChecked={Boolean(m.explicit)} />
        <Notice result={result} />
        <Button type="submit" disabled={pending}>
          Save metadata
        </Button>
      </form>
    </Section>
  );
}
function CoverForm({ item }: { item: LibraryItem }) {
  const { client, connection } = useAbs(),
    queries = useQueryClient();
  const [result, submit, pending] = useActionState<Result, FormData>(
    async (_prior, form) => {
      try {
        const file = z.instanceof(File).parse(form.get("cover"));
        if (!file.size || file.size > 5 * 1024 * 1024) throw new Error("Choose a PNG or JPEG under 5 MiB");
        await client.upload(
          `/api/items/${encodeURIComponent(item.id)}/cover`,
          file,
          z.object({ success: z.literal(true) }),
        );
        await queries.invalidateQueries({ queryKey: [connection.id] });
        return { kind: "saved", message: "Cover saved." };
      } catch (error) {
        return {
          kind: "error",
          message: error instanceof Error ? error.message : "Cover could not be saved",
        };
      }
    },
    { kind: "idle" },
  );
  return (
    <Section title="Cover">
      <form action={submit} className="space-y-3">
        <TextField
          type="file"
          name="cover"
          label="PNG or JPEG cover"
          accept="image/png,image/jpeg"
          required
        />
        <p className="text-sm text-muted">
          Up to 5 MiB and 20 million pixels. Original media remains unchanged.
        </p>
        <Notice result={result} />
        <Button type="submit" disabled={pending}>
          Save cover
        </Button>
      </form>
    </Section>
  );
}
function RemovalForm({ itemId }: { itemId: string }) {
  const { client, connection } = useAbs(),
    queries = useQueryClient();
  const [result, submit, pending] = useActionState<Result, FormData>(
    async (_prior, form) => {
      try {
        if (form.get("intent") === "restore") {
          await client.send(
            "POST",
            `/api/items/${encodeURIComponent(itemId)}/restore`,
            {},
            libraryItemSchema,
          );
        } else {
          await client.send(
            "DELETE",
            `/api/items/${encodeURIComponent(itemId)}`,
            z.object({ confirmation: z.literal("REMOVE") }).parse({ confirmation: form.get("confirmation") }),
            z.object({
              success: z.literal(true),
              mediaDeleted: z.literal(false),
              historyRetained: z.literal(true),
            }),
          );
        }
        await queries.invalidateQueries({ queryKey: [connection.id] });
        return {
          kind: "saved",
          message:
            form.get("intent") === "restore"
              ? "Item restored."
              : "Item removed from the catalog. Media and history retained.",
        };
      } catch (error) {
        return { kind: "error", message: error instanceof Error ? error.message : "Removal failed" };
      }
    },
    { kind: "idle" },
  );
  return (
    <Section title="Remove from catalog">
      <form action={submit} className="space-y-3">
        <p>
          Removal stops playback, closes public feeds and pauses podcast subscriptions. Media files, progress,
          listening history and list references remain. Scans keep this item hidden until you restore it.
          Restoring does not reopen feeds or subscriptions.
        </p>
        <TextField name="confirmation" label="Enter REMOVE to confirm" />
        <Notice result={result} />
        <div className="flex flex-wrap gap-3">
          <Button type="submit" name="intent" value="remove" disabled={pending}>
            Remove item
          </Button>
          <Button type="submit" name="intent" value="restore" variant="secondary" disabled={pending}>
            Restore retained item
          </Button>
          <ButtonLink href={`/item/${encodeURIComponent(itemId)}`}>View item</ButtonLink>
        </div>
      </form>
    </Section>
  );
}
function MetadataMatch({ item }: { item: LibraryItem }) {
  const { client } = useAbs();
  type MatchResult =
    | { kind: "idle" }
    | { kind: "error"; message: string }
    | { kind: "matches"; results: z.infer<typeof metadataMatchesSchema>["results"] };
  const [result, submit, pending] = useActionState<MatchResult, FormData>(
    async (_prior, form) => {
      try {
        return {
          kind: "matches",
          results: (
            await client.get(
              `/api/search/books?query=${encodeURIComponent(z.string().parse(form.get("query")))}`,
              metadataMatchesSchema,
            )
          ).results,
        };
      } catch (error) {
        return { kind: "error", message: error instanceof Error ? error.message : "Metadata search failed" };
      }
    },
    { kind: "idle" },
  );
  return (
    <Section title="Optional metadata match">
      <p className="text-sm text-muted">
        Search uses the provider configured by the owner. Applying a match replaces title, authors and
        publication year; other fields remain.
      </p>
      <form action={submit} className="space-y-3">
        <TextField name="query" label="Book search" defaultValue={item.media.metadata.title} required />
        <Button type="submit" disabled={pending}>
          Search metadata
        </Button>
      </form>
      {result.kind === "error" ? (
        <Alert>{result.message}</Alert>
      ) : result.kind === "matches" ? (
        result.results.length ? (
          <ul className="space-y-3">
            {result.results.map((match) => (
              <li key={match.key}>
                <ApplyMatch itemId={item.id} match={match} />
              </li>
            ))}
          </ul>
        ) : (
          <p>No metadata matches found.</p>
        )
      ) : null}
    </Section>
  );
}
function ApplyMatch({
  itemId,
  match,
}: {
  itemId: string;
  match: z.infer<typeof metadataMatchesSchema>["results"][number];
}) {
  const { client, connection } = useAbs(),
    queries = useQueryClient();
  const [result, submit, pending] = useActionState<Result, FormData>(
    async () => {
      try {
        await client.send(
          "PATCH",
          `/api/items/${encodeURIComponent(itemId)}/media`,
          metadataEditInput.parse({
            metadata: {
              title: match.title,
              authors: match.authors.map((name) => ({ name })),
              publishedYear: match.publishedYear,
            },
          }),
          libraryItemSchema,
        );
        await queries.invalidateQueries({ queryKey: [connection.id] });
        return { kind: "saved", message: "Match applied." };
      } catch (error) {
        return { kind: "error", message: error instanceof Error ? error.message : "Match failed" };
      }
    },
    { kind: "idle" },
  );
  return (
    <form action={submit} className="space-y-2 border-t border-line py-3">
      <p>
        {match.title} · {match.authors.join(", ")} · {match.publishedYear}
      </p>
      <Notice result={result} />
      <Button type="submit" disabled={pending}>
        Apply this match
      </Button>
    </form>
  );
}
