"use client";
import { useQueryClient } from "@tanstack/react-query";
import { useActionState } from "react";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { TextField } from "@/components/ui/field";
import { Alert } from "@/components/ui/status";
import { type ListImportReport, listImportReportSchema, listImportSchema } from "@/lib/abs/imports";
import { useAbs } from "@/lib/session/store";

type Result =
  | { kind: "idle" }
  | { kind: "error"; message: string }
  | { kind: "inspected"; report: ListImportReport }
  | { kind: "completed"; report: ListImportReport };
export function ListImportForm() {
  const { client, connection } = useAbs();
  const queries = useQueryClient();
  const [result, submit, pending] = useActionState<Result, FormData>(
    async (previous, form) => {
      try {
        const input = listImportSchema.parse({ digest: form.get("digest") });
        if (form.get("intent") === "commit") {
          if (
            previous.kind !== "inspected" ||
            previous.report.digest !== input.digest ||
            !previous.report.canImport
          )
            return { kind: "error", message: "Inspect this source before importing lists." };
          const completed = await client.send(
            "POST",
            "/api/admin/migrations/lists",
            input,
            z.object({ report: listImportReportSchema }),
          );
          await queries.invalidateQueries({ queryKey: [connection.id] });
          return { kind: "completed", report: completed.report };
        }
        return {
          kind: "inspected",
          report: await client.send(
            "POST",
            "/api/admin/migrations/lists/inspect",
            input,
            listImportReportSchema,
          ),
        };
      } catch (error) {
        return { kind: "error", message: error instanceof Error ? error.message : "List import failed." };
      }
    },
    { kind: "idle" },
  );
  const report = result.kind === "inspected" || result.kind === "completed" ? result.report : null;
  return (
    <form action={submit} className="space-y-4">
      <p>
        Use the source digest from a completed media import. Original collections and private playlists are
        restored from that archived snapshot.
      </p>
      <TextField name="digest" label="Source digest" required defaultValue={report?.digest ?? ""} />
      {result.kind === "error" ? <Alert>{result.message}</Alert> : null}
      {report ? (
        <div className="space-y-2">
          <p role="status">
            {result.kind === "completed" ? "Imported" : "Found"} {report.counts.collections} collections,{" "}
            {report.counts.playlists} playlists and {report.counts.members} members.
          </p>
          {report.notices.map((notice) => (
            <p key={notice} className="text-sm text-muted">
              {notice}
            </p>
          ))}
          {report.errors.map((error) => (
            <Alert key={`${error.table}:${error.id}:${error.message}`}>
              {error.table} {error.id}: {error.message}
            </Alert>
          ))}
          {report.unsupported.length ? (
            <ul aria-label="Archived list fields">
              {report.unsupported.map((entry) => (
                <li key={`${entry.table}:${entry.id}`}>
                  {entry.table} {entry.id}: {entry.fields.join(", ")}
                </li>
              ))}
            </ul>
          ) : null}
        </div>
      ) : null}
      {result.kind === "completed" ? null : (
        <div className="flex gap-2">
          <Button type="submit" name="intent" value="inspect" disabled={pending}>
            Inspect lists
          </Button>
          {result.kind === "inspected" && result.report.canImport ? (
            <Button type="submit" name="intent" value="commit" disabled={pending} variant="primary">
              Import lists
            </Button>
          ) : null}
        </div>
      )}
    </form>
  );
}
