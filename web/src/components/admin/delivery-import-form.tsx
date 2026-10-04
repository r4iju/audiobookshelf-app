"use client";
import { useQueryClient } from "@tanstack/react-query";
import { useActionState } from "react";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { TextField } from "@/components/ui/field";
import { Alert } from "@/components/ui/status";
import {
  type DeliveryImportReport,
  deliveryImportInput,
  deliveryImportReportSchema,
} from "@/lib/abs/imports";
import { useAbs } from "@/lib/session/store";

type Result =
  | { kind: "idle" }
  | { kind: "error"; message: string }
  | { kind: "inspected"; report: DeliveryImportReport; serverAddress: string }
  | { kind: "completed"; report: DeliveryImportReport };
export function DeliveryImportForm() {
  const { client, connection } = useAbs();
  const queries = useQueryClient();
  const [result, submit, pending] = useActionState<Result, FormData>(
    async (previous, form) => {
      try {
        const input = deliveryImportInput.parse({
          digest: form.get("digest"),
          serverAddress: form.get("serverAddress"),
        });
        if (form.get("intent") === "commit") {
          if (
            previous.kind !== "inspected" ||
            previous.report.digest !== input.digest ||
            previous.serverAddress !== input.serverAddress ||
            !previous.report.canImport
          )
            return {
              kind: "error",
              message: "Inspect this source before importing feeds and delivery settings.",
            };
          const completed = await client.send(
            "POST",
            "/api/admin/migrations/delivery",
            input,
            z.object({ report: deliveryImportReportSchema }),
          );
          await queries.invalidateQueries({ queryKey: [connection.id] });
          return { kind: "completed", report: completed.report };
        }
        return {
          kind: "inspected",
          serverAddress: input.serverAddress,
          report: await client.send(
            "POST",
            "/api/admin/migrations/delivery/inspect",
            input,
            deliveryImportReportSchema,
          ),
        };
      } catch (error) {
        return { kind: "error", message: error instanceof Error ? error.message : "Delivery import failed." };
      }
    },
    { kind: "idle" },
  );
  const report = result.kind === "inspected" || result.kind === "completed" ? result.report : null;
  return (
    <form action={submit} className="space-y-4">
      <p>
        Use the source digest from a completed media import. Original feeds, SMTP settings and e-reader access
        rules are restored from that archived snapshot. Choose the replacement public server URL explicitly.
      </p>
      <TextField
        name="serverAddress"
        label="Replacement public server URL"
        required
        defaultValue={result.kind === "inspected" ? result.serverAddress : ""}
      />
      <TextField name="digest" label="Source digest" required defaultValue={report?.digest ?? ""} />
      {result.kind === "error" ? <Alert>{result.message}</Alert> : null}
      {report ? (
        <div className="space-y-2">
          <p role="status">
            {result.kind === "completed" ? "Imported" : "Found"} {report.counts.feeds} feeds,{" "}
            {report.counts.episodes} episodes and {report.counts.devices} e-reader devices.
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
            <ul aria-label="Archived delivery fields">
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
            Inspect feeds and delivery
          </Button>
          {result.kind === "inspected" && result.report.canImport ? (
            <Button type="submit" name="intent" value="commit" disabled={pending} variant="primary">
              Import feeds and delivery
            </Button>
          ) : null}
        </div>
      )}
    </form>
  );
}
