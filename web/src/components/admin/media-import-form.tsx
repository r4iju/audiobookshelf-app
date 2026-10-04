"use client";
import { useQueryClient } from "@tanstack/react-query";
import { useActionState } from "react";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { TextField } from "@/components/ui/field";
import { Alert } from "@/components/ui/status";
import { type MediaImportReport, mediaImportReportSchema, mediaInspectSchema } from "@/lib/abs/imports";
import { useAbs } from "@/lib/session/store";

type Input = z.infer<typeof mediaInspectSchema>;
type Result =
  | { kind: "idle" }
  | { kind: "error"; message: string }
  | { kind: "inspected"; input: Input; report: MediaImportReport }
  | { kind: "completed"; items: number };
const completedSchema = z.object({ scope: z.literal("media"), report: mediaImportReportSchema });
export function MediaImportForm() {
  const { client, connection } = useAbs();
  const queries = useQueryClient();
  const [result, submit, pending] = useActionState<Result, FormData>(
    async (previous, form) => {
      try {
        const input = mediaInspectSchema.parse({
          sourcePath: form.get("sourcePath"),
          mappings: [{ from: form.get("originalPrefix"), to: form.get("mountedPrefix") }],
        });
        if (form.get("intent") === "commit") {
          if (
            previous.kind !== "inspected" ||
            !previous.report.canImport ||
            JSON.stringify(input) !== JSON.stringify(previous.input)
          )
            return {
              kind: "error",
              message: "Inspect the exact source and folder mapping before importing.",
            };
          const completed = await client.send(
            "POST",
            "/api/admin/migrations/media",
            { ...input, expectedDigest: previous.report.digest },
            completedSchema,
          );
          await queries.invalidateQueries({ queryKey: [connection.id] });
          return { kind: "completed", items: completed.report.counts.items };
        }
        return {
          kind: "inspected",
          input,
          report: await client.send(
            "POST",
            "/api/admin/migrations/media/inspect",
            input,
            mediaImportReportSchema,
          ),
        };
      } catch (error) {
        return {
          kind: "error",
          message: error instanceof Error ? error.message : "The source could not be inspected.",
        };
      }
    },
    { kind: "idle" },
  );
  if (result.kind === "completed")
    return (
      <p role="status">
        Imported {result.items} media items. Validate playback and remaining migration stages before cutover.
      </p>
    );
  const input = result.kind === "inspected" ? result.input : null;
  return (
    <form action={submit} className="space-y-4">
      <p>
        Use the same closed SQLite copy as your account import. Map an original media folder onto an existing
        mounted folder. The destination catalog must be empty.
      </p>
      <TextField
        name="sourcePath"
        label="Source database copy"
        required
        defaultValue={input?.sourcePath}
        placeholder="/imports/absdatabase.sqlite"
      />
      <TextField
        name="originalPrefix"
        label="Original media folder"
        required
        defaultValue={input?.mappings[0]?.from}
        placeholder="/original/audiobooks"
      />
      <TextField
        name="mountedPrefix"
        label="Mounted media folder"
        required
        defaultValue={input?.mappings[0]?.to}
        placeholder="/media/audiobooks"
      />
      {result.kind === "error" ? <Alert>{result.message}</Alert> : null}
      {result.kind === "inspected" ? (
        <div className="space-y-3" role="status">
          <p>
            {result.report.counts.libraries} libraries · {result.report.counts.items} items ·{" "}
            {result.report.counts.files} files · {result.report.counts.progress} progress records ·{" "}
            {result.report.counts.bookmarks} bookmarks · {result.report.counts.listeningSeconds} seconds
            listened
          </p>
          {result.report.errors.length ? (
            <Alert>
              <ul>
                {result.report.errors.map((error) => (
                  <li key={JSON.stringify(error)}>
                    {error.table}: {error.message}
                  </li>
                ))}
              </ul>
            </Alert>
          ) : null}
          {result.report.remainingData.length ? (
            <div>
              <h3 className="font-semibold">Data requiring remaining migration stages</h3>
              <ul>
                {result.report.remainingData.map((row) => (
                  <li key={row.table}>
                    {row.table}: {row.rows} records
                    {row.recordIds?.length ? (
                      <span className="block break-all text-xs">{row.recordIds.join(", ")}</span>
                    ) : null}
                  </li>
                ))}
              </ul>
            </div>
          ) : (
            <p>No unmapped records were found in this stage.</p>
          )}
          {result.report.notices.map((notice) => (
            <p key={notice} className="text-sm text-muted">
              {notice}
            </p>
          ))}
          <p>Full cutover is not yet approved by this inventory.</p>
        </div>
      ) : null}
      <div className="flex flex-wrap gap-3">
        <Button type="submit" name="intent" value="inspect" disabled={pending}>
          Inspect source copy
        </Button>
        {result.kind === "inspected" && result.report.canImport ? (
          <Button type="submit" name="intent" value="commit" disabled={pending} variant="secondary">
            Import media and history
          </Button>
        ) : null}
      </div>
    </form>
  );
}
