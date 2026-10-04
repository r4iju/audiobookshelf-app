"use client";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useActionState } from "react";
import { z } from "zod";
import { Button, ButtonLink } from "@/components/ui/button";
import { TextField } from "@/components/ui/field";
import { Section } from "@/components/ui/section";
import { SelectField } from "@/components/ui/select";
import { Alert, EmptyState, Spinner } from "@/components/ui/status";
import { type Library, librariesResponseSchema, librarySchema } from "@/lib/abs/schemas";
import { useAbs } from "@/lib/session/store";

const formSchema = z.object({
  name: z.string().trim().min(1).max(256),
  folder: z.string().min(1).max(4096),
  mediaType: z.enum(["book", "podcast"]),
});
const reportSchema = z.object({
  id: z.string(),
  status: z.enum(["running", "complete", "failed", "interrupted"]),
  scanned: z.number(),
  errors: z.array(z.object({ path: z.string(), message: z.string() })),
});
type Result = { kind: "idle" } | { kind: "error"; message: string } | { kind: "saved"; message: string };
export function LibrariesScreen() {
  const { connection, client } = useAbs();
  const libraries = useQuery({
    queryKey: [connection.id, "libraries"],
    queryFn: ({ signal }) => client.get("/api/libraries", librariesResponseSchema, signal),
  });
  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-6">
      <h1 className="text-2xl font-bold">Libraries</h1>
      <p className="text-muted">
        Add folders mounted inside the configured media roots. Scans read your media and retain missing items
        and their history.
      </p>
      <Section title="Create library">
        <CreateLibrary />
      </Section>
      {libraries.isPending ? (
        <Spinner label="Loading libraries" />
      ) : libraries.isError ? (
        <Alert>{libraries.error.message}</Alert>
      ) : libraries.data.libraries.length ? (
        libraries.data.libraries.map((library) => <LibraryScan key={library.id} library={library} />)
      ) : (
        <EmptyState title="No libraries yet" />
      )}
    </div>
  );
}
function CreateLibrary() {
  const { connection, client } = useAbs();
  const queries = useQueryClient();
  const [result, submit, pending] = useActionState<Result, FormData>(
    async (_previous, data) => {
      try {
        const fields = formSchema.parse(Object.fromEntries(data));
        await client.send(
          "POST",
          "/api/libraries",
          { name: fields.name, mediaType: fields.mediaType, folders: [{ fullPath: fields.folder }] },
          librarySchema,
        );
        await queries.invalidateQueries({ queryKey: [connection.id, "libraries"] });
        return { kind: "saved", message: "Library created. Scan its mounted folder to find media." };
      } catch (error) {
        return {
          kind: "error",
          message:
            error instanceof z.ZodError
              ? "Check the library fields"
              : error instanceof Error
                ? error.message
                : "Could not create library",
        };
      }
    },
    { kind: "idle" },
  );
  return (
    <form action={submit} className="flex flex-col gap-4">
      <fieldset disabled={pending} className="grid gap-4 sm:grid-cols-2">
        <TextField name="name" label="Library name" required />
        <SelectField
          name="mediaType"
          label="Media type"
          defaultValue="book"
          options={[
            { value: "book", label: "Books" },
            { value: "podcast", label: "Podcasts" },
          ]}
        />
        <TextField
          name="folder"
          label="Mounted folder"
          required
          help="Absolute path inside the container, for example /media/books"
          className="sm:col-span-2"
        />
        <Button type="submit" variant="primary">
          {pending ? "Creating…" : "Create library"}
        </Button>
      </fieldset>
      {result.kind !== "idle" ? (
        <Alert tone={result.kind === "saved" ? "info" : "danger"}>{result.message}</Alert>
      ) : null}
    </form>
  );
}
function LibraryScan({ library }: { library: Library }) {
  const { connection, client } = useAbs();
  const queries = useQueryClient();
  const key = [connection.id, "administration", "scans", library.id];
  const history = useQuery({
    queryKey: key,
    queryFn: ({ signal }) =>
      client.get(`/api/libraries/${library.id}/scans`, z.object({ scans: z.array(reportSchema) }), signal),
  });
  const [result, submit, pending] = useActionState<Result, FormData>(
    async () => {
      try {
        const report = await client.send("POST", `/api/libraries/${library.id}/scan`, {}, reportSchema);
        await queries.invalidateQueries({ queryKey: [connection.id] });
        return {
          kind: report.status === "failed" ? "error" : "saved",
          message: `Scan ${report.status}: ${report.scanned} items, ${report.errors.length} issues`,
        };
      } catch (error) {
        return { kind: "error", message: error instanceof Error ? error.message : "Could not scan library" };
      }
    },
    { kind: "idle" },
  );
  return (
    <Section title={library.name}>
      <p className="text-sm text-muted break-all">
        {library.folders.map((folder) => folder.fullPath).join(", ")}
      </p>
      <div className="flex flex-wrap gap-3">
        <form action={submit}>
          <Button type="submit" disabled={pending} variant="primary">
            {pending ? "Scanning…" : "Scan mounted folders"}
          </Button>
        </form>
        <ButtonLink href={`/library/${library.id}/items`}>Browse library</ButtonLink>
      </div>
      {result.kind !== "idle" ? (
        <Alert tone={result.kind === "saved" ? "info" : "danger"}>{result.message}</Alert>
      ) : null}
      {history.isPending ? (
        <Spinner label="Loading scan history" />
      ) : history.isError ? (
        <Alert>{history.error.message}</Alert>
      ) : history.data.scans.length ? (
        <ul className="flex flex-col gap-3">
          {history.data.scans.map((scan) => (
            <li key={scan.id}>
              <p className="text-sm">
                {scan.status}: {scan.scanned} items
              </p>
              {scan.errors.length ? (
                <ul className="text-sm text-danger">
                  {scan.errors.map((error) => (
                    <li key={`${error.path}:${error.message}`} className="break-all">
                      {error.path}: {error.message}
                    </li>
                  ))}
                </ul>
              ) : null}
            </li>
          ))}
        </ul>
      ) : (
        <p className="text-sm text-muted">No scans yet</p>
      )}
    </Section>
  );
}
