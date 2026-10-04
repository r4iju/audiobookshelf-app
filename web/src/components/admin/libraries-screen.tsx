"use client";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useActionState, useId } from "react";
import { z } from "zod";
import { Button, ButtonLink } from "@/components/ui/button";
import { TextField, Toggle } from "@/components/ui/field";
import { FormFeedback } from "@/components/ui/form-feedback";
import { Section } from "@/components/ui/section";
import { SelectField } from "@/components/ui/select";
import { Alert, EmptyState, Spinner } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { adminMessage } from "@/lib/abs/administration-messages";
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
  const { t } = useI18n();
  const { connection, client } = useAbs();
  const libraries = useQuery({
    queryKey: [connection.id, "managed-libraries"],
    queryFn: ({ signal }) => client.get("/api/admin/libraries", librariesResponseSchema, signal),
  });
  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-6">
      <h1 className="text-2xl font-bold">{t("HeaderLibraries")}</h1>
      <p className="text-muted">{t("WebAdminAddFoldersMountedInsideTheConfiguredMedia")}</p>
      <Section title={t("WebAdminCreateLibrary")}>
        <CreateLibrary />
      </Section>
      {libraries.isPending ? (
        <Spinner label={t("WebAdminLoadingLibraries")} />
      ) : libraries.isError ? (
        <Alert>{adminMessage(libraries.error.message, t)}</Alert>
      ) : libraries.data.libraries.length ? (
        libraries.data.libraries.map((library) => <LibraryScan key={library.id} library={library} />)
      ) : (
        <EmptyState title={t("WebAdminNoLibrariesYet")} />
      )}
    </div>
  );
}
function CreateLibrary() {
  const feedbackId = useId();
  const { t } = useI18n();
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
        await queries.invalidateQueries({ queryKey: [connection.id] });
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
    <form
      aria-describedby={result.kind === "error" ? feedbackId : undefined}
      action={submit}
      className="flex flex-col gap-4"
    >
      <fieldset disabled={pending} className="grid gap-4 sm:grid-cols-2">
        <TextField name="name" label={t("WebAdminLibraryName")} required />
        <SelectField
          name="mediaType"
          label={t("WebAdminMediaType")}
          defaultValue="book"
          options={[
            { value: "book", label: t("LabelBooks") },
            { value: "podcast", label: t("LabelPodcasts") },
          ]}
        />
        <TextField
          name="folder"
          label={t("WebAdminMountedFolder")}
          required
          help={t("WebAdminAbsolutePathInsideTheContainerForExample")}
          className="sm:col-span-2"
        />
        <Button type="submit" variant="primary">
          {pending ? t("WebAdminCreating") : t("WebAdminCreateLibrary")}
        </Button>
      </fieldset>
      {result.kind !== "idle" ? (
        <FormFeedback submission={result} id={feedbackId} tone={result.kind === "saved" ? "info" : "danger"}>
          {adminMessage(result.message, t)}
        </FormFeedback>
      ) : null}
    </form>
  );
}
function LibraryScan({ library }: { library: Library }) {
  const feedbackId = useId();
  const { t } = useI18n();
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
    <Section title={library.isArchived ? t("WebArchivedLibrary", library.name) : library.name}>
      <LibraryEditor library={library} />
      <p className="text-sm text-muted break-all">
        {library.folders.map((folder) => folder.fullPath).join(", ")}
      </p>
      <div className="flex flex-wrap gap-3">
        <form aria-describedby={result.kind === "error" ? feedbackId : undefined} action={submit}>
          <Button type="submit" disabled={pending || library.isArchived} variant="primary">
            {pending ? t("WebAdminScanning") : t("WebAdminScanMountedFolders")}
          </Button>
        </form>
        <ButtonLink href={`/library/${library.id}/items`}>{t("WebAdminBrowseLibrary")}</ButtonLink>
      </div>
      {result.kind !== "idle" ? (
        <FormFeedback submission={result} id={feedbackId} tone={result.kind === "saved" ? "info" : "danger"}>
          {adminMessage(result.message, t)}
        </FormFeedback>
      ) : null}
      {history.isPending ? (
        <Spinner label={t("WebAdminLoadingScanHistory")} />
      ) : history.isError ? (
        <Alert>{adminMessage(history.error.message, t)}</Alert>
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
                      {error.path}: {adminMessage(error.message, t)}
                    </li>
                  ))}
                </ul>
              ) : null}
            </li>
          ))}
        </ul>
      ) : (
        <p className="text-sm text-muted">{t("WebAdminNoScansYet")}</p>
      )}
    </Section>
  );
}

function LibraryEditor({ library }: { library: Library }) {
  const feedbackId = useId();
  const { t } = useI18n();
  const { client, connection } = useAbs();
  const queries = useQueryClient();
  const [result, action, pending] = useActionState<Result, FormData>(
    async (_old, form) => {
      try {
        if (form.get("mode") === "delete") {
          if (form.get("confirmation") !== library.name)
            return {
              kind: "error",
              message: "Type the library name to confirm deletion. Populated libraries can be archived.",
            };
          await client.command("DELETE", `/api/libraries/${encodeURIComponent(library.id)}`);
        } else {
          const fields = z
            .object({
              name: z.string().trim().min(1).max(256),
              displayOrder: z.coerce.number().int().min(0).max(10000),
              coverAspectRatio: z.coerce.number().min(0.3).max(3),
              folders: z.string().min(1),
            })
            .parse(Object.fromEntries(form));
          const folders = fields.folders
            .split(/\r?\n/)
            .map((fullPath) => fullPath.trim())
            .filter(Boolean)
            .map((fullPath) => ({
              id: library.folders.find((folder) => folder.fullPath === fullPath)?.id,
              fullPath,
            }));
          await client.send(
            "PATCH",
            `/api/libraries/${encodeURIComponent(library.id)}`,
            {
              name: fields.name,
              displayOrder: fields.displayOrder,
              settings: { coverAspectRatio: fields.coverAspectRatio },
              folders,
              isArchived: form.get("isArchived") === "on",
            },
            librarySchema,
          );
        }
        await queries.invalidateQueries({ queryKey: [connection.id] });
        return { kind: "saved", message: "Library updated. Media files and history are retained." };
      } catch (error) {
        return {
          kind: "error",
          message:
            error instanceof z.ZodError
              ? "Check the library fields"
              : error instanceof Error
                ? error.message
                : "Library update failed",
        };
      }
    },
    { kind: "idle" },
  );
  return (
    <details className="rounded-xl border border-line p-4">
      <summary className="cursor-pointer font-medium">{t("WebAdminEditLibrary")}</summary>
      <form
        aria-describedby={result.kind === "error" ? feedbackId : undefined}
        action={action}
        className="mt-4 flex flex-col gap-3"
      >
        <TextField name="name" label={t("WebAdminLibraryName")} defaultValue={library.name} required />
        <TextField
          name="displayOrder"
          label={t("WebAdminDisplayOrder")}
          type="number"
          min={0}
          max={10000}
          defaultValue={library.displayOrder}
        />
        <TextField
          name="coverAspectRatio"
          label={t("WebAdminCoverAspectRatio")}
          type="number"
          min={0.3}
          max={3}
          step="0.1"
          defaultValue={library.settings?.coverAspectRatio ?? 1}
        />
        <label className="flex flex-col gap-2 text-sm font-medium">
          {t("WebAdminMountedFoldersOnePerLine")}
          <textarea
            name="folders"
            className="min-h-24 rounded-xl border border-line bg-surface p-3 font-normal"
            defaultValue={library.folders.map((folder) => folder.fullPath).join("\n")}
            required
          />
        </label>
        <Toggle
          name="isArchived"
          label={t("WebAdminArchiveThisLibrary")}
          defaultChecked={library.isArchived}
        />
        <p className="text-sm text-muted">{t("WebAdminArchivedLibrariesAreHiddenAndTheirMedia")}</p>
        <Button type="submit" name="mode" value="save" disabled={pending}>
          {t("WebAdminSaveLibrary")}
        </Button>
        <TextField name="confirmation" label={t("WebAdminLibraryNameToConfirmEmptyLibraryDeletion")} />
        <Button type="submit" name="mode" value="delete" disabled={pending}>
          {t("WebAdminDeleteEmptyLibrary")}
        </Button>
        {result.kind !== "idle" ? (
          <FormFeedback
            submission={result}
            id={feedbackId}
            tone={result.kind === "saved" ? "info" : "danger"}
          >
            {adminMessage(result.message, t)}
          </FormFeedback>
        ) : null}
      </form>
    </details>
  );
}
