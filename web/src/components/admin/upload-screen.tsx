"use client";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useActionState } from "react";
import { z } from "zod";
import { Button, ButtonLink } from "@/components/ui/button";
import { TextField, Toggle } from "@/components/ui/field";
import { Section } from "@/components/ui/section";
import { SelectField } from "@/components/ui/select";
import { Alert, EmptyState, Spinner } from "@/components/ui/status";
import { providerSettingsInput } from "@/lib/abs/item-management";
import { librariesResponseSchema, libraryItemSchema } from "@/lib/abs/schemas";
import { useAbs } from "@/lib/session/store";

type Result = { kind: "idle" } | { kind: "error"; message: string } | { kind: "uploaded"; itemId: string };
export function UploadScreen() {
  const { client, connection } = useAbs(),
    queries = useQueryClient();
  const libraries = useQuery({
    queryKey: [connection.id, "libraries"],
    queryFn: ({ signal }) => client.get("/api/libraries", librariesResponseSchema, signal),
  });
  const [result, submit, pending] = useActionState<Result, FormData>(
    async (_prior, form) => {
      try {
        const id = z.string().min(1).parse(form.get("libraryId")),
          file = z.instanceof(File).parse(form.get("file"));
        if (!file.size || file.size > 1024 * 1024 * 1024)
          throw new Error("Choose a nonempty media file up to 1 GiB");
        const uploaded = await client.upload(
          `/api/libraries/${encodeURIComponent(id)}/upload?filename=${encodeURIComponent(file.name)}`,
          file,
          z.object({ item: libraryItemSchema }),
        );
        await queries.invalidateQueries({ queryKey: [connection.id] });
        return { kind: "uploaded", itemId: uploaded.item.id };
      } catch (error) {
        return { kind: "error", message: error instanceof Error ? error.message : "Upload failed" };
      }
    },
    { kind: "idle" },
  );
  const books = libraries.data?.libraries.filter((l) => l.mediaType === "book") ?? [];
  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-6">
      <h1 className="text-2xl font-bold">Upload and metadata</h1>
      <Section title="Upload a book">
        <p className="text-sm text-muted">
          Choose a book library containing the managed /data/media folder. Uploads create new items in
          persistent managed storage and leave mounted source media unchanged. Audio or ebook, up to 1 GiB;
          two transfers per server.
        </p>
        {libraries.isPending ? (
          <Spinner label="Loading libraries" />
        ) : libraries.isError ? (
          <Alert>{libraries.error.message}</Alert>
        ) : books.length ? (
          <form action={submit} className="space-y-4">
            <SelectField
              name="libraryId"
              label="Book library"
              options={books.map((l) => ({ value: l.id, label: l.name }))}
            />
            <TextField
              name="file"
              type="file"
              label="Audio or ebook file"
              accept=".mp3,.m4b,.m4a,.flac,.ogg,.opus,.wav,.aac,.epub,.pdf,.mobi,.azw3,.cbz,.cbr"
              required
            />
            {result.kind === "error" ? (
              <Alert>{result.message}</Alert>
            ) : result.kind === "uploaded" ? (
              <p role="status">
                Upload complete.{" "}
                <ButtonLink href={`/admin/items/${encodeURIComponent(result.itemId)}`}>
                  Edit uploaded item
                </ButtonLink>
              </p>
            ) : null}
            <Button type="submit" disabled={pending}>
              {pending ? "Uploading…" : "Upload book"}
            </Button>
          </form>
        ) : (
          <EmptyState title="Create a book library first" />
        )}
      </Section>
      <ProviderConfiguration />
    </div>
  );
}
function ProviderConfiguration() {
  const { client, connection } = useAbs();
  const provider = useQuery({
    queryKey: [connection.id, "metadata-provider"],
    queryFn: ({ signal }) => client.get("/api/admin/metadata-provider", providerSettingsInput, signal),
  });
  return (
    <Section title="Optional metadata provider">
      {provider.isPending ? (
        <Spinner label="Loading provider settings" />
      ) : provider.isError ? (
        <Alert>{provider.error.message}</Alert>
      ) : (
        <ProviderForm key={JSON.stringify(provider.data)} initial={provider.data} />
      )}
    </Section>
  );
}
function ProviderForm({ initial }: { initial: z.infer<typeof providerSettingsInput> }) {
  const { client, connection } = useAbs(),
    queries = useQueryClient();
  type State = { kind: "idle" } | { kind: "error"; message: string } | { kind: "saved" };
  const [result, submit, pending] = useActionState<State, FormData>(
    async (_prior, form) => {
      try {
        await client.send(
          "PATCH",
          "/api/admin/metadata-provider",
          providerSettingsInput.parse({
            enabled: form.get("enabled") === "on",
            searchUrl: form.get("searchUrl"),
          }),
          providerSettingsInput,
        );
        await queries.invalidateQueries({ queryKey: [connection.id, "metadata-provider"] });
        return { kind: "saved" };
      } catch (error) {
        return {
          kind: "error",
          message: error instanceof Error ? error.message : "Provider settings failed",
        };
      }
    },
    { kind: "idle" },
  );
  return (
    <form action={submit} className="space-y-4">
      <p className="text-sm text-muted">
        Disabled by default. Enabling this provider sends only the book search you submit to the configured
        Open Library-compatible endpoint. Results are reviewed before you apply them.
      </p>
      <Toggle name="enabled" label="Enable metadata search" defaultChecked={initial.enabled} />
      <TextField
        name="searchUrl"
        label="HTTPS search endpoint"
        type="url"
        required
        defaultValue={initial.searchUrl}
      />
      {result.kind === "error" ? (
        <Alert>{result.message}</Alert>
      ) : result.kind === "saved" ? (
        <p role="status">Provider settings saved.</p>
      ) : null}
      <Button type="submit" disabled={pending}>
        Save provider settings
      </Button>
    </form>
  );
}
